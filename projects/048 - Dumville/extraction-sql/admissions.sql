--┌────────────┐
--│ Admissions │
--└────────────┘

--------------------- RDE CHECK ---------------------
-- Le Mai Parkes  - 25 May 2022 - via pull request --
-----------------------------------------------------

-- OUTPUT: Data with the following fields
--  - PatientId (int)
--  - AdmissionDate (YYYYMMDD)
--  - DischargeDate (YYYYMMDD)
--  - Status (planned/unplanned/maternity/transfer/other)

--Just want the output, not the messages
SET NOCOUNT ON;

-- Set the start date
DECLARE @StartDate datetime;
SET @StartDate = '2020-01-01';

-- Set the end date
DECLARE @EndDate datetime;
SET @EndDate = '2022-07-01';

-- Assume temp table #OxAtHome (FK_Patient_Link_ID, AdmissionDate, DischargeDate)

-- Table of all patients (not matching cohort - will do that subsequently)
IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT FK_Patient_Link_ID INTO #Patients FROM #OxAtHome
WHERE AdmissionDate < @EndDate
AND (DischargeDate IS NULL OR DischargeDate < @EndDate);

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
--┌─────────────────────────────────────────┐
--│ Secondary admissions and length of stay │
--└─────────────────────────────────────────┘

-- OBJECTIVE: To obtain a table with every secondary care admission, along with the acute provider,
--						the date of admission, the date of discharge, and the length of stay.

-- INPUT: One parameter
--	-	all-patients: boolean - (true/false) if true, then all patients are included, otherwise only those in the pre-existing #Patients table.

-- OUTPUT: Two temp table as follows:
-- #Admissions (FK_Patient_Link_ID, AdmissionDate, AcuteProvider)
-- 	- FK_Patient_Link_ID - unique patient id
--	- AdmissionDate - date of admission (YYYY-MM-DD)
--	- AcuteProvider - Bolton, SRFT, Stockport etc..
--  (Limited to one admission per person per hospital per day, because if a patient has 2 admissions 
--   on the same day to the same hopsital then it's most likely data duplication rather than two short
--   hospital stays)
-- #LengthOfStay (FK_Patient_Link_ID, AdmissionDate)
-- 	- FK_Patient_Link_ID - unique patient id
--	- AdmissionDate - date of admission (YYYY-MM-DD)
--	- AcuteProvider - Bolton, SRFT, Stockport etc..
--	- DischargeDate - date of discharge (YYYY-MM-DD)
--	- LengthOfStay - Number of days between admission and discharge. 1 = [0,1) days, 2 = [1,2) days, etc.

-- Set the temp end date until new legal basis
DECLARE @TEMPAdmissionsEndDate datetime;
SET @TEMPAdmissionsEndDate = '2022-06-01';

-- Populate temporary table with admissions
-- Convert AdmissionDate to a date to avoid issues where a person has two admissions
-- on the same day (but only one discharge)
IF OBJECT_ID('tempdb..#Admissions') IS NOT NULL DROP TABLE #Admissions;
CREATE TABLE #Admissions (
	FK_Patient_Link_ID BIGINT,
	AdmissionDate DATE,
	AcuteProvider NVARCHAR(150)
);
BEGIN
	IF 'false'='true'
		INSERT INTO #Admissions
		SELECT DISTINCT FK_Patient_Link_ID, CONVERT(DATE, AdmissionDate) AS AdmissionDate, t.TenancyName AS AcuteProvider
		FROM [SharedCare].[Acute_Inpatients] i
		LEFT OUTER JOIN SharedCare.Reference_Tenancy t ON t.PK_Reference_Tenancy_ID = i.FK_Reference_Tenancy_ID
		WHERE EventType = 'Admission'
		AND AdmissionDate >= @StartDate
		AND AdmissionDate <= @TEMPAdmissionsEndDate;
	ELSE
		INSERT INTO #Admissions
		SELECT DISTINCT FK_Patient_Link_ID, CONVERT(DATE, AdmissionDate) AS AdmissionDate, t.TenancyName AS AcuteProvider
		FROM [SharedCare].[Acute_Inpatients] i
		LEFT OUTER JOIN SharedCare.Reference_Tenancy t ON t.PK_Reference_Tenancy_ID = i.FK_Reference_Tenancy_ID
		WHERE EventType = 'Admission'
		AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
		AND AdmissionDate >= @StartDate
		AND AdmissionDate <= @TEMPAdmissionsEndDate;
END

--┌──────────────────────┐
--│ Secondary discharges │
--└──────────────────────┘

-- OBJECTIVE: To obtain a table with every secondary care discharge, along with the acute provider,
--						and the date of discharge.

-- INPUT: One parameter
--	-	all-patients: boolean - (true/false) if true, then all patients are included, otherwise only those in the pre-existing #Patients table.

-- OUTPUT: A temp table as follows:
-- #Discharges (FK_Patient_Link_ID, DischargeDate, AcuteProvider)
-- 	- FK_Patient_Link_ID - unique patient id
--	- DischargeDate - date of discharge (YYYY-MM-DD)
--	- AcuteProvider - Bolton, SRFT, Stockport etc..
--  (Limited to one discharge per person per hospital per day, because if a patient has 2 discharges 
--   on the same day to the same hopsital then it's most likely data duplication rather than two short
--   hospital stays)

-- Set the temp end date until new legal basis
DECLARE @TEMPDischargesEndDate datetime;
SET @TEMPDischargesEndDate = '2022-06-01';

-- Populate temporary table with discharges
IF OBJECT_ID('tempdb..#Discharges') IS NOT NULL DROP TABLE #Discharges;
CREATE TABLE #Discharges (
	FK_Patient_Link_ID BIGINT,
	DischargeDate DATE,
	AcuteProvider NVARCHAR(150)
);
BEGIN
	IF 'false'='true'
		INSERT INTO #Discharges
    SELECT DISTINCT FK_Patient_Link_ID, CONVERT(DATE, DischargeDate) AS DischargeDate, t.TenancyName AS AcuteProvider 
    FROM [SharedCare].[Acute_Inpatients] i
    LEFT OUTER JOIN SharedCare.Reference_Tenancy t ON t.PK_Reference_Tenancy_ID = i.FK_Reference_Tenancy_ID
    WHERE EventType = 'Discharge'
    AND DischargeDate >= @StartDate
    AND DischargeDate <= @TEMPDischargesEndDate;
  ELSE
		INSERT INTO #Discharges
    SELECT DISTINCT FK_Patient_Link_ID, CONVERT(DATE, DischargeDate) AS DischargeDate, t.TenancyName AS AcuteProvider 
    FROM [SharedCare].[Acute_Inpatients] i
    LEFT OUTER JOIN SharedCare.Reference_Tenancy t ON t.PK_Reference_Tenancy_ID = i.FK_Reference_Tenancy_ID
    WHERE EventType = 'Discharge'
		AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
    AND DischargeDate >= @StartDate
    AND DischargeDate <= @TEMPDischargesEndDate;;
END
-- 535285 rows	535285 rows
-- 00:00:28		00:00:14


-- Link admission with discharge to get length of stay
-- Length of stay is zero-indexed e.g. 
-- 1 = [0,1) days
-- 2 = [1,2) days
IF OBJECT_ID('tempdb..#LengthOfStay') IS NOT NULL DROP TABLE #LengthOfStay;
SELECT 
	a.FK_Patient_Link_ID, a.AdmissionDate, a.AcuteProvider, 
	MIN(d.DischargeDate) AS DischargeDate, 
	1 + DATEDIFF(day,a.AdmissionDate, MIN(d.DischargeDate)) AS LengthOfStay
	INTO #LengthOfStay
FROM #Admissions a
INNER JOIN #Discharges d ON d.FK_Patient_Link_ID = a.FK_Patient_Link_ID AND d.DischargeDate >= a.AdmissionDate AND d.AcuteProvider = a.AcuteProvider
GROUP BY a.FK_Patient_Link_ID, a.AdmissionDate, a.AcuteProvider
ORDER BY a.FK_Patient_Link_ID, a.AdmissionDate, a.AcuteProvider;
-- 511740 rows	511740 rows	
-- 00:00:04		00:00:05


SELECT 
  o.FK_Patient_Link_ID AS PatientId,
  admit.AdmissionDate,
  los.DischargeDate,
  admit.AdmissionType AS [Status]
FROM #OxAtHome o
LEFT OUTER JOIN #AdmissionTypes admit ON admit.FK_Patient_Link_ID = o.FK_Patient_Link_ID
LEFT OUTER JOIN #LengthOfStay los 
  ON los.FK_Patient_Link_ID = o.FK_Patient_Link_ID
  AND los.AdmissionDate = admit.AdmissionDate
WHERE admit.AdmissionDate < @EndDate
AND (los.DischargeDate IS NULL OR los.DischargeDate < @EndDate);