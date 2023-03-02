--+--------------------------------------------------------------------------------+
--¦ Primary care encounter followed by unplanned hospital admission within 10 days ¦
--+--------------------------------------------------------------------------------+

-------- RESEARCH DATA ENGINEER CHECK ---------

-- OUTPUT: Data with the following fields
-- Year (YYYY)
-- Month (1-12)
-- CCG (can be an anonymised id for each CCG)
-- GPPracticeId
-- NumberOfUnplannedAdmissionsFollowingEncounter (integer) The number of unique patients for this year, month, ccg and practice, who had an unplanned hospital admission within 10 days of a GP encounter
-- NumberOfGPEncounter (integer) The number of GP encounters for this month, year, ccg and gp
-- NumberOfUnplannedAdmissions (integer) The number of unplanned hospital admissions

-- Set the start date
DECLARE @StartDate datetime;
DECLARE @EndDate datetime;
SET @StartDate = '2019-01-01';
SET @EndDate = '2022-06-01';

--Just want the output, not the messages
SET NOCOUNT ON;

-- Create a table with all patients (ID)=========================================================================================================================
IF OBJECT_ID('tempdb..#PatientsToInclude') IS NOT NULL DROP TABLE #PatientsToInclude;
SELECT FK_Patient_Link_ID INTO #PatientsToInclude
FROM RLS.vw_Patient_GP_History
GROUP BY FK_Patient_Link_ID
HAVING MIN(StartDate) < '2022-06-01';

IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT DISTINCT FK_Patient_Link_ID 
INTO #Patients 
FROM #PatientsToInclude;


--┌───────────────────────────────────────┐
--│ GET practice and ccg for each patient │
--└───────────────────────────────────────┘

-- OBJECTIVE:	For each patient to get the practice id that they are registered to, and 
--						the CCG name that the practice belongs to.

-- INPUT: Assumes there exists a temp table as follows:
-- #Patients (FK_Patient_Link_ID)
--  A distinct list of FK_Patient_Link_IDs for each patient in the cohort

-- OUTPUT: Two temp tables as follows:
-- #PatientPractice (FK_Patient_Link_ID, GPPracticeCode)
--	- FK_Patient_Link_ID - unique patient id
--	- GPPracticeCode - the nationally recognised practice id for the patient
-- #PatientPracticeAndCCG (FK_Patient_Link_ID, GPPracticeCode, CCG)
--	- FK_Patient_Link_ID - unique patient id
--	- GPPracticeCode - the nationally recognised practice id for the patient
--	- CCG - the name of the patient's CCG

-- If patients have a tenancy id of 2 we take this as their most likely GP practice
-- as this is the GP data feed and so most likely to be up to date
IF OBJECT_ID('tempdb..#PatientPractice') IS NOT NULL DROP TABLE #PatientPractice;
SELECT FK_Patient_Link_ID, MIN(GPPracticeCode) as GPPracticeCode INTO #PatientPractice FROM SharedCare.Patient
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND FK_Reference_Tenancy_ID = 2
AND GPPracticeCode IS NOT NULL
GROUP BY FK_Patient_Link_ID;
-- 1298467 rows
-- 00:00:11

-- Find the patients who remain unmatched
IF OBJECT_ID('tempdb..#UnmatchedPatientsForPracticeCode') IS NOT NULL DROP TABLE #UnmatchedPatientsForPracticeCode;
SELECT FK_Patient_Link_ID INTO #UnmatchedPatientsForPracticeCode FROM #Patients
EXCEPT
SELECT FK_Patient_Link_ID FROM #PatientPractice;
-- 12702 rows
-- 00:00:00

-- If every GPPracticeCode is the same for all their linked patient ids then we use that
INSERT INTO #PatientPractice
SELECT FK_Patient_Link_ID, MIN(GPPracticeCode) FROM SharedCare.Patient
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #UnmatchedPatientsForPracticeCode)
AND GPPracticeCode IS NOT NULL
GROUP BY FK_Patient_Link_ID
HAVING MIN(GPPracticeCode) = MAX(GPPracticeCode);
-- 12141
-- 00:00:00

-- Find any still unmatched patients
TRUNCATE TABLE #UnmatchedPatientsForPracticeCode;
INSERT INTO #UnmatchedPatientsForPracticeCode
SELECT FK_Patient_Link_ID FROM #Patients
EXCEPT
SELECT FK_Patient_Link_ID FROM #PatientPractice;
-- 561 rows
-- 00:00:00

-- If there is a unique most recent gp practice then we use that
INSERT INTO #PatientPractice
SELECT p.FK_Patient_Link_ID, MIN(p.GPPracticeCode) FROM SharedCare.Patient p
INNER JOIN (
	SELECT FK_Patient_Link_ID, MAX(HDMModifDate) MostRecentDate FROM SharedCare.Patient
	WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #UnmatchedPatientsForPracticeCode)
	GROUP BY FK_Patient_Link_ID
) sub ON sub.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND sub.MostRecentDate = p.HDMModifDate
WHERE p.GPPracticeCode IS NOT NULL
GROUP BY p.FK_Patient_Link_ID
HAVING MIN(GPPracticeCode) = MAX(GPPracticeCode);
-- 15

--┌──────────────────┐
--│ CCG lookup table │
--└──────────────────┘

-- OBJECTIVE: To provide lookup table for CCG names. The GMCR provides the CCG id (e.g. '00T', '01G') but not 
--            the CCG name. This table can be used in other queries when the output is required to be a ccg 
--            name rather than an id.

-- INPUT: No pre-requisites

-- OUTPUT: A temp table as follows:
-- #CCGLookup (CcgId, CcgName)
-- 	- CcgId - Nationally recognised ccg id
--	- CcgName - Bolton, Stockport etc..

IF OBJECT_ID('tempdb..#CCGLookup') IS NOT NULL DROP TABLE #CCGLookup;
CREATE TABLE #CCGLookup (CcgId nchar(3), CcgName nvarchar(20));
INSERT INTO #CCGLookup VALUES ('01G', 'Salford'); 
INSERT INTO #CCGLookup VALUES ('00T', 'Bolton'); 
INSERT INTO #CCGLookup VALUES ('01D', 'HMR'); 
INSERT INTO #CCGLookup VALUES ('02A', 'Trafford'); 
INSERT INTO #CCGLookup VALUES ('01W', 'Stockport');
INSERT INTO #CCGLookup VALUES ('00Y', 'Oldham'); 
INSERT INTO #CCGLookup VALUES ('02H', 'Wigan'); 
INSERT INTO #CCGLookup VALUES ('00V', 'Bury'); 
INSERT INTO #CCGLookup VALUES ('14L', 'Manchester'); 
INSERT INTO #CCGLookup VALUES ('01Y', 'Tameside Glossop'); 

IF OBJECT_ID('tempdb..#PatientPracticeAndCCG') IS NOT NULL DROP TABLE #PatientPracticeAndCCG;
SELECT p.FK_Patient_Link_ID, ISNULL(pp.GPPracticeCode,'') AS GPPracticeCode, ISNULL(ccg.CcgName, '') AS CCG
INTO #PatientPracticeAndCCG
FROM #Patients p
LEFT OUTER JOIN #PatientPractice pp ON pp.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN SharedCare.Reference_GP_Practice gp ON gp.OrganisationCode = pp.GPPracticeCode
LEFT OUTER JOIN #CCGLookup ccg ON ccg.CcgId = gp.Commissioner;
--┌───────────────────────────────┐
--│ Classify secondary admissions │
--└───────────────────────────────┘

-- OBJECTIVE: To categorise admissions to secondary care into 5 categories: Maternity, 
--						Unplanned, Planned, Transfer and Unknown.

-- ASSUMPTIONS:
--	-	We assume patients can only have one admission per day. This is probably not true, but 
--		where we see multiple admissions it is more likely to be data duplication, or internal
--		admissions, than an admission, discharge and another admission in the same day.
--	-	Where patients have multiple admissions we choose the "highest" category for admission
--		with the categories ranked as follows: Maternity > Unplanned > Planned > Transfer > Unknown
--	-	We have used the following classifications based on the AdmissionTypeCode:
--			- PLANNED: PL (ELECTIVE PLANNED), 11 (Elective - Waiting List), WL (ELECTIVE WL), 13 (Elective - Planned), 12 (Elective - Booked), BL (ELECTIVE BOOKED), D (NULL), Endoscopy (Endoscopy), OP (DIRECT OUTPAT CLINIC), Venesection (X36.2 Venesection), Colonoscopy (H22.9 Colonoscopy), Medical (Medical)
--			-	UNPLANNED: AE (AE.DEPT.OF PROVIDER), 21 (Emergency - Local A&E), I (NULL), GP (GP OR LOCUM GP), 22 (Emergency - GP), 23 (Emergency - Bed Bureau), 28 (Emergency - Other (inc other provider A&E)), 2D (Emergency - Other), 24 (Emergency - Clinic), EM (EMERGENCY OTHER), AI (ACUTE TO INTMED CARE), BB (EMERGENCY BED BUREAU), DO (EMERGENCY DOMICILE), 2A (A+E Department of another provider where the Patient has not been admitted), A+E (Admission	 A+E Admission), Emerg (GP	Emergency GP Patient)
--			-	MATERNITY: 31 (Maternity ante-partum), BH (BABY BORN IN HOSP), AN (MATERNITY ANTENATAL), 82 (Birth in this Health Care Provider), PN (MATERNITY POST NATAL), B (NULL), 32 (Maternity post-partum), BHOSP (Birth in this Health Care Provider)
--			-	TRANSFER: 81 (Transfer from other hosp (not A&E)), TR (PLAN TRANS TO TRUST), ET (EM TRAN (OTHER PROV)), HospTran (Transfer from other NHS Hospital), T (TRANSFER), CentTrans (Transfer from CEN Site)
--			-	OTHER: Anything else not previously classified

-- INPUT: No pre-requisites

-- OUTPUT: A temp table as follows:
-- #AdmissionTypes (FK_Patient_Link_ID, AdmissionDate, AcuteProvider, AdmissionType)
-- 	- FK_Patient_Link_ID - unique patient id
--	- AdmissionDate - date of admission (YYYY-MM-DD)
--	- AcuteProvider - Bolton, SRFT, Stockport etc..
--	- AdmissionType - One of: Maternity/Unplanned/Planned/Transfer/Unknown

-- For each acute admission we find the type. If multiple admissions on same day
-- we group and take the 'highest' category e.g.
-- choose Unplanned, then Planned, then Maternity, then Transfer, then Unknown
IF OBJECT_ID('tempdb..#AdmissionTypes') IS NOT NULL DROP TABLE #AdmissionTypes;
SELECT 
	FK_Patient_Link_ID, AdmissionDate, 
	CASE 
		WHEN AdmissionId = 5 THEN 'Maternity' 
		WHEN AdmissionId = 4 THEN 'Unplanned' 
		WHEN AdmissionId = 3 THEN 'Planned' 
		WHEN AdmissionId = 2 THEN 'Transfer' 
		WHEN AdmissionId = 1 THEN 'Unknown' 
	END as AdmissionType,
	AcuteProvider 
INTO #AdmissionTypes FROM (
	SELECT 
		FK_Patient_Link_ID, CONVERT(DATE, AdmissionDate) as AdmissionDate, 
		MAX(
			CASE 
				WHEN AdmissionTypeCode IN ('PL','11','WL','13','12','BL','D','Endoscopy','OP','Venesection','Colonoscopy','Flex sigmoidosco','Infliximab','IPPlannedAd','S.I. joint inj','Daycase','Extraction Multi','Chemotherapy','Total knee rep c','Total rep hip ce') THEN 3 --'Planned'
				WHEN AdmissionTypeCode IN ('AE','21','I','GP','22','23','EM','28','2D','24','AI','BB','DO','2A','A+E Admission','Emerg GP') THEN 4 --'Unplanned'
				WHEN AdmissionTypeCode IN ('31','BH','AN','82','PN','B','32','BHOSP') THEN 5 --'Maternity'
				WHEN AdmissionTypeCode IN ('81','TR','ET','HospTran','T','CentTrans') THEN 2 --'Transfer'
				WHEN AdmissionTypeCode IN ('Blood test','Blood transfusio','Medical') AND ReasonForAdmissionDescription LIKE ('Elective%') THEN 3 --'Planned'
				WHEN AdmissionTypeCode IN ('Blood test','Blood transfusio','Medical') AND ReasonForAdmissionDescription LIKE ('Emergency%') THEN 4 --'Unplanned'
				ELSE 1 --'Unknown'
			END
		)	AS AdmissionId,
		t.TenancyName AS AcuteProvider
	FROM SharedCare.Acute_Inpatients i
	LEFT OUTER JOIN SharedCare.Reference_Tenancy t ON t.PK_Reference_Tenancy_ID = i.FK_Reference_Tenancy_ID
	WHERE EventType = 'Admission'
	AND AdmissionDate >= @StartDate
	GROUP BY FK_Patient_Link_ID, CONVERT(DATE, AdmissionDate), t.TenancyName
) sub;
-- 523477 rows	523477 rows
-- 00:00:16		00:00:45
--┌───────────────────────┐
--│ Patient GP encounters │
--└───────────────────────┘

-- OBJECTIVE: To produce a table of GP encounters for a list of patients.
-- This script uses many codes related to observations (e.g. blood pressure), symptoms, and diagnoses, to infer when GP encounters occured.
-- This script includes face to face and telephone encounters - it will need copying and editing if you don't require both.

-- ASSUMPTIONS:
--	- multiple codes on the same day will be classed as one encounter (so max daily encounters per patient is 1)

-- INPUT: Assumes there exists a temp table as follows:
-- #Patients (FK_Patient_Link_ID)
--  A distinct list of FK_Patient_Link_IDs for each patient in the cohort

-- Also takes parameters:
--	-	all-patients: boolean - (true/false) if true, then all patients are included, otherwise only those in the pre-existing #Patients table.
--	- gp-events-table: string - (table name) the name of the table containing the GP events. Usually is "RLS.vw_GP_Events" but can be anything with the columns: FK_Patient_Link_ID, EventDate, FK_Reference_Coding_ID, and FK_Reference_SnomedCT_ID
--  - start-date: string - (YYYY-MM-DD) the date to count encounters from.
--  - end-date: string - (YYYY-MM-DD) the date to count encounters to.


-- OUTPUT: A temp table as follows:
-- #GPEncounters (FK_Patient_Link_ID, EncounterDate)
--	- FK_Patient_Link_ID - unique patient id
--	- EncounterDate - date the patient had a GP encounter


-- Create a table with all GP encounters ========================================================================================================

IF OBJECT_ID('tempdb..#CodingClassifier') IS NOT NULL DROP TABLE #CodingClassifier;
SELECT 'Face2face' AS EncounterType, PK_Reference_Coding_ID, FK_Reference_SnomedCT_ID
INTO #CodingClassifier
FROM SharedCare.Reference_Coding
WHERE CodingType='ReadCodeV2'
AND (
	MainCode like '1%'
	or MainCode like '2%'
	or MainCode in ('6A2..','6A9..','6AA..','6AB..','662d.','662e.','66AS.','66AS0','66AT.','66BB.','66f0.','66YJ.','66YM.','661Q.','66480','6AH..','6A9..','66p0.','6A2..','66Ay.','66Az.','69DC.')
	or MainCode like '6A%'
	or MainCode like '65%'
	or MainCode like '8B31[356]%'
	or MainCode like '8B3[3569ADEfilOqRxX]%'
	or MainCode in ('8BS3.')
	or MainCode like '8H[4-8]%' 
	or MainCode like '94Z%'
	or MainCode like '9N1C%' 
	or MainCode like '9N21%'
	or MainCode in ('9kF1.','9kR..','9HB5.')
	or MainCode like '9H9%'
);

INSERT INTO #CodingClassifier
SELECT 'Telephone', PK_Reference_Coding_ID, FK_Reference_SnomedCT_ID
FROM SharedCare.Reference_Coding
WHERE CodingType='ReadCodeV2'
AND (
	MainCode like '8H9%'
	or MainCode like '9N31%'
	or MainCode like '9N3A%'
);

-- Add the equivalent CTV3 codes
INSERT INTO #CodingClassifier
SELECT 'Face2face', PK_Reference_Coding_ID, FK_Reference_SnomedCT_ID FROM SharedCare.Reference_Coding
WHERE FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #CodingClassifier WHERE EncounterType='Face2face' AND FK_Reference_SnomedCT_ID != -1)
AND CodingType='CTV3';

INSERT INTO #CodingClassifier
SELECT 'Telephone', PK_Reference_Coding_ID, FK_Reference_SnomedCT_ID FROM SharedCare.Reference_Coding
WHERE FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #CodingClassifier WHERE EncounterType='Telephone' AND FK_Reference_SnomedCT_ID != -1)
AND CodingType='CTV3';

-- Add the equivalent EMIS codes
INSERT INTO #CodingClassifier
SELECT 'Face2face', FK_Reference_Coding_ID, FK_Reference_SnomedCT_ID FROM SharedCare.Reference_Local_Code
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #CodingClassifier WHERE EncounterType='Face2face' AND FK_Reference_SnomedCT_ID != -1) OR
	FK_Reference_Coding_ID IN (SELECT PK_Reference_Coding_ID FROM #CodingClassifier WHERE EncounterType='Face2face' AND PK_Reference_Coding_ID != -1)
);
INSERT INTO #CodingClassifier
SELECT 'Telephone', FK_Reference_Coding_ID, FK_Reference_SnomedCT_ID FROM SharedCare.Reference_Local_Code
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #CodingClassifier WHERE EncounterType='Telephone' AND FK_Reference_SnomedCT_ID != -1) OR
	FK_Reference_Coding_ID IN (SELECT PK_Reference_Coding_ID FROM #CodingClassifier WHERE EncounterType='Telephone' AND PK_Reference_Coding_ID != -1)
);

-- All above takes ~30s

IF OBJECT_ID('tempdb..#GPEncounters') IS NOT NULL DROP TABLE #GPEncounters;
CREATE TABLE #GPEncounters (
	FK_Patient_Link_ID BIGINT,
	EncounterDate DATE
);

BEGIN
  IF 'F'='true'
    INSERT INTO #GPEncounters 
    SELECT DISTINCT FK_Patient_Link_ID, CAST(EventDate AS DATE) AS EncounterDate
    FROM [RLS].[vw_GP_Events]
    WHERE 
      FK_Reference_Coding_ID IN (SELECT PK_Reference_Coding_ID FROM #CodingClassifier WHERE PK_Reference_Coding_ID != -1)
      AND EventDate BETWEEN '2019-01-01' AND '2022-06-01'
  ELSE 
    INSERT INTO #GPEncounters 
    SELECT DISTINCT FK_Patient_Link_ID, CAST(EventDate AS DATE) AS EncounterDate
    FROM [RLS].[vw_GP_Events]
    WHERE 
      FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
      AND FK_Reference_Coding_ID IN (SELECT PK_Reference_Coding_ID FROM #CodingClassifier WHERE PK_Reference_Coding_ID != -1)
      AND EventDate BETWEEN '2019-01-01' AND '2022-06-01'
  END


-- Numbers of GP encounter=========================================================================================================================================
-- All GP encounters
IF OBJECT_ID('tempdb..#GPEncounter') IS NOT NULL DROP TABLE #GPEncounter;
SELECT DISTINCT FK_Patient_Link_ID, EncounterDate,
	   YEAR (EncounterDate) AS [Year], MONTH (EncounterDate) AS [Month], DAY (EncounterDate) AS [Day]
INTO #GPEncounter
FROM #GPEncounters;

-- Count the number of GP encounters for each month
IF OBJECT_ID('tempdb..#GPEncounterFinal') IS NOT NULL DROP TABLE #GPEncounterFinal;
SELECT FK_Patient_Link_ID, [Year], [Month], COUNT(Day) AS NumberOfGPEncounter
INTO #GPEncounterFinal
FROM #GPEncounter
GROUP BY FK_Patient_Link_ID, [Year], [Month];


-- Numbers of unplanned admission=============================================================================================================================
-- All unplanned admission
IF OBJECT_ID('tempdb..#UnplannedAdmission') IS NOT NULL DROP TABLE #UnplannedAdmission;
SELECT DISTINCT FK_Patient_Link_ID, AdmissionDate,
	   YEAR (AdmissionDate) AS [Year], MONTH (AdmissionDate) AS [Month], DAY (AdmissionDate) AS [Day]
INTO #UnplannedAdmission
FROM #AdmissionTypes
WHERE AdmissionType = 'Unplanned' AND AdmissionDate < @EndDate;

-- Count unplanned admission for each month
IF OBJECT_ID('tempdb..#UnplannedAdmissionFinal') IS NOT NULL DROP TABLE #UnplannedAdmissionFinal;
SELECT FK_Patient_Link_ID, [Year], [Month], COUNT(Day) AS NumberOfUnplannedAdmissions
INTO #UnplannedAdmissionFinal
FROM #UnplannedAdmission
GROUP BY FK_Patient_Link_ID, [Year], [Month];


-- Create a table with all patients ===============================================================================================================================
IF OBJECT_ID('tempdb..#PatientsID') IS NOT NULL DROP TABLE #PatientsID;
SELECT DISTINCT FK_Patient_Link_ID 
INTO #PatientsID 
FROM [RLS].vw_Patient
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsToInclude);

-- All years and months from the start date
IF OBJECT_ID('tempdb..#Dates') IS NOT NULL DROP TABLE #Dates;
CREATE TABLE #Dates (
  d DATE,
  PRIMARY KEY (d)
)

WHILE ( @StartDate < @EndDate )
BEGIN
  INSERT INTO #Dates (d) VALUES( @StartDate )
  SELECT @StartDate = DATEADD(MONTH, 1, @StartDate )
END

IF OBJECT_ID('tempdb..#Time') IS NOT NULL DROP TABLE #Time;
SELECT DISTINCT YEAR(d) AS [Year], MONTH(d) AS [Month]
INTO #Time FROM #Dates

-- Merge 2 tables
IF OBJECT_ID('tempdb..#PatientsAll') IS NOT NULL DROP TABLE #PatientsAll;
SELECT *
INTO #PatientsAll
FROM #PatientsID, #Time;

-- Drop some tables
DROP TABLE #Dates
DROP TABLE #Time


-- Find patients who had unplanned admission within 10 days from GP encouter=============================================================================
IF OBJECT_ID('tempdb..#TableMerge') IS NOT NULL DROP TABLE #TableMerge;
SELECT p.FK_Patient_Link_ID, g.EncounterDate, u.AdmissionDate
INTO #TableMerge
FROM #PatientsID p
LEFT OUTER JOIN #GPEncounter g ON p.FK_Patient_Link_ID = g.FK_Patient_Link_ID 
LEFT OUTER JOIN #UnplannedAdmission u ON p.FK_Patient_Link_ID = u.FK_Patient_Link_ID
WHERE u.AdmissionDate <= DATEADD(DAY, 10, g.EncounterDate) AND u.AdmissionDate >= g.EncounterDate;

IF OBJECT_ID('tempdb..#TableAdmissionAfterGP') IS NOT NULL DROP TABLE #TableAdmissionAfterGP;
SELECT DISTINCT FK_Patient_Link_ID, YEAR(EncounterDate) AS [Year], MONTH(EncounterDate) AS [Month], 'Y' AS AdmissionAfterGP
INTO #TableAdmissionAfterGP
FROM #TableMerge;


-- Merge table=================================================================================================================================================================
-- Merge all information
IF OBJECT_ID('tempdb..#Table') IS NOT NULL DROP TABLE #Table;
SELECT p.FK_Patient_Link_ID, p.[Year], p.[Month], gp.GPPracticeCode, gp.CCG, u.NumberOfUnplannedAdmissions, e.NumberOfGPEncounter, t.AdmissionAfterGP
INTO #Table
FROM #PatientsAll p
LEFT OUTER JOIN #PatientPracticeAndCCG gp ON p.FK_Patient_Link_ID = GP.FK_Patient_Link_ID
LEFT OUTER JOIN #UnplannedAdmissionFinal u ON p.FK_Patient_Link_ID = u.FK_Patient_Link_ID AND p.[Year] = u.[Year] AND p.[Month] = u.[Month]
LEFT OUTER JOIN #GPEncounterFinal e ON p.FK_Patient_Link_ID = e.FK_Patient_Link_ID AND p.[Year] = e.[Year] AND p.[Month] = e.[Month]
LEFT OUTER JOIN #TableAdmissionAfterGP t ON p.FK_Patient_Link_ID = t.FK_Patient_Link_ID AND p.[Year] = t.[Year] AND p.[Month] = t.[Month];

-- Count
SELECT [Year], [Month], CCG, GPPracticeCode AS GPPracticeId, 
	   SUM (CASE WHEN AdmissionAfterGP = 'Y' THEN 1 ELSE 0 END) AS NumberOfUnplannedAdmissionsFollowingEncounter,
	   SUM (NumberOfGPEncounter) AS NumberOfGPEncounter,
	   SUM (NumberOfUnplannedAdmissions) AS NumberOfUnplannedAdmissions
FROM #Table
WHERE [Year] IS NOT NULL AND [Month] IS NOT NULL AND (CCG IS NOT NULL OR GPPracticeCode IS NOT NULL)
	  AND GPPracticeCode NOT LIKE '%DO NOT USE%' AND GPPracticeCode NOT LIKE '%TEST%'
GROUP BY [Year], [Month], CCG, GPPracticeCode
ORDER BY [Year], [Month], CCG, GPPracticeCode;


