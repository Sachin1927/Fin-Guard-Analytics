"""
Fin-Guard Analytics – Main Agent Entry Point
==============================================
Orchestrates the full monitoring loop:
  1. KPIMonitor polls the DB every N seconds
  2. ThresholdBreach triggers Investigator (SQL + GPT-4)
  3. Investigator result is sent via SlackNotifier
  4. State is persisted to disk after every poll

Run: python agent/main.py
"""

from __future__ import annotations

import sys
import time
import signal
from datetime import datetime, timezone

from loguru import logger
from rich.console import Console
from rich.panel import Panel
from rich.table import Table
from rich import box
from apscheduler.schedulers.blocking import BlockingScheduler

from agent.config import settings
from agent.memory import AgentState
from agent.monitor import KPIMonitor, ThresholdBreach
from agent.investigator import Investigator
from agent.notifier import SlackNotifier

# ─── Logging setup ────────────────────────────────────────────────────────────
logger.remove()
logger.add(
    sys.stderr,
    format="<green>{time:YYYY-MM-DD HH:mm:ss}</green> | <level>{level}</level> | {message}",
    level="INFO",
    colorize=True,
)
logger.add(
    "data/processed/agent.log",
    rotation="10 MB",
    retention="14 days",
    level="DEBUG",
    format="{time} | {level} | {message}",
)

console = Console()


# ─── Shared singletons ────────────────────────────────────────────────────────
monitor    = KPIMonitor()
investigator = Investigator()
notifier   = SlackNotifier()
state      = AgentState.load()


# ─── Rich dashboard printer ───────────────────────────────────────────────────

def print_kpi_dashboard(snapshot, breaches: list[ThresholdBreach]) -> None:
    """Print a rich terminal dashboard of current KPI values."""
    table = Table(title="📊 Fin-Guard KPI Snapshot", box=box.ROUNDED, show_lines=True)
    table.add_column("KPI",            style="cyan",   min_width=30)
    table.add_column("Value",          style="white",  justify="right")
    table.add_column("Threshold",      style="yellow", justify="right")
    table.add_column("Status",         justify="center")

    kpis = [
        ("PAR-30 (30d avg %)",            snapshot.par30_30d_avg,             settings.par30_threshold),
        ("Default Rate (%)",              snapshot.current_month_default_rate, settings.default_rate_threshold),
        ("Anomaly Count (Yesterday)",     snapshot.anomaly_count_yesterday,    settings.anomaly_count_threshold),
        ("NPL Ratio (%)",                 snapshot.overall_npl_ratio,          settings.npl_ratio_threshold),
    ]

    breached_names = {b.kpi_name for b in breaches}
    for label, value, threshold in kpis:
        val_str = f"{value:.4f}" if isinstance(value, float) else str(value)
        status  = "🔴 BREACH" if label in breached_names else "🟢 OK"
        table.add_row(label, val_str, str(threshold), status)

    console.print(table)
    console.print(
        Panel(
            f"Active Loans: [bold]{snapshot.active_loan_count:,}[/bold]  |  "
            f"Portfolio: [bold]${snapshot.total_active_portfolio:,.0f}[/bold]  |  "
            f"Total Polls: [bold]{state.total_polls}[/bold]  |  "
            f"Alerts Fired: [bold]{state.total_alerts_fired}[/bold]",
            title="[bold blue]Portfolio Overview[/bold blue]",
            border_style="blue",
        )
    )


# ─── Core Monitoring Cycle ────────────────────────────────────────────────────

def run_monitoring_cycle() -> None:
    """Single monitoring cycle – poll → evaluate → investigate → alert."""
    logger.info("=" * 60)
    logger.info(f"[Agent] Monitoring cycle started at {datetime.now(timezone.utc).isoformat()}")

    # 1. Poll KPIs
    snapshot, breaches = monitor.poll(state)
    if snapshot is None:
        logger.warning("[Agent] Snapshot unavailable – skipping cycle.")
        return

    # 2. Print Rich dashboard to terminal
    print_kpi_dashboard(snapshot, breaches)

    # 3. Process each breach
    for breach in breaches:
        kpi = breach.kpi_name

        # Skip if we already alerted for this KPI and it's still active
        if state.is_alert_active(kpi):
            logger.info(f"[Agent] Alert already active for {kpi} – suppressing duplicate.")
            continue

        logger.warning(f"[Agent] Investigating breach: {kpi} …")

        # 4. AI-driven root-cause investigation
        summary = investigator.investigate(breach)

        # 5. Send Slack alert
        notifier.send_alert(breach, summary)

        # 6. Update state
        state.add_alert(kpi, breach.current_value, breach.threshold)
        state.log_investigation(kpi, summary[:500])
        state.save()

        logger.success(f"[Agent] Alert pipeline complete for: {kpi}")

    # 7. Resolve alerts for KPIs that are now back to normal
    breached_names = {b.kpi_name for b in breaches}
    for alert in state.active_alerts:
        if not alert.get("resolved") and alert["kpi_name"] not in breached_names:
            logger.info(f"[Agent] Resolving alert: {alert['kpi_name']}")
            notifier.send_resolution(
                alert["kpi_name"],
                alert["current_value"],
                alert["threshold"],
            )
            state.resolve_alert(alert["kpi_name"])
            state.save()


# ─── Entry Point ──────────────────────────────────────────────────────────────

def main() -> None:
    console.print(
        Panel.fit(
            "[bold cyan]🛡️  Fin-Guard Analytics – Agentic AI Monitor[/bold cyan]\n"
            f"[white]Poll interval: [bold]{settings.poll_interval_seconds}s[/bold]  |  "
            f"DB: [bold]{settings.db_host}:{settings.db_port}/{settings.db_name}[/bold][/white]",
            border_style="cyan",
        )
    )

    scheduler = BlockingScheduler()
    scheduler.add_job(
        func=run_monitoring_cycle,
        trigger="interval",
        seconds=settings.poll_interval_seconds,
        id="kpi_monitor",
        name="KPI Monitor Cycle",
        replace_existing=True,
        max_instances=1,
    )

    # Run once immediately on start
    run_monitoring_cycle()

    def _shutdown(sig, frame):
        logger.info("[Agent] Shutdown signal received. Stopping scheduler …")
        scheduler.shutdown(wait=False)
        state.save()
        sys.exit(0)

    signal.signal(signal.SIGINT,  _shutdown)
    signal.signal(signal.SIGTERM, _shutdown)

    logger.info(f"[Agent] Scheduler started – running every {settings.poll_interval_seconds}s")
    scheduler.start()


if __name__ == "__main__":
    main()
