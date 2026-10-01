WITH avg_balance AS (
	SELECT
	account_id,
	AVG(balance) AS avg_bal
	FROM trans
	GROUP BY account_id
)
, quintile AS (
	SELECT
	account_id,
	avg_bal,
	NTILE(5) OVER (ORDER BY avg_bal) AS balance_quintile
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
        q.account_id,
        q.avg_bal,
        q.balance_quintile,
        lo.is_default
    FROM quintile q
    JOIN loan_outcome lo ON q.account_id = lo.account_id
)
SELECT
    balance_quintile,
    COUNT(*) AS num_accounts,
    SUM(is_default) AS num_defaults,
    ROUND(AVG(is_default) * 100.0, 2) AS default_rate_pct
FROM combined
GROUP BY balance_quintile
ORDER BY balance_quintile;
