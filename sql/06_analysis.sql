-- Phase 6: answering the 5 business questions
-- Window: Jan 2017 - Aug 2018 (in_analysis_window). Delivery measures use delivered orders with a delivery date.

-------------------------------------------------------------------
-- Q1. DELIVERY PERFORMANCE AGAINST THE PROMISED DATE
-------------------------------------------------------------------
-- Q1a. Overall
SELECT COUNT(*)                                                          AS delivered_orders,
       ROUND(AVG(delivery_days), 1)                                      AS avg_delivery_days,
       ROUND((PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY delivery_days))::numeric, 1) AS median_delivery_days,
       ROUND(100.0 * AVG(is_late::int), 1)                               AS pct_late,
       ROUND(AVG(days_vs_estimate), 1)                                   AS avg_days_vs_estimate
FROM analytics.fact_orders
WHERE in_analysis_window AND order_status = 'delivered' AND delivered_ts IS NOT NULL;

-- Q1b. Customer states with the most late deliveries (states with 1,000+ orders)
SELECT c.state,
       COUNT(*)                              AS delivered_orders,
       ROUND(AVG(f.delivery_days), 1)        AS avg_delivery_days,
       ROUND(100.0 * AVG(f.is_late::int), 1) AS pct_late
FROM analytics.fact_orders  AS f
JOIN analytics.dim_customer AS c ON c.customer_unique_id = f.customer_unique_id
WHERE f.in_analysis_window AND f.order_status = 'delivered' AND f.delivered_ts IS NOT NULL
GROUP BY c.state
HAVING COUNT(*) >= 1000
ORDER BY pct_late DESC;

-------------------------------------------------------------------
-- Q2. WHAT DRIVES LOW REVIEW SCORES (1-2 stars)
-------------------------------------------------------------------
-- Q2a. By delivery outcome
SELECT CASE WHEN order_status <> 'delivered' OR delivered_ts IS NULL THEN '1. not delivered'
            WHEN is_late THEN '2. delivered late'
            ELSE '3. delivered on time' END          AS outcome,
       COUNT(*)                                      AS reviewed_orders,
       ROUND(AVG(review_score), 2)                   AS avg_score,
       ROUND(100.0 * AVG((review_score <= 2)::int), 1) AS pct_low_score
FROM analytics.fact_orders
WHERE in_analysis_window AND review_score IS NOT NULL
GROUP BY 1
ORDER BY 1;

-- Q2b. By how late (delivered orders only)
SELECT CASE WHEN days_vs_estimate <= 0  THEN '1. on time or early'
            WHEN days_vs_estimate <= 3  THEN '2. 1-3 days late'
            WHEN days_vs_estimate <= 7  THEN '3. 4-7 days late'
            ELSE '4. over a week late' END           AS lateness,
       COUNT(*)                                      AS reviewed_orders,
       ROUND(AVG(review_score), 2)                   AS avg_score,
       ROUND(100.0 * AVG((review_score <= 2)::int), 1) AS pct_low_score
FROM analytics.fact_orders
WHERE in_analysis_window AND order_status = 'delivered' AND delivered_ts IS NOT NULL
  AND review_score IS NOT NULL
GROUP BY 1
ORDER BY 1;

-- Q2c. On-time orders only: one seller vs several sellers in the order
SELECT CASE WHEN sellers_count > 1 THEN 'several sellers' ELSE 'one seller' END AS order_type,
       COUNT(*)                                      AS reviewed_orders,
       ROUND(AVG(review_score), 2)                   AS avg_score,
       ROUND(100.0 * AVG((review_score <= 2)::int), 1) AS pct_low_score
FROM analytics.fact_orders
WHERE in_analysis_window AND order_status = 'delivered' AND delivered_ts IS NOT NULL
  AND NOT is_late AND review_score IS NOT NULL
GROUP BY 1;

-------------------------------------------------------------------
-- Q3. CATEGORY AND SELLER REVENUE CONTRIBUTION (item price, excluding canceled/unavailable)
-------------------------------------------------------------------
-- Q3a. Top 10 categories, share of revenue and running (cumulative) share
WITH cat AS (
    SELECT p.category, SUM(i.price) AS revenue
    FROM analytics.fact_order_items AS i
    JOIN analytics.dim_product      AS p ON p.product_id = i.product_id
    WHERE i.in_analysis_window AND i.order_status NOT IN ('canceled', 'unavailable')
    GROUP BY p.category
)
SELECT category,
       revenue,
       ROUND(100 * revenue / SUM(revenue) OVER (), 1)                          AS pct_of_total,
       ROUND(100 * SUM(revenue) OVER (ORDER BY revenue DESC) / SUM(revenue) OVER (), 1) AS cumulative_pct
FROM cat
ORDER BY revenue DESC
LIMIT 10;

-- Q3b. Seller concentration: how many sellers make 80% of revenue?
WITH s AS (
    SELECT seller_id, SUM(price) AS revenue
    FROM analytics.fact_order_items
    WHERE in_analysis_window AND order_status NOT IN ('canceled', 'unavailable')
    GROUP BY seller_id
),
ranked AS (
    SELECT revenue,
           ROW_NUMBER() OVER (ORDER BY revenue DESC)                     AS seller_rank,
           COUNT(*)     OVER ()                                          AS total_sellers,
           SUM(revenue) OVER (ORDER BY revenue DESC ROWS UNBOUNDED PRECEDING)
             / SUM(revenue) OVER ()                                      AS cumulative_share
    FROM s
)
SELECT MIN(seller_rank)                                     AS sellers_for_80pct,
       MAX(total_sellers)                                   AS total_sellers,
       ROUND(100.0 * MIN(seller_rank) / MAX(total_sellers), 1) AS pct_of_sellers
FROM ranked
WHERE cumulative_share >= 0.8;

-------------------------------------------------------------------
-- Q4. CUSTOMER REPEAT BEHAVIOUR
-------------------------------------------------------------------
-- Repeat = bought on 2+ different days. Compared with the naive "2+ orders" definition.
WITH c AS (
    SELECT customer_unique_id,
           COUNT(*)                      AS orders,
           COUNT(DISTINCT purchase_date) AS purchase_days
    FROM analytics.fact_orders
    WHERE in_analysis_window AND order_status NOT IN ('canceled', 'unavailable')
    GROUP BY customer_unique_id
)
SELECT COUNT(*)                                                   AS customers,
       COUNT(*) FILTER (WHERE purchase_days > 1)                  AS repeat_customers,
       ROUND(100.0 * COUNT(*) FILTER (WHERE purchase_days > 1) / COUNT(*), 2) AS pct_repeat,
       ROUND(100.0 * COUNT(*) FILTER (WHERE orders > 1) / COUNT(*), 2)        AS pct_repeat_naive
FROM c;

-------------------------------------------------------------------
-- Q5. WHERE MONEY IS BEING LOST
-------------------------------------------------------------------
-- Q5a. Paid value by order status (canceled + unavailable = sales that did not happen)
SELECT order_status,
       COUNT(*)                                                       AS orders,
       ROUND(SUM(payment_value), 0)                                   AS paid_value,
       ROUND(100 * SUM(payment_value) / SUM(SUM(payment_value)) OVER (), 2) AS pct_of_paid
FROM analytics.fact_orders
WHERE in_analysis_window
GROUP BY order_status
ORDER BY paid_value DESC;

-- Q5b. Freight burden: orders where shipping is a large share of the item value
SELECT CASE WHEN freight_value >= items_value       THEN '3. freight >= item value'
            WHEN freight_value >= 0.5 * items_value THEN '2. freight 50-100% of item value'
            ELSE '1. freight under 50%' END              AS freight_burden,
       COUNT(*)                                          AS orders,
       ROUND(AVG(review_score), 2)                       AS avg_score,
       ROUND(100.0 * AVG((review_score <= 2)::int), 1)   AS pct_low_score
FROM analytics.fact_orders
WHERE in_analysis_window AND items_count > 0 AND order_status = 'delivered'
GROUP BY 1
ORDER BY 1;


-- Q6. Do customers come back after a late first delivery?
WITH firsts AS (
    SELECT DISTINCT ON (customer_unique_id)
           customer_unique_id, purchase_date, is_late
    FROM analytics.fact_orders
    WHERE in_analysis_window AND order_status = 'delivered' AND delivered_ts IS NOT NULL
    ORDER BY customer_unique_id, purchase_ts
)
SELECT CASE WHEN f.is_late THEN 'first delivery late' ELSE 'first delivery on time' END AS first_experience,
       COUNT(*) AS customers,
       ROUND(100.0 * AVG((EXISTS (
           SELECT 1 FROM analytics.fact_orders AS o
           WHERE o.customer_unique_id = f.customer_unique_id
             AND o.purchase_date > f.purchase_date
             AND o.in_analysis_window
             AND o.order_status NOT IN ('canceled', 'unavailable')
       ))::int), 2) AS pct_came_back
FROM firsts AS f
GROUP BY 1;