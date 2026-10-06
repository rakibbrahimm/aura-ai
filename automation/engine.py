import threading
import time
from datetime import datetime

class AutomationEngine:
    def __init__(self):
        self.jobs = []
        self.running = False
        self.thread = None

    def add(self, name, callback, delay_seconds=60):
        self.jobs.append({
            "name": name,
            "callback": callback,
            "delay": delay_seconds,
            "next": time.time() + delay_seconds
        })

    def start(self):
        if self.running:
            return
        self.running = True
        self.thread = threading.Thread(
            target=self._loop,
            daemon=True
        )
        self.thread.start()

    def stop(self):
        self.running = False

    def _loop(self):
        while self.running:
            now = time.time()
            for job in self.jobs:
                if now >= job["next"]:
                    try:
                        job["callback"]()
                    except Exception:
                        pass
                    job["next"] = now + job["delay"]
            time.sleep(1)

engine = AutomationEngine()
