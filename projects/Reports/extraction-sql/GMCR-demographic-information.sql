--┌───────────────────┐
--│ GMCR demographics │
--└───────────────────┘

-- OBJECTIVE: Attempts to provide a demographic breakdown of all patients
--						in the GMCR. This is useful for papers that require summary
--						data about their patient population. This provides the demographics
--						for the population of living patients registered with a GM GP.
--						This might not be suitable for all papers.

-- INPUT: No pre-requisites

-- OUTPUT: Two tables (one for events and one for medications) with the following fields
-- 	- Concept - the clinical concept e.g. the diagnosis, medication, procedure...
--  - Version - the version of the clinical concept
--  - System  - the clinical system (EMIS/Vision/TPP)
--  - PatientsWithConcept  - the number of patients with a clinical code for this concept in their record
--  - Patients  - the number of patients for this system supplier
--  - PercentageOfPatients  - the percentage of patients for this system supplier with this concept

--Just want the output, not the messages
SET NOCOUNT ON;

--┌──────────────────────────────┐
--│ Practice system lookup table │
--└──────────────────────────────┘

-- OBJECTIVE: To provide lookup table for GP systems. The GMCR doesn't hold this information
--            in the data so here is a lookup. This was accurate on 27th Jan 2021 and will
--            likely drift out of date slowly as practices change systems. Though this doesn't 
--            happen very often.

-- INPUT: No pre-requisites

-- OUTPUT: A temp table as follows:
-- #PracticeSystemLookup (PracticeId, System)
-- 	- PracticeId - Nationally recognised practice id
--	- System - EMIS, TPP, VISION

IF OBJECT_ID('tempdb..#PracticeSystemLookup') IS NOT NULL DROP TABLE #PracticeSystemLookup;
CREATE TABLE #PracticeSystemLookup (PracticeId nchar(6), System nvarchar(20));
INSERT INTO #PracticeSystemLookup VALUES
('P82001', 'EMIS'),('P82002', 'TPP'),('P82003', 'TPP'),('P82004', 'TPP'),('P82005', 'TPP'),('P82006', 'EMIS'),('P82007', 'TPP'),('P82008', 'TPP'),('P82009', 'EMIS'),('P82010', 'EMIS'),('P82011', 'EMIS'),('P82012', 'EMIS'),('P82013', 'EMIS'),('P82014', 'TPP'),('P82015', 'EMIS'),('P82016', 'EMIS'),('P82018', 'EMIS'),('P82020', 'EMIS'),('P82021', 'EMIS'),('P82022', 'EMIS'),('P82023', 'Vision'),('P82025', 'TPP'),('P82029', 'EMIS'),('P82030', 'EMIS'),('P82031', 'EMIS'),('P82033', 'EMIS'),('P82034', 'EMIS'),('P82036', 'EMIS'),('P82037', 'EMIS'),('P82607', 'EMIS'),('P82609', 'EMIS'),('P82613', 'EMIS'),('P82616', 'EMIS'),('P82624', 'Vision'),('P82625', 'EMIS'),('P82626', 'EMIS'),('P82627', 'EMIS'),('P82629', 'Vision'),('P82633', 'EMIS'),('P82634', 'TPP'),('P82640', 'EMIS'),('P82643', 'EMIS'),('P82652', 'EMIS'),('P82660', 'Vision'),('Y00186', 'EMIS'),('Y02319', 'EMIS'),('Y02790', 'EMIS'),('Y03079', 'EMIS'),('Y03366', 'TPP'),('P83001', 'Vision'),('P83004', 'Vision'),('P83005', 'Vision'),('P83006', 'Vision'),('P83007', 'Vision'),('P83009', 'Vision'),('P83010', 'Vision'),('P83011', 'Vision'),('P83012', 'Vision'),('P83015', 'Vision'),('P83017', 'Vision'),('P83020', 'Vision'),('P83021', 'Vision'),('P83024', 'Vision'),('P83025', 'Vision'),('P83027', 'Vision'),('P83603', 'Vision'),('P83605', 'Vision'),('P83608', 'Vision'),('P83609', 'Vision'),('P83611', 'Vision'),('P83612', 'Vision'),('P83620', 'Vision'),('P83621', 'Vision'),('P83623', 'Vision'),('Y02755', 'Vision'),('P86001', 'EMIS'),('P86002', 'EMIS'),('P86003', 'EMIS'),('P86004', 'EMIS'),('P86005', 'EMIS'),('P86006', 'EMIS'),('P86007', 'EMIS'),('P86008', 'EMIS'),('P86009', 'EMIS'),('P86010', 'EMIS'),('P86011', 'EMIS'),('P86012', 'EMIS'),('P86013', 'EMIS'),('P86014', 'EMIS'),('P86015', 'EMIS'),('P86016', 'EMIS'),('P86017', 'EMIS'),('P86018', 'EMIS'),('P86019', 'EMIS'),('P86021', 'EMIS'),('P86022', 'EMIS'),('P86023', 'EMIS'),('P86026', 'EMIS'),('P86602', 'EMIS'),('P86606', 'EMIS'),('P86608', 'EMIS'),('P86609', 'EMIS'),('P86614', 'EMIS'),('P86619', 'EMIS'),('P86620', 'EMIS'),('P86624', 'EMIS'),('Y00726', 'EMIS'),('Y02718', 'EMIS'),('Y02720', 'EMIS'),('Y02721', 'EMIS'),('Y02795', 'EMIS'),('P84004', 'EMIS'),('P84005', 'EMIS'),('P84009', 'EMIS'),('P84010', 'EMIS'),('P84012', 'EMIS'),('P84014', 'EMIS'),('P84016', 'EMIS'),('P84017', 'EMIS'),('P84018', 'EMIS'),('P84019', 'EMIS'),('P84020', 'EMIS'),('P84021', 'EMIS'),('P84022', 'EMIS'),('P84023', 'EMIS'),('P84024', 'EMIS'),('P84025', 'EMIS'),('P84026', 'EMIS'),('P84027', 'EMIS'),('P84028', 'EMIS'),('P84029', 'EMIS'),('P84030', 'EMIS'),('P84032', 'EMIS'),('P84033', 'EMIS'),('P84034', 'EMIS'),('P84035', 'EMIS'),('P84037', 'EMIS'),('P84038', 'EMIS'),('P84039', 'EMIS'),('P84040', 'EMIS'),('P84041', 'EMIS'),('P84042', 'EMIS'),('P84043', 'EMIS'),('P84045', 'EMIS'),('P84046', 'EMIS'),('P84047', 'EMIS'),('P84048', 'EMIS'),('P84049', 'EMIS'),('P84050', 'EMIS'),('P84051', 'EMIS'),('P84052', 'EMIS'),('P84053', 'EMIS'),('P84054', 'EMIS'),('P84056', 'EMIS'),('P84059', 'EMIS'),('P84061', 'EMIS'),('P84064', 'EMIS'),('P84065', 'EMIS'),('P84066', 'EMIS'),('P84067', 'EMIS'),('P84068', 'EMIS'),('P84070', 'EMIS'),('P84071', 'EMIS'),('P84072', 'EMIS'),('P84074', 'EMIS'),('P84605', 'EMIS'),('P84611', 'EMIS'),('P84616', 'EMIS'),('P84626', 'EMIS'),('P84630', 'EMIS'),('P84635', 'EMIS'),('P84637', 'EMIS'),('P84639', 'EMIS'),('P84640', 'EMIS'),('P84644', 'EMIS'),('P84645', 'EMIS'),('P84650', 'EMIS'),('P84651', 'EMIS'),('P84652', 'EMIS'),('P84663', 'EMIS'),('P84665', 'EMIS'),('P84669', 'EMIS'),('P84672', 'EMIS'),('P84673', 'EMIS'),('P84678', 'EMIS'),('P84679', 'EMIS'),('P84683', 'EMIS'),('P84684', 'EMIS'),('P84689', 'EMIS'),('P84690', 'EMIS'),('Y01695', 'EMIS'),('Y02325', 'EMIS'),('Y02520', 'EMIS'),('Y02849', 'EMIS'),('Y02890', 'EMIS'),('Y02960', 'EMIS'),('P85001', 'EMIS'),('P85002', 'EMIS'),('P85003', 'EMIS'),('P85004', 'EMIS'),('P85005', 'EMIS'),('P85007', 'EMIS'),('P85008', 'EMIS'),('P85010', 'EMIS'),('P85011', 'EMIS'),('P85012', 'EMIS'),('P85013', 'EMIS'),('P85014', 'EMIS'),('P85015', 'EMIS'),('P85016', 'EMIS'),('P85017', 'EMIS'),('P85018', 'EMIS'),('P85019', 'EMIS'),('P85020', 'EMIS'),('P85021', 'EMIS'),('P85022', 'EMIS'),('P85026', 'EMIS'),('P85028', 'EMIS'),('P85601', 'EMIS'),('P85602', 'EMIS'),('P85605', 'EMIS'),('P85606', 'EMIS'),('P85607', 'EMIS'),('P85608', 'EMIS'),('P85610', 'EMIS'),('P85612', 'EMIS'),('P85614', 'EMIS'),('P85615', 'EMIS'),('P85620', 'EMIS'),('P85621', 'EMIS'),('P85622', 'EMIS'),('P89006', 'EMIS'),('Y01124', 'EMIS'),('Y02753', 'EMIS'),('Y02827', 'EMIS'),('Y02875', 'EMIS'),('Y02933', 'EMIS'),('P87002', 'EMIS'),('P87003', 'Vision'),('P87004', 'Vision'),('P87008', 'EMIS'),('P87015', 'Vision'),('P87016', 'EMIS'),('P87017', 'EMIS'),('P87019', 'EMIS'),('P87020', 'Vision'),('P87022', 'Vision'),('P87024', 'EMIS'),('P87025', 'EMIS'),('P87026', 'EMIS'),('P87027', 'EMIS'),('P87028', 'EMIS'),('P87032', 'Vision'),('P87035', 'EMIS'),('P87039', 'Vision'),('P87040', 'Vision'),('P87610', 'Vision'),('P87613', 'EMIS'),('P87618', 'EMIS'),('P87620', 'Vision'),('P87624', 'EMIS'),('P87625', 'EMIS'),('P87627', 'EMIS'),('P87630', 'EMIS'),('P87634', 'EMIS'),('P87639', 'Vision'),('P87648', 'Vision'),('P87649', 'EMIS'),('P87651', 'Vision'),('P87654', 'EMIS'),('P87657', 'Vision'),('P87658', 'EMIS'),('P87659', 'Vision'),('P87661', 'EMIS'),('Y00445', 'Vision'),('Y02622', 'EMIS'),('Y02625', 'EMIS'),('Y02767', 'EMIS'),('P88002', 'EMIS'),('P88003', 'EMIS'),('P88005', 'EMIS'),('P88006', 'EMIS'),('P88007', 'EMIS'),('P88008', 'EMIS'),('P88009', 'EMIS'),('P88011', 'EMIS'),('P88012', 'EMIS'),('P88013', 'EMIS'),('P88014', 'EMIS'),('P88015', 'EMIS'),('P88016', 'EMIS'),('P88017', 'EMIS'),('P88018', 'EMIS'),('P88019', 'EMIS'),('P88020', 'EMIS'),('P88021', 'EMIS'),('P88023', 'EMIS'),('P88024', 'EMIS'),('P88025', 'EMIS'),('P88026', 'EMIS'),('P88031', 'EMIS'),('P88034', 'EMIS'),('P88041', 'EMIS'),('P88042', 'EMIS'),('P88043', 'EMIS'),('P88044', 'EMIS'),('P88606', 'EMIS'),('P88607', 'EMIS'),('P88610', 'EMIS'),('P88615', 'EMIS'),('P88623', 'EMIS'),('P88625', 'EMIS'),('P88632', 'EMIS'),('Y00912', 'EMIS'),('C81077', 'EMIS'),('C81081', 'EMIS'),('C81106', 'EMIS'),('C81615', 'EMIS'),('C81640', 'EMIS'),('C81660', 'EMIS'),('P89002', 'EMIS'),('P89003', 'EMIS'),('P89004', 'EMIS'),('P89005', 'EMIS'),('P89007', 'TPP'),('P89008', 'EMIS'),('P89010', 'EMIS'),('P89011', 'EMIS'),('P89012', 'EMIS'),('P89013', 'EMIS'),('P89014', 'EMIS'),('P89015', 'EMIS'),('P89016', 'EMIS'),('P89018', 'EMIS'),('P89020', 'EMIS'),('P89021', 'EMIS'),('P89022', 'EMIS'),('P89023', 'EMIS'),('P89025', 'EMIS'),('P89026', 'EMIS'),('P89029', 'EMIS'),('P89030', 'EMIS'),('P89602', 'EMIS'),('P89609', 'EMIS'),('P89612', 'EMIS'),('P89613', 'EMIS'),('P89618', 'EMIS'),('Y02586', 'EMIS'),('Y02663', 'EMIS'),('Y02713', 'EMIS'),('Y02936', 'EMIS'),('P91003', 'EMIS'),('P91004', 'EMIS'),('P91006', 'EMIS'),('P91007', 'EMIS'),('P91008', 'EMIS'),('P91009', 'EMIS'),('P91011', 'EMIS'),('P91012', 'EMIS'),('P91013', 'EMIS'),('P91014', 'EMIS'),('P91016', 'EMIS'),('P91017', 'EMIS'),('P91018', 'EMIS'),('P91019', 'EMIS'),('P91020', 'EMIS'),('P91021', 'EMIS'),('P91026', 'EMIS'),('P91029', 'EMIS'),('P91035', 'EMIS'),('P91603', 'EMIS'),('P91604', 'EMIS'),('P91617', 'EMIS'),('P91619', 'EMIS'),('P91623', 'EMIS'),('P91625', 'EMIS'),('P91627', 'EMIS'),('P91629', 'EMIS'),('P91631', 'EMIS'),('P91633', 'EMIS'),('P92001', 'TPP'),('P92002', 'EMIS'),('P92003', 'EMIS'),('P92004', 'EMIS'),('P92005', 'TPP'),('P92006', 'TPP'),('P92007', 'TPP'),('P92008', 'EMIS'),('P92010', 'TPP'),('P92011', 'EMIS'),('P92012', 'TPP'),('P92014', 'EMIS'),('P92015', 'EMIS'),('P92016', 'TPP'),('P92017', 'EMIS'),('P92019', 'EMIS'),('P92020', 'EMIS'),('P92021', 'EMIS'),('P92023', 'EMIS'),('P92024', 'TPP'),('P92026', 'EMIS'),('P92028', 'EMIS'),('P92029', 'TPP'),('P92030', 'Vision'),('P92031', 'TPP'),('P92033', 'EMIS'),('P92034', 'TPP'),('P92035', 'TPP'),('P92038', 'TPP'),('P92041', 'EMIS'),('P92042', 'EMIS'),('P92602', 'EMIS'),('P92605', 'EMIS'),('P92607', 'TPP'),('P92615', 'TPP'),('P92616', 'EMIS'),('P92620', 'EMIS'),('P92621', 'EMIS'),('P92623', 'TPP'),('P92626', 'EMIS'),('P92630', 'EMIS'),('P92633', 'EMIS'),('P92634', 'EMIS'),('P92635', 'Vision'),('P92637', 'EMIS'),('P92639', 'TPP'),('P92642', 'TPP'),('P92646', 'EMIS'),('P92647', 'TPP'),('P92648', 'TPP'),('P92651', 'EMIS'),('P92653', 'TPP'),('Y00050', 'TPP'),('Y02274', 'EMIS'),('Y02321', 'EMIS'),('Y02322', 'EMIS'),('Y02378', 'EMIS'),('Y02885', 'EMIS'),('Y02886', 'EMIS');


-- Every unique person in the GMCR database
IF OBJECT_ID('tempdb..#AllGMCRPatients') IS NOT NULL DROP TABLE #AllGMCRPatients;
SELECT PK_Patient_Link_ID AS FK_Patient_Link_ID INTO #AllGMCRPatients FROM RLS.vw_Patient_Link;
-- 5464180

-- Populate patient table to get other demographic info
IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT FK_Patient_Link_ID INTO #Patients FROM #AllGMCRPatients;

--┌────────────────────────────┐
--│ Index Multiple Deprivation │
--└────────────────────────────┘

-- OBJECTIVE: To get the 2019 Index of Multiple Deprivation (IMD) decile for each patient.

-- INPUT: Assumes there exists a temp table as follows:
-- #Patients (FK_Patient_Link_ID)
--  A distinct list of FK_Patient_Link_IDs for each patient in the cohort

-- OUTPUT: A temp table as follows:
-- #PatientIMDDecile (FK_Patient_Link_ID, IMD2019Decile1IsMostDeprived10IsLeastDeprived)
-- 	- FK_Patient_Link_ID - unique patient id
--	- IMD2019Decile1IsMostDeprived10IsLeastDeprived - number 1 to 10 inclusive

-- Get all patients IMD_Score (which is a rank) for the cohort and map to decile
-- (Data on mapping thresholds at: https://www.gov.uk/government/statistics/english-indices-of-deprivation-2019
IF OBJECT_ID('tempdb..#AllPatientIMDDeciles') IS NOT NULL DROP TABLE #AllPatientIMDDeciles;
SELECT 
	FK_Patient_Link_ID,
	FK_Reference_Tenancy_ID,
	HDMModifDate,
	CASE 
		WHEN IMD_Score <= 3284 THEN 1
		WHEN IMD_Score <= 6568 THEN 2
		WHEN IMD_Score <= 9853 THEN 3
		WHEN IMD_Score <= 13137 THEN 4
		WHEN IMD_Score <= 16422 THEN 5
		WHEN IMD_Score <= 19706 THEN 6
		WHEN IMD_Score <= 22990 THEN 7
		WHEN IMD_Score <= 26275 THEN 8
		WHEN IMD_Score <= 29559 THEN 9
		ELSE 10
	END AS IMD2019Decile1IsMostDeprived10IsLeastDeprived 
INTO #AllPatientIMDDeciles
FROM RLS.vw_Patient p
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND IMD_Score IS NOT NULL
AND IMD_Score != -1;
-- 972479 rows
-- 00:00:11

-- If patients have a tenancy id of 2 we take this as their most likely IMD_Score
-- as this is the GP data feed and so most likely to be up to date
IF OBJECT_ID('tempdb..#PatientIMDDecile') IS NOT NULL DROP TABLE #PatientIMDDecile;
SELECT FK_Patient_Link_ID, MIN(IMD2019Decile1IsMostDeprived10IsLeastDeprived) as IMD2019Decile1IsMostDeprived10IsLeastDeprived INTO #PatientIMDDecile FROM #AllPatientIMDDeciles
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND FK_Reference_Tenancy_ID = 2
GROUP BY FK_Patient_Link_ID;
-- 247377 rows
-- 00:00:00

-- Find the patients who remain unmatched
IF OBJECT_ID('tempdb..#UnmatchedImdPatients') IS NOT NULL DROP TABLE #UnmatchedImdPatients;
SELECT FK_Patient_Link_ID INTO #UnmatchedImdPatients FROM #Patients
EXCEPT
SELECT FK_Patient_Link_ID FROM #PatientIMDDecile;
-- 38710 rows
-- 00:00:00

-- If every IMD_Score is the same for all their linked patient ids then we use that
INSERT INTO #PatientIMDDecile
SELECT FK_Patient_Link_ID, MIN(IMD2019Decile1IsMostDeprived10IsLeastDeprived) FROM #AllPatientIMDDeciles
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #UnmatchedImdPatients)
GROUP BY FK_Patient_Link_ID
HAVING MIN(IMD2019Decile1IsMostDeprived10IsLeastDeprived) = MAX(IMD2019Decile1IsMostDeprived10IsLeastDeprived);
-- 36656
-- 00:00:00

-- Find any still unmatched patients
TRUNCATE TABLE #UnmatchedImdPatients;
INSERT INTO #UnmatchedImdPatients
SELECT FK_Patient_Link_ID FROM #Patients
EXCEPT
SELECT FK_Patient_Link_ID FROM #PatientIMDDecile;
-- 2054 rows
-- 00:00:00

-- If there is a unique most recent imd decile then use that
INSERT INTO #PatientIMDDecile
SELECT p.FK_Patient_Link_ID, MIN(p.IMD2019Decile1IsMostDeprived10IsLeastDeprived) FROM #AllPatientIMDDeciles p
INNER JOIN (
	SELECT FK_Patient_Link_ID, MAX(HDMModifDate) MostRecentDate FROM #AllPatientIMDDeciles
	WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #UnmatchedImdPatients)
	GROUP BY FK_Patient_Link_ID
) sub ON sub.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND sub.MostRecentDate = p.HDMModifDate
GROUP BY p.FK_Patient_Link_ID
HAVING MIN(IMD2019Decile1IsMostDeprived10IsLeastDeprived) = MAX(IMD2019Decile1IsMostDeprived10IsLeastDeprived);
-- 489
-- 00:00:00
--┌───────────────────────────────┐
--│ Lower level super output area │
--└───────────────────────────────┘

-- OBJECTIVE: To get the LSOA for each patient.

-- INPUT: Assumes there exists a temp table as follows:
-- #Patients (FK_Patient_Link_ID)
--  A distinct list of FK_Patient_Link_IDs for each patient in the cohort

-- OUTPUT: A temp table as follows:
-- #PatientLSOA (FK_Patient_Link_ID, LSOA)
-- 	- FK_Patient_Link_ID - unique patient id
--	- LSOA - nationally recognised LSOA identifier

-- ASSUMPTIONS:
--	- Patient data is obtained from multiple sources. Where patients have multiple LSOAs we determine the LSOA as follows:
--	-	If the patients has an LSOA in their primary care data feed we use that as most likely to be up to date
--	-	If every LSOA for a paitent is the same, then we use that
--	-	If there is a single most recently updated LSOA in the database then we use that
--	-	Otherwise the patient's LSOA is considered unknown

-- Get all patients LSOA for the cohort
IF OBJECT_ID('tempdb..#AllPatientLSOAs') IS NOT NULL DROP TABLE #AllPatientLSOAs;
SELECT 
	FK_Patient_Link_ID,
	FK_Reference_Tenancy_ID,
	HDMModifDate,
	LSOA_Code
INTO #AllPatientLSOAs
FROM RLS.vw_Patient p
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND LSOA_Code IS NOT NULL;


-- If patients have a tenancy id of 2 we take this as their most likely LSOA_Code
-- as this is the GP data feed and so most likely to be up to date
IF OBJECT_ID('tempdb..#PatientLSOA') IS NOT NULL DROP TABLE #PatientLSOA;
SELECT FK_Patient_Link_ID, MIN(LSOA_Code) as LSOA_Code INTO #PatientLSOA FROM #AllPatientLSOAs
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND FK_Reference_Tenancy_ID = 2
GROUP BY FK_Patient_Link_ID;

-- Find the patients who remain unmatched
IF OBJECT_ID('tempdb..#UnmatchedLsoaPatients') IS NOT NULL DROP TABLE #UnmatchedLsoaPatients;
SELECT FK_Patient_Link_ID INTO #UnmatchedLsoaPatients FROM #Patients
EXCEPT
SELECT FK_Patient_Link_ID FROM #PatientLSOA;
-- 38710 rows
-- 00:00:00

-- If every LSOA_Code is the same for all their linked patient ids then we use that
INSERT INTO #PatientLSOA
SELECT FK_Patient_Link_ID, MIN(LSOA_Code) FROM #AllPatientLSOAs
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #UnmatchedLsoaPatients)
GROUP BY FK_Patient_Link_ID
HAVING MIN(LSOA_Code) = MAX(LSOA_Code);

-- Find any still unmatched patients
TRUNCATE TABLE #UnmatchedLsoaPatients;
INSERT INTO #UnmatchedLsoaPatients
SELECT FK_Patient_Link_ID FROM #Patients
EXCEPT
SELECT FK_Patient_Link_ID FROM #PatientLSOA;

-- If there is a unique most recent lsoa then use that
INSERT INTO #PatientLSOA
SELECT p.FK_Patient_Link_ID, MIN(p.LSOA_Code) FROM #AllPatientLSOAs p
INNER JOIN (
	SELECT FK_Patient_Link_ID, MAX(HDMModifDate) MostRecentDate FROM #AllPatientLSOAs
	WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #UnmatchedLsoaPatients)
	GROUP BY FK_Patient_Link_ID
) sub ON sub.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND sub.MostRecentDate = p.HDMModifDate
GROUP BY p.FK_Patient_Link_ID
HAVING MIN(LSOA_Code) = MAX(LSOA_Code);

--┌─────┐
--│ Sex │
--└─────┘

-- OBJECTIVE: To get the Sex for each patient.

-- INPUT: Assumes there exists a temp table as follows:
-- #Patients (FK_Patient_Link_ID)
--  A distinct list of FK_Patient_Link_IDs for each patient in the cohort

-- OUTPUT: A temp table as follows:
-- #PatientSex (FK_Patient_Link_ID, Sex)
-- 	- FK_Patient_Link_ID - unique patient id
--	- Sex - M/F

-- ASSUMPTIONS:
--	- Patient data is obtained from multiple sources. Where patients have multiple sexes we determine the sex as follows:
--	-	If the patients has a sex in their primary care data feed we use that as most likely to be up to date
--	-	If every sex for a patient is the same, then we use that
--	-	If there is a single most recently updated sex in the database then we use that
--	-	Otherwise the patient's sex is considered unknown

-- Get all patients sex for the cohort
IF OBJECT_ID('tempdb..#AllPatientSexs') IS NOT NULL DROP TABLE #AllPatientSexs;
SELECT 
	FK_Patient_Link_ID,
	FK_Reference_Tenancy_ID,
	HDMModifDate,
	Sex
INTO #AllPatientSexs
FROM RLS.vw_Patient p
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND Sex IS NOT NULL;


-- If patients have a tenancy id of 2 we take this as their most likely Sex
-- as this is the GP data feed and so most likely to be up to date
IF OBJECT_ID('tempdb..#PatientSex') IS NOT NULL DROP TABLE #PatientSex;
SELECT FK_Patient_Link_ID, MIN(Sex) as Sex INTO #PatientSex FROM #AllPatientSexs
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND FK_Reference_Tenancy_ID = 2
GROUP BY FK_Patient_Link_ID;

-- Find the patients who remain unmatched
IF OBJECT_ID('tempdb..#UnmatchedSexPatients') IS NOT NULL DROP TABLE #UnmatchedSexPatients;
SELECT FK_Patient_Link_ID INTO #UnmatchedSexPatients FROM #Patients
EXCEPT
SELECT FK_Patient_Link_ID FROM #PatientSex;

-- If every Sex is the same for all their linked patient ids then we use that
INSERT INTO #PatientSex
SELECT FK_Patient_Link_ID, MIN(Sex) FROM #AllPatientSexs
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #UnmatchedSexPatients)
GROUP BY FK_Patient_Link_ID
HAVING MIN(Sex) = MAX(Sex);

-- Find any still unmatched patients
TRUNCATE TABLE #UnmatchedSexPatients;
INSERT INTO #UnmatchedSexPatients
SELECT FK_Patient_Link_ID FROM #Patients
EXCEPT
SELECT FK_Patient_Link_ID FROM #PatientSex;

-- If there is a unique most recent Sex then use that
INSERT INTO #PatientSex
SELECT p.FK_Patient_Link_ID, MIN(p.Sex) FROM #AllPatientSexs p
INNER JOIN (
	SELECT FK_Patient_Link_ID, MAX(HDMModifDate) MostRecentDate FROM #AllPatientSexs
	WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #UnmatchedSexPatients)
	GROUP BY FK_Patient_Link_ID
) sub ON sub.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND sub.MostRecentDate = p.HDMModifDate
GROUP BY p.FK_Patient_Link_ID
HAVING MIN(Sex) = MAX(Sex);

--┌───────────────┐
--│ Year of birth │
--└───────────────┘

-- OBJECTIVE: To get the year of birth for each patient.

-- INPUT: Assumes there exists a temp table as follows:
-- #Patients (FK_Patient_Link_ID)
--  A distinct list of FK_Patient_Link_IDs for each patient in the cohort

-- OUTPUT: A temp table as follows:
-- #PatientYearOfBirth (FK_Patient_Link_ID, YearOfBirth)
-- 	- FK_Patient_Link_ID - unique patient id
--	- YearOfBirth - INT

-- ASSUMPTIONS:
--	- Patient data is obtained from multiple sources. Where patients have multiple YOBs we determine the YOB as follows:
--	-	If the patients has a YOB in their primary care data feed we use that as most likely to be up to date
--	-	If every YOB for a patient is the same, then we use that
--	-	If there is a single most recently updated YOB in the database then we use that
--	-	Otherwise we take the highest YOB for the patient that is not in the future

-- Get all patients year of birth for the cohort
IF OBJECT_ID('tempdb..#AllPatientYearOfBirths') IS NOT NULL DROP TABLE #AllPatientYearOfBirths;
SELECT 
	FK_Patient_Link_ID,
	FK_Reference_Tenancy_ID,
	HDMModifDate,
	YEAR(Dob) AS YearOfBirth
INTO #AllPatientYearOfBirths
FROM RLS.vw_Patient p
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND Dob IS NOT NULL;


-- If patients have a tenancy id of 2 we take this as their most likely YOB
-- as this is the GP data feed and so most likely to be up to date
IF OBJECT_ID('tempdb..#PatientYearOfBirth') IS NOT NULL DROP TABLE #PatientYearOfBirth;
SELECT FK_Patient_Link_ID, MIN(YearOfBirth) as YearOfBirth INTO #PatientYearOfBirth FROM #AllPatientYearOfBirths
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND FK_Reference_Tenancy_ID = 2
GROUP BY FK_Patient_Link_ID;

-- Find the patients who remain unmatched
IF OBJECT_ID('tempdb..#UnmatchedYobPatients') IS NOT NULL DROP TABLE #UnmatchedYobPatients;
SELECT FK_Patient_Link_ID INTO #UnmatchedYobPatients FROM #Patients
EXCEPT
SELECT FK_Patient_Link_ID FROM #PatientYearOfBirth;

-- If every YOB is the same for all their linked patient ids then we use that
INSERT INTO #PatientYearOfBirth
SELECT FK_Patient_Link_ID, MIN(YearOfBirth) FROM #AllPatientYearOfBirths
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #UnmatchedYobPatients)
GROUP BY FK_Patient_Link_ID
HAVING MIN(YearOfBirth) = MAX(YearOfBirth);

-- Find any still unmatched patients
TRUNCATE TABLE #UnmatchedYobPatients;
INSERT INTO #UnmatchedYobPatients
SELECT FK_Patient_Link_ID FROM #Patients
EXCEPT
SELECT FK_Patient_Link_ID FROM #PatientYearOfBirth;

-- If there is a unique most recent YOB then use that
INSERT INTO #PatientYearOfBirth
SELECT p.FK_Patient_Link_ID, MIN(p.YearOfBirth) FROM #AllPatientYearOfBirths p
INNER JOIN (
	SELECT FK_Patient_Link_ID, MAX(HDMModifDate) MostRecentDate FROM #AllPatientYearOfBirths
	WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #UnmatchedYobPatients)
	GROUP BY FK_Patient_Link_ID
) sub ON sub.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND sub.MostRecentDate = p.HDMModifDate
GROUP BY p.FK_Patient_Link_ID
HAVING MIN(YearOfBirth) = MAX(YearOfBirth);

-- Find any still unmatched patients
TRUNCATE TABLE #UnmatchedYobPatients;
INSERT INTO #UnmatchedYobPatients
SELECT FK_Patient_Link_ID FROM #Patients
EXCEPT
SELECT FK_Patient_Link_ID FROM #PatientYearOfBirth;

-- Otherwise just use the highest value (with the exception that can't be in the future)
INSERT INTO #PatientYearOfBirth
SELECT FK_Patient_Link_ID, MAX(YearOfBirth) FROM #AllPatientYearOfBirths
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #UnmatchedYobPatients)
GROUP BY FK_Patient_Link_ID
HAVING MAX(YearOfBirth) <= YEAR(GETDATE());

-- Every living unique person in the GMCR database
IF OBJECT_ID('tempdb..#AllLivingGMCRPatients') IS NOT NULL DROP TABLE #AllLivingGMCRPatients;
SELECT PK_Patient_Link_ID AS FK_Patient_Link_ID INTO #AllLivingGMCRPatients FROM RLS.vw_Patient_Link WHERE Deceased='N';
-- 5238741

-- Every unique person in the GMCR database who now or previously was registered with a GM GP
IF OBJECT_ID('tempdb..#GMCRPatientsWithGPFeed') IS NOT NULL DROP TABLE #GMCRPatientsWithGPFeed;
SELECT distinct FK_Patient_Link_ID INTO #GMCRPatientsWithGPFeed FROM RLS.vw_Patient WHERE FK_Reference_Tenancy_ID=2;
-- 3487444

-- Every unique living person in the GMCR database who now or previously was registered with a GM GP
IF OBJECT_ID('tempdb..#GMCRLivingPatientsWithGPFeed') IS NOT NULL DROP TABLE #GMCRLivingPatientsWithGPFeed;
SELECT FK_Patient_Link_ID INTO #GMCRLivingPatientsWithGPFeed FROM #GMCRPatientsWithGPFeed
INTERSECT
SELECT FK_Patient_Link_ID FROM #AllLivingGMCRPatients;
-- 3391988

-- Every unique person in the GMCR database who is currently registered with a GM GP (includes dead people who died while registered at a GM GP)
IF OBJECT_ID('tempdb..#GMCRPatientsWithGMGP') IS NOT NULL DROP TABLE #GMCRPatientsWithGMGP;
SELECT DISTINCT FK_Patient_Link_ID INTO #GMCRPatientsWithGMGP FROM RLS.vw_Patient
WHERE GPPracticeCode NOT LIKE 'ZZ%'
AND FK_Reference_Tenancy_ID=2;
-- 3246326

-- Every unique living person in the GMCR database who is currently registered with a GM GP
IF OBJECT_ID('tempdb..#GMCRLivingPatientsWithGMGP') IS NOT NULL DROP TABLE #GMCRLivingPatientsWithGMGP;
SELECT FK_Patient_Link_ID INTO #GMCRLivingPatientsWithGMGP FROM #GMCRPatientsWithGMGP
INTERSECT
SELECT FK_Patient_Link_ID FROM #AllLivingGMCRPatients;
-- 3153135

