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

HOST = os.environ.get("AURA_HOST", "127.0.0.1")
PORT = int(os.environ.get("PORT", os.environ.get("AURA_PORT", "8090")))

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


def gemini(messages, username):
    api_key = os.environ.get("GEMINI_API_KEY", "").strip()
    if not api_key:
        raise RuntimeError("Cloud AI key not configured.")

    user = load_user(DATA, username)
    profile = user.get("profile", {})
    memories = user.get("memory", [])[-10:]

    system = f"""
You are AURA AI.
Creator: RAKIB
Tagline: Your AI presence, when you're away.
User: {username}
Personality: {profile.get("personality", "helpful")}
Language: {profile.get("language", "auto")}
Saved memories: {json.dumps(memories, ensure_ascii=False)}
Be helpful, concise and transparent.
""".strip()

    contents = []
    contents.append({
        "role": "user",
        "parts": [{"text": system}]
    })

    for item in messages[-20:]:
        role = "user" if item.get("role") == "user" else "model"
        contents.append({
            "role": role,
            "parts": [{"text": str(item.get("content", ""))}]
        })

    payload = {
        "contents": contents
    }

    model = os.environ.get(
        "GEMINI_MODEL",
        "gemini-3.7-flash"
    )

    url = (
        "https://generativelanguage.googleapis.com/"
        "v1beta/models/"
        + model
        + ":generateContent"
    )

    request = urllib.request.Request(
        url,
        data=json.dumps(payload).encode(),
        headers={
            "Content-Type": "application/json",
            "x-goog-api-key": api_key
        },
        method="POST"
    )

    with urllib.request.urlopen(request, timeout=60) as response:
        result = json.loads(response.read().decode())

    candidates = result.get("candidates", [])
    if not candidates:
        raise RuntimeError("Gemini returned no response.")

    parts = candidates[0].get("content", {}).get("parts", [])
    text = "".join(
        str(part.get("text", ""))
        for part in parts
    ).strip()

    return text or "I couldn't generate a response."

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
                    chat_messages = previous + [
                        {
                            "role": "user",
                            "content": message
                        }
                    ]

                    if os.environ.get("GEMINI_API_KEY", "").strip():
                        reply = gemini(
                            chat_messages,
                            username
                        )
                    else:
                        reply = ollama(
                            chat_messages,
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
