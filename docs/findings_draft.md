# Findings (draft, from sql/06_analysis.sql)

Window: Jan 2017 - Aug 2018. Patterns are associations, not proof of cause.

## 1. Delivery performance
- Median delivery 10.2 days (mean 12.5); 6.8% of delivered orders arrive after the promised date.
- Orders arrive on average 11.8 days BEFORE the promised date: estimates are very cautious.
  (Whether long promises put off buyers cannot be tested with this data.)
- SP (40k orders): 8.7 days, 4.5% late. Northeast (CE, BA, PE): 18-21 days, up to 13.8% late.
- RJ is the standout problem: 2nd-largest market (12k orders), close to SP, yet 12.2% late.

## 2. What drives low review scores (1-2 stars)
- Low-score rate: on time 9.2%, late 62.4%, not delivered 77.8%.
- Dose-response: 1-3 days late 32.1%, 4-7 days 67.7%, over a week 79.3%.
- Late + not-delivered orders are ~9% of reviewed orders but ~43% of low scores.
- On-time orders with several sellers: 46.9% low scores vs 8.7% (small group: 1,246 orders). Lead, not proven.
- Freight cost has little effect (12.6% -> 15.4% low scores even when freight >= item value).

## 3. Category and seller revenue
- Top 10 categories = 62.4% of item revenue; largest (health_beauty) only 9.3%: spread out.
- 537 of 3,029 sellers (17.7%) generate 80% of revenue: strong seller concentration.

## 4. Repeat behaviour
- Only 2.17% of customers buy again on a different day.
- Counting "2+ orders" gives 3.04%, overstating repeat by ~40% (split checkouts).
- First delivery late: 1.62% came back vs 2.21% on time (27% fewer; z ~ 3). Region may also contribute.

## 5. Where money is lost
- Canceled + unavailable: R$257k (~1.6% of paid value); unavailable (stock) alone R$124k.
- 1,097 orders (R$176k) stuck at 'shipped', never marked delivered: check their age before drawing conclusions.
- Indirect: late delivery is linked to bad reviews and fewer returning customers, in a business where repeat is already only 2%.


YoY looks strong, but the monthly trend shows growth plateaued in 2018.