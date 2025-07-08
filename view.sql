-- View: v_transaction_history
CREATE OR REPLACE VIEW v_transaction_history AS
SELECT t.transaction_id, t.order_id, o.account_id, t.executed_at
FROM transactions t
JOIN orders o ON t.order_id = o.order_id;

-- view: v_stocks
CREATE OR REPLACE VIEW v_stocks AS
SELECT s.stock_id, s.status, s.total_shares, s.outstanding_shares, s.issue_date
FROM stocks s;

-- View: v_price_stocks
CREATE OR REPLACE VIEW v_price_stocks AS
SELECT s.stock_id, s.status, r.current_price
FROM stocks s
JOIN real_time_price r ON s.stock_id = r.stock_id;

-- View: v_price_stocks_detail
CREATE OR REPLACE VIEW v_price_stocks_detail AS
SELECT s.stock_id, s.status, r.current_price
FROM stocks s
JOIN real_time_price r ON s.stock_id = r.stock_id;

-- View: v_user_accounts
CREATE OR REPLACE VIEW v_user_accounts AS
SELECT u.user_id, u.first_name, u.last_name, a.account_id, a.account_type
FROM users u
JOIN accounts a ON u.user_id = a.user_id;

-- View: v_order_status
CREATE OR REPLACE VIEW v_order_status AS
SELECT o.order_id, o.account_id, o.stock_id, o.order_type, o.quantity, o.price, o.status, o.created_at
FROM orders o
JOIN stocks s ON o.stock_id = s.stock_id
JOIN accounts a ON o.account_id = a.account_id;

-- View: v_portfolio_summary
CREATE OR REPLACE VIEW v_portfolio_summary AS
SELECT p.portfolios_id, a.account_id, s.stock_id, s.status, p.quantity
FROM portfolios p
JOIN stocks s ON p.stock_id = s.stock_id
JOIN accounts a ON p.account_id = a.account_id;

-- View: v_deposit_withdraw_log
CREATE OR REPLACE VIEW v_deposit_withdraw_log AS
SELECT d.deposit_id AS id, d.account_id, d.amount, d.deposit_time AS time, 'Deposit' AS type
FROM deposits d
UNION ALL
SELECT w.withdrawal_id AS id, w.account_id, w.amount, w.withdrawal_time AS time, 'Withdrawal' AS type
FROM withdrawals w;


-- View: v_company_listed
CREATE OR REPLACE VIEW v_company_listed AS
SELECT c.company_id, c.company_name, c.ticker_symbol, c.industry, c.listed_date
FROM companies c
JOIN stocks s ON c.company_id = s.company_id
WHERE s.status = 'Listed';


-- View: v_company_change_log
CREATE OR REPLACE VIEW v_company_change_log AS
SELECT l.log_id, l.stock_id, c.company_name, l.field_changed, l.old_value, l.new_value, l.updated_at
FROM stock_update_logs l
JOIN stocks s ON l.stock_id = s.stock_id
JOIN companies c ON s.company_id = c.company_id;



-- View: v_balance_overview
CREATE OR REPLACE VIEW v_balance_overview AS
SELECT a.account_id, a.user_id, a.account_type, a.balance,
       COALESCE(SUM(d.amount), 0) AS total_deposits,
       COALESCE(SUM(w.amount), 0) AS total_withdrawals
FROM accounts a
LEFT JOIN deposits d ON a.account_id = d.account_id
LEFT JOIN withdrawals w ON a.account_id = w.account_id
GROUP BY a.account_id, a.user_id, a.account_type, a.balance;




--TOP SELL ORDER
CREATE OR REPLACE VIEW v_top_sell_orders AS
SELECT stock_id, price, SUM(quantity_remaining) AS total_quantity
FROM orders
WHERE order_type = 'SELL' AND status = 'Pending'
GROUP BY stock_id, price
ORDER BY stock_id, price ASC;

-- TOP BUY ORDER
CREATE OR REPLACE VIEW v_top_buy_orders AS
SELECT stock_id, price, SUM(quantity_remaining) AS total_quantity
FROM orders
WHERE order_type = 'BUY' AND status = 'Pending'
GROUP BY stock_id, price
ORDER BY stock_id, price DESC;

-- Lợi nhuận của tài khoản 
CREATE OR REPLACE VIEW v_loi_nhuan_theo_cp AS
WITH
-- Tổng các lần mua đã khớp
buy_fifo AS (
  SELECT
    o.account_id,
    o.stock_id,
    SUM(om.matched_quantity) AS total_bought,
    SUM(om.matched_quantity * om.matched_price) AS total_buy_value
  FROM order_matching_log om
  JOIN orders o ON o.order_id = om.order1_id
  WHERE o.order_type = 'BUY'
  GROUP BY o.account_id, o.stock_id
),

-- Tổng các lần bán đã khớp
sell_fifo AS (
  SELECT
    o.account_id,
    o.stock_id,
    SUM(om.matched_quantity) AS total_sold
  FROM order_matching_log om
  JOIN orders o ON o.order_id = om.order2_id
  WHERE o.order_type = 'SELL'
  GROUP BY o.account_id, o.stock_id
),

-- Số lượng còn giữ theo FIFO và giá vốn trung bình còn lại
fifo_calc AS (
  SELECT
    b.account_id,
    b.stock_id,
    (b.total_bought - COALESCE(s.total_sold, 0)) AS qty_remaining,
    CASE
      WHEN (b.total_bought - COALESCE(s.total_sold, 0)) > 0 THEN
        (b.total_buy_value
         - ((b.total_buy_value / NULLIF(b.total_bought, 0)) * COALESCE(s.total_sold, 0)))
        / NULLIF((b.total_bought - COALESCE(s.total_sold, 0)), 0)
      ELSE NULL
    END AS avg_cost_remaining
  FROM buy_fifo b
  LEFT JOIN sell_fifo s ON b.account_id = s.account_id AND b.stock_id = s.stock_id
),

-- Giá hiện tại mới nhất cho mỗi cổ phiếu
latest_price AS (
  SELECT stock_id, current_price
  FROM (
    SELECT stock_id, current_price,
           ROW_NUMBER() OVER (PARTITION BY stock_id ORDER BY timestamp DESC) AS rn
    FROM real_time_price
  ) sub
  WHERE rn = 1
)

-- Tính lãi/lỗ theo giá trị và phần trăm
SELECT
  f.account_id,
  f.stock_id,
  c.ticker_symbol,
  ROUND(lp.current_price, 2) AS current_price,
  ROUND(f.avg_cost_remaining, 2) AS gia_von_tb_con_lai,
  f.qty_remaining,
  ROUND((lp.current_price - f.avg_cost_remaining) * f.qty_remaining, 2) AS loi_nhuan_gia_tri,
  ROUND((lp.current_price - f.avg_cost_remaining) / f.avg_cost_remaining * 100, 2) AS percent_loi_nhuan
FROM fifo_calc f
JOIN latest_price lp ON lp.stock_id = f.stock_id
JOIN stocks s ON s.stock_id = f.stock_id
JOIN companies c ON c.company_id = s.company_id
WHERE f.qty_remaining > 0;

-- Lợi nhuận toàn thời gian cho mọi tài khoản (admin)
CREATE OR REPLACE VIEW v_total_pnl_summary AS
WITH
-- Tổng tiền & số lượng BUY đã khớp
buy_data AS (
  SELECT
    o.account_id,
    o.stock_id,
    SUM(om.matched_price * om.matched_quantity) AS total_buy_value,
    SUM(om.matched_quantity) AS total_buy_qty
  FROM order_matching_log om
  JOIN orders o ON o.order_id = om.order1_id
  WHERE o.order_type = 'BUY'
  GROUP BY o.account_id, o.stock_id
),

-- Tổng tiền & số lượng SELL đã khớp
sell_data AS (
  SELECT
    o.account_id,
    o.stock_id,
    SUM(om.matched_price * om.matched_quantity) AS total_sell_value,
    SUM(om.matched_quantity) AS total_sell_qty
  FROM order_matching_log om
  JOIN orders o ON o.order_id = om.order2_id
  WHERE o.order_type = 'SELL'
  GROUP BY o.account_id, o.stock_id
),

-- Giá hiện tại mới nhất cho mỗi cổ phiếu
latest_price AS (
  SELECT stock_id, current_price
  FROM (
    SELECT stock_id, current_price,
           ROW_NUMBER() OVER (PARTITION BY stock_id ORDER BY timestamp DESC) AS rn
    FROM real_time_price
  ) sub
  WHERE rn = 1
),

-- Gộp dữ liệu BUY + SELL + giá hiện tại
pnl_per_stock AS (
  SELECT
    COALESCE(b.account_id, s.account_id) AS account_id,
    COALESCE(b.stock_id, s.stock_id) AS stock_id,
    COALESCE(b.total_buy_value, 0) AS total_buy_value,
    COALESCE(b.total_buy_qty, 0) AS total_buy_qty,
    COALESCE(s.total_sell_value, 0) AS total_sell_value,
    COALESCE(s.total_sell_qty, 0) AS total_sell_qty,
    lp.current_price
  FROM buy_data b
  FULL OUTER JOIN sell_data s ON b.account_id = s.account_id AND b.stock_id = s.stock_id
  JOIN latest_price lp ON lp.stock_id = COALESCE(b.stock_id, s.stock_id)
),

-- Tính lãi/lỗ cho mỗi account_id
calc AS (
  SELECT
    account_id,
    SUM(
      CASE
        WHEN total_sell_qty = 0 THEN
          -- Chỉ tính unrealized
          total_buy_qty * (current_price - (total_buy_value / NULLIF(total_buy_qty, 0)))
        ELSE
          -- Tính cả realized + unrealized
          ((total_buy_qty - total_sell_qty) * (current_price - (total_buy_value / NULLIF(total_buy_qty, 0))))
          + ((total_sell_value / NULLIF(total_sell_qty, 0) - total_buy_value / NULLIF(total_buy_qty, 0)) * total_sell_qty)
      END
    ) AS loi_nhuan
  FROM pnl_per_stock
  GROUP BY account_id
)

SELECT * FROM calc;

-- Market board
CREATE OR REPLACE VIEW v_stock_market_board AS
SELECT 
    s.stock_id,
    c.ticker_symbol AS "CK",
    COALESCE(d.ceiling_price, 0) AS "Trần",
    COALESCE(d.floor_price, 0) AS "Sàn",
    COALESCE(d.reference_price, 0) AS "TC",

    -- BÊN MUA
    COALESCE(buy_3.price, 0) AS "Giá 3 Mua", COALESCE(buy_3.total_quantity, 0) AS "KL 3 Mua",
    COALESCE(buy_2.price, 0) AS "Giá 2 Mua", COALESCE(buy_2.total_quantity, 0) AS "KL 2 Mua",
    COALESCE(buy_1.price, 0) AS "Giá 1 Mua", COALESCE(buy_1.total_quantity, 0) AS "KL 1 Mua",

    -- BÊN BÁN
    COALESCE(sell_1.price, 0) AS "Giá 1 Bán", COALESCE(sell_1.total_quantity, 0) AS "KL 1 Bán",
    COALESCE(sell_2.price, 0) AS "Giá 2 Bán", COALESCE(sell_2.total_quantity, 0) AS "KL 2 Bán",
    COALESCE(sell_3.price, 0) AS "Giá 3 Bán", COALESCE(sell_3.total_quantity, 0) AS "KL 3 Bán",

    -- TỔNG HỢP
    COALESCE(d.total_volume, 0) AS "Tổng KL",
    COALESCE(d.high_price, 0) AS "Cao",
    COALESCE(d.low_price, 0) AS "Thấp"

FROM stocks s
JOIN companies c ON s.company_id = c.company_id
LEFT JOIN daily_stock_summary d ON s.stock_id = d.stock_id AND d.summary_date = CURRENT_DATE

-- BÊN MUA
LEFT JOIN LATERAL (
    SELECT price, SUM(quantity_remaining) AS total_quantity
    FROM orders
    WHERE stock_id = s.stock_id AND order_type = 'BUY' AND status = 'Pending'
    GROUP BY price
    ORDER BY price DESC
    LIMIT 1 OFFSET 2
) AS buy_3 ON TRUE

LEFT JOIN LATERAL (
    SELECT price, SUM(quantity_remaining) AS total_quantity
    FROM orders
    WHERE stock_id = s.stock_id AND order_type = 'BUY' AND status = 'Pending'
    GROUP BY price
    ORDER BY price DESC
    LIMIT 1 OFFSET 1
) AS buy_2 ON TRUE

LEFT JOIN LATERAL (
    SELECT price, SUM(quantity_remaining) AS total_quantity
    FROM orders
    WHERE stock_id = s.stock_id AND order_type = 'BUY' AND status = 'Pending'
    GROUP BY price
    ORDER BY price DESC
    LIMIT 1
) AS buy_1 ON TRUE

-- BÊN BÁN
LEFT JOIN LATERAL (
    SELECT price, SUM(quantity_remaining) AS total_quantity
    FROM orders
    WHERE stock_id = s.stock_id AND order_type = 'SELL' AND status = 'Pending'
    GROUP BY price
    ORDER BY price ASC
    LIMIT 1
) AS sell_1 ON TRUE

LEFT JOIN LATERAL (
    SELECT price, SUM(quantity_remaining) AS total_quantity
    FROM orders
    WHERE stock_id = s.stock_id AND order_type = 'SELL' AND status = 'Pending'
    GROUP BY price
    ORDER BY price ASC
    LIMIT 1 OFFSET 1
) AS sell_2 ON TRUE

LEFT JOIN LATERAL (
    SELECT price, SUM(quantity_remaining) AS total_quantity
    FROM orders
    WHERE stock_id = s.stock_id AND order_type = 'SELL' AND status = 'Pending'
    GROUP BY price
    ORDER BY price ASC
    LIMIT 1 OFFSET 2
) AS sell_3 ON TRUE;

-- asset movement
CREATE OR REPLACE VIEW v_asset_movements AS
SELECT
    log_id,
    created_at,
    'Cash'            AS movement_category,
    change_type       AS movement_type,
    account_id,
    NULL              AS stock_id,
    change_amount     AS amount,
    new_balance       AS new_value,
    NULL              AS change_quantity
FROM account_balance_log

UNION ALL

SELECT
    log_id,
    created_at,
    'Portfolio'       AS movement_category,
    change_type       AS movement_type,
    account_id,
    stock_id,
    NULL              AS amount,
    NULL              AS new_value,
    change_quantity   AS change_quantity
FROM portfolio_change_log

ORDER BY created_at DESC;

CREATE OR REPLACE VIEW v_tai_san_tong_hop AS
SELECT
  a.account_id,
  u.first_name,
  u.last_name,
  ROUND(
    a.balance + COALESCE(SUM(p.quantity * r.current_price), 0),
    2
  ) AS tai_san
FROM accounts a
JOIN users u ON u.user_id = a.user_id
LEFT JOIN portfolios p ON p.account_id = a.account_id
LEFT JOIN LATERAL (
  SELECT r1.current_price
  FROM real_time_price r1
  WHERE r1.stock_id = p.stock_id
  ORDER BY r1.timestamp DESC
  LIMIT 1
) r ON TRUE
GROUP BY a.account_id, u.first_name, u.last_name, a.balance;