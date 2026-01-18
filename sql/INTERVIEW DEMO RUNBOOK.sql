/*==============================================================================
  INTERVIEW DEMO RUNBOOK – StaffingPro-MSSQL (SQL Server 2025)
  Cél: 10-12 perc, sorban futtatva. Minden blokkhoz tartozik magyarázat.

==============================================================================*/

USE StaffingPro;
GO

--------------------------------------------------------------------------------
-- 0) ★ Gyors “health check”: van-e adat, és a fő objektumok megvannak-e?
-- - "Ez egy end-to-end demo: törzsadatok, operáció, timesheet, számlázás, audit."
--------------------------------------------------------------------------------
SELECT
  Persons     = (SELECT COUNT(*) FROM core.Person),
  Employees   = (SELECT COUNT(*) FROM core.Employee),
  Orders      = (SELECT COUNT(*) FROM ops.[Order]),
  Assignments = (SELECT COUNT(*) FROM ops.Assignment),
  Timesheets  = (SELECT COUNT(*) FROM ops.Timesheet),
  Invoices    = (SELECT COUNT(*) FROM ops.Invoice);

--------------------------------------------------------------------------------
-- 1) ★ Séma áttekintés (meta): milyen sémák és kulcs objektumok vannak?
-- - "Szétválasztottam a doméneket: core/ref/ops/audit/sec."
--------------------------------------------------------------------------------
SELECT s.name AS SchemaName, COUNT(*) AS ObjectCount
FROM sys.objects o
JOIN sys.schemas s ON s.schema_id = o.schema_id
WHERE s.name IN ('ref','core','ops','audit','sec')
GROUP BY s.name
ORDER BY s.name;

--------------------------------------------------------------------------------
-- 2) ★ Riport: Order fill rate (view)
-- - "View-ket használok riportoláshoz, így stabil az interface."
--------------------------------------------------------------------------------
SELECT TOP 10 *
FROM ops.vOrderFillRate
ORDER BY FillRate DESC;

--------------------------------------------------------------------------------
-- 3) ★ Aktív kiközvetítések (view)
-- - "Operációs áttekintő: ki hol dolgozik, melyik ügyfélnél, milyen szerepben."
--------------------------------------------------------------------------------
SELECT TOP 10 *
FROM ops.vActiveAssignments
ORDER BY StartDate DESC;

--------------------------------------------------------------------------------
-- 4) ★ Havi billable riport (view)
-- - "PayType szorzókkal számolom a számlázható órákat (night/weekend/holiday)."
--------------------------------------------------------------------------------
SELECT TOP 10 *
FROM ops.vBillableHoursMonthly
ORDER BY YearMonth DESC;

--------------------------------------------------------------------------------
-- 5) Data quality kontroll: vannak-e olyan timesheet sorok, amik nem rendelhetők orderhez?
-- - "Ez tipikus adatminőség ellenőrzés, mert számlázásnál gondot okozna."
--------------------------------------------------------------------------------
SELECT TOP 20
  tl.TimesheetLineId, t.EmployeeId, tl.WorkDate, tl.Hours, tl.PayTypeId,
  tl.OrderId, tl.AssignmentId
FROM ops.TimesheetLine tl
JOIN ops.Timesheet t ON t.TimesheetId = tl.TimesheetId
WHERE tl.OrderId IS NULL OR tl.AssignmentId IS NULL
ORDER BY tl.WorkDate DESC;

--------------------------------------------------------------------------------
-- 6) ★ Számla áttekintés: legutóbbi számlák és összegek
-- - "Invoice fej + line. TotalNetHuf a tételek összegéből frissül."
--------------------------------------------------------------------------------
SELECT TOP 10 InvoiceId, InvoiceNumber, TotalNetHuf, IssueDate, DueDate
FROM ops.Invoice
ORDER BY InvoiceId DESC;

--------------------------------------------------------------------------------
-- 7) ★ Számla részletek + Total ellenőrzés (reconciliation)
-- - "Mindig legyen ellenőrző lekérdezés: tárolt total = számolt total."
--------------------------------------------------------------------------------
DECLARE @LastInvoiceId int = (SELECT TOP 1 InvoiceId FROM ops.Invoice ORDER BY InvoiceId DESC);

SELECT
  i.InvoiceNumber,
  il.InvoiceLineId,
  il.Description,
  il.Quantity,
  il.UnitPriceHuf,
  il.LineNetHuf
FROM ops.Invoice i
JOIN ops.InvoiceLine il ON il.InvoiceId = i.InvoiceId
WHERE i.InvoiceId = @LastInvoiceId
ORDER BY il.InvoiceLineId;

SELECT
  i.InvoiceNumber,
  StoredTotal     = i.TotalNetHuf,
  CalculatedTotal = ISNULL(SUM(il.LineNetHuf), 0),
  Diff            = i.TotalNetHuf - ISNULL(SUM(il.LineNetHuf), 0)
FROM ops.Invoice i
LEFT JOIN ops.InvoiceLine il ON il.InvoiceId = i.InvoiceId
WHERE i.InvoiceId = @LastInvoiceId
GROUP BY i.InvoiceNumber, i.TotalNetHuf;

--------------------------------------------------------------------------------
-- 8) ★ Audit: Order változások (trigger log)
-- - "Az ops.Order-en trigger auditol. JSON snapshot old/new, gyors visszakeresés."
--------------------------------------------------------------------------------
SELECT TOP 10 ChangeAt, ChangeBy, ActionType, KeyValue
FROM audit.ChangeLog
WHERE SchemaName = 'ops' AND TableName = 'Order'
ORDER BY ChangeLogId DESC;

--------------------------------------------------------------------------------
-- 9) GDPR/PII demonstráció: DDM maszkolás (Email/Phone)
-- - "Maszkolás = megjelenítési védelem. Read-only usernek nem kell a teljes adat."
-- Megjegyzés: a maszkolás hatása jogosultságtól függ. Itt csak azt mutatom,
-- hogy az oszlopok maszk paraméterrel vannak definiálva.
--------------------------------------------------------------------------------
SELECT TOP 10
  PersonId, GivenName, FamilyName, Email, Phone
FROM core.Person
ORDER BY PersonId DESC;

SELECT
  c.name AS ColumnName,
  c.is_masked,
  c.masking_function
FROM sys.masked_columns c
JOIN sys.tables t ON t.object_id = c.object_id
JOIN sys.schemas s ON s.schema_id = t.schema_id
WHERE s.name = 'core' AND t.name = 'Person';

--------------------------------------------------------------------------------
-- 10) Business rule (defense): overlap keresés (should be empty)
-- - "Trigger tiltja a PLANNED/ACTIVE átfedést. Ez a report ellenőrzi."
--------------------------------------------------------------------------------
SELECT TOP 50
  e.EmployeeNumber,
  EmployeeName = CONCAT(p.FamilyName, N' ', p.GivenName),
  a1.AssignmentId AS A1, a1.StartDate AS A1_Start, a1.EndDate AS A1_End,
  a2.AssignmentId AS A2, a2.StartDate AS A2_Start, a2.EndDate AS A2_End
FROM ops.Assignment a1
JOIN ops.Assignment a2
  ON a2.EmployeeId = a1.EmployeeId
 AND a2.AssignmentId > a1.AssignmentId
JOIN ref.AssignmentStatus s1 ON s1.AssignmentStatusId = a1.AssignmentStatusId
JOIN ref.AssignmentStatus s2 ON s2.AssignmentStatusId = a2.AssignmentStatusId
JOIN core.Employee e ON e.EmployeeId = a1.EmployeeId
JOIN core.Person p ON p.PersonId = e.PersonId
WHERE s1.Code IN ('PLANNED','ACTIVE')
  AND s2.Code IN ('PLANNED','ACTIVE')
  AND a1.StartDate <= a2.EndDate
  AND a2.StartDate <= a1.EndDate
ORDER BY e.EmployeeNumber, a1.StartDate;

--------------------------------------------------------------------------------
-- 11) (Opcionális) Státusz frissítés demo (dry-run):
-- - "Van stored procedure-m üzleti státuszfrissítésre. Dry-run módban először listáz."
----------------------------------------------------------------------------------
-- Dry-run: csak megmutatja, mit frissítene
EXEC ops.uspRefreshOrderStatus
    @FromStatusCode = 'OPEN',
    @ToStatusCode   = 'FILLED',
    @Execute        = 0;

-- Végrehajtás: ténylegesen frissít
EXEC ops.uspRefreshOrderStatus
    @FromStatusCode = 'OPEN',
    @ToStatusCode   = 'FILLED',
    @Execute        = 1;

-- Ellenőrzés: audit log (Order változások)
SELECT TOP 20 ChangeAt, ActionType, KeyValue, OldData, NewData
FROM audit.ChangeLog
WHERE SchemaName = 'ops' AND TableName = 'Order'
ORDER BY ChangeLogId DESC;
