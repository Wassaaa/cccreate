from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from datetime import datetime
import json
import os


HOST = os.environ.get("CC_WEBHOOK_HOST", "0.0.0.0")
PORT = int(os.environ.get("CC_WEBHOOK_PORT", "8765"))
TOKEN = os.environ.get("CC_WEBHOOK_TOKEN", "")
ROOT = Path(__file__).resolve().parents[1]
INBOX = ROOT / "inbox"


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/health":
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"ok")
            return

        self.send_response(404)
        self.end_headers()
        self.wfile.write(b"not found")

    def do_POST(self):
        if self.path != "/report":
            self.send_response(404)
            self.end_headers()
            self.wfile.write(b"not found")
            return

        if TOKEN and self.headers.get("X-CC-Token") != TOKEN:
            self.send_response(401)
            self.end_headers()
            self.wfile.write(b"unauthorized")
            return

        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length)

        INBOX.mkdir(exist_ok=True)
        timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")

        try:
            parsed = json.loads(body.decode("utf-8"))
            formatted = json.dumps(parsed, indent=2, sort_keys=True)
        except Exception:
            formatted = body.decode("utf-8", errors="replace")

        latest = INBOX / "latest-report.json"
        archive = INBOX / f"report-{timestamp}.json"
        suffix = 1
        while archive.exists():
            archive = INBOX / f"report-{timestamp}-{suffix:02d}.json"
            suffix += 1

        latest.write_text(formatted + "\n", encoding="utf-8")
        archive.write_text(formatted + "\n", encoding="utf-8")

        print(f"Saved report to {latest} and {archive}")

        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"ok")

    def log_message(self, format, *args):
        print("%s - %s" % (self.address_string(), format % args))


if __name__ == "__main__":
    server = HTTPServer((HOST, PORT), Handler)
    print(f"Listening on http://{HOST}:{PORT}/report")
    print(f"Saving reports to {INBOX}")
    server.serve_forever()
