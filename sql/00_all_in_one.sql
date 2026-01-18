/*==============================================================================
  StaffingPro (Munkaerő-kölcsönző) – Portfolio DB (SQL Server 2025)
  ---------------------------------------------------------------------------
  Ha újratelepítés előtt törölni akarod az adatbázist, futtasd ezt külön:
  
  USE master;
  GO
  IF DB_ID(N'StaffingPro') IS NOT NULL
  BEGIN
      ALTER DATABASE [StaffingPro] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
      DROP DATABASE [StaffingPro];
  END
  GO
==============================================================================*/

SET NOCOUNT ON;
SET XACT_ABORT ON;

--------------------------------------------------------------------------------
-- 1) DB ÚJRAÉPÍTÉS (automatikus drop + create)
--------------------------------------------------------------------------------
USE master;
GO

IF DB_ID(N'StaffingPro') IS NOT NULL
BEGIN
    ALTER DATABASE [StaffingPro] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [StaffingPro];
END
GO

CREATE DATABASE [StaffingPro];
GO

-- ALTER AUTHORIZATION ON DATABASE::[StaffingPro] TO [dbo];
-- GO

USE [StaffingPro];
GO

/* -----------------------------------------------------------------------------
 2) SÉMÁK:
--------------------------------------------------------------------------------
    ref – törzsadatok (státuszok, típusok)
    core – alap entitások (Person, Company, Contract…)
    ops – operáció (Assignments, Timesheet, Billing)
    audit – audit táblák / log
    sec – jogosultság segéd  
-------------------------------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'ref')   EXEC('CREATE SCHEMA ref');  -- ref – törzsadatok (státuszok, típusok)
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'core')  EXEC('CREATE SCHEMA core'); -- core – alap entitások (Person, Company, Contract…)
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'ops')   EXEC('CREATE SCHEMA ops');  -- ops – operáció (Assignments, Timesheet, Billing)
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'audit') EXEC('CREATE SCHEMA audit');-- audit – audit táblák / log
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'sec')   EXEC('CREATE SCHEMA sec');  -- sec – jogosultság segéd
GO

--------------------------------------------------------------------------------
/* 3) REF TABLES (törzs) táblák + seed:
    ref.EmployeeStatus
    ref.OrderStatus
    ref.AssignmentStatus
    ref.PayType (normál/éjszakai/ünnep/…)
    ref.Country / City*/
-----------------------------------------------------------------------------------
CREATE TABLE ref.EmployeeStatus (
    EmployeeStatusId tinyint IDENTITY(1,1) NOT NULL CONSTRAINT PK_EmployeeStatus PRIMARY KEY,
    Code varchar(20) NOT NULL CONSTRAINT UQ_EmployeeStatus_Code UNIQUE,
    NameHu nvarchar(100) NOT NULL,
    NameEn nvarchar(100) NOT NULL,
    IsActive bit NOT NULL CONSTRAINT DF_EmployeeStatus_IsActive DEFAULT(1)
);

CREATE TABLE ref.OrderStatus (
    OrderStatusId tinyint IDENTITY(1,1) NOT NULL CONSTRAINT PK_OrderStatus PRIMARY KEY,
    Code varchar(20) NOT NULL CONSTRAINT UQ_OrderStatus_Code UNIQUE,
    NameHu nvarchar(100) NOT NULL,
    NameEn nvarchar(100) NOT NULL,
    IsActive bit NOT NULL CONSTRAINT DF_OrderStatus_IsActive DEFAULT(1)
);

CREATE TABLE ref.AssignmentStatus (
    AssignmentStatusId tinyint IDENTITY(1,1) NOT NULL CONSTRAINT PK_AssignmentStatus PRIMARY KEY,
    Code varchar(20) NOT NULL CONSTRAINT UQ_AssignmentStatus_Code UNIQUE,
    NameHu nvarchar(100) NOT NULL,
    NameEn nvarchar(100) NOT NULL,
    IsActive bit NOT NULL CONSTRAINT DF_AssignmentStatus_IsActive DEFAULT(1)
);

CREATE TABLE ref.PayType (
    PayTypeId tinyint IDENTITY(1,1) NOT NULL CONSTRAINT PK_PayType PRIMARY KEY,
    Code varchar(20) NOT NULL CONSTRAINT UQ_PayType_Code UNIQUE,
    NameHu nvarchar(100) NOT NULL,
    NameEn nvarchar(100) NOT NULL,
    Multiplier decimal(6,3) NOT NULL CONSTRAINT CK_PayType_Multiplier CHECK (Multiplier >= 0.000)
);

INSERT INTO ref.EmployeeStatus(Code, NameHu, NameEn) VALUES
('CANDIDATE', N'Jelölt', 'Candidate'),
('ACTIVE',    N'Aktív', 'Active'),
('INACTIVE',  N'Inaktív', 'Inactive'),
('EXITED',    N'Kilépett', 'Exited');

INSERT INTO ref.OrderStatus(Code, NameHu, NameEn) VALUES
('OPEN',      N'Nyitott', 'Open'),
('FILLED',    N'Betöltött', 'Filled'),
('CLOSED',    N'Lezárt', 'Closed'),
('CANCELLED', N'Törölt', 'Cancelled');

INSERT INTO ref.AssignmentStatus(Code, NameHu, NameEn) VALUES
('PLANNED', N'Tervezett', 'Planned'),
('ACTIVE',  N'Aktív', 'Active'),
('ENDED',   N'Befejezett', 'Ended'),
('CANCEL',  N'Törölt', 'Cancelled');

INSERT INTO ref.PayType(Code, NameHu, NameEn, Multiplier) VALUES
('NORMAL',   N'Normál', 'Normal', 1.000),
('NIGHT',    N'Éjszakai', 'Night', 1.250),
('WEEKEND',  N'Hétvégi', 'Weekend', 1.500),
('HOLIDAY',  N'Ünnepnapi', 'Holiday', 2.000);
GO

--------------------------------------------------------------------------------
/* 4) CORE TABLES (GDPR szemlélet):
    core.Person (személy alapadat: név, születési dátum opcionális, email, telefon)
    core.Employee (munkavállaló: PersonId FK, adóazonosító hash/maszkolt, belépés dátum, státusz)
    core.ClientCompany (ügyfélcég)
    core.ClientSite (telephely)
    core.JobRole (munkakör/pozíció törzs) */
--------------------------------------------------------------------------------
CREATE TABLE core.Person (
    PersonId int IDENTITY(1,1) NOT NULL CONSTRAINT PK_Person PRIMARY KEY,
    GivenName nvarchar(80) NOT NULL,
    FamilyName nvarchar(80) NOT NULL,

    Email nvarchar(254) MASKED WITH (FUNCTION = 'email()') NULL,
    Phone nvarchar(30)  MASKED WITH (FUNCTION = 'partial(2,"XXXXXXX",2)') NULL,

    IsDemoData bit NOT NULL CONSTRAINT DF_Person_IsDemoData DEFAULT(1),
    ConsentToContact bit NOT NULL CONSTRAINT DF_Person_ConsentToContact DEFAULT(0),
    DataRetentionUntil date NULL,
    CreatedAt datetime2(0) NOT NULL CONSTRAINT DF_Person_CreatedAt DEFAULT (SYSUTCDATETIME()),
    ModifiedAt datetime2(0) NOT NULL CONSTRAINT DF_Person_ModifiedAt DEFAULT (SYSUTCDATETIME())
);
GO

CREATE TRIGGER core.tr_Person_ModifiedAt
ON core.Person
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE p
      SET ModifiedAt = SYSUTCDATETIME()
    FROM core.Person p
    INNER JOIN inserted i ON i.PersonId = p.PersonId;
END
GO

CREATE TABLE core.Employee (
    EmployeeId int IDENTITY(1,1) NOT NULL CONSTRAINT PK_Employee PRIMARY KEY,
    PersonId int NOT NULL CONSTRAINT UQ_Employee_Person UNIQUE,
    EmployeeNumber varchar(20) NOT NULL CONSTRAINT UQ_Employee_Number UNIQUE,
    EmployeeStatusId tinyint NOT NULL,
    StartDate date NOT NULL,
    EndDate date NULL,
    -- GDPR: azonosítók hash-elve (pl. adóazonosító/TAJ helyett)
    GovernmentIdHash varbinary(32) NULL, -- SHA2_256
    CreatedAt datetime2(0) NOT NULL CONSTRAINT DF_Employee_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT FK_Employee_Person FOREIGN KEY(PersonId) REFERENCES core.Person(PersonId),
    CONSTRAINT FK_Employee_Status FOREIGN KEY(EmployeeStatusId) REFERENCES ref.EmployeeStatus(EmployeeStatusId),
    CONSTRAINT CK_Employee_DateRange CHECK (EndDate IS NULL OR StartDate <= EndDate)
);
GO

CREATE TABLE core.ClientCompany (
    ClientCompanyId int IDENTITY(1,1) NOT NULL CONSTRAINT PK_ClientCompany PRIMARY KEY,
    Name nvarchar(200) NOT NULL CONSTRAINT UQ_ClientCompany_Name UNIQUE,
    TaxNumberHash varbinary(32) NULL, -- GDPR: hash (nem tárolunk adószámot nyersen)
    IsActive bit NOT NULL CONSTRAINT DF_ClientCompany_IsActive DEFAULT(1),
    CreatedAt datetime2(0) NOT NULL CONSTRAINT DF_ClientCompany_CreatedAt DEFAULT (SYSUTCDATETIME())
);
GO

CREATE TABLE core.ClientSite (
    ClientSiteId int IDENTITY(1,1) NOT NULL CONSTRAINT PK_ClientSite PRIMARY KEY,
    ClientCompanyId int NOT NULL,
    SiteName nvarchar(200) NOT NULL,
    City nvarchar(100) NOT NULL,
    AddressLine nvarchar(200) NULL,
    IsActive bit NOT NULL CONSTRAINT DF_ClientSite_IsActive DEFAULT(1),
    CONSTRAINT FK_ClientSite_Company FOREIGN KEY(ClientCompanyId) REFERENCES core.ClientCompany(ClientCompanyId),
    CONSTRAINT UQ_ClientSite UNIQUE (ClientCompanyId, SiteName)
);
GO

CREATE TABLE core.JobRole (
    JobRoleId int IDENTITY(1,1) NOT NULL CONSTRAINT PK_JobRole PRIMARY KEY,
    Code varchar(30) NOT NULL CONSTRAINT UQ_JobRole_Code UNIQUE,
    NameHu nvarchar(120) NOT NULL,
    NameEn nvarchar(120) NOT NULL,
    IsActive bit NOT NULL CONSTRAINT DF_JobRole_IsActive DEFAULT(1)
);
GO

-- Indexek FK-kra
CREATE INDEX IX_Employee_PersonId ON core.Employee(PersonId);
CREATE INDEX IX_Employee_StatusId ON core.Employee(EmployeeStatusId);
CREATE INDEX IX_ClientSite_CompanyId ON core.ClientSite(ClientCompanyId);
GO

--------------------------------------------------------------------------------
/* 5) OPS TABLES:
    ops.Order (megbízás: ügyfél, telephely, pozíció, darabszám, időszak, óradíj, státusz)
    ops.Assignment (kiközvetítés: OrderId + EmployeeId + időszak + státusz)
    ops.Timesheet (heti/havi timesheet fej)
    ops.TimesheetLine (nap/óra bontás; dátum, óraszám, pótlék típus)
    ops.Invoice (számla fej)
    ops.InvoiceLine (tétel: melyik Order/Assignment/Timesheet alapján) */
--------------------------------------------------------------------------------
CREATE TABLE ops.[Order] (
    OrderId int IDENTITY(1,1) NOT NULL CONSTRAINT PK_Order PRIMARY KEY,
    OrderNumber varchar(30) NOT NULL CONSTRAINT UQ_Order_OrderNumber UNIQUE,
    ClientCompanyId int NOT NULL,
    ClientSiteId int NOT NULL,
    JobRoleId int NOT NULL,
    OrderStatusId tinyint NOT NULL,
    HeadcountRequested int NOT NULL,
    StartDate date NOT NULL,
    EndDate date NOT NULL,
    HourlyRateHuf decimal(12,2) NOT NULL,
    Notes nvarchar(400) NULL,
    CreatedAt datetime2(0) NOT NULL CONSTRAINT DF_Order_CreatedAt DEFAULT (SYSUTCDATETIME()),
    ModifiedAt datetime2(0) NOT NULL CONSTRAINT DF_Order_ModifiedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT FK_Order_Company FOREIGN KEY(ClientCompanyId) REFERENCES core.ClientCompany(ClientCompanyId),
    CONSTRAINT FK_Order_Site FOREIGN KEY(ClientSiteId) REFERENCES core.ClientSite(ClientSiteId),
    CONSTRAINT FK_Order_JobRole FOREIGN KEY(JobRoleId) REFERENCES core.JobRole(JobRoleId),
    CONSTRAINT FK_Order_Status FOREIGN KEY(OrderStatusId) REFERENCES ref.OrderStatus(OrderStatusId),
    CONSTRAINT CK_Order_Headcount CHECK (HeadcountRequested > 0 AND HeadcountRequested <= 10000),
    CONSTRAINT CK_Order_DateRange CHECK (StartDate <= EndDate),
    CONSTRAINT CK_Order_Rate CHECK (HourlyRateHuf >= 0.00)
);
GO

CREATE TRIGGER ops.tr_Order_ModifiedAt
ON ops.[Order]
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE o
      SET ModifiedAt = SYSUTCDATETIME()
    FROM ops.[Order] o
    INNER JOIN inserted i ON i.OrderId = o.OrderId;
END
GO

CREATE TABLE ops.Assignment (
    AssignmentId int IDENTITY(1,1) NOT NULL CONSTRAINT PK_Assignment PRIMARY KEY,
    OrderId int NOT NULL,
    EmployeeId int NOT NULL,
    AssignmentStatusId tinyint NOT NULL,
    StartDate date NOT NULL,
    EndDate date NOT NULL,
    CreatedAt datetime2(0) NOT NULL CONSTRAINT DF_Assignment_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT FK_Assignment_Order FOREIGN KEY(OrderId) REFERENCES ops.[Order](OrderId),
    CONSTRAINT FK_Assignment_Employee FOREIGN KEY(EmployeeId) REFERENCES core.Employee(EmployeeId),
    CONSTRAINT FK_Assignment_Status FOREIGN KEY(AssignmentStatusId) REFERENCES ref.AssignmentStatus(AssignmentStatusId),
    CONSTRAINT CK_Assignment_DateRange CHECK (StartDate <= EndDate)
);
GO

CREATE TABLE ops.Timesheet (
    TimesheetId int IDENTITY(1,1) NOT NULL CONSTRAINT PK_Timesheet PRIMARY KEY,
    EmployeeId int NOT NULL,
    PeriodStart date NOT NULL,
    PeriodEnd date NOT NULL,
    SubmittedAt datetime2(0) NULL,
    ApprovedAt datetime2(0) NULL,
    CreatedAt datetime2(0) NOT NULL CONSTRAINT DF_Timesheet_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT FK_Timesheet_Employee FOREIGN KEY(EmployeeId) REFERENCES core.Employee(EmployeeId),
    CONSTRAINT CK_Timesheet_Period CHECK (PeriodStart <= PeriodEnd)
);
GO

CREATE TABLE ops.TimesheetLine (
    TimesheetLineId int IDENTITY(1,1) NOT NULL CONSTRAINT PK_TimesheetLine PRIMARY KEY,
    TimesheetId int NOT NULL,
    WorkDate date NOT NULL,
    Hours decimal(5,2) NOT NULL,
    PayTypeId tinyint NOT NULL,
    OrderId int NULL,
    AssignmentId int NULL,
    CreatedAt datetime2(0) NOT NULL CONSTRAINT DF_TimesheetLine_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT FK_TimesheetLine_Timesheet FOREIGN KEY(TimesheetId) REFERENCES ops.Timesheet(TimesheetId),
    CONSTRAINT FK_TimesheetLine_PayType FOREIGN KEY(PayTypeId) REFERENCES ref.PayType(PayTypeId),
    CONSTRAINT FK_TimesheetLine_Order FOREIGN KEY(OrderId) REFERENCES ops.[Order](OrderId),
    CONSTRAINT FK_TimesheetLine_Assignment FOREIGN KEY(AssignmentId) REFERENCES ops.Assignment(AssignmentId),
    CONSTRAINT CK_TimesheetLine_Hours CHECK (Hours > 0 AND Hours <= 24)
);
GO

CREATE TABLE ops.Invoice (
    InvoiceId int IDENTITY(1,1) NOT NULL CONSTRAINT PK_Invoice PRIMARY KEY,
    InvoiceNumber varchar(30) NOT NULL CONSTRAINT UQ_Invoice_InvoiceNumber UNIQUE,
    ClientCompanyId int NOT NULL,
    PeriodStart date NOT NULL,
    PeriodEnd date NOT NULL,
    IssueDate date NOT NULL,
    DueDate date NOT NULL,
    TotalNetHuf decimal(14,2) NOT NULL CONSTRAINT DF_Invoice_Total DEFAULT(0),
    CreatedAt datetime2(0) NOT NULL CONSTRAINT DF_Invoice_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT FK_Invoice_Company FOREIGN KEY(ClientCompanyId) REFERENCES core.ClientCompany(ClientCompanyId),
    CONSTRAINT CK_Invoice_Period CHECK (PeriodStart <= PeriodEnd),
    CONSTRAINT CK_Invoice_Due CHECK (IssueDate <= DueDate)
);
GO

CREATE TABLE ops.InvoiceLine (
    InvoiceLineId int IDENTITY(1,1) NOT NULL CONSTRAINT PK_InvoiceLine PRIMARY KEY,
    InvoiceId int NOT NULL,
    OrderId int NULL,
    Description nvarchar(200) NOT NULL,
    Quantity decimal(12,2) NOT NULL,
    UnitPriceHuf decimal(12,2) NOT NULL,
    LineNetHuf AS (ROUND(Quantity * UnitPriceHuf, 2)) PERSISTED,
    CONSTRAINT FK_InvoiceLine_Invoice FOREIGN KEY(InvoiceId) REFERENCES ops.Invoice(InvoiceId),
    CONSTRAINT FK_InvoiceLine_Order FOREIGN KEY(OrderId) REFERENCES ops.[Order](OrderId),
    CONSTRAINT CK_InvoiceLine_Qty CHECK (Quantity > 0),
    CONSTRAINT CK_InvoiceLine_Unit CHECK (UnitPriceHuf >= 0)
);
GO

-- FK indexek
CREATE INDEX IX_Order_CompanyId ON ops.[Order](ClientCompanyId);
CREATE INDEX IX_Order_SiteId ON ops.[Order](ClientSiteId);
CREATE INDEX IX_Order_StatusId ON ops.[Order](OrderStatusId);
CREATE INDEX IX_Assignment_OrderId ON ops.Assignment(OrderId);
CREATE INDEX IX_Assignment_EmployeeId ON ops.Assignment(EmployeeId);
CREATE INDEX IX_Timesheet_Employee_Period ON ops.Timesheet(EmployeeId, PeriodStart, PeriodEnd);
CREATE INDEX IX_TimesheetLine_TimesheetId ON ops.TimesheetLine(TimesheetId);
CREATE INDEX IX_Invoice_Company_Period ON ops.Invoice(ClientCompanyId, PeriodStart, PeriodEnd);
CREATE INDEX IX_InvoiceLine_InvoiceId ON ops.InvoiceLine(InvoiceId);
GO

--------------------------------------------------------------------------------
/* 6) AUDIT TABLE
    audit.ChangeLog (generic napló: mi, mikor, ki, régi/új JSON) */
--------------------------------------------------------------------------------
CREATE TABLE audit.ChangeLog (
    ChangeLogId bigint IDENTITY(1,1) NOT NULL CONSTRAINT PK_ChangeLog PRIMARY KEY,
    ChangeAt datetime2(0) NOT NULL CONSTRAINT DF_ChangeLog_ChangeAt DEFAULT (SYSUTCDATETIME()),
    ChangeBy sysname NOT NULL CONSTRAINT DF_ChangeLog_ChangeBy DEFAULT (SUSER_SNAME()),
    SchemaName sysname NOT NULL,
    TableName sysname NOT NULL,
    ActionType varchar(10) NOT NULL,
    KeyValue nvarchar(200) NOT NULL,
    OldData nvarchar(max) NULL,
    NewData nvarchar(max) NULL
);
GO

CREATE TRIGGER ops.tr_Order_Audit
ON ops.[Order]
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Schema sysname = N'ops';
    DECLARE @Table sysname = N'Order';

    INSERT INTO audit.ChangeLog (SchemaName, TableName, ActionType, KeyValue, OldData, NewData)
    SELECT @Schema, @Table, 'INSERT',
           CONCAT('OrderId=', i.OrderId),
           NULL,
           (SELECT i.OrderId, i.OrderNumber, i.ClientCompanyId, i.ClientSiteId, i.JobRoleId, i.OrderStatusId,
                   i.HeadcountRequested, i.StartDate, i.EndDate, i.HourlyRateHuf, i.Notes
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
    FROM inserted i
    LEFT JOIN deleted d ON d.OrderId = i.OrderId
    WHERE d.OrderId IS NULL;

    INSERT INTO audit.ChangeLog (SchemaName, TableName, ActionType, KeyValue, OldData, NewData)
    SELECT @Schema, @Table, 'DELETE',
           CONCAT('OrderId=', d.OrderId),
           (SELECT d.OrderId, d.OrderNumber, d.ClientCompanyId, d.ClientSiteId, d.JobRoleId, d.OrderStatusId,
                   d.HeadcountRequested, d.StartDate, d.EndDate, d.HourlyRateHuf, d.Notes
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
           NULL
    FROM deleted d
    LEFT JOIN inserted i ON i.OrderId = d.OrderId
    WHERE i.OrderId IS NULL;

    INSERT INTO audit.ChangeLog (SchemaName, TableName, ActionType, KeyValue, OldData, NewData)
    SELECT @Schema, @Table, 'UPDATE',
           CONCAT('OrderId=', i.OrderId),
           (SELECT d.OrderId, d.OrderNumber, d.ClientCompanyId, d.ClientSiteId, d.JobRoleId, d.OrderStatusId,
                   d.HeadcountRequested, d.StartDate, d.EndDate, d.HourlyRateHuf, d.Notes
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
           (SELECT i.OrderId, i.OrderNumber, i.ClientCompanyId, i.ClientSiteId, i.JobRoleId, i.OrderStatusId,
                   i.HeadcountRequested, i.StartDate, i.EndDate, i.HourlyRateHuf, i.Notes
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
    FROM inserted i
    INNER JOIN deleted d ON d.OrderId = i.OrderId;
END
GO

--------------------------------------------------------------------------------
-- 7) Overlap tiltás (defense-in-depth)
--------------------------------------------------------------------------------
CREATE OR ALTER FUNCTION dbo.fnOverlaps(@aStart date, @aEnd date, @bStart date, @bEnd date)
RETURNS bit
AS
BEGIN
    RETURN IIF(@aStart <= @bEnd AND @bStart <= @aEnd, 1, 0);
END
GO

CREATE TRIGGER ops.tr_Assignment_NoOverlap
ON ops.Assignment
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (
        SELECT 1
        FROM ops.Assignment a
        INNER JOIN inserted i ON i.EmployeeId = a.EmployeeId
        WHERE a.AssignmentId <> i.AssignmentId
          AND dbo.fnOverlaps(a.StartDate, a.EndDate, i.StartDate, i.EndDate) = 1
          AND a.AssignmentStatusId IN (SELECT AssignmentStatusId FROM ref.AssignmentStatus WHERE Code IN ('PLANNED','ACTIVE'))
          AND i.AssignmentStatusId IN (SELECT AssignmentStatusId FROM ref.AssignmentStatus WHERE Code IN ('PLANNED','ACTIVE'))
    )
    BEGIN
        RAISERROR(N'Átfedő kiközvetítés nem engedélyezett ugyanarra a munkavállalóra (PLANNED/ACTIVE).', 16, 1);
        ROLLBACK TRANSACTION;
        RETURN;
    END
END
GO

--------------------------------------------------------------------------------
/* 8) VIEW-k (reporting):
    ops.vActiveAssignments (aktuális kiközvetítések)
    ops.vOrderFillRate (megbízás betöltöttség: kiosztott fő / kért fő)
    ops.vBillableHoursMonthly (havi számlázható órák ügyfelenként) */
--------------------------------------------------------------------------------
CREATE OR ALTER VIEW ops.vActiveAssignments
AS
SELECT
    a.AssignmentId,
    a.StartDate,
    a.EndDate,
    es.Code AS AssignmentStatus,
    e.EmployeeNumber,
    p.FamilyName,
    p.GivenName,
    o.OrderNumber,
    cc.Name AS ClientCompany,
    cs.SiteName AS ClientSite,
    jr.NameHu AS JobRoleHu
FROM ops.Assignment a
JOIN ref.AssignmentStatus es ON es.AssignmentStatusId = a.AssignmentStatusId
JOIN core.Employee e ON e.EmployeeId = a.EmployeeId
JOIN core.Person p ON p.PersonId = e.PersonId
JOIN ops.[Order] o ON o.OrderId = a.OrderId
JOIN core.ClientCompany cc ON cc.ClientCompanyId = o.ClientCompanyId
JOIN core.ClientSite cs ON cs.ClientSiteId = o.ClientSiteId
JOIN core.JobRole jr ON jr.JobRoleId = o.JobRoleId
WHERE es.Code = 'ACTIVE';
GO

CREATE OR ALTER VIEW ops.vOrderFillRate
AS
SELECT
    o.OrderId,
    o.OrderNumber,
    cc.Name AS ClientCompany,
    o.HeadcountRequested,
    AssignedCount = COUNT(CASE WHEN ast.Code IN ('PLANNED','ACTIVE') THEN 1 END),
    FillRate = CAST(
        CASE WHEN o.HeadcountRequested = 0 THEN 0
             ELSE (100.0 * COUNT(CASE WHEN ast.Code IN ('PLANNED','ACTIVE') THEN 1 END) / o.HeadcountRequested)
        END
        AS decimal(6,2)
    )
FROM ops.[Order] o
JOIN core.ClientCompany cc ON cc.ClientCompanyId = o.ClientCompanyId
LEFT JOIN ops.Assignment a ON a.OrderId = o.OrderId
LEFT JOIN ref.AssignmentStatus ast ON ast.AssignmentStatusId = a.AssignmentStatusId
GROUP BY o.OrderId, o.OrderNumber, cc.Name, o.HeadcountRequested;
GO

CREATE OR ALTER VIEW ops.vBillableHoursMonthly
AS
SELECT
    cc.Name AS ClientCompany,
    YearMonth = CONVERT(char(7), tl.WorkDate, 120),
    BillableHours = SUM(tl.Hours * pt.Multiplier),
    NetHuf = SUM(ROUND((tl.Hours * pt.Multiplier) * o.HourlyRateHuf, 2))
FROM ops.TimesheetLine tl
JOIN ops.Timesheet t ON t.TimesheetId = tl.TimesheetId
LEFT JOIN ops.[Order] o ON o.OrderId = tl.OrderId
LEFT JOIN core.ClientCompany cc ON cc.ClientCompanyId = o.ClientCompanyId
JOIN ref.PayType pt ON pt.PayTypeId = tl.PayTypeId
GROUP BY cc.Name, CONVERT(char(7), tl.WorkDate, 120);
GO

--------------------------------------------------------------------------------
/* 9) Tárolt eljárások (CRUD + üzleti logika)
    ops.uspCreateOrder
    ops.uspAssignEmployeeToOrder
    ops.uspSubmitTimesheet
    ops.uspGenerateInvoiceFromTimesheet (egyszerűsített számlagenerálás)
    Minden SP-ben:
        SET NOCOUNT ON;
        TRY...CATCH + saját hibakód / log
        tranzakció ahol kell*/
--------------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE ops.uspCreateOrder
    @ClientCompanyId int,
    @ClientSiteId int,
    @JobRoleId int,
    @HeadcountRequested int,
    @StartDate date,
    @EndDate date,
    @HourlyRateHuf decimal(12,2),
    @Notes nvarchar(400) = NULL,
    @OrderId int OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        DECLARE @OrderStatusId tinyint = (SELECT OrderStatusId FROM ref.OrderStatus WHERE Code = 'OPEN');

        DECLARE @OrderNumber varchar(30) =
            CONCAT('ORD-', FORMAT(SYSUTCDATETIME(), 'yyyyMMdd'), '-', RIGHT(CONVERT(varchar(36), NEWID()), 6));

        INSERT INTO ops.[Order](
            OrderNumber, ClientCompanyId, ClientSiteId, JobRoleId, OrderStatusId,
            HeadcountRequested, StartDate, EndDate, HourlyRateHuf, Notes
        )
        VALUES(
            @OrderNumber, @ClientCompanyId, @ClientSiteId, @JobRoleId, @OrderStatusId,
            @HeadcountRequested, @StartDate, @EndDate, @HourlyRateHuf, @Notes
        );

        SET @OrderId = SCOPE_IDENTITY();
    END TRY
    BEGIN CATCH
        DECLARE @msg nvarchar(4000) = ERROR_MESSAGE();
        RAISERROR(N'uspCreateOrder hiba: %s', 16, 1, @msg);
    END CATCH
END
GO

Audit trigger 1 táblára (pl. ops.Order) → audit.ChangeLog
CREATE OR ALTER PROCEDURE ops.uspAssignEmployeeToOrder
    @OrderId int,
    @EmployeeId int,
    @StartDate date,
    @EndDate date,
    @AssignmentId int OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRAN;

        DECLARE @oStart date, @oEnd date;
        SELECT @oStart = StartDate, @oEnd = EndDate
        FROM ops.[Order]
        WHERE OrderId = @OrderId;

        IF @oStart IS NULL
            THROW 50001, 'Order nem létezik.', 1;

        IF @StartDate < @oStart OR @EndDate > @oEnd
            THROW 50002, 'Assignment időszaka kívül esik az Order időszakán.', 1;

        IF EXISTS (
            SELECT 1
            FROM ops.Assignment a
            JOIN ref.AssignmentStatus s ON s.AssignmentStatusId = a.AssignmentStatusId
            WHERE a.EmployeeId = @EmployeeId
              AND s.Code IN ('PLANNED','ACTIVE')
              AND dbo.fnOverlaps(a.StartDate, a.EndDate, @StartDate, @EndDate) = 1
        )
            THROW 50003, 'Átfedő kiközvetítés (PLANNED/ACTIVE) a munkavállalónál.', 1;

        DECLARE @statusId tinyint = (SELECT AssignmentStatusId FROM ref.AssignmentStatus WHERE Code='PLANNED');

        INSERT INTO ops.Assignment(OrderId, EmployeeId, AssignmentStatusId, StartDate, EndDate)
        VALUES (@OrderId, @EmployeeId, @statusId, @StartDate, @EndDate);

        SET @AssignmentId = SCOPE_IDENTITY();

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        DECLARE @msg nvarchar(4000) = ERROR_MESSAGE();
        RAISERROR(N'uspAssignEmployeeToOrder hiba: %s', 16, 1, @msg);
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE ops.uspSubmitTimesheet
    @EmployeeId int,
    @PeriodStart date,
    @PeriodEnd date,
    @Submit bit = 1,
    @TimesheetId int OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRAN;

        INSERT INTO ops.Timesheet(EmployeeId, PeriodStart, PeriodEnd, SubmittedAt)
        VALUES (@EmployeeId, @PeriodStart, @PeriodEnd, CASE WHEN @Submit=1 THEN SYSUTCDATETIME() END);

        SET @TimesheetId = SCOPE_IDENTITY();

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        DECLARE @msg nvarchar(4000) = ERROR_MESSAGE();
        RAISERROR(N'uspSubmitTimesheet hiba: %s', 16, 1, @msg);
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE ops.uspGenerateInvoiceFromTimesheet
    @ClientCompanyId int,
    @PeriodStart date,
    @PeriodEnd date,
    @IssueDate date = NULL,
    @DueDays int = 15,
    @InvoiceId int OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRAN;

        IF @IssueDate IS NULL SET @IssueDate = CAST(GETDATE() AS date);

        DECLARE @InvoiceNumber varchar(30) =
            CONCAT('INV-', FORMAT(SYSUTCDATETIME(), 'yyyyMMdd'), '-', RIGHT(CONVERT(varchar(36), NEWID()), 6));

        INSERT INTO ops.Invoice(InvoiceNumber, ClientCompanyId, PeriodStart, PeriodEnd, IssueDate, DueDate, TotalNetHuf)
        VALUES(@InvoiceNumber, @ClientCompanyId, @PeriodStart, @PeriodEnd, @IssueDate, DATEADD(day, @DueDays, @IssueDate), 0);

        SET @InvoiceId = SCOPE_IDENTITY();

        ;WITH lines AS (
            SELECT
                tl.OrderId,
                Qty = SUM(tl.Hours * pt.Multiplier),
                UnitPrice = MAX(o.HourlyRateHuf),
                DescTxt = CONCAT(N'Szolgáltatás (óra) - ', MAX(o.OrderNumber))
            FROM ops.TimesheetLine tl
            JOIN ops.Timesheet t ON t.TimesheetId = tl.TimesheetId
            JOIN ref.PayType pt ON pt.PayTypeId = tl.PayTypeId
            JOIN ops.[Order] o ON o.OrderId = tl.OrderId
            WHERE tl.WorkDate BETWEEN @PeriodStart AND @PeriodEnd
              AND o.ClientCompanyId = @ClientCompanyId
              AND tl.OrderId IS NOT NULL
            GROUP BY tl.OrderId
        )
        INSERT INTO ops.InvoiceLine(InvoiceId, OrderId, Description, Quantity, UnitPriceHuf)
        SELECT @InvoiceId, OrderId, DescTxt, Qty, UnitPrice
        FROM lines
        WHERE Qty > 0;

        UPDATE i
          SET TotalNetHuf = (
              SELECT ISNULL(SUM(il.LineNetHuf), 0)
              FROM ops.InvoiceLine il
              WHERE il.InvoiceId = i.InvoiceId
          )
        FROM ops.Invoice i
        WHERE i.InvoiceId = @InvoiceId;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        DECLARE @msg nvarchar(4000) = ERROR_MESSAGE();
        RAISERROR(N'uspGenerateInvoiceFromTimesheet hiba: %s', 16, 1, @msg);
    END CATCH
END
GO

/*==============================================================================
  ops.uspRefreshOrderStatus
  Cél: Üzleti logika alapján Order státusz frissítés (pl. OPEN -> FILLED)

  Üzleti szabály (példa):
  - Ha egy Order-hez tartozó PLANNED/ACTIVE assignment-ek száma >= HeadcountRequested,
    akkor az Order "betöltött" (FILLED) státuszba kerülhet.

  Miért jó?
  - Szabály-alapú státuszkezelés (business logic)
  - TRY/CATCH + TRAN (adatkonzisztencia)
  - "Dry-run" mód (először nézd meg, mit frissítene)
  - A módosításokat a meglévő audit trigger naplózza (audit.ChangeLog)
==============================================================================*/
GO
CREATE OR ALTER PROCEDURE ops.uspRefreshOrderStatus
    @FromStatusCode varchar(20) = 'OPEN',     -- honnan
    @ToStatusCode   varchar(20) = 'FILLED',   -- hova
    @Execute bit = 0                          -- 0 = csak riport (dry-run), 1 = végrehajt
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        DECLARE @FromStatusId tinyint = (SELECT OrderStatusId FROM ref.OrderStatus WHERE Code = @FromStatusCode);
        DECLARE @ToStatusId   tinyint = (SELECT OrderStatusId FROM ref.OrderStatus WHERE Code = @ToStatusCode);

        IF @FromStatusId IS NULL
            THROW 50010, 'Ismeretlen @FromStatusCode (ref.OrderStatus.Code).', 1;

        IF @ToStatusId IS NULL
            THROW 50011, 'Ismeretlen @ToStatusCode (ref.OrderStatus.Code).', 1;

        /*----------------------------------------------------------------------
          Candidate halmaz: azok az Order-ök, amelyek:
          - jelenleg @FromStatusCode státuszban vannak (pl. OPEN)
          - és a PLANNED/ACTIVE assignment-ek száma eléri a kért létszámot
        ----------------------------------------------------------------------*/
        ;WITH candidates AS (
            SELECT
                o.OrderId,
                o.OrderNumber,
                o.ClientCompanyId,
                o.HeadcountRequested,
                AssignedCount = COUNT(CASE WHEN ast.Code IN ('PLANNED','ACTIVE') THEN 1 END)
            FROM ops.[Order] o
            LEFT JOIN ops.Assignment a ON a.OrderId = o.OrderId
            LEFT JOIN ref.AssignmentStatus ast ON ast.AssignmentStatusId = a.AssignmentStatusId
            WHERE o.OrderStatusId = @FromStatusId
            GROUP BY o.OrderId, o.OrderNumber, o.ClientCompanyId, o.HeadcountRequested
            HAVING COUNT(CASE WHEN ast.Code IN ('PLANNED','ACTIVE') THEN 1 END) >= o.HeadcountRequested
        )
        SELECT TOP 100
            c.OrderId,
            c.OrderNumber,
            cc.Name AS ClientCompany,
            c.HeadcountRequested,
            c.AssignedCount,
            FillRatePct = CAST(CASE WHEN c.HeadcountRequested = 0 THEN 0
                                    ELSE (100.0 * c.AssignedCount / c.HeadcountRequested)
                               END AS decimal(6,2)),
            ActionPlanned = CASE WHEN @Execute = 1 THEN 'WILL UPDATE' ELSE 'DRY RUN' END
        FROM candidates c
        JOIN core.ClientCompany cc ON cc.ClientCompanyId = c.ClientCompanyId
        ORDER BY c.OrderId DESC;

        -- Ha csak dry-run, itt vége (nem módosítunk semmit)
        IF @Execute = 0
            RETURN;

        BEGIN TRAN;

        /*----------------------------------------------------------------------
          UPDATE: @FromStatusId -> @ToStatusId azon Order-ökre, amelyek
          megfelelnek a candidate szabálynak.
          OUTPUT-tal visszaadjuk, mely sorokat állította át.
        ----------------------------------------------------------------------*/
        DECLARE @Changed TABLE (
            OrderId int NOT NULL,
            OrderNumber varchar(30) NOT NULL,
            OldStatusId tinyint NOT NULL,
            NewStatusId tinyint NOT NULL,
            ChangedAt datetime2(0) NOT NULL
        );

        ;WITH candidates AS (
            SELECT
                o.OrderId
            FROM ops.[Order] o
            LEFT JOIN ops.Assignment a ON a.OrderId = o.OrderId
            LEFT JOIN ref.AssignmentStatus ast ON ast.AssignmentStatusId = a.AssignmentStatusId
            WHERE o.OrderStatusId = @FromStatusId
            GROUP BY o.OrderId, o.HeadcountRequested
            HAVING COUNT(CASE WHEN ast.Code IN ('PLANNED','ACTIVE') THEN 1 END) >= o.HeadcountRequested
        )
        UPDATE o
            SET o.OrderStatusId = @ToStatusId
        OUTPUT
            inserted.OrderId,
            inserted.OrderNumber,
            deleted.OrderStatusId,
            inserted.OrderStatusId,
            SYSUTCDATETIME()
        INTO @Changed(OrderId, OrderNumber, OldStatusId, NewStatusId, ChangedAt)
        FROM ops.[Order] o
        JOIN candidates c ON c.OrderId = o.OrderId;

        COMMIT;

        -- Összefoglaló: hány sort érintett
        SELECT AffectedRows = COUNT(*) FROM @Changed;

        -- Részletek: mely Order-öket állította át
        SELECT
            ch.OrderId,
            ch.OrderNumber,
            OldStatus = osFrom.Code,
            NewStatus = osTo.Code,
            ch.ChangedAt
        FROM @Changed ch
        JOIN ref.OrderStatus osFrom ON osFrom.OrderStatusId = ch.OldStatusId
        JOIN ref.OrderStatus osTo   ON osTo.OrderStatusId   = ch.NewStatusId
        ORDER BY ch.ChangedAt DESC, ch.OrderId DESC;

        -- Megjegyzés:
        -- A tényleges változásnapló (régi/új JSON) a ops.tr_Order_Audit trigger miatt
        -- automatikusan bekerül az audit.ChangeLog táblába.
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;

        DECLARE @Err nvarchar(4000) = ERROR_MESSAGE();
        DECLARE @Num int = ERROR_NUMBER();
        DECLARE @Line int = ERROR_LINE();

        RAISERROR(N'uspRefreshOrderStatus hiba (%d) a %d. sorban: %s', 16, 1, @Num, @Line, @Err);
        RETURN;
    END CATCH
END
GO


--------------------------------------------------------------------------------
/* 10) SECURITY (szerepkörök, jogosultságok) Role-ok:
    rl_ops (operáció – megbízás, assignment)
    rl_payroll (timesheet)
    rl_finance (invoice)
    rl_readonly (csak view-k)
    Példa: táblákhoz nincs direkt SELECT, csak view-kon keresztül riporthoz. */
--------------------------------------------------------------------------------
CREATE ROLE rl_ops;
CREATE ROLE rl_payroll;
CREATE ROLE rl_finance;
CREATE ROLE rl_readonly;

GRANT SELECT ON ops.vActiveAssignments TO rl_readonly;
GRANT SELECT ON ops.vOrderFillRate TO rl_readonly;
GRANT SELECT ON ops.vBillableHoursMonthly TO rl_readonly;

GRANT EXECUTE ON ops.uspCreateOrder TO rl_ops;
GRANT EXECUTE ON ops.uspAssignEmployeeToOrder TO rl_ops;

GRANT EXECUTE ON ops.uspSubmitTimesheet TO rl_payroll;
GRANT INSERT, SELECT ON ops.Timesheet TO rl_payroll;
GRANT INSERT, SELECT ON ops.TimesheetLine TO rl_payroll;

GRANT EXECUTE ON ops.uspGenerateInvoiceFromTimesheet TO rl_finance;
GRANT SELECT, INSERT, UPDATE ON ops.Invoice TO rl_finance;
GRANT SELECT, INSERT ON ops.InvoiceLine TO rl_finance;
GO

--------------------------------------------------------------------------------
-- 11) DEMO ADATFELTÖLTÉS (stabil, GDPR-barát)
--------------------------------------------------------------------------------
PRINT 'Seeding demo data...';

INSERT INTO core.JobRole(Code, NameHu, NameEn) VALUES
('WAREHOUSE', N'Raktári dolgozó', 'Warehouse worker'),
('CASHIER',   N'Pénztáros', 'Cashier'),
('OPERATOR',  N'Gépkezelő', 'Machine operator'),
('DRIVER',    N'Sofőr', 'Driver'),
('ADMIN',     N'Irodai admin', 'Office admin'),
('QC',        N'Minőségellenőr', 'Quality inspector');

INSERT INTO core.ClientCompany(Name, TaxNumberHash) VALUES
(N'Acme Manufacturing Kft.', HASHBYTES('SHA2_256', CONVERT(varbinary(200), N'DEMO-ACME-TAX'))),
(N'BlueRiver Logistics Zrt.', HASHBYTES('SHA2_256', CONVERT(varbinary(200), N'DEMO-BLR-TAX'))),
(N'GreenMart Retail Kft.', HASHBYTES('SHA2_256', CONVERT(varbinary(200), N'DEMO-GM-TAX'))),
(N'SunSteel Industry Kft.', HASHBYTES('SHA2_256', CONVERT(varbinary(200), N'DEMO-SS-TAX'))),
(N'NovaServices Bt.', HASHBYTES('SHA2_256', CONVERT(varbinary(200), N'DEMO-NS-TAX')));

INSERT INTO core.ClientSite(ClientCompanyId, SiteName, City, AddressLine) VALUES
(1, N'Üzem 1', N'Miskolc', N'Demo utca 1.'),
(1, N'Üzem 2', N'Budapest', N'Demo utca 2.'),
(2, N'Raktár A', N'Budapest', N'Demo köz 10.'),
(2, N'Raktár B', N'Győr', N'Demo köz 11.'),
(3, N'Áruház Központ', N'Szeged', N'Demo tér 5.'),
(3, N'Áruház 2', N'Debrecen', N'Demo tér 6.'),
(4, N'Gyártósor', N'Kecskemét', N'Demo ipartelep 3.'),
(5, N'Iroda', N'Budapest', N'Demo irodaház 7.');

DECLARE @FirstNames TABLE(n nvarchar(80));
DECLARE @LastNames TABLE(n nvarchar(80));

INSERT INTO @FirstNames(n) VALUES
(N'Anna'),(N'Bence'),(N'Csilla'),(N'Dániel'),(N'Eszter'),
(N'Ferenc'),(N'Gábor'),(N'Hajnalka'),(N'István'),(N'Júlia'),
(N'Kata'),(N'László'),(N'Márk'),(N'Nóra'),(N'Olga'),
(N'Péter'),(N'Réka'),(N'Sándor'),(N'Tamás'),(N'Zsófia');

INSERT INTO @LastNames(n) VALUES
(N'Kovács'),(N'Szabó'),(N'Tóth'),(N'Varga'),(N'Kiss'),
(N'Molnár'),(N'Nagy'),(N'Balogh'),(N'Farkas'),(N'Papp'),
(N'Lakatos'),(N'Kocsis'),(N'Fekete'),(N'Horváth'),(N'Oláh'),
(N'Mészáros'),(N'Simon'),(N'Rácz'),(N'Boros'),(N'Gulyás');

;WITH rn AS (
    SELECT TOP (20)
           ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS RowNum
    FROM sys.all_objects
)
INSERT INTO core.Person(GivenName, FamilyName, Email, Phone, IsDemoData, ConsentToContact, DataRetentionUntil)
SELECT
    fn.n,
    ln.n,
    CONCAT(
        LOWER(REPLACE(fn.n, N' ', N'')), N'.',
        LOWER(REPLACE(ln.n, N' ', N'')), rn.RowNum,
        N'@example.invalid'
    ),
    CONCAT(N'+36', RIGHT(CONCAT('000000000', CAST(ABS(CHECKSUM(NEWID())) % 1000000000 AS varchar(9))), 9)),
    1,
    0,
    DATEADD(day, 365, CAST(GETDATE() AS date))
FROM rn
CROSS APPLY (SELECT TOP 1 n FROM @FirstNames ORDER BY NEWID()) fn
CROSS APPLY (SELECT TOP 1 n FROM @LastNames ORDER BY NEWID()) ln;

DECLARE @ActiveEmpStatus tinyint = (SELECT EmployeeStatusId FROM ref.EmployeeStatus WHERE Code='ACTIVE');

INSERT INTO core.Employee(PersonId, EmployeeNumber, EmployeeStatusId, StartDate, GovernmentIdHash)
SELECT
    p.PersonId,
    CONCAT('EMP-', RIGHT(CONCAT('0000', CAST(p.PersonId AS varchar(10))), 4)),
    @ActiveEmpStatus,
    DATEADD(day, -(ABS(CHECKSUM(NEWID())) % 365), CAST(GETDATE() AS date)),
    HASHBYTES('SHA2_256', CONVERT(varbinary(200), CONCAT(N'DEMO-GOV-', p.PersonId, N'-', NEWID())))
FROM core.Person p;

-- Random Order-ok (10 db)
DECLARE @i int = 1;
WHILE @i <= 10
BEGIN
    DECLARE @OrderId int;
    DECLARE @CompanyId int = (SELECT TOP 1 ClientCompanyId FROM core.ClientCompany ORDER BY NEWID());
    DECLARE @SiteId int = (SELECT TOP 1 ClientSiteId FROM core.ClientSite WHERE ClientCompanyId=@CompanyId ORDER BY NEWID());
    DECLARE @JobRoleId int = (SELECT TOP 1 JobRoleId FROM core.JobRole ORDER BY NEWID());

    DECLARE @Start date = DATEADD(day, (ABS(CHECKSUM(NEWID())) % 20), CAST(GETDATE() AS date));
    DECLARE @End date = DATEADD(day, 30 + (ABS(CHECKSUM(NEWID())) % 30), @Start);
    DECLARE @Headcount int = 1 + (ABS(CHECKSUM(NEWID())) % 5);
    DECLARE @Rate decimal(12,2) = 1800 + (ABS(CHECKSUM(NEWID())) % 2200);

    EXEC ops.uspCreateOrder
        @ClientCompanyId=@CompanyId,
        @ClientSiteId=@SiteId,
        @JobRoleId=@JobRoleId,
        @HeadcountRequested=@Headcount,
        @StartDate=@Start,
        @EndDate=@End,
        @HourlyRateHuf=@Rate,
        @Notes=N'DEMO order',
        @OrderId=@OrderId OUTPUT;

    SET @i += 1;
END

-- Assignments (kb. 25 db)
DECLARE @ActiveStatus tinyint = (SELECT AssignmentStatusId FROM ref.AssignmentStatus WHERE Code='ACTIVE');

DECLARE @a int = 1;
WHILE @a <= 25
BEGIN
    DECLARE @OrderId2 int = (SELECT TOP 1 OrderId FROM ops.[Order] ORDER BY NEWID());
    DECLARE @EmpId int = (SELECT TOP 1 EmployeeId FROM core.Employee ORDER BY NEWID());
    DECLARE @os date, @oe date;
    SELECT @os=StartDate, @oe=EndDate FROM ops.[Order] WHERE OrderId=@OrderId2;

    DECLARE @as date = DATEADD(day, (ABS(CHECKSUM(NEWID())) % 10), @os);
    DECLARE @ae date = DATEADD(day, 10 + (ABS(CHECKSUM(NEWID())) % 20), @as);
    IF @ae > @oe SET @ae = @oe;

    DECLARE @AssignmentId int;

    BEGIN TRY
        EXEC ops.uspAssignEmployeeToOrder
            @OrderId=@OrderId2,
            @EmployeeId=@EmpId,
            @StartDate=@as,
            @EndDate=@ae,
            @AssignmentId=@AssignmentId OUTPUT;

        IF (ABS(CHECKSUM(NEWID())) % 2) = 0
            UPDATE ops.Assignment SET AssignmentStatusId=@ActiveStatus WHERE AssignmentId=@AssignmentId;
    END TRY
    BEGIN CATCH
        -- overlap esetén tovább lépünk
    END CATCH

    SET @a += 1;
END

-- Timesheet-ek (10 db) + sorok
DECLARE @t int = 1;
WHILE @t <= 10
BEGIN
    DECLARE @EmpId2 int = (SELECT TOP 1 EmployeeId FROM core.Employee ORDER BY NEWID());
    DECLARE @PeriodStart date = DATEADD(day, -14, CAST(GETDATE() AS date));
    DECLARE @PeriodEnd date = DATEADD(day, -1, CAST(GETDATE() AS date));
    DECLARE @TimesheetId int;

    EXEC ops.uspSubmitTimesheet
        @EmployeeId=@EmpId2,
        @PeriodStart=@PeriodStart,
        @PeriodEnd=@PeriodEnd,
        @Submit=1,
        @TimesheetId=@TimesheetId OUTPUT;

    DECLARE @lines int = 5 + (ABS(CHECKSUM(NEWID())) % 4);
    DECLARE @k int = 1;

    WHILE @k <= @lines
    BEGIN
        DECLARE @wd date = DATEADD(day, (ABS(CHECKSUM(NEWID())) % 14), @PeriodStart);
        DECLARE @hrs decimal(5,2) = CAST(4 + (ABS(CHECKSUM(NEWID())) % 5) AS decimal(5,2));
        DECLARE @pay tinyint = (SELECT TOP 1 PayTypeId FROM ref.PayType ORDER BY NEWID());

        DECLARE @AnyAssign int = (
            SELECT TOP 1 a.AssignmentId
            FROM ops.Assignment a
            WHERE a.EmployeeId = @EmpId2
            ORDER BY NEWID()
        );

        DECLARE @OrderId3 int = NULL;
        IF @AnyAssign IS NOT NULL
            SELECT @OrderId3 = OrderId FROM ops.Assignment WHERE AssignmentId = @AnyAssign;

        INSERT INTO ops.TimesheetLine(TimesheetId, WorkDate, Hours, PayTypeId, OrderId, AssignmentId)
        VALUES(@TimesheetId, @wd, @hrs, @pay, @OrderId3, @AnyAssign);

        SET @k += 1;
    END

    SET @t += 1;
END

-- Számlák generálása
DECLARE @InvPeriodStart date = CONVERT(date, GETDATE() - 14);
DECLARE @InvPeriodEnd   date = CONVERT(date, GETDATE() - 1);
DECLARE @InvIssueDate   date = CONVERT(date, GETDATE());

DECLARE @c int = 1;
WHILE @c <= 3
BEGIN
    DECLARE @CompanyId2 int = (SELECT TOP 1 ClientCompanyId FROM core.ClientCompany ORDER BY NEWID());
    DECLARE @InvId int;

    EXEC ops.uspGenerateInvoiceFromTimesheet
        @ClientCompanyId = @CompanyId2,
        @PeriodStart     = @InvPeriodStart,
        @PeriodEnd       = @InvPeriodEnd,
        @IssueDate       = @InvIssueDate,
        @DueDays         = 15,
        @InvoiceId       = @InvId OUTPUT;

    SET @c += 1;
END

PRINT 'Demo data ready.';
GO

/* 
============================================================================
12) SQL AGENT JOB-OK (MENTÉSEK) – DEMO ONLY
--------------------------------------------------------------------------
Ez a blokk csak bemutató jellegű. Portfolio repo-ban maradhat,
de futtatása opcionális és környezetfüggő (SQL Agent, path, jogosultság).
--     A backup útvonal: @BackupDir (a script elején).
============================================================================

USE msdb;
GO

-- Biztonság: töröljük, ha már léteznek (idempotens jelleg)
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'StaffingPro - Weekly FULL Backup')
    EXEC msdb.dbo.sp_delete_job @job_name = N'StaffingPro - Weekly FULL Backup';

IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'StaffingPro - Daily DIFF Backup')
    EXEC msdb.dbo.sp_delete_job @job_name = N'StaffingPro - Daily DIFF Backup';

IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'StaffingPro - Log Backup (15 min)')
    EXEC msdb.dbo.sp_delete_job @job_name = N'StaffingPro - Log Backup (15 min)';
GO

DECLARE @BackupDir nvarchar(260) = N'C:\SQLBackups\StaffingPro'; -- <-- ha módosítod fent, itt is módosítsd!
DECLARE @Db sysname = N'StaffingPro';

--------------------------------------------------------------------------------
-- 13.1) Heti FULL backup (vasárnap 02:00)
--------------------------------------------------------------------------------
DECLARE @jobId uniqueidentifier;

EXEC msdb.dbo.sp_add_job
    @job_name = N'StaffingPro - Weekly FULL Backup',
    @enabled = 1,
    @description = N'Weekly FULL backup for StaffingPro',
    @category_name = N'Database Maintenance',
    @owner_login_name = SUSER_SNAME(),
    @job_id = @jobId OUTPUT;

EXEC msdb.dbo.sp_add_jobstep
    @job_id = @jobId,
    @step_name = N'FULL Backup',
    @subsystem = N'TSQL',
    @database_name = N'master',
    @command = N'
DECLARE @dir nvarchar(260)=N''' + @BackupDir + N''';
DECLARE @db sysname = N''' + @Db + N''';
DECLARE @file nvarchar(400)= CONCAT(@dir, N''\'', @db, N''_FULL_'', CONVERT(char(8), GETDATE(), 112), N''_'', REPLACE(CONVERT(char(8), GETDATE(), 108), '':'',''''), N''.bak'');
BACKUP DATABASE ' + QUOTENAME(@Db) + N'
TO DISK = @file
WITH INIT, COMPRESSION, CHECKSUM, STATS = 10;
RESTORE VERIFYONLY FROM DISK = @file WITH CHECKSUM;
';

-- Schedule: weekly Sunday 02:00
EXEC msdb.dbo.sp_add_schedule
    @schedule_name = N'StaffingPro - Weekly FULL (Sun 02:00)',
    @freq_type = 8,              -- weekly
    @freq_interval = 1,          -- Sunday
    @active_start_time = 020000; -- 02:00:00

EXEC msdb.dbo.sp_attach_schedule
    @job_id = @jobId,
    @schedule_name = N'StaffingPro - Weekly FULL (Sun 02:00)';

EXEC msdb.dbo.sp_add_jobserver
    @job_id = @jobId;
GO

--------------------------------------------------------------------------------
-- 13.2) Napi DIFF backup (H-Szo 02:00)
--------------------------------------------------------------------------------
DECLARE @jobId2 uniqueidentifier;

EXEC msdb.dbo.sp_add_job
    @job_name = N'StaffingPro - Daily DIFF Backup',
    @enabled = 1,
    @description = N'Daily differential backup for StaffingPro (Mon-Sat)',
    @category_name = N'Database Maintenance',
    @owner_login_name = SUSER_SNAME(),
    @job_id = @jobId2 OUTPUT;

EXEC msdb.dbo.sp_add_jobstep
    @job_id = @jobId2,
    @step_name = N'DIFF Backup',
    @subsystem = N'TSQL',
    @database_name = N'master',
    @command = N'
DECLARE @dir nvarchar(260)=N''' + @BackupDir + N''';
DECLARE @db sysname = N''' + @Db + N''';
DECLARE @file nvarchar(400)= CONCAT(@dir, N''\'', @db, N''_DIFF_'', CONVERT(char(8), GETDATE(), 112), N''_'', REPLACE(CONVERT(char(8), GETDATE(), 108), '':'',''''), N''.bak'');
BACKUP DATABASE ' + QUOTENAME(@Db) + N'
TO DISK = @file
WITH DIFFERENTIAL, INIT, COMPRESSION, CHECKSUM, STATS = 10;
RESTORE VERIFYONLY FROM DISK = @file WITH CHECKSUM;
';

-- Schedule: Mon-Sat 02:00 (freq_interval bitmask: Mon=2 Tue=4 Wed=8 Thu=16 Fri=32 Sat=64 => 2+4+8+16+32+64=126)
EXEC msdb.dbo.sp_add_schedule
    @schedule_name = N'StaffingPro - Daily DIFF (Mon-Sat 02:00)',
    @freq_type = 8,              -- weekly pattern used with bitmask for multiple days
    @freq_interval = 126,        -- Mon-Sat
    @active_start_time = 020000; -- 02:00:00

EXEC msdb.dbo.sp_attach_schedule
    @job_id = @jobId2,
    @schedule_name = N'StaffingPro - Daily DIFF (Mon-Sat 02:00)';

EXEC msdb.dbo.sp_add_jobserver
    @job_id = @jobId2;
GO

--------------------------------------------------------------------------------
13.3) Transaction LOG backup (15 percenként) – "tail job" jelleg
      Megjegyzés: FULL recovery model ajánlott log backuphoz.
--------------------------------------------------------------------------------
DECLARE @jobId3 uniqueidentifier;

EXEC msdb.dbo.sp_add_job
    @job_name = N'StaffingPro - Log Backup (15 min)',
    @enabled = 1,
    @description = N'Log backup every 15 minutes for StaffingPro',
    @category_name = N'Database Maintenance',
    @owner_login_name = SUSER_SNAME(),
    @job_id = @jobId3 OUTPUT;

EXEC msdb.dbo.sp_add_jobstep
    @job_id = @jobId3,
    @step_name = N'LOG Backup',
    @subsystem = N'TSQL',
    @database_name = N'master',
    @command = N'
-- Recovery model beállítás (portfolio célra):
IF EXISTS (SELECT 1 FROM sys.databases WHERE name = N''' + @Db + N''' AND recovery_model_desc <> ''FULL'')
BEGIN
    ALTER DATABASE ' + QUOTENAME(@Db) + N' SET RECOVERY FULL;
END

DECLARE @dir nvarchar(260)=N''' + @BackupDir + N''';
DECLARE @db sysname = N''' + @Db + N''';
DECLARE @file nvarchar(400)= CONCAT(@dir, N''\'', @db, N''_LOG_'', CONVERT(char(8), GETDATE(), 112), N''_'', REPLACE(CONVERT(char(8), GETDATE(), 108), '':'',''''), N''.trn'');
BACKUP LOG ' + QUOTENAME(@Db) + N'
TO DISK = @file
WITH INIT, COMPRESSION, CHECKSUM, STATS = 10;
';

-- Schedule: every 15 minutes
EXEC msdb.dbo.sp_add_schedule
    @schedule_name = N'StaffingPro - Log (Every 15 min)',
    @freq_type = 4,              -- daily
    @freq_interval = 1,          -- every day
    @freq_subday_type = 4,       -- minutes
    @freq_subday_interval = 15,  -- 15 minutes
    @active_start_time = 000000; -- start at midnight

EXEC msdb.dbo.sp_attach_schedule
    @job_id = @jobId3,
    @schedule_name = N'StaffingPro - Log (Every 15 min)';

EXEC msdb.dbo.sp_add_jobserver
    @job_id = @jobId3;
GO
*/
/*
--------------------------------------------------------------------------------
-- 14) DEMO lekérdezések
--------------------------------------------------------------------------------
PRINT '--- DEMO QUERIES ---';

SELECT TOP 10 * FROM ops.vOrderFillRate ORDER BY FillRate DESC;
SELECT TOP 10 * FROM ops.vActiveAssignments ORDER BY StartDate DESC;
SELECT TOP 10 * FROM ops.vBillableHoursMonthly ORDER BY YearMonth DESC;

SELECT TOP 10 InvoiceNumber, TotalNetHuf, IssueDate, DueDate
FROM ops.Invoice
ORDER BY InvoiceId DESC;

SELECT TOP 10 ChangeAt, ActionType, KeyValue
FROM audit.ChangeLog
ORDER BY ChangeLogId DESC;

PRINT 'DONE.';
GO

============================================================================ 
*/