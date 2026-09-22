#!/usr/bin/env bash

set -Eeuo pipefail

readonly EXIT_HEALTHY=0
readonly EXIT_UNHEALTHY=1
readonly EXIT_CONFIGURATION=2
readonly DEFAULT_CONFIG_FILE="${HEALTHCHECK_CONFIG_FILE:-endpoints.json}"
readonly DEFAULT_MAX_ATTEMPTS="${HEALTHCHECK_MAX_ATTEMPTS:-3}"
readonly DEFAULT_BACKOFF_SECONDS="${HEALTHCHECK_BACKOFF_SECONDS:-1}"
readonly DEFAULT_TIMEOUT_SECONDS="${HEALTHCHECK_TIMEOUT_SECONDS:-10}"

TEMP_DIR=""

log() { printf '%s\n' "$*" >&2; }
die() { log "error: $*"; exit "$EXIT_CONFIGURATION"; }

# Invoked indirectly by the EXIT, INT, and TERM traps installed in main.
# shellcheck disable=SC2329
cleanup() {
  if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
    rm -rf "$TEMP_DIR"
  fi
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

is_positive_integer() { [[ "$1" =~ ^[1-9][0-9]*$ ]]; }
is_non_negative_number() { [[ "$1" =~ ^([0-9]+([.][0-9]+)?|[.][0-9]+)$ ]]; }

load_config() {
  local config_file="${1:-$DEFAULT_CONFIG_FILE}"

  if [[ -n "${HEALTHCHECK_ENDPOINTS_JSON:-}" ]]; then
    printf '%s' "$HEALTHCHECK_ENDPOINTS_JSON"
    return
  fi

  [[ -r "$config_file" ]] || die "configuration file is not readable: $config_file"
  command cat "$config_file"
}

validate_config() {
  local config="$1"

  jq -e '
    (.endpoints | type == "array") and
    (.endpoints | length > 0) and
    all(.endpoints[];
      (.url | type == "string" and length > 0) and
      (.expected_status | type == "number" and . >= 100 and . <= 599) and
      ((.name // "") | type == "string") and
      ((.max_attempts // 1) | type == "number") and
      ((.backoff_seconds // 0) | type == "number") and
      ((.timeout_seconds // 1) | type == "number")
    )
  ' >/dev/null <<<"$config" || die "configuration must contain a non-empty, valid endpoints array"
}

seconds_to_milliseconds() {
  awk -v seconds="$1" 'BEGIN { printf "%.2f", seconds * 1000 }'
}

check_endpoint() {
  local endpoint="$1"
  local name url expected_status max_attempts backoff_seconds timeout_seconds
  local attempt=1 status_code="000" response_seconds="0" response_time_ms="0.00"
  local curl_output curl_exit error_message="" passed=false

  name=$(jq -r '.name // .url' <<<"$endpoint")
  url=$(jq -r '.url' <<<"$endpoint")
  expected_status=$(jq -r '.expected_status' <<<"$endpoint")
  max_attempts=$(jq -r --arg default "$DEFAULT_MAX_ATTEMPTS" '.max_attempts // ($default | tonumber)' <<<"$endpoint")
  backoff_seconds=$(jq -r --arg default "$DEFAULT_BACKOFF_SECONDS" '.backoff_seconds // ($default | tonumber)' <<<"$endpoint")
  timeout_seconds=$(jq -r --arg default "$DEFAULT_TIMEOUT_SECONDS" '.timeout_seconds // ($default | tonumber)' <<<"$endpoint")

  is_positive_integer "$max_attempts" || die "$name: max_attempts must be a positive integer"
  is_non_negative_number "$backoff_seconds" || die "$name: backoff_seconds must be zero or greater"
  is_non_negative_number "$timeout_seconds" || die "$name: timeout_seconds must be zero or greater"

  while ((attempt <= max_attempts)); do
    log "checking $name (attempt $attempt/$max_attempts)"

    if curl_output=$(curl \
      --silent --show-error --location \
      --max-time "$timeout_seconds" \
      --output /dev/null \
      --write-out $'%{http_code}\t%{time_total}' \
      "$url" 2>"$TEMP_DIR/curl-error"); then
      curl_exit=0
    else
      curl_exit=$?
    fi

    IFS=$'\t' read -r status_code response_seconds <<<"${curl_output:-000\t0}"
    status_code="${status_code:-000}"
    response_seconds="${response_seconds:-0}"
    response_time_ms=$(seconds_to_milliseconds "$response_seconds")

    if ((curl_exit == 0)) && [[ "$status_code" == "$expected_status" ]]; then
      passed=true
      error_message=""
      break
    fi

    if ((curl_exit != 0)); then
      error_message=$(<"$TEMP_DIR/curl-error")
      error_message="${error_message:-curl exited with code $curl_exit}"
    else
      error_message="expected HTTP $expected_status but received HTTP $status_code"
    fi

    if ((attempt < max_attempts)); then
      log "$name failed: $error_message; retrying in ${backoff_seconds}s"
      sleep "$backoff_seconds"
      backoff_seconds=$(awk -v delay="$backoff_seconds" 'BEGIN { printf "%.3f", delay * 2 }')
      ((attempt += 1))
    else
      break
    fi
  done

  jq -n \
    --arg name "$name" \
    --arg url "$url" \
    --argjson expected_status "$expected_status" \
    --arg status_code "$status_code" \
    --argjson response_time_ms "$response_time_ms" \
    --argjson attempts "$attempt" \
    --argjson passed "$passed" \
    --arg error "$error_message" \
    '{name: $name, url: $url, expected_status: $expected_status,
      status_code: (if $status_code == "000" then null else ($status_code | tonumber) end),
      response_time_ms: $response_time_ms, attempts: $attempts, passed: $passed,
      error: (if $error == "" then null else $error end)}'
}

main() {
  local config endpoint result results='[]'
  local total passed failed exit_code="$EXIT_HEALTHY"

  require_command curl
  require_command jq
  require_command awk
  is_positive_integer "$DEFAULT_MAX_ATTEMPTS" || die "HEALTHCHECK_MAX_ATTEMPTS must be a positive integer"
  is_non_negative_number "$DEFAULT_BACKOFF_SECONDS" || die "HEALTHCHECK_BACKOFF_SECONDS must be zero or greater"
  is_non_negative_number "$DEFAULT_TIMEOUT_SECONDS" || die "HEALTHCHECK_TIMEOUT_SECONDS must be zero or greater"

  TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/healthcheck.XXXXXX")
  trap cleanup EXIT INT TERM

  config=$(load_config "${1:-}")
  validate_config "$config"

  while IFS= read -r endpoint; do
    result=$(check_endpoint "$endpoint")
    results=$(jq --argjson result "$result" '. + [$result]' <<<"$results")
  done < <(jq -c '.endpoints[]' <<<"$config")

  total=$(jq 'length' <<<"$results")
  passed=$(jq '[.[] | select(.passed)] | length' <<<"$results")
  failed=$((total - passed))
  ((failed > 0)) && exit_code="$EXIT_UNHEALTHY"

  jq -n \
    --arg checked_at "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
    --argjson total "$total" --argjson passed "$passed" --argjson failed "$failed" \
    --argjson results "$results" \
    '{checked_at: $checked_at, summary: {total: $total, passed: $passed, failed: $failed}, results: $results}'

  exit "$exit_code"
}

main "$@"
