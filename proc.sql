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





-- 17. UC17: Tra cứu thông tin công ty theo ticker_symbol
CREATE OR REPLACE PROCEDURE UC17_get_company_info_by_ticker(
    IN  input_ticker      VARCHAR,
    OUT p_company_id      INT,
    OUT p_company_name    VARCHAR,
    OUT p_description     TEXT,
    OUT p_ticker_symbol   VARCHAR,
    OUT p_industry        VARCHAR,
    OUT p_listed_date     TIMESTAMP,
    OUT p_head_quarters   VARCHAR,
    OUT p_website         VARCHAR
)
LANGUAGE plpgsql
AS $$
BEGIN
    SELECT 
        company_id,
        company_name,
        description,
        ticker_symbol,
        industry,
        listed_date,
        head_quarters,
        website
    INTO
        p_company_id,
        p_company_name,
        p_description,
        p_ticker_symbol,
        p_industry,
        p_listed_date,
        p_head_quarters,
        p_website
    FROM companies
    WHERE ticker_symbol = input_ticker;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Không tìm thấy công ty với mã ticker: %', input_ticker;
    END IF;
END;
$$;

-- Procedures: cập nhật user
CREATE OR REPLACE PROCEDURE admin_procedure_reset_password(
  p_admin_id    INT,
  p_target_id   INT,
  p_new_password TEXT)
LANGUAGE plpgsql AS $$
BEGIN
  UPDATE users
  
     SET password = crypt(p_new_password, gen_salt('bf'))
   WHERE user_id = p_target_id;

  -- Ghi log
  INSERT INTO admin_user_action_log(admin_user_id, action, target_user_id, details)
  VALUES (p_admin_id, 'reset_password', p_target_id,
          jsonb_build_object('new_password_hash', (SELECT password FROM users WHERE user_id = p_target_id)));
END;
$$;

CREATE OR REPLACE PROCEDURE admin_procedure_update_user_info(
  p_admin_id   INT,
  p_target_id  INT,
  p_first_name TEXT,
  p_last_name  TEXT,
  p_email      TEXT,
  p_phone      TEXT)
LANGUAGE plpgsql AS $$
DECLARE
  _old users%ROWTYPE;
BEGIN
  SELECT * INTO _old FROM users WHERE user_id = p_target_id;

  UPDATE users
     SET first_name = p_first_name,
         last_name  = p_last_name,
         email      = p_email,
         phone      = p_phone
   WHERE user_id = p_target_id;

  -- Ghi log
  INSERT INTO admin_user_action_log(admin_user_id, action, target_user_id, details)
  VALUES (
    p_admin_id,
    'update_user_info',
    p_target_id,
    jsonb_build_object(
      'old', row_to_json(_old),
      'new', jsonb_build_object(
        'first_name', p_first_name,
        'last_name', p_last_name,
        'email', p_email,
        'phone', p_phone
      )
    )
  );
END;
$$;

CREATE OR REPLACE PROCEDURE admin_procedure_disable_user(
  p_admin_id  INT,
  p_target_id INT)
LANGUAGE plpgsql AS $$
BEGIN
  UPDATE users
     SET is_active = FALSE
   WHERE user_id = p_target_id;

  INSERT INTO admin_user_action_log(admin_user_id, action, target_user_id)
  VALUES (p_admin_id, 'disable_account', p_target_id, NULL);
END;
$$;

DROP PROCEDURE IF EXISTS admin_procedure_enable_user  CASCADE;
CREATE OR REPLACE PROCEDURE admin_procedure_enable_user(
  p_admin_id  INT,
  p_target_id INT)
LANGUAGE plpgsql AS $$
BEGIN
  UPDATE users
     SET is_active = TRUE
   WHERE user_id = p_target_id;

  INSERT INTO admin_user_action_log(admin_user_id, action, target_user_id)
  VALUES (p_admin_id, 'enable_account', p_target_id, NULL);
END;
$$;

--  Procedures: CRUD stocks/companies
--  Tạo mới stock	
CREATE OR REPLACE PROCEDURE admin_procedure_create_stock(
    p_admin_id      INT,
    p_symbol        TEXT,
    p_name          TEXT,
    p_company_id    INT,
    p_total_issued  BIGINT,
	p_oustanding_shares BIGINT,
    p_status        VARCHAR
)
LANGUAGE plpgsql AS $$
DECLARE
    v_stock_id INT;
BEGIN
	-- select * from stocks
    INSERT INTO stocks(symbol, company_id, total_issued, oustanding_shares, status)
    VALUES(p_symbol, p_company_id, p_total_issued, p.oustanding_shares, p_status)
    RETURNING stock_id INTO v_stock_id;

    INSERT INTO admin_user_action_log(admin_user_id, action, target_user_id, details)
    VALUES(
        p_admin_id,
        'create_stock',
        v_stock_id,
        jsonb_build_object(
            'symbol', p_symbol,
            'name',   p_name,
            'company_id', p_company_id,
            'total_issued', p_total_issued,
            'status', p_status
        )
    );
END;
$$;

-- Cập nhật số lượng phát hành
CREATE OR REPLACE PROCEDURE admin_procedure_update_stock_quantity(
    p_admin_id      INT,
    p_stock_id      INT,
    p_new_quantity  BIGINT
)
LANGUAGE plpgsql AS $$
DECLARE
    _old stocks%ROWTYPE;
BEGIN
    SELECT * INTO _old FROM stocks WHERE stock_id = p_stock_id;

    UPDATE stocks
       SET total_issued = p_new_quantity
     WHERE stock_id = p_stock_id;

    INSERT INTO admin_user_action_log(admin_user_id, action, target_user_id, details)
    VALUES(
        p_admin_id,
        'update_stock_quantity',
        p_stock_id,
        jsonb_build_object(
            'old', _old.total_issued,
            'new', p_new_quantity
        )
    );
END;
$$;

-- Cập nhật trạng thái listed/unlisted
CREATE OR REPLACE PROCEDURE admin_procedure_update_stock_status(
    p_admin_id     INT,
    p_stock_id     INT,
    p_new_status   VARCHAR
)
LANGUAGE plpgsql AS $$
DECLARE
    _old stocks%ROWTYPE;
BEGIN
    SELECT * INTO _old FROM stocks WHERE stock_id = p_stock_id;

    UPDATE stocks
       SET status     = p_new_status
     WHERE stock_id = p_stock_id;

    INSERT INTO admin_user_action_log(admin_user_id, action, target_user_id, details)
    VALUES(
        p_admin_id,
        'update_stock_status',
        p_stock_id,
        jsonb_build_object(
            'old', _old.status,
            'new', p_new_status
        )
    );
END;
$$;

-- Cập nhật thông tin company
CREATE OR REPLACE PROCEDURE admin_procedure_update_company_info(
    p_admin_id     INT,
    p_company_id   INT,
    p_name         TEXT,
    p_industry     TEXT,
    p_website      TEXT
)
LANGUAGE plpgsql AS $$
DECLARE
    _old companies%ROWTYPE;
BEGIN
    SELECT * INTO _old FROM companies WHERE company_id = p_company_id;

    UPDATE companies
       SET name        = p_name,
           industry    = p_industry,
           website     = p_website
     WHERE company_id = p_company_id;

    INSERT INTO admin_user_action_log(admin_user_id, action, target_user_id, details)
    VALUES(
        p_admin_id,
        'update_company_info',
        p_company_id,
        jsonb_build_object(
            'old', row_to_json(_old),
            'new', jsonb_build_object(
                'name', p_name,
                'industry', p_industry,
                'website', p_website
            )
        )
    );
END;
$$;

-- Price management: cập nhật real_time_price
CREATE OR REPLACE PROCEDURE admin_procedure_update_stock_price(
    p_admin_id   INT,
    p_stock_id   INT,
    p_price      NUMERIC
)
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO real_time_price(stock_id, price, timestamp)
    VALUES(p_stock_id, p_price, now())
    ON CONFLICT (stock_id) DO UPDATE SET
        price     = EXCLUDED.price,
        timestamp = EXCLUDED.timestamp;

    INSERT INTO admin_user_action_log(admin_user_id, action, target_user_id, details)
    VALUES(
        p_admin_id,
        'update_stock_price',
        p_stock_id,
        jsonb_build_object('price', p_price)
    );
END;
$$;

