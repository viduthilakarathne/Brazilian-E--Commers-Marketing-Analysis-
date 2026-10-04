/* =====================================================================
   05 - VALIDATION  (take screenshots of these results for Task 5 "Validation results")
   Reference numbers were computed independently from the raw CSV files with pandas.
   ===================================================================== */
USE Olist_DW;
-- 1. Row counts
SELECT 'FactOrderItem'  tbl, COUNT(*) n, 112650 expected FROM FactOrderItem UNION ALL
SELECT 'DimProduct',   COUNT(*), 32951 FROM DimProduct UNION ALL
SELECT 'DimSeller',    COUNT(*), 3095  FROM DimSeller  UNION ALL
SELECT 'DimCustomer (versions)', COUNT(*), 96352 FROM DimCustomer UNION ALL
SELECT 'DimPayment (excl. unknown)', COUNT(*)-1, 5 FROM DimPayment UNION ALL
SELECT 'DimOrderStatus (excl. unknown)', COUNT(*)-1, 8 FROM DimOrderStatus;
-- 2. Totals must match the source (price 13,591,643.70 | freight 2,251,909.54 | 98,666 orders)
SELECT SUM(price) total_price, SUM(freight_value) total_freight, SUM(CAST(is_first_item AS INT)) orders, COUNT(DISTINCT order_id) distinct_orders FROM FactOrderItem;
-- 3. Reference KPI values: avg delivery days 12.41 (110,196 delivered items) | avg review per order ~4.09
SELECT AVG(CAST(delivery_days AS FLOAT)) avg_delivery_days, COUNT(delivery_days) delivered_items FROM FactOrderItem;
-- 4. No orphan keys / unknowns (should all be 0, except Payment unknown = 1 order)
SELECT SUM(CASE WHEN Payment_Key=-1 THEN 1 ELSE 0 END) unknown_payment_rows,
       SUM(CASE WHEN Purchase_Date_Key=-1 THEN 1 ELSE 0 END) no_purchase_date,
       SUM(CASE WHEN review_score IS NULL THEN 1 ELSE 0 END) no_review_rows FROM FactOrderItem;
-- 5. Grain check: duplicates on (order_id, order_item_id) -> must return no rows
SELECT order_id, order_item_id, COUNT(*) c FROM FactOrderItem GROUP BY order_id, order_item_id HAVING COUNT(*)>1;
-- 6. SCD2 check: every customer has exactly ONE current version -> must return no rows
SELECT customer_unique_id FROM DimCustomer GROUP BY customer_unique_id HAVING SUM(CAST(is_current AS INT)) <> 1;
-- 7. Revenue by year (reference: 2016 = 49,785.92 | 2017 = 6,155,806.98 | 2018 = 7,386,050.80)
SELECT d.[Year], SUM(f.price) revenue FROM FactOrderItem f JOIN DimDate d ON d.Date_Key = f.Purchase_Date_Key GROUP BY d.[Year] ORDER BY d.[Year];
