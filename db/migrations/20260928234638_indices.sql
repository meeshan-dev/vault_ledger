-- migrate:up

CREATE INDEX transactions_account_id_created_at ON transactions(account_id, created_at DESC);
CREATE INDEX accounts_id ON accounts (id) WHERE is_active = true;

-- migrate:down

