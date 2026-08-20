-- =============================================================================
-- Fin-Guard Analytics – Anomaly Detection SQL
-- File   : 05_anomaly/anomaly_detection.sql
-- Purpose: Root-cause investigation queries used by the AI Agent
--          when a KPI threshold breach is detected.
-- =============================================================================


-- ─────────────────────────────────────────────────────────────────────────────
-- Query A: Identify which customer segments are driving the default spike
-- Usage  : AI Agent calls this when default_rate > threshold
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION reporting.fn_investigate_default_spike(
    p_start_date DATE DEFAULT CURRENT_DATE - 30,
    p_end_date   DATE DEFAULT CURRENT_DATE
)
RETURNS TABLE (
    risk_tier        TEXT,
    product_category TEXT,
    region_state     TEXT,
    defaulted_loans  BIGINT,
    total_loans      BIGINT,
    default_rate_pct NUMERIC,
    avg_credit_score NUMERIC,
    avg_loan_amount  NUMERIC
)
LANGUAGE plpgsql AS $$
BEGIN
    RETURN QUERY
    WITH window_defaults AS (
        SELECT
            fl.*,
            dc.risk_tier,
            dc.credit_score,
            dlp.category AS product_category,
            dr.state     AS region_state,
            dd.full_date AS issue_date
        FROM warehouse.fact_loan fl
        INNER JOIN warehouse.dim_date         dd  ON dd.date_key    = fl.issue_date_key
        INNER JOIN warehouse.dim_customer     dc  ON dc.customer_key = fl.customer_key
        INNER JOIN warehouse.dim_loan_product dlp ON dlp.product_key = fl.product_key
        INNER JOIN warehouse.dim_region       dr  ON dr.region_key   = fl.region_key
        WHERE dd.full_date BETWEEN p_start_date AND p_end_date
    )
    SELECT
        wd.risk_tier::TEXT,
        wd.product_category::TEXT,
        wd.region_state::TEXT,
        COUNT(*) FILTER (WHERE wd.loan_status = 'DEFAULTED')::BIGINT   AS defaulted_loans,
        COUNT(*)::BIGINT                                                  AS total_loans,
        ROUND(COUNT(*) FILTER (WHERE wd.loan_status = 'DEFAULTED') * 100.0
              / NULLIF(COUNT(*), 0), 4)                                  AS default_rate_pct,
        ROUND(AVG(wd.credit_score), 1)                                   AS avg_credit_score,
        ROUND(AVG(wd.principal_amount), 2)                               AS avg_loan_amount
    FROM window_defaults wd
    GROUP BY wd.risk_tier, wd.product_category, wd.region_state
    ORDER BY default_rate_pct DESC;
END;
$$;


-- ─────────────────────────────────────────────────────────────────────────────
-- Query B: Investigate PAR-30 spike – find loans sliding into delinquency
-- Usage  : AI Agent calls this when par30_pct > threshold
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION reporting.fn_investigate_par30_spike(
    p_dpd_min INT DEFAULT 30,
    p_dpd_max INT DEFAULT 89
)
RETURNS TABLE (
    loan_id          TEXT,
    customer_id      TEXT,
    risk_tier        TEXT,
    days_past_due    INT,
    outstanding      NUMERIC,
    product_category TEXT,
    state            TEXT,
    days_in_par30    INT
)
LANGUAGE plpgsql AS $$
BEGIN
    RETURN QUERY
    SELECT
        fl.loan_id::TEXT,
        dc.customer_id::TEXT,
        dc.risk_tier::TEXT,
        fl.days_past_due::INT,
        fl.outstanding_balance::NUMERIC,
        dlp.category::TEXT,
        dr.state::TEXT,
        (fl.days_past_due - p_dpd_min)::INT AS days_in_par30
    FROM warehouse.fact_loan fl
    INNER JOIN warehouse.dim_customer     dc  ON dc.customer_key = fl.customer_key AND dc.is_current
    INNER JOIN warehouse.dim_loan_product dlp ON dlp.product_key = fl.product_key
    INNER JOIN warehouse.dim_region       dr  ON dr.region_key   = fl.region_key
    WHERE fl.days_past_due BETWEEN p_dpd_min AND p_dpd_max
    ORDER BY fl.outstanding_balance DESC;
END;
$$;


-- ─────────────────────────────────────────────────────────────────────────────
-- Query C: Investigate anomaly count spike – find the suspicious transactions
-- Usage  : AI Agent calls this when anomaly_count > threshold
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION reporting.fn_investigate_anomaly_spike(
    p_date DATE DEFAULT CURRENT_DATE - 1
)
RETURNS TABLE (
    transaction_id   TEXT,
    customer_id      TEXT,
    risk_tier        TEXT,
    transaction_type TEXT,
    amount           NUMERIC,
    anomaly_score    NUMERIC,
    anomaly_reason   TEXT,
    region           TEXT
)
LANGUAGE plpgsql AS $$
BEGIN
    RETURN QUERY
    SELECT
        ft.transaction_id::TEXT,
        dc.customer_id::TEXT,
        dc.risk_tier::TEXT,
        ft.transaction_type::TEXT,
        ft.amount::NUMERIC,
        ft.anomaly_score::NUMERIC,
        ft.anomaly_reason::TEXT,
        (dr.city || ', ' || dr.state)::TEXT AS region
    FROM warehouse.fact_transaction ft
    INNER JOIN warehouse.dim_date     dd ON dd.date_key    = ft.txn_date_key
    INNER JOIN warehouse.dim_customer dc ON dc.customer_key = ft.customer_key
    INNER JOIN warehouse.dim_region   dr ON dr.region_key   = ft.region_key
    WHERE ft.is_anomaly = TRUE
      AND dd.full_date  = p_date
    ORDER BY ft.anomaly_score DESC
    LIMIT 50;
END;
$$;


-- ─────────────────────────────────────────────────────────────────────────────
-- Query D: Statistical outlier detection using IQR method
-- Tags loans that are statistical outliers in their product category
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW reporting.vw_loan_outliers AS
WITH product_stats AS (
    SELECT
        dlp.category,
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY fl.principal_amount) AS q1,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY fl.principal_amount) AS q3
    FROM warehouse.fact_loan fl
    INNER JOIN warehouse.dim_loan_product dlp ON dlp.product_key = fl.product_key
    GROUP BY dlp.category
),
iqr_bounds AS (
    SELECT
        category,
        q1,
        q3,
        (q3 - q1)           AS iqr,
        q1 - 1.5 * (q3-q1) AS lower_fence,
        q3 + 1.5 * (q3-q1) AS upper_fence
    FROM product_stats
)
SELECT
    fl.loan_id,
    dc.customer_id,
    dc.risk_tier,
    dlp.category,
    fl.principal_amount,
    ib.lower_fence,
    ib.upper_fence,
    CASE
        WHEN fl.principal_amount < ib.lower_fence THEN 'LOW_OUTLIER'
        WHEN fl.principal_amount > ib.upper_fence THEN 'HIGH_OUTLIER'
    END AS outlier_type
FROM warehouse.fact_loan fl
INNER JOIN warehouse.dim_loan_product dlp ON dlp.product_key  = fl.product_key
INNER JOIN warehouse.dim_customer     dc  ON dc.customer_key  = fl.customer_key
INNER JOIN iqr_bounds                 ib  ON ib.category      = dlp.category
WHERE fl.principal_amount < ib.lower_fence
   OR fl.principal_amount > ib.upper_fence
ORDER BY fl.principal_amount DESC;
