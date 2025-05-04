from flask import Flask, render_template, request, redirect, url_for, flash, session
import hashlib
import datetime
from db import get_conn
from psycopg2 import extras

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
               p.quantity, p.average_price, p.date
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
        # Cập nhật balance
        cur.execute(
            "UPDATE accounts SET balance = balance + %s WHERE account_id = %s;",
            (amount, account_id)
        )
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
            cur.execute(
                "UPDATE accounts SET balance = balance - %s WHERE account_id = %s;",
                (amount, account_id)
            )
            conn.commit()
            flash('Rút tiền thành công!', 'success')
        return redirect(url_for('withdraw'))
    cur.close()
    conn.close()
    return render_template('withdraw.html', accounts=accounts, user=user, user_email=user_email) 
# Đăng xuất
@app.route('/logout')
def logout():
    session.clear()
    flash('Bạn đã đăng xuất.', 'success')
    return redirect(url_for('login'))

if __name__ == '__main__':
    app.run(debug=True)