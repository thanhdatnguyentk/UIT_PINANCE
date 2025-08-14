# PINANCE (UIT Pinance)

Demo web application for my Information Management project.

## Table of Contents

* [Features](#features)
* [Technologies](#technologies)
* [Requirements](#requirements)
* [Installation](#installation)
* [Configuration](#configuration)
* [Database Setup](#database-setup)
* [Running the Application](#running-the-application)
* [Project Structure](#project-structure)
* [User Guide](#user-guide)
* [Reports](#reports)
* [Admin Access Guide](#admin-access-guide)

## Features

* **User Authentication**: Register, login, logout, and profile editing.
* **Account Management**: Create multiple account types, deposit and withdraw funds.
* **Market Overview**: Real-time price and volume data, historical charts.
* **Watchlist & Portfolio**: Track stocks, view average price, quantity, and purchase date.
* **Order Entry**: Support for limit orders, market orders, and trailing stops with leverage options.
* **Order Book**: Display top buy/sell orders.
* **Transaction History**: Complete record of executed trades.
* **Pending Orders**: View and cancel unmatched orders.
* **Asset Allocation**: Pie charts and line graphs showing cash and stock allocation over time.
* **Custom Reports**: Export CSV/PDF reports on stock transactions, current portfolio, cash flow, and balance history.
* **Help Center**: FAQ and user guides.

## Technologies

* **Backend**: Python, Flask
* **Database**: PostgreSQL (via `psycopg2`)
* **Templating**: Jinja2 (Flask templates)
* **Frontend**: HTML, CSS, JavaScript, Chart.js
* **Data Analysis**: pandas

## Requirements

* Python 3.7 or higher
* PostgreSQL 12 or higher
* pip or Poetry

## Installation

1. **Clone the repository**:

   ```bash
   git clone https://github.com/your-username/pinance.git
   cd pinance
   ```
2. **Create virtual environment**:

   ```bash
   python3 -m venv venv
   source venv/bin/activate
   ```
3. **Install dependencies**:

   ```bash
   pip install -r requirements.txt
   ```

> **Note**: If `requirements.txt` is not available, you can install manually:
>
> ```bash
> pip install Flask psycopg2-binary pandas
> ```

## Configuration

Copy `.env.example` to `.env` and fill in the environment variables:

```
SECRET_KEY=your_secret_key_here
DB_HOST=localhost
DB_PORT=5432
DB_NAME=pinance_db
DB_USER=username
DB_PASSWORD=password
```

Alternatively, you can configure directly in the `get_conn()` function of `db.py`.

## Database Setup

1. **Create database**:

   ```sql
   CREATE DATABASE pinance_db;
   ```
2. **Run schema file**:

   ```bash
   psql -U username -d pinance_db -f db/schema.sql
   ```
3. **(Optional) Load sample data**:

   ```bash
   psql -U username -d pinance_db -f db/sample_data.sql
   ```

> If you have migration or seed files (e.g., `update 12-5 (loi nhuan).sql`), run them after applying the schema.

## Running the Application

```bash
export FLASK_APP=main.py
export FLASK_ENV=development
flask run
```

The application runs by default at `http://127.0.0.1:5000/`.

## Project Structure

```
pinance/
├── app.py                 # Main Flask application
├── db.py                  # Database connection helper
├── templates/             # Jinja2 templates
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
├── static/                # Static resources (CSS, JS, images)
│   ├── css/style.css
│   └── js/script.js
├── requirements.txt       # Python libraries
└── README.md              # README file (this one)
```

## User Guide

1. **Homepage** (`/`): Browse public stocks, register or login.
2. **Dashboard** (`/dashboard`): View account summary and trading metrics.
3. **Watchlist** (`/watchlist`): View list of tracked stocks.
4. **Markets** (`/markets`): View latest prices and volumes.
5. **Stock Details** (`/stocks/<id>`): Price charts, order book, company information.
6. **Place Order** (`/stocks/<id>/order`): Place new buy/sell orders.
7. **Pending Orders** (`/pending_orders`): Manage unmatched orders.
8. **Transaction History** (`/transactions`): Review executed trades.
9. **Deposit/Withdraw** (`/deposit`, `/withdraw`): Manage cash balance.
10. **Asset Allocation** (`/asset_distribution`): View portfolio allocation charts.
11. **Reports** (`/reports`): Generate and export custom reports.
12. **Help** (`/help`): FAQ and user guides.

## Reports

* Export **CSV** or **PDF** reports directly from the interface.
* Supported report types:

  * Daily stock transactions
  * Current portfolio by account
  * Cash flow history (in/out)
  * Balance history over time

## Admin Access Guide
* Access the admin page using an account with ID 1001.
* Or modify line 25 in app/admin.py to use your desired ID.
