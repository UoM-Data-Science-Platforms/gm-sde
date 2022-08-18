--┌────────────────────────────────────────┐
--│ Electronic Frailty Index common queries│
--└────────────────────────────────────────┘

-- OBJECTIVE: The common logic for 2 EFI queries. This is unlikely to be executed directly, but is used by the other queries.

-- INPUT: Takes three parameters
--	-	all-patients: boolean - (true/false) if true, then all patients are included, otherwise only those in the pre-existing #Patients table.
--	- gp-events-table: string - (table name) the name of the table containing the GP events. Usually is "RLS.vw_GP_Events" but can be anything with the columns: FK_Patient_Link_ID, EventDate, and SuppliedCode
--	- gp-medications-table: string - (table name) the name of the table containing the GP medications. Usually is "RLS.vw_GP_Medications" but can be anything with the columns: FK_Patient_Link_ID, MedicationDate, and SuppliedCode

-- OUTPUT: Two temp tables as follows:
--	#EfiEvents (FK_Patient_Link_ID,	Deficit, EventDate)
--	- FK_Patient_Link_ID - unique patient id
--	- Deficit - the deficit (e.g. 'diabetes/hypertension/falls')
--	- EventDate - the first occurance of the deficit
--
--	#PolypharmacyPeriods (FK_Patient_Link_ID,	DateFrom,	DateTo)
--	- FK_Patient_Link_ID - unique patient id
--	- DateFrom - the start date of the polypharmacy period
--	- DateTo - the end date of the polypharmacy period

-- First we load all the EFI specific code sets
--> CODESET efi-activity-limitation:1 efi-anaemia:1 efi-arthritis:1 efi-atrial-fibrillation:1 efi-chd:1 efi-ckd:1
--> CODESET efi-diabetes:1 efi-dizziness:1 efi-dyspnoea:1 efi-falls:1 efi-foot-problems:1 efi-fragility-fracture:1
--> CODESET efi-hearing-loss:1 efi-heart-failure:1 efi-heart-valve-disease:1 efi-housebound:1 efi-hypertension:1
--> CODESET efi-hypotension:1 efi-cognitive-problems:1 efi-mobility-problems:1 efi-osteoporosis:1
--> CODESET efi-parkinsons:1 efi-peptic-ulcer:1 efi-pvd:1 efi-care-requirement:1 efi-respiratory-disease:1
--> CODESET efi-skin-ulcer:1 efi-sleep-disturbance:1 efi-social-vulnerability:1 efi-stroke-tia:1 efi-thyroid-disorders:1
--> CODESET efi-urinary-incontinence:1 efi-urinary-system-disease:1 efi-vision-problems:1 efi-weight-loss:1 

-- Temp table for holding results of the subqueries below
IF OBJECT_ID('tempdb..#EfiEvents') IS NOT NULL DROP TABLE #EfiEvents;
CREATE TABLE #EfiEvents (
	FK_Patient_Link_ID BIGINT,
	Deficit VARCHAR(50),
	EventDate DATE
);

-- The following finds the first date for each (non-medication) deficit for each patient and adds them to the #EfiEvents table.
--> EXECUTE subquery-efi.sql all-patients:{param:all-patients} gp-events-table:{param:gp-events-table} efi-category:'activity-limitation'
--> EXECUTE subquery-efi.sql all-patients:{param:all-patients} gp-events-table:{param:gp-events-table} efi-category:'anaemia'
--> EXECUTE subquery-efi.sql all-patients:{param:all-patients} gp-events-table:{param:gp-events-table} efi-category:'arthritis'
--> EXECUTE subquery-efi.sql all-patients:{param:all-patients} gp-events-table:{param:gp-events-table} efi-category:'atrial-fibrillation'
--> EXECUTE subquery-efi.sql all-patients:{param:all-patients} gp-events-table:{param:gp-events-table} efi-category:'chd'
--> EXECUTE subquery-efi.sql all-patients:{param:all-patients} gp-events-table:{param:gp-events-table} efi-category:'ckd'
--> EXECUTE subquery-efi.sql all-patients:{param:all-patients} gp-events-table:{param:gp-events-table} efi-category:'diabetes'
--> EXECUTE subquery-efi.sql all-patients:{param:all-patients} gp-events-table:{param:gp-events-table} efi-category:'dizziness'
--> EXECUTE subquery-efi.sql all-patients:{param:all-patients} gp-events-table:{param:gp-events-table} efi-category:'dyspnoea'
--> EXECUTE subquery-efi.sql all-patients:{param:all-patients} gp-events-table:{param:gp-events-table} efi-category:'falls'
--> EXECUTE subquery-efi.sql all-patients:{param:all-patients} gp-events-table:{param:gp-events-table} efi-category:'foot-problems'
--> EXECUTE subquery-efi.sql all-patients:{param:all-patients} gp-events-table:{param:gp-events-table} efi-category:'fragility-fracture'
--> EXECUTE subquery-efi.sql all-patients:{param:all-patients} gp-events-table:{param:gp-events-table} efi-category:'hearing-loss'
--> EXECUTE subquery-efi.sql all-patients:{param:all-patients} gp-events-table:{param:gp-events-table} efi-category:'heart-failure'
--> EXECUTE subquery-efi.sql all-patients:{param:all-patients} gp-events-table:{param:gp-events-table} efi-category:'heart-valve-disease'
--> EXECUTE subquery-efi.sql all-patients:{param:all-patients} gp-events-table:{param:gp-events-table} efi-category:'housebound'
--> EXECUTE subquery-efi.sql all-patients:{param:all-patients} gp-events-table:{param:gp-events-table} efi-category:'hypertension'
--> EXECUTE subquery-efi.sql all-patients:{param:all-patients} gp-events-table:{param:gp-events-table} efi-category:'hypotension'
--> EXECUTE subquery-efi.sql all-patients:{param:all-patients} gp-events-table:{param:gp-events-table} efi-category:'cognitive-problems'
--> EXECUTE subquery-efi.sql all-patients:{param:all-patients} gp-events-table:{param:gp-events-table} efi-category:'mobility-problems'
--> EXECUTE subquery-efi.sql all-patients:{param:all-patients} gp-events-table:{param:gp-events-table} efi-category:'osteoporosis'
--> EXECUTE subquery-efi.sql all-patients:{param:all-patients} gp-events-table:{param:gp-events-table} efi-category:'parkinsons'
--> EXECUTE subquery-efi.sql all-patients:{param:all-patients} gp-events-table:{param:gp-events-table} efi-category:'peptic-ulcer'
--> EXECUTE subquery-efi.sql all-patients:{param:all-patients} gp-events-table:{param:gp-events-table} efi-category:'pvd'
--> EXECUTE subquery-efi.sql all-patients:{param:all-patients} gp-events-table:{param:gp-events-table} efi-category:'care-requirement'
--> EXECUTE subquery-efi.sql all-patients:{param:all-patients} gp-events-table:{param:gp-events-table} efi-category:'respiratory-disease'
--> EXECUTE subquery-efi.sql all-patients:{param:all-patients} gp-events-table:{param:gp-events-table} efi-category:'skin-ulcer'
--> EXECUTE subquery-efi.sql all-patients:{param:all-patients} gp-events-table:{param:gp-events-table} efi-category:'sleep-disturbance'
--> EXECUTE subquery-efi.sql all-patients:{param:all-patients} gp-events-table:{param:gp-events-table} efi-category:'social-vulnerability'
--> EXECUTE subquery-efi.sql all-patients:{param:all-patients} gp-events-table:{param:gp-events-table} efi-category:'stroke-tia'
--> EXECUTE subquery-efi.sql all-patients:{param:all-patients} gp-events-table:{param:gp-events-table} efi-category:'thyroid-disorders'
--> EXECUTE subquery-efi.sql all-patients:{param:all-patients} gp-events-table:{param:gp-events-table} efi-category:'urinary-incontinence'
--> EXECUTE subquery-efi.sql all-patients:{param:all-patients} gp-events-table:{param:gp-events-table} efi-category:'urinary-system-disease'
--> EXECUTE subquery-efi.sql all-patients:{param:all-patients} gp-events-table:{param:gp-events-table} efi-category:'vision-problems'
--> EXECUTE subquery-efi.sql all-patients:{param:all-patients} gp-events-table:{param:gp-events-table} efi-category:'weight-loss '

-- Now we need to calculate polypharmacy as that is the 36th EFI deficit

-- Polypharmacy is defined as 5 different med codes on a single day. This then lasts for 6 weeks
-- (most Rx for 4 weeks, so add some padding to ensure people on 5 meds permanently, but with
-- small variation in time differences are classed as always poly rather than flipping in/out).
-- Overlapping periods are then combined.

-- Get all the dates that people were prescribed 5 or more meds
IF OBJECT_ID('tempdb..#PolypharmDates') IS NOT NULL DROP TABLE #PolypharmDates;
SELECT FK_Patient_Link_ID, CONVERT(DATE, [MedicationDate]) AS MedicationDate
INTO #PolypharmDates
FROM {param:gp-medications-table}
GROUP BY FK_Patient_Link_ID, CONVERT(DATE, [MedicationDate])
HAVING COUNT(DISTINCT SuppliedCode) >= 5;

-- Now convert to desired format (PatientId / DateFrom / DateTo)

-- Temp holiding table for loop below
IF OBJECT_ID('tempdb..#PolypharmacyPeriodsTEMP') IS NOT NULL DROP TABLE #PolypharmacyPeriodsTEMP;
CREATE TABLE #PolypharmacyPeriodsTEMP (
	FK_Patient_Link_ID BIGINT,
	DateFrom DATE,
	DateTo DATE
);

-- Populate initial start and end dates
IF OBJECT_ID('tempdb..#PolypharmacyPeriods') IS NOT NULL DROP TABLE #PolypharmacyPeriods;
SELECT FK_Patient_Link_ID, MedicationDate As DateFrom, DATEADD(day, 42, MedicationDate) AS DateTo
INTO #PolypharmacyPeriods
FROM PolypharmDates;

DECLARE @NumberDeleted INT;
SET @NumberDeleted=1;
WHILE ( @NumberDeleted > 0)
BEGIN

	-- PHASE 1
	-- Populate the temp table with overlapping periods. If there is no overlapping period,
	-- we just retain the initial period. If a period overlaps, then this populate the widest
	-- [DateFrom, DateTo] range.
	-- Grapically we go from:
	-- |------|
	--     |-----|
	--      |-------|
	--              |-----|
	--                      |-----|
	-- to:
	-- |------|
	-- |---------|
	-- |------------|
	--     |-----|
	--     |--------|
	--      |-------|
	--      |-------------|
	--              |-----|
	--                      |-----|
	--
	TRUNCATE TABLE #PolypharmacyPeriodsTEMP;
	INSERT INTO #PolypharmacyPeriodsTEMP
	select p1.FK_Patient_Link_ID, p1.DateFrom, ISNULL(p2.DateTo, p1.DateTo) AS DateTo
	from #PolypharmacyPeriods p1
	left outer join #PolypharmacyPeriods p2 on
		p1.FK_Patient_Link_ID = p2.FK_Patient_Link_ID and 
		p2.DateFrom <= p1.DateTo and 
		p2.DateFrom > p1.DateFrom;

	-- Make both polypharm period tables the same
	TRUNCATE TABLE #PolypharmacyPeriods;
	INSERT INTO #PolypharmacyPeriods
	SELECT * FROM #PolypharmacyPeriodsTEMP;

	-- PHASE 2
	-- The above will have resulted in overlapping periods. Here we remove any that are
	-- contained in other periods.
	-- Continuing the above graphical example, we go from:
	-- |------|
	-- |---------|
	-- |------------|
	--     |-----|
	--     |--------|
	--      |-------|
	--      |-------------|
	--              |-----|
	--                      |-----|
	-- to:
	-- |------------|
	--      |-------------|
	--                      |-----|
	DELETE p
	FROM #PolypharmacyPeriods p
	JOIN (
	SELECT p1.* FROM #PolypharmacyPeriodsTEMP p1
	INNER JOIN #PolypharmacyPeriodsTEMP p2 ON
		p1.FK_Patient_Link_ID = p2.FK_Patient_Link_ID AND
		(
			(p1.DateFrom >= p2.DateFrom AND	p1.DateTo < p2.DateTo) OR
			(p1.DateFrom > p2.DateFrom AND p1.DateTo <= p2.DateTo)
		)
	) sub ON sub.FK_Patient_Link_ID = p.FK_Patient_Link_ID and sub.DateFrom = p.DateFrom and sub.DateTo = p.DateTo;

	SELECT @NumberDeleted=@@ROWCOUNT;

	-- Provided we removed some periods, we need to re-run the loop. For our example, the 
	-- next iteration will first go from:
	-- |------------|
	--      |-------------|
	--                      |-----|
	-- to:
	-- |------------|
	-- |------------------|
	--      |-------------|
	--                      |-----|
	-- during PHASE 1, then during PHASE 2, 2 periods will be deleted leaving:
	-- |------------------|
	--                      |-----|
	-- One more iteration will occur, but nothing will change, so we'll exit the loop with the final
	-- two non-overlapping periods
END