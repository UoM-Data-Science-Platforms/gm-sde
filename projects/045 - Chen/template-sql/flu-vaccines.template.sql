
--┌────────────────────┐
--│ Flu vaccinations   │
--└────────────────────┘

-- OBJECTIVE: To obtain a table with all flu vaccinations for each patient.

-- OUTPUT: 
-- 	- FK_Patient_Link_ID - unique patient id
--	- VaccinationDate - date of vaccine administration (YYYY-MM-DD)

-- Set the start date
DECLARE @EndDate datetime;
SET @EndDate = '2023-12-31';

--> CODESET flu-vaccination:1
--> EXECUTE query-build-rq045-cohort.sql



SELECT p.FK_Patient_Link_ID, 
	FluVaccinationYearAndMonth = DATEADD(dd, -( DAY( CAST(p.EventDate AS DATE)) -1 ), CAST(p.EventDate AS DATE))
FROM SharedCare.GP_Events p
WHERE (
    FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'flu-vaccination' AND Version = 1) OR
    FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'flu-vaccination' AND Version = 1)
  )
  AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Cohort)
  AND EventDate <= @EndDate