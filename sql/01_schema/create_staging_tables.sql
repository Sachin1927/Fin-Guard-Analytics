-- =============================================================================
-- Fin-Guard Analytics – Staging Schema DDL
-- File   : 01_schema/create_staging_tables.sql
-- Purpose: Raw ingestion tables that mirror the CSV structure.
--          Data lands here first, then ETL promotes to warehouse schema.
-- =============================================================================

-- ─── Raw Customers ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS staging.raw_customers (
    customer_id         TEXT,
    first_name          TEXT,
    last_name           TEXT,
    date_of_birth       TEXT,
    gender              TEXT,
    email               TEXT,
    phone               TEXT,
    employment_status   TEXT,
    annual_income       TEXT,
    credit_score        TEXT,
    city                TEXT,
    state               TEXT,
    country             TEXT,
    _ingested_at        TIMESTAMPTZ DEFAULT NOW(),
    _source_file        TEXT
);

-- ─── Raw Loans ───────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS staging.raw_loans (
    loan_id             TEXT,
    customer_id         TEXT,
    product_code        TEXT,
    issue_date          TEXT,
    maturity_date       TEXT,
    principal_amount    TEXT,
    interest_rate       TEXT,
    tenure_months       TEXT,
    loan_status         TEXT,
    days_past_due       TEXT,
    outstanding_balance TEXT,
    _ingested_at        TIMESTAMPTZ DEFAULT NOW(),
    _source_file        TEXT
);

-- ─── Raw Transactions ────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS staging.raw_transactions (
    transaction_id      TEXT,
    customer_id         TEXT,
    loan_id             TEXT,
    transaction_date    TEXT,
    transaction_type    TEXT,
    amount              TEXT,
    currency            TEXT,
    fee_amount          TEXT,
    city                TEXT,
    state               TEXT,
    country             TEXT,
    _ingested_at        TIMESTAMPTZ DEFAULT NOW(),
    _source_file        TEXT
);

-- ─── Raw Loan Products ───────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS staging.raw_loan_products (
    product_code            TEXT,
    product_name            TEXT,
    category                TEXT,
    sub_category            TEXT,
    interest_rate_min       TEXT,
    interest_rate_max       TEXT,
    min_tenure_months       TEXT,
    max_tenure_months       TEXT,
    is_secured              TEXT,
    collateral_type         TEXT,
    _ingested_at            TIMESTAMPTZ DEFAULT NOW(),
    _source_file            TEXT
);

-- ─── ETL Run Log ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS staging.etl_run_log (
    run_id          SERIAL PRIMARY KEY,
    run_ts          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    step_name       VARCHAR(100),
    rows_extracted  INT,
    rows_rejected   INT,
    rows_loaded     INT,
    duration_ms     INT,
    status          VARCHAR(20),   -- SUCCESS / FAILED / PARTIAL
    error_msg       TEXT
);
