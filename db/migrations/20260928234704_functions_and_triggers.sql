-- migrate:up

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

DROP FUNCTION IF EXISTS withdrawal_validation;
DROP TRIGGER IF EXISTS trg_withdrawal_validation;
DROP FUNCTION IF EXISTS modify_balance;
DROP TRIGGER IF EXISTS trg_modify_balance;
