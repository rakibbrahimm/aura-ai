ROLES = {
    "user": {
        "chat",
        "memory",
        "history",
        "settings"
    },
    "admin": {
        "chat",
        "memory",
        "history",
        "settings",
        "analytics",
        "audit",
        "users",
        "connectors",
        "billing"
    }
}

def allowed(role, permission):
    return permission in ROLES.get(role, set())
