"""
Fin-Guard Analytics – LangChain Tool: KPI Snapshot Tool
=========================================================
Exposes the KPI snapshot view to the LangChain agent as a callable tool.
"""

from __future__ import annotations

import sqlalchemy as sa
from langchain_core.tools import tool
from loguru import logger

from agent.config import settings

_engine = sa.create_engine(settings.db_url, pool_pre_ping=True)


@tool
def get_kpi_snapshot() -> str:
    """
    Fetch the latest KPI snapshot from reporting.vw_kpi_snapshot.
    Returns a formatted summary of all key performance indicators:
    PAR-30 rate, default rate, anomaly count, NPL ratio, and portfolio size.
    Use this tool first to understand the current state of the portfolio.
    """
    try:
        with _engine.connect() as conn:
            row = conn.execute(
                sa.text("SELECT * FROM reporting.vw_kpi_snapshot LIMIT 1;")
            ).mappings().one_or_none()

        if row is None:
            return "⚠️ No KPI snapshot data available."

        return (
            f"**Fin-Guard KPI Snapshot** (as of {row.get('snapshot_ts', 'N/A')})\n\n"
            f"| KPI | Value |\n|-----|-------|\n"
            f"| PAR-30 (30d avg %) | `{row.get('par30_30d_avg', 'N/A')}` |\n"
            f"| Current Month Default Rate (%) | `{row.get('current_month_default_rate', 'N/A')}` |\n"
            f"| Anomaly Count (Yesterday) | `{row.get('anomaly_count_yesterday', 'N/A')}` |\n"
            f"| Active Loan Count | `{row.get('active_loan_count', 'N/A')}` |\n"
            f"| Overall NPL Ratio (%) | `{row.get('overall_npl_ratio', 'N/A')}` |\n"
            f"| Total Active Portfolio ($) | `{row.get('total_active_portfolio', 'N/A')}` |\n"
        )
    except Exception as exc:
        logger.error(f"[KPI Tool] {exc}")
        return f"❌ Error fetching KPI snapshot: {exc}"
