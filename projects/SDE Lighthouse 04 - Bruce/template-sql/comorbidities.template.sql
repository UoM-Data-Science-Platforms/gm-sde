--┌──────────────────────────────────────────────────┐
--│ SDE Lighthouse study 04 - Newman - comorbidities │
--└──────────────────────────────────────────────────┘

--Just want the output, not the messages
SET NOCOUNT ON;

DECLARE @StartDate datetime;
DECLARE @EndDate datetime;
SET @StartDate = '2020-01-01'; -- CHECK
SET @EndDate = '2023-10-31'; -- CHECK

DECLARE @IndexDate datetime;
DECLARE @MinDate datetime;
SET @IndexDate = '2020-01-01'; -- CHECK
SET @MinDate = '1900-01-01'; -- CHECK

--> EXECUTE query-build-lh004-cohort.sql

-- REDUCE THE #Patients TABLE SO THAT IT ONLY INCLUDES THE COHORT, AND REUSABLE QUERIES CAN USE IT TO BE RUN QUICKER 

DELETE FROM #Patients
WHERE FK_Patient_Link_ID NOT IN (SELECT FK_Patient_Link_ID FROM #Cohort)

--> EXECUTE query-patient-ltcs-date-range.sql


-- one code set needed for study but not included in LTCs
--> CODESET antiphospholipid-syndrome:1

IF OBJECT_ID('tempdb..#antiphospholipid_syndrome') IS NOT NULL DROP TABLE #antiphospholipid_syndrome;
SELECT 
	gp.FK_Patient_Link_ID,
	gp.EventDate
INTO #antiphospholipid_syndrome
FROM SharedCare.GP_Events gp
LEFT OUTER JOIN #VersionedSnomedSets s ON s.FK_Reference_SnomedCT_ID = gp.FK_Reference_SnomedCT_ID
LEFT OUTER JOIN #VersionedCodeSets c ON c.FK_Reference_Coding_ID = gp.FK_Reference_Coding_ID
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Cohort) 
AND 
	(
	gp.FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (Concept = 'antiphospholipid-syndrome'))  OR
    gp.FK_Reference_Coding_ID   IN (SELECT FK_Reference_Coding_ID   FROM #VersionedCodeSets WHERE (Concept = 'antiphospholipid-syndrome'))   
	 )
AND EventDate BETWEEN @StartDate AND @EndDate

-- Extra LTCS table

IF OBJECT_ID('tempdb..#ExtraLTCs') IS NOT NULL DROP TABLE #ExtraLTCs;
SELECT FK_Patient_Link_ID,
	LTC = 'antiphospholipid-syndrome',
	FirstDate = MIN(EventDate),
	LastDate = MAX(EventDate),
	ConditionOccurences = COUNT(*)
INTO #ExtraLTCs
FROM #antiphospholipid_syndrome
GROUP BY FK_Patient_Link_ID

--bring together for final output
SELECT *
FROM #PatientsWithLTCs
UNION ALL 
SELECT * 
FROM #ExtraLTCs