"""
Fin-Guard Analytics – Agent Memory / State Store
=================================================
In-memory + file-backed state for the monitoring agent.
Tracks:
  - Last seen KPI values
  - Active alerts (deduplicate repeated alerts)
  - Investigation history
"""

from __future__ import annotations

import json
import os
from dataclasses import dataclass, field, asdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

STATE_FILE = Path(__file__).parent.parent / "data" / "processed" / "agent_state.json"


@dataclass
class KPISnapshot:
    snapshot_ts:               str
    par30_30d_avg:             Optional[float] = None
    current_month_default_rate: Optional[float] = None
    anomaly_count_yesterday:   Optional[int]   = None
    active_loan_count:         Optional[int]   = None
    overall_npl_ratio:         Optional[float] = None
    total_active_portfolio:    Optional[float] = None


@dataclass
class AlertRecord:
    kpi_name:      str
    current_value: float
    threshold:     float
    triggered_at:  str
    resolved:      bool = False
    investigation: str  = ""


@dataclass
class AgentState:
    last_poll_ts:        str              = ""
    last_snapshot:       Optional[dict]   = None
    active_alerts:       list[dict]       = field(default_factory=list)
    investigation_log:   list[dict]       = field(default_factory=list)
    total_polls:         int              = 0
    total_alerts_fired:  int              = 0

    # ── Persistence ───────────────────────────────────────────────────────────
    def save(self) -> None:
        STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
        with open(STATE_FILE, "w") as f:
            json.dump(asdict(self), f, indent=2, default=str)

    @classmethod
    def load(cls) -> "AgentState":
        if STATE_FILE.exists():
            with open(STATE_FILE) as f:
                data = json.load(f)
            return cls(**{k: v for k, v in data.items() if k in cls.__dataclass_fields__})
        return cls()

    # ── Alert helpers ─────────────────────────────────────────────────────────
    def is_alert_active(self, kpi_name: str) -> bool:
        """Return True if an unresolved alert for this KPI already exists."""
        return any(
            a["kpi_name"] == kpi_name and not a.get("resolved", False)
            for a in self.active_alerts
        )

    def add_alert(self, kpi_name: str, value: float, threshold: float) -> None:
        rec = AlertRecord(
            kpi_name=kpi_name,
            current_value=value,
            threshold=threshold,
            triggered_at=datetime.now(timezone.utc).isoformat(),
        )
        self.active_alerts.append(asdict(rec))
        self.total_alerts_fired += 1

    def resolve_alert(self, kpi_name: str) -> None:
        for a in self.active_alerts:
            if a["kpi_name"] == kpi_name:
                a["resolved"] = True

    def log_investigation(self, kpi_name: str, summary: str) -> None:
        self.investigation_log.append(
            {
                "kpi_name":    kpi_name,
                "summary":     summary,
                "logged_at":   datetime.now(timezone.utc).isoformat(),
            }
        )
        # Keep only last 100 entries to control memory
        if len(self.investigation_log) > 100:
            self.investigation_log = self.investigation_log[-100:]
