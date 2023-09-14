--┌────────────────────────────────────┐
--│ An example SQL generation template │
--└────────────────────────────────────┘

-- OUTPUT: Data with the following fields
-- 	- PatientId (int)
-- 

--Just want the output, not the messages
SET NOCOUNT ON;

--> EXECUTE query-build-lh004-cohort.sql



--bring together for final output
--patients in main cohort
SELECT	 PatientId = m.FK_Patient_Link_ID
		,m.YearOfBirth
		,m.Sex
		,LSOA_Code
		,m.EthnicMainGroup ----- CHANGE TO MORE SPECIFIC ETHNICITY
		,IMD2019Decile1IsMostDeprived10IsLeastDeprived
		,pp.PatientPractice 
FROM #Cohort m
LEFT OUTER JOIN RLS.vw_Patient_Link pl ON pl.PK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientPractice pp ON pp.FK_Patient_Link_ID = m.FK_Patient_Link_ID
WHERE M.FK_Patient_Link_ID in (SELECT FK_Patient_Link_ID FROM #Patients)
