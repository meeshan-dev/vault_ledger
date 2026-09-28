-- migrate:up

ALTER TABLE accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE transactions ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation_accounts
ON accounts
FOR ALL
USING (tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::uuid)
WITH CHECK (tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::uuid);

CREATE POLICY tenant_isolation_transactions
ON transactions
FOR ALL
USING (
    account_id IN (
        SELECT id
        FROM accounts
        WHERE tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::uuid
    )
);

-- migrate:down

