-- migrate:up

CREATE MATERIALIZED VIEW mv_monthly_financial_report AS
SELECT
    a.tenant_id,
    DATE_TRUNC('month', t.created_at) AS report_month,
    COUNT(t.id) AS total_transaction_count,
    SUM(t.amount) FILTER (WHERE t.transaction_type = 'FEE') AS total_fee_revenue
FROM accounts a
JOIN transactions t ON a.id = t.account_id
GROUP BY a.tenant_id, DATE_TRUNC('month', t.created_at)
WITH DATA;

CREATE UNIQUE INDEX mv_monthly_financial_report_pk
ON mv_monthly_financial_report (tenant_id, report_month);

CREATE OR REPLACE PROCEDURE refresh_monthly_report()
AS $$
BEGIN
    COMMIT;  -- end the calling transaction so the refresh can run outside one

    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_monthly_financial_report;

    COMMIT;
END;
$$ LANGUAGE plpgsql;

-- migrate:down

DROP PROCEDURE IF EXISTS refresh_monthly_report();
DROP MATERIALIZED VIEW IF EXISTS mv_monthly_financial_report;