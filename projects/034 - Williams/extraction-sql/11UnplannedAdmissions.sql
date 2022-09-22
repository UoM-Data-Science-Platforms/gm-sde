--+--------------------------------------------------------------------------------+
--¦ An unplanned hospital admission                                                ¦
--+--------------------------------------------------------------------------------+

-------- RESEARCH DATA ENGINEER CHECK ---------

-- OUTPUT: Data with the following fields
-- PatientId
-- Date (YYYY/MM/DD) 


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
	FROM RLS.vw_Acute_Inpatients i
	LEFT OUTER JOIN SharedCare.Reference_Tenancy t ON t.PK_Reference_Tenancy_ID = i.FK_Reference_Tenancy_ID
	WHERE EventType = 'Admission'
	AND AdmissionDate >= @StartDate
	GROUP BY FK_Patient_Link_ID, CONVERT(DATE, AdmissionDate), t.TenancyName
) sub;
-- 523477 rows	523477 rows
-- 00:00:16		00:00:45


-- Create the table of secondary admision===============================================================================================================
SELECT DISTINCT FK_Patient_Link_ID AS PatientId, AdmissionDate AS Date
FROM #AdmissionTypes
WHERE AdmissionDate >= @StartDate AND AdmissionDate < @EndDate 
      AND AdmissionType = 'Unplanned' AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsToInclude);


