CREATE TABLE users (
    user_id SERIAL PRIMARY KEY,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    gender VARCHAR(5) CHECK (gender IN ('Nam', 'Nữ', 'Khác')),
    birthday DATE CHECK (birthday <= CURRENT_DATE),
    email VARCHAR(150) UNIQUE NOT NULL,
    phone VARCHAR(10) UNIQUE NOT NULL,
    payment_method VARCHAR(50) NOT NULL,
    password VARCHAR(256) NOT NULL
);

CREATE TABLE accounts (
    account_id SERIAL PRIMARY KEY,
    user_id INT REFERENCES users(user_id) ON DELETE CASCADE,
    account_type VARCHAR(50) CHECK (account_type IN ('Cash', 'Margin')) NOT NULL,
    balance NUMERIC(15,2) DEFAULT 0 CHECK (balance >= 0) NOT NULL
);

CREATE TABLE deposits (
    deposit_id SERIAL PRIMARY KEY,
    account_id INT REFERENCES accounts(account_id) ON DELETE CASCADE,
    amount NUMERIC(15,2) CHECK (amount > 0) NOT NULL,
    deposit_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE withdrawals (
    withdrawal_id SERIAL PRIMARY KEY,
    account_id INT REFERENCES accounts(account_id) ON DELETE CASCADE,
    amount NUMERIC(15,2) CHECK (amount > 0) NOT NULL,
    withdrawal_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);


CREATE TABLE companies (
    company_id SERIAL PRIMARY KEY,
    company_name VARCHAR(100) NOT NULL,
    description VARCHAR(500),
    ticker_symbol VARCHAR(50) UNIQUE NOT NULL,
    industry VARCHAR(50) NOT NULL,
    listed_date TIMESTAMP CHECK (listed_date <= CURRENT_DATE),
    head_quarters VARCHAR(255),
    website VARCHAR(255) CHECK (website LIKE 'http://%' OR website LIKE 'https://%')
);

CREATE TABLE companies_archive (
    archive_id SERIAL PRIMARY KEY,
    company_id INT,
    company_name VARCHAR(100),
    description VARCHAR(500),
    ticker_symbol VARCHAR(50),
    industry VARCHAR(50),
    listed_date TIMESTAMP,
    head_quarters VARCHAR(255),
    website VARCHAR(255),
    deleted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);


CREATE TABLE stocks (
    stock_id SERIAL PRIMARY KEY,
    company_id INT REFERENCES companies(company_id) ON DELETE CASCADE,
    total_shares BIGINT DEFAULT 0 CHECK (total_shares >= 0) NOT NULL,
    outstanding_shares BIGINT CHECK (outstanding_shares >= 0 AND outstanding_shares <= total_shares) NOT NULL,
	status VARCHAR(20) CHECK ( status IN ('Listed', 'Delisted', 'Suspended')),
	issue_date TIMESTAMP CHECK (issue_date <= CURRENT_DATE)
);

CREATE TABLE stock_update_logs (
    log_id SERIAL PRIMARY KEY,
    stock_id INT,
    field_changed TEXT,
    old_value TEXT,
    new_value TEXT,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE portfolios (
    portfolios_id SERIAL PRIMARY KEY,
    stock_id INT REFERENCES stocks(stock_id) ON DELETE CASCADE,
    account_id INT REFERENCES accounts(account_id) ON DELETE CASCADE,
    date TIMESTAMP NOT NULL,
    quantity INT CHECK (quantity > 0) NOT NULL,
    average_price DECIMAL(15,2) CHECK (average_price >= 0) NOT NULL
);

CREATE TABLE orders (
    order_id SERIAL PRIMARY KEY,
    account_id INT REFERENCES accounts(account_id) ON DELETE CASCADE,
    stock_id INT REFERENCES stocks(stock_id) ON DELETE CASCADE,
    order_type VARCHAR(4) CHECK (order_type IN ('BUY', 'SELL')) NOT NULL,
    quantity INT CHECK (quantity > 0) NOT NULL,
    price DECIMAL(10,2) CHECK (price > 0) NOT NULL,
    status VARCHAR(20) CHECK (status IN ('Pending', 'Completed', 'Cancelled')) NOT NULL DEFAULT 'Pending',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);


CREATE TABLE transactions (
    transaction_id SERIAL PRIMARY KEY,
    order_id INT REFERENCES orders(order_id) ON DELETE CASCADE,
    executed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE real_time_price (
    stock_id INT  REFERENCES stocks(stock_id) ON DELETE CASCADE,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    current_price DECIMAL CHECK (current_price > 0) NOT NULL,
    bid_price DECIMAL CHECK (bid_price > 0 AND bid_price <= ask_price) NOT NULL,
    ask_price DECIMAL CHECK (ask_price > 0) NOT NULL,
    volume INT CHECK (volume >= 0) NOT NULL,
    bid_volume INT CHECK (bid_volume >= 0) NOT NULL,
    ask_volume INT CHECK (ask_volume >= 0) NOT NULL
);

ALTER TABLE companies ALTER COLUMN description TYPE TEXT;
COPY companies(company_id, company_name, description, ticker_symbol, industry, listed_date, head_quarters, website
)
FROM 'C:\DataPinance\company.csv'
DELIMITER ','
CSV HEADER;
COPY real_time_price(stock_id, timestamp, current_price, bid_price, ask_price, volume, bid_volume, ask_volume
)
FROM 'C:\DataPinance\real_time_price.csv'
DELIMITER ','
CSV HEADER;

-- Xem ràng buộc trên bảng

select company_name, stock_id from companies c join stocks s on c.company_id = s.company_id ;
select * from stocks;

select * from real_time_price

select * from stocks
COPY stocks(stock_id,company_id,total_shares,outstanding_shares,status,issue_date)
FROM 'C:\DataPinance\stocks.csv'
DELIMITER ','
CSV HEADER;

-- UC1: Tạo tài khoản
-- 1. Tạo hàm để tạo account mặc định cho user mới
CREATE OR REPLACE FUNCTION UC1_create_default_account()
RETURNS TRIGGER AS $$
BEGIN
  
  INSERT INTO accounts (user_id, account_type, balance)
  VALUES (NEW.user_id, 'Cash', 0.00);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 2. Gắn trigger vào bảng users
CREATE TRIGGER UC1_trg_create_account_after_user_insert
AFTER INSERT ON users
FOR EACH ROW
EXECUTE FUNCTION UC1_create_default_account();
--- Test 
INSERT INTO users (first_name, last_name, gender, birthday, email, phone, payment_method, password)
VALUES ( 'An', 'Nguyen', 'Nam', '1995-06-01', 'an@example.com', '0912345678', 'Credit Card', 'hashedpass1');

INSERT INTO users (first_name, last_name, gender, birthday, email, phone, payment_method, password)
VALUES ('Linh', 'Tran', 'Nữ', '2000-10-05', 'linh@example.com', '0987654321', 'Bank Transfer', 'hashedpass2');

SELECT u.user_id, u.first_name, a.account_type, a.balance
FROM users u
JOIN accounts a ON u.user_id = a.user_id
ORDER BY u.user_id;

--- UC2 -  nạp tiền
CREATE OR REPLACE FUNCTION UC2_update_balance_after_deposit()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE accounts
    SET balance = balance + NEW.amount
    WHERE account_id = NEW.account_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER UC2_trg_update_balance_after_deposit
AFTER INSERT ON deposits
FOR EACH ROW
EXECUTE FUNCTION UC2_update_balance_after_deposit();
--- test 
SELECT account_id, balance FROM accounts WHERE account_id = 1;
INSERT INTO deposits (account_id, amount) VALUES (1, 500000);
INSERT INTO deposits (account_id, amount) VALUES (1, 100);

--- UC3 - rút tiền
CREATE OR REPLACE FUNCTION UC3_process_withdrawal()
RETURNS TRIGGER AS $$
DECLARE
    current_balance NUMERIC(15,2);
BEGIN
    SELECT balance INTO current_balance
    FROM accounts
    WHERE account_id = NEW.account_id;

    IF NEW.amount > current_balance THEN
        RAISE EXCEPTION 'Số dư không đủ để rút tiền';
    END IF;

    UPDATE accounts
    SET balance = balance - NEW.amount
    WHERE account_id = NEW.account_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER UC3_trg_process_withdrawal
AFTER INSERT ON withdrawals
FOR EACH ROW
EXECUTE FUNCTION UC3_process_withdrawal();

--- test 
SELECT account_id, balance FROM accounts WHERE account_id = 1;
INSERT INTO withdrawals (account_id, amount) VALUES (1, 200000);
INSERT INTO withdrawals (account_id, amount) VALUES (1, 1000);
INSERT INTO withdrawals (account_id, amount) VALUES (1, 99999999);

--- UC4: Xem số dư
CREATE OR REPLACE PROCEDURE UC4_get_account_balance(IN input_account_id INT, OUT current_balance NUMERIC)
LANGUAGE plpgsql
AS $$
BEGIN
    SELECT balance INTO current_balance
    FROM accounts
    WHERE account_id = input_account_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Không tìm thấy tài khoản với ID = %', input_account_id;
    END IF;
END;
$$;


DO $$
DECLARE
  so_du NUMERIC;
BEGIN
  CALL UC4_get_account_balance(1, so_du);
  RAISE NOTICE 'Số dư: %', so_du;
END;
$$;

--- UC10: xem danh mục đầu tư
CREATE OR REPLACE FUNCTION UC10_fn_view_portfolio(input_user_id INT)
RETURNS TABLE (
    account_id INT,
    account_type VARCHAR,
    stock_id INT,
    quantity INT,
    average_price NUMERIC
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        a.account_id,
        a.account_type,
        p.stock_id,
        p.quantity,
        p.average_price
    FROM portfolios p
    JOIN accounts a ON a.account_id = p.account_id
    WHERE a.user_id = input_user_id;
END;
$$;

SELECT * FROM UC10_fn_view_portfolio(1);

--- UC13: thêm công ty
CREATE OR REPLACE FUNCTION UC13_trg_create_default_stock()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO stocks (
        company_id,
        total_shares,
        outstanding_shares,
        status,
        issue_date
    )
    VALUES (
        NEW.company_id,
        1000000,               -- default total shares
        1000000,               -- default outstanding shares
        'Listed',              -- default status
        NEW.listed_date        -- issue_date = listed_date
    );

    RAISE NOTICE 'Đã tự động tạo mã cổ phiếu cho công ty: %', NEW.company_name;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


CREATE TRIGGER UC13_trg_after_company_insert
AFTER INSERT ON companies
FOR EACH ROW
EXECUTE FUNCTION UC13_trg_create_default_stock();

INSERT INTO companies (
    company_name, description, ticker_symbol, industry, listed_date, head_quarters, website
) VALUES (
    'NovaTech Inc.',
    'A tech company focused on AI and automation.',
    'NOVT',
    'Technology',
    CURRENT_DATE,
    'Silicon Valley',
    'https://novatech.com'
);

select * from companies
select * from stocks

--- UC15: Xóa công ty
CREATE OR REPLACE FUNCTION UC15_trg_archive_deleted_company()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO companies_archive (
        company_id,
        company_name,
        description,
        ticker_symbol,
        industry,
        listed_date,
        head_quarters,
        website
    )
    VALUES (
        OLD.company_id,
        OLD.company_name,
        OLD.description,
        OLD.ticker_symbol,
        OLD.industry,
        OLD.listed_date,
        OLD.head_quarters,
        OLD.website
    );

    RAISE NOTICE 'Đã lưu công ty bị xóa vào bảng archive: %', OLD.company_name;

    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER UC15_trg_before_company_delete
BEFORE DELETE ON companies
FOR EACH ROW
EXECUTE FUNCTION UC15_trg_archive_deleted_company();

select * from companies_archive

DELETE FROM companies WHERE company_id = 8;

--- UC16: chỉnh sửa thông tin cổ phiếu
CREATE OR REPLACE FUNCTION UC16_trg_manage_stock_update()
RETURNS TRIGGER AS $$
BEGIN
    -- Không cho chỉnh sửa số lượng nếu trạng thái là Delisted
    IF OLD.status = 'Delisted' AND (
        NEW.total_shares IS DISTINCT FROM OLD.total_shares OR
        NEW.outstanding_shares IS DISTINCT FROM OLD.outstanding_shares
    ) THEN
        RAISE EXCEPTION 'Không thể cập nhật số lượng cổ phiếu vì mã đã bị hủy niêm yết (Delisted).';
    END IF;

    -- Ghi log thay đổi số lượng cổ phiếu
    IF NEW.total_shares IS DISTINCT FROM OLD.total_shares THEN
        INSERT INTO stock_update_logs(stock_id, field_changed, old_value, new_value)
        VALUES (OLD.stock_id, 'total_shares', OLD.total_shares::TEXT, NEW.total_shares::TEXT);
    END IF;

    IF NEW.outstanding_shares IS DISTINCT FROM OLD.outstanding_shares THEN
        INSERT INTO stock_update_logs(stock_id, field_changed, old_value, new_value)
        VALUES (OLD.stock_id, 'outstanding_shares', OLD.outstanding_shares::TEXT, NEW.outstanding_shares::TEXT);
    END IF;

    IF NEW.status IS DISTINCT FROM OLD.status THEN
        INSERT INTO stock_update_logs(stock_id, field_changed, old_value, new_value)
        VALUES (OLD.stock_id, 'status', OLD.status, NEW.status);
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER UC16_trg_before_stock_update
BEFORE UPDATE ON stocks
FOR EACH ROW
EXECUTE FUNCTION UC16_trg_manage_stock_update();

UPDATE stocks
SET total_shares = 2000000000,
    outstanding_shares = 2000000000 -- hoặc giá trị nhỏ hơn
WHERE stock_id = 1;

select * from stocks

---- PHẦN 4 : Bảo mật
-- 4.2. Phân quyền trên cơ sở dữ liệu (CSDL)
--- tạo role
CREATE ROLE admin;
CREATE ROLE trader;
CREATE ROLE analyst;
---- gán quyền cho từng bảng 
--- users
GRANT SELECT, INSERT, UPDATE, DELETE ON users TO admin;

-- accounts
GRANT SELECT, INSERT, UPDATE, DELETE ON accounts TO admin;
GRANT SELECT, UPDATE ON accounts TO trader;
-- deposits, withdrawals
GRANT SELECT, INSERT, DELETE ON deposits TO admin;
GRANT SELECT, INSERT ON deposits TO trader;

GRANT SELECT, INSERT, DELETE ON withdrawals TO admin;
GRANT SELECT, INSERT ON withdrawals TO trader;
--companies, companies_archive
GRANT SELECT, INSERT, UPDATE, DELETE ON companies TO admin;

GRANT SELECT, INSERT, UPDATE, DELETE ON companies_archive TO admin;
---stocks, stock_update_logs
GRANT SELECT, INSERT, UPDATE, DELETE ON stocks TO admin;

GRANT SELECT, INSERT ON stock_update_logs TO admin;
--portfolios
GRANT SELECT, INSERT, UPDATE, DELETE ON portfolios TO admin;

---orders
GRANT SELECT, INSERT, UPDATE, DELETE ON orders TO admin;
GRANT SELECT, INSERT, UPDATE ON orders TO trader;
---transactions
GRANT SELECT, INSERT, DELETE ON transactions TO admin;
GRANT SELECT ON transactions TO trader;

--real_time_price
GRANT SELECT, INSERT, UPDATE ON real_time_price TO admin;

---tạo user
CREATE USER admin1 WITH PASSWORD 'Admin123';
GRANT admin TO admin1;

CREATE USER trader1 WITH PASSWORD 'TraderSecure123';
GRANT trader TO trader1;

CREATE USER analyst1 WITH PASSWORD 'AnalystSecure123';
GRANT analyst TO analyst1;
--- test
SET ROLE trader;
SELECT * FROM users;

SET ROLE analyst;
SELECT stock_id, current_price FROM real_time_price LIMIT 5;

SET ROLE trader;
INSERT INTO orders (account_id, stock_id, order_type, quantity, price)
VALUES (101, 5, 'BUY', 100, 25.50);

----4.3 View
-- view: v_stocks
CREATE OR REPLACE VIEW v_stocks AS
SELECT s.stock_id, s.status, s.total_shares, s.outstanding_shares, s.issue_date
FROM stocks s

-- View: v_price_stocks
CREATE OR REPLACE VIEW v_price_stocks AS
SELECT s.stock_id, s.status, r.current_price, r.volume
FROM stocks s
JOIN real_time_price r ON s.stock_id = r.stock_id
SELECT * FROM v_price_stocks;
-- View: v_price_stocks_detail

CREATE OR REPLACE VIEW v_price_stocks_detail AS
SELECT s.stock_id, s.status, r.current_price, r.volume, r.bid_price, r.ask_price, r.bid_volume, r.ask_volume
FROM stocks s
JOIN real_time_price r ON s.stock_id = r.stock_id

-- View: v_top_stocks
CREATE OR REPLACE VIEW v_top_stocks AS
SELECT s.stock_id, s.status, r.current_price, r.volume
FROM stocks s
JOIN real_time_price r ON s.stock_id = r.stock_id
WHERE r.volume > 100000;
select * from stocks
--  Hiển thị cổ phiếu có volume > 100000
SELECT * FROM v_top_stocks;
-- Kiểm tra cột stock_id và current_price tồn tại
SELECT stock_id, current_price FROM v_top_stocks LIMIT 5;
-- Không có dòng nào với volume <= 100000
SELECT * FROM v_top_stocks WHERE volume <= 100000;

-- View: v_user_accounts
CREATE OR REPLACE VIEW v_user_accounts AS
SELECT u.user_id, u.first_name, u.last_name, a.account_id, a.account_type
FROM users u
JOIN accounts a ON u.user_id = a.user_id;
--  Xem thông tin người dùng và tài khoản
SELECT * FROM v_user_accounts;
--  Kiểm tra có đúng cặp user_id – account_id
SELECT user_id, account_id FROM v_user_accounts;
--  Kiểm tra không có NULL trong account_type
SELECT * FROM v_user_accounts WHERE account_type IS NULL;

-- View: v_order_status
CREATE OR REPLACE VIEW v_order_status AS
SELECT o.order_id, o.account_id, o.stock_id, o.order_type, o.quantity, o.price, o.status, o.created_at
FROM orders o
JOIN stocks s ON o.stock_id = s.stock_id
JOIN accounts a ON o.account_id = a.account_id;
--  Xem tất cả lệnh đã đặt
SELECT * FROM v_order_status;
--  Kiểm tra các trạng thái hợp lệ
SELECT DISTINCT status FROM v_order_status;
--  Kiểm tra thông tin giá và số lượng hợp lệ
SELECT * FROM v_order_status WHERE price <= 0 OR quantity <= 0;

-- View: v_portfolio_summary
CREATE OR REPLACE VIEW v_portfolio_summary AS
SELECT p.portfolios_id, a.account_id, s.stock_id, s.status, p.quantity, p.average_price
FROM portfolios p
JOIN stocks s ON p.stock_id = s.stock_id
JOIN accounts a ON p.account_id = a.account_id;
--  Xem toàn bộ danh mục đầu tư
SELECT * FROM v_portfolio_summary;
--  Kiểm tra giá trung bình không âm
SELECT * FROM v_portfolio_summary WHERE average_price < 0;
--  Kiểm tra số lượng cổ phiếu > 0
SELECT * FROM v_portfolio_summary WHERE quantity <= 0;

-- View: v_transaction_history
CREATE OR REPLACE VIEW v_transaction_history AS
SELECT t.transaction_id, t.order_id, o.account_id, t.executed_at
FROM transactions t
JOIN orders o ON t.order_id = o.order_id;
--  Xem lịch sử khớp lệnh
SELECT * FROM v_transaction_history;
--  Kiểm tra có order_id hợp lệ
SELECT * FROM v_transaction_history WHERE order_id IS NULL;
--  Kiểm tra thời gian khớp lệnh không null
SELECT * FROM v_transaction_history WHERE executed_at IS NULL;


-- View: v_deposit_withdraw_log
CREATE OR REPLACE VIEW v_deposit_withdraw_log AS
SELECT d.deposit_id AS id, d.account_id, d.amount, d.deposit_time AS time, 'Deposit' AS type
FROM deposits d
UNION ALL
SELECT w.withdrawal_id AS id, w.account_id, w.amount, w.withdrawal_time AS time, 'Withdrawal' AS type
FROM withdrawals w;
-- View: v_deposit_withdraw_log
--  Xem tất cả giao dịch nạp/rút
SELECT * FROM v_deposit_withdraw_log ORDER BY time DESC;
--  Phân biệt đúng loại giao dịch
SELECT DISTINCT type FROM v_deposit_withdraw_log;
--  Kiểm tra số tiền giao dịch dương
SELECT * FROM v_deposit_withdraw_log WHERE amount <= 0;

-- View: v_company_listed
CREATE OR REPLACE VIEW v_company_listed AS
SELECT c.company_id, c.company_name, c.ticker_symbol, c.industry, c.listed_date
FROM companies c
JOIN stocks s ON c.company_id = s.company_id
WHERE s.status = 'Listed';
-- View: v_company_listed
--  Hiển thị công ty đang niêm yết
SELECT * FROM v_company_listed;
--  Kiểm tra trạng thái cổ phiếu = 'Listed'
-- (view này đã lọc từ bảng)
--  Kiểm tra ngành nghề hiển thị
SELECT DISTINCT industry FROM v_company_listed;

-- View: v_company_change_log
CREATE OR REPLACE VIEW v_company_change_log AS
SELECT l.log_id, l.stock_id, c.company_name, l.field_changed, l.old_value, l.new_value, l.updated_at
FROM stock_update_logs l
JOIN stocks s ON l.stock_id = s.stock_id
JOIN companies c ON s.company_id = c.company_id;
-- View: v_company_change_log
--  Xem log thay đổi thông tin công ty
SELECT * FROM v_company_change_log;
--  Kiểm tra có trường thay đổi nào bất thường
SELECT * FROM v_company_change_log WHERE field_changed IS NULL;
--  Kiểm tra thời gian cập nhật không null
SELECT * FROM v_company_change_log WHERE updated_at IS NULL;


-- View: v_balance_overview
CREATE OR REPLACE VIEW v_balance_overview AS
SELECT a.account_id, a.user_id, a.account_type, a.balance,
       COALESCE(SUM(d.amount), 0) AS total_deposits,
       COALESCE(SUM(w.amount), 0) AS total_withdrawals
FROM accounts a
LEFT JOIN deposits d ON a.account_id = d.account_id
LEFT JOIN withdrawals w ON a.account_id = w.account_id
GROUP BY a.account_id, a.user_id, a.account_type, a.balance;
-- View: v_balance_overview
--  Xem tổng quan số dư người dùng
SELECT * FROM v_balance_overview;
--  Kiểm tra dữ liệu tổng hợp đúng định dạng
SELECT account_id, total_deposits, total_withdrawals FROM v_balance_overview;
--  Kiểm tra giá trị âm bất thường
SELECT * FROM v_balance_overview WHERE balance < 0;


--- trao quyền trên view
GRANT SELECT ON v_user_accounts, v_company_listed, v_price_stocks, v_balance_overview, v_portfolio_summary, v_stocks, v_transaction_history  TO trader;
GRANT SELECT ON v_company_listed, v_price_stocks_detail, v_stocks TO analyst;

