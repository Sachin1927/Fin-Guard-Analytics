# Fin-Guard Analytics – Architecture & Data Flow

## System Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         DATA SOURCES                                │
│   Kaggle CSV / BigQuery Fintech Dataset                             │
│   (customers · loans · transactions · loan products)                │
└──────────────────────────┬──────────────────────────────────────────┘
                           │ Raw CSV files
                           ▼
┌──────────────────────────────────────────────────────────────────────┐
│                      STAGING LAYER (PostgreSQL)                      │
│   staging.raw_customers                                              │
│   staging.raw_loans                                                  │
│   staging.raw_transactions                                           │
│   staging.etl_run_log                                                │
└──────────────────────────┬───────────────────────────────────────────┘
                           │ ETL (SQL CTEs + Window Functions)
                           ▼
┌──────────────────────────────────────────────────────────────────────┐
│                      WAREHOUSE LAYER (Star Schema)                   │
│                                                                      │
│   DIMENSIONS                        FACTS                            │
│   ┌───────────────┐                ┌─────────────────┐              │
│   │  dim_date     │◄───────────────│  fact_loan      │              │
│   │  dim_customer │◄───────────────│  fact_transaction│              │
│   │  dim_region   │◄───────────────└─────────────────┘              │
│   │  dim_loan_prod│                                                  │
│   └───────────────┘                                                  │
└──────────────────────────┬───────────────────────────────────────────┘
                           │ KPI Views + Materialized Views
                           ▼
┌──────────────────────────────────────────────────────────────────────┐
│                      REPORTING LAYER                                 │
│   vw_par30                 vw_default_rate                           │
│   vw_txn_volume_by_region  vw_anomaly_summary                        │
│   vw_npl_ratio             vw_kpi_snapshot                           │
│   mv_daily_kpi_cache  (Materialized – refreshed nightly)            │
└───────────┬───────────────────────────────────────┬─────────────────┘
            │                                       │
            ▼                                       ▼
┌───────────────────────┐             ┌─────────────────────────────┐
│   Power BI Dashboard  │             │   Web Dashboard (HTML/JS)   │
│   Direct SQL Connector│             │   Chart.js + KPI Cards      │
│   - PAR-30 Time Series│             │   Anomaly Heatmap           │
│   - Default Rate Maps │             │   AI Agent Log Panel        │
│   - Risk Tier Slicers │             └────────────────┬────────────┘
└───────────────────────┘                              │
                                                       │
                           ┌───────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────────┐
│                     AGENTIC AI MONITOR (Python)                      │
│                                                                      │
│  ┌────────────┐  poll() ┌──────────────┐                            │
│  │  Scheduler │────────▶│  KPI Monitor │                            │
│  │ (APSchedul)│         │  (vw_kpi_    │                            │
│  └────────────┘         │   snapshot)  │                            │
│                         └──────┬───────┘                            │
│                                │ breach detected                    │
│                         ┌──────▼──────────────┐                     │
│                         │    Investigator      │                     │
│                         │  SQL Function        │                     │
│                         │  + GPT-4 LLM         │                     │
│                         └──────┬───────────────┘                     │
│                                │ root-cause summary                  │
│                         ┌──────▼────────┐                            │
│                         │  Slack Alert  │                            │
│                         │  (Block Kit)  │                            │
│                         └───────────────┘                            │
│                                                                      │
│         ┌─────────────────────────────┐                             │
│         │     Agent State (JSON)      │                             │
│         │  last_snapshot / alerts /   │                             │
│         │  investigation_log          │                             │
│         └─────────────────────────────┘                             │
└─────────────────────────────────────────────────────────────────────┘
```

## Database Schema Summary

| Schema | Purpose | Tables |
|--------|---------|--------|
| `staging` | Raw ingestion | raw_customers, raw_loans, raw_transactions, etl_run_log |
| `warehouse` | Star schema | dim_date, dim_customer, dim_region, dim_loan_product, fact_loan, fact_transaction |
| `reporting` | KPI layer | 6 views, 1 materialized view, 3 stored functions |

## ETL Pipeline Steps

1. **Extract** – COPY raw CSVs into staging tables
2. **Transform Step 1** – dim_region (deduplicate & derive city–state key)
3. **Transform Step 2** – dim_loan_product (UPSERT product catalogue)
4. **Transform Step 3** – dim_customer (SCD Type 2 with effective/expiry dates)
5. **Transform Step 4** – fact_loan (EMI calculation, is_npl, is_par30 flags)
6. **Transform Step 5** – fact_transaction (Z-score anomaly detection, scoring)
7. **Load** – All steps use `INSERT … ON CONFLICT DO UPDATE` (UPSERT)

## AI Agent Decision Tree

```
START → Poll vw_kpi_snapshot
  ├── PAR-30 > 5%  → fn_investigate_par30_spike()  → GPT-4 → Slack
  ├── Default > 3% → fn_investigate_default_spike() → GPT-4 → Slack
  ├── Anomaly > 50 → fn_investigate_anomaly_spike() → GPT-4 → Slack
  ├── NPL > 8%     → vw_npl_ratio query             → GPT-4 → Slack
  └── All OK       → Log success, update state
WAIT (poll_interval) → Repeat
```
