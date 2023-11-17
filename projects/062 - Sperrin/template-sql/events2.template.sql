--+--------------------------------------------------------------------------------+
--¦ Patient hospital admisson                                                      ¦
--+--------------------------------------------------------------------------------+
-- !!! NEED TO DO: WHEN WE HAVE WEEK OF BIRTH, PLEASE CHANGE THE QUERY-BUILD-RQ062-COHORT.SQL TO UPDATE THE COHORT. ALSO ADD WEEK OF BRTH FOR THE TABLE BELOW. THANKS.
-- !!! NEED TO DO: DISCUSS TO MAKE SURE THE PROVIDED DATA IS NOT IDENTIFIABLE.

-------- RESEARCH DATA ENGINEER CHECK ---------


-- OUTPUT: Data with the following fields
-- - PatientId
-- - AdmissionDate
-- - DischargeDate


--Just want the output, not the messages
SET NOCOUNT ON;

-- Set the start date
DECLARE @StartDate datetime;
SET @StartDate = '1800-01-01';


--> EXECUTE query-build-rq062-cohort.sql


-- Populate temporary table with admissions
-- Convert AdmissionDate to a date to avoid issues where a person has two admissions
-- on the same day (but only one discharge)
IF OBJECT_ID('tempdb..#Admissions') IS NOT NULL DROP TABLE #Admissions;
CREATE TABLE #Admissions (
	FK_Patient_Link_ID BIGINT,
	AdmissionDate DATE,
	AcuteProvider NVARCHAR(150)
);

INSERT INTO #Admissions
SELECT DISTINCT FK_Patient_Link_ID, CONVERT(DATE, AdmissionDate) AS AdmissionDate, t.TenancyName AS AcuteProvider
FROM [SharedCare].[Acute_Inpatients] i
LEFT OUTER JOIN SharedCare.Reference_Tenancy t ON t.PK_Reference_Tenancy_ID = i.FK_Reference_Tenancy_ID
WHERE EventType = 'Admission'
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND AdmissionDate >= @StartDate;


--> EXECUTE query-get-discharges.sql all-patients:false

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


-- Create the final table
SELECT FK_Patient_Link_ID AS PatientID, AdmissionDate, DischargeDate 
FROM #LengthOfStay
ORDER BY FK_Patient_Link_ID, AdmissionDate
