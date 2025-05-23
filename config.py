import os
from dotenv import load_dotenv

# Tải biến môi trường từ file .env
load_dotenv()
class Config:
    # Secret key cho Flask (đổi thành chuỗi đủ mạnh trên production)
    SECRET_KEY = os.getenv('SECRET_KEY', 'fallback_secret_key')

    # Nếu có biến DATABASE_URL thì dùng luôn, ngược lại ghép từ các biến con
    DATABASE_URL = os.getenv('DATABASE_URL')
    if DATABASE_URL:
        SQLALCHEMY_DATABASE_URI = DATABASE_URL
    else:
        DB_HOST = os.getenv('DB_HOST', 'localhost')
        DB_PORT = os.getenv('DB_PORT', '5432')
        DB_NAME = os.getenv('DB_NAME', 'PINANCE_new')
        DB_USER = os.getenv('DB_USER', 'postgres')
        DB_PASS = os.getenv('DB_PASS', '13031977')
        SQLALCHEMY_DATABASE_URI = (
            f"postgresql://{DB_USER}:{DB_PASS}@{DB_HOST}:{DB_PORT}/{DB_NAME}"
        )

    SQLALCHEMY_TRACK_MODIFICATIONS = False
