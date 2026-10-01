WITH monthly_credits AS (
    SELECT
        account_id,
        SUBSTR(date, 1, 7) AS year_month,
        SUM(amount)        AS credit_month
    FROM trans
    WHERE type = 'PRIJEM'          -- credit transactions
    GROUP BY account_id, year_month
),
avg_credits AS (
    SELECT
        account_id,
        ROUND(AVG(credit_month), 2) AS avg_monthly_credit
    FROM monthly_credits
    GROUP BY account_id
),
loan_ratio AS (
    SELECT
        l.account_id,
        ROUND(l.payments / a.avg_monthly_credit, 2) AS pti_ratio,
        CASE WHEN l.status = 'B' THEN 1 ELSE 0 END  AS is_default
    FROM loan l
    JOIN avg_credits a ON l.account_id = a.account_id
),
ratio_quartile AS (
    SELECT
        account_id,
        pti_ratio,
        NTILE(4) OVER (ORDER BY pti_ratio) AS quartile,
        is_default
    FROM loan_ratio
)
SELECT
    quartile,
    COUNT(*)                          AS num_accounts,
    SUM(is_default)                   AS num_defaults,
    ROUND(AVG(is_default) * 100.0, 2) AS default_rate_pct,
    MIN(pti_ratio)                    AS min_ratio,
    MAX(pti_ratio)                    AS max_ratio
FROM ratio_quartile
GROUP BY quartile
ORDER BY quartile;
