USE master;
GO

IF DB_ID('MegaCorp_ERP_OLTP') IS NOT NULL 
BEGIN
    ALTER DATABASE MegaCorp_ERP_OLTP SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE MegaCorp_ERP_OLTP;
END
GO

CREATE DATABASE MegaCorp_ERP_OLTP;
GO

USE MegaCorp_ERP_OLTP;
GO

-- تحسين سرعة الإدخال الضخم (Minimal Logging)
ALTER DATABASE MegaCorp_ERP_OLTP SET RECOVERY SIMPLE;
GO

-- إنشاء الـ Schemas للأقسام المختلفة
CREATE SCHEMA sales;
GO
CREATE SCHEMA scm;
GO
CREATE SCHEMA hr;
GO
CREATE SCHEMA fin;
GO

-- ============================================================================
-- 1. بناء جداول المرجعية والأقسام (Master & Reference Tables - 20 Tables)
-- ============================================================================

-- [1] المناطق الجغرافية
CREATE TABLE sales.Regions (
    RegionID INT PRIMARY KEY,
    RegionName NVARCHAR(50),
    Country NVARCHAR(50) DEFAULT N'Egypt'
);
INSERT INTO sales.Regions VALUES 
(1, N'Greater Cairo', N'Egypt'), (2, N'Alexandria & North Coast', N'Egypt'),
(3, N'Delta Region', N'Egypt'), (4, N'Suez Canal & Sinai', N'Egypt'), (5, N'Upper Egypt', N'Egypt');

-- [2] الفروع (30 فرع)
CREATE TABLE sales.Branches (
    BranchID INT PRIMARY KEY,
    BranchCode VARCHAR(15),
    BranchName NVARCHAR(100),
    RegionID INT FOREIGN KEY REFERENCES sales.Regions(RegionID),
    StoreSizeSqM INT,
    OpeningDate DATE
);
;WITH B AS (SELECT TOP 30 ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n FROM sys.all_objects)
INSERT INTO sales.Branches
SELECT n, 'BR-' + RIGHT('00' + CAST(n AS VARCHAR), 3), N'MegaStore Branch #' + CAST(n AS NVARCHAR),
       (n % 5) + 1, 500 + (n * 50), DATEADD(MONTH, - (n * 3), '2026-01-01')
FROM B;

-- [3] قنوات البيع
CREATE TABLE sales.Channels (
    ChannelID INT PRIMARY KEY,
    ChannelName NVARCHAR(50)
);
INSERT INTO sales.Channels VALUES (1, N'In-Store POS'), (2, N'E-Commerce Web'), (3, N'Mobile App'), (4, N'B2B Direct Corporate');

-- [4] شرائح العملاء
CREATE TABLE sales.CustomerSegments (
    SegmentID INT PRIMARY KEY,
    SegmentName NVARCHAR(50),
    MaxCreditLimit DECIMAL(12,2)
);
INSERT INTO sales.CustomerSegments VALUES 
(1, N'VIP Enterprise', 500000), (2, N'SMB Business', 150000), (3, N'Retail Prime', 25000), (4, N'Standard Consumer', 5000);

-- [5] الأقسام الإدارية (HR)
CREATE TABLE hr.Departments (
    DepartmentID INT PRIMARY KEY,
    DepartmentName NVARCHAR(100),
    CostCenterCode VARCHAR(20)
);
INSERT INTO hr.Departments VALUES 
(1, N'Retail Sales & Operations', 'CC-100'), (2, N'Supply Chain & Logistics', 'CC-200'),
(3, N'Information Technology & BI', 'CC-300'), (4, N'Corporate Finance & Audit', 'CC-400'),
(5, N'Human Resources', 'CC-500'), (6, N'Digital Marketing & E-Commerce', 'CC-600');

-- [6] المسميات الوظيفية
CREATE TABLE hr.JobTitles (
    JobTitleID INT PRIMARY KEY,
    JobTitle NVARCHAR(100),
    MinSalary DECIMAL(10,2),
    MaxSalary DECIMAL(10,2)
);
INSERT INTO hr.JobTitles VALUES 
(1, N'Sales Representative', 7000, 14000), (2, N'Branch Manager', 22000, 40000),
(3, N'Supply Chain Coordinator', 10000, 20000), (4, N'BI & Data Engineer', 25000, 55000),
(5, N'Financial Analyst', 15000, 32000), (6, N'HR Specialist', 10000, 22000);

-- [7] الموظفون (2,500 موظف)
CREATE TABLE hr.Employees (
    EmployeeID INT PRIMARY KEY,
    NationalID VARCHAR(14),
    FullName NVARCHAR(100),
    Gender CHAR(1),
    BirthDate DATE,
    HireDate DATE,
    TerminationDate DATE NULL,
    DepartmentID INT FOREIGN KEY REFERENCES hr.Departments(DepartmentID),
    JobTitleID INT FOREIGN KEY REFERENCES hr.JobTitles(JobTitleID),
    BranchID INT FOREIGN KEY REFERENCES sales.Branches(BranchID),
    BaseSalary DECIMAL(10,2),
    PerformanceRating INT -- 1 to 5
);
;WITH EmpNums AS (SELECT TOP 2500 ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n FROM sys.all_objects)
INSERT INTO hr.Employees
SELECT 
    10000 + n,
    '29' + RIGHT('000000000000' + CAST(ABS(CHECKSUM(NEWID())) AS VARCHAR), 12),
    N'Employee_' + CAST(10000 + n AS NVARCHAR),
    CASE WHEN n % 3 = 0 THEN 'F' ELSE 'M' END,
    DATEADD(DAY, - (8000 + (ABS(CHECKSUM(NEWID())) % 6000)), '2026-01-01'),
    DATEADD(DAY, - (ABS(CHECKSUM(NEWID())) % 2000), '2026-10-01'),
    CASE WHEN n % 9 = 0 THEN DATEADD(DAY, - (ABS(CHECKSUM(NEWID())) % 300), '2026-10-01') ELSE NULL END,
    (n % 6) + 1,
    (n % 6) + 1,
    (n % 30) + 1,
    CAST(8000 + (ABS(CHECKSUM(NEWID())) % 35000) AS DECIMAL(10,2)),
    (n % 5) + 1
FROM EmpNums;

-- [8] الفئات الرئيسية للمنتجات
CREATE TABLE scm.Categories (
    CategoryID INT PRIMARY KEY,
    CategoryName NVARCHAR(50)
);
INSERT INTO scm.Categories VALUES 
(1, N'Consumer Electronics'), (2, N'Home & Kitchen Appliances'), 
(3, N'Computers & Enterprise IT'), (4, N'Smartphones & Tablets'), (5, N'Office Furniture & Supplies');

-- [9] الفئات الفرعية (25 فئة فرعية)
CREATE TABLE scm.SubCategories (
    SubCategoryID INT PRIMARY KEY,
    SubCategoryName NVARCHAR(50),
    CategoryID INT FOREIGN KEY REFERENCES scm.Categories(CategoryID)
);
;WITH SubC AS (SELECT TOP 25 ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n FROM sys.all_objects)
INSERT INTO scm.SubCategories
SELECT n, N'SubCategory_' + CAST(n AS NVARCHAR), (n % 5) + 1 FROM SubC;

-- [10] العلامات التجارية (40 براند)
CREATE TABLE scm.Brands (
    BrandID INT PRIMARY KEY,
    BrandName NVARCHAR(50),
    OriginCountry NVARCHAR(50)
);
;WITH Br AS (SELECT TOP 40 ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n FROM sys.all_objects)
INSERT INTO scm.Brands
SELECT n, N'Brand_' + CAST(n AS NVARCHAR), 
       CASE n % 4 WHEN 0 THEN N'Germany' WHEN 1 THEN N'Japan' WHEN 2 THEN N'USA' ELSE N'China' END
FROM Br;

-- [11] الموردون (150 مورد)
CREATE TABLE scm.Suppliers (
    SupplierID INT PRIMARY KEY,
    SupplierName NVARCHAR(100),
    LeadTimeDays INT,
    ReliabilityScore DECIMAL(5,2)
);
;WITH Sup AS (SELECT TOP 150 ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n FROM sys.all_objects)
INSERT INTO scm.Suppliers
SELECT n, N'Global Supplier Co. #' + CAST(n AS NVARCHAR), (n % 21) + 3, CAST(70.0 + (n % 30) AS DECIMAL(5,2))
FROM Sup;

-- [12] المنتجات (2,000 منتج)
CREATE TABLE scm.Products (
    ProductID INT PRIMARY KEY,
    SKU VARCHAR(30),
    ProductName NVARCHAR(150),
    SubCategoryID INT FOREIGN KEY REFERENCES scm.SubCategories(SubCategoryID),
    BrandID INT FOREIGN KEY REFERENCES scm.Brands(BrandID),
    SupplierID INT FOREIGN KEY REFERENCES scm.Suppliers(SupplierID),
    UnitCost DECIMAL(12,2),
    ListPrice DECIMAL(12,2),
    ReorderLevel INT,
    IsDiscontinued BIT
);
;WITH Prd AS (SELECT TOP 2000 ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n FROM sys.all_objects)
INSERT INTO scm.Products
SELECT 
    n,
    'SKU-' + RIGHT('00000' + CAST(n AS VARCHAR), 5),
    N'Enterprise Product Model #' + CAST(n AS NVARCHAR),
    (n % 25) + 1,
    (n % 40) + 1,
    (n % 150) + 1,
    CAST(150 + (n * 2.5) AS DECIMAL(12,2)),
    CAST((150 + (n * 2.5)) * (1.20 + ((n % 30) / 100.0)) AS DECIMAL(12,2)),
    20 + (n % 50),
    CASE WHEN n % 20 = 0 THEN 1 ELSE 0 END
FROM Prd;

-- [13] المستودعات المركزية (10 مستودعات)
CREATE TABLE scm.Warehouses (
    WarehouseID INT PRIMARY KEY,
    WarehouseName NVARCHAR(100),
    RegionID INT FOREIGN KEY REFERENCES sales.Regions(RegionID),
    MaxCapacityUnits INT
);
;WITH Wh AS (SELECT TOP 10 ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n FROM sys.all_objects)
INSERT INTO scm.Warehouses
SELECT n, N'Central Logistics Hub #' + CAST(n AS NVARCHAR), (n % 5) + 1, 100000 + (n * 25000) FROM Wh;

-- [14] العملاء (50,000 عميل!)
CREATE TABLE sales.Customers (
    CustomerID INT PRIMARY KEY,
    CustomerCode VARCHAR(20),
    FullName NVARCHAR(100),
    SegmentID INT FOREIGN KEY REFERENCES sales.CustomerSegments(SegmentID),
    RegionID INT FOREIGN KEY REFERENCES sales.Regions(RegionID),
    RegistrationDate DATE,
    Email VARCHAR(100)
);
;WITH C1 AS (SELECT TOP 250 ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n FROM sys.all_objects),
      C2 AS (SELECT TOP 200 ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n FROM sys.all_objects),
      CustGen AS (SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS cid FROM C1 CROSS JOIN C2)
INSERT INTO sales.Customers WITH (TABLOCK)
SELECT 
    cid,
    'CUST-' + RIGHT('000000' + CAST(cid AS VARCHAR), 6),
    -- زرع 2% أسماء بمسافات غير منتظمة لتنظيفها في SSIS
    CASE WHEN cid % 50 = 0 THEN N'   client_name_' + CAST(cid AS NVARCHAR) + N'   '
         ELSE N'Customer_Account_' + CAST(cid AS NVARCHAR) END,
    (cid % 4) + 1,
    (cid % 5) + 1,
    DATEADD(DAY, - (ABS(CHECKSUM(NEWID())) % 1800), '2026-10-01'),
    'user' + CAST(cid AS VARCHAR) + '@megacorp-client.com'
FROM CustGen;

-- [15] شجرة الحسابات المالية (Chart of Accounts)
CREATE TABLE fin.GL_Accounts (
    AccountID INT PRIMARY KEY,
    AccountName NVARCHAR(100),
    AccountType NVARCHAR(50), -- Revenue, COGS, OPEX, Asset, Liability
    ParentCategory NVARCHAR(50)
);
INSERT INTO fin.GL_Accounts VALUES
(4010, N'Gross Product Sales', N'Revenue', N'Operating Revenue'),
(4020, N'Service & Warranty Revenue', N'Revenue', N'Operating Revenue'),
(5010, N'Cost of Goods Sold (Direct)', N'COGS', N'Cost of Sales'),
(5020, N'Inbound Freight & Customs', N'COGS', N'Cost of Sales'),
(6010, N'Salaries & Employee Benefits', N'OPEX', N'SG&A Expenses'),
(6020, N'Branch Rent & Utilities', N'OPEX', N'SG&A Expenses'),
(6030, N'Digital Marketing Campaigns', N'OPEX', N'Marketing & Sales'),
(6040, N'IT Infrastructure & Cloud Licenses', N'OPEX', N'Technology Expenses');

-- ============================================================================
-- 2. بناء جداول الحركات الضخمة (Massive Transactional Tables - Millions of Rows)
-- ============================================================================

-- [16] رؤوس فواتير المبيعات (500,000 فاتورة)
CREATE TABLE sales.SalesOrdersHeader (
    OrderID BIGINT PRIMARY KEY,
    OrderDate DATE NOT NULL,
    ShipDate DATE NOT NULL,
    CustomerID INT NOT NULL,
    BranchID INT NOT NULL,
    ChannelID INT NOT NULL,
    SalesRepID INT NOT NULL,
    OrderStatus VARCHAR(20)
);

;WITH H1 AS (SELECT TOP 1000 ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n FROM sys.all_objects),
      H2 AS (SELECT TOP 500 ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n FROM sys.all_objects),
      HeaderGen AS (SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS oid FROM H1 CROSS JOIN H2)
INSERT INTO sales.SalesOrdersHeader WITH (TABLOCK)
SELECT 
    oid,
    DATEADD(DAY, - (ABS(CHECKSUM(NEWID())) % 1460), '2026-11-01'), -- آخر 4 سنوات
    DATEADD(DAY, - (ABS(CHECKSUM(NEWID())) % 1455), '2026-11-05'),
    (ABS(CHECKSUM(NEWID())) % 50000) + 1,
    (ABS(CHECKSUM(NEWID())) % 30) + 1,
    (ABS(CHECKSUM(NEWID())) % 4) + 1,
    10001 + (ABS(CHECKSUM(NEWID())) % 2500),
    CASE WHEN oid % 20 = 0 THEN 'Cancelled' WHEN oid % 15 = 0 THEN 'Pending' ELSE 'Completed' END
FROM HeaderGen;

-- [17] تفاصيل فواتير المبيعات (2,000,000 صف - 2 مليون حركة بيع!)
CREATE TABLE sales.SalesOrderDetails (
    OrderDetailID BIGINT IDENTITY(1,1) PRIMARY KEY,
    OrderID BIGINT NOT NULL,
    ProductID INT NOT NULL,
    OrderQty INT NOT NULL,
    UnitPrice DECIMAL(12,2) NOT NULL,
    UnitCost DECIMAL(12,2) NOT NULL,
    DiscountPct DECIMAL(5,2) NOT NULL
);

;WITH D1 AS (SELECT TOP 2000 ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n FROM sys.all_objects),
      D2 AS (SELECT TOP 1000 ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n FROM sys.all_objects),
      DetailGen AS (SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS did FROM D1 CROSS JOIN D2)
INSERT INTO sales.SalesOrderDetails WITH (TABLOCK) (OrderID, ProductID, OrderQty, UnitPrice, UnitCost, DiscountPct)
SELECT 
    ((did - 1) % 500000) + 1,
    (ABS(CHECKSUM(NEWID())) % 2000) + 1,
    -- زرع 0.5% كميات سالبة أو صفرية كأخطاء لتنظيفها في الـ ETL
    CASE WHEN did % 200 = 0 THEN -1 ELSE (ABS(CHECKSUM(NEWID())) % 12) + 1 END,
    CAST(200 + (ABS(CHECKSUM(NEWID())) % 4800) AS DECIMAL(12,2)),
    CAST(140 + (ABS(CHECKSUM(NEWID())) % 3200) AS DECIMAL(12,2)),
    CASE WHEN did % 5 = 0 THEN 0.15 WHEN did % 3 = 0 THEN 0.05 ELSE 0.00 END
FROM DetailGen;

-- [18] مرتجعات المبيعات (150,000 حركة مرتجع)
CREATE TABLE sales.SalesReturns (
    ReturnID BIGINT IDENTITY(1,1) PRIMARY KEY,
    OrderDetailID BIGINT,
    ReturnDate DATE,
    ReturnQty INT,
    ReturnReason NVARCHAR(100)
);

INSERT INTO sales.SalesReturns WITH (TABLOCK) (OrderDetailID, ReturnDate, ReturnQty, ReturnReason)
SELECT TOP 150000
    OrderDetailID,
    DATEADD(DAY, (ABS(CHECKSUM(NEWID())) % 14) + 1, '2025-05-01'),
    1,
    CASE OrderDetailID % 4 
        WHEN 0 THEN N'Defective Item' 
        WHEN 1 THEN N'Late Delivery' 
        WHEN 2 THEN N'Wrong Item Shipped' 
        ELSE N'Customer Changed Mind' 
    END
FROM sales.SalesOrderDetails;

-- [19] حركات المخزون والتوريد (1,000,000 صف - مليون حركة مخزن!)
CREATE TABLE scm.InventoryMovements (
    MovementID BIGINT IDENTITY(1,1) PRIMARY KEY,
    MovementDate DATE NOT NULL,
    WarehouseID INT NOT NULL,
    ProductID INT NOT NULL,
    MovementType VARCHAR(20), -- 'IN-Purchase', 'OUT-Sale', 'ADJ-Damage', 'TRANSFER'
    QuantityChange INT
);

;WITH M1 AS (SELECT TOP 1000 ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n FROM sys.all_objects),
      M2 AS (SELECT TOP 1000 ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n FROM sys.all_objects)
INSERT INTO scm.InventoryMovements WITH (TABLOCK) (MovementDate, WarehouseID, ProductID, MovementType, QuantityChange)
SELECT 
    DATEADD(DAY, - (ABS(CHECKSUM(NEWID())) % 1460), '2026-11-01'),
    (ABS(CHECKSUM(NEWID())) % 10) + 1,
    (ABS(CHECKSUM(NEWID())) % 2000) + 1,
    CASE ABS(CHECKSUM(NEWID())) % 4 
        WHEN 0 THEN 'IN-Purchase' 
        WHEN 1 THEN 'OUT-Sale' 
        WHEN 2 THEN 'TRANSFER' 
        ELSE 'ADJ-Damage' 
    END,
    (ABS(CHECKSUM(NEWID())) % 50) - 15
FROM M1 CROSS JOIN M2;

-- [20] القيود المالية والموازنات (500,000 قيد محاسبي فعلي ومخطط)
CREATE TABLE fin.FinancialTransactions (
    FinTransID BIGINT IDENTITY(1,1) PRIMARY KEY,
    PostingDate DATE NOT NULL,
    AccountID INT FOREIGN KEY REFERENCES fin.GL_Accounts(AccountID),
    DepartmentID INT FOREIGN KEY REFERENCES hr.Departments(DepartmentID),
    BranchID INT FOREIGN KEY REFERENCES sales.Branches(BranchID),
    Scenario VARCHAR(15), -- 'Actual' or 'Budget'
    Amount DECIMAL(14,2)
);

;WITH F1 AS (SELECT TOP 1000 ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n FROM sys.all_objects),
      F2 AS (SELECT TOP 500 ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n FROM sys.all_objects)
INSERT INTO fin.FinancialTransactions WITH (TABLOCK) (PostingDate, AccountID, DepartmentID, BranchID, Scenario, Amount)
SELECT 
    DATEADD(DAY, - (ABS(CHECKSUM(NEWID())) % 1460), '2026-11-01'),
    CASE ABS(CHECKSUM(NEWID())) % 8 
        WHEN 0 THEN 4010 WHEN 1 THEN 4020 WHEN 2 THEN 5010 WHEN 3 THEN 5020
        WHEN 4 THEN 6010 WHEN 5 THEN 6020 WHEN 6 THEN 6030 ELSE 6040 
    END,
    (ABS(CHECKSUM(NEWID())) % 6) + 1,
    (ABS(CHECKSUM(NEWID())) % 30) + 1,
    CASE WHEN ABS(CHECKSUM(NEWID())) % 3 = 0 THEN 'Budget' ELSE 'Actual' END,
    CAST(1000 + (ABS(CHECKSUM(NEWID())) % 95000) AS DECIMAL(14,2))
FROM F1 CROSS JOIN F2;
GO