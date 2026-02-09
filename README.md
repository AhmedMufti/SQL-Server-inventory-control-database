# SQL Server Inventory Control Database

A production-ready SQL Server inventory control database implementation.

## Features
- **Relational Schema**: Products, Categories, Transactions, and Alerts.
- **Automated Stock Tracking**: Triggers to handle stock movement and prevent negative stock.
- **Stored Procedures**:
  - `usp_InsertInventoryTransaction`: Safe entry for stock movements.
  - `usp_GenerateMonthlyInventoryReport`: Detailed monthly stock analysis.
  - `usp_DetectLowStockItems`: Cursor-based alerting system.
- **Reporting**: Monthly movement reports with net movement and gross profit estimates.
- **Performance**: Optimized with specific indexes and best practices.

## Installation
1. Open `InventoryControlDatabase.sql` in SQL Server Management Studio (SSMS).
2. Execute the script to create the schema, logic, and sample data.
3. Use the verification tests at the bottom of the script to validate functionality.
