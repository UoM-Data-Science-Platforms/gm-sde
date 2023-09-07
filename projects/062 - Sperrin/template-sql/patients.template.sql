--+--------------------------------------------------------------------------------+
--¦ Patient information                                                            ¦
--+--------------------------------------------------------------------------------+

-------- RESEARCH DATA ENGINEER CHECK ---------

-- OUTPUT: Data with the following fields
-- PatientId
-- WeekOfBirth (dd/mm/yyyy)
-- MonthAndYearOfBirth (mm/yyyy)
-- Sex
-- Ethnicity
-- GPID
-- RegistrationGPDate 
-- DeregistrationGPDate
-- LSOA
-- IMD 
-- NumberGPEncounterBeforeSept2013


--Just want the output, not the messages
SET NOCOUNT ON;


--> EXECUTE query-build-rq062-cohort.sql
