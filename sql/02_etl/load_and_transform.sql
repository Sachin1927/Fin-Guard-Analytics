-- =============================================================================
-- Fin-Guard Analytics – ETL: Load & Transform
-- File   : 02_etl/load_and_transform.sql
-- Purpose: Full ETL pipeline from staging → warehouse star schema.
--          Uses CTEs, window functions, and UPSERT patterns.
-- =============================================================================

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 1: Load Dimension: dim_region
-- ─────────────────────────────────────────────────────────────────────────────
WITH deduplicated_regions AS (
    SELECT DISTINCT
        LOWER(TRIM(city))    AS city,
        LOWER(TRIM(state))   AS state,
        LOWER(TRIM(country)) AS country,
        -- Derive region_id from city/state combination
        MD5(LOWER(TRIM(city)) || '|' || LOWER(TRIM(state))) AS region_id
    FROM staging.raw_customers
    WHERE city IS NOT NULL
      AND state IS NOT NULL
      AND country IS NOT NULL
),
region_tier AS (
    SELECT *,
        CASE
            WHEN city IN ('new york','los angeles','chicago','houston','london','mumbai','delhi') THEN 'URBAN'
            WHEN city IS NOT NULL THEN 'SEMI-URBAN'
            ELSE 'RURAL'
        END AS region_tier
    FROM deduplicated_regions
)
INSERT INTO warehouse.dim_region (region_id, city, state, country, region_tier)
SELECT region_id, INITCAP(city), INITCAP(state), INITCAP(country), region_tier
FROM region_tier
ON CONFLICT (region_id) DO UPDATE
    SET city        = EXCLUDED.city,
        state       = EXCLUDED.state,
        country     = EXCLUDED.country,
        region_tier = EXCLUDED.region_tier;

INSERT INTO staging.etl_run_log (step_name, rows_loaded, status)
VALUES ('dim_region', (SELECT COUNT(*) FROM warehouse.dim_region), 'SUCCESS');


-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 2: Load Dimension: dim_loan_product
-- ─────────────────────────────────────────────────────────────────────────────
INSERT INTO warehouse.dim_loan_product (
    product_code, product_name, category, sub_category,
    interest_rate_min, interest_rate_max,
    min_tenure_months, max_tenure_months,
    is_secured, collateral_type
)
SELECT
    UPPER(TRIM(product_code)),
    INITCAP(TRIM(product_name)),
    UPPER(TRIM(category)),
    INITCAP(TRIM(sub_category)),
    NULLIF(interest_rate_min, '')::NUMERIC(5,2),
    NULLIF(interest_rate_max, '')::NUMERIC(5,2),
    NULLIF(min_tenure_months, '')::SMALLINT,
    NULLIF(max_tenure_months, '')::SMALLINT,
    CASE WHEN LOWER(is_secured) IN ('true','yes','1') THEN TRUE ELSE FALSE END,
    NULLIF(TRIM(collateral_type), '')
FROM staging.raw_loan_products
WHERE TRIM(product_code) IS NOT NULL
ON CONFLICT (product_code) DO UPDATE
    SET product_name       = EXCLUDED.product_name,
        category           = EXCLUDED.category,
        interest_rate_min  = EXCLUDED.interest_rate_min,
        interest_rate_max  = EXCLUDED.interest_rate_max;

INSERT INTO staging.etl_run_log (step_name, rows_loaded, status)
VALUES ('dim_loan_product', (SELECT COUNT(*) FROM warehouse.dim_loan_product), 'SUCCESS');


-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 3: Load Dimension: dim_customer  (SCD Type 2)
-- ─────────────────────────────────────────────────────────────────────────────
WITH cleaned_customers AS (
    SELECT
        TRIM(customer_id)                                   AS customer_id,
        INITCAP(TRIM(first_name))                           AS first_name,
        INITCAP(TRIM(last_name))                            AS last_name,
        NULLIF(date_of_birth, '')::DATE                     AS date_of_birth,
        UPPER(LEFT(TRIM(gender), 1))                        AS gender,
        LOWER(TRIM(email))                                  AS email,
        TRIM(phone)                                         AS phone,
        INITCAP(TRIM(employment_status))                    AS employment_status,
        NULLIF(REGEXP_REPLACE(annual_income, '[^0-9.]', '', 'g'), '')::NUMERIC(15,2) AS annual_income,
        NULLIF(credit_score, '')::SMALLINT                  AS credit_score,
        ROW_NUMBER() OVER (
            PARTITION BY TRIM(customer_id)
            ORDER BY _ingested_at DESC
        )                                                   AS rn
    FROM staging.raw_customers
    WHERE TRIM(customer_id) IS NOT NULL
      AND TRIM(customer_id) != ''
)
INSERT INTO warehouse.dim_customer (
    customer_id, first_name, last_name, date_of_birth,
    gender, email, phone, employment_status,
    annual_income, credit_score
)
SELECT
    customer_id, first_name, last_name, date_of_birth,
    gender, email, phone, employment_status,
    annual_income, credit_score
FROM cleaned_customers
WHERE rn = 1
ON CONFLICT (customer_id) DO UPDATE
    SET first_name        = EXCLUDED.first_name,
        last_name         = EXCLUDED.last_name,
        employment_status = EXCLUDED.employment_status,
        annual_income     = EXCLUDED.annual_income,
        credit_score      = EXCLUDED.credit_score,
        updated_at        = NOW();

INSERT INTO staging.etl_run_log (step_name, rows_loaded, status)
VALUES ('dim_customer', (SELECT COUNT(*) FROM warehouse.dim_customer), 'SUCCESS');


-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 4: Load Fact: fact_loan
-- ─────────────────────────────────────────────────────────────────────────────
WITH enriched_loans AS (
    SELECT
        TRIM(rl.loan_id)                                    AS loan_id,
        dc.customer_key,
        dlp.product_key,
        dr.region_key,
        TO_CHAR(NULLIF(rl.issue_date,'')::DATE, 'YYYYMMDD')::INT         AS issue_date_key,
        TO_CHAR(NULLIF(rl.maturity_date,'')::DATE, 'YYYYMMDD')::INT      AS maturity_date_key,
        NULLIF(rl.principal_amount, '')::NUMERIC(18,2)                    AS principal_amount,
        NULLIF(rl.interest_rate, '')::NUMERIC(5,2)                        AS interest_rate,
        NULLIF(rl.tenure_months, '')::SMALLINT                            AS tenure_months,
        NULLIF(rl.outstanding_balance, '')::NUMERIC(18,2)                 AS outstanding_balance,
        UPPER(TRIM(rl.loan_status))                                       AS loan_status,
        COALESCE(NULLIF(rl.days_past_due, '')::SMALLINT, 0)              AS days_past_due,
        -- Derived KPI flags
        COALESCE(NULLIF(rl.days_past_due,'')::SMALLINT, 0) > 90          AS is_npl,
        COALESCE(NULLIF(rl.days_past_due,'')::SMALLINT, 0) BETWEEN 30 AND 89 AS is_par30
    FROM staging.raw_loans rl
    INNER JOIN warehouse.dim_customer  dc  ON dc.customer_id = TRIM(rl.customer_id) AND dc.is_current
    INNER JOIN warehouse.dim_loan_product dlp ON dlp.product_code = UPPER(TRIM(rl.product_code))
    INNER JOIN warehouse.dim_customer dc2     ON dc2.customer_id  = TRIM(rl.customer_id)
    -- Join to region via customer city (denormalise)
    LEFT  JOIN (
        SELECT DISTINCT customer_id, region_key
        FROM warehouse.dim_customer dcc
        INNER JOIN staging.raw_customers src ON src.customer_id = dcc.customer_id
        INNER JOIN warehouse.dim_region dr2   ON dr2.region_id = MD5(LOWER(TRIM(src.city))||'|'||LOWER(TRIM(src.state)))
        WHERE dcc.is_current
    ) reg ON reg.customer_id = TRIM(rl.customer_id)
    WHERE TRIM(rl.loan_id) IS NOT NULL
),
final_loans AS (
    SELECT *,
        -- Compute monthly installment (EMI formula)
        CASE
            WHEN interest_rate > 0 AND tenure_months > 0 THEN
                ROUND(
                    principal_amount *
                    (interest_rate / 1200) *
                    POWER(1 + interest_rate/1200, tenure_months) /
                    (POWER(1 + interest_rate/1200, tenure_months) - 1),
                2)
            ELSE ROUND(principal_amount / NULLIF(tenure_months,0), 2)
        END AS monthly_installment
    FROM enriched_loans
)
INSERT INTO warehouse.fact_loan (
    loan_id, customer_key, product_key, region_key,
    issue_date_key, maturity_date_key,
    principal_amount, interest_rate, tenure_months,
    monthly_installment, outstanding_balance,
    loan_status, days_past_due, is_npl, is_par30
)
SELECT
    loan_id, customer_key, product_key, COALESCE(region_key, 1),
    issue_date_key, maturity_date_key,
    principal_amount, interest_rate, tenure_months,
    monthly_installment, outstanding_balance,
    loan_status, days_past_due, is_npl, is_par30
FROM final_loans
ON CONFLICT (loan_id) DO UPDATE
    SET outstanding_balance = EXCLUDED.outstanding_balance,
        loan_status         = EXCLUDED.loan_status,
        days_past_due       = EXCLUDED.days_past_due,
        is_npl              = EXCLUDED.is_npl,
        is_par30            = EXCLUDED.is_par30,
        updated_at          = NOW();

INSERT INTO staging.etl_run_log (step_name, rows_loaded, status)
VALUES ('fact_loan', (SELECT COUNT(*) FROM warehouse.fact_loan), 'SUCCESS');


-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 5: Load Fact: fact_transaction  (with anomaly scoring)
-- ─────────────────────────────────────────────────────────────────────────────
WITH txn_stats AS (
    -- Compute per-customer rolling stats for anomaly baseline
    SELECT
        customer_id,
        AVG(NULLIF(amount,'')::NUMERIC)    AS avg_txn_amount,
        STDDEV(NULLIF(amount,'')::NUMERIC) AS stddev_txn_amount
    FROM staging.raw_transactions
    GROUP BY customer_id
),
enriched_txns AS (
    SELECT
        TRIM(rt.transaction_id)                                           AS transaction_id,
        dc.customer_key,
        COALESCE(fl.loan_key, NULL)                                       AS loan_key,
        dr.region_key,
        TO_CHAR(NULLIF(rt.transaction_date,'')::DATE, 'YYYYMMDD')::INT   AS txn_date_key,
        UPPER(TRIM(rt.transaction_type))                                  AS transaction_type,
        NULLIF(rt.amount, '')::NUMERIC(18,2)                              AS amount,
        COALESCE(rt.currency, 'USD')                                      AS currency,
        COALESCE(NULLIF(rt.fee_amount,'')::NUMERIC(10,2), 0)             AS fee_amount,
        -- Z-score based anomaly detection
        CASE
            WHEN ts.stddev_txn_amount > 0
            THEN ABS(NULLIF(rt.amount,'')::NUMERIC - ts.avg_txn_amount) / ts.stddev_txn_amount
            ELSE 0
        END                                                               AS z_score
    FROM staging.raw_transactions rt
    INNER JOIN warehouse.dim_customer   dc  ON dc.customer_id = TRIM(rt.customer_id) AND dc.is_current
    INNER JOIN warehouse.dim_region     dr  ON dr.region_id   = MD5(LOWER(TRIM(rt.city))||'|'||LOWER(TRIM(rt.state)))
    LEFT  JOIN warehouse.fact_loan      fl  ON fl.loan_id     = TRIM(rt.loan_id)
    LEFT  JOIN txn_stats                ts  ON ts.customer_id = TRIM(rt.customer_id)
    WHERE TRIM(rt.transaction_id) IS NOT NULL
),
scored_txns AS (
    SELECT *,
        -- Normalise Z-score to 0-1 anomaly score
        1 - EXP(-z_score / 3.0)                         AS anomaly_score,
        (z_score > 3.0)                                  AS is_anomaly,
        CASE
            WHEN z_score > 3.0 THEN 'High-value outlier (Z > 3σ)'
            ELSE NULL
        END                                              AS anomaly_reason
    FROM enriched_txns
)
INSERT INTO warehouse.fact_transaction (
    transaction_id, customer_key, region_key, txn_date_key, loan_key,
    transaction_type, amount, currency, fee_amount,
    is_anomaly, anomaly_score, anomaly_reason
)
SELECT
    transaction_id, customer_key, region_key, txn_date_key, loan_key,
    transaction_type, amount, currency, fee_amount,
    is_anomaly, anomaly_score::NUMERIC(5,4), anomaly_reason
FROM scored_txns
ON CONFLICT (transaction_id) DO NOTHING;

INSERT INTO staging.etl_run_log (step_name, rows_loaded, status)
VALUES ('fact_transaction', (SELECT COUNT(*) FROM warehouse.fact_transaction), 'SUCCESS');

COMMIT;
