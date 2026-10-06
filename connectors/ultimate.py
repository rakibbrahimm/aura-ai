from dataclasses import dataclass

@dataclass
class ConnectorStatus:
    provider: str
    available: bool
    configured: bool
    enabled: bool
    message: str

class Connector:
    provider = "unknown"

    def status(self):
        return ConnectorStatus(
            self.provider,
            True,
            False,
            False,
            "Official credentials required"
        )

    def send(self, user, message):
        raise RuntimeError(
            f"{self.provider} connector is not configured"
        )

class WhatsAppConnector(Connector):
    provider = "whatsapp"

class TelegramConnector(Connector):
    provider = "telegram"

class EmailConnector(Connector):
    provider = "email"

class PaymentConnector(Connector):
    provider = "payments"

CONNECTORS = {
    "whatsapp": WhatsAppConnector(),
    "telegram": TelegramConnector(),
    "email": EmailConnector(),
    "payments": PaymentConnector()
}

def status():
    return {
        name: vars(conn.status())
        for name, conn in CONNECTORS.items()
    }
