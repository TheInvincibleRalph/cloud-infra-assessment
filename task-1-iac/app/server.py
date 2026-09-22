"""Dependency-free demonstration web application for Task 1."""

import json
import os
import socket
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class ApplicationHandler(BaseHTTPRequestHandler):
    """Serve the application page and the load balancer health endpoint."""

    def do_GET(self):
        if self.path == "/health":
            self._send_response(
                json.dumps({"status": "healthy"}).encode(),
                "application/json",
            )
            return

        project = os.environ.get("PROJECT", "cloud-engineer-assessment")
        environment = os.environ.get("ENVIRONMENT", "local")
        body = (
            "<!doctype html><html><head><title>Cloud Engineer Assessment</title>"
            "<meta name='viewport' content='width=device-width,initial-scale=1'>"
            "<style>body{font-family:system-ui;max-width:720px;margin:12vh auto;"
            "padding:2rem;background:#f6f8fa;color:#17202a}main{background:white;"
            "padding:2rem;border-left:5px solid #1677ff}code{background:#eef2f6;"
            "padding:.2rem .4rem}</style></head><body><main>"
            "<h1>Highly available web application</h1>"
            "<p>Served from a private EC2 instance behind an AWS Application Load Balancer.</p>"
            f"<p>Project: <code>{project}</code></p>"
            f"<p>Environment: <code>{environment}</code></p>"
            f"<p>Host: <code>{socket.gethostname()}</code></p>"
            "</main></body></html>"
        ).encode()
        self._send_response(body, "text/html; charset=utf-8")

    def _send_response(self, body, content_type):
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, message_format, *args):
        print(f"{self.client_address[0]} - {message_format % args}")


def main():
    port = int(os.environ.get("PORT", "8080"))
    server = ThreadingHTTPServer(("0.0.0.0", port), ApplicationHandler)
    print(f"Listening on port {port}")
    server.serve_forever()


if __name__ == "__main__":
    main()

