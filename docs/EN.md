# StaffingPro-MSSQL – Portfolio project (EN)

## What is it?
**StaffingPro** is a portfolio **Microsoft SQL Server 2025** database that models typical processes of a staffing agency:
- client companies and sites
- job orders (Order) with requested headcount
- assignments – linking employees to orders
- timesheets (Timesheet / TimesheetLine)
- invoicing (Invoice / InvoiceLine)
- audit logging (ChangeLog) to track changes

> **Important:** demo/portfolio database, not a production HR system. Seed data is synthetic.

---

## Project goals
This project demonstrates:
- a clean data model (schemas, PK/FK relationships)
- data quality & business rules (constraints)
- reporting layer (views)
- automated workflows (stored procedures)
- traceability (audit trigger + ChangeLog)
- GDPR-minded approach (minimal PII, masking, hashing)

---

## Technical highlights
### Schemas
- `ref` – reference data (statuses, pay types)
- `core` – core entities (Person, Employee, ClientCompany, ClientSite, JobRole)
- `ops` – operations (Order, Assignment, Timesheet, TimesheetLine, Invoice, InvoiceLine)
- `audit` – auditing (ChangeLog)
- `sec` – role patterns (optional)

### Integrity & performance
- PK/FK constraints with FK indexes
- CHECK constraints (date ranges, hours, amounts)
- defaults (CreatedAt/ModifiedAt, status defaults)

### Views (examples)
- `ops.vOrderFillRate` – fill rate (assigned / requested)
- `ops.vActiveAssignments` – currently active assignments
- `ops.vBillableHoursMonthly` – monthly billable hours per client

### Stored procedures (examples)
- create order / assign employee / submit timesheet / generate invoice
- `ops.uspRefreshOrderStatus` – business status refresh (OPEN → FILLED) with dry-run option

### Triggers (examples)
- audit logging with JSON snapshots into `audit.ChangeLog`
- overlapping assignment prevention for PLANNED/ACTIVE intervals

---

## GDPR & privacy (short)
- no real personal data
- `@example.invalid` email domain
- Dynamic Data Masking for Email/Phone (for read/report users)
- sensitive identifiers stored as hashes (if applicable)

See: `docs/GDPR_SECURITY.md`

---

## How to run
1. Open the install script in SSMS:
   - `sql/StaffingPro (Munkaerő-kölcsönző).sql`
2. Execute it (drop+create + schema + seed data).
3. Demo queries:
   - `sql/DEMO_QUERIES-StaffingPro(portfolio).sql`
4. Interview runbook (recommended, sequential):
   - `sql/20_interview_demo_runbook.sql` *(if added to the repo)*

---

## Screenshots / docs
Key images are in: `docs/screenshot/`
- ERD / diagram
- view outputs
- invoice example
- job demo (illustration only)

---

## Possible next steps
- row-level security / refined roles
- TDE / Always Encrypted (production security showcase)
- retention/anonymization process demo
- basic tSQLt tests (constraints & procedure tests)
