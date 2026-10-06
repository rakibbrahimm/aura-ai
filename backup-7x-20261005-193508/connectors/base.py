class Connector:
    name = "base"

    def status(self):
        return {
            "name": self.name,
            "enabled": False,
            "configured": False
        }

    def send(self, payload):
        raise NotImplementedError(
            "Connector must implement send()"
        )

    def receive(self, payload):
        raise NotImplementedError(
            "Connector must implement receive()"
        )
