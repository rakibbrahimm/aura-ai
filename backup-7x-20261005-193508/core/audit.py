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
