import json
import urllib.request
from pathlib import Path

BASE = Path(__file__).resolve().parent.parent
CONFIG_FILE = BASE / "config" / "aura.json"


def load_config():
    return json.loads(CONFIG_FILE.read_text())


def ask_ai(message, conversation):
    config = load_config()["ai"]

    payload = {
        "model": config["model"],
        "messages": [
            {
                "role": "system",
                "content": (
                    "You are AURA AI, created by RAKIB. You are a personal communication "
                    "assistant. Be natural, concise, and respectful."
                )
            },
            *conversation,
            {
                "role": "user",
                "content": message
            }
        ],
        "stream": False
    }

    data = json.dumps(payload).encode()

    request = urllib.request.Request(
        config["url"],
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST"
    )

    with urllib.request.urlopen(request, timeout=120) as response:
        result = json.loads(response.read().decode())

    return result["message"]["content"]


def main():
    print("AURA AI core online.")
    print("Local brain: Ollama / Qwen 2.5 0.5B")
    print("Type 'exit' to stop.")

    conversation = []

    while True:
        try:
            message = input("\nYou: ").strip()
        except (KeyboardInterrupt, EOFError):
            print("\nAURA offline.")
            break

        if message.lower() == "exit":
            print("AURA offline.")
            break

        if not message:
            continue

        try:
            reply = ask_ai(message, conversation)

            conversation.append({
                "role": "user",
                "content": message
            })
            conversation.append({
                "role": "assistant",
                "content": reply
            })

            print(f"AURA: {reply}")

        except Exception as error:
            print(f"AURA ERROR: {error}")


if __name__ == "__main__":
    main()
