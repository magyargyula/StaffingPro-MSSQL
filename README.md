# StaffingPro (MSSQL) – Munkaerő-kölcsönző portfolio adatbázis

## HU – Rövid leírás
Ez egy portfólió célú Microsoft SQL Server (2025) adatbázis projekt, amely egy munkaerő-kölcsönző cég alapfolyamatait modellezi:
- ügyfélcégek és telephelyek
- megbízások (Order)
- kiközvetítések (Assignment)
- timesheet (munkaórák)
- számlázás (Invoice)

A projekt célja: adatmodell + üzleti szabályok + adatminőség + audit + alap jogosultsági minta bemutatása.

## EN – Short description
Portfolio Microsoft SQL Server (2025) database project modeling a staffing agency:
client companies/sites, orders, assignments, timesheets, and invoicing.
Focus: data model, constraints, business rules, auditing, and basic security patterns.

---

## Features / Funkciók
- Schemas: `ref`, `core`, `ops`, `audit`, `sec`
- PK/FK + indexes on FKs
- CHECK/DEFAULT constraints (date ranges, hours, rates, headcount)
- Views:
  - `ops.vActiveAssignments`
  - `ops.vOrderFillRate`
  - `ops.vBillableHoursMonthly`
- Stored procedures:
  - `ops.uspCreateOrder`
  - `ops.uspAssignEmployeeToOrder`
  - `ops.uspSubmitTimesheet`
  - `ops.uspGenerateInvoiceFromTimesheet`
- Triggers:
  - ModifiedAt maintenance
  - Audit logging (`audit.ChangeLog`)
  - Overlapping assignment prevention
- GDPR/Security approach:
  - minimal PII, demo emails/phones
  - masking (DDM) for selected fields
  - hashed identifiers for tax/government IDs (no plaintext)

> Note: SQL Agent backup jobs are included in the script for demonstration purposes.

---

## How to run / Futtatás
1. Open SSMS
2. Run: `sql/00_all_in_one.sql`
3. Optional demo queries: `sql/10_demo_queries.sql`

---

## Demo queries (quick)
```sql
SELECT TOP 10 * FROM ops.vOrderFillRate ORDER BY FillRate DESC;
SELECT TOP 10 * FROM ops.vActiveAssignments ORDER BY StartDate DESC;
SELECT TOP 10 * FROM ops.vBillableHoursMonthly ORDER BY YearMonth DESC;

SELECT TOP 10 InvoiceNumber, TotalNetHuf, IssueDate, DueDate
FROM ops.Invoice
ORDER BY InvoiceId DESC;

SELECT TOP 10 ChangeAt, ActionType, KeyValue
FROM audit.ChangeLog
ORDER BY ChangeLogId DESC;
