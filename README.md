<h1 align="center">🛡️ Fin-Guard Analytics & Agentic AI Monitor</h1>

<p align="center">
  <em>A production-grade financial intelligence system that detects loan portfolio risk, monitors credit KPIs in real time, and autonomously alerts before problems become crises.</em>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Status-Active-brightgreen?style=for-the-badge" />
  <img src="https://img.shields.io/badge/Python-3.10+-blue?style=for-the-badge&logo=python" />
  <img src="https://img.shields.io/badge/PostgreSQL-15-336791?style=for-the-badge&logo=postgresql" />
  <img src="https://img.shields.io/badge/LangChain-AI%20Agent-orange?style=for-the-badge" />
  <img src="https://img.shields.io/badge/Power%20BI-Dashboard-F2C811?style=for-the-badge&logo=powerbi" />
  <img src="https://img.shields.io/badge/Docker-Containerized-2496ED?style=for-the-badge&logo=docker" />
</p>

---

## 📖 The Story Behind This Project

> *"Banks lose millions not because they lack data — but because they lack timely insight."*

### 🔴 The Problem

Financial institutions managing large loan portfolios face a brutal reality:

- **Loan defaults spike silently** — by the time a report is generated, the damage is done.
- **Risk teams drown in spreadsheets** — manually hunting anomalies across thousands of transactions every day.
- **KPI dashboards are reactive** — they tell you what *happened*, not what's *happening*.
- **Early warning systems are expensive** — most small-to-mid-size lenders can't afford proprietary risk platforms.

The result? A **$3.1 trillion global non-performing loan (NPL) problem** (World Bank, 2023) that keeps growing because institutions react too slowly.

---

### 🟡 The Gap

Most existing solutions either:

- Require **expensive enterprise BI tools** with long vendor lock-in contracts, or
- Are **static dashboards** that need a human to notice the red flag and manually investigate

There was no lightweight, **open, intelligent system** that could:
1. Continuously monitor credit risk KPIs
2. Automatically detect anomalies
3. Investigate root causes using SQL
4. Fire real-time alerts to the team

---

### 🟢 The Solution — Fin-Guard Analytics

**Fin-Guard Analytics** is built to close that gap. It's a full-stack data pipeline + AI agent that:

| What It Does | How |
|---|---|
| 🗃️ **Ingests & cleans** raw loan data | PostgreSQL ETL pipeline with CTE transformations |
| 📊 **Computes credit risk KPIs** | SQL views & stored procedures (PAR-30, NPL, Default Rate) |
| 🔍 **Detects anomalies autonomously** | SQL-based threshold logic + statistical flagging |
| 🤖 **Investigates root causes** | LangChain AI Agent with SQL tool access |
| 🚨 **Sends real-time alerts** | Slack Webhook dispatcher with context-rich messages |
| 📈 **Visualizes the portfolio** | Power BI dashboard + standalone HTML/JS web view |

---

## 💡 How It Works — The Data Journey

```
📥 Raw Data (CSV / Kaggle / BigQuery)
        │
        ▼
🧹 ETL Pipeline (SQL Transformations)
   └── Clean → Normalize → Star Schema
        │
        ▼
📐 KPI Engine (PostgreSQL Views)
   └── PAR-30 · Default Rate · NPL Ratio · Volume Trends
        │
        ▼
🤖 AI Agent Monitor (LangChain + GPT-4)
   ├── 🔄 Poller       → Fetches KPI snapshots on schedule
   ├── ⚖️  Threshold Check → Compares vs. business rules
   ├── 🔬 Investigator  → Runs root-cause SQL queries
   └── 📣 Notifier      → Fires Slack alert with findings
        │
        ▼
📊 Dashboard (Power BI / Web)
   └── Visual portfolio health for risk managers
```

---

## 🎯 Key KPIs Tracked & Why They Matter

| KPI | What It Measures | Alert Threshold | Business Impact |
|-----|-----------------|-----------------|-----------------|
| **PAR-30** | Portfolio at Risk (30 days overdue) | > 5% | Predicts near-term defaults |
| **Default Rate** | % of loans defaulted in 30 days | > 3% | Core credit quality signal |
| **NPL Ratio** | Non-Performing Loan ratio | > 8% | Regulatory & capital requirement risk |
| **Anomaly Flag Count** | Suspicious flagged transactions/day | > 50/day | Fraud & data integrity signal |
| **Transaction Volume** | Daily volume change by region | < -20% MoM | Demand shift & economic stress signal |

> 💡 **Storytelling Insight:** A jump in PAR-30 from 4.2% → 6.8% over two weeks is not just a number — it's an early signal that a specific borrower segment is under cash-flow stress. Fin-Guard catches that *before* it becomes a default wave.

---

## 🤖 AI Agent — The Brain of the System

The autonomous AI agent is the most powerful piece of this project. Here's its decision loop:

```
┌────────────────────────────────────────────────────────────────┐
│                     🤖  AI Agent Monitor                       │
│                                                                │
│   ┌──────────────┐     ┌──────────────┐     ┌──────────────┐  │
│   │   🔄 Poller   │────▶│  ⚖️ Threshold │────▶│ 🔬 Investigator│ │
│   │  (KPI Fetch) │     │    Check     │     │ (SQL Root    │  │
│   └──────────────┘     └──────────────┘     │  Cause Query)│  │
│                                             └──────┬───────┘  │
│                                                    │          │
│                                            ┌───────▼───────┐  │
│                                            │  📣 Slack Alert │  │
│                                            │   Dispatcher   │  │
│                                            │  (with context)│  │
│                                            └───────────────┘  │
└────────────────────────────────────────────────────────────────┘
```

**Agent capabilities:**
- 🧠 Maintains **memory of past alerts** to avoid duplicate noise
- 🔧 Uses **LangChain tools** (SQL Tool, KPI Tool, Alert Tool) to autonomously investigate
- 📋 Generates **human-readable explanations** — not just raw numbers
- 🔁 Runs on a **configurable polling schedule** (cron-based)

---

## 🛠️ Tech Stack

| Layer | Technology | Purpose |
|-------|-----------|---------|
| 🗄️ **Database** | PostgreSQL 15 | Core data warehouse |
| ⚙️ **ETL / SQL** | Pure SQL (CTEs, Window Functions, Stored Procs) | Data transformation & KPI computation |
| 🔍 **EDA** | SQL + Jupyter Notebooks | Exploratory analysis & model validation |
| 📊 **Excel Reporting** | openpyxl / xlsxwriter | Pivot-table prototypes for stakeholders |
| 📈 **BI Dashboard** | Power BI + HTML/JS Web View | Visual portfolio monitoring |
| 🤖 **AI Agent** | LangChain + OpenAI GPT-4 | Autonomous monitoring & investigation |
| 🚨 **Alerting** | Slack Webhooks | Real-time team notifications |
| 🐳 **Infrastructure** | Docker + Docker Compose | Portable, reproducible environment |

---

## 📁 Project Structure

```
Fin-Guard Analytics/
│
├── 📂 data/
│   ├── raw/                    # Raw CSV files from Kaggle / BigQuery
│   ├── processed/              # Cleaned & transformed exports
│   └── samples/                # Small sample datasets for testing
│
├── 📂 sql/
│   ├── 01_schema/              # DDL – create tables, star schema
│   ├── 02_etl/                 # ETL transformation scripts
│   ├── 03_eda/                 # Exploratory SQL queries
│   ├── 04_kpis/                # KPI calculation views & stored procedures
│   └── 05_anomaly/             # Anomaly detection SQL logic
│
├── 📂 excel/
│   └── reports/                # Pivot-table Excel prototypes
│
├── 📂 powerbi/
│   ├── dashboard.pbix          # Power BI dashboard file
│   └── README.md               # Connection & usage guide
│
├── 📂 agent/
│   ├── main.py                 # Entry point for the AI agent
│   ├── monitor.py              # KPI polling & threshold logic
│   ├── investigator.py         # Root-cause SQL investigation
│   ├── notifier.py             # Slack alert dispatcher
│   ├── config.py               # Config + secrets loader
│   ├── memory.py               # Agent memory / state store
│   └── tools/                  # LangChain tool definitions
│       ├── sql_tool.py
│       ├── kpi_tool.py
│       └── alert_tool.py
│
├── 📂 notebooks/
│   ├── 01_eda.ipynb            # Exploratory Data Analysis
│   ├── 02_feature_engineering.ipynb
│   └── 03_model_validation.ipynb
│
├── 📂 dashboard/               # Standalone HTML/JS dashboard (web preview)
│   ├── index.html
│   ├── app.js
│   └── styles.css
│
├── 📂 docs/
│   ├── architecture.md         # System design & data flow
│   ├── kpi_definitions.md      # KPI formulas & business rules
│   └── setup_guide.md          # Step-by-step environment setup
│
├── .env.example                # Template for environment variables
├── requirements.txt            # Python dependencies
├── docker-compose.yml          # PostgreSQL + pgAdmin stack
└── README.md                   # This file
```

---

## 🚀 Quick Start

### Prerequisites
- Docker & Docker Compose installed
- Python 3.10+
- OpenAI API key
- Slack Workspace (for alerts)

### Step 1 — Spin up the Database
```bash
docker-compose up -d
```

### Step 2 — Load Schema & Run ETL
```bash
psql -U fingard -d fingard_db -f sql/01_schema/create_star_schema.sql
psql -U fingard -d fingard_db -f sql/02_etl/load_and_transform.sql
psql -U fingard -d fingard_db -f sql/04_kpis/create_kpi_views.sql
```

### Step 3 — Install Python Dependencies
```bash
pip install -r requirements.txt
```

### Step 4 — Configure Secrets
```bash
cp .env.example .env
# Fill in: DB credentials, OpenAI API key, Slack webhook URL
```

### Step 5 — Launch the AI Agent Monitor
```bash
python agent/main.py
```

### Step 6 — Open the Web Dashboard
```bash
# Simply open in your browser:
dashboard/index.html
```

---

## 📌 Real-World Impact

> *Fin-Guard is designed to empower risk analysts and data teams at financial institutions to move from **reactive reporting** to **proactive intelligence**.*

- ⏱️ **Reduces anomaly detection time** from hours (manual) to seconds (automated)
- 💰 **Protects portfolio value** by catching risk signals before they cascade
- 📣 **Eliminates alert fatigue** — the AI agent only fires when thresholds are genuinely breached and root cause is confirmed
- 🔓 **Open & extensible** — no vendor lock-in, fully customizable thresholds and KPIs

---

## 🗺️ Roadmap

- [x] PostgreSQL Star Schema & ETL pipeline
- [x] KPI computation views & stored procedures
- [x] AI Agent with LangChain (Monitor → Investigate → Alert)
- [x] Power BI Dashboard + Web Dashboard
- [ ] ML-based anomaly detection (Isolation Forest / LSTM)
- [ ] Multi-channel alerting (Email, MS Teams, PagerDuty)
- [ ] REST API layer for KPI querying
- [ ] Automated report generation (PDF / Excel)

---

## 🤝 Contributing

Contributions, issues, and feature requests are welcome!  
Feel free to open an issue or submit a pull request.

---

## 📜 License

MIT License — see [LICENSE](LICENSE) for details.

---


