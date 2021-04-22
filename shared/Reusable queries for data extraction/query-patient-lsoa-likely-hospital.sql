--┌───────────────────────────────┐
--│ Likely hospital for each LSOA │
--└───────────────────────────────┘

-- OBJECTIVE: For each LSOA to get the hospital that most residents would visit.

-- INPUT: No pre-requisites

-- OUTPUT: A temp table as follows:
-- #LikelyLSOAHospital (LSOA, LikelyLSOAHospital)
--	- LSOA - nationally recognised LSOA identifier
-- 	- LikelyLSOAHospital - name of most likely hospital for this LSOA

-- ASSUMPTIONS:
--	- We count the number of hospital admissions per LSOA
--	-	If there is a single hospital with the most admissions then we assign that as the most likely hospital
--	-	If there are 2 or more that tie for the most admissions then we classify that LSOA as 'Unknown'

-- Get the patient id and tenancy id of all hospital admission
IF OBJECT_ID('tempdb..#AdmissionPatients') IS NOT NULL DROP TABLE #AdmissionPatients;
SELECT DISTINCT FK_Patient_Link_ID, FK_Reference_Tenancy_ID INTO #AdmissionPatients FROM RLS.vw_Acute_Inpatients;

-- Get all patients LSOA for the cohort
IF OBJECT_ID('tempdb..#AllAdmissionPatientLSOAs') IS NOT NULL DROP TABLE #AllAdmissionPatientLSOAs;
SELECT 
	FK_Patient_Link_ID,
	FK_Reference_Tenancy_ID,
	HDMModifDate,
	LSOA_Code
INTO #AllAdmissionPatientLSOAs
FROM RLS.vw_Patient p
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #AdmissionPatients)
AND LSOA_Code IS NOT NULL;

-- If patients have a tenancy id of 2 we take this as their most likely LSOA_Code
-- as this is the GP data feed and so most likely to be up to date
IF OBJECT_ID('tempdb..#PatientAdmissionLSOA') IS NOT NULL DROP TABLE #PatientAdmissionLSOA;
SELECT FK_Patient_Link_ID, MIN(LSOA_Code) as LSOA_Code INTO #PatientAdmissionLSOA FROM #AllAdmissionPatientLSOAs
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #AdmissionPatients)
AND FK_Reference_Tenancy_ID = 2
GROUP BY FK_Patient_Link_ID;

-- Find the patients who remain unmatched
IF OBJECT_ID('tempdb..#UnmatchedAdmissionLsoaPatients') IS NOT NULL DROP TABLE #UnmatchedAdmissionLsoaPatients;
SELECT FK_Patient_Link_ID INTO #UnmatchedAdmissionLsoaPatients FROM #AdmissionPatients
EXCEPT
SELECT FK_Patient_Link_ID FROM #PatientAdmissionLSOA;
-- 38710 rows
-- 00:00:00

-- If every LSOA_Code is the same for all their linked patient ids then we use that
INSERT INTO #PatientAdmissionLSOA
SELECT FK_Patient_Link_ID, MIN(LSOA_Code) FROM #AllAdmissionPatientLSOAs
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #UnmatchedAdmissionLsoaPatients)
GROUP BY FK_Patient_Link_ID
HAVING MIN(LSOA_Code) = MAX(LSOA_Code);

-- Find any still unmatched patients
TRUNCATE TABLE #UnmatchedAdmissionLsoaPatients;
INSERT INTO #UnmatchedAdmissionLsoaPatients
SELECT FK_Patient_Link_ID FROM #AdmissionPatients
EXCEPT
SELECT FK_Patient_Link_ID FROM #PatientAdmissionLSOA;

-- If there is a unique most recent lsoa then use that
INSERT INTO #PatientAdmissionLSOA
SELECT p.FK_Patient_Link_ID, MIN(p.LSOA_Code) FROM #AllAdmissionPatientLSOAs p
INNER JOIN (
	SELECT FK_Patient_Link_ID, MAX(HDMModifDate) MostRecentDate FROM #AllAdmissionPatientLSOAs
	WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #UnmatchedAdmissionLsoaPatients)
	GROUP BY FK_Patient_Link_ID
) sub ON sub.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND sub.MostRecentDate = p.HDMModifDate
GROUP BY p.FK_Patient_Link_ID
HAVING MIN(LSOA_Code) = MAX(LSOA_Code);

IF OBJECT_ID('tempdb..#LSOATenancyCounts') IS NOT NULL DROP TABLE #LSOATenancyCounts;
SELECT LSOA_Code, FK_Reference_Tenancy_ID, COUNT(*) AS Frequency
INTO #LSOATenancyCounts
FROM #PatientAdmissionLSOA pl
INNER JOIN #AdmissionPatients p ON p.FK_Patient_Link_ID = pl.FK_Patient_Link_ID
GROUP BY LSOA_Code,FK_Reference_Tenancy_ID;

IF OBJECT_ID('tempdb..#LikelyLSOAHospital') IS NOT NULL DROP TABLE #LikelyLSOAHospital;
SELECT a.LSOA_Code AS LSOA,CASE WHEN MIN(TenancyName) = MAX(TenancyName) THEN MAX(TenancyName) ELSE 'Unknown' END AS LikelyLSOAHospital
INTO #LikelyLSOAHospital
FROM #LSOATenancyCounts a
INNER JOIN (
	SELECT LSOA_Code, MAX(Frequency) AS MaxFrequency FROM #LSOATenancyCounts
	GROUP BY LSOA_Code
) b on b.LSOA_Code = a.LSOA_Code and a.Frequency = b.MaxFrequency
INNER JOIN SharedCare.Reference_Tenancy t on t.PK_Reference_Tenancy_ID = FK_Reference_Tenancy_ID
GROUP BY a.LSOA_Code


