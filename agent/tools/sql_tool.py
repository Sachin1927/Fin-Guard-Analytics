"""
Fin-Guard Analytics – LangChain Tool: SQL Query Tool
=====================================================
A LangChain Tool that lets the agent autonomously run read-only
SQL queries against the warehouse and reporting schemas.
"""

from __future__ import annotations

import pandas as pd
import sqlalchemy as sa
from langchain_core.tools import tool
from loguru import logger

from agent.config import settings

_engine = sa.create_engine(settings.db_url, pool_pre_ping=True)

# Safe read-only query prefix whitelist
_ALLOWED_PREFIXES = ("SELECT", "WITH", "EXPLAIN")


@tool
def run_sql_query(query: str) -> str:
    """
    Execute a read-only SQL SELECT query against the Fin-Guard PostgreSQL database.
    The query must start with SELECT, WITH, or EXPLAIN.
    Returns results as a markdown table (max 25 rows).

    Args:
        query: A valid PostgreSQL SELECT statement targeting warehouse.* or reporting.* schemas.
    """
    normalized = query.strip().upper()
    if not any(normalized.startswith(p) for p in _ALLOWED_PREFIXES):
        return "❌ Only SELECT / WITH / EXPLAIN queries are permitted."

    try:
        with _engine.connect() as conn:
            result = conn.execute(sa.text(query))
            df = pd.DataFrame(result.fetchmany(25), columns=result.keys())

        if df.empty:
            return "✅ Query executed successfully but returned 0 rows."

        logger.info(f"[SQL Tool] Returned {len(df)} rows for query: {query[:80]}…")
        return df.to_markdown(index=False)

    except Exception as exc:
        logger.error(f"[SQL Tool] Query failed: {exc}")
        return f"❌ SQL Error: {exc}"
