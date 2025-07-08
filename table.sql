CREATE TABLE users (
    user_id SERIAL PRIMARY KEY,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    gender VARCHAR(5) CHECK (gender IN ('Nam', 'Nữ', 'Khác')),
    birthday DATE CHECK (birthday <= CURRENT_DATE),
    email VARCHAR(150) UNIQUE NOT NULL,
    phone VARCHAR(10) UNIQUE NOT NULL,
    payment_method VARCHAR(50) NOT NULL,
    password VARCHAR(256) NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
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
    deposit_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE withdrawals (
    withdrawal_id SERIAL PRIMARY KEY,
    account_id INT REFERENCES accounts(account_id) ON DELETE CASCADE,
    amount NUMERIC(15,2) CHECK (amount > 0) NOT NULL,
    withdrawal_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE companies (
    company_id SERIAL PRIMARY KEY,
    company_name VARCHAR(100) NOT NULL,
    description TEXT,
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
    description TEXT,
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
    status VARCHAR(20) CHECK (status IN ('Listed', 'Delisted', 'Suspended')),
    issue_date TIMESTAMP CHECK (issue_date <= CURRENT_DATE)
);

CREATE TABLE real_time_price (
    stock_id INT REFERENCES stocks(stock_id) ON DELETE CASCADE,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    current_price DECIMAL CHECK (current_price > 0) NOT NULL,
    PRIMARY KEY(stock_id, timestamp)
);

CREATE TABLE historical_prices (
    id SERIAL PRIMARY KEY,
    stock_id INT REFERENCES stocks(stock_id) ON DELETE CASCADE,
    price DECIMAL NOT NULL,
    change_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE portfolios (
    portfolios_id SERIAL PRIMARY KEY,
    stock_id INT REFERENCES stocks(stock_id) ON DELETE CASCADE,
    account_id INT REFERENCES accounts(account_id) ON DELETE CASCADE,
    date TIMESTAMP NOT NULL,
    quantity INT CHECK (quantity >= 0) NOT NULL,
    CONSTRAINT uq_portfolio_current UNIQUE (stock_id, account_id)
);

CREATE TABLE orders (
    order_id SERIAL PRIMARY KEY,
    account_id INT REFERENCES accounts(account_id) ON DELETE CASCADE,
    stock_id INT REFERENCES stocks(stock_id) ON DELETE CASCADE,
    order_type VARCHAR(4) CHECK (order_type IN ('BUY', 'SELL')) NOT NULL,
    quantity INT CHECK (quantity > 0) NOT NULL,
    price DECIMAL(10,2) CHECK (price > 0) NOT NULL,
    status VARCHAR(20) CHECK (status IN ('Pending', 'Completed', 'Cancelled')) NOT NULL DEFAULT 'Pending',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    quantity_remaining INT CHECK (quantity_remaining >= 0)
);

CREATE TABLE transactions (
    transaction_id SERIAL PRIMARY KEY,
    order_id INT REFERENCES orders(order_id) ON DELETE CASCADE,
    executed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    quantity INT,
    matched_price NUMERIC(10,2),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE order_matching_log (
    log_id SERIAL PRIMARY KEY,
    order1_id INT REFERENCES orders(order_id) ON DELETE CASCADE,
    order2_id INT REFERENCES orders(order_id) ON DELETE CASCADE,
    matched_price NUMERIC(10,2) NOT NULL CHECK (matched_price > 0),
    matched_quantity INT NOT NULL CHECK (matched_quantity > 0),
    matched_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE stock_update_logs (
    log_id SERIAL PRIMARY KEY,
    stock_id INT,
    field_changed TEXT,
    old_value TEXT,
    new_value TEXT,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE account_balance_log (
    log_id SERIAL PRIMARY KEY,
    account_id INT REFERENCES accounts(account_id) ON DELETE CASCADE,
    change_amount NUMERIC(15,2) NOT NULL,
    new_balance NUMERIC(15,2) NOT NULL,
    change_type VARCHAR(50) NOT NULL CHECK (
        change_type IN ('Deposit', 'Withdrawal', 'BuyOrderPlaced', 'BuyRefund', 'SellExecuted', 'ManualAdjustment')
    ),
    related_order_id INT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE portfolio_change_log (
    log_id SERIAL PRIMARY KEY,
    account_id INT REFERENCES accounts(account_id) ON DELETE CASCADE,
    stock_id INT REFERENCES stocks(stock_id) ON DELETE CASCADE,
    change_quantity INT NOT NULL,
    new_quantity INT NOT NULL,
    change_type VARCHAR(50) NOT NULL CHECK (
        change_type IN ('BuyMatched', 'SellPlaced', 'ManualAdjustment')
    ),
    related_order_id INT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE daily_stock_summary (
    id SERIAL PRIMARY KEY,
    stock_id INT REFERENCES stocks(stock_id) ON DELETE CASCADE,
    summary_date DATE NOT NULL CHECK (summary_date <= CURRENT_DATE),
    reference_price DECIMAL(10,2) CHECK (reference_price > 0) NOT NULL,
    ceiling_price DECIMAL(10,2) CHECK (ceiling_price >= reference_price) NOT NULL,
    floor_price DECIMAL(10,2) CHECK (floor_price <= reference_price) NOT NULL,
    total_volume BIGINT CHECK (total_volume >= 0) NOT NULL,
    high_price DECIMAL(10,2) CHECK (high_price >= reference_price) NOT NULL,
    low_price DECIMAL(10,2) CHECK (low_price <= reference_price) NOT NULL
);

CREATE TABLE company_indicators (
    id SERIAL PRIMARY KEY,
    company_id INT REFERENCES companies(company_id) ON DELETE CASCADE,
    report_date DATE NOT NULL,
    eps NUMERIC(10, 2),
    pe_ratio NUMERIC(10, 2),
    roe NUMERIC(5, 2),
    book_value NUMERIC(15, 2),
    market_cap BIGINT,
    beta NUMERIC(4, 2),
    revenue BIGINT,
    net_income BIGINT,
    total_assets BIGINT,
    equity BIGINT,
    UNIQUE(company_id, report_date)
);

CREATE TABLE admin_user_action_log (
    log_id SERIAL PRIMARY KEY,
    admin_user_id INT NOT NULL,
    action VARCHAR(50) NOT NULL,
    target_user_id INT NOT NULL,
    action_time TIMESTAMPTZ DEFAULT now(),
    details JSONB
);

-- Cập nhật sequence sau khi khởi tạo:
SELECT setval('companies_company_id_seq', (SELECT MAX(company_id) FROM companies));
SELECT setval('stocks_stock_id_seq', (SELECT MAX(stock_id) FROM stocks));
SELECT setval('users_user_id_seq', (SELECT MAX(user_id) FROM users));
SELECT setval('accounts_account_id_seq', (SELECT MAX(account_id) FROM accounts));