from flask import Blueprint, render_template, request, redirect, url_for, flash, session
from psycopg2.extras import RealDictCursor
from db import get_conn
from flask import jsonify
from psycopg2 import extras

admin_bp = Blueprint('admin', __name__, url_prefix='/admin')
@admin_bp.route('/admin')
def admin_dashboard():
    conn = get_conn()
    cur = conn.cursor(cursor_factory=RealDictCursor)
    cur.execute("SELECT * FROM admin_function_list_users()")
    users = cur.fetchall()
    return render_template('admin/dashboard.html', users=users)

@admin_bp.before_request
def require_admin():
    # if session.get('role') != 'admin':
    #     flash('Bạn không có quyền truy cập trang này', 'error')
    #     return redirect(url_for('dashboard'))
    
    if 'user_id' not in session:
        flash('Bạn cần đăng nhập để truy cập trang này', 'error')
        return redirect(url_for('auth.login'))
    if session['user_id'] != 1001:
        print('user_id', session['user_id'])
        flash('Bạn không có quyền truy cập trang này', 'error')
        return redirect(url_for('dashboard'))
    # return render_template('admin/dashboard.html')


@admin_bp.route('/users', methods=['GET', 'POST'])
def manage_users():
    conn = get_conn()
    cur = conn.cursor(cursor_factory=RealDictCursor)
    
    email = request.form.get('email') if request.method == 'POST' else None
    name = request.form.get('name') if request.method == 'POST' else None
    if email:
        cur.execute("SELECT * FROM admin_function_search_users_by_email(%s)", (email,))
    elif name:
        cur.execute("SELECT * FROM admin_function_search_users_by_name(%s)", (name,))
    else:
        cur.execute("SELECT * FROM admin_function_list_users()")
    users = cur.fetchall()
    return render_template('admin/users.html', users=users)

@admin_bp.route('/users/reset_password/<int:user_id>', methods=['POST'])
def reset_password(user_id):
    new_password = request.form.get('new_password')
    conn = get_conn()
    cur = conn.cursor()

    cur.execute("CALL admin_procedure_reset_password(%s, %s, %s)", (session['user_id'], user_id, new_password))
    conn.commit()
    flash(f'Đã reset mật khẩu cho user {user_id}', 'success')
    return redirect(url_for('admin.manage_users'))

@admin_bp.route('/users/disable/<int:user_id>')
def disable_user(user_id):
    conn = get_conn()
    cur = conn.cursor()

    cur.execute("CALL admin_procedure_disable_user(%s, %s)", (session['user_id'], user_id))
    conn.commit()
    flash(f'User {user_id} đã bị disable', 'success')
    return redirect(url_for('admin.manage_users'))

@admin_bp.route('/users/enable/<int:user_id>')
def enable_user(user_id):
    conn = get_conn()
    cur = conn.cursor()

    cur.execute("CALL admin_procedure_enable_user(%s, %s)", (session['user_id'], user_id))
    conn.commit()
    flash(f'User {user_id} đã được enable', 'success')
    return redirect(url_for('admin.manage_users'))

@admin_bp.route('/users/edit/<int:user_id>', methods=['GET', 'POST'])
def edit_user(user_id):
    conn = get_conn()
    cur = conn.cursor(cursor_factory=RealDictCursor)
    if request.method == 'POST':
        cur.execute(
            "CALL admin_procedure_update_user_info(%s, %s, %s, %s, %s, %s)",
            (session['user_id'], user_id,
             request.form['first_name'], request.form['last_name'],
             request.form['email'], request.form['phone'])
        )
        conn.commit()
        flash(f'User {user_id} đã được cập nhật', 'success')
        return redirect(url_for('admin.manage_users'))
    else:
        cur.execute("SELECT * FROM users WHERE user_id = %s", (user_id,))
        user = cur.fetchone()
        return render_template('admin/edit_user.html', user=user)

# Add to python/app/admin.py (within the existing Blueprint `admin_bp`)

@admin_bp.route('/companies', methods=['GET', 'POST'])
def manage_companies():
    """
    List all companies or search by name.
    """
    conn = get_conn()
    cur = conn.cursor(cursor_factory=RealDictCursor)
    name = request.form.get('company_name') if request.method == 'POST' else None
    if name:
        cur.execute(
            "SELECT * FROM admin_function_search_companies_by_name(%s)",
            (name,)
        )
    else:   
        cur.execute(
            "SELECT * FROM admin_function_list_companies()"
        )
    companies = cur.fetchall()
    return render_template('admin/companies.html', companies=companies)

@admin_bp.route('/companies/create', methods=['GET', 'POST'])
def create_company():
    """
    Create a new company with full details.
    """
    if request.method == 'POST':
        company_name  = request.form['company_name']
        ticker_symbol = request.form['ticker_symbol']
        description   = request.form.get('description')
        industry      = request.form['industry']
        listed_date   = request.form['listed_date']
        head_quarters = request.form.get('head_quarters')
        website       = request.form.get('website')

        conn = get_conn()
        cur = conn.cursor()
        cur.execute(
            "INSERT INTO companies(company_name, ticker_symbol, description, industry, listed_date, head_quarters, website)"
            " VALUES (%s,%s,%s,%s,%s,%s,%s)",
            (company_name, ticker_symbol, description, industry, listed_date, head_quarters, website)
        )
        new_id = cur.fetchone()[0]  # Assuming the first column is the new company ID
        conn.commit()
        flash(f'Đã tạo công ty mới (ID: {new_id})', 'success')
        return redirect(url_for('admin.manage_companies'))
    return render_template('admin/create_company.html')

@admin_bp.route('/companies/edit/<int:company_id>', methods=['GET', 'POST'])
def edit_company(company_id):
    """
    Edit existing company information.
    """
    conn = get_conn()
    cur = conn.cursor(cursor_factory=RealDictCursor)
    if request.method == 'POST':
        company_name  = request.form['company_name']
        ticker_symbol = request.form['ticker_symbol']
        description   = request.form.get('description')
        industry      = request.form['industry']
        listed_date   = request.form['listed_date']
        head_quarters = request.form.get('head_quarters')
        website       = request.form.get('website')

        cur.execute(
            "UPDATE companies SET company_name=%s, ticker_symbol=%s, description=%s, industry=%s, listed_date=%s, head_quarters=%s, website=%s"
            " WHERE company_id=%s",
            (company_name, ticker_symbol, description, industry, listed_date, head_quarters, website, company_id)
        )
        conn.commit()
        flash(f'Đã cập nhật công ty {company_id}', 'success')
        return redirect(url_for('admin.manage_companies'))
    else:
        cur.execute(
            "SELECT * FROM companies WHERE company_id = %s",
            (company_id,)
        )
        company = cur.fetchone()
        return render_template('admin/edit_company.html', company=company)

@admin_bp.route('/companies/delete/<int:company_id>')
def delete_company(company_id):
    conn = get_conn()
    cur = conn.cursor()
    cur.execute("DELETE FROM companies WHERE company_id = %s", (company_id,))
    conn.commit()
    cur.close()
    conn.close()
    flash(f'Đã xóa công ty ID {company_id}', 'success')
    return redirect(url_for('admin.manage_companies'))

@admin_bp.route('/dashboard')
def dashboard():
    """
    Render admin dashboard page.
    """
    return render_template('admin/dashboard.html')

@admin_bp.route('/api/dashboard-data')
def dashboard_data():
    conn = get_conn()
    cur = conn.cursor()
    # Basic metrics
    cur.execute("SELECT COUNT(*) FROM transactions WHERE DATE(executed_at)=CURRENT_DATE")
    today_sales = cur.fetchone()[0] or 0
    cur.execute("SELECT COUNT(*) FROM transactions")
    total_sales = cur.fetchone()[0] or 0
    cur.execute("SELECT COALESCE(SUM(quantity*matched_price),0) FROM transactions WHERE DATE(executed_at)=CURRENT_DATE")
    today_revenue = cur.fetchone()[0]
    cur.execute("SELECT COALESCE(SUM(quantity*matched_price),0) FROM transactions")
    total_revenue = cur.fetchone()[0]
    # Summary
    cur.execute("SELECT total_value, total_volume FROM admin_function_report_transaction_summary()")
    summary = cur.fetchone() or (0,0)
    # Recent new users
    cur.execute("SELECT period_start, new_users FROM admin_function_report_new_users_by_period(CURRENT_DATE-6, CURRENT_DATE)")
    new_users = [{'date': r[0].strftime('%Y-%m-%d'), 'count': r[1]} for r in cur.fetchall()]
    # Monitoring series: deposits, withdrawals, orders, transactions last 7 days
    def fetch_series(table):
        cur.execute(
            f"SELECT created_at::date AS day, COUNT(*) FROM {table} "
            "WHERE created_at::date >= CURRENT_DATE-6 "
            "GROUP BY day ORDER BY day"
        )
        return [{'date': r[0].strftime('%Y-%m-%d'), 'count': r[1]} for r in cur.fetchall()]
    deposits = fetch_series('deposits')
    withdrawals = fetch_series('withdrawals')
    orders = fetch_series('orders')
    transactions = fetch_series('transactions')
    conn.close()
    return jsonify({
        'today_sales': today_sales,
        'total_sales': total_sales,
        'today_revenue': float(today_revenue),
        'total_revenue': float(total_revenue),
        'summary': {'total_value': float(summary[0] or 0), 'total_volume': float(summary[1] or 0)},
        'new_users': new_users,
        'deposits': deposits,
        'withdrawals': withdrawals,
        'orders': orders,
        'transactions': transactions
    })

@admin_bp.route('/user-profits')
def user_profits():
    """
    Hiển thị bảng lãi/lỗ và tài sản của người dùng.
    Cho phép lọc theo email/đổi tên và sắp xếp theo các cột.
    """
    # Lấy params từ query string
    sort_by = request.args.get('sort_by', 'total_pnl')  # realized_pnl, unrealized_pnl, total_pnl, total_assets
    order   = request.args.get('order', 'desc').upper()  # ASC or DESC
    search  = request.args.get('search', '')

    # Xác thực sort_by và order để tránh SQL injection
    valid_sort_columns = ['realized_pnl', 'total_assets', 'user_id', 'full_name']
    if sort_by not in valid_sort_columns:
        sort_by = 'realized_pnl'
    if order not in ['ASC', 'DESC']:
        order = 'DESC'

    conn = get_conn()
    cur  = conn.cursor(cursor_factory=RealDictCursor)

    # Build query: tổng hợp lãi/lỗ và tài sản theo user
    query = f"""
     SELECT
      u.user_id,
      u.first_name || ' ' || u.last_name AS full_name,
      v.loi_nhuan AS realized_pnl,
      t.tai_san AS total_assets
    FROM v_total_pnl_summary v
    JOIN accounts a ON v.account_id = a.account_id
    JOIN users u    ON a.user_id      = u.user_id
    JOIN v_tai_san_tong_hop t ON a.account_id = t.account_id
    WHERE (u.email ILIKE %s OR u.first_name ILIKE %s OR u.last_name ILIKE %s)
    ORDER BY {sort_by} {order}
    """
    ilike_pattern = f"%{search}%"
    cur.execute(query, (ilike_pattern, ilike_pattern, ilike_pattern))
    users = cur.fetchall()
    cur.close()
    conn.close()

    return render_template('admin/admin_user_profits.html', users=users,
                           sort_by=sort_by, order=order, search=search)

@admin_bp.route('/user-transactions/<int:user_id>')
def user_transactions(user_id):
    """
    Hiển thị chi tiết các giao dịch của một user: deposits, withdrawals, orders và transactions.
    """
    conn = get_conn()
    cur = conn.cursor(cursor_factory=RealDictCursor)
    # Lấy tất cả accounts của user
    cur.execute(
        "SELECT account_id FROM accounts WHERE user_id = %s",
        (user_id,)
    )
    accounts = [r['account_id'] for r in cur.fetchall()]
    if not accounts:
        flash('User không có tài khoản nào', 'info')
        return redirect(url_for('admin.manage_users'))

    # Lấy deposits
    cur.execute(
        "SELECT * FROM deposits WHERE account_id = ANY(%s) ORDER BY created_at DESC",
        (accounts,)
    )
    deposits = cur.fetchall()
    # Lấy withdrawals
    cur.execute(
        "SELECT * FROM withdrawals WHERE account_id = ANY(%s) ORDER BY created_at DESC",
        (accounts,)
    )
    withdrawals = cur.fetchall()
    # Lấy orders
    cur.execute(
        "SELECT o.*, c.ticker_symbol FROM orders o "
        "JOIN stocks s ON o.stock_id = s.stock_id "
        "JOIN companies c ON s.company_id = c.company_id "
        "WHERE o.account_id = ANY(%s) ORDER BY o.created_at DESC",
        (accounts,)
    )
    orders = cur.fetchall()
    # Lấy transactions
    cur.execute(
        "SELECT t.*, c.ticker_symbol FROM transactions t "
        "JOIN orders o ON t.order_id = o.order_id "
        "JOIN stocks s ON o.stock_id = s.stock_id "
        "JOIN companies c ON s.company_id = c.company_id "
        "WHERE o.account_id = ANY(%s) ORDER BY t.executed_at DESC",
        (accounts,)
    )
    transactions = cur.fetchall()

    cur.close()
    conn.close()
    return render_template(
        'admin/user_transactions.html',
        user_id=user_id,
        deposits=deposits,
        withdrawals=withdrawals,
        orders=orders,
        transactions=transactions
    )