import json
import os
import threading

_LOCK = threading.Lock()

class JSONStore:
    def __init__(self, root):
        self.root = root
        os.makedirs(root, exist_ok=True)

    def path(self, name):
        safe = "".join(
            c for c in name
            if c.isalnum() or c in "-_."
        )
        return os.path.join(self.root, safe + ".json")

    def read(self, name, default=None):
        path = self.path(name)

        with _LOCK:
            try:
                with open(path, "r", encoding="utf-8") as f:
                    return json.load(f)
            except Exception:
                return default

    def write(self, name, value):
        path = self.path(name)
        tmp = path + ".tmp"

        with _LOCK:
            with open(tmp, "w", encoding="utf-8") as f:
                json.dump(
                    value,
                    f,
                    ensure_ascii=False,
                    indent=2
                )

            os.replace(tmp, path)
