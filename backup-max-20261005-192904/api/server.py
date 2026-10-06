import hashlib
import json
import secrets
import urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

BASE = Path(__file__).resolve().parent.parent
USERS = BASE / "data" / "users"
USERS.mkdir(parents=True, exist_ok=True)

HOST = "127.0.0.1"
PORT = 8090
OLLAMA_URL = "http://127.0.0.1:11434/api/chat"
MODEL = "qwen2.5:0.5b"

sessions = {}


def hash_password(password):
    return hashlib.sha256(password.encode()).hexdigest()


def user_file(username):
    safe = "".join(c for c in username if c.isalnum() or c in "_-")
    return USERS / f"{safe}.json"


def load_user(username):
    path = user_file(username)
    if not path.exists():
        return None
    return json.loads(path.read_text())


def save_user(user):
    user_file(user["username"]).write_text(
        json.dumps(user, indent=2)
    )


def ask_ollama(user, message):
    history = user.get("memory", [])[-10:]

    messages = [
        {
            "role": "system",
            "content": (
                "You are AURA AI, an AI assistant created by RAKIB. "
                "Be helpful, natural, concise and respectful. "
                "Do not invent your creator or identity."
            )
        }
    ]

    messages.extend(history)
    messages.append({
        "role": "user",
        "content": message
    })

    payload = json.dumps({
        "model": MODEL,
        "messages": messages,
        "stream": False
    }).encode()

    request = urllib.request.Request(
        OLLAMA_URL,
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST"
    )

    with urllib.request.urlopen(request, timeout=120) as response:
        result = json.loads(response.read().decode())

    return result["message"]["content"]


class AURAHandler(BaseHTTPRequestHandler):

    def send_json(self, status, data):
        body = json.dumps(data).encode()

        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def read_json(self):
        length = int(self.headers.get("Content-Length", 0))

        if not length:
            return {}

        return json.loads(
            self.rfile.read(length).decode()
        )

    def do_GET(self):

        if self.path in ("/", "/index.html"):
            page = (BASE / "web" / "index.html").read_bytes()

            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(page)))
            self.end_headers()
            self.wfile.write(page)
            return


        if self.path == "/":
            self.send_json(200, {
                "name": "AURA AI",
                "status": "online",
                "version": "0.2.0",
                "creator": "RAKIB"
            })
            return

        if self.path == "/health":
            self.send_json(200, {
                "status": "ok",
                "service": "AURA AI",
                "brain": MODEL,
                "multi_user": True
            })
            return

        self.send_json(404, {
            "error": "Route not found"
        })

    def do_POST(self):

        data = self.read_json()

        if self.path == "/register":

            username = data.get("username", "").strip()
            password = data.get("password", "")

            if len(username) < 3:
                self.send_json(400, {
                    "error": "Username must be at least 3 characters"
                })
                return

            if len(password) < 6:
                self.send_json(400, {
                    "error": "Password must be at least 6 characters"
                })
                return

            if load_user(username):
                self.send_json(409, {
                    "error": "User already exists"
                })
                return

            user = {
                "username": username,
                "password_hash": hash_password(password),
                "user_id": secrets.token_hex(16),
                "memory": [],
                "connections": {},
                "settings": {
                    "ai_model": MODEL
                }
            }

            save_user(user)

            self.send_json(201, {
                "success": True,
                "message": "AURA account created",
                "user_id": user["user_id"]
            })
            return

        if self.path == "/login":

            username = data.get("username", "").strip()
            password = data.get("password", "")

            user = load_user(username)

            if not user:
                self.send_json(401, {
                    "error": "Invalid username or password"
                })
                return

            if user["password_hash"] != hash_password(password):
                self.send_json(401, {
                    "error": "Invalid username or password"
                })
                return

            token = secrets.token_hex(32)
            sessions[token] = username

            self.send_json(200, {
                "success": True,
                "message": "Login successful",
                "token": token,
                "user_id": user["user_id"]
            })
            return

        if self.path == "/history":

            token = data.get("token", "")
            username = sessions.get(token)

            if not username:
                self.send_json(401, {
                    "error": "Not authenticated"
                })
                return

            user = load_user(username)

            self.send_json(200, {
                "success": True,
                "user": username,
                "messages": user.get("memory", [])
            })
            return

        if self.path == "/logout":

            token = data.get("token", "")

            if token in sessions:
                del sessions[token]

            self.send_json(200, {
                "success": True,
                "message": "Logged out"
            })
            return

        if self.path == "/chat":

            token = data.get("token", "")
            message = data.get("message", "").strip()

            username = sessions.get(token)

            if not username:
                self.send_json(401, {
                    "error": "Not authenticated"
                })
                return

            if not message:
                self.send_json(400, {
                    "error": "Message is required"
                })
                return

            user = load_user(username)

            try:
                reply = ask_ollama(user, message)

                user["memory"].append({
                    "role": "user",
                    "content": message
                })

                user["memory"].append({
                    "role": "assistant",
                    "content": reply
                })

                user["memory"] = user["memory"][-20:]

                save_user(user)

                self.send_json(200, {
                    "success": True,
                    "reply": reply,
                    "user": username
                })

            except Exception as error:
                self.send_json(500, {
                    "error": str(error)
                })

            return

        self.send_json(404, {
            "error": "Route not found"
        })

    def log_message(self, format, *args):
        print("[AURA]", format % args)


print("================================")
print("       AURA AI BACKEND")
print("================================")
print(f"Server: http://{HOST}:{PORT}")
print(f"Brain: Ollama / {MODEL}")
print("Multi-user: ENABLED")
print("Memory: ENABLED")
print("")

server = HTTPServer((HOST, PORT), AURAHandler)

try:
    server.serve_forever()
except KeyboardInterrupt:
    print("\nAURA backend stopped.")
    server.server_close()
