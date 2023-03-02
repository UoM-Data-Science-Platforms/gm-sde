--┌──────────────────────────────────────────────┐
--│ Patients with multimorbidity and covid	     │
--└──────────────────────────────────────────────┘

---- RESEARCH DATA ENGINEER CHECK ----
-- 1st July 2022 - Richard Williams --
--------------------------------------

DECLARE @StartDate datetime;
DECLARE @EndDate datetime;
SET @StartDate = '2020-01-01';
SET @EndDate = '2022-05-01';

--Just want the output, not the messages
SET NOCOUNT ON;

--> EXECUTE query-get-possible-patients.sql

-- Set the date variables for the LTC code

DECLARE @IndexDate datetime;
DECLARE @MinDate datetime;
SET @IndexDate = '2022-05-01';
SET @MinDate = '1900-01-01';

--> EXECUTE query-patient-ltcs-date-range.sql 
--> EXECUTE query-patient-ltcs-number-of.sql

-- FIND ALL PATIENTS WITH A MENTAL CONDITION

IF OBJECT_ID('tempdb..#PatientsWithMentalCondition') IS NOT NULL DROP TABLE #PatientsWithMentalCondition;
SELECT DISTINCT FK_Patient_Link_ID 
INTO #PatientsWithMentalCondition
FROM #PatientsWithLTCs
WHERE LTC IN ('Anorexia Or Bulimia', 'Anxiety And Other Somatoform Disorders', 'Dementia', 'Depression', 'Schizophrenia Or Bipolar')
	AND FirstDate < '2020-03-01'
--872,174

-- FIND ALL PATIENTS WITH 2 OR MORE CONDITIONS, INCLUDING A MENTAL CONDITION

IF OBJECT_ID('tempdb..#2orMoreLTCsIncludingMental') IS NOT NULL DROP TABLE #2orMoreLTCsIncludingMental;
SELECT DISTINCT FK_Patient_Link_ID
INTO #2orMoreLTCsIncludingMental
FROM #NumLTCs 
WHERE NumberOfLTCs = 2
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsWithMentalCondition)
--677,226


--> EXECUTE query-patient-year-of-birth.sql
--> EXECUTE query-patients-with-covid.sql start-date:2020-01-01 gp-events-table:RLS.vw_GP_Events all-patients:false

------------------------------------ CREATE COHORT -------------------------------------
	-- REGISTERED WITH A GM GP
	-- OVER  18
	-- HAD A COVID19 INFECTION
	-- 2 OR MORE LTCs INCLUDING ONE MENTAL CONDITION (diagnosed before March 2020)

IF OBJECT_ID('tempdb..#Cohort') IS NOT NULL DROP TABLE #Cohort;
SELECT p.FK_Patient_Link_ID, 
	EthnicMainGroup,
	DeathDate,
	yob.YearOfBirth
INTO #Cohort
FROM #Patients p
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = p.FK_Patient_Link_ID
WHERE YEAR(@StartDate) - YearOfBirth >= 19 														 -- Over 18
	AND p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #CovidPatientsMultipleDiagnoses) -- had at least one covid19 infection
	AND p.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #2orMoreLTCsIncludingMental)     -- at least 2 LTCs including one mental


-- Get patient list of those with COVID death within 28 days of positive test
-- 22.11.22: updated to deal with '28 days' flag under-reporting
IF OBJECT_ID('tempdb..#COVIDDeath') IS NOT NULL DROP TABLE #COVIDDeath;
SELECT DISTINCT FK_Patient_Link_ID 
INTO #COVIDDeath 
FROM RLS.vw_COVID19
where (DeathWithin28Days = 'Y' 
        OR
    (GroupDescription = 'Confirmed' AND SubGroupDescription IN ('','Positive', 'Post complication', 'Post Assessment', 'Organism', NULL))
	) and DeathDate <= DATEADD(dd,28, EventDate)
--2414

-- TABLE OF GP EVENTS FOR COHORT TO SPEED UP REUSABLE QUERIES

IF OBJECT_ID('tempdb..#PatientEventData') IS NOT NULL DROP TABLE #PatientEventData;
SELECT 
  FK_Patient_Link_ID,
  CAST(EventDate AS DATE) AS EventDate,
  SuppliedCode,
  FK_Reference_SnomedCT_ID,
  FK_Reference_Coding_ID,
  [Value],
  Units
INTO #PatientEventData
FROM [RLS].vw_GP_Events
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Cohort)
	AND EventDate < '2022-06-01';

-- Improve performance later with an index (creates in ~1 minute - saves loads more than that)
DROP INDEX IF EXISTS eventData ON #PatientEventData;
CREATE INDEX eventData ON #PatientEventData (SuppliedCode) INCLUDE (FK_Patient_Link_ID, EventDate, [Value]);

-- TABLE OF GP MEDICATIONS FOR COHORT TO SPEED UP VACCINATION QUERY

IF OBJECT_ID('tempdb..#PatientMedicationData') IS NOT NULL DROP TABLE #PatientMedicationData;
SELECT 
  FK_Patient_Link_ID,
  CAST(MedicationDate AS DATE) AS MedicationDate,
  SuppliedCode,
  FK_Reference_SnomedCT_ID,
  FK_Reference_Coding_ID
INTO #PatientMedicationData
FROM [SharedCare].GP_Medications
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Cohort)
	AND	(
		SuppliedCode IN (SELECT Code FROM #AllCodes) OR
	    FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets) OR 
		FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets)
	)
AND MedicationDate BETWEEN '2020-01-01' AND '2022-06-01'

-- Improve performance later with an index (creates in ~1 minute - saves loads more than that)
DROP INDEX IF EXISTS medData ON #PatientMedicationData;
CREATE INDEX medData ON #PatientMedicationData (SuppliedCode) INCLUDE (FK_Patient_Link_ID, MedicationDate);


--> EXECUTE query-patient-sex.sql
--> EXECUTE query-patient-imd.sql
--> EXECUTE query-patient-lsoa.sql
--> EXECUTE query-patient-bmi.sql gp-events-table:#PatientEventData
--> EXECUTE query-patient-smoking-status.sql gp-events-table:#PatientEventData
--> EXECUTE query-patient-care-home-resident.sql
--> EXECUTE query-patient-practice-and-ccg.sql
--> EXECUTE query-get-covid-vaccines.sql gp-events-table:#PatientEventData gp-medications-table:#PatientMedicationData

------------------------------- OBSERVATIONS -------------------------------------

--> CODESET height:1 weight:1

IF OBJECT_ID('tempdb..#all_observations') IS NOT NULL DROP TABLE #all_observations;
SELECT 
	FK_Patient_Link_ID,
	CAST(EventDate AS DATE) AS EventDate,
	Concept = CASE WHEN sn.Concept IS NOT NULL THEN sn.Concept ELSE co.Concept END,
	[Value] = TRY_CONVERT(NUMERIC (18,5), [Value])
INTO #all_observations
FROM #PatientEventData gp
LEFT JOIN #VersionedSnomedSets sn ON sn.FK_Reference_SnomedCT_ID = gp.FK_Reference_SnomedCT_ID
LEFT JOIN #VersionedCodeSets co ON co.FK_Reference_Coding_ID = gp.FK_Reference_Coding_ID
WHERE
	(
	gp.FK_Reference_SnomedCT_ID   IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets sn WHERE sn.Concept In ('height', 'weight') AND [Version] = 1) 
	OR gp.FK_Reference_Coding_ID   IN (SELECT FK_Reference_Coding_ID   FROM #VersionedCodeSets co   WHERE co.Concept In ('height', 'weight') AND [Version] = 1)
	)
	AND [Value] IS NOT NULL AND [Value] != '0' AND [Value] <> '0.00000' AND (TRY_CONVERT(NUMERIC (18,5), [Value])) > 0 -- REMOVE NULL AND ZERO VALUES
	AND UPPER([Value]) NOT LIKE '%[A-Z]%'  -- REMOVE TEXT VALUES


-- create table of height and weight measurements

IF OBJECT_ID('tempdb..#height_weight') IS NOT NULL DROP TABLE #height_weight;
SELECT FK_Patient_Link_ID, [Value], EventDate, Concept
INTO #height_weight
FROM #all_observations
WHERE Concept in ('height', 'weight')
	AND EventDate <= @IndexDate

-- For height and weight we want closest prior to index date
IF OBJECT_ID('tempdb..#TempCurrentHeightWeight') IS NOT NULL DROP TABLE #TempCurrentHeightWeight;
SELECT 
	a.FK_Patient_Link_ID, 
	a.Concept,
	Max([Value]) as [Value],
	Max(EventDate) as EventDate
INTO #TempCurrentHeightWeight
FROM #height_weight a
INNER JOIN (
	SELECT FK_Patient_Link_ID, MAX(EventDate) AS MostRecentDate 
	FROM #height_weight
	GROUP BY FK_Patient_Link_ID
) sub ON sub.MostRecentDate = a.EventDate and sub.FK_Patient_Link_ID = a.FK_Patient_Link_ID
GROUP BY a.FK_Patient_Link_ID, a.Concept;

-- bring together in a table that can be joined to
IF OBJECT_ID('tempdb..#PatientHeightWeight') IS NOT NULL DROP TABLE #PatientHeightWeight;
SELECT 
	p.FK_Patient_Link_ID,
	height = MAX(CASE WHEN c.Concept = 'height' THEN TRY_CONVERT(NUMERIC(16,5), [Value]) ELSE NULL END),
	height_dt = MAX(CASE WHEN c.Concept = 'height' THEN EventDate ELSE NULL END),
	weight = MAX(CASE WHEN c.Concept = 'weight' THEN TRY_CONVERT(NUMERIC(16,5), [Value]) ELSE NULL END),
	weight_dt = MAX(CASE WHEN c.Concept = 'weight' THEN EventDate ELSE NULL END)
INTO #PatientHeightWeight
FROM #Cohort p
LEFT OUTER JOIN #TempCurrentHeightWeight c on c.FK_Patient_Link_ID = p.FK_Patient_Link_ID
GROUP BY p.FK_Patient_Link_ID


-- BRING TOGETHER FOR FINAL DATA EXTRACT

SELECT  
	PatientId = p.FK_Patient_Link_ID, 
	p.YearOfBirth, 
	Sex,
	BMI,
	BMIDate = DateOfBMIMeasurement,
	height,
	height_dt,
	weight,
	weight_dt,
	CurrentSmokingStatus = smok.CurrentSmokingStatus,
	WorstSmokingStatus = smok.WorstSmokingStatus,
	p.EthnicMainGroup,
	LSOA_Code,
	PracticeCCG = prac.CCG,
	IMD2019Decile1IsMostDeprived10IsLeastDeprived,
	IsCareHomeResident,
	DeathWithin28DaysCovid = CASE WHEN cd.FK_Patient_Link_ID IS NULL OR DeathDate >= @EndDate THEN 'N' ELSE 'Y' END,
	DeathDueToCovid_Year = CASE WHEN cd.FK_Patient_Link_ID IS NOT NULL THEN YEAR(p.DeathDate) ELSE null END,
	DeathDueToCovid_Month = CASE WHEN cd.FK_Patient_Link_ID IS NOT NULL THEN MONTH(p.DeathDate) ELSE null END,
	FirstCovidPositiveDate,
	SecondCovidPositiveDate, 
	ThirdCovidPositiveDate, 
	FourthCovidPositiveDate, 
	FifthCovidPositiveDate,
	FirstVaccineYear =  YEAR(VaccineDose1Date),
	FirstVaccineMonth = MONTH(VaccineDose1Date),
	SecondVaccineYear =  YEAR(VaccineDose2Date),
	SecondVaccineMonth = MONTH(VaccineDose2Date),
	ThirdVaccineYear =  YEAR(VaccineDose3Date),
	ThirdVaccineMonth = MONTH(VaccineDose3Date)
FROM #Cohort p 
LEFT OUTER JOIN #PatientLSOA lsoa ON lsoa.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientIMDDecile imd ON imd.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientBMI bmi ON bmi.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientSmokingStatus smok ON smok.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientHeightWeight heiwei ON heiwei.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientPracticeAndCCG prac ON prac.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #COVIDDeath cd ON cd.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #COVIDVaccinations vac ON vac.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #CovidPatientsMultipleDiagnoses cv ON cv.FK_Patient_Link_ID = P.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientCareHomeStatus ch on ch.FK_Patient_Link_ID = p.FK_Patient_Link_ID 