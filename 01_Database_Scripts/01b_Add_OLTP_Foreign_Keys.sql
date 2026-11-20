USE MegaCorp_ERP_OLTP;
GO

-- 1. ربط جدول رؤوس فواتير المبيعات (SalesOrdersHeader) بـ 4 جداول
ALTER TABLE sales.SalesOrdersHeader WITH NOCHECK
ADD CONSTRAINT FK_Orders_Customers FOREIGN KEY (CustomerID) REFERENCES sales.Customers(CustomerID);

ALTER TABLE sales.SalesOrdersHeader WITH NOCHECK
ADD CONSTRAINT FK_Orders_Branches FOREIGN KEY (BranchID) REFERENCES sales.Branches(BranchID);

ALTER TABLE sales.SalesOrdersHeader WITH NOCHECK
ADD CONSTRAINT FK_Orders_Channels FOREIGN KEY (ChannelID) REFERENCES sales.Channels(ChannelID);

ALTER TABLE sales.SalesOrdersHeader WITH NOCHECK
ADD CONSTRAINT FK_Orders_Employees FOREIGN KEY (SalesRepID) REFERENCES hr.Employees(EmployeeID);

-- 2. ربط جدول تفاصيل الفواتير (SalesOrderDetails) برؤوس الفواتير والمنتجات
ALTER TABLE sales.SalesOrderDetails WITH NOCHECK
ADD CONSTRAINT FK_OrderDetails_Orders FOREIGN KEY (OrderID) REFERENCES sales.SalesOrdersHeader(OrderID);

ALTER TABLE sales.SalesOrderDetails WITH NOCHECK
ADD CONSTRAINT FK_OrderDetails_Products FOREIGN KEY (ProductID) REFERENCES scm.Products(ProductID);

-- 3. ربط جدول المرتجعات (SalesReturns) بتفاصيل الفواتير
ALTER TABLE sales.SalesReturns WITH NOCHECK
ADD CONSTRAINT FK_Returns_OrderDetails FOREIGN KEY (OrderDetailID) REFERENCES sales.SalesOrderDetails(OrderDetailID);

-- 4. ربط جدول حركات المخزون (InventoryMovements) بالمستودعات والمنتجات
ALTER TABLE scm.InventoryMovements WITH NOCHECK
ADD CONSTRAINT FK_InvMovements_Warehouses FOREIGN KEY (WarehouseID) REFERENCES scm.Warehouses(WarehouseID);

ALTER TABLE scm.InventoryMovements WITH NOCHECK
ADD CONSTRAINT FK_InvMovements_Products FOREIGN KEY (ProductID) REFERENCES scm.Products(ProductID);
GO