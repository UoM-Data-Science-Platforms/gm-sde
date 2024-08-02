--┌─────────────┐
--│ Medications │
--└─────────────┘

------------ RESEARCH DATA ENGINEER CHECK ------------
-- 

-- All prescriptions of certain medications during the study period

-- OUTPUT: Data with the following fields
-- 	-   PatientId (int)
--  -   Year
--  -   Month
--	-	MedicationCategory - number of prescriptions for given medication category

--Just want the output, not the messages
SET NOCOUNT ON;

DECLARE @StartDate datetime;
DECLARE @EndDate datetime;
SET @StartDate = '2018-03-01';
SET @EndDate = '2023-08-31';

--> EXECUTE query-build-rq041-cohort.sql

-- load codesets needed for retrieving medication prescriptions

--> CODESET statins:1 ace-inhibitor:1 aspirin:1 clopidogrel:1 sglt2-inhibitors:1 nsaids:1 hormone-replacement-therapy-meds:1
--> CODESET female-sex-hormones:1 male-sex-hormones:1 anabolic-steroids:1

-- FIX ISSUE WITH DUPLICATE MEDICATIONS, CAUSED BY SOME CODES APPEARING MULTIPLE TIMES IN #VersionedCodeSets and #VersionedSnomedSets

IF OBJECT_ID('tempdb..#VersionedCodeSets_1') IS NOT NULL DROP TABLE #VersionedCodeSets_1;
SELECT DISTINCT FK_Reference_Coding_ID, Concept, [Version] INTO #VersionedCodeSets_1 FROM #VersionedCodeSets

IF OBJECT_ID('tempdb..#VersionedSnomedSets_1') IS NOT NULL DROP TABLE #VersionedSnomedSets_1;
SELECT DISTINCT FK_Reference_SnomedCT_ID, Concept, [Version] INTO #VersionedSnomedSets_1 FROM #VersionedSnomedSets

-- RETRIEVE ALL RELEVANT PRESCRIPTIONS FOR THE COHORT

-- ASSUME THAT IF A CODE IS PRESENT MORE THAN ONCE ON A GIVEN DAY FOR A PATIENT, IT IS A DUPLICATE

IF OBJECT_ID('tempdb..#meds_deduped') IS NOT NULL DROP TABLE #meds_deduped;
SELECT 
	 m.FK_Patient_Link_ID,
	 m.SuppliedCode,
	 m.FK_Reference_SnomedCT_ID,
	 m.FK_Reference_Coding_ID,
	 CAST(MedicationDate AS DATE) as PrescriptionDate
INTO #meds_deduped
FROM SharedCare.GP_Medications m
WHERE m.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Cohort)
	AND m.MedicationDate BETWEEN @StartDate AND @EndDate
	AND (
		m.FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets_1 WHERE (Concept NOT IN ('egfr','urinary-albumin-creatinine-ratio','glomerulonephritis', 'kidney-transplant', 'kidney-stones', 'vasculitis')))
		OR
		m.FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets_1 WHERE (Concept NOT IN ('egfr','urinary-albumin-creatinine-ratio','glomerulonephritis', 'kidney-transplant', 'kidney-stones', 'vasculitis')))
		)
GROUP BY m.FK_Patient_Link_ID,
	 m.SuppliedCode,
	 m.FK_Reference_SnomedCT_ID,
	 m.FK_Reference_Coding_ID,
	 CAST(MedicationDate AS DATE)

-- FOR EACH PRESCRIBED MEDICATION, PROVIDE THE CATEGORY AND PRESCRIPTION DATE

IF OBJECT_ID('tempdb..#medications_rx') IS NOT NULL DROP TABLE #medications_rx;
SELECT FK_Patient_Link_ID,
	 	PrescriptionDate,
		Concept = CASE WHEN s.Concept IS NOT NULL THEN s.Concept ELSE c.Concept END,
		m.FK_Reference_SnomedCT_ID,
	 	m.FK_Reference_Coding_ID
INTO #medications_rx
FROM #meds_deduped m
LEFT OUTER JOIN #VersionedSnomedSets_1 s ON s.FK_Reference_SnomedCT_ID = m.FK_Reference_SnomedCT_ID
LEFT OUTER JOIN #VersionedCodeSets_1 c ON c.FK_Reference_Coding_ID = m.FK_Reference_Coding_ID

--  FINAL TABLE: NUMBER OF EACH MEDICATION CATEGORY PRESCRIBED EACH MONTH 

IF OBJECT_ID('tempdb..#meds_wide') IS NOT NULL DROP TABLE #meds_wide;
select 
	PatientId = FK_Patient_Link_ID,
	YEAR(PrescriptionDate) as [Year], 
	Month(PrescriptionDate) as [Month], 
	statin = ISNULL(SUM(CASE WHEN Concept = 'statins' then 1 else 0 end),0),
	[ace-inhibitor-or-arb] = ISNULL(SUM(CASE WHEN Concept = 'ace-inhibitor' then 1 else 0 end),0),
	aspirin = ISNULL(SUM(CASE WHEN Concept = 'aspirin' then 1 else 0 end),0),
	clopidogrel = ISNULL(SUM(CASE WHEN Concept = 'clopidogrel' then 1 else 0 end),0),
	[sglt2-inhibitor] = ISNULL(SUM(CASE WHEN Concept = 'sglt2-inhibitors' then 1 else 0 end),0),
    nsaid = ISNULL(SUM(CASE WHEN Concept = 'nsaids' then 1 else 0 end),0), 
	[female-sex-hormones] = ISNULL(SUM(CASE WHEN Concept = 'female-sex-hormones' then 1 else 0 end),0),
	[male-sex-hormones] = ISNULL(SUM(CASE WHEN Concept = 'male-sex-hormones' then 1 else 0 end),0),
	[anabolic-steroids] = ISNULL(SUM(CASE WHEN Concept = 'anabolic-steroids' then 1 else 0 end),0),
	[hormone-replacement-therapy] = ISNULL(SUM(CASE WHEN Concept = 'hormone-replacement-therapy-meds' then 1 else 0 end),0)
from #medications_rx
group by FK_Patient_Link_ID, YEAR(PrescriptionDate), Month(PrescriptionDate)
order by FK_Patient_Link_ID, YEAR(PrescriptionDate), Month(PrescriptionDate)
