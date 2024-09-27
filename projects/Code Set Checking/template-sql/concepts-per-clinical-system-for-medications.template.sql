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

-- OUTPUT: A table with the following fields
-- 	- Concept - the medication
--  - Version - the version of the clinical concept
--  - System  - the clinical system (EMIS/Vision/TPP)
--  - PatientsWithConcept  - the number of patients with a clinical code for this concept in their record
--  - Patients  - the number of patients for this system supplier
--  - PercentageOfPatients  - the percentage of patients for this system supplier with this concept

--Just want the output, not the messages
SET NOCOUNT ON;

--> CODESET insert-concepts-here:version-number
--> EXECUTE query-practice-systems-lookup.sql

-- Get all patients from the GP_Medications table who have a matching FK_Reference_Coding_ID
IF OBJECT_ID('tempdb..#PatientsWithFKMedCode') IS NOT NULL DROP TABLE #PatientsWithFKMedCode;
SELECT FK_Patient_Link_ID, FK_Reference_Coding_ID INTO #PatientsWithFKMedCode FROM SharedCare.GP_Medications
WHERE FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets);

-- Then get all patients from the GP_Medications table who have a matching FK_Reference_SnomedCT_ID
IF OBJECT_ID('tempdb..#PatientsWithSNOMEDMedCode') IS NOT NULL DROP TABLE #PatientsWithSNOMEDMedCode;
SELECT FK_Patient_Link_ID, FK_Reference_SnomedCT_ID INTO #PatientsWithSNOMEDMedCode FROM SharedCare.GP_Medications
WHERE FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets);
--00:02:02 - for 2 above together

-- Link the above temp tables with the concept tables to find a list of patients with medications
-- and add to the previously created temp table
IF OBJECT_ID('tempdb..#PatientsWithCode') IS NOT NULL DROP TABLE #PatientsWithCode;
SELECT FK_Patient_Link_ID, Concept, [Version] INTO #PatientsWithCode FROM #PatientsWithFKMedCode p
INNER JOIN #VersionedCodeSets v ON v.FK_Reference_Coding_ID = p.FK_Reference_Coding_ID
UNION
SELECT FK_Patient_Link_ID, Concept, [Version] FROM #PatientsWithSNOMEDMedCode p
INNER JOIN #VersionedSnomedSets v ON v.FK_Reference_SnomedCT_ID = p.FK_Reference_SnomedCT_ID
GROUP BY FK_Patient_Link_ID, Concept, [Version];
--00:01:01

-- Counts the number of patients for each version of each concept for each clinical system
IF OBJECT_ID('tempdb..#PatientsWithCodePerSystem') IS NOT NULL DROP TABLE #PatientsWithCodePerSystem;
SELECT [System], Concept, [Version], count(*) as [Count] into #PatientsWithCodePerSystem FROM SharedCare.Patient p
INNER JOIN #PracticeSystemLookup s on s.PracticeId = p.GPPracticeCode
INNER JOIN #PatientsWithCode c on c.FK_Patient_Link_ID = p.FK_Patient_Link_ID
WHERE FK_Reference_Tenancy_ID = 2
AND NOT EXISTS (SELECT * FROM SharedCare.Patient_Link WHERE PK_Patient_Link_ID = p.FK_Patient_Link_ID and Deceased = 'Y')
GROUP BY [System], Concept, [Version];
--00:00:56

-- Counts the number of patients per system
IF OBJECT_ID('tempdb..#PatientsPerSystem') IS NOT NULL DROP TABLE #PatientsPerSystem;
SELECT [System], count(*) as [Count] into #PatientsPerSystem FROM SharedCare.Patient p
INNER JOIN #PracticeSystemLookup s on s.PracticeId = p.GPPracticeCode
WHERE FK_Reference_Tenancy_ID = 2
AND NOT EXISTS (SELECT * FROM SharedCare.Patient_Link WHERE PK_Patient_Link_ID = p.FK_Patient_Link_ID and Deceased = 'Y')
GROUP BY [System];
--00:00:41

-- Finds all patients with one of the clinical codes in the medication table
IF OBJECT_ID('tempdb..#PatientsWithSuppliedCode') IS NOT NULL DROP TABLE #PatientsWithSuppliedCode;
SELECT FK_Patient_Link_ID, SuppliedCode INTO #PatientsWithSuppliedCode FROM SharedCare.GP_Medications e
WHERE SuppliedCode IN (SELECT [Code] FROM #AllCodes);
--00:04:10

IF OBJECT_ID('tempdb..#PatientsWithSuppliedConcept') IS NOT NULL DROP TABLE #PatientsWithSuppliedConcept;
SELECT FK_Patient_Link_ID, Concept, [Version] AS [Version] INTO #PatientsWithSuppliedConcept FROM #PatientsWithSuppliedCode p
INNER JOIN #AllCodes a on a.Code = p.SuppliedCode
GROUP BY FK_Patient_Link_ID, [Concept], [Version];
--00:00:42

-- Counts the number of patients for each version of each concept for each clinical system
IF OBJECT_ID('tempdb..#PatientsWithSuppConceptPerSystem') IS NOT NULL DROP TABLE #PatientsWithSuppConceptPerSystem;
SELECT [System], Concept, [Version], count(*) as [Count] into #PatientsWithSuppConceptPerSystem FROM SharedCare.Patient p
INNER JOIN #PracticeSystemLookup s on s.PracticeId = p.GPPracticeCode
INNER JOIN #PatientsWithSuppliedConcept c on c.FK_Patient_Link_ID = p.FK_Patient_Link_ID
WHERE FK_Reference_Tenancy_ID = 2
AND NOT EXISTS (SELECT * FROM SharedCare.Patient_Link WHERE PK_Patient_Link_ID = p.FK_Patient_Link_ID and Deceased = 'Y')
GROUP BY [System], Concept, [Version];
--00:01:31

-- Populate table with system/event type possibilities
IF OBJECT_ID('tempdb..#SystemEventCombos') IS NOT NULL DROP TABLE #SystemEventCombos;
SELECT DISTINCT [Concept], [Version],'EMIS' as [System] INTO #SystemEventCombos FROM #AllCodes
UNION
SELECT DISTINCT [Concept], [Version],'TPP' as [System] FROM #AllCodes
UNION
SELECT DISTINCT [Concept], [Version],'Vision' as [System] FROM #AllCodes;

IF OBJECT_ID('tempdb..#TempFinal') IS NOT NULL DROP TABLE #TempFinal;
SELECT 
	s.Concept, s.[Version], pps.[System], MAX(pps.[Count]) as Patients, SUM(CASE WHEN p.[Count] IS NULL THEN 0 ELSE p.[Count] END) as PatientsWithConcept,
	SUM(CASE WHEN psps.[Count] IS NULL THEN 0 ELSE psps.[Count] END) as PatiensWithConceptFromCode,
	SUM(CASE WHEN p.[Count] IS NULL THEN 0 ELSE 100 * CAST(p.[Count] AS float)/pps.[Count] END) as PercentageOfPatients,
	SUM(CASE WHEN psps.[Count] IS NULL THEN 0 ELSE 100 * CAST(psps.[Count] AS float)/pps.[Count] END) as PercentageOfPatientsFromCode
INTO #TempFinal
FROM #SystemEventCombos s
LEFT OUTER JOIN #PatientsWithCodePerSystem p on p.[System] = s.[System] AND p.Concept = s.Concept AND p.[Version] = s.[Version]
INNER JOIN #PatientsPerSystem pps ON pps.[System] = s.[System]
LEFT OUTER JOIN #PatientsWithSuppConceptPerSystem psps ON psps.[System] = s.[System] AND psps.Concept = s.Concept AND psps.[Version] = s.[Version]
GROUP BY s.Concept, s.[Version], pps.[System]
ORDER BY s.Concept, s.[Version], pps.[System];

-- FINAL MEDICATION TABLE
SELECT Concept, Version, 
	CONCAT('| ', FORMAT (getdate(), 'yyyy-MM-dd') , ' | ', System, ' | ', Patients, ' | ',
		PatientsWithConcept, 
		' (',
		case when PercentageOfPatients = 0 then 0 else round(PercentageOfPatients ,2-floor(log10(abs(PercentageOfPatients )))) end, '%) | ',
		PatiensWithConceptFromCode, 
		' (',
		case when PercentageOfPatientsFromCode = 0 then 0 else round(PercentageOfPatientsFromCode ,2-floor(log10(abs(PercentageOfPatientsFromCode )))) end, '%) | ') AS TextForReadMe  FROM #TempFinal


-- The following code can be used to identify gaps in our code sets
-- The always false if statement ensures we can execute the whole file
-- without the following running.

IF 1 > 2
BEGIN

	-- THIS IS FOR CODES THAT APPEAR IN THE GP_Medications TABLE - SEE ABOVE FOR EVENTS
	-- To determine which codes are causing discrepancies
	set nocount off;

	-- change this to find potentially misssing codes.
	declare @medicationconcept varchar(55);
	set @medicationconcept = 'insert-concepts-here';

	-- Patients identified by the ref coding or SNOMED FK ids - but not by the supplied clinical codes
	IF OBJECT_ID('tempdb..#MEDSPatientsIdentifiedByIdButNotCode') IS NOT NULL DROP TABLE #MEDSPatientsIdentifiedByIdButNotCode;
	select distinct FK_Patient_Link_ID into #MEDSPatientsIdentifiedByIdButNotCode from #PatientsWithCode where Concept = @medicationconcept
	except
	select distinct FK_Patient_Link_ID from #PatientsWithSuppliedConcept where Concept = @medicationconcept

	-- Patients identified by the supplied clinical codes, but not the ref coding or SNOMED FK ids
	IF OBJECT_ID('tempdb..#MEDSPatientsIdentifiedByCodeButNotId') IS NOT NULL DROP TABLE #MEDSPatientsIdentifiedByCodeButNotId;
	select distinct FK_Patient_Link_ID into #MEDSPatientsIdentifiedByCodeButNotId from #PatientsWithSuppliedConcept where Concept = @medicationconcept
	except
	select distinct FK_Patient_Link_ID from #PatientsWithCode where Concept = @medicationconcept

	IF OBJECT_ID('tempdb..#MEDSPossibleExtraCodes') IS NOT NULL DROP TABLE #MEDSPossibleExtraCodes;
	select distinct SuppliedCode into #MEDSPossibleExtraCodes from SharedCare.GP_Medications
	where (
		FK_Reference_Coding_ID in (select FK_Reference_Coding_ID from #VersionedCodeSets where Concept=@medicationconcept) or
		FK_Reference_SnomedCT_ID in (select FK_Reference_SnomedCT_ID from #VersionedSnomedSets where Concept=@medicationconcept)
	)
	and FK_Patient_Link_ID IN (select FK_Patient_Link_ID from #MEDSPatientsIdentifiedByIdButNotCode);


	IF OBJECT_ID('tempdb..#MEDSPossibleExtraIds') IS NOT NULL DROP TABLE #MEDSPossibleExtraIds;
	select distinct FK_Reference_Coding_ID into #MEDSPossibleExtraIds from SharedCare.GP_Medications
	where SuppliedCode in (select Code from #AllCodes where Concept=@medicationconcept)
	and FK_Patient_Link_ID IN (select FK_Patient_Link_ID from #MEDSPatientsIdentifiedByCodeButNotId);

	-- spit out codes we may have missed
	select 
		'Potentially missing code', CodingType as CodingSource, MainCode as Code, 
		CASE 
			WHEN Term198 IS NULL THEN (
				CASE WHEN Term60 is null THEN (
					CASE WHEN Term30 is null THEN FullDescription COLLATE Latin1_General_CS_AS ELSE Term30 END
				) ELSE Term60 END
			) ELSE Term198 END AS Term from SharedCare.Reference_Coding
	where PK_Reference_Coding_ID in (select FK_Reference_Coding_ID from #MEDSPossibleExtraIds)
	union
	select 
		'Potentially missing code', CodingType as CodingSource, MainCode as Code, 
		CASE 
			WHEN Term198 IS NULL THEN (
				CASE WHEN Term60 is null THEN (
					CASE WHEN Term30 is null THEN FullDescription COLLATE Latin1_General_CS_AS ELSE Term30 END
				) ELSE Term60 END
			) ELSE Term198 END AS Term from SharedCare.Reference_Coding
	where MainCode in (select SuppliedCode from #MEDSPossibleExtraCodes)
	UNION
	select 'Potentially missing code', Source, LocalCode, LocalCodeDescription from SharedCare.Reference_Local_Code
	where LocalCode in (select SuppliedCode from #MEDSPossibleExtraCodes);
END

{{no-output-table}}