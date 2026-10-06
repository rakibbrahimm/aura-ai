import os
import sys
import json
import time

# AURA project root so core/ is importable.
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)
import uuid
import hashlib
import secrets
import logging
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from core.memory import load_user, save_user, add_message, add_memory
from core.local_tools import calculator, system_info, current_time

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
DATA = os.path.join(ROOT, "data")
WEB = os.path.join(ROOT, "web")
LOGS = os.path.join(ROOT, "logs")
CONFIG = os.path.join(ROOT, "config", "product.json")

HOST = "127.0.0.1"
PORT = 8090

os.makedirs(DATA, exist_ok=True)
os.makedirs(os.path.join(DATA, "users"), exist_ok=True)
os.makedirs(LOGS, exist_ok=True)

logging.basicConfig(
    filename=os.path.join(LOGS, "aura.log"),
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s"
)

SESSIONS = {}
SESSION_TTL = 60 * 60 * 24 * 7

def load_config():
    try:
        with open(CONFIG, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {
            "name": "AURA AI",
            "version": "2.0.0-local-max",
            "brain": {
                "provider": "ollama",
                "model": "qwen2.5:0.5b",
                "url": "http://127.0.0.1:11434/api/chat"
            }
        }

CFG = load_config()
BRAIN = CFG["brain"]

def hash_password(password, salt=None):
    if salt is None:
        salt = secrets.token_hex(16)

    digest = hashlib.pbkdf2_hmac(
        "sha256",
        password.encode(),
        salt.encode(),
        150000
    ).hex()

    return "pbkdf2$150000$" + salt + "$" + digest

def verify_password(password, stored):
    if stored.startswith("pbkdf2$"):
        try:
            _, rounds, salt, expected = stored.split("$", 3)
            actual = hashlib.pbkdf2_hmac(
                "sha256",
                password.encode(),
                salt.encode(),
                int(rounds)
            ).hex()
            return secrets.compare_digest(actual, expected)
        except Exception:
            return False

    # Compatibility with older AURA accounts.
    return secrets.compare_digest(
        hashlib.sha256(password.encode()).hexdigest(),
        stored
    )

def user_path(username):
    safe = "".join(c for c in username if c.isalnum() or c in "-_.")
    return os.path.join(DATA, "users", safe[:80] + ".json")

def account_exists(username):
    return os.path.exists(user_path(username))

def save_account(username, data):
    path = user_path(username)
    tmp = path + ".tmp"

    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

    os.replace(tmp, path)

def create_account(username, password):
    if account_exists(username):
        return False, "Account already exists."

    if len(username) < 3 or len(username) > 40:
        return False, "Username must be 3-40 characters."

    if len(password) < 6 or len(password) > 200:
        return False, "Password must be 6-200 characters."

    data = {
        "username": username,
        "password": hash_password(password),
        "created_at": time.time(),
        "profile": {
            "name": username,
            "personality": "helpful",
            "language": "auto"
        },
        "memory": [],
        "history": []
    }

    save_account(username, data)
    return True, "Account created."

def login(username, password):
    if not account_exists(username):
        return None

    path = user_path(username)

    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception:
        return None

    stored = data.get("password", "")

    if not verify_password(password, stored):
        return None

    # Upgrade legacy SHA256 account after successful login.
    if not stored.startswith("pbkdf2$"):
        data["password"] = hash_password(password)
        save_account(username, data)

    token = secrets.token_urlsafe(32)

    SESSIONS[token] = {
        "username": username,
        "expires": time.time() + SESSION_TTL
    }

    return token

def auth(handler):
    token = handler.headers.get("Authorization", "")

    if token.startswith("Bearer "):
        token = token[7:]

    item = SESSIONS.get(token)

    if not item:
        return None

    if item["expires"] < time.time():
        SESSIONS.pop(token, None)
        return None

    item["expires"] = time.time() + SESSION_TTL
    return item["username"]

def ollama_chat(messages, username):
    memory_data = load_user(DATA, username)

    profile = memory_data.get("profile", {})
    memories = memory_data.get("memory", [])[-10:]

    system = f"""
You are AURA AI.

You are a personal AI assistant operating locally for user {username}.

Product:
AURA AI

Creator:
RAKIB

Tagline:
Your AI presence, when you're away.

Rules:
- Never invent that you are another product.
- Never claim to be ChatGPT, Claude, Gemini, or another company's assistant.
- Be honest that your current local brain is {BRAIN.get("model", "unknown")}.
- Be concise but useful.
- Respect the user's profile and conversation context.
- Do not pretend that external communication APIs are connected when they are not.

User personality:
{profile.get("personality", "helpful")}

User language:
{profile.get("language", "auto")}

Relevant saved memories:
{json.dumps(memories, ensure_ascii=False)}
""".strip()

    payload = {
        "model": BRAIN.get("model", "qwen2.5:0.5b"),
        "messages": [
            {"role": "system", "content": system}
        ] + messages[-20:],
        "stream": False
    }

    req = urllib.request.Request(
        BRAIN.get("url", "http://127.0.0.1:11434/api/chat"),
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
        method="POST"
    )

    with urllib.request.urlopen(req, timeout=90) as response:
        result = json.loads(response.read().decode())

    return result.get("message", {}).get(
        "content",
        "I couldn't generate a response."
    )

def json_response(handler, data, status=200):
    raw = json.dumps(data, ensure_ascii=False).encode()

    handler.send_response(status)
    handler.send_header("Content-Type", "application/json; charset=utf-8")
    handler.send_header("Content-Length", str(len(raw)))
    handler.send_header("Access-Control-Allow-Origin", "*")
    handler.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization")
    handler.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
    handler.end_headers()
    handler.wfile.write(raw)

def read_json(handler):
    length = int(handler.headers.get("Content-Length", "0"))

    if length > 1024 * 1024:
        raise ValueError("request too large")

    raw = handler.rfile.read(length)
    if not raw:
        return {}

    return json.loads(raw.decode())

class Handler(BaseHTTPRequestHandler):

    def log_message(self, fmt, *args):
        logging.info("%s - %s", self.address_string(), fmt % args)

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.end_headers()

    def do_GET(self):
        try:
            path = self.path.split("?", 1)[0]

            if path == "/health":
                return json_response(self, {
                    "status": "ok",
                    "service": "AURA AI",
                    "version": CFG.get("version"),
                    "brain": BRAIN.get("model"),
                    "multi_user": True,
                    "memory": True,
                    "local_tools": True
                })

            if path == "/":
                return self.serve_file("index.html", "text/html; charset=utf-8")

            if path == "/manifest.json":
                return self.serve_file("manifest.json", "application/manifest+json")

            if path == "/sw.js":
                return self.serve_file("sw.js", "application/javascript")

            if path == "/api/status":
                username = auth(self)

                return json_response(self, {
                    "service": "AURA AI",
                    "version": CFG.get("version"),
                    "authenticated": bool(username),
                    "user": username,
                    "brain": BRAIN.get("model"),
                    "tools": True,
                    "memory": True
                })

            if path == "/history":
                username = auth(self)

                if not username:
                    return json_response(self, {"error": "Unauthorized"}, 401)

                data = load_user(DATA, username)

                return json_response(self, {
                    "history": data.get("history", [])
                })

            if path == "/memory":
                username = auth(self)

                if not username:
                    return json_response(self, {"error": "Unauthorized"}, 401)

                data = load_user(DATA, username)

                return json_response(self, {
                    "memory": data.get("memory", [])
                })

            if path == "/settings":
                username = auth(self)

                if not username:
                    return json_response(self, {"error": "Unauthorized"}, 401)

                data = load_user(DATA, username)

                return json_response(self, {
                    "profile": data.get("profile", {})
                })

            return self.serve_file(path.lstrip("/"))

        except Exception as e:
            logging.exception("GET failure")
            return json_response(self, {"error": str(e)}, 500)

    def do_POST(self):
        try:
            path = self.path.split("?", 1)[0]
            data = read_json(self)

            if path == "/register":
                username = str(data.get("username", "")).strip()
                password = str(data.get("password", ""))

                ok, message = create_account(username, password)

                return json_response(self, {
                    "ok": ok,
                    "message": message
                }, 200 if ok else 400)

            if path == "/login":
                username = str(data.get("username", "")).strip()
                password = str(data.get("password", ""))

                token = login(username, password)

                if not token:
                    return json_response(self, {
                        "ok": False,
                        "error": "Invalid username or password."
                    }, 401)

                return json_response(self, {
                    "ok": True,
                    "token": token,
                    "username": username
                })

            username = auth(self)

            if not username:
                return json_response(self, {
                    "error": "Unauthorized"
                }, 401)

            if path == "/logout":
                token = self.headers.get("Authorization", "")
                if token.startswith("Bearer "):
                    token = token[7:]
                SESSIONS.pop(token, None)

                return json_response(self, {"ok": True})

            if path == "/chat":
                message = str(data.get("message", "")).strip()

                if not message:
                    return json_response(self, {
                        "error": "Message required."
                    }, 400)

                if len(message) > 10000:
                    return json_response(self, {
                        "error": "Message too long."
                    }, 400)

                user_data = load_user(DATA, username)

                previous = [
                    {
                        "role": x.get("role"),
                        "content": x.get("content")
                    }
                    for x in user_data.get("history", [])[-20:]
                    if x.get("role") in ("user", "assistant")
                ]

                add_message(DATA, username, "user", message)

                try:
                    reply = ollama_chat(
                        previous + [
                            {"role": "user", "content": message}
                        ],
                        username
                    )
                except Exception as e:
                    logging.exception("Ollama failure")
                    return json_response(self, {
                        "error": "Local AI unavailable.",
                        "detail": str(e)
                    }, 503)

                add_message(DATA, username, "assistant", reply)

                return json_response(self, {
                    "ok": True,
                    "reply": reply,
                    "brain": BRAIN.get("model"),
                    "user": username
                })

            if path == "/memory":
                text_value = str(data.get("text", "")).strip()

                if not text_value:
                    return json_response(self, {
                        "error": "Memory text required."
                    }, 400)

                if len(text_value) > 2000:
                    return json_response(self, {
                        "error": "Memory too long."
                    }, 400)

                add_memory(DATA, username, text_value)

                return json_response(self, {"ok": True})

            if path == "/settings":
                profile = data.get("profile", {})

                user_data = load_user(DATA, username)
                current = user_data.setdefault("profile", {})

                if isinstance(profile, dict):
                    for key in ("name", "personality", "language"):
                        if key in profile:
                            value = str(profile[key])[:500]
                            current[key] = value

                save_user(DATA, username, user_data)

                return json_response(self, {
                    "ok": True,
                    "profile": current
                })

            if path == "/tool":
                tool = str(data.get("tool", "")).strip()

                if tool == "calculator":
                    expression = str(data.get("expression", ""))

                    try:
                        result = calculator(expression)
                    except Exception as e:
                        return json_response(self, {
                            "ok": False,
                            "error": str(e)
                        }, 400)

                    return json_response(self, {
                        "ok": True,
                        "tool": tool,
                        "result": result
                    })

                if tool == "time":
                    return json_response(self, {
                        "ok": True,
                        "tool": tool,
                        "result": current_time()
                    })

                if tool == "system":
                    return json_response(self, {
                        "ok": True,
                        "tool": tool,
                        "result": system_info()
                    })

                return json_response(self, {
                    "error": "Unknown tool."
                }, 400)

            return json_response(self, {
                "error": "Not found"
            }, 404)

        except Exception as e:
            logging.exception("POST failure")
            return json_response(self, {
                "error": str(e)
            }, 500)

    def serve_file(self, filename, content_type=None):
        if ".." in filename:
            return json_response(self, {"error": "Invalid path"}, 400)

        if filename.startswith("/"):
            filename = filename[1:]

        path = os.path.join(WEB, filename)

        if not os.path.isfile(path):
            return json_response(self, {"error": "Not found"}, 404)

        if content_type is None:
            if filename.endswith(".js"):
                content_type = "application/javascript"
            elif filename.endswith(".css"):
                content_type = "text/css"
            else:
                content_type = "text/plain"

        with open(path, "rb") as f:
            raw = f.read()

        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(raw)))
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()
        self.wfile.write(raw)

def main():
    print("=" * 40)
    print("          AURA AI MAX LOCAL")
    print("=" * 40)
    print("Server: http://127.0.0.1:8090")
    print("Brain:", BRAIN.get("model"))
    print("Multi-user: ENABLED")
    print("Memory: ENABLED")
    print("Tools: ENABLED")
    print("PWA: ENABLED")
    print("=" * 40)

    server = ThreadingHTTPServer((HOST, PORT), Handler)

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()

if __name__ == "__main__":
    main()
