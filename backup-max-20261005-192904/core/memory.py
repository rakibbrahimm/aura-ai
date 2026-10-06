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
