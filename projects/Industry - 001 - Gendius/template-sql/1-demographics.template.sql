--┌──────────────────────┐
--│ Patient demographics │
--└──────────────────────┘

TODO CKD code set

-- OUTPUT: Data with the following fields
--  - PatientID
--  - Practice (P27001/P27001/etc..)
--  - 2019IMDDecile1IsMostDeprived10IsLeastDeprived (integer 1-10)
--  - QuarterOfBirth (YYYY-MM-DD)
--  - YearMonthOfT2DDiagnosis (earliest diagnosis date - YYYY-MM)
--  - Sex (M/F)
--  - Height (most recent)
--  - Ethnicity (suppressed grouping is sufficient)
--  - YearMonthFirstSGLT2i prescription
--  - YearMonthFirstACE-I prescription
--  - YearMonthFirstARB prescription
--  - YearMonthCKDstage 3-5 diagnosis (earliest diagnosis date)
--  - YearMonthHFdiagnosis (earliest diagnosis date)
--  - YearMonthCVDdiagnosis (earliest diagnosis date)
--  - YearMonthCancerdiagnosis (earliest diagnosis date)
--  - YearMonthDeath
--  - YearMonthRegistrationwith a GM primary care practice (only to be provided if not registered at index date)
--  - YearMonthDeregistration from GM primary care practice (only to be provided if not registered at extract date)


--Just want the output, not the messages
SET NOCOUNT ON;

--> EXECUTE query-build-industry-001-cohort.sql date:2023-09-19

--> EXECUTE query-patient-sex.sql
--> EXECUTE query-patient-year-of-birth.sql
--> EXECUTE query-patient-imd.sql
--> EXECUTE query-patient-practice-and-ccg.sql