-- Adds/ensures columns used by offline charging & late fee
-- (Safe to run multiple times)

-- Some MySQL versions don't support IF NOT EXISTS on ADD COLUMN.
-- If yours doesn't, remove the "IF NOT EXISTS" parts.

ALTER TABLE afterpay_installments
    ADD COLUMN IF NOT EXISTS attempts INT NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS last_attempt_at DATETIME NULL,
    ADD COLUMN IF NOT EXISTS fee_applied TINYINT(1) NOT NULL DEFAULT 0;

-- Merchant payout log (if not created yet)
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




If your MySQL version doesn’t support ADD COLUMN IF NOT EXISTS, replace that ALTER TABLE with:

-- Check columns manually or run these one-by-one (will error if they already exist):
ALTER TABLE afterpay_installments ADD COLUMN attempts INT NOT NULL DEFAULT 0;
ALTER TABLE afterpay_installments ADD COLUMN last_attempt_at DATETIME NULL;
ALTER TABLE afterpay_installments ADD COLUMN fee_applied TINYINT(1) NOT NULL DEFAULT 0;
