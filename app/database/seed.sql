-- =============================================================================
-- Seed data for HardwareStoreDB (PostgreSQL)
-- NOTE: Password hashes below are SHA-256 hex strings of the plaintext
--       passwords from Assignment 1. In production, use bcrypt/argon2.
-- =============================================================================

INSERT INTO users (username, password_hash, role, email) VALUES
    ('admin',  encode(digest('AdminPass123!',    'sha256'), 'hex'), 'Admin',    'admin@hardwarestore.test'),
    ('alicia', encode(digest('CustomerPass123!', 'sha256'), 'hex'), 'Customer', 'alicia@example.com'),
    ('ben',    encode(digest('CustomerPass456!', 'sha256'), 'hex'), 'Customer', 'ben@example.com');

-- NOTE: encode(digest(...)) requires the pgcrypto extension.
-- Run once in RDS: CREATE EXTENSION IF NOT EXISTS pgcrypto;
-- Alternatively, replace the above with plain placeholder hashes for demo:
-- INSERT INTO users (username, password_hash, role, email) VALUES
--     ('admin',  'demo_hash_admin',  'Admin',    'admin@hardwarestore.test'),
--     ('alicia', 'demo_hash_alicia', 'Customer', 'alicia@example.com'),
--     ('ben',    'demo_hash_ben',    'Customer', 'ben@example.com');

INSERT INTO products (product_name, category, price, stock_quantity) VALUES
    ('NVIDIA RTX 4070 Super Graphics Card', 'Graphics Card', 2999.00, 8),
    ('27-inch 165Hz Gaming Monitor',        'Monitor',        899.00, 12),
    ('Mechanical Keyboard - Blue Switch',   'Keyboard',       249.00, 20),
    ('Wireless Gaming Mouse',               'Mouse',          189.00, 15);
