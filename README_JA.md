# PINANCE (UIT Pinance)

私の情報管理プロジェクトのデモWebアプリケーション。

## 目次

* [機能](#機能)
* [技術](#技術)
* [要件](#要件)
* [インストール](#インストール)
* [設定](#設定)
* [データベースセットアップ](#データベースセットアップ)
* [アプリケーションの実行](#アプリケーションの実行)
* [プロジェクト構造](#プロジェクト構造)
* [使用ガイド](#使用ガイド)
* [レポート](#レポート)
* [管理者アクセスガイド](#管理者アクセスガイド)

## 機能

* **ユーザー認証**: 登録、ログイン、ログアウト、プロフィール編集。
* **アカウント管理**: 複数のアカウントタイプの作成、入金・出金。
* **市場概要**: リアルタイムの価格・出来高データ、履歴チャート。
* **ウォッチリスト＆ポートフォリオ**: 株式の追跡、平均価格、数量、購入日の表示。
* **注文エントリ**: 指値注文、成行注文、トレイリングストップ、レバレッジオプション対応。
* **オーダーブック**: 上位の買い・売り注文を表示。
* **取引履歴**: 約定した取引の完全な記録。
* **待機注文**: 未約定注文の表示とキャンセル。
* **資産配分**: 時系列での現金・株式配分を示す円グラフと線グラフ。
* **カスタムレポート**: 株式取引、現在のポートフォリオ、キャッシュフロー、残高履歴のCSV/PDFレポート出力。
* **ヘルプセンター**: FAQ・使用ガイド。

## 技術

* **バックエンド**: Python, Flask
* **データベース**: PostgreSQL (`psycopg2`経由)
* **テンプレート**: Jinja2 (Flaskテンプレート)
* **フロントエンド**: HTML, CSS, JavaScript, Chart.js
* **データ分析**: pandas

## 要件

* Python 3.7以上
* PostgreSQL 12以上
* pipまたはPoetry

## インストール

1. **リポジトリのクローン**:

   ```bash
   git clone https://github.com/your-username/pinance.git
   cd pinance
   ```
2. **仮想環境の作成**:

   ```bash
   python3 -m venv venv
   source venv/bin/activate
   ```
3. **依存関係のインストール**:

   ```bash
   pip install -r requirements.txt
   ```

> **注意**: `requirements.txt`がない場合は、手動でインストールできます:
>
> ```bash
> pip install Flask psycopg2-binary pandas
> ```

## 設定

`.env.example`を`.env`にコピーして環境変数を設定してください:

```
SECRET_KEY=your_secret_key_here
DB_HOST=localhost
DB_PORT=5432
DB_NAME=pinance_db
DB_USER=username
DB_PASSWORD=password
```

または、`db.py`の`get_conn()`関数で直接設定することも可能です。

## データベースセットアップ

1. **データベースの作成**:

   ```sql
   CREATE DATABASE pinance_db;
   ```
2. **スキーマファイルの実行**:

   ```bash
   psql -U username -d pinance_db -f db/schema.sql
   ```
3. **（オプション）サンプルデータの読み込み**:

   ```bash
   psql -U username -d pinance_db -f db/sample_data.sql
   ```

> マイグレーションやシードファイル（例：`update 12-5 (loi nhuan).sql`）がある場合は、スキーマ適用後に実行してください。

## アプリケーションの実行

```bash
export FLASK_APP=main.py
export FLASK_ENV=development
flask run
```

アプリケーションはデフォルトで`http://127.0.0.1:5000/`で実行されます。

## プロジェクト構造

```
pinance/
├── app.py                 # メインFlaskアプリケーション
├── db.py                  # データベース接続ヘルパー
├── templates/             # Jinja2テンプレート
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
├── static/                # 静的リソース（CSS、JS、画像）
│   ├── css/style.css
│   └── js/script.js
├── requirements.txt       # Pythonライブラリ
└── README.md              # READMEファイル（このファイル）
```

## 使用ガイド

1. **ホームページ** (`/`): 公開株式の閲覧、登録・ログイン。
2. **ダッシュボード** (`/dashboard`): アカウント概要と取引メトリクスの表示。
3. **ウォッチリスト** (`/watchlist`): 追跡中の株式リストの表示。
4. **マーケット** (`/markets`): 最新の価格と出来高の表示。
5. **株式詳細** (`/stocks/<id>`): 価格チャート、オーダーブック、企業情報。
6. **注文** (`/stocks/<id>/order`): 新しい買い・売り注文の発注。
7. **待機注文** (`/pending_orders`): 未約定注文の管理。
8. **取引履歴** (`/transactions`): 約定した取引の確認。
9. **入金・出金** (`/deposit`, `/withdraw`): 現金残高の管理。
10. **資産配分** (`/asset_distribution`): ポートフォリオ配分チャートの表示。
11. **レポート** (`/reports`): カスタムレポートの作成・出力。
12. **ヘルプ** (`/help`): FAQと使用ガイド。

## レポート

* インターフェースから直接**CSV**または**PDF**レポートを出力。
* サポートされるレポートタイプ:

  * 日次株式取引
  * アカウント別現在のポートフォリオ
  * キャッシュフロー履歴（入出金）
  * 時系列残高履歴

## 管理者アクセスガイド
* ID 1001のアカウントで管理者ページにアクセスしてください。
* または、app/admin.pyの25行目を希望するIDに変更してください。
