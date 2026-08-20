"""
Fin-Guard Analytics - Synthetic Data Generator
================================================
Generates realistic sample CSV files for:
  - customers.csv
  - loans.csv
  - transactions.csv
  - loan_products.csv

Run: python scripts/generate_sample_data.py
Output goes to: data/raw/
"""

from __future__ import annotations

import csv
import random
import uuid
from datetime import date, timedelta
from pathlib import Path

try:
    import numpy as np
    HAS_NUMPY = True
except ImportError:
    HAS_NUMPY = False

random.seed(42)

OUTPUT_DIR = Path(__file__).parent.parent / "data" / "raw"
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

# --- Config ---
N_CUSTOMERS    = 5_000
N_LOANS        = 12_000
N_TRANSACTIONS = 60_000
START_DATE     = date(2021, 1, 1)
END_DATE       = date(2024, 12, 31)

# --- Reference Data ---
FIRST_NAMES = [
    "James","Mary","John","Patricia","Robert","Jennifer","Michael","Linda",
    "William","Barbara","David","Susan","Richard","Jessica","Joseph","Karen",
    "Thomas","Sarah","Charles","Lisa","Raj","Priya","Ahmad","Fatima",
    "Wei","Mei","Carlos","Maria","Ivan","Olga"
]

LAST_NAMES = [
    "Smith","Johnson","Williams","Brown","Jones","Garcia","Miller","Davis",
    "Wilson","Moore","Taylor","Anderson","Thomas","Jackson","White","Harris",
    "Martin","Thompson","Young","Robinson","Patel","Kumar","Khan","Ahmed",
    "Zhang","Chen","Rodriguez","Martinez","Petrov","Ivanova"
]

CITIES = [
    ("New York",    "New York",    "USA"),
    ("Los Angeles", "California",  "USA"),
    ("Chicago",     "Illinois",    "USA"),
    ("Houston",     "Texas",       "USA"),
    ("Phoenix",     "Arizona",     "USA"),
    ("London",      "England",     "UK"),
    ("Mumbai",      "Maharashtra", "India"),
    ("Delhi",       "Delhi",       "India"),
    ("Toronto",     "Ontario",     "Canada"),
    ("Sydney",      "NSW",         "Australia"),
    ("Singapore",   "Singapore",   "Singapore"),
    ("Dubai",       "Dubai",       "UAE"),
]

EMPLOYMENT = ["Full-time", "Part-time", "Self-employed", "Unemployed", "Retired", "Student"]

LOAN_PRODUCTS = [
    ("PL001", "Personal Loan Standard",  "PERSONAL", "Unsecured",    5.99,  18.99, 12,  60,  False, ""),
    ("PL002", "Personal Loan Premium",   "PERSONAL", "Unsecured",    4.50,  12.99, 12,  84,  False, ""),
    ("ML001", "Home Mortgage 30Y",       "MORTGAGE", "Fixed Rate",   3.25,   6.75, 120, 360, True,  "Real Estate"),
    ("ML002", "Home Mortgage 15Y",       "MORTGAGE", "Fixed Rate",   2.99,   5.99, 60,  180, True,  "Real Estate"),
    ("AL001", "Auto Loan Standard",      "AUTO",     "Secured",      4.99,  14.99, 24,  72,  True,  "Vehicle"),
    ("SB001", "SME Business Loan",       "SME",      "Working Cap",  7.99,  22.99, 12,  60,  False, ""),
    ("SB002", "SME Equipment Finance",   "SME",      "Asset Finance",6.50,  18.50, 24,  84,  True,  "Equipment"),
    ("ST001", "Student Loan Federal",    "STUDENT",  "Federal",      4.50,   7.00, 120, 240, False, ""),
]

LOAN_STATUSES = (
    ["ACTIVE"] * 70 + ["CLOSED"] * 15 + ["DEFAULTED"] * 8 + ["RESTRUCTURED"] * 7
)

TXN_TYPES = (
    ["REPAYMENT"] * 50 + ["TRANSFER"] * 20 + ["WITHDRAWAL"] * 15 +
    ["DEPOSIT"] * 10 + ["DISBURSEMENT"] * 5
)


# --- Helpers ---
def rand_date(start: date = START_DATE, end: date = END_DATE) -> date:
    delta = (end - start).days
    return start + timedelta(days=random.randint(0, delta))


def rand_credit_score() -> int:
    if HAS_NUMPY:
        return int(min(850, max(300, int(np.random.normal(680, 80)))))
    return random.randint(300, 850)


def rand_income() -> float:
    if HAS_NUMPY:
        val = np.random.lognormal(mean=11.0, sigma=0.7)
    else:
        import math
        val = math.exp(11.0 + random.gauss(0, 0.7))
    return round(float(val), 2)


def rand_principal() -> float:
    if HAS_NUMPY:
        val = np.random.lognormal(10.5, 1.0)
    else:
        import math
        val = math.exp(10.5 + random.gauss(0, 1.0))
    return round(max(1_000, min(500_000, float(val))), 2)


# --- Generators ---
def generate_loan_products() -> None:
    path = OUTPUT_DIR / "loan_products.csv"
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow([
            "product_code", "product_name", "category", "sub_category",
            "interest_rate_min", "interest_rate_max", "min_tenure_months",
            "max_tenure_months", "is_secured", "collateral_type"
        ])
        for row in LOAN_PRODUCTS:
            w.writerow(row)
    print(f"  Generated {len(LOAN_PRODUCTS)} loan products  =>  {path}")


def generate_customers() -> list[dict]:
    path = OUTPUT_DIR / "customers.csv"
    customers: list[dict] = []
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow([
            "customer_id", "first_name", "last_name", "date_of_birth", "gender",
            "email", "phone", "employment_status", "annual_income", "credit_score",
            "city", "state", "country"
        ])
        for _ in range(N_CUSTOMERS):
            cid    = f"CUST{str(uuid.uuid4().int)[:10]}"
            fn     = random.choice(FIRST_NAMES)
            ln     = random.choice(LAST_NAMES)
            dob    = rand_date(date(1950, 1, 1), date(2000, 12, 31))
            gender = random.choice(["M", "F", "O"])
            email  = f"{fn.lower()}.{ln.lower()}{random.randint(1,9999)}@email.com"
            phone  = f"+1-{random.randint(200,999)}-{random.randint(100,999)}-{random.randint(1000,9999)}"
            emp    = random.choice(EMPLOYMENT)
            income = rand_income()
            score  = rand_credit_score()
            city, state, country = random.choice(CITIES)
            w.writerow([cid, fn, ln, dob, gender, email, phone, emp, income, score,
                        city, state, country])
            customers.append({"customer_id": cid, "city": city, "state": state})
    print(f"  Generated {N_CUSTOMERS:,} customers          =>  {path}")
    return customers


def generate_loans(customers: list[dict]) -> list[dict]:
    path = OUTPUT_DIR / "loans.csv"
    loans: list[dict] = []
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow([
            "loan_id", "customer_id", "product_code", "issue_date", "maturity_date",
            "principal_amount", "interest_rate", "tenure_months", "loan_status",
            "days_past_due", "outstanding_balance"
        ])
        for _ in range(N_LOANS):
            cust      = random.choice(customers)
            product   = random.choice(LOAN_PRODUCTS)
            lid       = f"LOAN{str(uuid.uuid4().int)[:12]}"
            issue     = rand_date()
            tenure    = random.randint(product[6], product[7])
            maturity  = issue + timedelta(days=tenure * 30)
            principal = rand_principal()
            rate      = round(random.uniform(product[4], product[5]), 2)
            status    = random.choice(LOAN_STATUSES)
            dpd       = 0
            if status == "DEFAULTED":
                dpd = random.randint(90, 365)
            elif status == "ACTIVE":
                dpd = random.choices(
                    population=list(range(0, 90)),
                    weights=[85] + [1] * 89,
                    k=1
                )[0]
            outstanding = round(principal * random.uniform(0.1, 1.0), 2) if status != "CLOSED" else 0
            w.writerow([lid, cust["customer_id"], product[0], issue, maturity,
                        principal, rate, tenure, status, dpd, outstanding])
            loans.append({"loan_id": lid, "customer_id": cust["customer_id"],
                          "city": cust["city"], "state": cust["state"]})
    print(f"  Generated {N_LOANS:,} loans              =>  {path}")
    return loans


def generate_transactions(customers: list[dict], loans: list[dict]) -> None:
    path = OUTPUT_DIR / "transactions.csv"
    all_refs = loans if loans else customers
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow([
            "transaction_id", "customer_id", "loan_id", "transaction_date",
            "transaction_type", "amount", "currency", "fee_amount",
            "city", "state", "country"
        ])
        for _ in range(N_TRANSACTIONS):
            tid   = f"TXN{str(uuid.uuid4().int)[:14]}"
            ref   = random.choice(all_refs)
            cust  = ref.get("customer_id", "")
            loan  = ref.get("loan_id", "")
            tdate = rand_date()
            ttype = random.choice(TXN_TYPES)
            # Inject ~3% anomalous high-value transactions
            if random.random() < 0.03:
                amount = round(random.uniform(50_000, 500_000), 2)
            else:
                amount = round(random.uniform(10, 20_000), 2)
            currencies = ["USD"] * 80 + ["GBP", "EUR", "INR", "AED", "CAD", "AUD"] * 4
            currency = random.choice(currencies)
            fee      = round(amount * random.uniform(0.001, 0.02), 2)
            city     = ref.get("city", "New York")
            state    = ref.get("state", "New York")
            country  = "USA"
            w.writerow([tid, cust, loan, tdate, ttype, amount, currency, fee,
                        city, state, country])
    print(f"  Generated {N_TRANSACTIONS:,} transactions     =>  {path}")


# --- Main ---
if __name__ == "__main__":
    print("\n Fin-Guard Analytics - Generating sample data...\n")
    generate_loan_products()
    customers = generate_customers()
    loans     = generate_loans(customers)
    generate_transactions(customers, loans)
    print(f"\n All files written to: {OUTPUT_DIR.resolve()}\n")
