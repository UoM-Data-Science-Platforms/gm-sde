--┌────────────────────────────────────┐
--│ Covid Test Outcomes	               │
--└────────────────────────────────────┘

-- REVIEW LOG:

-- OUTPUT: Data with the following fields
-- Patient Id
-- TestOutcome (positive/negative/inconclusive)
-- TestDate (DD-MM-YYYY)
-- TestLocation (hospital/elsewhere) - NOT AVAILABLE

-- Set the start date
DECLARE @StartDate datetime;
SET @StartDate = '2020-01-31';

--Just want the output, not the messages
SET NOCOUNT ON;

-- Find all patients alive at start date
IF OBJECT_ID('tempdb..#PossiblePatients') IS NOT NULL DROP TABLE #PossiblePatients;
SELECT PK_Patient_Link_ID as FK_Patient_Link_ID, EthnicMainGroup, DeathDate INTO #PossiblePatients FROM [RLS].vw_Patient_Link
WHERE (DeathDate IS NULL OR DeathDate >= @StartDate);

-- Find all patients registered with a GP
IF OBJECT_ID('tempdb..#PatientsWithGP') IS NOT NULL DROP TABLE #PatientsWithGP;
SELECT DISTINCT FK_Patient_Link_ID INTO #PatientsWithGP FROM [RLS].vw_Patient
where FK_Reference_Tenancy_ID = 2;

-- Make cohort from patients alive at start date and registered with a GP
IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT pp.* INTO #Patients FROM #PossiblePatients pp
INNER JOIN #PatientsWithGP gp on gp.FK_Patient_Link_ID = pp.FK_Patient_Link_ID;

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

-- >>> Codesets required... Inserting the code set code
--
--┌────────────────────┐
--│ Clinical code sets │
--└────────────────────┘

-- OBJECTIVE: To populate temporary tables with the existing clinical code sets.
--            See the [SQL-generation-process.md](SQL-generation-process.md) for more details.

-- INPUT: No pre-requisites

-- OUTPUT: Five temp tables as follows:
--  #AllCodes (Concept, Version, Code)
--  #CodeSets (FK_Reference_Coding_ID, Concept)
--  #SnomedSets (FK_Reference_SnomedCT_ID, FK_SNOMED_ID)
--  #VersionedCodeSets (FK_Reference_Coding_ID, Concept, Version)
--  #VersionedSnomedSets (FK_Reference_SnomedCT_ID, Version, FK_SNOMED_ID)

--!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
--!!! DO NOT EDIT THIS FILE MANUALLY !!!
--!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

IF OBJECT_ID('tempdb..#AllCodes') IS NOT NULL DROP TABLE #AllCodes;
CREATE TABLE #AllCodes (
  [Concept] [varchar](255) NOT NULL,
  [Version] INT NOT NULL,
  [Code] [varchar](20) COLLATE Latin1_General_CS_AS NOT NULL
);

IF OBJECT_ID('tempdb..#codesreadv2') IS NOT NULL DROP TABLE #codesreadv2;
CREATE TABLE #codesreadv2 (
  [concept] [varchar](255) NOT NULL,
  [version] INT NOT NULL,
	[code] [varchar](20) COLLATE Latin1_General_CS_AS NOT NULL,
	[description] [varchar](255) NULL
) ON [PRIMARY];

INSERT INTO #codesreadv2
VALUES ('severe-mental-illness',1,'E11..99','Manic-depressive psychoses'),('severe-mental-illness',1,'E11..','Manic-depressive psychoses'),('severe-mental-illness',1,'E110.99','Mania/hypomania'),('severe-mental-illness',1,'E110.','Mania/hypomania'),('severe-mental-illness',1,'Eu30213','[X]Manic stupor'),('severe-mental-illness',1,'Eu302','[X]Manic stupor'),('severe-mental-illness',1,'ZRby100','mood states, bipolar'),('severe-mental-illness',1,'ZRby1','mood states, bipolar'),('severe-mental-illness',1,'13Y3.00','Manic-depression association member'),('severe-mental-illness',1,'13Y3.','Manic-depression association member'),('severe-mental-illness',1,'146D.00','H/O: manic depressive disorder'),('severe-mental-illness',1,'146D.','H/O: manic depressive disorder'),('severe-mental-illness',1,'1S42.00','Manic mood'),('severe-mental-illness',1,'1S42.','Manic mood'),('severe-mental-illness',1,'212V.00','Bipolar affective disorder resolved'),('severe-mental-illness',1,'212V.','Bipolar affective disorder resolved'),('severe-mental-illness',1,'46P3.00','Urine lithium'),('severe-mental-illness',1,'46P3.','Urine lithium'),('severe-mental-illness',1,'6657.00','On lithium'),('severe-mental-illness',1,'6657.','On lithium'),('severe-mental-illness',1,'6657.11','Lithium monitoring'),('severe-mental-illness',1,'6657.','Lithium monitoring'),('severe-mental-illness',1,'6657.12','Started lithium'),('severe-mental-illness',1,'6657.','Started lithium'),('severe-mental-illness',1,'665B.00','Lithium stopped'),('severe-mental-illness',1,'665B.','Lithium stopped'),('severe-mental-illness',1,'665J.00','Lithium level checked at 3 monthly intervals'),('severe-mental-illness',1,'665J.','Lithium level checked at 3 monthly intervals'),('severe-mental-illness',1,'665K.00','Lithium therapy record book completed'),('severe-mental-illness',1,'665K.','Lithium therapy record book completed'),('severe-mental-illness',1,'9Ol5.00','Lithium monitoring first letter'),('severe-mental-illness',1,'9Ol5.','Lithium monitoring first letter'),('severe-mental-illness',1,'9Ol6.00','Lithium monitoring second letter'),('severe-mental-illness',1,'9Ol6.','Lithium monitoring second letter'),('severe-mental-illness',1,'9Ol7.00','Lithium monitoring third letter'),('severe-mental-illness',1,'9Ol7.','Lithium monitoring third letter'),('severe-mental-illness',1,'E11..00','Affective psychoses'),('severe-mental-illness',1,'E11..','Affective psychoses'),('severe-mental-illness',1,'E11..11','Bipolar psychoses'),('severe-mental-illness',1,'E11..','Bipolar psychoses'),('severe-mental-illness',1,'E11..12','Depressive psychoses'),('severe-mental-illness',1,'E11..','Depressive psychoses'),('severe-mental-illness',1,'E11..13','Manic psychoses'),('severe-mental-illness',1,'E11..','Manic psychoses'),('severe-mental-illness',1,'E110.00','Manic disorder, single episode'),('severe-mental-illness',1,'E110.','Manic disorder, single episode'),('severe-mental-illness',1,'E110.11','Hypomanic psychoses'),('severe-mental-illness',1,'E110.','Hypomanic psychoses'),('severe-mental-illness',1,'E110000','Single manic episode, unspecified'),('severe-mental-illness',1,'E1100','Single manic episode, unspecified'),('severe-mental-illness',1,'E110100','Single manic episode, mild'),('severe-mental-illness',1,'E1101','Single manic episode, mild'),('severe-mental-illness',1,'E110200','Single manic episode, moderate'),('severe-mental-illness',1,'E1102','Single manic episode, moderate'),('severe-mental-illness',1,'E110300','Single manic episode, severe without mention of psychosis'),('severe-mental-illness',1,'E1103','Single manic episode, severe without mention of psychosis'),('severe-mental-illness',1,'E110400','Single manic episode, severe, with psychosis'),('severe-mental-illness',1,'E1104','Single manic episode, severe, with psychosis'),('severe-mental-illness',1,'E110500','Single manic episode in partial or unspecified remission'),('severe-mental-illness',1,'E1105','Single manic episode in partial or unspecified remission'),('severe-mental-illness',1,'E110600','Single manic episode in full remission'),('severe-mental-illness',1,'E1106','Single manic episode in full remission'),('severe-mental-illness',1,'E110z00','Manic disorder, single episode NOS'),('severe-mental-illness',1,'E110z','Manic disorder, single episode NOS'),('severe-mental-illness',1,'E111.00','Recurrent manic episodes'),('severe-mental-illness',1,'E111.','Recurrent manic episodes'),('severe-mental-illness',1,'E111000','Recurrent manic episodes, unspecified'),('severe-mental-illness',1,'E1110','Recurrent manic episodes, unspecified'),('severe-mental-illness',1,'E111100','Recurrent manic episodes, mild'),('severe-mental-illness',1,'E1111','Recurrent manic episodes, mild'),('severe-mental-illness',1,'E111200','Recurrent manic episodes, moderate'),('severe-mental-illness',1,'E1112','Recurrent manic episodes, moderate'),('severe-mental-illness',1,'E111300','Recurrent manic episodes, severe without mention psychosis'),('severe-mental-illness',1,'E1113','Recurrent manic episodes, severe without mention psychosis'),('severe-mental-illness',1,'E111400','Recurrent manic episodes, severe, with psychosis'),('severe-mental-illness',1,'E1114','Recurrent manic episodes, severe, with psychosis'),('severe-mental-illness',1,'E111500','Recurrent manic episodes, partial or unspecified remission'),('severe-mental-illness',1,'E1115','Recurrent manic episodes, partial or unspecified remission'),('severe-mental-illness',1,'E111600','Recurrent manic episodes, in full remission'),('severe-mental-illness',1,'E1116','Recurrent manic episodes, in full remission'),('severe-mental-illness',1,'E111z00','Recurrent manic episode NOS'),('severe-mental-illness',1,'E111z','Recurrent manic episode NOS'),('severe-mental-illness',1,'E114.00','Bipolar affective disorder, currently manic'),('severe-mental-illness',1,'E114.','Bipolar affective disorder, currently manic'),('severe-mental-illness',1,'E114.11','Manic-depressive - now manic'),('severe-mental-illness',1,'E114.','Manic-depressive - now manic'),('severe-mental-illness',1,'E114000','Bipolar affective disorder, currently manic, unspecified'),('severe-mental-illness',1,'E1140','Bipolar affective disorder, currently manic, unspecified'),('severe-mental-illness',1,'E114100','Bipolar affective disorder, currently manic, mild'),('severe-mental-illness',1,'E1141','Bipolar affective disorder, currently manic, mild'),('severe-mental-illness',1,'E114200','Bipolar affective disorder, currently manic, moderate'),('severe-mental-illness',1,'E1142','Bipolar affective disorder, currently manic, moderate'),('severe-mental-illness',1,'E114300','Bipolar affect disord, currently manic, severe, no psychosis'),('severe-mental-illness',1,'E1143','Bipolar affect disord, currently manic, severe, no psychosis'),('severe-mental-illness',1,'E114400','Bipolar affect disord, currently manic,severe with psychosis'),('severe-mental-illness',1,'E1144','Bipolar affect disord, currently manic,severe with psychosis'),('severe-mental-illness',1,'E114500','Bipolar affect disord,currently manic, part/unspec remission'),('severe-mental-illness',1,'E1145','Bipolar affect disord,currently manic, part/unspec remission'),('severe-mental-illness',1,'E114600','Bipolar affective disorder, currently manic, full remission'),('severe-mental-illness',1,'E1146','Bipolar affective disorder, currently manic, full remission'),('severe-mental-illness',1,'E114z00','Bipolar affective disorder, currently manic, NOS'),('severe-mental-illness',1,'E114z','Bipolar affective disorder, currently manic, NOS'),('severe-mental-illness',1,'E115.00','Bipolar affective disorder, currently depressed'),('severe-mental-illness',1,'E115.','Bipolar affective disorder, currently depressed'),('severe-mental-illness',1,'E115.11','Manic-depressive - now depressed'),('severe-mental-illness',1,'E115.','Manic-depressive - now depressed'),('severe-mental-illness',1,'E115000','Bipolar affective disorder, currently depressed, unspecified'),('severe-mental-illness',1,'E1150','Bipolar affective disorder, currently depressed, unspecified'),('severe-mental-illness',1,'E115100','Bipolar affective disorder, currently depressed, mild'),('severe-mental-illness',1,'E1151','Bipolar affective disorder, currently depressed, mild'),('severe-mental-illness',1,'E115200','Bipolar affective disorder, currently depressed, moderate'),('severe-mental-illness',1,'E1152','Bipolar affective disorder, currently depressed, moderate'),('severe-mental-illness',1,'E115300','Bipolar affect disord, now depressed, severe, no psychosis'),('severe-mental-illness',1,'E1153','Bipolar affect disord, now depressed, severe, no psychosis'),('severe-mental-illness',1,'E115400','Bipolar affect disord, now depressed, severe with psychosis'),('severe-mental-illness',1,'E1154','Bipolar affect disord, now depressed, severe with psychosis'),('severe-mental-illness',1,'E115500','Bipolar affect disord, now depressed, part/unspec remission'),('severe-mental-illness',1,'E1155','Bipolar affect disord, now depressed, part/unspec remission'),('severe-mental-illness',1,'E115600','Bipolar affective disorder, now depressed, in full remission'),('severe-mental-illness',1,'E1156','Bipolar affective disorder, now depressed, in full remission'),('severe-mental-illness',1,'E115z00','Bipolar affective disorder, currently depressed, NOS'),('severe-mental-illness',1,'E115z','Bipolar affective disorder, currently depressed, NOS'),('severe-mental-illness',1,'E116.00','Mixed bipolar affective disorder'),('severe-mental-illness',1,'E116.','Mixed bipolar affective disorder'),('severe-mental-illness',1,'E116000','Mixed bipolar affective disorder, unspecified'),('severe-mental-illness',1,'E1160','Mixed bipolar affective disorder, unspecified'),('severe-mental-illness',1,'E116100','Mixed bipolar affective disorder, mild'),('severe-mental-illness',1,'E1161','Mixed bipolar affective disorder, mild'),
('severe-mental-illness',1,'E116200','Mixed bipolar affective disorder, moderate'),('severe-mental-illness',1,'E1162','Mixed bipolar affective disorder, moderate'),('severe-mental-illness',1,'E116300','Mixed bipolar affective disorder, severe, without psychosis'),('severe-mental-illness',1,'E1163','Mixed bipolar affective disorder, severe, without psychosis'),('severe-mental-illness',1,'E116400','Mixed bipolar affective disorder, severe, with psychosis'),('severe-mental-illness',1,'E1164','Mixed bipolar affective disorder, severe, with psychosis'),('severe-mental-illness',1,'E116500','Mixed bipolar affective disorder, partial/unspec remission'),('severe-mental-illness',1,'E1165','Mixed bipolar affective disorder, partial/unspec remission'),('severe-mental-illness',1,'E116600','Mixed bipolar affective disorder, in full remission'),('severe-mental-illness',1,'E1166','Mixed bipolar affective disorder, in full remission'),('severe-mental-illness',1,'E116z00','Mixed bipolar affective disorder, NOS'),('severe-mental-illness',1,'E116z','Mixed bipolar affective disorder, NOS'),('severe-mental-illness',1,'E117.00','Unspecified bipolar affective disorder'),('severe-mental-illness',1,'E117.','Unspecified bipolar affective disorder'),('severe-mental-illness',1,'E117000','Unspecified bipolar affective disorder, unspecified'),('severe-mental-illness',1,'E1170','Unspecified bipolar affective disorder, unspecified'),('severe-mental-illness',1,'E117100','Unspecified bipolar affective disorder, mild'),('severe-mental-illness',1,'E1171','Unspecified bipolar affective disorder, mild'),('severe-mental-illness',1,'E117200','Unspecified bipolar affective disorder, moderate'),('severe-mental-illness',1,'E1172','Unspecified bipolar affective disorder, moderate'),('severe-mental-illness',1,'E117300','Unspecified bipolar affective disorder, severe, no psychosis'),('severe-mental-illness',1,'E1173','Unspecified bipolar affective disorder, severe, no psychosis'),('severe-mental-illness',1,'E117400','Unspecified bipolar affective disorder,severe with psychosis'),('severe-mental-illness',1,'E1174','Unspecified bipolar affective disorder,severe with psychosis'),('severe-mental-illness',1,'E117500','Unspecified bipolar affect disord, partial/unspec remission'),('severe-mental-illness',1,'E1175','Unspecified bipolar affect disord, partial/unspec remission'),('severe-mental-illness',1,'E117600','Unspecified bipolar affective disorder, in full remission'),('severe-mental-illness',1,'E1176','Unspecified bipolar affective disorder, in full remission'),('severe-mental-illness',1,'E117z00','Unspecified bipolar affective disorder, NOS'),('severe-mental-illness',1,'E117z','Unspecified bipolar affective disorder, NOS'),('severe-mental-illness',1,'E11y.00','Other and unspecified manic-depressive psychoses'),('severe-mental-illness',1,'E11y.','Other and unspecified manic-depressive psychoses'),('severe-mental-illness',1,'E11y000','Unspecified manic-depressive psychoses'),('severe-mental-illness',1,'E11y0','Unspecified manic-depressive psychoses'),('severe-mental-illness',1,'E11y100','Atypical manic disorder'),('severe-mental-illness',1,'E11y1','Atypical manic disorder'),('severe-mental-illness',1,'E11y200','Atypical depressive disorder'),('severe-mental-illness',1,'E11y2','Atypical depressive disorder'),('severe-mental-illness',1,'E11y300','Other mixed manic-depressive psychoses'),('severe-mental-illness',1,'E11y3','Other mixed manic-depressive psychoses'),('severe-mental-illness',1,'E11yz00','Other and unspecified manic-depressive psychoses NOS'),('severe-mental-illness',1,'E11yz','Other and unspecified manic-depressive psychoses NOS'),('severe-mental-illness',1,'E11z.00','Other and unspecified affective psychoses'),('severe-mental-illness',1,'E11z.','Other and unspecified affective psychoses'),('severe-mental-illness',1,'E11z000','Unspecified affective psychoses NOS'),('severe-mental-illness',1,'E11z0','Unspecified affective psychoses NOS'),('severe-mental-illness',1,'E11z100','Rebound mood swings'),('severe-mental-illness',1,'E11z1','Rebound mood swings'),('severe-mental-illness',1,'E11z200','Masked depression'),('severe-mental-illness',1,'E11z2','Masked depression'),('severe-mental-illness',1,'E11zz00','Other affective psychosis NOS'),('severe-mental-illness',1,'E11zz','Other affective psychosis NOS'),('severe-mental-illness',1,'Eu3..00','[X]Mood - affective disorders'),('severe-mental-illness',1,'Eu3..','[X]Mood - affective disorders'),('severe-mental-illness',1,'Eu30.00','[X]Manic episode'),('severe-mental-illness',1,'Eu30.','[X]Manic episode'),('severe-mental-illness',1,'Eu30.11','[X]Bipolar disorder, single manic episode'),('severe-mental-illness',1,'Eu30.','[X]Bipolar disorder, single manic episode'),('severe-mental-illness',1,'Eu30000','[X]Hypomania'),('severe-mental-illness',1,'Eu300','[X]Hypomania'),('severe-mental-illness',1,'Eu30100','[X]Mania without psychotic symptoms'),('severe-mental-illness',1,'Eu301','[X]Mania without psychotic symptoms'),('severe-mental-illness',1,'Eu30200','[X]Mania with psychotic symptoms'),('severe-mental-illness',1,'Eu302','[X]Mania with psychotic symptoms'),('severe-mental-illness',1,'Eu30211','[X]Mania with mood-congruent psychotic symptoms'),('severe-mental-illness',1,'Eu302','[X]Mania with mood-congruent psychotic symptoms'),('severe-mental-illness',1,'Eu30212','[X]Mania with mood-incongruent psychotic symptoms'),('severe-mental-illness',1,'Eu302','[X]Mania with mood-incongruent psychotic symptoms'),('severe-mental-illness',1,'Eu30y00','[X]Other manic episodes'),('severe-mental-illness',1,'Eu30y','[X]Other manic episodes'),('severe-mental-illness',1,'Eu30z00','[X]Manic episode, unspecified'),('severe-mental-illness',1,'Eu30z','[X]Manic episode, unspecified'),('severe-mental-illness',1,'Eu30z11','[X]Mania NOS'),('severe-mental-illness',1,'Eu30z','[X]Mania NOS'),('severe-mental-illness',1,'Eu31.00','[X]Bipolar affective disorder'),('severe-mental-illness',1,'Eu31.','[X]Bipolar affective disorder'),('severe-mental-illness',1,'Eu31.11','[X]Manic-depressive illness'),('severe-mental-illness',1,'Eu31.','[X]Manic-depressive illness'),('severe-mental-illness',1,'Eu31.12','[X]Manic-depressive psychosis'),('severe-mental-illness',1,'Eu31.','[X]Manic-depressive psychosis'),('severe-mental-illness',1,'Eu31.13','[X]Manic-depressive reaction'),('severe-mental-illness',1,'Eu31.','[X]Manic-depressive reaction'),('severe-mental-illness',1,'Eu31000','[X]Bipolar affective disorder, current episode hypomanic'),('severe-mental-illness',1,'Eu310','[X]Bipolar affective disorder, current episode hypomanic'),('severe-mental-illness',1,'Eu31100','[X]Bipolar affect disorder cur epi manic wout psychotic symp'),('severe-mental-illness',1,'Eu311','[X]Bipolar affect disorder cur epi manic wout psychotic symp'),('severe-mental-illness',1,'Eu31200','[X]Bipolar affect disorder cur epi manic with psychotic symp'),('severe-mental-illness',1,'Eu312','[X]Bipolar affect disorder cur epi manic with psychotic symp'),('severe-mental-illness',1,'Eu31300','[X]Bipolar affect disorder cur epi mild or moderate depressn'),('severe-mental-illness',1,'Eu313','[X]Bipolar affect disorder cur epi mild or moderate depressn'),('severe-mental-illness',1,'Eu31400','[X]Bipol aff disord, curr epis sev depress, no psychot symp'),('severe-mental-illness',1,'Eu314','[X]Bipol aff disord, curr epis sev depress, no psychot symp'),('severe-mental-illness',1,'Eu31500','[X]Bipolar affect dis cur epi severe depres with psyc symp'),('severe-mental-illness',1,'Eu315','[X]Bipolar affect dis cur epi severe depres with psyc symp'),('severe-mental-illness',1,'Eu31600','[X]Bipolar affective disorder, current episode mixed'),('severe-mental-illness',1,'Eu316','[X]Bipolar affective disorder, current episode mixed'),('severe-mental-illness',1,'Eu31700','[X]Bipolar affective disorder, currently in remission'),('severe-mental-illness',1,'Eu317','[X]Bipolar affective disorder, currently in remission'),('severe-mental-illness',1,'Eu31800','[X]Bipolar affective disorder type I'),('severe-mental-illness',1,'Eu318','[X]Bipolar affective disorder type I'),('severe-mental-illness',1,'Eu31900','[X]Bipolar affective disorder type II'),('severe-mental-illness',1,'Eu319','[X]Bipolar affective disorder type II'),('severe-mental-illness',1,'Eu31911','[X]Bipolar II disorder'),('severe-mental-illness',1,'Eu319','[X]Bipolar II disorder'),('severe-mental-illness',1,'Eu31y00','[X]Other bipolar affective disorders'),('severe-mental-illness',1,'Eu31y','[X]Other bipolar affective disorders'),('severe-mental-illness',1,'Eu31y11','[X]Bipolar II disorder'),('severe-mental-illness',1,'Eu31y','[X]Bipolar II disorder'),('severe-mental-illness',1,'Eu31y12','[X]Recurrent manic episodes'),('severe-mental-illness',1,'Eu31y','[X]Recurrent manic episodes'),('severe-mental-illness',1,'Eu31z00','[X]Bipolar affective disorder, unspecified'),('severe-mental-illness',1,'Eu31z','[X]Bipolar affective disorder, unspecified'),('severe-mental-illness',1,'Eu33213','[X]Manic-depress psychosis,depressd,no psychotic symptoms'),('severe-mental-illness',1,'Eu332','[X]Manic-depress psychosis,depressd,no psychotic symptoms'),('severe-mental-illness',1,'Eu33312','[X]Manic-depress psychosis,depressed type+psychotic symptoms'),('severe-mental-illness',1,'Eu333','[X]Manic-depress psychosis,depressed type+psychotic symptoms'),('severe-mental-illness',1,'Eu34.00','[X]Persistent mood affective disorders'),('severe-mental-illness',1,'Eu34.','[X]Persistent mood affective disorders'),('severe-mental-illness',1,'Eu34000','[X]Cyclothymia'),('severe-mental-illness',1,'Eu340','[X]Cyclothymia'),('severe-mental-illness',1,'Eu34011','[X]Affective personality disorder'),('severe-mental-illness',1,'Eu340','[X]Affective personality disorder'),('severe-mental-illness',1,'Eu34012','[X]Cycloid personality'),('severe-mental-illness',1,'Eu340','[X]Cycloid personality'),
('severe-mental-illness',1,'Eu34013','[X]Cyclothymic personality'),('severe-mental-illness',1,'Eu340','[X]Cyclothymic personality'),('severe-mental-illness',1,'Eu34y00','[X]Other persistent mood affective disorders'),('severe-mental-illness',1,'Eu34y','[X]Other persistent mood affective disorders'),('severe-mental-illness',1,'Eu34z00','[X]Persistent mood affective disorder, unspecified'),('severe-mental-illness',1,'Eu34z','[X]Persistent mood affective disorder, unspecified'),('severe-mental-illness',1,'Eu3y.00','[X]Other mood affective disorders'),('severe-mental-illness',1,'Eu3y.','[X]Other mood affective disorders'),('severe-mental-illness',1,'Eu3y000','[X]Other single mood affective disorders'),('severe-mental-illness',1,'Eu3y0','[X]Other single mood affective disorders'),('severe-mental-illness',1,'Eu3y011','[X]Mixed affective episode'),('severe-mental-illness',1,'Eu3y0','[X]Mixed affective episode'),('severe-mental-illness',1,'Eu3y100','[X]Other recurrent mood affective disorders'),('severe-mental-illness',1,'Eu3y1','[X]Other recurrent mood affective disorders'),('severe-mental-illness',1,'Eu3yy00','[X]Other specified mood affective disorders'),('severe-mental-illness',1,'Eu3yy','[X]Other specified mood affective disorders'),('severe-mental-illness',1,'Eu3z.00','[X]Unspecified mood affective disorder'),('severe-mental-illness',1,'Eu3z.','[X]Unspecified mood affective disorder'),('severe-mental-illness',1,'Eu3z.11','[X]Affective psychosis NOS'),('severe-mental-illness',1,'Eu3z.','[X]Affective psychosis NOS'),('severe-mental-illness',1,'ZV11111','[V]Personal history of manic-depressive psychosis'),('severe-mental-illness',1,'ZV111','[V]Personal history of manic-depressive psychosis'),('severe-mental-illness',1,'ZV11112','[V]Personal history of manic-depressive psychosis'),('severe-mental-illness',1,'ZV111','[V]Personal history of manic-depressive psychosis'),('severe-mental-illness',1,'E101100','Subchronic hebephrenic schizophrenia'),('severe-mental-illness',1,'E1011','Subchronic hebephrenic schizophrenia'),('severe-mental-illness',1,'E101300','Acute exacerbation of subchronic hebephrenic schizophrenia'),('severe-mental-illness',1,'E1013','Acute exacerbation of subchronic hebephrenic schizophrenia'),('severe-mental-illness',1,'E102300','Acute exacerbation of subchronic catatonic schizophrenia'),('severe-mental-illness',1,'E1023','Acute exacerbation of subchronic catatonic schizophrenia'),('severe-mental-illness',1,'E105100','Subchronic latent schizophrenia'),('severe-mental-illness',1,'E1051','Subchronic latent schizophrenia'),('severe-mental-illness',1,'E105300','Acute exacerbation of subchronic latent schizophrenia'),('severe-mental-illness',1,'E1053','Acute exacerbation of subchronic latent schizophrenia'),('severe-mental-illness',1,'E106.11','Restzustand - schizophrenia'),('severe-mental-illness',1,'E106.','Restzustand - schizophrenia'),('severe-mental-illness',1,'E141000','Active disintegrative psychoses'),('severe-mental-illness',1,'E1410','Active disintegrative psychoses'),('severe-mental-illness',1,'E141z00','Disintegrative psychosis NOS'),('severe-mental-illness',1,'E141z','Disintegrative psychosis NOS'),('severe-mental-illness',1,'Eu20512','[X]Restzustand schizophrenic'),('severe-mental-illness',1,'Eu205','[X]Restzustand schizophrenic'),('severe-mental-illness',1,'Eu20y11','[X]Cenesthopathic schizophrenia'),('severe-mental-illness',1,'Eu20y','[X]Cenesthopathic schizophrenia'),('severe-mental-illness',1,'Eu23111','[X]Bouffee delirante with symptoms of schizophrenia'),('severe-mental-illness',1,'Eu231','[X]Bouffee delirante with symptoms of schizophrenia'),('severe-mental-illness',1,'Eu60012','[X]Fanatic paranoid personality disorder'),('severe-mental-illness',1,'Eu600','[X]Fanatic paranoid personality disorder'),('severe-mental-illness',1,'ZS7C611','#N/A'),('severe-mental-illness',1,'ZS7C6','#N/A'),('severe-mental-illness',1,'13Y2.00','Schizophrenia association member'),('severe-mental-illness',1,'13Y2.','Schizophrenia association member'),('severe-mental-illness',1,'1464.00','H/O: schizophrenia'),('severe-mental-illness',1,'1464.','H/O: schizophrenia'),('severe-mental-illness',1,'146H.00','H/O: psychosis'),('severe-mental-illness',1,'146H.','H/O: psychosis'),('severe-mental-illness',1,'1BH..00','Delusions'),('severe-mental-illness',1,'1BH..','Delusions'),('severe-mental-illness',1,'1BH..11','Delusion'),('severe-mental-illness',1,'1BH..','Delusion'),('severe-mental-illness',1,'1BH0.00','Delusion of persecution'),('severe-mental-illness',1,'1BH0.','Delusion of persecution'),('severe-mental-illness',1,'1BH1.00','Grandiose delusions'),('severe-mental-illness',1,'1BH1.','Grandiose delusions'),('severe-mental-illness',1,'1BH2.00','Ideas of reference'),('severe-mental-illness',1,'1BH2.','Ideas of reference'),('severe-mental-illness',1,'1BH3.00','Paranoid ideation'),('severe-mental-illness',1,'1BH3.','Paranoid ideation'),('severe-mental-illness',1,'212W.00','Schizophrenia resolved'),('severe-mental-illness',1,'212W.','Schizophrenia resolved'),('severe-mental-illness',1,'212X.00','Psychosis resolved'),('severe-mental-illness',1,'212X.','Psychosis resolved'),('severe-mental-illness',1,'225E.00','O/E - paranoid delusions'),('severe-mental-illness',1,'225E.','O/E - paranoid delusions'),('severe-mental-illness',1,'225F.00','O/E - delusion of persecution'),('severe-mental-illness',1,'225F.','O/E - delusion of persecution'),('severe-mental-illness',1,'285..11','Psychotic condition, insight present'),('severe-mental-illness',1,'285..','Psychotic condition, insight present'),('severe-mental-illness',1,'286..11','Poor insight into psychotic condition'),('severe-mental-illness',1,'286..','Poor insight into psychotic condition'),('severe-mental-illness',1,'8G13100','CBTp - cognitive behavioural therapy for psychosis'),('severe-mental-illness',1,'8G131','CBTp - cognitive behavioural therapy for psychosis'),('severe-mental-illness',1,'8HHs.00','Referral for minor surgery'),('severe-mental-illness',1,'8HHs.','Referral for minor surgery'),('severe-mental-illness',1,'E03y300','Unspecified puerperal psychosis'),('severe-mental-illness',1,'E03y3','Unspecified puerperal psychosis'),('severe-mental-illness',1,'E040.00','Non-alcoholic amnestic syndrome'),('severe-mental-illness',1,'E040.','Non-alcoholic amnestic syndrome'),('severe-mental-illness',1,'E040.11','Korsakoffs non-alcoholic psychosis'),('severe-mental-illness',1,'E040.','Korsakoffs non-alcoholic psychosis'),('severe-mental-illness',1,'E1...00','Non-organic psychoses'),('severe-mental-illness',1,'E1...','Non-organic psychoses'),('severe-mental-illness',1,'E10..00','Schizophrenic disorders'),('severe-mental-illness',1,'E10..','Schizophrenic disorders'),('severe-mental-illness',1,'E100.00','Simple schizophrenia'),('severe-mental-illness',1,'E100.','Simple schizophrenia'),('severe-mental-illness',1,'E100.11','Schizophrenia simplex'),('severe-mental-illness',1,'E100.','Schizophrenia simplex'),('severe-mental-illness',1,'E100000','Unspecified schizophrenia'),('severe-mental-illness',1,'E1000','Unspecified schizophrenia'),('severe-mental-illness',1,'E100100','Subchronic schizophrenia'),('severe-mental-illness',1,'E1001','Subchronic schizophrenia'),('severe-mental-illness',1,'E100200','Chronic schizophrenic'),('severe-mental-illness',1,'E1002','Chronic schizophrenic'),('severe-mental-illness',1,'E100300','Acute exacerbation of subchronic schizophrenia'),('severe-mental-illness',1,'E1003','Acute exacerbation of subchronic schizophrenia'),('severe-mental-illness',1,'E100400','Acute exacerbation of chronic schizophrenia'),('severe-mental-illness',1,'E1004','Acute exacerbation of chronic schizophrenia'),('severe-mental-illness',1,'E100500','Schizophrenia in remission'),('severe-mental-illness',1,'E1005','Schizophrenia in remission'),('severe-mental-illness',1,'E100z00','Simple schizophrenia NOS'),('severe-mental-illness',1,'E100z','Simple schizophrenia NOS'),('severe-mental-illness',1,'E101.00','Hebephrenic schizophrenia'),('severe-mental-illness',1,'E101.','Hebephrenic schizophrenia'),('severe-mental-illness',1,'E101000','Unspecified hebephrenic schizophrenia'),('severe-mental-illness',1,'E1010','Unspecified hebephrenic schizophrenia'),('severe-mental-illness',1,'E101200','Chronic hebephrenic schizophrenia'),('severe-mental-illness',1,'E1012','Chronic hebephrenic schizophrenia'),('severe-mental-illness',1,'E101400','Acute exacerbation of chronic hebephrenic schizophrenia'),('severe-mental-illness',1,'E1014','Acute exacerbation of chronic hebephrenic schizophrenia'),('severe-mental-illness',1,'E101500','Hebephrenic schizophrenia in remission'),('severe-mental-illness',1,'E1015','Hebephrenic schizophrenia in remission'),('severe-mental-illness',1,'E101z00','Hebephrenic schizophrenia NOS'),('severe-mental-illness',1,'E101z','Hebephrenic schizophrenia NOS'),('severe-mental-illness',1,'E102.00','Catatonic schizophrenia'),('severe-mental-illness',1,'E102.','Catatonic schizophrenia'),('severe-mental-illness',1,'E102000','Unspecified catatonic schizophrenia'),('severe-mental-illness',1,'E1020','Unspecified catatonic schizophrenia'),('severe-mental-illness',1,'E102100','Subchronic catatonic schizophrenia'),('severe-mental-illness',1,'E1021','Subchronic catatonic schizophrenia'),('severe-mental-illness',1,'E102200','Chronic catatonic schizophrenia'),('severe-mental-illness',1,'E1022','Chronic catatonic schizophrenia'),('severe-mental-illness',1,'E102400','Acute exacerbation of chronic catatonic schizophrenia'),('severe-mental-illness',1,'E1024','Acute exacerbation of chronic catatonic schizophrenia'),('severe-mental-illness',1,'E102500','Catatonic schizophrenia in remission'),('severe-mental-illness',1,'E1025','Catatonic schizophrenia in remission'),('severe-mental-illness',1,'E102z00','Catatonic schizophrenia NOS'),('severe-mental-illness',1,'E102z','Catatonic schizophrenia NOS'),('severe-mental-illness',1,'E103.00','Paranoid schizophrenia'),
('severe-mental-illness',1,'E103.','Paranoid schizophrenia'),('severe-mental-illness',1,'E103000','Unspecified paranoid schizophrenia'),('severe-mental-illness',1,'E1030','Unspecified paranoid schizophrenia'),('severe-mental-illness',1,'E103100','Subchronic paranoid schizophrenia'),('severe-mental-illness',1,'E1031','Subchronic paranoid schizophrenia'),('severe-mental-illness',1,'E103200','Chronic paranoid schizophrenia'),('severe-mental-illness',1,'E1032','Chronic paranoid schizophrenia'),('severe-mental-illness',1,'E103300','Acute exacerbation of subchronic paranoid schizophrenia'),('severe-mental-illness',1,'E1033','Acute exacerbation of subchronic paranoid schizophrenia'),('severe-mental-illness',1,'E103400','Acute exacerbation of chronic paranoid schizophrenia'),('severe-mental-illness',1,'E1034','Acute exacerbation of chronic paranoid schizophrenia'),('severe-mental-illness',1,'E103500','Paranoid schizophrenia in remission'),('severe-mental-illness',1,'E1035','Paranoid schizophrenia in remission'),('severe-mental-illness',1,'E103z00','Paranoid schizophrenia NOS'),('severe-mental-illness',1,'E103z','Paranoid schizophrenia NOS'),('severe-mental-illness',1,'E104.00','Acute schizophrenic episode'),('severe-mental-illness',1,'E104.','Acute schizophrenic episode'),('severe-mental-illness',1,'E104.11','Oneirophrenia'),('severe-mental-illness',1,'E104.','Oneirophrenia'),('severe-mental-illness',1,'E105.00','Latent schizophrenia'),('severe-mental-illness',1,'E105.','Latent schizophrenia'),('severe-mental-illness',1,'E105000','Unspecified latent schizophrenia'),('severe-mental-illness',1,'E1050','Unspecified latent schizophrenia'),('severe-mental-illness',1,'E105200','Chronic latent schizophrenia'),('severe-mental-illness',1,'E1052','Chronic latent schizophrenia'),('severe-mental-illness',1,'E105400','Acute exacerbation of chronic latent schizophrenia'),('severe-mental-illness',1,'E1054','Acute exacerbation of chronic latent schizophrenia'),('severe-mental-illness',1,'E105500','Latent schizophrenia in remission'),('severe-mental-illness',1,'E1055','Latent schizophrenia in remission'),('severe-mental-illness',1,'E105z00','Latent schizophrenia NOS'),('severe-mental-illness',1,'E105z','Latent schizophrenia NOS'),('severe-mental-illness',1,'E106.00','Residual schizophrenia'),('severe-mental-illness',1,'E106.','Residual schizophrenia'),('severe-mental-illness',1,'E107.00','Schizo-affective schizophrenia'),('severe-mental-illness',1,'E107.','Schizo-affective schizophrenia'),('severe-mental-illness',1,'E107.11','Cyclic schizophrenia'),('severe-mental-illness',1,'E107.','Cyclic schizophrenia'),('severe-mental-illness',1,'E107000','Unspecified schizo-affective schizophrenia'),('severe-mental-illness',1,'E1070','Unspecified schizo-affective schizophrenia'),('severe-mental-illness',1,'E107100','Subchronic schizo-affective schizophrenia'),('severe-mental-illness',1,'E1071','Subchronic schizo-affective schizophrenia'),('severe-mental-illness',1,'E107200','Chronic schizo-affective schizophrenia'),('severe-mental-illness',1,'E1072','Chronic schizo-affective schizophrenia'),('severe-mental-illness',1,'E107300','Acute exacerbation of subchronic schizo-affective schizophrenia'),('severe-mental-illness',1,'E1073','Acute exacerbation of subchronic schizo-affective schizophrenia'),('severe-mental-illness',1,'E107400','Acute exacerbation of chronic schizo-affective schizophrenia'),('severe-mental-illness',1,'E1074','Acute exacerbation of chronic schizo-affective schizophrenia'),('severe-mental-illness',1,'E107500','Schizo-affective schizophrenia in remission'),('severe-mental-illness',1,'E1075','Schizo-affective schizophrenia in remission'),('severe-mental-illness',1,'E107z00','Schizo-affective schizophrenia NOS'),('severe-mental-illness',1,'E107z','Schizo-affective schizophrenia NOS'),('severe-mental-illness',1,'E10y.00','Other schizophrenia'),('severe-mental-illness',1,'E10y.','Other schizophrenia'),('severe-mental-illness',1,'E10y.11','Cenesthopathic schizophrenia'),('severe-mental-illness',1,'E10y.','Cenesthopathic schizophrenia'),('severe-mental-illness',1,'E10y000','Atypical schizophrenia'),('severe-mental-illness',1,'E10y0','Atypical schizophrenia'),('severe-mental-illness',1,'E10y100','Coenesthopathic schizophrenia'),('severe-mental-illness',1,'E10y1','Coenesthopathic schizophrenia'),('severe-mental-illness',1,'E10yz00','Other schizophrenia NOS'),('severe-mental-illness',1,'E10yz','Other schizophrenia NOS'),('severe-mental-illness',1,'E10z.00','Schizophrenia NOS'),('severe-mental-illness',1,'E10z.','Schizophrenia NOS'),('severe-mental-illness',1,'E11..00','Affective psychoses'),('severe-mental-illness',1,'E11..','Affective psychoses'),('severe-mental-illness',1,'E11z.00','Other and unspecified affective psychoses'),('severe-mental-illness',1,'E11z.','Other and unspecified affective psychoses'),('severe-mental-illness',1,'E11z000','Unspecified affective psychoses NOS'),('severe-mental-illness',1,'E11z0','Unspecified affective psychoses NOS'),('severe-mental-illness',1,'E11zz00','Other affective psychosis NOS'),('severe-mental-illness',1,'E11zz','Other affective psychosis NOS'),('severe-mental-illness',1,'E12..00','Paranoid states'),('severe-mental-illness',1,'E12..','Paranoid states'),('severe-mental-illness',1,'E120.00','Simple paranoid state'),('severe-mental-illness',1,'E120.','Simple paranoid state'),('severe-mental-illness',1,'E121.00','Chronic paranoid psychosis'),('severe-mental-illness',1,'E121.','Chronic paranoid psychosis'),('severe-mental-illness',1,'E121.11','Sanders disease'),('severe-mental-illness',1,'E121.','Sanders disease'),('severe-mental-illness',1,'E122.00','Paraphrenia'),('severe-mental-illness',1,'E122.','Paraphrenia'),('severe-mental-illness',1,'E123.00','Shared paranoid disorder'),('severe-mental-illness',1,'E123.','Shared paranoid disorder'),('severe-mental-illness',1,'E123.11','Folie a deux'),('severe-mental-illness',1,'E123.','Folie a deux'),('severe-mental-illness',1,'E12y.00','Other paranoid states'),('severe-mental-illness',1,'E12y.','Other paranoid states'),('severe-mental-illness',1,'E12y000','Paranoia querulans'),('severe-mental-illness',1,'E12y0','Paranoia querulans'),('severe-mental-illness',1,'E12yz00','Other paranoid states NOS'),('severe-mental-illness',1,'E12yz','Other paranoid states NOS'),('severe-mental-illness',1,'E12z.00','Paranoid psychosis NOS'),('severe-mental-illness',1,'E12z.','Paranoid psychosis NOS'),('severe-mental-illness',1,'E13..00','Other nonorganic psychoses'),('severe-mental-illness',1,'E13..','Other nonorganic psychoses'),('severe-mental-illness',1,'E13..11','Reactive psychoses'),('severe-mental-illness',1,'E13..','Reactive psychoses'),('severe-mental-illness',1,'E131.00','Acute hysterical psychosis'),('severe-mental-illness',1,'E131.','Acute hysterical psychosis'),('severe-mental-illness',1,'E132.00','Reactive confusion'),('severe-mental-illness',1,'E132.','Reactive confusion'),('severe-mental-illness',1,'E133.00','Acute paranoid reaction'),('severe-mental-illness',1,'E133.','Acute paranoid reaction'),('severe-mental-illness',1,'E133.11','Bouffee delirante'),('severe-mental-illness',1,'E133.','Bouffee delirante'),('severe-mental-illness',1,'E134.00','Psychogenic paranoid psychosis'),('severe-mental-illness',1,'E134.','Psychogenic paranoid psychosis'),('severe-mental-illness',1,'E13y.00','Other reactive psychoses'),('severe-mental-illness',1,'E13y.','Other reactive psychoses'),('severe-mental-illness',1,'E13y000','Psychogenic stupor'),('severe-mental-illness',1,'E13y0','Psychogenic stupor'),('severe-mental-illness',1,'E13y100','Brief reactive psychosis'),('severe-mental-illness',1,'E13y1','Brief reactive psychosis'),('severe-mental-illness',1,'E13yz00','Other reactive psychoses NOS'),('severe-mental-illness',1,'E13yz','Other reactive psychoses NOS'),('severe-mental-illness',1,'E13z.00','Nonorganic psychosis NOS'),('severe-mental-illness',1,'E13z.','Nonorganic psychosis NOS'),('severe-mental-illness',1,'E13z.11','Psychotic episode NOS'),('severe-mental-illness',1,'E13z.','Psychotic episode NOS'),('severe-mental-illness',1,'E14..00','Psychoses with origin in childhood'),('severe-mental-illness',1,'E14..','Psychoses with origin in childhood'),('severe-mental-illness',1,'E141.00','Disintegrative psychosis'),('severe-mental-illness',1,'E141.','Disintegrative psychosis'),('severe-mental-illness',1,'E141.11','Hellers syndrome'),('severe-mental-illness',1,'E141.','Hellers syndrome'),('severe-mental-illness',1,'E141100','Residual disintegrative psychoses'),('severe-mental-illness',1,'E1411','Residual disintegrative psychoses'),('severe-mental-illness',1,'E14y.00','Other childhood psychoses'),('severe-mental-illness',1,'E14y.','Other childhood psychoses'),('severe-mental-illness',1,'E14y000','Atypical childhood psychoses'),('severe-mental-illness',1,'E14y0','Atypical childhood psychoses'),('severe-mental-illness',1,'E14y100','Borderline psychosis of childhood'),('severe-mental-illness',1,'E14y1','Borderline psychosis of childhood'),('severe-mental-illness',1,'E14yz00','Other childhood psychoses NOS'),('severe-mental-illness',1,'E14yz','Other childhood psychoses NOS'),('severe-mental-illness',1,'E14z.00','Child psychosis NOS'),('severe-mental-illness',1,'E14z.','Child psychosis NOS'),('severe-mental-illness',1,'E14z.11','Childhood schizophrenia NOS'),('severe-mental-illness',1,'E14z.','Childhood schizophrenia NOS'),('severe-mental-illness',1,'E1y..00','Other specified non-organic psychoses'),('severe-mental-illness',1,'E1y..','Other specified non-organic psychoses'),('severe-mental-illness',1,'E1z..00','Non-organic psychosis NOS'),('severe-mental-illness',1,'E1z..','Non-organic psychosis NOS'),('severe-mental-illness',1,'E210.00','Paranoid personality disorder'),('severe-mental-illness',1,'E210.','Paranoid personality disorder'),('severe-mental-illness',1,'E212.00','Schizoid personality disorder'),
('severe-mental-illness',1,'E212.','Schizoid personality disorder'),('severe-mental-illness',1,'E212000','Unspecified schizoid personality disorder'),('severe-mental-illness',1,'E2120','Unspecified schizoid personality disorder'),('severe-mental-illness',1,'E212200','Schizotypal personality'),('severe-mental-illness',1,'E2122','Schizotypal personality'),('severe-mental-illness',1,'E212z00','Schizoid personality disorder NOS'),('severe-mental-illness',1,'E212z','Schizoid personality disorder NOS'),('severe-mental-illness',1,'Eu03.11','[X]Korsakovs psychosis, nonalcoholic'),('severe-mental-illness',1,'Eu03.','[X]Korsakovs psychosis, nonalcoholic'),('severe-mental-illness',1,'Eu04.00','[X]Delirium, not induced by alcohol and other psychoactive subs'),('severe-mental-illness',1,'Eu04.','[X]Delirium, not induced by alcohol and other psychoactive subs'),('severe-mental-illness',1,'Eu04.11','[X]Acute / subacute brain syndrome'),('severe-mental-illness',1,'Eu04.','[X]Acute / subacute brain syndrome'),('severe-mental-illness',1,'Eu04.12','[X]Acute / subacute confusional state, nonalcoholic'),('severe-mental-illness',1,'Eu04.','[X]Acute / subacute confusional state, nonalcoholic'),('severe-mental-illness',1,'Eu04.13','[X]Acute / subacute infective psychosis'),('severe-mental-illness',1,'Eu04.','[X]Acute / subacute infective psychosis'),('severe-mental-illness',1,'Eu05212','[X]Schizophrenia-like psychosis in epilepsy'),('severe-mental-illness',1,'Eu052','[X]Schizophrenia-like psychosis in epilepsy'),('severe-mental-illness',1,'Eu05y11','[X]Epileptic psychosis NOS'),('severe-mental-illness',1,'Eu05y','[X]Epileptic psychosis NOS'),('severe-mental-illness',1,'Eu0z.12','[X]Symptomatic psychosis NOS'),('severe-mental-illness',1,'Eu0z.','[X]Symptomatic psychosis NOS'),('severe-mental-illness',1,'Eu2..00','[X]Schizophrenia, schizotypal and delusional disorders'),('severe-mental-illness',1,'Eu2..','[X]Schizophrenia, schizotypal and delusional disorders'),('severe-mental-illness',1,'Eu20.00','[X]Schizophrenia'),('severe-mental-illness',1,'Eu20.','[X]Schizophrenia'),('severe-mental-illness',1,'Eu20000','[X]Paranoid schizophrenia'),('severe-mental-illness',1,'Eu200','[X]Paranoid schizophrenia'),('severe-mental-illness',1,'Eu20011','[X]Paraphrenic schizophrenia'),('severe-mental-illness',1,'Eu200','[X]Paraphrenic schizophrenia'),('severe-mental-illness',1,'Eu20100','[X]Hebephrenic schizophrenia'),('severe-mental-illness',1,'Eu201','[X]Hebephrenic schizophrenia'),('severe-mental-illness',1,'Eu20111','[X]Disorganised schizophrenia'),('severe-mental-illness',1,'Eu201','[X]Disorganised schizophrenia'),('severe-mental-illness',1,'Eu20200','[X]Catatonic schizophrenia'),('severe-mental-illness',1,'Eu202','[X]Catatonic schizophrenia'),('severe-mental-illness',1,'Eu20211','[X]Catatonic stupor'),('severe-mental-illness',1,'Eu202','[X]Catatonic stupor'),('severe-mental-illness',1,'Eu20212','[X]Schizophrenic catalepsy'),('severe-mental-illness',1,'Eu202','[X]Schizophrenic catalepsy'),('severe-mental-illness',1,'Eu20213','[X]Schizophrenic catatonia'),('severe-mental-illness',1,'Eu202','[X]Schizophrenic catatonia'),('severe-mental-illness',1,'Eu20214','[X]Schizophrenic flexibilatis cerea'),('severe-mental-illness',1,'Eu202','[X]Schizophrenic flexibilatis cerea'),('severe-mental-illness',1,'Eu20300','[X]Undifferentiated schizophrenia'),('severe-mental-illness',1,'Eu203','[X]Undifferentiated schizophrenia'),('severe-mental-illness',1,'Eu20311','[X]Atypical schizophrenia'),('severe-mental-illness',1,'Eu203','[X]Atypical schizophrenia'),('severe-mental-illness',1,'Eu20400','[X]Post-schizophrenic depression'),('severe-mental-illness',1,'Eu204','[X]Post-schizophrenic depression'),('severe-mental-illness',1,'Eu20500','[X]Residual schizophrenia'),('severe-mental-illness',1,'Eu205','[X]Residual schizophrenia'),('severe-mental-illness',1,'Eu20511','[X]Chronic undifferentiated schizophrenia'),('severe-mental-illness',1,'Eu205','[X]Chronic undifferentiated schizophrenia'),('severe-mental-illness',1,'Eu20600','[X]Simple schizophrenia'),('severe-mental-illness',1,'Eu206','[X]Simple schizophrenia'),('severe-mental-illness',1,'Eu20y00','[X]Other schizophrenia'),('severe-mental-illness',1,'Eu20y','[X]Other schizophrenia'),('severe-mental-illness',1,'Eu20y12','[X]Schizophreniform disord NOS'),('severe-mental-illness',1,'Eu20y','[X]Schizophreniform disord NOS'),('severe-mental-illness',1,'Eu20y13','[X]Schizophrenifrm psychos NOS'),('severe-mental-illness',1,'Eu20y','[X]Schizophrenifrm psychos NOS'),('severe-mental-illness',1,'Eu20z00','[X]Schizophrenia, unspecified'),('severe-mental-illness',1,'Eu20z','[X]Schizophrenia, unspecified'),('severe-mental-illness',1,'Eu21.00','[X]Schizotypal disorder'),('severe-mental-illness',1,'Eu21.','[X]Schizotypal disorder'),('severe-mental-illness',1,'Eu21.11','[X]Latent schizophrenic reaction'),('severe-mental-illness',1,'Eu21.','[X]Latent schizophrenic reaction'),('severe-mental-illness',1,'Eu21.12','[X]Borderline schizophrenia'),('severe-mental-illness',1,'Eu21.','[X]Borderline schizophrenia'),('severe-mental-illness',1,'Eu21.13','[X]Latent schizophrenia'),('severe-mental-illness',1,'Eu21.','[X]Latent schizophrenia'),('severe-mental-illness',1,'Eu21.14','[X]Prepsychotic schizophrenia'),('severe-mental-illness',1,'Eu21.','[X]Prepsychotic schizophrenia'),('severe-mental-illness',1,'Eu21.15','[X]Prodromal schizophrenia'),('severe-mental-illness',1,'Eu21.','[X]Prodromal schizophrenia'),('severe-mental-illness',1,'Eu21.16','[X]Pseudoneurotic schizophrenia'),('severe-mental-illness',1,'Eu21.','[X]Pseudoneurotic schizophrenia'),('severe-mental-illness',1,'Eu21.17','[X]Pseudopsychopathic schizophrenia'),('severe-mental-illness',1,'Eu21.','[X]Pseudopsychopathic schizophrenia'),('severe-mental-illness',1,'Eu21.18','[X]Schizotypal personality disorder'),('severe-mental-illness',1,'Eu21.','[X]Schizotypal personality disorder'),('severe-mental-illness',1,'Eu22.00','[X]Persistent delusional disorders'),('severe-mental-illness',1,'Eu22.','[X]Persistent delusional disorders'),('severe-mental-illness',1,'Eu22000','[X]Delusional disorder'),('severe-mental-illness',1,'Eu220','[X]Delusional disorder'),('severe-mental-illness',1,'Eu22011','[X]Paranoid psychosis'),('severe-mental-illness',1,'Eu220','[X]Paranoid psychosis'),('severe-mental-illness',1,'Eu22012','[X]Paranoid state'),('severe-mental-illness',1,'Eu220','[X]Paranoid state'),('severe-mental-illness',1,'Eu22013','[X]Paraphrenia - late'),('severe-mental-illness',1,'Eu220','[X]Paraphrenia - late'),('severe-mental-illness',1,'Eu22014','[X]Sensitiver Beziehungswahn'),('severe-mental-illness',1,'Eu220','[X]Sensitiver Beziehungswahn'),('severe-mental-illness',1,'Eu22015','[X]Paranoia'),('severe-mental-illness',1,'Eu220','[X]Paranoia'),('severe-mental-illness',1,'Eu22100','[X]Delusional misidentification syndrome'),('severe-mental-illness',1,'Eu221','[X]Delusional misidentification syndrome'),('severe-mental-illness',1,'Eu22111','[X]Capgras syndrome'),('severe-mental-illness',1,'Eu221','[X]Capgras syndrome'),('severe-mental-illness',1,'Eu22200','[X]Cotard syndrome'),('severe-mental-illness',1,'Eu222','[X]Cotard syndrome'),('severe-mental-illness',1,'Eu22300','[X]Paranoid state in remission'),('severe-mental-illness',1,'Eu223','[X]Paranoid state in remission'),('severe-mental-illness',1,'Eu22y00','[X]Other persistent delusional disorders'),('severe-mental-illness',1,'Eu22y','[X]Other persistent delusional disorders'),('severe-mental-illness',1,'Eu22y12','[X]Involutional paranoid state'),('severe-mental-illness',1,'Eu22y','[X]Involutional paranoid state'),('severe-mental-illness',1,'Eu22y13','[X]Paranoia querulans'),('severe-mental-illness',1,'Eu22y','[X]Paranoia querulans'),('severe-mental-illness',1,'Eu22z00','[X]Persistent delusional disorder, unspecified'),('severe-mental-illness',1,'Eu22z','[X]Persistent delusional disorder, unspecified'),('severe-mental-illness',1,'Eu23000','[X]Acute polymorphic psychotic disorder without symptoms of schizophrenia'),('severe-mental-illness',1,'Eu230','[X]Acute polymorphic psychotic disorder without symptoms of schizophrenia'),('severe-mental-illness',1,'Eu23011','[X]Bouffee delirante'),('severe-mental-illness',1,'Eu230','[X]Bouffee delirante'),('severe-mental-illness',1,'Eu23012','[X]Cycloid psychosis'),('severe-mental-illness',1,'Eu230','[X]Cycloid psychosis'),('severe-mental-illness',1,'Eu23100','[X]Acute polymorphic psychotic disorder with symptoms of schizophrenia'),('severe-mental-illness',1,'Eu231','[X]Acute polymorphic psychotic disorder with symptoms of schizophrenia'),('severe-mental-illness',1,'Eu23112','[X]Cycloid psychosis with symptoms of schizophrenia'),('severe-mental-illness',1,'Eu231','[X]Cycloid psychosis with symptoms of schizophrenia'),('severe-mental-illness',1,'Eu23200','[X]Acute schizophrenia-like psychotic disorder'),('severe-mental-illness',1,'Eu232','[X]Acute schizophrenia-like psychotic disorder'),('severe-mental-illness',1,'Eu23211','[X]Brief schizophreniform disorder'),('severe-mental-illness',1,'Eu232','[X]Brief schizophreniform disorder'),('severe-mental-illness',1,'Eu23212','[X]Brief schizophrenifrm psych'),('severe-mental-illness',1,'Eu232','[X]Brief schizophrenifrm psych'),('severe-mental-illness',1,'Eu23214','[X]Schizophrenic reaction'),('severe-mental-illness',1,'Eu232','[X]Schizophrenic reaction'),('severe-mental-illness',1,'Eu23300','[X]Other acute predominantly delusional psychotic disorders'),('severe-mental-illness',1,'Eu233','[X]Other acute predominantly delusional psychotic disorders'),('severe-mental-illness',1,'Eu23312','[X]Psychogenic paranoid psychosis'),('severe-mental-illness',1,'Eu233','[X]Psychogenic paranoid psychosis'),('severe-mental-illness',1,'Eu23z11','[X]Brief reactive psychosis NOS'),('severe-mental-illness',1,'Eu23z','[X]Brief reactive psychosis NOS'),('severe-mental-illness',1,'Eu23z12','[X]Reactive psychosis'),
('severe-mental-illness',1,'Eu23z','[X]Reactive psychosis'),('severe-mental-illness',1,'Eu24.11','[X]Folie a deux'),('severe-mental-illness',1,'Eu24.','[X]Folie a deux'),('severe-mental-illness',1,'Eu25.00','[X]Schizoaffective disorders'),('severe-mental-illness',1,'Eu25.','[X]Schizoaffective disorders'),('severe-mental-illness',1,'Eu25000','[X]Schizoaffective disorder, manic type'),('severe-mental-illness',1,'Eu250','[X]Schizoaffective disorder, manic type'),('severe-mental-illness',1,'Eu25011','[X]Schizoaffective psychosis, manic type'),('severe-mental-illness',1,'Eu250','[X]Schizoaffective psychosis, manic type'),('severe-mental-illness',1,'Eu25012','[X]Schizophreniform psychosis, manic type'),('severe-mental-illness',1,'Eu250','[X]Schizophreniform psychosis, manic type'),('severe-mental-illness',1,'Eu25100','[X]Schizoaffective disorder, depressive type'),('severe-mental-illness',1,'Eu251','[X]Schizoaffective disorder, depressive type'),('severe-mental-illness',1,'Eu25111','[X]Schizoaffective psychosis, depressive type'),('severe-mental-illness',1,'Eu251','[X]Schizoaffective psychosis, depressive type'),('severe-mental-illness',1,'Eu25112','[X]Schizophreniform psychosis, depressive type'),('severe-mental-illness',1,'Eu251','[X]Schizophreniform psychosis, depressive type'),('severe-mental-illness',1,'Eu25200','[X]Schizoaffective disorder, mixed type'),('severe-mental-illness',1,'Eu252','[X]Schizoaffective disorder, mixed type'),('severe-mental-illness',1,'Eu25211','[X]Cyclic schizophrenia'),('severe-mental-illness',1,'Eu252','[X]Cyclic schizophrenia'),('severe-mental-illness',1,'Eu25212','[X]Mixed schizophrenic and affective psychosis'),('severe-mental-illness',1,'Eu252','[X]Mixed schizophrenic and affective psychosis'),('severe-mental-illness',1,'Eu25y00','[X]Other schizoaffective disorders'),('severe-mental-illness',1,'Eu25y','[X]Other schizoaffective disorders'),('severe-mental-illness',1,'Eu25z00','[X]Schizoaffective disorder, unspecified'),('severe-mental-illness',1,'Eu25z','[X]Schizoaffective disorder, unspecified'),('severe-mental-illness',1,'Eu25z11','[X]Schizoaffective psychosis NOS'),('severe-mental-illness',1,'Eu25z','[X]Schizoaffective psychosis NOS'),('severe-mental-illness',1,'Eu26.00','[X]Nonorganic psychosis in remission'),('severe-mental-illness',1,'Eu26.','[X]Nonorganic psychosis in remission'),('severe-mental-illness',1,'Eu2y.00','[X]Other nonorganic psychotic disorders'),('severe-mental-illness',1,'Eu2y.','[X]Other nonorganic psychotic disorders'),('severe-mental-illness',1,'Eu2y.11','[X]Chronic hallucinatory psychosis'),('severe-mental-illness',1,'Eu2y.','[X]Chronic hallucinatory psychosis'),('severe-mental-illness',1,'Eu2z.00','[X]Unspecified nonorganic psychosis'),('severe-mental-illness',1,'Eu2z.','[X]Unspecified nonorganic psychosis'),('severe-mental-illness',1,'Eu2z.11','[X]Psychosis NOS'),('severe-mental-illness',1,'Eu2z.','[X]Psychosis NOS'),('severe-mental-illness',1,'Eu3z.11','[X]Affective psychosis NOS'),('severe-mental-illness',1,'Eu3z.','[X]Affective psychosis NOS'),('severe-mental-illness',1,'Eu44.11','[X]Conversion hysteria'),('severe-mental-illness',1,'Eu44.','[X]Conversion hysteria'),('severe-mental-illness',1,'Eu44.13','[X]Hysteria'),('severe-mental-illness',1,'Eu44.','[X]Hysteria'),('severe-mental-illness',1,'Eu44.14','[X]Hysterical psychosis'),('severe-mental-illness',1,'Eu44.','[X]Hysterical psychosis'),('severe-mental-illness',1,'Eu53111','[X]Puerperal psychosis NOS'),('severe-mental-illness',1,'Eu531','[X]Puerperal psychosis NOS'),('severe-mental-illness',1,'Eu60000','[X]Paranoid personality disorder'),('severe-mental-illness',1,'Eu600','[X]Paranoid personality disorder'),('severe-mental-illness',1,'Eu60011','[X]Expansive paranoid personality disorder'),('severe-mental-illness',1,'Eu600','[X]Expansive paranoid personality disorder'),('severe-mental-illness',1,'Eu60014','[X]Sensitive paranoid personality disorder'),('severe-mental-illness',1,'Eu600','[X]Sensitive paranoid personality disorder'),('severe-mental-illness',1,'Eu60100','[X]Schizoid personality disorder'),('severe-mental-illness',1,'Eu601','[X]Schizoid personality disorder'),('severe-mental-illness',1,'Eu84013','[X]Infantile psychosis'),('severe-mental-illness',1,'Eu840','[X]Infantile psychosis'),('severe-mental-illness',1,'Eu84111','[X]Atypical childhood psychosis'),('severe-mental-illness',1,'Eu841','[X]Atypical childhood psychosis'),('severe-mental-illness',1,'Eu84312','[X]Disintegrative psychosis'),('severe-mental-illness',1,'Eu843','[X]Disintegrative psychosis'),('severe-mental-illness',1,'Eu84313','[X]Hellers syndrome'),('severe-mental-illness',1,'Eu843','[X]Hellers syndrome'),('severe-mental-illness',1,'Eu84314','[X]Symbiotic psychosis'),('severe-mental-illness',1,'Eu843','[X]Symbiotic psychosis'),('severe-mental-illness',1,'Eu84512','[X]Schizoid disorder of childhood'),('severe-mental-illness',1,'Eu845','[X]Schizoid disorder of childhood'),('severe-mental-illness',1,'ZV11000','[V]Personal history of schizophrenia'),('severe-mental-illness',1,'ZV110','[V]Personal history of schizophrenia'),('severe-mental-illness',1,'9H8..00','On severe mental illness register'),('severe-mental-illness',1,'9H8..','On severe mental illness register'),('severe-mental-illness',1,'E0...00','Organic psychotic conditions'),('severe-mental-illness',1,'E0...','Organic psychotic conditions'),('severe-mental-illness',1,'E00..00','Senile and presenile organic psychotic conditions'),('severe-mental-illness',1,'E00..','Senile and presenile organic psychotic conditions'),('severe-mental-illness',1,'E00y.00','Other senile and presenile organic psychoses'),('severe-mental-illness',1,'E00y.','Other senile and presenile organic psychoses'),('severe-mental-illness',1,'E00z.00','Senile or presenile psychoses NOS'),('severe-mental-illness',1,'E00z.','Senile or presenile psychoses NOS'),('severe-mental-illness',1,'E010.00','Delirium tremens'),('severe-mental-illness',1,'E010.','Delirium tremens'),('severe-mental-illness',1,'E011.00','Alcohol amnestic syndrome'),('severe-mental-illness',1,'E011.','Alcohol amnestic syndrome'),('severe-mental-illness',1,'E011000','Korsakovs alcoholic psychosis'),('severe-mental-illness',1,'E0110','Korsakovs alcoholic psychosis'),('severe-mental-illness',1,'E011100','Korsakovs alcoholic psychosis with peripheral neuritis'),('severe-mental-illness',1,'E0111','Korsakovs alcoholic psychosis with peripheral neuritis'),('severe-mental-illness',1,'E011200','Wernicke-Korsakov syndrome'),('severe-mental-illness',1,'E0112','Wernicke-Korsakov syndrome'),('severe-mental-illness',1,'E012.00','Alcoholic dementia NOS'),('severe-mental-illness',1,'E012.','Alcoholic dementia NOS'),('severe-mental-illness',1,'E02..00','Drug psychoses'),('severe-mental-illness',1,'E02..','Drug psychoses'),('severe-mental-illness',1,'E021.00','Drug-induced paranoia or hallucinatory states'),('severe-mental-illness',1,'E021.','Drug-induced paranoia or hallucinatory states'),('severe-mental-illness',1,'E021000','Drug-induced paranoid state'),('severe-mental-illness',1,'E0210','Drug-induced paranoid state'),('severe-mental-illness',1,'E021100','Drug-induced hallucinosis'),('severe-mental-illness',1,'E0211','Drug-induced hallucinosis'),('severe-mental-illness',1,'E021z00','Drug-induced paranoia or hallucinatory state NOS'),('severe-mental-illness',1,'E021z','Drug-induced paranoia or hallucinatory state NOS'),('severe-mental-illness',1,'E02y.00','Other drug psychoses'),('severe-mental-illness',1,'E02y.','Other drug psychoses'),('severe-mental-illness',1,'E02y000','Drug-induced delirium'),('severe-mental-illness',1,'E02y0','Drug-induced delirium'),('severe-mental-illness',1,'E02y300','Drug-induced depressive state'),('severe-mental-illness',1,'E02y3','Drug-induced depressive state'),('severe-mental-illness',1,'E02y400','Drug-induced personality disorder'),('severe-mental-illness',1,'E02y4','Drug-induced personality disorder'),('severe-mental-illness',1,'E02z.00','Drug psychosis NOS'),('severe-mental-illness',1,'E02z.','Drug psychosis NOS'),('severe-mental-illness',1,'E03..00','Transient organic psychoses'),('severe-mental-illness',1,'E03..','Transient organic psychoses'),('severe-mental-illness',1,'E03y.00','Other transient organic psychoses'),('severe-mental-illness',1,'E03y.','Other transient organic psychoses'),('severe-mental-illness',1,'E03z.00','Transient organic psychoses NOS'),('severe-mental-illness',1,'E03z.','Transient organic psychoses NOS'),('severe-mental-illness',1,'E04..00','Other chronic organic psychoses'),('severe-mental-illness',1,'E04..','Other chronic organic psychoses'),('severe-mental-illness',1,'E04y.00','Other specified chronic organic psychoses'),('severe-mental-illness',1,'E04y.','Other specified chronic organic psychoses'),('severe-mental-illness',1,'E04z.00','Chronic organic psychosis NOS'),('severe-mental-illness',1,'E04z.','Chronic organic psychosis NOS'),('severe-mental-illness',1,'E0y..00','Other specified organic psychoses'),('severe-mental-illness',1,'E0y..','Other specified organic psychoses'),('severe-mental-illness',1,'E0z..00','Organic psychoses NOS'),('severe-mental-illness',1,'E0z..','Organic psychoses NOS'),('severe-mental-illness',1,'E112400','Single major depressive episode, severe, with psychosis'),('severe-mental-illness',1,'E1124','Single major depressive episode, severe, with psychosis'),('severe-mental-illness',1,'E113400','Recurrent major depressive episodes, severe, with psychosis'),('severe-mental-illness',1,'E1134','Recurrent major depressive episodes, severe, with psychosis'),('severe-mental-illness',1,'E211.00','Affective personality disorder'),('severe-mental-illness',1,'E211.','Affective personality disorder'),('severe-mental-illness',1,'E211000','Unspecified affective personality disorder'),('severe-mental-illness',1,'E2110','Unspecified affective personality disorder'),('severe-mental-illness',1,'E211300','Cyclothymic personality disorder'),
('severe-mental-illness',1,'E2113','Cyclothymic personality disorder'),('severe-mental-illness',1,'E211z00','Affective personality disorder NOS'),('severe-mental-illness',1,'E211z','Affective personality disorder NOS'),('severe-mental-illness',1,'Eu02z00','[X] Presenile dementia NOS'),('severe-mental-illness',1,'Eu02z','[X] Presenile dementia NOS'),('severe-mental-illness',1,'Eu10400','[X]Mental and behavioural disorders due to use of alcohol: withdrawal state with delirium'),('severe-mental-illness',1,'Eu104','[X]Mental and behavioural disorders due to use of alcohol: withdrawal state with delirium'),('severe-mental-illness',1,'Eu10600','[X]Korsakovs psychosis, alcohol induced'),('severe-mental-illness',1,'Eu106','[X]Korsakovs psychosis, alcohol induced'),('severe-mental-illness',1,'Eu10700','[X]Mental and behavioural disorders due to use of alcohol: residual and late-onset psychotic disorder'),('severe-mental-illness',1,'Eu107','[X]Mental and behavioural disorders due to use of alcohol: residual and late-onset psychotic disorder'),('severe-mental-illness',1,'Eu11500','[X]Mental and behavioural disorders due to use of opioids: psychotic disorder'),('severe-mental-illness',1,'Eu115','[X]Mental and behavioural disorders due to use of opioids: psychotic disorder'),('severe-mental-illness',1,'Eu12500','[X]Mental and behavioural disorders due to use of cannabinoids: psychotic disorder'),('severe-mental-illness',1,'Eu125','[X]Mental and behavioural disorders due to use of cannabinoids: psychotic disorder'),('severe-mental-illness',1,'Eu13500','[X]Mental and behavioural disorders due to use of sedatives or hypnotics: psychotic disorder'),('severe-mental-illness',1,'Eu135','[X]Mental and behavioural disorders due to use of sedatives or hypnotics: psychotic disorder'),('severe-mental-illness',1,'Eu14500','[X]Mental and behavioural disorders due to use of cocaine: psychotic disorder'),('severe-mental-illness',1,'Eu145','[X]Mental and behavioural disorders due to use of cocaine: psychotic disorder'),('severe-mental-illness',1,'Eu15500','[X]Mental and behavioural disorders due to use of other stimulants, including caffeine: psychotic disorder'),('severe-mental-illness',1,'Eu155','[X]Mental and behavioural disorders due to use of other stimulants, including caffeine: psychotic disorder'),('severe-mental-illness',1,'Eu19500','[X]Mental and behavioural disorders due to multiple drug use and use of other psychoactive substances: psychotic disorder'),('severe-mental-illness',1,'Eu195','[X]Mental and behavioural disorders due to multiple drug use and use of other psychoactive substances: psychotic disorder'),('severe-mental-illness',1,'Eu23.00','[X]Acute and transient psychotic disorders'),('severe-mental-illness',1,'Eu23.','[X]Acute and transient psychotic disorders'),('severe-mental-illness',1,'Eu32300','[X]Severe depressive episode with psychotic symptoms'),('severe-mental-illness',1,'Eu323','[X]Severe depressive episode with psychotic symptoms')

INSERT INTO #AllCodes
SELECT [concept], [version], [code] from #codesreadv2;

IF OBJECT_ID('tempdb..#codesctv3') IS NOT NULL DROP TABLE #codesctv3;
CREATE TABLE #codesctv3 (
  [concept] [varchar](255) NOT NULL,
  [version] INT NOT NULL,
	[code] [varchar](20) COLLATE Latin1_General_CS_AS NOT NULL,
	[description] [varchar](255) NULL
) ON [PRIMARY];

INSERT INTO #codesctv3
VALUES ('severe-mental-illness',1,'E1...','Non-organic psychoses'),('severe-mental-illness',1,'E10..','Schizophrenic disorders'),('severe-mental-illness',1,'E100.','Simple schizophrenia'),('severe-mental-illness',1,'E1000','Unspecified schizophrenia'),('severe-mental-illness',1,'E1001','Subchronic schizophrenia'),('severe-mental-illness',1,'E1002','Chronic schizophrenic'),('severe-mental-illness',1,'E1003','Acute exacerbation of subchronic schizophrenia'),('severe-mental-illness',1,'E1004','Acute exacerbation of chronic schizophrenia'),('severe-mental-illness',1,'E1005','Schizophrenia in remission'),('severe-mental-illness',1,'E100z','Simple schizophrenia NOS'),('severe-mental-illness',1,'E101.','Hebephrenic schizophrenia'),('severe-mental-illness',1,'E1010','Unspecified hebephrenic schizophrenia'),('severe-mental-illness',1,'E1011','Subchronic hebephrenic schizophrenia'),('severe-mental-illness',1,'E1012','Chronic hebephrenic schizophrenia'),('severe-mental-illness',1,'E1013','Acute exacerbation of subchronic hebephrenic schizophrenia'),('severe-mental-illness',1,'E1014','Acute exacerbation of chronic hebephrenic schizophrenia'),('severe-mental-illness',1,'E1015','Hebephrenic schizophrenia in remission'),('severe-mental-illness',1,'E101z','Hebephrenic schizophrenia NOS'),('severe-mental-illness',1,'E102.','Catatonic schizophrenia'),('severe-mental-illness',1,'E1020','Unspecified catatonic schizophrenia'),('severe-mental-illness',1,'E1021','Subchronic catatonic schizophrenia'),('severe-mental-illness',1,'E1022','Chronic catatonic schizophrenia'),('severe-mental-illness',1,'E1023','Acute exacerbation of subchronic catatonic schizophrenia'),('severe-mental-illness',1,'E1024','Acute exacerbation of chronic catatonic schizophrenia'),('severe-mental-illness',1,'E1025','Catatonic schizophrenia in remission'),('severe-mental-illness',1,'E102z','Catatonic schizophrenia NOS'),('severe-mental-illness',1,'E103.','Paranoid schizophrenia'),('severe-mental-illness',1,'E1030','Unspecified paranoid schizophrenia'),('severe-mental-illness',1,'E1031','Subchronic paranoid schizophrenia'),('severe-mental-illness',1,'E1032','Chronic paranoid schizophrenia'),('severe-mental-illness',1,'E1033','Acute exacerbation of subchronic paranoid schizophrenia'),('severe-mental-illness',1,'E1034','Acute exacerbation of chronic paranoid schizophrenia'),('severe-mental-illness',1,'E1035','Paranoid schizophrenia in remission'),('severe-mental-illness',1,'E103z','Paranoid schizophrenia NOS'),('severe-mental-illness',1,'E105.','Latent schizophrenia'),('severe-mental-illness',1,'E1050','Unspecified latent schizophrenia'),('severe-mental-illness',1,'E1051','Subchronic latent schizophrenia'),('severe-mental-illness',1,'E1052','Chronic latent schizophrenia'),('severe-mental-illness',1,'E1053','Acute exacerbation of subchronic latent schizophrenia'),('severe-mental-illness',1,'E1054','Acute exacerbation of chronic latent schizophrenia'),('severe-mental-illness',1,'E1055','Latent schizophrenia in remission'),('severe-mental-illness',1,'E105z','Latent schizophrenia NOS'),('severe-mental-illness',1,'E106.','Residual schizophrenia'),('severe-mental-illness',1,'E107.','Schizoaffective schizophrenia'),('severe-mental-illness',1,'E1070','Unspecified schizoaffective schizophrenia'),('severe-mental-illness',1,'E1071','Subchronic schizoaffective schizophrenia'),('severe-mental-illness',1,'E1072','Chronic schizoaffective schizophrenia'),('severe-mental-illness',1,'E1073','Acute exacerbation subchronic schizoaffective schizophrenia'),('severe-mental-illness',1,'E1074','Acute exacerbation of chronic schizoaffective schizophrenia'),('severe-mental-illness',1,'E1075','Schizoaffective schizophrenia in remission'),('severe-mental-illness',1,'E107z','Schizoaffective schizophrenia NOS'),('severe-mental-illness',1,'E10y.','Schizophrenia: [other] or [cenesthopathic]'),('severe-mental-illness',1,'E10y0','Atypical schizophrenia'),('severe-mental-illness',1,'E10y1','Cenesthopathic schizophrenia'),('severe-mental-illness',1,'E10yz','Other schizophrenia NOS'),('severe-mental-illness',1,'E10z.','Schizophrenia NOS'),('severe-mental-illness',1,'E1100','Single manic episode, unspecified'),('severe-mental-illness',1,'E1101','Single manic episode, mild'),('severe-mental-illness',1,'E1102','Single manic episode, moderate'),('severe-mental-illness',1,'E1103','Single manic episode, severe without mention of psychosis'),('severe-mental-illness',1,'E1104','Single manic episode, severe, with psychosis'),('severe-mental-illness',1,'E1105','Single manic episode in partial or unspecified remission'),('severe-mental-illness',1,'E1106','Single manic episode in full remission'),('severe-mental-illness',1,'E110z','Manic disorder, single episode NOS'),('severe-mental-illness',1,'E111.','Recurrent manic episodes'),('severe-mental-illness',1,'E1110','Recurrent manic episodes, unspecified'),('severe-mental-illness',1,'E1111','Recurrent manic episodes, mild'),('severe-mental-illness',1,'E1112','Recurrent manic episodes, moderate'),('severe-mental-illness',1,'E1113','Recurrent manic episodes, severe without mention psychosis'),('severe-mental-illness',1,'E1114','Recurrent manic episodes, severe, with psychosis'),('severe-mental-illness',1,'E1115','Recurrent manic episodes, partial or unspecified remission'),('severe-mental-illness',1,'E1116','Recurrent manic episodes, in full remission'),('severe-mental-illness',1,'E111z','Recurrent manic episode NOS'),('severe-mental-illness',1,'E1124','Single major depressive episode, severe, with psychosis'),('severe-mental-illness',1,'E1134','Recurrent major depressive episodes, severe, with psychosis'),('severe-mental-illness',1,'E114.','Bipolar affective disorder, current episode manic'),('severe-mental-illness',1,'E1140','Bipolar affective disorder, currently manic, unspecified'),('severe-mental-illness',1,'E1141','Bipolar affective disorder, currently manic, mild'),('severe-mental-illness',1,'E1142','Bipolar affective disorder, currently manic, moderate'),('severe-mental-illness',1,'E1143','Bipolar affect disord, currently manic, severe, no psychosis'),('severe-mental-illness',1,'E1144','Bipolar affect disord, currently manic,severe with psychosis'),('severe-mental-illness',1,'E1145','Bipolar affect disord,currently manic, part/unspec remission'),('severe-mental-illness',1,'E1146','Bipolar affective disorder, currently manic, full remission'),('severe-mental-illness',1,'E114z','Bipolar affective disorder, currently manic, NOS'),('severe-mental-illness',1,'E115.','Bipolar affective disorder, current episode depression'),('severe-mental-illness',1,'E1150','Bipolar affective disorder, currently depressed, unspecified'),('severe-mental-illness',1,'E1151','Bipolar affective disorder, currently depressed, mild'),('severe-mental-illness',1,'E1152','Bipolar affective disorder, currently depressed, moderate'),('severe-mental-illness',1,'E1153','Bipolar affect disord, now depressed, severe, no psychosis'),('severe-mental-illness',1,'E1154','Bipolar affect disord, now depressed, severe with psychosis'),('severe-mental-illness',1,'E1156','Bipolar affective disorder, now depressed, in full remission'),('severe-mental-illness',1,'E115z','Bipolar affective disorder, currently depressed, NOS'),('severe-mental-illness',1,'E116.','Mixed bipolar affective disorder'),('severe-mental-illness',1,'E1160','Mixed bipolar affective disorder, unspecified'),('severe-mental-illness',1,'E1161','Mixed bipolar affective disorder, mild'),('severe-mental-illness',1,'E1162','Mixed bipolar affective disorder, moderate'),('severe-mental-illness',1,'E1163','Mixed bipolar affective disorder, severe, without psychosis'),('severe-mental-illness',1,'E1164','Mixed bipolar affective disorder, severe, with psychosis'),('severe-mental-illness',1,'E1165','Mixed bipolar affective disorder, partial/unspec remission'),('severe-mental-illness',1,'E1166','Mixed bipolar affective disorder, in full remission'),('severe-mental-illness',1,'E116z','Mixed bipolar affective disorder, NOS'),('severe-mental-illness',1,'E117.','Unspecified bipolar affective disorder'),('severe-mental-illness',1,'E1170','Unspecified bipolar affective disorder, unspecified'),('severe-mental-illness',1,'E1171','Unspecified bipolar affective disorder, mild'),('severe-mental-illness',1,'E1172','Unspecified bipolar affective disorder, moderate'),('severe-mental-illness',1,'E1173','Unspecified bipolar affective disorder, severe, no psychosis'),('severe-mental-illness',1,'E1174','Unspecified bipolar affective disorder,severe with psychosis'),('severe-mental-illness',1,'E1176','Unspecified bipolar affective disorder, in full remission'),('severe-mental-illness',1,'E117z','Unspecified bipolar affective disorder, NOS'),('severe-mental-illness',1,'E11y.','Other and unspecified manic-depressive psychoses'),('severe-mental-illness',1,'E11y0','Unspecified manic-depressive psychoses'),('severe-mental-illness',1,'E11y1','Atypical manic disorder'),('severe-mental-illness',1,'E11y3','Other mixed manic-depressive psychoses'),('severe-mental-illness',1,'E11yz','Other and unspecified manic-depressive psychoses NOS'),('severe-mental-illness',1,'E11z.','Other and unspecified affective psychoses'),('severe-mental-illness',1,'E11z0','Unspecified affective psychoses NOS'),('severe-mental-illness',1,'E11zz','Other affective psychosis NOS'),('severe-mental-illness',1,'E120.','Simple paranoid state'),('severe-mental-illness',1,'E121.','[Chronic paranoid psychosis] or [Sanders disease]'),('severe-mental-illness',1,'E122.','Paraphrenia'),('severe-mental-illness',1,'E123.','Shared paranoid disorder'),('severe-mental-illness',1,'E12y0','Paranoia querulans'),('severe-mental-illness',1,'E13..','Psychoses: [other nonorganic] or [reactive]'),('severe-mental-illness',1,'E130.','Reactive depressive psychosis'),('severe-mental-illness',1,'E131.','Acute hysterical psychosis'),('severe-mental-illness',1,'E134.','Psychogenic paranoid psychosis'),
('severe-mental-illness',1,'E13y.','Other reactive psychoses'),('severe-mental-illness',1,'E13y0','Psychogenic stupor'),('severe-mental-illness',1,'E13y1','Brief reactive psychosis'),('severe-mental-illness',1,'E13yz','Other reactive psychoses NOS'),('severe-mental-illness',1,'E13z.','Psychosis: [nonorganic NOS] or [episode NOS]'),('severe-mental-illness',1,'E1y..','Other specified non-organic psychoses'),('severe-mental-illness',1,'E2122','Schizotypal personality disorder'),('severe-mental-illness',1,'Eu2..','[X]Schizophrenia, schizotypal and delusional disorders'),('severe-mental-illness',1,'Eu20.','Schizophrenia'),('severe-mental-illness',1,'Eu202','[X](Cat schiz)(cat stupor)(schiz catalep)(schiz flex cerea)'),('severe-mental-illness',1,'Eu203','[X]Undifferentiated schizophrenia'),('severe-mental-illness',1,'Eu20y','[X](Schizophr:[cenes][oth])(schizoform dis [& psychos] NOS)'),('severe-mental-illness',1,'Eu20z','[X]Schizophrenia, unspecified'),('severe-mental-illness',1,'Eu22y','[X](Oth pers delusion dis)(del dysm)(inv paranoid)(par quer)'),('severe-mental-illness',1,'Eu22z','[X]Persistent delusional disorder, unspecified'),('severe-mental-illness',1,'Eu230','[X]Ac polym psych dis, no schiz (& [bouf del][cycl psychos])'),('severe-mental-illness',1,'Eu231','[X]Acute polymorphic psychot disord with symp of schizophren'),('severe-mental-illness',1,'Eu232','[X]Ac schizophrenia-like psychot disord (& [named variants])'),('severe-mental-illness',1,'Eu233','[X](Oth ac delusn psychot dis) or (psychogen paran psychos)'),('severe-mental-illness',1,'Eu23y','[X]Other acute and transient psychotic disorders'),('severe-mental-illness',1,'Eu23z','[X]Ac trans psych dis, unsp (& [reac psychos (& brief NOS)])'),('severe-mental-illness',1,'Eu24.','Induced delusional disorder'),('severe-mental-illness',1,'Eu25.','Schizoaffective disorder'),('severe-mental-illness',1,'Eu252','[X](Mix schizoaff dis)(cycl schizo)(mix schiz/affect psych)'),('severe-mental-illness',1,'Eu25y','[X]Other schizoaffective disorders'),('severe-mental-illness',1,'Eu25z','[X]Schizoaffective disorder, unspecified'),('severe-mental-illness',1,'Eu2z.','[X] Psychosis: [unspecified nonorganic] or [NOS]'),('severe-mental-illness',1,'Eu30.','[X]Manic episode (& [bipolar disord, single manic episode])'),('severe-mental-illness',1,'Eu301','[X]Mania without psychotic symptoms'),('severe-mental-illness',1,'Eu302','[X](Mania+psych sym (& mood [congr][incong]))/(manic stupor)'),('severe-mental-illness',1,'Eu30y','[X]Other manic episodes'),('severe-mental-illness',1,'Eu30z','[X] Mania: [episode, unspecified] or [NOS]'),('severe-mental-illness',1,'Eu310','Bipolar affective disorder, current episode hypomanic'),('severe-mental-illness',1,'Eu311','[X]Bipolar affect disorder cur epi manic wout psychotic symp'),('severe-mental-illness',1,'Eu312','[X]Bipolar affect disorder cur epi manic with psychotic symp'),('severe-mental-illness',1,'Eu313','[X]Bipolar affect disorder cur epi mild or moderate depressn'),('severe-mental-illness',1,'Eu314','[X]Bipol aff disord, curr epis sev depress, no psychot symp'),('severe-mental-illness',1,'Eu316','Bipolar affective disorder , current episode mixed'),('severe-mental-illness',1,'Eu317','[X]Bipolar affective disorder, currently in remission'),('severe-mental-illness',1,'Eu31y','[X](Bipol affect disord:[II][other]) or (recur manic episod)'),('severe-mental-illness',1,'Eu31z','[X]Bipolar affective disorder, unspecified'),('severe-mental-illness',1,'Eu323','[X]Sev depress epis + psych symp:(& singl epis [named vars])'),('severe-mental-illness',1,'Eu333','[X]Depress with psych sympt: [recurr: (named vars)][endogen]'),('severe-mental-illness',1,'X00Qx','Psychotic episode NOS'),('severe-mental-illness',1,'X00Qy','Reactive psychoses'),('severe-mental-illness',1,'X00RU','Epileptic psychosis'),('severe-mental-illness',1,'X00S6','Psychotic disorder'),('severe-mental-illness',1,'X00S8','Post-schizophrenic depression'),('severe-mental-illness',1,'X00SA','Persistent delusional disorder'),('severe-mental-illness',1,'X00SC','Acute transient psychotic disorder'),('severe-mental-illness',1,'X00SD','Schizophreniform disorder'),('severe-mental-illness',1,'X00SJ','Mania'),('severe-mental-illness',1,'X00SK','Manic stupor'),('severe-mental-illness',1,'X00SL','Hypomania'),('severe-mental-illness',1,'X00SM','Bipolar disorder'),('severe-mental-illness',1,'X00SN','Bipolar II disorder'),('severe-mental-illness',1,'X50GE','Cutaneous monosymptomatic delusional psychosis'),('severe-mental-illness',1,'X50GF','Delusions of parasitosis'),('severe-mental-illness',1,'X50GG','Delusions of infestation'),('severe-mental-illness',1,'X50GH','Delusion of foul odour'),('severe-mental-illness',1,'X50GJ','Delusional hyperhidrosis'),('severe-mental-illness',1,'X761M','Schizophrenic prodrome'),('severe-mental-illness',1,'XE1Xw','Acute schizophrenic episode'),('severe-mental-illness',1,'XE1Xx','Other schizophrenia'),('severe-mental-illness',1,'XE1Xz','Manic disorder, single episode'),('severe-mental-illness',1,'XE1Y2','Chronic paranoid psychosis'),('severe-mental-illness',1,'XE1Y3','Other non-organic psychoses'),('severe-mental-illness',1,'XE1Y4','Acute paranoid reaction'),('severe-mental-illness',1,'XE1Y5','Non-organic psychosis NOS'),('severe-mental-illness',1,'XE1ZM','[X]Other schizophrenia'),('severe-mental-illness',1,'XE1ZN','[X]Schizotypal disorder'),('severe-mental-illness',1,'XE1ZO','Delusional disorder'),('severe-mental-illness',1,'XE1ZP','[X]Other persistent delusional disorders'),('severe-mental-illness',1,'XE1ZQ','[X]Acute polymorphic psychot disord without symp of schizoph'),('severe-mental-illness',1,'XE1ZR','[X]Other acute predominantly delusional psychotic disorders'),('severe-mental-illness',1,'XE1ZS','[X]Acute and transient psychotic disorder, unspecified'),('severe-mental-illness',1,'XE1ZT','[X]Other non-organic psychotic disorders'),('severe-mental-illness',1,'XE1ZU','[X]Unspecified nonorganic psychosis'),('severe-mental-illness',1,'XE1ZV','[X]Mania with psychotic symptoms'),('severe-mental-illness',1,'XE1ZW','[X]Manic episode, unspecified'),('severe-mental-illness',1,'XE1ZX','[X]Other bipolar affective disorders'),('severe-mental-illness',1,'XE1ZZ','[X]Severe depressive episode with psychotic symptoms'),('severe-mental-illness',1,'XE1Ze','[X]Recurrent depress disorder cur epi severe with psyc symp'),('severe-mental-illness',1,'XE1aM','Schizophrenic psychoses (& [paranoid schizophrenia])'),('severe-mental-illness',1,'XE1aU','(Paranoid states) or (delusion: [paranoid] or [persecution])'),('severe-mental-illness',1,'XE2b8','Schizoaffective disorder, mixed type'),('severe-mental-illness',1,'XE2uT','Schizoaffective disorder, manic type'),('severe-mental-illness',1,'XE2un','Schizoaffective disorder, depressive type'),('severe-mental-illness',1,'XM1GG','Borderline schizophrenia'),('severe-mental-illness',1,'XM1GH','Acute polymorphic psychotic disorder'),('severe-mental-illness',1,'XSGon','Severe major depression with psychotic features'),('severe-mental-illness',1,'Xa0lD','Involutional paranoid state'),('severe-mental-illness',1,'Xa0lF','Delusional dysmorphophobia'),('severe-mental-illness',1,'Xa0s9','Acute schizophrenia-like psychotic disorder'),('severe-mental-illness',1,'Xa0tC','Late paraphrenia'),('severe-mental-illness',1,'Xa1aD','Monosymptomatic hypochondriacal psychosis'),('severe-mental-illness',1,'Xa1aF','Erotomania'),('severe-mental-illness',1,'Xa1bS','Othello syndrome'),('severe-mental-illness',1,'XaB5u','Bouffee delirante'),('severe-mental-illness',1,'XaB5v','Cycloid psychosis'),('severe-mental-illness',1,'XaB8j','Oneirophrenia'),('severe-mental-illness',1,'XaB95','Other manic-depressive psychos'),('severe-mental-illness',1,'XaK4Y','[X]Erotomania'),('severe-mental-illness',1,'XaX52','Non-organic psychosis in remission'),('severe-mental-illness',1,'XaX53','Single major depress ep, severe with psych, psych in remissn'),('severe-mental-illness',1,'XaX54','Recurr major depress ep, severe with psych, psych in remissn'),('severe-mental-illness',1,'XaY1Y','Bipolar I disorder'),('severe-mental-illness',1,'XagU1','Recurrent reactiv depressiv episodes, severe, with psychosis'),('severe-mental-illness',1,'1464.','H/O: schizophrenia'),('severe-mental-illness',1,'665B.','Lithium stopped'),('severe-mental-illness',1,'E0...','Organic psychotic condition'),('severe-mental-illness',1,'E00..','Senile and presenile organic psychotic conditions (& dementia)'),('severe-mental-illness',1,'E00y.','(Other senile and presenile organic psychoses) or (presbyophrenic psychosis)'),('severe-mental-illness',1,'E00z.','Senile or presenile psychoses NOS'),('severe-mental-illness',1,'E010.','Delirium tremens'),('severe-mental-illness',1,'E011.','Korsakoff psychosis'),('severe-mental-illness',1,'E0111','Korsakovs alcoholic psychosis with peripheral neuritis'),('severe-mental-illness',1,'E0112','Wernicke-Korsakov syndrome'),('severe-mental-illness',1,'E012.','Alcoholic dementia NOS'),('severe-mental-illness',1,'E02..','Drug-induced psychosis'),('severe-mental-illness',1,'E021.','Drug-induced paranoia or hallucinatory states'),('severe-mental-illness',1,'E0210','Drug-induced paranoid state'),('severe-mental-illness',1,'E0211','Drug-induced hallucinosis'),('severe-mental-illness',1,'E021z','Drug-induced paranoia or hallucinatory state NOS'),('severe-mental-illness',1,'E02y.','Other drug psychoses'),('severe-mental-illness',1,'E02y0','Drug-induced delirium'),('severe-mental-illness',1,'E02y3','Drug-induced depressive state'),('severe-mental-illness',1,'E02y4','Drug-induced personality disorder'),('severe-mental-illness',1,'E02z.','Drug psychosis NOS'),('severe-mental-illness',1,'E03..','Transient organic psychoses'),('severe-mental-illness',1,'E03y.','Other transient organic psychoses'),('severe-mental-illness',1,'E03z.','Transient organic psychoses NOS'),('severe-mental-illness',1,'E04..','Other chronic organic psychoses'),
('severe-mental-illness',1,'E04y.','Other specified chronic organic psychoses'),('severe-mental-illness',1,'E04z.','Chronic organic psychosis NOS'),('severe-mental-illness',1,'E0y..','Other specified organic psychoses'),('severe-mental-illness',1,'E0z..','Organic psychoses NOS'),('severe-mental-illness',1,'E11..','Affective psychoses (& [bipolar] or [depressive] or [manic])'),('severe-mental-illness',1,'E11y2','Atypical depressive disorder'),('severe-mental-illness',1,'E11z1','Rebound mood swings'),('severe-mental-illness',1,'E12..','Paranoid disorder'),('severe-mental-illness',1,'E12y.','Other paranoid states'),('severe-mental-illness',1,'E12yz','Other paranoid states NOS'),('severe-mental-illness',1,'E12z.','Paranoid psychosis NOS'),('severe-mental-illness',1,'E141.','Childhood disintegrative disorder'),('severe-mental-illness',1,'E141z','Disintegrative psychosis NOS'),('severe-mental-illness',1,'E2110','Unspecified affective personality disorder'),('severe-mental-illness',1,'E2113','Affective personality disorder'),('severe-mental-illness',1,'E211z','Affective personality disorder NOS'),('severe-mental-illness',1,'E212.','Schizoid personality disorder'),('severe-mental-illness',1,'E2120','Unspecified schizoid personality disorder'),('severe-mental-illness',1,'E212z','Schizoid personality disorder NOS'),('severe-mental-illness',1,'Eu02z','[X] Dementia: [unspecif] or [presenile NOS (including presenile psychosis NOS)] or [primary degenerative NOS] or [senile NOS (including senile psychosis NOS)] or [senile depressed or paranoid type]'),('severe-mental-illness',1,'Eu104','[X]Mental and behavioural disorders due to use of alcohol: withdrawal state with delirium'),('severe-mental-illness',1,'Eu106','[X]Mental and behavioural disorders due to use of alcohol: amnesic syndrome'),('severe-mental-illness',1,'Eu107','[X] (Mental and behavioural disorders due to use of alcohol: residual and late-onset psychotic disorder) or (chronic alcoholic brain syndrome [& dementia NOS])'),('severe-mental-illness',1,'Eu115','[X]Mental and behavioural disorders due to use of opioids: psychotic disorder'),('severe-mental-illness',1,'Eu125','[X]Mental and behavioural disorders due to use of cannabinoids: psychotic disorder'),('severe-mental-illness',1,'Eu135','[X]Mental and behavioural disorders due to use of sedatives or hypnotics: psychotic disorder'),('severe-mental-illness',1,'Eu145','[X]Mental and behavioural disorders due to use of cocaine: psychotic disorder'),('severe-mental-illness',1,'Eu155','[X]Mental and behavioural disorders due to use of other stimulants, including caffeine: psychotic disorder'),('severe-mental-illness',1,'Eu195','[X]Mental and behavioural disorders due to multiple drug use and use of other psychoactive substances: psychotic disorder'),('severe-mental-illness',1,'Eu332','[X]Depression without psychotic symptoms: [recurrent: [major] or [manic-depressive psychosis, depressed type] or [vital] or [current severe episode]] or [endogenous]'),('severe-mental-illness',1,'Eu34.','[X]Persistent mood affective disorders'),('severe-mental-illness',1,'Eu3y.','[X]Other mood affective disorders'),('severe-mental-illness',1,'Eu3y0','[X] Mood affective disorders: [other single] or [mixed episode]'),('severe-mental-illness',1,'Eu44.','[X]Dissociative [conversion] disorders'),('severe-mental-illness',1,'X00Rk','Alcoholic dementia NOS'),('severe-mental-illness',1,'X40Do','Mild postnatal psychosis'),('severe-mental-illness',1,'X40Dp','Severe postnatal psychosis'),('severe-mental-illness',1,'Xa25J','Alcoholic dementia'),('severe-mental-illness',1,'Xa9B0','Puerperal psychosis'),('severe-mental-illness',1,'XaIWQ','On severe mental illness register'),('severe-mental-illness',1,'XE1Xr','Senile and presenile organic psychotic conditions'),('severe-mental-illness',1,'XE1Xt','Other senile and presenile organic psychoses'),('severe-mental-illness',1,'XE1Xu','Other alcoholic dementia'),('severe-mental-illness',1,'ZV110','[V]Personal history of schizophrenia'),('severe-mental-illness',1,'ZV111','[V]Personal history of affective disorder')

INSERT INTO #AllCodes
SELECT [concept], [version], [code] from #codesctv3;

IF OBJECT_ID('tempdb..#codessnomed') IS NOT NULL DROP TABLE #codessnomed;
CREATE TABLE #codessnomed (
  [concept] [varchar](255) NOT NULL,
  [version] INT NOT NULL,
	[code] [varchar](20) COLLATE Latin1_General_CS_AS NOT NULL,
	[description] [varchar](255) NULL
) ON [PRIMARY];

INSERT INTO #codessnomed
VALUES ('severe-mental-illness',1,'391193001','On severe mental illness register (finding)'),('severe-mental-illness',1,'69322001','Psychotic disorder (disorder)'),('severe-mental-illness',1,'10760421000119102','Psychotic disorder in mother complicating childbirth (disorder)'),('severe-mental-illness',1,'10760461000119107','Psychotic disorder in mother complicating pregnancy (disorder)'),('severe-mental-illness',1,'1089691000000105','Acute predominantly delusional psychotic disorder (disorder)'),('severe-mental-illness',1,'129602009','Simbiotic infantile psychosis (disorder)'),('severe-mental-illness',1,'15921731000119106','Psychotic disorder caused by methamphetamine (disorder)'),('severe-mental-illness',1,'17262008','Non-alcoholic Korsakoffs psychosis (disorder)'),('severe-mental-illness',1,'18260003','Postpartum psychosis (disorder)'),('severe-mental-illness',1,'191447007','Organic psychotic condition (disorder)'),('severe-mental-illness',1,'191483003','Drug-induced psychosis (disorder)'),('severe-mental-illness',1,'191525009','Non-organic psychoses (disorder)'),('severe-mental-illness',1,'191676002','Reactive depressive psychosis (disorder)'),('severe-mental-illness',1,'191680007','Psychogenic paranoid psychosis (disorder)'),('severe-mental-illness',1,'21831000119109','Phencyclidine psychosis (disorder)'),('severe-mental-illness',1,'231437006','Reactive psychoses (disorder)'),('severe-mental-illness',1,'231438001','Presbyophrenic psychosis (disorder)'),('severe-mental-illness',1,'231449007','Epileptic psychosis (disorder)'),('severe-mental-illness',1,'231450007','Psychosis associated with intensive care (disorder)'),('severe-mental-illness',1,'231489001','Acute transient psychotic disorder (disorder)'),('severe-mental-illness',1,'238972008','Cutaneous monosymptomatic delusional psychosis (disorder)'),('severe-mental-illness',1,'26530004','Severe bipolar disorder with psychotic features, mood-incongruent (disorder)'),('severe-mental-illness',1,'268623006','Other non-organic psychoses (disorder)'),('severe-mental-illness',1,'268625004','Non-organic psychosis NOS (disorder)'),('severe-mental-illness',1,'274953007','Acute polymorphic psychotic disorder (disorder)'),('severe-mental-illness',1,'278853003','Acute schizophrenia-like psychotic disorder (disorder)'),('severe-mental-illness',1,'32358001','Amphetamine delusional disorder (disorder)'),('severe-mental-illness',1,'357705009','Cotards syndrome (disorder)'),('severe-mental-illness',1,'371026009','Senile dementia with psychosis (disorder)'),('severe-mental-illness',1,'408858002','Infantile psychosis (disorder)'),('severe-mental-illness',1,'441704009','Affective psychosis (disorder)'),('severe-mental-illness',1,'473452003','Atypical psychosis (disorder)'),('severe-mental-illness',1,'50933003','Hallucinogen delusional disorder (disorder)'),('severe-mental-illness',1,'5464005','Brief reactive psychosis (disorder)'),('severe-mental-illness',1,'58214004','Schizophrenia (disorder)'),('severe-mental-illness',1,'58647003','Severe mood disorder with psychotic features, mood-congruent (disorder)'),('severe-mental-illness',1,'59617007','Severe depressed bipolar I disorder with psychotic features (disorder)'),('severe-mental-illness',1,'61831009','Induced psychotic disorder (disorder)'),('severe-mental-illness',1,'68890003','Schizoaffective disorder (disorder)'),('severe-mental-illness',1,'69482004','Korsakoffs psychosis (disorder)'),('severe-mental-illness',1,'70546001','Severe bipolar disorder with psychotic features, mood-congruent (disorder)'),('severe-mental-illness',1,'719717006','Psychosis co-occurrent and due to Parkinsons disease (disorder)'),('severe-mental-illness',1,'723936000','Psychotic disorder caused by cannabis (disorder)'),('severe-mental-illness',1,'724655005','Psychotic disorder caused by opioid (disorder)'),('severe-mental-illness',1,'724689006','Psychotic disorder caused by cocaine (disorder)'),('severe-mental-illness',1,'724696008','Psychotic disorder caused by hallucinogen (disorder)'),('severe-mental-illness',1,'724702008','Psychotic disorder caused by volatile inhalant (disorder)'),('severe-mental-illness',1,'724706006','Psychotic disorder caused by methylenedioxymethamphetamine (disorder)'),('severe-mental-illness',1,'724718002','Psychotic disorder caused by dissociative drug (disorder)'),('severe-mental-illness',1,'724719005','Psychotic disorder caused by ketamine (disorder)'),('severe-mental-illness',1,'724729003','Psychotic disorder caused by psychoactive substance (disorder)'),('severe-mental-illness',1,'724755002','Positive symptoms co-occurrent and due to primary psychotic disorder (disorder)'),('severe-mental-illness',1,'724756001','Negative symptoms co-occurrent and due to primary psychotic disorder (disorder)'),('severe-mental-illness',1,'724757005','Depressive symptoms co-occurrent and due to primary psychotic disorder (disorder)'),('severe-mental-illness',1,'724758000','Manic symptoms co-occurrent and due to primary psychotic disorder (disorder)'),('severe-mental-illness',1,'724759008','Psychomotor symptom co-occurrent and due to psychotic disorder (disorder)'),('severe-mental-illness',1,'724760003','Cognitive impairment co-occurrent and due to primary psychotic disorder (disorder)'),('severe-mental-illness',1,'735750005','Psychotic disorder with schizophreniform symptoms caused by cocaine (disorder)'),('severe-mental-illness',1,'762325009','Psychotic disorder caused by stimulant (disorder)'),('severe-mental-illness',1,'762327001','Psychotic disorder with delusions caused by stimulant (disorder)'),('severe-mental-illness',1,'762507003','Psychotic disorder caused by synthetic cathinone (disorder)'),('severe-mental-illness',1,'762509000','Psychotic disorder with delusions caused by synthetic cathinone (disorder)'),('severe-mental-illness',1,'765176007','Psychosis and severe depression co-occurrent and due to bipolar affective disorder (disorder)'),('severe-mental-illness',1,'7761000119106','Psychotic disorder due to amphetamine use (disorder)'),('severe-mental-illness',1,'786120041000132108','Psychotic disorder caused by substance (disorder)'),('severe-mental-illness',1,'191498001','Drug psychosis NOS (disorder)'),('severe-mental-illness',1,'191524008','Organic psychoses NOS (disorder)'),('severe-mental-illness',1,'191683009','Psychogenic stupor (disorder)'),('severe-mental-illness',1,'191700002','Other specified non-organic psychoses (disorder)'),('severe-mental-illness',1,'268694007','[X]Acute polymorphic psychotic disorder without symptoms of schizophrenia (disorder)'),('severe-mental-illness',1,'270901009','Schizoaffective disorder, mixed type (disorder)'),('severe-mental-illness',1,'278852008','Paranoid-hallucinatory epileptic psychosis (disorder)'),('severe-mental-illness',1,'426321000000107','[X]Other schizophrenia (disorder)'),('severe-mental-illness',1,'452061000000102','[X]Acute polymorphic psychotic disorder without symptoms of schizophrenia (disorder)'),('severe-mental-illness',1,'470311000000103','[X]Other acute and transient psychotic disorders (disorder)'),('severe-mental-illness',1,'4926007','Schizophrenia in remission (disorder)'),('severe-mental-illness',1,'54761006','Severe depressed bipolar I disorder with psychotic features, mood-congruent (disorder)'),('severe-mental-illness',1,'75122001','Inhalant-induced psychotic disorder with delusions (disorder)'),('severe-mental-illness',1,'84760002','Schizoaffective disorder, depressive type (disorder)'),('severe-mental-illness',1,'191473002','Alcohol amnestic syndrome NOS (disorder)'),('severe-mental-illness',1,'191523002','Other specified organic psychoses (disorder)'),('severe-mental-illness',1,'231436002','Psychotic episode NOS (disorder)'),('severe-mental-illness',1,'237352005','Severe postnatal psychosis (disorder)'),('severe-mental-illness',1,'416340002','Late onset schizophrenia (disorder)'),('severe-mental-illness',1,'63649001','Cannabis delusional disorder (disorder)'),('severe-mental-illness',1,'191491007','Other drug psychoses (disorder)'),('severe-mental-illness',1,'191579000','Schizophrenia NOS (disorder)'),('severe-mental-illness',1,'191678001','Reactive confusion (disorder)'),('severe-mental-illness',1,'1973000','Sedative, hypnotic AND/OR anxiolytic-induced psychotic disorder with delusions (disorder)'),('severe-mental-illness',1,'268624000','Acute paranoid reaction (disorder)'),('severe-mental-illness',1,'479991000000101','[X]Other acute predominantly delusional psychotic disorders (disorder)'),('severe-mental-illness',1,'589321000000104','Organic psychoses NOS (disorder)'),('severe-mental-illness',1,'645451000000101','Schizophrenia NOS (disorder)'),('severe-mental-illness',1,'762510005','Psychotic disorder with schizophreniform symptoms caused by synthetic cathinone (disorder)'),('severe-mental-illness',1,'191495003','Drug-induced depressive state (disorder)'),('severe-mental-illness',1,'191515004','Unspecified puerperal psychosis (disorder)'),('severe-mental-illness',1,'191542003','Catatonic schizophrenia (disorder)'),('severe-mental-illness',1,'191577003','Cenesthopathic schizophrenia (disorder)'),('severe-mental-illness',1,'237351003','Mild postnatal psychosis (disorder)'),('severe-mental-illness',1,'238977002','Delusional hyperhidrosis (disorder)'),('severe-mental-illness',1,'26472000','Paraphrenia (disorder)'),('severe-mental-illness',1,'410341000000107','[X]Other schizoaffective disorders (disorder)'),('severe-mental-illness',1,'50722006','PCP delusional disorder (disorder)'),('severe-mental-illness',1,'943071000000104','Opioid-induced psychosis (disorder)'),('severe-mental-illness',1,'1087461000000107','Late onset substance-induced psychosis (disorder)'),('severe-mental-illness',1,'20385005','Opioid-induced psychotic disorder with delusions (disorder)'),('severe-mental-illness',1,'238979004','Hyposchemazia (disorder)'),('severe-mental-illness',1,'268612007','Senile and presenile organic psychotic conditions (disorder)'),
('severe-mental-illness',1,'268618006','Other schizophrenia (disorder)'),('severe-mental-illness',1,'35252006','Disorganized schizophrenia (disorder)'),('severe-mental-illness',1,'558811000000104','Other non-organic psychoses (disorder)'),('severe-mental-illness',1,'63204009','Bouff├⌐e d├⌐lirante (disorder)'),('severe-mental-illness',1,'1087501000000107','Late onset cannabinoid-induced psychosis (disorder)'),('severe-mental-illness',1,'191499009','Transient organic psychoses (disorder)'),('severe-mental-illness',1,'191567000','Schizoaffective schizophrenia (disorder)'),('severe-mental-illness',1,'192327003','[X]Schizophrenia, unspecified (disorder)'),('severe-mental-illness',1,'192339006','[X]Other acute and transient psychotic disorders (disorder)'),('severe-mental-illness',1,'26203008','Severe depressed bipolar I disorder with psychotic features, mood-incongruent (disorder)'),('severe-mental-illness',1,'268617001','Acute schizophrenic episode (disorder)'),('severe-mental-illness',1,'268695008','[X]Other acute predominantly delusional psychotic disorders (disorder)'),('severe-mental-illness',1,'288751000119101','Reactive depressive psychosis, single episode (disorder)'),('severe-mental-illness',1,'38368003','Schizoaffective disorder, bipolar type (disorder)'),('severe-mental-illness',1,'403595006','Pinocchio syndrome (disorder)'),('severe-mental-illness',1,'442891000000100','[X]Acute polymorphic psychotic disorder with symptoms of schizophrenia (disorder)'),('severe-mental-illness',1,'551651000000107','Other specified organic psychoses (disorder)'),('severe-mental-illness',1,'620141000000103','Other reactive psychoses (disorder)'),('severe-mental-illness',1,'943101000000108','Cocaine-induced psychosis (disorder)'),('severe-mental-illness',1,'1087481000000103','Late onset cocaine-induced psychosis (disorder)'),('severe-mental-illness',1,'191484009','Drug-induced paranoia or hallucinatory states (disorder)'),('severe-mental-illness',1,'191526005','Schizophrenic disorders (disorder)'),('severe-mental-illness',1,'30491001','Cocaine delusional disorder (disorder)'),('severe-mental-illness',1,'33380008','Severe manic bipolar I disorder with psychotic features, mood-incongruent (disorder)'),('severe-mental-illness',1,'439911000000108','[X]Schizoaffective disorder, unspecified (disorder)'),('severe-mental-illness',1,'558801000000101','Other schizophrenia (disorder)'),('severe-mental-illness',1,'623951000000105','Alcohol amnestic syndrome NOS (disorder)'),('severe-mental-illness',1,'64731001','Severe mixed bipolar I disorder with psychotic features, mood-congruent (disorder)'),('severe-mental-illness',1,'64905009','Paranoid schizophrenia (disorder)'),('severe-mental-illness',1,'712824002','Acute polymorphic psychotic disorder without symptoms of schizophrenia (disorder)'),('severe-mental-illness',1,'737340007','Psychotic disorder caused by synthetic cannabinoid (disorder)'),('severe-mental-illness',1,'762508008','Psychotic disorder with hallucinations caused by synthetic cathinone (disorder)'),('severe-mental-illness',1,'1086471000000103','Recurrent reactive depressive episodes, severe, with psychosis (disorder)'),('severe-mental-illness',1,'1087491000000101','Late onset lysergic acid diethylamide-induced psychosis (disorder)'),('severe-mental-illness',1,'191496002','Drug-induced personality disorder (disorder)'),('severe-mental-illness',1,'238974009','Delusions of infestation (disorder)'),('severe-mental-illness',1,'589311000000105','Other chronic organic psychoses (disorder)'),('severe-mental-illness',1,'755311000000100','Non-organic psychosis in remission (disorder)'),('severe-mental-illness',1,'88975006','Schizophreniform disorder (disorder)'),('severe-mental-illness',1,'191492000','Drug-induced delirium (disorder)'),('severe-mental-illness',1,'191493005','Drug-induced dementia (disorder)'),('severe-mental-illness',1,'268691004','[X]Other schizophrenia (disorder)'),('severe-mental-illness',1,'307417003','Cycloid psychosis (disorder)'),('severe-mental-illness',1,'466791000000100','[X]Acute and transient psychotic disorder, unspecified (disorder)'),('severe-mental-illness',1,'558821000000105','Non-organic psychosis NOS (disorder)'),('severe-mental-illness',1,'621181000000100','Drug psychosis NOS (disorder)'),('severe-mental-illness',1,'712850003','Acute polymorphic psychotic disorder co-occurrent with symptoms of schizophrenia (disorder)'),('severe-mental-illness',1,'83746006','Chronic schizophrenia (disorder)'),('severe-mental-illness',1,'191494004','Drug-induced amnestic syndrome (disorder)'),('severe-mental-illness',1,'231451006','Drug-induced intensive care psychosis (disorder)'),('severe-mental-illness',1,'238978007','Hyperschemazia (disorder)'),('severe-mental-illness',1,'26025008','Residual schizophrenia (disorder)'),('severe-mental-illness',1,'268696009','[X]Acute and transient psychotic disorder, unspecified (disorder)'),('severe-mental-illness',1,'470301000000100','[X]Schizophrenia, unspecified (disorder)'),('severe-mental-illness',1,'762326005','Psychotic disorder with hallucinations caused by stimulant (disorder)'),('severe-mental-illness',1,'943081000000102','Cannabis-induced psychosis (disorder)'),('severe-mental-illness',1,'943091000000100','Sedative-induced psychosis (disorder)'),('severe-mental-illness',1,'10875004','Severe mixed bipolar I disorder with psychotic features, mood-incongruent (disorder)'),('severe-mental-illness',1,'1087511000000109','Late onset amphetamine-induced psychosis (disorder)'),('severe-mental-illness',1,'191471000','Korsakovs alcoholic psychosis with peripheral neuritis (disorder)'),('severe-mental-illness',1,'191682004','Other reactive psychoses (disorder)'),('severe-mental-illness',1,'192345003','[X]Schizoaffective disorder, unspecified (disorder)'),('severe-mental-illness',1,'238973003','Delusions of parasitosis (disorder)'),('severe-mental-illness',1,'238975005','Delusion of foul odor (disorder)'),('severe-mental-illness',1,'551591000000100','Unspecified puerperal psychosis (disorder)'),('severe-mental-illness',1,'737225007','Secondary psychotic syndrome with hallucinations and delusions (disorder)'),('severe-mental-illness',1,'78640000','Severe manic bipolar I disorder with psychotic features, mood-congruent (disorder)'),('severe-mental-illness',1,'943131000000102','Hallucinogen-induced psychosis (disorder)'),('severe-mental-illness',1,'111484002','Undifferentiated schizophrenia (disorder)'),('severe-mental-illness',1,'191518002','Other chronic organic psychoses (disorder)'),('severe-mental-illness',1,'191527001','Simple schizophrenia (disorder)'),('severe-mental-illness',1,'192335000','[X]Acute polymorphic psychotic disorder with symptoms of schizophrenia (disorder)'),('severe-mental-illness',1,'192344004','[X]Other schizoaffective disorders (disorder)'),('severe-mental-illness',1,'247804008','Schizophrenic prodrome (disorder)'),('severe-mental-illness',1,'271428004','Schizoaffective disorder, manic type (disorder)'),('severe-mental-illness',1,'60401000119104','Postpartum psychosis in remission (disorder)'),('severe-mental-illness',1,'624001000000107','Other drug psychoses (disorder)'),('severe-mental-illness',1,'111483008','Catatonic schizophrenia in remission (disorder)'),('severe-mental-illness',1,'191486006','Drug-induced hallucinosis (disorder)'),('severe-mental-illness',1,'191487002','Drug-induced paranoia or hallucinatory state NOS (disorder)'),('severe-mental-illness',1,'191538001','Acute exacerbation of subchronic hebephrenic schizophrenia (disorder)'),('severe-mental-illness',1,'191540006','Hebephrenic schizophrenia in remission (disorder)'),('severe-mental-illness',1,'191543008','Unspecified catatonic schizophrenia (disorder)'),('severe-mental-illness',1,'191548004','Acute exacerbation of chronic catatonic schizophrenia (disorder)'),('severe-mental-illness',1,'191551006','Unspecified paranoid schizophrenia (disorder)'),('severe-mental-illness',1,'31658008','Chronic paranoid schizophrenia (disorder)'),('severe-mental-illness',1,'551581000000102','Other drug psychoses NOS (disorder)'),('severe-mental-illness',1,'551641000000109','Chronic organic psychosis NOS (disorder)'),('severe-mental-illness',1,'71103003','Chronic residual schizophrenia (disorder)'),('severe-mental-illness',1,'46721000','Psychoactive substance-induced organic personality disorder (disorder)'),('severe-mental-illness',1,'63181006','Paranoid schizophrenia in remission (disorder)'),('severe-mental-illness',1,'762345001','Mood disorder with depressive symptoms caused by dissociative drug (disorder)'),('severe-mental-illness',1,'762512002','Mood disorder with depressive symptoms caused by synthetic cathinone (disorder)'),('severe-mental-illness',1,'8635005','Alcohol withdrawal delirium (disorder)'),('severe-mental-illness',1,'8837000','Amphetamine delirium (disorder)'),('severe-mental-illness',1,'111480006','Psychoactive substance-induced organic dementia (disorder)'),('severe-mental-illness',1,'12939007','Chronic disorganized schizophrenia (disorder)'),('severe-mental-illness',1,'191570001','Chronic schizoaffective schizophrenia (disorder)'),('severe-mental-illness',1,'302507002','Sedative amnestic disorder (disorder)'),('severe-mental-illness',1,'551611000000108','Transient organic psychoses NOS (disorder)'),('severe-mental-illness',1,'68995007','Chronic catatonic schizophrenia (disorder)'),('severe-mental-illness',1,'70328006','Cocaine delirium (disorder)'),('severe-mental-illness',1,'762506007','Delirium caused by synthetic cathinone (disorder)'),('severe-mental-illness',1,'191536002','Subchronic hebephrenic schizophrenia (disorder)'),('severe-mental-illness',1,'191554003','Acute exacerbation of subchronic paranoid schizophrenia (disorder)'),('severe-mental-illness',1,'39807006','Cannabis intoxication delirium (disorder)'),('severe-mental-illness',1,'579811000000105','Paranoid schizophrenia NOS (disorder)'),
('severe-mental-illness',1,'589341000000106','Simple schizophrenia NOS (disorder)'),('severe-mental-illness',1,'589361000000107','Unspecified catatonic schizophrenia (disorder)'),('severe-mental-illness',1,'632271000000100','Psychotic episode NOS (disorder)'),('severe-mental-illness',1,'633401000000100','Unspecified paranoid schizophrenia (disorder)'),('severe-mental-illness',1,'68772007','Stauders lethal catatonia (disorder)'),('severe-mental-illness',1,'762342003','Mood disorder with depressive symptoms caused by ecstasy type drug (disorder)'),('severe-mental-illness',1,'191522007','Chronic organic psychosis NOS (disorder)'),('severe-mental-illness',1,'191531007','Acute exacerbation of chronic schizophrenia (disorder)'),('severe-mental-illness',1,'191550007','Catatonic schizophrenia NOS (disorder)'),('severe-mental-illness',1,'724675001','Psychotic disorder caused by anxiolytic (disorder)'),('severe-mental-illness',1,'762336002','Mood disorder with depressive symptoms caused by hallucinogen (disorder)'),('severe-mental-illness',1,'191530008','Acute exacerbation of subchronic schizophrenia (disorder)'),('severe-mental-illness',1,'191537006','Chronic hebephrenic schizophrenia (disorder)'),('severe-mental-illness',1,'39003006','Psychoactive substance-induced organic delirium (disorder)'),('severe-mental-illness',1,'42868002','Subchronic catatonic schizophrenia (disorder)'),('severe-mental-illness',1,'645441000000104','Other schizophrenia NOS (disorder)'),('severe-mental-illness',1,'724705005','Delirium caused by methylenedioxymethamphetamine (disorder)'),('severe-mental-illness',1,'762321000','Mood disorder with depressive symptoms caused by opioid (disorder)'),('severe-mental-illness',1,'76566000','Subchronic residual schizophrenia (disorder)'),('severe-mental-illness',1,'191528006','Unspecified schizophrenia (disorder)'),('severe-mental-illness',1,'191539009','Acute exacerbation of chronic hebephrenic schizophrenia (disorder)'),('severe-mental-illness',1,'191555002','Acute exacerbation of chronic paranoid schizophrenia (disorder)'),('severe-mental-illness',1,'191569002','Subchronic schizoaffective schizophrenia (disorder)'),('severe-mental-illness',1,'301643003','Sedative, hypnotic AND/OR anxiolytic-induced persisting amnestic disorder (disorder)'),('severe-mental-illness',1,'31715000','PCP delirium (disorder)'),('severe-mental-illness',1,'1089481000000106','Cataleptic schizophrenia (disorder)'),('severe-mental-illness',1,'191485005','Drug-induced paranoid state (disorder)'),('severe-mental-illness',1,'191521000','Other specified chronic organic psychoses (disorder)'),('severe-mental-illness',1,'191541005','Hebephrenic schizophrenia NOS (disorder)'),('severe-mental-illness',1,'191575006','Schizoaffective schizophrenia NOS (disorder)'),('severe-mental-illness',1,'29599000','Chronic undifferentiated schizophrenia (disorder)'),('severe-mental-illness',1,'32875003','Inhalant-induced persisting dementia (disorder)'),('severe-mental-illness',1,'39610001','Undifferentiated schizophrenia in remission (disorder)'),('severe-mental-illness',1,'441833000','Lethal catatonia (disorder)'),('severe-mental-illness',1,'551621000000102','Other reactive psychoses NOS (disorder)'),('severe-mental-illness',1,'589381000000103','Unspecified schizoaffective schizophrenia (disorder)'),('severe-mental-illness',1,'762324008','Delirium caused by stimulant (disorder)'),('severe-mental-illness',1,'762329003','Mood disorder with depressive symptoms caused by stimulant (disorder)'),('severe-mental-illness',1,'191514000','Other transient organic psychoses (disorder)'),('severe-mental-illness',1,'191534004','Simple schizophrenia NOS (disorder)'),('severe-mental-illness',1,'191568005','Unspecified schizoaffective schizophrenia (disorder)'),('severe-mental-illness',1,'26847009','Chronic schizophrenia with acute exacerbations (disorder)'),('severe-mental-illness',1,'268614008','Other senile and presenile organic psychoses (disorder)'),('severe-mental-illness',1,'442251000000107','[X]Undifferentiated schizophrenia (disorder)'),('severe-mental-illness',1,'551631000000100','Other specified chronic organic psychoses (disorder)'),('severe-mental-illness',1,'589301000000108','Other transient organic psychoses (disorder)'),('severe-mental-illness',1,'589331000000102','Unspecified schizophrenia (disorder)'),('severe-mental-illness',1,'623941000000107','Senile or presenile psychoses NOS (disorder)'),('severe-mental-illness',1,'85861002','Subchronic undifferentiated schizophrenia (disorder)'),('severe-mental-illness',1,'191469000','Senile or presenile psychoses NOS (disorder)'),('severe-mental-illness',1,'191547009','Acute exacerbation of subchronic catatonic schizophrenia (disorder)'),('severe-mental-illness',1,'191572009','Acute exacerbation of chronic schizoaffective schizophrenia (disorder)'),('severe-mental-illness',1,'191574005','Schizoaffective schizophrenia in remission (disorder)'),('severe-mental-illness',1,'191578008','Other schizophrenia NOS (disorder)'),('severe-mental-illness',1,'191685002','Other reactive psychoses NOS (disorder)'),('severe-mental-illness',1,'192322009','[X]Undifferentiated schizophrenia (disorder)'),('severe-mental-illness',1,'36158005','Schizophreniform disorder with good prognostic features (disorder)'),('severe-mental-illness',1,'55736003','Schizophreniform disorder without good prognostic features (disorder)'),('severe-mental-illness',1,'724674002','Psychotic disorder caused by hypnotic (disorder)'),('severe-mental-illness',1,'724690002','Mood disorder with depressive symptoms caused by cocaine (disorder)'),('severe-mental-illness',1,'724716003','Delirium caused by ketamine (disorder)'),('severe-mental-illness',1,'762339009','Mood disorder with depressive symptoms caused by volatile inhalant (disorder)'),('severe-mental-illness',1,'191497006','Other drug psychoses NOS (disorder)'),('severe-mental-illness',1,'191517007','Transient organic psychoses NOS (disorder)'),('severe-mental-illness',1,'191535003','Unspecified hebephrenic schizophrenia (disorder)'),('severe-mental-illness',1,'191557005','Paranoid schizophrenia NOS (disorder)'),('severe-mental-illness',1,'191571002','Acute exacerbation of subchronic schizoaffective schizophrenia (disorder)'),('severe-mental-illness',1,'27387000','Subchronic disorganized schizophrenia (disorder)'),('severe-mental-illness',1,'281004','Dementia associated with alcoholism (disorder)'),('severe-mental-illness',1,'31373002','Disorganized schizophrenia in remission (disorder)'),('severe-mental-illness',1,'38295006','Involutional paraphrenia (disorder)'),('severe-mental-illness',1,'621261000000102','Other specified non-organic psychoses (disorder)'),('severe-mental-illness',1,'623991000000102','Drug-induced paranoia or hallucinatory state NOS (disorder)'),('severe-mental-illness',1,'724676000','Mood disorder with depressive symptoms caused by sedative (disorder)'),('severe-mental-illness',1,'724678004','Mood disorder with depressive symptoms caused by anxiolytic (disorder)'),('severe-mental-illness',1,'724717007','Delirium caused by dissociative drug (disorder)'),('severe-mental-illness',1,'16990005','Subchronic schizophrenia (disorder)'),('severe-mental-illness',1,'51133006','Residual schizophrenia in remission (disorder)'),('severe-mental-illness',1,'544861000000109','Other senile and presenile organic psychoses (disorder)'),('severe-mental-illness',1,'589351000000109','Hebephrenic schizophrenia NOS (disorder)'),('severe-mental-illness',1,'633351000000106','Unspecified hebephrenic schizophrenia (disorder)'),('severe-mental-illness',1,'633391000000103','Catatonic schizophrenia NOS (disorder)'),('severe-mental-illness',1,'645431000000108','Schizoaffective schizophrenia NOS (disorder)'),('severe-mental-illness',1,'724673008','Psychotic disorder caused by sedative (disorder)'),('severe-mental-illness',1,'724677009','Mood disorder with depressive symptoms caused by hypnotic (disorder)'),('severe-mental-illness',1,'79866005','Subchronic paranoid schizophrenia (disorder)'),('severe-mental-illness',1,'59651006','Sedative, hypnotic AND/OR anxiolytic-induced persisting dementia (disorder)'),('severe-mental-illness',1,'41521002','Subchronic paranoid schizophrenia with acute exacerbations (disorder)'),('severe-mental-illness',1,'5444000','Sedative, hypnotic AND/OR anxiolytic intoxication delirium (disorder)'),('severe-mental-illness',1,'551601000000106','Other transient organic psychoses NOS (disorder)'),('severe-mental-illness',1,'7025000','Subchronic undifferentiated schizophrenia with acute exacerbations (disorder)'),('severe-mental-illness',1,'86817004','Subchronic catatonic schizophrenia with acute exacerbations (disorder)'),('severe-mental-illness',1,'111482003','Subchronic schizophrenia with acute exacerbations (disorder)'),('severe-mental-illness',1,'30336007','Chronic residual schizophrenia with acute exacerbations (disorder)'),('severe-mental-illness',1,'17435002','Chronic paranoid schizophrenia with acute exacerbations (disorder)'),('severe-mental-illness',1,'14291003','Subchronic disorganized schizophrenia with acute exacerbations (disorder)'),('severe-mental-illness',1,'21894002','Chronic catatonic schizophrenia with acute exacerbations (disorder)'),('severe-mental-illness',1,'70814008','Subchronic residual schizophrenia with acute exacerbations (disorder)'),('severe-mental-illness',1,'191516003','Other transient organic psychoses NOS (disorder)'),('severe-mental-illness',1,'35218008','Chronic disorganized schizophrenia with acute exacerbations (disorder)'),('severe-mental-illness',1,'737339005','Delirium caused by synthetic cannabinoid (disorder)'),('severe-mental-illness',1,'79204003','Chronic undifferentiated schizophrenia with acute exacerbations (disorder)'),('severe-mental-illness',1,'191563001','Acute exacerbation of subchronic latent schizophrenia (disorder)'),('severe-mental-illness',1,'13746004','Bipolar disorder (disorder)'),
('severe-mental-illness',1,'12969000','Severe bipolar II disorder, most recent episode major depressive, in full remission (disorder)'),('severe-mental-illness',1,'13313007','Mild bipolar disorder (disorder)'),('severe-mental-illness',1,'16506000','Mixed bipolar I disorder (disorder)'),('severe-mental-illness',1,'191618007','Bipolar affective disorder, current episode manic (disorder)'),('severe-mental-illness',1,'191627008','Bipolar affective disorder, current episode depression (disorder)'),('severe-mental-illness',1,'191636007','Mixed bipolar affective disorder (disorder)'),('severe-mental-illness',1,'191646009','Unspecified bipolar affective disorder (disorder)'),('severe-mental-illness',1,'191656008','Other and unspecified manic-depressive psychoses (disorder)'),('severe-mental-illness',1,'192356003','[X]Bipolar affective disorder, current episode manic without psychotic symptoms (disorder)'),('severe-mental-illness',1,'192357007','[X]Bipolar affective disorder, current episode manic with psychotic symptoms (disorder)'),('severe-mental-illness',1,'192358002','[X]Bipolar affective disorder, current episode mild or moderate depression (disorder)'),('severe-mental-illness',1,'192359005','[X]Bipolar affective disorder, current episode severe depression without psychotic symptoms (disorder)'),('severe-mental-illness',1,'192363003','[X]Bipolar affective disorder, currently in remission (disorder)'),('severe-mental-illness',1,'192365005','[X]Bipolar affective disorder, unspecified (disorder)'),('severe-mental-illness',1,'231444002','Organic bipolar disorder (disorder)'),('severe-mental-illness',1,'268701002','[X]Other bipolar affective disorders (disorder)'),('severe-mental-illness',1,'30520009','Severe bipolar II disorder, most recent episode major depressive with psychotic features (disorder)'),('severe-mental-illness',1,'31446002','Bipolar I disorder, most recent episode hypomanic (disorder)'),('severe-mental-illness',1,'35722002','Severe bipolar II disorder, most recent episode major depressive, in remission (disorder)'),('severe-mental-illness',1,'35846004','Moderate bipolar II disorder, most recent episode major depressive (disorder)'),('severe-mental-illness',1,'371596008','Bipolar I disorder (disorder)'),('severe-mental-illness',1,'371600003','Severe bipolar disorder (disorder)'),('severe-mental-illness',1,'38368003','Schizoaffective disorder, bipolar type (disorder)'),('severe-mental-illness',1,'417731000000103','[X]Bipolar affective disorder, unspecified (disorder)'),('severe-mental-illness',1,'41836007','Bipolar disorder in full remission (disorder)'),('severe-mental-illness',1,'426091000000108','[X]Other bipolar affective disorders (disorder)'),('severe-mental-illness',1,'431661000000104','[X]Bipolar affective disorder, current episode manic with psychotic symptoms (disorder)'),('severe-mental-illness',1,'443561000000100','[X]Bipolar affective disorder, current episode manic without psychotic symptoms (disorder)'),('severe-mental-illness',1,'4441000','Severe bipolar disorder with psychotic features (disorder)'),('severe-mental-illness',1,'454161000000105','[X]Bipolar affective disorder, currently in remission (disorder)'),('severe-mental-illness',1,'465911000000102','[X]Bipolar affective disorder, current episode severe depression without psychotic symptoms (disorder)'),('severe-mental-illness',1,'467121000000100','[X]Bipolar affective disorder, current episode mild or moderate depression (disorder)'),('severe-mental-illness',1,'53049002','Severe bipolar disorder without psychotic features (disorder)'),('severe-mental-illness',1,'5703000','Bipolar disorder in partial remission (disorder)'),('severe-mental-illness',1,'602491000000105','Unspecified bipolar affective disorder (disorder)'),('severe-mental-illness',1,'613621000000102','Other and unspecified manic-depressive psychoses (disorder)'),('severe-mental-illness',1,'67002003','Severe bipolar II disorder, most recent episode major depressive, in partial remission (disorder)'),('severe-mental-illness',1,'75360000','Bipolar I disorder, single manic episode, in remission (disorder)'),('severe-mental-illness',1,'76105009','Cyclothymia (disorder)'),('severe-mental-illness',1,'767631007','Bipolar disorder, most recent episode depression (disorder)'),('severe-mental-illness',1,'767632000','Bipolar disorder, most recent episode manic (disorder)'),('severe-mental-illness',1,'79584002','Moderate bipolar disorder (disorder)'),('severe-mental-illness',1,'83225003','Bipolar II disorder (disorder)'),('severe-mental-illness',1,'85248005','Bipolar disorder in remission (disorder)'),('severe-mental-illness',1,'9340000','Bipolar I disorder, single manic episode (disorder)'),('severe-mental-illness',1,'191638008','Mixed bipolar affective disorder, mild (disorder)'),('severe-mental-illness',1,'191648005','Unspecified bipolar affective disorder, mild (disorder)'),('severe-mental-illness',1,'26530004','Severe bipolar disorder with psychotic features, mood-incongruent (disorder)'),('severe-mental-illness',1,'530311000000107','Bipolar affective disorder, currently depressed, severe, without mention of psychosis (disorder)'),('severe-mental-illness',1,'602561000000100','Unspecified bipolar affective disorder, in full remission (disorder)'),('severe-mental-illness',1,'615921000000105','Bipolar affective disorder, currently manic, in partial or unspecified remission (disorder)'),('severe-mental-illness',1,'624011000000109','Other and unspecified manic-depressive psychoses NOS (disorder)'),('severe-mental-illness',1,'66631006','Moderate depressed bipolar I disorder (disorder)'),('severe-mental-illness',1,'73471000','Bipolar I disorder, most recent episode mixed with catatonic features (disorder)'),('severe-mental-illness',1,'14495005','Severe bipolar I disorder, single manic episode without psychotic features (disorder)'),('severe-mental-illness',1,'191623007','Bipolar affective disorder, currently manic, severe, with psychosis (disorder)'),('severe-mental-illness',1,'191626004','Bipolar affective disorder, currently manic, NOS (disorder)'),('severe-mental-illness',1,'191660006','Other mixed manic-depressive psychoses (disorder)'),('severe-mental-illness',1,'48937005','Bipolar II disorder, most recent episode hypomanic (disorder)'),('severe-mental-illness',1,'602521000000108','Unspecified bipolar affective disorder, mild (disorder)'),('severe-mental-illness',1,'613511000000109','Bipolar affective disorder, currently depressed, NOS (disorder)'),('severe-mental-illness',1,'613631000000100','Unspecified manic-depressive psychoses (disorder)'),('severe-mental-illness',1,'65042007','Bipolar I disorder, most recent episode mixed with postpartum onset (disorder)'),('severe-mental-illness',1,'767635003','Bipolar I disorder, most recent episode manic (disorder)'),('severe-mental-illness',1,'767636002','Bipolar I disorder, most recent episode depression (disorder)'),('severe-mental-illness',1,'10981006','Severe mixed bipolar I disorder with psychotic features (disorder)'),('severe-mental-illness',1,'1196001','Chronic bipolar II disorder, most recent episode major depressive (disorder)'),('severe-mental-illness',1,'191624001','Bipolar affective disorder, currently manic, in partial or unspecified remission (disorder)'),('severe-mental-illness',1,'191630001','Bipolar affective disorder, currently depressed, moderate (disorder)'),('severe-mental-illness',1,'21900002','Bipolar I disorder, most recent episode depressed with catatonic features (disorder)'),('severe-mental-illness',1,'371604007','Severe bipolar II disorder (disorder)'),('severe-mental-illness',1,'46229002','Severe mixed bipolar I disorder without psychotic features (disorder)'),('severe-mental-illness',1,'49512000','Depressed bipolar I disorder in partial remission (disorder)'),('severe-mental-illness',1,'51637008','Chronic bipolar I disorder, most recent episode depressed (disorder)'),('severe-mental-illness',1,'530301000000105','Bipolar affective disorder, currently manic, severe, without mention of psychosis (disorder)'),('severe-mental-illness',1,'589391000000101','Unspecified affective personality disorder (disorder)'),('severe-mental-illness',1,'615931000000107','Bipolar affective disorder, currently manic, NOS (disorder)'),('severe-mental-illness',1,'623971000000101','Unspecified bipolar affective disorder, NOS (disorder)'),('severe-mental-illness',1,'68569003','Manic bipolar I disorder (disorder)'),('severe-mental-illness',1,'70546001','Severe bipolar disorder with psychotic features, mood-congruent (disorder)'),('severe-mental-illness',1,'191619004','Bipolar affective disorder, currently manic, unspecified (disorder)'),('severe-mental-illness',1,'191650002','Unspecified bipolar affective disorder, severe, without mention of psychosis (disorder)'),('severe-mental-illness',1,'20960007','Severe bipolar II disorder, most recent episode major depressive with psychotic features, mood-incongruent (disorder)'),('severe-mental-illness',1,'307525004','Other manic-depressive psychos (disorder)'),('severe-mental-illness',1,'30935000','Manic bipolar I disorder in full remission (disorder)'),('severe-mental-illness',1,'3530005','Bipolar I disorder, single manic episode, in full remission (disorder)'),('severe-mental-illness',1,'40926005','Moderate mixed bipolar I disorder (disorder)'),('severe-mental-illness',1,'55516002','Bipolar I disorder, most recent episode manic with postpartum onset (disorder)'),('severe-mental-illness',1,'59617007','Severe depressed bipolar I disorder with psychotic features (disorder)'),('severe-mental-illness',1,'87203005','Bipolar I disorder, most recent episode depressed with postpartum onset (disorder)'),('severe-mental-illness',1,'133091000119105','Rapid cycling bipolar I disorder (disorder)'),('severe-mental-illness',1,'191632009','Bipolar affective disorder, currently depressed, severe, with psychosis (disorder)'),
('severe-mental-illness',1,'191661005','Other and unspecified manic-depressive psychoses NOS (disorder)'),('severe-mental-illness',1,'192362008','Bipolar affective disorder , current episode mixed (disorder)'),('severe-mental-illness',1,'271000119101','Severe mixed bipolar I disorder (disorder)'),('severe-mental-illness',1,'29929003','Bipolar I disorder, most recent episode depressed with atypical features (disorder)'),('severe-mental-illness',1,'36583000','Mixed bipolar I disorder in partial remission (disorder)'),('severe-mental-illness',1,'41552001','Mild bipolar I disorder, single manic episode (disorder)'),('severe-mental-illness',1,'43769008','Mild mixed bipolar I disorder (disorder)'),('severe-mental-illness',1,'13581000','Severe bipolar I disorder, single manic episode with psychotic features, mood-congruent (disorder)'),('severe-mental-illness',1,'16295005','Bipolar II disorder, most recent episode major depressive (disorder)'),('severe-mental-illness',1,'191629006','Bipolar affective disorder, currently depressed, mild (disorder)'),('severe-mental-illness',1,'22121000','Depressed bipolar I disorder in full remission (disorder)'),('severe-mental-illness',1,'35481005','Mixed bipolar I disorder in remission (disorder)'),('severe-mental-illness',1,'41832009','Severe bipolar I disorder, single manic episode with psychotic features (disorder)'),('severe-mental-illness',1,'602541000000101','Unspecified bipolar affective disorder, severe, with psychosis (disorder)'),('severe-mental-illness',1,'615951000000100','Bipolar affective disorder, currently depressed, in partial or unspecified remission (disorder)'),('severe-mental-illness',1,'63249007','Manic bipolar I disorder in partial remission (disorder)'),('severe-mental-illness',1,'633731000000103','Bipolar affective disorder, currently manic, unspecified (disorder)'),('severe-mental-illness',1,'702251000000106','Other manic-depressive psychos (disorder)'),('severe-mental-illness',1,'767633005','Bipolar affective disorder, most recent episode mixed (disorder)'),('severe-mental-illness',1,'81319007','Severe bipolar II disorder, most recent episode major depressive without psychotic features (disorder)'),('severe-mental-illness',1,'86058007','Severe bipolar I disorder, single manic episode with psychotic features, mood-incongruent (disorder)'),('severe-mental-illness',1,'87950005','Bipolar I disorder, single manic episode with catatonic features (disorder)'),('severe-mental-illness',1,'111485001','Mixed bipolar I disorder in full remission (disorder)'),('severe-mental-illness',1,'191653000','Unspecified bipolar affective disorder, in full remission (disorder)'),('severe-mental-illness',1,'45479006','Manic bipolar I disorder in remission (disorder)'),('severe-mental-illness',1,'589401000000103','Affective personality disorder NOS (disorder)'),('severe-mental-illness',1,'602531000000105','Unspecified bipolar affective disorder, moderate (disorder)'),('severe-mental-illness',1,'613611000000108','Unspecified bipolar affective disorder, severe, without mention of psychosis (disorder)'),('severe-mental-illness',1,'615941000000103','Bipolar affective disorder, currently depressed, unspecified (disorder)'),('severe-mental-illness',1,'698946008','Cyclothymia in remission (disorder)'),('severe-mental-illness',1,'75752004','Bipolar I disorder, most recent episode depressed with melancholic features (disorder)'),('severe-mental-illness',1,'191622002','Bipolar affective disorder, currently manic, severe, without mention of psychosis (disorder)'),('severe-mental-illness',1,'191625000','Bipolar affective disorder, currently manic, in full remission (disorder)'),('severe-mental-illness',1,'191631002','Bipolar affective disorder, currently depressed, severe, without mention of psychosis (disorder)'),('severe-mental-illness',1,'191633004','Bipolar affective disorder, currently depressed, in partial or unspecified remission (disorder)'),('severe-mental-illness',1,'191635006','Bipolar affective disorder, currently depressed, NOS (disorder)'),('severe-mental-illness',1,'191649002','Unspecified bipolar affective disorder, moderate (disorder)'),('severe-mental-illness',1,'191651003','Unspecified bipolar affective disorder, severe, with psychosis (disorder)'),('severe-mental-illness',1,'371599001','Severe bipolar I disorder (disorder (disorder)'),('severe-mental-illness',1,'53607008','Depressed bipolar I disorder in remission (disorder)'),('severe-mental-illness',1,'602551000000103','Unspecified bipolar affective disorder, in partial or unspecified remission (disorder)'),('severe-mental-illness',1,'61771000119106','Bipolar II disorder, most recent episode rapid cycling (disorder)'),('severe-mental-illness',1,'1499003','Bipolar I disorder, single manic episode with postpartum onset (disorder)'),('severe-mental-illness',1,'17782008','Bipolar I disorder, most recent episode manic with catatonic features (disorder)'),('severe-mental-illness',1,'191620005','Bipolar affective disorder, currently manic, mild (disorder)'),('severe-mental-illness',1,'191755004','Affective personality disorder NOS (disorder)'),('severe-mental-illness',1,'19300006','Severe bipolar II disorder, most recent episode major depressive with psychotic features, mood-congruent (disorder)'),('severe-mental-illness',1,'49468007','Depressed bipolar I disorder (disorder)'),('severe-mental-illness',1,'61403008','Severe depressed bipolar I disorder without psychotic features (disorder)'),('severe-mental-illness',1,'191647000','Unspecified bipolar affective disorder, unspecified (disorder)'),('severe-mental-illness',1,'191654006','Unspecified bipolar affective disorder, NOS (disorder)'),('severe-mental-illness',1,'191657004','Unspecified manic-depressive psychoses (disorder)'),('severe-mental-illness',1,'191752001','Unspecified affective personality disorder (disorder)'),('severe-mental-illness',1,'28663008','Severe manic bipolar I disorder with psychotic features (disorder)'),('severe-mental-illness',1,'613641000000109','Other mixed manic-depressive psychoses (disorder)'),('severe-mental-illness',1,'71294008','Mild bipolar II disorder, most recent episode major depressive (disorder)'),('severe-mental-illness',1,'191621009','Bipolar affective disorder, currently manic, moderate (disorder)'),('severe-mental-illness',1,'191634005','Bipolar affective disorder, currently depressed, in full remission (disorder)'),('severe-mental-illness',1,'191652005','Unspecified bipolar affective disorder, in partial or unspecified remission (disorder)'),('severe-mental-illness',1,'71984005','Mild manic bipolar I disorder (disorder)'),('severe-mental-illness',1,'723903001','Bipolar type I disorder currently in full remission (disorder)'),('severe-mental-illness',1,'723905008','Bipolar type II disorder currently in full remission (disorder)'),('severe-mental-illness',1,'74686005','Mild depressed bipolar I disorder (disorder)'),('severe-mental-illness',1,'765176007','Psychosis and severe depression co-occurrent and due to bipolar affective disorder (disorder)'),('severe-mental-illness',1,'78269000','Bipolar I disorder, single manic episode, in partial remission (disorder)'),('severe-mental-illness',1,'162004','Severe manic bipolar I disorder without psychotic features (disorder)'),('severe-mental-illness',1,'191628003','Bipolar affective disorder, currently depressed, unspecified (disorder)'),('severe-mental-illness',1,'191643001','Mixed bipolar affective disorder, in full remission (disorder)'),('severe-mental-illness',1,'602511000000102','Unspecified bipolar affective disorder, unspecified (disorder)'),('severe-mental-illness',1,'82998009','Moderate manic bipolar I disorder (disorder)'),('severe-mental-illness',1,'54761006','Severe depressed bipolar I disorder with psychotic features, mood-congruent (disorder)'),('severe-mental-illness',1,'191642006','Mixed bipolar affective disorder, in partial or unspecified remission (disorder)'),('severe-mental-illness',1,'10875004','Severe mixed bipolar I disorder with psychotic features, mood-incongruent (disorder)'),('severe-mental-illness',1,'191641004','Mixed bipolar affective disorder, severe, with psychosis (disorder)'),('severe-mental-illness',1,'602481000000108','Mixed bipolar affective disorder, NOS (disorder)'),('severe-mental-illness',1,'78640000','Severe manic bipolar I disorder with psychotic features, mood-congruent (disorder)'),('severe-mental-illness',1,'191644007','Mixed bipolar affective disorder, NOS (disorder)'),('severe-mental-illness',1,'23741000119105','Severe manic bipolar I disorder (disorder)'),('severe-mental-illness',1,'34315001','Bipolar II disorder, most recent episode major depressive with melancholic features (disorder)'),('severe-mental-illness',1,'602471000000106','Mixed bipolar affective disorder, in partial or unspecified remission (disorder)'),('severe-mental-illness',1,'760721000000109','Mixed bipolar affective disorder, in partial remission (disorder)'),('severe-mental-illness',1,'26203008','Severe depressed bipolar I disorder with psychotic features, mood-incongruent (disorder)'),('severe-mental-illness',1,'191640003','Mixed bipolar affective disorder, severe, without mention of psychosis (disorder)'),('severe-mental-illness',1,'22407005','Bipolar II disorder, most recent episode major depressive with catatonic features (disorder)'),('severe-mental-illness',1,'28884001','Moderate bipolar I disorder, single manic episode (disorder)'),('severe-mental-illness',1,'613581000000102','Mixed bipolar affective disorder, unspecified (disorder)'),('severe-mental-illness',1,'191637003','Mixed bipolar affective disorder, unspecified (disorder)'),('severe-mental-illness',1,'191639000','Mixed bipolar affective disorder, moderate (disorder)'),('severe-mental-illness',1,'30687003','Bipolar II disorder, most recent episode major depressive with postpartum onset (disorder)'),('severe-mental-illness',1,'33380008','Severe manic bipolar I disorder with psychotic features, mood-incongruent (disorder)'),
('severe-mental-illness',1,'43568002','Bipolar II disorder, most recent episode major depressive with atypical features (disorder)'),('severe-mental-illness',1,'64731001','Severe mixed bipolar I disorder with psychotic features, mood-congruent (disorder)'),('severe-mental-illness',1,'261000119107','Severe depressed bipolar I disorder (disorder)'),('severe-mental-illness',1,'764591000000108','Mixed bipolar affective disorder, severe (disorder)'),('severe-mental-illness',1,'529851000000108','Mixed bipolar affective disorder, severe, without mention of psychosis (disorder)'),('severe-mental-illness',1,'58214004','Schizophrenia (disorder)'),('severe-mental-illness',1,'111484002','Undifferentiated schizophrenia (disorder)'),('severe-mental-illness',1,'191526005','Schizophrenic disorders (disorder)'),('severe-mental-illness',1,'191527001','Simple schizophrenia (disorder)'),('severe-mental-illness',1,'191542003','Catatonic schizophrenia (disorder)'),('severe-mental-illness',1,'191577003','Cenesthopathic schizophrenia (disorder)'),('severe-mental-illness',1,'191579000','Schizophrenia NOS (disorder)'),('severe-mental-illness',1,'192327003','[X]Schizophrenia, unspecified (disorder)'),('severe-mental-illness',1,'247804008','Schizophrenic prodrome (disorder)'),('severe-mental-illness',1,'26025008','Residual schizophrenia (disorder)'),('severe-mental-illness',1,'26472000','Paraphrenia (disorder)'),('severe-mental-illness',1,'268617001','Acute schizophrenic episode (disorder)'),('severe-mental-illness',1,'268618006','Other schizophrenia (disorder)'),('severe-mental-illness',1,'268691004','[X]Other schizophrenia (disorder)'),('severe-mental-illness',1,'35252006','Disorganized schizophrenia (disorder)'),('severe-mental-illness',1,'416340002','Late onset schizophrenia (disorder)'),('severe-mental-illness',1,'426321000000107','[X]Other schizophrenia (disorder)'),('severe-mental-illness',1,'470301000000100','[X]Schizophrenia, unspecified (disorder)'),('severe-mental-illness',1,'4926007','Schizophrenia in remission (disorder)'),('severe-mental-illness',1,'558801000000101','Other schizophrenia (disorder)'),('severe-mental-illness',1,'645451000000101','Schizophrenia NOS (disorder)'),('severe-mental-illness',1,'64905009','Paranoid schizophrenia (disorder)'),('severe-mental-illness',1,'83746006','Chronic schizophrenia (disorder)'),('severe-mental-illness',1,'1089481000000106','Cataleptic schizophrenia (disorder)'),('severe-mental-illness',1,'191541005','Hebephrenic schizophrenia NOS (disorder)'),('severe-mental-illness',1,'29599000','Chronic undifferentiated schizophrenia (disorder)'),('severe-mental-illness',1,'39610001','Undifferentiated schizophrenia in remission (disorder)'),('severe-mental-illness',1,'441833000','Lethal catatonia (disorder)'),('severe-mental-illness',1,'16990005','Subchronic schizophrenia (disorder)'),('severe-mental-illness',1,'51133006','Residual schizophrenia in remission (disorder)'),('severe-mental-illness',1,'589351000000109','Hebephrenic schizophrenia NOS (disorder)'),('severe-mental-illness',1,'633351000000106','Unspecified hebephrenic schizophrenia (disorder)'),('severe-mental-illness',1,'633391000000103','Catatonic schizophrenia NOS (disorder)'),('severe-mental-illness',1,'79866005','Subchronic paranoid schizophrenia (disorder)'),('severe-mental-illness',1,'191534004','Simple schizophrenia NOS (disorder)'),('severe-mental-illness',1,'26847009','Chronic schizophrenia with acute exacerbations (disorder)'),('severe-mental-illness',1,'442251000000107','[X]Undifferentiated schizophrenia (disorder)'),('severe-mental-illness',1,'589331000000102','Unspecified schizophrenia (disorder)'),('severe-mental-illness',1,'85861002','Subchronic undifferentiated schizophrenia (disorder)'),('severe-mental-illness',1,'111483008','Catatonic schizophrenia in remission (disorder)'),('severe-mental-illness',1,'191538001','Acute exacerbation of subchronic hebephrenic schizophrenia (disorder)'),('severe-mental-illness',1,'191540006','Hebephrenic schizophrenia in remission (disorder)'),('severe-mental-illness',1,'191543008','Unspecified catatonic schizophrenia (disorder)'),('severe-mental-illness',1,'191548004','Acute exacerbation of chronic catatonic schizophrenia (disorder)'),('severe-mental-illness',1,'191551006','Unspecified paranoid schizophrenia (disorder)'),('severe-mental-illness',1,'31658008','Chronic paranoid schizophrenia (disorder)'),('severe-mental-illness',1,'71103003','Chronic residual schizophrenia (disorder)'),('severe-mental-illness',1,'63181006','Paranoid schizophrenia in remission (disorder)'),('severe-mental-illness',1,'191547009','Acute exacerbation of subchronic catatonic schizophrenia (disorder)'),('severe-mental-illness',1,'191578008','Other schizophrenia NOS (disorder)'),('severe-mental-illness',1,'192322009','[X]Undifferentiated schizophrenia (disorder)'),('severe-mental-illness',1,'191536002','Subchronic hebephrenic schizophrenia (disorder)'),('severe-mental-illness',1,'191554003','Acute exacerbation of subchronic paranoid schizophrenia (disorder)'),('severe-mental-illness',1,'579811000000105','Paranoid schizophrenia NOS (disorder)'),('severe-mental-illness',1,'589341000000106','Simple schizophrenia NOS (disorder)'),('severe-mental-illness',1,'589361000000107','Unspecified catatonic schizophrenia (disorder)'),('severe-mental-illness',1,'633401000000100','Unspecified paranoid schizophrenia (disorder)'),('severe-mental-illness',1,'68772007','Stauders lethal catatonia (disorder)'),('severe-mental-illness',1,'191531007','Acute exacerbation of chronic schizophrenia (disorder)'),('severe-mental-illness',1,'191550007','Catatonic schizophrenia NOS (disorder)'),('severe-mental-illness',1,'191528006','Unspecified schizophrenia (disorder)'),('severe-mental-illness',1,'191539009','Acute exacerbation of chronic hebephrenic schizophrenia (disorder)'),('severe-mental-illness',1,'191555002','Acute exacerbation of chronic paranoid schizophrenia (disorder)'),('severe-mental-illness',1,'12939007','Chronic disorganized schizophrenia (disorder)'),('severe-mental-illness',1,'68995007','Chronic catatonic schizophrenia (disorder)'),('severe-mental-illness',1,'191530008','Acute exacerbation of subchronic schizophrenia (disorder)'),('severe-mental-illness',1,'191537006','Chronic hebephrenic schizophrenia (disorder)'),('severe-mental-illness',1,'42868002','Subchronic catatonic schizophrenia (disorder)'),('severe-mental-illness',1,'645441000000104','Other schizophrenia NOS (disorder)'),('severe-mental-illness',1,'76566000','Subchronic residual schizophrenia (disorder)'),('severe-mental-illness',1,'191535003','Unspecified hebephrenic schizophrenia (disorder)'),('severe-mental-illness',1,'191557005','Paranoid schizophrenia NOS (disorder)'),('severe-mental-illness',1,'27387000','Subchronic disorganized schizophrenia (disorder)'),('severe-mental-illness',1,'31373002','Disorganized schizophrenia in remission (disorder)'),('severe-mental-illness',1,'38295006','Involutional paraphrenia (disorder)'),('severe-mental-illness',1,'86817004','Subchronic catatonic schizophrenia with acute exacerbations (disorder)'),('severe-mental-illness',1,'7025000','Subchronic undifferentiated schizophrenia with acute exacerbations (disorder)'),('severe-mental-illness',1,'17435002','Chronic paranoid schizophrenia with acute exacerbations (disorder)'),('severe-mental-illness',1,'41521002','Subchronic paranoid schizophrenia with acute exacerbations (disorder)'),('severe-mental-illness',1,'111482003','Subchronic schizophrenia with acute exacerbations (disorder)'),('severe-mental-illness',1,'14291003','Subchronic disorganized schizophrenia with acute exacerbations (disorder)'),('severe-mental-illness',1,'30336007','Chronic residual schizophrenia with acute exacerbations (disorder)'),('severe-mental-illness',1,'21894002','Chronic catatonic schizophrenia with acute exacerbations (disorder)'),('severe-mental-illness',1,'70814008','Subchronic residual schizophrenia with acute exacerbations (disorder)'),('severe-mental-illness',1,'35218008','Chronic disorganized schizophrenia with acute exacerbations (disorder)'),('severe-mental-illness',1,'79204003','Chronic undifferentiated schizophrenia with acute exacerbations (disorder)'),('severe-mental-illness',1,'191563001','Acute exacerbation of subchronic latent schizophrenia (disorder)')

INSERT INTO #AllCodes
SELECT [concept], [version], [code] from #codessnomed;

IF OBJECT_ID('tempdb..#codesemis') IS NOT NULL DROP TABLE #codesemis;
CREATE TABLE #codesemis (
  [concept] [varchar](255) NOT NULL,
  [version] INT NOT NULL,
	[code] [varchar](20) COLLATE Latin1_General_CS_AS NOT NULL,
	[description] [varchar](255) NULL
) ON [PRIMARY];



INSERT INTO #AllCodes
SELECT [concept], [version], [code] from #codesemis;


IF OBJECT_ID('tempdb..#TempRefCodes') IS NOT NULL DROP TABLE #TempRefCodes;
CREATE TABLE #TempRefCodes (FK_Reference_Coding_ID BIGINT NOT NULL, concept VARCHAR(255) NOT NULL, version INT NOT NULL);

-- Read v2 codes
INSERT INTO #TempRefCodes
SELECT PK_Reference_Coding_ID, dcr.concept, dcr.[version]
FROM [SharedCare].[Reference_Coding] rc
INNER JOIN #codesreadv2 dcr on dcr.code = rc.MainCode
WHERE CodingType='ReadCodeV2'
and PK_Reference_Coding_ID != -1;

-- CTV3 codes
INSERT INTO #TempRefCodes
SELECT PK_Reference_Coding_ID, dcc.concept, dcc.[version]
FROM [SharedCare].[Reference_Coding] rc
INNER JOIN #codesctv3 dcc on dcc.code = rc.MainCode
WHERE CodingType='CTV3'
and PK_Reference_Coding_ID != -1;

-- EMIS codes with a FK Reference Coding ID
INSERT INTO #TempRefCodes
SELECT FK_Reference_Coding_ID, ce.concept, ce.[version]
FROM [SharedCare].[Reference_Local_Code] rlc
INNER JOIN #codesemis ce on ce.code = rlc.LocalCode
WHERE FK_Reference_Coding_ID != -1;

IF OBJECT_ID('tempdb..#TempSNOMEDRefCodes') IS NOT NULL DROP TABLE #TempSNOMEDRefCodes;
CREATE TABLE #TempSNOMEDRefCodes (FK_Reference_SnomedCT_ID BIGINT NOT NULL, concept VARCHAR(255) NOT NULL, [version] INT NOT NULL);

-- SNOMED codes
INSERT INTO #TempSNOMEDRefCodes
SELECT PK_Reference_SnomedCT_ID, dcs.concept, dcs.[version]
FROM SharedCare.Reference_SnomedCT rs
INNER JOIN #codessnomed dcs on dcs.code = rs.ConceptID;

-- EMIS codes with a FK SNOMED ID but without a FK Reference Coding ID
INSERT INTO #TempSNOMEDRefCodes
SELECT FK_Reference_SnomedCT_ID, ce.concept, ce.[version]
FROM [SharedCare].[Reference_Local_Code] rlc
INNER JOIN #codesemis ce on ce.code = rlc.LocalCode
WHERE FK_Reference_Coding_ID = -1
AND FK_Reference_SnomedCT_ID != -1;

-- De-duped tables
IF OBJECT_ID('tempdb..#CodeSets') IS NOT NULL DROP TABLE #CodeSets;
CREATE TABLE #CodeSets (FK_Reference_Coding_ID BIGINT NOT NULL, concept VARCHAR(255) NOT NULL);

IF OBJECT_ID('tempdb..#SnomedSets') IS NOT NULL DROP TABLE #SnomedSets;
CREATE TABLE #SnomedSets (FK_Reference_SnomedCT_ID BIGINT NOT NULL, concept VARCHAR(255) NOT NULL);

IF OBJECT_ID('tempdb..#VersionedCodeSets') IS NOT NULL DROP TABLE #VersionedCodeSets;
CREATE TABLE #VersionedCodeSets (FK_Reference_Coding_ID BIGINT NOT NULL, Concept VARCHAR(255), [Version] INT);

IF OBJECT_ID('tempdb..#VersionedSnomedSets') IS NOT NULL DROP TABLE #VersionedSnomedSets;
CREATE TABLE #VersionedSnomedSets (FK_Reference_SnomedCT_ID BIGINT NOT NULL, Concept VARCHAR(255), [Version] INT);

INSERT INTO #VersionedCodeSets
SELECT DISTINCT * FROM #TempRefCodes;

INSERT INTO #VersionedSnomedSets
SELECT DISTINCT * FROM #TempSNOMEDRefCodes;

INSERT INTO #CodeSets
SELECT FK_Reference_Coding_ID, c.concept
FROM #VersionedCodeSets c
INNER JOIN (
  SELECT concept, MAX(version) AS maxVersion FROM #VersionedCodeSets
  GROUP BY concept)
sub ON sub.concept = c.concept AND c.version = sub.maxVersion;

INSERT INTO #SnomedSets
SELECT FK_Reference_SnomedCT_ID, c.concept
FROM #VersionedSnomedSets c
INNER JOIN (
  SELECT concept, MAX(version) AS maxVersion FROM #VersionedSnomedSets
  GROUP BY concept)
sub ON sub.concept = c.concept AND c.version = sub.maxVersion;

-- >>> Following codesets injected: severe-mental-illness

-- SMI episodes to identify cohort

IF OBJECT_ID('tempdb..#SMI_Episodes') IS NOT NULL DROP TABLE #SMI_Episodes;
SELECT gp.FK_Patient_Link_ID, 
		YearOfBirth, 
		Sex
INTO #SMI_Episodes
FROM [RLS].[vw_GP_Events] gp
LEFT OUTER JOIN #Patients p ON p.FK_Patient_link_ID = gp.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = p.FK_Patient_Link_ID
WHERE SuppliedCode IN 
	(SELECT [Code] FROM #AllCodes WHERE [Concept] IN ('severe-mental-illness') AND [Version] = 1)
	AND gp.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
	AND (gp.EventDate) <= '2020-01-31'

-- Define the main cohort to be matched

IF OBJECT_ID('tempdb..#MainCohort') IS NOT NULL DROP TABLE #MainCohort;
SELECT DISTINCT FK_Patient_Link_ID, 
		YearOfBirth, 
		Sex
INTO #MainCohort
FROM #SMI_Episodes
--51,082

-- Define the population of potential matches for the cohort
IF OBJECT_ID('tempdb..#PotentialMatches') IS NOT NULL DROP TABLE #PotentialMatches;
SELECT p.FK_Patient_Link_ID, Sex, YearOfBirth
INTO #PotentialMatches
FROM #Patients p
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = p.FK_Patient_Link_ID
EXCEPT
SELECT FK_Patient_Link_ID, Sex, YearOfBirth FROM #MainCohort;
-- 3,378,730

--┌────────────────────────────────────────────────────────────┐
--│ Cohort matching on year of birth / sex 					   │
--└────────────────────────────────────────────────────────────┘

-- OBJECTIVE: To take a primary cohort and find a 1:5 matched cohort based on year of birth and sex.

-- INPUT: Takes one parameter
--  - yob-flex: integer - number of years each way that still allow a year of birth match
-- Requires two temp tables to exist as follows:
-- #MainCohort (FK_Patient_Link_ID, Sex, YearOfBirth)
-- 	- FK_Patient_Link_ID - unique patient id
--	- Sex - M/F
--	- YearOfBirth - Integer
-- #PotentialMatches (FK_Patient_Link_ID, Sex, YearOfBirth)
-- 	- FK_Patient_Link_ID - unique patient id
--	- Sex - M/F
--	- YearOfBirth - Integer

-- OUTPUT: A temp table as follows:
-- #CohortStore (FK_Patient_Link_ID, YearOfBirth, Sex, MatchingPatientId, MatchingYearOfBirth)
--  - FK_Patient_Link_ID - unique patient id for primary cohort patient
--  - YearOfBirth - of the primary cohort patient
--  - Sex - of the primary cohort patient
--  - MatchingPatientId - id of the matched patient
--  - MatchingYearOfBirth - year of birth of the matched patient

-- First we copy the #PrimaryCohort table to avoid pollution
IF OBJECT_ID('tempdb..#Cases') IS NOT NULL DROP TABLE #Cases;
SELECT FK_Patient_Link_ID AS PatientId, YearOfBirth, Sex
INTO #Cases FROM #MainCohort;

-- Then we do the same with the #PotentialMatches but with a bit of flexibility on the age and date
IF OBJECT_ID('tempdb..#Matches') IS NOT NULL DROP TABLE #Matches;
SELECT FK_Patient_Link_ID AS PatientId, YearOfBirth, Sex
INTO #Matches FROM (select p.FK_Patient_Link_ID, p.YearOfBirth, p.Sex from #Cases c inner join (
	SELECT FK_Patient_Link_ID, YearOfBirth, Sex FROM #PotentialMatches
) p on c.Sex = p.Sex and c.YearOfBirth >= p.YearOfBirth - 1 and c.YearOfBirth <= p.YearOfBirth + 1 
group by p.FK_Patient_Link_ID, p.YearOfBirth, p.Sex) sub;

-- Table to store the matches
IF OBJECT_ID('tempdb..#CohortStore') IS NOT NULL DROP TABLE #CohortStore;
CREATE TABLE #CohortStore(
  PatientId BIGINT, 
  YearOfBirth INT, 
  Sex nchar(1), 
  MatchingPatientId BIGINT,
  MatchingYearOfBirth INT
) ON [PRIMARY];

-- 1. If anyone only matches one case then use them. Remove and repeat until everyone matches
--    multiple people TODO or until the #Cases table is empty
DECLARE @LastRowInsert INT; 
SET @LastRowInsert=1;
WHILE ( @LastRowInsert > 0)
BEGIN  
  -- match them
  INSERT INTO #CohortStore
  SELECT PatientId, YearOfBirth, Sex, MatchedPatientId, YearOfBirth FROM (
	  SELECT c.PatientId, c.YearOfBirth, c.Sex, p.PatientId AS MatchedPatientId, Row_Number() OVER(PARTITION BY MAX(c.PatientId) ORDER BY NewID()) AS AssignedPersonNumber
	  FROM #Cases c
		INNER JOIN #Matches p 
		  ON p.Sex = c.Sex 
		  AND p.YearOfBirth = c.YearOfBirth
		WHERE p.PatientId in (
		-- find patients in the matches who only match a single case
			select m.PatientId
		  from #Matches m 
		  inner join #Cases c ON m.Sex = c.Sex 
			  AND m.YearOfBirth = c.YearOfBirth
			group by m.PatientId
			having count(*) = 1
		)
	  GROUP BY c.PatientId, c.YearOfBirth, c.Sex, p.PatientId
	) sub
	WHERE AssignedPersonNumber <= 5
  ORDER BY PatientId;
  SELECT @LastRowInsert=@@ROWCOUNT;

  -- remove from cases anyone we've already got n for
  delete from #Cases where PatientId in (
  select PatientId FROM #CohortStore
  group by PatientId
  having count(*) >= 5);

  -- remove from matches anyone already used
  DELETE FROM #Matches WHERE PatientId IN (SELECT MatchingPatientId FROM #CohortStore);
END

--select distinct MatchingPatientId from #CohortStore
--select count(*) from #CohortStore
--This next query shows how many people with no match, 1 match, 2 match etc.
--SELECT Num, COUNT(*) FROM ( SELECT PatientId, COUNT(*) AS Num FROM #CohortStore GROUP BY PatientId) sub GROUP BY Num UNION SELECT 0, x FROM (SELECT COUNT(*) AS x FROM (SELECT PatientId FROM #Cases EXCEPT SELECT PatientId FROM #CohortStore) sub1) sub ORDER BY Num;


-- 2. Now we focus on people without any matches and try and give everyone a match
DECLARE @LastRowInsert2 INT;
SET @LastRowInsert2=1;
WHILE ( @LastRowInsert2 > 0)
BEGIN
  INSERT INTO #CohortStore
  SELECT PatientId, YearOfBirth, Sex, MatchedPatientId, YearOfBirth FROM (
  SELECT c.PatientId, c.YearOfBirth, c.Sex, MAX(p.PatientId) AS MatchedPatientId, Row_Number() OVER(PARTITION BY MAX(p.PatientId) ORDER BY NewID()) AS AssignedPersonNumber
  FROM #Cases c
  INNER JOIN #Matches p 
    ON p.Sex = c.Sex 
    AND p.YearOfBirth = c.YearOfBirth 
  WHERE c.PatientId in (
    -- find patients who aren't currently matched
select PatientId from #Cases except select PatientId from #CohortStore
  )
  GROUP BY c.PatientId, c.YearOfBirth, c.Sex) sub
  WHERE sub.AssignedPersonNumber = 1;
  SELECT @LastRowInsert2=@@ROWCOUNT;

  DELETE FROM #Matches WHERE PatientId IN (SELECT MatchingPatientId FROM #CohortStore);
END

-- 3. There are some people who we can't find a match for.. try relaxing the date requirement
DECLARE @LastRowInsert3 INT;
SET @LastRowInsert3=1;
WHILE ( @LastRowInsert3 > 0)
BEGIN
  INSERT INTO #CohortStore
  SELECT sub.PatientId, sub.YearOfBirth, sub.Sex, MatchedPatientId, m.YearOfBirth FROM (
  SELECT c.PatientId, c.YearOfBirth, c.Sex, MAX(p.PatientId) AS MatchedPatientId, Row_Number() OVER(PARTITION BY MAX(p.PatientId) ORDER BY NewID()) AS AssignedPersonNumber
  FROM #Cases c
  INNER JOIN #Matches p 
    ON p.Sex = c.Sex 
    AND p.YearOfBirth = c.YearOfBirth
  WHERE c.PatientId in (
    -- find patients who aren't currently matched
select PatientId from #Cases except select PatientId from #CohortStore
  )
  GROUP BY c.PatientId, c.YearOfBirth, c.Sex) sub
  INNER JOIN #Matches m 
    ON m.Sex = sub.Sex 
    AND m.PatientId = sub.MatchedPatientId
    AND m.YearOfBirth = sub.YearOfBirth
  WHERE sub.AssignedPersonNumber = 1
  GROUP BY sub.PatientId, sub.YearOfBirth, sub.Sex, MatchedPatientId, m.YearOfBirth;
  SELECT @LastRowInsert3=@@ROWCOUNT;

  DELETE FROM #Matches WHERE PatientId IN (SELECT MatchingPatientId FROM #CohortStore);
END


-- 4. There are some people who we still can't find a match for.. try relaxing the age and date requirement
DECLARE @LastRowInsert4 INT;
SET @LastRowInsert4=1;
WHILE ( @LastRowInsert4 > 0)
BEGIN
  INSERT INTO #CohortStore
  SELECT sub.PatientId, sub.YearOfBirth, sub.Sex, MatchedPatientId, MAX(m.YearOfBirth) FROM (
  SELECT c.PatientId, c.YearOfBirth, c.Sex, MAX(p.PatientId) AS MatchedPatientId, Row_Number() OVER(PARTITION BY MAX(p.PatientId) ORDER BY NewID()) AS AssignedPersonNumber
  FROM #Cases c
  INNER JOIN #Matches p 
    ON p.Sex = c.Sex 
    AND p.YearOfBirth >= c.YearOfBirth - 1
    AND p.YearOfBirth <= c.YearOfBirth + 1
  WHERE c.PatientId in (
    -- find patients who aren't currently matched
select PatientId from #Cases except select PatientId from #CohortStore
  )
  GROUP BY c.PatientId, c.YearOfBirth, c.Sex) sub
  INNER JOIN #Matches m 
    ON m.Sex = sub.Sex 
    AND m.PatientId = sub.MatchedPatientId
    AND m.YearOfBirth >= sub.YearOfBirth - 1
    AND m.YearOfBirth <= sub.YearOfBirth + 1
  WHERE sub.AssignedPersonNumber = 1
  GROUP BY sub.PatientId, sub.YearOfBirth, sub.Sex, MatchedPatientId;
  SELECT @LastRowInsert4=@@ROWCOUNT;

  DELETE FROM #Matches WHERE PatientId IN (SELECT MatchingPatientId FROM #CohortStore);
END

--This next query shows how many people with no match, 1 match, 2 match etc.
--SELECT Num, COUNT(*) FROM ( SELECT PatientId, COUNT(*) AS Num FROM #CohortStore GROUP BY PatientId) sub GROUP BY Num UNION SELECT 0, x FROM (SELECT COUNT(*) AS x FROM (SELECT PatientId FROM #Cases EXCEPT SELECT PatientId FROM #CohortStore) sub1) sub ORDER BY Num;

-- 5. Now we focus on people with only 1 match(es) and attempt to give them another
DECLARE @LastRowInsert5 INT;
SET @LastRowInsert5=1;
WHILE ( @LastRowInsert5 > 0)
BEGIN
  INSERT INTO #CohortStore
  SELECT PatientId, YearOfBirth, Sex, MatchedPatientId, YearOfBirth FROM (
  SELECT c.PatientId, c.YearOfBirth, c.Sex, MAX(p.PatientId) AS MatchedPatientId, Row_Number() OVER(PARTITION BY MAX(p.PatientId) ORDER BY NewID()) AS AssignedPersonNumber
  FROM #Cases c
  INNER JOIN #Matches p 
    ON p.Sex = c.Sex 
    AND p.YearOfBirth = c.YearOfBirth
  WHERE c.PatientId in (
    -- find patients who currently only have 1 match(es)
select PatientId from #CohortStore group by PatientId having count(*) = 1
  )
  GROUP BY c.PatientId, c.YearOfBirth, c.Sex) sub
  WHERE sub.AssignedPersonNumber = 1;
  SELECT @LastRowInsert5=@@ROWCOUNT;

  DELETE FROM #Matches WHERE PatientId IN (SELECT MatchingPatientId FROM #CohortStore);
END

-- 6. There are some people who we can't find a 2nd match.. try relaxing the date requirement
DECLARE @LastRowInsert6 INT;
SET @LastRowInsert6=1;
WHILE ( @LastRowInsert6 > 0)
BEGIN
  INSERT INTO #CohortStore
  SELECT sub.PatientId, sub.YearOfBirth, sub.Sex, MatchedPatientId, m.YearOfBirth FROM (
  SELECT c.PatientId, c.YearOfBirth, c.Sex, MAX(p.PatientId) AS MatchedPatientId, Row_Number() OVER(PARTITION BY MAX(p.PatientId) ORDER BY NewID()) AS AssignedPersonNumber
  FROM #Cases c
  INNER JOIN #Matches p 
    ON p.Sex = c.Sex 
    AND p.YearOfBirth = c.YearOfBirth
  WHERE c.PatientId in (
    -- find patients who currently only have 1 match(es)
select PatientId from #CohortStore group by PatientId having count(*) = 1
  )
  GROUP BY c.PatientId, c.YearOfBirth, c.Sex) sub
  INNER JOIN #Matches m 
    ON m.Sex = sub.Sex 
    AND m.PatientId = sub.MatchedPatientId
    AND m.YearOfBirth = sub.YearOfBirth
  WHERE sub.AssignedPersonNumber = 1
  GROUP BY sub.PatientId, sub.YearOfBirth, sub.Sex, MatchedPatientId, m.YearOfBirth;
  SELECT @LastRowInsert6=@@ROWCOUNT;

  DELETE FROM #Matches WHERE PatientId IN (SELECT MatchingPatientId FROM #CohortStore);
END

-- 7. There are some people who we still can't find a 2nd match.. try relaxing the age and date requirement
DECLARE @LastRowInsert7 INT;
SET @LastRowInsert7=1;
WHILE ( @LastRowInsert7 > 0)
BEGIN
  INSERT INTO #CohortStore
  SELECT sub.PatientId, sub.YearOfBirth, sub.Sex, MatchedPatientId, MAX(m.YearOfBirth) FROM (
  SELECT c.PatientId, c.YearOfBirth, c.Sex, MAX(p.PatientId) AS MatchedPatientId, Row_Number() OVER(PARTITION BY MAX(p.PatientId) ORDER BY NewID()) AS AssignedPersonNumber
  FROM #Cases c
  INNER JOIN #Matches p 
    ON p.Sex = c.Sex 
    AND p.YearOfBirth >= c.YearOfBirth - 1
    AND p.YearOfBirth <= c.YearOfBirth + 1
  WHERE c.PatientId in (
    -- find patients who currently only have 1 match(es)
select PatientId from #CohortStore group by PatientId having count(*) = 1
  )
  GROUP BY c.PatientId, c.YearOfBirth, c.Sex) sub
  INNER JOIN #Matches m 
    ON m.Sex = sub.Sex 
    AND m.PatientId = sub.MatchedPatientId
    AND m.YearOfBirth >= sub.YearOfBirth - 1
    AND m.YearOfBirth <= sub.YearOfBirth + 1
  WHERE sub.AssignedPersonNumber = 1
  GROUP BY sub.PatientId, sub.YearOfBirth, sub.Sex, MatchedPatientId;
  SELECT @LastRowInsert7=@@ROWCOUNT;

  DELETE FROM #Matches WHERE PatientId IN (SELECT MatchingPatientId FROM #CohortStore);
END

--This next query shows how many people with no match, 1 match, 2 match etc.
--SELECT Num, COUNT(*) FROM ( SELECT PatientId, COUNT(*) AS Num FROM #CohortStore GROUP BY PatientId) sub GROUP BY Num UNION SELECT 0, x FROM (SELECT COUNT(*) AS x FROM (SELECT PatientId FROM #Cases EXCEPT SELECT PatientId FROM #CohortStore) sub1) sub ORDER BY Num;

-- 8. Now we focus on people with only 2 match(es) and attempt to give them another
DECLARE @LastRowInsert8 INT;
SET @LastRowInsert8=1;
WHILE ( @LastRowInsert8 > 0)
BEGIN
  INSERT INTO #CohortStore
  SELECT PatientId, YearOfBirth, Sex, MatchedPatientId, YearOfBirth FROM (
  SELECT c.PatientId, c.YearOfBirth, c.Sex, MAX(p.PatientId) AS MatchedPatientId, Row_Number() OVER(PARTITION BY MAX(p.PatientId) ORDER BY NewID()) AS AssignedPersonNumber
  FROM #Cases c
  INNER JOIN #Matches p 
    ON p.Sex = c.Sex 
    AND p.YearOfBirth = c.YearOfBirth 
  WHERE c.PatientId in (
    -- find patients who currently only have 2 match(es)
select PatientId from #CohortStore group by PatientId having count(*) = 2
  )
  GROUP BY c.PatientId, c.YearOfBirth, c.Sex) sub
  WHERE sub.AssignedPersonNumber = 1;
  SELECT @LastRowInsert8=@@ROWCOUNT;

  DELETE FROM #Matches WHERE PatientId IN (SELECT MatchingPatientId FROM #CohortStore);
END

-- 9. There are some people who we can't find a 3rd match.. try relaxing the date requirement
DECLARE @LastRowInsert9 INT;
SET @LastRowInsert9=1;
WHILE ( @LastRowInsert9 > 0)
BEGIN
  INSERT INTO #CohortStore
  SELECT sub.PatientId, sub.YearOfBirth, sub.Sex, MatchedPatientId, m.YearOfBirth FROM (
  SELECT c.PatientId, c.YearOfBirth, c.Sex, MAX(p.PatientId) AS MatchedPatientId, Row_Number() OVER(PARTITION BY MAX(p.PatientId) ORDER BY NewID()) AS AssignedPersonNumber
  FROM #Cases c
  INNER JOIN #Matches p 
    ON p.Sex = c.Sex 
    AND p.YearOfBirth = c.YearOfBirth
  WHERE c.PatientId in (
    -- find patients who currently only have 2 match(es)
select PatientId from #CohortStore group by PatientId having count(*) = 2
  )
  GROUP BY c.PatientId, c.YearOfBirth, c.Sex) sub
  INNER JOIN #Matches m 
    ON m.Sex = sub.Sex 
    AND m.PatientId = sub.MatchedPatientId
    AND m.YearOfBirth = sub.YearOfBirth
  WHERE sub.AssignedPersonNumber = 1
  GROUP BY sub.PatientId, sub.YearOfBirth, sub.Sex, MatchedPatientId, m.YearOfBirth;
  SELECT @LastRowInsert9=@@ROWCOUNT;

  DELETE FROM #Matches WHERE PatientId IN (SELECT MatchingPatientId FROM #CohortStore);
END

-- 10. There are some people who we still can't find a 3rd match.. try relaxing the age and date requirement
DECLARE @LastRowInsert10 INT;
SET @LastRowInsert10=1;
WHILE ( @LastRowInsert10 > 0)
BEGIN
  INSERT INTO #CohortStore
  SELECT sub.PatientId, sub.YearOfBirth, sub.Sex, MatchedPatientId, MAX(m.YearOfBirth) FROM (
  SELECT c.PatientId, c.YearOfBirth, c.Sex, MAX(p.PatientId) AS MatchedPatientId, Row_Number() OVER(PARTITION BY MAX(p.PatientId) ORDER BY NewID()) AS AssignedPersonNumber
  FROM #Cases c
  INNER JOIN #Matches p 
    ON p.Sex = c.Sex 
    AND p.YearOfBirth >= c.YearOfBirth - 1
    AND p.YearOfBirth <= c.YearOfBirth + 1
  WHERE c.PatientId in (
    -- find patients who currently only have 2 match(es)
select PatientId from #CohortStore group by PatientId having count(*) = 2
  )
  GROUP BY c.PatientId, c.YearOfBirth, c.Sex) sub
  INNER JOIN #Matches m 
    ON m.Sex = sub.Sex 
    AND m.PatientId = sub.MatchedPatientId
    AND m.YearOfBirth >= sub.YearOfBirth - 1
    AND m.YearOfBirth <= sub.YearOfBirth + 1
  WHERE sub.AssignedPersonNumber = 1
  GROUP BY sub.PatientId, sub.YearOfBirth, sub.Sex, MatchedPatientId;
  SELECT @LastRowInsert10=@@ROWCOUNT;

  DELETE FROM #Matches WHERE PatientId IN (SELECT MatchingPatientId FROM #CohortStore);
END

--This next query shows how many people with no match, 1 match, 2 match etc.
--SELECT Num, COUNT(*) FROM ( SELECT PatientId, COUNT(*) AS Num FROM #CohortStore GROUP BY PatientId) sub GROUP BY Num UNION SELECT 0, x FROM (SELECT COUNT(*) AS x FROM (SELECT PatientId FROM #Cases EXCEPT SELECT PatientId FROM #CohortStore) sub1) sub ORDER BY Num;

-- 11. Now we focus on people with only 3 match(es) and attempt to give them another
DECLARE @LastRowInsert11 INT;
SET @LastRowInsert11=1;
WHILE ( @LastRowInsert11 > 0)
BEGIN
  INSERT INTO #CohortStore
  SELECT PatientId, YearOfBirth, Sex, MatchedPatientId, YearOfBirth FROM (
  SELECT c.PatientId, c.YearOfBirth, c.Sex, MAX(p.PatientId) AS MatchedPatientId, Row_Number() OVER(PARTITION BY MAX(p.PatientId) ORDER BY NewID()) AS AssignedPersonNumber
  FROM #Cases c
  INNER JOIN #Matches p 
    ON p.Sex = c.Sex 
    AND p.YearOfBirth = c.YearOfBirth
  WHERE c.PatientId in (
    -- find patients who currently only have 3 match(es)
select PatientId from #CohortStore group by PatientId having count(*) = 3
  )
  GROUP BY c.PatientId, c.YearOfBirth, c.Sex) sub
  WHERE sub.AssignedPersonNumber = 1;
  SELECT @LastRowInsert11=@@ROWCOUNT;

  DELETE FROM #Matches WHERE PatientId IN (SELECT MatchingPatientId FROM #CohortStore);
END

-- 12. There are some people who we can't find a 4th match.. try relaxing the date requirement
DECLARE @LastRowInsert12 INT;
SET @LastRowInsert12=1;
WHILE ( @LastRowInsert12 > 0)
BEGIN
  INSERT INTO #CohortStore
  SELECT sub.PatientId, sub.YearOfBirth, sub.Sex, MatchedPatientId, m.YearOfBirth FROM (
  SELECT c.PatientId, c.YearOfBirth, c.Sex, MAX(p.PatientId) AS MatchedPatientId, Row_Number() OVER(PARTITION BY MAX(p.PatientId) ORDER BY NewID()) AS AssignedPersonNumber
  FROM #Cases c
  INNER JOIN #Matches p 
    ON p.Sex = c.Sex 
    AND p.YearOfBirth = c.YearOfBirth
  WHERE c.PatientId in (
    -- find patients who currently only have 3 match(es)
select PatientId from #CohortStore group by PatientId having count(*) = 3
  )
  GROUP BY c.PatientId, c.YearOfBirth, c.Sex) sub
  INNER JOIN #Matches m 
    ON m.Sex = sub.Sex 
    AND m.PatientId = sub.MatchedPatientId
    AND m.YearOfBirth = sub.YearOfBirth
  WHERE sub.AssignedPersonNumber = 1
  GROUP BY sub.PatientId, sub.YearOfBirth, sub.Sex, MatchedPatientId, m.YearOfBirth;
  SELECT @LastRowInsert12=@@ROWCOUNT;

  DELETE FROM #Matches WHERE PatientId IN (SELECT MatchingPatientId FROM #CohortStore);
END

-- 13. There are some people who we still can't find a 4th match.. try relaxing the age and date requirement
DECLARE @LastRowInsert13 INT;
SET @LastRowInsert13=1;
WHILE ( @LastRowInsert13 > 0)
BEGIN
  INSERT INTO #CohortStore
  SELECT sub.PatientId, sub.YearOfBirth, sub.Sex, MatchedPatientId, MAX(m.YearOfBirth) FROM (
  SELECT c.PatientId, c.YearOfBirth, c.Sex, MAX(p.PatientId) AS MatchedPatientId, Row_Number() OVER(PARTITION BY MAX(p.PatientId) ORDER BY NewID()) AS AssignedPersonNumber
  FROM #Cases c
  INNER JOIN #Matches p 
    ON p.Sex = c.Sex 
    AND p.YearOfBirth >= c.YearOfBirth - 1
    AND p.YearOfBirth <= c.YearOfBirth + 1
  WHERE c.PatientId in (
    -- find patients who currently only have 3 match(es)
select PatientId from #CohortStore group by PatientId having count(*) = 3
  )
  GROUP BY c.PatientId, c.YearOfBirth, c.Sex) sub
  INNER JOIN #Matches m 
    ON m.Sex = sub.Sex 
    AND m.PatientId = sub.MatchedPatientId
    AND m.YearOfBirth >= sub.YearOfBirth - 1
    AND m.YearOfBirth <= sub.YearOfBirth + 1
  WHERE sub.AssignedPersonNumber = 1
  GROUP BY sub.PatientId, sub.YearOfBirth, sub.Sex, MatchedPatientId;
  SELECT @LastRowInsert13=@@ROWCOUNT;

  DELETE FROM #Matches WHERE PatientId IN (SELECT MatchingPatientId FROM #CohortStore);
END

--This next query shows how many people with no match, 1 match, 2 match etc.
--SELECT Num, COUNT(*) FROM ( SELECT PatientId, COUNT(*) AS Num FROM #CohortStore GROUP BY PatientId) sub GROUP BY Num UNION SELECT 0, x FROM (SELECT COUNT(*) AS x FROM (SELECT PatientId FROM #Cases EXCEPT SELECT PatientId FROM #CohortStore) sub1) sub ORDER BY Num;

-- 14. Now we focus on people with only 4 match(es) and attempt to give them another
DECLARE @LastRowInsert14 INT;
SET @LastRowInsert14=1;
WHILE ( @LastRowInsert14 > 0)
BEGIN
  INSERT INTO #CohortStore
  SELECT PatientId, YearOfBirth, Sex, MatchedPatientId, YearOfBirth FROM (
  SELECT c.PatientId, c.YearOfBirth, c.Sex, MAX(p.PatientId) AS MatchedPatientId, Row_Number() OVER(PARTITION BY MAX(p.PatientId) ORDER BY NewID()) AS AssignedPersonNumber
  FROM #Cases c
  INNER JOIN #Matches p 
    ON p.Sex = c.Sex 
    AND p.YearOfBirth = c.YearOfBirth
  WHERE c.PatientId in (
    -- find patients who currently only have 4 match(es)
select PatientId from #CohortStore group by PatientId having count(*) = 4
  )
  GROUP BY c.PatientId, c.YearOfBirth, c.Sex) sub
  WHERE sub.AssignedPersonNumber = 1;
  SELECT @LastRowInsert14=@@ROWCOUNT;

  DELETE FROM #Matches WHERE PatientId IN (SELECT MatchingPatientId FROM #CohortStore);
END

-- 15. There are some people who we can't find a 5th match.. try relaxing the date requirement
DECLARE @LastRowInsert15 INT;
SET @LastRowInsert15=1;
WHILE ( @LastRowInsert15 > 0)
BEGIN
  INSERT INTO #CohortStore
  SELECT sub.PatientId, sub.YearOfBirth, sub.Sex, MatchedPatientId, m.YearOfBirth FROM (
  SELECT c.PatientId, c.YearOfBirth, c.Sex, MAX(p.PatientId) AS MatchedPatientId, Row_Number() OVER(PARTITION BY MAX(p.PatientId) ORDER BY NewID()) AS AssignedPersonNumber
  FROM #Cases c
  INNER JOIN #Matches p 
    ON p.Sex = c.Sex 
    AND p.YearOfBirth = c.YearOfBirth
  WHERE c.PatientId in (
    -- find patients who currently only have 4 match(es)
select PatientId from #CohortStore group by PatientId having count(*) = 4
  )
  GROUP BY c.PatientId, c.YearOfBirth, c.Sex) sub
  INNER JOIN #Matches m 
    ON m.Sex = sub.Sex 
    AND m.PatientId = sub.MatchedPatientId
    AND m.YearOfBirth = sub.YearOfBirth
  WHERE sub.AssignedPersonNumber = 1
  GROUP BY sub.PatientId, sub.YearOfBirth, sub.Sex, MatchedPatientId, m.YearOfBirth;
  SELECT @LastRowInsert15=@@ROWCOUNT;

  DELETE FROM #Matches WHERE PatientId IN (SELECT MatchingPatientId FROM #CohortStore);
END

-- 16. There are some people who we still can't find a 5th match.. try relaxing the age and date requirement
DECLARE @LastRowInsert16 INT;
SET @LastRowInsert16=1;
WHILE ( @LastRowInsert16 > 0)
BEGIN
  INSERT INTO #CohortStore
  SELECT sub.PatientId, sub.YearOfBirth, sub.Sex,  MatchedPatientId, MAX(m.YearOfBirth) FROM (
  SELECT c.PatientId, c.YearOfBirth, c.Sex, MAX(p.PatientId) AS MatchedPatientId, Row_Number() OVER(PARTITION BY MAX(p.PatientId) ORDER BY NewID()) AS AssignedPersonNumber
  FROM #Cases c
  INNER JOIN #Matches p 
    ON p.Sex = c.Sex 
    AND p.YearOfBirth >= c.YearOfBirth - 1
    AND p.YearOfBirth <= c.YearOfBirth + 1
  WHERE c.PatientId in (
    -- find patients who currently only have 4 match(es)
select PatientId from #CohortStore group by PatientId having count(*) = 4
  )
  GROUP BY c.PatientId, c.YearOfBirth, c.Sex) sub
  INNER JOIN #Matches m 
    ON m.Sex = sub.Sex 
    AND m.PatientId = sub.MatchedPatientId
    AND m.YearOfBirth >= sub.YearOfBirth - 1
    AND m.YearOfBirth <= sub.YearOfBirth + 1
  WHERE sub.AssignedPersonNumber = 1
  GROUP BY sub.PatientId, sub.YearOfBirth, sub.Sex, MatchedPatientId;
  SELECT @LastRowInsert16=@@ROWCOUNT;

  DELETE FROM #Matches WHERE PatientId IN (SELECT MatchingPatientId FROM #CohortStore);
END


-- Get the matched cohort detail - same as main cohort
IF OBJECT_ID('tempdb..#MatchedCohort') IS NOT NULL DROP TABLE #MatchedCohort;
SELECT 
  c.MatchingPatientId AS FK_Patient_Link_ID,
  Sex,
  MatchingYearOfBirth,
  PatientId AS PatientWhoIsMatched
INTO #MatchedCohort
FROM #CohortStore c
WHERE c.PatientId IN (SELECT FK_Patient_Link_ID FROM #Patients);
--254,824

-- Define a table with all the patient ids for the main cohort and the matched cohort
IF OBJECT_ID('tempdb..#PatientIds') IS NOT NULL DROP TABLE #PatientIds;
SELECT PatientId AS FK_Patient_Link_ID INTO #PatientIds FROM #CohortStore
UNION
SELECT MatchingPatientId FROM #CohortStore;


-- find all covid tests for the main and matched cohort
IF OBJECT_ID('tempdb..#covidtests') IS NOT NULL DROP TABLE #covidtests;
SELECT 
      [FK_Patient_Link_ID]
      ,[EventDate]
      ,[MainCode]
      ,[CodeDescription]
      ,[GroupDescription]
      ,[SubGroupDescription]
	  ,TestOutcome = CASE WHEN GroupDescription = 'Confirmed'														then 'Positive'
			WHEN SubGroupDescription = '' and GroupDescription = 'Excluded'											then 'Negative'
			WHEN SubGroupDescription = '' and GroupDescription = 'Tested' and CodeDescription like '%not detected%' then 'Negative'
			WHEN SubGroupDescription = 'Offered' and GroupDescription = 'Tested'									then 'Unknown/Inconclusive'
			WHEN SubGroupDescription = 'Unknown' 																	then 'Unknown/Inconclusive'
			WHEN SubGroupDescription = '' and GroupDescription = 'Tested' and CodeDescription not like '%detected%' 
							and CodeDescription not like '%positive%' and CodeDescription not like '%negative%'		then 'Unknown/Inconclusive'
			WHEN SubGroupDescription != ''																			then SubGroupDescription
			WHEN SubGroupDescription = '' and CodeDescription like '%reslt unknow%'									then 'Unknown/Inconclusive'
							ELSE 'CHECK' END
INTO #covidtests
FROM [RLS].[vw_COVID19]
WHERE 
	(FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #MainCohort) OR FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #MatchedCohort))
	and GroupDescription != 'Vaccination' 
	and GroupDescription not in ('Exposed', 'Suspected', 'Tested for immunity')
	and (GroupDescription != 'Unknown' and SubGroupDescription != '')

--bring together for final output
--patients in main cohort
SELECT m.FK_Patient_Link_ID
	,NULL AS MainCohortMatchedPatientId
	,TestOutcome
	,TestDate = EventDate
FROM #covidtests cv
LEFT JOIN #MainCohort m ON cv.FK_Patient_Link_ID = m.FK_Patient_Link_ID
where m.FK_Patient_Link_ID is not null
UNION 
--patients in matched cohort
SELECT m.FK_Patient_Link_ID
	,PatientWhoIsMatched AS MainCohortMatchedPatientId
	,TestOutcome
	,TestDate = EventDate
FROM #covidtests cv
LEFT JOIN #MatchedCohort m ON cv.FK_Patient_Link_ID = m.FK_Patient_Link_ID
where m.FK_Patient_Link_ID is not null
--146,101