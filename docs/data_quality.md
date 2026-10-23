# Data quality findings (staging layer)

All checks are in `sql/03_profile.sql`.

| # | Check | Finding | Decision |
|---|---|---|---|
| 1 | order_id unique in orders | 99,441 rows, 99,441 distinct | Primary key of orders |
| 2 | review_id unique in reviews | 99,224 rows, 98,410 distinct | One review is copied onto several orders from the same checkout (same customer, bought within seconds). Count reviews with DISTINCT review_id |
| 3 | Orders with more than one review | 547 orders (0.6%); scores sometimes differ | Keep the latest review per order (by review_answer_timestamp) |
| 4 | Date order | 0 delivered before purchase; 8 'delivered' with no date; 166 carrier dates before purchase; 23 deliveries before the carrier date | Keep all orders, flag date issues; exclude only from the measures they would distort |
| 5 | Orders per month | 2016 is thin (~330 orders, Nov missing); Sep-Oct 2018 have 20 (export cut-off) | Analysis window Jan 2017 - Aug 2018. YoY = Jan-Aug 2018 vs Jan-Aug 2017 |
| 6 | Items vs payments | 99.7% match; 249 'paid more' orders are credit card with ~6.5 instalments (+R$3,052, consistent with interest); 39 'paid less' (-R$199) unexplained | Category/seller revenue = item price (+ freight); customer spend = payment_value |
| 7 | Orders with no items | 775 (603 unavailable, 164 canceled, 8 other); 1 delivered order with no payment | Unavailable orders were paid for but had no items: investigate as lost sales |
| 8 | Product categories | 610 products (1.9%) have no category; 2 categories have no English name | Label 'unknown'; fall back to the Portuguese name |
| 9 | Review scores | Only 1-5 | Clean |

**Principle:** nothing is deleted. Problem records are flagged and excluded only from the calculations they would distort, so every total still reconciles to 99,441 orders.