/* =====================================================================
   06 - DATA MARTS (department specific, built as views in schema "mart")
   ===================================================================== */
USE Olist_DW;
GO
IF SCHEMA_ID('mart') IS NULL EXEC('CREATE SCHEMA mart');
GO
/* SALES & MARKETING MART  - users: sales managers, category/marketing managers */
CREATE OR ALTER VIEW mart.vw_SalesMart AS
SELECT d.FullDate AS purchase_date, d.[Year], d.Quarter_Name, d.Month_Name, d.Year_Month,
       c.customer_unique_id, c.region AS customer_region, c.state AS customer_state, c.city AS customer_city,
       p.category_name_en AS product_category, s.seller_id, s.state AS seller_state,
       pay.payment_type, st.order_status, f.order_id,
       f.price, f.freight_value, f.item_total, f.payment_installments, f.review_score, f.item_count, f.is_first_item
FROM dbo.FactOrderItem f
JOIN dbo.DimDate d ON d.Date_Key=f.Purchase_Date_Key
JOIN dbo.DimCustomer c ON c.Customer_Key=f.Customer_Key
JOIN dbo.DimProduct p ON p.Product_Key=f.Product_Key
JOIN dbo.DimSeller s ON s.Seller_Key=f.Seller_Key
JOIN dbo.DimPayment pay ON pay.Payment_Key=f.Payment_Key
JOIN dbo.DimOrderStatus st ON st.Status_Key=f.Status_Key;
GO
/* LOGISTICS & DELIVERY MART - users: operations / logistics managers (delivered orders only) */
CREATE OR ALTER VIEW mart.vw_DeliveryMart AS
SELECT d.[Year], d.Year_Month, c.region AS customer_region, c.state AS customer_state,
       s.state AS seller_state, p.weight_class, p.category_name_en AS product_category,
       f.order_id, f.freight_value, f.delivery_days, f.delivery_delay_days,
       CASE WHEN f.delivery_delay_days > 0 THEN 1 ELSE 0 END AS is_late, f.review_score
FROM dbo.FactOrderItem f
JOIN dbo.DimDate d ON d.Date_Key=f.Purchase_Date_Key
JOIN dbo.DimCustomer c ON c.Customer_Key=f.Customer_Key
JOIN dbo.DimSeller s ON s.Seller_Key=f.Seller_Key
JOIN dbo.DimProduct p ON p.Product_Key=f.Product_Key
WHERE f.Delivered_Date_Key <> -1;
GO
-- quick tests (screenshot these)
SELECT TOP 10 product_category, SUM(price) revenue FROM mart.vw_SalesMart GROUP BY product_category ORDER BY revenue DESC;
SELECT customer_region, AVG(1.0*delivery_days) avg_days, AVG(1.0*is_late) late_rate FROM mart.vw_DeliveryMart GROUP BY customer_region;
