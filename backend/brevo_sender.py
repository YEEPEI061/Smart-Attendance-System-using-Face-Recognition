import os
import requests
from dotenv import load_dotenv

load_dotenv()

BREVO_API_KEY = os.getenv("BREVO_API_KEY")
SENDER_EMAIL = os.getenv("BREVO_SENDER_EMAIL")
SENDER_NAME = os.getenv("BREVO_SENDER_NAME", "Smart Attendance System")


def send_email(to_email: str, subject: str, body: str) -> None:
    """
    Send a transactional email via the Brevo (Sendinblue) API.
    Requires BREVO_API_KEY and BREVO_SENDER_EMAIL in your .env file.
    No OAuth, no browser login — just an API key.
    """
    if not BREVO_API_KEY:
        raise ValueError("BREVO_API_KEY is not set in your .env file.")
    if not SENDER_EMAIL:
        raise ValueError("BREVO_SENDER_EMAIL is not set in your .env file.")

    url = "https://api.brevo.com/v3/smtp/email"

    headers = {
        "accept": "application/json",
        "api-key": BREVO_API_KEY,
        "content-type": "application/json",
    }

    payload = {
        "sender": {
            "name": SENDER_NAME,
            "email": SENDER_EMAIL,
        },
        "to": [{"email": to_email}],
        "subject": subject,
        "textContent": body,
    }

    response = requests.post(url, headers=headers, json=payload)

    if response.status_code not in (200, 201):
        raise Exception(
            f"Brevo API error {response.status_code}: {response.text}"
        )