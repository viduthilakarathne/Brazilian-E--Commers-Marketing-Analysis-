/* =====================================================================
   02 - STAGING DATABASE  (Olist_Staging)
   Raw copy of every source, loaded by SSIS (truncate + load each run).
   ===================================================================== */
IF DB_ID('Olist_Staging') IS NULL CREATE DATABASE Olist_Staging;
GO
USE Olist_Staging;
GO
DROP TABLE IF EXISTS Customers_Staging, Sellers_Staging, Products_Staging, CategoryTranslation_Staging,
    Orders_Staging, OrderItems_Staging, Payments_Staging, Reviews_Staging, Geolocation_Staging;
GO
CREATE TABLE Customers_Staging (customer_id CHAR(32), customer_unique_id CHAR(32), customer_zip_code_prefix CHAR(5), customer_city VARCHAR(100), customer_state CHAR(2));
CREATE TABLE Sellers_Staging   (seller_id CHAR(32), seller_zip_code_prefix CHAR(5), seller_city VARCHAR(100), seller_state CHAR(2));
CREATE TABLE CategoryTranslation_Staging (product_category_name VARCHAR(100), product_category_name_english VARCHAR(100));
CREATE TABLE Products_Staging  (product_id CHAR(32), product_category_name VARCHAR(100), product_name_lenght INT, product_description_lenght INT,
    product_photos_qty INT, product_weight_g INT, product_length_cm INT, product_height_cm INT, product_width_cm INT);
CREATE TABLE Orders_Staging    (order_id CHAR(32), customer_id CHAR(32), order_status VARCHAR(20), order_purchase_timestamp DATETIME2(0),
    order_approved_at DATETIME2(0), order_delivered_carrier_date DATETIME2(0), order_delivered_customer_date DATETIME2(0), order_estimated_delivery_date DATETIME2(0));
CREATE TABLE OrderItems_Staging(order_id CHAR(32), order_item_id INT, product_id CHAR(32), seller_id CHAR(32), shipping_limit_date DATETIME2(0), price DECIMAL(10,2), freight_value DECIMAL(10,2));
-- flat-file sources
CREATE TABLE Payments_Staging  (order_id CHAR(32), payment_sequential INT, payment_type VARCHAR(30), payment_installments INT, payment_value DECIMAL(10,2));
CREATE TABLE Reviews_Staging   (review_id CHAR(32), order_id CHAR(32), review_score INT, review_comment_title NVARCHAR(200), review_comment_message NVARCHAR(MAX),
    review_creation_date DATETIME2(0), review_answer_timestamp DATETIME2(0));
CREATE TABLE Geolocation_Staging (geolocation_zip_code_prefix CHAR(5), geolocation_lat FLOAT, geolocation_lng FLOAT, geolocation_city VARCHAR(100), geolocation_state CHAR(2));
GO
