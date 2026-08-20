# Fin-Guard Analytics – Setup Guide

## Prerequisites

| Tool | Version | Download |
|------|---------|---------|
| Docker Desktop | Latest | https://docker.com |
| Python | ≥ 3.11 | https://python.org |
| PostgreSQL client (psql) | ≥ 15 | Bundled with Docker |
| Power BI Desktop | Latest | Microsoft Store |
| Git | Latest | https://git-scm.com |

---

## Step 1: Start Infrastructure

```bash
# Start PostgreSQL + pgAdmin
docker-compose up -d

# Verify containers are running
docker ps
```

- **PostgreSQL**: `localhost:5432`
- **pgAdmin**: http://localhost:5050 (admin@fingard.local / admin)

---

## Step 2: Initialize the Database

```bash
# Create staging + warehouse schemas
psql -h localhost -U fingard -d fingard_db -f sql/01_schema/create_staging_tables.sql
psql -h localhost -U fingard -d fingard_db -f sql/01_schema/create_star_schema.sql

# Create KPI views and anomaly functions
psql -h localhost -U fingard -d fingard_db -f sql/04_kpis/create_kpi_views.sql
psql -h localhost -U fingard -d fingard_db -f sql/05_anomaly/anomaly_detection.sql
```

---

## Step 3: Generate & Load Sample Data

```bash
# Install Python deps
pip install -r requirements.txt

# Generate synthetic CSVs (5K customers, 12K loans, 60K transactions)
python scripts/generate_sample_data.py

# Load CSVs into staging (adjust paths as needed)
psql -h localhost -U fingard -d fingard_db -c \
  "\COPY staging.raw_customers FROM 'data/raw/customers.csv' CSV HEADER"

psql -h localhost -U fingard -d fingard_db -c \
  "\COPY staging.raw_loans FROM 'data/raw/loans.csv' CSV HEADER"

psql -h localhost -U fingard -d fingard_db -c \
  "\COPY staging.raw_transactions FROM 'data/raw/transactions.csv' CSV HEADER"

psql -h localhost -U fingard -d fingard_db -c \
  "\COPY staging.raw_loan_products FROM 'data/raw/loan_products.csv' CSV HEADER"

# Run full ETL
psql -h localhost -U fingard -d fingard_db -f sql/02_etl/load_and_transform.sql
```

---

## Step 4: Configure Secrets

```bash
cp .env.example .env
```

Edit `.env` and fill in:
- `OPENAI_API_KEY` – from https://platform.openai.com
- `SLACK_WEBHOOK_URL` – from https://api.slack.com/apps → Incoming Webhooks

---

## Step 5: Run the AI Agent

```bash
python agent/main.py
```

The agent will:
1. Poll `reporting.vw_kpi_snapshot` every 5 minutes
2. Display a Rich terminal dashboard
3. Log to `data/processed/agent.log`
4. Fire Slack alerts if thresholds are breached

---

## Step 6: Generate Excel Report

```bash
python scripts/generate_excel_report.py
# Output: excel/reports/FinGuard_Report_<date>.xlsx
```

---

## Step 7: View the Web Dashboard

Open `dashboard/index.html` in any modern browser.

No server required – the dashboard uses Chart.js via CDN with simulated data.
For live data, point it to a REST API wrapper around your KPI views.

---

## Step 8: Connect Power BI

1. Open `powerbi/dashboard.pbix` in Power BI Desktop
2. In the **Transform Data** menu → **Data source settings**
3. Update server: `localhost`, database: `fingard_db`
4. Credentials: username `fingard`, password `fingard_secret`
5. Click **Refresh** to load live data

---

## Useful SQL Commands

```sql
-- Check ETL run log
SELECT * FROM staging.etl_run_log ORDER BY run_ts DESC LIMIT 10;

-- Live KPI snapshot
SELECT * FROM reporting.vw_kpi_snapshot;

-- Refresh materialized cache
CALL reporting.refresh_kpi_cache();

-- Top defaulting segments
SELECT * FROM reporting.fn_investigate_default_spike();

-- Anomaly investigation
SELECT * FROM reporting.fn_investigate_anomaly_spike();
```

---

## Troubleshooting

| Issue | Fix |
|-------|-----|
| Docker not starting | Ensure Docker Desktop is running |
| psql connection refused | Check `DB_HOST=localhost` in .env |
| OpenAI 401 error | Verify `OPENAI_API_KEY` in .env |
| Slack alert not delivered | Check webhook URL format & channel name |
| ETL errors | Check `staging.etl_run_log` for failure messages |
