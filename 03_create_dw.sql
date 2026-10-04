/* =====================================================================
   03 - DATA WAREHOUSE  (Olist_DW)  -  STAR SCHEMA
   Business process : Order fulfilment / sales of marketplace items
   GRAIN            : ONE ROW PER ORDER ITEM (order_id + order_item_id)
   ===================================================================== */
IF DB_ID('Olist_DW') IS NULL CREATE DATABASE Olist_DW;
GO
USE Olist_DW;
GO
DROP TABLE IF EXISTS FactOrderItem, FactOrderFulfillment, DimCustomer, DimProduct, DimSeller, DimPayment, DimOrderStatus, DimDate;
GO
/* ---------- DimDate (role-playing: purchase / delivered / estimated) ---------- */
CREATE TABLE DimDate (
    Date_Key INT PRIMARY KEY,            -- yyyymmdd, -1 = unknown / not yet happened
    FullDate DATE NULL, [Year] INT, Quarter_No INT, Quarter_Name VARCHAR(10),
    Month_No INT, Month_Name VARCHAR(10), Year_Month CHAR(7),
    Day_Of_Month INT, Day_Name VARCHAR(10), Week_Of_Year INT, Is_Weekend BIT);
-- hierarchy: Year > Quarter > Month > Day
SET DATEFIRST 7;
;WITH d AS (SELECT CAST('2016-01-01' AS DATE) dt UNION ALL SELECT DATEADD(DAY,1,dt) FROM d WHERE dt < '2019-12-31')
INSERT DimDate
SELECT CONVERT(INT, FORMAT(dt,'yyyyMMdd')), dt, YEAR(dt), DATEPART(QUARTER,dt), 'Q'+CAST(DATEPART(QUARTER,dt) AS VARCHAR),
       MONTH(dt), DATENAME(MONTH,dt), FORMAT(dt,'yyyy-MM'), DAY(dt), DATENAME(WEEKDAY,dt), DATEPART(ISO_WEEK,dt),
       CASE WHEN DATENAME(WEEKDAY,dt) IN ('Saturday','Sunday') THEN 1 ELSE 0 END
FROM d OPTION (MAXRECURSION 0);
INSERT DimDate (Date_Key, Month_Name, Day_Name) VALUES (-1,'Unknown','Unknown');
GO
/* ---------- DimCustomer : SCD Type 2 on location (city/state/zip) ---------- */
CREATE TABLE DimCustomer (
    Customer_Key INT IDENTITY(1,1) PRIMARY KEY,
    customer_unique_id CHAR(32) NOT NULL,         -- business key (the real person)
    zip_code_prefix CHAR(5), city VARCHAR(100), state CHAR(2),
    region VARCHAR(20),                           -- hierarchy: Region > State > City
    latitude FLOAT NULL, longitude FLOAT NULL,    -- from geolocation file
    start_date DATE NOT NULL, end_date DATE NULL, is_current BIT NOT NULL);
CREATE INDEX IX_DimCustomer_bk ON DimCustomer(customer_unique_id, zip_code_prefix, city, state);
/* ---------- DimProduct (Type 1) ---------- */
CREATE TABLE DimProduct (
    Product_Key INT IDENTITY(1,1) PRIMARY KEY,
    product_id CHAR(32) NOT NULL UNIQUE,
    category_name_pt VARCHAR(100), category_name_en VARCHAR(100),   -- hierarchy: Category > Product
    name_length INT, description_length INT, photos_qty INT,
    weight_g INT, length_cm INT, height_cm INT, width_cm INT,
    volume_cm3 BIGINT NULL, weight_class VARCHAR(10));
/* ---------- DimSeller (Type 1) ---------- */
CREATE TABLE DimSeller (
    Seller_Key INT IDENTITY(1,1) PRIMARY KEY,
    seller_id CHAR(32) NOT NULL UNIQUE,
    zip_code_prefix CHAR(5), city VARCHAR(100), state CHAR(2), region VARCHAR(20),
    latitude FLOAT NULL, longitude FLOAT NULL);
/* ---------- small lookup dimensions ---------- */
CREATE TABLE DimPayment (Payment_Key INT IDENTITY(1,1) PRIMARY KEY, payment_type VARCHAR(30) NOT NULL UNIQUE);
CREATE TABLE DimOrderStatus (Status_Key INT IDENTITY(1,1) PRIMARY KEY, order_status VARCHAR(20) NOT NULL UNIQUE);
SET IDENTITY_INSERT DimPayment ON;     INSERT DimPayment (Payment_Key, payment_type) VALUES (-1,'unknown'); SET IDENTITY_INSERT DimPayment OFF;
SET IDENTITY_INSERT DimOrderStatus ON; INSERT DimOrderStatus (Status_Key, order_status) VALUES (-1,'unknown'); SET IDENTITY_INSERT DimOrderStatus OFF;
GO
/* ---------- FACT ---------- */
CREATE TABLE FactOrderItem (
    Fact_Key BIGINT IDENTITY(1,1) PRIMARY KEY,
    Customer_Key INT NOT NULL REFERENCES DimCustomer(Customer_Key),
    Product_Key  INT NOT NULL REFERENCES DimProduct(Product_Key),
    Seller_Key   INT NOT NULL REFERENCES DimSeller(Seller_Key),
    Payment_Key  INT NOT NULL REFERENCES DimPayment(Payment_Key),
    Status_Key   INT NOT NULL REFERENCES DimOrderStatus(Status_Key),
    Purchase_Date_Key  INT NOT NULL REFERENCES DimDate(Date_Key),
    Delivered_Date_Key INT NOT NULL REFERENCES DimDate(Date_Key),
    Estimated_Date_Key INT NOT NULL REFERENCES DimDate(Date_Key),
    order_id CHAR(32) NOT NULL, order_item_id INT NOT NULL,       -- degenerate dimensions
    price DECIMAL(10,2) NOT NULL, freight_value DECIMAL(10,2) NOT NULL,
    item_total AS (price + freight_value) PERSISTED,
    payment_installments INT NULL,
    review_score TINYINT NULL,            -- order-level, NON-additive: use AVG, never SUM
    delivery_days INT NULL,               -- purchase -> customer delivery (delivered orders only)
    delivery_delay_days INT NULL,         -- delivered - estimated  (>0 = late)
    item_count INT NOT NULL DEFAULT 1,
    is_first_item BIT NOT NULL,           -- 1 on one row per order -> SUM = number of orders
    CONSTRAINT UQ_Fact_grain UNIQUE (order_id, order_item_id));
GO
