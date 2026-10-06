import hashlib
import hmac
import secrets
import time
import threading

_lock = threading.Lock()
_attempts = {}

def random_token(length=32):
    return secrets.token_urlsafe(length)

def hash_value(value):
    return hashlib.sha256(value.encode()).hexdigest()

def secure_compare(a, b):
    return hmac.compare_digest(str(a), str(b))

def rate_allowed(key, limit=60, window=60):
    now = time.time()

    with _lock:
        entries = _attempts.setdefault(key, [])
        entries[:] = [x for x in entries if now - x < window]

        if len(entries) >= limit:
            return False

        entries.append(now)
        return True

def clean_rate_state():
    now = time.time()

    with _lock:
        for key in list(_attempts):
            _attempts[key] = [
                x for x in _attempts[key]
                if now - x < 3600
            ]

            if not _attempts[key]:
                del _attempts[key]
