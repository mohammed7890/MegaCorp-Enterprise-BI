\# 📘 MegaCorp Enterprise BI \& Data Analytics Suite

\*\*Document Version:\*\* 1.0 | \*\*Tech Stack:\*\* SQL Server, SSIS, SSAS Tabular, SSRS, Power BI, Git



\---



\## 1. Executive Summary \& Business Problem Statement



\### 1.1 Operational Pain Points (The "Why")

MegaCorp is a multi-channel enterprise operating across 5 geographical regions and 30 retail branches, managing over 2,000 products, 50,000 customers, and 2,500 employees. Despite steady top-line revenue growth, executive leadership identified three critical operational bottlenecks:

1\. \*\*Profit Margin Erosion:\*\* Net profit margins declined by 14% over the last two quarters, with no visibility into whether discount abuse, supplier cost spikes, or high product return rates were driving the loss.

2\. \*\*Inventory Imbalance:\*\* Simultaneous occurrences of high-demand product stockouts in retail branches and slow-moving dead stock accumulating in central warehouses.

3\. \*\*Siloed \& Delayed Reporting:\*\* Monthly financial and operational reconciliations required manual Excel consolidation across 4 departments (`Sales`, `Supply Chain`, `HR`, `Finance`), resulting in a 15-day reporting lag and conflicting KPIs.



\### 1.2 Diagnostic Questions Answered by This Solution

\* \*\*Commercial \& Margin Analysis:\*\* Which product categories, channels, and sales representatives generate high revenue but eroded net margins due to excessive discounting?

\* \*\*Supply Chain Optimization:\*\* Which SKUs fall below reorder thresholds, and how does supplier lead time impact branch stockouts?

\* \*\*Financial Variance Control:\*\* Which branches and cost centers exceed their allocated OPEX budgets (`Actual vs. Budget`)?



\---



\## 2. System Architecture \& Version Control Workflow



\### 2.1 Four-Tier Enterprise Architecture

1\. \*\*Source Tier (OLTP):\*\* `MegaCorp\_ERP\_OLTP` (SQL Server Relational Database - 3NF Normalized, 20 Tables across 4 schemas).

2\. \*\*Integration \& Data Quality Tier (ETL):\*\* SQL Server Integration Services (\*\*SSIS\*\*) with automated quarantine logging (`err.Rejected\_Sales\_Records`).

3\. \*\*Storage Tier (OLAP DWH):\*\* `MegaCorp\_DWH` designed as a \*\*Galaxy (Fact Constellation) Schema\*\* utilizing Clustered Columnstore Indexes (CCI).

4\. \*\*Semantic \& Presentation Tier:\*\* \*\*SSAS Tabular\*\* (Partitioned, Role-Secured, Perspectives) serving \*\*Power BI\*\* (Live Connection) and \*\*SSRS\*\* Paginated Reports.



\### 2.2 Git Branching Strategy

This project adheres to software engineering best practices using feature-branching:

\* `main`: Production-ready scripts, verified ETL packages, semantic models, and final documentation.

\* `feature/data-warehouse-galaxy-schema`: Dimensional modeling, Star/Galaxy schemas, and Columnstore indexing.

\* `feature/ssis-etl-pipelines`: Incremental loads, SCD Type 2 logic, and error quarantine flows.

\* `feature/ssas-semantic-layer`: Tabular model, partitions, calculation groups, and Dynamic RLS.

\* `feature/reporting-ssrs-powerbi`: Paginated operational reports and interactive executive dashboards.



\---



\## 3. Module 1: Source OLTP Database Specifications (`MegaCorp\_ERP\_OLTP`)



\### 3.1 Schema \& Table Inventory (20 Tables | \~3.73 Million Records)

\* \*\*`sales` Schema (8 Tables):\*\* `Regions` (5), `Branches` (30), `Channels` (4), `CustomerSegments` (4), `Customers` (50,000), `SalesOrdersHeader` (500,000), `SalesOrderDetails` (2,000,000), `SalesReturns` (150,000).

\* \*\*`scm` Schema (6 Tables):\*\* `Categories` (5), `SubCategories` (25), `Brands` (40), `Suppliers` (150), `Products` (2,000), `Warehouses` (10), `InventoryMovements` (1,000,000).

\* \*\*`hr` Schema (3 Tables):\*\* `Departments` (6), `JobTitles` (6), `Employees` (2,500).

\* \*\*`fin` Schema (2 Tables):\*\* `GL\_Accounts` (8), `FinancialTransactions` (500,000).



\### 3.2 Engineering \& Data Quality Notes

\* \*\*Performance Optimization:\*\* Foreign key constraints on massive transactional tables (`01b\_Add\_OLTP\_Foreign\_Keys.sql`) are applied post-bulk-load using `WITH NOCHECK` to maximize insertion throughput while maintaining full relational diagram integrity.

\* \*\*Simulated Data Anomalies:\*\* 2% of customer names contain leading/trailing spaces, and 0.5% (\~10,000 rows) of `SalesOrderDetails` contain negative quantities (`-1`) to validate automated ETL error interception in Module 3.


---

## 🏗️ Module 2: Enterprise Data Warehouse (`MegaCorp_DWH`) — Completed ✅

In this phase, transactional data from `MegaCorp_ERP_OLTP` was transformed and loaded into an analytical **Galaxy Schema (Fact Constellation)** optimized for high-speed BI querying and historical accuracy.

### 🔑 Key Architectural Decisions
* **Galaxy Schema (Fact Constellation):** Chosen over a single Star Schema to model 4 distinct business processes (`Sales`, `Returns`, `Inventory`, `Finance`) at their exact grain without generating sparse `NULL` rows, while sharing **8 Conformed Dimensions**.
* **Clustered Columnstore Indexes (CCI):** Applied across all 4 fact tables to achieve up to 10x data compression and enable Batch Mode execution for multi-million-row aggregations.
* **Slowly Changing Dimensions (SCD Type 2):** Implemented (`StartDate`, `EndDate`, `IsCurrent`) on `DimProduct`, `DimCustomer`, and `DimEmployee` to preserve historical pricing, customer segments, and organizational changes.
* **Error Quarantine Pattern:** Isolated `10,000` invalid sales records (`OrderQty <= 0`) into `err.Rejected_Sales_Records` with rejection reasons and timestamps, preventing pipeline failures while maintaining 100% financial auditability.
* **Smart Surrogate Keys & Denormalization:** Built a dedicated `DimDate` table (`2020–2030`, `YYYYMMDD` integer keys) and flattened multi-table hierarchies (e.g., 5 product tables merged into `DimProduct`) to eliminate expensive runtime joins.

### 📊 DWH Schema & Loaded Row Counts
| Schema | Table Name | Role / Type | Loaded Rows | Notes |
| :--- | :--- | :--- | :---: | :--- |
| `dim` | `DimDate` | Conformed Dimension | 4,018 | Smart Key (`YYYYMMDD`), Weekend flags |
| `dim` | `DimProduct` | SCD Type 2 Dimension | 2,000 | Merged Categories, SubCategories, Brands & Suppliers |
| `dim` | `DimCustomer` | SCD Type 2 Dimension | 50,000 | Standardized (`TRIM`/`UPPER`), merged Regions & Segments |
| `dim` | `DimBranch` | Conformed Dimension | 30 | Merged Branches & Geographic Regions |
| `dim` | `DimChannel` | Conformed Dimension | 4 | Sales Channels |
| `dim` | `DimEmployee` | SCD Type 2 Dimension | 2,500 | Merged Departments, Cost Centers & Job Titles |
| `dim` | `DimWarehouse` | Conformed Dimension | — | Warehouses & storage capacity |
| `dim` | `DimGLAccount` | Conformed Dimension | — | General Ledger Chart of Accounts |
| `fact` | `FactSales` | Fact Table (CCI) | 1,990,000 | Clean sales transactions with pre-calculated profit |
| `fact` | `FactReturns` | Fact Table (CCI) | 150,000 | Customer returns & refund amounts |
| `fact` | `FactInventory` | Fact Table (CCI) | 1,000,000 | Warehouse stock movements (`IN`/`OUT`/`ADJUSTMENT`) |
| `fact` | `FactFinance` | Fact Table (CCI) | 500,000 | Actual vs. Budget financial postings |
| `err` | `Rejected_Sales_Records` | Error Quarantine | 10,000 | Isolated negative/zero quantity anomalies |
| `etl` | `Watermark` | Control Table | 4 | Tracks `LastLoadedID` for incremental SSIS loads |

### 📂 Scripts Added in Module 2
* `01_Database_Scripts/03_Create_DWH_Galaxy_Schema.sql`
* `01_Database_Scripts/04_Populate_DWH_Dimensions.sql`
* `01_Database_Scripts/05_Populate_DWH_Facts.sql`