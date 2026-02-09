# 📦 SQL Server Inventory Control Database

[![SQL Server](https://img.shields.io/badge/SQL%20Server-2019+-CC2927?style=for-the-badge&logo=microsoftsqlserver&logoColor=white)](https://www.microsoft.com/sql-server)
[![T-SQL](https://img.shields.io/badge/T--SQL-Pure-blue?style=for-the-badge)](https://docs.microsoft.com/en-us/sql/t-sql/)
[![License](https://img.shields.io/badge/License-MIT-green?style=for-the-badge)](LICENSE)

A **production-ready**, enterprise-grade inventory control database built with pure T-SQL. Designed for real-world inventory management with automated stock tracking, comprehensive reporting, and intelligent alerting.

---

## ✨ Features

### 🗄️ Robust Schema Design
- **Products** — SKU, pricing (cost/sale), stock quantities, reorder thresholds, audit timestamps
- **Product Categories** — Hierarchical product organization
- **Inventory Transactions** — Complete audit trail of all IN/OUT stock movements
- **Low Stock Alerts** — Automated warning system with severity levels

### ⚡ Automated Stock Management
- **Real-time Updates** — Triggers automatically adjust stock on every transaction
- **Negative Stock Prevention** — Built-in validation blocks invalid withdrawals
- **Audit Snapshots** — Every transaction captures before/after stock levels

### 📊 Reporting & Analytics
- **Monthly Movement Reports** — Parameterized by year, month, and category
- **Stock Valuation** — Real-time inventory value calculations
- **Transaction Summaries** — IN/OUT counts with gross profit estimates

### 🔔 Intelligent Alerting
- **Cursor-Based Detection** — Iterates through products to identify low stock
- **Severity Classification** — WARNING and CRITICAL alert levels
- **Duplicate Prevention** — Avoids redundant alerts for the same items

### 🛡️ Enterprise Best Practices
- Comprehensive error handling with `TRY...CATCH`
- Transaction management with atomic rollbacks
- Optimized indexing strategy for performance
- Data validation through CHECK constraints
- Full audit trail with user tracking

---

## 🏗️ Database Schema

```
┌─────────────────────┐     ┌─────────────────────────────┐
│  ProductCategories  │     │          Products           │
├─────────────────────┤     ├─────────────────────────────┤
│ CategoryID (PK)     │◄────│ CategoryID (FK)             │
│ CategoryName        │     │ ProductID (PK)              │
│ Description         │     │ SKU (Unique)                │
│ IsActive            │     │ ProductName                 │
│ CreatedAt           │     │ UnitCost / UnitPrice        │
│ ModifiedAt          │     │ StockQuantity               │
└─────────────────────┘     │ ReorderLevel / ReorderQty   │
                            │ CreatedAt / ModifiedAt      │
                            └──────────────┬──────────────┘
                                           │
                    ┌──────────────────────┼──────────────────────┐
                    ▼                      ▼                      │
┌─────────────────────────────┐  ┌─────────────────────────┐     │
│  InventoryTransactions      │  │    LowStockAlerts       │     │
├─────────────────────────────┤  ├─────────────────────────┤     │
│ TransactionID (PK)          │  │ AlertID (PK)            │     │
│ ProductID (FK)              │  │ ProductID (FK)          │◄────┘
│ TransactionType (IN/OUT)    │  │ SKU / ProductName       │
│ Quantity                    │  │ CurrentStock            │
│ UnitCost                    │  │ StockDeficit            │
│ ReferenceType / Number      │  │ AlertSeverity           │
│ StockBefore / StockAfter    │  │ AlertMessage            │
│ TransactionDate             │  │ IsAcknowledged          │
└─────────────────────────────┘  └─────────────────────────┘
```

---

## 🚀 Quick Start

### Prerequisites
- SQL Server 2019 or later
- SQL Server Management Studio (SSMS)

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/AhmedMufti/SQL-Server-inventory-control-database.git
   ```

2. **Open in SSMS**
   - Launch SQL Server Management Studio
   - Connect to your SQL Server instance
   - Open `InventoryControlDatabase.sql`

3. **Create the database** *(optional)*
   - Uncomment the database creation block in Section 1
   - Execute it separately first

4. **Run the full script**
   - Press `F5` or click Execute
   - The script includes verification tests that run automatically

---

## 📖 Usage Examples

### Insert a Stock IN Transaction
```sql
EXEC usp_InsertInventoryTransaction 
    @ProductID = 1, 
    @TransactionType = 'IN', 
    @Quantity = 100, 
    @UnitCost = 12.50,
    @ReferenceType = 'PO',
    @ReferenceNumber = 'PO-2026-001',
    @Notes = 'Supplier delivery';
```

### Insert a Stock OUT Transaction
```sql
EXEC usp_InsertInventoryTransaction 
    @ProductID = 1, 
    @TransactionType = 'OUT', 
    @Quantity = 25,
    @ReferenceType = 'SO',
    @ReferenceNumber = 'SO-2026-001',
    @Notes = 'Customer order fulfilled';
```

### Generate Monthly Report
```sql
-- Report for February 2026
EXEC usp_GenerateMonthlyInventoryReport 
    @Year = 2026, 
    @Month = 2;

-- Report for specific category
EXEC usp_GenerateMonthlyInventoryReport 
    @Year = 2026, 
    @Month = 2,
    @CategoryID = 1;  -- Electronics only
```

### Detect Low Stock Items
```sql
-- Use default reorder levels
EXEC usp_DetectLowStockItems;

-- Override threshold (e.g., all items below 50 units)
EXEC usp_DetectLowStockItems @ThresholdOverride = 50;

-- Only show critical alerts
EXEC usp_DetectLowStockItems @SeverityFilter = 'CRITICAL';
```

---

## 📁 Project Structure

```
SQL-Server-inventory-control-database/
│
├── InventoryControlDatabase.sql   # Complete database implementation
│   ├── Section 1-2: Database setup & cleanup
│   ├── Section 3: Table definitions
│   ├── Section 4: Index creation
│   ├── Section 5: Stock update trigger
│   ├── Section 6-8: Stored procedures
│   ├── Section 9: Sample data
│   └── Section 10: Verification tests
│
└── README.md                      # This file
```

---

## 🔧 Database Objects

| Type | Name | Description |
|------|------|-------------|
| **Table** | `ProductCategories` | Product categorization lookup |
| **Table** | `Products` | Master product data with stock levels |
| **Table** | `InventoryTransactions` | Complete transaction audit log |
| **Table** | `LowStockAlerts` | Alert history with acknowledgment tracking |
| **Trigger** | `trg_UpdateProductStock_AfterInsert` | Auto-updates stock & prevents negative values |
| **Procedure** | `usp_InsertInventoryTransaction` | Safe transaction entry with validation |
| **Procedure** | `usp_GenerateMonthlyInventoryReport` | Parameterized monthly reporting |
| **Procedure** | `usp_DetectLowStockItems` | Cursor-based low stock detection |

---

## 📈 Sample Data

The script includes realistic sample data for testing:

- **5 Categories**: Electronics, Office Supplies, Furniture, Industrial Equipment, Packaging Materials
- **20 Products**: Various items with different stock levels and price points
- **Historical Transactions**: 2 months of IN/OUT movements including POs, SOs, adjustments, and returns

---

## 🤝 Contributing

Contributions are welcome! Feel free to:
- Report bugs or issues
- Suggest new features
- Submit pull requests

---

## 📄 License

This project is open source and available under the [MIT License](LICENSE).

---

## 👤 Author

**Ahmed Mufti**

- GitHub: [@AhmedMufti](https://github.com/AhmedMufti)

---

<p align="center">
  <sub>Built with ❤️ for inventory management</sub>
</p>
