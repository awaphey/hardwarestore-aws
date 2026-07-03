"""
Hardware Store Operations - AWS Edition
========================================
Flask application adapted for secure AWS deployment.

Changes from Assignment 1 (local MSSQL) → Assignment 2 (AWS PostgreSQL):
  - Database: pyodbc/MSSQL → psycopg2/PostgreSQL (RDS)
  - Credentials: hardcoded connection string → AWS Secrets Manager
  - Logging: local log files → Amazon CloudWatch Logs (via watchtower)
  - Auth: Windows Trusted Connection → username/password (RDS requirement)

Security controls demonstrated (Part D requirement):
  - Credentials never hardcoded; fetched at runtime from Secrets Manager
  - CloudWatch logging for audit trail (maps to Risk 6 from Part A)
  - Parameterised queries throughout (SQL injection prevention)
  - Flask SECRET_KEY pulled from Secrets Manager (not env var default)
"""

import json
import logging
import os
from decimal import Decimal, InvalidOperation

import boto3
import psycopg2
import psycopg2.extras
import watchtower
from botocore.exceptions import ClientError
from flask import Flask, flash, redirect, render_template, request, url_for

# ---------------------------------------------------------------------------
# Logging setup — sends logs to Amazon CloudWatch Logs
# ---------------------------------------------------------------------------
LOG_GROUP = os.environ.get("CW_LOG_GROUP", "hardwarestore-app")
LOG_STREAM = os.environ.get("CW_LOG_STREAM", "app")
AWS_REGION = os.environ.get("AWS_DEFAULT_REGION", "us-east-1")

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

# Console handler (for local development / systemd journal)
_console_handler = logging.StreamHandler()
_console_handler.setFormatter(
    logging.Formatter("%(asctime)s [%(levelname)s] %(name)s: %(message)s")
)
logger.addHandler(_console_handler)

# CloudWatch handler (for production on EC2)
try:
    _cw_handler = watchtower.CloudWatchLogHandler(
        log_group_name=LOG_GROUP,
        log_stream_name=LOG_STREAM,
        boto3_client=boto3.client("logs", region_name=AWS_REGION),
    )
    logger.addHandler(_cw_handler)
    logger.info("CloudWatch logging handler attached — log group: %s", LOG_GROUP)
except Exception as _cw_err:  # noqa: BLE001
    # If running locally without AWS credentials, fall back to console only
    logger.warning("CloudWatch handler unavailable (%s); using console only.", _cw_err)


# ---------------------------------------------------------------------------
# AWS Secrets Manager — fetch DB credentials + Flask secret at startup
# ---------------------------------------------------------------------------
_cached_secret = None  # type: dict


def _get_secret() -> dict:
    """
    Fetch and cache the application secret from AWS Secrets Manager.

    The secret JSON is expected to contain:
        host, port, dbname, username, password, flask_secret

    Falls back to individual environment variables when running locally
    (SECRET_NAME not set), so the app can still be tested without AWS.
    """
    global _cached_secret  # noqa: PLW0603
    if _cached_secret is not None:
        return _cached_secret

    secret_name = os.environ.get("SECRET_NAME")

    if secret_name:
        # --- AWS path: fetch from Secrets Manager ---
        client = boto3.client("secretsmanager", region_name=AWS_REGION)
        try:
            response = client.get_secret_value(SecretId=secret_name)
            _cached_secret = json.loads(response["SecretString"])
            logger.info("Credentials loaded from Secrets Manager: %s", secret_name)
        except ClientError as exc:
            logger.error("Failed to retrieve secret '%s': %s", secret_name, exc)
            raise
    else:
        # --- Local fallback: individual environment variables ---
        logger.warning(
            "SECRET_NAME not set — falling back to environment variables for DB credentials."
        )
        _cached_secret = {
            "host": os.environ.get("DB_HOST", "localhost"),
            "port": int(os.environ.get("DB_PORT", "5432")),
            "dbname": os.environ.get("DB_NAME", "hardwarestore"),
            "username": os.environ.get("DB_USER", "appuser"),
            "password": os.environ.get("DB_PASSWORD", ""),
            "flask_secret": os.environ.get("FLASK_SECRET_KEY", "dev-only-secret"),
        }

    return _cached_secret


# ---------------------------------------------------------------------------
# Flask application factory
# ---------------------------------------------------------------------------
app = Flask(__name__)

# Fetch Flask secret from Secrets Manager (never a hardcoded default in prod)
_secret = _get_secret()
app.config["SECRET_KEY"] = _secret.get(
    "flask_secret", os.environ.get("FLASK_SECRET_KEY", "dev-only-secret")
)


# ---------------------------------------------------------------------------
# Request/response logging hooks (CloudWatch audit trail — Part D requirement)
# ---------------------------------------------------------------------------
@app.before_request
def _log_request() -> None:
    logger.info("→ %s %s (from %s)", request.method, request.path, request.remote_addr)


@app.after_request
def _log_response(response):
    logger.info(
        "← %s %s → HTTP %s", request.method, request.path, response.status_code
    )
    return response


# ---------------------------------------------------------------------------
# Database connection
# ---------------------------------------------------------------------------
def get_connection():
    """
    Open a new PostgreSQL connection using credentials from Secrets Manager.
    Uses NamedTupleCursor so rows support attribute-style access (row.ProductID),
    keeping templates identical to the original MSSQL version.
    """
    secret = _get_secret()
    conn = psycopg2.connect(
        host=secret["host"],
        port=int(secret["port"]),
        dbname=secret["dbname"],
        user=secret["username"],
        password=secret["password"],
        # Enforce TLS — RDS requires ssl, ALB handles the public TLS termination
        sslmode="require",
        cursor_factory=psycopg2.extras.NamedTupleCursor,
    )
    return conn


# ---------------------------------------------------------------------------
# Helper queries
# ---------------------------------------------------------------------------
def fetch_products():
    """Return all products ordered newest-first."""
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT
                    product_id   AS "ProductID",
                    product_name AS "ProductName",
                    category     AS "Category",
                    price        AS "Price",
                    stock_quantity AS "StockQuantity"
                FROM products
                ORDER BY product_id DESC
                """
            )
            return cur.fetchall()


def fetch_customers():
    """Return all customer-role users for the order form."""
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT
                    user_id  AS "UserID",
                    username AS "Username",
                    email    AS "Email"
                FROM users
                WHERE role = %s
                ORDER BY username
                """,
                ("Customer",),
            )
            return cur.fetchall()


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------
@app.route("/")
def index():
    return render_template("products.html", products=fetch_products())


@app.post("/products")
def add_product():
    name = request.form.get("product_name", "").strip()
    category = request.form.get("category", "").strip()
    price_raw = request.form.get("price", "").strip()
    stock_raw = request.form.get("stock_quantity", "").strip()

    if not name or not category:
        flash("Product name and category are required.", "error")
        return redirect(url_for("index"))

    try:
        price = Decimal(price_raw)
        stock_quantity = int(stock_raw)
    except (InvalidOperation, ValueError):
        flash("Price and stock quantity must be valid numbers.", "error")
        return redirect(url_for("index"))

    if price < 0 or stock_quantity < 0:
        flash("Price and stock quantity cannot be negative.", "error")
        return redirect(url_for("index"))

    with get_connection() as conn:
        with conn.cursor() as cur:
            # Parameterised INSERT — prevents SQL injection (Part A Risk 3 mitigation)
            cur.execute(
                """
                INSERT INTO products (product_name, category, price, stock_quantity)
                VALUES (%s, %s, %s, %s)
                """,
                (name, category, price, stock_quantity),
            )
        conn.commit()

    logger.info("Product added: '%s' (category: %s)", name, category)
    flash("Product added to inventory.", "success")
    return redirect(url_for("index"))


@app.post("/products/<int:product_id>/delete")
def delete_product(product_id: int):
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT COUNT(*) FROM order_details WHERE product_id = %s",
                (product_id,),
            )
            linked_order_count = cur.fetchone()[0]

            if linked_order_count:
                flash("This product is linked to existing orders and cannot be removed.", "error")
                return redirect(url_for("index"))

            cur.execute("DELETE FROM products WHERE product_id = %s", (product_id,))
        conn.commit()

    logger.info("Product deleted: product_id=%d", product_id)
    flash("Product removed from inventory.", "success")
    return redirect(url_for("index"))


@app.route("/orders")
def orders():
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT
                    o.order_id        AS "OrderID",
                    u.username        AS "Username",
                    u.email           AS "Email",
                    o.order_date      AS "OrderDate",
                    o.total_amount    AS "TotalAmount",
                    p.product_name    AS "ProductName",
                    od.quantity       AS "Quantity",
                    od.subtotal_price AS "SubtotalPrice"
                FROM orders o
                INNER JOIN users u         ON o.user_id   = u.user_id
                INNER JOIN order_details od ON o.order_id  = od.order_id
                INNER JOIN products p      ON od.product_id = p.product_id
                ORDER BY o.order_id DESC
                """
            )
            order_rows = cur.fetchall()

    return render_template(
        "orders.html",
        orders=order_rows,
        products=fetch_products(),
        customers=fetch_customers(),
    )


@app.post("/orders")
def create_order():
    try:
        user_id = int(request.form.get("user_id", ""))
        product_id = int(request.form.get("product_id", ""))
        quantity = int(request.form.get("quantity", ""))
    except ValueError:
        flash("Customer, product, and quantity are required.", "error")
        return redirect(url_for("orders"))

    if quantity <= 0:
        flash("Quantity must be greater than zero.", "error")
        return redirect(url_for("orders"))

    with get_connection() as conn:
        with conn.cursor() as cur:
            try:
                # FOR UPDATE locks the row to prevent race conditions on stock
                cur.execute(
                    """
                    SELECT price, stock_quantity
                    FROM products
                    WHERE product_id = %s
                    FOR UPDATE
                    """,
                    (product_id,),
                )
                product = cur.fetchone()

                if not product:
                    flash("Selected product is no longer available.", "error")
                    return redirect(url_for("orders"))

                price = Decimal(str(product[0]))
                stock_quantity = int(product[1])

                if stock_quantity < quantity:
                    flash("Not enough stock is available for this order.", "error")
                    return redirect(url_for("orders"))

                subtotal = price * quantity

                cur.execute(
                    """
                    INSERT INTO orders (user_id, total_amount)
                    VALUES (%s, %s)
                    RETURNING order_id
                    """,
                    (user_id, subtotal),
                )
                order_id = cur.fetchone()[0]

                cur.execute(
                    """
                    INSERT INTO order_details (order_id, product_id, quantity, subtotal_price)
                    VALUES (%s, %s, %s, %s)
                    """,
                    (order_id, product_id, quantity, subtotal),
                )

                cur.execute(
                    """
                    UPDATE products
                    SET stock_quantity = stock_quantity - %s
                    WHERE product_id = %s
                    """,
                    (quantity, product_id),
                )
                conn.commit()
                logger.info(
                    "Order created: order_id=%d, user_id=%d, product_id=%d, qty=%d",
                    order_id, user_id, product_id, quantity,
                )
            except Exception:
                conn.rollback()
                logger.exception("Order creation failed — transaction rolled back.")
                raise

    flash("Order created successfully and inventory was updated.", "success")
    return redirect(url_for("orders"))


# ---------------------------------------------------------------------------
# Health check endpoint — used by ALB target group health checks
# ---------------------------------------------------------------------------
@app.route("/health")
def health():
    """
    Simple health check for the ALB target group.
    Returns 200 OK when the app is running, 503 if DB is unreachable.
    """
    try:
        with get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT 1")
        return {"status": "ok"}, 200
    except Exception as exc:  # noqa: BLE001
        logger.error("Health check failed: %s", exc)
        return {"status": "error", "detail": str(exc)}, 503


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=False)
