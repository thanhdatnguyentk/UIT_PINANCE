# PINANCE (UIT Pinance)

Demo web cho đồ án Quản lý thông tin của tôi.

## Mục lục

* [Tính năng](#tính-năng)
* [Công nghệ](#công-nghệ)
* [Yêu cầu](#yêu-cầu)
* [Cài đặt](#cài-đặt)
* [Cấu hình](#cấu-hình)
* [Thiết lập cơ sở dữ liệu](#thiết-lập-cơ-sở-dữ-liệu)
* [Chạy ứng dụng](#chạy-ứng-dụng)
* [Cấu trúc dự án](#cấu-trúc-dự-án)
* [Hướng dẫn sử dụng](#hướng-dẫn-sử-dụng)
* [Báo cáo](#báo-cáo)

## Tính năng

* **Xác thực người dùng**: Đăng ký, đăng nhập, đăng xuất và chỉnh sửa hồ sơ.
* **Quản lý tài khoản**: Tạo nhiều loại tài khoản, nạp và rút tiền.
* **Tổng quan thị trường**: Dữ liệu giá và khối lượng theo thời gian thực, biểu đồ lịch sử.
* **Danh sách theo dõi & Danh mục đầu tư**: Theo dõi cổ phiếu, xem giá trung bình, số lượng và ngày mua.
* **Đặt lệnh**: Hỗ trợ lệnh giới hạn, lệnh thị trường và trailing stop với tùy chọn đòn bẩy.
* **Sổ lệnh**: Hiển thị các lệnh mua/bán hàng đầu.
* **Lịch sử giao dịch**: Ghi nhận đầy đủ các giao dịch đã khớp.
* **Lệnh chờ**: Xem và hủy các lệnh chưa khớp.
* **Phân bổ tài sản**: Biểu đồ hình tròn và đường thể hiện phân bổ tiền mặt và cổ phiếu theo thời gian.
* **Báo cáo tùy chỉnh**: Xuất báo cáo CSV/PDF về giao dịch cổ phiếu, danh mục hiện tại, luồng tiền và lịch sử số dư.
* **Trung tâm trợ giúp**: Mục hỏi đáp và hướng dẫn sử dụng.

## Công nghệ

* **Backend**: Python, Flask
* **Cơ sở dữ liệu**: PostgreSQL (thông qua `psycopg2`)
* **Templating**: Jinja2 (Flask templates)
* **Frontend**: HTML, CSS, JavaScript, Chart.js
* **Phân tích dữ liệu**: pandas

## Yêu cầu

* Python 3.7 trở lên
* PostgreSQL 12 trở lên
* pip hoặc Poetry

## Cài đặt

1. **Clone repo**:

   ```bash
   git clone https://github.com/your-username/pinance.git
   cd pinance
   ```
2. **Tạo môi trường ảo**:

   ```bash
   python3 -m venv venv
   source venv/bin/activate
   ```
3. **Cài đặt phụ thuộc**:

   ```bash
   pip install -r requirements.txt
   ```

> **Lưu ý**: Nếu không có `requirements.txt`, bạn có thể cài thủ công:
>
> ```bash
> pip install Flask psycopg2-binary pandas
> ```

## Cấu hình

Sao chép file `.env.example` thành `.env` và điền thông tin biến môi trường:

```
SECRET_KEY=your_secret_key_here
DB_HOST=localhost
DB_PORT=5432
DB_NAME=pinance_db
DB_USER=username
DB_PASSWORD=password
```

Hoặc bạn có thể cấu hình trực tiếp trong hàm `get_conn()` của `db.py`.

## Thiết lập cơ sở dữ liệu

1. **Tạo database**:

   ```sql
   CREATE DATABASE pinance_db;
   ```
2. **Chạy file schema**:

   ```bash
   psql -U username -d pinance_db -f db/schema.sql
   ```
3. **(Tùy chọn) Nạp dữ liệu mẫu**:

   ```bash
   psql -U username -d pinance_db -f db/sample_data.sql
   ```

> Nếu bạn có file migration hoặc seed (ví dụ `update 12-5 (loi nhuan).sql`), hãy chạy sau khi áp schema.

## Chạy ứng dụng

```bash
export FLASK_APP=app.py
export FLASK_ENV=development
flask run
```

Ứng dụng mặc định chạy tại `http://127.0.0.1:5000/`.

## Cấu trúc dự án

```
pinance/
├── app.py                 # Ứng dụng Flask chính
├── db.py                  # Trợ giúp kết nối cơ sở dữ liệu
├── templates/             # Các template Jinja2
│   ├── index.html
│   ├── login.html
│   ├── register.html
│   ├── dashboard.html
│   ├── watchlist.html
│   ├── markets.html
│   ├── stock_detail.html
│   ├── order_entry.html
│   ├── pending_orders.html
│   ├── transactions.html
│   ├── deposit.html
│   ├── withdraw.html
│   ├── edit_profile.html
│   ├── asset_distribution.html
│   ├── reports.html
│   └── help.html
├── static/                # Tài nguyên tĩnh (CSS, JS, hình ảnh)
│   ├── css/style.css
│   └── js/script.js
├── requirements.txt       # Thư viện Python
└── README.md              # Tệp README (bản này)
```

## Hướng dẫn sử dụng

1. **Trang chủ** (`/`): Duyệt cổ phiếu công khai, đăng ký hoặc đăng nhập.
2. **Dashboard** (`/dashboard`): Xem tóm tắt tài khoản và số liệu giao dịch.
3. **Watchlist** (`/watchlist`): Xem danh sách cổ phiếu đang theo dõi.
4. **Markets** (`/markets`): Xem giá và khối lượng mới nhất.
5. **Chi tiết cổ phiếu** (`/stocks/<id>`): Biểu đồ giá, sổ lệnh, thông tin công ty.
6. **Đặt lệnh** (`/stocks/<id>/order`): Đặt lệnh mua/bán mới.
7. **Lệnh chờ** (`/pending_orders`): Quản lý các lệnh chưa khớp.
8. **Lịch sử giao dịch** (`/transactions`): Xem lại các giao dịch đã thực hiện.
9. **Nạp/Rút tiền** (`/deposit`, `/withdraw`): Quản lý số dư tiền mặt.
10. **Phân bổ tài sản** (`/asset_distribution`): Xem biểu đồ phân bổ danh mục.
11. **Báo cáo** (`/reports`): Tạo và xuất báo cáo tùy chỉnh.
12. **Trợ giúp** (`/help`): Hỏi đáp và hướng dẫn sử dụng.

## Báo cáo

* Xuất báo cáo **CSV** hoặc **PDF** trực tiếp từ giao diện.
* Các loại báo cáo hỗ trợ:

  * Giao dịch cổ phiếu theo ngày
  * Danh mục hiện tại theo tài khoản
  * Lịch sử dòng tiền vào/ra
  * Lịch sử số dư theo thời gian
