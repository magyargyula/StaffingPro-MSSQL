# GDPR & Security notes (StaffingPro-MSSQL)

> **HU (rövid):** Ez a projekt **demó/portfólió célú** adatbázis. Nem tartalmaz valós személyes adatokat.  
> **EN (short):** This is a **demo/portfolio** database. It contains no real personal data.

---

## 1) Data scope & minimization (Adatkezelés és minimalizálás)

**HU:**
- A demo adatbázisban csak olyan mezők szerepelnek, amelyek a folyamatok bemutatásához szükségesek.
- Valós személyes adat (név, e-mail, telefonszám, azonosító) **nem kerül tárolásra** – minden generált.
- A személyes azonosítók helyett **hash** kerül mentésre (pl. `TaxNumberHash`, `GovernmentIdHash`).

**EN:**
- The demo database only stores fields required to showcase typical workflows.
- No real personal data is used (names/emails/phones/IDs are synthetic).
- Sensitive identifiers are stored as **hashes** (e.g., `TaxNumberHash`, `GovernmentIdHash`).

---

## 2) Demo data & anonymization (Demó adatok és anonimizálás)

**HU:**
- A `core.Person` rekordok generált nevekkel készülnek.
- Az e-mail domain `@example.invalid`, így véletlenül sem valós cím.
- A `Phone` mező is generált és nem hívható valós telefonszám.

**EN:**
- `core.Person` records are generated with synthetic data.
- Email domain uses `@example.invalid` to avoid real addresses.
- Phone numbers are generated and not intended to be real.

---

## 3) Dynamic Data Masking (Maszkolás – DDM)

**HU:**
- Bizonyos oszlopok **Dynamic Data Masking**-gal védettek:
  - `core.Person.Email` → `email()`
  - `core.Person.Phone` → `partial(...)`
- Cél: riport/olvasási jogosultságnál ne jelenjen meg teljes érték.

**EN:**
- Some columns are protected using **Dynamic Data Masking**:
  - `core.Person.Email` → `email()`
  - `core.Person.Phone` → `partial(...)`
- Goal: prevent exposure of full values for read-only/report users.

> Megjegyzés / Note: DDM nem titkosítás, hanem megjelenítési védelem.  
> DDM is not encryption; it protects data presentation.

---

## 4) Hashing of identifiers (Érzékeny azonosítók hash-elése)

**HU:**
- Példák:
  - `core.ClientCompany.TaxNumberHash`
  - `core.Employee.GovernmentIdHash`
- A projekt `HASHBYTES('SHA2_256', ...)` függvényt használ.
- Cél: a nyers azonosító ne legyen visszafejthető az adatbázisból.

**EN:**
- Examples:
  - `core.ClientCompany.TaxNumberHash`
  - `core.Employee.GovernmentIdHash`
- Uses `HASHBYTES('SHA2_256', ...)`.
- Goal: avoid storing raw identifiers and reduce exposure.

---

## 5) Audit logging (Változásnapló / audit)

**HU:**
- A módosítások nyomon követésére `audit.ChangeLog` tábla van.
- `ops.[Order]` táblán trigger rögzíti INSERT/UPDATE/DELETE eseményeket JSON formátumban.
- Cél: megfelelőség, hibakeresés, visszakövethetőség.

**EN:**
- Changes are tracked in `audit.ChangeLog`.
- A trigger on `ops.[Order]` records INSERT/UPDATE/DELETE events with JSON snapshots.
- Purpose: traceability, debugging, compliance.

---

## 6) Role-based permissions (Jogosultságok / szerepkörök)

**HU:**
- Példa szerepkörök:
  - `rl_ops` (operáció)
  - `rl_payroll` (munkaidő / timesheet)
  - `rl_finance` (számlázás)
  - `rl_readonly` (riport)
- Cél: legkisebb jogosultság elve (least privilege).

**EN:**
- Example roles:
  - `rl_ops`, `rl_payroll`, `rl_finance`, `rl_readonly`
- Goal: apply **least privilege**.

---

## 7) Retention (Megőrzés / adattörlés elv)

**HU:**
- `core.Person.DataRetentionUntil` mező demonstrációs jelleggel jelzi, meddig tartható meg adat.
- Valós rendszerben ez segítené automatizált törlési/anonimizálási folyamatokat.

**EN:**
- `core.Person.DataRetentionUntil` demonstrates a retention concept.
- In real systems, it supports automated deletion/anonymization.

---

## 8) What this project is NOT (A projekt korlátai)

**HU:**
- Nem valós HR rendszer és nem éles adatkezelés.
- Nem tartalmaz titkosítást (TDE/Always Encrypted) – demó célra fókuszál.

**EN:**
- Not a production HR system.
- No encryption features (TDE/Always Encrypted) are configured (demo scope).

---

## 9) Suggested next steps (Továbbfejlesztési ötletek)

**HU:**
- TDE bekapcsolás (production példa)
- Always Encrypted (érzékeny mezők)
- DLP/monitoring, row-level security
- Automatikus retention job (anonimizálás/törlés)

**EN:**
- Enable TDE for production examples
- Always Encrypted for sensitive fields
- Add RLS and monitoring
- Scheduled retention jobs (anonymize/delete)
