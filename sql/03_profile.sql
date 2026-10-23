-- Phase 3: data quality checks on the staging layer

-- Check 1: is order_id unique in orders?
SELECT COUNT(*)                  AS total_rows,
       COUNT(DISTINCT order_id)  AS distinct_order_ids
FROM staging.orders;


-- Check 2: is review_id unique in order_reviews?
SELECT COUNT(*)                    AS total_rows,
       COUNT(DISTINCT review_id)     AS distinct_review_ids
FROM staging.order_reviews;

-- Check 3: which review_ids repeat, and do they belong to different orders?
SELECT review_id,
       COUNT(*)                  AS times_used,
       COUNT(DISTINCT order_id)  AS different_orders
FROM staging.order_reviews
GROUP BY review_id
HAVING COUNT(*) > 1
ORDER BY times_used DESC
LIMIT 10;


-- Check 4: is a repeated review the same customer, buying at the same time?
SELECT r.review_id,
       r.order_id,
       r.review_score,
       c.customer_unique_id,
       o.order_purchase_timestamp
FROM staging.order_reviews AS r
JOIN staging.orders        AS o ON o.order_id    = r.order_id
JOIN staging.customers     AS c ON c.customer_id = o.customer_id
WHERE r.review_id = '308316408775d1600dad81bd3184556d';



-- Check 5: how many orders have more than one review?
SELECT COUNT(*) AS orders_with_multiple_reviews
FROM (
    SELECT order_id
    FROM staging.order_reviews
    GROUP BY order_id
    HAVING COUNT(*) > 1
) AS multi;


-- Check 6: what do multiple reviews on the same order look like?
SELECT order_id,
       review_id,
       review_score,
       review_creation_date,
       review_answer_timestamp
FROM staging.order_reviews
WHERE order_id IN (
    SELECT order_id
    FROM staging.order_reviews
    GROUP BY order_id
    HAVING COUNT(*) > 1
)
ORDER BY order_id, review_answer_timestamp
LIMIT 20;




-- Finding: 547 orders have more than one review; scores sometimes differ (e.g. 3 then 1).
-- Decision: keep the latest review per order (by review_answer_timestamp).
-- Finding: 814 review rows reuse a review_id across orders: one review copied onto
--          orders from the same checkout (same customer, bought within seconds).
--          Count reviews with COUNT(DISTINCT review_id).

-- Check 7: are the order dates in a logical order?
SELECT
    COUNT(*) FILTER (WHERE order_status = 'delivered'
                       AND NULLIF(order_delivered_customer_date, '') IS NULL)        AS delivered_but_no_date,
    COUNT(*) FILTER (WHERE NULLIF(order_approved_at, '')::timestamp
                         < order_purchase_timestamp::timestamp)                     AS approved_before_purchase,
    COUNT(*) FILTER (WHERE NULLIF(order_delivered_carrier_date, '')::timestamp
                         < order_purchase_timestamp::timestamp)                     AS shipped_before_purchase,
    COUNT(*) FILTER (WHERE NULLIF(order_delivered_customer_date, '')::timestamp
                         < NULLIF(order_delivered_carrier_date, '')::timestamp)     AS delivered_before_shipped,
    COUNT(*) FILTER (WHERE NULLIF(order_delivered_customer_date, '')::timestamp
                         < order_purchase_timestamp::timestamp)                     AS delivered_before_purchase
FROM staging.orders;

-- Finding: purchase -> delivered dates are clean (0 delivered before purchase).
-- Finding: 8 orders are 'delivered' with no delivery date: excluded from delivery-time measures.
-- Finding: 166 carrier dates are before purchase, and 23 deliveries are before the carrier date.
-- Decision: keep these orders, but flag them; exclude them only from carrier-stage analysis.

-- Check 8: orders per month (find thin months at the start and end)
SELECT DATE_TRUNC('month', order_purchase_timestamp::timestamp)::date AS month,
       COUNT(*) AS orders
FROM staging.orders
GROUP BY 1
ORDER BY 1;

-- Finding: 2016 has ~330 orders (Nov 2016 missing); Sep-Oct 2018 have 20 (export cut-off).
-- Decision: analysis window Jan 2017 - Aug 2018 (20 full months).
--           YoY compares Jan-Aug 2018 vs Jan-Aug 2017 only.
-- Note: Nov 2017 spike (7,544 orders), likely Black Friday; verify with daily data before claiming.

-- Check 9: do item totals match payment totals per order?
WITH items AS (
    SELECT order_id,
           SUM(price::numeric + freight_value::numeric) AS item_total
    FROM staging.order_items
    GROUP BY order_id
),
pay AS (
    SELECT order_id,
           SUM(payment_value::numeric) AS paid
    FROM staging.order_payments
    GROUP BY order_id
)
SELECT COUNT(*)                                                   AS orders_compared,
       COUNT(*) FILTER (WHERE ABS(i.item_total - p.paid) <= 0.01) AS amounts_match,
       COUNT(*) FILTER (WHERE p.paid > i.item_total + 0.01)       AS paid_more_than_items,
       COUNT(*) FILTER (WHERE p.paid < i.item_total - 0.01)       AS paid_less_than_items
FROM items AS i
JOIN pay   AS p ON p.order_id = i.order_id;


-- Check 10: mismatched orders, by payment type and instalments
WITH items AS (
    SELECT order_id,
           SUM(price::numeric + freight_value::numeric) AS item_total
    FROM staging.order_items
    GROUP BY order_id
),
pay AS (
    SELECT order_id,
           SUM(payment_value::numeric)                             AS paid,
           MAX(payment_installments::int)                          AS max_installments,
           STRING_AGG(DISTINCT payment_type, ', ')                 AS payment_types
    FROM staging.order_payments
    GROUP BY order_id
)
SELECT CASE WHEN p.paid > i.item_total THEN 'paid more' ELSE 'paid less' END AS mismatch,
       p.payment_types,
       COUNT(*)                                  AS orders,
       ROUND(AVG(p.max_installments), 1)         AS avg_installments,
       ROUND(SUM(p.paid - i.item_total), 2)      AS total_difference
FROM items AS i
JOIN pay   AS p ON p.order_id = i.order_id
WHERE ABS(p.paid - i.item_total) > 0.01
GROUP BY 1, 2
ORDER BY 1, 3 DESC;


-- Finding: 98,362 of 98,665 orders (99.7%) have payments equal to items + freight.
-- Finding: 249 'paid more' orders are credit card with ~6.5 instalments (+R$3,052 in total),
--          consistent with instalment interest. 39 'paid less' orders (-R$199) are unexplained.
-- Decision: category/seller revenue = item price (+ freight); customer spend = payment_value.


-- Check 11: orders with no items or no payments, by status
SELECT o.order_status,
       COUNT(*) FILTER (WHERE NOT EXISTS (SELECT 1 FROM staging.order_items    AS i WHERE i.order_id = o.order_id)) AS no_items,
       COUNT(*) FILTER (WHERE NOT EXISTS (SELECT 1 FROM staging.order_payments AS p WHERE p.order_id = o.order_id)) AS no_payments
FROM staging.orders AS o
GROUP BY o.order_status
ORDER BY no_items DESC;

-- Finding: 775 orders have no items (603 unavailable, 164 canceled, 8 other); 1 delivered order has no payment.
-- Lead for 'where money is lost': unavailable orders have payments but no items (lost sales from stock issues).

-- Check 12: product categories and review scores
SELECT
    (SELECT COUNT(*) FROM staging.products
      WHERE NULLIF(product_category_name, '') IS NULL)                      AS products_no_category,
    (SELECT COUNT(DISTINCT p.product_category_name) FROM staging.products AS p
      WHERE NULLIF(p.product_category_name, '') IS NOT NULL
        AND NOT EXISTS (SELECT 1 FROM staging.category_translation AS t
                         WHERE t.product_category_name = p.product_category_name)) AS categories_no_english,
    (SELECT STRING_AGG(DISTINCT review_score, ', ') FROM staging.order_reviews) AS review_score_values;