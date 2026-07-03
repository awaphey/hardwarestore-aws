-- =============================================================================
-- HardwareStoreDB — PostgreSQL Schema
-- Converted from MSSQL (Assignment 1) for RDS PostgreSQL (Assignment 2)
-- =============================================================================

-- Drop tables in reverse dependency order (idempotent re-runs)
DROP TABLE IF EXISTS order_details CASCADE;
DROP TABLE IF EXISTS orders       CASCADE;
DROP TABLE IF EXISTS products     CASCADE;
DROP TABLE IF EXISTS users        CASCADE;

-- -----------------------------------------------------------------------------
-- Users: staff (Admin) and customers who place orders
-- -----------------------------------------------------------------------------
CREATE TABLE users (
    user_id       SERIAL PRIMARY KEY,
    username      VARCHAR(50)  NOT NULL UNIQUE,
    password_hash VARCHAR(128) NOT NULL,
    role          VARCHAR(20)  NOT NULL,
    email         VARCHAR(120) NOT NULL UNIQUE,
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    CONSTRAINT ck_users_role CHECK (role IN ('Admin', 'Customer'))
);

-- -----------------------------------------------------------------------------
-- Products: hardware store inventory catalog
-- -----------------------------------------------------------------------------
CREATE TABLE products (
    product_id     SERIAL PRIMARY KEY,
    product_name   VARCHAR(100)   NOT NULL,
    category       VARCHAR(60)    NOT NULL,
    price          DECIMAL(10,2)  NOT NULL,
    stock_quantity INT            NOT NULL,
    created_at     TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    CONSTRAINT ck_products_price         CHECK (price >= 0),
    CONSTRAINT ck_products_stock_quantity CHECK (stock_quantity >= 0)
);

-- -----------------------------------------------------------------------------
-- Orders: customer purchase records
-- -----------------------------------------------------------------------------
CREATE TABLE orders (
    order_id     SERIAL PRIMARY KEY,
    user_id      INT            NOT NULL REFERENCES users(user_id),
    order_date   TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    total_amount DECIMAL(10,2)  NOT NULL,
    CONSTRAINT ck_orders_total_amount CHECK (total_amount >= 0)
);

-- -----------------------------------------------------------------------------
-- Order_Details: line items for each order
-- -----------------------------------------------------------------------------
CREATE TABLE order_details (
    order_detail_id SERIAL PRIMARY KEY,
    order_id        INT           NOT NULL REFERENCES orders(order_id)   ON DELETE CASCADE,
    product_id      INT           NOT NULL REFERENCES products(product_id),
    quantity        INT           NOT NULL,
    subtotal_price  DECIMAL(10,2) NOT NULL,
    CONSTRAINT ck_order_details_quantity       CHECK (quantity > 0),
    CONSTRAINT ck_order_details_subtotal_price CHECK (subtotal_price >= 0)
);

-- Indexes to match the original MSSQL performance tuning
CREATE INDEX ix_orders_user_id           ON orders(user_id);
CREATE INDEX ix_order_details_order_id   ON order_details(order_id);
CREATE INDEX ix_order_details_product_id ON order_details(product_id);
