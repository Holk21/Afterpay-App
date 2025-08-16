-- Core tables
CREATE TABLE IF NOT EXISTS afterpay_catalog (
  id INT AUTO_INCREMENT PRIMARY KEY,
  shop_id VARCHAR(64) NOT NULL,
  name VARCHAR(64) NOT NULL,
  label VARCHAR(100) NOT NULL,
  price INT NOT NULL DEFAULT 0,
  image_url VARCHAR(255) NULL,
  UNIQUE KEY shop_item (shop_id, name)
);

CREATE TABLE IF NOT EXISTS afterpay_orders (
  id INT AUTO_INCREMENT PRIMARY KEY,
  citizenid VARCHAR(64) NOT NULL,
  shop_id VARCHAR(64) NOT NULL,
  plan_id VARCHAR(64) NOT NULL,
  total INT NOT NULL DEFAULT 0,
  status VARCHAR(32) NOT NULL DEFAULT 'active',
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS afterpay_order_items (
  id INT AUTO_INCREMENT PRIMARY KEY,
  order_id INT NOT NULL,
  item_name VARCHAR(64) NOT NULL,
  label VARCHAR(100) NOT NULL,
  price INT NOT NULL DEFAULT 0,
  qty INT NOT NULL DEFAULT 1,
  KEY order_idx (order_id)
);

CREATE TABLE IF NOT EXISTS afterpay_installments (
  id INT AUTO_INCREMENT PRIMARY KEY,
  order_id INT NOT NULL,
  due_at DATETIME NOT NULL,
  amount INT NOT NULL DEFAULT 0,
  paid TINYINT(1) NOT NULL DEFAULT 0,
  paid_at DATETIME NULL,
  attempts INT NOT NULL DEFAULT 0,
  last_attempt_at DATETIME NULL,
  fee_applied TINYINT(1) NOT NULL DEFAULT 0,
  KEY order_idx (order_id),
  KEY due_idx (due_at)
);

-- Merchant payouts
CREATE TABLE IF NOT EXISTS afterpay_merchant_payouts (
  id INT AUTO_INCREMENT PRIMARY KEY,
  shop_id VARCHAR(64) NOT NULL,
  order_id INT NOT NULL,
  installment_id INT NULL,
  gross INT NOT NULL,
  fee INT NOT NULL,
  net INT NOT NULL,
  paid_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);
