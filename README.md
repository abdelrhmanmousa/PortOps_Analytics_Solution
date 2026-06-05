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

---

## 6. Q&A: Technical Justifications

### Data Warehousing

**Q: What is the difference between SCD Type 1 and Type 2?**

Type 1 overwrites existing data (e.g., `customer_name`), providing only the current view with no historical record of what the value was before. Type 2 tracks history (e.g., `customer_tier`) by creating new rows with effective dates, preserving every version of a record over time. In this project, Type 1 was used for names to keep reports clean, and Type 2 was used for tiers to ensure a customer's performance is attributed to the correct tier they held at the time of the move.

**Q: Why use Surrogate Keys?**

For two reasons. First, they decouple the warehouse from source system changes — for example, if a `customer_id` changes in the Excel source, the warehouse is unaffected. Second, they are essential for SCD Type 2: since a single `customer_id` can have multiple rows (one per historical version), the Surrogate Key provides a unique identifier for the fact table to link to a specific historical version of that customer.

**Q: How is an out-of-range date handled with a bounded `dim_date`?**

If a fact row arrives with a date outside the loaded range (1 Apr 2025 – 31 Mar 2026), the SSIS Lookup will fail to find a match. The pipeline is designed to redirect these "No Match" rows to a Default/Unknown member (`ID = -1`). This prevents package failure and keeps the data visible in reports as "Uncategorized Date" for troubleshooting.

---

### SSIS

**Q: Why avoid the SCD Wizard?**

The Wizard performs row-by-row updates (RBAR — Row By Agonizing Row), which is extremely slow for large datasets. It also generates complex, hard-to-maintain packages. A manual pattern using Lookups and Conditional Splits is more performant, supports better error logging, and allows bulk-inserting new records rather than processing them one at a time.

**Q: How does Automated Row-Count Reconciliation work?**

Row Count transformations in the Data Flow populate package variables for Source and Target counts. At the end of the pipeline, an Execute SQL Task compares these counts. If they mismatch, the package logs a `'Failure'` status to `stg.etl_log` and halts the process, ensuring data integrity is never silently compromised.

**Q: What is the role of Staging?**

Staging acts as both a "buffer" and a "sanitizer." It decouples the ETL from the source file, allowing heavy transformations (such as SCD logic) to be performed within SQL Server rather than directly against the Excel driver — which would be slower and prone to locking and connection errors.

---

### Power BI

**Q: Why is only one active relationship allowed between the same two tables?**

Multiple active relationships between the same two tables create ambiguity. If a user filtered by Date, Power BI would not know whether to apply the filter via the "Gate In Date" or "Gate Out Date" path, leading to inconsistent and untrustworthy results. One relationship must be active; the others are kept inactive and activated explicitly inside measures.

**Q: What is the difference between `USERELATIONSHIP` and `CROSSFILTER`?**

`USERELATIONSHIP` activates a specific inactive relationship for the duration of a single measure calculation — it is the correct tool for handling multiple timestamps (e.g., gate-in vs. gate-out) on the same fact table. `CROSSFILTER` changes the *direction* of an existing relationship's cross-filtering (e.g., making a one-way filter behave like a two-way filter). They solve different problems; `USERELATIONSHIP` is the appropriate choice here.

**Q: A KPI is not respecting a Date Slicer — how would you debug this?**

Three checks in order: First, verify the measure references the correct column from `dim_date` (not a date column on the fact table directly). Second, confirm the relationship between `dim_date` and the fact table is set to **Active**. Third, inspect the measure definition for filter-overriding functions such as `ALL()` or a `USERELATIONSHIP()` call that may be intentionally or accidentally bypassing the slicer context.