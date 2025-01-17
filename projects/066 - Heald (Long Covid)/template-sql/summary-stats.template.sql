--┌─────────────────────────┐
--│ Summary stats for RQ066 │
--└─────────────────────────┘

-- OUTPUT: A tabular form of totals for the whole GM population to act as
--         a denominator for the study. This includes the total population,
--         broken down by age, ethnicity, townsend quintile and sex

--Just want the output, not the messages
SET NOCOUNT ON;

-- Table of all patients with a GP record
IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT DISTINCT FK_Patient_Link_ID
INTO #Patients
FROM SharedCare.Patient
WHERE FK_Reference_Tenancy_ID=2
AND GPPracticeCode NOT LIKE 'ZZZ%';
-- 21s

--> EXECUTE query-patients-with-covid.sql start-date:2020-01-01 all-patients:false gp-events-table:SharedCare.GP_Events
-- 1m38
--> EXECUTE query-patient-year-of-birth.sql
-- 26s
--> EXECUTE query-patient-sex.sql
-- 26s
--> EXECUTE query-patient-lsoa.sql
-- 25s
--> EXECUTE query-patient-townsend.sql
-- 8s

-- Whole population with COVID
IF OBJECT_ID('tempdb..#C19PopulationAll') IS NOT NULL DROP TABLE #C19PopulationAll;
SELECT
  'C19  Whole population' AS Descriptor,
  COUNT(*) AS Total,
  SUM(CASE WHEN sex.Sex = 'M' THEN 1 ELSE 0 END) As MaleTotal,
  SUM(CASE WHEN sex.Sex = 'F' THEN 1 ELSE 0 END) As FemaleTotal
INTO #C19PopulationAll
FROM #Patients pat
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN SharedCare.Patient_Link pl ON pl.PK_Patient_Link_ID = pat.FK_Patient_Link_ID
INNER JOIN #CovidPatientsMultipleDiagnoses c ON c.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
WHERE DeathDate IS NULL;

-- 10 year age bands with COVID
IF OBJECT_ID('tempdb..#C19PopulationAgeBands') IS NOT NULL DROP TABLE #C19PopulationAgeBands;
SELECT 
	CASE
		WHEN 2024 - yob.YearOfBirth <= 10 THEN 'C19 Age: 0-10'
		WHEN 2024 - yob.YearOfBirth <= 20 THEN 'C19 Age: 11-20'
		WHEN 2024 - yob.YearOfBirth <= 30 THEN 'C19 Age: 21-30'
		WHEN 2024 - yob.YearOfBirth <= 40 THEN 'C19 Age: 31-40'
		WHEN 2024 - yob.YearOfBirth <= 50 THEN 'C19 Age: 41-50'
		WHEN 2024 - yob.YearOfBirth <= 60 THEN 'C19 Age: 51-60'
		WHEN 2024 - yob.YearOfBirth <= 70 THEN 'C19 Age: 61-70'
		WHEN 2024 - yob.YearOfBirth <= 80 THEN 'C19 Age: 71-80'
		WHEN 2024 - yob.YearOfBirth <= 90 THEN 'C19 Age: 81-90'
		ELSE 'C19 Age: 90+'
	END AS Descriptor,
  COUNT(*) As Total,
  SUM(CASE WHEN sex.Sex = 'M' THEN 1 ELSE 0 END) As MaleTotal,
  SUM(CASE WHEN sex.Sex = 'F' THEN 1 ELSE 0 END) As FemaleTotal
INTO #C19PopulationAgeBands
FROM #Patients pat
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN SharedCare.Patient_Link pl ON pl.PK_Patient_Link_ID = pat.FK_Patient_Link_ID
INNER JOIN #CovidPatientsMultipleDiagnoses c ON c.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
WHERE DeathDate IS NULL
GROUP BY CASE
	WHEN 2024 - yob.YearOfBirth <= 10 THEN 'C19 Age: 0-10'
	WHEN 2024 - yob.YearOfBirth <= 20 THEN 'C19 Age: 11-20'
	WHEN 2024 - yob.YearOfBirth <= 30 THEN 'C19 Age: 21-30'
	WHEN 2024 - yob.YearOfBirth <= 40 THEN 'C19 Age: 31-40'
	WHEN 2024 - yob.YearOfBirth <= 50 THEN 'C19 Age: 41-50'
	WHEN 2024 - yob.YearOfBirth <= 60 THEN 'C19 Age: 51-60'
	WHEN 2024 - yob.YearOfBirth <= 70 THEN 'C19 Age: 61-70'
	WHEN 2024 - yob.YearOfBirth <= 80 THEN 'C19 Age: 71-80'
	WHEN 2024 - yob.YearOfBirth <= 90 THEN 'C19 Age: 81-90'
	ELSE 'C19 Age: 90+'
END
ORDER BY Descriptor;

-- Split by ethnicity with COVID
IF OBJECT_ID('tempdb..#C19PopulationEthnicity') IS NOT NULL DROP TABLE #C19PopulationEthnicity;
SELECT
  CONCAT('C19 Ethnicity: ',  ISNULL(EthnicMainGroup, 'zNULL')) AS Descriptor,
  COUNT(*) As Total,  
  SUM(CASE WHEN sex.Sex = 'M' THEN 1 ELSE 0 END) As MaleTotal,
  SUM(CASE WHEN sex.Sex = 'F' THEN 1 ELSE 0 END) As FemaleTotal
INTO #C19PopulationEthnicity
FROM #Patients pat
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN SharedCare.Patient_Link pl ON pl.PK_Patient_Link_ID = pat.FK_Patient_Link_ID
INNER JOIN #CovidPatientsMultipleDiagnoses c ON c.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
WHERE DeathDate IS NULL
GROUP BY EthnicMainGroup
ORDER BY EthnicMainGroup;

-- Split by townsend quintile with COVID
IF OBJECT_ID('tempdb..#C19PopulationTownsend') IS NOT NULL DROP TABLE #C19PopulationTownsend;
SELECT
  CONCAT('C19 Townsend: ',  ISNULL(TRY_CAST(TownsendQuintileHigherIsMoreDeprived as varchar), 'NULL')) AS Descriptor,
  COUNT(*) As Total,  
  SUM(CASE WHEN sex.Sex = 'M' THEN 1 ELSE 0 END) As MaleTotal,
  SUM(CASE WHEN sex.Sex = 'F' THEN 1 ELSE 0 END) As FemaleTotal
INTO #C19PopulationTownsend
FROM #Patients pat
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientTownsend town ON town.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN SharedCare.Patient_Link pl ON pl.PK_Patient_Link_ID = pat.FK_Patient_Link_ID
INNER JOIN #CovidPatientsMultipleDiagnoses c ON c.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
WHERE DeathDate IS NULL
GROUP BY TownsendQuintileHigherIsMoreDeprived;

-- Whole population
IF OBJECT_ID('tempdb..#PopulationAll') IS NOT NULL DROP TABLE #PopulationAll;
SELECT
  ' Whole population' AS Descriptor,
  COUNT(*) AS Total,
  SUM(CASE WHEN sex.Sex = 'M' THEN 1 ELSE 0 END) As MaleTotal,
  SUM(CASE WHEN sex.Sex = 'F' THEN 1 ELSE 0 END) As FemaleTotal
INTO #PopulationAll
FROM #Patients pat
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN SharedCare.Patient_Link pl ON pl.PK_Patient_Link_ID = pat.FK_Patient_Link_ID
WHERE DeathDate IS NULL;

-- 10 year age bands
IF OBJECT_ID('tempdb..#PopulationAgeBands') IS NOT NULL DROP TABLE #PopulationAgeBands;
SELECT 
	CASE
		WHEN 2024 - yob.YearOfBirth <= 10 THEN 'Age: 0-10'
		WHEN 2024 - yob.YearOfBirth <= 20 THEN 'Age: 11-20'
		WHEN 2024 - yob.YearOfBirth <= 30 THEN 'Age: 21-30'
		WHEN 2024 - yob.YearOfBirth <= 40 THEN 'Age: 31-40'
		WHEN 2024 - yob.YearOfBirth <= 50 THEN 'Age: 41-50'
		WHEN 2024 - yob.YearOfBirth <= 60 THEN 'Age: 51-60'
		WHEN 2024 - yob.YearOfBirth <= 70 THEN 'Age: 61-70'
		WHEN 2024 - yob.YearOfBirth <= 80 THEN 'Age: 71-80'
		WHEN 2024 - yob.YearOfBirth <= 90 THEN 'Age: 81-90'
		ELSE 'Age: 90+'
	END AS Descriptor,
  COUNT(*) As Total,
  SUM(CASE WHEN sex.Sex = 'M' THEN 1 ELSE 0 END) As MaleTotal,
  SUM(CASE WHEN sex.Sex = 'F' THEN 1 ELSE 0 END) As FemaleTotal
INTO #PopulationAgeBands
FROM #Patients pat
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN SharedCare.Patient_Link pl ON pl.PK_Patient_Link_ID = pat.FK_Patient_Link_ID
WHERE DeathDate IS NULL
GROUP BY CASE
	WHEN 2024 - yob.YearOfBirth <= 10 THEN 'Age: 0-10'
	WHEN 2024 - yob.YearOfBirth <= 20 THEN 'Age: 11-20'
	WHEN 2024 - yob.YearOfBirth <= 30 THEN 'Age: 21-30'
	WHEN 2024 - yob.YearOfBirth <= 40 THEN 'Age: 31-40'
	WHEN 2024 - yob.YearOfBirth <= 50 THEN 'Age: 41-50'
	WHEN 2024 - yob.YearOfBirth <= 60 THEN 'Age: 51-60'
	WHEN 2024 - yob.YearOfBirth <= 70 THEN 'Age: 61-70'
	WHEN 2024 - yob.YearOfBirth <= 80 THEN 'Age: 71-80'
	WHEN 2024 - yob.YearOfBirth <= 90 THEN 'Age: 81-90'
	ELSE 'Age: 90+'
END
ORDER BY Descriptor;

-- Split by ethnicity
IF OBJECT_ID('tempdb..#PopulationEthnicity') IS NOT NULL DROP TABLE #PopulationEthnicity;
SELECT
  CONCAT('Ethnicity: ',  ISNULL(EthnicMainGroup, 'zNULL')) AS Descriptor,
  COUNT(*) As Total,  
  SUM(CASE WHEN sex.Sex = 'M' THEN 1 ELSE 0 END) As MaleTotal,
  SUM(CASE WHEN sex.Sex = 'F' THEN 1 ELSE 0 END) As FemaleTotal
INTO #PopulationEthnicity
FROM #Patients pat
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN SharedCare.Patient_Link pl ON pl.PK_Patient_Link_ID = pat.FK_Patient_Link_ID
WHERE DeathDate IS NULL
GROUP BY EthnicMainGroup
ORDER BY EthnicMainGroup;

-- Split by townsend quintile
IF OBJECT_ID('tempdb..#PopulationTownsend') IS NOT NULL DROP TABLE #PopulationTownsend;
SELECT
  CONCAT('Townsend: ',  ISNULL(TRY_CAST(TownsendQuintileHigherIsMoreDeprived as varchar), 'NULL')) AS Descriptor,
  COUNT(*) As Total,  
  SUM(CASE WHEN sex.Sex = 'M' THEN 1 ELSE 0 END) As MaleTotal,
  SUM(CASE WHEN sex.Sex = 'F' THEN 1 ELSE 0 END) As FemaleTotal
INTO #PopulationTownsend
FROM #Patients pat
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientTownsend town ON town.FK_Patient_Link_ID = pat.FK_Patient_Link_ID
LEFT OUTER JOIN SharedCare.Patient_Link pl ON pl.PK_Patient_Link_ID = pat.FK_Patient_Link_ID
WHERE DeathDate IS NULL
GROUP BY TownsendQuintileHigherIsMoreDeprived;

SELECT * FROM #PopulationAll
UNION
SELECT * FROM #PopulationAgeBands
UNION
SELECT * FROM #PopulationEthnicity
UNION
SELECT * FROM #PopulationTownsend
UNION
SELECT * FROM #C19PopulationAll
UNION
SELECT * FROM #C19PopulationAgeBands
UNION
SELECT * FROM #C19PopulationEthnicity
UNION
SELECT * FROM #C19PopulationTownsend
ORDER BY Descriptor;