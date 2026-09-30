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