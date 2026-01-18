/*===========================================================================
  DEMO QUERIES – StaffingPro (portfolio)
  Cél: gyorsan megmutatni riportok, üzleti kontrollok, audit és számlázás mûködését.
===========================================================================*/

-- 1) Megrendelések betöltöttsége (FillRate): megmutatja, hogy a kért létszámhoz képest
--    hány fõ van ténylegesen hozzárendelve (PLANNED/ACTIVE).
--    Miért fontos? Kapacitás-tervezés és operatív státusz riport.
SELECT TOP 10 *
FROM ops.vOrderFillRate
ORDER BY FillRate DESC;

-----------------------------------------------------------------------------

-- 2) Aktív kiközvetítések: kik dolgoznak éppen, hol és milyen megbízáson.
--    Miért fontos? Napi operatív áttekintés (diszpécser/operáció).
SELECT TOP 10 *
FROM ops.vActiveAssignments
ORDER BY StartDate DESC;

------------------------------------------------------------------------------

-- 3) Havi számlázható órák: ügyfelenként hónapra aggregálja a munkaórákat
--    (pótlék szorzókkal, PayType.Multiplier).
--    Miért fontos? Finance/controlling gyors havi kimutatás.
SELECT TOP 10 *
FROM ops.vBillableHoursMonthly
ORDER BY YearMonth DESC;

------------------------------------------------------------------------------

-- 4) Legutóbbi számlák: egyszerû lista a számlafej adataival.
--    Miért fontos? számlázási folyamat ellenõrzése (kiállítás, fizetési határidõ).
SELECT TOP 10
       InvoiceNumber, TotalNetHuf, IssueDate, DueDate
FROM ops.Invoice
ORDER BY InvoiceId DESC;

-------------------------------------------------------------------------------

-- 5) Audit napló (Order tábla): ki/mikor/milyen mûveletet végzett és melyik kulcson.
--    Miért fontos? változáskövetés, hibakeresés, megfelelõség.
SELECT TOP 10
       ChangeAt, ActionType, KeyValue
FROM audit.ChangeLog
ORDER BY ChangeLogId DESC;

-------------------------------------------------------------------------------

-- 6) "Üres" megrendelések (nincs rá kiosztás):
--    Azokat az Order-öket listázza, amelyekhez 0 darab PLANNED/ACTIVE assignment tartozik.
--    Miért fontos? operatív teendõlista: még nincs ember rendelve a megbízásra.
SELECT TOP 10
       o.OrderNumber,
       cc.Name AS ClientCompany,
       o.StartDate, o.EndDate,
       o.HeadcountRequested,
       AssignedCount = COUNT(a.AssignmentId)
FROM ops.[Order] o
JOIN core.ClientCompany cc ON cc.ClientCompanyId = o.ClientCompanyId
LEFT JOIN ops.Assignment a ON a.OrderId = o.OrderId
LEFT JOIN ref.AssignmentStatus ast ON ast.AssignmentStatusId = a.AssignmentStatusId
                                  AND ast.Code IN ('PLANNED','ACTIVE')
GROUP BY o.OrderNumber, cc.Name, o.StartDate, o.EndDate, o.HeadcountRequested
HAVING COUNT(a.AssignmentId) = 0
ORDER BY o.StartDate ASC;

--------------------------------------------------------------------------------

-- 7) "Top 5" munkavállaló a timesheet alapján (elmúlt 14 nap):
--    Megmutatja, kik dolgoztak a legtöbbet az elmúlt 2 hétben (szorzózott órákkal is).
--    Miért fontos? terhelés/kapacitás, payroll ellenõrzés, egyszerû analytics.
DECLARE @From date = CONVERT(date, GETDATE() - 14);
DECLARE @To   date = CONVERT(date, GETDATE() - 1);

SELECT TOP 5
       e.EmployeeNumber,
       FullName = CONCAT(p.FamilyName, N' ', p.GivenName),
       RawHours = SUM(tl.Hours),
       WeightedHours = SUM(tl.Hours * pt.Multiplier)
FROM ops.TimesheetLine tl
JOIN ops.Timesheet t ON t.TimesheetId = tl.TimesheetId
JOIN core.Employee e ON e.EmployeeId = t.EmployeeId
JOIN core.Person p ON p.PersonId = e.PersonId
JOIN ref.PayType pt ON pt.PayTypeId = tl.PayTypeId
WHERE tl.WorkDate BETWEEN @From AND @To
GROUP BY e.EmployeeNumber, p.FamilyName, p.GivenName
ORDER BY WeightedHours DESC;

--------------------------------------------------------------------------------

-- 8) Számla tételek részletezése (legutóbbi számla):
--    A legutolsó Invoice-hoz kilistázza a tételeket és a végösszeg ellenõrzését.
--    Miért fontos? számlázás transzparencia + TotalNetHuf validálása.
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

-- Total ellenõrzés: a tételek összege = Invoice.TotalNetHuf?
SELECT
    i.InvoiceNumber,
    StoredTotal = i.TotalNetHuf,
    CalculatedTotal = ISNULL(SUM(il.LineNetHuf), 0),
    Diff = i.TotalNetHuf - ISNULL(SUM(il.LineNetHuf), 0)
FROM ops.Invoice i
LEFT JOIN ops.InvoiceLine il ON il.InvoiceId = i.InvoiceId
WHERE i.InvoiceId = @LastInvoiceId
GROUP BY i.InvoiceNumber, i.TotalNetHuf;

-------------------------------------------------------------------------------

-- 9) Timesheet adatminõség ellenõrzés (példa kontroll):
--    Megkeresi azokat a TimesheetLine sorokat, ahol nincs OrderId / AssignmentId,
--    vagyis a munkaóra nincs egyértelmûen megbízáshoz kötve.
--    Miért fontos? számlázhatóság és adatminõség (hiányos kapcsolások).
SELECT TOP 20
       tl.TimesheetLineId,
       t.EmployeeId,
       tl.WorkDate,
       tl.Hours,
       tl.PayTypeId,
       tl.OrderId,
       tl.AssignmentId
FROM ops.TimesheetLine tl
JOIN ops.Timesheet t ON t.TimesheetId = tl.TimesheetId
WHERE (tl.OrderId IS NULL OR tl.AssignmentId IS NULL)
ORDER BY tl.WorkDate DESC;

---------------------------------------------------------------------------------
-- 10) PRO: Átfedõ kiközvetítések keresése (debug/report)
--    Elvileg a trigger (ops.tr_Assignment_NoOverlap) tiltja az átfedést PLANNED/ACTIVE
--    státuszban. Ez a lekérdezés mégis hasznos:
--      - ha régi adatokból migrálsz,
--      - ha ideiglenesen kikapcsolták a triggert,
--      - ha audit/debug célból ellenõriznéd a szabály érvényesülését.
--    Mit csinál? Összepárosítja ugyanazon EmployeeId-hez tartozó assignment sorokat,
--    és kiszûri azokat, ahol a dátum-intervallumok átfedik egymást.
SELECT TOP 50
       e.EmployeeNumber,
       EmployeeName = CONCAT(p.FamilyName, N' ', p.GivenName),

       a1.AssignmentId AS AssignmentId_1,
       a1.StartDate    AS Start_1,
       a1.EndDate      AS End_1,
       s1.Code         AS Status_1,
       o1.OrderNumber  AS Order_1,

       a2.AssignmentId AS AssignmentId_2,
       a2.StartDate    AS Start_2,
       a2.EndDate      AS End_2,
       s2.Code         AS Status_2,
       o2.OrderNumber  AS Order_2
FROM ops.Assignment a1
JOIN ops.Assignment a2
  ON a2.EmployeeId = a1.EmployeeId
 AND a2.AssignmentId > a1.AssignmentId              -- duplikációk elkerülése
JOIN ref.AssignmentStatus s1 ON s1.AssignmentStatusId = a1.AssignmentStatusId
JOIN ref.AssignmentStatus s2 ON s2.AssignmentStatusId = a2.AssignmentStatusId
JOIN core.Employee e ON e.EmployeeId = a1.EmployeeId
JOIN core.Person p ON p.PersonId = e.PersonId
JOIN ops.[Order] o1 ON o1.OrderId = a1.OrderId
JOIN ops.[Order] o2 ON o2.OrderId = a2.OrderId
WHERE
    -- csak a releváns (munkát érintõ) státuszok
    s1.Code IN ('PLANNED','ACTIVE')
    AND s2.Code IN ('PLANNED','ACTIVE')
    -- átfedés feltétel: start1 <= end2 és start2 <= end1
    AND a1.StartDate <= a2.EndDate
    AND a2.StartDate <= a1.EndDate
ORDER BY e.EmployeeNumber, a1.StartDate, a2.StartDate;

--------------------------------------------------------------------------------
-- 11) PRO: Order státusz frissítés (OPEN -> FILLED) riport + frissítõ utasítás
--    Üzleti logika: ha a PLANNED/ACTIVE assignment-ek száma eléri a
--    HeadcountRequested értéket, akkor az Order tekinthetõ "betöltöttnek".
--    Ez két részbõl áll:
--      (A) Riport: megmutatja mely orderök "betölthetõk" (OPEN, de már elérték a létszámot)
--      (B) Update: ténylegesen átállítja FILLED-re (DEMO-ban elõtte nézd meg a riportot)

-- (A) Riport: mely OPEN orderök érik el a kért létszámot?
DECLARE @OpenStatusId   tinyint = (SELECT OrderStatusId FROM ref.OrderStatus WHERE Code='OPEN');
DECLARE @FilledStatusId tinyint = (SELECT OrderStatusId FROM ref.OrderStatus WHERE Code='FILLED');

SELECT TOP 20
       o.OrderId,
       o.OrderNumber,
       cc.Name AS ClientCompany,
       o.HeadcountRequested,
       AssignedCount = COUNT(CASE WHEN ast.Code IN ('PLANNED','ACTIVE') THEN 1 END),
       CanBeFilled = CASE
                        WHEN COUNT(CASE WHEN ast.Code IN ('PLANNED','ACTIVE') THEN 1 END) >= o.HeadcountRequested
                        THEN 1 ELSE 0
                     END
FROM ops.[Order] o
JOIN core.ClientCompany cc ON cc.ClientCompanyId = o.ClientCompanyId
LEFT JOIN ops.Assignment a ON a.OrderId = o.OrderId
LEFT JOIN ref.AssignmentStatus ast ON ast.AssignmentStatusId = a.AssignmentStatusId
WHERE o.OrderStatusId = @OpenStatusId
GROUP BY o.OrderId, o.OrderNumber, cc.Name, o.HeadcountRequested
HAVING COUNT(CASE WHEN ast.Code IN ('PLANNED','ACTIVE') THEN 1 END) >= o.HeadcountRequested
ORDER BY o.OrderId DESC;

-- (B) Frissítés: OPEN -> FILLED azoknál, akik elérték a kért létszámot
UPDATE o
SET o.OrderStatusId = @FilledStatusId
FROM ops.[Order] o
WHERE o.OrderStatusId = @OpenStatusId
  AND EXISTS (
      SELECT 1
      FROM ops.Assignment a
      JOIN ref.AssignmentStatus ast ON ast.AssignmentStatusId = a.AssignmentStatusId
      WHERE a.OrderId = o.OrderId
        AND ast.Code IN ('PLANNED','ACTIVE')
      GROUP BY a.OrderId
      HAVING COUNT(*) >= o.HeadcountRequested
  );

-- Ellenõrzés: mutassuk a legutóbb FILLED-re állított orderöket
SELECT TOP 10
       o.OrderNumber,
       os.Code AS OrderStatus,
       o.HeadcountRequested,
       cc.Name AS ClientCompany,
       o.ModifiedAt
FROM ops.[Order] o
JOIN ref.OrderStatus os ON os.OrderStatusId = o.OrderStatusId
JOIN core.ClientCompany cc ON cc.ClientCompanyId = o.ClientCompanyId
ORDER BY o.ModifiedAt DESC;
