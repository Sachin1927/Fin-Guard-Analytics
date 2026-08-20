"""
Fin-Guard Analytics – Excel Report Generator
=============================================
Exports KPI data from PostgreSQL to Excel with:
  - Pivot-style summary tables
  - Conditional formatting (traffic-light colors)
  - Charts (line + bar)
  - Data validation per sheet

Run: python scripts/generate_excel_report.py
Output: excel/reports/FinGuard_Report_<date>.xlsx
"""

from __future__ import annotations

import os
import sys
from datetime import date
from pathlib import Path

import pandas as pd
import sqlalchemy as sa
import xlsxwriter

# Add project root to path
sys.path.insert(0, str(Path(__file__).parent.parent))
from agent.config import settings

OUTPUT_DIR = Path(__file__).parent.parent / "excel" / "reports"
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

engine = sa.create_engine(settings.db_url)


# ── Data Fetchers ─────────────────────────────────────────────────────────────

def fetch(query: str) -> pd.DataFrame:
    with engine.connect() as conn:
        return pd.read_sql(sa.text(query), conn)


def get_default_rate_trend() -> pd.DataFrame:
    return fetch("""
        SELECT year, month_num, month_name, total_loans_issued, defaults,
               default_rate_pct, ytd_defaults
        FROM reporting.vw_default_rate
        ORDER BY year, month_num
    """)


def get_par30_trend() -> pd.DataFrame:
    return fetch("""
        SELECT full_date, par30_pct, par30_7d_avg, par30_30d_avg
        FROM reporting.vw_par30
        ORDER BY full_date DESC
        LIMIT 90
    """)


def get_anomaly_summary() -> pd.DataFrame:
    return fetch("""
        SELECT full_date, transaction_type, country, anomaly_count,
               total_txns, anomaly_rate_pct, anomalous_volume
        FROM reporting.vw_anomaly_summary
        ORDER BY full_date DESC, anomaly_count DESC
        LIMIT 500
    """)


def get_npl_breakdown() -> pd.DataFrame:
    return fetch("""
        SELECT year, month_name, risk_tier, product_category,
               total_loans, npl_loans, npl_ratio_pct
        FROM reporting.vw_npl_ratio
        ORDER BY year DESC, npl_ratio_pct DESC
        LIMIT 200
    """)


def get_kpi_snapshot() -> pd.DataFrame:
    return fetch("SELECT * FROM reporting.vw_kpi_snapshot LIMIT 1")


# ── Excel Writer ──────────────────────────────────────────────────────────────

def write_excel_report() -> Path:
    report_date = date.today().strftime("%Y-%m-%d")
    output_path = OUTPUT_DIR / f"FinGuard_Report_{report_date}.xlsx"

    workbook = xlsxwriter.Workbook(str(output_path))

    # ── Formats ───────────────────────────────────────────────────────────────
    hdr_fmt = workbook.add_format({
        "bold": True, "bg_color": "#1A365D", "font_color": "#FFFFFF",
        "border": 1, "align": "center", "valign": "vcenter",
    })
    title_fmt = workbook.add_format({
        "bold": True, "font_size": 16, "font_color": "#1A365D",
    })
    subtitle_fmt = workbook.add_format({
        "italic": True, "font_color": "#4A5568", "font_size": 10,
    })
    num_fmt    = workbook.add_format({"num_format": "#,##0.00", "border": 1})
    pct_fmt    = workbook.add_format({"num_format": "0.0000%",  "border": 1})
    date_fmt   = workbook.add_format({"num_format": "yyyy-mm-dd","border": 1})
    int_fmt    = workbook.add_format({"num_format": "#,##0",    "border": 1})
    ok_fmt     = workbook.add_format({"bg_color": "#C6EFCE", "font_color": "#276221", "border": 1, "num_format": "0.0000"})
    warn_fmt   = workbook.add_format({"bg_color": "#FFEB9C", "font_color": "#9C6500", "border": 1, "num_format": "0.0000"})
    crit_fmt   = workbook.add_format({"bg_color": "#FFC7CE", "font_color": "#9C0006", "border": 1, "num_format": "0.0000"})

    # ── Sheet 1: KPI Summary ──────────────────────────────────────────────────
    ws = workbook.add_worksheet("KPI Summary")
    ws.set_tab_color("#1A365D")
    ws.set_column("A:A", 35)
    ws.set_column("B:D", 20)
    ws.write("A1", "🛡️ Fin-Guard Analytics – KPI Executive Summary", title_fmt)
    ws.write("A2", f"Report Date: {report_date}  |  Data Source: PostgreSQL Warehouse", subtitle_fmt)
    ws.set_row(0, 25)

    kpi_headers = ["KPI", "Current Value", "Threshold", "Status"]
    for col, h in enumerate(kpi_headers):
        ws.write(3, col, h, hdr_fmt)

    try:
        snap = get_kpi_snapshot()
        if not snap.empty:
            row = snap.iloc[0]
            kpi_rows = [
                ("PAR-30 (30d avg %)",        row.get("par30_30d_avg", 0),             settings.par30_threshold),
                ("Default Rate (curr month %)", row.get("current_month_default_rate", 0), settings.default_rate_threshold),
                ("Anomaly Count (yesterday)",   row.get("anomaly_count_yesterday", 0),  settings.anomaly_count_threshold),
                ("NPL Ratio (%)",               row.get("overall_npl_ratio", 0),         settings.npl_ratio_threshold),
                ("Active Loans",                row.get("active_loan_count", 0),          None),
                ("Total Portfolio ($)",         row.get("total_active_portfolio", 0),     None),
            ]
            for r_idx, (label, value, threshold) in enumerate(kpi_rows, start=4):
                ws.write(r_idx, 0, label)
                ws.write(r_idx, 1, float(value) if value is not None else 0)
                ws.write(r_idx, 2, threshold if threshold else "N/A")
                if threshold and value is not None:
                    val = float(value)
                    if val > threshold * 1.5:
                        fmt, status = crit_fmt, "🔴 CRITICAL"
                    elif val > threshold:
                        fmt, status = warn_fmt, "🟡 WARNING"
                    else:
                        fmt, status = ok_fmt, "🟢 OK"
                    ws.write(r_idx, 1, val, fmt)
                    ws.write(r_idx, 3, status)
    except Exception as e:
        ws.write(4, 0, f"Error fetching KPI snapshot: {e}")

    # ── Sheet 2: Default Rate Trend ───────────────────────────────────────────
    ws2 = workbook.add_worksheet("Default Rate Trend")
    ws2.set_tab_color("#E53E3E")
    ws2.set_column("A:G", 18)
    ws2.write("A1", "📉 Monthly Default Rate Trend", title_fmt)
    try:
        df = get_default_rate_trend()
        headers = list(df.columns)
        for col, h in enumerate(headers):
            ws2.write(2, col, h, hdr_fmt)
        for r_idx, row in enumerate(df.itertuples(index=False), start=3):
            ws2.write(r_idx, 0, row.year,              int_fmt)
            ws2.write(r_idx, 1, row.month_num,         int_fmt)
            ws2.write(r_idx, 2, str(row.month_name).strip())
            ws2.write(r_idx, 3, row.total_loans_issued, int_fmt)
            ws2.write(r_idx, 4, row.defaults,           int_fmt)
            ws2.write(r_idx, 5, float(row.default_rate_pct or 0) / 100, pct_fmt)
            ws2.write(r_idx, 6, row.ytd_defaults,       int_fmt)

        # Embed a line chart
        chart = workbook.add_chart({"type": "line"})
        chart.add_series({
            "name": "Default Rate %",
            "categories": ["Default Rate Trend", 3, 2, 3 + len(df) - 1, 2],
            "values":     ["Default Rate Trend", 3, 5, 3 + len(df) - 1, 5],
            "line": {"color": "#E53E3E", "width": 2.5},
            "marker": {"type": "circle", "size": 5},
        })
        chart.set_title({"name": "Monthly Default Rate (%)"})
        chart.set_x_axis({"name": "Month"})
        chart.set_y_axis({"name": "Default Rate (%)", "num_format": "0.00%"})
        chart.set_style(10)
        ws2.insert_chart("I3", chart, {"x_scale": 1.8, "y_scale": 1.4})
    except Exception as e:
        ws2.write(3, 0, f"Error: {e}")

    # ── Sheet 3: PAR-30 Trend ─────────────────────────────────────────────────
    ws3 = workbook.add_worksheet("PAR-30 Trend")
    ws3.set_tab_color("#F0A500")
    ws3.set_column("A:D", 20)
    ws3.write("A1", "⚠️ PAR-30 Portfolio at Risk Trend (Last 90 Days)", title_fmt)
    try:
        df3 = get_par30_trend()
        headers3 = ["Date", "PAR-30 %", "7-Day Avg %", "30-Day Avg %"]
        for col, h in enumerate(headers3):
            ws3.write(2, col, h, hdr_fmt)
        for r_idx, row in enumerate(df3.itertuples(index=False), start=3):
            ws3.write(r_idx, 0, str(row.full_date))
            ws3.write(r_idx, 1, float(row.par30_pct or 0) / 100, pct_fmt)
            ws3.write(r_idx, 2, float(row.par30_7d_avg or 0) / 100, pct_fmt)
            ws3.write(r_idx, 3, float(row.par30_30d_avg or 0) / 100, pct_fmt)
    except Exception as e:
        ws3.write(3, 0, f"Error: {e}")

    # ── Sheet 4: Anomaly Summary ──────────────────────────────────────────────
    ws4 = workbook.add_worksheet("Anomaly Summary")
    ws4.set_tab_color("#805AD5")
    ws4.set_column("A:G", 20)
    ws4.write("A1", "🔍 Transaction Anomaly Summary", title_fmt)
    try:
        df4 = get_anomaly_summary()
        headers4 = list(df4.columns)
        for col, h in enumerate(headers4):
            ws4.write(2, col, h, hdr_fmt)
        for r_idx, row in enumerate(df4.itertuples(index=False), start=3):
            for col_idx, val in enumerate(row[1:], start=0):
                ws4.write(r_idx, col_idx, str(val) if val is not None else "")
    except Exception as e:
        ws4.write(3, 0, f"Error: {e}")

    # ── Sheet 5: NPL Breakdown ────────────────────────────────────────────────
    ws5 = workbook.add_worksheet("NPL Breakdown")
    ws5.set_tab_color("#E53E3E")
    ws5.set_column("A:G", 22)
    ws5.write("A1", "📊 NPL Ratio by Risk Tier & Product", title_fmt)
    try:
        df5 = get_npl_breakdown()
        for col, h in enumerate(list(df5.columns)):
            ws5.write(2, col, h, hdr_fmt)
        for r_idx, row in enumerate(df5.itertuples(index=False), start=3):
            for col_idx, val in enumerate(row[1:], start=0):
                ws5.write(r_idx, col_idx, str(val) if val is not None else "")
    except Exception as e:
        ws5.write(3, 0, f"Error: {e}")

    workbook.close()
    print(f"✅ Excel report written → {output_path}")
    return output_path


if __name__ == "__main__":
    write_excel_report()
