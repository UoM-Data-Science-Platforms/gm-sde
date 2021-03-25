--┌──────────────────────────────────────────────┐
--│ Single clinical concepts per clinical system │
--└──────────────────────────────────────────────┘

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
--						This code enables you to examine a single concept which is quicker than the
--						other file which looks at all clinical concepts.

-- INPUT: No pre-requisites

--Just want the output, not the messages
SET NOCOUNT ON;

--> EXECUTE load-code-sets.sql
--> EXECUTE query-practice-systems-lookup.sql


DECLARE @concept varchar(255);
SET @concept = 'insert-concept-here';

-- Finds all patients with one of the clinical codes for the concept of interest
IF OBJECT_ID('tempdb..#PatientsWithCode') IS NOT NULL DROP TABLE #PatientsWithCode;
SELECT 'EVENT' AS [Table], FK_Patient_Link_ID, Concept, [Version] INTO #PatientsWithCode FROM RLS.[vw_GP_Events] e
INNER JOIN #VersionedCodeSets v on v.FK_Reference_Coding_ID = e.FK_Reference_Coding_ID
WHERE v.Concept = @concept
UNION
SELECT 'EVENT', FK_Patient_Link_ID, Concept, [Version] FROM RLS.[vw_GP_Events] e
INNER JOIN #VersionedSnomedSets v on v.FK_Reference_SnomedCT_ID = e.FK_Reference_SnomedCT_ID
WHERE v.Concept = @concept
GROUP BY FK_Patient_Link_ID, Concept, [Version];

-- Finds all patients with one of the clinical codes in the GP_Medications table
INSERT INTO #PatientsWithCode
SELECT 'MED', FK_Patient_Link_ID, Concept, [Version] FROM RLS.[vw_GP_Medications] e
INNER JOIN #VersionedCodeSets v on v.FK_Reference_Coding_ID = e.FK_Reference_Coding_ID
WHERE v.Concept = @concept
UNION
SELECT 'MED', FK_Patient_Link_ID, Concept, [Version] FROM RLS.[vw_GP_Medications] e
INNER JOIN #VersionedSnomedSets v on v.FK_Reference_SnomedCT_ID = e.FK_Reference_SnomedCT_ID
WHERE v.Concept = @concept
GROUP BY FK_Patient_Link_ID, Concept, [Version];

-- Counts the number of patients for each version of each concept for each clinical system
IF OBJECT_ID('tempdb..#PatientsWithCodePerSystem') IS NOT NULL DROP TABLE #PatientsWithCodePerSystem;
SELECT [System], [Table], Concept, [Version], count(*) as [Count] into #PatientsWithCodePerSystem FROM RLS.vw_Patient p
INNER JOIN #PracticeSystemLookup s on s.PracticeId = p.GPPracticeCode
INNER JOIN #PatientsWithCode c on c.FK_Patient_Link_ID = p.FK_Patient_Link_ID
WHERE FK_Reference_Tenancy_ID = 2
AND NOT EXISTS (SELECT * FROM [RLS].vw_Patient_Link WHERE PK_Patient_Link_ID = p.FK_Patient_Link_ID and Deceased = 'Y')
GROUP BY [System], [Table], Concept, [Version];

-- Counts the number of patients per system
IF OBJECT_ID('tempdb..#PatientsPerSystem') IS NOT NULL DROP TABLE #PatientsPerSystem;
SELECT [System], count(*) as [Count] into #PatientsPerSystem FROM RLS.vw_Patient p
INNER JOIN #PracticeSystemLookup s on s.PracticeId = p.GPPracticeCode
WHERE FK_Reference_Tenancy_ID = 2
AND NOT EXISTS (SELECT * FROM [RLS].vw_Patient_Link WHERE PK_Patient_Link_ID = p.FK_Patient_Link_ID and Deceased = 'Y')
GROUP BY [System];

-- Finds all patients with one of the clinical codes
IF OBJECT_ID('tempdb..#PatientsWithSuppliedCode') IS NOT NULL DROP TABLE #PatientsWithSuppliedCode;
SELECT 'EVENT' AS [Table], FK_Patient_Link_ID, SuppliedCode INTO #PatientsWithSuppliedCode FROM RLS.[vw_GP_Events] e
WHERE SuppliedCode IN (SELECT [Code] FROM #AllCodes WHERE Concept = @concept);
--03:27

-- Finds all patients with one of the clinical codes in the meds table
INSERT INTO #PatientsWithSuppliedCode
SELECT 'MED', FK_Patient_Link_ID, SuppliedCode FROM RLS.[vw_GP_Medications] e
WHERE SuppliedCode IN (SELECT [Code] FROM #AllCodes WHERE Concept = @concept);

IF OBJECT_ID('tempdb..#PatientsWithSuppliedConcept') IS NOT NULL DROP TABLE #PatientsWithSuppliedConcept;
SELECT FK_Patient_Link_ID, [Table], Concept, [Version] AS [Version] INTO #PatientsWithSuppliedConcept FROM #PatientsWithSuppliedCode p
INNER JOIN #AllCodes a on a.Code = p.SuppliedCode
GROUP BY FK_Patient_Link_ID, [Table], [Concept], [Version];

-- Counts the number of patients for each version of each concept for each clinical system
IF OBJECT_ID('tempdb..#PatientsWithSuppConceptPerSystem') IS NOT NULL DROP TABLE #PatientsWithSuppConceptPerSystem;
SELECT [System], [Table], Concept, [Version], count(*) as [Count] into #PatientsWithSuppConceptPerSystem FROM RLS.vw_Patient p
INNER JOIN #PracticeSystemLookup s on s.PracticeId = p.GPPracticeCode
INNER JOIN #PatientsWithSuppliedConcept c on c.FK_Patient_Link_ID = p.FK_Patient_Link_ID
WHERE FK_Reference_Tenancy_ID = 2
AND NOT EXISTS (SELECT * FROM [RLS].vw_Patient_Link WHERE PK_Patient_Link_ID = p.FK_Patient_Link_ID and Deceased = 'Y')
GROUP BY [System], [Table], Concept, [Version];

-- Populate table with system/event type possibilities
IF OBJECT_ID('tempdb..#SystemEventCombos') IS NOT NULL DROP TABLE #SystemEventCombos;
SELECT DISTINCT [Concept], [Version],'EMIS' as [System],'EVENT' as [Table] INTO #SystemEventCombos FROM #AllCodes WHERE Concept = @concept
UNION
SELECT DISTINCT [Concept], [Version],'TPP' as [System],'EVENT' as [Table] FROM #AllCodes WHERE Concept = @concept
UNION
SELECT DISTINCT [Concept], [Version],'Vision' as [System],'EVENT' as [Table] FROM #AllCodes WHERE Concept = @concept
UNION
SELECT DISTINCT [Concept], [Version],'EMIS' as [System],'MED' as [Table] FROM #AllCodes WHERE Concept = @concept
UNION
SELECT DISTINCT [Concept], [Version],'TPP' as [System],'MED' as [Table] FROM #AllCodes WHERE Concept = @concept
UNION
SELECT DISTINCT [Concept], [Version],'Vision' as [System],'MED' as [Table] FROM #AllCodes WHERE Concept = @concept;

-- Final table to display the proportion of patients per version of concept for each clinical system
SELECT 
	s.Concept, s.[Table], s.[Version], pps.[System], pps.[Count] as Patients, CASE WHEN p.[Count] IS NULL THEN 0 ELSE p.[Count] END as PatientsWithConcept,
	CASE WHEN psps.[Count] IS NULL THEN 0 ELSE psps.[Count] END as PatiensWithConceptFromCode,
	CASE WHEN p.[Count] IS NULL THEN 0 ELSE 100 * CAST(p.[Count] AS float)/pps.[Count] END as PercentageOfPatients,
	CASE WHEN psps.[Count] IS NULL THEN 0 ELSE 100 * CAST(psps.[Count] AS float)/pps.[Count] END as PercentageOfPatientsFromCode
FROM #SystemEventCombos s
LEFT OUTER JOIN #PatientsWithCodePerSystem p on p.[System] = s.[System] AND p.[Table] = s.[Table] AND p.Concept = s.Concept AND p.[Version] = s.[Version]
INNER JOIN #PatientsPerSystem pps ON pps.[System] = s.[System]
LEFT OUTER JOIN #PatientsWithSuppConceptPerSystem psps ON psps.[System] = s.[System] AND psps.Concept = s.Concept AND psps.[Table] = s.[Table] AND psps.[Version] = s.[Version]
ORDER BY s.Concept, s.[Table], s.[Version], pps.[System];

-- The following code can be used to identify gaps in our code sets
-- The always false if statement ensures we can execute the whole file
-- without the following running.
IF 1 > 2
BEGIN

	-- To determine which codes are causing discrepancies
	set nocount off;

	-- change this to find potentially misssing codes.
	declare @conceptx varchar(55);
	set @conceptx = 'insert-concept-here-must-be-same-as-above';

	-- Patients identified by the ref coding or SNOMED FK ids - but not by the supplied clinical codes
	IF OBJECT_ID('tempdb..#PatientsIdentifiedByIdButNotCode') IS NOT NULL DROP TABLE #PatientsIdentifiedByIdButNotCode;
	select distinct FK_Patient_Link_ID into #PatientsIdentifiedByIdButNotCode from #PatientsWithCode where Concept = @conceptx
	except
	select distinct FK_Patient_Link_ID from #PatientsWithSuppliedConcept where Concept = @conceptx

	-- Patients identified by the supplied clinical codes, but not the ref coding or SNOMED FK ids
	IF OBJECT_ID('tempdb..#PatientsIdentifiedByCodeButNotId') IS NOT NULL DROP TABLE #PatientsIdentifiedByCodeButNotId;
	select distinct FK_Patient_Link_ID into #PatientsIdentifiedByCodeButNotId from #PatientsWithSuppliedConcept where Concept = @conceptx
	except
	select distinct FK_Patient_Link_ID from #PatientsWithCode where Concept = @conceptx

	IF OBJECT_ID('tempdb..#PossibleExtraCodes') IS NOT NULL DROP TABLE #PossibleExtraCodes;
	select distinct SuppliedCode into #PossibleExtraCodes from RLS.vw_GP_Events
	where (
		FK_Reference_Coding_ID in (select FK_Reference_Coding_ID from #VersionedCodeSets where Concept=@conceptx) or
		FK_Reference_SnomedCT_ID in (select FK_Reference_SnomedCT_ID from #VersionedSnomedSets where Concept=@conceptx)
	)
	and FK_Patient_Link_ID IN (select FK_Patient_Link_ID from #PatientsIdentifiedByIdButNotCode);


	IF OBJECT_ID('tempdb..#PossibleExtraIds') IS NOT NULL DROP TABLE #PossibleExtraIds;
	select distinct FK_Reference_Coding_ID into #PossibleExtraIds from RLS.vw_GP_Events
	where SuppliedCode in (select Code from #AllCodes where Concept=@conceptx)
	and FK_Patient_Link_ID IN (select FK_Patient_Link_ID from #PatientsIdentifiedByCodeButNotId);

	-- spit out codes we may have missed
	select 
		'Potentially missing code', CodingType as CodingSource, MainCode as Code, 
		CASE 
			WHEN Term198 IS NULL THEN (
				CASE WHEN Term60 is null THEN (
					CASE WHEN Term30 is null THEN FullDescription ELSE Term30 END
				) ELSE Term60 END
			) ELSE Term198 END AS Term from SharedCare.Reference_Coding
	where PK_Reference_Coding_ID in (select FK_Reference_Coding_ID from #PossibleExtraIds)
	union
	select 
		'Potentially missing code', CodingType as CodingSource, MainCode as Code, 
		CASE 
			WHEN Term198 IS NULL THEN (
				CASE WHEN Term60 is null THEN (
					CASE WHEN Term30 is null THEN FullDescription ELSE Term30 END
				) ELSE Term60 END
			) ELSE Term198 END AS Term from SharedCare.Reference_Coding
	where MainCode in (select SuppliedCode from #PossibleExtraCodes)
	UNION
	select 'Potentially missing code', Source, LocalCode, LocalCodeDescription from SharedCare.Reference_Local_Code
	where LocalCode in (select SuppliedCode from #PossibleExtraCodes);
END
