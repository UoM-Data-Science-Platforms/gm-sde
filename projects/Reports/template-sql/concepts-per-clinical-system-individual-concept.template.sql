--┌──────────────────────────────┐
--│  │
--└──────────────────────────────┘

-- OBJECTIVE: 

-- INPUT: No pre-requisites

--Just want the output, not the messages
SET NOCOUNT ON;

--> EXECUTE load-code-sets.sql
--> EXECUTE query-practice-systems-lookup.sql


DECLARE @concept varchar(255);
SET @concept = 'severe-mental-illness';

-- Finds all patients with one of the clinical codes
IF OBJECT_ID('tempdb..#PatientsWithCode') IS NOT NULL DROP TABLE #PatientsWithCode;
SELECT FK_Patient_Link_ID, Concept, [Version] INTO #PatientsWithCode FROM RLS.[vw_GP_Events] e
INNER JOIN #VersionedCodeSets v on v.FK_Reference_Coding_ID = e.FK_Reference_Coding_ID
WHERE v.Concept = @concept
UNION
SELECT FK_Patient_Link_ID, Concept, [Version] FROM RLS.[vw_GP_Events] e
INNER JOIN #VersionedSnomedSets v on v.FK_Reference_SnomedCT_ID = e.FK_Reference_SnomedCT_ID
WHERE v.Concept = @concept
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
select * from #PatientsPerSystem

-- Finds all patients with one of the clinical codes
IF OBJECT_ID('tempdb..#PatientsWithSuppliedCode') IS NOT NULL DROP TABLE #PatientsWithSuppliedCode;
SELECT FK_Patient_Link_ID, SuppliedCode INTO #PatientsWithSuppliedCode FROM RLS.[vw_GP_Events] e
WHERE SuppliedCode IN (SELECT [Code] FROM #AllCodes WHERE Concept = @concept);
--03:27

IF OBJECT_ID('tempdb..#PatientsWithSuppliedConcept') IS NOT NULL DROP TABLE #PatientsWithSuppliedConcept;
SELECT FK_Patient_Link_ID, Concept, [Version] INTO #PatientsWithSuppliedConcept FROM #PatientsWithSuppliedCode p
INNER JOIN #AllCodes a on a.Code = p.SuppliedCode
GROUP BY FK_Patient_Link_ID, [Concept], [Version];

-- Counts the number of patients for each version of each concept for each clinical system
IF OBJECT_ID('tempdb..#PatientsWithSuppConceptPerSystem') IS NOT NULL DROP TABLE #PatientsWithSuppConceptPerSystem;
SELECT [System], Concept, [Version], count(*) as [Count] into #PatientsWithSuppConceptPerSystem FROM RLS.vw_Patient p
INNER JOIN #PracticeSystemLookup s on s.PracticeId = p.GPPracticeCode
INNER JOIN #PatientsWithSuppliedConcept c on c.FK_Patient_Link_ID = p.FK_Patient_Link_ID
WHERE FK_Reference_Tenancy_ID = 2
AND NOT EXISTS (SELECT * FROM [RLS].vw_Patient_Link WHERE PK_Patient_Link_ID = p.FK_Patient_Link_ID and Deceased = 'Y')
GROUP BY [System], Concept, [Version];

-- Final table to display the proportion of patients per version of concept for each clinical system
SELECT 
	p.Concept, p.[Version], pps.[System], pps.[Count] as Patients,p.[Count] as PatientsWithConcept, 
	psps.[Count] as PatiensWithConceptFromCode,
	 100 * CAST(p.[Count] AS float)/pps.[Count] as PercentageOfPatients,
	 100 * CAST(psps.[Count] AS float)/pps.[Count] as PercentageOfPatientsFromCode
FROM #PatientsWithCodePerSystem p
INNER JOIN #PatientsPerSystem pps ON pps.[System] = p.[System]
INNER JOIN #PatientsWithSuppConceptPerSystem psps ON psps.[System] = p.[System] AND psps.Concept = p.Concept AND psps.[Version] = p.[Version]
ORDER BY p.Concept, p.[Version], pps.[System];
