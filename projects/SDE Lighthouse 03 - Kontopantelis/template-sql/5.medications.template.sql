--┌─────────────┐
--│ Medications │
--└─────────────┘

------------ RESEARCH DATA ENGINEER CHECK ------------
-- 
------------------------------------------------------

-- All prescriptions of: antipsychotic medication.

-- OUTPUT: Data with the following fields
-- 	-   PatientId (int)
--	-	MedicationDescription
--	-	MostRecentPrescriptionDate (YYYY-MM-DD)

--Just want the output, not the messages
SET NOCOUNT ON;

-- Set the start date
DECLARE @StartDate datetime;
DECLARE @EndDate datetime;
SET @StartDate = '2006-01-01';
SET @EndDate = '2023-10-31';

--> EXECUTE query-build-lh003-cohort.sql

--> CODESET antipsychotics:1 
-- acetylcholinesterase-inhibitors:1 anticholinergic-medications:1 drowsy-medications:3

SELECT "FK_Patient_ID", "MedicationDate", "Field_ID"
FROM INTERMEDIATE.GP_RECORD."MedicationsClusters"
WHERE "Field_ID" IN ('ANTIPSYDRUG_COD','BENZODRUG_COD')
LIMIT 100


-- antipsychotics, anti-dementia meds, anticholinergics, benzodiazepines, z-drugs and sedating antihistamines.
--ANTIPSYDRUG_COD
--BENZODRUG_COD (includes z-drugs)

-- DEMENTIA PATIENTS WITH RX OF CERTAIN MEDS SINCE 31.07.19

IF OBJECT_ID('tempdb..#medications') IS NOT NULL DROP TABLE #medications;
SELECT 
	 m.FK_Patient_Link_ID,
		CAST(MedicationDate AS DATE) as PrescriptionDate,
		[concept] = CASE WHEN s.[concept] IS NOT NULL THEN s.[concept] ELSE c.[concept] END,
		[description] = CASE WHEN s.[description] IS NOT NULL THEN s.[description] ELSE c.[description] END,
		Dosage,
		Quantity
INTO #medications
FROM SharedCare.GP_Medications m
LEFT OUTER JOIN #VersionedSnomedSets s ON s.FK_Reference_SnomedCT_ID = m.FK_Reference_SnomedCT_ID
LEFT OUTER JOIN #VersionedCodeSets c ON c.FK_Reference_Coding_ID = m.FK_Reference_Coding_ID
WHERE m.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Cohort)
AND m.MedicationDate BETWEEN @StartDate AND @EndDate
AND (
	m.FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets) OR
    m.FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets)
);


-- Dosage information *might* contain sensitive information, so let's 
-- restrict to dosage instructions that occur >= 50 times
IF OBJECT_ID('tempdb..#SafeDosages') IS NOT NULL DROP TABLE #SafeDosages;
SELECT Dosage INTO #SafeDosages FROM #medications
group by Dosage
having count(*) >= 50;



-- CREATE TABLE OF ALL ANTIPSYCHOTIC RX FOR THE DEMENTIA COHORT, WITH THE MEDICATION TYPE AND PRESCRIPTION DATE

SELECT 
	PatientId = FK_Patient_Link_ID,
	PrescriptionDate,
	concept,
	Description = REPLACE(Description, ',',' '),
	Dosage = LEFT(REPLACE(REPLACE(REPLACE(ISNULL(#SafeDosages.Dosage, 'REDACTED'),',',' '),CHAR(13),' '),CHAR(10),' '),50),
	Quantity
FROM #medications m
LEFT OUTER JOIN #SafeDosages ON m.Dosage = #SafeDosages.Dosage
