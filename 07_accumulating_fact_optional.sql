/* =====================================================================
   07 - OPTIONAL: ACCUMULATING SNAPSHOT FACT (one row per order, milestones filled in over time)
   Not required by the brief, but Olist has a natural order lifecycle. Skip if short on time.
   ===================================================================== */
USE Olist_DW;
GO
CREATE TABLE FactOrderFulfillment (
    order_id CHAR(32) PRIMARY KEY,
    Customer_Key INT NULL, Status_Key INT NULL,
    Purchase_Date_Key INT, Approved_Date_Key INT, Carrier_Date_Key INT, Delivered_Date_Key INT, Estimated_Date_Key INT,   -- -1 = milestone not reached yet
    days_to_approve INT NULL, days_to_carrier INT NULL, days_carrier_to_customer INT NULL, days_total INT NULL);
GO
CREATE OR ALTER PROCEDURE dbo.usp_Upsert_FactOrderFulfillment AS
BEGIN SET NOCOUNT ON;
  ;WITH src AS (
    SELECT o.order_id, dst.Status_Key,
      COALESCE(CONVERT(INT,FORMAT(o.order_purchase_timestamp,'yyyyMMdd')),-1) pk,
      COALESCE(CONVERT(INT,FORMAT(o.order_approved_at,'yyyyMMdd')),-1) ak,
      COALESCE(CONVERT(INT,FORMAT(o.order_delivered_carrier_date,'yyyyMMdd')),-1) ck,
      COALESCE(CONVERT(INT,FORMAT(o.order_delivered_customer_date,'yyyyMMdd')),-1) dk,
      COALESCE(CONVERT(INT,FORMAT(o.order_estimated_delivery_date,'yyyyMMdd')),-1) ek,
      DATEDIFF(DAY,o.order_purchase_timestamp,o.order_approved_at) a,
      DATEDIFF(DAY,o.order_purchase_timestamp,o.order_delivered_carrier_date) c,
      DATEDIFF(DAY,o.order_delivered_carrier_date,o.order_delivered_customer_date) cc,
      DATEDIFF(DAY,o.order_purchase_timestamp,o.order_delivered_customer_date) t
    FROM Olist_Staging.dbo.Orders_Staging o LEFT JOIN DimOrderStatus dst ON dst.order_status=LOWER(o.order_status))
  MERGE FactOrderFulfillment tgt USING src ON tgt.order_id=src.order_id
  WHEN MATCHED THEN UPDATE SET Status_Key=src.Status_Key, Approved_Date_Key=src.ak, Carrier_Date_Key=src.ck, Delivered_Date_Key=src.dk,
       days_to_approve=src.a, days_to_carrier=src.c, days_carrier_to_customer=src.cc, days_total=src.t
  WHEN NOT MATCHED THEN INSERT (order_id,Status_Key,Purchase_Date_Key,Approved_Date_Key,Carrier_Date_Key,Delivered_Date_Key,Estimated_Date_Key,days_to_approve,days_to_carrier,days_carrier_to_customer,days_total)
       VALUES (src.order_id,src.Status_Key,src.pk,src.ak,src.ck,src.dk,src.ek,src.a,src.c,src.cc,src.t); END;
GO
