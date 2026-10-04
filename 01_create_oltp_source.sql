/* =====================================================================
   01 - SOURCE 1: Olist_OLTP (relational database)
   Loads 6 of the Olist CSV files into a normalised OLTP database.
   The other 3 files (payments, reviews, geolocation) stay as flat-file
   sources and are read directly by SSIS (Source 2, 3, 4).
   Needs SQL Server 2017+ (BULK INSERT ... FORMAT='CSV').
   >>> Change @path below to the folder where you saved the CSV files.
   ===================================================================== */
IF DB_ID('Olist_OLTP') IS NULL CREATE DATABASE Olist_OLTP;
GO
USE Olist_OLTP;
GO
DROP TABLE IF EXISTS order_items, orders, products, product_category_translation, sellers, customers;
GO
CREATE TABLE customers (
    customer_id              CHAR(32)     NOT NULL PRIMARY KEY,
    customer_unique_id       CHAR(32)     NOT NULL,
    customer_zip_code_prefix CHAR(5)      NOT NULL,
    customer_city            VARCHAR(100) NOT NULL,
    customer_state           CHAR(2)      NOT NULL);
CREATE TABLE sellers (
    seller_id              CHAR(32)     NOT NULL PRIMARY KEY,
    seller_zip_code_prefix CHAR(5)      NOT NULL,
    seller_city            VARCHAR(100) NOT NULL,
    seller_state           CHAR(2)      NOT NULL);
CREATE TABLE product_category_translation (
    product_category_name         VARCHAR(100) NOT NULL PRIMARY KEY,
    product_category_name_english VARCHAR(100) NOT NULL);
CREATE TABLE products (
    product_id                 CHAR(32) NOT NULL PRIMARY KEY,
    product_category_name      VARCHAR(100) NULL,
    product_name_lenght        INT NULL,   -- spelling kept as in the source file
    product_description_lenght INT NULL,
    product_photos_qty         INT NULL,
    product_weight_g           INT NULL,
    product_length_cm          INT NULL,
    product_height_cm          INT NULL,
    product_width_cm           INT NULL);
CREATE TABLE orders (
    order_id                       CHAR(32)    NOT NULL PRIMARY KEY,
    customer_id                    CHAR(32)    NOT NULL REFERENCES customers(customer_id),
    order_status                   VARCHAR(20) NOT NULL,
    order_purchase_timestamp       DATETIME2(0) NULL,
    order_approved_at              DATETIME2(0) NULL,
    order_delivered_carrier_date   DATETIME2(0) NULL,
    order_delivered_customer_date  DATETIME2(0) NULL,
    order_estimated_delivery_date  DATETIME2(0) NULL);
CREATE TABLE order_items (
    order_id            CHAR(32) NOT NULL REFERENCES orders(order_id),
    order_item_id       INT      NOT NULL,
    product_id          CHAR(32) NOT NULL REFERENCES products(product_id),
    seller_id           CHAR(32) NOT NULL REFERENCES sellers(seller_id),
    shipping_limit_date DATETIME2(0) NULL,
    price               DECIMAL(10,2) NOT NULL,
    freight_value       DECIMAL(10,2) NOT NULL,
    CONSTRAINT PK_order_items PRIMARY KEY (order_id, order_item_id));
GO
/* ---- load (order matters because of the foreign keys) ---- */
DECLARE @path NVARCHAR(300) = N'C:\Users\ASUS\Downloads\DWBI Assingement\Files\';   -- <<< CHANGE THIS
DECLARE @t TABLE (tbl SYSNAME, f NVARCHAR(100));
INSERT @t VALUES ('customers','olist_customers_dataset.csv'),('sellers','olist_sellers_dataset.csv'),
 ('product_category_translation','product_category_name_translation.csv'),('products','olist_products_dataset.csv'),
 ('orders','olist_orders_dataset.csv'),('order_items','olist_order_items_dataset.csv');
DECLARE @tbl SYSNAME, @f NVARCHAR(100), @sql NVARCHAR(MAX);
DECLARE c CURSOR FOR SELECT tbl, f FROM @t;   -- insertion order = load order
OPEN c; FETCH NEXT FROM c INTO @tbl, @f;
WHILE @@FETCH_STATUS = 0
BEGIN
  SET @sql = N'BULK INSERT dbo.' + @tbl + N' FROM ''' + @path + @f + N'''
    WITH (FORMAT=''CSV'', FIELDQUOTE=''"'', FIRSTROW=2, ROWTERMINATOR=''0x0a'',
          CODEPAGE=''65001'', KEEPNULLS, TABLOCK);';
  EXEC sp_executesql @sql;
  FETCH NEXT FROM c INTO @tbl, @f;
END
CLOSE c; DEALLOCATE c;
GO
-- If you get a row-terminator error, change '0x0a' to '0x0d0a' (depends on how the file was saved).
SELECT 'customers' t, COUNT(*) n FROM customers UNION ALL SELECT 'sellers',COUNT(*) FROM sellers
UNION ALL SELECT 'products',COUNT(*) FROM products UNION ALL SELECT 'orders',COUNT(*) FROM orders
UNION ALL SELECT 'order_items',COUNT(*) FROM order_items UNION ALL SELECT 'category_translation',COUNT(*) FROM product_category_translation;
-- Expected: 99441 / 3095 / 32951 / 99441 / 112650 / 71
