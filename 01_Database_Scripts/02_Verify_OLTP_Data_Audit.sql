USE MegaCorp_ERP_OLTP;
GO

-- 1. عرض عدد الصفوف والمساحة لكل جدول من الـ 20 جدولاً
SELECT 
    s.name AS SchemaName,
    t.name AS TableName,
    SUM(p.rows) AS TotalRows,
    CAST(ROUND(((SUM(a.total_pages) * 8) / 1024.00), 2) AS NUMERIC(36, 2)) AS TotalSpace_MB
FROM sys.tables t
INNER JOIN sys.indexes i ON t.OBJECT_ID = i.object_id
INNER JOIN sys.partitions p ON i.object_id = p.OBJECT_ID AND i.index_id = p.index_id
INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
LEFT OUTER JOIN sys.schemas s ON t.schema_id = s.schema_id
WHERE t.is_ms_shipped = 0 AND i.OBJECT_ID > 255
GROUP BY t.name, s.name
ORDER BY TotalRows DESC;

-- 2. التحقق من وجود الأخطاء المزروعة (الكميات السالبة وأسماء العملاء غير المنظمة)
SELECT COUNT(*) AS Corrupted_Sales_Rows FROM sales.SalesOrderDetails WHERE OrderQty <= 0;
SELECT TOP 10 CustomerID, '[' + FullName + ']' AS Dirty_Customer_Name FROM sales.Customers WHERE FullName LIKE ' %';