USE master;
GO

IF EXISTS (SELECT name FROM sys.databases WHERE name = N'MegaCorp_DWH')
BEGIN
    ALTER DATABASE MegaCorp_DWH SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE MegaCorp_DWH;
END
GO

CREATE DATABASE MegaCorp_DWH;
GO

USE MegaCorp_DWH;
GO

-- إنشاء الـ Schemas المنطقية
CREATE SCHEMA dim;
GO
CREATE SCHEMA fact;
GO
CREATE SCHEMA etl;
GO
CREATE SCHEMA err;
GO

-- ============================================================================
-- 1. جداول الأبعاد (Conformed Dimensions with Surrogate Keys & SCD Type 2)
-- ============================================================================

CREATE TABLE dim.DimDate (
    DateKey INT PRIMARY KEY,                -- YYYYMMDD
    FullDate DATE NOT NULL,
    DayNumberOfWeek TINYINT NOT NULL,
    DayName NVARCHAR(15) NOT NULL,
    DayNumberOfMonth TINYINT NOT NULL,
    MonthNumber TINYINT NOT NULL,
    MonthName NVARCHAR(15) NOT NULL,
    CalendarQuarter TINYINT NOT NULL,
    CalendarYear SMALLINT NOT NULL,
    IsWeekend BIT NOT NULL
);

CREATE TABLE dim.DimProduct (
    ProductKey INT IDENTITY(1,1) PRIMARY KEY, -- Surrogate Key
    ProductID INT NOT NULL,                   -- Business/Natural Key
    ProductSKU NVARCHAR(30) NOT NULL,
    ProductName NVARCHAR(150) NOT NULL,
    CategoryName NVARCHAR(100) NOT NULL,
    SubCategoryName NVARCHAR(100) NOT NULL,
    BrandName NVARCHAR(100) NOT NULL,
    SupplierName NVARCHAR(150) NOT NULL,
    UnitCost DECIMAL(12,2) NOT NULL,
    UnitPrice DECIMAL(12,2) NOT NULL,
    ReorderLevel INT NOT NULL,
    -- أعمدة تتبع التغييرات التاريخية (SCD Type 2)
    StartDate DATETIME NOT NULL DEFAULT '2020-01-01',
    EndDate DATETIME NULL,
    IsCurrent BIT NOT NULL DEFAULT 1
);

CREATE TABLE dim.DimCustomer (
    CustomerKey INT IDENTITY(1,1) PRIMARY KEY,
    CustomerID INT NOT NULL,
    FullName NVARCHAR(150) NOT NULL,
    Email NVARCHAR(150) NULL,
    City NVARCHAR(100) NOT NULL,
    SegmentName NVARCHAR(50) NOT NULL,
    DiscountCapPct DECIMAL(5,2) NOT NULL,
    StartDate DATETIME NOT NULL DEFAULT '2020-01-01',
    EndDate DATETIME NULL,
    IsCurrent BIT NOT NULL DEFAULT 1
);

CREATE TABLE dim.DimBranch (
    BranchKey INT IDENTITY(1,1) PRIMARY KEY,
    BranchID INT NOT NULL,
    BranchName NVARCHAR(100) NOT NULL,
    City NVARCHAR(100) NOT NULL,
    RegionName NVARCHAR(100) NOT NULL,
    Country NVARCHAR(100) NOT NULL,
    SquareMeters INT NOT NULL
);

CREATE TABLE dim.DimChannel (
    ChannelKey INT IDENTITY(1,1) PRIMARY KEY,
    ChannelID INT NOT NULL,
    ChannelName NVARCHAR(50) NOT NULL
);

CREATE TABLE dim.DimEmployee (
    EmployeeKey INT IDENTITY(1,1) PRIMARY KEY,
    EmployeeID INT NOT NULL,
    FullName NVARCHAR(150) NOT NULL,
    DepartmentName NVARCHAR(100) NOT NULL,
    JobTitle NVARCHAR(100) NOT NULL,
    HireDate DATE NOT NULL,
    BaseSalary DECIMAL(12,2) NOT NULL,
    StartDate DATETIME NOT NULL DEFAULT '2020-01-01',
    EndDate DATETIME NULL,
    IsCurrent BIT NOT NULL DEFAULT 1
);

CREATE TABLE dim.DimWarehouse (
    WarehouseKey INT IDENTITY(1,1) PRIMARY KEY,
    WarehouseID INT NOT NULL,
    WarehouseName NVARCHAR(100) NOT NULL,
    City NVARCHAR(100) NOT NULL,
    CapacityUnits INT NOT NULL
);

CREATE TABLE dim.DimGLAccount (
    AccountKey INT IDENTITY(1,1) PRIMARY KEY,
    AccountID INT NOT NULL,
    AccountCode NVARCHAR(20) NOT NULL,
    AccountName NVARCHAR(100) NOT NULL,
    AccountType NVARCHAR(30) NOT NULL
);

-- ============================================================================
-- 2. جداول الحقائق (Fact Tables - Galaxy Schema)
-- ============================================================================

CREATE TABLE fact.FactSales (
    SalesKey BIGINT IDENTITY(1,1) NOT NULL,
    OrderID INT NOT NULL,
    OrderDetailID INT NOT NULL,
    DateKey INT NOT NULL,
    CustomerKey INT NOT NULL,
    ProductKey INT NOT NULL,
    BranchKey INT NOT NULL,
    ChannelKey INT NOT NULL,
    EmployeeKey INT NOT NULL,
    Quantity INT NOT NULL,
    UnitPrice DECIMAL(12,2) NOT NULL,
    UnitCost DECIMAL(12,2) NOT NULL,
    DiscountAmount DECIMAL(12,2) NOT NULL,
    GrossRevenue DECIMAL(14,2) NOT NULL,
    NetRevenue DECIMAL(14,2) NOT NULL,
    TotalCost DECIMAL(14,2) NOT NULL,
    NetProfit DECIMAL(14,2) NOT NULL
);

CREATE TABLE fact.FactReturns (
    ReturnKey BIGINT IDENTITY(1,1) NOT NULL,
    ReturnID INT NOT NULL,
    OrderDetailID INT NOT NULL,
    DateKey INT NOT NULL,
    CustomerKey INT NOT NULL,
    ProductKey INT NOT NULL,
    BranchKey INT NOT NULL,
    ChannelKey INT NOT NULL,
    ReturnedQty INT NOT NULL,
    RefundAmount DECIMAL(14,2) NOT NULL,
    ReturnReason NVARCHAR(100) NOT NULL
);

CREATE TABLE fact.FactInventory (
    InventoryKey BIGINT IDENTITY(1,1) NOT NULL,
    MovementID INT NOT NULL,
    DateKey INT NOT NULL,
    WarehouseKey INT NOT NULL,
    ProductKey INT NOT NULL,
    MovementType NVARCHAR(20) NOT NULL, -- IN, OUT, ADJUSTMENT
    QuantityChange INT NOT NULL,
    UnitCostValue DECIMAL(14,2) NOT NULL
);

CREATE TABLE fact.FactFinance (
    FinanceKey BIGINT IDENTITY(1,1) NOT NULL,
    TransactionID INT NOT NULL,
    DateKey INT NOT NULL,
    BranchKey INT NOT NULL,
    AccountKey INT NOT NULL,
    ActualAmount DECIMAL(14,2) NOT NULL,
    BudgetAmount DECIMAL(14,2) NOT NULL,
    VarianceAmount DECIMAL(14,2) NOT NULL
);

-- ============================================================================
-- 3. ضغط البيانات وتسريع الاستعلامات (Clustered Columnstore Indexes)
-- ============================================================================
CREATE CLUSTERED COLUMNSTORE INDEX CCI_FactSales ON fact.FactSales;
CREATE CLUSTERED COLUMNSTORE INDEX CCI_FactReturns ON fact.FactReturns;
CREATE CLUSTERED COLUMNSTORE INDEX CCI_FactInventory ON fact.FactInventory;
CREATE CLUSTERED COLUMNSTORE INDEX CCI_FactFinance ON fact.FactFinance;
GO

-- ============================================================================
-- 4. طبقة التحكم في التحديث وعزل الأخطاء (ETL Control & Error Quarantine)
-- ============================================================================
CREATE TABLE etl.Watermark (
    TableName NVARCHAR(100) PRIMARY KEY,
    LastLoadedID BIGINT NOT NULL DEFAULT 0,
    LastUpdated DATETIME NOT NULL DEFAULT GETDATE()
);

INSERT INTO etl.Watermark (TableName, LastLoadedID)
VALUES 
    ('SalesOrders', 0),
    ('SalesReturns', 0),
    ('InventoryMovements', 0),
    ('FinancialTransactions', 0);

CREATE TABLE err.Rejected_Sales_Records (
    ErrorID INT IDENTITY(1,1) PRIMARY KEY,
    OrderID INT NULL,
    OrderDetailID INT NULL,
    ProductID INT NULL,
    RawQuantity INT NULL,
    RejectionReason NVARCHAR(250) NOT NULL,
    RejectedAt DATETIME NOT NULL DEFAULT GETDATE()
);
GO