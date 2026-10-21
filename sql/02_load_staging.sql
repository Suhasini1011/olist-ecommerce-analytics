-- Load the raw Olist CSVs into the staging tables (Neon PostgreSQL).
-- Run from the project folder in psql (not DBeaver):
--   psql "$NEON_URL" -f sql/02_load_staging.sql
-- CSVs live in data/raw/ (not in Git; download from Kaggle).
-- Why psql: DBeaver's CSV importer split review comments containing line breaks
-- into extra rows (158,240 instead of 99,224). \copy with FORMAT csv handles them correctly.
-- Each \copy is one transaction: if the connection drops, that table loads nothing,
-- so it is safe to rerun just that line. Never rerun a line that succeeded (it doubles the rows).
-- Verified row counts: orders 99,441; order_items 112,650; order_payments 103,886;
-- order_reviews 99,224; customers 99,441; sellers 3,095; products 32,951; category_translation 71.

\copy staging.orders FROM 'data/raw/olist_orders_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy staging.order_items FROM 'data/raw/olist_order_items_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy staging.order_payments FROM 'data/raw/olist_order_payments_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy staging.order_reviews FROM 'data/raw/olist_order_reviews_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy staging.customers FROM 'data/raw/olist_customers_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy staging.sellers FROM 'data/raw/olist_sellers_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy staging.products FROM 'data/raw/olist_products_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy staging.category_translation FROM 'data/raw/product_category_name_translation.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')