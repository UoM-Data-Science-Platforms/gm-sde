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
SET @StartDate = '2014-01-01';


--> EXECUTE query-build-rq062-cohort.sql
--> EXECUTE query-get-admissions-and-length-of-stay.sql all-patients:false

----- create anonymised identifier for each hospital
-- this is included in case PI wants to consider the fact that each hospitalstarted providing complete data on different dates

IF OBJECT_ID('tempdb..#hospitals') IS NOT NULL DROP TABLE #hospitals;
SELECT DISTINCT AcuteProvider
INTO #hospitals
FROM #LengthOfStay

IF OBJECT_ID('tempdb..#RandomiseHospital') IS NOT NULL DROP TABLE #RandomiseHospital;
SELECT AcuteProvider
	, HospitalID = ROW_NUMBER() OVER (order by newid())
INTO #RandomiseHospital
FROM #hospitals

-- Create the final table
SELECT FK_Patient_Link_ID AS PatientID,
 	   YearAndMonthOfAdmission = DATEADD(dd, -( DAY( AdmissionDate) -1 ), AdmissionDate),
	   LengthOfStayDays = LengthOfStay,
	   HospitalID 
FROM #LengthOfStay a
LEFT JOIN #RandomiseHospital rh ON rh.AcuteProvider = a.AcuteProvider
ORDER BY FK_Patient_Link_ID, AdmissionDate


------ advise team that some hospitals only started providing data in 2020/21. Show them table on this page: https://github.com/rw251/gm-idcr/blob/master/docs/index.md