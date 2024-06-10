--┌─────────────┐
--│ Medications │
--└─────────────┘

------------ RESEARCH DATA ENGINEER CHECK ------------
-- 
------------------------------------------------------

-- All prescriptions of: cardiovascular, immunosuppresant, and steroid medications.

-- OUTPUT: Data with the following fields
-- 	-   PatientId (int)
--	-	MedicationDescription
--	-	MostRecentPrescriptionDate (YYYY-MM-DD)

--Just want the output, not the messages
SET NOCOUNT ON;

-- Set the start date
DECLARE @StartDate datetime;
DECLARE @EndDate datetime;
SET @StartDate = '2006-01-01'; -- CHECK
SET @EndDate = '2023-10-31'; --CHECK

--> EXECUTE query-build-lh004-cohort.sql

-- steroids
--> CODESET prednisolone:1

-- immunosuppressants
--> CODESET methotrexate:1 tacrolimus:1 azathioprine:1 mycophenolate-mofetil:1 ciclosporin:1 hydroxychloroquine:1 

-- to add: chloroquine

--> CODESET cyclophosphamide:1 rituximab:1

-- cardiovascular
--> CODESET ace-inhibitor:1 sglt2-inhibitors:1 statins:1 antiplatelet-medications:1


-- SLE PATIENTS WITH RX OF CERTAIN MEDS SINCE ____

IF OBJECT_ID('tempdb..#medications') IS NOT NULL DROP TABLE #medications;
SELECT 
	 m.FK_Patient_Link_ID,
		CAST(MedicationDate AS DATE) as PrescriptionDate,
		Quantity,
		Dosage,
		[concept] = CASE WHEN s.[concept] IS NOT NULL THEN s.[concept] ELSE c.[concept] END
		--[description] = CASE WHEN s.[description] IS NOT NULL THEN s.[description] ELSE c.[description] END
INTO #medications
FROM SharedCare.GP_Medications m
LEFT OUTER JOIN #VersionedSnomedSets s ON s.FK_Reference_SnomedCT_ID = m.FK_Reference_SnomedCT_ID
LEFT OUTER JOIN #VersionedCodeSets c ON c.FK_Reference_Coding_ID = m.FK_Reference_Coding_ID
WHERE m.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Cohort)
AND m.MedicationDate BETWEEN @StartDate AND @EndDate
AND (
	m.FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets) OR
    m.FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets)
);

-- TABLE FOR NUMBER OF EACH MED PRESCRIBED IN THE LAST YEAR 

SELECT
	FK_Patient_Link_ID,
	MIN(PrescriptionDate) AS MinDate,
	MAX(PrescriptionDate) AS MaxDate,
	COUNT(*) AS PrescriptionsInLastYear
FROM #medications
WHERE PrescriptionDate BETWEEN DATEADD(DD, -365, @EndDate) AND @EndDate

-- TABLE FLAGGING WHICH MEDICATIONS EACH PATIENT IS CURRENTLY ON



