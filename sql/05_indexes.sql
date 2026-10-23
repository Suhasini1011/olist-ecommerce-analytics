-- Phase 5: index tuning with EXPLAIN ANALYZE (before and after)

-- 0. Refresh the table statistics the planner uses to choose a plan
ANALYZE analytics.fact_orders;
ANALYZE analytics.fact_order_items;

-- TEST A: look up one customer's orders (a selective lookup, like a customer service screen)
-- A1. BEFORE
EXPLAIN ANALYZE
SELECT order_id, purchase_date, payment_value, review_score
FROM analytics.fact_orders
WHERE customer_unique_id = '46958f708ade6b6a88b2e5aca1e66de5';

-- A2. Add the index
CREATE INDEX idx_fact_orders_customer ON analytics.fact_orders (customer_unique_id);

-- A3. AFTER (same query)
EXPLAIN ANALYZE
SELECT order_id, purchase_date, payment_value, review_score
FROM analytics.fact_orders
WHERE customer_unique_id = '46958f708ade6b6a88b2e5aca1e66de5';

-- TEST B: revenue by category (reads ALL items, so does an index help here?)
-- B1. BEFORE
EXPLAIN ANALYZE
SELECT p.category, SUM(i.price) AS revenue
FROM analytics.fact_order_items AS i
JOIN analytics.dim_product      AS p ON p.product_id = i.product_id
GROUP BY p.category;

-- B2. Add the index
CREATE INDEX idx_fact_items_product ON analytics.fact_order_items (product_id);

-- B3. AFTER (same query)
EXPLAIN ANALYZE
SELECT p.category, SUM(i.price) AS revenue
FROM analytics.fact_order_items AS i
JOIN analytics.dim_product      AS p ON p.product_id = i.product_id
GROUP BY p.category;


-- RESULTS (Neon free tier, measured with EXPLAIN ANALYZE)
-- Test A, one customer's orders: Seq Scan 6.71 ms -> Index Scan 0.047 ms (~140x faster). Index kept.
-- Test B, revenue by category:   Seq Scan 68.1 ms -> Seq Scan 65.5 ms (index not used; the query reads every row).
--                                Index dropped: no benefit, and it costs space and load time.
DROP INDEX IF EXISTS analytics.idx_fact_items_product;