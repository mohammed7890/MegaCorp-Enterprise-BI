USE MegaCorp_DWH;
GO

-- ============================================================================
-- 2. تعبئة جدول التقويم (DimDate) من 2020-01-01 إلى 2030-12-31 (4,018 يوم)
-- ============================================================================
DECLARE @StartDate DATE = '2020-01-01';
DECLARE @EndDate   DATE = '2030-12-31';

WITH DateCTE AS (
    SELECT @StartDate AS FullDate
    UNION ALL
    SELECT DATEADD(DAY, 1, FullDate)
    FROM DateCTE
    WHERE FullDate < @EndDate
)
INSERT INTO dim.DimDate (
    DateKey, FullDate, DayNumberOfWeek, DayName, DayNumberOfMonth,
    MonthNumber, MonthName, CalendarQuarter, CalendarYear, IsWeekend
)
SELECT 
    CAST(CONVERT(VARCHAR(8), FullDate, 112) AS INT) AS DateKey,
    FullDate,
    DATEPART(WEEKDAY, FullDate) AS DayNumberOfWeek,
    DATENAME(WEEKDAY, FullDate) AS DayName,
    DAY(FullDate) AS DayNumberOfMonth,
    MONTH(FullDate) AS MonthNumber,
    DATENAME(MONTH, FullDate) AS MonthName,
    DATEPART(QUARTER, FullDate) AS CalendarQuarter,
    YEAR(FullDate) AS CalendarYear,
    CASE WHEN DATEPART(WEEKDAY, FullDate) IN (6, 7) THEN 1 ELSE 0 END AS IsWeekend
FROM DateCTE
OPTION (MAXRECURSION 0);
GO

-- ============================================================================
-- 3. تحميل كافة الأبعاد السبعة مع التنظيف والدمج (Denormalization & Cleansing)
-- ============================================================================

-- أ) المنتجات (دمج 5 جداول: Products + SubCategories + Categories + Brands + Suppliers)
INSERT INTO dim.DimProduct (
    ProductID, SKU, ProductName, CategoryName, SubCategoryName,
    BrandName, OriginCountry, SupplierName, LeadTimeDays, UnitCost, ListPrice,
    ReorderLevel, IsDiscontinued, StartDate, IsCurrent
)
SELECT 
    p.ProductID, p.SKU, LTRIM(RTRIM(p.ProductName)),
    c.CategoryName, sc.SubCategoryName, b.BrandName, b.OriginCountry,
    s.SupplierName, s.LeadTimeDays, p.UnitCost, p.ListPrice,
    p.ReorderLevel, p.IsDiscontinued, '2020-01-01', 1
FROM MegaCorp_ERP_OLTP.scm.Products p
INNER JOIN MegaCorp_ERP_OLTP.scm.SubCategories sc ON p.SubCategoryID = sc.SubCategoryID
INNER JOIN MegaCorp_ERP_OLTP.scm.Categories c     ON sc.CategoryID = c.CategoryID
INNER JOIN MegaCorp_ERP_OLTP.scm.Brands b         ON p.BrandID = b.BrandID
INNER JOIN MegaCorp_ERP_OLTP.scm.Suppliers s      ON p.SupplierID = s.SupplierID;

-- ب) العملاء (تنظيف الأسماء + دمج الشرائح والمناطق)
INSERT INTO dim.DimCustomer (
    CustomerID, CustomerCode, FullName, Email, RegionName, Country,
    SegmentName, MaxCreditLimit, RegistrationDate, StartDate, IsCurrent
)
SELECT 
    cust.CustomerID, cust.CustomerCode,
    UPPER(LTRIM(RTRIM(cust.FullName))) AS FullName,
    LOWER(LTRIM(RTRIM(cust.Email))) AS Email,
    r.RegionName, r.Country,
    seg.SegmentName, seg.MaxCreditLimit, cust.RegistrationDate, '2020-01-01', 1
FROM MegaCorp_ERP_OLTP.sales.Customers cust
INNER JOIN MegaCorp_ERP_OLTP.sales.CustomerSegments seg ON cust.SegmentID = seg.SegmentID
INNER JOIN MegaCorp_ERP_OLTP.sales.Regions r           ON cust.RegionID = r.RegionID;

-- ج) الفروع والمناطق الجغرافية
INSERT INTO dim.DimBranch (BranchID, BranchCode, BranchName, RegionName, Country, StoreSizeSqM, OpeningDate)
SELECT 
    b.BranchID, b.BranchCode, b.BranchName, r.RegionName, r.Country, b.StoreSizeSqM, b.OpeningDate
FROM MegaCorp_ERP_OLTP.sales.Branches b
INNER JOIN MegaCorp_ERP_OLTP.sales.Regions r ON b.RegionID = r.RegionID;

-- د) قنوات البيع
INSERT INTO dim.DimChannel (ChannelID, ChannelName)
SELECT ChannelID, ChannelName
FROM MegaCorp_ERP_OLTP.sales.Channels;

-- هـ) الموظفون والأقسام والمسميات الوظيفية
INSERT INTO dim.DimEmployee (
    EmployeeID, NationalID, FullName, Gender, DepartmentName, CostCenterCode,
    JobTitle, HireDate, BaseSalary, PerformanceRating, StartDate, IsCurrent
)
SELECT 
    e.EmployeeID, e.NationalID, LTRIM(RTRIM(e.FullName)), e.Gender,
    d.DepartmentName, d.CostCenterCode, j.JobTitle, e.HireDate,
    e.BaseSalary, e.PerformanceRating, '2020-01-01', 1
FROM MegaCorp_ERP_OLTP.hr.Employees e
INNER JOIN MegaCorp_ERP_OLTP.hr.Departments d ON e.DepartmentID = d.DepartmentID
INNER JOIN MegaCorp_ERP_OLTP.hr.JobTitles j   ON e.JobTitleID = j.JobTitleID;

-- و) المستودعات والمناطق
INSERT INTO dim.DimWarehouse (WarehouseID, WarehouseName, RegionName, Country, MaxCapacityUnits)
SELECT w.WarehouseID, w.WarehouseName, r.RegionName, r.Country, w.MaxCapacityUnits
FROM MegaCorp_ERP_OLTP.scm.Warehouses w
INNER JOIN MegaCorp_ERP_OLTP.sales.Regions r ON w.RegionID = r.RegionID;

-- ز) شجرة الحسابات المالية
INSERT INTO dim.DimGLAccount (AccountID, AccountName, AccountType, ParentCategory)
SELECT AccountID, AccountName, AccountType, ParentCategory
FROM MegaCorp_ERP_OLTP.fin.GL_Accounts;
GO