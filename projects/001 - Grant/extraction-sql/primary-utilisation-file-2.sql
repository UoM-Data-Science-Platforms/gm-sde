--┌─────────────────────────────────┐
--│ Primary care utilisation file 2 │
--└─────────────────────────────────┘

-- OUTPUT: Data with the following fields
-- 	•	Date (YYYY-MM-DD) 
--	•	ConsultationType (face2face/remote/home visit/ooh/other)
-- 	•	CCG (Bolton/Salford/HMR/etc.)
-- 	•	Practice (P27001/P27001/etc..)
-- 	•	CovidHealthcareUtilisation (TRUE/FALSE)
-- 	•	2019IMDDecile (integer 1-10)
-- 	•	NumberOfLTCs (integer 0,1,2) – where 2 represents 2 or more
-- 	•	NumberOfConsultations (integer) 

--Just want the output, not the messages
SET NOCOUNT ON;

-- Set the start date
DECLARE @StartDate datetime;
SET @StartDate = '2020-01-01';

-- TODO - need to work on the GP consulation classification