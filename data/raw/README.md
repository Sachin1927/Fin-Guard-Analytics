# Raw Data Directory

Place raw CSV files from Kaggle or BigQuery here before running ETL.

## Expected Files
- `customers.csv`        – Customer demographics & credit scores
- `loans.csv`            – Loan issuances with status & DPD
- `transactions.csv`     – Financial transactions
- `loan_products.csv`    – Product catalogue

## Data Sources
- **Kaggle**: https://www.kaggle.com/datasets/sgpjesus/bank-account-fraud-dataset-neurips-2022
- **Alternative**: https://www.kaggle.com/datasets/laotse/credit-risk-dataset
- **Synthetic**: Run `python scripts/generate_sample_data.py` to generate 5K/12K/60K rows

## Column Requirements
See `sql/01_schema/create_staging_tables.sql` for exact column names expected.
