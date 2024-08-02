IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT DISTINCT FK_Patient_Link_ID
INTO #Patients
FROM SharedCare.Patient
WHERE FK_Reference_Tenancy_ID=2
AND GPPracticeCode NOT LIKE 'ZZZ%';


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
FROM SharedCare.Patient p
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND Dob IS NOT NULL;


-- If patients have a tenancy id of 2 we take this as their most likely YOB
-- as this is the GP data feed and so most likely to be up to date
IF OBJECT_ID('tempdb..#PatientYearOfBirth') IS NOT NULL DROP TABLE #PatientYearOfBirth;
SELECT FK_Patient_Link_ID, MIN(YearOfBirth) as YearOfBirth INTO #PatientYearOfBirth FROM #AllPatientYearOfBirths
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND FK_Reference_Tenancy_ID = 2
GROUP BY FK_Patient_Link_ID
HAVING MIN(YearOfBirth) = MAX(YearOfBirth);

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

-- Tidy up - helpful in ensuring the tempdb doesn't run out of space mid-query
DROP TABLE #AllPatientYearOfBirths;
DROP TABLE #UnmatchedYobPatients;
-- 15s

-- Max age is 24 and first year is 2019, so we can exclude everyone born in 1994 and before.
TRUNCATE TABLE #Patients;
INSERT INTO #Patients
SELECT FK_Patient_Link_ID FROM #PatientYearOfBirth WHERE YearOfBirth > 1994;
-- 0s

IF OBJECT_ID('tempdb..#GPEvents') IS NOT NULL DROP TABLE #GPEvents;
SELECT FK_Patient_Link_ID, CAST(EventDate AS DATE) AS EventDate, SuppliedCode
INTO #GPEvents
FROM SharedCare.GP_Events
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND FK_Reference_Coding_ID IN (124578,124579,124580,124581,124582,124583,124584,124585,124586,124587,124588,124589,124590,124591,124592,124593,124594,124595,124596,124597,124598,124599,124600,124601,124602,124603,124604,124605,124606,124607,124608,124609,124610,124611,124612,124613,124614,124615,124616,124617,124618,124619,124620,124621,124622,124623,124624,124625,124626,124627,124628,124629,124630,124631,124632,124633,124634,124635,124636,124637,124638,124639,124640,124641,124642,124643,124644,124645,124646,124647,124648,124649,124650,124651,124652,124653,124654,124655,124656,124657,124658,124659,124660,124661,124662,124663,124664,124665,124666,117523,117524,117525,117526,117527,117528,117529,117530,117531,117532,117534,117535,117536,117537,117539,117540,117541,117542,117543,117544,117545,117546,117547,117548,117550,117551,117552,117553,117554,117555,117556,117557,117558,117559,117560,117561,117562,117563,117564,117565,117566,117567,117568,117569,117570,117571,117572,117573,117574,117575,117576,73632,274894,274895,274896,287830,287831,287832,287836,287876,287877,288307,288308,290405,290406,291804,291805,291806,291807,291808,291809,291810,291811,291812,291813,291814,291815,291816,291817,291818,291819,291846,291820,291847,291821,291848,291822,291849,291823,291850,291824,291851,291825,291852,291826,291853,291827,291854,291828,291855,291829,291856,291830,291857,291831,291858,291832,291833,291834,291835,291836,291837,291838,291839,291840,291841,291842,291843,291844,291845,291896,291897,291871,291898,291872,291899,291873,291900,291874,291901,291875,291902,291876,291877,291878,291879,291880,291881,291882,291883,291884,291885,291886,291887,291888,291889,291890,291891,291892,291893,291894,291895,304297,304298,73634,271383,73654,73658,73662,73668,73671,125022,125023,125030,125033,125035,125041,125042,125045,125047,125048,125050,125052,125053,125054,125055,125056,125073,125076,317447,317439,317440,317450,317452,317477,317483,317485,317487,317488,317489,317490,317491,317465,317466,317469,317514,317511);
-- 52s

IF OBJECT_ID('tempdb..#Ethnicities') IS NOT NULL DROP TABLE #Ethnicities;
SELECT 
  PK_Patient_Link_ID AS FK_Patient_Link_ID,
  EthnicMainGroup,
  NHS_EthnicCategory,
  EthnicCategoryDescription,
  EthnicGroupAlgorithm,
  EthnicGroupDescription
INTO #Ethnicities
FROM SharedCare.Patient_Link
WHERE PK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients);


select EthnicMainGroup, count(*) from #Ethnicities
group by EthnicMainGroup
order by count(*) desc;

select NHS_EthnicCategory, count(*) from #Ethnicities
group by NHS_EthnicCategory
order by count(*) desc;

select NHS_EthnicCategory, count(*) from #Ethnicities
group by NHS_EthnicCategory
order by count(*) desc;

select EthnicCategoryDescription, count(*) from #Ethnicities
where EthnicMainGroup like 'Other%'
group by EthnicCategoryDescription
order by count(*) desc;

select FK_Patient_Link_ID into #Anyotherethnicgroup
from #Ethnicities
where EthnicCategoryDescription = ('Any other ethnic group');
select FK_Patient_Link_ID into #Anyothergroup
from #Ethnicities
where EthnicCategoryDescription = ('Any other group');

select eth, count(*) from (
select FK_Patient_Link_ID, max(EthnicOrigin) eth from SharedCare.Patient
where FK_Patient_Link_ID in (SELECT FK_Patient_Link_ID FROM #Anyothergroup)
and EthnicOrigin is not null
and EthnicOrigin not in ('Any other ethnic group','Not known','Not stated','','Other Ethnic Group','British','Prefer Not To Say','X','NOT YET RECORDED','NKN','99')
group by FK_Patient_Link_ID
having max(EthnicOrigin) = min(EthnicOrigin)
) sub
group by eth
order by count(*) desc
order by FK_Patient_Link_ID
-- 
-- 17016
-- - 5756 have better ethnicity if removing all other/unknown etc.
-- - 2427 probably have better ethnicity but need eg.. pakistani == other asian background
select count(*) from #Anyothergroup


IF OBJECT_ID('tempdb..#reqw') IS NOT NULL DROP TABLE #reqw;
select FK_Patient_Link_ID,
CASE
WHEN EthnicOrigin = 'White British' THEN 'White'
WHEN EthnicOrigin = 'A - White British' THEN 'White'
WHEN EthnicOrigin = 'AFRICAN (BLACK or BLACK BRITISH)' THEN 'Black or Black British'
WHEN EthnicOrigin = 'Black/Blk Brit-African' THEN 'Black or Black British'
WHEN EthnicOrigin = 'WHITE & BLACK CARIBBEAN (MIXED' THEN 'Mixed'
WHEN EthnicOrigin = '0' THEN 'Refused and not stated group'
WHEN EthnicOrigin = '00' THEN 'Refused and not stated group'
WHEN EthnicOrigin = '1' THEN 'Refused and not stated group'
WHEN EthnicOrigin = 'G - Any other mixed background' THEN 'Mixed'
WHEN EthnicOrigin = '2' THEN 'Refused and not stated group'
WHEN EthnicOrigin = '03' THEN 'Refused and not stated group'
WHEN EthnicOrigin = '3' THEN 'Refused and not stated group'
WHEN EthnicOrigin = '4' THEN 'Refused and not stated group'
WHEN EthnicOrigin = 'OTHER ASIAN BACKGROUND' THEN 'Asian or Asian British'
WHEN EthnicOrigin = 'Black/Blk Brit-Caribbean' THEN 'Black or Black British'
WHEN EthnicOrigin = '5' THEN 'Refused and not stated group'
WHEN EthnicOrigin = '6' THEN 'Refused and not stated group'
WHEN EthnicOrigin = 'B - White Irish' THEN 'White'
WHEN EthnicOrigin = 'BANGLADESHI (ASIAN or ASIAN BRITISH)' THEN 'Asian or Asian British'
WHEN EthnicOrigin = 'White - Irish' THEN 'White'
WHEN EthnicOrigin = '7' THEN 'Refused and not stated group'
WHEN EthnicOrigin = '8' THEN 'Refused and not stated group'
WHEN EthnicOrigin = 'Black or Black British - Caribbean' THEN 'Black or Black British'
WHEN EthnicOrigin = '9' THEN 'Refused and not stated group'
WHEN EthnicOrigin = '10' THEN 'Refused and not stated group'
WHEN EthnicOrigin = '12' THEN 'Refused and not stated group'
WHEN EthnicOrigin = '13' THEN 'Refused and not stated group'
WHEN EthnicOrigin = '14' THEN 'Refused and not stated group'
WHEN EthnicOrigin = 'White - British' THEN 'White'
WHEN EthnicOrigin = 'Asian or Asian British - Indian' THEN 'Asian or Asian British'
WHEN EthnicOrigin = 'WHITE & ASIAN (MIXED)' THEN 'Mixed'
WHEN EthnicOrigin = 'WHITE & BLACK AFRICAN (MIXED)' THEN 'Mixed'
WHEN EthnicOrigin = '15' THEN 'Refused and not stated group'
WHEN EthnicOrigin = '18' THEN 'Refused and not stated group'
WHEN EthnicOrigin = 'Any other White background' THEN 'White'
WHEN EthnicOrigin = 'PAKISTANI (ASIAN or ASIAN BRITISH)' THEN 'Asian or Asian British'
WHEN EthnicOrigin = 'OTHER WHITE BACKGROUND' THEN 'White'
WHEN EthnicOrigin = 'Mixed - Any other background' THEN 'Mixed'
WHEN EthnicOrigin = 'Mixed-any oth mixed background' THEN 'Mixed'
WHEN EthnicOrigin = '19' THEN 'Refused and not stated group'
WHEN EthnicOrigin = 'WHITE AND BLACK AFRICAN (MIXED)' THEN 'Mixed'
WHEN EthnicOrigin = 'E - Mixed White and Black African' THEN 'Mixed'
WHEN EthnicOrigin = '' THEN 'Refused and not stated group'
WHEN EthnicOrigin = 'BRITISH (WHITE)' THEN 'White'
WHEN EthnicOrigin = 'White and Black Caribbean' THEN 'Mixed'
WHEN EthnicOrigin = 'Mixed-White & Black African' THEN 'Mixed'
WHEN EthnicOrigin = '20' THEN 'Refused and not stated group'
WHEN EthnicOrigin = 'AFRICAN (BLACK or BLACK BRITIS' THEN 'Black or Black British'
WHEN EthnicOrigin = 'White Irish' THEN 'White'
WHEN EthnicOrigin = 'Asian or Asian British' THEN 'Asian or Asian British'
WHEN EthnicOrigin = '29' THEN 'Refused and not stated group'
WHEN EthnicOrigin = 'F - Mixed White and Asian' THEN 'Mixed'
WHEN EthnicOrigin = '30' THEN 'Refused and not stated group'
WHEN EthnicOrigin = 'Asian/Asian Brit - Indian' THEN 'Asian or Asian British'
WHEN EthnicOrigin = 'White - any other White b/g' THEN 'White'
WHEN EthnicOrigin = 'Asian/Asian Brit - Pakistani' THEN 'Asian or Asian British'
WHEN EthnicOrigin = 'Mixed-White & Asian' THEN 'Mixed'
WHEN EthnicOrigin = 'Mixed - White and Asian' THEN 'Mixed'
WHEN EthnicOrigin = '31' THEN 'Refused and not stated group'
WHEN EthnicOrigin = 'BANGLADESHI (ASIAN or ASIAN BR' THEN 'Asian or Asian British'
WHEN EthnicOrigin = 'Asian/Asian Brit - Bangladeshi' THEN 'Asian or Asian British'
WHEN EthnicOrigin = 'Black or Black British' THEN 'Black or Black British'
WHEN EthnicOrigin = '40' THEN 'Refused and not stated group'
WHEN EthnicOrigin = 'Any other Black background' THEN 'Black or Black British'
WHEN EthnicOrigin = '50' THEN 'Refused and not stated group'
WHEN EthnicOrigin = '60' THEN 'Refused and not stated group'
WHEN EthnicOrigin = 'OTHER BLACK BACKGROUND' THEN 'Black or Black British'
WHEN EthnicOrigin = 'Mixed-White & Black Caribbean' THEN 'Mixed'
WHEN EthnicOrigin = 'WHITE  AND  BLACK CARIBBEAN (MIXED)' THEN 'Mixed'
WHEN EthnicOrigin = 'WHITE AND ASIAN (MIXED)' THEN 'Mixed'
WHEN EthnicOrigin = '70' THEN 'Refused and not stated group'
WHEN EthnicOrigin = 'P - Any other Black background' THEN 'Black or Black British'
WHEN EthnicOrigin = '80' THEN 'Refused and not stated group'
WHEN EthnicOrigin = '91' THEN 'Refused and not stated group'
WHEN EthnicOrigin = 'Black' THEN 'Black or Black British'
WHEN EthnicOrigin = 'CARIBBEAN (BLACK or BLACK BRITISH)' THEN 'Black or Black British'
WHEN EthnicOrigin = 'C - Any other White background' THEN 'White'
WHEN EthnicOrigin = '92' THEN 'Refused and not stated group'
WHEN EthnicOrigin = '99' THEN 'Refused and not stated group'
WHEN EthnicOrigin = '0F' THEN 'Refused and not stated group'
WHEN EthnicOrigin = 'D - Mixed White and Black Caribbean' THEN 'Mixed'
WHEN EthnicOrigin = 'N - Black African or Black British Afric' THEN 'Black or Black British'
WHEN EthnicOrigin = '8I' THEN 'Refused and not stated group'
WHEN EthnicOrigin = 'African' THEN 'Black or Black British'
WHEN EthnicOrigin = 'INDIAN (ASIAN or ASIAN BRITISH)' THEN 'Asian or Asian British'
WHEN EthnicOrigin = 'Asian or Asian British - Pakistani' THEN 'Asian or Asian British'
WHEN EthnicOrigin = 'Any other ethnic group' THEN 'Other Ethnic Groups'
WHEN EthnicOrigin = 'Bangladeshi' THEN 'Asian or Asian British'
WHEN EthnicOrigin = 'British' THEN 'Refused and not stated group'
WHEN EthnicOrigin = 'WHITE AND BLACK CARIBBEAN (MIXED)' THEN 'Mixed'
WHEN EthnicOrigin = 'Caribbean' THEN 'Black or Black British'
WHEN EthnicOrigin = 'Carribean' THEN 'Black or Black British'
WHEN EthnicOrigin = 'CE' THEN 'Refused and not stated group'
WHEN EthnicOrigin = 'Asian Indian' THEN 'Asian or Asian British'
WHEN EthnicOrigin = 'Asian Pakistani' THEN 'Asian or Asian British'
WHEN EthnicOrigin = 'WHITE  AND  ASIAN (MIXED)' THEN 'Mixed'
WHEN EthnicOrigin = 'Asian or Asian British - Any other Asian' THEN 'Asian or Asian British'
WHEN EthnicOrigin = 'Mixed - White and Black Caribbean' THEN 'Mixed'
WHEN EthnicOrigin = 'Chinese' THEN 'Chinese'
WHEN EthnicOrigin = 'CHINESE (OTHER ETHNIC GROUPS)' THEN 'Chinese'
WHEN EthnicOrigin = 'Any other Asian background' THEN 'Asian or Asian British'
WHEN EthnicOrigin = 'Any other mixed background' THEN 'Mixed'
WHEN EthnicOrigin = 'DO NOT WISH TO ANSWER' THEN 'Refused and not stated group'
WHEN EthnicOrigin = 'Gypsy or Irish Traveller' THEN 'Refused and not stated group'
WHEN EthnicOrigin = 'H - Indian or British Indian' THEN 'Asian or Asian British'
WHEN EthnicOrigin = 'OTHER MIXED BACKGROUND' THEN 'Mixed'
WHEN EthnicOrigin = 'PAKISTANI (ASIAN or ASIAN BRIT' THEN 'Asian or Asian British'
WHEN EthnicOrigin = 'Mixed White and Black Caribbean' THEN 'Mixed'
WHEN EthnicOrigin = 'I' THEN 'Refused and not stated group'
WHEN EthnicOrigin = 'WHITE  AND  BLACK AFRICAN (MIXED)' THEN 'Mixed'
WHEN EthnicOrigin = 'Mixed - White and Black African' THEN 'Mixed'
WHEN EthnicOrigin = 'Indian' THEN 'Asian or Asian British'
WHEN EthnicOrigin = 'Irish' THEN 'Refused and not stated group'
WHEN EthnicOrigin = 'J - Pakistani or British Pakistani' THEN 'Asian or Asian British'
WHEN EthnicOrigin = 'K - Bangladeshi or British Bangladeshi' THEN 'Asian or Asian British'
WHEN EthnicOrigin = 'Mixed White and Asian' THEN 'Mixed'
WHEN EthnicOrigin = 'Asian/Asian Brit-any oth Asian b/g' THEN 'Asian or Asian British'
WHEN EthnicOrigin = 'MUS' THEN 'Refused and not stated group'
WHEN EthnicOrigin = 'Black Caribbean' THEN 'Black or Black British'
WHEN EthnicOrigin = 'NG' THEN 'Refused and not stated group'
WHEN EthnicOrigin = 'INDIAN (ASIAN or ASIAN BRITISH' THEN 'Asian or Asian British'
WHEN EthnicOrigin = 'Asian' THEN 'Asian or Asian British'
WHEN EthnicOrigin = 'NKN' THEN 'Refused and not stated group'
WHEN EthnicOrigin = 'Black or Black British - Any other Black' THEN 'Black or Black British'
WHEN EthnicOrigin = 'Not known' THEN 'Refused and not stated group'
WHEN EthnicOrigin = 'White and Asian' THEN 'Asian or Asian British'
WHEN EthnicOrigin = 'Asian Bangladeshi' THEN 'Asian or Asian British'
WHEN EthnicOrigin = 'L  - Asian - other' THEN 'Asian or Asian British'
WHEN EthnicOrigin = 'White - Any other White background' THEN 'White'
WHEN EthnicOrigin = 'Any other Asian backround' THEN 'Asian or Asian British'
WHEN EthnicOrigin = 'Not Set' THEN 'Refused and not stated group'
WHEN EthnicOrigin = 'Not Specified' THEN 'Refused and not stated group'
WHEN EthnicOrigin = 'Not stated' THEN 'Refused and not stated group'
WHEN EthnicOrigin = 'NOT YET RECORDED' THEN 'Refused and not stated group'
WHEN EthnicOrigin = 'NSP' THEN 'Refused and not stated group'
WHEN EthnicOrigin = 'NULL' THEN 'Refused and not stated group'
WHEN EthnicOrigin = 'Asian or Asian British - Bangladeshi' THEN 'Asian or Asian British'
WHEN EthnicOrigin = 'CARIBBEAN (BLACK or BLACK BRIT' THEN 'Black or Black British'
WHEN EthnicOrigin = 'IRISH (WHITE)' THEN 'White'
WHEN EthnicOrigin = 'NULL' THEN 'Refused and not stated group'
WHEN EthnicOrigin = 'M - Black Caribbean or Black British Car' THEN 'Black or Black British'
WHEN EthnicOrigin = 'O' THEN 'Refused and not stated group'
WHEN EthnicOrigin = 'Black Carib' THEN 'Black or Black British'
WHEN EthnicOrigin = 'Black African' THEN 'Black or Black British'
WHEN EthnicOrigin = 'White and Black African' THEN 'Mixed'
WHEN EthnicOrigin = 'Other Ethnic Group' THEN 'Other Ethnic Groups'
WHEN EthnicOrigin = 'Other Ethnic Group - Chinese' THEN 'Chinese'
WHEN EthnicOrigin = 'Mixed White and Black African' THEN 'Mixed'
WHEN EthnicOrigin = 'Black or Black British - African' THEN 'Black or Black British'
WHEN EthnicOrigin = 'Black/Blk Brit-Any oth Blk b/g' THEN 'Black or Black British'
WHEN EthnicOrigin = 'Pakistani' THEN 'Asian or Asian British'
WHEN EthnicOrigin = 'WHITE ' THEN 'White'
WHEN EthnicOrigin = 'Prefer Not To Say' THEN 'Refused and not stated group'
WHEN EthnicOrigin = 'R - Chinese' THEN 'Chinese'
WHEN EthnicOrigin = 'REFUSED' THEN 'Refused and not stated group'
WHEN EthnicOrigin = 'S - Any other ethnic group' THEN 'Other Ethnic Groups'
WHEN EthnicOrigin = 'Black/Black Brit - African' THEN 'Black or Black British'
WHEN EthnicOrigin = 'System Generated' THEN 'Refused and not stated group'
WHEN EthnicOrigin = 'UN' THEN 'Refused and not stated group'
WHEN EthnicOrigin = 'Unknown' THEN 'Refused and not stated group'
WHEN EthnicOrigin = 'W' THEN 'Refused and not stated group'
WHEN EthnicOrigin = 'X' THEN 'Refused and not stated group'
WHEN EthnicOrigin = 'Z - Not Stated' THEN 'Refused and not stated group'
WHEN EthnicOrigin = '' THEN ''
WHEN EthnicOrigin = 'Asian British or Other Asian Background' THEN 'Asian or Asian British'
ELSE 'Refused and not stated group' END AS EthnicOrigin
into #reqw
from SharedCare.Patient
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients);

select eth, count(*) from (
select FK_Patient_Link_ID, max(EthnicOrigin) eth from #reqw
where FK_Patient_Link_ID in (SELECT FK_Patient_Link_ID FROM #Anyotherethnicgroup UNION SELECT FK_Patient_Link_ID FROM #Anyothergroup)
and EthnicOrigin is not null
and EthnicOrigin not in ('Refused and not stated group','Other Ethnic Groups')
group by FK_Patient_Link_ID
having max(EthnicOrigin) = min(EthnicOrigin)
) sub
-- 2459 with contradictory
-- 48451
group by eth
order by count(*) desc
order by FK_Patient_Link_ID


-- 140597
-- - 30773 have better ethnicity if removing all other/unknown etc.
-- - 12476 probably have better ethnicity but need eg.. pakistani == other asian background
select count(*) from #Anyotherethnicgroup

select e.*/*, c.CodeDescription*/ from #GPEvents e
--left outer join [Config].[Clinical_Coding_Groups] c on c.FK_Reference_Coding_ID = e.FK_Patient_Link_ID
where FK_Patient_Link_ID in (select  * from #Anyotherethnicgroup)