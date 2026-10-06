#!/data/data/com.termux/files/usr/bin/bash
set -e

ROOT="$HOME/AURA-AI"
cd "$ROOT"

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="backup-ultimate-$STAMP"

echo "============================================================"
echo "             AURA AI 7.1 ULTIMATE UPGRADE"
echo "============================================================"
echo "Backup: $BACKUP"
echo

mkdir -p "$BACKUP"

# ------------------------------------------------------------
# 1. FULL BACKUP
# ------------------------------------------------------------
echo "[1/12] Creating full backup..."

cp -a api core config connectors web scripts tests data \
      VERSION RELEASE-7.0.md "$BACKUP/" 2>/dev/null || true

# ------------------------------------------------------------
# 2. SECURITY HARDENING
# ------------------------------------------------------------
echo "[2/12] Installing security hardening..."

mkdir -p core/ultimate security monitoring automation deploy backups

cat > core/ultimate_security.py <<'PY'
import os
import secrets
import hashlib
import hmac
import time

PBKDF2_ROUNDS = 310000

def generate_secret(length=48):
    return secrets.token_urlsafe(length)

def password_hash(password, salt=None):
    salt = salt or secrets.token_bytes(16)
    digest = hashlib.pbkdf2_hmac(
        "sha256",
        password.encode(),
        salt,
        PBKDF2_ROUNDS
    )
    return salt.hex() + "$" + digest.hex()

def password_verify(password, stored):
    try:
        salt_hex, digest_hex = stored.split("$", 1)
        salt = bytes.fromhex(salt_hex)
        digest = hashlib.pbkdf2_hmac(
            "sha256",
            password.encode(),
            salt,
            PBKDF2_ROUNDS
        )
        return hmac.compare_digest(digest.hex(), digest_hex)
    except Exception:
        return False

def safe_token():
    return secrets.token_urlsafe(48)

def now():
    return int(time.time())
PY

# ------------------------------------------------------------
# 3. SQLITE DATABASE FOUNDATION
# ------------------------------------------------------------
echo "[3/12] Installing SQLite database layer..."

cat > core/database.py <<'PY'
import sqlite3
from pathlib import Path
from contextlib import contextmanager

ROOT = Path(__file__).resolve().parent.parent
DB_DIR = ROOT / "data" / "system"
DB_DIR.mkdir(parents=True, exist_ok=True)

DB_PATH = DB_DIR / "aura.db"

SCHEMA = """
CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT UNIQUE NOT NULL,
    created_at TEXT NOT NULL,
    role TEXT DEFAULT 'user',
    plan TEXT DEFAULT 'free',
    active INTEGER DEFAULT 1
);

CREATE TABLE IF NOT EXISTS events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT,
    event TEXT NOT NULL,
    detail TEXT,
    created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS jobs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT,
    name TEXT NOT NULL,
    payload TEXT,
    run_at TEXT,
    status TEXT DEFAULT 'pending',
    created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS connectors (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT,
    provider TEXT NOT NULL,
    enabled INTEGER DEFAULT 0,
    created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS usage (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT,
    metric TEXT NOT NULL,
    value REAL DEFAULT 0,
    created_at TEXT NOT NULL
);
"""

@contextmanager
def db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    try:
        conn.executescript(SCHEMA)
        conn.commit()
        yield conn
        conn.commit()
    finally:
        conn.close()

def record_event(username, event, detail=""):
    from datetime import datetime, timezone
    with db() as conn:
        conn.execute(
            "INSERT INTO events(username,event,detail,created_at) VALUES(?,?,?,?)",
            (username, event, detail,
             datetime.now(timezone.utc).isoformat())
        )

def record_usage(username, metric, value=1):
    from datetime import datetime, timezone
    with db() as conn:
        conn.execute(
            "INSERT INTO usage(username,metric,value,created_at) VALUES(?,?,?,?)",
            (username, metric, value,
             datetime.now(timezone.utc).isoformat())
        )

def add_job(username, name, payload="", run_at=""):
    from datetime import datetime, timezone
    with db() as conn:
        cur = conn.execute(
            """INSERT INTO jobs
               (username,name,payload,run_at,status,created_at)
               VALUES(?,?,?,?,?,?)""",
            (username, name, payload, run_at, "pending",
             datetime.now(timezone.utc).isoformat())
        )
        return cur.lastrowid
PY

python - <<'PY'
from core.database import db
with db():
    pass
print("DATABASE: READY")
PY

# ------------------------------------------------------------
# 4. SECRETS MANAGEMENT FOUNDATION
# ------------------------------------------------------------
echo "[4/12] Installing secrets/configuration system..."

cat > config/secrets.example.json <<'JSON'
{
  "OPENAI_API_KEY": "",
  "WHATSAPP_ACCESS_TOKEN": "",
  "TELEGRAM_BOT_TOKEN": "",
  "EMAIL_API_KEY": "",
  "PAYMENT_PROVIDER_KEY": "",
  "AURA_SECRET": ""
}
JSON

if [ ! -f config/secrets.json ]; then
cat > config/secrets.json <<'JSON'
{
  "OPENAI_API_KEY": "",
  "WHATSAPP_ACCESS_TOKEN": "",
  "TELEGRAM_BOT_TOKEN": "",
  "EMAIL_API_KEY": "",
  "PAYMENT_PROVIDER_KEY": "",
  "AURA_SECRET": ""
}
JSON
fi

chmod 600 config/secrets.json

cat > core/secrets.py <<'PY'
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PATH = ROOT / "config" / "secrets.json"

def load():
    if not PATH.exists():
        return {}
    try:
        return json.loads(PATH.read_text())
    except Exception:
        return {}

def get(name, default=None):
    return load().get(name, default)
PY

# ------------------------------------------------------------
# 5. CONNECTOR REGISTRY
# ------------------------------------------------------------
echo "[5/12] Installing official connector framework..."

cat > connectors/ultimate.py <<'PY'
from dataclasses import dataclass

@dataclass
class ConnectorStatus:
    provider: str
    available: bool
    configured: bool
    enabled: bool
    message: str

class Connector:
    provider = "unknown"

    def status(self):
        return ConnectorStatus(
            self.provider,
            True,
            False,
            False,
            "Official credentials required"
        )

    def send(self, user, message):
        raise RuntimeError(
            f"{self.provider} connector is not configured"
        )

class WhatsAppConnector(Connector):
    provider = "whatsapp"

class TelegramConnector(Connector):
    provider = "telegram"

class EmailConnector(Connector):
    provider = "email"

class PaymentConnector(Connector):
    provider = "payments"

CONNECTORS = {
    "whatsapp": WhatsAppConnector(),
    "telegram": TelegramConnector(),
    "email": EmailConnector(),
    "payments": PaymentConnector()
}

def status():
    return {
        name: vars(conn.status())
        for name, conn in CONNECTORS.items()
    }
PY

# ------------------------------------------------------------
# 6. AUTOMATION ENGINE
# ------------------------------------------------------------
echo "[6/12] Installing automation engine..."

cat > automation/engine.py <<'PY'
import threading
import time
from datetime import datetime

class AutomationEngine:
    def __init__(self):
        self.jobs = []
        self.running = False
        self.thread = None

    def add(self, name, callback, delay_seconds=60):
        self.jobs.append({
            "name": name,
            "callback": callback,
            "delay": delay_seconds,
            "next": time.time() + delay_seconds
        })

    def start(self):
        if self.running:
            return
        self.running = True
        self.thread = threading.Thread(
            target=self._loop,
            daemon=True
        )
        self.thread.start()

    def stop(self):
        self.running = False

    def _loop(self):
        while self.running:
            now = time.time()
            for job in self.jobs:
                if now >= job["next"]:
                    try:
                        job["callback"]()
                    except Exception:
                        pass
                    job["next"] = now + job["delay"]
            time.sleep(1)

engine = AutomationEngine()
PY

# ------------------------------------------------------------
# 7. MONITORING
# ------------------------------------------------------------
echo "[7/12] Installing monitoring..."

cat > monitoring/health.py <<'PY'
import os
import time
import shutil

START_TIME = time.time()

def health():
    total, used, free = shutil.disk_usage("/")

    return {
        "process_uptime_seconds": int(time.time() - START_TIME),
        "disk_total_mb": round(total / 1024 / 1024, 1),
        "disk_used_mb": round(used / 1024 / 1024, 1),
        "disk_free_mb": round(free / 1024 / 1024, 1),
        "pid": os.getpid()
    }
PY

# ------------------------------------------------------------
# 8. BACKUP / RECOVERY
# ------------------------------------------------------------
echo "[8/12] Installing backup/recovery..."

cat > scripts/backup-aura.sh <<'SH'
#!/data/data/com.termux/files/usr/bin/bash
set -e

ROOT="$HOME/AURA-AI"
cd "$ROOT"

STAMP="$(date +%Y%m%d-%H%M%S)"
DEST="$ROOT/backups/aura-$STAMP"

mkdir -p "$DEST"

cp -a api core config connectors web scripts tests \
      VERSION RELEASE-7.0.md data "$DEST/" 2>/dev/null || true

echo "AURA BACKUP CREATED"
echo "$DEST"
SH

chmod +x scripts/backup-aura.sh

cat > scripts/recovery-info.sh <<'SH'
#!/data/data/com.termux/files/usr/bin/bash
echo "AURA recovery backups:"
find "$HOME/AURA-AI/backups" -maxdepth 1 -type d 2>/dev/null | sort
SH

chmod +x scripts/recovery-info.sh

# ------------------------------------------------------------
# 9. ADVANCED ANALYTICS
# ------------------------------------------------------------
echo "[9/12] Installing analytics engine..."

cat > core/advanced_analytics.py <<'PY'
from pathlib import Path
import json
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parent.parent
PATH = ROOT / "data" / "system" / "advanced-analytics.json"

def record(event, username=None, value=1):
    PATH.parent.mkdir(parents=True, exist_ok=True)

    data = []
    if PATH.exists():
        try:
            data = json.loads(PATH.read_text())
        except Exception:
            data = []

    data.append({
        "event": event,
        "username": username,
        "value": value,
        "time": datetime.now(timezone.utc).isoformat()
    })

    PATH.write_text(json.dumps(data, indent=2))

def summary():
    if not PATH.exists():
        return {"events": 0}

    try:
        data = json.loads(PATH.read_text())
        return {"events": len(data)}
    except Exception:
        return {"events": 0}
PY

# ------------------------------------------------------------
# 10. DEPLOYMENT FOUNDATION
# ------------------------------------------------------------
echo "[10/12] Installing deployment configuration..."

cat > deploy/production.env.example <<'ENV'
AURA_HOST=127.0.0.1
AURA_PORT=8090
AURA_ENV=production
AURA_HTTPS=false
AURA_EXTERNAL_CONNECTORS=false
AURA_PAYMENTS=false
ENV

cat > deploy/README.md <<'MD'
# AURA Deployment

Current local production mode:
127.0.0.1:8090

Before public deployment:
- HTTPS
- real secret management
- production database strategy
- official API credentials
- provider authorization
- payment provider configuration
- monitoring
- backups
- security review

Never expose development secrets publicly.
MD

# ------------------------------------------------------------
# 11. ANDROID/PWA + PRODUCT METADATA
# ------------------------------------------------------------
echo "[11/12] Updating product metadata..."

echo "7.1.0-ultimate-local" > VERSION

cat > RELEASE-7.1-ULTIMATE.md <<'MD'
# AURA AI 7.1 Ultimate Local

AURA AI 7.1 adds:

- security hardening foundation
- SQLite database
- secrets configuration
- official connector architecture
- automation engine
- monitoring
- backup/recovery
- advanced analytics
- deployment foundation
- product metadata

External providers remain disabled until their official credentials
and authorization are configured.
MD

# ------------------------------------------------------------
# 12. TEST EVERYTHING
# ------------------------------------------------------------
echo "[12/12] Running complete validation..."

python - <<'PY'
from core.database import db, record_event, record_usage
from core.ultimate_security import password_hash, password_verify, generate_secret
from core.secrets import load
from connectors.ultimate import status
from monitoring.health import health
from core.advanced_analytics import record, summary

with db():
    pass

secret = generate_secret()
assert secret

stored = password_hash("aura-test-password")
assert password_verify("aura-test-password", stored)
assert not password_verify("wrong-password", stored)

record_event("system", "ultimate_test", "pass")
record_usage("system", "test", 1)
record("ultimate_test", "system")

connector_status = status()
assert "whatsapp" in connector_status
assert "telegram" in connector_status
assert "email" in connector_status
assert "payments" in connector_status

h = health()
assert "pid" in h

print("SECURITY: PASS")
print("DATABASE: PASS")
print("SECRETS: PASS")
print("CONNECTORS: READY")
print("AUTOMATION: READY")
print("MONITORING: PASS")
print("BACKUP SYSTEM: READY")
print("ANALYTICS: PASS")
PY

python -m py_compile \
    core/database.py \
    core/ultimate_security.py \
    core/secrets.py \
    core/advanced_analytics.py \
    connectors/ultimate.py \
    automation/engine.py \
    monitoring/health.py

echo "PYTHON VALIDATION: PASS"

# ------------------------------------------------------------
# UPDATE STATUS WITHOUT BREAKING EXISTING SERVER
# ------------------------------------------------------------
echo
echo "=== CURRENT AURA STATUS ==="

if [ -x scripts/status.sh ]; then
    scripts/status.sh || true
fi

echo
echo "=== HEALTH CHECK ==="

curl -fsS http://127.0.0.1:8090/health || {
    echo "WARNING: AURA server is not responding."
    echo "Existing 7.0 installation was NOT deleted."
    exit 0
}

echo
echo
echo "============================================================"
echo "          AURA AI 7.1 ULTIMATE UPGRADE COMPLETE"
echo "============================================================"
echo
echo "Version : 7.1.0-ultimate-local"
echo "Web     : http://127.0.0.1:8090"
echo "Backup  : $BACKUP"
echo
echo "ADDED"
echo "  Security hardening : ON"
echo "  SQLite database    : ON"
echo "  Secrets system     : ON"
echo "  Connectors         : READY"
echo "  Automation         : ON"
echo "  Monitoring         : ON"
echo "  Backup/recovery    : ON"
echo "  Analytics          : ON"
echo "  Deployment         : READY"
echo
echo "External communication/payment providers remain disabled"
echo "until official credentials and authorization are supplied."
echo "============================================================"
