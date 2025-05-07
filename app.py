from flask import Flask, render_template, request, redirect, url_for, flash, session
import hashlib
import datetime
from db import get_conn
from psycopg2 import extras
import pandas as pd

app = Flask(__name__)
app.secret_key = 'your_secret_key'

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
    if not session.get('user_id'):
        flash('Vui lòng đăng nhập để xem Watchlist.', 'error')
        return redirect(url_for('login'))
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
        return redirect(url_for('dashboard'))

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
    # Lấy dữ liệu thị trường
    cur.execute(
        """
        SELECT s.stock_id, c.ticker_symbol, r.current_price, r.volume
        FROM stocks s
        JOIN real_time_price r ON s.stock_id = r.stock_id
        JOIN companies c ON s.company_id = c.company_id
        WHERE r.timestamp = (
            SELECT MAX(timestamp) FROM real_time_price WHERE stock_id = s.stock_id
        )
        """
    )
    market_data = cur.fetchall()
    cur.close()
    conn.close()
    return render_template('markets.html', user=user, user_email=user_email, market_data=market_data)

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
        "SELECT current_price, bid_price, ask_price, volume, timestamp"
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
    # Lấy giá mới nhất
    cur.execute(
        "SELECT current_price, bid_price, ask_price, volume, timestamp"
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
    # Lấy thông tin user cho dropdown
    cur.execute("SELECT first_name, last_name, email FROM users WHERE user_id=%s", (session['user_id'],))
    user = cur.fetchone()
    user_email = user['email']
    # Lấy danh sách tài khoản của user để chọn khi đặt lệnh
    cur.execute(
        "SELECT account_id, account_type, balance FROM accounts WHERE user_id = %s", (session['user_id'],)
    )
    accounts = cur.fetchall()
    # Lấy account_id đầu tiên để sử dụng
    account_id = accounts[0]['account_id'] if accounts else None
    # Lấy thông tin stock
    cur.execute(
        "SELECT s.stock_id, c.ticker_symbol, s.status FROM stocks s JOIN companies c ON s.company_id=c.company_id WHERE s.stock_id=%s",
        (stock_id,)
    )
    stock = cur.fetchone()
    if request.method == 'POST':
        price = float(request.form['price'])
        size = float(request.form['size'])
        order_type = request.form['order_type']
        leverage = int(request.form['leverage'])
        side = request.form['side']
        tp = request.form.get('take_profit') or None
        sl = request.form.get('stop_loss') or None
        # Insert order sử dụng account_id đúng
        cur.execute(
            "INSERT INTO orders (account_id, stock_id, order_type, quantity, price, status)"
            " VALUES (%s, %s, %s, %s, %s, 'Pending') RETURNING order_id;",
            (account_id, stock_id, side.upper(), size, price)
        )
        order_id = cur.fetchone()[0]
        conn.commit()
        flash(f'Order {order_id} placed successfully!', 'success')
        cur.close()
        conn.close()
        return redirect(url_for('order_entry', stock_id=stock_id))
    # GET: render order entry page
    cur.close()
    conn.close()
    return render_template('order_entry.html', user=user, user_email=user_email, stock=stock, accounts=accounts, latest=latest,
        series=series, company=company)


@app.route('/transactions')
def transactions():
    # Chuyển hướng nếu chưa login
    if not session.get('user_id'):
        return redirect(url_for('login'))

    conn = get_conn()
    cur = conn.cursor(cursor_factory=extras.DictCursor)

    # Truy vấn lịch sử giao dịch, join transactions → orders → stocks → companies
    cur.execute("""
        SELECT
          t.transaction_id,
          c.ticker_symbol,
          o.order_type,
          o.quantity,
          o.price,
          t.executed_at
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

    return render_template('transactions.html',user=user, user_email=user_email,  transactions=transactions)

# Orderss page
@app.route('/pending_orders')
def pending_orders():
    if not session.get('user_id'):
        return redirect(url_for('login'))
    conn = get_conn()
    cur = conn.cursor(cursor_factory=extras.DictCursor)
    # Lấy các lệnh có status Pending cho user
    cur.execute(
        """
        SELECT o.order_id, c.ticker_symbol, o.order_type, o.quantity, o.price, o.created_at, o.status
        FROM orders o
        JOIN stocks s ON o.stock_id = s.stock_id
        JOIN companies c ON s.company_id = c.company_id
        WHERE o.account_id IN (
            SELECT account_id FROM accounts WHERE user_id = %s
        )
        ORDER BY o.created_at DESC;
        """, (session['user_id'],)
    )
    orders = cur.fetchall()

    # Lấy thông tin user cho dropdown
    cur.execute("SELECT first_name, last_name, email FROM users WHERE user_id=%s", (session['user_id'],))
    user = cur.fetchone()
    user_email = user['email']

    cur.close()
    conn.close()
    return render_template('pending_orders.html', orders=orders, user=user, user_email=user_email)

@app.route('/help')
def help_page():
    if not session.get('user_id'):
        return redirect(url_for('login'))
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
if __name__ == '__main__':
    app.run(debug=True)