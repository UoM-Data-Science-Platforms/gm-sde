--┌─────────────┐
--│ Medications │
--└─────────────┘

------------ RESEARCH DATA ENGINEER CHECK ------------
-- 

-- All prescriptions of certain medications during the study period

-- OUTPUT: Data with the following fields
-- 	-   PatientId (int)
--  -   Year
--  -   MedicationDate
--	-	MedicationCategory - number of prescriptions for given medication category

--Just want the output, not the messages
SET NOCOUNT ON;

DECLARE @StartDate datetime;
DECLARE @EndDate datetime;
SET @StartDate = '1900-09-01'; 
SET @EndDate = '2023-12-31';

--> EXECUTE query-build-rq062-cohort.sql

-- load codesets needed for retrieving medication prescriptions

--> CODESET calcium-channel-blockers:1 beta-blockers:1
--> CODESET statins:1 ace-inhibitor:1 diuretic:1
--> CODESET angiotensin-receptor-blockers:1 acetylcholinesterase-inhibitors:1 

-- RETRIEVE ALL RELEVANT PRESCRPTIONS FOR THE COHORT

IF OBJECT_ID('tempdb..#medications_rx') IS NOT NULL DROP TABLE #medications_rx;
SELECT 
	 m.FK_Patient_Link_ID,
	CAST(MedicationDate AS DATE) as PrescriptionDate,
	Concept
INTO #medications_rx
FROM SharedCare.GP_Medications m
INNER JOIN #AllCodes a ON a.code = SuppliedCode
WHERE m.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND m.MedicationDate BETWEEN @StartDate AND @EndDate;

--- create index on meds table
DROP INDEX IF EXISTS medsdata1 ON #medications_rx;
CREATE INDEX medsdata1 ON #medications_rx (Concept) INCLUDE (FK_Patient_Link_ID, PrescriptionDate);

---- Find 70th birthday of each patient (to the closest quarter), for working out closest meds before and after 
IF OBJECT_ID('tempdb..#70thBirthdayDates') IS NOT NULL DROP TABLE #70thBirthdayDates;
SELECT p.FK_Patient_Link_ID, 
		[70thBirthday] = DATEADD(year,70,CONVERT(Date, wob.DateOfBirthPID))
INTO #70thBirthdayDates
FROM #Patients p
LEFT OUTER JOIN #PatientWeekOfBirth wob ON wob.FK_Patient_Link_ID = p.FK_Patient_Link_ID;

-- Last Prescriptions before 2013-09-01
IF OBJECT_ID('tempdb..#last_rx_before_2013_09_01') IS NOT NULL DROP TABLE #last_rx_before_2013_09_01;
SELECT FK_Patient_Link_ID, Concept, MAX(PrescriptionDate) as LastRxBefore2013_09_01
INTO #last_rx_before_2013_09_01
FROM #medications_rx m
WHERE PrescriptionDate < '2013-09-01'
GROUP BY FK_Patient_Link_ID, Concept

-- First Prescription after 2013-09-01
IF OBJECT_ID('tempdb..#first_rx_after_2013_09_01') IS NOT NULL DROP TABLE #first_rx_after_2013_09_01;
SELECT FK_Patient_Link_ID, Concept, MIN(PrescriptionDate) as FirstRxAfter2013_09_01
INTO #first_rx_after_2013_09_01
FROM #medications_rx m
WHERE PrescriptionDate > '2013-09-01'
GROUP BY FK_Patient_Link_ID, Concept

-- Last Prescription before 70th birthday
IF OBJECT_ID('tempdb..#last_rx_before_70th') IS NOT NULL DROP TABLE #last_rx_before_70th;
SELECT m.FK_Patient_Link_ID, Concept, MAX(PrescriptionDate) as LastRxBefore70thBirthday
INTO #last_rx_before_70th
FROM #medications_rx m
LEFT JOIN #70thBirthdayDates bd ON bd.FK_Patient_Link_ID = m.FK_Patient_Link_ID
WHERE PrescriptionDate < [70thBirthday]
GROUP BY m.FK_Patient_Link_ID, Concept

-- First Prescription after 70th birthday
IF OBJECT_ID('tempdb..#first_rx_after_70th') IS NOT NULL DROP TABLE #first_rx_after_70th;
SELECT m.FK_Patient_Link_ID, Concept, MIN(PrescriptionDate) as FirstRxAfter70thBirthday
INTO #first_rx_after_70th
FROM #medications_rx m
LEFT JOIN #70thBirthdayDates bd ON bd.FK_Patient_Link_ID = m.FK_Patient_Link_ID
WHERE PrescriptionDate > [70thBirthday]
GROUP BY m.FK_Patient_Link_ID, Concept

-- bring together for final output at patient level

SELECT PatientId = m.FK_Patient_Link_ID,
	m.Concept,
	FirstRx = MIN(PrescriptionDate), 
	LastRxBefore2013_09_01= CONVERT(Date, MAX(DATEADD(m, DATEDIFF(m, 0, LastRxBefore2013_09_01), 0))), -- inform PI that these are set to first of the month
	FirstRxAfter2013_09_01 = CONVERT(Date, MAX(DATEADD(m, DATEDIFF(m, 0, FirstRxAfter2013_09_01), 0))),
	LastRxBefore70thBirthday = CONVERT(Date, MAX(DATEADD(m, DATEDIFF(m, 0, LastRxBefore70thBirthday), 0))), 
	FirstRxAfter70thBirthday = CONVERT(Date, MAX(DATEADD(m, DATEDIFF(m, 0, FirstRxAfter70thBirthday), 0)))
FROM #medications_rx m
LEFT JOIN #last_rx_before_2013_09_01 t1 ON t1.FK_Patient_Link_ID = m.FK_Patient_Link_ID AND t1.Concept = m.Concept
LEFT JOIN #first_rx_after_2013_09_01 t2 ON t2.FK_Patient_Link_ID = m.FK_Patient_Link_ID AND t2.Concept = m.Concept
LEFT JOIN #last_rx_before_70th t3 ON t3.FK_Patient_Link_ID = m.FK_Patient_Link_ID AND t3.Concept = m.Concept
LEFT JOIN #first_rx_after_70th t4 ON t4.FK_Patient_Link_ID = m.FK_Patient_Link_ID AND t4.Concept = m.Concept
GROUP BY m.FK_Patient_Link_ID, m.Concept