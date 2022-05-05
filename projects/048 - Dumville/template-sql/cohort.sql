--┌──────────────────┐
--│ Main cohort file │
--└──────────────────┘

-- OUTPUT: Data with the following fields
--  - PatientId (int)
--  - MatchingPatientId (int)
--  - OximetryAtHome (YYYYMMDD - or blank if not used)
--  - FirstCovidPositiveDate (DDMMYYYY)
--  - SecondCovidPositiveDate (DDMMYYYY)
--  - ThirdCovidPositiveDate (DDMMYYYY)
--  - YearOfBirth (YYYY)
--  - Sex (M/F)
--  - LSOA
--  - Ethnicity
--  - IMD2019Decile1IsMostDeprived10IsLeastDeprived
--  - MonthOfDeath (MM)
--  - YearOfDeath (YYYY)
--  - LivesInCareHome (Y/N)


--Just want the output, not the messages
SET NOCOUNT ON;

