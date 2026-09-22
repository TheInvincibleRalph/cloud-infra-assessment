# syntax=docker/dockerfile:1

FROM golang:1.25-alpine AS test
WORKDIR /src
RUN apk add --no-cache gcc musl-dev
COPY go.mod ./
COPY cmd ./cmd
COPY internal ./internal
RUN go test -race ./...

FROM test AS build
ARG VERSION=dev
RUN CGO_ENABLED=0 GOOS=linux go build \
    -trimpath \
    -ldflags="-s -w -X main.version=${VERSION}" \
    -o /out/assessment-api \
    ./cmd/api

FROM gcr.io/distroless/static-debian12:nonroot AS runtime
WORKDIR /
COPY --from=build --chown=nonroot:nonroot /out/assessment-api /assessment-api
EXPOSE 8080
USER nonroot:nonroot
ENTRYPOINT ["/assessment-api"]
