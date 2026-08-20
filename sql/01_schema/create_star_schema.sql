-- =============================================================================
-- Fin-Guard Analytics – Star Schema DDL
-- File   : 01_schema/create_star_schema.sql
-- Purpose: Create the complete star schema including dimension tables,
--          fact tables, indexes, and audit columns.
-- =============================================================================

-- ─── Extensions ──────────────────────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";   -- fuzzy text search

-- ─── Schema ──────────────────────────────────────────────────────────────────
CREATE SCHEMA IF NOT EXISTS staging;    -- raw ingested data
CREATE SCHEMA IF NOT EXISTS warehouse;  -- cleaned star schema
CREATE SCHEMA IF NOT EXISTS reporting;  -- KPI views & materialized views

-- =============================================================================
-- DIMENSION TABLES
-- =============================================================================

-- dim_date: Pre-generated calendar dimension
CREATE TABLE IF NOT EXISTS warehouse.dim_date (
    date_key        INTEGER PRIMARY KEY,          -- YYYYMMDD
    full_date       DATE        NOT NULL UNIQUE,
    day_of_week     SMALLINT,                     -- 1=Mon … 7=Sun
    day_name        VARCHAR(10),
    day_of_month    SMALLINT,
    day_of_year     SMALLINT,
    week_of_year    SMALLINT,
    month_num       SMALLINT,
    month_name      VARCHAR(10),
    quarter         SMALLINT,
    year            SMALLINT,
    is_weekend      BOOLEAN DEFAULT FALSE,
    is_holiday      BOOLEAN DEFAULT FALSE,
    fiscal_period   VARCHAR(7)                    -- e.g. "FY24Q1"
);

-- Populate dim_date for 2018-01-01 → 2030-12-31
INSERT INTO warehouse.dim_date
SELECT
    TO_CHAR(d, 'YYYYMMDD')::INTEGER  AS date_key,
    d                                AS full_date,
    EXTRACT(ISODOW  FROM d)          AS day_of_week,
    TO_CHAR(d, 'Day')                AS day_name,
    EXTRACT(DAY     FROM d)          AS day_of_month,
    EXTRACT(DOY     FROM d)          AS day_of_year,
    EXTRACT(WEEK    FROM d)          AS week_of_year,
    EXTRACT(MONTH   FROM d)          AS month_num,
    TO_CHAR(d, 'Month')              AS month_name,
    EXTRACT(QUARTER FROM d)          AS quarter,
    EXTRACT(YEAR    FROM d)          AS year,
    EXTRACT(ISODOW  FROM d) IN (6,7) AS is_weekend,
    FALSE                            AS is_holiday,
    'FY' || TO_CHAR(d, 'YY') || 'Q' || EXTRACT(QUARTER FROM d)::TEXT AS fiscal_period
FROM generate_series('2018-01-01'::DATE, '2030-12-31'::DATE, '1 day') AS g(d)
ON CONFLICT DO NOTHING;


-- dim_customer: One row per unique customer
CREATE TABLE IF NOT EXISTS warehouse.dim_customer (
    customer_key        SERIAL PRIMARY KEY,
    customer_id         VARCHAR(50)  NOT NULL UNIQUE,
    first_name          VARCHAR(100),
    last_name           VARCHAR(100),
    date_of_birth       DATE,
    age                 SMALLINT GENERATED ALWAYS AS
                            (EXTRACT(YEAR FROM AGE(date_of_birth))::SMALLINT) STORED,
    gender              CHAR(1),                  -- M / F / O
    email               VARCHAR(255),
    phone               VARCHAR(30),
    employment_status   VARCHAR(50),
    annual_income       NUMERIC(15, 2),
    credit_score        SMALLINT,
    risk_tier           VARCHAR(20)               -- LOW / MEDIUM / HIGH / CRITICAL
                        GENERATED ALWAYS AS (
                            CASE
                                WHEN credit_score >= 750 THEN 'LOW'
                                WHEN credit_score >= 650 THEN 'MEDIUM'
                                WHEN credit_score >= 550 THEN 'HIGH'
                                ELSE 'CRITICAL'
                            END
                        ) STORED,
    -- SCD Type 2 columns
    effective_date      DATE         NOT NULL DEFAULT CURRENT_DATE,
    expiry_date         DATE         NOT NULL DEFAULT '9999-12-31',
    is_current          BOOLEAN      NOT NULL DEFAULT TRUE,
    -- Audit
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);


-- dim_region: Geographic hierarchy
CREATE TABLE IF NOT EXISTS warehouse.dim_region (
    region_key      SERIAL PRIMARY KEY,
    region_id       VARCHAR(20)  NOT NULL UNIQUE,
    city            VARCHAR(100),
    state           VARCHAR(100),
    country         VARCHAR(100),
    country_code    CHAR(3),
    latitude        NUMERIC(9, 6),
    longitude       NUMERIC(9, 6),
    region_tier     VARCHAR(20)   -- URBAN / SEMI-URBAN / RURAL
);


-- dim_loan_product: Loan product catalogue
CREATE TABLE IF NOT EXISTS warehouse.dim_loan_product (
    product_key         SERIAL PRIMARY KEY,
    product_code        VARCHAR(30) NOT NULL UNIQUE,
    product_name        VARCHAR(100),
    category            VARCHAR(50),   -- PERSONAL / MORTGAGE / AUTO / SME / STUDENT
    sub_category        VARCHAR(50),
    interest_rate_min   NUMERIC(5, 2),
    interest_rate_max   NUMERIC(5, 2),
    min_tenure_months   SMALLINT,
    max_tenure_months   SMALLINT,
    is_secured          BOOLEAN DEFAULT FALSE,
    collateral_type     VARCHAR(50)
);


-- =============================================================================
-- FACT TABLES
-- =============================================================================

-- fact_loan: One row per loan issuance
CREATE TABLE IF NOT EXISTS warehouse.fact_loan (
    loan_key            BIGSERIAL    PRIMARY KEY,
    loan_id             VARCHAR(50)  NOT NULL UNIQUE,
    -- Foreign keys
    customer_key        INT          NOT NULL REFERENCES warehouse.dim_customer(customer_key),
    product_key         INT          NOT NULL REFERENCES warehouse.dim_loan_product(product_key),
    region_key          INT          NOT NULL REFERENCES warehouse.dim_region(region_key),
    issue_date_key      INT          NOT NULL REFERENCES warehouse.dim_date(date_key),
    maturity_date_key   INT                   REFERENCES warehouse.dim_date(date_key),
    -- Measures
    principal_amount    NUMERIC(18, 2) NOT NULL,
    interest_rate       NUMERIC(5, 2)  NOT NULL,
    tenure_months       SMALLINT       NOT NULL,
    monthly_installment NUMERIC(15, 2),
    outstanding_balance NUMERIC(18, 2),
    total_interest      NUMERIC(18, 2),
    -- Status
    loan_status         VARCHAR(30)    NOT NULL,   -- ACTIVE / CLOSED / DEFAULTED / RESTRUCTURED
    days_past_due       SMALLINT       NOT NULL DEFAULT 0,
    is_npl              BOOLEAN        NOT NULL DEFAULT FALSE,  -- Non-Performing Loan
    is_par30            BOOLEAN        NOT NULL DEFAULT FALSE,  -- Past 30 days
    -- Audit
    created_at          TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ    NOT NULL DEFAULT NOW()
);


-- fact_transaction: One row per financial transaction
CREATE TABLE IF NOT EXISTS warehouse.fact_transaction (
    txn_key             BIGSERIAL    PRIMARY KEY,
    transaction_id      VARCHAR(60)  NOT NULL UNIQUE,
    -- Foreign keys
    customer_key        INT          NOT NULL REFERENCES warehouse.dim_customer(customer_key),
    region_key          INT          NOT NULL REFERENCES warehouse.dim_region(region_key),
    txn_date_key        INT          NOT NULL REFERENCES warehouse.dim_date(date_key),
    loan_key            BIGINT                REFERENCES warehouse.fact_loan(loan_key),
    -- Measures
    transaction_type    VARCHAR(50)  NOT NULL,  -- REPAYMENT / DISBURSEMENT / TRANSFER / WITHDRAWAL / DEPOSIT
    amount              NUMERIC(18, 2) NOT NULL,
    currency            CHAR(3)      NOT NULL DEFAULT 'USD',
    fee_amount          NUMERIC(10, 2) DEFAULT 0,
    -- Anomaly detection
    is_anomaly          BOOLEAN      NOT NULL DEFAULT FALSE,
    anomaly_score       NUMERIC(5, 4),          -- 0.0 – 1.0
    anomaly_reason      VARCHAR(255),
    -- Audit
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);


-- =============================================================================
-- INDEXES
-- =============================================================================

-- Fact loan indexes
CREATE INDEX IF NOT EXISTS idx_loan_customer     ON warehouse.fact_loan(customer_key);
CREATE INDEX IF NOT EXISTS idx_loan_product      ON warehouse.fact_loan(product_key);
CREATE INDEX IF NOT EXISTS idx_loan_region       ON warehouse.fact_loan(region_key);
CREATE INDEX IF NOT EXISTS idx_loan_issue_date   ON warehouse.fact_loan(issue_date_key);
CREATE INDEX IF NOT EXISTS idx_loan_status       ON warehouse.fact_loan(loan_status);
CREATE INDEX IF NOT EXISTS idx_loan_is_npl       ON warehouse.fact_loan(is_npl) WHERE is_npl = TRUE;
CREATE INDEX IF NOT EXISTS idx_loan_is_par30     ON warehouse.fact_loan(is_par30) WHERE is_par30 = TRUE;

-- Fact transaction indexes
CREATE INDEX IF NOT EXISTS idx_txn_customer      ON warehouse.fact_transaction(customer_key);
CREATE INDEX IF NOT EXISTS idx_txn_date          ON warehouse.fact_transaction(txn_date_key);
CREATE INDEX IF NOT EXISTS idx_txn_type          ON warehouse.fact_transaction(transaction_type);
CREATE INDEX IF NOT EXISTS idx_txn_anomaly       ON warehouse.fact_transaction(is_anomaly) WHERE is_anomaly = TRUE;

-- Customer indexes
CREATE INDEX IF NOT EXISTS idx_cust_id           ON warehouse.dim_customer(customer_id);
CREATE INDEX IF NOT EXISTS idx_cust_risk_tier    ON warehouse.dim_customer(risk_tier);
CREATE INDEX IF NOT EXISTS idx_cust_is_current   ON warehouse.dim_customer(is_current) WHERE is_current = TRUE;
