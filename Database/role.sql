--- users
GRANT SELECT, INSERT, UPDATE, DELETE ON users TO admin_SQL;

-- accounts
GRANT SELECT, INSERT, UPDATE, DELETE ON accounts TO admin_SQL;
GRANT SELECT, UPDATE ON accounts TO trader;
-- deposits, withdrawals
GRANT SELECT, INSERT, DELETE ON deposits TO admin_SQL;
GRANT SELECT, INSERT ON deposits TO trader;

GRANT SELECT, INSERT, DELETE ON withdrawals TO admin_SQL;
GRANT SELECT, INSERT ON withdrawals TO trader;
--companies, companies_archive
GRANT SELECT, INSERT, UPDATE, DELETE ON companies TO admin_SQL;

GRANT SELECT, INSERT, UPDATE, DELETE ON companies_archive TO admin_SQL;
---stocks, stock_update_logs
GRANT SELECT, INSERT, UPDATE, DELETE ON stocks TO admin_SQL;

GRANT SELECT, INSERT ON stock_update_logs TO admin_SQL;
--portfolios
GRANT SELECT, INSERT, UPDATE, DELETE ON portfolios TO admin_SQL;

---orders
GRANT SELECT, INSERT, UPDATE, DELETE ON orders TO admin_SQL;
GRANT SELECT, INSERT, UPDATE ON orders TO trader;
---transactions
GRANT SELECT, INSERT, DELETE ON transactions TO admin_SQL;
GRANT SELECT ON transactions TO trader;

--real_time_price
GRANT SELECT, INSERT, UPDATE ON real_time_price TO admin_SQL;
