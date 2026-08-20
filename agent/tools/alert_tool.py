"""
Fin-Guard Analytics – LangChain Tool: Alert Dispatcher Tool
=============================================================
Allows the LangChain agent to autonomously send Slack alerts.
"""

from __future__ import annotations

from langchain_core.tools import tool
from loguru import logger
import httpx

from agent.config import settings


@tool
def send_slack_alert(message: str, severity: str = "WARNING") -> str:
    """
    Send a Slack alert message to the Fin-Guard monitoring channel.
    Use this tool when you have identified a critical KPI breach and
    need to notify the team.

    Args:
        message:  The alert message body (plain text or markdown).
        severity: One of "INFO", "WARNING", or "CRITICAL".
    """
    if not settings.slack_webhook_url:
        return "⚠️ Slack webhook not configured. Alert not sent."

    color_map = {
        "INFO":     "#3182CE",
        "WARNING":  "#F0A500",
        "CRITICAL": "#E53E3E",
    }
    color  = color_map.get(severity.upper(), "#F0A500")
    emoji  = {"INFO": "ℹ️", "WARNING": "⚠️", "CRITICAL": "🚨"}.get(severity.upper(), "⚠️")

    payload = {
        "channel": settings.slack_channel,
        "attachments": [
            {
                "color": color,
                "blocks": [
                    {
                        "type": "header",
                        "text": {
                            "type": "plain_text",
                            "text": f"{emoji} Fin-Guard AI Agent Alert [{severity.upper()}]",
                        },
                    },
                    {
                        "type": "section",
                        "text": {"type": "mrkdwn", "text": message[:2900]},
                    },
                ],
            }
        ],
    }

    try:
        resp = httpx.post(settings.slack_webhook_url, json=payload, timeout=10)
        resp.raise_for_status()
        logger.success("[Alert Tool] Slack message sent successfully.")
        return "✅ Alert sent to Slack successfully."
    except Exception as exc:
        logger.error(f"[Alert Tool] Failed: {exc}")
        return f"❌ Failed to send Slack alert: {exc}"
