# Czech Bank Loan Risk Analysis (SQL)

Credit risk analysis on the Berka dataset (1993–1998 Czech bank data) using SQL;
examining where loan portfolio risk concentrates, whether account behavior predicts 
default, and whether debt burden at approval predicts default.

**Data source:** [Hugging Face](https://huggingface.co/datasets/yifanmai/czech_bank_qa/tree/main) 
(`czech_bank.db`) and open it directly in DB Browser for SQLite.

**Tools:** SQLite, DB Browser for SQLite  
**Loan status codes:** A = Finished–OK, B = Finished–Defaulted, C = Running–OK, D = Running–In Debt

---
## Q1: Where is risk concentrated in the loan portfolio?

**Business context:** Before assessing individual loan risk, a portfolio manager needs 
to know where the bank's money is currently sitting across loan outcomes.

**Decision this supports:** Informs which loan segments merit closer monitoring, and 
whether the bank's largest exposures are concentrated in healthy or struggling loans.

```sql
WITH status_summary AS (
SELECT
status,
COUNT(status) AS loan_count,
SUM(amount) AS loan_exposure
FROM loan
GROUP BY status
),
summary_with_total AS (
SELECT 
status,
loan_count,
loan_exposure,
SUM(loan_count) OVER () AS total_loan_all,
SUM(loan_exposure) OVER () AS total_exposure_all
FROM status_summary
)
SELECT 
status,
CASE
			WHEN status  = 'A' THEN 'Finished  - OK'
			WHEN status = 'B' THEN 'Finished - Defaulted'
			WHEN status = 'C' THEN 'Running - OK'
			WHEN status = 'D' THEN 'Running - In Debt'
END AS status_label,
loan_count,
loan_exposure,
ROUND(loan_count * 100.0 / total_loan_all, 2) AS pct_loan,
ROUND(loan_exposure * 100.0 / total_exposure_all, 2) AS pct_exposure
FROM summary_with_total;
```
**Finding:** Loans currently performing well (Running–OK) make up 59.1% of the loan book 
by count and an even higher 66.9% of total exposure, the bank's largest loans skew 
healthy. Loans currently in debt (Running–In Debt) are only 6.6% of loans by count but 
10.9% of exposure, meaning these loans are larger than average; a concentration point 
worth monitoring, since a small number of high value loans carry disproportionate 
dollar risk if they convert to default.

**Caveat:** Exposure is measured as original loan amount granted, not current 
outstanding balance, so it reflects total capital placed at risk over the loan's life, 
not what remains unpaid today.

---

## Q2: Does account balance behavior predict default?

**Business context:** Traditional credit scoring relies on bank's history. Modern 
lenders increasingly ask whether transaction behavior adds predictive signal on its own.

**Decision this supports:** Whether balance based behavioral signals are worth 
incorporating into a risk model alongside (or instead of) bank's data.

```sql
WITH avg_balance AS (
SELECT
account_id,
AVG(balance) AS avg
FROM trans
GROUP BY account_id
)
, bucket AS (
SELECT
account_id,
avg,
NTILE(5) OVER (ORDER BY avg) AS group_balance
FROM avg_balance
)
, loan_outcome AS (
SELECT
account_id,
CASE
			WHEN status = 'B' THEN 1 ELSE 0 END AS is_default
FROM loan
)
, combined AS (
    SELECT
        b.account_id,
        b.avg,
        b.group_balance,
        lo.is_default
    FROM bucket b
    JOIN loan_outcome lo ON b.account_id = lo.account_id
)
SELECT
    group_balance,
    COUNT(*) AS num_accounts,
    SUM(is_default) AS num_defaults,
    ROUND(AVG(is_default) * 100.0, 2) AS default_rate_pct
FROM combined
GROUP BY group_balance
ORDER BY group_balance;
```

**Finding:** Accounts in the lowest balance quintile default at 15.0%, compared to just 
0.41% for the highest balance quintile; roughly a 37x difference. The relationship 
isn't perfectly linear across all five groups (quintile 3 defaults more than quintile 2), 
but the gap between lowest and highest is large and consistent with balance behavior 
carrying real predictive signal beyond what a bureau report alone would show.

**Caveat:** Group sizes are uneven (40 accounts in quintile 1 vs. 246 in quintile 5), 
since accounts with loans skew toward higher balances overall, the 15% figure rests 
on a smaller, noisier sample than the 0.41% figure.

---

## Q3: Does debt-service burden at approval predict default?

**Business context:** A loan can look acceptable on size and term alone, and still be 
unaffordable if the required payment consumes too much of the borrower's regular income.

**Decision this supports:** Whether an affordability check (payment ÷ income) at 
underwriting would catch risk that loan size or term alone would miss.

```sql
WITH credit_account_sum AS (
SELECT 
			account_id,
			SUBSTR(date, 1, 7) AS year_month,
			sum(amount) AS credit_month
FROM trans
WHERE type = 'PRIJEM'
GROUP BY account_id, year_month
), credit_account_average AS (
SELECT 
			account_id,
			ROUND(AVG(credit_month), 2) AS avg_cr_mo
FROM credit_account_sum
GROUP BY account_id
)
,loan_p_sts AS (
SELECT
account_id,
payments,
status
FROM loan
)
, acc_p_avg_sts AS (
SELECT 
			l.account_id,
			l.payments,
			c.avg_cr_mo,
			l.status
FROM loan_p_sts l
JOIN credit_account_average c ON l.account_id = c.account_id
)
, debt_group AS (
SELECT 
			account_id,
			ROUND((payments / avg_cr_mo), 2) AS debt_ratio,
			status,
			CASE 
						WHEN status = 'B' THEN 1 ELSE 0 END AS is_default
FROM acc_p_avg_sts
ORDER BY debt_ratio
)
, debt_quartile AS (
SELECT 
			account_id,
			debt_ratio,
			NTILE (4) OVER(ORDER BY debt_ratio) AS quartile,
			is_default
FROM debt_group
)
, default_quartile AS (
SELECT
			quartile,
			COUNT(*) AS no_account,
			ROUND(AVG(is_default) * 100.0, 2) AS defaulf_pct,
			SUM(is_default) AS default_acc
FROM debt_quartile
GROUP BY quartile
)
SELECT 
			quartile,
			MIN(debt_ratio) AS min_ratio,
			MAX(debt_ratio) AS max_ratio
FROM debt_quartile
GROUP BY quartile;
```

**Finding:** Loans in the top debt-burden quartile (payment to credit ratio ≥ 0.16) 
default at 9.41%, compared to a roughly flat 2.3 – 3.5% across the bottom three quartiles
; a 3 – 4x jump once the ratio crosses 0.16. Unlike balance (from previous question or Q2),
where risk declined gradually across all five groups, debt burden shows a threshold effect:
risk stays stable, then rises sharply past one point. This suggests an affordability cutoff 
could be a useful, simple underwriting rule on its own.

**Caveat:** A small number of top quartile accounts (highest debt-burden) show ratios above 
1.0 (payment exceeding average credit amount), which may reflect income arriving outside the 
tracked account rather than genuine unaffordability, worth investigating before treating 0.16 
as a hard cutoff.

---

## Overall takeaway

Three independent signals; balance level, balance-derived quintiles, and debt-service 
burden, each carry real predictive relationship with default, but with different 
*shapes*: balance risk declines gradually, while debt burden shows a sharp threshold. 
This suggests a risk model combining both would likely outperform either alone, a 
gradual signal (balance) plus a threshold flag (debt ratio ≥ 0.16) catch different 
kinds of risk.

**Option A — prebuilt database (fastest):**
Download the ready-made SQLite file from [Hugging Face](https://huggingface.co/datasets/yifanmai/czech_bank_qa/tree/main) 
(`czech_bank.db`) and open it directly in DB Browser for SQLite.

**Option B — build from source CSVs:**
1. Download CSVs from the [Kaggle mirror](https://www.kaggle.com/datasets/marceloventura/the-berka-dataset)
2. Import into SQLite via DB Browser (`File → Import → Table from CSV`, delimiter `;`)
3. Run queries in `/queries/` against the resulting database