USE MegaCorp_DWH;
GO

-- ============================================================================
-- 1. تفريغ جداول الحقائق والأخطاء لضمان عدم التكرار دون المساس بهيكل الجداول
-- ============================================================================
TRUNCATE TABLE err.Rejected_Sales_Records;
TRUNCATE TABLE fact.FactSales;
TRUNCATE TABLE fact.FactReturns;
TRUNCATE TABLE fact.FactInventory;
TRUNCATE TABLE fact.FactFinance;
GO

-- ============================================================================
-- 2. عزل البيانات التالفة في الحجر الصحي (Error Quarantine Pattern)
-- ============================================================================
INSERT INTO err.Rejected_Sales_Records (OrderID, OrderDetailID, ProductID, RawQuantity, RejectionReason)
SELECT 
    d.OrderID,
    d.OrderDetailID,
    d.ProductID,
    d.OrderQty,
    'Invalid Quantity (<= 0) detected during ETL Staging'
FROM MegaCorp_ERP_OLTP.sales.SalesOrderDetails d
WHERE d.OrderQty <= 0;
GO

-- ============================================================================
-- 3. تحميل جداول الحقائق الأربعة باستخدام Surrogate Keys (Set-Based Load)
-- ============================================================================

-- أ) تحميل المبيعات النظيفة (~1.99M صف)
INSERT INTO fact.FactSales (
    OrderID, OrderDetailID, DateKey, CustomerKey, ProductKey, BranchKey, ChannelKey, EmployeeKey,
    Quantity, UnitPrice, UnitCost, DiscountAmount, GrossRevenue, NetRevenue, TotalCost, NetProfit
)
SELECT 
    h.OrderID,
    d.OrderDetailID,
    CAST(CONVERT(VARCHAR(8), h.OrderDate, 112) AS INT) AS DateKey,
    c.CustomerKey,
    p.ProductKey,
    b.BranchKey,
    ch.ChannelKey,
    ISNULL(e.EmployeeKey, -1) AS EmployeeKey,
    d.OrderQty,
    d.UnitPrice,
    d.UnitCost,
    CAST((d.OrderQty * d.UnitPrice) * (d.DiscountPct / 100.0) AS DECIMAL(14,2)) AS DiscountAmount,
    CAST(d.OrderQty * d.UnitPrice AS DECIMAL(14,2)) AS GrossRevenue,
    CAST((d.OrderQty * d.UnitPrice) * (1 - d.DiscountPct / 100.0) AS DECIMAL(14,2)) AS NetRevenue,
    CAST(d.OrderQty * d.UnitCost AS DECIMAL(14,2)) AS TotalCost,
    CAST(((d.OrderQty * d.UnitPrice) * (1 - d.DiscountPct / 100.0)) - (d.OrderQty * d.UnitCost) AS DECIMAL(14,2)) AS NetProfit
FROM MegaCorp_ERP_OLTP.sales.SalesOrderDetails d
INNER JOIN MegaCorp_ERP_OLTP.sales.SalesOrdersHeader h ON d.OrderID = h.OrderID
INNER JOIN dim.DimCustomer c  ON h.CustomerID = c.CustomerID AND c.IsCurrent = 1
INNER JOIN dim.DimProduct p   ON d.ProductID = p.ProductID   AND p.IsCurrent = 1
INNER JOIN dim.DimBranch b    ON h.BranchID = b.BranchID
INNER JOIN dim.DimChannel ch  ON h.ChannelID = ch.ChannelID
LEFT JOIN  dim.DimEmployee e  ON h.SalesRepID = e.EmployeeID AND e.IsCurrent = 1
WHERE d.OrderQty > 0;

-- ب) تحميل المرتجعات (~150K صف)
INSERT INTO fact.FactReturns (
    ReturnID, OrderDetailID, DateKey, CustomerKey, ProductKey, BranchKey, ChannelKey,
    ReturnedQty, RefundAmount, ReturnReason
)
SELECT 
    r.ReturnID,
    r.OrderDetailID,
    CAST(CONVERT(VARCHAR(8), r.ReturnDate, 112) AS INT) AS DateKey,
    c.CustomerKey,
    p.ProductKey,
    b.BranchKey,
    ch.ChannelKey,
    r.ReturnQty,
    CAST(r.ReturnQty * d.UnitPrice * (1 - d.DiscountPct / 100.0) AS DECIMAL(14,2)) AS RefundAmount,
    r.ReturnReason
FROM MegaCorp_ERP_OLTP.sales.SalesReturns r
INNER JOIN MegaCorp_ERP_OLTP.sales.SalesOrderDetails d ON r.OrderDetailID = d.OrderDetailID
INNER JOIN MegaCorp_ERP_OLTP.sales.SalesOrdersHeader h ON d.OrderID = h.OrderID
INNER JOIN dim.DimCustomer c  ON h.CustomerID = c.CustomerID AND c.IsCurrent = 1
INNER JOIN dim.DimProduct p   ON d.ProductID = p.ProductID   AND p.IsCurrent = 1
INNER JOIN dim.DimBranch b    ON h.BranchID = b.BranchID
INNER JOIN dim.DimChannel ch  ON h.ChannelID = ch.ChannelID;

-- ج) تحميل حركات المخزون (~1.0M صف)
INSERT INTO fact.FactInventory (
    MovementID, DateKey, WarehouseKey, ProductKey, MovementType, QuantityChange, UnitCostValue
)
SELECT 
    m.MovementID,
    CAST(CONVERT(VARCHAR(8), m.MovementDate, 112) AS INT) AS DateKey,
    w.WarehouseKey,
    p.ProductKey,
    m.MovementType,
    m.QuantityChange,
    CAST(m.QuantityChange * p.UnitCost AS DECIMAL(14,2)) AS UnitCostValue
FROM MegaCorp_ERP_OLTP.scm.InventoryMovements m
INNER JOIN dim.DimWarehouse w ON m.WarehouseID = w.WarehouseID
INNER JOIN dim.DimProduct p   ON m.ProductID = p.ProductID AND p.IsCurrent = 1;

-- د) تحميل القيود المالية والموازنات (~500K صف)
INSERT INTO fact.FactFinance (
    TransactionID, DateKey, BranchKey, AccountKey, ActualAmount, BudgetAmount, VarianceAmount
)
SELECT 
    f.FinTransID,
    CAST(CONVERT(VARCHAR(8), f.PostingDate, 112) AS INT) AS DateKey,
    b.BranchKey,
    a.AccountKey,
    CASE WHEN f.Scenario = 'Actual' THEN f.Amount ELSE 0 END AS ActualAmount,
    CASE WHEN f.Scenario = 'Budget' THEN f.Amount ELSE 0 END AS BudgetAmount,
    CASE WHEN f.Scenario = 'Actual' THEN f.Amount ELSE -f.Amount END AS VarianceAmount
FROM MegaCorp_ERP_OLTP.fin.FinancialTransactions f
INNER JOIN dim.DimBranch b    ON f.BranchID = b.BranchID
INNER JOIN dim.DimGLAccount a ON f.AccountID = a.AccountID;
GO

-- ============================================================================
-- 4. تحديث جدول الـ Watermark وتدقيق أعداد الصفوف النهائية
-- ============================================================================
UPDATE etl.Watermark SET LastLoadedID = (SELECT MAX(OrderID) FROM fact.FactSales), LastUpdated = GETDATE() WHERE TableName = 'SalesOrders';
UPDATE etl.Watermark SET LastLoadedID = (SELECT MAX(ReturnID) FROM fact.FactReturns), LastUpdated = GETDATE() WHERE TableName = 'SalesReturns';
UPDATE etl.Watermark SET LastLoadedID = (SELECT MAX(MovementID) FROM fact.FactInventory), LastUpdated = GETDATE() WHERE TableName = 'InventoryMovements';
UPDATE etl.Watermark SET LastLoadedID = (SELECT MAX(TransactionID) FROM fact.FactFinance), LastUpdated = GETDATE() WHERE TableName = 'FinancialTransactions';

SELECT 'FactSales (Clean)' AS TableName, COUNT(*) AS TotalRows FROM fact.FactSales
UNION ALL
SELECT 'err.Rejected_Sales_Records (Quarantined)', COUNT(*) FROM err.Rejected_Sales_Records
UNION ALL
SELECT 'FactReturns', COUNT(*) FROM fact.FactReturns
UNION ALL
SELECT 'FactInventory', COUNT(*) FROM fact.FactInventory
UNION ALL
SELECT 'FactFinance', COUNT(*) FROM fact.FactFinance;
GO