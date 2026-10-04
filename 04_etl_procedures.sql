/* =====================================================================
   04 - TRANSFORM & LOAD (T-SQL called from SSIS Execute SQL Tasks)
   Run order: DimPayment, DimOrderStatus, DimProduct, DimSeller, DimCustomer, Fact
   (all dimensions BEFORE the fact table)
   ===================================================================== */
USE Olist_DW;
GO
CREATE OR ALTER FUNCTION dbo.fn_Region(@s CHAR(2)) RETURNS VARCHAR(20) AS
BEGIN RETURN CASE
  WHEN @s IN ('AC','AP','AM','PA','RO','RR','TO') THEN 'North'
  WHEN @s IN ('AL','BA','CE','MA','PB','PE','PI','RN','SE') THEN 'Northeast'
  WHEN @s IN ('DF','GO','MT','MS') THEN 'Central-West'
  WHEN @s IN ('ES','MG','RJ','SP') THEN 'Southeast'
  WHEN @s IN ('PR','RS','SC') THEN 'South' ELSE 'Unknown' END; END;
GO
/* ---- small dimensions (insert-if-new) ---- */
CREATE OR ALTER PROCEDURE dbo.usp_Load_DimPayment AS
BEGIN SET NOCOUNT ON;
  INSERT DimPayment (payment_type)
  SELECT DISTINCT LOWER(LTRIM(RTRIM(payment_type))) FROM Olist_Staging.dbo.Payments_Staging p
  WHERE payment_type IS NOT NULL AND NOT EXISTS (SELECT 1 FROM DimPayment d WHERE d.payment_type = LOWER(LTRIM(RTRIM(p.payment_type)))); END;
GO
CREATE OR ALTER PROCEDURE dbo.usp_Load_DimOrderStatus AS
BEGIN SET NOCOUNT ON;
  INSERT DimOrderStatus (order_status)
  SELECT DISTINCT LOWER(LTRIM(RTRIM(order_status))) FROM Olist_Staging.dbo.Orders_Staging o
  WHERE NOT EXISTS (SELECT 1 FROM DimOrderStatus d WHERE d.order_status = LOWER(LTRIM(RTRIM(o.order_status)))); END;
GO
/* ---- DimProduct : upsert (Type 1), fixes spelling, translates category, derives volume/weight class ---- */
CREATE OR ALTER PROCEDURE dbo.usp_Load_DimProduct AS
BEGIN SET NOCOUNT ON;
  ;WITH src AS (
    SELECT p.product_id,
           COALESCE(NULLIF(p.product_category_name,''),'unknown') AS category_name_pt,
           COALESCE(t.product_category_name_english, NULLIF(p.product_category_name,''), 'unknown') AS category_name_en,
           p.product_name_lenght AS name_length, p.product_description_lenght AS description_length,
           p.product_photos_qty AS photos_qty, p.product_weight_g AS weight_g,
           p.product_length_cm AS length_cm, p.product_height_cm AS height_cm, p.product_width_cm AS width_cm,
           CASE WHEN p.product_length_cm IS NULL OR p.product_height_cm IS NULL OR p.product_width_cm IS NULL THEN NULL
                ELSE CAST(p.product_length_cm AS BIGINT)*p.product_height_cm*p.product_width_cm END AS volume_cm3,
           CASE WHEN p.product_weight_g IS NULL THEN 'Unknown' WHEN p.product_weight_g < 500 THEN 'Light'
                WHEN p.product_weight_g < 5000 THEN 'Medium' ELSE 'Heavy' END AS weight_class
    FROM Olist_Staging.dbo.Products_Staging p
    LEFT JOIN Olist_Staging.dbo.CategoryTranslation_Staging t ON t.product_category_name = p.product_category_name)
  MERGE DimProduct AS tgt USING src ON tgt.product_id = src.product_id
  WHEN MATCHED THEN UPDATE SET category_name_pt=src.category_name_pt, category_name_en=src.category_name_en, name_length=src.name_length,
       description_length=src.description_length, photos_qty=src.photos_qty, weight_g=src.weight_g, length_cm=src.length_cm,
       height_cm=src.height_cm, width_cm=src.width_cm, volume_cm3=src.volume_cm3, weight_class=src.weight_class
  WHEN NOT MATCHED THEN INSERT (product_id,category_name_pt,category_name_en,name_length,description_length,photos_qty,weight_g,length_cm,height_cm,width_cm,volume_cm3,weight_class)
       VALUES (src.product_id,src.category_name_pt,src.category_name_en,src.name_length,src.description_length,src.photos_qty,src.weight_g,src.length_cm,src.height_cm,src.width_cm,src.volume_cm3,src.weight_class); END;
GO
/* ---- DimSeller : upsert (Type 1) + lat/lng from de-duplicated geolocation ---- */
CREATE OR ALTER PROCEDURE dbo.usp_Load_DimSeller AS
BEGIN SET NOCOUNT ON;
  ;WITH geo AS (SELECT geolocation_zip_code_prefix zip, AVG(geolocation_lat) lat, AVG(geolocation_lng) lng
                FROM Olist_Staging.dbo.Geolocation_Staging GROUP BY geolocation_zip_code_prefix),
  src AS (SELECT s.seller_id, s.seller_zip_code_prefix zip, LOWER(LTRIM(RTRIM(s.seller_city))) city, UPPER(s.seller_state) state,
                 dbo.fn_Region(UPPER(s.seller_state)) region, g.lat, g.lng
          FROM Olist_Staging.dbo.Sellers_Staging s LEFT JOIN geo g ON g.zip = s.seller_zip_code_prefix)
  MERGE DimSeller tgt USING src ON tgt.seller_id = src.seller_id
  WHEN MATCHED THEN UPDATE SET zip_code_prefix=src.zip, city=src.city, state=src.state, region=src.region, latitude=src.lat, longitude=src.lng
  WHEN NOT MATCHED THEN INSERT (seller_id,zip_code_prefix,city,state,region,latitude,longitude) VALUES (src.seller_id,src.zip,src.city,src.state,src.region,src.lat,src.lng); END;
GO
/* ---- DimCustomer : SCD Type 2. One version per (customer_unique_id, zip, city, state);
        start_date = first purchase from that location, end_date = day before the next location ---- */
CREATE OR ALTER PROCEDURE dbo.usp_Load_DimCustomer AS
BEGIN SET NOCOUNT ON;
  ;WITH geo AS (SELECT geolocation_zip_code_prefix zip, AVG(geolocation_lat) lat, AVG(geolocation_lng) lng
                FROM Olist_Staging.dbo.Geolocation_Staging GROUP BY geolocation_zip_code_prefix),
  ver AS (SELECT c.customer_unique_id, c.customer_zip_code_prefix zip, LOWER(LTRIM(RTRIM(c.customer_city))) city, UPPER(c.customer_state) state,
                 CAST(MIN(o.order_purchase_timestamp) AS DATE) first_seen
          FROM Olist_Staging.dbo.Customers_Staging c JOIN Olist_Staging.dbo.Orders_Staging o ON o.customer_id = c.customer_id
          GROUP BY c.customer_unique_id, c.customer_zip_code_prefix, LOWER(LTRIM(RTRIM(c.customer_city))), UPPER(c.customer_state)),
  src AS (SELECT v.*, DATEADD(DAY,-1, LEAD(v.first_seen) OVER (PARTITION BY v.customer_unique_id ORDER BY v.first_seen, v.zip)) end_date,
                 dbo.fn_Region(v.state) region, g.lat, g.lng
          FROM ver v LEFT JOIN geo g ON g.zip = v.zip)
  MERGE DimCustomer tgt USING src
     ON tgt.customer_unique_id = src.customer_unique_id AND tgt.zip_code_prefix = src.zip AND tgt.city = src.city AND tgt.state = src.state
  WHEN MATCHED THEN UPDATE SET end_date = src.end_date, is_current = CASE WHEN src.end_date IS NULL THEN 1 ELSE 0 END
  WHEN NOT MATCHED THEN INSERT (customer_unique_id,zip_code_prefix,city,state,region,latitude,longitude,start_date,end_date,is_current)
       VALUES (src.customer_unique_id,src.zip,src.city,src.state,src.region,src.lat,src.lng,src.first_seen,src.end_date, CASE WHEN src.end_date IS NULL THEN 1 ELSE 0 END); END;
GO
/* ---- FACT (full reload each run) ----
   Transformations: one payment row per order (largest value), one review per order (latest answer),
   date keys, delivery_days, delivery_delay_days, is_first_item */
CREATE OR ALTER PROCEDURE dbo.usp_Load_FactOrderItem AS
BEGIN SET NOCOUNT ON;
  TRUNCATE TABLE FactOrderItem;
  ;WITH pay AS (SELECT order_id, LOWER(LTRIM(RTRIM(payment_type))) payment_type, payment_installments,
                       ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY payment_value DESC, payment_sequential) rn
                FROM Olist_Staging.dbo.Payments_Staging),
  rev AS (SELECT order_id, review_score,
                 ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY review_answer_timestamp DESC, review_creation_date DESC) rn
          FROM Olist_Staging.dbo.Reviews_Staging)
  INSERT FactOrderItem (Customer_Key,Product_Key,Seller_Key,Payment_Key,Status_Key,Purchase_Date_Key,Delivered_Date_Key,Estimated_Date_Key,
        order_id,order_item_id,price,freight_value,payment_installments,review_score,delivery_days,delivery_delay_days,is_first_item)
  SELECT dc.Customer_Key, dp.Product_Key, ds.Seller_Key, COALESCE(dpy.Payment_Key,-1), COALESCE(dst.Status_Key,-1),
         COALESCE(CONVERT(INT,FORMAT(o.order_purchase_timestamp,'yyyyMMdd')),-1),
         COALESCE(CONVERT(INT,FORMAT(o.order_delivered_customer_date,'yyyyMMdd')),-1),
         COALESCE(CONVERT(INT,FORMAT(o.order_estimated_delivery_date,'yyyyMMdd')),-1),
         i.order_id, i.order_item_id, i.price, i.freight_value, pay.payment_installments, rev.review_score,
         CASE WHEN o.order_delivered_customer_date IS NOT NULL THEN DATEDIFF(DAY,o.order_purchase_timestamp,o.order_delivered_customer_date) END,
         CASE WHEN o.order_delivered_customer_date IS NOT NULL THEN DATEDIFF(DAY,o.order_estimated_delivery_date,o.order_delivered_customer_date) END,
         CASE WHEN i.order_item_id = 1 THEN 1 ELSE 0 END
  FROM Olist_Staging.dbo.OrderItems_Staging i
  JOIN Olist_Staging.dbo.Orders_Staging o    ON o.order_id = i.order_id
  JOIN Olist_Staging.dbo.Customers_Staging c ON c.customer_id = o.customer_id
  JOIN DimCustomer dc ON dc.customer_unique_id=c.customer_unique_id AND dc.zip_code_prefix=c.customer_zip_code_prefix
                     AND dc.city=LOWER(LTRIM(RTRIM(c.customer_city))) AND dc.state=UPPER(c.customer_state)
  JOIN DimProduct dp ON dp.product_id = i.product_id
  JOIN DimSeller  ds ON ds.seller_id  = i.seller_id
  LEFT JOIN pay ON pay.order_id = i.order_id AND pay.rn = 1
  LEFT JOIN DimPayment dpy ON dpy.payment_type = pay.payment_type
  LEFT JOIN rev ON rev.order_id = i.order_id AND rev.rn = 1
  LEFT JOIN DimOrderStatus dst ON dst.order_status = LOWER(LTRIM(RTRIM(o.order_status))); END;
GO
CREATE OR ALTER PROCEDURE dbo.usp_Run_Full_Load AS
BEGIN EXEC usp_Load_DimPayment; EXEC usp_Load_DimOrderStatus; EXEC usp_Load_DimProduct; EXEC usp_Load_DimSeller;
      EXEC usp_Load_DimCustomer; EXEC usp_Load_FactOrderItem; END;
GO
