"""
Fin-Guard Analytics – KPI Monitor
===================================
Polls the reporting.vw_kpi_snapshot view and checks each KPI
against configured thresholds. Returns a list of breached KPIs.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Optional

import sqlalchemy as sa
from loguru import logger

from agent.config import settings
from agent.memory import AgentState, KPISnapshot


@dataclass
class ThresholdBreach:
    kpi_name:      str
    current_value: float
    threshold:     float
    direction:     str   # "above" | "below"
    severity:      str   # "WARNING" | "CRITICAL"

    @property
    def message(self) -> str:
        return (
            f"🚨 [{self.severity}] *{self.kpi_name}* is {self.direction} threshold: "
            f"`{self.current_value:.4f}` (threshold: `{self.threshold}`)"
        )


class KPIMonitor:
    """Connects to PostgreSQL and evaluates KPI thresholds."""

    def __init__(self) -> None:
        self._engine = sa.create_engine(settings.db_url, pool_pre_ping=True)

    # ── Database queries ──────────────────────────────────────────────────────

    def fetch_kpi_snapshot(self) -> Optional[KPISnapshot]:
        """Read the latest values from reporting.vw_kpi_snapshot."""
        query = "SELECT * FROM reporting.vw_kpi_snapshot LIMIT 1;"
        try:
            with self._engine.connect() as conn:
                result = conn.execute(sa.text(query)).mappings().one_or_none()
                if result is None:
                    logger.warning("vw_kpi_snapshot returned no rows.")
                    return None
                return KPISnapshot(
                    snapshot_ts=str(result.get("snapshot_ts", "")),
                    par30_30d_avg=float(result["par30_30d_avg"] or 0),
                    current_month_default_rate=float(result["current_month_default_rate"] or 0),
                    anomaly_count_yesterday=int(result["anomaly_count_yesterday"] or 0),
                    active_loan_count=int(result["active_loan_count"] or 0),
                    overall_npl_ratio=float(result["overall_npl_ratio"] or 0),
                    total_active_portfolio=float(result["total_active_portfolio"] or 0),
                )
        except Exception as exc:
            logger.error(f"Failed to fetch KPI snapshot: {exc}")
            return None

    # ── Threshold evaluation ──────────────────────────────────────────────────

    def evaluate_thresholds(self, snapshot: KPISnapshot) -> list[ThresholdBreach]:
        """Compare snapshot values to configured thresholds."""
        breaches: list[ThresholdBreach] = []

        checks = [
            (
                "PAR-30 Rate (%)",
                snapshot.par30_30d_avg,
                settings.par30_threshold,
                "above",
            ),
            (
                "Default Rate (%)",
                snapshot.current_month_default_rate,
                settings.default_rate_threshold,
                "above",
            ),
            (
                "Anomaly Count (Yesterday)",
                snapshot.anomaly_count_yesterday,
                settings.anomaly_count_threshold,
                "above",
            ),
            (
                "NPL Ratio (%)",
                snapshot.overall_npl_ratio,
                settings.npl_ratio_threshold,
                "above",
            ),
        ]

        for kpi_name, value, threshold, direction in checks:
            if value is None:
                continue
            breached = (direction == "above" and value > threshold) or (
                direction == "below" and value < threshold
            )
            if breached:
                severity = "CRITICAL" if value > threshold * 1.5 else "WARNING"
                breaches.append(
                    ThresholdBreach(kpi_name, value, threshold, direction, severity)
                )
                logger.warning(
                    f"[BREACH] {kpi_name}: {value:.4f} {direction} {threshold} [{severity}]"
                )
            else:
                logger.info(f"[OK] {kpi_name}: {value:.4f} (threshold: {threshold})")

        return breaches

    # ── Main polling method ───────────────────────────────────────────────────

    def poll(self, state: AgentState) -> tuple[Optional[KPISnapshot], list[ThresholdBreach]]:
        """
        Full polling cycle:
          1. Fetch snapshot from DB
          2. Evaluate thresholds
          3. Update agent state
          4. Return snapshot + breaches
        """
        logger.info(f"[Monitor] Starting KPI poll #{state.total_polls + 1} …")
        snapshot = self.fetch_kpi_snapshot()

        if snapshot is None:
            return None, []

        breaches = self.evaluate_thresholds(snapshot)

        state.last_poll_ts  = datetime.now(timezone.utc).isoformat()
        state.last_snapshot = snapshot.__dict__
        state.total_polls  += 1
        state.save()

        return snapshot, breaches
