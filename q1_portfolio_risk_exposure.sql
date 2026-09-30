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
