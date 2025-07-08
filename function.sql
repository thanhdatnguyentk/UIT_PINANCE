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


-- Tìm công ty theo tên chứa chuỗi bất kỳ (case-insensitive)
CREATE OR REPLACE FUNCTION UC_17_search_companies_by_name(
    IN input_name_pattern TEXT
)
RETURNS TABLE (
    company_id    INT,
    company_name  VARCHAR,
    ticker_symbol VARCHAR,
    industry      VARCHAR,
    listed_date   TIMESTAMP
)
LANGUAGE sql
AS $$
    SELECT
        company_id,
        company_name,
        ticker_symbol,
        industry,
        listed_date
    FROM companies
    WHERE company_name ILIKE '%' || input_name_pattern || '%';
$$;

-- Functions: lấy danh sách và tìm kiếm user
CREATE OR REPLACE FUNCTION admin_function_list_users()
RETURNS SETOF users AS $$
BEGIN
  RETURN QUERY
    SELECT * FROM users ORDER BY user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


CREATE OR REPLACE FUNCTION admin_function_search_users_by_email(p_email TEXT)
RETURNS SETOF users AS $$
BEGIN
  RETURN QUERY
    SELECT * FROM users
     WHERE email ILIKE '%' || p_email || '%'
     ORDER BY user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION admin_function_search_users_by_name(p_name TEXT)
RETURNS SETOF users AS $$
BEGIN
  RETURN QUERY
    SELECT * FROM users
     WHERE first_name ILIKE '%' || p_name || '%'
        OR last_name  ILIKE '%' || p_name || '%'
     ORDER BY user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 1. Functions: list và search stocks/companies

CREATE OR REPLACE FUNCTION admin_function_list_stocks()
RETURNS SETOF stocks AS $$
BEGIN
    RETURN QUERY
        SELECT *
          FROM stocks
         ORDER BY stock_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


CREATE OR REPLACE FUNCTION admin_function_search_stocks_by_symbol(p_symbol TEXT)
RETURNS SETOF stocks AS $$
BEGIN
    RETURN QUERY
        SELECT *
          FROM stocks
         WHERE symbol ILIKE '%' || p_symbol || '%'
            OR name   ILIKE '%' || p_symbol || '%'
         ORDER BY stock_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION admin_function_list_companies()
RETURNS SETOF companies AS $$
BEGIN
    RETURN QUERY
        SELECT *
          FROM companies
         ORDER BY company_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION admin_function_search_companies_by_name(p_name TEXT)
RETURNS SETOF companies AS $$
BEGIN
    RETURN QUERY
        SELECT *
          FROM companies 
         WHERE company_name ILIKE '%' || p_name || '%'
         ORDER BY company_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

--     Danh sách nạp: admin_function_list_deposits()
--     Danh sách rút: admin_function_list_withdrawals()
--     Danh sách lệnh: admin_function_list_orders()
--     Danh sách giao dịch: admin_function_list_transactions()


CREATE OR REPLACE FUNCTION admin_function_list_deposits()
RETURNS SETOF deposits AS $$
BEGIN
    RETURN QUERY
      SELECT *
        FROM deposits;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


CREATE OR REPLACE FUNCTION admin_function_list_withdrawals()
RETURNS SETOF withdrawals AS $$
BEGIN
    RETURN QUERY
      SELECT *
        FROM withdrawals;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


CREATE OR REPLACE FUNCTION admin_function_list_orders()
RETURNS SETOF orders AS $$
BEGIN
    RETURN QUERY
      SELECT *
        FROM orders;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


CREATE OR REPLACE FUNCTION admin_function_list_transactions()
RETURNS SETOF transactions AS $$
BEGIN
    RETURN QUERY
      SELECT *
        FROM transactions;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- 2. Báo cáo cấp cao
--    Số user mới theo ngày/tuần/tháng: admin_function_report_new_users_by_period(p_period)
--    Tổng giá trị và khối lượng giao dịch: admin_function_report_transaction_summary()
--    Top cổ phiếu giao dịch nhiều nhất: admin_function_report_top_traded_stocks(p_limit)
--    -op phiên tăng/giảm giá mạnh: admin_function_report_top_price_movers(p_period, p_limit)

CREATE OR REPLACE FUNCTION admin_function_report_new_users_by_period(
    p_start_date DATE,
    p_end_date   DATE
)
RETURNS TABLE(period_start TIMESTAMPTZ, new_users BIGINT) 
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  RETURN QUERY
  SELECT
    date_trunc('day', created_at) AS period_start,
    COUNT(*)                      AS new_users
  FROM users
  WHERE created_at::date BETWEEN p_start_date AND p_end_date
  GROUP BY 1
  ORDER BY 1;
END;
$$;


CREATE FUNCTION admin_function_report_transaction_summary()
  RETURNS TABLE(total_value NUMERIC, total_volume BIGINT) AS $$
BEGIN
  RETURN QUERY
  SELECT
    SUM(t.quantity * t.matched_price) AS total_value,
    SUM(t.quantity)                  AS total_volume
  FROM transactions t;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


CREATE OR REPLACE FUNCTION admin_function_report_top_traded_stocks(
    p_limit INT
)
RETURNS TABLE(stock_id INT, ticker_symbol TEXT, total_quantity NUMERIC) AS $$
BEGIN
    RETURN QUERY
    SELECT s.stock_id,
           c.ticker_symbol,
           SUM(t.quantity) AS total_quantity
      FROM transactions t
      JOIN orders o    ON t.order_id    = o.order_id
      JOIN stocks s    ON o.stock_id    = s.stock_id
      JOIN companies c ON s.company_id  = c.company_id
     GROUP BY s.stock_id, c.ticker_symbol
     ORDER BY total_quantity DESC
     LIMIT p_limit;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


CREATE OR REPLACE FUNCTION admin_function_report_top_price_movers(
    p_period TEXT,  -- 'day', 'week', 'month'
    p_limit  INT
)
RETURNS TABLE(stock_id INT, ticker_symbol TEXT, price_change NUMERIC) AS $$
BEGIN
    RETURN QUERY
    WITH price_seq AS (
        SELECT
          p.stock_id,
          FIRST_VALUE(p.current_price) OVER w AS start_price,
          LAST_VALUE(p.current_price) OVER w  AS end_price
        FROM (
          SELECT r.stock_id, r.current_price, r.timestamp
            FROM real_time_price r
           WHERE r.timestamp >= now() - (
                  CASE p_period
                    WHEN 'day'   THEN INTERVAL '1 day'
                    WHEN 'week'  THEN INTERVAL '7 days'
                    WHEN 'month' THEN INTERVAL '1 month'
                    ELSE p_period::interval
                  END
                 )
           ORDER BY r.stock_id, r.timestamp
        ) p
        WINDOW w AS (
          PARTITION BY p.stock_id
          ORDER BY p.timestamp
          ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
        )
    )
    SELECT
      ps.stock_id,
      c.ticker_symbol,
      (ps.end_price - ps.start_price) AS price_change
    FROM price_seq ps
    JOIN stocks s    ON ps.stock_id = s.stock_id
    JOIN companies c ON s.company_id  = c.company_id
    ORDER BY ABS(ps.end_price - ps.start_price) DESC
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
