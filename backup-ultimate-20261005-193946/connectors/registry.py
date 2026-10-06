from .base import Connector

class ConnectorRegistry:
    def __init__(self):
        self.items = {}

    def register(self, connector):
        if not isinstance(connector, Connector):
            raise TypeError("Invalid connector")
        self.items[connector.name] = connector

    def status(self):
        return {
            name: connector.status()
            for name, connector in self.items.items()
        }
