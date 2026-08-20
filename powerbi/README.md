# Power BI Dashboard – Connection & Usage Guide

## Connection Setup

### Direct PostgreSQL Connection

1. Open Power BI Desktop
2. **Get Data** → **PostgreSQL database**
3. Server: `localhost:5432`
4. Database: `fingard_db`
5. Data Connectivity mode: **DirectQuery** (for live data) or **Import** (for performance)

### Recommended Tables/Views to Import

| View/Table | Purpose | Refresh |
|-----------|---------|---------|
| `reporting.vw_par30` | PAR-30 time series | Daily |
| `reporting.vw_default_rate` | Default rate trend | Daily |
| `reporting.vw_txn_volume_by_region` | Regional heatmap | Hourly |
| `reporting.vw_anomaly_summary` | Anomaly dashboard | Real-time |
| `reporting.vw_npl_ratio` | NPL breakdown | Daily |
| `reporting.mv_daily_kpi_cache` | Executive summary | Daily |
| `warehouse.dim_customer` | Customer slicer | Weekly |
| `warehouse.dim_region` | Region slicer | Monthly |

---

## Dashboard Pages

### Page 1: Executive KPI Overview
- **Card visuals**: PAR-30, Default Rate, NPL Ratio, Anomaly Count
- **Gauge charts**: Show threshold proximity
- **Conditional formatting**: Red for breach, amber for warning, green for OK

### Page 2: Default Rate Deep Dive
- **Line chart**: Monthly default rate trend (2021–present)
- **Matrix**: Default rate by Risk Tier × Product Category
- **Bar chart**: Top 10 states by default rate

### Page 3: Transaction Analysis
- **Area chart**: Daily transaction volume (stacked by type)
- **Map visual**: Geographic heatmap of transaction volume
- **Anomaly scatter**: Amount vs Anomaly Score

### Page 4: Portfolio at Risk (PAR)
- **Waterfall chart**: DPD bucket transitions
- **Heat matrix**: PAR by region × month
- **Table**: Top 20 at-risk loans

### Page 5: AI Agent Monitoring Log
- **Table**: Last 100 agent poll results from `staging.etl_run_log`
- **Timeline**: Alert history

---

## DAX Measures

```dax
PAR30 Rate = 
DIVIDE(
    SUMX(FILTER('fact_loan', 'fact_loan'[is_par30] = TRUE()), [outstanding_balance]),
    SUM('fact_loan'[outstanding_balance]),
    0
) * 100

Default Rate MoM = 
VAR current_month = CALCULATE(COUNTROWS(FILTER('fact_loan', [loan_status]="DEFAULTED")), DATESMTD('dim_date'[full_date]))
VAR prev_month = CALCULATE(COUNTROWS(FILTER('fact_loan', [loan_status]="DEFAULTED")), PREVIOUSMONTH('dim_date'[full_date]))
RETURN DIVIDE(current_month - prev_month, prev_month, 0) * 100

NPL Ratio = 
DIVIDE(COUNTROWS(FILTER('fact_loan', [is_npl]=TRUE())), COUNTROWS('fact_loan'), 0) * 100
```

---

## Slicers (Recommended)

- **Date Range** – from `dim_date`
- **Risk Tier** – from `dim_customer`
- **Product Category** – from `dim_loan_product`
- **Region / State** – from `dim_region`
- **Loan Status** – from `fact_loan`
