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
