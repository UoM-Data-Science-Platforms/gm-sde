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

-- OUTPUT: Two tables (one for events and one for medications) with the following fields
-- 	- Concept - the clinical concept e.g. the diagnosis, medication, procedure...
--  - Version - the version of the clinical concept
--  - System  - the clinical system (EMIS/Vision/TPP)
--  - PatientsWithConcept  - the number of patients with a clinical code for this concept in their record
--  - Patients  - the number of patients for this system supplier
--  - PercentageOfPatients  - the percentage of patients for this system supplier with this concept

--Just want the output, not the messages
SET NOCOUNT ON;

-- >>> Codesets required... Inserting the code set code

-- >>> Following codesets injected: 
--┌──────────────────────────────┐
--│ Practice system lookup table │
--└──────────────────────────────┘

-- OBJECTIVE: To provide lookup table for GP systems. The GMCR doesn't hold this information
--            in the data so here is a lookup. This was accurate on 27th Jan 2021 and will
--            likely drift out of date slowly as practices change systems. Though this doesn't 
--            happen very often.

-- INPUT: No pre-requisites

-- OUTPUT: A temp table as follows:
-- #PracticeSystemLookup (PracticeId, System)
-- 	- PracticeId - Nationally recognised practice id
--	- System - EMIS, TPP, VISION

IF OBJECT_ID('tempdb..#PracticeSystemLookup') IS NOT NULL DROP TABLE #PracticeSystemLookup;
CREATE TABLE #PracticeSystemLookup (PracticeId nchar(6), System nvarchar(20));
INSERT INTO #PracticeSystemLookup VALUES
('P82001', 'EMIS'),('P82002', 'TPP'),('P82003', 'TPP'),('P82004', 'TPP'),('P82005', 'TPP'),('P82006', 'EMIS'),('P82007', 'TPP'),('P82008', 'TPP'),('P82009', 'EMIS'),('P82010', 'EMIS'),('P82011', 'EMIS'),('P82012', 'EMIS'),('P82013', 'EMIS'),('P82014', 'TPP'),('P82015', 'EMIS'),('P82016', 'EMIS'),('P82018', 'EMIS'),('P82020', 'EMIS'),('P82021', 'EMIS'),('P82022', 'EMIS'),('P82023', 'Vision'),('P82025', 'TPP'),('P82029', 'EMIS'),('P82030', 'EMIS'),('P82031', 'EMIS'),('P82033', 'EMIS'),('P82034', 'EMIS'),('P82036', 'EMIS'),('P82037', 'EMIS'),('P82607', 'EMIS'),('P82609', 'EMIS'),('P82613', 'EMIS'),('P82616', 'EMIS'),('P82624', 'Vision'),('P82625', 'EMIS'),('P82626', 'EMIS'),('P82627', 'EMIS'),('P82629', 'Vision'),('P82633', 'EMIS'),('P82634', 'TPP'),('P82640', 'EMIS'),('P82643', 'EMIS'),('P82652', 'EMIS'),('P82660', 'Vision'),('Y00186', 'EMIS'),('Y02319', 'EMIS'),('Y02790', 'EMIS'),('Y03079', 'EMIS'),('Y03366', 'TPP'),('P83001', 'Vision'),('P83004', 'Vision'),('P83005', 'Vision'),('P83006', 'Vision'),('P83007', 'Vision'),('P83009', 'Vision'),('P83010', 'Vision'),('P83011', 'Vision'),('P83012', 'Vision'),('P83015', 'Vision'),('P83017', 'Vision'),('P83020', 'Vision'),('P83021', 'Vision'),('P83024', 'Vision'),('P83025', 'Vision'),('P83027', 'Vision'),('P83603', 'Vision'),('P83605', 'Vision'),('P83608', 'Vision'),('P83609', 'Vision'),('P83611', 'Vision'),('P83612', 'Vision'),('P83620', 'Vision'),('P83621', 'Vision'),('P83623', 'Vision'),('Y02755', 'Vision'),('P86001', 'EMIS'),('P86002', 'EMIS'),('P86003', 'EMIS'),('P86004', 'EMIS'),('P86005', 'EMIS'),('P86006', 'EMIS'),('P86007', 'EMIS'),('P86008', 'EMIS'),('P86009', 'EMIS'),('P86010', 'EMIS'),('P86011', 'EMIS'),('P86012', 'EMIS'),('P86013', 'EMIS'),('P86014', 'EMIS'),('P86015', 'EMIS'),('P86016', 'EMIS'),('P86017', 'EMIS'),('P86018', 'EMIS'),('P86019', 'EMIS'),('P86021', 'EMIS'),('P86022', 'EMIS'),('P86023', 'EMIS'),('P86026', 'EMIS'),('P86602', 'EMIS'),('P86606', 'EMIS'),('P86608', 'EMIS'),('P86609', 'EMIS'),('P86614', 'EMIS'),('P86619', 'EMIS'),('P86620', 'EMIS'),('P86624', 'EMIS'),('Y00726', 'EMIS'),('Y02718', 'EMIS'),('Y02720', 'EMIS'),('Y02721', 'EMIS'),('Y02795', 'EMIS'),('P84004', 'EMIS'),('P84005', 'EMIS'),('P84009', 'EMIS'),('P84010', 'EMIS'),('P84012', 'EMIS'),('P84014', 'EMIS'),('P84016', 'EMIS'),('P84017', 'EMIS'),('P84018', 'EMIS'),('P84019', 'EMIS'),('P84020', 'EMIS'),('P84021', 'EMIS'),('P84022', 'EMIS'),('P84023', 'EMIS'),('P84024', 'EMIS'),('P84025', 'EMIS'),('P84026', 'EMIS'),('P84027', 'EMIS'),('P84028', 'EMIS'),('P84029', 'EMIS'),('P84030', 'EMIS'),('P84032', 'EMIS'),('P84033', 'EMIS'),('P84034', 'EMIS'),('P84035', 'EMIS'),('P84037', 'EMIS'),('P84038', 'EMIS'),('P84039', 'EMIS'),('P84040', 'EMIS'),('P84041', 'EMIS'),('P84042', 'EMIS'),('P84043', 'EMIS'),('P84045', 'EMIS'),('P84046', 'EMIS'),('P84047', 'EMIS'),('P84048', 'EMIS'),('P84049', 'EMIS'),('P84050', 'EMIS'),('P84051', 'EMIS'),('P84052', 'EMIS'),('P84053', 'EMIS'),('P84054', 'EMIS'),('P84056', 'EMIS'),('P84059', 'EMIS'),('P84061', 'EMIS'),('P84064', 'EMIS'),('P84065', 'EMIS'),('P84066', 'EMIS'),('P84067', 'EMIS'),('P84068', 'EMIS'),('P84070', 'EMIS'),('P84071', 'EMIS'),('P84072', 'EMIS'),('P84074', 'EMIS'),('P84605', 'EMIS'),('P84611', 'EMIS'),('P84616', 'EMIS'),('P84626', 'EMIS'),('P84630', 'EMIS'),('P84635', 'EMIS'),('P84637', 'EMIS'),('P84639', 'EMIS'),('P84640', 'EMIS'),('P84644', 'EMIS'),('P84645', 'EMIS'),('P84650', 'EMIS'),('P84651', 'EMIS'),('P84652', 'EMIS'),('P84663', 'EMIS'),('P84665', 'EMIS'),('P84669', 'EMIS'),('P84672', 'EMIS'),('P84673', 'EMIS'),('P84678', 'EMIS'),('P84679', 'EMIS'),('P84683', 'EMIS'),('P84684', 'EMIS'),('P84689', 'EMIS'),('P84690', 'EMIS'),('Y01695', 'EMIS'),('Y02325', 'EMIS'),('Y02520', 'EMIS'),('Y02849', 'EMIS'),('Y02890', 'EMIS'),('Y02960', 'EMIS'),('P85001', 'EMIS'),('P85002', 'EMIS'),('P85003', 'EMIS'),('P85004', 'EMIS'),('P85005', 'EMIS'),('P85007', 'EMIS'),('P85008', 'EMIS'),('P85010', 'EMIS'),('P85011', 'EMIS'),('P85012', 'EMIS'),('P85013', 'EMIS'),('P85014', 'EMIS'),('P85015', 'EMIS'),('P85016', 'EMIS'),('P85017', 'EMIS'),('P85018', 'EMIS'),('P85019', 'EMIS'),('P85020', 'EMIS'),('P85021', 'EMIS'),('P85022', 'EMIS'),('P85026', 'EMIS'),('P85028', 'EMIS'),('P85601', 'EMIS'),('P85602', 'EMIS'),('P85605', 'EMIS'),('P85606', 'EMIS'),('P85607', 'EMIS'),('P85608', 'EMIS'),('P85610', 'EMIS'),('P85612', 'EMIS'),('P85614', 'EMIS'),('P85615', 'EMIS'),('P85620', 'EMIS'),('P85621', 'EMIS'),('P85622', 'EMIS'),('P89006', 'EMIS'),('Y01124', 'EMIS'),('Y02753', 'EMIS'),('Y02827', 'EMIS'),('Y02875', 'EMIS'),('Y02933', 'EMIS'),('P87002', 'EMIS'),('P87003', 'Vision'),('P87004', 'Vision'),('P87008', 'EMIS'),('P87015', 'Vision'),('P87016', 'EMIS'),('P87017', 'EMIS'),('P87019', 'EMIS'),('P87020', 'Vision'),('P87022', 'Vision'),('P87024', 'EMIS'),('P87025', 'EMIS'),('P87026', 'EMIS'),('P87027', 'EMIS'),('P87028', 'EMIS'),('P87032', 'Vision'),('P87035', 'EMIS'),('P87039', 'Vision'),('P87040', 'Vision'),('P87610', 'Vision'),('P87613', 'EMIS'),('P87618', 'EMIS'),('P87620', 'Vision'),('P87624', 'EMIS'),('P87625', 'EMIS'),('P87627', 'EMIS'),('P87630', 'EMIS'),('P87634', 'EMIS'),('P87639', 'Vision'),('P87648', 'Vision'),('P87649', 'EMIS'),('P87651', 'Vision'),('P87654', 'EMIS'),('P87657', 'Vision'),('P87658', 'EMIS'),('P87659', 'Vision'),('P87661', 'EMIS'),('Y00445', 'Vision'),('Y02622', 'EMIS'),('Y02625', 'EMIS'),('Y02767', 'EMIS'),('P88002', 'EMIS'),('P88003', 'EMIS'),('P88005', 'EMIS'),('P88006', 'EMIS'),('P88007', 'EMIS'),('P88008', 'EMIS'),('P88009', 'EMIS'),('P88011', 'EMIS'),('P88012', 'EMIS'),('P88013', 'EMIS'),('P88014', 'EMIS'),('P88015', 'EMIS'),('P88016', 'EMIS'),('P88017', 'EMIS'),('P88018', 'EMIS'),('P88019', 'EMIS'),('P88020', 'EMIS'),('P88021', 'EMIS'),('P88023', 'EMIS'),('P88024', 'EMIS'),('P88025', 'EMIS'),('P88026', 'EMIS'),('P88031', 'EMIS'),('P88034', 'EMIS'),('P88041', 'EMIS'),('P88042', 'EMIS'),('P88043', 'EMIS'),('P88044', 'EMIS'),('P88606', 'EMIS'),('P88607', 'EMIS'),('P88610', 'EMIS'),('P88615', 'EMIS'),('P88623', 'EMIS'),('P88625', 'EMIS'),('P88632', 'EMIS'),('Y00912', 'EMIS'),('C81077', 'EMIS'),('C81081', 'EMIS'),('C81106', 'EMIS'),('C81615', 'EMIS'),('C81640', 'EMIS'),('C81660', 'EMIS'),('P89002', 'EMIS'),('P89003', 'EMIS'),('P89004', 'EMIS'),('P89005', 'EMIS'),('P89007', 'TPP'),('P89008', 'EMIS'),('P89010', 'EMIS'),('P89011', 'EMIS'),('P89012', 'EMIS'),('P89013', 'EMIS'),('P89014', 'EMIS'),('P89015', 'EMIS'),('P89016', 'EMIS'),('P89018', 'EMIS'),('P89020', 'EMIS'),('P89021', 'EMIS'),('P89022', 'EMIS'),('P89023', 'EMIS'),('P89025', 'EMIS'),('P89026', 'EMIS'),('P89029', 'EMIS'),('P89030', 'EMIS'),('P89602', 'EMIS'),('P89609', 'EMIS'),('P89612', 'EMIS'),('P89613', 'EMIS'),('P89618', 'EMIS'),('Y02586', 'EMIS'),('Y02663', 'EMIS'),('Y02713', 'EMIS'),('Y02936', 'EMIS'),('P91003', 'EMIS'),('P91004', 'EMIS'),('P91006', 'EMIS'),('P91007', 'EMIS'),('P91008', 'EMIS'),('P91009', 'EMIS'),('P91011', 'EMIS'),('P91012', 'EMIS'),('P91013', 'EMIS'),('P91014', 'EMIS'),('P91016', 'EMIS'),('P91017', 'EMIS'),('P91018', 'EMIS'),('P91019', 'EMIS'),('P91020', 'EMIS'),('P91021', 'EMIS'),('P91026', 'EMIS'),('P91029', 'EMIS'),('P91035', 'EMIS'),('P91603', 'EMIS'),('P91604', 'EMIS'),('P91617', 'EMIS'),('P91619', 'EMIS'),('P91623', 'EMIS'),('P91625', 'EMIS'),('P91627', 'EMIS'),('P91629', 'EMIS'),('P91631', 'EMIS'),('P91633', 'EMIS'),('P92001', 'TPP'),('P92002', 'EMIS'),('P92003', 'EMIS'),('P92004', 'EMIS'),('P92005', 'TPP'),('P92006', 'TPP'),('P92007', 'TPP'),('P92008', 'EMIS'),('P92010', 'TPP'),('P92011', 'EMIS'),('P92012', 'TPP'),('P92014', 'EMIS'),('P92015', 'EMIS'),('P92016', 'TPP'),('P92017', 'EMIS'),('P92019', 'EMIS'),('P92020', 'EMIS'),('P92021', 'EMIS'),('P92023', 'EMIS'),('P92024', 'TPP'),('P92026', 'EMIS'),('P92028', 'EMIS'),('P92029', 'TPP'),('P92030', 'Vision'),('P92031', 'TPP'),('P92033', 'EMIS'),('P92034', 'TPP'),('P92035', 'TPP'),('P92038', 'TPP'),('P92041', 'EMIS'),('P92042', 'EMIS'),('P92602', 'EMIS'),('P92605', 'EMIS'),('P92607', 'TPP'),('P92615', 'TPP'),('P92616', 'EMIS'),('P92620', 'EMIS'),('P92621', 'EMIS'),('P92623', 'TPP'),('P92626', 'EMIS'),('P92630', 'EMIS'),('P92633', 'EMIS'),('P92634', 'EMIS'),('P92635', 'Vision'),('P92637', 'EMIS'),('P92639', 'TPP'),('P92642', 'TPP'),('P92646', 'EMIS'),('P92647', 'TPP'),('P92648', 'TPP'),('P92651', 'EMIS'),('P92653', 'TPP'),('Y00050', 'TPP'),('Y02274', 'EMIS'),('Y02321', 'EMIS'),('Y02322', 'EMIS'),('Y02378', 'EMIS'),('Y02885', 'EMIS'),('Y02886', 'EMIS');


-- Finds all patients with one of the clinical codes in the GP_Events table
IF OBJECT_ID('tempdb..#PatientsWithCode') IS NOT NULL DROP TABLE #PatientsWithCode;
SELECT 'EVENT' AS [Table], FK_Patient_Link_ID, Concept, [Version] INTO #PatientsWithCode FROM RLS.[vw_GP_Events] e
INNER JOIN #VersionedCodeSets v on v.FK_Reference_Coding_ID = e.FK_Reference_Coding_ID
UNION
SELECT 'EVENT', FK_Patient_Link_ID, Concept, [Version] FROM RLS.[vw_GP_Events] e
INNER JOIN #VersionedSnomedSets v on v.FK_Reference_SnomedCT_ID = e.FK_Reference_SnomedCT_ID
GROUP BY FK_Patient_Link_ID, Concept, [Version];

-- Finds all patients with one of the clinical codes in the GP_Medications table
INSERT INTO #PatientsWithCode
SELECT 'MED', FK_Patient_Link_ID, Concept, [Version] FROM RLS.[vw_GP_Medications] e
INNER JOIN #VersionedCodeSets v on v.FK_Reference_Coding_ID = e.FK_Reference_Coding_ID
UNION
SELECT 'MED', FK_Patient_Link_ID, Concept, [Version] FROM RLS.[vw_GP_Medications] e
INNER JOIN #VersionedSnomedSets v on v.FK_Reference_SnomedCT_ID = e.FK_Reference_SnomedCT_ID
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

-- Finds all patients with one of the clinical codes in the events table
IF OBJECT_ID('tempdb..#PatientsWithSuppliedCode') IS NOT NULL DROP TABLE #PatientsWithSuppliedCode;
SELECT 'EVENT' AS [Table], FK_Patient_Link_ID, SuppliedCode INTO #PatientsWithSuppliedCode FROM RLS.[vw_GP_Events] e
WHERE SuppliedCode IN (SELECT [Code] FROM #AllCodes);
--03:27

-- Finds all patients with one of the clinical codes in the meds table
INSERT INTO #PatientsWithSuppliedCode
SELECT 'MED', FK_Patient_Link_ID, SuppliedCode FROM RLS.[vw_GP_Medications] e
WHERE SuppliedCode IN (SELECT [Code] FROM #AllCodes);

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
SELECT DISTINCT [Concept], [Version],'EMIS' as [System],'EVENT' as [Table] INTO #SystemEventCombos FROM #AllCodes
UNION
SELECT DISTINCT [Concept], [Version],'TPP' as [System],'EVENT' as [Table] FROM #AllCodes
UNION
SELECT DISTINCT [Concept], [Version],'Vision' as [System],'EVENT' as [Table] FROM #AllCodes
UNION
SELECT DISTINCT [Concept], [Version],'EMIS' as [System],'MED' as [Table] FROM #AllCodes
UNION
SELECT DISTINCT [Concept], [Version],'TPP' as [System],'MED' as [Table] FROM #AllCodes
UNION
SELECT DISTINCT [Concept], [Version],'Vision' as [System],'MED' as [Table] FROM #AllCodes;

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
	declare @concept varchar(55);
	set @concept = 'moderate-clinical-vulnerability';

	-- Patients identified by the ref coding or SNOMED FK ids - but not by the supplied clinical codes
	IF OBJECT_ID('tempdb..#PatientsIdentifiedByIdButNotCode') IS NOT NULL DROP TABLE #PatientsIdentifiedByIdButNotCode;
	select distinct FK_Patient_Link_ID into #PatientsIdentifiedByIdButNotCode from #PatientsWithCode where Concept = @concept
	except
	select distinct FK_Patient_Link_ID from #PatientsWithSuppliedConcept where Concept = @concept

	-- Patients identified by the supplied clinical codes, but not the ref coding or SNOMED FK ids
	IF OBJECT_ID('tempdb..#PatientsIdentifiedByCodeButNotId') IS NOT NULL DROP TABLE #PatientsIdentifiedByCodeButNotId;
	select distinct FK_Patient_Link_ID into #PatientsIdentifiedByCodeButNotId from #PatientsWithSuppliedConcept where Concept = @concept
	except
	select distinct FK_Patient_Link_ID from #PatientsWithCode where Concept = @concept

	IF OBJECT_ID('tempdb..#PossibleExtraCodes') IS NOT NULL DROP TABLE #PossibleExtraCodes;
	select distinct SuppliedCode into #PossibleExtraCodes from RLS.vw_GP_Events
	where (
		FK_Reference_Coding_ID in (select FK_Reference_Coding_ID from #VersionedCodeSets where Concept=@concept) or
		FK_Reference_SnomedCT_ID in (select FK_Reference_SnomedCT_ID from #VersionedSnomedSets where Concept=@concept)
	)
	and FK_Patient_Link_ID IN (select FK_Patient_Link_ID from #PatientsIdentifiedByIdButNotCode);


	IF OBJECT_ID('tempdb..#PossibleExtraIds') IS NOT NULL DROP TABLE #PossibleExtraIds;
	select distinct FK_Reference_Coding_ID into #PossibleExtraIds from RLS.vw_GP_Events
	where SuppliedCode in (select Code from #AllCodes where Concept=@concept)
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