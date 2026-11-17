-- ============================================================
-- Olist database: table creation script (PostgreSQL)
-- Run this once in an empty database, then load the CSV files
-- in this order (the order matters because of the foreign keys):
--   1. customers              <- olist_customers_dataset.csv
--   2. sellers                <- olist_sellers_dataset.csv
--   3. category_translation   <- product_category_name_translation.csv
--   4. products               <- olist_products_dataset.csv
--   5. orders                 <- olist_orders_dataset.csv
--   6. order_items            <- olist_order_items_dataset.csv
--   7. order_payments         <- olist_order_payments_dataset.csv
--   8. order_reviews          <- olist_order_reviews_dataset.csv
-- (olist_geolocation_dataset.csv is not used.)
-- ============================================================

create table customers (
  customer_id varchar(50) primary key,
  customer_unique_id varchar(50),
  customer_zip_code_prefix int,
  customer_city varchar(100),
  customer_state char(2)
);

create table sellers (
  seller_id varchar(50) primary key,
  seller_zip_code_prefix int,
  seller_city varchar(100),
  seller_state char(2)
);

create table category_translation (
  product_category_name varchar(100) primary key,
  product_category_name_english varchar(100)
);

-- "lenght" is spelled like this in the original CSV, so it is kept as is
create table products (
  product_id varchar(50) primary key,
  product_category_name varchar(100),
  product_name_lenght int,
  product_description_lenght int,
  product_photos_qty int,
  product_weight_g int,
  product_length_cm int,
  product_height_cm int,
  product_width_cm int
);

create table orders (
  order_id varchar(50) primary key,
  customer_id varchar(50) references customers(customer_id),
  order_status varchar(20),
  order_purchase_timestamp timestamp,
  order_approved_at timestamp,
  order_delivered_carrier_date timestamp,
  order_delivered_customer_date timestamp,
  order_estimated_delivery_date timestamp
);

create table order_items (
  order_id varchar(50) references orders(order_id),
  order_item_id int,
  product_id varchar(50) references products(product_id),
  seller_id varchar(50) references sellers(seller_id),
  shipping_limit_date timestamp,
  price numeric(10,2),
  freight_value numeric(10,2),
  primary key (order_id, order_item_id)
);

create table order_payments (
  order_id varchar(50) references orders(order_id),
  payment_sequential int,
  payment_type varchar(30),
  payment_installments int,
  payment_value numeric(10,2),
  primary key (order_id, payment_sequential)
);

-- No primary key here on purpose: the same review_id can appear more
-- than once in the data, and a primary key would make the import fail.
create table order_reviews (
  review_id varchar(50),
  order_id varchar(50) references orders(order_id),
  review_score int,
  review_comment_title text,
  review_comment_message text,
  review_creation_date timestamp,
  review_answer_timestamp timestamp
);
