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
