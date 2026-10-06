#!/data/data/com.termux/files/usr/bin/bash
set -e

cd "$HOME/AURA-AI"

echo "========================================"
echo "       AURA AI LOCAL UPGRADE"
echo "========================================"

# --------------------------------------------------
# 1. BACKUP CURRENT AURA
# --------------------------------------------------

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="backup-aura-$STAMP"

mkdir -p "$BACKUP"

cp -a api core web config data scripts logs VERSION "$BACKUP/" 2>/dev/null || true

echo "[1/10] Backup created: $BACKUP"

# --------------------------------------------------
# 2. DIRECTORIES
# --------------------------------------------------

mkdir -p \
    api \
    core \
    web \
    web/icons \
    data/users \
    logs \
    config \
    scripts \
    connectors

# --------------------------------------------------
# 3. LOCAL TOOLS
# --------------------------------------------------

cat > core/local_tools.py <<'PY'
import ast
import operator
from datetime import datetime

_ALLOWED = {
    ast.Add: operator.add,
    ast.Sub: operator.sub,
    ast.Mult: operator.mul,
    ast.Div: operator.truediv,
    ast.Mod: operator.mod,
    ast.Pow: operator.pow,
    ast.USub: operator.neg,
    ast.UAdd: operator.pos,
}


def calculate(expression):
    expression = expression.strip()

    if len(expression) > 100:
        raise ValueError("Expression too long")

    tree = ast.parse(expression, mode="eval")

    def evaluate(node):
        if isinstance(node, ast.Constant):
            if isinstance(node.value, (int, float)):
                return node.value
            raise ValueError("Invalid value")

        if isinstance(node, ast.BinOp):
            operation = _ALLOWED.get(type(node.op))
            if not operation:
                raise ValueError("Operator not allowed")
            return operation(
                evaluate(node.left),
                evaluate(node.right)
            )

        if isinstance(node, ast.UnaryOp):
            operation = _ALLOWED.get(type(node.op))
            if not operation:
                raise ValueError("Operator not allowed")
            return operation(evaluate(node.operand))

        raise ValueError("Only basic arithmetic is supported")

    result = evaluate(tree.body)

    if isinstance(result, float) and result.is_integer():
        return int(result)

    return result


def now():
    return datetime.now().astimezone().isoformat()


def run_tool(name, argument):
    if name == "calculator":
        return str(calculate(argument))

    if name == "time":
        return now()

    raise ValueError("Unknown local tool")
PY

# --------------------------------------------------
# 4. MEMORY ENGINE
# --------------------------------------------------

cat > core/memory.py <<'PY'
import json
from pathlib import Path

BASE = Path(__file__).resolve().parent.parent
USERS = BASE / "data" / "users"


def user_file(username):
    safe = "".join(
        c for c in username
        if c.isalnum() or c in "_-"
    )
    return USERS / f"{safe}.json"


def load(username):
    path = user_file(username)

    if not path.exists():
        return None

    return json.loads(path.read_text())


def save(user):
    user_file(user["username"]).write_text(
        json.dumps(user, indent=2)
    )


def add_message(user, role, content):
    user.setdefault("memory", []).append({
        "role": role,
        "content": content
    })

    # Keep local context bounded.
    user["memory"] = user["memory"][-50:]

    save(user)


def get_recent(user, count=20):
    return user.get("memory", [])[-count:]


def set_preference(user, key, value):
    user.setdefault("settings", {})
    user["settings"][key] = value
    save(user)
PY

# --------------------------------------------------
# 5. PRODUCT CONFIG
# --------------------------------------------------

cat > config/product.json <<'JSON'
{
  "name": "AURA AI",
  "version": "1.0.0-local",
  "creator": "RAKIB",
  "tagline": "Your AI presence, when you're away.",
  "multi_user": true,
  "memory": true,
  "voice": true,
  "pwa": true,
  "local_tools": true,
  "connectors": {
    "telegram": "not_configured",
    "whatsapp": "not_configured",
    "instagram": "not_configured",
    "messenger": "not_configured",
    "email": "not_configured"
  }
}
JSON

echo "AURA 1.0 LOCAL" > VERSION

# --------------------------------------------------
# 6. CONNECTOR FRAMEWORK
# --------------------------------------------------

cat > connectors/README.md <<'MD'
# AURA Connectors

This directory contains official-platform connector modules.

Connectors must:
- use official APIs
- require user authorization
- keep credentials private
- respect platform policies
- never silently impersonate a user

Current status:

Telegram: not configured
WhatsApp: not configured
Instagram: not configured
Messenger: not configured
Email: not configured
MD

cat > connectors/__init__.py <<'PY'
# AURA connector framework
PY

# --------------------------------------------------
# 7. UPGRADED API
# --------------------------------------------------

cat > api/server.py <<'PY'
import hashlib
import hmac
import json
import secrets
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from core.local_tools import run_tool
from core.memory import load, save, add_message, get_recent, set_preference


BASE = Path(__file__).resolve().parent.parent

HOST = "127.0.0.1"
PORT = 8090

OLLAMA_URL = "http://127.0.0.1:11434/api/chat"
MODEL = "qwen2.5:0.5b"

sessions = {}


def password_hash(password, salt=None):
    if salt is None:
        salt = secrets.token_hex(16)

    digest = hashlib.pbkdf2_hmac(
        "sha256",
        password.encode(),
        salt.encode(),
        150000
    ).hex()

    return f"pbkdf2${salt}${digest}"


def password_check(password, stored):
    if stored.startswith("pbkdf2$"):
        _, salt, expected = stored.split("$", 2)

        actual = hashlib.pbkdf2_hmac(
            "sha256",
            password.encode(),
            salt.encode(),
            150000
        ).hex()

        return hmac.compare_digest(actual, expected)

    # Compatibility with the previous AURA 0.5 accounts.
    old = hashlib.sha256(password.encode()).hexdigest()
    return hmac.compare_digest(old, stored)


def user_file(username):
    safe = "".join(
        c for c in username
        if c.isalnum() or c in "_-"
    )
    return BASE / "data" / "users" / f"{safe}.json"


def load_user(username):
    path = user_file(username)

    if not path.exists():
        return None

    return load(username)


def save_user(user):
    save(user)


def ask_ollama(user, message):

    settings = user.get("settings", {})
    model = settings.get("ai_model", MODEL)

    messages = [
        {
            "role": "system",
            "content": (
                "You are AURA AI, an AI assistant created by RAKIB. "
                "Be helpful, natural, concise and respectful. "
                "Never invent your creator or identity. "
                "You are an AI, not a human. "
                "Respect the user's preferences and conversation context."
            )
        }
    ]

    messages.extend(get_recent(user, 20))

    messages.append({
        "role": "user",
        "content": message
    })

    payload = json.dumps({
        "model": model,
        "messages": messages,
        "stream": False
    }).encode()

    request = urllib.request.Request(
        OLLAMA_URL,
        data=payload,
        headers={
            "Content-Type": "application/json"
        },
        method="POST"
    )

    with urllib.request.urlopen(
        request,
        timeout=120
    ) as response:

        result = json.loads(
            response.read().decode()
        )

    return result["message"]["content"]


def authenticated_user(data):
    token = data.get("token", "")
    username = sessions.get(token)

    if not username:
        return None

    return load_user(username)


class AURAHandler(BaseHTTPRequestHandler):

    def send_json(self, status, data):

        body = json.dumps(
            data,
            ensure_ascii=False
        ).encode()

        self.send_response(status)

        self.send_header(
            "Content-Type",
            "application/json; charset=utf-8"
        )

        self.send_header(
            "Content-Length",
            str(len(body))
        )

        self.send_header(
            "Access-Control-Allow-Origin",
            "*"
        )

        self.send_header(
            "Access-Control-Allow-Headers",
            "Content-Type"
        )

        self.send_header(
            "Access-Control-Allow-Methods",
            "GET,POST,OPTIONS"
        )

        self.end_headers()
        self.wfile.write(body)

    def send_file(self, path, content_type):

        if not path.exists():
            self.send_json(404, {
                "error": "File not found"
            })
            return

        body = path.read_bytes()

        self.send_response(200)

        self.send_header(
            "Content-Type",
            content_type
        )

        self.send_header(
            "Content-Length",
            str(len(body))
        )

        self.end_headers()

        self.wfile.write(body)

    def read_json(self):

        try:
            length = int(
                self.headers.get(
                    "Content-Length",
                    0
                )
            )

            if not length:
                return {}

            return json.loads(
                self.rfile.read(length).decode()
            )

        except Exception:
            return {}

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header(
            "Access-Control-Allow-Origin",
            "*"
        )
        self.send_header(
            "Access-Control-Allow-Headers",
            "Content-Type"
        )
        self.send_header(
            "Access-Control-Allow-Methods",
            "GET,POST,OPTIONS"
        )
        self.end_headers()

    def do_GET(self):

        if self.path in ("/", "/index.html"):
            return self.send_file(
                BASE / "web" / "index.html",
                "text/html; charset=utf-8"
            )

        if self.path == "/manifest.json":
            return self.send_file(
                BASE / "web" / "manifest.json",
                "application/manifest+json"
            )

        if self.path == "/sw.js":
            return self.send_file(
                BASE / "web" / "sw.js",
                "application/javascript"
            )

        if self.path == "/health":
            return self.send_json(200, {
                "status": "ok",
                "service": "AURA AI",
                "version": "1.0.0-local",
                "brain": MODEL,
                "multi_user": True,
                "memory": True,
                "voice": True,
                "pwa": True,
                "local_tools": True
            })

        self.send_json(404, {
            "error": "Route not found"
        })

    def do_POST:

        pass
PY

# Fix the intentionally separated method declaration safely.
python - <<'PY'
from pathlib import Path

p = Path("api/server.py")
s = p.read_text()

s = s.replace(
    "    def do_POST:\\n\\n        pass",
    '''    def do_POST(self):

        data = self.read_json()

        if self.path == "/register":

            username = str(
                data.get("username", "")
            ).strip()

            password = str(
                data.get("password", "")
            )

            if len(username) < 3:
                return self.send_json(400, {
                    "error": "Username must be at least 3 characters"
                })

            if len(password) < 6:
                return self.send_json(400, {
                    "error": "Password must be at least 6 characters"
                })

            if load_user(username):
                return self.send_json(409, {
                    "error": "User already exists"
                })

            user = {
                "username": username,
                "password_hash": password_hash(password),
                "user_id": secrets.token_hex(16),
                "memory": [],
                "connections": {},
                "settings": {
                    "ai_model": MODEL,
                    "personality": "helpful",
                    "voice": True
                }
            }

            save_user(user)

            return self.send_json(201, {
                "success": True,
                "message": "AURA account created",
                "user_id": user["user_id"]
            })

        if self.path == "/login":

            username = str(
                data.get("username", "")
            ).strip()

            password = str(
                data.get("password", "")
            )

            user = load_user(username)

            if not user or not password_check(
                password,
                user.get("password_hash", "")
            ):
                return self.send_json(401, {
                    "error": "Invalid username or password"
                })

            # Upgrade old SHA256 accounts after successful login.
            if not user["password_hash"].startswith("pbkdf2$"):
                user["password_hash"] = password_hash(password)
                save_user(user)

            token = secrets.token_urlsafe(48)

            sessions[token] = username

            return self.send_json(200, {
                "success": True,
                "message": "Login successful",
                "token": token,
                "user_id": user["user_id"],
                "username": username
            })

        if self.path == "/logout":

            token = data.get("token", "")

            sessions.pop(token, None)

            return self.send_json(200, {
                "success": True,
                "message": "Logged out"
            })

        if self.path == "/chat":

            user = authenticated_user(data)

            if not user:
                return self.send_json(401, {
                    "error": "Not authenticated"
                })

            message = str(
                data.get("message", "")
            ).strip()

            if not message:
                return self.send_json(400, {
                    "error": "Message is required"
                })

            try:
                reply = ask_ollama(
                    user,
                    message
                )

                add_message(
                    user,
                    "user",
                    message
                )

                add_message(
                    user,
                    "assistant",
                    reply
                )

                return self.send_json(200, {
                    "success": True,
                    "reply": reply,
                    "user": user["username"]
                })

            except Exception as error:

                return self.send_json(500, {
                    "error": str(error)
                })

        if self.path == "/history":

            user = authenticated_user(data)

            if not user:
                return self.send_json(401, {
                    "error": "Not authenticated"
                })

            return self.send_json(200, {
                "success": True,
                "messages": get_recent(user, 50)
            })

        if self.path == "/settings":

            user = authenticated_user(data)

            if not user:
                return self.send_json(401, {
                    "error": "Not authenticated"
                })

            return self.send_json(200, {
                "success": True,
                "settings": user.get(
                    "settings",
                    {}
                )
            })

        if self.path == "/settings/update":

            user = authenticated_user(data)

            if not user:
                return self.send_json(401, {
                    "error": "Not authenticated"
                })

            updates = data.get(
                "settings",
                {}
            )

            allowed = {
                "personality",
                "voice"
            }

            for key, value in updates.items():
                if key in allowed:
                    set_preference(
                        user,
                        key,
                        value
                    )

            return self.send_json(200, {
                "success": True,
                "settings": user.get(
                    "settings",
                    {}
                )
            })

        if self.path == "/tool":

            user = authenticated_user(data)

            if not user:
                return self.send_json(401, {
                    "error": "Not authenticated"
                })

            name = data.get("name", "")
            argument = data.get("argument", "")

            try:
                result = run_tool(
                    name,
                    argument
                )

                return self.send_json(200, {
                    "success": True,
                    "tool": name,
                    "result": result
                })

            except Exception as error:

                return self.send_json(400, {
                    "error": str(error)
                })

        self.send_json(404, {
            "error": "Route not found"
        })

    def log_message(self, format, *args):
        print("[AURA]", format % args)


print("================================")
print("       AURA AI 1.0 LOCAL")
print("================================")
print(f"Server: http://{HOST}:{PORT}")
print(f"Brain: Ollama / {MODEL}")
print("Multi-user: ENABLED")
print("Memory: ENABLED")
print("Voice: ENABLED")
print("PWA: ENABLED")
print("Local tools: ENABLED")
print("")

server = ThreadingHTTPServer(
    (HOST, PORT),
    AURAHandler
)

try:
    server.serve_forever()
except KeyboardInterrupt:
    print("\\nAURA backend stopped.")
    server.server_close()
'''
)

p.write_text(s)
print("API installed.")
PY

# --------------------------------------------------
# 8. PWA
# --------------------------------------------------

cat > web/manifest.json <<'JSON'
{
  "name": "AURA AI",
  "short_name": "AURA",
  "start_url": "/",
  "display": "standalone",
  "background_color": "#05070b",
  "theme_color": "#05070b",
  "description": "Your AI presence, when you're away."
}
JSON

cat > web/sw.js <<'JS'
const CACHE = "aura-v1";

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

self.addEventListener("fetch", event => {
    event.respondWith(
        fetch(event.request).catch(() =>
            caches.match(event.request)
        )
    );
});
JS

# --------------------------------------------------
# 9. NEW DASHBOARD
# --------------------------------------------------

cat > web/index.html <<'HTML'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport"
      content="width=device-width,initial-scale=1">
<meta name="theme-color" content="#05070b">

<link rel="manifest" href="/manifest.json">

<title>AURA AI</title>

<style>
*{
    box-sizing:border-box;
}

body{
    margin:0;
    background:#05070b;
    color:#f4f7fb;
    font-family:system-ui,Arial,sans-serif;
}

header{
    padding:22px;
    text-align:center;
}

.logo{
    font-size:32px;
    letter-spacing:8px;
    font-weight:700;
}

.sub{
    opacity:.6;
    font-size:13px;
}

main{
    width:min(900px,94%);
    margin:auto;
}

.card{
    background:#0d1118;
    border:1px solid #252c37;
    border-radius:18px;
    padding:20px;
    margin-bottom:18px;
}

input,button,select{
    width:100%;
    padding:13px;
    margin-top:9px;
    border-radius:10px;
    border:1px solid #303846;
    background:#070a0f;
    color:#fff;
}

button{
    cursor:pointer;
}

button:hover{
    background:#17202d;
}

#chat{
    height:52vh;
    overflow:auto;
    padding:5px;
}

.msg{
    padding:12px 14px;
    margin:9px 0;
    border-radius:12px;
    white-space:pre-wrap;
}

.user{
    background:#17202d;
}

.aura{
    background:#101b17;
}

.row{
    display:flex;
    gap:8px;
}

.row button{
    width:auto;
    padding-left:18px;
    padding-right:18px;
}

.hidden{
    display:none;
}

#status{
    opacity:.7;
    min-height:20px;
}

.voice{
    font-size:22px;
}

footer{
    text-align:center;
    opacity:.45;
    padding:20px;
    font-size:12px;
}
</style>
</head>

<body>

<header>
    <div class="logo">AURA</div>
    <div class="sub">
        Your AI presence, when you're away.
    </div>
</header>

<main>

<section id="auth" class="card">

    <h2>AURA Account</h2>

    <input id="username"
           placeholder="Username"
           autocomplete="username">

    <input id="password"
           type="password"
           placeholder="Password"
           autocomplete="current-password">

    <div class="row">
        <button onclick="register()">Create account</button>
        <button onclick="login()">Login</button>
    </div>

    <p id="status"></p>

</section>


<section id="app" class="hidden">

<div class="card">

    <div class="row">
        <h2 style="flex:1">AURA</h2>
        <button onclick="logout()">Logout</button>
    </div>

    <div id="chat"></div>

    <div class="row">
        <input id="message"
               placeholder="Talk to AURA..."
               onkeydown="
                 if(event.key==='Enter') send()
               ">

        <button onclick="send()">Send</button>
    </div>

    <div class="row">
        <button class="voice"
                onclick="listen()">🎙️</button>

        <button class="voice"
                onclick="stopSpeaking()">🔇</button>
    </div>

</div>


<div class="card">

    <h3>Local Tools</h3>

    <input id="calc"
           placeholder="Example: 25 * 4 + 10">

    <button onclick="calculate()">
        Calculate
    </button>

    <p id="toolResult"></p>

</div>


<div class="card">

    <h3>Settings</h3>

    <select id="personality">
        <option value="helpful">Helpful</option>
        <option value="concise">Concise</option>
        <option value="friendly">Friendly</option>
        <option value="professional">Professional</option>
    </select>

    <button onclick="saveSettings()">
        Save settings
    </button>

</div>

</section>

</main>

<footer>
AURA AI · Local Edition · Created by RAKIB
</footer>


<script>

const API = location.origin;

let token =
    localStorage.getItem("aura_token") || "";

function setStatus(text){
    document.getElementById(
        "status"
    ).textContent = text;
}

function showApp(){
    document.getElementById(
        "auth"
    ).classList.add("hidden");

    document.getElementById(
        "app"
    ).classList.remove("hidden");

    loadHistory();
    loadSettings();
}

async function api(path, body){

    const response = await fetch(
        API + path,
        {
            method:"POST",
            headers:{
                "Content-Type":
                    "application/json"
            },
            body:JSON.stringify(body)
        }
    );

    return response.json();
}


async function register(){

    const username =
        document.getElementById(
            "username"
        ).value.trim();

    const password =
        document.getElementById(
            "password"
        ).value;

    const data = await api(
        "/register",
        {
            username,
            password
        }
    );

    setStatus(
        data.message ||
        data.error ||
        "Done"
    );
}


async function login(){

    const username =
        document.getElementById(
            "username"
        ).value.trim();

    const password =
        document.getElementById(
            "password"
        ).value;

    const data = await api(
        "/login",
        {
            username,
            password
        }
    );

    if(data.token){

        token = data.token;

        localStorage.setItem(
            "aura_token",
            token
        );

        showApp();

    }else{

        setStatus(
            data.error ||
            "Login failed"
        );
    }
}


async function send(){

    const input =
        document.getElementById(
            "message"
        );

    const message =
        input.value.trim();

    if(!message) return;

    addMessage(
        "You",
        message,
        "user"
    );

    input.value = "";

    const data = await api(
        "/chat",
        {
            token,
            message
        }
    );

    if(data.reply){

        addMessage(
            "AURA",
            data.reply,
            "aura"
        );

        speak(data.reply);

    }else{

        addMessage(
            "AURA",
            "Error: " +
            (data.error || "Unknown error"),
            "aura"
        );
    }
}


async function loadHistory(){

    const data = await api(
        "/history",
        {token}
    );

    if(!data.messages) return;

    document.getElementById(
        "chat"
    ).innerHTML = "";

    for(const message of data.messages){

        addMessage(
            message.role === "user"
                ? "You"
                : "AURA",
            message.content,
            message.role === "user"
                ? "user"
                : "aura"
        );
    }
}


function addMessage(
    name,
    text,
    type
){

    const chat =
        document.getElementById(
            "chat"
        );

    const div =
        document.createElement(
            "div"
        );

    div.className =
        "msg " + type;

    div.textContent =
        name + ": " + text;

    chat.appendChild(div);

    chat.scrollTop =
        chat.scrollHeight;
}


function speak(text){

    if(
        !("speechSynthesis" in window)
    ) return;

    stopSpeaking();

    const utterance =
        new SpeechSynthesisUtterance(
            text
        );

    utterance.rate = 1;

    speechSynthesis.speak(
        utterance
    );
}


function stopSpeaking(){

    if(
        "speechSynthesis" in window
    ){
        speechSynthesis.cancel();
    }
}


function listen(){

    const Recognition =
        window.SpeechRecognition ||
        window.webkitSpeechRecognition;

    if(!Recognition){

        alert(
            "Voice input is not supported by this browser."
        );

        return;
    }

    const recognition =
        new Recognition();

    recognition.lang =
        navigator.language || "en-US";

    recognition.interimResults =
        false;

    recognition.onresult =
        event => {

            const text =
                event.results[0][0].transcript;

            document.getElementById(
                "message"
            ).value = text;

            send();
        };

    recognition.start();
}


async function calculate(){

    const expression =
        document.getElementById(
            "calc"
        ).value.trim();

    if(!expression) return;

    const data = await api(
        "/tool",
        {
            token,
            name:"calculator",
            argument:expression
        }
    );

    document.getElementById(
        "toolResult"
    ).textContent =
        data.result ||
        data.error ||
        "";
}


async function loadSettings(){

    const data = await api(
        "/settings",
        {token}
    );

    if(
        data.settings &&
        data.settings.personality
    ){

        document.getElementById(
            "personality"
        ).value =
            data.settings.personality;
    }
}


async function saveSettings(){

    const personality =
        document.getElementById(
            "personality"
        ).value;

    const data = await api(
        "/settings/update",
        {
            token,
            settings:{
                personality
            }
        }
    );

    alert(
        data.success
            ? "Settings saved."
            : data.error
    );
}


async function logout(){

    await api(
        "/logout",
        {token}
    );

    localStorage.removeItem(
        "aura_token"
    );

    token = "";

    location.reload();
}


if("serviceWorker" in navigator){

    navigator.serviceWorker.register(
        "/sw.js"
    ).catch(() => {});
}


if(token){
    showApp();
}

</script>

</body>
</html>
HTML

# --------------------------------------------------
# 10. STARTUP / VALIDATION
# --------------------------------------------------

cat > scripts/start-aura.sh <<'SH'
#!/data/data/com.termux/files/usr/bin/sh

cd "$HOME/AURA-AI" || exit 1

mkdir -p logs

if curl -s --max-time 1 \
    http://127.0.0.1:8090/health \
    >/dev/null 2>&1
then
    echo "AURA already running."
    exit 0
fi

nohup python api/server.py \
    >> logs/backend.log 2>&1 &

echo $! > logs/backend.pid

sleep 3

if curl -s --max-time 3 \
    http://127.0.0.1:8090/health
then
    echo
    echo "AURA started successfully."
else
    echo
    echo "AURA failed to start."
    tail -30 logs/backend.log
    exit 1
fi
SH

chmod +x scripts/start-aura.sh

cat > scripts/status.sh <<'SH'
#!/data/data/com.termux/files/usr/bin/sh

echo "========== AURA STATUS =========="

curl -s \
    --max-time 3 \
    http://127.0.0.1:8090/health || true

echo
echo "Version: $(cat "$HOME/AURA-AI/VERSION")"
echo "================================="
SH

chmod +x scripts/status.sh

cat > scripts/stop-aura.sh <<'SH'
#!/data/data/com.termux/files/usr/bin/sh

PID_FILE="$HOME/AURA-AI/logs/backend.pid"

if [ -f "$PID_FILE" ]; then
    PID="$(cat "$PID_FILE")"
    kill "$PID" 2>/dev/null || true
    rm -f "$PID_FILE"
fi

echo "AURA stopped."
SH

chmod +x scripts/stop-aura.sh

# --------------------------------------------------
# VALIDATE EVERYTHING
# --------------------------------------------------

echo
echo "[10/10] Validating..."

python -m py_compile \
    api/server.py \
    core/local_tools.py \
    core/memory.py

echo "Python syntax: OK"

# Restart current backend safely.
if [ -f logs/backend.pid ]; then
    OLD_PID="$(cat logs/backend.pid)"
    kill "$OLD_PID" 2>/dev/null || true
    rm -f logs/backend.pid
fi

sleep 2

./scripts/start-aura.sh

echo
echo "========================================"
echo "       AURA AI 1.0 LOCAL READY"
echo "========================================"

./scripts/status.sh

echo
echo "Dashboard:"
echo "http://127.0.0.1:8090"

echo
echo "Backup:"
echo "$BACKUP"

echo
echo "Commands:"
echo "./scripts/start-aura.sh"
echo "./scripts/stop-aura.sh"
echo "./scripts/status.sh"

echo
echo "========================================"
echo " Upgrades installed:"
echo " - Multi-user accounts"
echo " - Stronger password hashing"
echo " - Persistent memory"
echo " - Chat history"
echo " - User settings"
echo " - Voice input"
echo " - Voice output"
echo " - Local calculator"
echo " - PWA support"
echo " - Connector framework"
echo " - Background backend"
echo " - Health monitoring"
echo "========================================"
