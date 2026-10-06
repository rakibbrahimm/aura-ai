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
