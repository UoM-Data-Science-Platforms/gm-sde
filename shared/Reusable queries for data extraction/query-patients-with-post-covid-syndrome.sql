--┌────────────────────────────────────────────────┐
--│ Patients with post-COVID syndrome (long COVID) │
--└────────────────────────────────────────────────┘

-- OBJECTIVE: To get tables of all patients with a post-COVID syndrome code in their record.
--            Separated into diagnosis, assessment and referral codes.
--
-- INPUT: Takes three parameters
--  - start-date: string - (YYYY-MM-DD) the date to count diagnoses from. Usually this should be 2020-01-01.
--	-	all-patients: boolean - (true/false) if true, then all patients are included, otherwise only those in the pre-existing #Patients table.
--	- gp-events-table: string - (table name) the name of the table containing the GP events. Usually is "SharedCare.GP_Events" but can be anything with the columns: FK_Patient_Link_ID, EventDate, and SuppliedCode
--
-- OUTPUT: One temp table as follows:
-- #PostCOVIDPatients
--	-	FK_Patient_Link_ID - unique patient id
--  - FirstPostCOVIDDiagnosisDate - First date of a post COVID diagnosis
--  - FirstPostCOVIDAssessmentDate - First date of a post COVID assessment
--  - FirstPostCOVIDReferralDate - First date of a post COVID referral

--> CODESETS post-covid-syndrome:1 post-covid-referral:1 post-covid-assessment:1

DECLARE @TEMPLongCovidEndDate DATE
SET @TEMPLongCovidEndDate = '2022-06-01';

IF OBJECT_ID('tempdb..#TEMPPostCOVIDPatients') IS NOT NULL DROP TABLE #TEMPPostCOVIDPatients;
SELECT FK_Patient_Link_ID, MIN(CAST(EventDate AS DATE)) AS FirstEventDate
INTO #TEMPPostCOVIDPatients
FROM {param:gp-events-table}
WHERE SuppliedCode IN (SELECT Code FROM #AllCodes WHERE Concept = 'post-covid-syndrome' AND [Version] = 1)
AND EventDate > '{param:start-date}'
AND EventDate <= @TEMPLongCovidEndDate
{if:all-patients=true}
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsToInclude)
{endif:all-patients}
{if:all-patients=false}
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
{endif:all-patients}
GROUP BY FK_Patient_Link_ID;

IF OBJECT_ID('tempdb..#TEMPPostCOVIDReferralPatients') IS NOT NULL DROP TABLE #TEMPPostCOVIDReferralPatients;
SELECT FK_Patient_Link_ID, MIN(CAST(EventDate AS DATE)) AS FirstEventDate
INTO #TEMPPostCOVIDReferralPatients
FROM {param:gp-events-table}
WHERE SuppliedCode IN (SELECT Code FROM #AllCodes WHERE Concept = 'post-covid-referral' AND [Version] = 1)
AND EventDate > '{param:start-date}'
AND EventDate <= @TEMPLongCovidEndDate
{if:all-patients=true}
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsToInclude)
{endif:all-patients}
{if:all-patients=false}
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
{endif:all-patients}
GROUP BY FK_Patient_Link_ID;

IF OBJECT_ID('tempdb..#TEMPPostCOVIDAssessmentPatients') IS NOT NULL DROP TABLE #TEMPPostCOVIDAssessmentPatients;
SELECT FK_Patient_Link_ID, MIN(CAST(EventDate AS DATE)) AS FirstEventDate
INTO #TEMPPostCOVIDAssessmentPatients
FROM {param:gp-events-table}
WHERE SuppliedCode IN (SELECT Code FROM #AllCodes WHERE Concept = 'post-covid-assessment' AND [Version] = 1)
AND EventDate > '{param:start-date}'
AND EventDate <= @TEMPLongCovidEndDate
{if:all-patients=true}
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsToInclude)
{endif:all-patients}
{if:all-patients=false}
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
{endif:all-patients}
GROUP BY FK_Patient_Link_ID;

IF OBJECT_ID('tempdb..#TEMPPostCOVIDPatientIds') IS NOT NULL DROP TABLE #TEMPPostCOVIDPatientIds;
SELECT FK_Patient_Link_ID INTO #TEMPPostCOVIDPatientIds FROM #TEMPPostCOVIDPatients
UNION
SELECT FK_Patient_Link_ID FROM #TEMPPostCOVIDAssessmentPatients
UNION
SELECT FK_Patient_Link_ID FROM #TEMPPostCOVIDReferralPatients;

IF OBJECT_ID('tempdb..#PostCOVIDPatients') IS NOT NULL DROP TABLE #PostCOVIDPatients;
SELECT p.FK_Patient_Link_ID,
  post.FirstEventDate AS FirstPostCOVIDDiagnosisDate,
  refer.FirstEventDate AS FirstPostCOVIDAssessmentDate,
  assess.FirstEventDate AS FirstPostCOVIDReferralDate
INTO #PostCOVIDPatients
FROM #TEMPPostCOVIDPatientIds p
LEFT OUTER JOIN #TEMPPostCOVIDPatients post ON post.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #TEMPPostCOVIDReferralPatients refer ON refer.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #TEMPPostCOVIDAssessmentPatients assess ON assess.FK_Patient_Link_ID = p.FK_Patient_Link_ID;