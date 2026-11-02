import json, os, socket
from http.server import BaseHTTPRequestHandler, HTTPServer

MESSAGE = os.getenv("APP_MESSAGE", "Ola")
PORT = int(os.getenv("PORT", "8000"))

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        body = json.dumps({
            "message": MESSAGE,
            "container": socket.gethostname(),
            "path": self.path,
        }).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(body)

HTTPServer(("0.0.0.0", PORT), Handler).serve_forever()