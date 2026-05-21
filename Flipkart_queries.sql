CREATE DATABASE IF NOT EXISTS flipkart_sales;
USE flipkart_sales;
CREATE TABLE dim_products (
    product_id       VARCHAR(10)    PRIMARY KEY,
    product_name     TEXT,
    main_category    VARCHAR(100),
    brand            VARCHAR(100),
    retail_price     DECIMAL(10,2),
    discounted_price DECIMAL(10,2),
    discount_pct     DECIMAL(5,2)
);
CREATE TABLE dim_customers (
    customer_id      VARCHAR(10)   PRIMARY KEY,
    customer_name    VARCHAR(100),
    city             VARCHAR(50),
    state            VARCHAR(50),
    age              INT,
    customer_segment VARCHAR(30)
);
CREATE TABLE dim_sellers (
    seller_id        VARCHAR(10)   PRIMARY KEY,
    seller_name      VARCHAR(100),
    seller_city      VARCHAR(50),
    seller_rating    DECIMAL(3,1),
    joined_year      INT
);
CREATE TABLE fact_orders (
    order_id             VARCHAR(15)   PRIMARY KEY,
    order_date           DATE,
    order_month          INT,
    order_year           INT,
    order_quarter        VARCHAR(5),
    is_weekend           TINYINT(1),
    is_big_billion_day   TINYINT(1),
    is_festive_season    TINYINT(1),
    customer_id          VARCHAR(10),
    product_id           VARCHAR(10),
    seller_id            VARCHAR(10),
    quantity             INT,
    unit_price           DECIMAL(10,2),
    retail_price         DECIMAL(10,2),
    total_amount         DECIMAL(10,2),
    discount_pct         DECIMAL(5,2),
    payment_method       VARCHAR(20),
    order_status         VARCHAR(20),
    main_category        VARCHAR(100),
    FOREIGN KEY (customer_id) REFERENCES dim_customers(customer_id),
    FOREIGN KEY (product_id)  REFERENCES dim_products(product_id),
    FOREIGN KEY (seller_id)   REFERENCES dim_sellers(seller_id)
);
CREATE TABLE fact_returns (
    return_id       VARCHAR(12)   PRIMARY KEY,
    order_id        VARCHAR(15),
    product_id      VARCHAR(10),
    customer_id     VARCHAR(10),
    main_category   VARCHAR(100),
    return_date     DATE,
    return_reason   VARCHAR(100),
    refund_amount   DECIMAL(10,2),
    return_status   VARCHAR(30),
    FOREIGN KEY (order_id)    REFERENCES fact_orders(order_id),
    FOREIGN KEY (product_id)  REFERENCES dim_products(product_id),
    FOREIGN KEY (customer_id) REFERENCES dim_customers(customer_id)
);
SHOW TABLES;
select * from dim_products;
Select * from dim_customers;
select * from dim_sellers;

-- ════════════════════════════════════════════════════════════
--  Q1: Big Billion Days vs Regular Day — sales comparison
--      Uses: CASE WHEN, GROUP BY, aggregation
-- ════════════════════════════════════════════════════════════
 
CREATE OR REPLACE VIEW v_bbd_vs_regular AS
SELECT
    CASE
        WHEN is_big_billion_day = 1 THEN 'Big Billion Days'
        WHEN is_festive_season  = 1 THEN 'Festive Season'
        ELSE 'Regular Day'
    END                                           AS day_type,
 
    COUNT(DISTINCT order_date)                    AS total_days,
    COUNT(*)                                      AS total_orders,
    ROUND(SUM(total_amount), 0)                   AS total_revenue,
    ROUND(AVG(total_amount), 0)                   AS avg_order_value,
    ROUND(COUNT(*) / COUNT(DISTINCT order_date), 0) AS orders_per_day,
    ROUND(SUM(total_amount) / COUNT(DISTINCT order_date), 0) AS revenue_per_day,
 
    -- Category breakdown during each period
    GROUP_CONCAT(DISTINCT main_category
        ORDER BY main_category SEPARATOR ', ')    AS top_categories
 
FROM fact_orders
WHERE order_status = 'Delivered'
GROUP BY day_type
ORDER BY revenue_per_day DESC;
 
-- Drill down: daily revenue trend with BBD flag
CREATE OR REPLACE VIEW v_daily_revenue_trend AS
SELECT
    order_date,
    order_year,
    order_month,
    is_big_billion_day,
    is_festive_season,
    is_weekend,
    COUNT(*)                     AS total_orders,
    ROUND(SUM(total_amount), 0)  AS daily_revenue,
    ROUND(AVG(total_amount), 0)  AS avg_order_value,
    COUNT(DISTINCT customer_id)  AS unique_customers
FROM fact_ordersv_bbd_vs_regular
WHERE order_status = 'Delivered'
GROUP BY order_date, order_year, order_month,
         is_big_billion_day, is_festive_season, is_weekend
ORDER BY order_date;

SELECT * FROM v_bbd_vs_regular;

-- ════════════════════════════════════════════════════════════
--  Q2: Product return rate by category — RATIO calculation
--      Uses: LEFT JOIN, RATIO, CASE WHEN
-- ════════════════════════════════════════════════════════════
 
CREATE OR REPLACE VIEW v_return_rate_by_category AS
SELECT
    o.main_category,
    COUNT(DISTINCT o.order_id)                    AS total_orders,
    COUNT(DISTINCT r.return_id)                   AS total_returns,
 
    -- Return rate ratio
    ROUND(
        COUNT(DISTINCT r.return_id) * 100.0
        / NULLIF(COUNT(DISTINCT o.order_id), 0),
    2)                                            AS return_rate_pct,
 
    ROUND(SUM(r.refund_amount), 0)                AS total_refunded,
    ROUND(AVG(r.refund_amount), 0)                AS avg_refund_amount,
 
    -- Most common return reason per category
    -- (use a subquery for this)
    ROUND(SUM(o.total_amount), 0)                 AS total_revenue,
 
    -- Revenue lost to returns as % of gross revenue
    ROUND(
        SUM(r.refund_amount) * 100.0
        / NULLIF(SUM(o.total_amount), 0),
    2)                                            AS revenue_loss_pct,
 
    CASE
        WHEN COUNT(DISTINCT r.return_id) * 100.0
             / NULLIF(COUNT(DISTINCT o.order_id), 0) > 15 THEN 'High Risk'
        WHEN COUNT(DISTINCT r.return_id) * 100.0
             / NULLIF(COUNT(DISTINCT o.order_id), 0) > 8  THEN 'Medium Risk'
        ELSE 'Low Risk'
    END                                           AS return_risk_level
 
FROM fact_orders o
LEFT JOIN fact_returns r ON o.order_id = r.order_id
GROUP BY o.main_category
ORDER BY return_rate_pct DESC;
 
-- Return reasons breakdown per category
CREATE OR REPLACE VIEW v_return_reasons AS
SELECT
    main_category,
    return_reason,
    COUNT(*)                                      AS return_count,
    ROUND(SUM(refund_amount), 0)                  AS total_refunded,
    RANK() OVER (
        PARTITION BY main_category
        ORDER BY COUNT(*) DESC
    )                                             AS reason_rank
FROM fact_returns
GROUP BY main_category, return_reason
ORDER BY main_category, reason_rank;

Select *  from v_return_rate_by_category;

-- ════════════════════════════════════════════════════════════
--  Q3: Customer cohort retention
--      Uses: Multi-table JOINs, DATE functions, cohort logic
-- ════════════════════════════════════════════════════════════
 
-- First purchase month per customer = their cohort
CREATE OR REPLACE VIEW v_customer_cohorts AS
SELECT
    c.customer_id,
    c.customer_name,
    c.city,
    c.state,
    c.customer_segment,
    c.age,
 
    -- Cohort = month of first ever order
    DATE_FORMAT(MIN(o.order_date), '%Y-%m')       AS cohort_month,
    MIN(o.order_date)                             AS first_order_date,
    MAX(o.order_date)                             AS last_order_date,
    COUNT(DISTINCT o.order_id)                    AS total_orders,
    ROUND(SUM(o.total_amount), 0)                 AS lifetime_value,
    ROUND(AVG(o.total_amount), 0)                 AS avg_order_value,
 
    -- Are they a repeat customer?
    CASE
        WHEN COUNT(DISTINCT o.order_id) > 1 THEN 'Repeat'
        ELSE 'One-time'
    END                                           AS customer_type,
 
    -- Days between first and last order
    DATEDIFF(MAX(o.order_date), MIN(o.order_date)) AS customer_lifespan_days
 
FROM dim_customers c
INNER JOIN fact_orders o
    ON c.customer_id = o.customer_id
   AND o.order_status = 'Delivered'
GROUP BY
    c.customer_id, c.customer_name, c.city, c.state,
    c.customer_segment, c.age;
 
-- Cohort size and repeat rate by month
CREATE OR REPLACE VIEW v_cohort_summary AS
SELECT
    cohort_month,
    COUNT(*)                                          AS cohort_size,
    SUM(CASE WHEN customer_type = 'Repeat' THEN 1 ELSE 0 END) AS repeat_customers,
    ROUND(
        SUM(CASE WHEN customer_type = 'Repeat' THEN 1 ELSE 0 END)
        * 100.0 / COUNT(*), 1
    )                                                 AS retention_rate_pct,
    ROUND(AVG(lifetime_value), 0)                     AS avg_ltv,
    ROUND(AVG(total_orders), 1)                       AS avg_orders_per_customer
FROM v_customer_cohorts
GROUP BY cohort_month
ORDER BY cohort_month;

Select * from v_customer_cohorts;
-- ════════════════════════════════════════════════════════════
--  Q4: Top sellers using DENSE_RANK with revenue filter
--      Uses: DENSE_RANK(), window functions, multi-table JOIN
-- ════════════════════════════════════════════════════════════
 
CREATE OR REPLACE VIEW v_seller_performance AS
SELECT
    s.seller_id,
    s.seller_name,
    s.seller_city,
    s.seller_rating,
    s.joined_year,
 
    COUNT(DISTINCT o.order_id)              AS total_orders,
    ROUND(SUM(o.total_amount), 0)           AS total_revenue,
    ROUND(AVG(o.total_amount), 0)           AS avg_order_value,
    COUNT(DISTINCT o.customer_id)           AS unique_customers,
    COUNT(DISTINCT o.main_category)         AS categories_sold,
 
    -- Return rate for this seller
    COUNT(DISTINCT r.return_id)             AS total_returns,
    ROUND(
        COUNT(DISTINCT r.return_id) * 100.0
        / NULLIF(COUNT(DISTINCT o.order_id), 0),
    1)                                      AS return_rate_pct,
 
    -- Rank by revenue using DENSE_RANK
    DENSE_RANK() OVER (
        ORDER BY SUM(o.total_amount) DESC
    )                                       AS revenue_rank,
 
    -- Rank within their city
    DENSE_RANK() OVER (
        PARTITION BY s.seller_city
        ORDER BY SUM(o.total_amount) DESC
    )                                       AS city_revenue_rank,
 
    -- Seller tier based on revenue
    CASE
        WHEN SUM(o.total_amount) >= 500000  THEN 'Platinum'
        WHEN SUM(o.total_amount) >= 200000  THEN 'Gold'
        WHEN SUM(o.total_amount) >= 50000   THEN 'Silver'
        ELSE 'Bronze'
    END                                     AS seller_tier
 
FROM dim_sellers s
INNER JOIN fact_orders o  ON s.seller_id = o.seller_id
                         AND o.order_status = 'Delivered'
LEFT  JOIN fact_returns r ON o.order_id = r.order_id
GROUP BY
    s.seller_id, s.seller_name, s.seller_city,
    s.seller_rating, s.joined_year
ORDER BY revenue_rank;
-- ════════════════════════════════════════════════════════════
--  Q4: Top sellers using DENSE_RANK with revenue filter
--      Uses: DENSE_RANK(), window functions, multi-table JOIN
-- ════════════════════════════════════════════════════════════
 
CREATE OR REPLACE VIEW v_seller_performance AS
SELECT
    s.seller_id,
    s.seller_name,
    s.seller_city,
    s.seller_rating,
    s.joined_year,
 
    COUNT(DISTINCT o.order_id)              AS total_orders,
    ROUND(SUM(o.total_amount), 0)           AS total_revenue,
    ROUND(AVG(o.total_amount), 0)           AS avg_order_value,
    COUNT(DISTINCT o.customer_id)           AS unique_customers,
    COUNT(DISTINCT o.main_category)         AS categories_sold,
 
    -- Return rate for this seller
    COUNT(DISTINCT r.return_id)             AS total_returns,
    ROUND(
        COUNT(DISTINCT r.return_id) * 100.0
        / NULLIF(COUNT(DISTINCT o.order_id), 0),
    1)                                      AS return_rate_pct,
 
    -- Rank by revenue using DENSE_RANK
    DENSE_RANK() OVER (
        ORDER BY SUM(o.total_amount) DESC
    )                                       AS revenue_rank,
 
    -- Rank within their city
    DENSE_RANK() OVER (
        PARTITION BY s.seller_city
        ORDER BY SUM(o.total_amount) DESC
    )                                       AS city_revenue_rank,
 
    -- Seller tier based on revenue
    CASE
        WHEN SUM(o.total_amount) >= 500000  THEN 'Platinum'
        WHEN SUM(o.total_amount) >= 200000  THEN 'Gold'
        WHEN SUM(o.total_amount) >= 50000   THEN 'Silver'
        ELSE 'Bronze'
    END                                     AS seller_tier
 
FROM dim_sellers s
INNER JOIN fact_orders o  ON s.seller_id = o.seller_id
                         AND o.order_status = 'Delivered'
LEFT  JOIN fact_returns r ON o.order_id = r.order_id
GROUP BY
    s.seller_id, s.seller_name, s.seller_city,
    s.seller_rating, s.joined_year
ORDER BY revenue_rank;
 
-- Top 10 sellers overall (for Power BI table)
SELECT * FROM v_seller_performance
WHERE revenue_rank <= 10;
 
-- Top 3 sellers per city
SELECT * FROM v_seller_performance
WHERE city_revenue_rank <= 3
ORDER BY seller_city, city_revenue_rank;
 -- ════════════════════════════════════════════════════════════
--  Q5: Monthly revenue trend with MoM growth
--      Uses: LAG(), window function, date aggregation
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE VIEW v_monthly_revenue AS
SELECT
    order_year,
    order_month,
    DATE_FORMAT(MIN(order_date), '%Y-%m')        AS yearmonth,
    COUNT(*)                                      AS total_orders,
    ROUND(SUM(total_amount), 0)                   AS monthly_revenue,
    ROUND(AVG(total_amount), 0)                   AS avg_order_value,
    COUNT(DISTINCT customer_id)                   AS unique_customers,
    SUM(is_big_billion_day)                       AS bbd_orders,
    SUM(is_festive_season)                        AS festive_orders,
 
    -- Month over month revenue growth %
    ROUND(
        (SUM(total_amount) - LAG(SUM(total_amount))
            OVER (ORDER BY order_year, order_month))
        * 100.0
        / NULLIF(LAG(SUM(total_amount))
            OVER (ORDER BY order_year, order_month), 0),
    1)                                            AS mom_growth_pct,
 
    -- Running cumulative revenue
    ROUND(SUM(SUM(total_amount))
        OVER (ORDER BY order_year, order_month), 0) AS cumulative_revenue
 
FROM fact_orders
WHERE order_status = 'Delivered'
GROUP BY order_year, order_month
ORDER BY order_year, order_month;
 
 Select * from v_monthly_revenue;
 -- ════════════════════════════════════════════════════════════
--  Q6: Payment method intelligence
--      UPI vs COD vs Card — who spends more?
-- ════════════════════════════════════════════════════════════
 
CREATE OR REPLACE VIEW v_payment_intelligence AS
SELECT
    payment_method,
    COUNT(*)                                      AS total_orders,
    ROUND(SUM(total_amount), 0)                   AS total_revenue,
    ROUND(AVG(total_amount), 0)                   AS avg_order_value,
    COUNT(DISTINCT customer_id)                   AS unique_customers,
    ROUND(COUNT(*) * 100.0
        / SUM(COUNT(*)) OVER (), 1)               AS order_share_pct,
 
    -- Return rate by payment method
    -- (COD typically has higher returns)
    ROUND(AVG(discount_pct), 1)                   AS avg_discount_taken
 
FROM fact_orders
WHERE order_status IN ('Delivered','Returned')
GROUP BY payment_method
ORDER BY total_revenue DESC;


-- ════════════════════════════════════════════════════════════
--  Q7: Customer segment value analysis
--      Multi-table JOIN: customers + orders + returns
-- ════════════════════════════════════════════════════════════
 
CREATE OR REPLACE VIEW v_segment_analysis AS
SELECT
    c.customer_segment,
    COUNT(DISTINCT c.customer_id)                 AS total_customers,
    COUNT(DISTINCT o.order_id)                    AS total_orders,
    ROUND(SUM(o.total_amount), 0)                 AS total_revenue,
    ROUND(AVG(o.total_amount), 0)                 AS avg_order_value,
    ROUND(SUM(o.total_amount)
        / COUNT(DISTINCT c.customer_id), 0)       AS avg_ltv_per_customer,
 
    -- Most popular category per segment
    -- Return behaviour
    COUNT(DISTINCT r.return_id)                   AS total_returns,
    ROUND(
        COUNT(DISTINCT r.return_id) * 100.0
        / NULLIF(COUNT(DISTINCT o.order_id), 0),
    1)                                            AS return_rate_pct,
 
    -- Payment preference
    -- (shows which segment trusts digital payments more)
    ROUND(
        SUM(CASE WHEN o.payment_method = 'COD'
            THEN 1 ELSE 0 END) * 100.0
        / COUNT(*), 1
    )                                             AS cod_usage_pct
 
FROM dim_customers c
INNER JOIN fact_orders  o ON c.customer_id = o.customer_id
                          AND o.order_status IN ('Delivered','Returned')
LEFT  JOIN fact_returns r ON o.order_id = r.order_id
GROUP BY c.customer_segment
ORDER BY avg_ltv_per_customer DESC;

select * from v_segment_analysis;
-- ════════════════════════════════════════════════════════════
--  Q8: City-wise sales performance
--      Which cities generate the most revenue?
-- ════════════════════════════════════════════════════════════
 
CREATE OR REPLACE VIEW v_city_performance AS
SELECT
    c.state,
    c.city,
    COUNT(DISTINCT o.order_id)                    AS total_orders,
    ROUND(SUM(o.total_amount), 0)                 AS total_revenue,
    ROUND(AVG(o.total_amount), 0)                 AS avg_order_value,
    COUNT(DISTINCT c.customer_id)                 AS total_customers,
    ROUND(SUM(o.total_amount)
        / COUNT(DISTINCT c.customer_id), 0)       AS revenue_per_customer,
 
    -- Rank cities by revenue within state
    DENSE_RANK() OVER (
        PARTITION BY c.state
        ORDER BY SUM(o.total_amount) DESC
    )                                             AS state_rank,
 
    -- Rank cities nationally
    DENSE_RANK() OVER (
        ORDER BY SUM(o.total_amount) DESC
    )                                             AS national_rank
 
FROM dim_customers c
INNER JOIN fact_orders o ON c.customer_id = o.customer_id
                         AND o.order_status = 'Delivered'
GROUP BY c.state, c.city
ORDER BY national_rank;

Select * from v_city_performance;

-- List all views created
SHOW FULL TABLES WHERE TABLE_TYPE = 'VIEW';