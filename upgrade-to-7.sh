#!/data/data/com.termux/files/usr/bin/bash
set -e

cd "$HOME/AURA-AI"

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="backup-7x-$STAMP"

echo "============================================================"
echo "              AURA AI 7.0 PRODUCTION UPGRADE"
echo "============================================================"
echo "Backup: $BACKUP"
echo

mkdir -p "$BACKUP"
cp -a api core config data web scripts connectors logs VERSION \
  "$BACKUP/" 2>/dev/null || true

mkdir -p \
  api/v1 \
  core \
  config \
  data/users \
  data/system \
  data/audit \
  connectors \
  web \
  scripts \
  logs \
  tests

echo "[1/15] Creating production configuration..."

cat > config/production.json <<'JSON'
{
  "product": {
    "name": "AURA AI",
    "version": "7.0.0-local-production",
    "tagline": "Your AI presence, when you're away."
  },
  "server": {
    "host": "127.0.0.1",
    "port": 8090
  },
  "ai": {
    "provider": "ollama",
    "model": "qwen2.5:0.5b",
    "url": "http://127.0.0.1:11434/api/chat"
  },
  "limits": {
    "max_message_chars": 10000,
    "max_history": 100,
    "max_memory": 100,
    "rate_window_seconds": 60,
    "rate_limit": 60
  },
  "features": {
    "multi_user": true,
    "memory": true,
    "history": true,
    "tools": true,
    "voice": true,
    "pwa": true,
    "audit": true,
    "rate_limit": true,
    "admin": true,
    "analytics": true,
    "connectors": true,
    "billing": true
  },
  "external_services": {
    "whatsapp": false,
    "telegram": false,
    "instagram": false,
    "email": false,
    "payments": false
  }
}
JSON

cat > config/secrets.example.json <<'JSON'
{
  "production": {
    "secret_key": "GENERATE_A_REAL_SECRET",
    "database_url": "",
    "connectors": {
      "whatsapp": {
        "access_token": "",
        "phone_number_id": ""
      },
      "telegram": {
        "bot_token": ""
      },
      "instagram": {
        "access_token": ""
      }
    },
    "payments": {
      "provider": "",
      "secret_key": "",
      "webhook_secret": ""
    }
  }
}
JSON

chmod 600 config/secrets.example.json

echo "[2/15] Installing security/rate-limit/audit engine..."

cat > core/security.py <<'PY'
import hashlib
import hmac
import secrets
import time
import threading

_lock = threading.Lock()
_attempts = {}

def random_token(length=32):
    return secrets.token_urlsafe(length)

def hash_value(value):
    return hashlib.sha256(value.encode()).hexdigest()

def secure_compare(a, b):
    return hmac.compare_digest(str(a), str(b))

def rate_allowed(key, limit=60, window=60):
    now = time.time()

    with _lock:
        entries = _attempts.setdefault(key, [])
        entries[:] = [x for x in entries if now - x < window]

        if len(entries) >= limit:
            return False

        entries.append(now)
        return True

def clean_rate_state():
    now = time.time()

    with _lock:
        for key in list(_attempts):
            _attempts[key] = [
                x for x in _attempts[key]
                if now - x < 3600
            ]

            if not _attempts[key]:
                del _attempts[key]
PY

cat > core/audit.py <<'PY'
import json
import os
import threading
import time

_LOCK = threading.Lock()

def write_audit(root, event, username=None, metadata=None):
    directory = os.path.join(root, "data", "audit")
    os.makedirs(directory, exist_ok=True)

    record = {
        "time": time.time(),
        "event": event,
        "username": username,
        "metadata": metadata or {}
    }

    path = os.path.join(directory, "events.jsonl")

    with _LOCK:
        with open(path, "a", encoding="utf-8") as f:
            f.write(json.dumps(record, ensure_ascii=False) + "\n")
PY

cat > core/analytics.py <<'PY'
import json
import os
import threading
import time

_LOCK = threading.Lock()

def event(root, name, username=None, value=1):
    directory = os.path.join(root, "data", "system")
    os.makedirs(directory, exist_ok=True)

    path = os.path.join(directory, "analytics.json")

    with _LOCK:
        try:
            with open(path, "r", encoding="utf-8") as f:
                data = json.load(f)
        except Exception:
            data = {
                "events": {},
                "users": {},
                "updated": 0
            }

        data["events"][name] = data["events"].get(name, 0) + value

        if username:
            data["users"][username] = \
                data["users"].get(username, 0) + value

        data["updated"] = time.time()

        tmp = path + ".tmp"

        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)

        os.replace(tmp, path)

def read(root):
    path = os.path.join(
        root, "data", "system", "analytics.json"
    )

    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {
            "events": {},
            "users": {},
            "updated": 0
        }
PY

echo "[3/15] Installing connector architecture..."

cat > connectors/base.py <<'PY'
class Connector:
    name = "base"

    def status(self):
        return {
            "name": self.name,
            "enabled": False,
            "configured": False
        }

    def send(self, payload):
        raise NotImplementedError(
            "Connector must implement send()"
        )

    def receive(self, payload):
        raise NotImplementedError(
            "Connector must implement receive()"
        )
PY

cat > connectors/registry.py <<'PY'
from .base import Connector

class ConnectorRegistry:
    def __init__(self):
        self.items = {}

    def register(self, connector):
        if not isinstance(connector, Connector):
            raise TypeError("Invalid connector")
        self.items[connector.name] = connector

    def status(self):
        return {
            name: connector.status()
            for name, connector in self.items.items()
        }
PY

cat > connectors/README.md <<'MD'
# AURA 7.0 Connector Architecture

Supported connector slots:

- WhatsApp Business / Meta official API
- Telegram Bot API
- Instagram official APIs where permitted
- Email providers
- Future approved communication services

Rules:

- Official API only.
- Explicit user authorization.
- No credential scraping.
- No unofficial automation.
- No secret impersonation.
- AI identity/disclosure must follow the platform and user configuration.
- Connectors remain disabled until configured.

This package provides architecture only.
It does not claim any external service is connected.
MD

echo "[4/15] Installing billing abstraction..."

cat > core/billing.py <<'PY'
import json
import os
import time

def billing_status(root):
    path = os.path.join(root, "data", "system", "billing.json")

    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {
            "provider": None,
            "enabled": False,
            "plans": {
                "free": {
                    "monthly_messages": 100
                },
                "pro": {
                    "monthly_messages": 5000
                }
            },
            "updated": time.time()
        }

def save_billing(root, data):
    directory = os.path.join(root, "data", "system")
    os.makedirs(directory, exist_ok=True)

    path = os.path.join(directory, "billing.json")
    tmp = path + ".tmp"

    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)

    os.replace(tmp, path)
PY

echo "[5/15] Installing admin/roles engine..."

cat > core/roles.py <<'PY'
ROLES = {
    "user": {
        "chat",
        "memory",
        "history",
        "settings"
    },
    "admin": {
        "chat",
        "memory",
        "history",
        "settings",
        "analytics",
        "audit",
        "users",
        "connectors",
        "billing"
    }
}

def allowed(role, permission):
    return permission in ROLES.get(role, set())
PY

echo "[6/15] Installing database abstraction..."

cat > core/store.py <<'PY'
import json
import os
import threading

_LOCK = threading.Lock()

class JSONStore:
    def __init__(self, root):
        self.root = root
        os.makedirs(root, exist_ok=True)

    def path(self, name):
        safe = "".join(
            c for c in name
            if c.isalnum() or c in "-_."
        )
        return os.path.join(self.root, safe + ".json")

    def read(self, name, default=None):
        path = self.path(name)

        with _LOCK:
            try:
                with open(path, "r", encoding="utf-8") as f:
                    return json.load(f)
            except Exception:
                return default

    def write(self, name, value):
        path = self.path(name)
        tmp = path + ".tmp"

        with _LOCK:
            with open(tmp, "w", encoding="utf-8") as f:
                json.dump(
                    value,
                    f,
                    ensure_ascii=False,
                    indent=2
                )

            os.replace(tmp, path)
PY

echo "[7/15] Installing production API..."

cat > api/v1/__init__.py <<'PY'
__version__ = "7.0.0"
PY

cat > api/v1/system.py <<'PY'
import os
import platform
import time

def status():
    return {
        "python": platform.python_version(),
        "platform": platform.platform(),
        "machine": platform.machine(),
        "pid": os.getpid(),
        "time": time.time()
    }
PY

echo "[8/15] Installing API compatibility layer..."

cat > api/server.py <<'PY'
import os
import sys
import json
import time
import uuid
import hashlib
import secrets
import logging
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "..")
)

if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

from core.memory import (
    load_user,
    save_user,
    add_message,
    add_memory
)
from core.local_tools import (
    calculator,
    system_info,
    current_time
)
from core.security import (
    rate_allowed,
    random_token
)
from core.audit import write_audit
from core.analytics import event, read as analytics_read
from core.billing import billing_status
from core.roles import allowed
from api.v1.system import status as system_status

HOST = "127.0.0.1"
PORT = 8090

DATA = os.path.join(ROOT, "data")
WEB = os.path.join(ROOT, "web")
LOGS = os.path.join(ROOT, "logs")
CONFIG = os.path.join(
    ROOT,
    "config",
    "production.json"
)

os.makedirs(os.path.join(DATA, "users"), exist_ok=True)
os.makedirs(os.path.join(DATA, "system"), exist_ok=True)
os.makedirs(os.path.join(DATA, "audit"), exist_ok=True)
os.makedirs(LOGS, exist_ok=True)

logging.basicConfig(
    filename=os.path.join(LOGS, "aura.log"),
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s"
)

with open(CONFIG, encoding="utf-8") as f:
    CFG = json.load(f)

BRAIN = CFG["ai"]

SESSIONS = {}
SESSION_TTL = 7 * 24 * 60 * 60

def hash_password(password, salt=None):
    salt = salt or secrets.token_hex(16)

    digest = hashlib.pbkdf2_hmac(
        "sha256",
        password.encode(),
        salt.encode(),
        150000
    ).hex()

    return (
        "pbkdf2$150000$"
        + salt
        + "$"
        + digest
    )

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

            return secrets.compare_digest(
                actual,
                expected
            )
        except Exception:
            return False

    return secrets.compare_digest(
        hashlib.sha256(password.encode()).hexdigest(),
        stored
    )

def user_path(username):
    safe = "".join(
        c for c in username
        if c.isalnum() or c in "-_."
    )

    return os.path.join(
        DATA,
        "users",
        safe[:80] + ".json"
    )

def create_account(username, password):
    path = user_path(username)

    if os.path.exists(path):
        return False, "Account already exists."

    if len(username) < 3 or len(username) > 40:
        return False, "Username must be 3-40 characters."

    if len(password) < 6:
        return False, "Password must be at least 6 characters."

    data = {
        "username": username,
        "password": hash_password(password),
        "role": "user",
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

    write_audit(
        ROOT,
        "account_created",
        username
    )

    event(
        ROOT,
        "account_created",
        username
    )

    return True, "Account created."

def save_account(username, data):
    path = user_path(username)
    tmp = path + ".tmp"

    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(
            data,
            f,
            ensure_ascii=False,
            indent=2
        )

    os.replace(tmp, path)

def login(username, password):
    path = user_path(username)

    if not os.path.exists(path):
        return None

    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except Exception:
        return None

    if not verify_password(
        password,
        data.get("password", "")
    ):
        return None

    if not data.get("password", "").startswith("pbkdf2$"):
        data["password"] = hash_password(password)
        save_account(username, data)

    token = random_token(32)

    SESSIONS[token] = {
        "username": username,
        "role": data.get("role", "user"),
        "expires": time.time() + SESSION_TTL
    }

    write_audit(
        ROOT,
        "login",
        username
    )

    event(
        ROOT,
        "login",
        username
    )

    return token

def auth(handler):
    token = handler.headers.get(
        "Authorization",
        ""
    )

    if token.startswith("Bearer "):
        token = token[7:]

    session = SESSIONS.get(token)

    if not session:
        return None

    if session["expires"] < time.time():
        SESSIONS.pop(token, None)
        return None

    session["expires"] = (
        time.time() + SESSION_TTL
    )

    return session

def json_response(handler, data, status=200):
    raw = json.dumps(
        data,
        ensure_ascii=False
    ).encode()

    handler.send_response(status)
    handler.send_header(
        "Content-Type",
        "application/json; charset=utf-8"
    )
    handler.send_header(
        "Content-Length",
        str(len(raw))
    )
    handler.send_header(
        "Access-Control-Allow-Origin",
        "*"
    )
    handler.send_header(
        "Access-Control-Allow-Headers",
        "Content-Type, Authorization"
    )
    handler.send_header(
        "Access-Control-Allow-Methods",
        "GET, POST, OPTIONS"
    )
    handler.end_headers()

    handler.wfile.write(raw)

def read_json(handler):
    length = int(
        handler.headers.get(
            "Content-Length",
            "0"
        )
    )

    if length > 1024 * 1024:
        raise ValueError("Request too large")

    raw = handler.rfile.read(length)

    if not raw:
        return {}

    return json.loads(
        raw.decode()
    )

def ollama(messages, username):
    user = load_user(
        DATA,
        username
    )

    profile = user.get(
        "profile",
        {}
    )

    memories = user.get(
        "memory",
        []
    )[-10:]

    system = f"""
You are AURA AI.

AURA AI is a personal AI assistant.

Creator:
RAKIB

Tagline:
Your AI presence, when you're away.

Current local model:
{BRAIN.get("model")}

Never claim to be another AI company or product.
Never claim an external connector is active unless it is actually configured.
Be transparent that this deployment is local.

User:
{username}

Personality:
{profile.get("personality", "helpful")}

Language:
{profile.get("language", "auto")}

Saved memories:
{json.dumps(memories, ensure_ascii=False)}
""".strip()

    payload = {
        "model": BRAIN.get(
            "model",
            "qwen2.5:0.5b"
        ),
        "messages": [
            {
                "role": "system",
                "content": system
            }
        ] + messages[-20:],
        "stream": False
    }

    request = urllib.request.Request(
        BRAIN.get(
            "url",
            "http://127.0.0.1:11434/api/chat"
        ),
        data=json.dumps(
            payload
        ).encode(),
        headers={
            "Content-Type":
                "application/json"
        },
        method="POST"
    )

    with urllib.request.urlopen(
        request,
        timeout=90
    ) as response:
        result = json.loads(
            response.read().decode()
        )

    return result.get(
        "message",
        {}
    ).get(
        "content",
        "I couldn't generate a response."
    )

class Handler(BaseHTTPRequestHandler):

    def log_message(self, fmt, *args):
        logging.info(
            "%s - %s",
            self.address_string(),
            fmt % args
        )

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header(
            "Access-Control-Allow-Origin",
            "*"
        )
        self.send_header(
            "Access-Control-Allow-Headers",
            "Content-Type, Authorization"
        )
        self.send_header(
            "Access-Control-Allow-Methods",
            "GET, POST, OPTIONS"
        )
        self.end_headers()

    def do_GET(self):
        try:
            path = self.path.split(
                "?",
                1
            )[0]

            if path == "/health":
                return json_response(
                    self,
                    {
                        "status": "ok",
                        "service": "AURA AI",
                        "version": CFG[
                            "product"
                        ]["version"],
                        "brain": BRAIN["model"],
                        "multi_user": True,
                        "memory": True,
                        "tools": True,
                        "audit": True,
                        "analytics": True,
                        "connectors": True,
                        "billing": True
                    }
                )

            if path == "/":
                return self.serve(
                    "index.html",
                    "text/html; charset=utf-8"
                )

            if path == "/manifest.json":
                return self.serve(
                    "manifest.json",
                    "application/json"
                )

            if path == "/sw.js":
                return self.serve(
                    "sw.js",
                    "application/javascript"
                )

            session = auth(self)

            if path == "/api/status":
                return json_response(
                    self,
                    {
                        "service": "AURA AI",
                        "version": CFG[
                            "product"
                        ]["version"],
                        "authenticated": bool(session),
                        "user": (
                            session["username"]
                            if session else None
                        ),
                        "brain": BRAIN["model"]
                    }
                )

            if not session:
                return json_response(
                    self,
                    {"error": "Unauthorized"},
                    401
                )

            username = session["username"]

            if path == "/history":
                user = load_user(
                    DATA,
                    username
                )

                return json_response(
                    self,
                    {
                        "history":
                            user.get(
                                "history",
                                []
                            )
                    }
                )

            if path == "/memory":
                user = load_user(
                    DATA,
                    username
                )

                return json_response(
                    self,
                    {
                        "memory":
                            user.get(
                                "memory",
                                []
                            )
                    }
                )

            if path == "/settings":
                user = load_user(
                    DATA,
                    username
                )

                return json_response(
                    self,
                    {
                        "profile":
                            user.get(
                                "profile",
                                {}
                            )
                    }
                )

            if path == "/admin/analytics":
                if not allowed(
                    session["role"],
                    "analytics"
                ):
                    return json_response(
                        self,
                        {"error": "Forbidden"},
                        403
                    )

                return json_response(
                    self,
                    analytics_read(ROOT)
                )

            if path == "/admin/system":
                if not allowed(
                    session["role"],
                    "analytics"
                ):
                    return json_response(
                        self,
                        {"error": "Forbidden"},
                        403
                    )

                return json_response(
                    self,
                    {
                        "system":
                            system_status(),
                        "billing":
                            billing_status(ROOT),
                        "connectors": {
                            "whatsapp":
                                False,
                            "telegram":
                                False,
                            "instagram":
                                False,
                            "email":
                                False
                        }
                    }
                )

            return self.serve(
                path.lstrip("/")
            )

        except Exception as exc:
            logging.exception(
                "GET failure"
            )

            return json_response(
                self,
                {"error": str(exc)},
                500
            )

    def do_POST(self):
        try:
            path = self.path.split(
                "?",
                1
            )[0]

            data = read_json(self)

            client = self.client_address[0]

            if not rate_allowed(
                client,
                CFG["limits"]["rate_limit"],
                CFG["limits"]["rate_window_seconds"]
            ):
                return json_response(
                    self,
                    {
                        "error":
                            "Rate limit exceeded."
                    },
                    429
                )

            if path == "/register":
                username = str(
                    data.get(
                        "username",
                        ""
                    )
                ).strip()

                password = str(
                    data.get(
                        "password",
                        ""
                    )
                )

                ok, message = create_account(
                    username,
                    password
                )

                return json_response(
                    self,
                    {
                        "ok": ok,
                        "message": message
                    },
                    200 if ok else 400
                )

            if path == "/login":
                username = str(
                    data.get(
                        "username",
                        ""
                    )
                ).strip()

                password = str(
                    data.get(
                        "password",
                        ""
                    )
                )

                token = login(
                    username,
                    password
                )

                if not token:
                    return json_response(
                        self,
                        {
                            "ok": False,
                            "error":
                                "Invalid username or password."
                        },
                        401
                    )

                return json_response(
                    self,
                    {
                        "ok": True,
                        "token": token,
                        "username": username
                    }
                )

            session = auth(self)

            if not session:
                return json_response(
                    self,
                    {"error": "Unauthorized"},
                    401
                )

            username = session["username"]

            if path == "/logout":
                token = self.headers.get(
                    "Authorization",
                    ""
                )

                if token.startswith("Bearer "):
                    token = token[7:]

                SESSIONS.pop(
                    token,
                    None
                )

                write_audit(
                    ROOT,
                    "logout",
                    username
                )

                return json_response(
                    self,
                    {"ok": True}
                )

            if path == "/chat":
                message = str(
                    data.get(
                        "message",
                        ""
                    )
                ).strip()

                max_chars = CFG[
                    "limits"
                ]["max_message_chars"]

                if not message:
                    return json_response(
                        self,
                        {
                            "error":
                                "Message required."
                        },
                        400
                    )

                if len(message) > max_chars:
                    return json_response(
                        self,
                        {
                            "error":
                                "Message too long."
                        },
                        400
                    )

                user = load_user(
                    DATA,
                    username
                )

                previous = [
                    {
                        "role":
                            item.get(
                                "role"
                            ),
                        "content":
                            item.get(
                                "content"
                            )
                    }
                    for item in user.get(
                        "history",
                        []
                    )[-20:]
                    if item.get(
                        "role"
                    ) in (
                        "user",
                        "assistant"
                    )
                ]

                add_message(
                    DATA,
                    username,
                    "user",
                    message
                )

                try:
                    reply = ollama(
                        previous + [
                            {
                                "role":
                                    "user",
                                "content":
                                    message
                            }
                        ],
                        username
                    )
                except Exception as exc:
                    logging.exception(
                        "AI failure"
                    )

                    return json_response(
                        self,
                        {
                            "error":
                                "Local AI unavailable.",
                            "detail":
                                str(exc)
                        },
                        503
                    )

                add_message(
                    DATA,
                    username,
                    "assistant",
                    reply
                )

                event(
                    ROOT,
                    "chat",
                    username
                )

                return json_response(
                    self,
                    {
                        "ok": True,
                        "reply": reply,
                        "brain": BRAIN["model"],
                        "user": username
                    }
                )

            if path == "/memory":
                value = str(
                    data.get(
                        "text",
                        ""
                    )
                ).strip()

                if not value:
                    return json_response(
                        self,
                        {
                            "error":
                                "Memory required."
                        },
                        400
                    )

                add_memory(
                    DATA,
                    username,
                    value[:2000]
                )

                event(
                    ROOT,
                    "memory_saved",
                    username
                )

                return json_response(
                    self,
                    {"ok": True}
                )

            if path == "/settings":
                profile = data.get(
                    "profile",
                    {}
                )

                user = load_user(
                    DATA,
                    username
                )

                current = user.setdefault(
                    "profile",
                    {}
                )

                if isinstance(
                    profile,
                    dict
                ):
                    for key in (
                        "name",
                        "personality",
                        "language"
                    ):
                        if key in profile:
                            current[key] = str(
                                profile[key]
                            )[:500]

                save_user(
                    DATA,
                    username,
                    user
                )

                return json_response(
                    self,
                    {
                        "ok": True,
                        "profile":
                            current
                    }
                )

            if path == "/tool":
                tool = str(
                    data.get(
                        "tool",
                        ""
                    )
                )

                if tool == "calculator":
                    try:
                        result = calculator(
                            str(
                                data.get(
                                    "expression",
                                    ""
                                )
                            )
                        )

                        return json_response(
                            self,
                            {
                                "ok": True,
                                "result": result
                            }
                        )
                    except Exception as exc:
                        return json_response(
                            self,
                            {
                                "ok": False,
                                "error": str(exc)
                            },
                            400
                        )

                if tool == "time":
                    return json_response(
                        self,
                        {
                            "ok": True,
                            "result":
                                current_time()
                        }
                    )

                if tool == "system":
                    return json_response(
                        self,
                        {
                            "ok": True,
                            "result":
                                system_info()
                        }
                    )

                return json_response(
                    self,
                    {
                        "error":
                            "Unknown tool."
                    },
                    400
                )

            return json_response(
                self,
                {"error": "Not found"},
                404
            )

        except Exception as exc:
            logging.exception(
                "POST failure"
            )

            return json_response(
                self,
                {"error": str(exc)},
                500
            )

    def serve(
        self,
        filename,
        content_type=None
    ):
        if ".." in filename:
            return json_response(
                self,
                {"error": "Invalid path"},
                400
            )

        path = os.path.join(
            WEB,
            filename
        )

        if not os.path.isfile(path):
            return json_response(
                self,
                {"error": "Not found"},
                404
            )

        if not content_type:
            if filename.endswith(".js"):
                content_type = (
                    "application/javascript"
                )
            elif filename.endswith(".css"):
                content_type = "text/css"
            else:
                content_type = "text/plain"

        with open(path, "rb") as f:
            raw = f.read()

        self.send_response(200)
        self.send_header(
            "Content-Type",
            content_type
        )
        self.send_header(
            "Content-Length",
            str(len(raw))
        )
        self.send_header(
            "Cache-Control",
            "no-cache"
        )
        self.end_headers()
        self.wfile.write(raw)

def main():
    print("=" * 55)
    print("                 AURA AI 7.0")
    print("=" * 55)
    print("Server:", f"http://{HOST}:{PORT}")
    print("Brain:", BRAIN["model"])
    print("Multi-user: ENABLED")
    print("Memory: ENABLED")
    print("Security: ENABLED")
    print("Audit: ENABLED")
    print("Analytics: ENABLED")
    print("Connectors: READY")
    print("Billing: READY")
    print("=" * 55)

    server = ThreadingHTTPServer(
        (HOST, PORT),
        Handler
    )

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()

if __name__ == "__main__":
    main()
PY

echo "[9/15] Installing production dashboard..."

cat > web/manifest.json <<'JSON'
{
  "name": "AURA AI 7.0",
  "short_name": "AURA",
  "start_url": "/",
  "display": "standalone",
  "background_color": "#05070d",
  "theme_color": "#05070d",
  "description": "AURA AI — Your AI presence, when you're away."
}
JSON

cat > web/sw.js <<'JS'
const CACHE = "aura-7-v1";

self.addEventListener("install", event => {
  event.waitUntil(
    caches.open(CACHE).then(cache =>
      cache.addAll([
        "/",
        "/manifest.json"
      ])
    )
  );
});

self.addEventListener("activate", event => {
  event.waitUntil(
    caches.keys().then(keys =>
      Promise.all(
        keys
          .filter(k => k !== CACHE)
          .map(k => caches.delete(k))
      )
    )
  );
});

self.addEventListener("fetch", event => {
  event.respondWith(
    fetch(event.request).catch(
      () => caches.match(event.request)
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
<title>AURA AI 7.0</title>
<style>
*{box-sizing:border-box}
body{
 margin:0;
 background:#05070d;
 color:#eef3ff;
 font-family:system-ui,-apple-system,Segoe UI,sans-serif
}
header{
 padding:18px;
 border-bottom:1px solid #20283a;
 display:flex;
 justify-content:space-between;
 align-items:center
}
.logo{
 font-size:25px;
 font-weight:900;
 letter-spacing:6px
}
.badge{
 border:1px solid #2b3650;
 border-radius:999px;
 padding:6px 10px;
 font-size:11px
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
 margin-top:8px;
 border-radius:11px;
 border:1px solid #29334a;
 background:#070a12;
 color:#fff
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
 height:50vh;
 min-height:300px;
 overflow:auto
}
.msg{
 padding:12px;
 margin:8px 0;
 border-radius:14px;
 white-space:pre-wrap;
 overflow-wrap:anywhere
}
.user{background:#18223a}
.ai{background:#111927}
.muted{color:#8792aa;font-size:13px}
.hidden{display:none}
.tools{
 display:grid;
 grid-template-columns:repeat(4,1fr);
 gap:8px
}
@media(max-width:650px){
 .row,.tools{grid-template-columns:1fr}
}
</style>
</head>
<body>

<header>
 <div>
  <div class="logo">AURA</div>
  <div class="muted">
   Your AI presence, when you're away.
  </div>
 </div>
 <div id="status" class="badge">OFFLINE</div>
</header>

<main>

<section id="auth" class="card">
 <h2>AURA AI 7.0</h2>
 <input id="username" placeholder="Username">
 <input id="password" type="password" placeholder="Password">

 <div class="row">
  <button onclick="login()">LOGIN</button>
  <button onclick="register()">REGISTER</button>
 </div>

 <p id="authMsg" class="muted"></p>
</section>

<section id="app" class="hidden">

<div class="card">
 <div class="row">
  <div>
   <strong id="who">USER</strong>
   <div id="brain" class="muted">Local brain</div>
  </div>
  <button onclick="logout()">LOGOUT</button>
 </div>
</div>

<div class="card">
 <div id="chat" class="chat"></div>

 <textarea id="message"
  rows="3"
  placeholder="Talk to AURA..."></textarea>

 <div class="tools">
  <button onclick="send()">SEND</button>
  <button onclick="voice()">🎙️ VOICE</button>
  <button onclick="speak()">🔊 SPEAK</button>
  <button onclick="historyLoad()">↻ HISTORY</button>
 </div>
</div>

<div class="card">
 <h3>Local Tools</h3>
 <input id="calc"
  placeholder="Calculator: (25*4)+10">
 <div class="row">
  <button onclick="calc()">CALCULATE</button>
  <button onclick="timeTool()">TIME</button>
 </div>
 <button onclick="systemTool()">SYSTEM INFO</button>
 <p id="tool" class="muted"></p>
</div>

<div class="card">
 <h3>Memory</h3>
 <input id="mem"
  placeholder="Save something for AURA">
 <button onclick="memory()">SAVE MEMORY</button>
</div>

<div class="card">
 <h3>Profile</h3>
 <input id="name" placeholder="Display name">

 <select id="personality">
  <option>helpful</option>
  <option>friendly</option>
  <option>concise</option>
  <option>technical</option>
 </select>

 <select id="language">
  <option>auto</option>
  <option>English</option>
  <option>Hindi</option>
  <option>Urdu</option>
  <option>Hinglish</option>
 </select>

 <button onclick="settings()">
  SAVE SETTINGS
 </button>
</div>

</section>
</main>

<script>
let token=localStorage.getItem("aura7_token")||"";
let last="";

const $=x=>document.getElementById(x);

async function api(path,opt={}){
 opt.headers={
  "Content-Type":"application/json",
  ...(opt.headers||{})
 };

 if(token)
  opt.headers.Authorization="Bearer "+token;

 const r=await fetch(path,opt);
 const d=await r.json().catch(()=>({}));

 if(!r.ok)
  throw Error(d.error||d.message||"Request failed");

 return d;
}

async function register(){
 try{
  const d=await api("/register",{
   method:"POST",
   body:JSON.stringify({
    username:$("username").value.trim(),
    password:$("password").value
   })
  });

  $("authMsg").textContent=d.message;
 }catch(e){
  $("authMsg").textContent=e.message;
 }
}

async function login(){
 try{
  const d=await api("/login",{
   method:"POST",
   body:JSON.stringify({
    username:$("username").value.trim(),
    password:$("password").value
   })
  });

  token=d.token;
  localStorage.setItem("aura7_token",token);

  $("auth").classList.add("hidden");
  $("app").classList.remove("hidden");
  $("status").textContent="ONLINE";
  $("who").textContent=d.username;

  await status();
  await historyLoad();
  await loadSettings();
 }catch(e){
  $("authMsg").textContent=e.message;
 }
}

async function logout(){
 try{
  await api("/logout",{method:"POST"});
 }catch(e){}

 token="";
 localStorage.removeItem("aura7_token");
 location.reload();
}

function add(role,text){
 const d=document.createElement("div");
 d.className="msg "+(
  role==="user"?"user":"ai"
 );
 d.textContent=text;
 $("chat").appendChild(d);
 $("chat").scrollTop=$("chat").scrollHeight;
}

async function send(){
 const text=$("message").value.trim();
 if(!text)return;

 add("user",text);
 $("message").value="";

 try{
  const d=await api("/chat",{
   method:"POST",
   body:JSON.stringify({
    message:text
   })
  });

  last=d.reply;
  add("assistant",d.reply);
  $("brain").textContent=
   "Brain: "+d.brain;
 }catch(e){
  add("assistant","AURA: "+e.message);
 }
}

async function historyLoad(){
 try{
  const d=await api("/history");
  $("chat").innerHTML="";

  for(const x of d.history||[])
   add(
    x.role==="user"?"user":"assistant",
    x.content
   );
 }catch(e){}
}

async function status(){
 try{
  const d=await api("/api/status");
  $("brain").textContent=
   "Brain: "+d.brain;
 }catch(e){}
}

async function loadSettings(){
 try{
  const d=await api("/settings");
  const p=d.profile||{};

  $("name").value=p.name||"";
  $("personality").value=
   p.personality||"helpful";
  $("language").value=
   p.language||"auto";
 }catch(e){}
}

async function settings(){
 try{
  await api("/settings",{
   method:"POST",
   body:JSON.stringify({
    profile:{
     name:$("name").value,
     personality:$("personality").value,
     language:$("language").value
    }
   })
  });
 }catch(e){
  alert(e.message);
 }
}

async function memory(){
 try{
  await api("/memory",{
   method:"POST",
   body:JSON.stringify({
    text:$("mem").value
   })
  });

  $("mem").value="";
 }catch(e){
  alert(e.message);
 }
}

async function calc(){
 try{
  const d=await api("/tool",{
   method:"POST",
   body:JSON.stringify({
    tool:"calculator",
    expression:$("calc").value
   })
  });

  $("tool").textContent=
   "Result: "+d.result;
 }catch(e){
  $("tool").textContent=e.message;
 }
}

async function timeTool(){
 try{
  const d=await api("/tool",{
   method:"POST",
   body:JSON.stringify({
    tool:"time"
   })
  });

  $("tool").textContent=
   JSON.stringify(d.result);
 }catch(e){}
}

async function systemTool(){
 try{
  const d=await api("/tool",{
   method:"POST",
   body:JSON.stringify({
    tool:"system"
   })
  });

  $("tool").textContent=
   JSON.stringify(d.result);
 }catch(e){}
}

function voice(){
 const R=
  window.SpeechRecognition||
  window.webkitSpeechRecognition;

 if(!R){
  alert("Voice recognition unavailable.");
  return;
 }

 const r=new R();
 r.lang="en-IN";
 r.continuous=false;
 r.interimResults=false;

 r.onresult=e=>{
  $("message").value=
   e.results[0][0].transcript;
 };

 r.start();
}

function speak(){
 if(!last)return;

 if(!window.speechSynthesis){
  alert("Speech synthesis unavailable.");
  return;
 }

 speechSynthesis.cancel();

 const u=
  new SpeechSynthesisUtterance(last);

 speechSynthesis.speak(u);
}

$("message").addEventListener(
 "keydown",
 e=>{
  if(e.key==="Enter"&&!e.shiftKey){
   e.preventDefault();
   send();
  }
 }
);

if("serviceWorker" in navigator)
 navigator.serviceWorker.register("/sw.js")
  .catch(()=>{});

if(token){
 api("/api/status")
  .then(()=>{
   $("auth").classList.add("hidden");
   $("app").classList.remove("hidden");
   $("status").textContent="ONLINE";
   status();
   historyLoad();
   loadSettings();
  })
  .catch(()=>{
   token="";
   localStorage.removeItem("aura7_token");
  });
}
</script>
</body>
</html>
HTML

echo "[10/15] Installing deployment helpers..."

cat > scripts/start-aura.sh <<'SH'
#!/data/data/com.termux/files/usr/bin/bash
set -e

cd "$HOME/AURA-AI"
mkdir -p logs

export PYTHONPATH="$HOME/AURA-AI${PYTHONPATH:+:$PYTHONPATH}"

if [ -f logs/backend.pid ]; then
 PID="$(cat logs/backend.pid 2>/dev/null || true)"
 if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
  echo "AURA already running: $PID"
  exit 0
 fi
fi

nohup python "$HOME/AURA-AI/api/server.py" \
 > "$HOME/AURA-AI/logs/backend.log" 2>&1 &

PID=$!
echo "$PID" > logs/backend.pid

sleep 2

if kill -0 "$PID" 2>/dev/null; then
 echo "AURA started successfully."
 curl -s http://127.0.0.1:8090/health || true
 echo
else
 echo "AURA failed to start."
 tail -n 80 logs/backend.log || true
 exit 1
fi
SH

cat > scripts/stop-aura.sh <<'SH'
#!/data/data/com.termux/files/usr/bin/bash

cd "$HOME/AURA-AI"

if [ -f logs/backend.pid ]; then
 PID="$(cat logs/backend.pid 2>/dev/null || true)"

 if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
  kill "$PID" 2>/dev/null || true
  sleep 1
 fi

 rm -f logs/backend.pid
fi

echo "AURA stopped."
SH

cat > scripts/status.sh <<'SH'
#!/data/data/com.termux/files/usr/bin/bash

cd "$HOME/AURA-AI"

echo "================================================"
echo "                 AURA AI 7.0"
echo "================================================"

curl -s http://127.0.0.1:8090/health || true
echo

if [ -f logs/backend.pid ]; then
 PID="$(cat logs/backend.pid 2>/dev/null || true)"

 if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
  echo "Backend: ONLINE"
  echo "PID: $PID"
 else
  echo "Backend: OFFLINE"
 fi
else
 echo "Backend: OFFLINE"
fi

echo "Version: $(cat VERSION 2>/dev/null || echo unknown)"
echo "================================================"
SH

cat > scripts/start.sh <<'SH'
#!/data/data/com.termux/files/usr/bin/bash
exec "$HOME/AURA-AI/scripts/start-aura.sh"
SH

cat > scripts/stop.sh <<'SH'
#!/data/data/com.termux/files/usr/bin/bash
exec "$HOME/AURA-AI/scripts/stop-aura.sh"
SH

chmod +x scripts/*.sh

echo "[11/15] Installing test suite..."

cat > tests/test_core.py <<'PY'
import os
import sys
import tempfile

ROOT = os.path.abspath(
    os.path.join(
        os.path.dirname(__file__),
        ".."
    )
)

sys.path.insert(0, ROOT)

from core.local_tools import calculator
from core.security import rate_allowed
from core.billing import billing_status

assert calculator("2+3*4") == 14

assert rate_allowed(
    "test-key-fresh",
    limit=2,
    window=60
)

assert rate_allowed(
    "test-key-fresh",
    limit=2,
    window=60
)

assert rate_allowed(
    "test-key-fresh",
    limit=2,
    window=60
) is False

with tempfile.TemporaryDirectory() as d:
    x = billing_status(d)
    assert "plans" in x

print("CORE TESTS: PASS")
PY

python tests/test_core.py

echo "[12/15] Validating all Python modules..."

python -m py_compile \
 api/server.py \
 api/v1/__init__.py \
 api/v1/system.py \
 core/security.py \
 core/audit.py \
 core/analytics.py \
 core/billing.py \
 core/roles.py \
 core/store.py \
 core/memory.py \
 core/local_tools.py \
 connectors/base.py \
 connectors/registry.py

echo "PYTHON VALIDATION: PASS"

echo "[13/15] Writing release metadata..."

cat > RELEASE-7.0.md <<'MD'
# AURA AI 7.0

Production foundation.

## Included

- Multi-user authentication
- PBKDF2 password hashing
- Persistent memory
- Conversation history
- Local AI
- Local tools
- Rate limiting
- Audit logging
- Analytics
- Roles
- Admin API foundation
- Billing abstraction
- Connector registry
- PWA
- Voice UI
- Backup/rollback foundation
- Production configuration
- API version namespace

## External integrations

External messaging and payment providers are intentionally disabled
until official API credentials and authorization are configured.

## Current local brain

Ollama / qwen2.5:0.5b
MD

printf '7.0.0-local-production\n' > VERSION

echo "[14/15] Restarting backend..."

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

echo "[15/15] Final production smoke test..."

python - <<'PY'
import json
import urllib.request

url = "http://127.0.0.1:8090/health"

with urllib.request.urlopen(
    url,
    timeout=10
) as r:
    data = json.loads(
        r.read().decode()
    )

assert data["status"] == "ok"
assert data["version"] == "7.0.0-local-production"
assert data["multi_user"] is True
assert data["memory"] is True
assert data["tools"] is True
assert data["audit"] is True
assert data["analytics"] is True
assert data["connectors"] is True
assert data["billing"] is True

print("HEALTH TEST: PASS")
print(json.dumps(data))
PY

echo
echo "============================================================"
echo "              AURA AI 7.0 UPGRADE COMPLETE"
echo "============================================================"
echo "Version : $(cat VERSION)"
echo "Web     : http://127.0.0.1:8090"
echo "Health  : http://127.0.0.1:8090/health"
echo "Backup  : $BACKUP"
echo
echo "7.0 FEATURES"
echo "  Authentication : ON"
echo "  Memory         : ON"
echo "  History        : ON"
echo "  Local AI       : ON"
echo "  Tools          : ON"
echo "  Rate limiting  : ON"
echo "  Audit logs     : ON"
echo "  Analytics      : ON"
echo "  Roles          : ON"
echo "  Billing layer  : READY"
echo "  Connectors     : READY"
echo "  PWA            : ON"
echo "  Voice          : ON"
echo "============================================================"
