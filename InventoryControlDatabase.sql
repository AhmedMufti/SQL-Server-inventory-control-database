/*
================================================================================
  INVENTORY CONTROL DATABASE - Production-Ready SQL Server Implementation
================================================================================
  Author:       Database Engineering Team
  Created:      2026-02-09
  Database:     SQL Server 2019+
  Purpose:      Complete inventory management system with stock tracking,
                transaction logging, automated alerts, and reporting
  
  EXECUTION ORDER:
    1. Create Database (optional - run separately if needed)
    2. Create Tables
    3. Create Indexes
    4. Create Triggers
    5. Create Stored Procedures
    6. Create Alert System
    7. Insert Sample Data
================================================================================
*/

-- ============================================================================
-- SECTION 1: DATABASE CREATION (Run separately if database doesn't exist)
-- ============================================================================

/*
-- Uncomment to create database
USE master;
GO

IF EXISTS (SELECT name FROM sys.databases WHERE name = N'InventoryControl')
BEGIN
    ALTER DATABASE InventoryControl SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE InventoryControl;
END
GO

CREATE DATABASE InventoryControl
    COLLATE Latin1_General_CI_AS;
GO
*/

USE InventoryControl;
GO

-- ============================================================================
-- SECTION 2: DROP EXISTING OBJECTS (For clean re-runs)
-- ============================================================================

-- Drop procedures first (they depend on tables)
IF EXISTS (SELECT * FROM sys.procedures WHERE name = 'usp_GenerateMonthlyInventoryReport')
    DROP PROCEDURE usp_GenerateMonthlyInventoryReport;
GO

IF EXISTS (SELECT * FROM sys.procedures WHERE name = 'usp_DetectLowStockItems')
    DROP PROCEDURE usp_DetectLowStockItems;
GO

IF EXISTS (SELECT * FROM sys.procedures WHERE name = 'usp_InsertInventoryTransaction')
    DROP PROCEDURE usp_InsertInventoryTransaction;
GO

-- Drop triggers (they depend on tables)
IF EXISTS (SELECT * FROM sys.triggers WHERE name = 'trg_UpdateProductStock_AfterInsert')
    DROP TRIGGER trg_UpdateProductStock_AfterInsert;
GO

-- Drop tables in dependency order
IF EXISTS (SELECT * FROM sys.tables WHERE name = 'LowStockAlerts')
    DROP TABLE LowStockAlerts;
GO

IF EXISTS (SELECT * FROM sys.tables WHERE name = 'InventoryTransactions')
    DROP TABLE InventoryTransactions;
GO

IF EXISTS (SELECT * FROM sys.tables WHERE name = 'Products')
    DROP TABLE Products;
GO

IF EXISTS (SELECT * FROM sys.tables WHERE name = 'ProductCategories')
    DROP TABLE ProductCategories;
GO

-- ============================================================================
-- SECTION 3: CREATE TABLES
-- ============================================================================

-- -----------------------------------------------------------------------------
-- Table: ProductCategories
-- Purpose: Lookup table for product categorization
-- -----------------------------------------------------------------------------
CREATE TABLE ProductCategories (
    CategoryID      INT IDENTITY(1,1)   NOT NULL,
    CategoryName    NVARCHAR(100)       NOT NULL,
    Description     NVARCHAR(500)       NULL,
    IsActive        BIT                 NOT NULL DEFAULT 1,
    CreatedAt       DATETIME2(3)        NOT NULL DEFAULT SYSDATETIME(),
    ModifiedAt      DATETIME2(3)        NOT NULL DEFAULT SYSDATETIME(),

    -- Constraints
    CONSTRAINT PK_ProductCategories PRIMARY KEY CLUSTERED (CategoryID),
    CONSTRAINT UQ_ProductCategories_Name UNIQUE (CategoryName)
);
GO

-- -----------------------------------------------------------------------------
-- Table: Products
-- Purpose: Core product master table with pricing, stock, and audit fields
-- -----------------------------------------------------------------------------
CREATE TABLE Products (
    ProductID           INT IDENTITY(1,1)       NOT NULL,
    SKU                 VARCHAR(50)             NOT NULL,           -- Stock Keeping Unit
    ProductName         NVARCHAR(200)           NOT NULL,
    Description         NVARCHAR(1000)          NULL,
    CategoryID          INT                     NULL,
    
    -- Pricing
    UnitCost            DECIMAL(18,4)           NOT NULL DEFAULT 0, -- Cost price
    UnitPrice           DECIMAL(18,4)           NOT NULL,           -- Selling price
    
    -- Stock Management
    StockQuantity       INT                     NOT NULL DEFAULT 0, -- Current stock level
    ReorderLevel        INT                     NOT NULL DEFAULT 10,-- Threshold for low stock alerts
    ReorderQuantity     INT                     NOT NULL DEFAULT 50,-- Suggested reorder amount
    
    -- Status
    IsActive            BIT                     NOT NULL DEFAULT 1,
    IsDiscontinued      BIT                     NOT NULL DEFAULT 0,
    
    -- Audit Timestamps
    CreatedAt           DATETIME2(3)            NOT NULL DEFAULT SYSDATETIME(),
    ModifiedAt          DATETIME2(3)            NOT NULL DEFAULT SYSDATETIME(),
    CreatedBy           NVARCHAR(128)           NOT NULL DEFAULT SYSTEM_USER,
    ModifiedBy          NVARCHAR(128)           NOT NULL DEFAULT SYSTEM_USER,

    -- Constraints
    CONSTRAINT PK_Products PRIMARY KEY CLUSTERED (ProductID),
    CONSTRAINT UQ_Products_SKU UNIQUE (SKU),
    CONSTRAINT FK_Products_Category FOREIGN KEY (CategoryID) 
        REFERENCES ProductCategories(CategoryID),
    CONSTRAINT CK_Products_UnitPrice_Positive CHECK (UnitPrice >= 0),
    CONSTRAINT CK_Products_UnitCost_Positive CHECK (UnitCost >= 0),
    CONSTRAINT CK_Products_StockQuantity_NonNegative CHECK (StockQuantity >= 0),
    CONSTRAINT CK_Products_ReorderLevel_Positive CHECK (ReorderLevel >= 0),
    CONSTRAINT CK_Products_ReorderQuantity_Positive CHECK (ReorderQuantity > 0)
);
GO

-- -----------------------------------------------------------------------------
-- Table: InventoryTransactions
-- Purpose: Transaction log for all stock movements (IN/OUT)
-- -----------------------------------------------------------------------------
CREATE TABLE InventoryTransactions (
    TransactionID       BIGINT IDENTITY(1,1)    NOT NULL,
    ProductID           INT                     NOT NULL,
    
    -- Transaction Details
    TransactionType     CHAR(3)                 NOT NULL,           -- 'IN' or 'OUT'
    Quantity            INT                     NOT NULL,           -- Always positive
    UnitCost            DECIMAL(18,4)           NULL,               -- Cost at time of transaction
    
    -- Reference Information
    ReferenceType       VARCHAR(50)             NULL,               -- PO, SO, ADJ, RET, etc.
    ReferenceNumber     VARCHAR(100)            NULL,               -- External reference
    Notes               NVARCHAR(500)           NULL,
    
    -- Audit Fields
    TransactionDate     DATETIME2(3)            NOT NULL DEFAULT SYSDATETIME(),
    CreatedBy           NVARCHAR(128)           NOT NULL DEFAULT SYSTEM_USER,
    
    -- Stock Snapshot (for audit trail)
    StockBefore         INT                     NULL,               -- Stock before this transaction
    StockAfter          INT                     NULL,               -- Stock after this transaction

    -- Constraints
    CONSTRAINT PK_InventoryTransactions PRIMARY KEY CLUSTERED (TransactionID),
    CONSTRAINT FK_InventoryTransactions_Product FOREIGN KEY (ProductID) 
        REFERENCES Products(ProductID),
    CONSTRAINT CK_InventoryTransactions_Type CHECK (TransactionType IN ('IN', 'OUT')),
    CONSTRAINT CK_InventoryTransactions_Quantity_Positive CHECK (Quantity > 0)
);
GO

-- -----------------------------------------------------------------------------
-- Table: LowStockAlerts
-- Purpose: Alert log for low stock notifications
-- -----------------------------------------------------------------------------
CREATE TABLE LowStockAlerts (
    AlertID             BIGINT IDENTITY(1,1)    NOT NULL,
    ProductID           INT                     NOT NULL,
    SKU                 VARCHAR(50)             NOT NULL,
    ProductName         NVARCHAR(200)           NOT NULL,
    
    -- Alert Details
    CurrentStock        INT                     NOT NULL,
    ReorderLevel        INT                     NOT NULL,
    StockDeficit        INT                     NOT NULL,           -- How much below threshold
    SuggestedReorder    INT                     NOT NULL,
    
    -- Alert Message
    AlertMessage        NVARCHAR(1000)          NOT NULL,
    AlertSeverity       VARCHAR(20)             NOT NULL DEFAULT 'WARNING', -- WARNING, CRITICAL
    
    -- Status
    IsAcknowledged      BIT                     NOT NULL DEFAULT 0,
    AcknowledgedAt      DATETIME2(3)            NULL,
    AcknowledgedBy      NVARCHAR(128)           NULL,
    
    -- Timestamps
    CreatedAt           DATETIME2(3)            NOT NULL DEFAULT SYSDATETIME(),

    -- Constraints
    CONSTRAINT PK_LowStockAlerts PRIMARY KEY CLUSTERED (AlertID),
    CONSTRAINT FK_LowStockAlerts_Product FOREIGN KEY (ProductID) 
        REFERENCES Products(ProductID),
    CONSTRAINT CK_LowStockAlerts_Severity CHECK (AlertSeverity IN ('WARNING', 'CRITICAL', 'INFO'))
);
GO

-- ============================================================================
-- SECTION 4: CREATE INDEXES
-- ============================================================================

-- Products table indexes
CREATE NONCLUSTERED INDEX IX_Products_CategoryID 
    ON Products(CategoryID) 
    WHERE IsActive = 1;

CREATE NONCLUSTERED INDEX IX_Products_StockQuantity 
    ON Products(StockQuantity, ReorderLevel) 
    INCLUDE (SKU, ProductName)
    WHERE IsActive = 1;

CREATE NONCLUSTERED INDEX IX_Products_ModifiedAt 
    ON Products(ModifiedAt DESC);

-- InventoryTransactions indexes (optimized for reporting)
CREATE NONCLUSTERED INDEX IX_InventoryTransactions_ProductID_Date 
    ON InventoryTransactions(ProductID, TransactionDate DESC)
    INCLUDE (TransactionType, Quantity);

CREATE NONCLUSTERED INDEX IX_InventoryTransactions_Date_Type 
    ON InventoryTransactions(TransactionDate, TransactionType)
    INCLUDE (ProductID, Quantity);

CREATE NONCLUSTERED INDEX IX_InventoryTransactions_Reference 
    ON InventoryTransactions(ReferenceType, ReferenceNumber)
    WHERE ReferenceNumber IS NOT NULL;

-- LowStockAlerts indexes
CREATE NONCLUSTERED INDEX IX_LowStockAlerts_ProductID 
    ON LowStockAlerts(ProductID, CreatedAt DESC);

CREATE NONCLUSTERED INDEX IX_LowStockAlerts_Unacknowledged 
    ON LowStockAlerts(CreatedAt DESC)
    WHERE IsAcknowledged = 0;

GO

-- ============================================================================
-- SECTION 5: CREATE TRIGGER - Auto-update Stock on Transaction Insert
-- ============================================================================

CREATE TRIGGER trg_UpdateProductStock_AfterInsert
ON InventoryTransactions
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @ErrorMessage NVARCHAR(4000);
    DECLARE @ErrorSeverity INT;
    
    BEGIN TRY
        -- Validate that stock won't go negative for OUT transactions
        IF EXISTS (
            SELECT 1
            FROM inserted i
            INNER JOIN Products p ON i.ProductID = p.ProductID
            WHERE i.TransactionType = 'OUT'
              AND p.StockQuantity < i.Quantity
        )
        BEGIN
            -- Get details for error message
            SELECT TOP 1 
                @ErrorMessage = CONCAT(
                    'Insufficient stock for Product ID: ', i.ProductID,
                    ' (SKU: ', p.SKU, '). ',
                    'Current Stock: ', p.StockQuantity,
                    ', Requested: ', i.Quantity
                )
            FROM inserted i
            INNER JOIN Products p ON i.ProductID = p.ProductID
            WHERE i.TransactionType = 'OUT'
              AND p.StockQuantity < i.Quantity;
            
            RAISERROR(@ErrorMessage, 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END
        
        -- First, capture stock before values
        UPDATE InventoryTransactions
        SET StockBefore = p.StockQuantity
        FROM InventoryTransactions it
        INNER JOIN inserted i ON it.TransactionID = i.TransactionID
        INNER JOIN Products p ON i.ProductID = p.ProductID;
        
        -- Update product stock quantities
        -- IN transactions: Add to stock
        UPDATE Products
        SET StockQuantity = StockQuantity + i.TotalIn,
            ModifiedAt = SYSDATETIME(),
            ModifiedBy = SYSTEM_USER
        FROM Products p
        INNER JOIN (
            SELECT ProductID, SUM(Quantity) AS TotalIn
            FROM inserted
            WHERE TransactionType = 'IN'
            GROUP BY ProductID
        ) i ON p.ProductID = i.ProductID;
        
        -- OUT transactions: Subtract from stock
        UPDATE Products
        SET StockQuantity = StockQuantity - o.TotalOut,
            ModifiedAt = SYSDATETIME(),
            ModifiedBy = SYSTEM_USER
        FROM Products p
        INNER JOIN (
            SELECT ProductID, SUM(Quantity) AS TotalOut
            FROM inserted
            WHERE TransactionType = 'OUT'
            GROUP BY ProductID
        ) o ON p.ProductID = o.ProductID;
        
        -- Update stock after values
        UPDATE InventoryTransactions
        SET StockAfter = p.StockQuantity
        FROM InventoryTransactions it
        INNER JOIN inserted i ON it.TransactionID = i.TransactionID
        INNER JOIN Products p ON i.ProductID = p.ProductID;
        
    END TRY
    BEGIN CATCH
        SET @ErrorMessage = ERROR_MESSAGE();
        SET @ErrorSeverity = ERROR_SEVERITY();
        
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
            
        RAISERROR(@ErrorMessage, @ErrorSeverity, 1);
    END CATCH
END
GO

-- ============================================================================
-- SECTION 6: CREATE STORED PROCEDURE - Insert Inventory Transaction (Safe)
-- ============================================================================

CREATE PROCEDURE usp_InsertInventoryTransaction
    @ProductID          INT,
    @TransactionType    CHAR(3),
    @Quantity           INT,
    @UnitCost           DECIMAL(18,4) = NULL,
    @ReferenceType      VARCHAR(50) = NULL,
    @ReferenceNumber    VARCHAR(100) = NULL,
    @Notes              NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    
    DECLARE @TransactionID BIGINT;
    DECLARE @ErrorMessage NVARCHAR(4000);
    
    BEGIN TRY
        -- Input validation
        IF @ProductID IS NULL
        BEGIN
            RAISERROR('Product ID cannot be NULL.', 16, 1);
            RETURN -1;
        END
        
        IF @TransactionType NOT IN ('IN', 'OUT')
        BEGIN
            RAISERROR('Transaction type must be IN or OUT.', 16, 1);
            RETURN -1;
        END
        
        IF @Quantity <= 0
        BEGIN
            RAISERROR('Quantity must be a positive number.', 16, 1);
            RETURN -1;
        END
        
        -- Check if product exists
        IF NOT EXISTS (SELECT 1 FROM Products WHERE ProductID = @ProductID)
        BEGIN
            SET @ErrorMessage = CONCAT('Product ID ', @ProductID, ' does not exist.');
            RAISERROR(@ErrorMessage, 16, 1);
            RETURN -1;
        END
        
        -- Check stock availability for OUT transactions
        IF @TransactionType = 'OUT'
        BEGIN
            DECLARE @CurrentStock INT;
            SELECT @CurrentStock = StockQuantity FROM Products WHERE ProductID = @ProductID;
            
            IF @CurrentStock < @Quantity
            BEGIN
                SET @ErrorMessage = CONCAT(
                    'Insufficient stock. Available: ', @CurrentStock, 
                    ', Requested: ', @Quantity
                );
                RAISERROR(@ErrorMessage, 16, 1);
                RETURN -1;
            END
        END
        
        BEGIN TRANSACTION;
        
            -- Insert the transaction (trigger will handle stock update)
            INSERT INTO InventoryTransactions (
                ProductID,
                TransactionType,
                Quantity,
                UnitCost,
                ReferenceType,
                ReferenceNumber,
                Notes
            )
            VALUES (
                @ProductID,
                @TransactionType,
                @Quantity,
                @UnitCost,
                @ReferenceType,
                @ReferenceNumber,
                @Notes
            );
            
            SET @TransactionID = SCOPE_IDENTITY();
        
        COMMIT TRANSACTION;
        
        -- Return the new transaction ID
        SELECT @TransactionID AS TransactionID;
        RETURN 0;
        
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
            
        SET @ErrorMessage = ERROR_MESSAGE();
        RAISERROR(@ErrorMessage, 16, 1);
        RETURN -1;
    END CATCH
END
GO

-- ============================================================================
-- SECTION 7: CREATE STORED PROCEDURE - Monthly Inventory Movement Report
-- ============================================================================

CREATE PROCEDURE usp_GenerateMonthlyInventoryReport
    @Year       INT,
    @Month      INT,
    @CategoryID INT = NULL  -- Optional filter by category
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @StartDate DATETIME2(3);
    DECLARE @EndDate DATETIME2(3);
    DECLARE @ErrorMessage NVARCHAR(4000);
    
    BEGIN TRY
        -- Input validation
        IF @Year < 2000 OR @Year > 2100
        BEGIN
            RAISERROR('Year must be between 2000 and 2100.', 16, 1);
            RETURN -1;
        END
        
        IF @Month < 1 OR @Month > 12
        BEGIN
            RAISERROR('Month must be between 1 and 12.', 16, 1);
            RETURN -1;
        END
        
        -- Calculate date range for the specified month
        SET @StartDate = DATEFROMPARTS(@Year, @Month, 1);
        SET @EndDate = DATEADD(MONTH, 1, @StartDate);
        
        -- Main report query with optimized CTE approach
        ;WITH TransactionSummary AS (
            SELECT 
                p.ProductID,
                p.SKU,
                p.ProductName,
                pc.CategoryName,
                p.UnitPrice,
                p.StockQuantity AS CurrentStock,
                p.ReorderLevel,
                
                -- Stock IN for the month
                ISNULL(SUM(CASE 
                    WHEN it.TransactionType = 'IN' 
                    AND it.TransactionDate >= @StartDate 
                    AND it.TransactionDate < @EndDate 
                    THEN it.Quantity 
                END), 0) AS TotalStockIn,
                
                -- Stock OUT for the month
                ISNULL(SUM(CASE 
                    WHEN it.TransactionType = 'OUT' 
                    AND it.TransactionDate >= @StartDate 
                    AND it.TransactionDate < @EndDate 
                    THEN it.Quantity 
                END), 0) AS TotalStockOut,
                
                -- Transaction counts
                COUNT(CASE 
                    WHEN it.TransactionType = 'IN' 
                    AND it.TransactionDate >= @StartDate 
                    AND it.TransactionDate < @EndDate 
                    THEN 1 
                END) AS InTransactionCount,
                
                COUNT(CASE 
                    WHEN it.TransactionType = 'OUT' 
                    AND it.TransactionDate >= @StartDate 
                    AND it.TransactionDate < @EndDate 
                    THEN 1 
                END) AS OutTransactionCount,
                
                -- Value calculations
                ISNULL(SUM(CASE 
                    WHEN it.TransactionType = 'IN' 
                    AND it.TransactionDate >= @StartDate 
                    AND it.TransactionDate < @EndDate 
                    THEN it.Quantity * ISNULL(it.UnitCost, p.UnitCost)
                END), 0) AS TotalStockInValue,
                
                ISNULL(SUM(CASE 
                    WHEN it.TransactionType = 'OUT' 
                    AND it.TransactionDate >= @StartDate 
                    AND it.TransactionDate < @EndDate 
                    THEN it.Quantity * p.UnitPrice
                END), 0) AS TotalStockOutValue
                
            FROM Products p
            LEFT JOIN ProductCategories pc ON p.CategoryID = pc.CategoryID
            LEFT JOIN InventoryTransactions it ON p.ProductID = it.ProductID
            WHERE p.IsActive = 1
              AND (@CategoryID IS NULL OR p.CategoryID = @CategoryID)
            GROUP BY 
                p.ProductID,
                p.SKU,
                p.ProductName,
                pc.CategoryName,
                p.UnitPrice,
                p.StockQuantity,
                p.ReorderLevel
        )
        SELECT 
            ProductID,
            SKU,
            ProductName,
            ISNULL(CategoryName, 'Uncategorized') AS Category,
            TotalStockIn,
            TotalStockOut,
            (TotalStockIn - TotalStockOut) AS NetMovement,
            CurrentStock,
            InTransactionCount,
            OutTransactionCount,
            (InTransactionCount + OutTransactionCount) AS TotalTransactions,
            FORMAT(TotalStockInValue, 'C') AS StockInValue,
            FORMAT(TotalStockOutValue, 'C') AS StockOutValue,
            FORMAT((TotalStockOutValue - TotalStockInValue), 'C') AS GrossProfit,
            CASE 
                WHEN CurrentStock <= 0 THEN 'OUT OF STOCK'
                WHEN CurrentStock < ReorderLevel THEN 'LOW STOCK'
                ELSE 'NORMAL'
            END AS StockStatus,
            ReorderLevel
        FROM TransactionSummary
        ORDER BY TotalStockOut DESC, ProductName;
        
        -- Summary section
        SELECT 
            @Year AS ReportYear,
            @Month AS ReportMonth,
            DATENAME(MONTH, @StartDate) AS MonthName,
            COUNT(DISTINCT p.ProductID) AS TotalProducts,
            SUM(CASE WHEN p.StockQuantity <= 0 THEN 1 ELSE 0 END) AS OutOfStockProducts,
            SUM(CASE WHEN p.StockQuantity > 0 AND p.StockQuantity < p.ReorderLevel THEN 1 ELSE 0 END) AS LowStockProducts,
            ISNULL(SUM(it.TotalIn), 0) AS GrandTotalStockIn,
            ISNULL(SUM(it.TotalOut), 0) AS GrandTotalStockOut,
            SUM(p.StockQuantity) AS TotalCurrentInventory,
            FORMAT(SUM(p.StockQuantity * p.UnitCost), 'C') AS TotalInventoryValue
        FROM Products p
        LEFT JOIN ProductCategories pc ON p.CategoryID = pc.CategoryID
        LEFT JOIN (
            SELECT 
                ProductID,
                SUM(CASE WHEN TransactionType = 'IN' THEN Quantity ELSE 0 END) AS TotalIn,
                SUM(CASE WHEN TransactionType = 'OUT' THEN Quantity ELSE 0 END) AS TotalOut
            FROM InventoryTransactions
            WHERE TransactionDate >= @StartDate AND TransactionDate < @EndDate
            GROUP BY ProductID
        ) it ON p.ProductID = it.ProductID
        WHERE p.IsActive = 1
          AND (@CategoryID IS NULL OR p.CategoryID = @CategoryID);
        
        RETURN 0;
        
    END TRY
    BEGIN CATCH
        SET @ErrorMessage = ERROR_MESSAGE();
        RAISERROR(@ErrorMessage, 16, 1);
        RETURN -1;
    END CATCH
END
GO

-- ============================================================================
-- SECTION 8: CREATE STORED PROCEDURE - Low Stock Detection (Cursor-Based)
-- ============================================================================

CREATE PROCEDURE usp_DetectLowStockItems
    @ThresholdOverride  INT = NULL,     -- Optional: Override default reorder levels
    @SeverityFilter     VARCHAR(20) = NULL  -- Optional: 'WARNING' or 'CRITICAL' only
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Cursor variables
    DECLARE @ProductID INT;
    DECLARE @SKU VARCHAR(50);
    DECLARE @ProductName NVARCHAR(200);
    DECLARE @CurrentStock INT;
    DECLARE @ReorderLevel INT;
    DECLARE @ReorderQuantity INT;
    DECLARE @StockDeficit INT;
    DECLARE @AlertMessage NVARCHAR(1000);
    DECLARE @AlertSeverity VARCHAR(20);
    DECLARE @EffectiveThreshold INT;
    
    -- Counter variables
    DECLARE @AlertsCreated INT = 0;
    DECLARE @WarningCount INT = 0;
    DECLARE @CriticalCount INT = 0;
    
    DECLARE @ErrorMessage NVARCHAR(4000);
    
    BEGIN TRY
        BEGIN TRANSACTION;
        
        -- Declare cursor for all active products with stock issues
        DECLARE LowStockCursor CURSOR LOCAL FAST_FORWARD FOR
            SELECT 
                ProductID,
                SKU,
                ProductName,
                StockQuantity,
                ReorderLevel,
                ReorderQuantity
            FROM Products
            WHERE IsActive = 1
              AND IsDiscontinued = 0
              AND StockQuantity < ISNULL(@ThresholdOverride, ReorderLevel)
            ORDER BY 
                -- Prioritize by severity (out of stock first, then by deficit)
                CASE WHEN StockQuantity <= 0 THEN 0 ELSE 1 END,
                (ISNULL(@ThresholdOverride, ReorderLevel) - StockQuantity) DESC;
        
        OPEN LowStockCursor;
        
        FETCH NEXT FROM LowStockCursor 
        INTO @ProductID, @SKU, @ProductName, @CurrentStock, 
             @ReorderLevel, @ReorderQuantity;
        
        -- Iterate through all low stock items
        WHILE @@FETCH_STATUS = 0
        BEGIN
            -- Calculate effective threshold
            SET @EffectiveThreshold = ISNULL(@ThresholdOverride, @ReorderLevel);
            SET @StockDeficit = @EffectiveThreshold - @CurrentStock;
            
            -- Determine alert severity
            SET @AlertSeverity = CASE
                WHEN @CurrentStock <= 0 THEN 'CRITICAL'
                WHEN @CurrentStock <= (@EffectiveThreshold / 2) THEN 'CRITICAL'
                ELSE 'WARNING'
            END;
            
            -- Check if we should skip based on severity filter
            IF @SeverityFilter IS NULL OR @AlertSeverity = @SeverityFilter
            BEGIN
                -- Build alert message
                SET @AlertMessage = CONCAT(
                    '[', @AlertSeverity, '] Low stock alert for ', @ProductName,
                    ' (SKU: ', @SKU, '). ',
                    'Current stock: ', @CurrentStock, ' units. ',
                    'Reorder level: ', @EffectiveThreshold, ' units. ',
                    'Deficit: ', @StockDeficit, ' units. ',
                    'Recommended reorder quantity: ', 
                    CASE 
                        WHEN @CurrentStock <= 0 THEN @ReorderQuantity * 2  -- Double for out of stock
                        ELSE @ReorderQuantity 
                    END, ' units.'
                );
                
                -- Check if a similar unacknowledged alert already exists (avoid duplicates)
                IF NOT EXISTS (
                    SELECT 1 
                    FROM LowStockAlerts 
                    WHERE ProductID = @ProductID 
                      AND IsAcknowledged = 0
                      AND CAST(CreatedAt AS DATE) = CAST(SYSDATETIME() AS DATE)
                )
                BEGIN
                    -- Insert alert record
                    INSERT INTO LowStockAlerts (
                        ProductID,
                        SKU,
                        ProductName,
                        CurrentStock,
                        ReorderLevel,
                        StockDeficit,
                        SuggestedReorder,
                        AlertMessage,
                        AlertSeverity
                    )
                    VALUES (
                        @ProductID,
                        @SKU,
                        @ProductName,
                        @CurrentStock,
                        @EffectiveThreshold,
                        @StockDeficit,
                        CASE 
                            WHEN @CurrentStock <= 0 THEN @ReorderQuantity * 2
                            ELSE @ReorderQuantity 
                        END,
                        @AlertMessage,
                        @AlertSeverity
                    );
                    
                    SET @AlertsCreated = @AlertsCreated + 1;
                    
                    IF @AlertSeverity = 'CRITICAL'
                        SET @CriticalCount = @CriticalCount + 1;
                    ELSE
                        SET @WarningCount = @WarningCount + 1;
                    
                    -- Print alert to messages (for SSMS display)
                    PRINT @AlertMessage;
                END
            END
            
            FETCH NEXT FROM LowStockCursor 
            INTO @ProductID, @SKU, @ProductName, @CurrentStock, 
                 @ReorderLevel, @ReorderQuantity;
        END
        
        CLOSE LowStockCursor;
        DEALLOCATE LowStockCursor;
        
        COMMIT TRANSACTION;
        
        -- Return summary
        SELECT 
            @AlertsCreated AS TotalAlertsCreated,
            @CriticalCount AS CriticalAlerts,
            @WarningCount AS WarningAlerts,
            SYSDATETIME() AS ProcessedAt;
        
        -- Return the alerts created in this run
        IF @AlertsCreated > 0
        BEGIN
            SELECT 
                AlertID,
                SKU,
                ProductName,
                CurrentStock,
                ReorderLevel,
                StockDeficit,
                SuggestedReorder,
                AlertSeverity,
                AlertMessage,
                CreatedAt
            FROM LowStockAlerts
            WHERE CAST(CreatedAt AS DATE) = CAST(SYSDATETIME() AS DATE)
              AND IsAcknowledged = 0
            ORDER BY 
                CASE AlertSeverity WHEN 'CRITICAL' THEN 1 ELSE 2 END,
                StockDeficit DESC;
        END
        
        RETURN 0;
        
    END TRY
    BEGIN CATCH
        IF CURSOR_STATUS('local', 'LowStockCursor') >= 0
        BEGIN
            CLOSE LowStockCursor;
            DEALLOCATE LowStockCursor;
        END
        
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
            
        SET @ErrorMessage = ERROR_MESSAGE();
        RAISERROR(@ErrorMessage, 16, 1);
        RETURN -1;
    END CATCH
END
GO

-- ============================================================================
-- SECTION 9: INSERT SAMPLE DATA
-- ============================================================================

PRINT 'Inserting sample data...';
GO

-- Insert product categories
INSERT INTO ProductCategories (CategoryName, Description)
VALUES 
    ('Electronics', 'Electronic devices and components'),
    ('Office Supplies', 'General office supplies and stationery'),
    ('Furniture', 'Office and warehouse furniture'),
    ('Industrial Equipment', 'Heavy machinery and industrial tools'),
    ('Packaging Materials', 'Boxes, tape, and packaging supplies');
GO

-- Insert sample products
SET IDENTITY_INSERT Products OFF;

INSERT INTO Products (SKU, ProductName, Description, CategoryID, UnitCost, UnitPrice, StockQuantity, ReorderLevel, ReorderQuantity)
VALUES 
    -- Electronics
    ('ELEC-001', 'Wireless Mouse', 'Ergonomic wireless mouse with USB receiver', 1, 12.50, 24.99, 150, 25, 100),
    ('ELEC-002', 'USB-C Hub', '7-port USB-C hub with HDMI output', 1, 35.00, 69.99, 75, 20, 50),
    ('ELEC-003', 'Mechanical Keyboard', 'RGB mechanical gaming keyboard', 1, 45.00, 89.99, 40, 15, 30),
    ('ELEC-004', 'Webcam HD', '1080p HD webcam with microphone', 1, 28.00, 54.99, 8, 20, 40),
    ('ELEC-005', '27" Monitor', '27 inch 4K IPS Monitor', 1, 250.00, 449.99, 12, 10, 20),
    
    -- Office Supplies
    ('OFFC-001', 'A4 Paper Ream', '500 sheets, 80gsm white paper', 2, 3.50, 7.99, 500, 100, 200),
    ('OFFC-002', 'Ballpoint Pens (12pk)', 'Blue ballpoint pens, pack of 12', 2, 2.00, 5.99, 200, 50, 100),
    ('OFFC-003', 'Stapler Heavy Duty', 'Industrial stapler, 100 sheet capacity', 2, 15.00, 29.99, 45, 10, 25),
    ('OFFC-004', 'Whiteboard Markers', 'Assorted colors, pack of 8', 2, 4.00, 9.99, 180, 30, 60),
    ('OFFC-005', 'Document Folders', 'Plastic folders, pack of 25', 2, 8.00, 18.99, 5, 15, 50),
    
    -- Furniture
    ('FURN-001', 'Office Chair Ergonomic', 'Adjustable ergonomic office chair', 3, 180.00, 349.99, 25, 5, 15),
    ('FURN-002', 'Standing Desk', 'Electric height-adjustable desk', 3, 350.00, 699.99, 8, 3, 10),
    ('FURN-003', 'Filing Cabinet 3-Drawer', 'Metal filing cabinet with lock', 3, 120.00, 229.99, 15, 5, 10),
    
    -- Industrial Equipment
    ('INDL-001', 'Pallet Jack', 'Manual hydraulic pallet jack', 4, 250.00, 449.99, 6, 2, 5),
    ('INDL-002', 'Safety Goggles (12pk)', 'ANSI-rated safety goggles', 4, 24.00, 49.99, 30, 10, 25),
    ('INDL-003', 'Power Drill', 'Cordless 20V power drill', 4, 85.00, 159.99, 0, 8, 15),
    
    -- Packaging Materials
    ('PACK-001', 'Cardboard Boxes (Large)', 'Large shipping boxes, 50 pack', 5, 45.00, 89.99, 60, 20, 50),
    ('PACK-002', 'Packing Tape', 'Heavy duty packing tape, 6 rolls', 5, 12.00, 24.99, 150, 30, 75),
    ('PACK-003', 'Bubble Wrap Roll', '100ft bubble wrap roll', 5, 18.00, 34.99, 25, 10, 30),
    ('PACK-004', 'Shipping Labels', 'Self-adhesive labels, 500 pack', 5, 15.00, 32.99, 3, 10, 30);
GO

-- Insert sample inventory transactions
PRINT 'Inserting sample transactions...';

-- Disable trigger temporarily to set historical dates
DISABLE TRIGGER trg_UpdateProductStock_AfterInsert ON InventoryTransactions;
GO

-- Insert historical transactions (last 2 months)
DECLARE @BaseDate DATE = DATEADD(MONTH, -2, GETDATE());

INSERT INTO InventoryTransactions (ProductID, TransactionType, Quantity, UnitCost, ReferenceType, ReferenceNumber, TransactionDate, Notes)
VALUES 
    -- Stock IN transactions (Purchase Orders)
    (1, 'IN', 200, 12.50, 'PO', 'PO-2026-001', DATEADD(DAY, 1, @BaseDate), 'Initial stock purchase'),
    (2, 'IN', 100, 35.00, 'PO', 'PO-2026-001', DATEADD(DAY, 1, @BaseDate), 'Initial stock purchase'),
    (3, 'IN', 50, 45.00, 'PO', 'PO-2026-002', DATEADD(DAY, 5, @BaseDate), 'Keyboard restock'),
    (6, 'IN', 600, 3.50, 'PO', 'PO-2026-003', DATEADD(DAY, 10, @BaseDate), 'Paper bulk order'),
    (11, 'IN', 30, 180.00, 'PO', 'PO-2026-004', DATEADD(DAY, 15, @BaseDate), 'Office chair restock'),
    (17, 'IN', 100, 45.00, 'PO', 'PO-2026-005', DATEADD(DAY, 20, @BaseDate), 'Boxes bulk order'),
    
    -- Stock OUT transactions (Sales Orders)
    (1, 'OUT', 50, NULL, 'SO', 'SO-2026-001', DATEADD(DAY, 8, @BaseDate), 'Customer order fulfilled'),
    (2, 'OUT', 25, NULL, 'SO', 'SO-2026-002', DATEADD(DAY, 12, @BaseDate), 'Corporate bulk sale'),
    (6, 'OUT', 100, NULL, 'SO', 'SO-2026-003', DATEADD(DAY, 18, @BaseDate), 'Office supplies order'),
    (11, 'OUT', 5, NULL, 'SO', 'SO-2026-004', DATEADD(DAY, 25, @BaseDate), 'Furniture order'),
    
    -- Adjustments
    (4, 'OUT', 12, NULL, 'ADJ', 'ADJ-001', DATEADD(DAY, 30, @BaseDate), 'Damaged units written off'),
    (16, 'OUT', 15, NULL, 'ADJ', 'ADJ-002', DATEADD(DAY, 35, @BaseDate), 'All remaining stock transferred out'),
    
    -- Returns
    (3, 'IN', 5, 45.00, 'RET', 'RET-001', DATEADD(DAY, 40, @BaseDate), 'Customer return - defective claim'),
    
    -- Recent transactions (current month)
    (7, 'IN', 100, 2.00, 'PO', 'PO-2026-010', DATEADD(DAY, -7, GETDATE()), 'Pen restock'),
    (8, 'OUT', 5, NULL, 'SO', 'SO-2026-015', DATEADD(DAY, -5, GETDATE()), 'Office supplies order'),
    (18, 'OUT', 50, NULL, 'SO', 'SO-2026-016', DATEADD(DAY, -3, GETDATE()), 'Bulk tape order'),
    (17, 'OUT', 40, NULL, 'SO', 'SO-2026-017', DATEADD(DAY, -1, GETDATE()), 'Warehouse shipping order');
GO

-- Re-enable trigger
ENABLE TRIGGER trg_UpdateProductStock_AfterInsert ON InventoryTransactions;
GO

PRINT 'Sample data inserted successfully.';
GO

-- ============================================================================
-- SECTION 10: VERIFICATION & TESTING QUERIES
-- ============================================================================

PRINT '==================================================================';
PRINT 'VERIFICATION TESTS';
PRINT '==================================================================';
GO

-- Test 1: View all products with current stock
PRINT '';
PRINT '--- TEST 1: Products Overview ---';
SELECT 
    p.ProductID,
    p.SKU,
    p.ProductName,
    pc.CategoryName,
    p.StockQuantity,
    p.ReorderLevel,
    CASE 
        WHEN p.StockQuantity <= 0 THEN 'OUT OF STOCK'
        WHEN p.StockQuantity < p.ReorderLevel THEN 'LOW STOCK'
        ELSE 'OK'
    END AS StockStatus,
    FORMAT(p.UnitPrice, 'C') AS UnitPrice,
    FORMAT(p.StockQuantity * p.UnitCost, 'C') AS InventoryValue
FROM Products p
LEFT JOIN ProductCategories pc ON p.CategoryID = pc.CategoryID
WHERE p.IsActive = 1
ORDER BY p.SKU;
GO

-- Test 2: Test trigger with IN transaction
PRINT '';
PRINT '--- TEST 2: Testing Stock IN Transaction ---';
EXEC usp_InsertInventoryTransaction 
    @ProductID = 1, 
    @TransactionType = 'IN', 
    @Quantity = 25, 
    @UnitCost = 12.50,
    @ReferenceType = 'PO',
    @ReferenceNumber = 'PO-2026-TEST',
    @Notes = 'Test purchase order';
GO

-- Verify stock was updated
SELECT SKU, ProductName, StockQuantity 
FROM Products 
WHERE ProductID = 1;
GO

-- Test 3: Test trigger with OUT transaction
PRINT '';
PRINT '--- TEST 3: Testing Stock OUT Transaction ---';
EXEC usp_InsertInventoryTransaction 
    @ProductID = 1, 
    @TransactionType = 'OUT', 
    @Quantity = 10,
    @ReferenceType = 'SO',
    @ReferenceNumber = 'SO-2026-TEST',
    @Notes = 'Test sales order';
GO

-- Verify stock was reduced
SELECT SKU, ProductName, StockQuantity 
FROM Products 
WHERE ProductID = 1;
GO

-- Test 4: Test negative stock prevention
PRINT '';
PRINT '--- TEST 4: Testing Negative Stock Prevention ---';
PRINT 'Attempting to remove more stock than available (should fail)...';
BEGIN TRY
    EXEC usp_InsertInventoryTransaction 
        @ProductID = 16,  -- Power Drill has 0 stock
        @TransactionType = 'OUT', 
        @Quantity = 5;
    PRINT 'ERROR: Transaction should have been rejected!';
END TRY
BEGIN CATCH
    PRINT CONCAT('SUCCESS: Transaction correctly rejected - ', ERROR_MESSAGE());
END CATCH
GO

-- Test 5: View transaction log
PRINT '';
PRINT '--- TEST 5: Recent Transaction Log ---';
SELECT TOP 10
    it.TransactionID,
    p.SKU,
    it.TransactionType,
    it.Quantity,
    it.StockBefore,
    it.StockAfter,
    it.ReferenceType,
    it.ReferenceNumber,
    it.TransactionDate
FROM InventoryTransactions it
INNER JOIN Products p ON it.ProductID = p.ProductID
ORDER BY it.TransactionDate DESC;
GO

-- Test 6: Run monthly report
PRINT '';
PRINT '--- TEST 6: Monthly Inventory Report (Current Month) ---';
EXEC usp_GenerateMonthlyInventoryReport 
    @Year = 2026, 
    @Month = 2;
GO

-- Test 7: Run low stock detection
PRINT '';
PRINT '--- TEST 7: Low Stock Detection ---';
EXEC usp_DetectLowStockItems;
GO

-- View generated alerts
PRINT '';
PRINT '--- Generated Low Stock Alerts ---';
SELECT 
    AlertID,
    SKU,
    ProductName,
    AlertSeverity,
    CurrentStock,
    ReorderLevel,
    SuggestedReorder,
    CreatedAt
FROM LowStockAlerts
WHERE IsAcknowledged = 0
ORDER BY 
    CASE AlertSeverity WHEN 'CRITICAL' THEN 1 ELSE 2 END,
    StockDeficit DESC;
GO

PRINT '';
PRINT '==================================================================';
PRINT 'DATABASE SETUP COMPLETE';
PRINT '==================================================================';
PRINT 'Objects created:';
PRINT '  - 4 Tables: ProductCategories, Products, InventoryTransactions, LowStockAlerts';
PRINT '  - 8 Indexes for optimized queries';
PRINT '  - 1 Trigger: trg_UpdateProductStock_AfterInsert';
PRINT '  - 3 Stored Procedures:';
PRINT '      * usp_InsertInventoryTransaction - Safe transaction insertion';
PRINT '      * usp_GenerateMonthlyInventoryReport - Monthly reporting';
PRINT '      * usp_DetectLowStockItems - Cursor-based low stock detection';
PRINT '';
PRINT 'Sample data includes:';
PRINT '  - 5 Product Categories';
PRINT '  - 20 Products across categories';
PRINT '  - Historical transaction records';
PRINT '';
PRINT 'Ready for production use!';
GO
