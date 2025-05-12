import psycopg2
from config import Config


def get_conn():
    """
    Trả về kết nối psycopg2 sử dụng chuỗi kết nối SQLALCHEMY_DATABASE_URI từ Config.
    Config sẽ đọc DATABASE_URL (nếu có) hoặc ghép từ các biến DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASS.
    """
    # Sử dụng DSN từ Config
    return psycopg2.connect(Config.SQLALCHEMY_DATABASE_URI)