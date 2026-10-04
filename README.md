# Olist DWBI Project 

Power BI (Task 7) and the dashboard insights (Task 8) are left out, as requested.
This guide gives you the design, the scripts and the evidence checklist. **The report text, the SSIS packages and the screenshots must be your own work** – the brief does not allow a fully AI-generated submission. Use the notes below as a starting point and rewrite them in your own words.

## Run order
| # | File | What it does | Evidence to capture |
|---|------|--------------|---------------------|
| 1 | 01_create_oltp_source.sql | Creates **Olist_OLTP** and loads 6 CSVs | Object Explorer + row counts |
| 2 | 02_create_staging.sql | Creates **Olist_Staging** | Table list |
| 3 | 03_create_dw.sql | Creates **Olist_DW** (dimensions + fact + DimDate) | Database diagram of the star schema |
| 4 | SSIS: `Olist_Load_Staging.dtsx` (you build) | Extract 9 sources → staging (truncate + load) | Control flow with green ticks |
| 5 | 04_etl_procedures.sql | Transform & load procs | Proc code |
| 6 | SSIS: `Olist_Load_DW.dtsx` (you build) | Execute SQL Tasks: dims first, then fact | Control flow with green ticks |
| 7 | 05_validation.sql | Checks vs numbers computed independently from the raw CSVs | Result grids |
| 8 | 06_data_marts.sql | Sales and Delivery marts (views) | Views + sample queries |
| 9 | 07_accumulating_fact_optional.sql | Optional order-lifecycle fact | Optional |

## Task 1 – Dataset & scenario (notes)
- **Domain:** e-commerce / retail marketplace (Brazilian Olist, Kaggle "Brazilian E-Commerce Public Dataset by Olist"). Orders from Sept 2016 to Oct 2018.
- **Why OLTP-like:** normalised tables with primary/foreign keys that record each order, item, payment and review as it happens.
- **Business problem:** management can't easily see revenue trends by category/region, how late deliveries hurt reviews, or how payment methods differ across regions.
- **Size:** 99,441 orders · 112,650 order items · 99,441 customer records (96,096 unique customers) · 32,951 products · 3,095 sellers · 103,886 payment rows · 99,224 reviews · 1,000,163 geolocation rows.
- Write the attribute description for each file from the CSV headers.

## Task 2 – Sources & preparation (notes)
| Source | Type | Contents |
|---|---|---|
| Olist_OLTP | SQL Server (relational) | customers, orders, order_items, products, sellers, category translation |
| olist_order_payments_dataset.csv | CSV | payment type, installments, value (can be several rows per order) |
| olist_order_reviews_dataset.csv | CSV | score, comments (some orders have 2+ reviews) |
| olist_geolocation_dataset.csv | CSV | lat/lng per zip prefix (1M rows, **261,831 exact duplicates**) |

Relationships: orders→customers (customer_id), order_items→orders/products/sellers, payments & reviews→orders (order_id), geolocation→customers/sellers (zip prefix).
**Data issues found while profiling** (these become your transformation list):
- Misspelt columns `product_name_lenght` / `product_description_lenght`.
- 610 products with no category; 2 categories (`pc_gamer`, `portateis_cozinha_e_preparadores_de_alimentos`) missing from the English translation file.
- 160 orders with no approval date, 1,783 with no carrier date, 2,965 with no delivery date (not yet delivered / cancelled).
- 551 orders have more than one review; `review_id` repeats 814 times.
- Geolocation has many rows per zip prefix (19,015 distinct prefixes).
- 775 orders have no items (cancelled/unavailable) – they don't reach the fact table.
- `customer_id` is per order; the real customer is `customer_unique_id` (96,096 people for 99,441 customer records).

## Task 3 – Architecture (draw this in draw.io)
Source layer (Olist_OLTP + 3 CSV files) → **SSIS** Extract → **Olist_Staging** → Transform/Load (T-SQL procs run by SSIS) → **Olist_DW** (enterprise DW, star schema) → Data marts (Sales mart, Delivery mart) → Presentation layer (OLAP/cube and BI – Power BI would go here; you can show it greyed out or "future work" since this part is excluded).
Explain each box in 2–3 sentences.

## Task 4 – Dimensional model (notes)
- **Business process:** order fulfilment/sales. **Grain:** one row per order item.
- **Measures:** price, freight_value, item_total (derived), delivery_days, delivery_delay_days, review_score (non-additive), payment_installments, item_count.
- **Dimensions:** DimDate (role-playing ×3: purchase / delivered / estimated), DimCustomer (SCD2), DimProduct, DimSeller, DimPayment, DimOrderStatus. Degenerate dimensions: order_id, order_item_id.
- **Hierarchies:** Date: Year > Quarter > Month > Day · Customer/Seller: Region > State > City · Product: Category > Product.
- **Design assumptions to state:**
  1. Payments and reviews are order-level, so the fact keeps one payment type (largest payment) and the latest review per order. Payment value is **not** stored on item rows to avoid double counting.
  2. `is_first_item` is 1 on one row per order, so `SUM(is_first_item)` = order count and average review per order is not weighted by item count.
  3. DimCustomer is SCD Type 2 on location. Only ~120 customers changed city, but it shows the technique properly. Product/Seller are Type 1.
  4. Unknown members (key −1) are used for missing dates, payment type and status.
  5. Orders without items are excluded because the grain is the item.

## Task 5 – ETL (notes)
- **Extract:** OLE DB Source → OLE DB Destination for OLTP tables, Flat File Source for the 3 CSVs. Each data flow has an `OnPreExecute` Execute SQL Task: `TRUNCATE TABLE ...`.
- **Transform (done in procs, explain each):** trim/lowercase city names, spelling fix, English category with 'unknown' fallback, volume and weight class derived, region derived from state, geolocation averaged per zip prefix, latest review per order, largest payment per order, date keys, delivery_days and delay days, SCD2 versioning.
- **Load order:** DimPayment → DimOrderStatus → DimProduct → DimSeller → DimCustomer → FactOrderItem (the fact needs the dimension keys).
- **Validation:** screenshots of 05_validation.sql. Expected: fact 112,650 rows; price 13,591,643.70; freight 2,251,909.54; 98,666 orders; DimCustomer 96,352 versions.
- **Run `EXEC dbo.usp_Run_Full_Load`** once to test everything before building the SSIS wrappers.

Tip: I could not run these scripts against a real SQL Server here. The expected numbers come from the raw CSVs, but expect to fix small errors (file paths, a collation or version issue) when you run them. If something fails, paste the error and I'll help debug.

## Task 6 – Data marts (notes)
- **Sales & Marketing Mart:** purpose – revenue/category/customer analysis. Users – sales and category managers. Benefits – simple flat view, no joins needed.
- **Delivery & Logistics Mart:** purpose – delivery speed and lateness. Users – operations/logistics managers. Benefits – delivered-orders only, ready-made `is_late` flag, links delivery to review score.

