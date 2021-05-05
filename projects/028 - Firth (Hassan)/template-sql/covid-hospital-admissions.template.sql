--┌────────────────────────────────────┐
--│ Hospital stay information  	       │
--└────────────────────────────────────┘

-- REVIEW LOG:

-- OUTPUT: Data with the following fields
-- Patient Id
-- AdmissionDate (DD-MM-YYYY)
-- DischargeDate (DD-MM-YYYY)
-- LengthOfStay 
-- Hospital - ANONYMOUS


--Just want the output, not the messages
SET NOCOUNT ON;

--> CODESET severe-mental-illness

-- COHORT: PATIENTS THAT HAVE AN SMI DIAGNOSIS AS OF 31.01.20

IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT distinct gp.FK_Patient_Link_ID 
INTO #Patients
FROM [RLS].[vw_GP_Events] gp
LEFT OUTER JOIN #Patients p ON p.PK_Patient_ID = gp.FK_Patient_ID
WHERE SuppliedCode IN (
	SELECT [Code] FROM #AllCodes WHERE [Concept] IN ('severe-mental-illness') AND [Version] = 1
)
	AND (gp.EventDate) <= '2020-01-31'

--> EXECUTE query-get-admissions-and-length-of-stay.sql
--> EXECUTE query-admissions-covid-utilisation.sql

IF OBJECT_ID('tempdb..#HospitalAdmissions') IS NOT NULL DROP TABLE #HospitalAdmissions;
SELECT 
	FK_Patient_Link_ID,
	AdmissionDate,
	DischargeDate,
	LengthOfStay,
	Hospital = l.AcuteProvider
INTO #HospitalAdmissions
FROM #LengthOfStay l
LEFT OUTER JOIN #COVIDUtilisationAdmissions c ON c.FK_Patient_Link_ID = l.FK_Patient_Link_ID AND c.AdmissionDate = l.AdmissionDate AND c.AcuteProvider = l.AcuteProvider
LEFT OUTER JOIN #PatientPracticeAndCCG ppc ON ppc.FK_Patient_Link_ID = l.FK_Patient_Link_ID
WHERE c.CovidHealthcareUtilisation = 'TRUE'