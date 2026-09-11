import os
from flask import Flask, jsonify
import psycopg2

app = Flask(__name__)

DB_HOST = os.environ.get("DB_HOST", "db")
DB_NAME = os.environ.get("DB_NAME", "appdb")
DB_USER = os.environ.get("DB_USER", "appuser")
DB_PASSWORD = os.environ.get("DB_PASSWORD", "")


@app.route("/")
def index():
    return jsonify({
        "status": "ok",
        "message": "Hello from the containerized Flask backend, routed through Nginx!"
    })


@app.route("/health")
def health():
    return jsonify({"status": "healthy"}), 200


@app.route("/db-check")
def db_check():
    try:
        conn = psycopg2.connect(
            host=DB_HOST, dbname=DB_NAME, user=DB_USER,
            password=DB_PASSWORD, connect_timeout=3
        )
        conn.close()
        return jsonify({"database": "connected"}), 200
    except Exception as e:
        return jsonify({"database": "error", "detail": str(e)}), 500


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
