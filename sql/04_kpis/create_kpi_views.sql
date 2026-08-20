-- =============================================================================
-- Fin-Guard Analytics – KPI Views & Materialized Views
-- File   : 04_kpis/create_kpi_views.sql
-- Purpose: Define all business KPIs as SQL views for Power BI consumption
--          and AI agent polling.
-- =============================================================================


-- ─────────────────────────────────────────────────────────────────────────────
-- KPI 1: Portfolio at Risk – PAR 30 (rolling 30-day window)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW reporting.vw_par30 AS
WITH portfolio AS (
    SELECT
        dd.full_date,
        SUM(fl.outstanding_balance)                                                          AS total_portfolio,
        SUM(fl.outstanding_balance) FILTER (WHERE fl.is_par30 OR fl.is_npl)                 AS at_risk_balance,
        COUNT(fl.loan_key)                                                                   AS total_loans,
        COUNT(fl.loan_key)         FILTER (WHERE fl.is_par30 OR fl.is_npl)                  AS at_risk_loans
    FROM warehouse.fact_loan fl
    INNER JOIN warehouse.dim_date dd ON dd.date_key = fl.issue_date_key
    GROUP BY dd.full_date
)
SELECT
    full_date,
    total_portfolio,
    at_risk_balance,
    total_loans,
    at_risk_loans,
    ROUND(at_risk_balance / NULLIF(total_portfolio, 0) * 100, 4) AS par30_pct,
    -- 7-day rolling average
    ROUND(AVG(at_risk_balance / NULLIF(total_portfolio,0) * 100)
          OVER (ORDER BY full_date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW), 4) AS par30_7d_avg,
    -- 30-day rolling average
    ROUND(AVG(at_risk_balance / NULLIF(total_portfolio,0) * 100)
          OVER (ORDER BY full_date ROWS BETWEEN 29 PRECEDING AND CURRENT ROW), 4) AS par30_30d_avg
FROM portfolio
ORDER BY full_date;


-- ─────────────────────────────────────────────────────────────────────────────
-- KPI 2: 30-Day Loan Default Rate
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW reporting.vw_default_rate AS
WITH monthly_defaults AS (
    SELECT
        dd.year,
        dd.month_num,
        dd.month_name,
        DATE_TRUNC('month', dd.full_date)               AS month_start,
        COUNT(fl.loan_key)                              AS total_loans_issued,
        COUNT(fl.loan_key) FILTER (WHERE fl.loan_status = 'DEFAULTED')  AS defaults,
        SUM(fl.principal_amount)                        AS total_principal,
        SUM(fl.principal_amount) FILTER (WHERE fl.loan_status = 'DEFAULTED') AS defaulted_principal
    FROM warehouse.fact_loan fl
    INNER JOIN warehouse.dim_date dd ON dd.date_key = fl.issue_date_key
    GROUP BY dd.year, dd.month_num, dd.month_name, DATE_TRUNC('month', dd.full_date)
)
SELECT
    year,
    month_num,
    month_name,
    month_start,
    total_loans_issued,
    defaults,
    ROUND(defaults * 100.0 / NULLIF(total_loans_issued, 0), 4)          AS default_rate_pct,
    defaulted_principal,
    ROUND(defaulted_principal * 100.0 / NULLIF(total_principal, 0), 4)  AS default_amount_pct,
    -- Quarter-to-date cumulative
    SUM(defaults) OVER (
        PARTITION BY year, CEIL(month_num / 3.0)
        ORDER BY month_num
    )                                                                     AS qtd_defaults,
    -- Year-to-date cumulative
    SUM(defaults) OVER (PARTITION BY year ORDER BY month_num)            AS ytd_defaults
FROM monthly_defaults
ORDER BY year, month_num;


-- ─────────────────────────────────────────────────────────────────────────────
-- KPI 3: Transaction Volume by Region (daily)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW reporting.vw_txn_volume_by_region AS
SELECT
    dd.full_date,
    dd.year,
    dd.month_num,
    dd.week_of_year,
    dr.country,
    dr.state,
    dr.city,
    dr.region_tier,
    ft.transaction_type,
    COUNT(ft.txn_key)               AS txn_count,
    ROUND(SUM(ft.amount), 2)        AS total_volume,
    ROUND(AVG(ft.amount), 2)        AS avg_amount,
    COUNT(ft.txn_key) FILTER (WHERE ft.is_anomaly) AS anomaly_count,
    -- Day-over-day change
    LAG(SUM(ft.amount)) OVER (
        PARTITION BY dr.state, ft.transaction_type
        ORDER BY dd.full_date
    )                                               AS prev_day_volume,
    ROUND(
        (SUM(ft.amount) - LAG(SUM(ft.amount)) OVER (PARTITION BY dr.state, ft.transaction_type ORDER BY dd.full_date))
        * 100.0
        / NULLIF(LAG(SUM(ft.amount)) OVER (PARTITION BY dr.state, ft.transaction_type ORDER BY dd.full_date), 0),
    2)                                              AS dod_pct_change
FROM warehouse.fact_transaction ft
INNER JOIN warehouse.dim_date   dd ON dd.date_key   = ft.txn_date_key
INNER JOIN warehouse.dim_region dr ON dr.region_key = ft.region_key
GROUP BY dd.full_date, dd.year, dd.month_num, dd.week_of_year,
         dr.country, dr.state, dr.city, dr.region_tier, ft.transaction_type
ORDER BY dd.full_date, dr.country, dr.state;


-- ─────────────────────────────────────────────────────────────────────────────
-- KPI 4: Anomaly Flag Summary Dashboard View
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW reporting.vw_anomaly_summary AS
WITH daily_anomalies AS (
    SELECT
        dd.full_date,
        ft.transaction_type,
        dr.country,
        dr.state,
        COUNT(*) FILTER (WHERE ft.is_anomaly)                           AS anomaly_count,
        COUNT(*)                                                         AS total_txns,
        ROUND(AVG(ft.anomaly_score) FILTER (WHERE ft.is_anomaly), 4)    AS avg_anomaly_score,
        ROUND(SUM(ft.amount) FILTER (WHERE ft.is_anomaly), 2)           AS anomalous_volume
    FROM warehouse.fact_transaction ft
    INNER JOIN warehouse.dim_date   dd ON dd.date_key   = ft.txn_date_key
    INNER JOIN warehouse.dim_region dr ON dr.region_key = ft.region_key
    GROUP BY dd.full_date, ft.transaction_type, dr.country, dr.state
)
SELECT
    *,
    ROUND(anomaly_count * 100.0 / NULLIF(total_txns, 0), 4) AS anomaly_rate_pct,
    SUM(anomaly_count) OVER (ORDER BY full_date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS anomaly_7d_rolling
FROM daily_anomalies
ORDER BY full_date DESC, anomaly_count DESC;


-- ─────────────────────────────────────────────────────────────────────────────
-- KPI 5: NPL Ratio (Non-Performing Loan)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW reporting.vw_npl_ratio AS
SELECT
    dd.year,
    dd.month_num,
    dd.month_name,
    dc_risk.risk_tier,
    dlp.category                                              AS product_category,
    COUNT(fl.loan_key)                                        AS total_loans,
    COUNT(fl.loan_key) FILTER (WHERE fl.is_npl)              AS npl_loans,
    ROUND(SUM(fl.outstanding_balance), 2)                    AS total_outstanding,
    ROUND(SUM(fl.outstanding_balance) FILTER (WHERE fl.is_npl), 2) AS npl_outstanding,
    ROUND(
        COUNT(fl.loan_key) FILTER (WHERE fl.is_npl) * 100.0
        / NULLIF(COUNT(fl.loan_key), 0),
    4)                                                        AS npl_ratio_pct
FROM warehouse.fact_loan fl
INNER JOIN warehouse.dim_date         dd      ON dd.date_key    = fl.issue_date_key
INNER JOIN warehouse.dim_customer     dc_risk ON dc_risk.customer_key = fl.customer_key
INNER JOIN warehouse.dim_loan_product dlp     ON dlp.product_key      = fl.product_key
GROUP BY dd.year, dd.month_num, dd.month_name, dc_risk.risk_tier, dlp.category
ORDER BY dd.year, dd.month_num, npl_ratio_pct DESC;


-- ─────────────────────────────────────────────────────────────────────────────
-- KPI 6: Executive Summary (single-row current snapshot for AI Agent polling)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW reporting.vw_kpi_snapshot AS
SELECT
    NOW()                                                            AS snapshot_ts,
    -- PAR30
    (SELECT ROUND(AVG(par30_pct), 4) FROM reporting.vw_par30
     WHERE full_date >= CURRENT_DATE - 30)                          AS par30_30d_avg,
    -- Default Rate (current month)
    (SELECT ROUND(default_rate_pct, 4) FROM reporting.vw_default_rate
     WHERE year = EXTRACT(YEAR FROM NOW())
       AND month_num = EXTRACT(MONTH FROM NOW())
     LIMIT 1)                                                        AS current_month_default_rate,
    -- Anomaly count (last 24h)
    (SELECT COALESCE(SUM(anomaly_count), 0) FROM reporting.vw_anomaly_summary
     WHERE full_date = CURRENT_DATE - 1)                            AS anomaly_count_yesterday,
    -- Total active loans
    (SELECT COUNT(*) FROM warehouse.fact_loan WHERE loan_status = 'ACTIVE') AS active_loan_count,
    -- NPL ratio (all-time)
    (SELECT ROUND(SUM(npl_loans)*100.0/NULLIF(SUM(total_loans),0),4)
     FROM reporting.vw_npl_ratio)                                   AS overall_npl_ratio,
    -- Portfolio size
    (SELECT ROUND(SUM(outstanding_balance), 2) FROM warehouse.fact_loan
     WHERE loan_status = 'ACTIVE')                                  AS total_active_portfolio;


-- ─────────────────────────────────────────────────────────────────────────────
-- MATERIALIZED VIEW: Daily KPI cache (refresh nightly or via agent trigger)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE MATERIALIZED VIEW IF NOT EXISTS reporting.mv_daily_kpi_cache AS
SELECT * FROM reporting.vw_kpi_snapshot
WITH DATA;

CREATE UNIQUE INDEX IF NOT EXISTS idx_mv_daily_kpi_ts
    ON reporting.mv_daily_kpi_cache (snapshot_ts);


-- ─────────────────────────────────────────────────────────────────────────────
-- STORED PROCEDURE: Refresh all materialized views
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE reporting.refresh_kpi_cache()
LANGUAGE plpgsql AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY reporting.mv_daily_kpi_cache;
    RAISE NOTICE 'KPI cache refreshed at %', NOW();
END;
$$;
