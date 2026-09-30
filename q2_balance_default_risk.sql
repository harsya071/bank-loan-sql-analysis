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