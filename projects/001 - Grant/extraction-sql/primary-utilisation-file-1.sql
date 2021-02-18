--┌─────────────────────────────────┐
--│ Primary care utilisation file 1 │
--└─────────────────────────────────┘

-- OUTPUT: Data with the following fields
-- 	•	Date (YYYY-MM-DD) 
--	•	ConsultationType (face2face/remote/home visit/ooh/other)
-- 	•	CCG (Bolton/Salford/HMR/etc.)
-- 	•	Practice (P27001/P27001/etc..)
-- 	•	CovidHealthcareUtilisation (TRUE/FALSE)
-- 	•	2019IMDDecile (integer 1-10)
-- 	•	LTCGroup  (none/respiratory/mental health/cardiovascular/ etc.) 
-- 	•	NumberOfConsultations (integer) 

-- TODO questions
-- * If someone has 2 GP consulations on the same day does that count as 1 or 2?
--	 Can only count as one, because it could be duplication.
-- * Frequently encounters have the code '.....' which basically means no code. Can happen several times a day. Risk of including is that it is perhaps recording
--	 every time someone looks at the record - e.g. to check appointment. Risk of excluding is that it means something else.
-- * Will need to just look for consultations with a particular set of codes.
-- * IMD score not useful. IMD decile is useful.
-- * For patients without an IMD - or with multiple conflicting ones - do we ignore? Or put in separate column?

--Just want the output, not the messages
SET NOCOUNT ON;

-- Set the start date
DECLARE @StartDate datetime;
SET @StartDate = '2020-01-01';

-- TODO - need to work on the GP consulation classification