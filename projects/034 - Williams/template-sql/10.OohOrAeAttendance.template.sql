--+--------------------------------------------------------------------------------+
--¦ OOH or A&E attendance                                                          ¦
--+--------------------------------------------------------------------------------+

-------- RESEARCH DATA ENGINEER CHECK ---------

-- OUTPUT: Data with the following fields
-- PatientId
-- Date (YYYY/MM/DD) 


-- Set the start date
DECLARE @StartDate datetime;
SET @StartDate = '2019-01-01';

--Just want the output, not the messages
SET NOCOUNT ON;

-- Create the final table==========================================================================================================================================
-- No OOH data is available
SELECT DISTINCT FK_Patient_Link_ID AS PatientID, TRY_CONVERT(DATE, AttendanceDate) AS Date
FROM [RLS].[vw_Acute_AE]
WHERE EventType = 'Attendance' AND TRY_CONVERT(DATE, AttendanceDate) >= @StartDate;