-- TODO questions
-- * If someone has 2 GP consulations on the same day does that count as 1 or 2?
--	 Can only count as one, because it could be duplication.
-- * Frequently encounters have the code '.....' which basically means no code. Can happen several times a day. Risk of including is that it is perhaps recording
--	 every time someone looks at the record - e.g. to check appointment. Risk of excluding is that it means something else.
-- * Will need to just look for consultations with a particular set of codes.
-- * IMD score not useful. IMD decile is useful.
-- * For patients without an IMD - or with multiple conflicting ones - do we ignore? Or put in separate column?

--Just want the output, not the messages
SET NOCOUNT ON;

-- Get the consultation codes of interest
IF OBJECT_ID('tempdb..#GPEncounterCodes') IS NOT NULL DROP TABLE #GPEncounterCodes;
SELECT PK_Reference_Coding_ID INTO #GPEncounterCodes FROM SharedCare.Reference_Coding
where MainCode = '9N11.'

-- Find the id and link id of all patients with a GP encounter
IF OBJECT_ID('tempdb..#PatientsWithEncounter') IS NOT NULL DROP TABLE #PatientsWithEncounter;
SELECT DISTINCT FK_Patient_ID, FK_Patient_Link_ID INTO #PatientsWithEncounter FROM RLS.vw_GP_Encounters
WHERE EncounterDate >= @StartDate
AND FK_Reference_Coding_ID IN (SELECT PK_Reference_Coding_ID FROM #GPEncounterCodes);

-- Get the LTCs that each patient had prior to 1st Jan 2020
IF OBJECT_ID('tempdb..#PatientsWithLTCs') IS NOT NULL DROP TABLE #PatientsWithLTCs;
SELECT DISTINCT FK_Patient_Link_ID, CASE 
	WHEN FK_Reference_Coding_ID IN (1,2,3) THEN 'dx1'
	WHEN FK_Reference_Coding_ID IN (248447) THEN 'hypertension' 
	WHEN FK_Reference_Coding_ID IN (239611) THEN 'diabetes'
	END AS LTC INTO #PatientsWithLTCs FROM RLS.vw_GP_Events e
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsWithEncounter)
AND EventDate < @StartDate
AND FK_Reference_Coding_ID IN (1,2,3,248447,239611);

-- Calculate the number of LTCs for each patient prior to 1st Jan 2020
IF OBJECT_ID('tempdb..#NumLTCs') IS NOT NULL DROP TABLE #NumLTCs;
SELECT FK_Patient_Link_ID, COUNT(*) AS NumberOfLTCs INTO #NumLTCs FROM #PatientsWithLTCs
GROUP BY FK_Patient_Link_ID;

-- Calculate the LTC groups for each patient prior to 1st Jan 2020
IF OBJECT_ID('tempdb..#LTCGroups') IS NOT NULL DROP TABLE #LTCGroups;
SELECT DISTINCT FK_Patient_Link_ID, CASE 
		WHEN LTC IN ('diabetes', 'ckd') THEN 'diabetes'
		WHEN LTC IN ('hypertension', 'hf') THEN 'cardiovascular'
	END AS LTCGroup INTO #LTCGroups FROM #PatientsWithLTCs;

-- If patients have a tenancy id of 2 we take this as their most likely IMD_Score
IF OBJECT_ID('tempdb..#PatientIMD') IS NOT NULL DROP TABLE #PatientIMD;
SELECT FK_Patient_Link_ID, MIN(IMD_Score) as IMD_Score INTO #PatientIMD FROM RLS.vw_Patient p
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsWithEncounter)
AND FK_Reference_Tenancy_ID = 2
AND IMD_Score IS NOT NULL
AND IMD_Score != -1
GROUP BY FK_Patient_Link_ID;

-- Find the patients with encounters but who don't have a tenancy id of 
IF OBJECT_ID('tempdb..#UnmatchedPatients') IS NOT NULL DROP TABLE #UnmatchedPatients;
SELECT FK_Patient_Link_ID INTO #UnmatchedPatients FROM #PatientsWithEncounter
EXCEPT
SELECT FK_Patient_Link_ID FROM #PatientIMD;

-- If every IMD_Score is the same for all their linked patient ids then we use that
INSERT INTO #PatientIMD
SELECT FK_Patient_Link_ID, MIN(IMD_Score) as IMD_Score FROM RLS.vw_Patient p
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #UnmatchedPatients)
AND IMD_Score IS NOT NULL
AND IMD_Score != -1
GROUP BY FK_Patient_Link_ID
HAVING MIN(IMD_Score) = MAX(IMD_Score);

-- Convert IMD rank to decile
IF OBJECT_ID('tempdb..#PatientIMDDecile') IS NOT NULL DROP TABLE #PatientIMDDecile;
select FK_Patient_Link_ID, CASE 
		WHEN IMD_Score <= 3284 THEN 1
		WHEN IMD_Score <= 6568 THEN 2
		WHEN IMD_Score <= 9853 THEN 3
		WHEN IMD_Score <= 13137 THEN 4
		WHEN IMD_Score <= 16422 THEN 5
		WHEN IMD_Score <= 19706 THEN 6
		WHEN IMD_Score <= 22990 THEN 7
		WHEN IMD_Score <= 26275 THEN 8
		WHEN IMD_Score <= 29559 THEN 9
		ELSE 10
	END AS IMD2019Decile1IsMostDeprived10IsLeastDeprived INTO #PatientIMDDecile from #PatientIMD;

