# Design Documentation: Port Operations Data Mart

## 1. Fact Table Grain Definitions

**fact_container_movement:**
Grain: One row per individual container move (Lift).
Reasoning: This is the most granular level available. It allows management to calculate precise crane productivity and cycle times. Aggregating this would lose the ability to analyze equipment-level bottlenecks.

**fact_vessel_call:**
Grain: One row per vessel arrival/departure event.
Reasoning: Management needs to evaluate the performance of a ship's entire stay. This grain supports KPIs like "Move Variance" (Planned vs. Actual) and "Stay Hours" per visit.

**fact_gate_transaction:**
Grain: One row per truck gate-in/gate-out event.
Reasoning: Capturing the transaction grain allows for dwell-time analysis and enables the dual-date relationship requirement in Power BI to analyze gate activity by both entry and exit timestamps.

---

## 2. SCD Type 2 Implementation (dim_customer)

To satisfy engineering best practices, I avoided the standard SSIS SCD Wizard in favor of a manual pattern for better performance and control:

### SSIS Data Flow Architecture



```
Source
   ↓
Lookup (join on Natural Key: customer_id)
   ├─────────────────────┐
   ↓                     ↓
No Match             Match Output
   ↓                     ↓
Derived Column      Conditional Split
(set SCD cols)           ├──────────────────────┐
   ↓                     ↓                      ↓
OLE DB Destination  Default Output          Tier Changed
(INSERT new row)      (Ignore –             (Type 2 change
                    no change detected)      detected)
                                               ↓
                                           Multicast
                                      ↙              ↘
                           OLE DB Command        Derived Column
                           (UPDATE existing:     (set new row cols:
                            is_current = 0,       is_current = 1,
                            row_end_date =        row_start_date = now,
                            GETDATE())            row_end_date = 9999-12-31)
                                                       ↓
                                               OLE DB Destination
                                               (INSERT new version)
```

### Component Breakdown

- **Change Detection:** I used a Lookup Transformation to join the staging data to the existing dimension on the Natural Key (`customer_id`). A Conditional Split then compares the incoming `customer_tier` and `credit_limit` against the current values in the warehouse.

- **Expiring History:** For detected changes, an OLE DB Command executes a SQL Update to set `is_current = 0` and the `row_end_date` to the current timestamp for the existing record.

- **Maintaining Current State:** Simultaneously, a new record is inserted via an OLE DB Destination with `is_current = 1`, `row_start_date` set to the current timestamp, and `row_end_date` set to a future-dated placeholder (`9999-12-31`).

- **Type 1 Attributes:** Fields like `customer_name` and `country` are handled via an Update command to ensure they are overwritten globally without triggering new rows.

---

## 3. Date Dimension (dim_date)

- **Population Method:** The dimension was populated via a T-SQL script within an Execute SQL Task to ensure portability and logic consistency.

- **Range:** 1 April 2025 – 31 March 2026. This covers the full operational window specified in the README.

- **Fiscal Logic:** Per requirements, the fiscal year begins 1 April. I implemented a `CASE` statement to map April as Fiscal Month 1 and adjust the Fiscal Year attribute accordingly.

---

## 4. Data Quality Management

- **Nulls & Blanks:** I implemented a `-1` "Unknown" member in every dimension. Any fact row with a missing or invalid foreign key was redirected to this member during the Lookup phase to ensure referential integrity and zero data loss.

- **Mixed Data Types:** Date columns provided as strings in Excel were standardized to `DT_DBTIMESTAMP` using the Data Conversion transformation in SSIS.

- **Duplicates:** Per the README, duplicates were treated as DQ findings. I implemented a Row-Count reconciliation check between Staging and the Warehouse to ensure no silent dropping of rows occurred.

- **Business Rule Check:** I implemented a validation check to identify "Logic Errors" (e.g., Vessel ATD occurring before ATA). These rows are loaded but flagged in the ETL audit log for operational cleanup.

---

## 5. Scalability (10M+ Row Scenario)

If the data volume were to scale significantly, I would implement the following changes:

- **Incremental Loading:** Move away from "Truncate and Reload." I would use Change Data Capture (CDC) or Delta detection (based on a `LastModified` timestamp) to only process new or changed records.

- **Columnstore Indexing:** I would implement Clustered Columnstore Indexes on the fact tables. This provides massive compression and significantly speeds up the heavy aggregation queries used by Power BI.
