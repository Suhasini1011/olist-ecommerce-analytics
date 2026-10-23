-- Phase 4: build the analytics layer (star schema) from staging.
-- Safe to rerun: it drops and rebuilds the whole analytics schema.
-- Decisions come from docs/data_quality.md.

DROP SCHEMA IF EXISTS analytics CASCADE;
CREATE SCHEMA analytics;

---------------------------------------------------------------
-- DIMENSIONS (the "describe" tables)
---------------------------------------------------------------

-- dim_date: one row per calendar day (Power BI needs a full date table for time intelligence)
CREATE TABLE analytics.dim_date AS
SELECT d::date                                   AS date_key,
       EXTRACT(YEAR    FROM d)::int              AS year,
       EXTRACT(QUARTER FROM d)::int              AS quarter,
       EXTRACT(MONTH   FROM d)::int              AS month,
       TO_CHAR(d, 'Mon')                         AS month_name,
       TO_CHAR(d, 'YYYY-MM')                     AS year_month,
       EXTRACT(ISODOW  FROM d)::int              AS day_of_week,
       TO_CHAR(d, 'Dy')                          AS day_name,
       EXTRACT(ISODOW  FROM d) IN (6, 7)         AS is_weekend,
       (d >= DATE '2017-01-01' AND d < DATE '2018-09-01') AS in_analysis_window
FROM generate_series(DATE '2016-01-01', DATE '2018-12-31', INTERVAL '1 day') AS d;

-- dim_customer: one row per real person (customer_unique_id), location from their latest order
CREATE TABLE analytics.dim_customer AS
SELECT DISTINCT ON (c.customer_unique_id)
       c.customer_unique_id,
       c.customer_zip_code_prefix AS zip_prefix,
       c.customer_city            AS city,
       c.customer_state           AS state
FROM staging.customers AS c
JOIN staging.orders    AS o ON o.customer_id = c.customer_id
ORDER BY c.customer_unique_id, o.order_purchase_timestamp::timestamp DESC;

-- dim_product: English category, 'unknown' if missing, Portuguese if no translation
CREATE TABLE analytics.dim_product AS
SELECT p.product_id,
       COALESCE(t.product_category_name_english,
                NULLIF(p.product_category_name, ''),
                'unknown')                                       AS category,
       NULLIF(p.product_category_name, '')                       AS category_portuguese,
       NULLIF(p.product_photos_qty, '')::numeric::int            AS photos_qty,
       NULLIF(p.product_weight_g, '')::numeric::int              AS weight_g,
       NULLIF(p.product_length_cm, '')::numeric::int             AS length_cm,
       NULLIF(p.product_height_cm, '')::numeric::int             AS height_cm,
       NULLIF(p.product_width_cm, '')::numeric::int              AS width_cm,
       NULLIF(p.product_description_lenght, '')::numeric::int    AS description_length
FROM staging.products                  AS p
LEFT JOIN staging.category_translation AS t
       ON t.product_category_name = p.product_category_name;

-- dim_seller
CREATE TABLE analytics.dim_seller AS
SELECT seller_id,
       seller_zip_code_prefix AS zip_prefix,
       seller_city            AS city,
       seller_state           AS state
FROM staging.sellers;

---------------------------------------------------------------
-- FACT 1: fact_orders, one row per ORDER
---------------------------------------------------------------
CREATE TABLE analytics.fact_orders AS
WITH o AS (
    SELECT order_id, customer_id, order_status,
           order_purchase_timestamp::timestamp                   AS purchase_ts,
           NULLIF(order_approved_at, '')::timestamp              AS approved_ts,
           NULLIF(order_delivered_carrier_date, '')::timestamp   AS carrier_ts,
           NULLIF(order_delivered_customer_date, '')::timestamp  AS delivered_ts,
           NULLIF(order_estimated_delivery_date, '')::timestamp  AS estimated_ts
    FROM staging.orders
),
items AS (            -- add up items per order FIRST (avoids fan-out)
    SELECT order_id,
           COUNT(*)                   AS items_count,
           COUNT(DISTINCT seller_id)  AS sellers_count,
           SUM(price::numeric)        AS items_value,
           SUM(freight_value::numeric) AS freight_value
    FROM staging.order_items
    GROUP BY order_id
),
pay AS (              -- add up payments per order FIRST
    SELECT order_id,
           SUM(payment_value::numeric)    AS payment_value,
           MAX(payment_installments::int) AS max_installments
    FROM staging.order_payments
    GROUP BY order_id
),
main_pay AS (         -- the payment type that paid the most
    SELECT DISTINCT ON (order_id) order_id, payment_type AS main_payment_type
    FROM staging.order_payments
    ORDER BY order_id, payment_value::numeric DESC
),
rev AS (              -- latest review per order (decision from Phase 3)
    SELECT DISTINCT ON (order_id)
           order_id, review_id,
           review_score::int                            AS review_score,
           NULLIF(review_comment_message, '') IS NOT NULL AS has_review_comment
    FROM staging.order_reviews
    ORDER BY order_id, review_answer_timestamp::timestamp DESC
)
SELECT o.order_id,
       c.customer_unique_id,
       o.order_status,
       o.purchase_ts::date                           AS purchase_date,
       o.purchase_ts, o.approved_ts, o.carrier_ts, o.delivered_ts,
       o.estimated_ts::date                          AS estimated_delivery_date,
       COALESCE(i.items_count, 0)                    AS items_count,
       COALESCE(i.sellers_count, 0)                  AS sellers_count,
       COALESCE(i.items_value, 0)                    AS items_value,
       COALESCE(i.freight_value, 0)                  AS freight_value,
       p.payment_value,
       p.max_installments,
       mp.main_payment_type,
       r.review_id,
       r.review_score,
       r.has_review_comment,
       ROUND(EXTRACT(EPOCH FROM (o.delivered_ts - o.purchase_ts)) / 86400.0, 1) AS delivery_days,
       (o.delivered_ts::date - o.estimated_ts::date)                           AS days_vs_estimate,
       CASE WHEN o.delivered_ts IS NULL THEN NULL
            ELSE o.delivered_ts::date > o.estimated_ts::date END               AS is_late,
       (COALESCE(o.carrier_ts < o.purchase_ts, false)
        OR COALESCE(o.delivered_ts < o.carrier_ts, false)
        OR (o.order_status = 'delivered' AND o.delivered_ts IS NULL))          AS has_date_issue,
       DENSE_RANK() OVER (PARTITION BY c.customer_unique_id
                          ORDER BY o.purchase_ts::date)                        AS purchase_occasion,
       (o.purchase_ts >= DATE '2017-01-01' AND o.purchase_ts < DATE '2018-09-01') AS in_analysis_window
FROM o
JOIN staging.customers AS c  ON c.customer_id = o.customer_id
LEFT JOIN items        AS i  ON i.order_id    = o.order_id
LEFT JOIN pay          AS p  ON p.order_id    = o.order_id
LEFT JOIN main_pay     AS mp ON mp.order_id   = o.order_id
LEFT JOIN rev          AS r  ON r.order_id    = o.order_id;

---------------------------------------------------------------
-- FACT 2: fact_order_items, one row per ITEM
---------------------------------------------------------------
CREATE TABLE analytics.fact_order_items AS
SELECT i.order_id,
       i.order_item_id::int                    AS order_item_id,
       i.product_id,
       i.seller_id,
       f.customer_unique_id,
       f.purchase_date,
       f.order_status,
       NULLIF(i.shipping_limit_date, '')::timestamp AS shipping_limit_ts,
       i.price::numeric(10,2)                  AS price,
       i.freight_value::numeric(10,2)          AS freight_value,
       f.review_score,
       f.is_late,
       f.in_analysis_window
FROM staging.order_items     AS i
JOIN analytics.fact_orders   AS f ON f.order_id = i.order_id;

---------------------------------------------------------------
-- KEYS: primary keys (uniqueness) and foreign keys (every link must point to a real row)
---------------------------------------------------------------
ALTER TABLE analytics.dim_date         ADD PRIMARY KEY (date_key);
ALTER TABLE analytics.dim_customer     ADD PRIMARY KEY (customer_unique_id);
ALTER TABLE analytics.dim_product      ADD PRIMARY KEY (product_id);
ALTER TABLE analytics.dim_seller       ADD PRIMARY KEY (seller_id);
ALTER TABLE analytics.fact_orders      ADD PRIMARY KEY (order_id);
ALTER TABLE analytics.fact_order_items ADD PRIMARY KEY (order_id, order_item_id);

ALTER TABLE analytics.fact_orders
    ADD FOREIGN KEY (customer_unique_id) REFERENCES analytics.dim_customer,
    ADD FOREIGN KEY (purchase_date)      REFERENCES analytics.dim_date;
ALTER TABLE analytics.fact_order_items
    ADD FOREIGN KEY (order_id)      REFERENCES analytics.fact_orders,
    ADD FOREIGN KEY (product_id)    REFERENCES analytics.dim_product,
    ADD FOREIGN KEY (seller_id)     REFERENCES analytics.dim_seller,
    ADD FOREIGN KEY (purchase_date) REFERENCES analytics.dim_date;

---------------------------------------------------------------
-- VALIDATION: row counts and money must reconcile with staging
---------------------------------------------------------------
SELECT 'fact_orders'      AS check_name, COUNT(*)::text AS result, '99441'  AS expected FROM analytics.fact_orders
UNION ALL SELECT 'fact_order_items', COUNT(*)::text, '112650' FROM analytics.fact_order_items
UNION ALL SELECT 'dim_customer',     COUNT(*)::text, '96096'  FROM analytics.dim_customer
UNION ALL SELECT 'dim_product',      COUNT(*)::text, '32951'  FROM analytics.dim_product
UNION ALL SELECT 'dim_seller',       COUNT(*)::text, '3095'   FROM analytics.dim_seller
UNION ALL SELECT 'dim_date',         COUNT(*)::text, '1096'   FROM analytics.dim_date
UNION ALL SELECT 'item revenue matches',
       ((SELECT SUM(items_value) FROM analytics.fact_orders)
      = (SELECT SUM(price) FROM analytics.fact_order_items))::text, 'true';