--┌──────────────────────────────────┐
--│ First prescriptions from GP data │
--└──────────────────────────────────┘

-- OBJECTIVE: To obtain, for each patient, the first date for each medication they have ever
--						been prescribed.

-- ASSUMPTIONS:
--	-	The same medication can have multiple clinical codes. GraphNet attempt to standardize
--		the coding across different providers by giving each code an id. Therefore the Readv2
--		code for a medication and the EMIS code for the same medication will have the same id.
--	-	

-- INPUT: No pre-requisites

-- OUTPUT: A temp table as follows:
-- #FirstMedications (FK_Patient_Link_ID, FirstMedDate, Code)
-- 	- FK_Patient_Link_ID - unique patient id
--	- FirstMedDate - first date for this medication (YYYY-MM-DD)
--	- Code - The medication code as either:
--					 "FNNNNNN" where 'NNNNNN' is a FK_Reference_Coding_ID or 
--					 "SNNNNNN" where 'NNNNNN' is a FK_Reference_SnomedCT_ID

-- Finds the first medication dates for each person. That is the dates on which each
-- new medication was first given to a patient. We rely on the first occurrence of
-- either the FK_Reference_Coding_ID or the FK_Reference_SnomedCT_ID instead of the
-- SuppliedCode field. Partly for performance reasons as grouping the entire table
-- on the VARCHAR field SuppliedCode takes several hours, but mainly because a person
-- receiving the same drug sometimes with the Read code and sometimes with the EMIS
-- code would appear as having two drugs prescribed. This is mitigated to some degree
-- by using the FK...IDs where the same drug with multiple clinical codes would only
-- appear once in the lookup tables.
IF OBJECT_ID('tempdb..#FirstMedications') IS NOT NULL DROP TABLE #FirstMedications;
SELECT 
	FK_Patient_Link_ID, 
	MIN(CONVERT(DATE, MedicationDate)) AS FirstMedDate,
	CASE
		WHEN FK_Reference_Coding_ID != -1 THEN 'F'+CONVERT(VARCHAR,FK_Reference_Coding_ID)
		ELSE 'S'+CONVERT(VARCHAR,FK_Reference_SnomedCT_ID)
	END AS Code
INTO #FirstMedications
FROM RLS.vw_GP_Medications
WHERE (FK_Reference_Coding_ID != -1 OR FK_Reference_SnomedCT_ID != -1)
GROUP BY 
	FK_Patient_Link_ID, 
	CASE
		WHEN FK_Reference_Coding_ID != -1 THEN 'F'+CONVERT(VARCHAR,FK_Reference_Coding_ID)
		ELSE 'S'+CONVERT(VARCHAR,FK_Reference_SnomedCT_ID)
	END
HAVING MIN(CONVERT(DATE, MedicationDate)) >= @StartDate;
-- 3681476
-- 00:08:58