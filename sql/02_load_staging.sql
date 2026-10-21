-- Load the raw Olist CSVs into the staging tables.
-- Run in psql (not DBeaver): psql '<service URI>' -f sql/02_load_staging.sql
-- Run from the project folder. CSVs live in data/raw/ (not in Git; download from Kaggle).
-- Why psql: DBeaver's importer split review comments containing line breaks
-- into extra rows (158,240 instead of 99,224). \copy with FORMAT csv handles them correctly.
-- Note: orders, order_items and order_payments were first loaded with DBeaver,
-- which stored blanks as '' instead of NULL. The analytics layer uses NULLIF to handle both.

\copy staging.orders FROM 'data/raw/olist_orders_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy staging.order_items FROM 'data/raw/olist_order_items_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy staging.order_payments FROM 'data/raw/olist_order_payments_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy staging.order_reviews FROM 'data/raw/olist_order_reviews_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy staging.customers FROM 'data/raw/olist_customers_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy staging.sellers FROM 'data/raw/olist_sellers_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy staging.products FROM 'data/raw/olist_products_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy staging.category_translation FROM 'data/raw/product_category_name_translation.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')