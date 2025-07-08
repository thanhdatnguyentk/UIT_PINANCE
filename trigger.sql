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



--- UC2 -  nạp tiền
CREATE OR REPLACE FUNCTION UC2_update_balance_after_deposit()
RETURNS TRIGGER AS $$
DECLARE
    v_new_balance NUMERIC(15,2);
BEGIN
    -- Cập nhật số dư
    UPDATE accounts
    SET balance = balance + NEW.amount
    WHERE account_id = NEW.account_id;

    -- Lấy lại số dư mới sau cập nhật
    SELECT balance INTO v_new_balance
    FROM accounts
    WHERE account_id = NEW.account_id;

    -- Ghi vào bảng log
    INSERT INTO account_balance_log (
        account_id,
        change_amount,
        new_balance,
        change_type,
        related_order_id,
        created_at
    )
    VALUES (
        NEW.account_id,
        NEW.amount,
        v_new_balance,
        'Deposit',
        NULL,
        CURRENT_TIMESTAMP
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER UC2_trg_update_balance_after_deposit
AFTER INSERT ON deposits
FOR EACH ROW
EXECUTE FUNCTION UC2_update_balance_after_deposit();


--- UC3 - rút tiền
CREATE OR REPLACE FUNCTION UC3_process_withdrawal()
RETURNS TRIGGER AS $$
DECLARE
    current_balance NUMERIC(15,2);
    new_balance NUMERIC(15,2);
BEGIN
    -- Lấy số dư hiện tại
    SELECT balance INTO current_balance
    FROM accounts
    WHERE account_id = NEW.account_id;

    -- Kiểm tra đủ tiền không
    IF NEW.amount > current_balance THEN
        RAISE EXCEPTION 'Số dư không đủ để rút tiền';
    END IF;

    -- Cập nhật số dư
    UPDATE accounts
    SET balance = balance - NEW.amount
    WHERE account_id = NEW.account_id;

    -- Lấy số dư mới
    SELECT balance INTO new_balance
    FROM accounts
    WHERE account_id = NEW.account_id;

    -- Ghi log
    INSERT INTO account_balance_log (
        account_id,
        change_amount,
        new_balance,
        change_type,
        related_order_id,
        created_at
    )
    VALUES (
        NEW.account_id,
        -NEW.amount,         -- âm vì là rút
        new_balance,
        'Withdrawal',
        NULL,
        CURRENT_TIMESTAMP
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER UC3_trg_process_withdrawal
AFTER INSERT ON withdrawals
FOR EACH ROW
EXECUTE FUNCTION UC3_process_withdrawal();


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





-- Trigger kiểm tra điều kiện đặt lệnh trên bảng orders
-- 1. Hàm kiểm tra điều kiện đặt lệnh
CREATE OR REPLACE FUNCTION fn_check_order_condition()
RETURNS TRIGGER AS
$$
DECLARE
    v_balance NUMERIC;
    v_quantity INT;
    v_ref_price NUMERIC;
    v_price_upper NUMERIC;
    v_price_lower NUMERIC;
BEGIN
    -- Lấy giá tham chiếu của cổ phiếu trong ngày
    SELECT reference_price INTO v_ref_price
    FROM daily_stock_summary
    WHERE stock_id = NEW.stock_id
      AND summary_date = CURRENT_DATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Không tìm thấy giá tham chiếu cho cổ phiếu % trong ngày.', NEW.stock_id;
    END IF;

    -- Tính giá trần và sàn theo biên độ ±7%
    v_price_upper := ROUND(v_ref_price * 1.07, 2);
    v_price_lower := ROUND(v_ref_price * 0.93, 2);

    -- Kiểm tra giá có nằm trong biên độ không
    IF NEW.price > v_price_upper OR NEW.price < v_price_lower THEN
        RAISE EXCEPTION 'Giá đặt lệnh vượt biên độ cho phép (%.2f - %.2f).', v_price_lower, v_price_upper;
    END IF;

    -- Kiểm tra điều kiện tài chính hoặc cổ phiếu
    IF NEW.order_type = 'BUY' THEN
        SELECT balance INTO v_balance
        FROM accounts
        WHERE account_id = NEW.account_id;

        IF v_balance < (NEW.price * NEW.quantity) THEN
            RAISE EXCEPTION 'Tài khoản không đủ tiền để đặt lệnh mua.';
        END IF;

    ELSIF NEW.order_type = 'SELL' THEN
        SELECT quantity INTO v_quantity
        FROM portfolios
        WHERE account_id = NEW.account_id
          AND stock_id = NEW.stock_id;

        IF NOT FOUND OR v_quantity < NEW.quantity THEN
            RAISE EXCEPTION 'Tài khoản không đủ cổ phiếu để đặt lệnh bán.';
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
-- 2. Tạo trigger cho bảng orders
DROP TRIGGER IF EXISTS tr_check_order_condition ON orders;
CREATE TRIGGER tr_check_order_condition
BEFORE INSERT
ON orders
FOR EACH ROW
EXECUTE FUNCTION fn_check_order_condition();



-- Trigger cập nhật số dư và portfolio khi lệnh được đặt 

-- before insert
CREATE OR REPLACE FUNCTION trg_order_placement_func()
RETURNS trigger AS $$
DECLARE
    v_new_quantity INT;
    v_new_balance NUMERIC(15,2);
BEGIN
    IF NEW.order_type = 'SELL' THEN
        -- Trừ cổ phiếu khi đặt lệnh bán
        UPDATE portfolios
        SET quantity = quantity - NEW.quantity,
            date = CURRENT_TIMESTAMP
        WHERE account_id = NEW.account_id
          AND stock_id = NEW.stock_id;

        -- Lấy lại số lượng mới sau khi trừ
        SELECT quantity INTO v_new_quantity
        FROM portfolios
        WHERE account_id = NEW.account_id AND stock_id = NEW.stock_id;

        -- Ghi log trừ cổ phiếu
        INSERT INTO portfolio_change_log (
            account_id, stock_id, change_quantity, new_quantity,
            change_type, related_order_id, created_at
        )
        VALUES (
            NEW.account_id, NEW.stock_id, -NEW.quantity, v_new_quantity,
            'SellPlaced', NEW.order_id, CURRENT_TIMESTAMP
        );

    ELSIF NEW.order_type = 'BUY' THEN
        -- Trừ tiền khi đặt lệnh mua
        UPDATE accounts
        SET balance = balance - (NEW.quantity * NEW.price)
        WHERE account_id = NEW.account_id;

        -- Lấy lại số dư mới sau khi trừ
        SELECT balance INTO v_new_balance
        FROM accounts
        WHERE account_id = NEW.account_id;

        -- Ghi log trừ tiền
        INSERT INTO account_balance_log (
            account_id, change_amount, new_balance,
            change_type, related_order_id, created_at
        )
        VALUES (
            NEW.account_id, -(NEW.quantity * NEW.price), v_new_balance,
            'BuyOrderPlaced', NEW.order_id, CURRENT_TIMESTAMP
        );
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_order_placement
BEFORE INSERT ON orders
FOR EACH ROW
EXECUTE PROCEDURE trg_order_placement_func();



-- Trigger ngăn cập nhật balance âm trên bảng accounts
CREATE OR REPLACE FUNCTION fn_prevent_negative_balance()
RETURNS TRIGGER AS
$$
BEGIN
    IF NEW.balance < 0 THEN
       RAISE EXCEPTION 'Số dư tài khoản không được âm: %', NEW.balance;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS tr_prevent_negative_balance ON accounts;
CREATE TRIGGER tr_prevent_negative_balance
BEFORE UPDATE
ON accounts
FOR EACH ROW
EXECUTE FUNCTION fn_prevent_negative_balance();




-- Trigger default cho quantity_remaining
CREATE OR REPLACE FUNCTION fn_set_quantity_remaining()
RETURNS TRIGGER AS
$$
BEGIN
    -- Nếu như trường quantity_remaining không được cung cấp (NULL), 
    -- thì gán giá trị bằng quantity của lệnh.
    IF NEW.quantity_remaining IS NULL THEN
        NEW.quantity_remaining := NEW.quantity;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS tr_set_quantity_remaining ON orders;

CREATE TRIGGER tr_set_quantity_remaining
BEFORE INSERT
ON orders
FOR EACH ROW
EXECUTE FUNCTION fn_set_quantity_remaining();




-- Trigger tự động “đóng” lệnh khi đủ khớp
CREATE OR REPLACE FUNCTION fn_close_filled_order()
RETURNS TRIGGER AS
$$
BEGIN
    -- Nếu số lượng chưa khớp giảm xuống bằng 0 (hoặc âm, mặc dù về lý thuyết không nên âm)
    IF NEW.quantity_remaining <= 0 AND OLD.quantity_remaining > 0 THEN
        NEW.status := 'Completed';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS tr_close_filled_order ON orders;
CREATE TRIGGER tr_close_filled_order
BEFORE UPDATE
ON orders
FOR EACH ROW
EXECUTE FUNCTION fn_close_filled_order();



--  Trigger khớp lệnh ưu tiên
CREATE OR REPLACE FUNCTION fn_match_order()
RETURNS TRIGGER AS
$$
DECLARE
    v_match RECORD;
    v_matched_qty INT;
    v_new_remaining INT;
    v_match_remaining INT;
    v_matched_price NUMERIC(10,2);
BEGIN
    -- Nếu lệnh mới là BUY: tìm SELL phù hợp từ người khác
    IF NEW.order_type = 'BUY' THEN
        LOOP
            SELECT order_id, quantity_remaining, created_at, price
              INTO v_match
              FROM orders
             WHERE stock_id = NEW.stock_id
               AND order_type = 'SELL'
               AND status = 'Pending'
               AND price <= NEW.price
               AND account_id != NEW.account_id
             ORDER BY price ASC, created_at ASC
             LIMIT 1;

            IF NOT FOUND THEN
                EXIT;
            END IF;

            SELECT quantity_remaining INTO v_new_remaining FROM orders WHERE order_id = NEW.order_id;
            SELECT quantity_remaining INTO v_match_remaining FROM orders WHERE order_id = v_match.order_id;

            v_matched_qty := LEAST(v_new_remaining, v_match_remaining);
            v_matched_price := v_match.price;

            UPDATE orders
            SET quantity_remaining = quantity_remaining - v_matched_qty,
                status = CASE WHEN (quantity_remaining - v_matched_qty) = 0 THEN 'Completed' ELSE status END
            WHERE order_id = v_match.order_id;

            UPDATE orders
            SET quantity_remaining = quantity_remaining - v_matched_qty,
                status = CASE WHEN (quantity_remaining - v_matched_qty) = 0 THEN 'Completed' ELSE status END
            WHERE order_id = NEW.order_id;

            -- ✅ NEW là BUY → order1 = BUY, order2 = SELL
            INSERT INTO order_matching_log (order1_id, order2_id, matched_price, matched_quantity, matched_at)
            VALUES (NEW.order_id, v_match.order_id, v_matched_price, v_matched_qty, CURRENT_TIMESTAMP);

            SELECT quantity_remaining INTO v_new_remaining FROM orders WHERE order_id = NEW.order_id;
            IF v_new_remaining <= 0 THEN
                EXIT;
            END IF;
        END LOOP;

    -- Nếu lệnh mới là SELL: tìm BUY phù hợp từ người khác
    ELSIF NEW.order_type = 'SELL' THEN
        LOOP
            SELECT order_id, quantity_remaining, created_at, price
              INTO v_match
              FROM orders
             WHERE stock_id = NEW.stock_id
               AND order_type = 'BUY'
               AND status = 'Pending'
               AND price >= NEW.price
               AND account_id != NEW.account_id
             ORDER BY price DESC, created_at ASC
             LIMIT 1;

            IF NOT FOUND THEN
                EXIT;
            END IF;

            SELECT quantity_remaining INTO v_new_remaining FROM orders WHERE order_id = NEW.order_id;
            SELECT quantity_remaining INTO v_match_remaining FROM orders WHERE order_id = v_match.order_id;

            v_matched_qty := LEAST(v_new_remaining, v_match_remaining);
            v_matched_price := v_match.price;

            UPDATE orders
            SET quantity_remaining = quantity_remaining - v_matched_qty,
                status = CASE WHEN (quantity_remaining - v_matched_qty) = 0 THEN 'Completed' ELSE status END
            WHERE order_id = v_match.order_id;

            UPDATE orders
            SET quantity_remaining = quantity_remaining - v_matched_qty,
                status = CASE WHEN (quantity_remaining - v_matched_qty) = 0 THEN 'Completed' ELSE status END
            WHERE order_id = NEW.order_id;

            -- ✅ v_match là BUY → order1 = BUY, NEW là SELL → order2
            INSERT INTO order_matching_log (order1_id, order2_id, matched_price, matched_quantity, matched_at)
            VALUES (v_match.order_id, NEW.order_id, v_matched_price, v_matched_qty, CURRENT_TIMESTAMP);

            SELECT quantity_remaining INTO v_new_remaining FROM orders WHERE order_id = NEW.order_id;
            IF v_new_remaining <= 0 THEN
                EXIT;
            END IF;
        END LOOP;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS tr_match_order ON orders;
CREATE TRIGGER tr_match_order
AFTER INSERT
ON orders
FOR EACH ROW
EXECUTE FUNCTION fn_match_order();




-- Trigger sau khi khớp lệnh
CREATE OR REPLACE FUNCTION fn_finalize_trade_v2()
RETURNS TRIGGER AS
$$
DECLARE
    v_order1 RECORD;
    v_order2 RECORD;
    v_buyer_id INT;
    v_seller_id INT;
    v_stock_id INT;
    v_matched_price NUMERIC(10,2);
    v_matched_quantity INT;
    v_price_difference NUMERIC(10,2);
    v_new_balance NUMERIC(15,2);
    v_new_quantity INT;
BEGIN
    -- Lấy thông tin 2 lệnh
    SELECT * INTO v_order1 FROM orders WHERE order_id = NEW.order1_id;
    SELECT * INTO v_order2 FROM orders WHERE order_id = NEW.order2_id;

    v_stock_id := v_order1.stock_id;
    v_matched_price := NEW.matched_price;
    v_matched_quantity := NEW.matched_quantity;

    -- Phân biệt bên mua và bán
    IF v_order1.order_type = 'BUY' THEN
        v_buyer_id := v_order1.account_id;
        v_seller_id := v_order2.account_id;

        -- Cộng cổ phiếu cho người mua
        INSERT INTO portfolios (stock_id, account_id, quantity, date)
        VALUES (v_stock_id, v_buyer_id, v_matched_quantity, CURRENT_TIMESTAMP)
        ON CONFLICT (stock_id, account_id) DO UPDATE
        SET quantity = portfolios.quantity + EXCLUDED.quantity,
            date = CURRENT_TIMESTAMP;

        -- Lấy số lượng mới để ghi log
        SELECT quantity INTO v_new_quantity
        FROM portfolios
        WHERE stock_id = v_stock_id AND account_id = v_buyer_id;

        -- Ghi log danh mục
        INSERT INTO portfolio_change_log (
            account_id, stock_id, change_quantity, new_quantity,
            change_type, related_order_id, created_at
        )
        VALUES (
            v_buyer_id, v_stock_id, v_matched_quantity, v_new_quantity,
            'BuyMatched', NEW.order1_id, CURRENT_TIMESTAMP
        );

        -- Cộng tiền cho người bán
        UPDATE accounts
        SET balance = balance + (v_matched_quantity * v_matched_price)
        WHERE account_id = v_seller_id;

        SELECT balance INTO v_new_balance FROM accounts WHERE account_id = v_seller_id;

        INSERT INTO account_balance_log (
            account_id, change_amount, new_balance,
            change_type, related_order_id, created_at
        )
        VALUES (
            v_seller_id, v_matched_quantity * v_matched_price, v_new_balance,
            'SellExecuted', NEW.order2_id, CURRENT_TIMESTAMP
        );

        -- Hoàn tiền dư nếu cần
        IF v_order1.price > v_matched_price THEN
            v_price_difference := (v_order1.price - v_matched_price) * v_matched_quantity;

            UPDATE accounts
            SET balance = balance + v_price_difference
            WHERE account_id = v_buyer_id;

            SELECT balance INTO v_new_balance FROM accounts WHERE account_id = v_buyer_id;

            INSERT INTO account_balance_log (
                account_id, change_amount, new_balance,
                change_type, related_order_id, created_at
            )
            VALUES (
                v_buyer_id, v_price_difference, v_new_balance,
                'BuyRefund', NEW.order1_id, CURRENT_TIMESTAMP
            );
        END IF;

    ELSE
        -- Trường hợp order1 là SELL
        v_seller_id := v_order1.account_id;
        v_buyer_id := v_order2.account_id;

        -- Cộng cổ phiếu cho người mua
        INSERT INTO portfolios (stock_id, account_id, quantity, date)
        VALUES (v_stock_id, v_buyer_id, v_matched_quantity, CURRENT_TIMESTAMP)
        ON CONFLICT (stock_id, account_id) DO UPDATE
        SET quantity = portfolios.quantity + EXCLUDED.quantity,
            date = CURRENT_TIMESTAMP;

        SELECT quantity INTO v_new_quantity
        FROM portfolios
        WHERE stock_id = v_stock_id AND account_id = v_buyer_id;

        INSERT INTO portfolio_change_log (
            account_id, stock_id, change_quantity, new_quantity,
            change_type, related_order_id, created_at
        )
        VALUES (
            v_buyer_id, v_stock_id, v_matched_quantity, v_new_quantity,
            'BuyMatched', NEW.order2_id, CURRENT_TIMESTAMP
        );

        -- Cộng tiền cho người bán
        UPDATE accounts
        SET balance = balance + (v_matched_quantity * v_matched_price)
        WHERE account_id = v_seller_id;

        SELECT balance INTO v_new_balance FROM accounts WHERE account_id = v_seller_id;

        INSERT INTO account_balance_log (
            account_id, change_amount, new_balance,
            change_type, related_order_id, created_at
        )
        VALUES (
            v_seller_id, v_matched_quantity * v_matched_price, v_new_balance,
            'SellExecuted', NEW.order1_id, CURRENT_TIMESTAMP
        );

        -- Hoàn tiền nếu BUY đặt giá cao hơn
        IF v_order2.price > v_matched_price THEN
            v_price_difference := (v_order2.price - v_matched_price) * v_matched_quantity;

            UPDATE accounts
            SET balance = balance + v_price_difference
            WHERE account_id = v_buyer_id;

            SELECT balance INTO v_new_balance FROM accounts WHERE account_id = v_buyer_id;

            INSERT INTO account_balance_log (
                account_id, change_amount, new_balance,
                change_type, related_order_id, created_at
            )
            VALUES (
                v_buyer_id, v_price_difference, v_new_balance,
                'BuyRefund', NEW.order2_id, CURRENT_TIMESTAMP
            );
        END IF;
    END IF;

    -- Ghi giao dịch cho cả 2 lệnh
    INSERT INTO transactions (order_id, executed_at, quantity, matched_price)
    VALUES 
        (NEW.order1_id, CURRENT_TIMESTAMP, v_matched_quantity, v_matched_price),
        (NEW.order2_id, CURRENT_TIMESTAMP, v_matched_quantity, v_matched_price);

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;



CREATE TRIGGER trg_finalize_trade
AFTER INSERT ON order_matching_log
FOR EACH ROW
EXECUTE FUNCTION fn_finalize_trade_v2();





-- TRigger xóa portfolios khi quantity = 0
CREATE OR REPLACE FUNCTION delete_zero_quantity()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.quantity = 0 THEN
        DELETE FROM portfolios WHERE portfolios_id = NEW.portfolios_id;
        RETURN NULL; -- Bản ghi đã bị xóa nên không trả về NEW nữa
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER trg_delete_zero_quantity
BEFORE INSERT OR UPDATE ON portfolios
FOR EACH ROW EXECUTE FUNCTION delete_zero_quantity();



-- Cancel order
CREATE OR REPLACE FUNCTION fn_refund_on_cancel()
RETURNS TRIGGER AS $$
DECLARE
    refund_amount NUMERIC(15,2);
BEGIN
  -- Chỉ xử lý khi chuyển sang trạng thái Cancelled
  IF NEW.status = 'Cancelled' AND OLD.status <> 'Cancelled' THEN

    -- Nếu là BUY: hoàn lại tiền
    IF NEW.order_type = 'BUY' THEN
      refund_amount := NEW.quantity_remaining * NEW.price;

      UPDATE accounts
      SET balance = balance + refund_amount
      WHERE account_id = NEW.account_id;

      INSERT INTO account_balance_log (
        account_id, change_amount, new_balance, change_type, related_order_id, created_at
      )
      VALUES (
        NEW.account_id,
        refund_amount,
        (SELECT balance FROM accounts WHERE account_id = NEW.account_id),
        'ManualAdjustment',
        NEW.order_id,
        CURRENT_TIMESTAMP
      );

    -- Nếu là SELL: hoàn lại cổ phiếu
    ELSIF NEW.order_type = 'SELL' THEN
      UPDATE portfolios
      SET quantity = quantity + NEW.quantity_remaining,
          date = CURRENT_TIMESTAMP
      WHERE account_id = NEW.account_id AND stock_id = NEW.stock_id;

      INSERT INTO portfolio_change_log (
        account_id, stock_id, change_quantity, new_quantity, change_type, related_order_id, created_at
      )
      VALUES (
        NEW.account_id,
        NEW.stock_id,
        NEW.quantity_remaining,
        (SELECT quantity FROM portfolios WHERE account_id = NEW.account_id AND stock_id = NEW.stock_id),
        'ManualAdjustment',
        NEW.order_id,
        CURRENT_TIMESTAMP
      );
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER trg_refund_on_cancel
AFTER UPDATE ON orders
FOR EACH ROW
WHEN (OLD.status IS DISTINCT FROM NEW.status AND NEW.status = 'Cancelled')
EXECUTE FUNCTION fn_refund_on_cancel();

-- Trigger để tự động ghi log mỗi khi user.is_active thay đổi hoặc password bị reset 
-- (trường hợp ai đó update trực tiếp bảng users)

CREATE OR REPLACE FUNCTION admin_trigger_log_user_update()
RETURNS TRIGGER AS $$
BEGIN
  IF OLD.is_active IS DISTINCT FROM NEW.is_active THEN
    INSERT INTO admin_user_action_log(admin_user_id, action, target_user_id, details)
    VALUES (
      1001,
      CASE WHEN NEW.is_active THEN 'enable_account' ELSE 'disable_account' END,
      NEW.user_id,
      jsonb_build_object('old_active', OLD.is_active, 'new_active', NEW.is_active)
    );
  END IF;

  IF OLD.password IS DISTINCT FROM NEW.password THEN
    INSERT INTO admin_user_action_log(admin_user_id, action, target_user_id, details)
    VALUES (
      1001,
      'reset_password_direct',
      NEW.user_id,
      jsonb_build_object('changed_at', now())
    );
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER admin_trigger_after_user_update
AFTER UPDATE ON users
FOR EACH ROW
EXECUTE FUNCTION admin_trigger_log_user_update();

-- Triggers: log direct updates on stocks và companies
CREATE OR REPLACE FUNCTION admin_trigger_log_stock_company_update()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_TABLE_NAME = 'stocks' THEN
        IF OLD.total_issued IS DISTINCT FROM NEW.total_issued THEN
            INSERT INTO admin_user_action_log(admin_user_id, action, target_user_id, details)
            VALUES(
                COALESCE(current_setting('app.current_admin_id')::INT, NULL),
                'update_stock_quantity',
                NEW.stock_id,
                jsonb_build_object('old', OLD.total_issued, 'new', NEW.total_issued)
            );
        END IF;
        IF OLD.status IS DISTINCT FROM NEW.status THEN
            INSERT INTO admin_user_action_log(admin_user_id, action, target_user_id, details)
            VALUES(
                COALESCE(current_setting('app.current_admin_id')::INT, NULL),
                'update_stock_status',
                NEW.stock_id,
                jsonb_build_object('old', OLD.status, 'new', NEW.status)
            );
        END IF;
    ELSIF TG_TABLE_NAME = 'companies' THEN
        IF OLD.company_name IS DISTINCT FROM NEW.company_name OR OLD.industry IS DISTINCT FROM NEW.industry OR OLD.website IS DISTINCT FROM NEW.website THEN
            INSERT INTO admin_user_action_log(admin_user_id, action, target_user_id, details)
            VALUES(
                COALESCE(current_setting('app.current_admin_id')::INT, NULL),
                'update_company_info',
                NEW.company_id,
                jsonb_build_object(
                    'old', jsonb_build_object('company_name', OLD.company_name, 'industry', OLD.industry, 'website', OLD.website),
                    'new', jsonb_build_object('company_name', NEW.company_name, 'industry', NEW.industry, 'website', NEW.website)
                )
            );
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER admin_trigger_after_stocks_update
    AFTER UPDATE ON stocks
    FOR EACH ROW EXECUTE FUNCTION admin_trigger_log_stock_company_update();

-- Update  at
CREATE OR REPLACE FUNCTION trg_set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS set_users_updated_at ON users;
CREATE TRIGGER set_users_updated_at
  BEFORE UPDATE ON users
  FOR EACH ROW
  EXECUTE FUNCTION trg_set_updated_at();

-- update bang stock_summary
CREATE OR REPLACE FUNCTION update_daily_summary()
RETURNS TRIGGER AS
$$
DECLARE
    v_stock_id INT;
    v_order_type VARCHAR(4);
    v_exists BOOLEAN;
    v_ref_price DECIMAL;
BEGIN
    -- Lấy stock_id và order_type từ orders
    SELECT stock_id, order_type INTO v_stock_id, v_order_type
    FROM orders
    WHERE order_id = NEW.order_id;

    -- Chỉ cập nhật nếu là lệnh BUY (để tránh nhân đôi volume)
    IF v_order_type != 'BUY' THEN
        RETURN NEW;
    END IF;

    -- Kiểm tra đã có bản ghi daily_stock_summary hôm nay chưa
    SELECT EXISTS (
        SELECT 1 FROM daily_stock_summary
        WHERE stock_id = v_stock_id AND summary_date = CURRENT_DATE
    ) INTO v_exists;

    IF v_exists THEN
        -- Cập nhật volume, high/low
        UPDATE daily_stock_summary
        SET 
            total_volume = total_volume + NEW.quantity,
            high_price = GREATEST(high_price, NEW.matched_price),
            low_price = LEAST(low_price, NEW.matched_price)
        WHERE stock_id = v_stock_id AND summary_date = CURRENT_DATE;

    ELSE
        -- Nếu chưa có thì tạo mới
        v_ref_price := NEW.matched_price;

        INSERT INTO daily_stock_summary (
            stock_id, summary_date, reference_price,
            ceiling_price, floor_price,
            total_volume, high_price, low_price
        )
        VALUES (
            v_stock_id,
            CURRENT_DATE,
            v_ref_price,
            ROUND(v_ref_price * 1.07, 2),
            ROUND(v_ref_price * 0.93, 2),
            NEW.quantity,
            v_ref_price,
            v_ref_price
        );
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


CREATE TRIGGER trg_update_daily_summary
AFTER INSERT ON transactions
FOR EACH ROW
EXECUTE FUNCTION update_daily_summary();


-- Cap nhat gia san/tran
CREATE OR REPLACE FUNCTION fn_update_daily_summary_from_price()
RETURNS TRIGGER AS
$$
DECLARE
    v_exists BOOLEAN;
    v_ref_price DECIMAL;
BEGIN
    -- Kiểm tra đã có bản ghi cho ngày hôm nay chưa
    SELECT EXISTS (
        SELECT 1 FROM daily_stock_summary
        WHERE stock_id = NEW.stock_id AND summary_date = CURRENT_DATE
    ) INTO v_exists;

    IF v_exists THEN
        -- Nếu có thì cập nhật giá cao nhất / thấp nhất
        UPDATE daily_stock_summary
        SET
            high_price = GREATEST(high_price, NEW.current_price),
            low_price  = LEAST(low_price, NEW.current_price)
        WHERE stock_id = NEW.stock_id AND summary_date = CURRENT_DATE;

    ELSE
        -- Nếu chưa có thì tạo mới bản ghi
        -- Giả sử current_price là giá tham chiếu (có thể điều chỉnh lại nếu bạn có nguồn tốt hơn)
        v_ref_price := NEW.current_price;

        INSERT INTO daily_stock_summary (
            stock_id, summary_date, reference_price,
            ceiling_price, floor_price,
            total_volume, high_price, low_price
        )
        VALUES (
            NEW.stock_id,
            CURRENT_DATE,
            v_ref_price,
            ROUND(v_ref_price * 1.07, 2),
            ROUND(v_ref_price * 0.93, 2),
            0,
            v_ref_price,
            v_ref_price
        );
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER trg_update_daily_summary_from_price
AFTER INSERT ON real_time_price
FOR EACH ROW
EXECUTE FUNCTION fn_update_daily_summary_from_price();
