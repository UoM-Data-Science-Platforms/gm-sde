--┌───────────────────────────────────────┐
--│ Clinical concepts per clinical system │
--└───────────────────────────────────────┘

-- OBJECTIVE: To provide a report on the proportion of patients who have a particular
--            clinical concept in their record, broken down by clinical system. Because
--            different clinical systems use different clinical code terminologies, if
--            the percentage of patients with a particular condition is similar across 
--            clinical systems then we can be confident in our code sets. If there is a
--            discrepancy then this could be due to faulty code sets, or it could be an
--            underlying issue with the GMCR. Finally there is a possibility that because
--            TPP and Vision have relatively few patients compared with EMIS in GM, that
--            differences in the demographics of the TPP and Vision practices, or random
--            chance, will result in differences that are non indicative of any problem.

-- INPUT: No pre-requisites

-- OUTPUT: Table with the following fields
-- 	- Concept - the clinical concept e.g. the diagnosis, medication, procedure...
--  - Version - the version of the clinical concept
--  - System  - the clinical system (EMIS/Vision/TPP)
--  - PatientsWithConcept  - the number of patients with a clinical code for this concept in their record
--  - Patients  - the number of patients for this system supplier
--  - PercentageOfPatients  - the percentage of patients for this system supplier with this concept

--Just want the output, not the messages
SET NOCOUNT ON;

--> EXECUTE load-code-sets.sql
--> EXECUTE query-practice-systems-lookup.sql

-- Finds all patients with one of the clinical codes
IF OBJECT_ID('tempdb..#PatientsWithCode') IS NOT NULL DROP TABLE #PatientsWithCode;
SELECT FK_Patient_Link_ID, Concept, [Version] INTO #PatientsWithCode FROM RLS.[vw_GP_Events] e
INNER JOIN #VersionedCodeSets v on v.FK_Reference_Coding_ID = e.FK_Reference_Coding_ID
UNION
SELECT FK_Patient_Link_ID, Concept, [Version] FROM RLS.[vw_GP_Events] e
INNER JOIN #VersionedSnomedSets v on v.FK_Reference_SnomedCT_ID = e.FK_Reference_SnomedCT_ID
GROUP BY FK_Patient_Link_ID, Concept, [Version];

-- Counts the number of patients for each version of each concept for each clinical system
IF OBJECT_ID('tempdb..#PatientsWithCodePerSystem') IS NOT NULL DROP TABLE #PatientsWithCodePerSystem;
SELECT [System], Concept, [Version], count(*) as [Count] into #PatientsWithCodePerSystem FROM RLS.vw_Patient p
INNER JOIN #PracticeSystemLookup s on s.PracticeId = p.GPPracticeCode
INNER JOIN #PatientsWithCode c on c.FK_Patient_Link_ID = p.FK_Patient_Link_ID
WHERE FK_Reference_Tenancy_ID = 2
AND NOT EXISTS (SELECT * FROM [RLS].vw_Patient_Link WHERE PK_Patient_Link_ID = p.FK_Patient_Link_ID and Deceased = 'Y')
GROUP BY [System], Concept, [Version];

-- Counts the number of patients per system
IF OBJECT_ID('tempdb..#PatientsPerSystem') IS NOT NULL DROP TABLE #PatientsPerSystem;
SELECT [System], count(*) as [Count] into #PatientsPerSystem FROM RLS.vw_Patient p
INNER JOIN #PracticeSystemLookup s on s.PracticeId = p.GPPracticeCode
WHERE FK_Reference_Tenancy_ID = 2
AND NOT EXISTS (SELECT * FROM [RLS].vw_Patient_Link WHERE PK_Patient_Link_ID = p.FK_Patient_Link_ID and Deceased = 'Y')
GROUP BY [System];

-- Final table to display the proportion of patients per version of concept for each clinical system
SELECT p.Concept, p.[Version], pps.[System], p.[Count] as PatientsWithConcept, pps.[Count] as Patients, 100 * CAST(p.[Count] AS float)/pps.[Count] as PercentageOfPatients
FROM #PatientsWithCodePerSystem p
INNER JOIN #PatientsPerSystem pps ON pps.[System] = p.[System]
ORDER BY p.Concept, p.[Version], pps.[System];