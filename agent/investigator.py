"""
Fin-Guard Analytics – Root-Cause Investigator
===============================================
When the KPI Monitor detects a breach, the Investigator:
  1. Calls the appropriate stored SQL function in PostgreSQL
  2. Passes the results to GPT-4 with a structured prompt
  3. Returns a plain-English root-cause summary

Uses LangChain's SQL agent for autonomous query generation when
the predefined functions don't cover the breach type.
"""

from __future__ import annotations

import json
from typing import Optional

import pandas as pd
import sqlalchemy as sa
from langchain_openai import ChatOpenAI
from langchain_core.messages import HumanMessage, SystemMessage
from loguru import logger
from tenacity import retry, stop_after_attempt, wait_exponential

from agent.config import settings
from agent.monitor import ThresholdBreach


SYSTEM_PROMPT = """
You are a senior credit risk analyst AI assistant for Fin-Guard Analytics.
You will receive raw data from a financial database showing loan portfolio metrics.
Your job is to:
1. Identify the primary root cause of the KPI breach
2. Highlight the top 3 most impacted segments (region, risk tier, product category)
3. Recommend 2-3 immediate actions
4. Rate the severity: LOW / MEDIUM / HIGH / CRITICAL

Be concise. Use bullet points. Maximum 250 words.
"""


class Investigator:
    """Autonomous root-cause investigation using SQL + GPT-4."""

    def __init__(self) -> None:
        self._engine = sa.create_engine(settings.db_url, pool_pre_ping=True)
        self._llm = ChatOpenAI(
            model=settings.openai_model,
            api_key=settings.openai_api_key,
            temperature=0,
            max_tokens=600,
        )

    # ── SQL Helpers ───────────────────────────────────────────────────────────

    def _run_sql(self, query: str, params: dict | None = None) -> pd.DataFrame:
        with self._engine.connect() as conn:
            result = conn.execute(sa.text(query), params or {})
            return pd.DataFrame(result.fetchall(), columns=result.keys())

    # ── Investigation Functions per KPI ───────────────────────────────────────

    def _investigate_default_rate(self) -> str:
        logger.info("[Investigator] Running default rate investigation …")
        df = self._run_sql("SELECT * FROM reporting.fn_investigate_default_spike()")
        if df.empty:
            return "No default data found for the investigation window."
        top = df.head(10).to_markdown(index=False)
        return f"**Top defaulting segments (last 30 days):**\n\n{top}"

    def _investigate_par30(self) -> str:
        logger.info("[Investigator] Running PAR-30 investigation …")
        df = self._run_sql("SELECT * FROM reporting.fn_investigate_par30_spike()")
        if df.empty:
            return "No PAR-30 data found."
        top = df.head(10).to_markdown(index=False)
        return f"**Top loans in PAR-30 bucket:**\n\n{top}"

    def _investigate_anomalies(self) -> str:
        logger.info("[Investigator] Running anomaly investigation …")
        df = self._run_sql("SELECT * FROM reporting.fn_investigate_anomaly_spike()")
        if df.empty:
            return "No anomalies found for yesterday."
        top = df.head(10).to_markdown(index=False)
        return f"**Top flagged transactions:**\n\n{top}"

    def _investigate_npl(self) -> str:
        logger.info("[Investigator] Running NPL ratio investigation …")
        df = self._run_sql(
            """
            SELECT risk_tier, product_category, SUM(npl_loans) AS npl_total,
                   ROUND(AVG(npl_ratio_pct),4) AS avg_npl_pct
            FROM reporting.vw_npl_ratio
            WHERE year = EXTRACT(YEAR FROM NOW())
            GROUP BY risk_tier, product_category
            ORDER BY avg_npl_pct DESC
            LIMIT 10;
            """
        )
        if df.empty:
            return "No NPL data found."
        return f"**NPL breakdown by risk tier & product:**\n\n{df.to_markdown(index=False)}"

    # ── LLM Summarization ────────────────────────────────────────────────────

    @retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=1, min=2, max=10))
    def _ask_llm(self, breach: ThresholdBreach, raw_data: str) -> str:
        user_prompt = f"""
KPI BREACH DETECTED:
  - KPI: {breach.kpi_name}
  - Current Value: {breach.current_value:.4f}
  - Threshold: {breach.threshold}
  - Severity: {breach.severity}

RAW DATABASE FINDINGS:
{raw_data}

Please provide root-cause analysis and recommended actions.
"""
        messages = [
            SystemMessage(content=SYSTEM_PROMPT),
            HumanMessage(content=user_prompt),
        ]
        response = self._llm.invoke(messages)
        return response.content.strip()

    # ── Public Interface ──────────────────────────────────────────────────────

    def investigate(self, breach: ThresholdBreach) -> str:
        """
        Run root-cause investigation for a given breach.
        Returns an LLM-generated summary paragraph.
        """
        kpi = breach.kpi_name.lower()

        if "default" in kpi:
            raw_data = self._investigate_default_rate()
        elif "par" in kpi:
            raw_data = self._investigate_par30()
        elif "anomal" in kpi:
            raw_data = self._investigate_anomalies()
        elif "npl" in kpi:
            raw_data = self._investigate_npl()
        else:
            raw_data = "⚠️ No specific investigation query available for this KPI."

        if not settings.openai_api_key:
            logger.warning("[Investigator] No OpenAI API key – returning raw data only.")
            return raw_data

        try:
            summary = self._ask_llm(breach, raw_data)
            logger.success(f"[Investigator] LLM summary generated for {breach.kpi_name}")
            return summary
        except Exception as exc:
            logger.error(f"[Investigator] LLM call failed: {exc}")
            return raw_data   # fall back to raw SQL data
