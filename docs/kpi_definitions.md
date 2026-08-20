# Fin-Guard Analytics – KPI Definitions

## 1. Portfolio at Risk – PAR-30

| Property | Value |
|---------|-------|
| **Definition** | Percentage of the outstanding loan portfolio that is 30+ days past due |
| **Formula** | `(Sum of outstanding balance with DPD ≥ 30) / (Total outstanding balance) × 100` |
| **Source View** | `reporting.vw_par30` |
| **Alert Threshold** | **5.0%** |
| **Severity: CRITICAL** | > 7.5% |
| **International Standard** | CGAP / World Bank SEEP Framework |

---

## 2. 30-Day Loan Default Rate

| Property | Value |
|---------|-------|
| **Definition** | Monthly ratio of loans that moved to DEFAULTED status |
| **Formula** | `(Count of loans defaulted in month) / (Count of loans issued in month) × 100` |
| **Source View** | `reporting.vw_default_rate` |
| **Alert Threshold** | **3.0%** |
| **Severity: CRITICAL** | > 4.5% |
| **Note** | Tracked as both count-based and amount-based rates |

---

## 3. Non-Performing Loan (NPL) Ratio

| Property | Value |
|---------|-------|
| **Definition** | Percentage of loans 90+ days past due (internationally recognized NPL threshold) |
| **Formula** | `(Count of loans with DPD ≥ 90) / (Total active loans) × 100` |
| **Source View** | `reporting.vw_npl_ratio` |
| **Alert Threshold** | **8.0%** |
| **Severity: CRITICAL** | > 12% |
| **International Standard** | Basel III / IMF Financial Soundness Indicators |

---

## 4. Anomaly Flag Count

| Property | Value |
|---------|-------|
| **Definition** | Daily count of transactions flagged by Z-score anomaly detection (Z > 3σ) |
| **Formula** | `Z-score = |amount - customer_avg_amount| / customer_stddev_amount` |
| **Alert Rule** | Flag when Z > 3.0 |
| **Source View** | `reporting.vw_anomaly_summary` |
| **Alert Threshold** | **50 flags per day** |
| **Anomaly Score** | `1 - exp(-Z/3)` normalized to [0,1] |

---

## 5. Transaction Volume by Region

| Property | Value |
|---------|-------|
| **Definition** | Daily and monthly transaction volume aggregated by city/state/country |
| **Metric** | Total `amount` in USD, count of transactions |
| **Alert Rule** | > 20% day-over-day drop triggers investigation |
| **Source View** | `reporting.vw_txn_volume_by_region` |

---

## 6. Days Past Due (DPD) Buckets

| Bucket | DPD Range | Classification |
|--------|-----------|----------------|
| Current | 0 days | Performing |
| PAR 1-29 | 1–29 days | Watch List |
| PAR 30-59 | 30–59 days | Sub-Standard |
| PAR 60-89 | 60–89 days | Doubtful |
| NPL | 90+ days | Non-Performing |
| Write-off | 180+ days | Write-off Eligible |

---

## 7. Customer Risk Tier

| Tier | Credit Score Range | Treatment |
|------|-------------------|-----------|
| LOW | ≥ 750 | Standard terms |
| MEDIUM | 650–749 | Enhanced monitoring |
| HIGH | 550–649 | Restricted products |
| CRITICAL | < 550 | Collateral required |
