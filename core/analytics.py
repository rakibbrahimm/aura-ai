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
