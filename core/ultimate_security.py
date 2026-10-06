import os
import secrets
import hashlib
import hmac
import time

PBKDF2_ROUNDS = 310000

def generate_secret(length=48):
    return secrets.token_urlsafe(length)

def password_hash(password, salt=None):
    salt = salt or secrets.token_bytes(16)
    digest = hashlib.pbkdf2_hmac(
        "sha256",
        password.encode(),
        salt,
        PBKDF2_ROUNDS
    )
    return salt.hex() + "$" + digest.hex()

def password_verify(password, stored):
    try:
        salt_hex, digest_hex = stored.split("$", 1)
        salt = bytes.fromhex(salt_hex)
        digest = hashlib.pbkdf2_hmac(
            "sha256",
            password.encode(),
            salt,
            PBKDF2_ROUNDS
        )
        return hmac.compare_digest(digest.hex(), digest_hex)
    except Exception:
        return False

def safe_token():
    return secrets.token_urlsafe(48)

def now():
    return int(time.time())
