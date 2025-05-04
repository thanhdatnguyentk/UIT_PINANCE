from flask import Flask, render_template, request, redirect, url_for, flash, session
import hashlib
import datetime
from db import get_conn
from psycopg2 import extras

app = Flask(__name__)
app.secret_key = 'your_secret_key'

# Trang chủ: hiển thị chứng khoán
@app.route('/')
def index():
    conn = get_conn()
    cur = conn.cursor()
    cur.execute("SELECT * FROM stocks;")
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
                "INSERT INTO users (first_name, last_name, gender, birthday, email, phone, payment_method, password) "
                "VALUES (%s, %s, %s, %s, %s, %s, %s, %s);",
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
        cur.execute("SELECT user_id, first_name FROM users WHERE email = %s AND password = %s;", (email, hashed))
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

# Đăng xuất
@app.route('/logout')
def logout():
    session.clear()
    flash('Bạn đã đăng xuất.', 'success')
    return redirect(url_for('login'))

if __name__ == '__main__':
    app.run(debug=True)