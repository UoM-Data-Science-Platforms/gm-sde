--┌─────────────────────────────────────────┐
--│ Medications - sex hormone prescriptions │
--└─────────────────────────────────────────┘

-------- RESEARCH DATA ENGINEER CHECK -------------------------------

---------------------------------------------------------------------

--	- PatientId
--	- PrescriptionDate
--	- MedicationCategory/Code
--	- MedicationDescription (including duration, quantity and frequency information)
--	- Practice location/name (if allowed)

-- Prescriptions and treatments of interest include
--	-	hormone replacement therapies e.g 
--		-	oestradiol
--		-	progesterone
--		-	testosterone
--	-	birth control e.g
--		-	coil
--		-	implant
--		-	injection
--		-	contraceptive pill
--		-	termination pill
--	-	treatments for IMIDs e.g
--		-	biologics
--		-	steroids
--		-	DMARDS
--		-	NSAIDS
--	-	minor procedures including
--		-	coil fitting or removal
--		-	implant fitting or removal
--		-	peri or postpartum procedures.

DECLARE @StartDate datetime;
DECLARE @EndDate datetime;
SET @StartDate = 'CHANGE';
SET @EndDate = 'CHANGE';

--Just want the output, not the messages
SET NOCOUNT ON;

------------------------------------------------------------------------------
--> EXECUTE query-build-lh009-cohort.sql
------------------------------------------------------------------------------

--> CODESET hormone-replacement-therapy-meds:1


-- RX OF MEDS SINCE START DATE FOR COHORT, WITH CONCEPT AND DESCRIPTION

IF OBJECT_ID('tempdb..#meds') IS NOT NULL DROP TABLE #meds;
SELECT 
	 m.FK_Patient_Link_ID,
	 CAST(MedicationDate AS DATE) as PrescriptionDate,
	 [concept] = CASE WHEN s.[concept] IS NOT NULL THEN s.[concept] ELSE c.[concept] END,
	 Quantity,
	 [description] = CASE WHEN s.[description] IS NOT NULL THEN s.[description] ELSE c.[description] END
INTO #meds
FROM SharedCare.GP_Medications m
LEFT OUTER JOIN #VersionedSnomedSets s ON s.FK_Reference_SnomedCT_ID = m.FK_Reference_SnomedCT_ID
LEFT OUTER JOIN #VersionedCodeSets c ON c.FK_Reference_Coding_ID = m.FK_Reference_Coding_ID
WHERE m.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Cohort)
	AND m.MedicationDate BETWEEN @StartDate and @EndDate
	AND UPPER(SourceTable) NOT LIKE '%REPMED%'  -- exclude duplicate prescriptions 
	AND RepeatMedicationFlag = 'N' 				-- exclude duplicate prescriptions 

-- Produce final table of all medication prescriptions for main and matched cohort
SELECT	 
	PatientId = FK_Patient_Link_ID
	,MedicationCategory = concept
	,MedicationDescription = REPLACE([description], ',', '|')
	,Quantity
	,PrescriptionDate
FROM #meds m 
