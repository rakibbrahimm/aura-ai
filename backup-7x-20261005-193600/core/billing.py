import json
import os
import time

def billing_status(root):
    path = os.path.join(root, "data", "system", "billing.json")

    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {
            "provider": None,
            "enabled": False,
            "plans": {
                "free": {
                    "monthly_messages": 100
                },
                "pro": {
                    "monthly_messages": 5000
                }
            },
            "updated": time.time()
        }

def save_billing(root, data):
    directory = os.path.join(root, "data", "system")
    os.makedirs(directory, exist_ok=True)

    path = os.path.join(directory, "billing.json")
    tmp = path + ".tmp"

    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)

    os.replace(tmp, path)
