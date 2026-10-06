import os
import time
import shutil

START_TIME = time.time()

def health():
    total, used, free = shutil.disk_usage("/")

    return {
        "process_uptime_seconds": int(time.time() - START_TIME),
        "disk_total_mb": round(total / 1024 / 1024, 1),
        "disk_used_mb": round(used / 1024 / 1024, 1),
        "disk_free_mb": round(free / 1024 / 1024, 1),
        "pid": os.getpid()
    }
