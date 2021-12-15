--┌─────────────────────────────┐
--│ Patient cohort demographics │

------------- RDE CHECK --------------
-- RDE Name: George Tilston, Date of check: 06/05/21

-- OUTPUT: Data with the following fields
-- 	- PatientId (int)
-- 	- Sex (M/F/U)
--  - YearOfBirth (int) 
--  - GPPracticeCode
--  - DeathDate (YYY/MM/DD)

--Just want the output, not the messages
SET NOCOUNT ON;

-- For now let's use the in-built QOF rule for the RA cohort. We can refine this over time
--> EXECUTE query-qof-cohort.sql condition:"Rheumatoid Arthritis" outputtable:Patients

--> EXECUTE query-patient-sex.sql
--> EXECUTE query-patient-year-of-birth.sql
--> EXECUTE query-patient-practice-and-ccg.sql

SELECT p.FK_Patient_Link_ID AS PatientId, Sex, YearOfBirth, GPPracticeCode, pl.DeathDate FROM #Patients p
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientPractice pp ON pp.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN [RLS].vw_Patient_Link pl ON pl.PK_Patient_Link_ID = p.FK_Patient_Link_ID;
