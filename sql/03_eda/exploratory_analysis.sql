-- =============================================================================
-- Fin-Guard Analytics – EDA Queries
-- File   : 03_eda/exploratory_analysis.sql
-- Purpose: Exploratory Data Analysis – distributions, outliers, baseline KPIs
-- =============================================================================


-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Data Quality Report: Row counts per table
-- ─────────────────────────────────────────────────────────────────────────────
SELECT 'staging.raw_customers'    AS table_name, COUNT(*) AS row_count FROM staging.raw_customers
UNION ALL
SELECT 'staging.raw_loans',                       COUNT(*) FROM staging.raw_loans
UNION ALL
SELECT 'staging.raw_transactions',                COUNT(*) FROM staging.raw_transactions
UNION ALL
SELECT 'warehouse.dim_customer',                  COUNT(*) FROM warehouse.dim_customer
UNION ALL
SELECT 'warehouse.fact_loan',                     COUNT(*) FROM warehouse.fact_loan
UNION ALL
SELECT 'warehouse.fact_transaction',              COUNT(*) FROM warehouse.fact_transaction
ORDER BY table_name;


-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Null / Missing Analysis: dim_customer
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
    'credit_score'      AS field,
    COUNT(*) FILTER (WHERE credit_score IS NULL) AS nulls,
    ROUND(COUNT(*) FILTER (WHERE credit_score IS NULL) * 100.0 / COUNT(*), 2) AS null_pct
FROM warehouse.dim_customer
UNION ALL
SELECT
    'annual_income',
    COUNT(*) FILTER (WHERE annual_income IS NULL),
    ROUND(COUNT(*) FILTER (WHERE annual_income IS NULL) * 100.0 / COUNT(*), 2)
FROM warehouse.dim_customer
UNION ALL
SELECT
    'date_of_birth',
    COUNT(*) FILTER (WHERE date_of_birth IS NULL),
    ROUND(COUNT(*) FILTER (WHERE date_of_birth IS NULL) * 100.0 / COUNT(*), 2)
FROM warehouse.dim_customer
ORDER BY null_pct DESC;


-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Credit Score Distribution (histogram buckets)
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
    WIDTH_BUCKET(credit_score, 300, 850, 11) AS bucket,
    MIN(credit_score)  AS bucket_floor,
    MAX(credit_score)  AS bucket_ceil,
    COUNT(*)           AS customers,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS pct
FROM warehouse.dim_customer
WHERE credit_score IS NOT NULL
GROUP BY bucket
ORDER BY bucket;


-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Loan Amount Descriptive Statistics
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
    COUNT(*)                                      AS total_loans,
    MIN(principal_amount)                         AS min_amount,
    MAX(principal_amount)                         AS max_amount,
    ROUND(AVG(principal_amount), 2)               AS mean_amount,
    PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY principal_amount) AS p25,
    PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY principal_amount) AS median,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY principal_amount) AS p75,
    PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY principal_amount) AS p95,
    ROUND(STDDEV(principal_amount), 2)            AS stddev
FROM warehouse.fact_loan;


-- ─────────────────────────────────────────────────────────────────────────────
-- 5. Loans by Status (portfolio composition)
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
    loan_status,
    COUNT(*)                                   AS loan_count,
    ROUND(SUM(principal_amount), 2)            AS total_principal,
    ROUND(AVG(principal_amount), 2)            AS avg_principal,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS pct_of_portfolio
FROM warehouse.fact_loan
GROUP BY loan_status
ORDER BY loan_count DESC;


-- ─────────────────────────────────────────────────────────────────────────────
-- 6. Monthly Loan Origination Trend (time-series)
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
    dd.year,
    dd.month_num,
    dd.month_name,
    COUNT(fl.loan_key)                  AS loans_issued,
    ROUND(SUM(fl.principal_amount), 2)  AS total_disbursed,
    -- Month-over-month growth
    LAG(COUNT(fl.loan_key)) OVER (ORDER BY dd.year, dd.month_num) AS prev_month_count,
    ROUND(
        (COUNT(fl.loan_key) - LAG(COUNT(fl.loan_key)) OVER (ORDER BY dd.year, dd.month_num))
        * 100.0
        / NULLIF(LAG(COUNT(fl.loan_key)) OVER (ORDER BY dd.year, dd.month_num), 0),
    2) AS mom_growth_pct
FROM warehouse.fact_loan fl
INNER JOIN warehouse.dim_date dd ON dd.date_key = fl.issue_date_key
GROUP BY dd.year, dd.month_num, dd.month_name
ORDER BY dd.year, dd.month_num;


-- ─────────────────────────────────────────────────────────────────────────────
-- 7. Transaction Volume by Type & Region
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
    dr.state,
    dr.country,
    ft.transaction_type,
    COUNT(*)                           AS txn_count,
    ROUND(SUM(ft.amount), 2)           AS total_volume,
    ROUND(AVG(ft.amount), 2)           AS avg_amount
FROM warehouse.fact_transaction ft
INNER JOIN warehouse.dim_region dr ON dr.region_key = ft.region_key
GROUP BY ROLLUP(dr.country, dr.state, ft.transaction_type)
ORDER BY dr.country, dr.state, txn_count DESC;


-- ─────────────────────────────────────────────────────────────────────────────
-- 8. Top 10 Anomalous Transactions
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
    ft.transaction_id,
    dc.customer_id,
    dc.risk_tier,
    ft.transaction_type,
    ft.amount,
    ft.anomaly_score,
    ft.anomaly_reason,
    dd.full_date AS transaction_date,
    dr.city, dr.state
FROM warehouse.fact_transaction ft
INNER JOIN warehouse.dim_customer   dc ON dc.customer_key = ft.customer_key
INNER JOIN warehouse.dim_date       dd ON dd.date_key     = ft.txn_date_key
INNER JOIN warehouse.dim_region     dr ON dr.region_key   = ft.region_key
WHERE ft.is_anomaly = TRUE
ORDER BY ft.anomaly_score DESC
LIMIT 10;


-- ─────────────────────────────────────────────────────────────────────────────
-- 9. Customer Risk Tier Breakdown
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
    risk_tier,
    COUNT(*)                                              AS customers,
    ROUND(AVG(credit_score), 1)                           AS avg_credit_score,
    ROUND(AVG(annual_income), 2)                          AS avg_income,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2)   AS pct
FROM warehouse.dim_customer
WHERE is_current
GROUP BY risk_tier
ORDER BY avg_credit_score DESC;


-- ─────────────────────────────────────────────────────────────────────────────
-- 10. Days-Past-Due Distribution (PAR buckets)
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
    CASE
        WHEN days_past_due = 0         THEN 'Current (0 days)'
        WHEN days_past_due BETWEEN 1  AND 29 THEN 'PAR 1-29'
        WHEN days_past_due BETWEEN 30 AND 59 THEN 'PAR 30-59'
        WHEN days_past_due BETWEEN 60 AND 89 THEN 'PAR 60-89'
        WHEN days_past_due >= 90       THEN 'NPL (90+ days)'
    END                                         AS dpd_bucket,
    COUNT(*)                                    AS loan_count,
    ROUND(SUM(principal_amount), 2)             AS outstanding_principal,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS pct_count
FROM warehouse.fact_loan
GROUP BY dpd_bucket
ORDER BY MIN(days_past_due);
