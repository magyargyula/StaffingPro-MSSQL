# StaffingPro-MSSQL – Portfólió projekt (HU)

## Mi ez?
A **StaffingPro** egy portfólió célú **Microsoft SQL Server 2025** adatbázis, amely egy munkaerő-kölcsönző cég tipikus folyamatait modellezi:
- ügyfélcégek és telephelyek kezelése
- megbízások (Order) és kért létszám
- kiközvetítések (Assignment) – munkavállaló hozzárendelése megbízáshoz
- munkaidő nyilvántartás (Timesheet)
- számlázás (Invoice / InvoiceLine)
- audit napló (ChangeLog) a módosítások követésére

> **Fontos:** demó/portfólió adatbázis, nem éles HR rendszer. A seed adatok generáltak.

---

## Fő célom a projekttel
Olyan adatbázis-mintát szerettem volna létrehozni, ami megmutatja:
- tiszta adatmodell (PK/FK kapcsolatok, sémák)
- adatminőség és üzleti szabályok (CHECK-ek, szabályok)
- riportolhatóság (view-k)
- üzleti folyamatok automatizálása (stored procedure)
- nyomonkövethetőség (audit trigger + ChangeLog)
- GDPR szemlélet (minimális PII, maszkolás, hash)

---

## Technikai elemek
### Sémák
- `ref` – státuszok és törzsadatok (EmployeeStatus, OrderStatus, AssignmentStatus, PayType)
- `core` – alap entitások (Person, Employee, ClientCompany, ClientSite, JobRole)
- `ops` – operáció (Order, Assignment, Timesheet, TimesheetLine, Invoice, InvoiceLine)
- `audit` – naplózás (ChangeLog)
- `sec` – jogosultsági minták (ha használod)

### Integritás és teljesítmény
- PK/FK kapcsolatok és FK indexelés
- CHECK constraint-ek (dátum intervallumok, óraszámok, összegek)
- default értékek (CreatedAt/ModifiedAt, státuszok)

### View-k (példák)
- `ops.vOrderFillRate` – betöltöttség (kiosztott fő / kért fő)
- `ops.vActiveAssignments` – aktuális kiközvetítések
- `ops.vBillableHoursMonthly` – havi számlázható órák ügyfelenként

### Stored procedure-k (példák)
- megbízás létrehozás / kiosztás / timesheet leadás / számlagenerálás
- `ops.uspRefreshOrderStatus` – státusz frissítés (OPEN → FILLED) “dry-run” móddal

### Triggerek (példák)
- audit logolás JSON snapshot-tal az `audit.ChangeLog` táblába
- átfedő assignment tiltás (PLANNED/ACTIVE időszak átfedés)

---

## GDPR és adatvédelem (röviden)
- nincsenek valós személyes adatok
- `@example.invalid` email domain
- DDM (Dynamic Data Masking) Email/Phone mezőkre (riport olvasóknak)
- érzékeny azonosítók tárolása hash-el (ha van ilyen mező)

Részletesen: `docs/GDPR_SECURITY.md`

---

## Hogyan futtasd?
1. Nyisd meg SSMS-ben a telepítő scriptet:
   - `sql/StaffingPro (Munkaerő-kölcsönző).sql`
2. Futtasd le (drop+create + schema + data seed).
3. Demo lekérdezések:
   - `sql/DEMO_QUERIES-StaffingPro(portfolio).sql`
4. Interjú runbook (ajánlott, sorban futtatható):
   - `sql/20_interview_demo_runbook.sql` *(ha felvetted a repo-ba)*

---

## Képernyőképek / dokumentáció
A legfontosabb képek: `docs/screenshot/`
- adatbázis diagram (ERD)
- view-k eredményei
- számla példa
- job demo (bemutató jelleggel)

---

## Továbbfejlesztési ötletek
- row-level security / finomabb role-ok
- TDE / Always Encrypted bemutató (production security)
- retention/anonimizálás automatikus folyamat
- tSQLt alap tesztek (adatintegritás és procs)
