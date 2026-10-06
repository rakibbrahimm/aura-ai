#!/data/data/com.termux/files/usr/bin/bash
set -e

ROOT="$HOME/AURA-AI"
cd "$ROOT"

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="backup-max-$STAMP"

echo "======================================================"
echo "             AURA AI MAXIMUM LOCAL UPGRADE"
echo "======================================================"
echo "Backup: $BACKUP"
echo

mkdir -p "$BACKUP"

echo "[1/12] Creating complete backup..."
cp -a api core config data web scripts VERSION "$BACKUP/" 2>/dev/null || true

echo "[2/12] Creating directories..."
mkdir -p api core config data/users web scripts connectors logs

touch core/__init__.py

echo "[3/12] Installing local tools..."

cat > core/local_tools.py <<'PY'
import ast
import datetime
import math
import operator
import platform
import os

_ALLOWED = {
    ast.Add: operator.add,
    ast.Sub: operator.sub,
    ast.Mult: operator.mul,
    ast.Div: operator.truediv,
    ast.FloorDiv: operator.floordiv,
    ast.Mod: operator.mod,
    ast.Pow: operator.pow,
    ast.USub: operator.neg,
    ast.UAdd: operator.pos,
}

def _eval(node):
    if isinstance(node, ast.Expression):
        return _eval(node.body)

    if isinstance(node, ast.Constant):
        if isinstance(node.value, (int, float)):
            return node.value
        raise ValueError("invalid constant")

    if isinstance(node, ast.BinOp):
        op = type(node.op)
        if op not in _ALLOWED:
            raise ValueError("operator not allowed")
        left = _eval(node.left)
        right = _eval(node.right)

        if op is ast.Pow and abs(right) > 100:
            raise ValueError("power too large")

        return _ALLOWED[op](left, right)

    if isinstance(node, ast.UnaryOp):
        op = type(node.op)
        if op not in _ALLOWED:
            raise ValueError("operator not allowed")
        return _ALLOWED[op](_eval(node.operand))

    raise ValueError("expression not allowed")

def calculator(expression):
    expression = expression.strip()

    if len(expression) > 200:
        raise ValueError("expression too long")

    tree = ast.parse(expression, mode="eval")
    result = _eval(tree)

    if isinstance(result, float) and not math.isfinite(result):
        raise ValueError("invalid result")

    return result

def system_info():
    return {
        "platform": platform.platform(),
        "python": platform.python_version(),
        "machine": platform.machine(),
        "processor": platform.processor(),
        "pid": os.getpid()
    }

def current_time():
    now = datetime.datetime.now()
    return {
        "date": now.strftime("%Y-%m-%d"),
        "time": now.strftime("%H:%M:%S"),
        "day": now.strftime("%A")
    }
PY

echo "[4/12] Installing persistent memory engine..."

cat > core/memory.py <<'PY'
import json
import os
import threading
from datetime import datetime

LOCK = threading.Lock()

def user_file(data_dir, username):
    safe = "".join(
        c for c in username
        if c.isalnum() or c in "-_."
    )[:80]

    return os.path.join(data_dir, "users", safe + ".json")

def default_user(username):
    return {
        "username": username,
        "created_at": datetime.utcnow().isoformat() + "Z",
        "profile": {
            "name": username,
            "personality": "helpful",
            "language": "auto"
        },
        "memory": [],
        "history": []
    }

def load_user(data_dir, username):
    os.makedirs(os.path.join(data_dir, "users"), exist_ok=True)
    path = user_file(data_dir, username)

    with LOCK:
        if not os.path.exists(path):
            data = default_user(username)
            save_user(data_dir, username, data)
            return data

        try:
            with open(path, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            data = default_user(username)
            save_user(data_dir, username, data)
            return data

def save_user(data_dir, username, data):
    os.makedirs(os.path.join(data_dir, "users"), exist_ok=True)
    path = user_file(data_dir, username)
    tmp = path + ".tmp"

    with LOCK:
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)

        os.replace(tmp, path)

def add_message(data_dir, username, role, content):
    data = load_user(data_dir, username)

    data.setdefault("history", []).append({
        "role": role,
        "content": content,
        "time": datetime.utcnow().isoformat() + "Z"
    })

    data["history"] = data["history"][-100:]
    save_user(data_dir, username, data)

def add_memory(data_dir, username, text):
    data = load_user(data_dir, username)

    data.setdefault("memory", []).append({
        "text": text,
        "time": datetime.utcnow().isoformat() + "Z"
    })

    data["memory"] = data["memory"][-100:]
    save_user(data_dir, username, data)
PY

echo "[5/12] Installing product configuration..."

cat > config/product.json <<'JSON'
{
  "name": "AURA AI",
  "version": "2.0.0-local-max",
  "tagline": "Your AI presence, when you're away.",
  "mode": "local",
  "brain": {
    "provider": "ollama",
    "model": "qwen2.5:0.5b",
    "url": "http://127.0.0.1:11434/api/chat"
  },
  "features": {
    "multi_user": true,
    "persistent_memory": true,
    "history": true,
    "local_tools": true,
    "voice": true,
    "pwa": true,
    "official_connectors_ready": true
  }
}
JSON

printf '2.0.0-local-max\n' > VERSION

echo "[6/12] Installing connector framework..."

cat > connectors/README.md <<'MD'
# AURA Official Connector Layer

AURA can later connect to communication services through their
official APIs.

Connector requirements:

1. Official API only.
2. User authorization required.
3. Clear AI disclosure.
4. No credential scraping.
5. No unofficial automation.
6. User can disconnect a connector.
7. Store only the minimum required data.

This directory currently contains the local connector framework only.
No external communication service is enabled by default.
MD

echo "[7/12] Installing MAX API..."

cat > api/server.py <<'PY'
import os
import json
import time
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
PY

echo "[8/12] Installing MAX web dashboard..."

cat > web/manifest.json <<'JSON'
{
  "name": "AURA AI",
  "short_name": "AURA",
  "start_url": "/",
  "display": "standalone",
  "background_color": "#05070d",
  "theme_color": "#05070d",
  "description": "AURA AI — Your AI presence, when you're away."
}
JSON

cat > web/sw.js <<'JS'
const CACHE = "aura-max-v1";

self.addEventListener("install", event => {
  event.waitUntil(
    caches.open(CACHE).then(cache =>
      cache.addAll(["/", "/manifest.json"])
    )
  );
});

self.addEventListener("fetch", event => {
  event.respondWith(
    fetch(event.request).catch(() =>
      caches.match(event.request)
    )
  );
});
JS

cat > web/index.html <<'HTML'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport"
      content="width=device-width,initial-scale=1,viewport-fit=cover">
<meta name="theme-color" content="#05070d">
<link rel="manifest" href="/manifest.json">
<title>AURA AI</title>

<style>
*{box-sizing:border-box}
body{
  margin:0;
  min-height:100vh;
  background:#05070d;
  color:#f3f6ff;
  font-family:system-ui,-apple-system,Segoe UI,sans-serif
}
header{
  padding:18px;
  border-bottom:1px solid #202638;
  display:flex;
  justify-content:space-between;
  align-items:center
}
.logo{
  font-size:25px;
  font-weight:800;
  letter-spacing:5px
}
.badge{
  font-size:11px;
  padding:6px 9px;
  border:1px solid #27314b;
  border-radius:999px
}
main{
  width:min(1000px,94%);
  margin:20px auto
}
.card{
  background:#0a0e18;
  border:1px solid #20283a;
  border-radius:18px;
  padding:18px;
  margin-bottom:16px
}
input,textarea,button,select{
  width:100%;
  padding:13px;
  border-radius:11px;
  border:1px solid #29334a;
  background:#070a12;
  color:white;
  margin-top:8px
}
button{
  cursor:pointer;
  font-weight:700
}
.row{
  display:grid;
  grid-template-columns:1fr 1fr;
  gap:10px
}
.chat{
  height:52vh;
  min-height:300px;
  overflow:auto;
  padding:10px
}
.msg{
  padding:12px 14px;
  border-radius:14px;
  margin:9px 0;
  white-space:pre-wrap;
  overflow-wrap:anywhere
}
.user{background:#172038;margin-left:12%}
.ai{background:#101723;margin-right:12%}
.muted{
  color:#8994aa;
  font-size:13px
}
.hidden{display:none}
.toolbar{
  display:grid;
  grid-template-columns:repeat(4,1fr);
  gap:8px
}
@media(max-width:650px){
  .row,.toolbar{grid-template-columns:1fr}
  .user,.ai{margin-left:0;margin-right:0}
}
</style>
</head>

<body>

<header>
  <div>
    <div class="logo">AURA</div>
    <div class="muted">Your AI presence, when you're away.</div>
  </div>
  <div id="status" class="badge">OFFLINE</div>
</header>

<main>

<section id="auth" class="card">
  <h2>Welcome to AURA</h2>
  <input id="username" placeholder="Username" autocomplete="username">
  <input id="password" type="password" placeholder="Password"
         autocomplete="current-password">

  <div class="row">
    <button onclick="login()">LOGIN</button>
    <button onclick="register()">CREATE ACCOUNT</button>
  </div>

  <p id="authMsg" class="muted"></p>
</section>

<section id="app" class="hidden">

<div class="card">
  <div class="row">
    <div>
      <strong id="who">AURA USER</strong>
      <div class="muted" id="brain">Local brain</div>
    </div>
    <button onclick="logout()">LOGOUT</button>
  </div>
</div>

<div class="card">
  <div id="chat" class="chat"></div>

  <textarea id="message"
            rows="3"
            placeholder="Talk to AURA..."></textarea>

  <div class="toolbar">
    <button onclick="send()">SEND</button>
    <button onclick="voiceInput()">🎙️ VOICE</button>
    <button onclick="speakLast()">🔊 SPEAK</button>
    <button onclick="loadHistory()">↻ HISTORY</button>
  </div>
</div>

<div class="card">
  <h3>Local Tools</h3>

  <div class="row">
    <button onclick="toolTime()">TIME</button>
    <button onclick="toolSystem()">SYSTEM</button>
  </div>

  <input id="calc" placeholder="Calculator e.g. (25*4)+10">
  <button onclick="toolCalc()">CALCULATE</button>
  <p id="toolOut" class="muted"></p>
</div>

<div class="card">
  <h3>Memory</h3>
  <input id="memoryText"
         placeholder="Something AURA should remember">
  <button onclick="saveMemory()">SAVE MEMORY</button>
  <p id="memoryOut" class="muted"></p>
</div>

<div class="card">
  <h3>Personalization</h3>

  <input id="profileName" placeholder="Your display name">

  <select id="personality">
    <option value="helpful">Helpful</option>
    <option value="concise">Concise</option>
    <option value="friendly">Friendly</option>
    <option value="technical">Technical</option>
  </select>

  <select id="language">
    <option value="auto">Auto language</option>
    <option value="English">English</option>
    <option value="Hindi">Hindi</option>
    <option value="Urdu">Urdu</option>
    <option value="Hinglish">Hinglish</option>
  </select>

  <button onclick="saveSettings()">SAVE SETTINGS</button>
</div>

</section>
</main>

<script>
let token = localStorage.getItem("aura_token") || "";
let lastReply = "";

const $ = id => document.getElementById(id);

async function api(path, options={}) {
  options.headers = {
    "Content-Type":"application/json",
    ...(options.headers || {})
  };

  if(token) {
    options.headers.Authorization = "Bearer " + token;
  }

  const r = await fetch(path, options);
  const data = await r.json().catch(()=>({}));

  if(!r.ok) {
    throw new Error(data.error || data.message || "Request failed");
  }

  return data;
}

async function register(){
  try{
    const data = await api("/register", {
      method:"POST",
      body:JSON.stringify({
        username:$("username").value.trim(),
        password:$("password").value
      })
    });

    $("authMsg").textContent = data.message;
  }catch(e){
    $("authMsg").textContent = e.message;
  }
}

async function login(){
  try{
    const data = await api("/login", {
      method:"POST",
      body:JSON.stringify({
        username:$("username").value.trim(),
        password:$("password").value
      })
    });

    token = data.token;
    localStorage.setItem("aura_token", token);

    $("auth").classList.add("hidden");
    $("app").classList.remove("hidden");

    $("who").textContent = data.username;
    $("status").textContent = "ONLINE";

    await loadStatus();
    await loadHistory();
    await loadSettings();
  }catch(e){
    $("authMsg").textContent = e.message;
  }
}

async function logout(){
  try{
    await api("/logout", {method:"POST"});
  }catch(e){}

  token="";
  localStorage.removeItem("aura_token");

  $("app").classList.add("hidden");
  $("auth").classList.remove("hidden");
  $("status").textContent="OFFLINE";
}

function addMessage(role,text){
  const div=document.createElement("div");
  div.className="msg " + (role==="user"?"user":"ai");
  div.textContent=text;
  $("chat").appendChild(div);
  $("chat").scrollTop=$("chat").scrollHeight;
}

async function send(){
  const message=$("message").value.trim();
  if(!message) return;

  addMessage("user",message);
  $("message").value="";

  try{
    const data=await api("/chat",{
      method:"POST",
      body:JSON.stringify({message})
    });

    lastReply=data.reply;
    addMessage("assistant",data.reply);
    $("brain").textContent="Brain: "+data.brain;
  }catch(e){
    addMessage("assistant","AURA error: "+e.message);
  }
}

async function loadHistory(){
  try{
    const data=await api("/history");
    $("chat").innerHTML="";

    for(const item of data.history || []){
      addMessage(
        item.role==="user"?"user":"assistant",
        item.content
      );
    }
  }catch(e){}
}

async function loadStatus(){
  try{
    const data=await api("/api/status");
    $("brain").textContent="Brain: "+data.brain;
  }catch(e){}
}

async function loadSettings(){
  try{
    const data=await api("/settings");
    const p=data.profile || {};

    $("profileName").value=p.name || "";
    $("personality").value=p.personality || "helpful";
    $("language").value=p.language || "auto";
  }catch(e){}
}

async function saveSettings(){
  try{
    await api("/settings",{
      method:"POST",
      body:JSON.stringify({
        profile:{
          name:$("profileName").value,
          personality:$("personality").value,
          language:$("language").value
        }
      })
    });

    $("memoryOut").textContent="Settings saved.";
  }catch(e){
    $("memoryOut").textContent=e.message;
  }
}

async function saveMemory(){
  try{
    await api("/memory",{
      method:"POST",
      body:JSON.stringify({
        text:$("memoryText").value
      })
    });

    $("memoryText").value="";
    $("memoryOut").textContent="Memory saved.";
  }catch(e){
    $("memoryOut").textContent=e.message;
  }
}

async function toolTime(){
  try{
    const d=await api("/tool",{
      method:"POST",
      body:JSON.stringify({tool:"time"})
    });

    $("toolOut").textContent =
      JSON.stringify(d.result);
  }catch(e){
    $("toolOut").textContent=e.message;
  }
}

async function toolSystem(){
  try{
    const d=await api("/tool",{
      method:"POST",
      body:JSON.stringify({tool:"system"})
    });

    $("toolOut").textContent =
      JSON.stringify(d.result);
  }catch(e){
    $("toolOut").textContent=e.message;
  }
}

async function toolCalc(){
  try{
    const d=await api("/tool",{
      method:"POST",
      body:JSON.stringify({
        tool:"calculator",
        expression:$("calc").value
      })
    });

    $("toolOut").textContent=String(d.result);
  }catch(e){
    $("toolOut").textContent=e.message;
  }
}

function voiceInput(){
  const SpeechRecognition =
    window.SpeechRecognition ||
    window.webkitSpeechRecognition;

  if(!SpeechRecognition){
    alert("Voice recognition is not supported by this browser.");
    return;
  }

  const r=new SpeechRecognition();
  r.lang="en-IN";
  r.interimResults=false;
  r.continuous=false;

  r.onresult=e=>{
    $("message").value=e.results[0][0].transcript;
  };

  r.start();
}

function speakLast(){
  if(!lastReply) return;

  if(!("speechSynthesis" in window)){
    alert("Speech synthesis is not supported.");
    return;
  }

  speechSynthesis.cancel();

  const u=new SpeechSynthesisUtterance(lastReply);
  u.rate=.95;
  speechSynthesis.speak(u);
}

$("message").addEventListener("keydown",e=>{
  if(e.key==="Enter" && !e.shiftKey){
    e.preventDefault();
    send();
  }
});

if("serviceWorker" in navigator){
  navigator.serviceWorker.register("/sw.js").catch(()=>{});
}

if(token){
  api("/api/status")
    .then(()=>{
      $("auth").classList.add("hidden");
      $("app").classList.remove("hidden");
      $("status").textContent="ONLINE";
      loadStatus();
      loadHistory();
      loadSettings();
    })
    .catch(()=>{
      token="";
      localStorage.removeItem("aura_token");
    });
}
</script>

</body>
</html>
HTML

echo "[9/12] Installing startup/status scripts..."

cat > scripts/start-aura.sh <<'SH'
#!/data/data/com.termux/files/usr/bin/bash
set -e

cd "$HOME/AURA-AI"

mkdir -p logs

if [ -f logs/backend.pid ]; then
    PID="$(cat logs/backend.pid 2>/dev/null || true)"

    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
        echo "AURA is already running: PID $PID"
        exit 0
    fi
fi

nohup python api/server.py > logs/backend.log 2>&1 &
PID=$!

echo "$PID" > logs/backend.pid

sleep 2

if kill -0 "$PID" 2>/dev/null; then
    echo "AURA started successfully."
    curl -s http://127.0.0.1:8090/health || true
    echo
else
    echo "AURA failed to start."
    tail -n 50 logs/backend.log || true
    exit 1
fi
SH

cat > scripts/stop-aura.sh <<'SH'
#!/data/data/com.termux/files/usr/bin/bash

cd "$HOME/AURA-AI"

if [ ! -f logs/backend.pid ]; then
    echo "AURA is not running."
    exit 0
fi

PID="$(cat logs/backend.pid 2>/dev/null || true)"

if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
    kill "$PID" 2>/dev/null || true
    echo "AURA stopped."
else
    echo "AURA process not found."
fi

rm -f logs/backend.pid
SH

cat > scripts/status.sh <<'SH'
#!/data/data/com.termux/files/usr/bin/bash

cd "$HOME/AURA-AI"

echo "=========================================="
echo "          AURA AI MAX STATUS"
echo "=========================================="

curl -s http://127.0.0.1:8090/health || true

echo
echo

if [ -f logs/backend.pid ]; then
    PID="$(cat logs/backend.pid 2>/dev/null || true)"
    echo "PID: $PID"

    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
        echo "Backend: ONLINE"
    else
        echo "Backend: OFFLINE"
    fi
else
    echo "Backend: OFFLINE"
fi

echo "Version: $(cat VERSION 2>/dev/null || echo unknown)"
echo "=========================================="
SH

chmod +x scripts/start-aura.sh
chmod +x scripts/stop-aura.sh
chmod +x scripts/status.sh

echo "[10/12] Installing compatibility launchers..."

cat > scripts/start.sh <<'SH'
#!/data/data/com.termux/files/usr/bin/bash
exec "$HOME/AURA-AI/scripts/start-aura.sh"
SH

cat > scripts/stop.sh <<'SH'
#!/data/data/com.termux/files/usr/bin/bash
exec "$HOME/AURA-AI/scripts/stop-aura.sh"
SH

chmod +x scripts/start.sh scripts/stop.sh

echo "[11/12] Validating everything..."

python -m py_compile api/server.py
python -m py_compile core/memory.py
python -m py_compile core/local_tools.py

echo "Python syntax: OK"

python - <<'PY'
import json
with open("config/product.json", encoding="utf-8") as f:
    x=json.load(f)
assert x["name"]=="AURA AI"
assert x["features"]["multi_user"] is True
print("Configuration: OK")
PY

echo "Testing local calculator..."

python - <<'PY'
from core.local_tools import calculator
assert calculator("2+3*4") == 14
print("Tools: OK")
PY

echo "[12/12] Restarting AURA..."

if [ -f logs/backend.pid ]; then
    PID="$(cat logs/backend.pid 2>/dev/null || true)"
    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
        kill "$PID" 2>/dev/null || true
        sleep 1
    fi
fi

rm -f logs/backend.pid

./scripts/start-aura.sh

sleep 2

echo
echo "Final health:"
curl -s http://127.0.0.1:8090/health
echo

echo
echo "======================================================"
echo "        AURA AI MAXIMUM LOCAL UPGRADE DONE"
echo "======================================================"
echo "Version: $(cat VERSION)"
echo "Web:     http://127.0.0.1:8090"
echo "Health:  http://127.0.0.1:8090/health"
echo "Backup:  $BACKUP"
echo
echo "Features:"
echo "  Multi-user       : ON"
echo "  Persistent memory: ON"
echo "  Chat history     : ON"
echo "  Local tools      : ON"
echo "  Voice UI         : ON"
echo "  PWA              : ON"
echo "  Settings         : ON"
echo "  Official APIs    : READY / NOT CONNECTED"
echo "======================================================"
