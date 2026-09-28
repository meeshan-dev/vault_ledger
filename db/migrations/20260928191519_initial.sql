-- migrate:up
CREATE TYPE transaction_type_enum AS ENUM ('DEPOSIT', 'WITHDRAWAL', 'FEE');

CREATE TABLE accounts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL,
    owner_name TEXT NOT NULL,
    balance NUMERIC(13, 2) NOT NULL DEFAULT 0.00,
    is_active BOOLEAN NOT NULL DEFAULT true
);

CREATE TABLE transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    amount NUMERIC(13, 2) NOT NULL,
    transaction_type transaction_type_enum NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

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

CREATE INDEX transactions_account_id_created_at ON transactions(account_id, created_at DESC);
CREATE INDEX accounts_id ON accounts (id) WHERE is_active = true;

CREATE OR REPLACE FUNCTION withdrawal_validation()
RETURNS TRIGGER AS $$
DECLARE
    acc accounts%ROWTYPE;
    fee NUMERIC(13, 2);
BEGIN
    -- Exit early if the transaction is not a withdrawal (Prevents infinite re-entrancy loops)
    IF NEW.transaction_type != 'WITHDRAWAL' THEN
        RETURN NEW;
    END IF;
    
    SELECT * INTO acc FROM accounts WHERE id = NEW.account_id FOR UPDATE;

    IF acc.id IS NULL THEN
        RAISE EXCEPTION 'Target account does not exist' USING ERRCODE = 'foreign_key_violation';
    END IF;

    IF NEW.amount > acc.balance THEN
        RAISE EXCEPTION 'Insufficient funds for withdrawal' USING CONDITION = 'check_violation';
    END IF;

    fee := ROUND((1.5 / 100) * NEW.amount, 2);
    
    INSERT INTO transactions (account_id, amount, transaction_type)
    VALUES (NEW.account_id, fee, 'FEE');

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_withdrawal_validation
BEFORE INSERT ON transactions
FOR EACH ROW
EXECUTE FUNCTION withdrawal_validation();

CREATE OR REPLACE FUNCTION modify_balance()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.transaction_type = 'WITHDRAWAL' THEN
        UPDATE accounts
        SET balance = balance - NEW.amount
        WHERE id = NEW.account_id;
        
    ELSIF NEW.transaction_type = 'DEPOSIT' THEN
        UPDATE accounts
        SET balance = balance + NEW.amount
        WHERE id = NEW.account_id;
        
    ELSIF NEW.transaction_type = 'FEE' THEN
        UPDATE accounts
        SET balance = balance - NEW.amount
        WHERE id = NEW.account_id;
        
    ELSE
        RAISE EXCEPTION 'unsupported transaction_type: %', NEW.transaction_type;
    END IF; 

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_modify_balance
AFTER INSERT ON transactions
FOR EACH ROW
EXECUTE FUNCTION modify_balance();

-- migrate:down