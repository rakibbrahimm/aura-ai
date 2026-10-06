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
