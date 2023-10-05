--+--------------------------------------------------------------------------------+
--¦ Alcohol longitudinal information (skin cohort)                                ¦
--+--------------------------------------------------------------------------------+

-------- RESEARCH DATA ENGINEER CHECK ---------

-- OUTPUT: Data with the following fields
-- PatientId
-- EventDate (YYYY-MM-DD)
-- AlcoholStatus (alcohol-non-drinker/ alcohol-light-drinker/ alcohol-moderate-drinker/ alcohol-heavy-drinker/ alcohol-weekly-intake)


--> CODESET skin-cancer:1


-- Set the start date
DECLARE @StartDate datetime;
DECLARE @EndDate datetime;
SET @StartDate = '2011-01-01';
SET @EndDate = GETDATE();

--Just want the output, not the messages
SET NOCOUNT ON;


-- Create the skin cancer cohort=====================================================================================================================================
IF OBJECT_ID('tempdb..#SkinCohort') IS NOT NULL DROP TABLE #SkinCohort;
SELECT DISTINCT FK_Patient_Link_ID 
INTO #SkinCohort
FROM SharedCare.GP_Events
WHERE (SuppliedCode IN (SELECT Code FROM #AllCodes WHERE (Concept = 'skin-cancer' AND [Version] = 1)))
      AND EventDate >= @StartDate AND EventDate < @EndDate;


-- Create a table with all patients within th e skin cohort=========================================================================================================================
IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT PK_Patient_Link_ID AS FK_Patient_Link_ID INTO #Patients
FROM SharedCare.Patient_Link
WHERE PK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #SkinCohort);


--> CODESET alcohol-non-drinker:1 alcohol-light-drinker:1 alcohol-moderate-drinker:1 alcohol-heavy-drinker:1 alcohol-weekly-intake:1


IF OBJECT_ID('tempdb..#AllPatientAlcoholIntakeCodes') IS NOT NULL DROP TABLE #AllPatientAlcoholIntakeCodes;
SELECT 
	FK_Patient_Link_ID,
	CAST(EventDate AS DATE) AS EventDate,
	FK_Reference_Coding_ID,
	FK_Reference_SnomedCT_ID,
	[Value]
INTO #AllPatientAlcoholIntakeCodes
FROM [SharedCare].[GP_Events]
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND FK_Reference_SnomedCT_ID IN (
	SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets 
	WHERE Concept IN (
	'alcohol-non-drinker', 
	'alcohol-light-drinker',
	'alcohol-moderate-drinker',
	'alcohol-heavy-drinker'
	)
	AND [Version]=1
) AND CAST(EventDate AS DATE) < @EndDate
UNION
SELECT 
	FK_Patient_Link_ID,
	CAST(EventDate AS DATE) AS EventDate,
	FK_Reference_Coding_ID,
	FK_Reference_SnomedCT_ID,
	[Value]
FROM [SharedCare].[GP_Events]
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets 
	WHERE Concept IN (
	'alcohol-non-drinker', 
	'alcohol-light-drinker',
	'alcohol-moderate-drinker',
	'alcohol-heavy-drinker'
	)
	AND [Version]=1
) AND CAST(EventDate AS DATE) < @EndDate;


-- The final table========================================================================================================
SELECT 
	a.FK_Patient_Link_ID AS PatientId,
	EventDate,
	CASE WHEN c.Concept IS NULL THEN s.Concept ELSE c.Concept END AS AlcoholStatus
FROM #AllPatientAlcoholIntakeCodes a
LEFT OUTER JOIN #VersionedCodeSets c on c.FK_Reference_Coding_ID = a.FK_Reference_Coding_ID
LEFT OUTER JOIN #VersionedSnomedSets s on s.FK_Reference_SnomedCT_ID = a.FK_Reference_SnomedCT_ID
ORDER BY FK_Patient_Link_ID, EventDate;
