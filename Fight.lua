import os
from http.server import HTTPServer, BaseHTTPRequestHandler
import json

class MockServerHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length)
        print(f"[HTTP] Gelen İstek: {self.path}")

        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()

        response_data = {
            "status": 0, 
            "message": "success", 
            "data": {
                "LoginIP": "192.168.0.198",
                "LoginPort": 9000,
                "serverIp": "192.168.0.198",
                "port": 9000
            }
        }
        self.wfile.write(json.dumps(response_data).encode("utf-8"))

    def do_GET(self):
        self.do_POST()

if __name__ == '__main__':
    port = int(os.environ.get("PORT", 8080))
    server_address = ('0.0.0.0', port)
    httpd = HTTPServer(server_address, MockServerHandler)
    print(f"Sunucu {port} portunda aktif...")
    httpd.serve_forever()

