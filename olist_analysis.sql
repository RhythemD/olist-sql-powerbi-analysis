
-- Olist E-Commerce Analysis (PostgreSQL)
-- Dataset: Brazilian E-Commerce Public Dataset by Olist (Kaggle)
-- Goal: understand sales, delivery performance and customer
--       reviews, and prepare clean views for a Power BI dashboard
-- Revenue is in BRL (Brazilian real)
-- Run order: top to bottom (views are dropped and recreated safely)



-- ------------------------------------------------------------
-- PART 1: DATA CHECKS (raw tables)
-- Why: before analysing anything I wanted to know what is missing
-- or odd in the data, so that the numbers later can be trusted.
-- ------------------------------------------------------------

-- Check 1: Date range: first and last order?
-- Why: to know which period the analysis covers and whether the
--      first and last months are complete.
-- Finding: orders run from 4 Sep 2016 to 17 Oct 2018. Delivered revenue
--          appears from Sep 2016 to Aug 2018 (see Q1). The first months
--          have very little data and there are no delivered orders
--          after Aug 2018.
select min(order_purchase_timestamp) as first_order,
       max(order_purchase_timestamp) as latest_order
from orders;

-- Check 2: How many orders have order_delivered_customer_date as NULL?
--          Are all of them not in delivered status?
-- Why: delivery time cannot be calculated without a delivery date.
--      I wanted to see if only undelivered orders have it missing.
-- Finding: No. 8 orders marked 'delivered' also have no delivery date,
--          so they are left out of the delivery analysis.
select order_status, count(*) as null_count
from orders
where order_delivered_customer_date is null
group by order_status
order by null_count desc;

-- Check 3: Are there orders with more than one review?
-- Why: if an order has 2 reviews, joining reviews to orders counts that
--      order twice and can slightly distort the average review score.
-- Finding: 547 orders have more than one review (a few have 3). This is
--          handled in the stg_delivery view by averaging reviews per order.
select order_id, count(review_id) as review_count
from order_reviews
group by order_id
having count(review_id) > 1
order by review_count desc;

-- Check 4: How many products have a blank category?
-- Why: the category analysis would miss these products.
-- Finding: 610 products have no category, so their items are labelled
--          'unknown' in the category analysis.
select count(*) as blank_counts
from products
where product_category_name is null
   or trim(product_category_name) = '';

-- Check 5: Which categories have no match in category_translation?
-- Why: I want category names in English for the dashboard. If a
--      category has no translation, it needs a fallback name.
-- Finding: 2 categories have no English translation: pc_gamer and
--          portateis_cozinha_e_preparadores_de_alimentos. The stg_sales
--          view falls back to their Portuguese names.
select distinct p.product_category_name
from products as p
left join category_translation as q
on p.product_category_name = q.product_category_name
where q.product_category_name is null
and p.product_category_name is not null;

-- Check 6: Are there any zero or negative values in price (order_items)?
-- Why: such rows would make revenue wrong.
-- Finding: no rows returned, so there are no zero or negative prices.
select order_id, price
from order_items
where price <= 0;


-- ------------------------------------------------------------
-- PART 2: STAGING VIEWS
-- Why: so I do not repeat the same filters and joins in every query.
-- All analysis below reads from these views.
-- Views depend on each other, so they are dropped in reverse order
-- and created in order.
-- ------------------------------------------------------------
drop view if exists stg_delivery;
drop view if exists stg_sales;
drop view if exists stg_delivered_orders;

-- View 1: delivered orders only
-- Why: revenue and delivery metrics should only count orders that
--      actually reached the customer. Orders without a delivery date
--      are removed because delivery time cannot be calculated for them.
create view stg_delivered_orders as
select o.order_id,
o.customer_id,
o.order_purchase_timestamp,
o.order_delivered_customer_date,
o.order_estimated_delivery_date
from orders as o
where o.order_status = 'delivered'
and o.order_delivered_customer_date is not null;

-- View 2: one row per item sold in a delivered order
-- Why: this is the base for all revenue, category and seller analysis.
-- coalesce picks the English category name first, then the Portuguese
-- name, then 'unknown', so no item is lost because of a missing name.
create view stg_sales as
select oi.order_id,
oi.order_item_id,
oi.product_id,
oi.seller_id,
d.customer_id,
d.order_purchase_timestamp,
oi.price,
oi.freight_value,
coalesce(t.product_category_name_english, p.product_category_name, 'unknown') as category
from order_items as oi
join stg_delivered_orders as d on oi.order_id = d.order_id
left join products as p on oi.product_id = p.product_id
left join category_translation as t on p.product_category_name = t.product_category_name;

-- View 3: one row per delivered order, built for Power BI
-- Why: Power BI can build the delivery visuals from one table instead
--      of many joins. It holds the customer state, delivery days, a
--      late flag (1 = late) and the review score.
-- Reviews are averaged per order first, so an order with 2 reviews is
-- not counted twice.
create view stg_delivery as
select d.order_id,
c.customer_state,
d.order_purchase_timestamp,
d.order_delivered_customer_date::date - d.order_purchase_timestamp::date as delivery_days,
case when d.order_delivered_customer_date > d.order_estimated_delivery_date then 1 else 0 end as is_late,
case when d.order_delivered_customer_date > d.order_estimated_delivery_date then 'late' else 'on_time' end as delivery_status,
r.review_score
from stg_delivered_orders as d
join customers as c on d.customer_id = c.customer_id
left join (
  select order_id, avg(review_score) as review_score
  from order_reviews
  group by order_id
) as r on d.order_id = r.order_id;

-- Check 7: do the views keep the right number of orders?
-- Why: to make sure the filters and joins in the views do not drop or
--      duplicate any orders by mistake.
-- Finding: 96,478 orders are delivered and 96,470 of them have a
--          delivery date. Both views also have 96,470 rows, so the
--          joins neither lose nor duplicate orders.
select
  (select count(*) from orders where order_status = 'delivered') as delivered_all,
  (select count(*) from orders where order_status = 'delivered' and order_delivered_customer_date is not null) as delivered_with_date,
  (select count(*) from stg_delivered_orders) as stg_delivered,
  (select count(*) from stg_delivery) as stg_delivery;


-- ------------------------------------------------------------
-- PART 3: REVENUE ANALYSIS
-- Question: how is the business growing and what sells the most?
-- ------------------------------------------------------------

-- Q1: Monthly revenue
-- Why: to see the sales trend over time and find the peak month.
-- Finding: revenue grew through 2017 and peaked in Nov 2017 (about
--          0.99M). In 2018 it stayed between about 0.83M and 0.98M.
--          Late 2016 months have very little data, and there is no
--          data for Nov 2016 or after Aug 2018.
select date_trunc('month', order_purchase_timestamp) as month,
       sum(price) as revenue
from stg_sales
group by 1
order by 1 desc;

-- Q2: Current month revenue vs last month revenue
-- Why: first step towards growth percentage. lag() brings the
--      previous row's value into the current row.
-- Finding: the first month has no previous month, so prev_revenue is NULL.
with monthly as (
  select date_trunc('month', order_purchase_timestamp) as month,
         sum(price) as revenue
  from stg_sales
  group by 1
)
select revenue,
       month,
       lag(revenue) over (order by month) as prev_revenue
from monthly
order by 2;

-- Q3: Growth percentage from last month vs current month
-- Why: to see which months grew or fell the fastest.
-- Two CTEs are used because prev_revenue must exist before the
-- growth formula can use it.
-- Finding: growth was fastest in early 2017 (Feb +109.5%, Mar +53.4%),
--          then Nov 2017 jumped +52.4% (Black Friday month) and fell
--          26.5% in Dec 2017. In 2018 revenue was almost flat, with
--          monthly changes between about -12% and +27%.
--          Dec 2016 (-100%) and Jan 2017 (over 1,000,000%) are not
--          meaningful: the revenue base is tiny and Nov 2016 has no
--          data, so lag() compares those months with the wrong one.
with monthly as (
  select date_trunc('month', order_purchase_timestamp) as month,
         sum(price) as revenue
  from stg_sales
  group by 1
),
with_prev as (
  select month,
         revenue,
         lag(revenue) over (order by month) as prev_revenue
  from monthly
)
select month,
       revenue,
       prev_revenue,
       round((revenue - prev_revenue) / prev_revenue * 100, 1) as growth_pct
from with_prev
order by month;

-- Q4: Top 10 categories by revenue
-- Why: to know which product categories bring the most money.
-- Finding: health_beauty (about 1.23M), watches_gifts (about 1.17M) and
--          bed_bath_table (about 1.02M) are the top 3.
select category,
       sum(price) as total_revenue
from stg_sales
group by category
order by sum(price) desc
limit 10;

-- Q5: Top 10 sellers by revenue
-- Why: to see whether sales depend on a few sellers.
-- Finding: the top 10 sellers together bring about 1.75M, which is only
--          about 13% of the 13.22M revenue. The best seller makes about
--          227K, so sales are spread across many sellers.
select seller_id,
       sum(price) as revenue
from stg_sales
group by seller_id
order by sum(price) desc
limit 10;


-- ------------------------------------------------------------
-- PART 4: PAYMENTS
-- ------------------------------------------------------------

-- Q6: Payment type split
-- Why: to understand how customers pay (credit card, boleto, voucher...).
-- The subquery in brackets gives the total of all payments, which is
-- used as the denominator for the percentage.
-- Note: this query uses all orders, not only delivered ones, and payment
--       value includes freight, so the total (about 16.0M) is higher than
--       the 13.22M product revenue.
-- Finding: credit card is 78.34% of payments, boleto 17.92%, voucher
--          2.37% and debit card 1.36%.
select payment_type,
       sum(payment_value) as payment_total,
       round(sum(payment_value) * 100.0 / (select sum(payment_value) from order_payments), 2) as percentage
from order_payments
group by payment_type
order by sum(payment_value) desc;


-- ------------------------------------------------------------
-- PART 5: DELIVERY AND CUSTOMER REVIEWS
-- Question: how good is delivery, and does it affect customers?
-- ------------------------------------------------------------

-- Q7: Average delivery time
-- Why: to know how long customers wait on average.
-- ::date removes the time part, so the difference is in whole days.
-- Finding: about 12.5 days from order to delivery.
select round(avg(order_delivered_customer_date::date - order_purchase_timestamp::date), 2) as avg_delivery_days
from stg_delivered_orders;

-- Q8: Late delivery percentage
-- Why: to see how often the promised delivery date is missed.
-- Each late order is counted as 1 and the rest as 0, so sum() gives
-- the number of late orders.
-- Finding: about 8.11% of delivered orders arrived late.
select count(*) as total_orders,
       sum(case when order_delivered_customer_date > order_estimated_delivery_date then 1 else 0 end) as total_late_orders,
       round(sum(case when order_delivered_customer_date > order_estimated_delivery_date then 1 else 0 end) * 100.0 / count(*), 2) as late_pct
from stg_delivered_orders;

-- Q9: Late vs on-time average review score
-- Why: to check if late delivery hurts customer satisfaction. This is
--      the main finding of the project.
-- Finding: on-time orders score about 4.29 and late orders about 2.57,
--          a drop of about 1.7 points. (Values can differ by about
--          0.01 from the dashboard, which averages reviews per order.)
select case when d.order_delivered_customer_date > d.order_estimated_delivery_date then 'late'
            else 'ontime' end as delivery_review,
       count(*) as total_reviews,
       round(avg(r.review_score), 2) as avg_review_score
from order_reviews as r
join stg_delivered_orders as d
on r.order_id = d.order_id
group by delivery_review;

-- Q10: State wise late percentage (top 10 worst states)
-- Why: to find where delivery problems are concentrated.
-- having count(*) >= 100 removes states with very few orders, because
-- their percentage would not be reliable.
-- Finding: AL (about 23.9%) and MA (about 19.7%) are the worst, followed
--          by PI, CE, SE, BA (about 14%) and RJ (about 13.5%).
select c.customer_state,
       count(*) as total_orders,
       round(sum(case when d.order_delivered_customer_date > d.order_estimated_delivery_date then 1 else 0 end) * 100.0 / count(*), 2) as late_pct
from stg_delivered_orders as d
join customers as c
on d.customer_id = c.customer_id
group by c.customer_state
having count(*) >= 100
order by late_pct desc
limit 10;


-- ------------------------------------------------------------
-- NOTES
-- 1. Revenue uses price only (freight is not included).
-- 2. Analysis covers delivered orders with a delivery date
--    (96,470 orders); 8 delivered orders without a date were excluded.
-- 3. Late 2016 has very little revenue and Nov 2016 has no delivered
--    orders, so growth numbers for Dec 2016 and Jan 2017 are not
--    meaningful. Delivered revenue ends in Aug 2018.
-- ------------------------------------------------------------
