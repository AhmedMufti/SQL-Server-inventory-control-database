# SQL Server Inventory Control Database

A complete inventory management database built with T-SQL. Handles products, stock movements, reporting, and low-stock alerts.

## What's Included

- **Tables**: Products, categories, transaction log, and alerts
- **Trigger**: Automatically updates stock when transactions are inserted, blocks negative stock
- **Stored Procedures**:
  - `usp_InsertInventoryTransaction` — safely insert stock IN/OUT movements
  - `usp_GenerateMonthlyInventoryReport` — monthly stock movement summary
  - `usp_DetectLowStockItems` — finds products below reorder level and logs alerts
- **Sample Data**: 20 products across 5 categories with 2 months of transaction history

## Requirements

- SQL Server 2019+
- SSMS or any SQL client

## Setup

1. Open `InventoryControlDatabase.sql` in SSMS
2. If you need a new database, uncomment the creation block at the top
3. Run the script (F5)

The script includes test queries at the end so you can verify everything works.

## Usage

**Add stock:**
```sql
EXEC usp_InsertInventoryTransaction 
    @ProductID = 1, 
    @TransactionType = 'IN', 
    @Quantity = 100, 
    @ReferenceType = 'PO',
    @ReferenceNumber = 'PO-2026-001';
```

**Remove stock:**
```sql
EXEC usp_InsertInventoryTransaction 
    @ProductID = 1, 
    @TransactionType = 'OUT', 
    @Quantity = 25,
    @ReferenceType = 'SO',
    @ReferenceNumber = 'SO-2026-001';
```

**Monthly report:**
```sql
EXEC usp_GenerateMonthlyInventoryReport @Year = 2026, @Month = 2;
```

**Check low stock:**
```sql
EXEC usp_DetectLowStockItems;
```

## Schema

```
ProductCategories (1) ──── (*) Products (1) ──┬── (*) InventoryTransactions
                                              └── (*) LowStockAlerts
```

- `Products` tracks SKU, pricing, current stock, and reorder thresholds
- `InventoryTransactions` logs every stock movement with before/after snapshots
- `LowStockAlerts` stores warnings when stock drops below reorder level

## Notes

- The trigger prevents negative stock — if you try to withdraw more than available, the transaction rolls back
- Low stock detection uses a cursor to iterate products (as requested), though a set-based approach would be faster at scale
- All procedures have error handling with try/catch

## License

MIT
