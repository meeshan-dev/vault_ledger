-- migrate:up

CREATE VIEW account_summaries_view AS
WITH totals AS (
    SELECT
        account_id,
        SUM(amount) FILTER (WHERE transaction_type = 'DEPOSIT')    AS total_deposits,
        SUM(amount) FILTER (WHERE transaction_type = 'WITHDRAWAL') AS total_withdrawals
    FROM transactions
    GROUP BY account_id
)
SELECT
    acc.*,
    COALESCE(t.total_deposits, 0.00)    AS total_deposits,
    COALESCE(t.total_withdrawals, 0.00) AS total_withdrawals
FROM accounts acc
LEFT JOIN totals t ON t.account_id = acc.id;

CREATE OR REPLACE FUNCTION update_account_summary()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO accounts (tenant_id, owner_name, is_active, balance)
    VALUES (NEW.tenant_id, NEW.owner_name, NEW.is_active, NEW.balance)
    RETURNING id INTO NEW.account_id;

    IF NEW.balance IS NOT NULL AND NEW.balance > 0 THEN
        INSERT INTO transactions (account_id, amount, transaction_type)
        VALUES (NEW.account_id, NEW.balance, 'DEPOSIT');
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_account_summaries_view
INSTEAD OF INSERT ON account_summaries_view
FOR EACH ROW
EXECUTE FUNCTION update_account_summary();

-- migrate:down

DROP TRIGGER IF EXISTS update_account_summaries_view ON account_summaries_view;
DROP FUNCTION IF EXISTS update_account_summary();
DROP VIEW IF EXISTS account_summaries_view;