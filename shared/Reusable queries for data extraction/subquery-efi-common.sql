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
--> EXECUTE subquery-efi.sql all-patients:{param:all-patients} gp-events-table:{param:gp-events-table} efi-category:'weight-loss'

-- Now we add some hard coded deficits which come from values rather than

-- First populate a temp table with values for codes of interest
IF OBJECT_ID('tempdb..#EfiValueData') IS NOT NULL DROP TABLE #EfiValueData;
BEGIN
  IF '{param:all-patients}'='true'
    SELECT FK_Patient_Link_ID, CONVERT(DATE, [EventDate]) AS EventDate, SuppliedCode, [Value]
		INTO #EfiValueData
    FROM {param:gp-events-table}
    WHERE SuppliedCode IN ('16D2.','246V.','246W.','38DE.','39F..','3AD3.','423..','442A.','442W.','44lD.','451E.','451F.','46N..','46N4.','46N7.','46TC.','46W..','585a.','58EE.','66Yf.','687C.','XaJLG','XaF4O','XaF4b','XaP9J','Y1259','Y1258','XaIup','XaK8U','YA310','Y01e7','XaJv3','XE2eH','XE2eG','XaEMS','XE2eI','XE2n3','XE2bw','XSFyN','XaIz7','XaITU','XE2wy','XaELV','39C..','XC0tc','XM0an','XE2m6','Xa96v','Y3351','XaISO','XaZpN','XaK8y','XaMDA','XacUJ','XacUK')
		AND [Value] IS NOT NULL AND UPPER([Value]) NOT LIKE '%[A-Z]%'  -- EXTRA CHECKS IN CASE ANY NULL OR TEXT VALUES REMAINED
    AND EventDate <= GETDATE()
    GROUP BY FK_Patient_Link_ID;
  ELSE
    SELECT FK_Patient_Link_ID, CONVERT(DATE, [EventDate]) AS EventDate, SuppliedCode, [Value]
		INTO #EfiValueData
    FROM {param:gp-events-table}
    WHERE SuppliedCode IN ('16D2.','246V.','246W.','38DE.','39F..','3AD3.','423..','442A.','442W.','44lD.','451E.','451F.','46N..','46N4.','46N7.','46TC.','46W..','585a.','58EE.','66Yf.','687C.','XaJLG','XaF4O','XaF4b','XaP9J','Y1259','Y1258','XaIup','XaK8U','YA310','Y01e7','XaJv3','XE2eH','XE2eG','XaEMS','XE2eI','XE2n3','XE2bw','XSFyN','XaIz7','XaITU','XE2wy','XaELV','39C..','XC0tc','XM0an','XE2m6','Xa96v','Y3351','XaISO','XaZpN','XaK8y','XaMDA','XacUJ','XacUK')
		AND [Value] IS NOT NULL AND UPPER([Value]) NOT LIKE '%[A-Z]%'  -- EXTRA CHECKS IN CASE ANY NULL OR TEXT VALUES REMAINED
    AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
    AND EventDate <= GETDATE()
    GROUP BY FK_Patient_Link_ID;
  END
END

-- FALLS included if the "number of falls in last 12 months" is >0
--> EXECUTE subquery-efi-values.sql efi-category:'falls' supplied-codes:"'Y3351','XaISO','16D2.'" min-value:0 max-value:10000 all-patients:{param:all-patients}

-- HYPERTENSION included if avg 24hr diastolic >85
--> EXECUTE subquery-efi-values.sql efi-category:'hypertension' supplied-codes:"'246V.','XaF4b'" min-value:85 max-value:10000 all-patients:{param:all-patients}

-- HYPERTENSION included if avg 24hr systolic >135
--> EXECUTE subquery-efi-values.sql efi-category:'hypertension' supplied-codes:"'246W.','XaF4O'" min-value:135 max-value:10000 all-patients:{param:all-patients}

-- AF included if any score
--> EXECUTE subquery-efi-values.sql efi-category:'atrial-fibrillation' supplied-codes:"'38DE.','XaP9J'" min-value:-1 max-value:10000 all-patients:{param:all-patients}

-- ACTIVITY LIMITATION if Barthel<=18 then deficit
--> EXECUTE subquery-efi-values.sql efi-category:'activity-limitation' supplied-codes:"'39F..','XM0an'" min-value:-1 max-value:18.1 all-patients:{param:all-patients}

-- Memory & cognitive problems if Six item cognitive impairment test >=8
--> EXECUTE subquery-efi-values.sql efi-category:'cognitive-problems' supplied-codes:"'3AD3.','XaJLG'" min-value:7.9 max-value:10000 all-patients:{param:all-patients}

-- Anaemia if haemaglobin is below reference range. BUT lower range is 130 for males and I've regularly had less than this
-- after giving blood so not sure it's a good idea to include.
--//> EXECUTE subquery-efi-values.sql efi-category:'anaemia' supplied-codes:"'423..','XE2m6','Xa96v'" min-value:X max-value:Y all-patients:{param:all-patients}

-- Thyroid problems if TSH outside of 0.27 - 4.2
--> EXECUTE subquery-efi-values.sql efi-category:'thyroid-disorders' supplied-codes:"'442A.','442W.','XE2wy','XaELV'" min-value:0 max-value:2.7 all-patients:{param:all-patients}
--> EXECUTE subquery-efi-values.sql efi-category:'thyroid-disorders' supplied-codes:"'442A.','442W.','XE2wy','XaELV'" min-value:4.2 max-value:10000 all-patients:{param:all-patients}

-- Chronic kidney disease if Glomerular filtration rate <60
--> EXECUTE subquery-efi-values.sql efi-category:'ckd' supplied-codes:"'451E.','451F.','XSFyN','XaZpN','XaK8y','XaMDA','XacUJ','XacUK'" min-value:0 max-value:60 all-patients:{param:all-patients}

-- Chronic kidney disease if Urine protein
-- Chronic kidney disease if Urine albumin
-- Chronic kidney disease if Urine protein/creatinine index
-- Chronic kidney disease if Urine albumin:creatinine ratio
-- Chronic kidney disease if Urine microalbumin

-- Peripheral vascular disease if ABPI < 0.95
--> EXECUTE subquery-efi-values.sql efi-category:'pvd' supplied-codes:"'585a.','Y1259','Y1258','XaIup'" min-value:0 max-value:0.95 all-patients:{param:all-patients}

-- Osteoporosis if Hip DXA scan T score <= -2.5
--> EXECUTE subquery-efi-values.sql efi-category:'osteoporosis' supplied-codes:"'XaITU','58EE.'" min-value:-10000 max-value:-2.499 all-patients:{param:all-patients}

-- Respiratory problems if Number of COPD exacerbations in past year OR Number of hours of oxygen therapy per day OR
-- Number of unscheduled encounters for COPD in the last 12 months >= 1
--> EXECUTE subquery-efi-values.sql efi-category:'respiratory-disease' supplied-codes:"'66Yf.','XaK8U','YA310','Y01e7'" min-value:0.9 max-value:10000 all-patients:{param:all-patients}

-- Weight loss/anorexia if Malnutrition universal screening tool score >= 1
--> EXECUTE subquery-efi-values.sql efi-category:'weight-loss' supplied-codes:"'687C.','XaJv3'" min-value:0.9999 max-value:10000 all-patients:{param:all-patients}


-- Now we need to calculate polypharmacy as that is the 36th EFI deficit

-- Polypharmacy is defined as 5 different med codes on a single day. This then lasts for 6 weeks
-- (most Rx for 4 weeks, so add some padding to ensure people on 5 meds permanently, but with
-- small variation in time differences are classed as always poly rather than flipping in/out).
-- Overlapping periods are then combined.

-- Get all the dates that people were prescribed 5 or more meds
IF OBJECT_ID('tempdb..#PolypharmDates5OnOneDay') IS NOT NULL DROP TABLE #PolypharmDates5OnOneDay;
SELECT FK_Patient_Link_ID, CONVERT(DATE, [MedicationDate]) AS MedicationDate
INTO #PolypharmDates5OnOneDay
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
FROM #PolypharmDates5OnOneDay;

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


-- UPDATE Andy Clegg algorithm is for 5 different meds in a 12 month period. Maybe
-- we should define it in both ways - and allow sensitivity analysis
-- The following is a look back so gives number of meds in 12 months prior to a prescription
-- This will deal with the start events.
IF OBJECT_ID('tempdb..#PolypharmDates5InLastYear') IS NOT NULL DROP TABLE #PolypharmDates5InLastYear;
SELECT m1.FK_Patient_Link_ID, CONVERT(DATE, m1.[MedicationDate]) AS PotentialPolypharmStartDate
INTO #PolypharmDates5InLastYear
FROM {param:gp-medications-table} m1
LEFT OUTER JOIN {param:gp-medications-table} m2
	ON m1.FK_Patient_Link_ID = m2.FK_Patient_Link_ID
	AND CONVERT(DATE, m1.[MedicationDate]) >= CONVERT(DATE, m2.[MedicationDate])
	AND CONVERT(DATE, m1.[MedicationDate]) < DATEADD(year, 1, CONVERT(DATE, m2.[MedicationDate]))
GROUP BY m1.FK_Patient_Link_ID, CONVERT(DATE, m1.[MedicationDate])
HAVING COUNT(DISTINCT m2.SuppliedCode) >= 5;

-- Next is a look forward from the day after a medication. This will deal with the stop events
IF OBJECT_ID('tempdb..#PolypharmDates5InLastYear') IS NOT NULL DROP TABLE #PolypharmDates5InLastYear;
SELECT m1.FK_Patient_Link_ID, DATEADD(year, 1, CONVERT(DATE, m1.[MedicationDate])) AS PotentialPolypharmEndDate
INTO #PolypharmStopDates5InLastYear
FROM {param:gp-medications-table} m1
LEFT OUTER JOIN {param:gp-medications-table} m2
	ON m1.FK_Patient_Link_ID = m2.FK_Patient_Link_ID
	AND DATEADD(year, 1, CONVERT(DATE, m1.[MedicationDate])) >= CONVERT(DATE, m2.[MedicationDate])
	AND DATEADD(year, 1, CONVERT(DATE, m1.[MedicationDate])) < DATEADD(year, 1, CONVERT(DATE, m2.[MedicationDate]))
GROUP BY m1.FK_Patient_Link_ID, DATEADD(year, 1, CONVERT(DATE, m1.[MedicationDate]))
HAVING COUNT(DISTINCT m2.SuppliedCode) < 5;

-- Now convert to desired format (PatientId / DateFrom / DateTo)

-- Temp holiding table for loop below
IF OBJECT_ID('tempdb..#PolypharmacyPeriodsYearTEMP') IS NOT NULL DROP TABLE #PolypharmacyPeriodsYearTEMP;
CREATE TABLE #PolypharmacyPeriodsYearTEMP (
	FK_Patient_Link_ID BIGINT,
	DateFrom DATE,
	DateTo DATE
);

-- Populate initial start and end dates
IF OBJECT_ID('tempdb..#PolypharmacyPeriods5In1Year') IS NOT NULL DROP TABLE #PolypharmacyPeriods5In1Year;
SELECT a.FK_Patient_Link_ID, PotentialPolypharmStartDate AS DateFrom, MIN(PotentialPolypharmEndDate) AS DateTo
INTO #PolypharmacyPeriods5In1Year
FROM #PolypharmDates5InLastYear a
LEFT OUTER JOIN #PolypharmStopDates5InLastYear b
	ON a.FK_Patient_Link_ID = b.FK_Patient_Link_ID
	AND PotentialPolypharmStartDate < PotentialPolypharmEndDate
GROUP BY a.FK_Patient_Link_ID, PotentialPolypharmStartDate

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
	TRUNCATE TABLE #PolypharmacyPeriodsYearTEMP;
	INSERT INTO #PolypharmacyPeriodsYearTEMP
	select p1.FK_Patient_Link_ID, p1.DateFrom, ISNULL(p2.DateTo, p1.DateTo) AS DateTo
	from #PolypharmacyPeriods5In1Year p1
	left outer join #PolypharmacyPeriods5In1Year p2 on
		p1.FK_Patient_Link_ID = p2.FK_Patient_Link_ID and 
		p2.DateFrom <= p1.DateTo and 
		p2.DateFrom > p1.DateFrom;

	-- Make both polypharm period tables the same
	TRUNCATE TABLE #PolypharmacyPeriods5In1Year;
	INSERT INTO #PolypharmacyPeriods5In1Year
	SELECT * FROM #PolypharmacyPeriodsYearTEMP;

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
	FROM #PolypharmacyPeriods5In1Year p
	JOIN (
	SELECT p1.* FROM #PolypharmacyPeriodsYearTEMP p1
	INNER JOIN #PolypharmacyPeriodsYearTEMP p2 ON
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