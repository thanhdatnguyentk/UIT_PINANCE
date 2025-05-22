from flask import Flask, render_template, request, redirect, url_for, flash, session
import hashlib
import datetime
from db import get_conn
from psycopg2 import extras
import pandas as pd
import datetime
from flask import jsonify
from app.admin import admin_bp
from waitress import serve

app = Flask(__name__)
app.register_blueprint(admin_bp)
app.secret_key = 'your_secret_key'

@app.context_processor
def utility_processor():
    def now():
        return datetime.datetime.now()
    return dict(now=now)
# Trang chủ: hiển thị trang dashboard nếu đã đăng nhập, ngược lại landing page
@app.route('/')
def index():
    if session.get('user_id'):
        return redirect(url_for('dashboard'))
    conn = get_conn()
    cur = conn.cursor()
    cur.execute("SELECT stock_id, total_shares, outstanding_shares, status, issue_date FROM stocks;")
    stocks = cur.fetchall()
    cur.close()
    conn.close()
    return render_template('index.html', stocks=stocks)


# Đăng ký
@app.route('/register', methods=['GET', 'POST'])
def register():
    if request.method == 'POST':
        first_name = request.form['first_name'].strip()
        last_name = request.form['last_name'].strip()
        gender = request.form['gender']
        birthday = request.form['birthday']
        email = request.form['email'].strip()
        phone = request.form['phone'].strip()
        payment_method = request.form['payment_method'].strip()
        password = request.form['password']
        confirm = request.form['confirm_password']

        if password != confirm:
            flash('Mật khẩu xác nhận không khớp!', 'error')
            return redirect(url_for('register'))

        try:
            bd = datetime.datetime.strptime(birthday, '%Y-%m-%d').date()
            if bd > datetime.date.today():
                flash('Ngày sinh không được lớn hơn hôm nay!', 'error')
                return redirect(url_for('register'))
        except ValueError:
            flash('Định dạng ngày sinh không hợp lệ!', 'error')
            return redirect(url_for('register'))

        hashed = hashlib.sha256(password.encode()).hexdigest()

        try:
            conn = get_conn()
            cur = conn.cursor()
            cur.execute(
                "INSERT INTO users (first_name, last_name, gender, birthday, email, phone, payment_method, password) VALUES (%s, %s, %s, %s, %s, %s, %s, %s);",
                (first_name, last_name, gender, birthday, email, phone, payment_method, hashed)
            )
            # thêm cho người dùng 1000 đô vào tài khoản
            #get account_id
            cur.execute(
                "SELECT account_id FROM accounts WHERE user_id = currval('users_user_id_seq');"
            )
            acc_id = cur.fetchone()[0]
            cur.execute(
                "UPDATE accounts set balance = 10000 where account_id = %s;",
                (acc_id, )
            )
            # thêm cho người dùng 100 stock mỗi loại cổ phiếu
            cur.execute(
                """
                INSERT INTO portfolios (account_id, stock_id,date, quantity)
                SELECT %s, stock_id, now(), 100
                FROM stocks;
                """
                , (acc_id, )
            )
            conn.commit()
            cur.close()
            conn.close()
            flash('Đăng ký thành công! Vui lòng đăng nhập.', 'success')
            return redirect(url_for('login'))
        except Exception as e:
            flash(f'Lỗi khi đăng ký: {e}', 'error')
            return redirect(url_for('register'))

    return render_template('register.html', max_date=datetime.date.today().isoformat())

# Đăng nhập
@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        email = request.form['email'].strip()
        password = request.form['password']
        hashed = hashlib.sha256(password.encode()).hexdigest()

        conn = get_conn()
        cur = conn.cursor(cursor_factory=extras.DictCursor)
        cur.execute(
            "SELECT user_id, first_name FROM users WHERE email = %s AND password = %s;",
            (email, hashed)
        )
        user = cur.fetchone()
        cur.close()
        conn.close()

        if user:
            session['user_id'] = user['user_id']
            session['first_name'] = user['first_name']
            flash(f'Chào mừng {user[1]}!', 'success')
            return redirect(url_for('index'))
        else:
            flash('Email hoặc mật khẩu không đúng!', 'error')
            return redirect(url_for('login'))

    return render_template('login.html')
# Dashboard
@app.route('/dashboard')
def dashboard():
    if not session.get('user_id'):
        return redirect(url_for('login'))
    conn = get_conn()
    cur = conn.cursor(cursor_factory=extras.DictCursor)
    cur.execute("SELECT first_name, last_name FROM users WHERE user_id = %s", (session['user_id'],))
    user = cur.fetchone()
    cur.execute("SELECT account_id, account_type, balance FROM accounts WHERE user_id = %s", (session['user_id'],))
    accounts = cur.fetchall()
    cur.execute("SELECT COUNT(*) FROM deposits WHERE account_id IN (SELECT account_id FROM accounts WHERE user_id=%s)", (session['user_id'],))
    total_deposits = cur.fetchone()[0]
    cur.execute("SELECT COUNT(*) FROM withdrawals WHERE account_id IN (SELECT account_id FROM accounts WHERE user_id=%s)", (session['user_id'],))
    total_withdrawals = cur.fetchone()[0]
    cur.close()
    conn.close()
    return render_template('dashboard.html', user=user, accounts=accounts,
                           total_deposits=total_deposits, total_withdrawals=total_withdrawals)

# Watchlist: xem danh mục cổ phiếu
@app.route('/watchlist')
def watchlist():

    conn = get_conn()
    cur = conn.cursor(cursor_factory=extras.DictCursor)
    # Lấy thông tin user để dropdown
    cur.execute("SELECT first_name, last_name, email FROM users WHERE user_id = %s", (session['user_id'],))
    user = cur.fetchone()
    user_email = user['email']
    # Lấy danh sách portfolios
    cur.execute(
        """
        SELECT p.portfolios_id, c.ticker_symbol, c.company_name,
               p.quantity, p.date
        FROM portfolios p
        JOIN stocks s ON p.stock_id = s.stock_id
        JOIN companies c ON s.company_id = c.company_id
        JOIN accounts a ON p.account_id = a.account_id
        WHERE a.user_id = %s
        ORDER BY p.date DESC;
        """, (session['user_id'],)
    )
    portfolios = cur.fetchall()
    

    cur.close()
    conn.close()
    return render_template('watchlist.html', portfolios=portfolios, user=user, user_email=user_email)

# Nạp tiền
@app.route('/deposit', methods=['GET', 'POST'])
def deposit():
    if not session.get('user_id'):
        return redirect(url_for('login'))
    conn = get_conn()
    cur = conn.cursor(cursor_factory=extras.DictCursor)
    # Lấy thông tin user cho dropdown
    cur.execute("SELECT first_name, last_name, email FROM users WHERE user_id = %s", (session['user_id'],))
    user = cur.fetchone()
    user_email = user['email']
    # Lấy danh sách tài khoản của user
    cur.execute("SELECT account_id, account_type, balance FROM accounts WHERE user_id = %s", (session['user_id'],))
    accounts = cur.fetchall()
    if request.method == 'POST':
        account_id = request.form['account_id']
        amount = request.form['amount']
        cur.execute(
            "INSERT INTO deposits (account_id, amount) VALUES (%s, %s);",
            (account_id, amount)
        )
        conn.commit()

        conn.commit()
        flash('Nạp tiền thành công!', 'success')
        return redirect(url_for('deposit'))
    cur.close()
    conn.close()
    return render_template('deposit.html', accounts=accounts, user=user, user_email=user_email)

# Rút tiền
@app.route('/withdraw', methods=['GET', 'POST'])
def withdraw():
    if not session.get('user_id'):
        return redirect(url_for('login'))
    
    conn = get_conn()
    cur = conn.cursor(cursor_factory=extras.DictCursor)
    # Lấy thông tin user cho dropdown
    cur.execute("SELECT first_name, last_name, email FROM users WHERE user_id = %s", (session['user_id'],))
    user = cur.fetchone()
    user_email = user['email']
    cur.execute("SELECT account_id, account_type, balance FROM accounts WHERE user_id = %s", (session['user_id'],))
    accounts = cur.fetchall()
    if request.method == 'POST':
        account_id = request.form['account_id']
        amount = float(request.form['amount'])
        # Kiểm tra số dư
        cur.execute("SELECT balance FROM accounts WHERE account_id = %s", (account_id,))
        balance = cur.fetchone()['balance']
        if amount > balance:
            flash('Số tiền rút vượt quá số dư!', 'error')
        else:
            cur.execute(
                "INSERT INTO withdrawals (account_id, amount) VALUES (%s, %s);",
                (account_id, amount)
            )
        
            conn.commit()
            flash('Rút tiền thành công!', 'success')
        return redirect(url_for('withdraw'))
    cur.close()
    conn.close()
    return render_template('withdraw.html', accounts=accounts, user=user, user_email=user_email) 
# Chỉnh sửa thông tin cá nhân
@app.route('/profile/edit', methods=['GET', 'POST'])
def edit_profile():
    if not session.get('user_id'):
        return redirect(url_for('login'))

    conn = get_conn()
    cur = conn.cursor(cursor_factory=extras.DictCursor)
    # Lấy thông tin user hiện tại
    cur.execute("""
        SELECT first_name, last_name, gender, birthday, email, phone, payment_method
        FROM users
        WHERE user_id = %s
    """, (session['user_id'],))
    user = cur.fetchone()

    if request.method == 'POST':
        # Đọc dữ liệu từ form
        first_name     = request.form['first_name'].strip()
        last_name      = request.form['last_name'].strip()
        gender         = request.form['gender']
        birthday       = request.form['birthday']
        email          = request.form['email'].strip()
        phone          = request.form['phone'].strip()
        payment_method = request.form['payment_method'].strip()

        # Cập nhật vào DB
        cur.execute("""
            UPDATE users
            SET first_name=%s, last_name=%s, gender=%s,
                birthday=%s, email=%s, phone=%s, payment_method=%s
            WHERE user_id = %s
        """, (
            first_name, last_name, gender,
            birthday, email, phone, payment_method,
            session['user_id']
        ))
        conn.commit()
        flash('Cập nhật thông tin thành công!', 'success')
        cur.close()
        conn.close()
        return redirect(url_for('edit_profile'))

    cur.close()
    conn.close()
    return render_template(
        'edit_profile.html',
        user=user,
        max_date=datetime.date.today().isoformat()
    )
# Đăng xuất
@app.route('/logout')
def logout():
    session.clear()
    flash('Bạn đã đăng xuất.', 'success')
    return redirect(url_for('login'))

@app.route('/markets')
def markets():
    if not session.get('user_id'):
        return redirect(url_for('login'))
        
    conn = get_conn()
    cur = conn.cursor(cursor_factory=extras.DictCursor)
    
    # Lấy thông tin user cho profile dropdown
    cur.execute("SELECT first_name, last_name, email FROM users WHERE user_id = %s", (session['user_id'],))
    user = cur.fetchone()
    user_email = user['email']
    
    # Lấy thông tin bảng giá từ view v_stock_market_board
    cur.execute(
        """
        SELECT 
            stock_id, "CK", "Trần", "Sàn", "TC",
            "Giá 3 Mua", "KL 3 Mua", 
            "Giá 2 Mua", "KL 2 Mua", 
            "Giá 1 Mua", "KL 1 Mua",
            "Giá 1 Bán", "KL 1 Bán", 
            "Giá 2 Bán", "KL 2 Bán", 
            "Giá 3 Bán", "KL 3 Bán",
            "Tổng KL", "Cao", "Thấp"
        FROM v_stock_market_board
        WHERE "CK" IS NOT NULL
        ORDER BY "CK"
        """
    )
    market_data = cur.fetchall()
    
    # Lấy giá hiện tại từ real_time_price
    cur.execute(
        """
        SELECT s.stock_id, MAX(r.current_price) AS current_price
        FROM stocks s
        JOIN companies c ON s.company_id = c.company_id
        LEFT JOIN (
            SELECT stock_id, current_price, 
                   ROW_NUMBER() OVER (PARTITION BY stock_id ORDER BY timestamp DESC) as rn
            FROM real_time_price
        ) r ON s.stock_id = r.stock_id AND r.rn = 1
        GROUP BY s.stock_id
        """
    )
    current_prices = {row['stock_id']: row['current_price'] for row in cur.fetchall()}
    
    cur.close()
    conn.close()
    
    return render_template('markets.html', 
                          user=user, 
                          user_email=user_email, 
                          market_data=market_data,
                          current_prices=current_prices)

@app.route('/stocks/<int:stock_id>')
def stock_detail(stock_id):
    if not session.get('user_id'):
        return redirect(url_for('login'))
    conn = get_conn()
    cur = conn.cursor(cursor_factory=extras.DictCursor)
    # Thông tin cơ bản
    cur.execute(
        """
        SELECT c.company_name, c.ticker_symbol, s.total_shares, s.outstanding_shares, s.status
        FROM stocks s
        JOIN companies c ON s.company_id = c.company_id
        WHERE s.stock_id = %s;
        """, (stock_id,)
    )
    stock = cur.fetchone()
    # Lấy giá mới nhất
    cur.execute(
        "SELECT current_price, timestamp"
        " FROM real_time_price"
        " WHERE stock_id = %s"
        " ORDER BY timestamp DESC LIMIT 10;",
        (stock_id,)
    )
    latest = cur.fetchone()
    # Dữ liệu 1 tháng
    cur.execute(
        "SELECT timestamp, current_price"
        " FROM real_time_price"
        " WHERE stock_id = %s"
        " ORDER BY timestamp DESC LIMIT 30;",
        (stock_id,)
    )
    series = cur.fetchall()
    # User for dropdown
    cur.execute("SELECT first_name, last_name, email FROM users WHERE user_id = %s", (session['user_id'],))
    user = cur.fetchone()
    user_email = user['email']
    cur.close()
    conn.close()
    return render_template(
        'stock_detail.html', stock=stock, latest=latest,
        series=series, user=user, user_email=user_email
    )

# Order Entry & Place Order route
@app.route('/stocks/<int:stock_id>/order', methods=['GET','POST'])
def order_entry(stock_id):
    if not session.get('user_id'):
        return redirect(url_for('login'))
    conn = get_conn()
    cur = conn.cursor(cursor_factory=extras.DictCursor)
    
    # Thông tin cơ bản
    cur.execute(
        """
        SELECT c.company_name, c.ticker_symbol, s.total_shares, s.outstanding_shares, s.status
        FROM stocks s
        JOIN companies c ON s.company_id = c.company_id
        WHERE s.stock_id = %s;
        """, (stock_id,)
    )
    stock = cur.fetchone()
    
    # Thông tin công ty
    cur.execute(
        """
        SELECT c.company_name, c.ticker_symbol, c.description, c.industry, c.listed_date, c.head_quarters, c.website
        FROM stocks s
        JOIN companies c ON s.company_id = c.company_id
        WHERE s.stock_id = %s;
        """, (stock_id,)
    )
    company = cur.fetchone()

    # Lấy thông tin công ty từ bảng company_indicators
    cur.execute(
        """
        SELECT ci.*
        FROM company_indicators ci
        JOIN stocks s ON ci.company_id = s.company_id
        WHERE s.stock_id = %s
        ORDER BY ci.report_date DESC
        LIMIT 1;
        """, (stock_id,)
    )
    company_indicators = cur.fetchone()

    # Lấy thông tin giá tham chiếu, giá trần, giá sàn mới nhất
    cur.execute(
        """
        SELECT reference_price, ceiling_price, floor_price, high_price, low_price, total_volume
        FROM daily_stock_summary
        WHERE stock_id = %s
        ORDER BY summary_date DESC
        LIMIT 1;
        """, (stock_id,)
    )
    price_info = cur.fetchone()
    
    # Lấy giá mới nhất (chỉ có stock_id, timestamp, current_price)
    cur.execute(
        "SELECT current_price, timestamp "
        "FROM real_time_price "
        "WHERE stock_id = %s "
        "ORDER BY timestamp DESC LIMIT 1;",
        (stock_id,)
    )
    latest = cur.fetchone()
    
    # Xử lý trường hợp không có real-time data
    if latest is None:
        # Set giá trị mặc định để tránh lỗi
        latest = {"current_price": 0, "timestamp": datetime.datetime.now()}
    
    # Lấy lịch sử giá cho biểu đồ
    cur.execute(
        "SELECT timestamp, current_price "
        "FROM real_time_price "
        "WHERE stock_id = %s "
        "ORDER BY timestamp DESC LIMIT 24;",
        (stock_id,)
    )
    series = cur.fetchall()
    
    # Lấy danh sách tài khoản của user
    cur.execute(
        "SELECT account_id, account_type, balance FROM accounts WHERE user_id = %s",
        (session['user_id'],)
    )
    accounts = cur.fetchall()
    
    # Lấy thông tin user cho dropdown
    cur.execute(
        "SELECT first_name, last_name, email FROM users WHERE user_id = %s",
        (session['user_id'],)
    )
    user = cur.fetchone()
    user_email = user['email']
    
    # Lấy top 3 buy orders có giá cao nhất
    cur.execute("""
        SELECT price, total_quantity 
        FROM v_top_buy_orders 
        WHERE stock_id = %s
    """, (stock_id,))
    top_buy_orders = cur.fetchall()
    
    # Lấy top 3 sell orders có giá thấp nhất
    cur.execute("""
        SELECT price, total_quantity 
        FROM v_top_sell_orders
        WHERE stock_id = %s
    """, (stock_id,))
    top_sell_orders = cur.fetchall()
    
    # Phần xử lý POST request...
    if request.method == 'POST':
        try:
            # Lấy dữ liệu từ form
            side = request.form.get('side')  # 'buy' hoặc 'sell'
            price = float(request.form.get('price'))
            size = int(float(request.form.get('size')))  # Chuyển đổi từ float sang int
            order_type = request.form.get('order_type', 'limit')  # Mặc định là limit
            
            # Kiểm tra dữ liệu đầu vào
            if not side or not price or not size or price <= 0 or size <= 0:
                flash('Vui lòng nhập đầy đủ thông tin hợp lệ', 'error')
                return redirect(url_for('order_entry', stock_id=stock_id))
            
            # Kiểm tra giá trần/sàn nếu có thông tin giá
            if price_info:
                ceiling_price = float(price_info['ceiling_price'])
                floor_price = float(price_info['floor_price'])
                
                if price > ceiling_price:
                    flash(f'Giá đặt ({price}) vượt quá giá trần ({ceiling_price})', 'error')
                    return redirect(url_for('order_entry', stock_id=stock_id))
                    
                if price < floor_price:
                    flash(f'Giá đặt ({price}) thấp hơn giá sàn ({floor_price})', 'error')
                    return redirect(url_for('order_entry', stock_id=stock_id))
            
            # Chuyển đổi side thành order_type đúng format cho DB
            order_type_db = 'BUY' if side == 'buy' else 'SELL'
            
            # Lấy tài khoản đầu tiên của user (hoặc có thể cho phép user chọn tài khoản)
            if not accounts or len(accounts) == 0:
                flash('Không tìm thấy tài khoản hợp lệ', 'error')
                return redirect(url_for('order_entry', stock_id=stock_id))
                
            account_id = accounts[0]['account_id']
            
            # Kiểm tra số dư tài khoản nếu là lệnh mua
            if side == 'buy':
                total_cost = price * size
                
                if accounts[0]['balance'] < total_cost:
                    flash(f'Số dư không đủ để đặt lệnh mua. Cần {total_cost:,.2f}$, hiện có {accounts[0]["balance"]:,.2f}$', 'error')
                    return redirect(url_for('order_entry', stock_id=stock_id))
            
            # Thêm lệnh vào DB
            cur.execute("""
                INSERT INTO orders (account_id, stock_id, order_type, quantity, quantity_remaining, price, status)
                VALUES (%s, %s, %s, %s, %s, %s, 'Pending')
                RETURNING order_id;
            """, (account_id, stock_id, order_type_db, size, size, price))
            
            order_id = cur.fetchone()['order_id']
            conn.commit()
            
            flash(f'Đặt lệnh {side} thành công! Mã lệnh: {order_id}', 'success')
            return redirect(url_for('order_entry', stock_id=stock_id))
            
        except ValueError as e:
            flash(f'Dữ liệu không hợp lệ: {str(e)}', 'error')
            conn.rollback()
            
        except Exception as e:
            flash(f'Có lỗi xảy ra: {str(e)}', 'error')
            conn.rollback()
            
    # GET: render order entry page
    cur.close()
    conn.close()
    return render_template('order_entry.html', 
                          user=user, 
                          user_email=user_email, 
                          stock=stock, 
                          accounts=accounts, 
                          latest=latest,
                          series=series, 
                          company=company,
                          top_buy_orders=top_buy_orders,
                          top_sell_orders=top_sell_orders,
                          price_info=price_info,
                          company_indicators=company_indicators)

@app.route('/transactions')
def transactions():
    # Chuyển hướng nếu chưa login
    if not session.get('user_id'):
        return redirect(url_for('login'))

    conn = get_conn()
    cur = conn.cursor(cursor_factory=extras.DictCursor)

    # Truy vấn lịch sử giao dịch, join transactions → orders → stocks → companies
    # Thêm o.price để lấy giá đặt ban đầu
    cur.execute("""
        SELECT
          t.transaction_id,
          c.ticker_symbol,
          o.order_type,
          t.quantity,
          o.price as order_price,  -- Thêm giá đặt ban đầu
          t.matched_price,
          t.executed_at,
          s.stock_id    
        FROM transactions t
        JOIN orders o      ON t.order_id   = o.order_id
        JOIN stocks s      ON o.stock_id    = s.stock_id
        JOIN companies c   ON s.company_id  = c.company_id
        WHERE o.account_id IN (
          SELECT account_id FROM accounts WHERE user_id = %s
        )
        ORDER BY t.executed_at DESC;
    """, (session['user_id'],))

    transactions = cur.fetchall()

    # Lấy thông tin user cho dropdown
    cur.execute("SELECT first_name, last_name, email FROM users WHERE user_id=%s", (session['user_id'],))
    user = cur.fetchone()
    user_email = user['email']
    cur.close()
    conn.close()

    return render_template('transactions.html', user=user, user_email=user_email, transactions=transactions)

# Orderss page
@app.route('/pending_orders')
def pending_orders():
    if not session.get('user_id'):
        return redirect(url_for('login'))

    # 1) Lấy tham số lọc từ URL, mặc định là All
    status_filter = request.args.get('status', 'All')

    conn = get_conn()
    cur = conn.cursor(cursor_factory=extras.DictCursor)

    # 2) Chuyển thành điều kiện SQL: nếu 'All' thì không lọc, ngược lại so sánh o.status
    sql = """
      SELECT o.order_id, c.ticker_symbol, o.order_type, o.quantity, o.price, o.created_at, o.status,
             o.quantity_remaining
      FROM orders o
      JOIN stocks s ON o.stock_id = s.stock_id
      JOIN companies c ON s.company_id = c.company_id
      WHERE o.account_id IN (
        SELECT account_id FROM accounts WHERE user_id = %s
      )
      AND (%s = 'All' OR o.status = %s)
      ORDER BY o.created_at DESC
    """
    cur.execute(sql, (session['user_id'], status_filter, status_filter))
    orders = cur.fetchall()

    # 3) Lấy thông tin user cho dropdown
    cur.execute("SELECT first_name, last_name, email FROM users WHERE user_id=%s", (session['user_id'],))
    user = cur.fetchone()
    user_email = user['email']

    cur.close()
    conn.close()

    return render_template(
        'pending_orders.html',
        orders=orders,
        user=user,
        user_email=user_email,
        status_filter=status_filter  # truyền xuống template
    )

@app.route('/help')
def help_page():
    # Lấy thông tin user cho dropdown
    conn = get_conn()
    cur = conn.cursor(cursor_factory=extras.DictCursor)
    cur.execute("SELECT first_name, last_name, email FROM users WHERE user_id = %s", (session['user_id'],))
    user = cur.fetchone()
    user_email = user['email']
    cur.close()
    conn.close()
    # Render template help.html
    return render_template('help.html', user=user, user_email=user_email)

# Unified Company Search (lookup by ticker OR search by name)
@app.route('/company_search', methods=['GET', 'POST'])
def company_search():

    query = None
    company = None
    results = []
    
    # Use GET for search form
    if request.method == 'GET':
        query = request.args.get('query', '').strip()
    # Allow POST as well
    if request.method == 'POST':
        query = request.form.get('query', '').strip()


    conn = get_conn()
    cur = conn.cursor(cursor_factory=extras.DictCursor)
    cur.execute("SELECT first_name, last_name, email FROM users WHERE user_id = %s", (session['user_id'],))
    user = cur.fetchone()
    user_email = user['email']
    # First, try lookup by ticker (exact match)
    try:
        ticker = query.upper()
        # CALL procedure, using placeholders for OUT params
        cur.execute(
            "CALL UC17_get_company_info_by_ticker(%s, %s, %s, %s, %s, %s, %s, %s)",
            [ticker, None, None, None, None, None, None, None]
        )
        # Fetch OUT params
        cur.execute("SELECT p_company_id, p_company_name, p_description, p_ticker_symbol, p_industry, p_listed_date, p_head_quarters, p_website;")
        company = cur.fetchone()
    except Exception:
        # Not found or error, ignore and fallback to name search
        conn.rollback()
    # If no exact ticker - or simply always do name search as well
    try:
        name_pattern = query
        cur.execute("SELECT * FROM UC_17_search_companies_by_name(%s)", [name_pattern])
        results = cur.fetchall()
        ticker_list = [r['ticker_symbol'] for r in results]

    except Exception as e:
        flash(f'Lỗi khi tìm kiếm công ty: {e}', 'error')
    finally:
        cur.close()
        conn.close()

    return render_template(
        'company_search.html',
        query=query,
        company=company,
        results=results,
        user=user, 
        user_email=user_email
    )

@app.route('/asset_distribution')
def asset_distribution():
    if not session.get('user_id'):
        return redirect(url_for('login'))

    conn = get_conn()
    cur = conn.cursor(cursor_factory=extras.DictCursor)

    # Lấy thông tin user
    cur.execute("SELECT first_name, last_name, email FROM users WHERE user_id = %s", (session['user_id'],))
    user = cur.fetchone()
    user_email = user['email']

    # Lấy số dư tiền mặt
    cur.execute("SELECT SUM(balance) AS total_balance FROM accounts WHERE user_id = %s", (session['user_id'],))
    balance = cur.fetchone()['total_balance'] or 0

    # Lấy giá trị cổ phiếu
    cur.execute("""
        SELECT c.company_name AS label, SUM(p.quantity * r.current_price) AS value
        FROM portfolios p
        JOIN accounts a ON p.account_id = a.account_id
        JOIN stocks s ON p.stock_id = s.stock_id
        JOIN companies c ON s.company_id = c.company_id
        JOIN LATERAL (
            SELECT current_price FROM real_time_price
            WHERE stock_id = s.stock_id
            ORDER BY timestamp DESC
            LIMIT 1
        ) r ON TRUE
        WHERE a.user_id = %s
        GROUP BY c.company_name;
    """, (session['user_id'],))
    stock_data = cur.fetchall()

    # Lấy thông tin lợi nhuận theo cổ phiếu từ view v_loi_nhuan_theo_cp
    cur.execute("""
        SELECT ticker_symbol, gia_von_tb_con_lai, 
               qty_remaining, percent_loi_nhuan, loi_nhuan_gia_tri
        FROM v_loi_nhuan_theo_cp
        WHERE account_id IN (SELECT account_id FROM accounts WHERE user_id = %s)
    """, (session['user_id'],))
    profit_data = cur.fetchall()

    cur.execute("""
        SELECT log_id, created_at, movement_category, movement_type,
               account_id, stock_id, amount, new_value, change_quantity
        FROM v_asset_movements
        WHERE account_id IN (
            SELECT account_id FROM accounts WHERE user_id = %s
        )
        ORDER BY created_at 
        LIMIT 100;
    """, (session['user_id'],))
    movements = cur.fetchall()
    
    cur.execute("""
        SELECT created_at, new_balance
        FROM account_balance_log
        WHERE account_id IN (
          SELECT account_id FROM accounts WHERE user_id = %s
        )
        ORDER BY created_at;
    """, (session['user_id'],))
    cash_history = cur.fetchall()

    cur.close()
    conn.close()

    labels = ['Tiền mặt'] + [row['label'] for row in stock_data]
    values = [float(balance)] + [float(row['value']) for row in stock_data]

    # Tính tổng tài sản để hiển thị trong bảng phân bố
    total_assets = float(balance) + sum(float(row['value']) for row in stock_data)
    asset_distribution = [
        {'name': 'Tiền mặt', 'value': float(balance), 'percentage': (float(balance)/total_assets*100 if total_assets > 0 else 0)},
    ]
    for row in stock_data:
        asset_distribution.append({
            'name': row['label'],
            'value': float(row['value']),
            'percentage': (float(row['value'])/total_assets*100 if total_assets > 0 else 0)
        })

    return render_template('asset_distribution.html', 
                          cash_history=cash_history, 
                          labels=labels, 
                          values=values, 
                          movements=movements, 
                          user=user, 
                          user_email=user_email,
                          asset_distribution=asset_distribution,
                          profit_data=profit_data,
                          total_assets=total_assets)

@app.route('/reports', methods=['GET', 'POST'])
def reports():
    if not session.get('user_id'):
        return redirect(url_for('login'))
    
    conn = get_conn()
    cur = conn.cursor(cursor_factory=extras.DictCursor)
    
    # Get user info for dropdown
    cur.execute("SELECT first_name, last_name, email FROM users WHERE user_id = %s", (session['user_id'],))
    user = cur.fetchone()
    user_email = user['email']
    
    report_data = None
    selected_date = None
    report_type = None
    selected_account = None
    transaction_type = None
    start_date = None
    end_date = None
    accounts = []
    chart_data = {}
    
    # Lấy danh sách tài khoản của user
    cur.execute("SELECT account_id, account_type FROM accounts WHERE user_id = %s", (session['user_id'],))
    accounts = cur.fetchall()
    
    if request.method == 'POST':
        report_type = request.form.get('report_type')
        
        # Stock transactions report
        if report_type == 'stock_transactions':
            selected_date = request.form.get('report_date')
            
            if selected_date:  # Kiểm tra selected_date có tồn tại
                cur.execute("""
                    SELECT
                      ROW_NUMBER() OVER (ORDER BY oml.matched_at) AS stt,
                      c.ticker_symbol,
                      TO_CHAR(oml.matched_at, 'YYYY-MM-DD') AS ngay_giao_dich,
                      o.order_type,
                      CAST(o.price AS FLOAT) AS order_price,
                      CAST(oml.matched_price AS FLOAT) AS matched_price,
                      CAST(oml.matched_quantity AS FLOAT) AS matched_quantity,
                      CAST(oml.matched_price * oml.matched_quantity AS FLOAT) AS thanh_tien
                    FROM orders o
                    JOIN stocks s ON o.stock_id = s.stock_id
                    JOIN companies c ON s.company_id = c.company_id
                    JOIN order_matching_log oml
                      ON (oml.order1_id = o.order_id OR oml.order2_id = o.order_id)
                    WHERE DATE(oml.matched_at) = %s
                      AND o.status = 'Completed'
                      AND o.account_id IN (SELECT account_id FROM accounts WHERE user_id = %s)
                    ORDER BY oml.matched_at
                """, (selected_date, session['user_id']))
                
                report_data = cur.fetchall()
                # Chuyển đổi kiểu dữ liệu
                for row in report_data:
                    row['order_price'] = float(row['order_price'])
                    row['matched_price'] = float(row['matched_price'])
                    row['matched_quantity'] = float(row['matched_quantity'])
                    row['thanh_tien'] = float(row['thanh_tien'])
        
        # Stock holdings report (với biểu đồ donut)
        elif report_type == 'stock_holdings':
            selected_account = request.form.get('account_id')
            
            if selected_account:  # Kiểm tra selected_account có giá trị
                try:
                    account_id = int(selected_account)  # Chuyển đổi sang số nguyên
                    
                    # Lấy dữ liệu số lượng cổ phiếu
                    cur.execute("""
                        SELECT
                          ROW_NUMBER() OVER (ORDER BY c.ticker_symbol) AS stt,
                          c.ticker_symbol,
                          c.company_name,
                          CAST(SUM(p.quantity) AS INTEGER) AS so_luong
                        FROM portfolios p
                        JOIN stocks s ON p.stock_id = s.stock_id
                        JOIN companies c ON s.company_id = c.company_id
                        WHERE p.account_id = %s
                        GROUP BY c.ticker_symbol, c.company_name
                        ORDER BY c.ticker_symbol
                    """, (account_id,))
                    
                    report_data = cur.fetchall()
                    # Chuyển đổi kiểu dữ liệu
                    for row in report_data:
                        row['so_luong'] = int(row['so_luong'])
                    
                    # Lấy dữ liệu giá trị cổ phiếu cho biểu đồ
                    cur.execute("""
                        SELECT 
                            c.ticker_symbol,
                            CAST(SUM(p.quantity * r.current_price) AS FLOAT) AS value
                        FROM portfolios p
                        JOIN stocks s ON p.stock_id = s.stock_id
                        JOIN companies c ON s.company_id = c.company_id
                        JOIN LATERAL (
                            SELECT current_price FROM real_time_price
                            WHERE stock_id = s.stock_id
                            ORDER BY timestamp DESC
                            LIMIT 1
                        ) r ON TRUE
                        WHERE p.account_id = %s
                        GROUP BY c.ticker_symbol
                    """, (account_id,))
                    
                    chart_records = cur.fetchall()
                    chart_data = {
                        'labels': [row['ticker_symbol'] for row in chart_records],
                        'values': [float(row['value']) for row in chart_records]
                    }
                    
                except ValueError:
                    flash('Vui lòng chọn tài khoản hợp lệ', 'error')
            else:
                flash('Vui lòng chọn tài khoản', 'error')
            
        # Báo cáo lịch sử nạp/rút tiền (với biểu đồ cột đối xứng)
        elif report_type == 'money_transactions':
            selected_account = request.form.get('account_id_money')
            transaction_type = request.form.get('transaction_type')
            start_date = request.form.get('start_date')
            end_date = request.form.get('end_date')  # Thay đổi từ một ngày sang khoảng ngày
            
            # Kiểm tra các giá trị đầu vào
            if not selected_account or not start_date or not end_date:
                flash('Vui lòng chọn đầy đủ thông tin tài khoản và khoảng thời gian', 'error')
            else:
                try:
                    account_id = int(selected_account)
                    
                    if transaction_type == 'deposit':
                        # Chỉ lấy giao dịch nạp tiền
                        cur.execute("""
                            SELECT
                              ROW_NUMBER() OVER (ORDER BY abl.created_at) AS stt,
                              'Nạp tiền' AS loai_giao_dich,
                              CAST(abl.change_amount AS FLOAT) AS amount,
                              CAST(abl.new_balance AS FLOAT) AS so_du_moi,
                              TO_CHAR(abl.created_at, 'YYYY-MM-DD HH24:MI:SS') AS thoi_gian
                            FROM account_balance_log abl
                            WHERE abl.account_id = %s 
                              AND DATE(abl.created_at) BETWEEN %s AND %s
                              AND abl.change_type = 'Deposit'
                            ORDER BY abl.created_at
                        """, (account_id, start_date, end_date))
                        
                    elif transaction_type == 'withdrawal':
                        # Chỉ lấy giao dịch rút tiền
                        cur.execute("""
                            SELECT
                              ROW_NUMBER() OVER (ORDER BY abl.created_at) AS stt,
                              'Rút tiền' AS loai_giao_dich,
                              CAST(ABS(abl.change_amount) AS FLOAT) AS amount,
                              CAST(abl.new_balance AS FLOAT) AS so_du_moi,
                              TO_CHAR(abl.created_at, 'YYYY-MM-DD HH24:MI:SS') AS thoi_gian
                            FROM account_balance_log abl
                            WHERE abl.account_id = %s 
                              AND DATE(abl.created_at) BETWEEN %s AND %s
                              AND abl.change_type = 'Withdrawal'
                            ORDER BY abl.created_at
                        """, (account_id, start_date, end_date))
                        
                    else:  # all - lấy cả nạp và rút tiền
                        cur.execute("""
                            SELECT
                              ROW_NUMBER() OVER (ORDER BY abl.created_at) AS stt,
                              CASE 
                                WHEN abl.change_type = 'Deposit' THEN 'Nạp tiền'
                                WHEN abl.change_type = 'Withdrawal' THEN 'Rút tiền'
                                ELSE abl.change_type
                              END AS loai_giao_dich,
                              CASE 
                                WHEN abl.change_type = 'Deposit' THEN CAST(abl.change_amount AS FLOAT)
                                ELSE CAST(ABS(abl.change_amount) AS FLOAT)
                              END AS amount,
                              CAST(abl.new_balance AS FLOAT) AS so_du_moi,
                              TO_CHAR(abl.created_at, 'YYYY-MM-DD HH24:MI:SS') AS thoi_gian
                            FROM account_balance_log abl
                            WHERE abl.account_id = %s 
                              AND DATE(abl.created_at) BETWEEN %s AND %s
                              AND abl.change_type IN ('Deposit', 'Withdrawal')
                            ORDER BY abl.created_at
                        """, (account_id, start_date, end_date))
                    
                    report_data = cur.fetchall()
                    # Chuyển đổi kiểu dữ liệu
                    for row in report_data:
                        row['amount'] = float(row['amount'])
                        row['so_du_moi'] = float(row['so_du_moi'])
                    
                    # Thêm dữ liệu cho biểu đồ cột đối xứng
                    # Lấy tổng nạp và rút theo ngày
                    cur.execute("""
                        SELECT 
                            TO_CHAR(created_at, 'YYYY-MM-DD') AS ngay,
                            CAST(SUM(CASE WHEN change_type = 'Deposit' THEN change_amount ELSE 0 END) AS FLOAT) AS tong_nap,
                            CAST(SUM(CASE WHEN change_type = 'Withdrawal' THEN ABS(change_amount) ELSE 0 END) AS FLOAT) AS tong_rut
                        FROM account_balance_log
                        WHERE account_id = %s 
                          AND DATE(created_at) BETWEEN %s AND %s
                          AND change_type IN ('Deposit', 'Withdrawal')
                        GROUP BY TO_CHAR(created_at, 'YYYY-MM-DD')
                        ORDER BY ngay
                    """, (account_id, start_date, end_date))
                    
                    chart_records = cur.fetchall()
                    chart_data = {
                        'labels': [row['ngay'] for row in chart_records],
                        'deposits': [float(row['tong_nap']) for row in chart_records],
                        'withdrawals': [float(row['tong_rut']) for row in chart_records]
                    }
                    
                except ValueError:
                    flash('Vui lòng chọn tài khoản hợp lệ', 'error')
                    
        # Báo cáo biến động số dư (với biểu đồ đường)
        elif report_type == 'balance_history':
            selected_account = request.form.get('account_id_balance')
            start_date = request.form.get('start_date')
            end_date = request.form.get('end_date')
            
            if not selected_account or not start_date or not end_date:
                flash('Vui lòng chọn đầy đủ thông tin tài khoản và khoảng thời gian', 'error')
            else:
                try:
                    account_id = int(selected_account)
                    
                    cur.execute("""
                        SELECT
                          ROW_NUMBER() OVER (ORDER BY abl.created_at) AS stt,
                          TO_CHAR(abl.created_at, 'YYYY-MM-DD HH24:MI:SS') AS thoi_gian,
                          abl.change_type AS loai_bien_dong,
                          CAST(abl.change_amount AS FLOAT) AS so_tien_thay_doi,
                          CAST(abl.new_balance AS FLOAT) AS so_du_moi,
                          COALESCE(o.order_id::TEXT, '-') AS ma_lenh_lien_quan
                        FROM account_balance_log abl
                        LEFT JOIN orders o ON abl.related_order_id = o.order_id
                        WHERE abl.account_id = %s 
                          AND DATE(abl.created_at) BETWEEN %s AND %s
                        ORDER BY abl.created_at
                    """, (account_id, start_date, end_date))
                    
                    report_data = cur.fetchall()
                    # Chuyển đổi kiểu dữ liệu
                    for row in report_data:
                        row['so_tien_thay_doi'] = float(row['so_tien_thay_doi'])
                        row['so_du_moi'] = float(row['so_du_moi'])
                    
                    # Dữ liệu cho biểu đồ đường
                    cur.execute("""
                        SELECT 
                            TO_CHAR(created_at, 'YYYY-MM-DD') AS ngay,
                            CAST(MAX(new_balance) AS FLOAT) AS so_du_cuoi_ngay
                        FROM (
                            SELECT 
                                created_at,
                                new_balance,
                                ROW_NUMBER() OVER (PARTITION BY TO_CHAR(created_at, 'YYYY-MM-DD') ORDER BY created_at DESC) AS rn
                            FROM account_balance_log
                            WHERE account_id = %s
                              AND DATE(created_at) BETWEEN %s AND %s
                        ) as daily_balance
                        WHERE rn = 1
                        GROUP BY ngay
                        ORDER BY ngay
                    """, (account_id, start_date, end_date))
                    
                    chart_records = cur.fetchall()
                    chart_data = {
                        'labels': [row['ngay'] for row in chart_records],
                        'balances': [float(row['so_du_cuoi_ngay']) for row in chart_records]
                    }
                    
                except ValueError:
                    flash('Vui lòng chọn tài khoản hợp lệ', 'error')
    
    cur.close()
    conn.close()
    
    return render_template(
        'reports.html', 
        user=user, 
        user_email=user_email,
        report_data=report_data,
        report_type=report_type,
        selected_date=selected_date,
        selected_account=selected_account,
        transaction_type=transaction_type,
        start_date=start_date,
        end_date=end_date,
        accounts=accounts,
        chart_data=chart_data
    )
@app.route('/api/stocks', methods=['GET'])
def api_stocks():
    """
    API endpoint to return all stocks joined with real-time price data as JSON.
    """
    conn = get_conn()
    cur = conn.cursor(cursor_factory=extras.DictCursor)
    cur.execute(
        """
        SELECT
          s.stock_id,
          s.company_id,
          s.total_shares,
          s.outstanding_shares,
          s.status,
          s.issue_date,
          r.timestamp,
          r.current_price,
        FROM stocks s
        LEFT JOIN real_time_price r
          ON s.stock_id = r.stock_id
        ORDER BY s.stock_id, r.timestamp;
        """
    )
    rows = cur.fetchall()
    cur.close()
    conn.close()
    return jsonify([{
        'stock_id': row[0],
        'company_id': row[1],
        'total_shares': int(row[2]),
        'outstanding_shares': int(row[3]),
        'status': row[4],
        'issue_date': row[5].isoformat(),
        'timestamp': row[6].isoformat(),
        'current_price': float(row[7])
    } for row in rows])

@app.route('/orders/<int:order_id>/cancel', methods=['POST'])
def cancel_order(order_id):
    if not session.get('user_id'):
        return redirect(url_for('login'))

    conn = get_conn()
    cur = conn.cursor(cursor_factory=extras.DictCursor)
    # Kiểm tra quyền sở hữu: chỉ cho user hủy lệnh của chính họ
    cur.execute("""
        SELECT o.account_id
        FROM orders o
        JOIN accounts a ON o.account_id = a.account_id
        WHERE o.order_id = %s AND a.user_id = %s AND o.status <> 'Cancelled';
    """, (order_id, session['user_id']))
    row = cur.fetchone()
    if not row:
        flash('Không tìm thấy lệnh hợp lệ để hủy.', 'error')
    else:
        # Cập nhật trạng thái sang Cancelled -> trigger fn_refund_on_cancel sẽ chạy
        cur.execute(
            "UPDATE orders SET status = 'Cancelled' WHERE order_id = %s;",
            (order_id,)
        )
        conn.commit()
        flash(f'Lệnh #{order_id} đã được hủy.', 'success')

    cur.close()
    conn.close()
    return redirect(url_for('pending_orders'))
if __name__ == '__main__':
    # serve(app, host='127.0.0.1', port=5000)
    app.run(debug=True)