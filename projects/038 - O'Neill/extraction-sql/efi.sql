--┌──────────┐
--│ EFI file │
--└──────────┘

-- OUTPUT: Data showing the cumulative deficits for each person over time with
--         the following fields:
--  - PatientId
--  - DateFrom - the date from which this number of deficits occurred
--  - NumberOfDeficits - the number of deficits on the DateFrom date

--Just want the output, not the messages
SET NOCOUNT ON;

-- Set the temp end date until new legal basis
DECLARE @TEMPRQ038EndDate datetime;
SET @TEMPRQ038EndDate = '2022-06-01';

-- Build the main cohort
--┌────────────────────────────────────────────────────┐
--│ Define Cohort for RQ038: COVID + frailty project   │
--└────────────────────────────────────────────────────┘

-- OBJECTIVE: To build the cohort of patients needed for RQ038. This reduces
--						duplication of code in the template scripts. The cohort is any
--						patient who was >=60 years old on 1 Jan 2020 and have at least
--				 		one GP recorded positive COVID test
--            UPDATE 21/12/22 - recent SURG approved ALL patients >= 60 years
-- INPUT: A variable:
--	@TEMPRQ038EndDate - the date that we will not get records beyond

-- OUTPUT: Temp tables as follows:
-- #Patients - list of patient ids of the cohort

------------------------------------------------------------------------------

-- Only include patients who were first registered at a GP practice prior
-- to June 2022. This is 1 month before COPI expired and so acts as a buffer.
-- If we only looked at patients who first registered before July 2022, then
-- there is a chance that their data was processed after COPI expired.
IF OBJECT_ID('tempdb..#PatientsToInclude') IS NOT NULL DROP TABLE #PatientsToInclude;
SELECT FK_Patient_Link_ID INTO #PatientsToInclude
FROM SharedCare.Patient_GP_History
GROUP BY FK_Patient_Link_ID
HAVING MIN(StartDate) < @TEMPRQ038EndDate;

-- Table of all patients with COVID at least once
IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT FK_Patient_Link_ID INTO #Patients FROM #PatientsToInclude

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

-- Now restrict to those >=60 on 1st January 2020
TRUNCATE TABLE #Patients;
INSERT INTO #Patients
SELECT FK_Patient_Link_ID FROM #PatientYearOfBirth
WHERE YearOfBirth <= 1959;

-- Forces the code lists to insert here, so we can reference them in the below queries
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

--#region Clinical code sets

IF OBJECT_ID('tempdb..#AllCodes') IS NOT NULL DROP TABLE #AllCodes;
CREATE TABLE #AllCodes (
  [Concept] [varchar](255) NOT NULL,
  [Version] INT NOT NULL,
  [Code] [varchar](20) COLLATE Latin1_General_CS_AS NOT NULL,
  [description] [varchar] (255) NULL 
);

IF OBJECT_ID('tempdb..#codesreadv2') IS NOT NULL DROP TABLE #codesreadv2;
CREATE TABLE #codesreadv2 (
  [concept] [varchar](255) NOT NULL,
  [version] INT NOT NULL,
	[code] [varchar](20) COLLATE Latin1_General_CS_AS NOT NULL,
	[term] [varchar](20) COLLATE Latin1_General_CS_AS NULL,
	[description] [varchar](255) NULL
) ON [PRIMARY];

INSERT INTO #codesreadv2
VALUES ('efi-arthritis',1,'14G..',NULL,'H/O: musculoskeletal disease'),('efi-arthritis',1,'14G..00',NULL,'H/O: musculoskeletal disease'),('efi-arthritis',1,'14G1.',NULL,'H/O: rheumatoid arthritis'),('efi-arthritis',1,'14G1.00',NULL,'H/O: rheumatoid arthritis'),('efi-arthritis',1,'14G2.',NULL,'H/O: osteoarthritis'),('efi-arthritis',1,'14G2.00',NULL,'H/O: osteoarthritis'),('efi-arthritis',1,'52A31',NULL,'Plain X-ray hip joint abnormal'),('efi-arthritis',1,'52A3100',NULL,'Plain X-ray hip joint abnormal'),('efi-arthritis',1,'52A71',NULL,'Plain X-ray knee abnormal'),('efi-arthritis',1,'52A7100',NULL,'Plain X-ray knee abnormal'),('efi-arthritis',1,'66H..',NULL,'Rheumatol. disorder monitoring'),('efi-arthritis',1,'66H..00',NULL,'Rheumatol. disorder monitoring'),('efi-arthritis',1,'N0504',NULL,'Primary general osteoarthrosis'),('efi-arthritis',1,'N050400',NULL,'Primary general osteoarthrosis'),('efi-arthritis',1,'7K3..',NULL,'Knee joint operations'),('efi-arthritis',1,'7K3..00',NULL,'Knee joint operations'),('efi-arthritis',1,'7K30.',NULL,'Tot prosth repl knee + cement'),('efi-arthritis',1,'7K30.00',NULL,'Tot prosth repl knee + cement'),('efi-arthritis',1,'7K32.',NULL,'Other total prosth repl knee'),('efi-arthritis',1,'7K32.00',NULL,'Other total prosth repl knee'),('efi-arthritis',1,'7K6Z3',NULL,'Injection into joint NEC'),('efi-arthritis',1,'7K6Z300',NULL,'Injection into joint NEC'),('efi-arthritis',1,'7K6Z7',NULL,'Inject steroid into knee joint'),('efi-arthritis',1,'7K6Z700',NULL,'Inject steroid into knee joint'),('efi-arthritis',1,'7K6ZK',NULL,'Intra-articular injection'),('efi-arthritis',1,'7K6ZK00',NULL,'Intra-articular injection'),('efi-arthritis',1,'C340.',NULL,'Gouty arthropathy'),('efi-arthritis',1,'C340.00',NULL,'Gouty arthropathy'),('efi-arthritis',1,'C34z.',NULL,'Gout NOS'),('efi-arthritis',1,'C34z.00',NULL,'Gout NOS'),('efi-arthritis',1,'N023.',NULL,'Gouty arthritis'),('efi-arthritis',1,'N023.00',NULL,'Gouty arthritis'),('efi-arthritis',1,'N0310',NULL,'Arthropathy-ulcerative Colitis'),('efi-arthritis',1,'N031000',NULL,'Arthropathy-ulcerative Colitis'),('efi-arthritis',1,'N04..',NULL,'Rheumatoid arthritis+similar'),('efi-arthritis',1,'N04..00',NULL,'Rheumatoid arthritis+similar'),('efi-arthritis',1,'N040.',NULL,'Rheumatoid arthritis'),('efi-arthritis',1,'N040.00',NULL,'Rheumatoid arthritis'),('efi-arthritis',1,'N0400',NULL,'Rheumatoid arthritis-Cx spine'),('efi-arthritis',1,'N040000',NULL,'Rheumatoid arthritis-Cx spine'),('efi-arthritis',1,'N0401',NULL,'Oth rheumatoid arthritis-spine'),('efi-arthritis',1,'N040100',NULL,'Oth rheumatoid arthritis-spine'),('efi-arthritis',1,'N0402',NULL,'Rheumatoid arthritis-shoulder'),('efi-arthritis',1,'N040200',NULL,'Rheumatoid arthritis-shoulder'),('efi-arthritis',1,'N0404',NULL,'Rheumatoid arthr-acromioclav j'),('efi-arthritis',1,'N040400',NULL,'Rheumatoid arthr-acromioclav j'),('efi-arthritis',1,'N0405',NULL,'Rheumatoid arthritis of elbow'),('efi-arthritis',1,'N040500',NULL,'Rheumatoid arthritis of elbow'),('efi-arthritis',1,'N0407',NULL,'Rheumatoid arthritis of wrist'),('efi-arthritis',1,'N040700',NULL,'Rheumatoid arthritis of wrist'),('efi-arthritis',1,'N0408',NULL,'Rheumatoid arthritis-MCP joint'),('efi-arthritis',1,'N040800',NULL,'Rheumatoid arthritis-MCP joint'),('efi-arthritis',1,'N0409',NULL,'Rheumatoid arthritis-PIPJ-fing'),('efi-arthritis',1,'N040900',NULL,'Rheumatoid arthritis-PIPJ-fing'),('efi-arthritis',1,'N040A',NULL,'Rheumatoid arthritis-DIPJ-fing'),('efi-arthritis',1,'N040A00',NULL,'Rheumatoid arthritis-DIPJ-fing'),('efi-arthritis',1,'N040B',NULL,'Rheumatoid arthritis of hip'),('efi-arthritis',1,'N040B00',NULL,'Rheumatoid arthritis of hip'),('efi-arthritis',1,'N040C',NULL,'Rheumatoid arthritis of SIJ'),('efi-arthritis',1,'N040C00',NULL,'Rheumatoid arthritis of SIJ'),('efi-arthritis',1,'N040D',NULL,'Rheumatoid arthritis of knee'),('efi-arthritis',1,'N040D00',NULL,'Rheumatoid arthritis of knee'),('efi-arthritis',1,'N040F',NULL,'Rheumatoid arthritis of ankle'),('efi-arthritis',1,'N040F00',NULL,'Rheumatoid arthritis of ankle'),('efi-arthritis',1,'N040G',NULL,'Rheumatoid arthr-subtalar jnt'),('efi-arthritis',1,'N040G00',NULL,'Rheumatoid arthr-subtalar jnt'),('efi-arthritis',1,'N040H',NULL,'Rheumatoid arthr-talonav joint'),('efi-arthritis',1,'N040H00',NULL,'Rheumatoid arthr-talonav joint'),('efi-arthritis',1,'N040J',NULL,'Rheumatoid arthr-oth tarsal jt'),('efi-arthritis',1,'N040J00',NULL,'Rheumatoid arthr-oth tarsal jt'),('efi-arthritis',1,'N040K',NULL,'Rheumatoid arthr-1st MTP joint'),('efi-arthritis',1,'N040K00',NULL,'Rheumatoid arthr-1st MTP joint'),('efi-arthritis',1,'N040L',NULL,'Rheumatoid arthr-lesser MTP jt'),('efi-arthritis',1,'N040L00',NULL,'Rheumatoid arthr-lesser MTP jt'),('efi-arthritis',1,'N040M',NULL,'Rheumatoid arthr-IP joint-toe'),('efi-arthritis',1,'N040M00',NULL,'Rheumatoid arthr-IP joint-toe'),('efi-arthritis',1,'N040P',NULL,'Seronegative rheumat arthritis'),('efi-arthritis',1,'N040P00',NULL,'Seronegative rheumat arthritis'),('efi-arthritis',1,'N040S',NULL,'Rheumat arthr - multiple joint'),('efi-arthritis',1,'N040S00',NULL,'Rheumat arthr - multiple joint'),('efi-arthritis',1,'N040T',NULL,'Flare of rheumatoid arthritis'),('efi-arthritis',1,'N040T00',NULL,'Flare of rheumatoid arthritis'),('efi-arthritis',1,'N047.',NULL,'Seropositive errosive RA'),('efi-arthritis',1,'N047.00',NULL,'Seropositive errosive RA'),('efi-arthritis',1,'N04X.',NULL,'Seroposit rheum arthr, unsp'),('efi-arthritis',1,'N04X.00',NULL,'Seroposit rheum arthr, unsp'),('efi-arthritis',1,'N05..',NULL,'Osteoarthritis+allied disord.'),('efi-arthritis',1,'N05..00',NULL,'Osteoarthritis+allied disord.'),('efi-arthritis',1,'N050.',NULL,'Generalised osteoarthritis-OA'),('efi-arthritis',1,'N050.00',NULL,'Generalised osteoarthritis-OA'),('efi-arthritis',1,'N0502',NULL,'Generalised OA-multiple sites'),('efi-arthritis',1,'N050200',NULL,'Generalised OA-multiple sites'),('efi-arthritis',1,'N0506',NULL,'Erosive osteoarthrosis'),('efi-arthritis',1,'N050600',NULL,'Erosive osteoarthrosis'),('efi-arthritis',1,'N0535',NULL,'Local.OA unsp.-pelvic/thigh'),('efi-arthritis',1,'N053500',NULL,'Local.OA unsp.-pelvic/thigh'),('efi-arthritis',1,'N0536',NULL,'Local.OA unsp.-lower leg'),('efi-arthritis',1,'N053600',NULL,'Local.OA unsp.-lower leg'),('efi-arthritis',1,'N05z1',NULL,'Osteoarthritis NOS-shoulder'),('efi-arthritis',1,'N05z100',NULL,'Osteoarthritis NOS-shoulder'),('efi-arthritis',1,'N05z4',NULL,'Osteoarthritis NOS-hand'),('efi-arthritis',1,'N05z400',NULL,'Osteoarthritis NOS-hand'),('efi-arthritis',1,'N05z5',NULL,'Osteoarthritis NOS-pelv./thigh'),('efi-arthritis',1,'N05z500',NULL,'Osteoarthritis NOS-pelv./thigh'),('efi-arthritis',1,'N05z6',NULL,'Osteoarthritis NOS-lower leg'),('efi-arthritis',1,'N05z600',NULL,'Osteoarthritis NOS-lower leg'),('efi-arthritis',1,'N05z9',NULL,'Osteoarthritis NOS, shoulder'),('efi-arthritis',1,'N05z900',NULL,'Osteoarthritis NOS, shoulder'),('efi-arthritis',1,'N05zJ',NULL,'OA NOS-hip'),('efi-arthritis',1,'N05zJ00',NULL,'OA NOS-hip'),('efi-arthritis',1,'N05zL',NULL,'Osteoarthritis NOS, of knee'),('efi-arthritis',1,'N05zL00',NULL,'Osteoarthritis NOS, of knee'),('efi-arthritis',1,'N06z.',NULL,'Arthropathy NOS'),('efi-arthritis',1,'N06z.00',NULL,'Arthropathy NOS'),('efi-arthritis',1,'N06z5',NULL,'Arthropathy NOS-pelvic/thigh'),('efi-arthritis',1,'N06z500',NULL,'Arthropathy NOS-pelvic/thigh'),('efi-arthritis',1,'N06z6',NULL,'Arthropathy NOS-lower leg'),('efi-arthritis',1,'N06z600',NULL,'Arthropathy NOS-lower leg'),('efi-arthritis',1,'N06zz',NULL,'Arthropathy NOS'),('efi-arthritis',1,'N06zz00',NULL,'Arthropathy NOS'),('efi-arthritis',1,'N11..',NULL,'Spondylosis + allied disorders'),('efi-arthritis',1,'N11..00',NULL,'Spondylosis + allied disorders'),('efi-arthritis',1,'N11D.',NULL,'Osteoarthritis of spine'),('efi-arthritis',1,'N11D.00',NULL,'Osteoarthritis of spine'),('efi-arthritis',1,'Nyu10',NULL,'[X]Rheum arthrit+inv/o org/sys'),('efi-arthritis',1,'Nyu1000',NULL,'[X]Rheum arthrit+inv/o org/sys'),('efi-arthritis',1,'Nyu11',NULL,'[X]O sero+ve rheumat arthritis'),('efi-arthritis',1,'Nyu1100',NULL,'[X]O sero+ve rheumat arthritis'),('efi-arthritis',1,'Nyu12',NULL,'[X]Oth spcf rheumatd arthritis'),('efi-arthritis',1,'Nyu1200',NULL,'[X]Oth spcf rheumatd arthritis'),('efi-arthritis',1,'Nyu1G',NULL,'[X]Seroposit rheum arthr, unsp'),('efi-arthritis',1,'Nyu1G00',NULL,'[X]Seroposit rheum arthr, unsp');
INSERT INTO #codesreadv2
VALUES ('efi-atrial-fibrillation',1,'14AN.',NULL,'H/O: atrial fibrillation'),('efi-atrial-fibrillation',1,'14AN.00',NULL,'H/O: atrial fibrillation'),('efi-atrial-fibrillation',1,'2432.',NULL,'O/E - pulse irregularly irreg.'),('efi-atrial-fibrillation',1,'2432.00',NULL,'O/E - pulse irregularly irreg.'),('efi-atrial-fibrillation',1,'3272.',NULL,'ECG: atrial fibrillation'),('efi-atrial-fibrillation',1,'3272.00',NULL,'ECG: atrial fibrillation'),('efi-atrial-fibrillation',1,'3273.',NULL,'ECG: atrial flutter'),('efi-atrial-fibrillation',1,'3273.00',NULL,'ECG: atrial flutter'),('efi-atrial-fibrillation',1,'662S.',NULL,'Atrial fibrillation monitoring'),('efi-atrial-fibrillation',1,'662S.00',NULL,'Atrial fibrillation monitoring'),('efi-atrial-fibrillation',1,'6A9..',NULL,'Atrial fibrillat annual review'),('efi-atrial-fibrillation',1,'6A9..00',NULL,'Atrial fibrillat annual review'),('efi-atrial-fibrillation',1,'7936A',NULL,'IV pacer control atrial fibril'),('efi-atrial-fibrillation',1,'7936A00',NULL,'IV pacer control atrial fibril'),('efi-atrial-fibrillation',1,'9Os1.',NULL,'Atrial fibril monit 2nd letter'),('efi-atrial-fibrillation',1,'9Os1.00',NULL,'Atrial fibril monit 2nd letter'),('efi-atrial-fibrillation',1,'9hF0.',NULL,'Excep atr fib qual ind: Pt uns'),('efi-atrial-fibrillation',1,'9hF0.00',NULL,'Excep atr fib qual ind: Pt uns'),('efi-atrial-fibrillation',1,'9hF1.',NULL,'Exc atr fib qual ind: Inf diss'),('efi-atrial-fibrillation',1,'9hF1.00',NULL,'Exc atr fib qual ind: Inf diss'),('efi-atrial-fibrillation',1,'G573.',NULL,'Atrial fibrillation/flutter'),('efi-atrial-fibrillation',1,'G573.00',NULL,'Atrial fibrillation/flutter'),('efi-atrial-fibrillation',1,'G5730',NULL,'Atrial fibrillation'),('efi-atrial-fibrillation',1,'G573000',NULL,'Atrial fibrillation'),('efi-atrial-fibrillation',1,'G5731',NULL,'Atrial flutter'),('efi-atrial-fibrillation',1,'G573100',NULL,'Atrial flutter'),('efi-atrial-fibrillation',1,'G5732',NULL,'Paroxysmal atrial fibrillation'),('efi-atrial-fibrillation',1,'G573200',NULL,'Paroxysmal atrial fibrillation'),('efi-atrial-fibrillation',1,'G5733',NULL,'Non-rheumatic atrial fibrill'),('efi-atrial-fibrillation',1,'G573300',NULL,'Non-rheumatic atrial fibrill'),('efi-atrial-fibrillation',1,'G5734',NULL,'Permanent atrial fibrillation'),('efi-atrial-fibrillation',1,'G573400',NULL,'Permanent atrial fibrillation'),('efi-atrial-fibrillation',1,'G5735',NULL,'Persistent atrial fibrillation'),('efi-atrial-fibrillation',1,'G573500',NULL,'Persistent atrial fibrillation'),('efi-atrial-fibrillation',1,'G573z',NULL,'Atrial fibrillat./flutter NOS'),('efi-atrial-fibrillation',1,'G573z00',NULL,'Atrial fibrillat./flutter NOS');
INSERT INTO #codesreadv2
VALUES ('efi-chd',1,'79294',NULL,'Insert coronary artery stent'),('efi-chd',1,'7929400',NULL,'Insert coronary artery stent'),('efi-chd',1,'14A..',NULL,'H/O: cardiovascular disease'),('efi-chd',1,'14A..00',NULL,'H/O: cardiovascular disease'),('efi-chd',1,'14A4.',NULL,'H/O: myocardial infarct >60'),('efi-chd',1,'14A4.00',NULL,'H/O: myocardial infarct >60'),('efi-chd',1,'14A5.',NULL,'H/O: angina pectoris'),('efi-chd',1,'14A5.00',NULL,'H/O: angina pectoris'),('efi-chd',1,'322..',NULL,'ECG: myocardial ischaemia'),('efi-chd',1,'322..00',NULL,'ECG: myocardial ischaemia'),('efi-chd',1,'3222.',NULL,'ECG:shows myocardial ischaemia'),('efi-chd',1,'3222.00',NULL,'ECG:shows myocardial ischaemia'),('efi-chd',1,'322Z.',NULL,'ECG: myocardial ischaemia NOS'),('efi-chd',1,'322Z.00',NULL,'ECG: myocardial ischaemia NOS'),('efi-chd',1,'662K0',NULL,'Angina control - good'),('efi-chd',1,'662K000',NULL,'Angina control - good'),('efi-chd',1,'662K1',NULL,'Angina control - poor'),('efi-chd',1,'662K100',NULL,'Angina control - poor'),('efi-chd',1,'662K3',NULL,'Angina control - worsening'),('efi-chd',1,'662K300',NULL,'Angina control - worsening'),('efi-chd',1,'6A2..',NULL,'Corony heart dis annual review'),('efi-chd',1,'6A2..00',NULL,'Corony heart dis annual review'),('efi-chd',1,'6A4..',NULL,'Coronary heart disease review'),('efi-chd',1,'6A4..00',NULL,'Coronary heart disease review'),('efi-chd',1,'792..',NULL,'Coronary artery operations'),('efi-chd',1,'792..00',NULL,'Coronary artery operations'),('efi-chd',1,'7928.',NULL,'Translum balloon angiop coro a'),('efi-chd',1,'7928.00',NULL,'Translum balloon angiop coro a'),('efi-chd',1,'889A.',NULL,'Diab mell ins gluc inf ac mi'),('efi-chd',1,'889A.00',NULL,'Diab mell ins gluc inf ac mi'),('efi-chd',1,'8H2V.',NULL,'Admit isch heart dis emergency'),('efi-chd',1,'8H2V.00',NULL,'Admit isch heart dis emergency'),('efi-chd',1,'8I3z.',NULL,'Cardiovsc dis ann reviw dcline'),('efi-chd',1,'8I3z.00',NULL,'Cardiovsc dis ann reviw dcline'),('efi-chd',1,'G3...',NULL,'Ischaemic heart disease'),('efi-chd',1,'G3...00',NULL,'Ischaemic heart disease'),('efi-chd',1,'G30..',NULL,'Acute myocardial infarction'),('efi-chd',1,'G30..00',NULL,'Acute myocardial infarction'),('efi-chd',1,'G3071',NULL,'Acute non-ST seg elevation mi'),('efi-chd',1,'G307100',NULL,'Acute non-ST seg elevation mi'),('efi-chd',1,'G308.',NULL,'Inferior myocard. infarct NOS'),('efi-chd',1,'G308.00',NULL,'Inferior myocard. infarct NOS'),('efi-chd',1,'G30y.',NULL,'Other acute myocardial infarct'),('efi-chd',1,'G30y.00',NULL,'Other acute myocardial infarct'),('efi-chd',1,'G30yz',NULL,'Other acute myocardial inf.NOS'),('efi-chd',1,'G30yz00',NULL,'Other acute myocardial inf.NOS'),('efi-chd',1,'G30z.',NULL,'Acute myocardial infarct. NOS'),('efi-chd',1,'G30z.00',NULL,'Acute myocardial infarct. NOS'),('efi-chd',1,'G31..',NULL,'Other acute/subacute IHD'),('efi-chd',1,'G31..00',NULL,'Other acute/subacute IHD'),('efi-chd',1,'G311.',NULL,'Preinfarction syndrome'),('efi-chd',1,'G311.00',NULL,'Preinfarction syndrome'),('efi-chd',1,'G3111',NULL,'Unstable angina'),('efi-chd',1,'G311100',NULL,'Unstable angina'),('efi-chd',1,'G31y2',NULL,'Subendocardial ischaemia'),('efi-chd',1,'G31y200',NULL,'Subendocardial ischaemia'),('efi-chd',1,'G31y3',NULL,'Transient myocardial ischaemia'),('efi-chd',1,'G31y300',NULL,'Transient myocardial ischaemia'),('efi-chd',1,'G31yz',NULL,'Other acute/subacute IHD NOS'),('efi-chd',1,'G31yz00',NULL,'Other acute/subacute IHD NOS'),('efi-chd',1,'G32..',NULL,'Old myocardial infarction'),('efi-chd',1,'G32..00',NULL,'Old myocardial infarction'),('efi-chd',1,'G33..',NULL,'Angina pectoris'),('efi-chd',1,'G33..00',NULL,'Angina pectoris'),('efi-chd',1,'G332.',NULL,'Coronary artery spasm'),('efi-chd',1,'G332.00',NULL,'Coronary artery spasm'),('efi-chd',1,'G33z.',NULL,'Angina pectoris NOS'),('efi-chd',1,'G33z.00',NULL,'Angina pectoris NOS'),('efi-chd',1,'G33z3',NULL,'Angina on effort'),('efi-chd',1,'G33z300',NULL,'Angina on effort'),('efi-chd',1,'G33z4',NULL,'Ischaemic chest pain'),('efi-chd',1,'G33z400',NULL,'Ischaemic chest pain'),('efi-chd',1,'G33z7',NULL,'Stable angina'),('efi-chd',1,'G33z700',NULL,'Stable angina'),('efi-chd',1,'G33zz',NULL,'Angina pectoris NOS'),('efi-chd',1,'G33zz00',NULL,'Angina pectoris NOS'),('efi-chd',1,'G34..',NULL,'Other chr.ischaemic heart dis.'),('efi-chd',1,'G34..00',NULL,'Other chr.ischaemic heart dis.'),('efi-chd',1,'G340.',NULL,'Coronary atherosclerosis'),('efi-chd',1,'G340.00',NULL,'Coronary atherosclerosis'),('efi-chd',1,'G344.',NULL,'Silent myocardial ischaemia'),('efi-chd',1,'G344.00',NULL,'Silent myocardial ischaemia'),('efi-chd',1,'G34y0',NULL,'Chronic coronary insufficiency'),('efi-chd',1,'G34y000',NULL,'Chronic coronary insufficiency'),('efi-chd',1,'G34y1',NULL,'Chronic myocardial ischaemia'),('efi-chd',1,'G34y100',NULL,'Chronic myocardial ischaemia'),('efi-chd',1,'G34yz',NULL,'Other specif.chronic IHD NOS'),('efi-chd',1,'G34yz00',NULL,'Other specif.chronic IHD NOS'),('efi-chd',1,'G34z.',NULL,'Other chronic IHD NOS'),('efi-chd',1,'G34z.00',NULL,'Other chronic IHD NOS'),('efi-chd',1,'G36..',NULL,'Certain curnt comp fol acut MI'),('efi-chd',1,'G36..00',NULL,'Certain curnt comp fol acut MI'),('efi-chd',1,'G361.',NULL,'Atrl sept def/c comp fol ac MI'),('efi-chd',1,'G361.00',NULL,'Atrl sept def/c comp fol ac MI'),('efi-chd',1,'G362.',NULL,'Vent sep def/c comp fol ac MI'),('efi-chd',1,'G362.00',NULL,'Vent sep def/c comp fol ac MI'),('efi-chd',1,'G37..',NULL,'Cardiac syndrome X'),('efi-chd',1,'G37..00',NULL,'Cardiac syndrome X'),('efi-chd',1,'G3y..',NULL,'Ischaemic heart disease OS'),('efi-chd',1,'G3y..00',NULL,'Ischaemic heart disease OS'),('efi-chd',1,'G3z..',NULL,'Ischaemic heart disease NOS'),('efi-chd',1,'G3z..00',NULL,'Ischaemic heart disease NOS'),('efi-chd',1,'Gyu3.',NULL,'[X]Ischaemic heart diseases'),('efi-chd',1,'Gyu3.00',NULL,'[X]Ischaemic heart diseases'),('efi-chd',1,'Gyu30',NULL,'[X]Other forms/angina pectoris'),('efi-chd',1,'Gyu3000',NULL,'[X]Other forms/angina pectoris');
INSERT INTO #codesreadv2
VALUES ('efi-ckd',1,'1Z1..',NULL,'Chronic renal impairment'),('efi-ckd',1,'1Z1..00',NULL,'Chronic renal impairment'),('efi-ckd',1,'1Z12.',NULL,'Chronic kidney disease stage 3'),('efi-ckd',1,'1Z12.00',NULL,'Chronic kidney disease stage 3'),('efi-ckd',1,'1Z13.',NULL,'Chronic kidney disease stage 4'),('efi-ckd',1,'1Z13.00',NULL,'Chronic kidney disease stage 4'),('efi-ckd',1,'1Z14.',NULL,'Chronic kidney disease stage 5'),('efi-ckd',1,'1Z14.00',NULL,'Chronic kidney disease stage 5'),('efi-ckd',1,'1Z15.',NULL,'Chronic kidney diseas stage 3A'),('efi-ckd',1,'1Z15.00',NULL,'Chronic kidney diseas stage 3A'),('efi-ckd',1,'1Z16.',NULL,'Chronic kidney diseas stage 3B'),('efi-ckd',1,'1Z16.00',NULL,'Chronic kidney diseas stage 3B'),('efi-ckd',1,'1Z1B.',NULL,'CKD stage 3 with proteinuria'),('efi-ckd',1,'1Z1B.00',NULL,'CKD stage 3 with proteinuria'),('efi-ckd',1,'1Z1C.',NULL,'CKD stage 3 wthout proteinuria'),('efi-ckd',1,'1Z1C.00',NULL,'CKD stage 3 wthout proteinuria'),('efi-ckd',1,'1Z1D.',NULL,'CKD stage 3A with proteinuria'),('efi-ckd',1,'1Z1D.00',NULL,'CKD stage 3A with proteinuria'),('efi-ckd',1,'1Z1E.',NULL,'CKD stge 3A wthout proteinuria'),('efi-ckd',1,'1Z1E.00',NULL,'CKD stge 3A wthout proteinuria'),('efi-ckd',1,'1Z1F.',NULL,'CKD stage 3B with proteinuria'),('efi-ckd',1,'1Z1F.00',NULL,'CKD stage 3B with proteinuria'),('efi-ckd',1,'1Z1G.',NULL,'CKD stge 3B wthout proteinuria'),('efi-ckd',1,'1Z1G.00',NULL,'CKD stge 3B wthout proteinuria'),('efi-ckd',1,'1Z1H.',NULL,'CKD stage 4 with proteinuria'),('efi-ckd',1,'1Z1H.00',NULL,'CKD stage 4 with proteinuria'),('efi-ckd',1,'1Z1J.',NULL,'CKD stage 4 wthout proteinuria'),('efi-ckd',1,'1Z1J.00',NULL,'CKD stage 4 wthout proteinuria'),('efi-ckd',1,'1Z1K.',NULL,'CKD stage 5 with proteinuria'),('efi-ckd',1,'1Z1K.00',NULL,'CKD stage 5 with proteinuria'),('efi-ckd',1,'1Z1L.',NULL,'CKD stage 5 wthout proteinuria'),('efi-ckd',1,'1Z1L.00',NULL,'CKD stage 5 wthout proteinuria'),('efi-ckd',1,'4677.',NULL,'Urine protein test = ++++'),('efi-ckd',1,'4677.00',NULL,'Urine protein test = ++++'),('efi-ckd',1,'6AA..',NULL,'Chronic kid dis annual review'),('efi-ckd',1,'6AA..00',NULL,'Chronic kid dis annual review'),('efi-ckd',1,'9hE0.',NULL,'Ex ch kid dis qu ind: Pat uns'),('efi-ckd',1,'9hE0.00',NULL,'Ex ch kid dis qu ind: Pat uns'),('efi-ckd',1,'9hE1.',NULL,'Ex ch kid dis qua ind: Inf dis'),('efi-ckd',1,'9hE1.00',NULL,'Ex ch kid dis qua ind: Inf dis'),('efi-ckd',1,'C104.',NULL,'Diab.mell. with nephropathy'),('efi-ckd',1,'C104.00',NULL,'Diab.mell. with nephropathy'),('efi-ckd',1,'C104y',NULL,'Oth specfd diab mel+renal comp'),('efi-ckd',1,'C104y00',NULL,'Oth specfd diab mel+renal comp'),('efi-ckd',1,'C104z',NULL,'Diab.mell.+nephropathy NOS'),('efi-ckd',1,'C104z00',NULL,'Diab.mell.+nephropathy NOS'),('efi-ckd',1,'C1080',NULL,'Insuln-dep diab mel+renal comp'),('efi-ckd',1,'C108000',NULL,'Insuln-dep diab mel+renal comp'),('efi-ckd',1,'C108D',NULL,'IDDM with nephropathy'),('efi-ckd',1,'C108D00',NULL,'IDDM with nephropathy'),('efi-ckd',1,'C1090',NULL,'Non-ins-dp diab mel+renal comp'),('efi-ckd',1,'C109000',NULL,'Non-ins-dp diab mel+renal comp'),('efi-ckd',1,'C1093',NULL,'Non-ins-dp diab mel+multi comp'),('efi-ckd',1,'C109300',NULL,'Non-ins-dp diab mel+multi comp'),('efi-ckd',1,'C109C',NULL,'NIDDM with nephropathy'),('efi-ckd',1,'C109C00',NULL,'NIDDM with nephropathy'),('efi-ckd',1,'C10E0',NULL,'Type 1 d m with renal comps'),('efi-ckd',1,'C10E000',NULL,'Type 1 d m with renal comps'),('efi-ckd',1,'C10ED',NULL,'Type 1 diab mell + nephropathy'),('efi-ckd',1,'C10ED00',NULL,'Type 1 diab mell + nephropathy'),('efi-ckd',1,'C10EK',NULL,'Type 1 d m + persist proteinur'),('efi-ckd',1,'C10EK00',NULL,'Type 1 d m + persist proteinur'),('efi-ckd',1,'C10EL',NULL,'Type 1 d m + persist microalb'),('efi-ckd',1,'C10EL00',NULL,'Type 1 d m + persist microalb'),('efi-ckd',1,'C10F0',NULL,'Type 2 diab mell + renal compl'),('efi-ckd',1,'C10F000',NULL,'Type 2 diab mell + renal compl'),('efi-ckd',1,'C10F3',NULL,'Type 2 diab mell + multip comp'),('efi-ckd',1,'C10F300',NULL,'Type 2 diab mell + multip comp'),('efi-ckd',1,'C10FC',NULL,'Type 2 diab mell + nephropathy'),('efi-ckd',1,'C10FC00',NULL,'Type 2 diab mell + nephropathy'),('efi-ckd',1,'C10FL',NULL,'Type 2 d m + persist proteinur'),('efi-ckd',1,'C10FL00',NULL,'Type 2 d m + persist proteinur'),('efi-ckd',1,'C10FM',NULL,'Type 2 d m + persist microalb'),('efi-ckd',1,'C10FM00',NULL,'Type 2 d m + persist microalb'),('efi-ckd',1,'Cyu23',NULL,'[X]Unspec diab mel + ren compl'),('efi-ckd',1,'Cyu2300',NULL,'[X]Unspec diab mel + ren compl'),('efi-ckd',1,'K05..',NULL,'Chronic renal failure'),('efi-ckd',1,'K05..00',NULL,'Chronic renal failure'),('efi-ckd',1,'K050.',NULL,'End stage renal failure'),('efi-ckd',1,'K050.00',NULL,'End stage renal failure'),('efi-ckd',1,'PD13.',NULL,'Multicystic renal dysplasia'),('efi-ckd',1,'PD13.00',NULL,'Multicystic renal dysplasia'),('efi-ckd',1,'R110.',NULL,'[D]Proteinuria'),('efi-ckd',1,'R110.00',NULL,'[D]Proteinuria');
INSERT INTO #codesreadv2
VALUES ('efi-diabetes',1,'2BBR.',NULL,'O/E - R eye preprolif diab ret'),('efi-diabetes',1,'2BBR.00',NULL,'O/E - R eye preprolif diab ret'),('efi-diabetes',1,'2BBS.',NULL,'O/E - L eye preprolif diab ret'),('efi-diabetes',1,'2BBS.00',NULL,'O/E - L eye preprolif diab ret'),('efi-diabetes',1,'2BBT.',NULL,'O/E - R eye prolif diab ret'),('efi-diabetes',1,'2BBT.00',NULL,'O/E - R eye prolif diab ret'),('efi-diabetes',1,'2G5L.',NULL,'O/E - L diab foot - ulcerated'),('efi-diabetes',1,'2G5L.00',NULL,'O/E - L diab foot - ulcerated'),('efi-diabetes',1,'42W3.',NULL,'Hb. A1C > 10% - bad control'),('efi-diabetes',1,'42W3.00',NULL,'Hb. A1C > 10% - bad control'),('efi-diabetes',1,'42c..',NULL,'HbA1 - diabetic control'),('efi-diabetes',1,'42c..00',NULL,'HbA1 - diabetic control'),('efi-diabetes',1,'66A..',NULL,'Diabetic monitoring'),('efi-diabetes',1,'66A..00',NULL,'Diabetic monitoring'),('efi-diabetes',1,'66A4.',NULL,'Diabetic on oral treatment'),('efi-diabetes',1,'66A4.00',NULL,'Diabetic on oral treatment'),('efi-diabetes',1,'66A5.',NULL,'Diabetic on insulin'),('efi-diabetes',1,'66A5.00',NULL,'Diabetic on insulin'),('efi-diabetes',1,'66AD.',NULL,'Fundoscopy - diabetic check'),('efi-diabetes',1,'66AD.00',NULL,'Fundoscopy - diabetic check'),('efi-diabetes',1,'66AH0',NULL,'Conversion to insulin'),('efi-diabetes',1,'66AH000',NULL,'Conversion to insulin'),('efi-diabetes',1,'66AJ.',NULL,'Diabetic - poor control'),('efi-diabetes',1,'66AJ.00',NULL,'Diabetic - poor control'),('efi-diabetes',1,'66AR.',NULL,'Diabetes management plan given'),('efi-diabetes',1,'66AR.00',NULL,'Diabetes management plan given'),('efi-diabetes',1,'66AS.',NULL,'Diabetic annual review'),('efi-diabetes',1,'66AS.00',NULL,'Diabetic annual review'),('efi-diabetes',1,'66AU.',NULL,'Diabetes care by hospital only'),('efi-diabetes',1,'66AU.00',NULL,'Diabetes care by hospital only'),('efi-diabetes',1,'66AZ.',NULL,'Diabetic monitoring NOS'),('efi-diabetes',1,'66AZ.00',NULL,'Diabetic monitoring NOS'),('efi-diabetes',1,'66Ab.',NULL,'Diabetic foot examination'),('efi-diabetes',1,'66Ab.00',NULL,'Diabetic foot examination'),('efi-diabetes',1,'66Ac.',NULL,'Diabetic periph neurop screen'),('efi-diabetes',1,'66Ac.00',NULL,'Diabetic periph neurop screen'),('efi-diabetes',1,'66Ai.',NULL,'Diabetic 6 month review'),('efi-diabetes',1,'66Ai.00',NULL,'Diabetic 6 month review'),('efi-diabetes',1,'66Aq.',NULL,'Diabetic foot screen'),('efi-diabetes',1,'66Aq.00',NULL,'Diabetic foot screen'),('efi-diabetes',1,'68A7.',NULL,'Diabetic retinopathy screening'),('efi-diabetes',1,'68A7.00',NULL,'Diabetic retinopathy screening'),('efi-diabetes',1,'8A17.',NULL,'Self monitoring blood glucose'),('efi-diabetes',1,'8A17.00',NULL,'Self monitoring blood glucose'),('efi-diabetes',1,'8BL2.',NULL,'Pt on max tol ther for diabet'),('efi-diabetes',1,'8BL2.00',NULL,'Pt on max tol ther for diabet'),('efi-diabetes',1,'8CR2.',NULL,'Diabetes clin management plan'),('efi-diabetes',1,'8CR2.00',NULL,'Diabetes clin management plan'),('efi-diabetes',1,'8H7f.',NULL,'Referral to diabetes nurse'),('efi-diabetes',1,'8H7f.00',NULL,'Referral to diabetes nurse'),('efi-diabetes',1,'8HBG.',NULL,'Diab retinopathy 12 mth review'),('efi-diabetes',1,'8HBG.00',NULL,'Diab retinopathy 12 mth review'),('efi-diabetes',1,'8HBH.',NULL,'Diab retinopathy 6 mth review'),('efi-diabetes',1,'8HBH.00',NULL,'Diab retinopathy 6 mth review'),('efi-diabetes',1,'8Hl1.',NULL,'Ref diabetc retinopathy screen'),('efi-diabetes',1,'8Hl1.00',NULL,'Ref diabetc retinopathy screen'),('efi-diabetes',1,'9NND.',NULL,'Under care of diab foot screen'),('efi-diabetes',1,'9NND.00',NULL,'Under care of diab foot screen'),('efi-diabetes',1,'9OL1.',NULL,'Attends diabetes monitoring'),('efi-diabetes',1,'9OL1.00',NULL,'Attends diabetes monitoring'),('efi-diabetes',1,'9OLD.',NULL,'Diabet pt unsuit dig ret photo'),('efi-diabetes',1,'9OLD.00',NULL,'Diabet pt unsuit dig ret photo'),('efi-diabetes',1,'9h4..',NULL,'Except report: diabet qual ind'),('efi-diabetes',1,'9h4..00',NULL,'Except report: diabet qual ind'),('efi-diabetes',1,'9h41.',NULL,'Except diabet qual ind: Pt uns'),('efi-diabetes',1,'9h41.00',NULL,'Except diabet qual ind: Pt uns'),('efi-diabetes',1,'9h42.',NULL,'Excep diabet qual ind: Inf dis'),('efi-diabetes',1,'9h42.00',NULL,'Excep diabet qual ind: Inf dis'),('efi-diabetes',1,'C10..',NULL,'Diabetes mellitus'),('efi-diabetes',1,'C10..00',NULL,'Diabetes mellitus'),('efi-diabetes',1,'C100.',NULL,'Diab.mell. - no complication'),('efi-diabetes',1,'C100.00',NULL,'Diab.mell. - no complication'),('efi-diabetes',1,'C1000',NULL,'Diab.mell.no comp. - juvenile'),('efi-diabetes',1,'C100000',NULL,'Diab.mell.no comp. - juvenile'),('efi-diabetes',1,'C1001',NULL,'Diab.mell.no comp. - adult'),('efi-diabetes',1,'C100100',NULL,'Diab.mell.no comp. - adult'),('efi-diabetes',1,'C100z',NULL,'Diab.mell.no comp. - onset NOS'),('efi-diabetes',1,'C100z00',NULL,'Diab.mell.no comp. - onset NOS'),('efi-diabetes',1,'C101.',NULL,'Diab.mell.with ketoacidosis'),('efi-diabetes',1,'C101.00',NULL,'Diab.mell.with ketoacidosis'),('efi-diabetes',1,'C1010',NULL,'Diab.mell.+ketoacid - juvenile'),('efi-diabetes',1,'C101000',NULL,'Diab.mell.+ketoacid - juvenile'),('efi-diabetes',1,'C1011',NULL,'Diab.mell.+ketoacid - adult'),('efi-diabetes',1,'C101100',NULL,'Diab.mell.+ketoacid - adult'),('efi-diabetes',1,'C101y',NULL,'Oth specfd diab mel+ketoacidos'),('efi-diabetes',1,'C101y00',NULL,'Oth specfd diab mel+ketoacidos'),('efi-diabetes',1,'C101z',NULL,'Diab.mell.+ketoacid -onset NOS'),('efi-diabetes',1,'C101z00',NULL,'Diab.mell.+ketoacid -onset NOS'),('efi-diabetes',1,'C102.',NULL,'Diab.mell. + hyperosmolar coma'),('efi-diabetes',1,'C102.00',NULL,'Diab.mell. + hyperosmolar coma'),('efi-diabetes',1,'C102z',NULL,'Diabetes+hyperosmolar coma NOS'),('efi-diabetes',1,'C102z00',NULL,'Diabetes+hyperosmolar coma NOS'),('efi-diabetes',1,'C103.',NULL,'Diab.mell. + ketoacidotic coma'),('efi-diabetes',1,'C103.00',NULL,'Diab.mell. + ketoacidotic coma'),('efi-diabetes',1,'C1030',NULL,'Diab.mell.+ketoac coma-juvenil'),('efi-diabetes',1,'C103000',NULL,'Diab.mell.+ketoac coma-juvenil'),('efi-diabetes',1,'C1031',NULL,'Diab.mell.+ketoac coma - adult'),('efi-diabetes',1,'C103100',NULL,'Diab.mell.+ketoac coma - adult'),('efi-diabetes',1,'C103y',NULL,'Oth specif diab mell with coma'),('efi-diabetes',1,'C103y00',NULL,'Oth specif diab mell with coma'),('efi-diabetes',1,'C104.',NULL,'Diab.mell. with nephropathy'),('efi-diabetes',1,'C104.00',NULL,'Diab.mell. with nephropathy'),('efi-diabetes',1,'C104y',NULL,'Oth specfd diab mel+renal comp'),('efi-diabetes',1,'C104y00',NULL,'Oth specfd diab mel+renal comp'),('efi-diabetes',1,'C104z',NULL,'Diab.mell.+nephropathy NOS'),('efi-diabetes',1,'C104z00',NULL,'Diab.mell.+nephropathy NOS'),('efi-diabetes',1,'C105.',NULL,'Diab.mell.+ eye manifestation'),('efi-diabetes',1,'C105.00',NULL,'Diab.mell.+ eye manifestation'),('efi-diabetes',1,'C105y',NULL,'Oth specfd diab mel+ophth comp'),('efi-diabetes',1,'C105y00',NULL,'Oth specfd diab mel+ophth comp'),('efi-diabetes',1,'C105z',NULL,'Diab.mell.+eye manif NOS'),('efi-diabetes',1,'C105z00',NULL,'Diab.mell.+eye manif NOS'),('efi-diabetes',1,'C106.',NULL,'Diab.mell. with neuropathy'),('efi-diabetes',1,'C106.00',NULL,'Diab.mell. with neuropathy'),('efi-diabetes',1,'C1061',NULL,'Diab.mell.+neuropathy - adult'),('efi-diabetes',1,'C106100',NULL,'Diab.mell.+neuropathy - adult'),('efi-diabetes',1,'C106y',NULL,'Oth specf diab mel+neuro comps'),('efi-diabetes',1,'C106y00',NULL,'Oth specf diab mel+neuro comps'),('efi-diabetes',1,'C106z',NULL,'Diab.mell.+neuropathy NOS'),('efi-diabetes',1,'C106z00',NULL,'Diab.mell.+neuropathy NOS'),('efi-diabetes',1,'C107.',NULL,'Diab.mell.+periph.circul.dis'),('efi-diabetes',1,'C107.00',NULL,'Diab.mell.+periph.circul.dis'),('efi-diabetes',1,'C107z',NULL,'Diab.+periph.circ.disease NOS'),('efi-diabetes',1,'C107z00',NULL,'Diab.+periph.circ.disease NOS'),('efi-diabetes',1,'C108.',NULL,'Insulin depnd diabetes melitus'),('efi-diabetes',1,'C108.00',NULL,'Insulin depnd diabetes melitus'),('efi-diabetes',1,'C1080',NULL,'Insuln-dep diab mel+renal comp'),('efi-diabetes',1,'C108000',NULL,'Insuln-dep diab mel+renal comp'),('efi-diabetes',1,'C1081',NULL,'Insul-dep diab mel+ophth comps'),('efi-diabetes',1,'C108100',NULL,'Insul-dep diab mel+ophth comps'),('efi-diabetes',1,'C1082',NULL,'Insul-dep diab mel+neuro comps'),('efi-diabetes',1,'C108200',NULL,'Insul-dep diab mel+neuro comps'),('efi-diabetes',1,'C1083',NULL,'Insul dep diab mel+multi comps'),('efi-diabetes',1,'C108300',NULL,'Insul dep diab mel+multi comps'),('efi-diabetes',1,'C1085',NULL,'Insul depen diab mel+ulcer'),('efi-diabetes',1,'C108500',NULL,'Insul depen diab mel+ulcer'),('efi-diabetes',1,'C1086',NULL,'Insulin depen diab mel+gangren'),('efi-diabetes',1,'C108600',NULL,'Insulin depen diab mel+gangren'),('efi-diabetes',1,'C1087',NULL,'Insul-depend diab mell+retinop'),('efi-diabetes',1,'C108700',NULL,'Insul-depend diab mell+retinop'),('efi-diabetes',1,'C1088',NULL,'Insul dep diab mell-poor contr'),('efi-diabetes',1,'C108800',NULL,'Insul dep diab mell-poor contr'),('efi-diabetes',1,'C1089',NULL,'Insulin dep diabet adult onset'),('efi-diabetes',1,'C108900',NULL,'Insulin dep diabet adult onset'),('efi-diabetes',1,'C108A',NULL,'Insulin-dependent dm no comp'),('efi-diabetes',1,'C108A00',NULL,'Insulin-dependent dm no comp'),('efi-diabetes',1,'C108B',NULL,'IDDM with mononeuropathy'),('efi-diabetes',1,'C108B00',NULL,'IDDM with mononeuropathy'),('efi-diabetes',1,'C108C',NULL,'IDDM with polyneuropathy'),('efi-diabetes',1,'C108C00',NULL,'IDDM with polyneuropathy'),('efi-diabetes',1,'C108D',NULL,'IDDM with nephropathy'),('efi-diabetes',1,'C108D00',NULL,'IDDM with nephropathy'),('efi-diabetes',1,'C108E',NULL,'IDDM with hypoglycaemic coma'),('efi-diabetes',1,'C108E00',NULL,'IDDM with hypoglycaemic coma'),('efi-diabetes',1,'C108F',NULL,'IDDM with diabetic cataract'),('efi-diabetes',1,'C108F00',NULL,'IDDM with diabetic cataract'),
('efi-diabetes',1,'C108J',NULL,'IDDM with neuropath arthropath'),('efi-diabetes',1,'C108J00',NULL,'IDDM with neuropath arthropath'),('efi-diabetes',1,'C108y',NULL,'Oth specf diab mel+multip comp'),('efi-diabetes',1,'C108y00',NULL,'Oth specf diab mel+multip comp'),('efi-diabetes',1,'C108z',NULL,'Unspecifd diab mel+multip comp'),('efi-diabetes',1,'C108z00',NULL,'Unspecifd diab mel+multip comp'),('efi-diabetes',1,'C109.',NULL,'Non-insulin depd diabetes mell'),('efi-diabetes',1,'C109.00',NULL,'Non-insulin depd diabetes mell'),('efi-diabetes',1,'C1090',NULL,'Non-ins-dp diab mel+renal comp'),('efi-diabetes',1,'C109000',NULL,'Non-ins-dp diab mel+renal comp'),('efi-diabetes',1,'C1091',NULL,'Non-ins-dp diab mel+ophth comp'),('efi-diabetes',1,'C109100',NULL,'Non-ins-dp diab mel+ophth comp'),('efi-diabetes',1,'C1092',NULL,'Non-ins-dp diab mel+neuro comp'),('efi-diabetes',1,'C109200',NULL,'Non-ins-dp diab mel+neuro comp'),('efi-diabetes',1,'C1093',NULL,'Non-ins-dp diab mel+multi comp'),('efi-diabetes',1,'C109300',NULL,'Non-ins-dp diab mel+multi comp'),('efi-diabetes',1,'C1094',NULL,'Non-insul depen diab mel+ulcer'),('efi-diabetes',1,'C109400',NULL,'Non-insul depen diab mel+ulcer'),('efi-diabetes',1,'C1095',NULL,'Non-insulin dep diab mell+gang'),('efi-diabetes',1,'C109500',NULL,'Non-insulin dep diab mell+gang'),('efi-diabetes',1,'C1096',NULL,'Non-insul dep diab mel+retinop'),('efi-diabetes',1,'C109600',NULL,'Non-insul dep diab mel+retinop'),('efi-diabetes',1,'C1097',NULL,'Non-insul dep diab-poor contr'),('efi-diabetes',1,'C109700',NULL,'Non-insul dep diab-poor contr'),('efi-diabetes',1,'C1099',NULL,'Non-insul-dep diab mel no comp'),('efi-diabetes',1,'C109900',NULL,'Non-insul-dep diab mel no comp'),('efi-diabetes',1,'C109A',NULL,'NIDDM with mononeuropathy'),('efi-diabetes',1,'C109A00',NULL,'NIDDM with mononeuropathy'),('efi-diabetes',1,'C109B',NULL,'NIDDM with polyneuropathy'),('efi-diabetes',1,'C109B00',NULL,'NIDDM with polyneuropathy'),('efi-diabetes',1,'C109C',NULL,'NIDDM with nephropathy'),('efi-diabetes',1,'C109C00',NULL,'NIDDM with nephropathy'),('efi-diabetes',1,'C109D',NULL,'NIDDM with hypoglycaemic coma'),('efi-diabetes',1,'C109D00',NULL,'NIDDM with hypoglycaemic coma'),('efi-diabetes',1,'C109E',NULL,'NIDDM with diabetic cataract'),('efi-diabetes',1,'C109E00',NULL,'NIDDM with diabetic cataract'),('efi-diabetes',1,'C109F',NULL,'NIDDM with periph angiopath'),('efi-diabetes',1,'C109F00',NULL,'NIDDM with periph angiopath'),('efi-diabetes',1,'C109G',NULL,'NIDDM with arthropathy'),('efi-diabetes',1,'C109G00',NULL,'NIDDM with arthropathy'),('efi-diabetes',1,'C109H',NULL,'NIDDM with neuropath arthrop'),('efi-diabetes',1,'C109H00',NULL,'NIDDM with neuropath arthrop'),('efi-diabetes',1,'C109J',NULL,'Insul treated Type 2 diab mell'),('efi-diabetes',1,'C109J00',NULL,'Insul treated Type 2 diab mell'),('efi-diabetes',1,'C10A1',NULL,'Malnut-rlat diab mell+ketoacid'),('efi-diabetes',1,'C10A100',NULL,'Malnut-rlat diab mell+ketoacid'),('efi-diabetes',1,'C10B0',NULL,'Sterod ind diab mel w/out comp'),('efi-diabetes',1,'C10B000',NULL,'Sterod ind diab mel w/out comp'),('efi-diabetes',1,'C10C.',NULL,'Diab mell aut dom'),('efi-diabetes',1,'C10C.00',NULL,'Diab mell aut dom'),('efi-diabetes',1,'C10D.',NULL,'Diab mell aut dom type 2'),('efi-diabetes',1,'C10D.00',NULL,'Diab mell aut dom type 2'),('efi-diabetes',1,'C10E.',NULL,'Type 1 diabetes mellitus'),('efi-diabetes',1,'C10E.00',NULL,'Type 1 diabetes mellitus'),('efi-diabetes',1,'C10E0',NULL,'Type 1 d m with renal comps'),('efi-diabetes',1,'C10E000',NULL,'Type 1 d m with renal comps'),('efi-diabetes',1,'C10E1',NULL,'Type 1 diab mell + ophth comps'),('efi-diabetes',1,'C10E100',NULL,'Type 1 diab mell + ophth comps'),('efi-diabetes',1,'C10E2',NULL,'Type 1 diab mell + neuro comps'),('efi-diabetes',1,'C10E200',NULL,'Type 1 diab mell + neuro comps'),('efi-diabetes',1,'C10E3',NULL,'Type 1 diab mell + mult comps'),('efi-diabetes',1,'C10E300',NULL,'Type 1 diab mell + mult comps'),('efi-diabetes',1,'C10E5',NULL,'Type 1 diab mell with ulcer'),('efi-diabetes',1,'C10E500',NULL,'Type 1 diab mell with ulcer'),('efi-diabetes',1,'C10E6',NULL,'Type 1 diab mell with gangrene'),('efi-diabetes',1,'C10E600',NULL,'Type 1 diab mell with gangrene'),('efi-diabetes',1,'C10E7',NULL,'Type 1 diab mell + retinopathy'),('efi-diabetes',1,'C10E700',NULL,'Type 1 diab mell + retinopathy'),('efi-diabetes',1,'C10E8',NULL,'Type 1 diab mell poor control'),('efi-diabetes',1,'C10E800',NULL,'Type 1 diab mell poor control'),('efi-diabetes',1,'C10E9',NULL,'Type 1 diab mell matur onset'),('efi-diabetes',1,'C10E900',NULL,'Type 1 diab mell matur onset'),('efi-diabetes',1,'C10EA',NULL,'Type 1 diab mell without comp'),('efi-diabetes',1,'C10EA00',NULL,'Type 1 diab mell without comp'),('efi-diabetes',1,'C10EB',NULL,'Type 1 diab mell + mononeurop'),('efi-diabetes',1,'C10EB00',NULL,'Type 1 diab mell + mononeurop'),('efi-diabetes',1,'C10EC',NULL,'Type 1 diab mell + polyneurop'),('efi-diabetes',1,'C10EC00',NULL,'Type 1 diab mell + polyneurop'),('efi-diabetes',1,'C10ED',NULL,'Type 1 diab mell + nephropathy'),('efi-diabetes',1,'C10ED00',NULL,'Type 1 diab mell + nephropathy'),('efi-diabetes',1,'C10EE',NULL,'Type 1 diab mell + hypo coma'),('efi-diabetes',1,'C10EE00',NULL,'Type 1 diab mell + hypo coma'),('efi-diabetes',1,'C10EF',NULL,'Type 1 diab mell + diab catar'),('efi-diabetes',1,'C10EF00',NULL,'Type 1 diab mell + diab catar'),('efi-diabetes',1,'C10EJ',NULL,'Type 1 diab mell+neuro arthrop'),('efi-diabetes',1,'C10EJ00',NULL,'Type 1 diab mell+neuro arthrop'),('efi-diabetes',1,'C10EK',NULL,'Type 1 d m + persist proteinur'),('efi-diabetes',1,'C10EK00',NULL,'Type 1 d m + persist proteinur'),('efi-diabetes',1,'C10EL',NULL,'Type 1 d m + persist microalb'),('efi-diabetes',1,'C10EL00',NULL,'Type 1 d m + persist microalb'),('efi-diabetes',1,'C10EM',NULL,'Type 1 d m with ketoacidosis'),('efi-diabetes',1,'C10EM00',NULL,'Type 1 d m with ketoacidosis'),('efi-diabetes',1,'C10EN',NULL,'Type 1 d m+ketoacidotic coma'),('efi-diabetes',1,'C10EN00',NULL,'Type 1 d m+ketoacidotic coma'),('efi-diabetes',1,'C10EP',NULL,'Type 1 d m + exudat maculopath'),('efi-diabetes',1,'C10EP00',NULL,'Type 1 d m + exudat maculopath'),('efi-diabetes',1,'C10EQ',NULL,'Type 1 dm with gastroparesis'),('efi-diabetes',1,'C10EQ00',NULL,'Type 1 dm with gastroparesis'),('efi-diabetes',1,'C10ER',NULL,'Latent autoimm diab mell adult'),('efi-diabetes',1,'C10ER00',NULL,'Latent autoimm diab mell adult'),('efi-diabetes',1,'C10F.',NULL,'Type 2 diabetes mellitus'),('efi-diabetes',1,'C10F.00',NULL,'Type 2 diabetes mellitus'),('efi-diabetes',1,'C10F0',NULL,'Type 2 diab mell + renal compl'),('efi-diabetes',1,'C10F000',NULL,'Type 2 diab mell + renal compl'),('efi-diabetes',1,'C10F1',NULL,'Type 2 diab mell+ophthal comp'),('efi-diabetes',1,'C10F100',NULL,'Type 2 diab mell+ophthal comp'),('efi-diabetes',1,'C10F2',NULL,'Type 2 diab mell + neurol comp'),('efi-diabetes',1,'C10F200',NULL,'Type 2 diab mell + neurol comp'),('efi-diabetes',1,'C10F3',NULL,'Type 2 diab mell + multip comp'),('efi-diabetes',1,'C10F300',NULL,'Type 2 diab mell + multip comp'),('efi-diabetes',1,'C10F4',NULL,'Type 2 diab mell with ulcer'),('efi-diabetes',1,'C10F400',NULL,'Type 2 diab mell with ulcer'),('efi-diabetes',1,'C10F5',NULL,'Type 2 diab mell + gangrene'),('efi-diabetes',1,'C10F500',NULL,'Type 2 diab mell + gangrene'),('efi-diabetes',1,'C10F6',NULL,'Type 2 diab mell + retinopathy'),('efi-diabetes',1,'C10F600',NULL,'Type 2 diab mell + retinopathy'),('efi-diabetes',1,'C10F7',NULL,'Type 2 diab mell+poor control'),('efi-diabetes',1,'C10F700',NULL,'Type 2 diab mell+poor control'),('efi-diabetes',1,'C10F9',NULL,'Type 2 diab mell without comp'),('efi-diabetes',1,'C10F900',NULL,'Type 2 diab mell without comp'),('efi-diabetes',1,'C10FA',NULL,'Type 2 diab mell mononeurop'),('efi-diabetes',1,'C10FA00',NULL,'Type 2 diab mell mononeurop'),('efi-diabetes',1,'C10FB',NULL,'Type 2 diab mell + polyneurop'),('efi-diabetes',1,'C10FB00',NULL,'Type 2 diab mell + polyneurop'),('efi-diabetes',1,'C10FC',NULL,'Type 2 diab mell + nephropathy'),('efi-diabetes',1,'C10FC00',NULL,'Type 2 diab mell + nephropathy'),('efi-diabetes',1,'C10FD',NULL,'Type 2 diab mell+hypogly coma'),('efi-diabetes',1,'C10FD00',NULL,'Type 2 diab mell+hypogly coma'),('efi-diabetes',1,'C10FE',NULL,'Type 2 diab mell+diab catarct'),('efi-diabetes',1,'C10FE00',NULL,'Type 2 diab mell+diab catarct'),('efi-diabetes',1,'C10FF',NULL,'Type 2 diab mell+perip angiop'),('efi-diabetes',1,'C10FF00',NULL,'Type 2 diab mell+perip angiop'),('efi-diabetes',1,'C10FG',NULL,'Type 2 diab mell + arthropathy'),('efi-diabetes',1,'C10FG00',NULL,'Type 2 diab mell + arthropathy'),('efi-diabetes',1,'C10FH',NULL,'Type 2 diab mell neurop+arthr'),('efi-diabetes',1,'C10FH00',NULL,'Type 2 diab mell neurop+arthr'),('efi-diabetes',1,'C10FJ',NULL,'Insul treated Type 2 diab mell'),('efi-diabetes',1,'C10FJ00',NULL,'Insul treated Type 2 diab mell'),('efi-diabetes',1,'C10FL',NULL,'Type 2 d m + persist proteinur'),('efi-diabetes',1,'C10FL00',NULL,'Type 2 d m + persist proteinur'),('efi-diabetes',1,'C10FM',NULL,'Type 2 d m + persist microalb'),('efi-diabetes',1,'C10FM00',NULL,'Type 2 d m + persist microalb'),('efi-diabetes',1,'C10FN',NULL,'Type 2 d m with ketoacidosis'),('efi-diabetes',1,'C10FN00',NULL,'Type 2 d m with ketoacidosis'),('efi-diabetes',1,'C10FP',NULL,'Type 2 d m+ketoacidotic coma'),('efi-diabetes',1,'C10FP00',NULL,'Type 2 d m+ketoacidotic coma'),('efi-diabetes',1,'C10FQ',NULL,'Type 2 d m + exudat maculopath'),('efi-diabetes',1,'C10FQ00',NULL,'Type 2 d m + exudat maculopath'),('efi-diabetes',1,'C10FR',NULL,'Type 2 dm with gastroparesis'),('efi-diabetes',1,'C10FR00',NULL,'Type 2 dm with gastroparesis'),('efi-diabetes',1,'C10H.',NULL,'DM induced by non-steroid drug'),('efi-diabetes',1,'C10H.00',NULL,'DM induced by non-steroid drug'),('efi-diabetes',1,'C10y.',NULL,'Diab.mell.+other manifestation'),('efi-diabetes',1,'C10y.00',NULL,'Diab.mell.+other manifestation'),
('efi-diabetes',1,'C10yy',NULL,'Oth spec diab mel+oth spec cmp'),('efi-diabetes',1,'C10yy00',NULL,'Oth spec diab mel+oth spec cmp'),('efi-diabetes',1,'C10z.',NULL,'Diab.mell. + unspec comp'),('efi-diabetes',1,'C10z.00',NULL,'Diab.mell. + unspec comp'),('efi-diabetes',1,'C10zz',NULL,'Diab.mell. + unspec comp NOS'),('efi-diabetes',1,'C10zz00',NULL,'Diab.mell. + unspec comp NOS'),('efi-diabetes',1,'Cyu2.',NULL,'[X]Diabetes mellitus'),('efi-diabetes',1,'Cyu2.00',NULL,'[X]Diabetes mellitus'),('efi-diabetes',1,'Cyu23',NULL,'[X]Unspec diab mel + ren compl'),('efi-diabetes',1,'Cyu2300',NULL,'[X]Unspec diab mel + ren compl'),('efi-diabetes',1,'F1711',NULL,'Autonomic neuropathy-diabetes'),('efi-diabetes',1,'F171100',NULL,'Autonomic neuropathy-diabetes'),('efi-diabetes',1,'F372.',NULL,'Polyneuropathy in diabetes'),('efi-diabetes',1,'F372.00',NULL,'Polyneuropathy in diabetes'),('efi-diabetes',1,'F3720',NULL,'Acute painful diab neuropathy'),('efi-diabetes',1,'F372000',NULL,'Acute painful diab neuropathy'),('efi-diabetes',1,'F3721',NULL,'Chron painful diab neuropathy'),('efi-diabetes',1,'F372100',NULL,'Chron painful diab neuropathy'),('efi-diabetes',1,'F3722',NULL,'Asymptomatic diab neuropathy'),('efi-diabetes',1,'F372200',NULL,'Asymptomatic diab neuropathy'),('efi-diabetes',1,'F3813',NULL,'Myasthenic syndrome+diabetes'),('efi-diabetes',1,'F381300',NULL,'Myasthenic syndrome+diabetes'),('efi-diabetes',1,'F3y0.',NULL,'Diabetic mononeuropathy'),('efi-diabetes',1,'F3y0.00',NULL,'Diabetic mononeuropathy'),('efi-diabetes',1,'F420.',NULL,'Diabetic retinopathy'),('efi-diabetes',1,'F420.00',NULL,'Diabetic retinopathy'),('efi-diabetes',1,'F4200',NULL,'Background diabetic retinopath'),('efi-diabetes',1,'F420000',NULL,'Background diabetic retinopath'),('efi-diabetes',1,'F4204',NULL,'Diabetic maculopathy'),('efi-diabetes',1,'F420400',NULL,'Diabetic maculopathy'),('efi-diabetes',1,'F4206',NULL,'Non prolif diab retinop'),('efi-diabetes',1,'F420600',NULL,'Non prolif diab retinop'),('efi-diabetes',1,'F420z',NULL,'Diabetic retinopathy NOS'),('efi-diabetes',1,'F420z00',NULL,'Diabetic retinopathy NOS'),('efi-diabetes',1,'F42y9',NULL,'Macular oedema'),('efi-diabetes',1,'F42y900',NULL,'Macular oedema');
INSERT INTO #codesreadv2
VALUES ('efi-foot-problems',1,'13G8.',NULL,'Domiciliary chiropody'),('efi-foot-problems',1,'13G8.00',NULL,'Domiciliary chiropody'),('efi-foot-problems',1,'9N08.',NULL,'Seen in chiropody clinic'),('efi-foot-problems',1,'9N08.00',NULL,'Seen in chiropody clinic'),('efi-foot-problems',1,'9N1y7',NULL,'Seen in chiropody clinic'),('efi-foot-problems',1,'9N1y700',NULL,'Seen in chiropody clinic'),('efi-foot-problems',1,'9N2Q.',NULL,'Seen by podiatrist'),('efi-foot-problems',1,'9N2Q.00',NULL,'Seen by podiatrist'),('efi-foot-problems',1,'M20..',NULL,'Corns and callosities'),('efi-foot-problems',1,'M20..00',NULL,'Corns and callosities'),('efi-foot-problems',1,'M2000',NULL,'Hard corn'),('efi-foot-problems',1,'M200000',NULL,'Hard corn');
INSERT INTO #codesreadv2
VALUES ('efi-fragility-fracture',1,'14G6.',NULL,'H/O: fragility fracture'),('efi-fragility-fracture',1,'14G6.00',NULL,'H/O: fragility fracture'),('efi-fragility-fracture',1,'14G7.',NULL,'H/O: hip fracture'),('efi-fragility-fracture',1,'14G7.00',NULL,'H/O: hip fracture'),('efi-fragility-fracture',1,'14G8.',NULL,'H/O: vertebral fracture'),('efi-fragility-fracture',1,'14G8.00',NULL,'H/O: vertebral fracture'),('efi-fragility-fracture',1,'7K1D0',NULL,'Pry op red+int fxn prx fem #+'),('efi-fragility-fracture',1,'7K1D000',NULL,'Pry op red+int fxn prx fem #+'),('efi-fragility-fracture',1,'7K1D6',NULL,'Pry opn red+int fxn prx fem #+'),('efi-fragility-fracture',1,'7K1D600',NULL,'Pry opn red+int fxn prx fem #+'),('efi-fragility-fracture',1,'7K1H6',NULL,'Rv op rd+int fxn prx fem #+scw'),('efi-fragility-fracture',1,'7K1H600',NULL,'Rv op rd+int fxn prx fem #+scw'),('efi-fragility-fracture',1,'7K1H8',NULL,'Rv op rd+int fxn prx fem #+scw'),('efi-fragility-fracture',1,'7K1H800',NULL,'Rv op rd+int fxn prx fem #+scw'),('efi-fragility-fracture',1,'7K1J0',NULL,'Cl rd+int fx prx fem #+scrw'),('efi-fragility-fracture',1,'7K1J000',NULL,'Cl rd+int fx prx fem #+scrw'),('efi-fragility-fracture',1,'7K1J6',NULL,'Py int fx(no rd)prx fem #+scw'),('efi-fragility-fracture',1,'7K1J600',NULL,'Py int fx(no rd)prx fem #+scw'),('efi-fragility-fracture',1,'7K1J8',NULL,'Rv int fxn(no rd)prx fem #+scw'),('efi-fragility-fracture',1,'7K1J800',NULL,'Rv int fxn(no rd)prx fem #+scw'),('efi-fragility-fracture',1,'7K1JB',NULL,'Pry cls rd+int fx prx fem #+sc'),('efi-fragility-fracture',1,'7K1JB00',NULL,'Pry cls rd+int fx prx fem #+sc'),('efi-fragility-fracture',1,'7K1JD',NULL,'Pry cls rd+int fx prx fem #+sc'),('efi-fragility-fracture',1,'7K1JD00',NULL,'Pry cls rd+int fx prx fem #+sc'),('efi-fragility-fracture',1,'7K1Jd',NULL,'Cl red intrac # NOF in fix DHS'),('efi-fragility-fracture',1,'7K1Jd00',NULL,'Cl red intrac # NOF in fix DHS'),('efi-fragility-fracture',1,'7K1L4',NULL,'Closed reduction # hip'),('efi-fragility-fracture',1,'7K1L400',NULL,'Closed reduction # hip'),('efi-fragility-fracture',1,'7K1LL',NULL,'Closed reduction # radius/ulna'),('efi-fragility-fracture',1,'7K1LL00',NULL,'Closed reduction # radius/ulna'),('efi-fragility-fracture',1,'7K1Y0',NULL,'Re intra fr nck fe fi us nl sc'),('efi-fragility-fracture',1,'7K1Y000',NULL,'Re intra fr nck fe fi us nl sc'),('efi-fragility-fracture',1,'N1y1.',NULL,'Fatigue fracture of vertebra'),('efi-fragility-fracture',1,'N1y1.00',NULL,'Fatigue fracture of vertebra'),('efi-fragility-fracture',1,'N331.',NULL,'Pathological fracture'),('efi-fragility-fracture',1,'N331.00',NULL,'Pathological fracture'),('efi-fragility-fracture',1,'N3311',NULL,'Pathological # - lumbar vert.'),('efi-fragility-fracture',1,'N331100',NULL,'Pathological # - lumbar vert.'),('efi-fragility-fracture',1,'N331A',NULL,'Osteopor path # cerv vertebrae'),('efi-fragility-fracture',1,'N331A00',NULL,'Osteopor path # cerv vertebrae'),('efi-fragility-fracture',1,'N331D',NULL,'Collapsed vertebra NOS'),('efi-fragility-fracture',1,'N331D00',NULL,'Collapsed vertebra NOS'),('efi-fragility-fracture',1,'N331G',NULL,'Collapse of lumbar vertebra'),('efi-fragility-fracture',1,'N331G00',NULL,'Collapse of lumbar vertebra'),('efi-fragility-fracture',1,'N331H',NULL,'Collap cerv vert due to osteop'),('efi-fragility-fracture',1,'N331H00',NULL,'Collap cerv vert due to osteop'),('efi-fragility-fracture',1,'N331J',NULL,'Collap lumb vert due to osteo'),('efi-fragility-fracture',1,'N331J00',NULL,'Collap lumb vert due to osteo'),('efi-fragility-fracture',1,'N331K',NULL,'Coll thorac vert due osteopor'),('efi-fragility-fracture',1,'N331K00',NULL,'Coll thorac vert due osteopor'),('efi-fragility-fracture',1,'N331L',NULL,'Collap vert due osteopor NOS'),('efi-fragility-fracture',1,'N331L00',NULL,'Collap vert due osteopor NOS'),('efi-fragility-fracture',1,'N331M',NULL,'Fragility # unsp osteoporosis'),('efi-fragility-fracture',1,'N331M00',NULL,'Fragility # unsp osteoporosis'),('efi-fragility-fracture',1,'N331N',NULL,'Fragility fracture'),('efi-fragility-fracture',1,'N331N00',NULL,'Fragility fracture'),('efi-fragility-fracture',1,'NyuB0',NULL,'[X]Oth osteoporosis+patholog #'),('efi-fragility-fracture',1,'NyuB000',NULL,'[X]Oth osteoporosis+patholog #'),('efi-fragility-fracture',1,'S10..',NULL,'#Spine - no cord lesion'),('efi-fragility-fracture',1,'S10..00',NULL,'#Spine - no cord lesion'),('efi-fragility-fracture',1,'S1000',NULL,'Clsd # unsp cerv vertebra'),('efi-fragility-fracture',1,'S100000',NULL,'Clsd # unsp cerv vertebra'),('efi-fragility-fracture',1,'S1005',NULL,'Clsd # fifth cerv vertebra'),('efi-fragility-fracture',1,'S100500',NULL,'Clsd # fifth cerv vertebra'),('efi-fragility-fracture',1,'S1006',NULL,'Clsd # sixth cerv vertebra'),('efi-fragility-fracture',1,'S100600',NULL,'Clsd # sixth cerv vertebra'),('efi-fragility-fracture',1,'S1007',NULL,'Clsd # seventh cerv vertebra'),('efi-fragility-fracture',1,'S100700',NULL,'Clsd # seventh cerv vertebra'),('efi-fragility-fracture',1,'S100H',NULL,'Clsd # cerv vert, wedge'),('efi-fragility-fracture',1,'S100H00',NULL,'Clsd # cerv vert, wedge'),('efi-fragility-fracture',1,'S100K',NULL,'Cls # cerv vert, spinous prcss'),('efi-fragility-fracture',1,'S100K00',NULL,'Cls # cerv vert, spinous prcss'),('efi-fragility-fracture',1,'S102.',NULL,'Clsd # thoracic vertebra'),('efi-fragility-fracture',1,'S102.00',NULL,'Clsd # thoracic vertebra'),('efi-fragility-fracture',1,'S1020',NULL,'Clsd # thoracic vert, burst'),('efi-fragility-fracture',1,'S102000',NULL,'Clsd # thoracic vert, burst'),('efi-fragility-fracture',1,'S1021',NULL,'Clsd # thoracic vert, wedge'),('efi-fragility-fracture',1,'S102100',NULL,'Clsd # thoracic vert, wedge'),('efi-fragility-fracture',1,'S102y',NULL,'Othr spec clsd # thorac vert'),('efi-fragility-fracture',1,'S102y00',NULL,'Othr spec clsd # thorac vert'),('efi-fragility-fracture',1,'S102z',NULL,'Clsd # thorac vert NOS'),('efi-fragility-fracture',1,'S102z00',NULL,'Clsd # thorac vert NOS'),('efi-fragility-fracture',1,'S1031',NULL,'Open # thorac vert, wedge'),('efi-fragility-fracture',1,'S103100',NULL,'Open # thorac vert, wedge'),('efi-fragility-fracture',1,'S104.',NULL,'Clsd # lumbar vert'),('efi-fragility-fracture',1,'S104.00',NULL,'Clsd # lumbar vert'),('efi-fragility-fracture',1,'S1040',NULL,'Clsd # lumbar vert, burst'),('efi-fragility-fracture',1,'S104000',NULL,'Clsd # lumbar vert, burst'),('efi-fragility-fracture',1,'S1041',NULL,'Clsd # lumbar vert, wedge'),('efi-fragility-fracture',1,'S104100',NULL,'Clsd # lumbar vert, wedge'),('efi-fragility-fracture',1,'S1042',NULL,'Cls # lumbr vert-spondylolysis'),('efi-fragility-fracture',1,'S104200',NULL,'Cls # lumbr vert-spondylolysis'),('efi-fragility-fracture',1,'S10A0',NULL,'Fracture/1st cervical vertebra'),('efi-fragility-fracture',1,'S10A000',NULL,'Fracture/1st cervical vertebra'),('efi-fragility-fracture',1,'S10B.',NULL,'Fracture/lumbar spine+pelvis'),('efi-fragility-fracture',1,'S10B.00',NULL,'Fracture/lumbar spine+pelvis'),('efi-fragility-fracture',1,'S10B0',NULL,'Fracture of lumbar vertebra'),('efi-fragility-fracture',1,'S10B000',NULL,'Fracture of lumbar vertebra'),('efi-fragility-fracture',1,'S10B6',NULL,'Mult fractur/lumbar spine+pelv'),('efi-fragility-fracture',1,'S10B600',NULL,'Mult fractur/lumbar spine+pelv'),('efi-fragility-fracture',1,'S112.',NULL,'Closed thoracic #+cord lesion'),('efi-fragility-fracture',1,'S112.00',NULL,'Closed thoracic #+cord lesion'),('efi-fragility-fracture',1,'S114.',NULL,'Closed lumbar # + cord lesion'),('efi-fragility-fracture',1,'S114.00',NULL,'Closed lumbar # + cord lesion'),('efi-fragility-fracture',1,'S1145',NULL,'Cls spn # + cauda equina lesn'),('efi-fragility-fracture',1,'S114500',NULL,'Cls spn # + cauda equina lesn'),('efi-fragility-fracture',1,'S15..',NULL,'Fracture of thoracic vertebra'),('efi-fragility-fracture',1,'S15..00',NULL,'Fracture of thoracic vertebra'),('efi-fragility-fracture',1,'S150.',NULL,'Multi fractures/thoracic spine'),('efi-fragility-fracture',1,'S150.00',NULL,'Multi fractures/thoracic spine'),('efi-fragility-fracture',1,'S1500',NULL,'Cl multi fractur of thor spine'),('efi-fragility-fracture',1,'S150000',NULL,'Cl multi fractur of thor spine'),('efi-fragility-fracture',1,'S23..',NULL,'#Radius and ulna'),('efi-fragility-fracture',1,'S23..00',NULL,'#Radius and ulna'),('efi-fragility-fracture',1,'S234.',NULL,'Closed #radius/ulna-lower end'),('efi-fragility-fracture',1,'S234.00',NULL,'Closed #radius/ulna-lower end'),('efi-fragility-fracture',1,'S2341',NULL,'Closed Colles fracture'),('efi-fragility-fracture',1,'S234100',NULL,'Closed Colles fracture'),('efi-fragility-fracture',1,'S2346',NULL,'Clsd # radius+ulna, distal'),('efi-fragility-fracture',1,'S234600',NULL,'Clsd # radius+ulna, distal'),('efi-fragility-fracture',1,'S2351',NULL,'Open Colles fracture'),('efi-fragility-fracture',1,'S235100',NULL,'Open Colles fracture'),('efi-fragility-fracture',1,'S23B.',NULL,'Fracture / lower end of radius'),('efi-fragility-fracture',1,'S23B.00',NULL,'Fracture / lower end of radius'),('efi-fragility-fracture',1,'S23C.',NULL,'Fractr/lw end/both ulna+radius'),('efi-fragility-fracture',1,'S23C.00',NULL,'Fractr/lw end/both ulna+radius'),('efi-fragility-fracture',1,'S23x1',NULL,'Closed #radius alone unspecif.'),('efi-fragility-fracture',1,'S23x100',NULL,'Closed #radius alone unspecif.'),('efi-fragility-fracture',1,'S23y.',NULL,'Open #radius/ulna unspecified'),('efi-fragility-fracture',1,'S23y.00',NULL,'Open #radius/ulna unspecified'),('efi-fragility-fracture',1,'S3...',NULL,'Fracture of lower limb'),('efi-fragility-fracture',1,'S3...00',NULL,'Fracture of lower limb'),('efi-fragility-fracture',1,'S30..',NULL,'#Neck of femur'),('efi-fragility-fracture',1,'S30..00',NULL,'#Neck of femur'),('efi-fragility-fracture',1,'S300.',NULL,'Cls # prox femur,transcerv'),('efi-fragility-fracture',1,'S300.00',NULL,'Cls # prox femur,transcerv'),('efi-fragility-fracture',1,'S3000',NULL,'Cl # prx fem,intrcp sctn,unsp'),
('efi-fragility-fracture',1,'S300000',NULL,'Cl # prx fem,intrcp sctn,unsp'),('efi-fragility-fracture',1,'S3001',NULL,'Cls # prox fmur,transepiphys'),('efi-fragility-fracture',1,'S300100',NULL,'Cls # prox fmur,transepiphys'),('efi-fragility-fracture',1,'S3004',NULL,'Closed fracture head of femur'),('efi-fragility-fracture',1,'S300400',NULL,'Closed fracture head of femur'),('efi-fragility-fracture',1,'S3005',NULL,'Cl # prx fem,sbcp,Gdn grd unsp'),('efi-fragility-fracture',1,'S300500',NULL,'Cl # prx fem,sbcp,Gdn grd unsp'),('efi-fragility-fracture',1,'S3006',NULL,'Cl # prx fem,sbcap,Gdn grd I'),('efi-fragility-fracture',1,'S300600',NULL,'Cl # prx fem,sbcap,Gdn grd I'),('efi-fragility-fracture',1,'S3007',NULL,'Cl # prx fem,sbcap,Gdn grd II'),('efi-fragility-fracture',1,'S300700',NULL,'Cl # prx fem,sbcap,Gdn grd II'),('efi-fragility-fracture',1,'S3009',NULL,'Cl # prx fem,sbcap,Gdn grd IV'),('efi-fragility-fracture',1,'S300900',NULL,'Cl # prx fem,sbcap,Gdn grd IV'),('efi-fragility-fracture',1,'S300y',NULL,'Cls # prox fmur,othr transcerv'),('efi-fragility-fracture',1,'S300y00',NULL,'Cls # prox fmur,othr transcerv'),('efi-fragility-fracture',1,'S300z',NULL,'Cls # prox fmur,transcerv NOS'),('efi-fragility-fracture',1,'S300z00',NULL,'Cls # prox fmur,transcerv NOS'),('efi-fragility-fracture',1,'S3010',NULL,'Op # prox fem,intcap sctn,unsp'),('efi-fragility-fracture',1,'S301000',NULL,'Op # prox fem,intcap sctn,unsp'),('efi-fragility-fracture',1,'S3015',NULL,'Op # prx fem subcap,Gdn gd uns'),('efi-fragility-fracture',1,'S301500',NULL,'Op # prx fem subcap,Gdn gd uns'),('efi-fragility-fracture',1,'S302.',NULL,'Cls # prox femur,pertrochntrc'),('efi-fragility-fracture',1,'S302.00',NULL,'Cls # prox femur,pertrochntrc'),('efi-fragility-fracture',1,'S3020',NULL,'Cl # prx fem-trchntrc sct unsp'),('efi-fragility-fracture',1,'S302000',NULL,'Cl # prx fem-trchntrc sct unsp'),('efi-fragility-fracture',1,'S3021',NULL,'Cl # prx fem-intrtrchntrc-2 pt'),('efi-fragility-fracture',1,'S302100',NULL,'Cl # prx fem-intrtrchntrc-2 pt'),('efi-fragility-fracture',1,'S3022',NULL,'Cls # prox fmur-subtrchntrc'),('efi-fragility-fracture',1,'S302200',NULL,'Cls # prox fmur-subtrchntrc'),('efi-fragility-fracture',1,'S3023',NULL,'Cl # prx fem-intertroch-commin'),('efi-fragility-fracture',1,'S302300',NULL,'Cl # prx fem-intertroch-commin'),('efi-fragility-fracture',1,'S3024',NULL,'Closed # femur, intertrochant'),('efi-fragility-fracture',1,'S302400',NULL,'Closed # femur, intertrochant'),('efi-fragility-fracture',1,'S302z',NULL,'Cl # prx fem-prtrchntr sct NOS'),('efi-fragility-fracture',1,'S302z00',NULL,'Cl # prx fem-prtrchntr sct NOS'),('efi-fragility-fracture',1,'S303.',NULL,'Op # prox fem,pertrochanteric'),('efi-fragility-fracture',1,'S303.00',NULL,'Op # prox fem,pertrochanteric'),('efi-fragility-fracture',1,'S3030',NULL,'Op # prx fem,trchntrc sct,unsp'),('efi-fragility-fracture',1,'S303000',NULL,'Op # prx fem,trchntrc sct,unsp'),('efi-fragility-fracture',1,'S3032',NULL,'Opn # prox fmur-subtrochntrc'),('efi-fragility-fracture',1,'S303200',NULL,'Opn # prox fmur-subtrochntrc'),('efi-fragility-fracture',1,'S3034',NULL,'Open # femur, intertrochant'),('efi-fragility-fracture',1,'S303400',NULL,'Open # femur, intertrochant'),('efi-fragility-fracture',1,'S304.',NULL,'Pertrochanteric fracture'),('efi-fragility-fracture',1,'S304.00',NULL,'Pertrochanteric fracture'),('efi-fragility-fracture',1,'S305.',NULL,'Subtrochanteric fracture'),('efi-fragility-fracture',1,'S305.00',NULL,'Subtrochanteric fracture'),('efi-fragility-fracture',1,'S30y.',NULL,'Closed #neck of femur NOS'),('efi-fragility-fracture',1,'S30y.00',NULL,'Closed #neck of femur NOS'),('efi-fragility-fracture',1,'S30z.',NULL,'Open #neck of femur NOS'),('efi-fragility-fracture',1,'S30z.00',NULL,'Open #neck of femur NOS'),('efi-fragility-fracture',1,'S31z.',NULL,'#Femur NOS'),('efi-fragility-fracture',1,'S31z.00',NULL,'#Femur NOS'),('efi-fragility-fracture',1,'S4500',NULL,'Cls trmtc dslctn hip, unsp'),('efi-fragility-fracture',1,'S450000',NULL,'Cls trmtc dslctn hip, unsp'),('efi-fragility-fracture',1,'S4E..',NULL,'#-dslc/subluxation hip'),('efi-fragility-fracture',1,'S4E..00',NULL,'#-dslc/subluxation hip'),('efi-fragility-fracture',1,'S4E0.',NULL,'Closed #-dslc, hip joint'),('efi-fragility-fracture',1,'S4E0.00',NULL,'Closed #-dslc, hip joint'),('efi-fragility-fracture',1,'S4E1.',NULL,'Open #-dslc, hip joint'),('efi-fragility-fracture',1,'S4E1.00',NULL,'Open #-dslc, hip joint'),('efi-fragility-fracture',1,'S4E2.',NULL,'Closed #-sublux, hip joint'),('efi-fragility-fracture',1,'S4E2.00',NULL,'Closed #-sublux, hip joint');
INSERT INTO #codesreadv2
VALUES ('efi-hearing-loss',1,'31340',NULL,'Audiogram bilateral abnormal'),('efi-hearing-loss',1,'3134000',NULL,'Audiogram bilateral abnormal'),('efi-hearing-loss',1,'1C12.',NULL,'Hearing difficulty'),('efi-hearing-loss',1,'1C12.00',NULL,'Hearing difficulty'),('efi-hearing-loss',1,'1C13.',NULL,'Deafness'),('efi-hearing-loss',1,'1C13.00',NULL,'Deafness'),('efi-hearing-loss',1,'1C131',NULL,'Unilateral deafness'),('efi-hearing-loss',1,'1C13100',NULL,'Unilateral deafness'),('efi-hearing-loss',1,'1C132',NULL,'Partial deafness'),('efi-hearing-loss',1,'1C13200',NULL,'Partial deafness'),('efi-hearing-loss',1,'1C133',NULL,'Bilateral deafness'),('efi-hearing-loss',1,'1C13300',NULL,'Bilateral deafness'),('efi-hearing-loss',1,'1C16.',NULL,'Deteriorating hearing'),('efi-hearing-loss',1,'1C16.00',NULL,'Deteriorating hearing'),('efi-hearing-loss',1,'2BM2.',NULL,'O/E -tune fork=conductive deaf'),('efi-hearing-loss',1,'2BM2.00',NULL,'O/E -tune fork=conductive deaf'),('efi-hearing-loss',1,'2BM3.',NULL,'O/E tune fork=perceptive deaf'),('efi-hearing-loss',1,'2BM3.00',NULL,'O/E tune fork=perceptive deaf'),('efi-hearing-loss',1,'2BM4.',NULL,'O/E - High tone deafness'),('efi-hearing-loss',1,'2BM4.00',NULL,'O/E - High tone deafness'),('efi-hearing-loss',1,'2DG..',NULL,'Hearing aid worn'),('efi-hearing-loss',1,'2DG..00',NULL,'Hearing aid worn'),('efi-hearing-loss',1,'3134.',NULL,'Auditory/vestib. test abnormal'),('efi-hearing-loss',1,'3134.00',NULL,'Auditory/vestib. test abnormal'),('efi-hearing-loss',1,'8D2..',NULL,'Auditory aid'),('efi-hearing-loss',1,'8D2..00',NULL,'Auditory aid'),('efi-hearing-loss',1,'8E3..',NULL,'Deafness remedial therapy'),('efi-hearing-loss',1,'8E3..00',NULL,'Deafness remedial therapy'),('efi-hearing-loss',1,'8HR2.',NULL,'Refer for audiometry'),('efi-hearing-loss',1,'8HR2.00',NULL,'Refer for audiometry'),('efi-hearing-loss',1,'8HT2.',NULL,'Referral to hearing aid clinic'),('efi-hearing-loss',1,'8HT2.00',NULL,'Referral to hearing aid clinic'),('efi-hearing-loss',1,'8HT3.',NULL,'Referral to audiology clinic'),('efi-hearing-loss',1,'8HT3.00',NULL,'Referral to audiology clinic'),('efi-hearing-loss',1,'Eu446',NULL,'[X]Dissoc anaesth/sensory loss'),('efi-hearing-loss',1,'Eu44600',NULL,'[X]Dissoc anaesth/sensory loss'),('efi-hearing-loss',1,'F5801',NULL,'Presbyacusis'),('efi-hearing-loss',1,'F580100',NULL,'Presbyacusis'),('efi-hearing-loss',1,'F59..',NULL,'Hearing loss'),('efi-hearing-loss',1,'F59..00',NULL,'Hearing loss'),('efi-hearing-loss',1,'F590.',NULL,'Conductive hearing loss'),('efi-hearing-loss',1,'F590.00',NULL,'Conductive hearing loss'),('efi-hearing-loss',1,'F591.',NULL,'Sensorineural hearing loss'),('efi-hearing-loss',1,'F591.00',NULL,'Sensorineural hearing loss'),('efi-hearing-loss',1,'F5912',NULL,'Neural hearing loss'),('efi-hearing-loss',1,'F591200',NULL,'Neural hearing loss'),('efi-hearing-loss',1,'F5915',NULL,'Ototoxicity - deafness'),('efi-hearing-loss',1,'F591500',NULL,'Ototoxicity - deafness'),('efi-hearing-loss',1,'F5916',NULL,'Sensorineural hear loss,bilat'),('efi-hearing-loss',1,'F591600',NULL,'Sensorineural hear loss,bilat'),('efi-hearing-loss',1,'F592.',NULL,'Mixed conduct/sensori deafness'),('efi-hearing-loss',1,'F592.00',NULL,'Mixed conduct/sensori deafness'),('efi-hearing-loss',1,'F594.',NULL,'High frequency deafness'),('efi-hearing-loss',1,'F594.00',NULL,'High frequency deafness'),('efi-hearing-loss',1,'F595.',NULL,'Low frequency deafness'),('efi-hearing-loss',1,'F595.00',NULL,'Low frequency deafness'),('efi-hearing-loss',1,'F59z.',NULL,'Deafness NOS'),('efi-hearing-loss',1,'F59z.00',NULL,'Deafness NOS'),('efi-hearing-loss',1,'F5A..',NULL,'Hearing impairment'),('efi-hearing-loss',1,'F5A..00',NULL,'Hearing impairment'),('efi-hearing-loss',1,'ZV532',NULL,'[V]Hearing aid fitting/adjust.'),('efi-hearing-loss',1,'ZV53200',NULL,'[V]Hearing aid fitting/adjust.');
INSERT INTO #codesreadv2
VALUES ('efi-heart-failure',1,'14A6.',NULL,'H/O: heart failure'),('efi-heart-failure',1,'14A6.00',NULL,'H/O: heart failure'),('efi-heart-failure',1,'14AM.',NULL,'H/O:Heart failure in last year'),('efi-heart-failure',1,'14AM.00',NULL,'H/O:Heart failure in last year'),('efi-heart-failure',1,'1736.',NULL,'Paroxysmal nocturnal dyspnoea'),('efi-heart-failure',1,'1736.00',NULL,'Paroxysmal nocturnal dyspnoea'),('efi-heart-failure',1,'1O1..',NULL,'Heart failure confirmed'),('efi-heart-failure',1,'1O1..00',NULL,'Heart failure confirmed'),('efi-heart-failure',1,'33BA.',NULL,'Impaired left ventricular func'),('efi-heart-failure',1,'33BA.00',NULL,'Impaired left ventricular func'),('efi-heart-failure',1,'388D.',NULL,'NYHA classif heart fail symps'),('efi-heart-failure',1,'388D.00',NULL,'NYHA classif heart fail symps'),('efi-heart-failure',1,'585f.',NULL,'Echocardiogram shows LVSDF'),('efi-heart-failure',1,'585f.00',NULL,'Echocardiogram shows LVSDF'),('efi-heart-failure',1,'662T.',NULL,'Congestive heart failure monit'),('efi-heart-failure',1,'662T.00',NULL,'Congestive heart failure monit'),('efi-heart-failure',1,'662W.',NULL,'Heart failure annual review'),('efi-heart-failure',1,'662W.00',NULL,'Heart failure annual review'),('efi-heart-failure',1,'662g.',NULL,'NYHA classification - class II'),('efi-heart-failure',1,'662g.00',NULL,'NYHA classification - class II'),('efi-heart-failure',1,'662h.',NULL,'NYHA classification- class III'),('efi-heart-failure',1,'662h.00',NULL,'NYHA classification- class III'),('efi-heart-failure',1,'662p.',NULL,'Heart failure 6 month review'),('efi-heart-failure',1,'662p.00',NULL,'Heart failure 6 month review'),('efi-heart-failure',1,'679X.',NULL,'Heart failure education'),('efi-heart-failure',1,'679X.00',NULL,'Heart failure education'),('efi-heart-failure',1,'67D4.',NULL,'Heart failure info given to pt'),('efi-heart-failure',1,'67D4.00',NULL,'Heart failure info given to pt'),('efi-heart-failure',1,'8CL3.',NULL,'HF care plan discussed with pt'),('efi-heart-failure',1,'8CL3.00',NULL,'HF care plan discussed with pt'),('efi-heart-failure',1,'8H2S.',NULL,'Admit heart failure emergency'),('efi-heart-failure',1,'8H2S.00',NULL,'Admit heart failure emergency'),('efi-heart-failure',1,'8HBE.',NULL,'Heart failure follow-up'),('efi-heart-failure',1,'8HBE.00',NULL,'Heart failure follow-up'),('efi-heart-failure',1,'8HHb.',NULL,'Referral to heart failure nurs'),('efi-heart-failure',1,'8HHb.00',NULL,'Referral to heart failure nurs'),('efi-heart-failure',1,'8HHz.',NULL,'Ref to heart failur exerc prog'),('efi-heart-failure',1,'8HHz.00',NULL,'Ref to heart failur exerc prog'),('efi-heart-failure',1,'9N0k.',NULL,'Seen in heart failure clinic'),('efi-heart-failure',1,'9N0k.00',NULL,'Seen in heart failure clinic'),('efi-heart-failure',1,'9N2p.',NULL,'Seen by comm heart failur nurs'),('efi-heart-failure',1,'9N2p.00',NULL,'Seen by comm heart failur nurs'),('efi-heart-failure',1,'9N4s.',NULL,'DNA pract nur heart fail clinc'),('efi-heart-failure',1,'9N4s.00',NULL,'DNA pract nur heart fail clinc'),('efi-heart-failure',1,'9N4w.',NULL,'DNA heart failure clinic'),('efi-heart-failure',1,'9N4w.00',NULL,'DNA heart failure clinic'),('efi-heart-failure',1,'9N6T.',NULL,'Ref by heart fail nurs special'),('efi-heart-failure',1,'9N6T.00',NULL,'Ref by heart fail nurs special'),('efi-heart-failure',1,'9Or0.',NULL,'Heart failure review completed'),('efi-heart-failure',1,'9Or0.00',NULL,'Heart failure review completed'),('efi-heart-failure',1,'9Or5.',NULL,'Heart fail monitori 3rd letter'),('efi-heart-failure',1,'9Or5.00',NULL,'Heart fail monitori 3rd letter'),('efi-heart-failure',1,'9hH0.',NULL,'Exc heart fai qual ind: Pt uns'),('efi-heart-failure',1,'9hH0.00',NULL,'Exc heart fai qual ind: Pt uns'),('efi-heart-failure',1,'9hH1.',NULL,'Ex heart fai qual ind: Inf dis'),('efi-heart-failure',1,'9hH1.00',NULL,'Ex heart fai qual ind: Inf dis'),('efi-heart-failure',1,'G58..',NULL,'Heart failure'),('efi-heart-failure',1,'G58..00',NULL,'Heart failure'),('efi-heart-failure',1,'G580.',NULL,'Congestive heart failure'),('efi-heart-failure',1,'G580.00',NULL,'Congestive heart failure'),('efi-heart-failure',1,'G5800',NULL,'Acute congestive heart failure'),('efi-heart-failure',1,'G580000',NULL,'Acute congestive heart failure'),('efi-heart-failure',1,'G5801',NULL,'Chroncongestive heart failure'),('efi-heart-failure',1,'G580100',NULL,'Chroncongestive heart failure'),('efi-heart-failure',1,'G5804',NULL,'Cong heart fail due valv dis'),('efi-heart-failure',1,'G580400',NULL,'Cong heart fail due valv dis'),('efi-heart-failure',1,'G581.',NULL,'Left ventricular failure'),('efi-heart-failure',1,'G581.00',NULL,'Left ventricular failure'),('efi-heart-failure',1,'G582.',NULL,'Acute heart failure'),('efi-heart-failure',1,'G582.00',NULL,'Acute heart failure'),('efi-heart-failure',1,'G58z.',NULL,'Heart failure NOS'),('efi-heart-failure',1,'G58z.00',NULL,'Heart failure NOS'),('efi-heart-failure',1,'G5y4z',NULL,'Post cardiac op.heart fail NOS'),('efi-heart-failure',1,'G5y4z00',NULL,'Post cardiac op.heart fail NOS'),('efi-heart-failure',1,'G5yy9',NULL,'Left ventricul systol dysfunc'),('efi-heart-failure',1,'G5yy900',NULL,'Left ventricul systol dysfunc'),('efi-heart-failure',1,'SP111',NULL,'Cardiac insuffic.comp.of care'),('efi-heart-failure',1,'SP11100',NULL,'Cardiac insuffic.comp.of care');
INSERT INTO #codesreadv2
VALUES ('efi-heart-valve-disease',1,'G540.',NULL,'Mitral valve incompetence'),('efi-heart-valve-disease',1,'G540.00',NULL,'Mitral valve incompetence'),('efi-heart-valve-disease',1,'G5402',NULL,'Mitral valve prolapse'),('efi-heart-valve-disease',1,'G540200',NULL,'Mitral valve prolapse'),('efi-heart-valve-disease',1,'G5415',NULL,'Aortic stenosis'),('efi-heart-valve-disease',1,'G541500',NULL,'Aortic stenosis'),('efi-heart-valve-disease',1,'G543.',NULL,'Pulmonary valve disorders'),('efi-heart-valve-disease',1,'G543.00',NULL,'Pulmonary valve disorders');
INSERT INTO #codesreadv2
VALUES ('efi-hypertension',1,'14A2.',NULL,'H/O: hypertension'),('efi-hypertension',1,'14A2.00',NULL,'H/O: hypertension'),('efi-hypertension',1,'246M.',NULL,'White coat hypertension'),('efi-hypertension',1,'246M.00',NULL,'White coat hypertension'),('efi-hypertension',1,'6627.',NULL,'Good hypertension control'),('efi-hypertension',1,'6627.00',NULL,'Good hypertension control'),('efi-hypertension',1,'6628.',NULL,'Poor hypertension control'),('efi-hypertension',1,'6628.00',NULL,'Poor hypertension control'),('efi-hypertension',1,'662F.',NULL,'Hypertension treatm. started'),('efi-hypertension',1,'662F.00',NULL,'Hypertension treatm. started'),('efi-hypertension',1,'662O.',NULL,'On treatment for hypertension'),('efi-hypertension',1,'662O.00',NULL,'On treatment for hypertension'),('efi-hypertension',1,'662b.',NULL,'Moderate hypertension control'),('efi-hypertension',1,'662b.00',NULL,'Moderate hypertension control'),('efi-hypertension',1,'8CR4.',NULL,'Hyperten clin management plan'),('efi-hypertension',1,'8CR4.00',NULL,'Hyperten clin management plan'),('efi-hypertension',1,'8HT5.',NULL,'Referral hypertension clinic'),('efi-hypertension',1,'8HT5.00',NULL,'Referral hypertension clinic'),('efi-hypertension',1,'8I3N.',NULL,'Hypertension treatment refused'),('efi-hypertension',1,'8I3N.00',NULL,'Hypertension treatment refused'),('efi-hypertension',1,'9N03.',NULL,'Seen in hypertension clinic'),('efi-hypertension',1,'9N03.00',NULL,'Seen in hypertension clinic'),('efi-hypertension',1,'9N1y2',NULL,'Seen in hypertension clinic'),('efi-hypertension',1,'9N1y200',NULL,'Seen in hypertension clinic'),('efi-hypertension',1,'9h3..',NULL,'Except rep: hypertens qual ind'),('efi-hypertension',1,'9h3..00',NULL,'Except rep: hypertens qual ind'),('efi-hypertension',1,'9h31.',NULL,'Exc hypertens qual ind: Pt uns'),('efi-hypertension',1,'9h31.00',NULL,'Exc hypertens qual ind: Pt uns'),('efi-hypertension',1,'9h32.',NULL,'Exc hyperten qual ind: Inf dis'),('efi-hypertension',1,'9h32.00',NULL,'Exc hyperten qual ind: Inf dis'),('efi-hypertension',1,'F4211',NULL,'Atherosclerotic retinopathy'),('efi-hypertension',1,'F421100',NULL,'Atherosclerotic retinopathy'),('efi-hypertension',1,'F4213',NULL,'Hypertensive retinopathy'),('efi-hypertension',1,'F421300',NULL,'Hypertensive retinopathy'),('efi-hypertension',1,'G2...',NULL,'Hypertensive disease'),('efi-hypertension',1,'G2...00',NULL,'Hypertensive disease'),('efi-hypertension',1,'G20..',NULL,'Essential hypertension'),('efi-hypertension',1,'G20..00',NULL,'Essential hypertension'),('efi-hypertension',1,'G200.',NULL,'Malignant essential hypertens.'),('efi-hypertension',1,'G200.00',NULL,'Malignant essential hypertens.'),('efi-hypertension',1,'G201.',NULL,'Benign essential hypertension'),('efi-hypertension',1,'G201.00',NULL,'Benign essential hypertension'),('efi-hypertension',1,'G202.',NULL,'Systolic hypertension'),('efi-hypertension',1,'G202.00',NULL,'Systolic hypertension'),('efi-hypertension',1,'G203.',NULL,'Diastolic hypertension'),('efi-hypertension',1,'G203.00',NULL,'Diastolic hypertension'),('efi-hypertension',1,'G20z.',NULL,'Essential hypertension NOS'),('efi-hypertension',1,'G20z.00',NULL,'Essential hypertension NOS'),('efi-hypertension',1,'G22z.',NULL,'Hypertensive renal disease NOS'),('efi-hypertension',1,'G22z.00',NULL,'Hypertensive renal disease NOS'),('efi-hypertension',1,'G24..',NULL,'Secondary hypertension'),('efi-hypertension',1,'G24..00',NULL,'Secondary hypertension'),('efi-hypertension',1,'G240.',NULL,'Secondary malignant hypertens.'),('efi-hypertension',1,'G240.00',NULL,'Secondary malignant hypertens.'),('efi-hypertension',1,'G240z',NULL,'Secondary malign.hypertens.NOS'),('efi-hypertension',1,'G240z00',NULL,'Secondary malign.hypertens.NOS'),('efi-hypertension',1,'G241.',NULL,'Secondary benign hypertension'),('efi-hypertension',1,'G241.00',NULL,'Secondary benign hypertension'),('efi-hypertension',1,'G241z',NULL,'Secondary benign hypertens.NOS'),('efi-hypertension',1,'G241z00',NULL,'Secondary benign hypertens.NOS'),('efi-hypertension',1,'G244.',NULL,'Hypertens 2ndry endocrin disor'),('efi-hypertension',1,'G244.00',NULL,'Hypertens 2ndry endocrin disor'),('efi-hypertension',1,'G24z.',NULL,'Secondary hypertension NOS'),('efi-hypertension',1,'G24z.00',NULL,'Secondary hypertension NOS'),('efi-hypertension',1,'G24z0',NULL,'Secondary renovasc.hypert. NOS'),('efi-hypertension',1,'G24z000',NULL,'Secondary renovasc.hypert. NOS'),('efi-hypertension',1,'G24z1',NULL,'Hypertension secondary to drug'),('efi-hypertension',1,'G24z100',NULL,'Hypertension secondary to drug'),('efi-hypertension',1,'G24zz',NULL,'Secondary hypertension NOS'),('efi-hypertension',1,'G24zz00',NULL,'Secondary hypertension NOS'),('efi-hypertension',1,'G2z..',NULL,'Hypertensive disease NOS'),('efi-hypertension',1,'G2z..00',NULL,'Hypertensive disease NOS'),('efi-hypertension',1,'Gyu20',NULL,'[X]Oth secondary hypertension'),('efi-hypertension',1,'Gyu2000',NULL,'[X]Oth secondary hypertension'),('efi-hypertension',1,'Gyu21',NULL,'[X]Hyperten,2ndary oth ren dis'),('efi-hypertension',1,'Gyu2100',NULL,'[X]Hyperten,2ndary oth ren dis');
INSERT INTO #codesreadv2
VALUES ('efi-hypotension',1,'79370',NULL,'Implant cardiac pacemaker NEC'),('efi-hypotension',1,'7937000',NULL,'Implant cardiac pacemaker NEC'),('efi-hypotension',1,'1B55.',NULL,'Dizziness on standing up'),('efi-hypotension',1,'1B55.00',NULL,'Dizziness on standing up'),('efi-hypotension',1,'1B6..',NULL,'Disturbance of consciousness'),('efi-hypotension',1,'1B6..00',NULL,'Disturbance of consciousness'),('efi-hypotension',1,'1B62.',NULL,'Syncope/vasovagal faint'),('efi-hypotension',1,'1B62.00',NULL,'Syncope/vasovagal faint'),('efi-hypotension',1,'1B65.',NULL,'Had a collapse'),('efi-hypotension',1,'1B65.00',NULL,'Had a collapse'),('efi-hypotension',1,'1B68.',NULL,'Felt faint'),('efi-hypotension',1,'1B68.00',NULL,'Felt faint'),('efi-hypotension',1,'F1303',NULL,'Parkinson+orthostatic hypoten.'),('efi-hypotension',1,'F130300',NULL,'Parkinson+orthostatic hypoten.'),('efi-hypotension',1,'G87..',NULL,'Hypotension'),('efi-hypotension',1,'G87..00',NULL,'Hypotension'),('efi-hypotension',1,'G870.',NULL,'Orthostatic hypotension'),('efi-hypotension',1,'G870.00',NULL,'Orthostatic hypotension'),('efi-hypotension',1,'G871.',NULL,'Chronic hypotension'),('efi-hypotension',1,'G871.00',NULL,'Chronic hypotension'),('efi-hypotension',1,'G872.',NULL,'Idiopathic hypotension'),('efi-hypotension',1,'G872.00',NULL,'Idiopathic hypotension'),('efi-hypotension',1,'G873.',NULL,'Hypotension due to drugs'),('efi-hypotension',1,'G873.00',NULL,'Hypotension due to drugs'),('efi-hypotension',1,'G87z.',NULL,'Hypotension NOS'),('efi-hypotension',1,'G87z.00',NULL,'Hypotension NOS'),('efi-hypotension',1,'R002.',NULL,'[D]Syncope and collapse'),('efi-hypotension',1,'R002.00',NULL,'[D]Syncope and collapse'),('efi-hypotension',1,'R0021',NULL,'[D]Fainting'),('efi-hypotension',1,'R002100',NULL,'[D]Fainting'),('efi-hypotension',1,'R0022',NULL,'[D]Vasovagal attack'),('efi-hypotension',1,'R002200',NULL,'[D]Vasovagal attack'),('efi-hypotension',1,'R0023',NULL,'[D]Collapse'),('efi-hypotension',1,'R002300',NULL,'[D]Collapse'),('efi-hypotension',1,'R0042',NULL,'[D]Light-headedness'),('efi-hypotension',1,'R004200',NULL,'[D]Light-headedness');
INSERT INTO #codesreadv2
VALUES ('efi-osteoporosis',1,'56812',NULL,'Bone densimetry abnormal'),('efi-osteoporosis',1,'5681200',NULL,'Bone densimetry abnormal'),('efi-osteoporosis',1,'14OD.',NULL,'At risk osteoporotic fracture'),('efi-osteoporosis',1,'14OD.00',NULL,'At risk osteoporotic fracture'),('efi-osteoporosis',1,'58EN.',NULL,'Lumbar DXA result osteopenic'),('efi-osteoporosis',1,'58EN.00',NULL,'Lumbar DXA result osteopenic'),('efi-osteoporosis',1,'66a..',NULL,'Osteoporosis monitoring'),('efi-osteoporosis',1,'66a..00',NULL,'Osteoporosis monitoring'),('efi-osteoporosis',1,'66a2.',NULL,'Osteoporosis treatment started'),('efi-osteoporosis',1,'66a2.00',NULL,'Osteoporosis treatment started'),('efi-osteoporosis',1,'66a3.',NULL,'Osteoporosis treatment stopped'),('efi-osteoporosis',1,'66a3.00',NULL,'Osteoporosis treatment stopped'),('efi-osteoporosis',1,'66a4.',NULL,'Osteoporosis treatment changed'),('efi-osteoporosis',1,'66a4.00',NULL,'Osteoporosis treatment changed'),('efi-osteoporosis',1,'66a5.',NULL,'Osteoporosis - no treatment'),('efi-osteoporosis',1,'66a5.00',NULL,'Osteoporosis - no treatment'),('efi-osteoporosis',1,'66a6.',NULL,'Osteoporosis - dietary advice'),('efi-osteoporosis',1,'66a6.00',NULL,'Osteoporosis - dietary advice'),('efi-osteoporosis',1,'66a7.',NULL,'Osteoporosis - diet assessment'),('efi-osteoporosis',1,'66a7.00',NULL,'Osteoporosis - diet assessment'),('efi-osteoporosis',1,'66a8.',NULL,'Osteoporosis - exercise advice'),('efi-osteoporosis',1,'66a8.00',NULL,'Osteoporosis - exercise advice'),('efi-osteoporosis',1,'66a9.',NULL,'Osteoporosis-falls prevention'),('efi-osteoporosis',1,'66a9.00',NULL,'Osteoporosis-falls prevention'),('efi-osteoporosis',1,'66aA.',NULL,'Osteoporosis-treatmnt response'),('efi-osteoporosis',1,'66aA.00',NULL,'Osteoporosis-treatmnt response'),('efi-osteoporosis',1,'66aE.',NULL,'Refer osteoporosis specialist'),('efi-osteoporosis',1,'66aE.00',NULL,'Refer osteoporosis specialist'),('efi-osteoporosis',1,'8HTS.',NULL,'Refer to osteoporosis clinic'),('efi-osteoporosis',1,'8HTS.00',NULL,'Refer to osteoporosis clinic'),('efi-osteoporosis',1,'9N0h.',NULL,'Seen in osteoporosis clinic'),('efi-osteoporosis',1,'9N0h.00',NULL,'Seen in osteoporosis clinic'),('efi-osteoporosis',1,'9Od0.',NULL,'Attends osteoporosis monitor'),('efi-osteoporosis',1,'9Od0.00',NULL,'Attends osteoporosis monitor'),('efi-osteoporosis',1,'9Od2.',NULL,'Osteoporosis monitor default'),('efi-osteoporosis',1,'9Od2.00',NULL,'Osteoporosis monitor default'),('efi-osteoporosis',1,'N330.',NULL,'Osteoporosis'),('efi-osteoporosis',1,'N330.00',NULL,'Osteoporosis'),('efi-osteoporosis',1,'N3300',NULL,'Osteoporosis, unspecified'),('efi-osteoporosis',1,'N330000',NULL,'Osteoporosis, unspecified'),('efi-osteoporosis',1,'N3301',NULL,'Senile osteoporosis'),('efi-osteoporosis',1,'N330100',NULL,'Senile osteoporosis'),('efi-osteoporosis',1,'N3302',NULL,'Postmenopausal osteoporosis'),('efi-osteoporosis',1,'N330200',NULL,'Postmenopausal osteoporosis'),('efi-osteoporosis',1,'N3303',NULL,'Idiopathic osteoporosis'),('efi-osteoporosis',1,'N330300',NULL,'Idiopathic osteoporosis'),('efi-osteoporosis',1,'N3304',NULL,'Dissuse osteoporosis'),('efi-osteoporosis',1,'N330400',NULL,'Dissuse osteoporosis'),('efi-osteoporosis',1,'N3305',NULL,'Drug-induced osteoporosis'),('efi-osteoporosis',1,'N330500',NULL,'Drug-induced osteoporosis'),('efi-osteoporosis',1,'N3306',NULL,'Postoophorectomy osteoporosis'),('efi-osteoporosis',1,'N330600',NULL,'Postoophorectomy osteoporosis'),('efi-osteoporosis',1,'N3307',NULL,'Postsurg malabsorp osteoporos'),('efi-osteoporosis',1,'N330700',NULL,'Postsurg malabsorp osteoporos'),('efi-osteoporosis',1,'N3308',NULL,'Local osteoporosis - Lequesne'),('efi-osteoporosis',1,'N330800',NULL,'Local osteoporosis - Lequesne'),('efi-osteoporosis',1,'N330A',NULL,'Osteoporosis in endocr disord'),('efi-osteoporosis',1,'N330A00',NULL,'Osteoporosis in endocr disord'),('efi-osteoporosis',1,'N330B',NULL,'Vertebral osteoporosis'),('efi-osteoporosis',1,'N330B00',NULL,'Vertebral osteoporosis'),('efi-osteoporosis',1,'N330C',NULL,'Osteoporosis localized spine'),('efi-osteoporosis',1,'N330C00',NULL,'Osteoporosis localized spine'),('efi-osteoporosis',1,'N330D',NULL,'Osteoporos due corticosteroid'),('efi-osteoporosis',1,'N330D00',NULL,'Osteoporos due corticosteroid'),('efi-osteoporosis',1,'N330z',NULL,'Osteoporosis NOS'),('efi-osteoporosis',1,'N330z00',NULL,'Osteoporosis NOS'),('efi-osteoporosis',1,'N3312',NULL,'Postoophorc osteopor+path frct'),('efi-osteoporosis',1,'N331200',NULL,'Postoophorc osteopor+path frct'),('efi-osteoporosis',1,'N3315',NULL,'Drug-ind osteopor + path fract'),('efi-osteoporosis',1,'N331500',NULL,'Drug-ind osteopor + path fract'),('efi-osteoporosis',1,'N3316',NULL,'Idiopath osteopor + path fract'),('efi-osteoporosis',1,'N331600',NULL,'Idiopath osteopor + path fract'),('efi-osteoporosis',1,'N3318',NULL,'Osteopor path # lumb vertebrae'),('efi-osteoporosis',1,'N331800',NULL,'Osteopor path # lumb vertebrae'),('efi-osteoporosis',1,'N3319',NULL,'Osteopor path # thor vertebrae'),('efi-osteoporosis',1,'N331900',NULL,'Osteopor path # thor vertebrae'),('efi-osteoporosis',1,'N331B',NULL,'Postmenop osteopor+path fract'),('efi-osteoporosis',1,'N331B00',NULL,'Postmenop osteopor+path fract'),('efi-osteoporosis',1,'N331L',NULL,'Collap vert due osteopor NOS'),('efi-osteoporosis',1,'N331L00',NULL,'Collap vert due osteopor NOS'),('efi-osteoporosis',1,'N3370',NULL,'Disuse atrophy of bone'),('efi-osteoporosis',1,'N337000',NULL,'Disuse atrophy of bone'),('efi-osteoporosis',1,'NyuB0',NULL,'[X]Oth osteoporosis+patholog #'),('efi-osteoporosis',1,'NyuB000',NULL,'[X]Oth osteoporosis+patholog #'),('efi-osteoporosis',1,'NyuB1',NULL,'[X]Other osteoporosis'),('efi-osteoporosis',1,'NyuB100',NULL,'[X]Other osteoporosis'),('efi-osteoporosis',1,'NyuB8',NULL,'[X]Unsp osteopor + pathol frac'),('efi-osteoporosis',1,'NyuB800',NULL,'[X]Unsp osteopor + pathol frac'),('efi-osteoporosis',1,'NyuBC',NULL,'[X]Osteopenia'),('efi-osteoporosis',1,'NyuBC00',NULL,'[X]Osteopenia');
INSERT INTO #codesreadv2
VALUES ('efi-parkinsons',1,'297A.',NULL,'O/E - Parkinsonian tremor'),('efi-parkinsons',1,'297A.00',NULL,'O/E - Parkinsonian tremor'),('efi-parkinsons',1,'2987.',NULL,'O/E -Parkinson flexion posture'),('efi-parkinsons',1,'2987.00',NULL,'O/E -Parkinson flexion posture'),('efi-parkinsons',1,'2994.',NULL,'O/E-festination-Parkinson gait'),('efi-parkinsons',1,'2994.00',NULL,'O/E-festination-Parkinson gait'),('efi-parkinsons',1,'A94y1',NULL,'Syphilitic parkinsonism'),('efi-parkinsons',1,'A94y100',NULL,'Syphilitic parkinsonism'),('efi-parkinsons',1,'F116.',NULL,'Lewy body disease'),('efi-parkinsons',1,'F116.00',NULL,'Lewy body disease'),('efi-parkinsons',1,'F11x9',NULL,'Cerebral degen Parkinson dis'),('efi-parkinsons',1,'F11x900',NULL,'Cerebral degen Parkinson dis'),('efi-parkinsons',1,'F12..',NULL,'Parkinsons disease'),('efi-parkinsons',1,'F12..00',NULL,'Parkinsons disease'),('efi-parkinsons',1,'F120.',NULL,'Paralysis agitans'),('efi-parkinsons',1,'F120.00',NULL,'Paralysis agitans'),('efi-parkinsons',1,'F121.',NULL,'Secondary parkinsonism - drugs'),('efi-parkinsons',1,'F121.00',NULL,'Secondary parkinsonism - drugs'),('efi-parkinsons',1,'F12W.',NULL,'Sec parkinson oth ext agent'),('efi-parkinsons',1,'F12W.00',NULL,'Sec parkinson oth ext agent'),('efi-parkinsons',1,'F12X.',NULL,'Secondary parkinsm,unspecif'),('efi-parkinsons',1,'F12X.00',NULL,'Secondary parkinsm,unspecif'),('efi-parkinsons',1,'F12z.',NULL,'Parkinsons disease NOS'),('efi-parkinsons',1,'F12z.00',NULL,'Parkinsons disease NOS'),('efi-parkinsons',1,'F13..',NULL,'Other extrapyramidal disease'),('efi-parkinsons',1,'F13..00',NULL,'Other extrapyramidal disease'),('efi-parkinsons',1,'F1303',NULL,'Parkinson+orthostatic hypoten.'),('efi-parkinsons',1,'F130300',NULL,'Parkinson+orthostatic hypoten.'),('efi-parkinsons',1,'Fyu20',NULL,'[X]O drg-induc 2ndy parkinsnsm'),('efi-parkinsons',1,'Fyu2000',NULL,'[X]O drg-induc 2ndy parkinsnsm'),('efi-parkinsons',1,'Fyu21',NULL,'[X]Oth secondary parkinsonism'),('efi-parkinsons',1,'Fyu2100',NULL,'[X]Oth secondary parkinsonism'),('efi-parkinsons',1,'Fyu22',NULL,'[X]Parkinsonism in diseases CE'),('efi-parkinsons',1,'Fyu2200',NULL,'[X]Parkinsonism in diseases CE'),('efi-parkinsons',1,'Fyu29',NULL,'[X]Secondary parkinsm,unspecif'),('efi-parkinsons',1,'Fyu2900',NULL,'[X]Secondary parkinsm,unspecif'),('efi-parkinsons',1,'Fyu2B',NULL,'[X]Sec parkinson oth ext agent'),('efi-parkinsons',1,'Fyu2B00',NULL,'[X]Sec parkinson oth ext agent'),('efi-parkinsons',1,'R0103',NULL,'[D]Tremor NOS'),('efi-parkinsons',1,'R010300',NULL,'[D]Tremor NOS'),('efi-parkinsons',1,'TJ64.',NULL,'AR - antiparkinsonism drugs'),('efi-parkinsons',1,'TJ64.00',NULL,'AR - antiparkinsonism drugs'),('efi-parkinsons',1,'U6067',NULL,'[X]Antiparkinson drug adv eff'),('efi-parkinsons',1,'U606700',NULL,'[X]Antiparkinson drug adv eff');
INSERT INTO #codesreadv2
VALUES ('efi-peptic-ulcer',1,'76121',NULL,'Open excis lesion stomach NEC'),('efi-peptic-ulcer',1,'7612100',NULL,'Open excis lesion stomach NEC'),('efi-peptic-ulcer',1,'76270',NULL,'Closure perforate duoden ulcer'),('efi-peptic-ulcer',1,'7627000',NULL,'Closure perforate duoden ulcer'),('efi-peptic-ulcer',1,'76271',NULL,'Suture of duodenal ulcer NEC'),('efi-peptic-ulcer',1,'7627100',NULL,'Suture of duodenal ulcer NEC'),('efi-peptic-ulcer',1,'76272',NULL,'Oversew blood vessel duo ulcer'),('efi-peptic-ulcer',1,'7627200',NULL,'Oversew blood vessel duo ulcer'),('efi-peptic-ulcer',1,'14C1.',NULL,'H/O: peptic ulcer'),('efi-peptic-ulcer',1,'14C1.00',NULL,'H/O: peptic ulcer'),('efi-peptic-ulcer',1,'1956.',NULL,'Peptic ulcer symptoms'),('efi-peptic-ulcer',1,'1956.00',NULL,'Peptic ulcer symptoms'),('efi-peptic-ulcer',1,'761D5',NULL,'Endo inj haemostas duod ulcer'),('efi-peptic-ulcer',1,'761D500',NULL,'Endo inj haemostas duod ulcer'),('efi-peptic-ulcer',1,'761D6',NULL,'Endo inj haemost gastric ulcer'),('efi-peptic-ulcer',1,'761D600',NULL,'Endo inj haemost gastric ulcer'),('efi-peptic-ulcer',1,'761J.',NULL,'Gastric ulcer operations'),('efi-peptic-ulcer',1,'761J.00',NULL,'Gastric ulcer operations'),('efi-peptic-ulcer',1,'761J0',NULL,'Closure perforat gastric ulcer'),('efi-peptic-ulcer',1,'761J000',NULL,'Closure perforat gastric ulcer'),('efi-peptic-ulcer',1,'761J1',NULL,'Closure of gastric ulcer NEC'),('efi-peptic-ulcer',1,'761J100',NULL,'Closure of gastric ulcer NEC'),('efi-peptic-ulcer',1,'761Jy',NULL,'Gastric ulcer operation OS'),('efi-peptic-ulcer',1,'761Jy00',NULL,'Gastric ulcer operation OS'),('efi-peptic-ulcer',1,'761Jz',NULL,'Gastric ulcer operation NOS'),('efi-peptic-ulcer',1,'761Jz00',NULL,'Gastric ulcer operation NOS'),('efi-peptic-ulcer',1,'7627.',NULL,'Operations on duodenal ulcer'),('efi-peptic-ulcer',1,'7627.00',NULL,'Operations on duodenal ulcer'),('efi-peptic-ulcer',1,'7627y',NULL,'Duodenal ulcer operation OS'),('efi-peptic-ulcer',1,'7627y00',NULL,'Duodenal ulcer operation OS'),('efi-peptic-ulcer',1,'7627z',NULL,'Duodenal ulcer operation NOS'),('efi-peptic-ulcer',1,'7627z00',NULL,'Duodenal ulcer operation NOS'),('efi-peptic-ulcer',1,'J1016',NULL,'Ulcerative oesophagitis'),('efi-peptic-ulcer',1,'J101600',NULL,'Ulcerative oesophagitis'),('efi-peptic-ulcer',1,'J1020',NULL,'Peptic ulcer of oesophagus'),('efi-peptic-ulcer',1,'J102000',NULL,'Peptic ulcer of oesophagus'),('efi-peptic-ulcer',1,'J11..',NULL,'Gastric ulcer - (GU)'),('efi-peptic-ulcer',1,'J11..00',NULL,'Gastric ulcer - (GU)'),('efi-peptic-ulcer',1,'J110.',NULL,'Acute gastric ulcer'),('efi-peptic-ulcer',1,'J110.00',NULL,'Acute gastric ulcer'),('efi-peptic-ulcer',1,'J1100',NULL,'Acute GU + no complication'),('efi-peptic-ulcer',1,'J110000',NULL,'Acute GU + no complication'),('efi-peptic-ulcer',1,'J1101',NULL,'Acute GU + haemorrhage'),('efi-peptic-ulcer',1,'J110100',NULL,'Acute GU + haemorrhage'),('efi-peptic-ulcer',1,'J1102',NULL,'Acute GU + perforation'),('efi-peptic-ulcer',1,'J110200',NULL,'Acute GU + perforation'),('efi-peptic-ulcer',1,'J1103',NULL,'Acute GU + hge + perforation'),('efi-peptic-ulcer',1,'J110300',NULL,'Acute GU + hge + perforation'),('efi-peptic-ulcer',1,'J1104',NULL,'Acute GU + obstruction'),('efi-peptic-ulcer',1,'J110400',NULL,'Acute GU + obstruction'),('efi-peptic-ulcer',1,'J110y',NULL,'Acute GU unspecified'),('efi-peptic-ulcer',1,'J110y00',NULL,'Acute GU unspecified'),('efi-peptic-ulcer',1,'J110z',NULL,'Acute gastric ulcer NOS'),('efi-peptic-ulcer',1,'J110z00',NULL,'Acute gastric ulcer NOS'),('efi-peptic-ulcer',1,'J111.',NULL,'Chronic gastric ulcer'),('efi-peptic-ulcer',1,'J111.00',NULL,'Chronic gastric ulcer'),('efi-peptic-ulcer',1,'J1110',NULL,'Chronic GU + no complication'),('efi-peptic-ulcer',1,'J111000',NULL,'Chronic GU + no complication'),('efi-peptic-ulcer',1,'J1111',NULL,'Chronic GU + haemorrhage'),('efi-peptic-ulcer',1,'J111100',NULL,'Chronic GU + haemorrhage'),('efi-peptic-ulcer',1,'J1112',NULL,'Chronic GU + perforation'),('efi-peptic-ulcer',1,'J111200',NULL,'Chronic GU + perforation'),('efi-peptic-ulcer',1,'J1114',NULL,'Chronic GU + obstruction'),('efi-peptic-ulcer',1,'J111400',NULL,'Chronic GU + obstruction'),('efi-peptic-ulcer',1,'J111y',NULL,'Chronic GU unspecified'),('efi-peptic-ulcer',1,'J111y00',NULL,'Chronic GU unspecified'),('efi-peptic-ulcer',1,'J111z',NULL,'Chronic gastric ulcer NOS'),('efi-peptic-ulcer',1,'J111z00',NULL,'Chronic gastric ulcer NOS'),('efi-peptic-ulcer',1,'J112.',NULL,'Anti-platelet induced gast ulc'),('efi-peptic-ulcer',1,'J112.00',NULL,'Anti-platelet induced gast ulc'),('efi-peptic-ulcer',1,'J113.',NULL,'NSAID induced gastric ulcer'),('efi-peptic-ulcer',1,'J113.00',NULL,'NSAID induced gastric ulcer'),('efi-peptic-ulcer',1,'J113z',NULL,'NSAID induced gastric ulc NOS'),('efi-peptic-ulcer',1,'J113z00',NULL,'NSAID induced gastric ulc NOS'),('efi-peptic-ulcer',1,'J11y.',NULL,'Unspecified gastric ulcer'),('efi-peptic-ulcer',1,'J11y.00',NULL,'Unspecified gastric ulcer'),('efi-peptic-ulcer',1,'J11y0',NULL,'Unspecif. GU + no complication'),('efi-peptic-ulcer',1,'J11y000',NULL,'Unspecif. GU + no complication'),('efi-peptic-ulcer',1,'J11y1',NULL,'Unspec. GU + haemorrhage'),('efi-peptic-ulcer',1,'J11y100',NULL,'Unspec. GU + haemorrhage'),('efi-peptic-ulcer',1,'J11y2',NULL,'Unspec. GU + perforation'),('efi-peptic-ulcer',1,'J11y200',NULL,'Unspec. GU + perforation'),('efi-peptic-ulcer',1,'J11yz',NULL,'Unspecified gastric ulcer NOS'),('efi-peptic-ulcer',1,'J11yz00',NULL,'Unspecified gastric ulcer NOS'),('efi-peptic-ulcer',1,'J11z.',NULL,'Gastric ulcer NOS'),('efi-peptic-ulcer',1,'J11z.00',NULL,'Gastric ulcer NOS'),('efi-peptic-ulcer',1,'J12..',NULL,'Duodenal ulcer - (DU)'),('efi-peptic-ulcer',1,'J12..00',NULL,'Duodenal ulcer - (DU)'),('efi-peptic-ulcer',1,'J120.',NULL,'Acute duodenal ulcer'),('efi-peptic-ulcer',1,'J120.00',NULL,'Acute duodenal ulcer'),('efi-peptic-ulcer',1,'J1200',NULL,'Acute DU + no complication'),('efi-peptic-ulcer',1,'J120000',NULL,'Acute DU + no complication'),('efi-peptic-ulcer',1,'J1201',NULL,'Acute DU + haemorrhage'),('efi-peptic-ulcer',1,'J120100',NULL,'Acute DU + haemorrhage'),('efi-peptic-ulcer',1,'J1202',NULL,'Acute DU + perforation'),('efi-peptic-ulcer',1,'J120200',NULL,'Acute DU + perforation'),('efi-peptic-ulcer',1,'J1203',NULL,'Acute DU + hge + perforation'),('efi-peptic-ulcer',1,'J120300',NULL,'Acute DU + hge + perforation'),('efi-peptic-ulcer',1,'J120y',NULL,'Acute DU unspecified'),('efi-peptic-ulcer',1,'J120y00',NULL,'Acute DU unspecified'),('efi-peptic-ulcer',1,'J120z',NULL,'Acute duodenal ulcer NOS'),('efi-peptic-ulcer',1,'J120z00',NULL,'Acute duodenal ulcer NOS'),('efi-peptic-ulcer',1,'J121.',NULL,'Chronic duodenal ulcer'),('efi-peptic-ulcer',1,'J121.00',NULL,'Chronic duodenal ulcer'),('efi-peptic-ulcer',1,'J1210',NULL,'Chronic DU + no complication'),('efi-peptic-ulcer',1,'J121000',NULL,'Chronic DU + no complication'),('efi-peptic-ulcer',1,'J1211',NULL,'Chronic DU + haemorrhage'),('efi-peptic-ulcer',1,'J121100',NULL,'Chronic DU + haemorrhage'),('efi-peptic-ulcer',1,'J1212',NULL,'Chronic DU + perforation'),('efi-peptic-ulcer',1,'J121200',NULL,'Chronic DU + perforation'),('efi-peptic-ulcer',1,'J1213',NULL,'Chronic DU + hge + perforat.'),('efi-peptic-ulcer',1,'J121300',NULL,'Chronic DU + hge + perforat.'),('efi-peptic-ulcer',1,'J1214',NULL,'Chronic DU + obstruction'),('efi-peptic-ulcer',1,'J121400',NULL,'Chronic DU + obstruction'),('efi-peptic-ulcer',1,'J121y',NULL,'Chronic DU unspecified'),('efi-peptic-ulcer',1,'J121y00',NULL,'Chronic DU unspecified'),('efi-peptic-ulcer',1,'J121z',NULL,'Chronic duodenal ulcer NOS'),('efi-peptic-ulcer',1,'J121z00',NULL,'Chronic duodenal ulcer NOS'),('efi-peptic-ulcer',1,'J122.',NULL,'Duodenal ulcer disease'),('efi-peptic-ulcer',1,'J122.00',NULL,'Duodenal ulcer disease'),('efi-peptic-ulcer',1,'J124.',NULL,'Recurrent duodenal ulcer'),('efi-peptic-ulcer',1,'J124.00',NULL,'Recurrent duodenal ulcer'),('efi-peptic-ulcer',1,'J125.',NULL,'Anti-platelet induced duod ulc'),('efi-peptic-ulcer',1,'J125.00',NULL,'Anti-platelet induced duod ulc'),('efi-peptic-ulcer',1,'J126.',NULL,'NSAID induced duodenal ulcer'),('efi-peptic-ulcer',1,'J126.00',NULL,'NSAID induced duodenal ulcer'),('efi-peptic-ulcer',1,'J126z',NULL,'NSAID induced duoden ulc NOS'),('efi-peptic-ulcer',1,'J126z00',NULL,'NSAID induced duoden ulc NOS'),('efi-peptic-ulcer',1,'J12y.',NULL,'Unspecified duodenal ulcer'),('efi-peptic-ulcer',1,'J12y.00',NULL,'Unspecified duodenal ulcer'),('efi-peptic-ulcer',1,'J12y0',NULL,'Unspec. DU + no complication'),('efi-peptic-ulcer',1,'J12y000',NULL,'Unspec. DU + no complication'),('efi-peptic-ulcer',1,'J12y1',NULL,'Unspec. DU + haemorrhage'),('efi-peptic-ulcer',1,'J12y100',NULL,'Unspec. DU + haemorrhage'),('efi-peptic-ulcer',1,'J12y2',NULL,'Unspec. DU + perforation'),('efi-peptic-ulcer',1,'J12y200',NULL,'Unspec. DU + perforation'),('efi-peptic-ulcer',1,'J12y3',NULL,'Unspec. DU + hge + perforat.'),('efi-peptic-ulcer',1,'J12y300',NULL,'Unspec. DU + hge + perforat.'),('efi-peptic-ulcer',1,'J12y4',NULL,'Unspec. DU + obstruction'),('efi-peptic-ulcer',1,'J12y400',NULL,'Unspec. DU + obstruction'),('efi-peptic-ulcer',1,'J12yy',NULL,'Unspec.DU; unspec.hge/perf.'),('efi-peptic-ulcer',1,'J12yy00',NULL,'Unspec.DU; unspec.hge/perf.'),('efi-peptic-ulcer',1,'J12yz',NULL,'Unspecified duodenal ulcer NOS'),('efi-peptic-ulcer',1,'J12yz00',NULL,'Unspecified duodenal ulcer NOS'),('efi-peptic-ulcer',1,'J12z.',NULL,'Duodenal ulcer NOS'),('efi-peptic-ulcer',1,'J12z.00',NULL,'Duodenal ulcer NOS'),('efi-peptic-ulcer',1,'J13..',NULL,'Peptic ulcer - (PU) site unsp.'),('efi-peptic-ulcer',1,'J13..00',NULL,'Peptic ulcer - (PU) site unsp.'),('efi-peptic-ulcer',1,'J130.',NULL,'Acute peptic ulcer'),('efi-peptic-ulcer',1,'J130.00',NULL,'Acute peptic ulcer'),('efi-peptic-ulcer',1,'J1300',NULL,'Acute PU + no complication'),('efi-peptic-ulcer',1,'J130000',NULL,'Acute PU + no complication'),('efi-peptic-ulcer',1,'J1301',NULL,'Acute PU + haemorrhage'),
('efi-peptic-ulcer',1,'J130100',NULL,'Acute PU + haemorrhage'),('efi-peptic-ulcer',1,'J1302',NULL,'Acute PU + perforation'),('efi-peptic-ulcer',1,'J130200',NULL,'Acute PU + perforation'),('efi-peptic-ulcer',1,'J1303',NULL,'Acute PU + hge + perforation'),('efi-peptic-ulcer',1,'J130300',NULL,'Acute PU + hge + perforation'),('efi-peptic-ulcer',1,'J130y',NULL,'Acute PU unspecified'),('efi-peptic-ulcer',1,'J130y00',NULL,'Acute PU unspecified'),('efi-peptic-ulcer',1,'J130z',NULL,'Acute peptic ulcer NOS'),('efi-peptic-ulcer',1,'J130z00',NULL,'Acute peptic ulcer NOS'),('efi-peptic-ulcer',1,'J131.',NULL,'Chronic peptic ulcer'),('efi-peptic-ulcer',1,'J131.00',NULL,'Chronic peptic ulcer'),('efi-peptic-ulcer',1,'J1310',NULL,'Chronic PU + no complication'),('efi-peptic-ulcer',1,'J131000',NULL,'Chronic PU + no complication'),('efi-peptic-ulcer',1,'J1311',NULL,'Chronic PU + haemorrhage'),('efi-peptic-ulcer',1,'J131100',NULL,'Chronic PU + haemorrhage'),('efi-peptic-ulcer',1,'J1312',NULL,'Chronic PU + perforation'),('efi-peptic-ulcer',1,'J131200',NULL,'Chronic PU + perforation'),('efi-peptic-ulcer',1,'J131y',NULL,'Chronic PU unspecified'),('efi-peptic-ulcer',1,'J131y00',NULL,'Chronic PU unspecified'),('efi-peptic-ulcer',1,'J131z',NULL,'Chronic peptic ulcer NOS'),('efi-peptic-ulcer',1,'J131z00',NULL,'Chronic peptic ulcer NOS'),('efi-peptic-ulcer',1,'J13y.',NULL,'Unspecified peptic ulcer'),('efi-peptic-ulcer',1,'J13y.00',NULL,'Unspecified peptic ulcer'),('efi-peptic-ulcer',1,'J13y0',NULL,'Unspec. PU + no complication'),('efi-peptic-ulcer',1,'J13y000',NULL,'Unspec. PU + no complication'),('efi-peptic-ulcer',1,'J13y1',NULL,'Unspec. PU + haemorrhage'),('efi-peptic-ulcer',1,'J13y100',NULL,'Unspec. PU + haemorrhage'),('efi-peptic-ulcer',1,'J13y2',NULL,'Unspec. PU + perforation'),('efi-peptic-ulcer',1,'J13y200',NULL,'Unspec. PU + perforation'),('efi-peptic-ulcer',1,'J13yz',NULL,'Unspecified peptic ulcer NOS'),('efi-peptic-ulcer',1,'J13yz00',NULL,'Unspecified peptic ulcer NOS'),('efi-peptic-ulcer',1,'J13z.',NULL,'Peptic ulcer NOS'),('efi-peptic-ulcer',1,'J13z.00',NULL,'Peptic ulcer NOS'),('efi-peptic-ulcer',1,'J14..',NULL,'Gastrojejunal ulcer (GJU)'),('efi-peptic-ulcer',1,'J14..00',NULL,'Gastrojejunal ulcer (GJU)'),('efi-peptic-ulcer',1,'J1401',NULL,'Acute GJU + haemorrhage'),('efi-peptic-ulcer',1,'J140100',NULL,'Acute GJU + haemorrhage'),('efi-peptic-ulcer',1,'J1411',NULL,'Chronic GJU + haemorrhage'),('efi-peptic-ulcer',1,'J141100',NULL,'Chronic GJU + haemorrhage'),('efi-peptic-ulcer',1,'J14y.',NULL,'Unspecif. gastrojejunal ulcer'),('efi-peptic-ulcer',1,'J14y.00',NULL,'Unspecif. gastrojejunal ulcer'),('efi-peptic-ulcer',1,'J14z.',NULL,'Gastrojejunal ulcer NOS'),('efi-peptic-ulcer',1,'J14z.00',NULL,'Gastrojejunal ulcer NOS'),('efi-peptic-ulcer',1,'J17y8',NULL,'Healed gastric ulcer - scar'),('efi-peptic-ulcer',1,'J17y800',NULL,'Healed gastric ulcer - scar'),('efi-peptic-ulcer',1,'J57y8',NULL,'Primary ulcer of intestine'),('efi-peptic-ulcer',1,'J57y800',NULL,'Primary ulcer of intestine'),('efi-peptic-ulcer',1,'ZV12C',NULL,'[V]PH of gastric ulcer'),('efi-peptic-ulcer',1,'ZV12C00',NULL,'[V]PH of gastric ulcer');
INSERT INTO #codesreadv2
VALUES ('efi-pvd',1,'24E9.',NULL,'O/E - R.dorsalis pedis absent'),('efi-pvd',1,'24E9.00',NULL,'O/E - R.dorsalis pedis absent'),('efi-pvd',1,'24EA.',NULL,'O/E - Absent right foot pulses'),('efi-pvd',1,'24EA.00',NULL,'O/E - Absent right foot pulses'),('efi-pvd',1,'24EC.',NULL,'O/E - R dorsalis pedis abnorm'),('efi-pvd',1,'24EC.00',NULL,'O/E - R dorsalis pedis abnorm'),('efi-pvd',1,'24F9.',NULL,'O/E - L.dorsalis pedis absent'),('efi-pvd',1,'24F9.00',NULL,'O/E - L.dorsalis pedis absent'),('efi-pvd',1,'C107.',NULL,'Diab.mell.+periph.circul.dis'),('efi-pvd',1,'C107.00',NULL,'Diab.mell.+periph.circul.dis'),('efi-pvd',1,'C1086',NULL,'Insulin depen diab mel+gangren'),('efi-pvd',1,'C108600',NULL,'Insulin depen diab mel+gangren'),('efi-pvd',1,'C109F',NULL,'NIDDM with periph angiopath'),('efi-pvd',1,'C109F00',NULL,'NIDDM with periph angiopath'),('efi-pvd',1,'C10E6',NULL,'Type 1 diab mell with gangrene'),('efi-pvd',1,'C10E600',NULL,'Type 1 diab mell with gangrene'),('efi-pvd',1,'C10FF',NULL,'Type 2 diab mell+perip angiop'),('efi-pvd',1,'C10FF00',NULL,'Type 2 diab mell+perip angiop'),('efi-pvd',1,'G670.',NULL,'Cerebral atherosclerosis'),('efi-pvd',1,'G670.00',NULL,'Cerebral atherosclerosis'),('efi-pvd',1,'G700.',NULL,'Aortic atherosclerosis'),('efi-pvd',1,'G700.00',NULL,'Aortic atherosclerosis'),('efi-pvd',1,'G73..',NULL,'Other peripheral vascular dis.'),('efi-pvd',1,'G73..00',NULL,'Other peripheral vascular dis.'),('efi-pvd',1,'G73z.',NULL,'Peripheral vascular dis. NOS'),('efi-pvd',1,'G73z.00',NULL,'Peripheral vascular dis. NOS'),('efi-pvd',1,'G73zz',NULL,'Peripheral vasc.disease NOS'),('efi-pvd',1,'G73zz00',NULL,'Peripheral vasc.disease NOS'),('efi-pvd',1,'M2710',NULL,'Ischaemic ulcer diabetic foot'),('efi-pvd',1,'M271000',NULL,'Ischaemic ulcer diabetic foot');
INSERT INTO #codesreadv2
VALUES ('efi-respiratory-disease',1,'74592',NULL,'Nebuliser therapy'),('efi-respiratory-disease',1,'7459200',NULL,'Nebuliser therapy'),('efi-respiratory-disease',1,'14B..',NULL,'H/O: respiratory disease'),('efi-respiratory-disease',1,'14B..00',NULL,'H/O: respiratory disease'),('efi-respiratory-disease',1,'14B3.',NULL,'H/O: chr.obstr. airway disease'),('efi-respiratory-disease',1,'14B3.00',NULL,'H/O: chr.obstr. airway disease'),('efi-respiratory-disease',1,'14B4.',NULL,'H/O: asthma'),('efi-respiratory-disease',1,'14B4.00',NULL,'H/O: asthma'),('efi-respiratory-disease',1,'14OX.',NULL,'At risk of COPD exacerbation'),('efi-respiratory-disease',1,'14OX.00',NULL,'At risk of COPD exacerbation'),('efi-respiratory-disease',1,'1712.',NULL,'Dry cough'),('efi-respiratory-disease',1,'1712.00',NULL,'Dry cough'),('efi-respiratory-disease',1,'1713.',NULL,'Productive cough -clear sputum'),('efi-respiratory-disease',1,'1713.00',NULL,'Productive cough -clear sputum'),('efi-respiratory-disease',1,'1715.',NULL,'Productive cough-yellow sputum'),('efi-respiratory-disease',1,'1715.00',NULL,'Productive cough-yellow sputum'),('efi-respiratory-disease',1,'171A.',NULL,'Chronic cough'),('efi-respiratory-disease',1,'171A.00',NULL,'Chronic cough'),('efi-respiratory-disease',1,'173A.',NULL,'Exercise induced asthma'),('efi-respiratory-disease',1,'173A.00',NULL,'Exercise induced asthma'),('efi-respiratory-disease',1,'178..',NULL,'Asthma trigger'),('efi-respiratory-disease',1,'178..00',NULL,'Asthma trigger'),('efi-respiratory-disease',1,'1780.',NULL,'Aspirin induced asthma'),('efi-respiratory-disease',1,'1780.00',NULL,'Aspirin induced asthma'),('efi-respiratory-disease',1,'1O2..',NULL,'Asthma confirmed'),('efi-respiratory-disease',1,'1O2..00',NULL,'Asthma confirmed'),('efi-respiratory-disease',1,'3399.',NULL,'FEV1/FVC ratio abnormal'),('efi-respiratory-disease',1,'3399.00',NULL,'FEV1/FVC ratio abnormal'),('efi-respiratory-disease',1,'339U.',NULL,'FEV1/FVC < 70% of predicted'),('efi-respiratory-disease',1,'339U.00',NULL,'FEV1/FVC < 70% of predicted'),('efi-respiratory-disease',1,'33G0.',NULL,'Spirometry reversibility neg'),('efi-respiratory-disease',1,'33G0.00',NULL,'Spirometry reversibility neg'),('efi-respiratory-disease',1,'388t.',NULL,'RCP asthma assessment'),('efi-respiratory-disease',1,'388t.00',NULL,'RCP asthma assessment'),('efi-respiratory-disease',1,'663..',NULL,'Respiratory disease monitoring'),('efi-respiratory-disease',1,'663..00',NULL,'Respiratory disease monitoring'),('efi-respiratory-disease',1,'663J.',NULL,'Airways obstruction reversible'),('efi-respiratory-disease',1,'663J.00',NULL,'Airways obstruction reversible'),('efi-respiratory-disease',1,'663N.',NULL,'Asthma disturbing sleep'),('efi-respiratory-disease',1,'663N.00',NULL,'Asthma disturbing sleep'),('efi-respiratory-disease',1,'663N0',NULL,'Asthma causing night waking'),('efi-respiratory-disease',1,'663N000',NULL,'Asthma causing night waking'),('efi-respiratory-disease',1,'663N1',NULL,'Asthma disturbs sleep weekly'),('efi-respiratory-disease',1,'663N100',NULL,'Asthma disturbs sleep weekly'),('efi-respiratory-disease',1,'663N2',NULL,'Asthma disturbs sleep freqntly'),('efi-respiratory-disease',1,'663N200',NULL,'Asthma disturbs sleep freqntly'),('efi-respiratory-disease',1,'663O.',NULL,'Asthma not disturbing sleep'),('efi-respiratory-disease',1,'663O.00',NULL,'Asthma not disturbing sleep'),('efi-respiratory-disease',1,'663O0',NULL,'Asthma never disturbs sleep'),('efi-respiratory-disease',1,'663O000',NULL,'Asthma never disturbs sleep'),('efi-respiratory-disease',1,'663P.',NULL,'Asthma limiting activities'),('efi-respiratory-disease',1,'663P.00',NULL,'Asthma limiting activities'),('efi-respiratory-disease',1,'663Q.',NULL,'Asthma not limiting activities'),('efi-respiratory-disease',1,'663Q.00',NULL,'Asthma not limiting activities'),('efi-respiratory-disease',1,'663U.',NULL,'Asthma management plan given'),('efi-respiratory-disease',1,'663U.00',NULL,'Asthma management plan given'),('efi-respiratory-disease',1,'663V.',NULL,'Asthma severity'),('efi-respiratory-disease',1,'663V.00',NULL,'Asthma severity'),('efi-respiratory-disease',1,'663V0',NULL,'Occasional asthma'),('efi-respiratory-disease',1,'663V000',NULL,'Occasional asthma'),('efi-respiratory-disease',1,'663V1',NULL,'Mild asthma'),('efi-respiratory-disease',1,'663V100',NULL,'Mild asthma'),('efi-respiratory-disease',1,'663V2',NULL,'Moderate asthma'),('efi-respiratory-disease',1,'663V200',NULL,'Moderate asthma'),('efi-respiratory-disease',1,'663V3',NULL,'Severe asthma'),('efi-respiratory-disease',1,'663V300',NULL,'Severe asthma'),('efi-respiratory-disease',1,'663W.',NULL,'Asthma prophylaxis used'),('efi-respiratory-disease',1,'663W.00',NULL,'Asthma prophylaxis used'),('efi-respiratory-disease',1,'663d.',NULL,'Emerg asthm adm since lst appt'),('efi-respiratory-disease',1,'663d.00',NULL,'Emerg asthm adm since lst appt'),('efi-respiratory-disease',1,'663e.',NULL,'Asthma restricts exercise'),('efi-respiratory-disease',1,'663e.00',NULL,'Asthma restricts exercise'),('efi-respiratory-disease',1,'663f.',NULL,'Asthma never restrcts exercise'),('efi-respiratory-disease',1,'663f.00',NULL,'Asthma never restrcts exercise'),('efi-respiratory-disease',1,'663h.',NULL,'Asthma - currently dormant'),('efi-respiratory-disease',1,'663h.00',NULL,'Asthma - currently dormant'),('efi-respiratory-disease',1,'663j.',NULL,'Asthma - currently active'),('efi-respiratory-disease',1,'663j.00',NULL,'Asthma - currently active'),('efi-respiratory-disease',1,'663l.',NULL,'Spacer device in use'),('efi-respiratory-disease',1,'663l.00',NULL,'Spacer device in use'),('efi-respiratory-disease',1,'663m.',NULL,'Asth A&E attend since last vis'),('efi-respiratory-disease',1,'663m.00',NULL,'Asth A&E attend since last vis'),('efi-respiratory-disease',1,'663n.',NULL,'Asth treat compliance satisfac'),('efi-respiratory-disease',1,'663n.00',NULL,'Asth treat compliance satisfac'),('efi-respiratory-disease',1,'663p.',NULL,'Asth treat compliance unsatisf'),('efi-respiratory-disease',1,'663p.00',NULL,'Asth treat compliance unsatisf'),('efi-respiratory-disease',1,'663q.',NULL,'Asthma daytime symptoms'),('efi-respiratory-disease',1,'663q.00',NULL,'Asthma daytime symptoms'),('efi-respiratory-disease',1,'663r.',NULL,'Asthma night symp 1-2 per mth'),('efi-respiratory-disease',1,'663r.00',NULL,'Asthma night symp 1-2 per mth'),('efi-respiratory-disease',1,'663s.',NULL,'Asthma never causes day symps'),('efi-respiratory-disease',1,'663s.00',NULL,'Asthma never causes day symps'),('efi-respiratory-disease',1,'663t.',NULL,'Asthma day symp 1-2 per mth'),('efi-respiratory-disease',1,'663t.00',NULL,'Asthma day symp 1-2 per mth'),('efi-respiratory-disease',1,'663u.',NULL,'Asthma day symp 1-2 per week'),('efi-respiratory-disease',1,'663u.00',NULL,'Asthma day symp 1-2 per week'),('efi-respiratory-disease',1,'663v.',NULL,'Asthma daytime symps most days'),('efi-respiratory-disease',1,'663v.00',NULL,'Asthma daytime symps most days'),('efi-respiratory-disease',1,'663w.',NULL,'Asthm limits walk hills/stairs'),('efi-respiratory-disease',1,'663w.00',NULL,'Asthm limits walk hills/stairs'),('efi-respiratory-disease',1,'663x.',NULL,'Asthma limits walking on flat'),('efi-respiratory-disease',1,'663x.00',NULL,'Asthma limits walking on flat'),('efi-respiratory-disease',1,'663y.',NULL,'Num asthm exacs in past year'),('efi-respiratory-disease',1,'663y.00',NULL,'Num asthm exacs in past year'),('efi-respiratory-disease',1,'66Y5.',NULL,'Change in asthma managemt plan'),('efi-respiratory-disease',1,'66Y5.00',NULL,'Change in asthma managemt plan'),('efi-respiratory-disease',1,'66Y9.',NULL,'Step up chnge asthm managmt pl'),('efi-respiratory-disease',1,'66Y9.00',NULL,'Step up chnge asthm managmt pl'),('efi-respiratory-disease',1,'66YA.',NULL,'Step down chnge asthm manag pl'),('efi-respiratory-disease',1,'66YA.00',NULL,'Step down chnge asthm manag pl'),('efi-respiratory-disease',1,'66YB.',NULL,'COPD monitoring'),('efi-respiratory-disease',1,'66YB.00',NULL,'COPD monitoring'),('efi-respiratory-disease',1,'66YD.',NULL,'COPD monitoring due'),('efi-respiratory-disease',1,'66YD.00',NULL,'COPD monitoring due'),('efi-respiratory-disease',1,'66YE.',NULL,'Asthma monitoring due'),('efi-respiratory-disease',1,'66YE.00',NULL,'Asthma monitoring due'),('efi-respiratory-disease',1,'66YI.',NULL,'COPD self-managemnt plan given'),('efi-respiratory-disease',1,'66YI.00',NULL,'COPD self-managemnt plan given'),('efi-respiratory-disease',1,'66YJ.',NULL,'Asthma annual review'),('efi-respiratory-disease',1,'66YJ.00',NULL,'Asthma annual review'),('efi-respiratory-disease',1,'66YK.',NULL,'Asthma follow-up'),('efi-respiratory-disease',1,'66YK.00',NULL,'Asthma follow-up'),('efi-respiratory-disease',1,'66YL.',NULL,'COPD follow-up'),('efi-respiratory-disease',1,'66YL.00',NULL,'COPD follow-up'),('efi-respiratory-disease',1,'66YM.',NULL,'COPD annual review'),('efi-respiratory-disease',1,'66YM.00',NULL,'COPD annual review'),('efi-respiratory-disease',1,'66YP.',NULL,'Asthma night-time symptoms'),('efi-respiratory-disease',1,'66YP.00',NULL,'Asthma night-time symptoms'),('efi-respiratory-disease',1,'66YQ.',NULL,'Asthma monitoring by nurse'),('efi-respiratory-disease',1,'66YQ.00',NULL,'Asthma monitoring by nurse'),('efi-respiratory-disease',1,'66YR.',NULL,'Asthma monitoring by doctor'),('efi-respiratory-disease',1,'66YR.00',NULL,'Asthma monitoring by doctor'),('efi-respiratory-disease',1,'66YS.',NULL,'COPD monitoring by nurse'),('efi-respiratory-disease',1,'66YS.00',NULL,'COPD monitoring by nurse'),('efi-respiratory-disease',1,'66YT.',NULL,'COPD monitoring by doctor'),('efi-respiratory-disease',1,'66YT.00',NULL,'COPD monitoring by doctor'),('efi-respiratory-disease',1,'66YZ.',NULL,'Does not have asthma man plan'),('efi-respiratory-disease',1,'66YZ.00',NULL,'Does not have asthma man plan'),('efi-respiratory-disease',1,'66Yd.',NULL,'COPD A&E attend sin last visit'),('efi-respiratory-disease',1,'66Yd.00',NULL,'COPD A&E attend sin last visit'),
('efi-respiratory-disease',1,'66Ye.',NULL,'Emer COPD admi sin last appoin'),('efi-respiratory-disease',1,'66Ye.00',NULL,'Emer COPD admi sin last appoin'),('efi-respiratory-disease',1,'66Yf.',NULL,'Numb COPD exacer in past year'),('efi-respiratory-disease',1,'66Yf.00',NULL,'Numb COPD exacer in past year'),('efi-respiratory-disease',1,'66Yg.',NULL,'COPD disturbs sleep'),('efi-respiratory-disease',1,'66Yg.00',NULL,'COPD disturbs sleep'),('efi-respiratory-disease',1,'66Yh.',NULL,'COPD does not disturb sleep'),('efi-respiratory-disease',1,'66Yh.00',NULL,'COPD does not disturb sleep'),('efi-respiratory-disease',1,'66Yi.',NULL,'Mult COPD emerg hosp admission'),('efi-respiratory-disease',1,'66Yi.00',NULL,'Mult COPD emerg hosp admission'),('efi-respiratory-disease',1,'679J.',NULL,'Health education - asthma'),('efi-respiratory-disease',1,'679J.00',NULL,'Health education - asthma'),('efi-respiratory-disease',1,'679V.',NULL,'Health education - COPD'),('efi-respiratory-disease',1,'679V.00',NULL,'Health education - COPD'),('efi-respiratory-disease',1,'8764.',NULL,'Nebuliser therapy'),('efi-respiratory-disease',1,'8764.00',NULL,'Nebuliser therapy'),('efi-respiratory-disease',1,'8776.',NULL,'LTOT - Long-term oxyg therapy'),('efi-respiratory-disease',1,'8776.00',NULL,'LTOT - Long-term oxyg therapy'),('efi-respiratory-disease',1,'8778.',NULL,'Ambulatory oxygen therapy'),('efi-respiratory-disease',1,'8778.00',NULL,'Ambulatory oxygen therapy'),('efi-respiratory-disease',1,'8793.',NULL,'Asthma control step 0'),('efi-respiratory-disease',1,'8793.00',NULL,'Asthma control step 0'),('efi-respiratory-disease',1,'8794.',NULL,'Asthma control step 1'),('efi-respiratory-disease',1,'8794.00',NULL,'Asthma control step 1'),('efi-respiratory-disease',1,'8795.',NULL,'Asthma control step 2'),('efi-respiratory-disease',1,'8795.00',NULL,'Asthma control step 2'),('efi-respiratory-disease',1,'8796.',NULL,'Asthma control step 3'),('efi-respiratory-disease',1,'8796.00',NULL,'Asthma control step 3'),('efi-respiratory-disease',1,'8797.',NULL,'Asthma control step 4'),('efi-respiratory-disease',1,'8797.00',NULL,'Asthma control step 4'),('efi-respiratory-disease',1,'8798.',NULL,'Asthma control step 5'),('efi-respiratory-disease',1,'8798.00',NULL,'Asthma control step 5'),('efi-respiratory-disease',1,'8B3j.',NULL,'Asthma medication review'),('efi-respiratory-disease',1,'8B3j.00',NULL,'Asthma medication review'),('efi-respiratory-disease',1,'8CR0.',NULL,'Asthma clin management plan'),('efi-respiratory-disease',1,'8CR0.00',NULL,'Asthma clin management plan'),('efi-respiratory-disease',1,'8CR1.',NULL,'COPD clinical management plan'),('efi-respiratory-disease',1,'8CR1.00',NULL,'COPD clinical management plan'),('efi-respiratory-disease',1,'8FA..',NULL,'Pulmonary rehabilitation'),('efi-respiratory-disease',1,'8FA..00',NULL,'Pulmonary rehabilitation'),('efi-respiratory-disease',1,'8FA1.',NULL,'Pulm rehab programme commenced'),('efi-respiratory-disease',1,'8FA1.00',NULL,'Pulm rehab programme commenced'),('efi-respiratory-disease',1,'8H2P.',NULL,'Emergency admission, asthma'),('efi-respiratory-disease',1,'8H2P.00',NULL,'Emergency admission, asthma'),('efi-respiratory-disease',1,'8H2R.',NULL,'Admit COPD emergency'),('efi-respiratory-disease',1,'8H2R.00',NULL,'Admit COPD emergency'),('efi-respiratory-disease',1,'8H7u.',NULL,'Referral to pulmonary rehab'),('efi-respiratory-disease',1,'8H7u.00',NULL,'Referral to pulmonary rehab'),('efi-respiratory-disease',1,'8HTT.',NULL,'Referral to asthma clinic'),('efi-respiratory-disease',1,'8HTT.00',NULL,'Referral to asthma clinic'),('efi-respiratory-disease',1,'9N1d.',NULL,'Seen in asthma clinic'),('efi-respiratory-disease',1,'9N1d.00',NULL,'Seen in asthma clinic'),('efi-respiratory-disease',1,'9N4Q.',NULL,'Did not attend asthma clinic'),('efi-respiratory-disease',1,'9N4Q.00',NULL,'Did not attend asthma clinic'),('efi-respiratory-disease',1,'9N4W.',NULL,'Did not attend COPD clinic'),('efi-respiratory-disease',1,'9N4W.00',NULL,'Did not attend COPD clinic'),('efi-respiratory-disease',1,'9OJ1.',NULL,'Attends asthma monitoring'),('efi-respiratory-disease',1,'9OJ1.00',NULL,'Attends asthma monitoring'),('efi-respiratory-disease',1,'9OJ2.',NULL,'Refuses asthma monitoring'),('efi-respiratory-disease',1,'9OJ2.00',NULL,'Refuses asthma monitoring'),('efi-respiratory-disease',1,'9OJ3.',NULL,'Asthma monitor offer default'),('efi-respiratory-disease',1,'9OJ3.00',NULL,'Asthma monitor offer default'),('efi-respiratory-disease',1,'9OJ7.',NULL,'Asthma monitor verbal invite'),('efi-respiratory-disease',1,'9OJ7.00',NULL,'Asthma monitor verbal invite'),('efi-respiratory-disease',1,'9OJA.',NULL,'Asthma monitoring check done'),('efi-respiratory-disease',1,'9OJA.00',NULL,'Asthma monitoring check done'),('efi-respiratory-disease',1,'9Oi3.',NULL,'COPD monitoring verbal invite'),('efi-respiratory-disease',1,'9Oi3.00',NULL,'COPD monitoring verbal invite'),('efi-respiratory-disease',1,'9h52.',NULL,'Except COPD qual ind: Inf dis'),('efi-respiratory-disease',1,'9h52.00',NULL,'Except COPD qual ind: Inf dis'),('efi-respiratory-disease',1,'9hA1.',NULL,'Except asthma qual ind: Pt uns'),('efi-respiratory-disease',1,'9hA1.00',NULL,'Except asthma qual ind: Pt uns'),('efi-respiratory-disease',1,'9hA2.',NULL,'Excep asthma qual ind: Inf dis'),('efi-respiratory-disease',1,'9hA2.00',NULL,'Excep asthma qual ind: Inf dis'),('efi-respiratory-disease',1,'9kf..',NULL,'COPD - enhanced services admin'),('efi-respiratory-disease',1,'9kf..00',NULL,'COPD - enhanced services admin'),('efi-respiratory-disease',1,'9kf0.',NULL,'COPD unsuitbl pulm rehab - ESA'),('efi-respiratory-disease',1,'9kf0.00',NULL,'COPD unsuitbl pulm rehab - ESA'),('efi-respiratory-disease',1,'G401.',NULL,'Pulmonary embolism'),('efi-respiratory-disease',1,'G401.00',NULL,'Pulmonary embolism'),('efi-respiratory-disease',1,'G4011',NULL,'Recurrent pulmonary embolism'),('efi-respiratory-disease',1,'G401100',NULL,'Recurrent pulmonary embolism'),('efi-respiratory-disease',1,'G410.',NULL,'Primary pulmonary hypertension'),('efi-respiratory-disease',1,'G410.00',NULL,'Primary pulmonary hypertension'),('efi-respiratory-disease',1,'G41y0',NULL,'Secondary pulmonary hypertens.'),('efi-respiratory-disease',1,'G41y000',NULL,'Secondary pulmonary hypertens.'),('efi-respiratory-disease',1,'H....',NULL,'Respiratory system diseases'),('efi-respiratory-disease',1,'H....00',NULL,'Respiratory system diseases'),('efi-respiratory-disease',1,'H3...',NULL,'Chronic obstructive pulm.dis.'),('efi-respiratory-disease',1,'H3...00',NULL,'Chronic obstructive pulm.dis.'),('efi-respiratory-disease',1,'H30..',NULL,'Bronchitis unspecified'),('efi-respiratory-disease',1,'H30..00',NULL,'Bronchitis unspecified'),('efi-respiratory-disease',1,'H302.',NULL,'Wheezy bronchitis'),('efi-respiratory-disease',1,'H302.00',NULL,'Wheezy bronchitis'),('efi-respiratory-disease',1,'H31..',NULL,'Chronic bronchitis'),('efi-respiratory-disease',1,'H31..00',NULL,'Chronic bronchitis'),('efi-respiratory-disease',1,'H310.',NULL,'Simple chronic bronchitis'),('efi-respiratory-disease',1,'H310.00',NULL,'Simple chronic bronchitis'),('efi-respiratory-disease',1,'H3100',NULL,'Chronic catarrhal bronchitis'),('efi-respiratory-disease',1,'H310000',NULL,'Chronic catarrhal bronchitis'),('efi-respiratory-disease',1,'H310z',NULL,'Simple chronic bronchitis NOS'),('efi-respiratory-disease',1,'H310z00',NULL,'Simple chronic bronchitis NOS'),('efi-respiratory-disease',1,'H311.',NULL,'Mucopurulent chr.bronchitis'),('efi-respiratory-disease',1,'H311.00',NULL,'Mucopurulent chr.bronchitis'),('efi-respiratory-disease',1,'H3110',NULL,'Purulent chronic bronchitis'),('efi-respiratory-disease',1,'H311000',NULL,'Purulent chronic bronchitis'),('efi-respiratory-disease',1,'H3111',NULL,'Fetid chronic bronchitis'),('efi-respiratory-disease',1,'H311100',NULL,'Fetid chronic bronchitis'),('efi-respiratory-disease',1,'H312.',NULL,'Obstructive chronic bronchitis'),('efi-respiratory-disease',1,'H312.00',NULL,'Obstructive chronic bronchitis'),('efi-respiratory-disease',1,'H3120',NULL,'Chronic asthmatic bronchitis'),('efi-respiratory-disease',1,'H312000',NULL,'Chronic asthmatic bronchitis'),('efi-respiratory-disease',1,'H3122',NULL,'Acute exacerbation of COAD'),('efi-respiratory-disease',1,'H312200',NULL,'Acute exacerbation of COAD'),('efi-respiratory-disease',1,'H312z',NULL,'Obstructive chr.bronchitis NOS'),('efi-respiratory-disease',1,'H312z00',NULL,'Obstructive chr.bronchitis NOS'),('efi-respiratory-disease',1,'H31y.',NULL,'Other chronic bronchitis'),('efi-respiratory-disease',1,'H31y.00',NULL,'Other chronic bronchitis'),('efi-respiratory-disease',1,'H31yz',NULL,'Other chronic bronchitis NOS'),('efi-respiratory-disease',1,'H31yz00',NULL,'Other chronic bronchitis NOS'),('efi-respiratory-disease',1,'H31z.',NULL,'Chronic bronchitis NOS'),('efi-respiratory-disease',1,'H31z.00',NULL,'Chronic bronchitis NOS'),('efi-respiratory-disease',1,'H32..',NULL,'Emphysema'),('efi-respiratory-disease',1,'H32..00',NULL,'Emphysema'),('efi-respiratory-disease',1,'H33..',NULL,'Asthma'),('efi-respiratory-disease',1,'H33..00',NULL,'Asthma'),('efi-respiratory-disease',1,'H330.',NULL,'Extrinsic (atopic) asthma'),('efi-respiratory-disease',1,'H330.00',NULL,'Extrinsic (atopic) asthma'),('efi-respiratory-disease',1,'H3300',NULL,'Extrinsic asthma - no status'),('efi-respiratory-disease',1,'H330000',NULL,'Extrinsic asthma - no status'),('efi-respiratory-disease',1,'H3301',NULL,'Extrinsic asthma + status'),('efi-respiratory-disease',1,'H330100',NULL,'Extrinsic asthma + status'),('efi-respiratory-disease',1,'H330z',NULL,'Extrinsic asthma NOS'),('efi-respiratory-disease',1,'H330z00',NULL,'Extrinsic asthma NOS'),('efi-respiratory-disease',1,'H331.',NULL,'Intrinsic asthma'),('efi-respiratory-disease',1,'H331.00',NULL,'Intrinsic asthma'),('efi-respiratory-disease',1,'H3310',NULL,'Intrinsic asthma - no status'),('efi-respiratory-disease',1,'H331000',NULL,'Intrinsic asthma - no status'),
('efi-respiratory-disease',1,'H3311',NULL,'Intrinsic asthma + status'),('efi-respiratory-disease',1,'H331100',NULL,'Intrinsic asthma + status'),('efi-respiratory-disease',1,'H331z',NULL,'Intrinsic asthma NOS'),('efi-respiratory-disease',1,'H331z00',NULL,'Intrinsic asthma NOS'),('efi-respiratory-disease',1,'H332.',NULL,'Mixed asthma'),('efi-respiratory-disease',1,'H332.00',NULL,'Mixed asthma'),('efi-respiratory-disease',1,'H333.',NULL,'Acute exacerbation of asthma'),('efi-respiratory-disease',1,'H333.00',NULL,'Acute exacerbation of asthma'),('efi-respiratory-disease',1,'H334.',NULL,'Brittle asthma'),('efi-respiratory-disease',1,'H334.00',NULL,'Brittle asthma'),('efi-respiratory-disease',1,'H33z.',NULL,'Asthma unspecified'),('efi-respiratory-disease',1,'H33z.00',NULL,'Asthma unspecified'),('efi-respiratory-disease',1,'H33z0',NULL,'Status asthmaticus NOS'),('efi-respiratory-disease',1,'H33z000',NULL,'Status asthmaticus NOS'),('efi-respiratory-disease',1,'H33z1',NULL,'Asthma attack'),('efi-respiratory-disease',1,'H33z100',NULL,'Asthma attack'),('efi-respiratory-disease',1,'H33z2',NULL,'Late-onset asthma'),('efi-respiratory-disease',1,'H33z200',NULL,'Late-onset asthma'),('efi-respiratory-disease',1,'H33zz',NULL,'Asthma NOS'),('efi-respiratory-disease',1,'H33zz00',NULL,'Asthma NOS'),('efi-respiratory-disease',1,'H36..',NULL,'Mild chron obstr pulm disease'),('efi-respiratory-disease',1,'H36..00',NULL,'Mild chron obstr pulm disease'),('efi-respiratory-disease',1,'H37..',NULL,'Mod chron obstr pulm disease'),('efi-respiratory-disease',1,'H37..00',NULL,'Mod chron obstr pulm disease'),('efi-respiratory-disease',1,'H38..',NULL,'Sev chron obstr pulm disease'),('efi-respiratory-disease',1,'H38..00',NULL,'Sev chron obstr pulm disease'),('efi-respiratory-disease',1,'H39..',NULL,'Very severe COPD'),('efi-respiratory-disease',1,'H39..00',NULL,'Very severe COPD'),('efi-respiratory-disease',1,'H3y..',NULL,'Chronic obstr.airway dis.OS'),('efi-respiratory-disease',1,'H3y..00',NULL,'Chronic obstr.airway dis.OS'),('efi-respiratory-disease',1,'H3y0.',NULL,'Chr obs pulm dis+ac l resp inf'),('efi-respiratory-disease',1,'H3y0.00',NULL,'Chr obs pulm dis+ac l resp inf'),('efi-respiratory-disease',1,'H3y1.',NULL,'Chr obs pulm dis+ac exac,unspc'),('efi-respiratory-disease',1,'H3y1.00',NULL,'Chr obs pulm dis+ac exac,unspc'),('efi-respiratory-disease',1,'H3z..',NULL,'Chronic obstr.airway dis.NOS'),('efi-respiratory-disease',1,'H3z..00',NULL,'Chronic obstr.airway dis.NOS'),('efi-respiratory-disease',1,'H564.',NULL,'Bronchioliti oblit organ pneum'),('efi-respiratory-disease',1,'H564.00',NULL,'Bronchioliti oblit organ pneum'),('efi-respiratory-disease',1,'Hyu31',NULL,'[X]O spcf chron obs pulmon dis'),('efi-respiratory-disease',1,'Hyu3100',NULL,'[X]O spcf chron obs pulmon dis'),('efi-respiratory-disease',1,'N04y0',NULL,'Rheumatoid lung'),('efi-respiratory-disease',1,'N04y000',NULL,'Rheumatoid lung'),('efi-respiratory-disease',1,'R062.',NULL,'[D]Cough'),('efi-respiratory-disease',1,'R062.00',NULL,'[D]Cough'),('efi-respiratory-disease',1,'TJF73',NULL,'AR - theophylline (asthma)'),('efi-respiratory-disease',1,'TJF7300',NULL,'AR - theophylline (asthma)'),('efi-respiratory-disease',1,'U60F6',NULL,'[X]Antiasthmatics adv eff,NEC'),('efi-respiratory-disease',1,'U60F600',NULL,'[X]Antiasthmatics adv eff,NEC'),('efi-respiratory-disease',1,'ZV129',NULL,'[V] PH - Pulmonary embolism'),('efi-respiratory-disease',1,'ZV12900',NULL,'[V] PH - Pulmonary embolism');
INSERT INTO #codesreadv2
VALUES ('efi-skin-ulcer',1,'14F3.',NULL,'H/O: chronic skin ulcer'),('efi-skin-ulcer',1,'14F3.00',NULL,'H/O: chronic skin ulcer'),('efi-skin-ulcer',1,'14F5.',NULL,'H/O: venous leg ulcer'),('efi-skin-ulcer',1,'14F5.00',NULL,'H/O: venous leg ulcer'),('efi-skin-ulcer',1,'2924.',NULL,'O/E - trophic skin ulceration'),('efi-skin-ulcer',1,'2924.00',NULL,'O/E - trophic skin ulceration'),('efi-skin-ulcer',1,'2FF..',NULL,'O/E - skin ulcer'),('efi-skin-ulcer',1,'2FF..00',NULL,'O/E - skin ulcer'),('efi-skin-ulcer',1,'2FF2.',NULL,'O/E - skin ulcer present'),('efi-skin-ulcer',1,'2FF2.00',NULL,'O/E - skin ulcer present'),('efi-skin-ulcer',1,'2FF3.',NULL,'O/E - depth of ulcer'),('efi-skin-ulcer',1,'2FF3.00',NULL,'O/E - depth of ulcer'),('efi-skin-ulcer',1,'2FFZ.',NULL,'O/E - skin ulcer NOS'),('efi-skin-ulcer',1,'2FFZ.00',NULL,'O/E - skin ulcer NOS'),('efi-skin-ulcer',1,'2G48.',NULL,'O/E - ankle ulcer'),('efi-skin-ulcer',1,'2G48.00',NULL,'O/E - ankle ulcer'),('efi-skin-ulcer',1,'2G54.',NULL,'O/E - Right foot ulcer'),('efi-skin-ulcer',1,'2G54.00',NULL,'O/E - Right foot ulcer'),('efi-skin-ulcer',1,'2G55.',NULL,'O/E - Left foot ulcer'),('efi-skin-ulcer',1,'2G55.00',NULL,'O/E - Left foot ulcer'),('efi-skin-ulcer',1,'2G5H.',NULL,'O/E - R diab foot - ulcerated'),('efi-skin-ulcer',1,'2G5H.00',NULL,'O/E - R diab foot - ulcerated'),('efi-skin-ulcer',1,'2G5L.',NULL,'O/E - L diab foot - ulcerated'),('efi-skin-ulcer',1,'2G5L.00',NULL,'O/E - L diab foot - ulcerated'),('efi-skin-ulcer',1,'2G5V.',NULL,'O/E - R chron diab foot ulcer'),('efi-skin-ulcer',1,'2G5V.00',NULL,'O/E - R chron diab foot ulcer'),('efi-skin-ulcer',1,'2G5W.',NULL,'O/E - L chron diab foot ulcer'),('efi-skin-ulcer',1,'2G5W.00',NULL,'O/E - L chron diab foot ulcer'),('efi-skin-ulcer',1,'39C..',NULL,'Pressure sore index value'),('efi-skin-ulcer',1,'39C..00',NULL,'Pressure sore index value'),('efi-skin-ulcer',1,'39C0.',NULL,'Pressure sore'),('efi-skin-ulcer',1,'39C0.00',NULL,'Pressure sore'),('efi-skin-ulcer',1,'4JG3.',NULL,'Skin ulcer swab taken'),('efi-skin-ulcer',1,'4JG3.00',NULL,'Skin ulcer swab taken'),('efi-skin-ulcer',1,'7G2E5',NULL,'Dressing of skin ulcer NEC'),('efi-skin-ulcer',1,'7G2E500',NULL,'Dressing of skin ulcer NEC'),('efi-skin-ulcer',1,'7G2EA',NULL,'Two lay comp bandag skin ulcer'),('efi-skin-ulcer',1,'7G2EA00',NULL,'Two lay comp bandag skin ulcer'),('efi-skin-ulcer',1,'7G2EB',NULL,'Four lay comp band skin ulcer'),('efi-skin-ulcer',1,'7G2EB00',NULL,'Four lay comp band skin ulcer'),('efi-skin-ulcer',1,'7G2EC',NULL,'Three lay comp band skin ulcer'),('efi-skin-ulcer',1,'7G2EC00',NULL,'Three lay comp band skin ulcer'),('efi-skin-ulcer',1,'81H1.',NULL,'Dressing of ulcer'),('efi-skin-ulcer',1,'81H1.00',NULL,'Dressing of ulcer'),('efi-skin-ulcer',1,'8CT1.',NULL,'Leg ulcr compress thrpy finish'),('efi-skin-ulcer',1,'8CT1.00',NULL,'Leg ulcr compress thrpy finish'),('efi-skin-ulcer',1,'8CV2.',NULL,'Leg ulcer compress thrpy start'),('efi-skin-ulcer',1,'8CV2.00',NULL,'Leg ulcer compress thrpy start'),('efi-skin-ulcer',1,'8HTh.',NULL,'Referral to leg ulcer clinic'),('efi-skin-ulcer',1,'8HTh.00',NULL,'Referral to leg ulcer clinic'),('efi-skin-ulcer',1,'9N0t.',NULL,'Seen prim care leg ulcer clini'),('efi-skin-ulcer',1,'9N0t.00',NULL,'Seen prim care leg ulcer clini'),('efi-skin-ulcer',1,'9NM5.',NULL,'Attending leg ulcer clinic'),('efi-skin-ulcer',1,'9NM5.00',NULL,'Attending leg ulcer clinic'),('efi-skin-ulcer',1,'C1094',NULL,'Non-insul depen diab mel+ulcer'),('efi-skin-ulcer',1,'C109400',NULL,'Non-insul depen diab mel+ulcer'),('efi-skin-ulcer',1,'C10F4',NULL,'Type 2 diab mell with ulcer'),('efi-skin-ulcer',1,'C10F400',NULL,'Type 2 diab mell with ulcer'),('efi-skin-ulcer',1,'G830.',NULL,'Varicose vein leg with ulcer'),('efi-skin-ulcer',1,'G830.00',NULL,'Varicose vein leg with ulcer'),('efi-skin-ulcer',1,'G832.',NULL,'Varicose vein leg+ulcer+eczema'),('efi-skin-ulcer',1,'G832.00',NULL,'Varicose vein leg+ulcer+eczema'),('efi-skin-ulcer',1,'G835.',NULL,'Infected varicose ulcer'),('efi-skin-ulcer',1,'G835.00',NULL,'Infected varicose ulcer'),('efi-skin-ulcer',1,'G837.',NULL,'Venous ulcer of leg'),('efi-skin-ulcer',1,'G837.00',NULL,'Venous ulcer of leg'),('efi-skin-ulcer',1,'M27..',NULL,'Chronic skin ulcer'),('efi-skin-ulcer',1,'M27..00',NULL,'Chronic skin ulcer'),('efi-skin-ulcer',1,'M270.',NULL,'Decubitus (pressure) ulcer'),('efi-skin-ulcer',1,'M270.00',NULL,'Decubitus (pressure) ulcer'),('efi-skin-ulcer',1,'M271.',NULL,'Non-pressure ulcer lower limb'),('efi-skin-ulcer',1,'M271.00',NULL,'Non-pressure ulcer lower limb'),('efi-skin-ulcer',1,'M2710',NULL,'Ischaemic ulcer diabetic foot'),('efi-skin-ulcer',1,'M271000',NULL,'Ischaemic ulcer diabetic foot'),('efi-skin-ulcer',1,'M2711',NULL,'Neuropathic diab ulcer - foot'),('efi-skin-ulcer',1,'M271100',NULL,'Neuropathic diab ulcer - foot'),('efi-skin-ulcer',1,'M2712',NULL,'Mixed diabetic ulcer - foot'),('efi-skin-ulcer',1,'M271200',NULL,'Mixed diabetic ulcer - foot'),('efi-skin-ulcer',1,'M2713',NULL,'Arterial leg ulcer'),('efi-skin-ulcer',1,'M271300',NULL,'Arterial leg ulcer'),('efi-skin-ulcer',1,'M2714',NULL,'Mixed venous+artery leg ulcer'),('efi-skin-ulcer',1,'M271400',NULL,'Mixed venous+artery leg ulcer'),('efi-skin-ulcer',1,'M2715',NULL,'Venous ulcer of leg'),('efi-skin-ulcer',1,'M271500',NULL,'Venous ulcer of leg'),('efi-skin-ulcer',1,'M272.',NULL,'Ulcer of skin'),('efi-skin-ulcer',1,'M272.00',NULL,'Ulcer of skin'),('efi-skin-ulcer',1,'M27y.',NULL,'Chronic ulcer skin, other site'),('efi-skin-ulcer',1,'M27y.00',NULL,'Chronic ulcer skin, other site'),('efi-skin-ulcer',1,'M27z.',NULL,'Chronic skin ulcer NOS'),('efi-skin-ulcer',1,'M27z.00',NULL,'Chronic skin ulcer NOS');
INSERT INTO #codesreadv2
VALUES ('efi-stroke-tia',1,'14A7.',NULL,'H/O: CVA/stroke'),('efi-stroke-tia',1,'14A7.00',NULL,'H/O: CVA/stroke'),('efi-stroke-tia',1,'14AB.',NULL,'H/O: TIA'),('efi-stroke-tia',1,'14AB.00',NULL,'H/O: TIA'),('efi-stroke-tia',1,'14AK.',NULL,'H/O: Stroke in last year'),('efi-stroke-tia',1,'14AK.00',NULL,'H/O: Stroke in last year'),('efi-stroke-tia',1,'662M.',NULL,'Stroke monitoring'),('efi-stroke-tia',1,'662M.00',NULL,'Stroke monitoring'),('efi-stroke-tia',1,'662e.',NULL,'Stroke/CVA annual review'),('efi-stroke-tia',1,'662e.00',NULL,'Stroke/CVA annual review'),('efi-stroke-tia',1,'662o.',NULL,'Haemorrhagic stroke monitoring'),('efi-stroke-tia',1,'662o.00',NULL,'Haemorrhagic stroke monitoring'),('efi-stroke-tia',1,'7P242',NULL,'Delivery rehabilitation stroke'),('efi-stroke-tia',1,'7P24200',NULL,'Delivery rehabilitation stroke'),('efi-stroke-tia',1,'8HBJ.',NULL,'Stroke / TIA referral'),('efi-stroke-tia',1,'8HBJ.00',NULL,'Stroke / TIA referral'),('efi-stroke-tia',1,'8HHM.',NULL,'Ref to stroke func improv serv'),('efi-stroke-tia',1,'8HHM.00',NULL,'Ref to stroke func improv serv'),('efi-stroke-tia',1,'8HTQ.',NULL,'Referral to stroke clinic'),('efi-stroke-tia',1,'8HTQ.00',NULL,'Referral to stroke clinic'),('efi-stroke-tia',1,'9N0p.',NULL,'Seen in stroke clinic'),('efi-stroke-tia',1,'9N0p.00',NULL,'Seen in stroke clinic'),('efi-stroke-tia',1,'9N4X.',NULL,'Did not attend stroke clinic'),('efi-stroke-tia',1,'9N4X.00',NULL,'Did not attend stroke clinic'),('efi-stroke-tia',1,'9Om1.',NULL,'Stroke/TIA monitor 2nd letter'),('efi-stroke-tia',1,'9Om1.00',NULL,'Stroke/TIA monitor 2nd letter'),('efi-stroke-tia',1,'9Om2.',NULL,'Stroke/TIA monitor 3rd letter'),('efi-stroke-tia',1,'9Om2.00',NULL,'Stroke/TIA monitor 3rd letter'),('efi-stroke-tia',1,'9Om3.',NULL,'Stroke/TIA monitor verb invit'),('efi-stroke-tia',1,'9Om3.00',NULL,'Stroke/TIA monitor verb invit'),('efi-stroke-tia',1,'9Om4.',NULL,'Stroke/TIA monitr phone invite'),('efi-stroke-tia',1,'9Om4.00',NULL,'Stroke/TIA monitr phone invite'),('efi-stroke-tia',1,'9h21.',NULL,'Except stroke qual ind: Pt uns'),('efi-stroke-tia',1,'9h21.00',NULL,'Except stroke qual ind: Pt uns'),('efi-stroke-tia',1,'9h22.',NULL,'Exc stroke qual ind: Infor dis'),('efi-stroke-tia',1,'9h22.00',NULL,'Exc stroke qual ind: Infor dis'),('efi-stroke-tia',1,'F4236',NULL,'Amaurosis fugax'),('efi-stroke-tia',1,'F423600',NULL,'Amaurosis fugax'),('efi-stroke-tia',1,'G6...',NULL,'Cerebrovascular disease'),('efi-stroke-tia',1,'G6...00',NULL,'Cerebrovascular disease'),('efi-stroke-tia',1,'G61..',NULL,'Intracerebral haemorrhage'),('efi-stroke-tia',1,'G61..00',NULL,'Intracerebral haemorrhage'),('efi-stroke-tia',1,'G621.',NULL,'Subdural haemorrhage-nontraum.'),('efi-stroke-tia',1,'G621.00',NULL,'Subdural haemorrhage-nontraum.'),('efi-stroke-tia',1,'G622.',NULL,'Subdural haematoma - nontraum'),('efi-stroke-tia',1,'G622.00',NULL,'Subdural haematoma - nontraum'),('efi-stroke-tia',1,'G631.',NULL,'Carotid artery occlusion'),('efi-stroke-tia',1,'G631.00',NULL,'Carotid artery occlusion'),('efi-stroke-tia',1,'G634.',NULL,'Carotid artery stenosis'),('efi-stroke-tia',1,'G634.00',NULL,'Carotid artery stenosis'),('efi-stroke-tia',1,'G64..',NULL,'Cerebral arterial occlusion'),('efi-stroke-tia',1,'G64..00',NULL,'Cerebral arterial occlusion'),('efi-stroke-tia',1,'G640.',NULL,'Cerebral thrombosis'),('efi-stroke-tia',1,'G640.00',NULL,'Cerebral thrombosis'),('efi-stroke-tia',1,'G65..',NULL,'Transient cerebral ischaemia'),('efi-stroke-tia',1,'G65..00',NULL,'Transient cerebral ischaemia'),('efi-stroke-tia',1,'G65y.',NULL,'Other transient cerebral isch.'),('efi-stroke-tia',1,'G65y.00',NULL,'Other transient cerebral isch.'),('efi-stroke-tia',1,'G65z.',NULL,'Transient cerebral ischaem.NOS'),('efi-stroke-tia',1,'G65z.00',NULL,'Transient cerebral ischaem.NOS'),('efi-stroke-tia',1,'G65z1',NULL,'Intermittent CVA'),('efi-stroke-tia',1,'G65z100',NULL,'Intermittent CVA'),('efi-stroke-tia',1,'G65zz',NULL,'Transient cerebral ischaem.NOS'),('efi-stroke-tia',1,'G65zz00',NULL,'Transient cerebral ischaem.NOS'),('efi-stroke-tia',1,'G66..',NULL,'Stroke/CVA unspecified'),('efi-stroke-tia',1,'G66..00',NULL,'Stroke/CVA unspecified'),('efi-stroke-tia',1,'G663.',NULL,'Brain stem stroke syndrome'),('efi-stroke-tia',1,'G663.00',NULL,'Brain stem stroke syndrome'),('efi-stroke-tia',1,'G664.',NULL,'Cerebellar stroke syndrome'),('efi-stroke-tia',1,'G664.00',NULL,'Cerebellar stroke syndrome'),('efi-stroke-tia',1,'G667.',NULL,'Left sided CVA'),('efi-stroke-tia',1,'G667.00',NULL,'Left sided CVA'),('efi-stroke-tia',1,'G670.',NULL,'Cerebral atherosclerosis'),('efi-stroke-tia',1,'G670.00',NULL,'Cerebral atherosclerosis'),('efi-stroke-tia',1,'G6711',NULL,'Chronic cerebral ischaemia'),('efi-stroke-tia',1,'G671100',NULL,'Chronic cerebral ischaemia'),('efi-stroke-tia',1,'G682.',NULL,'Seq/oth nontraum intrcran haem'),('efi-stroke-tia',1,'G682.00',NULL,'Seq/oth nontraum intrcran haem'),('efi-stroke-tia',1,'G68X.',NULL,'Seql/strok,n spc/hm,infarc'),('efi-stroke-tia',1,'G68X.00',NULL,'Seql/strok,n spc/hm,infarc'),('efi-stroke-tia',1,'Gyu6.',NULL,'[X]Cerebrovascular diseases'),('efi-stroke-tia',1,'Gyu6.00',NULL,'[X]Cerebrovascular diseases'),('efi-stroke-tia',1,'Gyu6B',NULL,'[X]Seql/o n-traum intracrn hm'),('efi-stroke-tia',1,'Gyu6B00',NULL,'[X]Seql/o n-traum intracrn hm'),('efi-stroke-tia',1,'Gyu6C',NULL,'[X]Seql/strok,n spc/hm,infarc'),('efi-stroke-tia',1,'Gyu6C00',NULL,'[X]Seql/strok,n spc/hm,infarc'),('efi-stroke-tia',1,'S62..',NULL,'Cerebral haemge after injury'),('efi-stroke-tia',1,'S62..00',NULL,'Cerebral haemge after injury'),('efi-stroke-tia',1,'S620.',NULL,'Cls trm subarach haemorrhage'),('efi-stroke-tia',1,'S620.00',NULL,'Cls trm subarach haemorrhage'),('efi-stroke-tia',1,'S622.',NULL,'Cls trm subdural haemorrhage'),('efi-stroke-tia',1,'S622.00',NULL,'Cls trm subdural haemorrhage'),('efi-stroke-tia',1,'S627.',NULL,'Traum subarachnoid haemorrhage'),('efi-stroke-tia',1,'S627.00',NULL,'Traum subarachnoid haemorrhage'),('efi-stroke-tia',1,'S628.',NULL,'Traumatic subdural haemorrhage'),('efi-stroke-tia',1,'S628.00',NULL,'Traumatic subdural haemorrhage'),('efi-stroke-tia',1,'S629.',NULL,'Traumatic subdural haematoma'),('efi-stroke-tia',1,'S629.00',NULL,'Traumatic subdural haematoma'),('efi-stroke-tia',1,'S6290',NULL,'Trau subdl hae witht op int wo'),('efi-stroke-tia',1,'S629000',NULL,'Trau subdl hae witht op int wo');
INSERT INTO #codesreadv2
VALUES ('efi-thyroid-disorders',1,'1431.',NULL,'H/O: hyperthyroidism'),('efi-thyroid-disorders',1,'1431.00',NULL,'H/O: hyperthyroidism'),('efi-thyroid-disorders',1,'1432.',NULL,'H/O: hypothyroidism'),('efi-thyroid-disorders',1,'1432.00',NULL,'H/O: hypothyroidism'),('efi-thyroid-disorders',1,'4422.',NULL,'Thyroid hormone tests high'),('efi-thyroid-disorders',1,'4422.00',NULL,'Thyroid hormone tests high'),('efi-thyroid-disorders',1,'442I.',NULL,'Thyroid functn tests abnormal'),('efi-thyroid-disorders',1,'442I.00',NULL,'Thyroid functn tests abnormal'),('efi-thyroid-disorders',1,'66BB.',NULL,'Hypothyroidism annual review'),('efi-thyroid-disorders',1,'66BB.00',NULL,'Hypothyroidism annual review'),('efi-thyroid-disorders',1,'66BZ.',NULL,'Thyroid disease monitoring NOS'),('efi-thyroid-disorders',1,'66BZ.00',NULL,'Thyroid disease monitoring NOS'),('efi-thyroid-disorders',1,'8CR5.',NULL,'Hypothyroidism clin man plan'),('efi-thyroid-disorders',1,'8CR5.00',NULL,'Hypothyroidism clin man plan'),('efi-thyroid-disorders',1,'9N4T.',NULL,'DNA hyperthyroidism clinic'),('efi-thyroid-disorders',1,'9N4T.00',NULL,'DNA hyperthyroidism clinic'),('efi-thyroid-disorders',1,'9Oj0.',NULL,'Hypothyroidism monit 1st lett'),('efi-thyroid-disorders',1,'9Oj0.00',NULL,'Hypothyroidism monit 1st lett'),('efi-thyroid-disorders',1,'C0...',NULL,'Disorders of thyroid gland'),('efi-thyroid-disorders',1,'C0...00',NULL,'Disorders of thyroid gland'),('efi-thyroid-disorders',1,'C02..',NULL,'Thyrotoxicosis'),('efi-thyroid-disorders',1,'C02..00',NULL,'Thyrotoxicosis'),('efi-thyroid-disorders',1,'C04..',NULL,'Acquired hypothyroidism'),('efi-thyroid-disorders',1,'C04..00',NULL,'Acquired hypothyroidism'),('efi-thyroid-disorders',1,'C040.',NULL,'Postsurgical hypothyroidism'),('efi-thyroid-disorders',1,'C040.00',NULL,'Postsurgical hypothyroidism'),('efi-thyroid-disorders',1,'C041.',NULL,'Other postablative hypothyroid'),('efi-thyroid-disorders',1,'C041.00',NULL,'Other postablative hypothyroid'),('efi-thyroid-disorders',1,'C0410',NULL,'Irradiation hypothyroidism'),('efi-thyroid-disorders',1,'C041000',NULL,'Irradiation hypothyroidism'),('efi-thyroid-disorders',1,'C041z',NULL,'Postablative hypothyroid. NOS'),('efi-thyroid-disorders',1,'C041z00',NULL,'Postablative hypothyroid. NOS'),('efi-thyroid-disorders',1,'C042.',NULL,'Iodine hypothyroidism'),('efi-thyroid-disorders',1,'C042.00',NULL,'Iodine hypothyroidism'),('efi-thyroid-disorders',1,'C043.',NULL,'Other iatrogenic hypothyroid.'),('efi-thyroid-disorders',1,'C043.00',NULL,'Other iatrogenic hypothyroid.'),('efi-thyroid-disorders',1,'C043z',NULL,'Iatrogenic hypothyroidism NOS'),('efi-thyroid-disorders',1,'C043z00',NULL,'Iatrogenic hypothyroidism NOS'),('efi-thyroid-disorders',1,'C044.',NULL,'Postinfectious hypothyroidism'),('efi-thyroid-disorders',1,'C044.00',NULL,'Postinfectious hypothyroidism'),('efi-thyroid-disorders',1,'C046.',NULL,'Autoimmune myxoedema'),('efi-thyroid-disorders',1,'C046.00',NULL,'Autoimmune myxoedema'),('efi-thyroid-disorders',1,'C04y.',NULL,'Other acquired hypothyroidism'),('efi-thyroid-disorders',1,'C04y.00',NULL,'Other acquired hypothyroidism'),('efi-thyroid-disorders',1,'C04z.',NULL,'Hypothyroidism NOS'),('efi-thyroid-disorders',1,'C04z.00',NULL,'Hypothyroidism NOS'),('efi-thyroid-disorders',1,'C1343',NULL,'TSH deficiency'),('efi-thyroid-disorders',1,'C134300',NULL,'TSH deficiency'),('efi-thyroid-disorders',1,'Cyu1.',NULL,'[X]Disorders of thyroid gland'),('efi-thyroid-disorders',1,'Cyu1.00',NULL,'[X]Disorders of thyroid gland'),('efi-thyroid-disorders',1,'Cyu11',NULL,'[X]Other specfd hypothyroidism'),('efi-thyroid-disorders',1,'Cyu1100',NULL,'[X]Other specfd hypothyroidism');
INSERT INTO #codesreadv2
VALUES ('efi-urinary-system-disease',1,'14D..',NULL,'H/O: urinary disease'),('efi-urinary-system-disease',1,'14D..00',NULL,'H/O: urinary disease'),('efi-urinary-system-disease',1,'14DZ.',NULL,'H/O: urinary disease NOS'),('efi-urinary-system-disease',1,'14DZ.00',NULL,'H/O: urinary disease NOS'),('efi-urinary-system-disease',1,'1A1..',NULL,'Micturition frequency'),('efi-urinary-system-disease',1,'1A1..00',NULL,'Micturition frequency'),('efi-urinary-system-disease',1,'1A13.',NULL,'Nocturia'),('efi-urinary-system-disease',1,'1A13.00',NULL,'Nocturia'),('efi-urinary-system-disease',1,'1A1Z.',NULL,'Micturition frequency NOS'),('efi-urinary-system-disease',1,'1A1Z.00',NULL,'Micturition frequency NOS'),('efi-urinary-system-disease',1,'1A55.',NULL,'Dysuria'),('efi-urinary-system-disease',1,'1A55.00',NULL,'Dysuria'),('efi-urinary-system-disease',1,'1AA..',NULL,'Prostatism'),('efi-urinary-system-disease',1,'1AA..00',NULL,'Prostatism'),('efi-urinary-system-disease',1,'1AC2.',NULL,'Polyuria'),('efi-urinary-system-disease',1,'1AC2.00',NULL,'Polyuria'),('efi-urinary-system-disease',1,'7B39.',NULL,'Endos prostatec/male blad outl'),('efi-urinary-system-disease',1,'7B39.00',NULL,'Endos prostatec/male blad outl'),('efi-urinary-system-disease',1,'7B390',NULL,'TUR prostatectomy'),('efi-urinary-system-disease',1,'7B39000',NULL,'TUR prostatectomy'),('efi-urinary-system-disease',1,'8156.',NULL,'Attention to urinary catheter'),('efi-urinary-system-disease',1,'8156.00',NULL,'Attention to urinary catheter'),('efi-urinary-system-disease',1,'8H5B.',NULL,'Referred to urologist'),('efi-urinary-system-disease',1,'8H5B.00',NULL,'Referred to urologist'),('efi-urinary-system-disease',1,'K....',NULL,'Genitourinary system diseases'),('efi-urinary-system-disease',1,'K....00',NULL,'Genitourinary system diseases'),('efi-urinary-system-disease',1,'K155.',NULL,'Recurrent cystitis'),('efi-urinary-system-disease',1,'K155.00',NULL,'Recurrent cystitis'),('efi-urinary-system-disease',1,'K1653',NULL,'Detrusor instability'),('efi-urinary-system-disease',1,'K165300',NULL,'Detrusor instability'),('efi-urinary-system-disease',1,'K1654',NULL,'Unstable bladder'),('efi-urinary-system-disease',1,'K165400',NULL,'Unstable bladder'),('efi-urinary-system-disease',1,'K16y4',NULL,'Irritable bladder'),('efi-urinary-system-disease',1,'K16y400',NULL,'Irritable bladder'),('efi-urinary-system-disease',1,'K190.',NULL,'Urinary tract infect.unsp.site'),('efi-urinary-system-disease',1,'K190.00',NULL,'Urinary tract infect.unsp.site'),('efi-urinary-system-disease',1,'K1903',NULL,'Recurrent urinary tract infecn'),('efi-urinary-system-disease',1,'K190300',NULL,'Recurrent urinary tract infecn'),('efi-urinary-system-disease',1,'K1905',NULL,'Urinary tract infection'),('efi-urinary-system-disease',1,'K190500',NULL,'Urinary tract infection'),('efi-urinary-system-disease',1,'K190z',NULL,'Urinary tract infect.unsp.NOS'),('efi-urinary-system-disease',1,'K190z00',NULL,'Urinary tract infect.unsp.NOS'),('efi-urinary-system-disease',1,'K1971',NULL,'Painful haematuria'),('efi-urinary-system-disease',1,'K197100',NULL,'Painful haematuria'),('efi-urinary-system-disease',1,'K1973',NULL,'Frank haematuria'),('efi-urinary-system-disease',1,'K197300',NULL,'Frank haematuria'),('efi-urinary-system-disease',1,'K20..',NULL,'Benign prostatic hypertrophy'),('efi-urinary-system-disease',1,'K20..00',NULL,'Benign prostatic hypertrophy'),('efi-urinary-system-disease',1,'Ky...',NULL,'Genitourinary diseases OS'),('efi-urinary-system-disease',1,'Ky...00',NULL,'Genitourinary diseases OS'),('efi-urinary-system-disease',1,'Kz...',NULL,'Genitourinary disease NOS'),('efi-urinary-system-disease',1,'Kz...00',NULL,'Genitourinary disease NOS'),('efi-urinary-system-disease',1,'R08..',NULL,'[D]Urinary system symptoms'),('efi-urinary-system-disease',1,'R08..00',NULL,'[D]Urinary system symptoms'),('efi-urinary-system-disease',1,'R082.',NULL,'[D]Retention of urine'),('efi-urinary-system-disease',1,'R082.00',NULL,'[D]Retention of urine'),('efi-urinary-system-disease',1,'R0822',NULL,'[D]Acute retention of urine'),('efi-urinary-system-disease',1,'R082200',NULL,'[D]Acute retention of urine'),('efi-urinary-system-disease',1,'SP031',NULL,'Mech.comp.-urethral catheter'),('efi-urinary-system-disease',1,'SP03100',NULL,'Mech.comp.-urethral catheter');
INSERT INTO #codesreadv2
VALUES ('efi-vision-problems',1,'72630',NULL,'Simple linear extraction lens'),('efi-vision-problems',1,'7263000',NULL,'Simple linear extraction lens'),('efi-vision-problems',1,'72661',NULL,'Discission of cataract'),('efi-vision-problems',1,'7266100',NULL,'Discission of cataract'),('efi-vision-problems',1,'1483.',NULL,'H/O: cataract'),('efi-vision-problems',1,'1483.00',NULL,'H/O: cataract'),('efi-vision-problems',1,'1B75.',NULL,'Loss of vision'),('efi-vision-problems',1,'1B75.00',NULL,'Loss of vision'),('efi-vision-problems',1,'22E5.',NULL,'O/E - cataract present'),('efi-vision-problems',1,'22E5.00',NULL,'O/E - cataract present'),('efi-vision-problems',1,'22EG.',NULL,'Wears glasses'),('efi-vision-problems',1,'22EG.00',NULL,'Wears glasses'),('efi-vision-problems',1,'2BBm.',NULL,'O/E - R clin sig macula oedema'),('efi-vision-problems',1,'2BBm.00',NULL,'O/E - R clin sig macula oedema'),('efi-vision-problems',1,'2BBn.',NULL,'O/E - L clin sig macula oedema'),('efi-vision-problems',1,'2BBn.00',NULL,'O/E - L clin sig macula oedema'),('efi-vision-problems',1,'2BBo.',NULL,'O/E - sight threat diab retin'),('efi-vision-problems',1,'2BBo.00',NULL,'O/E - sight threat diab retin'),('efi-vision-problems',1,'2BBr.',NULL,'Impair vision due diab retinop'),('efi-vision-problems',1,'2BBr.00',NULL,'Impair vision due diab retinop'),('efi-vision-problems',1,'2BT..',NULL,'Cataract observation'),('efi-vision-problems',1,'2BT..00',NULL,'Cataract observation'),('efi-vision-problems',1,'2BT0.',NULL,'O/E - Right cataract present'),('efi-vision-problems',1,'2BT0.00',NULL,'O/E - Right cataract present'),('efi-vision-problems',1,'2BT1.',NULL,'O/E - Left cataract present'),('efi-vision-problems',1,'2BT1.00',NULL,'O/E - Left cataract present'),('efi-vision-problems',1,'6688.',NULL,'Registered partially sighted'),('efi-vision-problems',1,'6688.00',NULL,'Registered partially sighted'),('efi-vision-problems',1,'6689.',NULL,'Registered blind'),('efi-vision-problems',1,'6689.00',NULL,'Registered blind'),('efi-vision-problems',1,'8F61.',NULL,'Blind rehabilitation'),('efi-vision-problems',1,'8F61.00',NULL,'Blind rehabilitation'),('efi-vision-problems',1,'8H52.',NULL,'Ophthalmological referral'),('efi-vision-problems',1,'8H52.00',NULL,'Ophthalmological referral'),('efi-vision-problems',1,'9m08.',NULL,'Exclu diab ret screen as blind'),('efi-vision-problems',1,'9m08.00',NULL,'Exclu diab ret screen as blind'),('efi-vision-problems',1,'C108F',NULL,'IDDM with diabetic cataract'),('efi-vision-problems',1,'C108F00',NULL,'IDDM with diabetic cataract'),('efi-vision-problems',1,'C109E',NULL,'NIDDM with diabetic cataract'),('efi-vision-problems',1,'C109E00',NULL,'NIDDM with diabetic cataract'),('efi-vision-problems',1,'C10EF',NULL,'Type 1 diab mell + diab catar'),('efi-vision-problems',1,'C10EF00',NULL,'Type 1 diab mell + diab catar'),('efi-vision-problems',1,'C10EP',NULL,'Type 1 d m + exudat maculopath'),('efi-vision-problems',1,'C10EP00',NULL,'Type 1 d m + exudat maculopath'),('efi-vision-problems',1,'C10FE',NULL,'Type 2 diab mell+diab catarct'),('efi-vision-problems',1,'C10FE00',NULL,'Type 2 diab mell+diab catarct'),('efi-vision-problems',1,'C10FQ',NULL,'Type 2 d m + exudat maculopath'),('efi-vision-problems',1,'C10FQ00',NULL,'Type 2 d m + exudat maculopath'),('efi-vision-problems',1,'F4042',NULL,'Blind hypertensive eye'),('efi-vision-problems',1,'F404200',NULL,'Blind hypertensive eye'),('efi-vision-problems',1,'F421A',NULL,'Retinal neovascularization NOS'),('efi-vision-problems',1,'F421A00',NULL,'Retinal neovascularization NOS'),('efi-vision-problems',1,'F422.',NULL,'Other proliferative retinopath'),('efi-vision-problems',1,'F422.00',NULL,'Other proliferative retinopath'),('efi-vision-problems',1,'F422y',NULL,'Other proliferat.retinop.OS'),('efi-vision-problems',1,'F422y00',NULL,'Other proliferat.retinop.OS'),('efi-vision-problems',1,'F422z',NULL,'Proliferative retinopathy NOS'),('efi-vision-problems',1,'F422z00',NULL,'Proliferative retinopathy NOS'),('efi-vision-problems',1,'F4239',NULL,'Retinal venous branch occlus.'),('efi-vision-problems',1,'F423900',NULL,'Retinal venous branch occlus.'),('efi-vision-problems',1,'F425.',NULL,'Macula/posterior pole degen.'),('efi-vision-problems',1,'F425.00',NULL,'Macula/posterior pole degen.'),('efi-vision-problems',1,'F4250',NULL,'Senile macular degen.unspecif.'),('efi-vision-problems',1,'F425000',NULL,'Senile macular degen.unspecif.'),('efi-vision-problems',1,'F4251',NULL,'Dry senile macular degenerat.'),('efi-vision-problems',1,'F425100',NULL,'Dry senile macular degenerat.'),('efi-vision-problems',1,'F4252',NULL,'Wet senile macular degenerat.'),('efi-vision-problems',1,'F425200',NULL,'Wet senile macular degenerat.'),('efi-vision-problems',1,'F4253',NULL,'Cystoid macular degeneration'),('efi-vision-problems',1,'F425300',NULL,'Cystoid macular degeneration'),('efi-vision-problems',1,'F4254',NULL,'Macular cyst/hole/pseudohole'),('efi-vision-problems',1,'F425400',NULL,'Macular cyst/hole/pseudohole'),('efi-vision-problems',1,'F4257',NULL,'Drusen'),('efi-vision-problems',1,'F425700',NULL,'Drusen'),('efi-vision-problems',1,'F427C',NULL,'Vitelliform dystrophy'),('efi-vision-problems',1,'F427C00',NULL,'Vitelliform dystrophy'),('efi-vision-problems',1,'F42y4',NULL,'Subretinal haemorrhage'),('efi-vision-problems',1,'F42y400',NULL,'Subretinal haemorrhage'),('efi-vision-problems',1,'F42y9',NULL,'Macular oedema'),('efi-vision-problems',1,'F42y900',NULL,'Macular oedema'),('efi-vision-problems',1,'F4305',NULL,'Focal macular retinochoroidit.'),('efi-vision-problems',1,'F430500',NULL,'Focal macular retinochoroidit.'),('efi-vision-problems',1,'F4332',NULL,'Other macular scars'),('efi-vision-problems',1,'F433200',NULL,'Other macular scars'),('efi-vision-problems',1,'F46..',NULL,'Cataract'),('efi-vision-problems',1,'F46..00',NULL,'Cataract'),('efi-vision-problems',1,'F4602',NULL,'Presenile cataract unspecified'),('efi-vision-problems',1,'F460200',NULL,'Presenile cataract unspecified'),('efi-vision-problems',1,'F4603',NULL,'Ant.subcapsular polar cataract'),('efi-vision-problems',1,'F460300',NULL,'Ant.subcapsular polar cataract'),('efi-vision-problems',1,'F4604',NULL,'Post.subcapsul. polar cataract'),('efi-vision-problems',1,'F460400',NULL,'Post.subcapsul. polar cataract'),('efi-vision-problems',1,'F4605',NULL,'Cortical cataract'),('efi-vision-problems',1,'F460500',NULL,'Cortical cataract'),('efi-vision-problems',1,'F4606',NULL,'Lamellar zonular cataract'),('efi-vision-problems',1,'F460600',NULL,'Lamellar zonular cataract'),('efi-vision-problems',1,'F4607',NULL,'Nuclear cataract'),('efi-vision-problems',1,'F460700',NULL,'Nuclear cataract'),('efi-vision-problems',1,'F460z',NULL,'Nonsenile cataract NOS'),('efi-vision-problems',1,'F460z00',NULL,'Nonsenile cataract NOS'),('efi-vision-problems',1,'F461.',NULL,'Senile cataract'),('efi-vision-problems',1,'F461.00',NULL,'Senile cataract'),('efi-vision-problems',1,'F4610',NULL,'Senile cataract unspecified'),('efi-vision-problems',1,'F461000',NULL,'Senile cataract unspecified'),('efi-vision-problems',1,'F4614',NULL,'Incipient cataract NOS'),('efi-vision-problems',1,'F461400',NULL,'Incipient cataract NOS'),('efi-vision-problems',1,'F4615',NULL,'Immature cataract NOS'),('efi-vision-problems',1,'F461500',NULL,'Immature cataract NOS'),('efi-vision-problems',1,'F4617',NULL,'Post.subcap.polar sen.cataract'),('efi-vision-problems',1,'F461700',NULL,'Post.subcap.polar sen.cataract'),('efi-vision-problems',1,'F4618',NULL,'Cortical senile cataract'),('efi-vision-problems',1,'F461800',NULL,'Cortical senile cataract'),('efi-vision-problems',1,'F4619',NULL,'Nuclear senile cataract'),('efi-vision-problems',1,'F461900',NULL,'Nuclear senile cataract'),('efi-vision-problems',1,'F461A',NULL,'Total, mature senile cataract'),('efi-vision-problems',1,'F461A00',NULL,'Total, mature senile cataract'),('efi-vision-problems',1,'F461B',NULL,'Hypermature cataract'),('efi-vision-problems',1,'F461B00',NULL,'Hypermature cataract'),('efi-vision-problems',1,'F461y',NULL,'Other senile cataract'),('efi-vision-problems',1,'F461y00',NULL,'Other senile cataract'),('efi-vision-problems',1,'F461z',NULL,'Senile cataract NOS'),('efi-vision-problems',1,'F461z00',NULL,'Senile cataract NOS'),('efi-vision-problems',1,'F462.',NULL,'Traumatic cataract'),('efi-vision-problems',1,'F462.00',NULL,'Traumatic cataract'),('efi-vision-problems',1,'F462z',NULL,'Traumatic cataract NOS'),('efi-vision-problems',1,'F462z00',NULL,'Traumatic cataract NOS'),('efi-vision-problems',1,'F463.',NULL,'Cataract secondary ocular dis.'),('efi-vision-problems',1,'F463.00',NULL,'Cataract secondary ocular dis.'),('efi-vision-problems',1,'F4633',NULL,'Cataract with neovascularizat.'),('efi-vision-problems',1,'F463300',NULL,'Cataract with neovascularizat.'),('efi-vision-problems',1,'F4634',NULL,'Cataract in degenerat.disord.'),('efi-vision-problems',1,'F463400',NULL,'Cataract in degenerat.disord.'),('efi-vision-problems',1,'F463z',NULL,'Cataract due to ocular dis NOS'),('efi-vision-problems',1,'F463z00',NULL,'Cataract due to ocular dis NOS'),('efi-vision-problems',1,'F464.',NULL,'Cataract due to other disorder'),('efi-vision-problems',1,'F464.00',NULL,'Cataract due to other disorder'),('efi-vision-problems',1,'F4640',NULL,'Diabetic cataract'),('efi-vision-problems',1,'F464000',NULL,'Diabetic cataract'),('efi-vision-problems',1,'F4642',NULL,'Myotonic cataract'),('efi-vision-problems',1,'F464200',NULL,'Myotonic cataract'),('efi-vision-problems',1,'F4644',NULL,'Drug induced cataract'),('efi-vision-problems',1,'F464400',NULL,'Drug induced cataract'),('efi-vision-problems',1,'F4646',NULL,'Radiation induced cataract'),('efi-vision-problems',1,'F464600',NULL,'Radiation induced cataract'),('efi-vision-problems',1,'F4647',NULL,'Other physical infl. cataract'),('efi-vision-problems',1,'F464700',NULL,'Other physical infl. cataract'),('efi-vision-problems',1,'F464z',NULL,'Cataract + other disorder NOS'),
('efi-vision-problems',1,'F464z00',NULL,'Cataract + other disorder NOS'),('efi-vision-problems',1,'F465.',NULL,'After cataract'),('efi-vision-problems',1,'F465.00',NULL,'After cataract'),('efi-vision-problems',1,'F4650',NULL,'Secondary cataract unspecified'),('efi-vision-problems',1,'F465000',NULL,'Secondary cataract unspecified'),('efi-vision-problems',1,'F465z',NULL,'After cataract NOS'),('efi-vision-problems',1,'F465z00',NULL,'After cataract NOS'),('efi-vision-problems',1,'F466.',NULL,'Bilateral cataracts'),('efi-vision-problems',1,'F466.00',NULL,'Bilateral cataracts'),('efi-vision-problems',1,'F46y.',NULL,'Other cataract'),('efi-vision-problems',1,'F46y.00',NULL,'Other cataract'),('efi-vision-problems',1,'F46yz',NULL,'Other cataract NOS'),('efi-vision-problems',1,'F46yz00',NULL,'Other cataract NOS'),('efi-vision-problems',1,'F46z.',NULL,'Cataract NOS'),('efi-vision-problems',1,'F46z.00',NULL,'Cataract NOS'),('efi-vision-problems',1,'F46z0',NULL,'Immature cortical cataract'),('efi-vision-problems',1,'F46z000',NULL,'Immature cortical cataract'),('efi-vision-problems',1,'F4840',NULL,'Visual field defect, unspecif.'),('efi-vision-problems',1,'F484000',NULL,'Visual field defect, unspecif.'),('efi-vision-problems',1,'F49..',NULL,'Blindness and low vision'),('efi-vision-problems',1,'F49..00',NULL,'Blindness and low vision'),('efi-vision-problems',1,'F490.',NULL,'Blindness, both eyes'),('efi-vision-problems',1,'F490.00',NULL,'Blindness, both eyes'),('efi-vision-problems',1,'F4900',NULL,'Blindness both eyes unspecif.'),('efi-vision-problems',1,'F490000',NULL,'Blindness both eyes unspecif.'),('efi-vision-problems',1,'F4909',NULL,'Acquired blindness, both eyes'),('efi-vision-problems',1,'F490900',NULL,'Acquired blindness, both eyes'),('efi-vision-problems',1,'F490z',NULL,'Blindness both eyes NOS'),('efi-vision-problems',1,'F490z00',NULL,'Blindness both eyes NOS'),('efi-vision-problems',1,'F494.',NULL,'Legal blindness USA'),('efi-vision-problems',1,'F494.00',NULL,'Legal blindness USA'),('efi-vision-problems',1,'F4950',NULL,'Blindness,one eye, unspecified'),('efi-vision-problems',1,'F495000',NULL,'Blindness,one eye, unspecified'),('efi-vision-problems',1,'F495A',NULL,'Acquired blindness, one eye'),('efi-vision-problems',1,'F495A00',NULL,'Acquired blindness, one eye'),('efi-vision-problems',1,'F49z.',NULL,'Visual loss NOS'),('efi-vision-problems',1,'F49z.00',NULL,'Visual loss NOS'),('efi-vision-problems',1,'F4A24',NULL,'Macular keratitis NOS'),('efi-vision-problems',1,'F4A2400',NULL,'Macular keratitis NOS'),('efi-vision-problems',1,'F4H34',NULL,'Toxic optic neuropathy'),('efi-vision-problems',1,'F4H3400',NULL,'Toxic optic neuropathy'),('efi-vision-problems',1,'F4H40',NULL,'Ischaemic optic neuropathy'),('efi-vision-problems',1,'F4H4000',NULL,'Ischaemic optic neuropathy'),('efi-vision-problems',1,'F4H73',NULL,'Cortical blindness'),('efi-vision-problems',1,'F4H7300',NULL,'Cortical blindness'),('efi-vision-problems',1,'F4K2D',NULL,'Vitreous syn fol cataract surg'),('efi-vision-problems',1,'F4K2D00',NULL,'Vitreous syn fol cataract surg'),('efi-vision-problems',1,'FyuE1',NULL,'[X]Other specified cataract'),('efi-vision-problems',1,'FyuE100',NULL,'[X]Other specified cataract'),('efi-vision-problems',1,'FyuF7',NULL,'[X]Oth proliferativ retinopthy'),('efi-vision-problems',1,'FyuF700',NULL,'[X]Oth proliferativ retinopthy'),('efi-vision-problems',1,'FyuL.',NULL,'[X]Visual disturbanc+blindness'),('efi-vision-problems',1,'FyuL.00',NULL,'[X]Visual disturbanc+blindness'),('efi-vision-problems',1,'P33..',NULL,'Congenital cataract/lens anom.'),('efi-vision-problems',1,'P33..00',NULL,'Congenital cataract/lens anom.'),('efi-vision-problems',1,'P330.',NULL,'Congenital cataract unspecif.'),('efi-vision-problems',1,'P330.00',NULL,'Congenital cataract unspecif.'),('efi-vision-problems',1,'P331.',NULL,'Capsular/subcapsular cataract'),('efi-vision-problems',1,'P331.00',NULL,'Capsular/subcapsular cataract'),('efi-vision-problems',1,'P3310',NULL,'Capsular cataract'),('efi-vision-problems',1,'P331000',NULL,'Capsular cataract'),('efi-vision-problems',1,'P3311',NULL,'Subcapsular cataract'),('efi-vision-problems',1,'P331100',NULL,'Subcapsular cataract'),('efi-vision-problems',1,'P331z',NULL,'Capsular/subcaps.cataract NOS'),('efi-vision-problems',1,'P331z00',NULL,'Capsular/subcaps.cataract NOS'),('efi-vision-problems',1,'S813.',NULL,'Avulsion of eye'),('efi-vision-problems',1,'S813.00',NULL,'Avulsion of eye'),('efi-vision-problems',1,'SJ0z.',NULL,'Optic nerve/pathway inj. NOS'),('efi-vision-problems',1,'SJ0z.00',NULL,'Optic nerve/pathway inj. NOS');
INSERT INTO #codesreadv2
VALUES ('efi-activity-limitation',1,'13O5.',NULL,'Attendance allowance'),('efi-activity-limitation',1,'13O5.00',NULL,'Attendance allowance'),('efi-activity-limitation',1,'13V8.',NULL,'Has disabled driver badge'),('efi-activity-limitation',1,'13V8.00',NULL,'Has disabled driver badge'),('efi-activity-limitation',1,'13VC.',NULL,'Disability'),('efi-activity-limitation',1,'13VC.00',NULL,'Disability'),('efi-activity-limitation',1,'8F6..',NULL,'Specific disability rehab.'),('efi-activity-limitation',1,'8F6..00',NULL,'Specific disability rehab.'),('efi-activity-limitation',1,'9EB5.',NULL,'Form DS1500 completed'),('efi-activity-limitation',1,'9EB5.00',NULL,'Form DS1500 completed');
INSERT INTO #codesreadv2
VALUES ('efi-anaemia',1,'145..',NULL,'H/O: blood disorder'),('efi-anaemia',1,'145..00',NULL,'H/O: blood disorder'),('efi-anaemia',1,'1451.',NULL,'H/O: anaemia - iron deficient'),('efi-anaemia',1,'1451.00',NULL,'H/O: anaemia - iron deficient'),('efi-anaemia',1,'1452.',NULL,'H/O: Anaemia vit.B12 deficient'),('efi-anaemia',1,'1452.00',NULL,'H/O: Anaemia vit.B12 deficient'),('efi-anaemia',1,'1453.',NULL,'H/O: haemolytic anaemia'),('efi-anaemia',1,'1453.00',NULL,'H/O: haemolytic anaemia'),('efi-anaemia',1,'1454.',NULL,'H/O: anaemia NOS'),('efi-anaemia',1,'1454.00',NULL,'H/O: anaemia NOS'),('efi-anaemia',1,'2C23.',NULL,'O/E - clinically anaemic'),('efi-anaemia',1,'2C23.00',NULL,'O/E - clinically anaemic'),('efi-anaemia',1,'42R41',NULL,'Ferritin level low'),('efi-anaemia',1,'42R4100',NULL,'Ferritin level low'),('efi-anaemia',1,'42T2.',NULL,'Serum vitamin B12 low'),('efi-anaemia',1,'42T2.00',NULL,'Serum vitamin B12 low'),('efi-anaemia',1,'66E5.',NULL,'B12 injections - at surgery'),('efi-anaemia',1,'66E5.00',NULL,'B12 injections - at surgery'),('efi-anaemia',1,'7Q090',NULL,'Hypop hae ren anae drug Band 1'),('efi-anaemia',1,'7Q09000',NULL,'Hypop hae ren anae drug Band 1'),('efi-anaemia',1,'7Q091',NULL,'Hypopl hae ren ana drug Band 2'),('efi-anaemia',1,'7Q09100',NULL,'Hypopl hae ren ana drug Band 2'),('efi-anaemia',1,'B9370',NULL,'Ref anaem,no siderobl,so state'),('efi-anaemia',1,'B937000',NULL,'Ref anaem,no siderobl,so state'),('efi-anaemia',1,'B9371',NULL,'Refr anaemia with sideroblasts'),('efi-anaemia',1,'B937100',NULL,'Refr anaemia with sideroblasts'),('efi-anaemia',1,'B9372',NULL,'Refr anaem with excess blasts'),('efi-anaemia',1,'B937200',NULL,'Refr anaem with excess blasts'),('efi-anaemia',1,'B9373',NULL,'Ref anaem+exc blast with trnsf'),('efi-anaemia',1,'B937300',NULL,'Ref anaem+exc blast with trnsf'),('efi-anaemia',1,'B937X',NULL,'Refractory anaemia,unspecif'),('efi-anaemia',1,'B937X00',NULL,'Refractory anaemia,unspecif'),('efi-anaemia',1,'BBmA.',NULL,'[M]Refract anaemia+sideroblast'),('efi-anaemia',1,'BBmA.00',NULL,'[M]Refract anaemia+sideroblast'),('efi-anaemia',1,'BBmB.',NULL,'[M]Refr anam+xs blst+transform'),('efi-anaemia',1,'BBmB.00',NULL,'[M]Refr anam+xs blst+transform'),('efi-anaemia',1,'BBmL.',NULL,'[M] Refract anaem excess blast'),('efi-anaemia',1,'BBmL.00',NULL,'[M] Refract anaem excess blast'),('efi-anaemia',1,'ByuHC',NULL,'[X]Refractory anaemia,unspecif'),('efi-anaemia',1,'ByuHC00',NULL,'[X]Refractory anaemia,unspecif'),('efi-anaemia',1,'C2620',NULL,'Folic acid deficiency'),('efi-anaemia',1,'C262000',NULL,'Folic acid deficiency'),('efi-anaemia',1,'C2621',NULL,'Vitamin B12 deficiency'),('efi-anaemia',1,'C262100',NULL,'Vitamin B12 deficiency'),('efi-anaemia',1,'D0...',NULL,'Deficiency anaemias'),('efi-anaemia',1,'D0...00',NULL,'Deficiency anaemias'),('efi-anaemia',1,'D00..',NULL,'Iron deficiency anaemias'),('efi-anaemia',1,'D00..00',NULL,'Iron deficiency anaemias'),('efi-anaemia',1,'D000.',NULL,'Iron defic.anaemia-blood loss'),('efi-anaemia',1,'D000.00',NULL,'Iron defic.anaemia-blood loss'),('efi-anaemia',1,'D001.',NULL,'Iron defic.anaemia-dietary'),('efi-anaemia',1,'D001.00',NULL,'Iron defic.anaemia-dietary'),('efi-anaemia',1,'D00y.',NULL,'Other spec. iron defic.anaemia'),('efi-anaemia',1,'D00y.00',NULL,'Other spec. iron defic.anaemia'),('efi-anaemia',1,'D00y1',NULL,'Microcytic hypochromic anaemia'),('efi-anaemia',1,'D00y100',NULL,'Microcytic hypochromic anaemia'),('efi-anaemia',1,'D00yz',NULL,'Other spec iron def. anaem NOS'),('efi-anaemia',1,'D00yz00',NULL,'Other spec iron def. anaem NOS'),('efi-anaemia',1,'D00z.',NULL,'Unspec iron deficiency anaemia'),('efi-anaemia',1,'D00z.00',NULL,'Unspec iron deficiency anaemia'),('efi-anaemia',1,'D00z0',NULL,'Achlorhydric anaemia'),('efi-anaemia',1,'D00z000',NULL,'Achlorhydric anaemia'),('efi-anaemia',1,'D00z1',NULL,'Chlorotic anaemia'),('efi-anaemia',1,'D00z100',NULL,'Chlorotic anaemia'),('efi-anaemia',1,'D00z2',NULL,'Idiopathic hypochromic anaemia'),('efi-anaemia',1,'D00z200',NULL,'Idiopathic hypochromic anaemia'),('efi-anaemia',1,'D00zz',NULL,'Iron deficiency anaemia NOS'),('efi-anaemia',1,'D00zz00',NULL,'Iron deficiency anaemia NOS'),('efi-anaemia',1,'D01..',NULL,'Other deficiency anaemias'),('efi-anaemia',1,'D01..00',NULL,'Other deficiency anaemias'),('efi-anaemia',1,'D010.',NULL,'Pernicious anaemia'),('efi-anaemia',1,'D010.00',NULL,'Pernicious anaemia'),('efi-anaemia',1,'D011.',NULL,'Other vit.B12 defic. anaemias'),('efi-anaemia',1,'D011.00',NULL,'Other vit.B12 defic. anaemias'),('efi-anaemia',1,'D0110',NULL,'Vit.B12 defic.anaemia-dietary'),('efi-anaemia',1,'D011000',NULL,'Vit.B12 defic.anaemia-dietary'),('efi-anaemia',1,'D0111',NULL,'Vit.B12 defic.anaemia-malabs.'),('efi-anaemia',1,'D011100',NULL,'Vit.B12 defic.anaemia-malabs.'),('efi-anaemia',1,'D011X',NULL,'Vit B12 defic anaemia, unsp'),('efi-anaemia',1,'D011X00',NULL,'Vit B12 defic anaemia, unsp'),('efi-anaemia',1,'D011z',NULL,'Other vit.B12 defic anaem. NOS'),('efi-anaemia',1,'D011z00',NULL,'Other vit.B12 defic anaem. NOS'),('efi-anaemia',1,'D012.',NULL,'Folate-deficiency anaemia'),('efi-anaemia',1,'D012.00',NULL,'Folate-deficiency anaemia'),('efi-anaemia',1,'D0121',NULL,'Folate-defic. anaemia-dietary'),('efi-anaemia',1,'D012100',NULL,'Folate-defic. anaemia-dietary'),('efi-anaemia',1,'D0122',NULL,'Folate-defic. anaemia-drug ind'),('efi-anaemia',1,'D012200',NULL,'Folate-defic. anaemia-drug ind'),('efi-anaemia',1,'D0123',NULL,'Folate-defic. anaemia - malabs'),('efi-anaemia',1,'D012300',NULL,'Folate-defic. anaemia - malabs'),('efi-anaemia',1,'D0124',NULL,'Folate-defic.anaemia-liver dis'),('efi-anaemia',1,'D012400',NULL,'Folate-defic.anaemia-liver dis'),('efi-anaemia',1,'D0125',NULL,'Macrocytic anaemia unspecified'),('efi-anaemia',1,'D012500',NULL,'Macrocytic anaemia unspecified'),('efi-anaemia',1,'D012z',NULL,'Folate-deficiency anaemia NOS'),('efi-anaemia',1,'D012z00',NULL,'Folate-deficiency anaemia NOS'),('efi-anaemia',1,'D013.',NULL,'Oth spec megalo anaemia NEC'),('efi-anaemia',1,'D013.00',NULL,'Oth spec megalo anaemia NEC'),('efi-anaemia',1,'D0130',NULL,'Combined B12+folate defic anae'),('efi-anaemia',1,'D013000',NULL,'Combined B12+folate defic anae'),('efi-anaemia',1,'D013z',NULL,'Megaloblastic anaemia NEC NOS'),('efi-anaemia',1,'D013z00',NULL,'Megaloblastic anaemia NEC NOS'),('efi-anaemia',1,'D014.',NULL,'Protein-deficiency anaemia'),('efi-anaemia',1,'D014.00',NULL,'Protein-deficiency anaemia'),('efi-anaemia',1,'D0140',NULL,'Amino-acid deficiency anaemia'),('efi-anaemia',1,'D014000',NULL,'Amino-acid deficiency anaemia'),('efi-anaemia',1,'D014z',NULL,'Protein-deficiency anaemia NOS'),('efi-anaemia',1,'D014z00',NULL,'Protein-deficiency anaemia NOS'),('efi-anaemia',1,'D01y.',NULL,'Other nutrit. defic. anaemia'),('efi-anaemia',1,'D01y.00',NULL,'Other nutrit. defic. anaemia'),('efi-anaemia',1,'D01yy',NULL,'Other nutrit.defic.anaemia OS'),('efi-anaemia',1,'D01yy00',NULL,'Other nutrit.defic.anaemia OS'),('efi-anaemia',1,'D01yz',NULL,'Other nutrit.defic.anaemia NOS'),('efi-anaemia',1,'D01yz00',NULL,'Other nutrit.defic.anaemia NOS'),('efi-anaemia',1,'D01z.',NULL,'Other deficiency anaemias NOS'),('efi-anaemia',1,'D01z.00',NULL,'Other deficiency anaemias NOS'),('efi-anaemia',1,'D01z0',NULL,'[X]Megaloblastic anaemia NOS'),('efi-anaemia',1,'D01z000',NULL,'[X]Megaloblastic anaemia NOS'),('efi-anaemia',1,'D0y..',NULL,'Deficiency anaemias OS'),('efi-anaemia',1,'D0y..00',NULL,'Deficiency anaemias OS'),('efi-anaemia',1,'D0z..',NULL,'Deficiency anaemias NOS'),('efi-anaemia',1,'D0z..00',NULL,'Deficiency anaemias NOS'),('efi-anaemia',1,'D1...',NULL,'Haemolytic anaemias'),('efi-anaemia',1,'D1...00',NULL,'Haemolytic anaemias'),('efi-anaemia',1,'D104.',NULL,'Thalassaemia'),('efi-anaemia',1,'D104.00',NULL,'Thalassaemia'),('efi-anaemia',1,'D1040',NULL,'Thalassaemia major NEC'),('efi-anaemia',1,'D104000',NULL,'Thalassaemia major NEC'),('efi-anaemia',1,'D1047',NULL,'Beta major thalassaemia'),('efi-anaemia',1,'D104700',NULL,'Beta major thalassaemia'),('efi-anaemia',1,'D104z',NULL,'Thalassaemia NOS'),('efi-anaemia',1,'D104z00',NULL,'Thalassaemia NOS'),('efi-anaemia',1,'D106.',NULL,'Sickle-cell anaemia'),('efi-anaemia',1,'D106.00',NULL,'Sickle-cell anaemia'),('efi-anaemia',1,'D1060',NULL,'Sickle-cell unspecified type'),('efi-anaemia',1,'D106000',NULL,'Sickle-cell unspecified type'),('efi-anaemia',1,'D1061',NULL,'Sickle-cell anaemia-no crisis'),('efi-anaemia',1,'D106100',NULL,'Sickle-cell anaemia-no crisis'),('efi-anaemia',1,'D1062',NULL,'Sickle-cell with crisis'),('efi-anaemia',1,'D106200',NULL,'Sickle-cell with crisis'),('efi-anaemia',1,'D106z',NULL,'Sickle-cell anaemia NOS'),('efi-anaemia',1,'D106z00',NULL,'Sickle-cell anaemia NOS'),('efi-anaemia',1,'D11..',NULL,'Acquired haemolytic anaemias'),('efi-anaemia',1,'D11..00',NULL,'Acquired haemolytic anaemias'),('efi-anaemia',1,'D110.',NULL,'Autoimmune haemolytic anaemias'),('efi-anaemia',1,'D110.00',NULL,'Autoimmune haemolytic anaemias'),('efi-anaemia',1,'D1100',NULL,'Primary cold-type haemol.anaem'),('efi-anaemia',1,'D110000',NULL,'Primary cold-type haemol.anaem'),('efi-anaemia',1,'D1101',NULL,'Primary warm-type haemol.anaem'),('efi-anaemia',1,'D110100',NULL,'Primary warm-type haemol.anaem'),('efi-anaemia',1,'D1102',NULL,'Secondary cold-type haem.anaem'),('efi-anaemia',1,'D110200',NULL,'Secondary cold-type haem.anaem'),('efi-anaemia',1,'D1103',NULL,'Secondary warm-type haem.anaem'),('efi-anaemia',1,'D110300',NULL,'Secondary warm-type haem.anaem'),('efi-anaemia',1,'D1104',NULL,'Drug-induced autoim haem anaem'),('efi-anaemia',1,'D110400',NULL,'Drug-induced autoim haem anaem'),('efi-anaemia',1,'D110z',NULL,'Autoimmune haemol.anaemia NOS'),('efi-anaemia',1,'D110z00',NULL,'Autoimmune haemol.anaemia NOS'),('efi-anaemia',1,'D111.',NULL,'Non-autoimmune haemol.anaemia'),('efi-anaemia',1,'D111.00',NULL,'Non-autoimmune haemol.anaemia'),('efi-anaemia',1,'D1110',NULL,'Mechanical haemolytic anaemia'),
('efi-anaemia',1,'D111000',NULL,'Mechanical haemolytic anaemia'),('efi-anaemia',1,'D1111',NULL,'Microangiopathic haemol.anaem.'),('efi-anaemia',1,'D111100',NULL,'Microangiopathic haemol.anaem.'),('efi-anaemia',1,'D1112',NULL,'Toxic haemolytic anaemia'),('efi-anaemia',1,'D111200',NULL,'Toxic haemolytic anaemia'),('efi-anaemia',1,'D1114',NULL,'Drug-induced haemolyt anaemia'),('efi-anaemia',1,'D111400',NULL,'Drug-induced haemolyt anaemia'),('efi-anaemia',1,'D1115',NULL,'Infective haemolytic anaemia'),('efi-anaemia',1,'D111500',NULL,'Infective haemolytic anaemia'),('efi-anaemia',1,'D111y',NULL,'Non-autoimm.haemol.anaemia OS'),('efi-anaemia',1,'D111y00',NULL,'Non-autoimm.haemol.anaemia OS'),('efi-anaemia',1,'D111z',NULL,'Non-autoimm.haemol.anaemia NOS'),('efi-anaemia',1,'D111z00',NULL,'Non-autoimm.haemol.anaemia NOS'),('efi-anaemia',1,'D112z',NULL,'Haemolysis Hb-uria,extern,NOS'),('efi-anaemia',1,'D112z00',NULL,'Haemolysis Hb-uria,extern,NOS'),('efi-anaemia',1,'D11z.',NULL,'Acquired haemolytic anaem. NOS'),('efi-anaemia',1,'D11z.00',NULL,'Acquired haemolytic anaem. NOS'),('efi-anaemia',1,'D1y..',NULL,'Haemolytic anaemias OS'),('efi-anaemia',1,'D1y..00',NULL,'Haemolytic anaemias OS'),('efi-anaemia',1,'D1z..',NULL,'Haemolytic anaemias NOS'),('efi-anaemia',1,'D1z..00',NULL,'Haemolytic anaemias NOS'),('efi-anaemia',1,'D2...',NULL,'Aplastic and other anaemias'),('efi-anaemia',1,'D2...00',NULL,'Aplastic and other anaemias'),('efi-anaemia',1,'D20..',NULL,'Aplastic anaemia'),('efi-anaemia',1,'D20..00',NULL,'Aplastic anaemia'),('efi-anaemia',1,'D200.',NULL,'Constitutional aplastic anaem.'),('efi-anaemia',1,'D200.00',NULL,'Constitutional aplastic anaem.'),('efi-anaemia',1,'D2000',NULL,'Congenital hypoplastic anaemia'),('efi-anaemia',1,'D200000',NULL,'Congenital hypoplastic anaemia'),('efi-anaemia',1,'D2002',NULL,'Constit aplas anaem + malform'),('efi-anaemia',1,'D200200',NULL,'Constit aplas anaem + malform'),('efi-anaemia',1,'D200y',NULL,'Constit.aplastic anaemia OS'),('efi-anaemia',1,'D200y00',NULL,'Constit.aplastic anaemia OS'),('efi-anaemia',1,'D200z',NULL,'Constitut.aplastic anaemia NOS'),('efi-anaemia',1,'D200z00',NULL,'Constitut.aplastic anaemia NOS'),('efi-anaemia',1,'D201.',NULL,'Acquired aplastic anaemia'),('efi-anaemia',1,'D201.00',NULL,'Acquired aplastic anaemia'),('efi-anaemia',1,'D2010',NULL,'Aplastic anaemia-chronic dis.'),('efi-anaemia',1,'D201000',NULL,'Aplastic anaemia-chronic dis.'),('efi-anaemia',1,'D2011',NULL,'Aplastic anaemia due to drugs'),('efi-anaemia',1,'D201100',NULL,'Aplastic anaemia due to drugs'),('efi-anaemia',1,'D2012',NULL,'Aplastic anaemia-infection'),('efi-anaemia',1,'D201200',NULL,'Aplastic anaemia-infection'),('efi-anaemia',1,'D2013',NULL,'Aplastic anaemia-radiation'),('efi-anaemia',1,'D201300',NULL,'Aplastic anaemia-radiation'),('efi-anaemia',1,'D2014',NULL,'Aplastic anaemia-toxic'),('efi-anaemia',1,'D201400',NULL,'Aplastic anaemia-toxic'),('efi-anaemia',1,'D2017',NULL,'Transient hypoplastic anaemia'),('efi-anaemia',1,'D201700',NULL,'Transient hypoplastic anaemia'),('efi-anaemia',1,'D201z',NULL,'Acquired aplastic anaemia NOS'),('efi-anaemia',1,'D201z00',NULL,'Acquired aplastic anaemia NOS'),('efi-anaemia',1,'D204.',NULL,'Idiopathic aplastic anaemia'),('efi-anaemia',1,'D204.00',NULL,'Idiopathic aplastic anaemia'),('efi-anaemia',1,'D20z.',NULL,'Aplastic anaemia NOS'),('efi-anaemia',1,'D20z.00',NULL,'Aplastic anaemia NOS'),('efi-anaemia',1,'D21..',NULL,'Other and unspecified anaemias'),('efi-anaemia',1,'D21..00',NULL,'Other and unspecified anaemias'),('efi-anaemia',1,'D210.',NULL,'Sideroblastic anaemia'),('efi-anaemia',1,'D210.00',NULL,'Sideroblastic anaemia'),('efi-anaemia',1,'D2101',NULL,'Acquired sideroblastic anaemia'),('efi-anaemia',1,'D210100',NULL,'Acquired sideroblastic anaemia'),('efi-anaemia',1,'D2103',NULL,'2ndy sideroblstc anaem due/dis'),('efi-anaemia',1,'D210300',NULL,'2ndy sideroblstc anaem due/dis'),('efi-anaemia',1,'D2104',NULL,'2ndy sidrblst anaem due/drg+tx'),('efi-anaemia',1,'D210400',NULL,'2ndy sidrblst anaem due/drg+tx'),('efi-anaemia',1,'D210z',NULL,'Sideroblastic anaemia NOS'),('efi-anaemia',1,'D210z00',NULL,'Sideroblastic anaemia NOS'),('efi-anaemia',1,'D211.',NULL,'Acute posthaemorrhagic anaemia'),('efi-anaemia',1,'D211.00',NULL,'Acute posthaemorrhagic anaemia'),('efi-anaemia',1,'D212.',NULL,'Anaemia in neoplastic disease'),('efi-anaemia',1,'D212.00',NULL,'Anaemia in neoplastic disease'),('efi-anaemia',1,'D2120',NULL,'Anaemia in ovarian carcinoma'),('efi-anaemia',1,'D212000',NULL,'Anaemia in ovarian carcinoma'),('efi-anaemia',1,'D213.',NULL,'Refractory Anaemia'),('efi-anaemia',1,'D213.00',NULL,'Refractory Anaemia'),('efi-anaemia',1,'D214.',NULL,'Chronic anaemia'),('efi-anaemia',1,'D214.00',NULL,'Chronic anaemia'),('efi-anaemia',1,'D215.',NULL,'Anaemia second renal failure'),('efi-anaemia',1,'D215.00',NULL,'Anaemia second renal failure'),('efi-anaemia',1,'D2150',NULL,'Anaemia secondary to CRF'),('efi-anaemia',1,'D215000',NULL,'Anaemia secondary to CRF'),('efi-anaemia',1,'D21y.',NULL,'Other specified anaemias'),('efi-anaemia',1,'D21y.00',NULL,'Other specified anaemias'),('efi-anaemia',1,'D21yy',NULL,'Other anaemia OS'),('efi-anaemia',1,'D21yy00',NULL,'Other anaemia OS'),('efi-anaemia',1,'D21yz',NULL,'Other specified anaemia NOS'),('efi-anaemia',1,'D21yz00',NULL,'Other specified anaemia NOS'),('efi-anaemia',1,'D21z.',NULL,'Anaemia unspecified'),('efi-anaemia',1,'D21z.00',NULL,'Anaemia unspecified'),('efi-anaemia',1,'D2y..',NULL,'Anaemias OS'),('efi-anaemia',1,'D2y..00',NULL,'Anaemias OS'),('efi-anaemia',1,'D2z..',NULL,'Other anaemias NOS'),('efi-anaemia',1,'D2z..00',NULL,'Other anaemias NOS'),('efi-anaemia',1,'Dyu0.',NULL,'[X]Nutritional anaemias'),('efi-anaemia',1,'Dyu0.00',NULL,'[X]Nutritional anaemias'),('efi-anaemia',1,'Dyu00',NULL,'[X]Oth iron deficncy anaemias'),('efi-anaemia',1,'Dyu0000',NULL,'[X]Oth iron deficncy anaemias'),('efi-anaemia',1,'Dyu01',NULL,'[X]Oth dietry vit B12 def anem'),('efi-anaemia',1,'Dyu0100',NULL,'[X]Oth dietry vit B12 def anem'),('efi-anaemia',1,'Dyu02',NULL,'[X]Other vit B12 defic anaemia'),('efi-anaemia',1,'Dyu0200',NULL,'[X]Other vit B12 defic anaemia'),('efi-anaemia',1,'Dyu03',NULL,'[X]Oth folat deficiency anaems'),('efi-anaemia',1,'Dyu0300',NULL,'[X]Oth folat deficiency anaems'),('efi-anaemia',1,'Dyu04',NULL,'[X]O megaloblast anaemias,NEC'),('efi-anaemia',1,'Dyu0400',NULL,'[X]O megaloblast anaemias,NEC'),('efi-anaemia',1,'Dyu05',NULL,'[X]Anaem(n-megblst)a o s nut d'),('efi-anaemia',1,'Dyu0500',NULL,'[X]Anaem(n-megblst)a o s nut d'),('efi-anaemia',1,'Dyu06',NULL,'[X]Vit B12 defic anaemia, unsp'),('efi-anaemia',1,'Dyu0600',NULL,'[X]Vit B12 defic anaemia, unsp'),('efi-anaemia',1,'Dyu1.',NULL,'[X]Haemolytic anaemias'),('efi-anaemia',1,'Dyu1.00',NULL,'[X]Haemolytic anaemias'),('efi-anaemia',1,'Dyu15',NULL,'[X]Oth autoim hmolytic anaems'),('efi-anaemia',1,'Dyu1500',NULL,'[X]Oth autoim hmolytic anaems'),('efi-anaemia',1,'Dyu16',NULL,'[X]O n-autoimm hmolytc anaema'),('efi-anaemia',1,'Dyu1600',NULL,'[X]O n-autoimm hmolytc anaema'),('efi-anaemia',1,'Dyu17',NULL,'[X]Oth acqrd hmolytc anaemias'),('efi-anaemia',1,'Dyu1700',NULL,'[X]Oth acqrd hmolytc anaemias'),('efi-anaemia',1,'Dyu2.',NULL,'[X]Aplastic and other anaemias'),('efi-anaemia',1,'Dyu2.00',NULL,'[X]Aplastic and other anaemias'),('efi-anaemia',1,'Dyu21',NULL,'[X]Oth spcfd aplastic anaemias'),('efi-anaemia',1,'Dyu2100',NULL,'[X]Oth spcfd aplastic anaemias'),('efi-anaemia',1,'Dyu22',NULL,'[X]Anaemia in oth chron dis CE'),('efi-anaemia',1,'Dyu2200',NULL,'[X]Anaemia in oth chron dis CE'),('efi-anaemia',1,'Dyu23',NULL,'[X]Oth sideroblastic anaemias'),('efi-anaemia',1,'Dyu2300',NULL,'[X]Oth sideroblastic anaemias'),('efi-anaemia',1,'Dyu24',NULL,'[X]Other specified anaemias'),('efi-anaemia',1,'Dyu2400',NULL,'[X]Other specified anaemias'),('efi-anaemia',1,'J6141',NULL,'Chronic active hepatitis'),('efi-anaemia',1,'J614100',NULL,'Chronic active hepatitis');
INSERT INTO #codesreadv2
VALUES ('efi-care-requirement',1,'13F6.',NULL,'Nursing/other home'),('efi-care-requirement',1,'13F6.00',NULL,'Nursing/other home'),('efi-care-requirement',1,'13F61',NULL,'Lives in a nursing home'),('efi-care-requirement',1,'13F6100',NULL,'Lives in a nursing home'),('efi-care-requirement',1,'13FX.',NULL,'Lives in care home'),('efi-care-requirement',1,'13FX.00',NULL,'Lives in care home'),('efi-care-requirement',1,'13G6.',NULL,'Home help'),('efi-care-requirement',1,'13G6.00',NULL,'Home help'),('efi-care-requirement',1,'13G61',NULL,'Home help attends'),('efi-care-requirement',1,'13G6100',NULL,'Home help attends'),('efi-care-requirement',1,'13WJ.',NULL,'Help by relatives'),('efi-care-requirement',1,'13WJ.00',NULL,'Help by relatives'),('efi-care-requirement',1,'8GEB.',NULL,'Care from friends'),('efi-care-requirement',1,'8GEB.00',NULL,'Care from friends'),('efi-care-requirement',1,'918F.',NULL,'Has a carer'),('efi-care-requirement',1,'918F.00',NULL,'Has a carer'),('efi-care-requirement',1,'9N1G.',NULL,'Seen in nursing home'),('efi-care-requirement',1,'9N1G.00',NULL,'Seen in nursing home');
INSERT INTO #codesreadv2
VALUES ('efi-cognitive-problems',1,'1461.',NULL,'H/O: dementia'),('efi-cognitive-problems',1,'1461.00',NULL,'H/O: dementia'),('efi-cognitive-problems',1,'1B1A.',NULL,'Memory loss - amnesia'),('efi-cognitive-problems',1,'1B1A.00',NULL,'Memory loss - amnesia'),('efi-cognitive-problems',1,'1S21.',NULL,'Disturb of mem for ord events'),('efi-cognitive-problems',1,'1S21.00',NULL,'Disturb of mem for ord events'),('efi-cognitive-problems',1,'2841.',NULL,'Confused'),('efi-cognitive-problems',1,'2841.00',NULL,'Confused'),('efi-cognitive-problems',1,'28E..',NULL,'Cognitive decline'),('efi-cognitive-problems',1,'28E..00',NULL,'Cognitive decline'),('efi-cognitive-problems',1,'3A10.',NULL,'Memory: own age not known'),('efi-cognitive-problems',1,'3A10.00',NULL,'Memory: own age not known'),('efi-cognitive-problems',1,'3A20.',NULL,'Memory: present time not known'),('efi-cognitive-problems',1,'3A20.00',NULL,'Memory: present time not known'),('efi-cognitive-problems',1,'3A30.',NULL,'Memory: present place not knwn'),('efi-cognitive-problems',1,'3A30.00',NULL,'Memory: present place not knwn'),('efi-cognitive-problems',1,'3A40.',NULL,'Memory: present year not known'),('efi-cognitive-problems',1,'3A40.00',NULL,'Memory: present year not known'),('efi-cognitive-problems',1,'3A50.',NULL,'Memory: own DOB not known'),('efi-cognitive-problems',1,'3A50.00',NULL,'Memory: own DOB not known'),('efi-cognitive-problems',1,'3A60.',NULL,'Memory: present month not knwn'),('efi-cognitive-problems',1,'3A60.00',NULL,'Memory: present month not knwn'),('efi-cognitive-problems',1,'3A70.',NULL,'Memory: important event not kn'),('efi-cognitive-problems',1,'3A70.00',NULL,'Memory: important event not kn'),('efi-cognitive-problems',1,'3A80.',NULL,'Memory: import.person not knwn'),('efi-cognitive-problems',1,'3A80.00',NULL,'Memory: import.person not knwn'),('efi-cognitive-problems',1,'3A91.',NULL,'Memory: count down unsuccess.'),('efi-cognitive-problems',1,'3A91.00',NULL,'Memory: count down unsuccess.'),('efi-cognitive-problems',1,'3AA1.',NULL,'Memory: address recall unsucc.'),('efi-cognitive-problems',1,'3AA1.00',NULL,'Memory: address recall unsucc.'),('efi-cognitive-problems',1,'3AE..',NULL,'GDS: assess prim deg dement'),('efi-cognitive-problems',1,'3AE..00',NULL,'GDS: assess prim deg dement'),('efi-cognitive-problems',1,'66h..',NULL,'Dementia monitoring'),('efi-cognitive-problems',1,'66h..00',NULL,'Dementia monitoring'),('efi-cognitive-problems',1,'6AB..',NULL,'Dementia annual review'),('efi-cognitive-problems',1,'6AB..00',NULL,'Dementia annual review'),('efi-cognitive-problems',1,'8HTY.',NULL,'Referral to memory clinic'),('efi-cognitive-problems',1,'8HTY.00',NULL,'Referral to memory clinic'),('efi-cognitive-problems',1,'9NdL.',NULL,'Lacks capacity consnt MCA 2005'),('efi-cognitive-problems',1,'9NdL.00',NULL,'Lacks capacity consnt MCA 2005'),('efi-cognitive-problems',1,'9Nk1.',NULL,'Seen in memory clinic'),('efi-cognitive-problems',1,'9Nk1.00',NULL,'Seen in memory clinic'),('efi-cognitive-problems',1,'9Ou..',NULL,'Dementia monitoring admin.'),('efi-cognitive-problems',1,'9Ou..00',NULL,'Dementia monitoring admin.'),('efi-cognitive-problems',1,'9Ou2.',NULL,'Dementia monitoring 2nd letter'),('efi-cognitive-problems',1,'9Ou2.00',NULL,'Dementia monitoring 2nd letter'),('efi-cognitive-problems',1,'9Ou3.',NULL,'Dementia monitoring 3rd letter'),('efi-cognitive-problems',1,'9Ou3.00',NULL,'Dementia monitoring 3rd letter'),('efi-cognitive-problems',1,'9Ou4.',NULL,'Dementia monitor verbal invite'),('efi-cognitive-problems',1,'9Ou4.00',NULL,'Dementia monitor verbal invite'),('efi-cognitive-problems',1,'9Ou5.',NULL,'Dementia monitor phone invite'),('efi-cognitive-problems',1,'9Ou5.00',NULL,'Dementia monitor phone invite'),('efi-cognitive-problems',1,'9hD..',NULL,'Excep report: demen qual indic'),('efi-cognitive-problems',1,'9hD..00',NULL,'Excep report: demen qual indic'),('efi-cognitive-problems',1,'9hD0.',NULL,'Exc demen qual ind: Pat unsuit'),('efi-cognitive-problems',1,'9hD0.00',NULL,'Exc demen qual ind: Pat unsuit'),('efi-cognitive-problems',1,'9hD1.',NULL,'Exc demen qual ind: Inform dis'),('efi-cognitive-problems',1,'9hD1.00',NULL,'Exc demen qual ind: Inform dis'),('efi-cognitive-problems',1,'E00..',NULL,'Senile/presenile organic psych'),('efi-cognitive-problems',1,'E00..00',NULL,'Senile/presenile organic psych'),('efi-cognitive-problems',1,'E000.',NULL,'Senile dementia-uncomplicated'),('efi-cognitive-problems',1,'E000.00',NULL,'Senile dementia-uncomplicated'),('efi-cognitive-problems',1,'E001.',NULL,'Presenile dementia'),('efi-cognitive-problems',1,'E001.00',NULL,'Presenile dementia'),('efi-cognitive-problems',1,'E0010',NULL,'Presenile dementia - uncomplic'),('efi-cognitive-problems',1,'E001000',NULL,'Presenile dementia - uncomplic'),('efi-cognitive-problems',1,'E0011',NULL,'Presenile dementia + delirium'),('efi-cognitive-problems',1,'E001100',NULL,'Presenile dementia + delirium'),('efi-cognitive-problems',1,'E0012',NULL,'Presenile dementia + paranoia'),('efi-cognitive-problems',1,'E001200',NULL,'Presenile dementia + paranoia'),('efi-cognitive-problems',1,'E0013',NULL,'Presenile dementia+depression'),('efi-cognitive-problems',1,'E001300',NULL,'Presenile dementia+depression'),('efi-cognitive-problems',1,'E001z',NULL,'Presenile dementia NOS'),('efi-cognitive-problems',1,'E001z00',NULL,'Presenile dementia NOS'),('efi-cognitive-problems',1,'E002.',NULL,'Sen.dement.-depressed/paranoid'),('efi-cognitive-problems',1,'E002.00',NULL,'Sen.dement.-depressed/paranoid'),('efi-cognitive-problems',1,'E0020',NULL,'Senile dementia + paranoia'),('efi-cognitive-problems',1,'E002000',NULL,'Senile dementia + paranoia'),('efi-cognitive-problems',1,'E0021',NULL,'Senile dementia + depression'),('efi-cognitive-problems',1,'E002100',NULL,'Senile dementia + depression'),('efi-cognitive-problems',1,'E002z',NULL,'Sen.dement.-depr./paranoid NOS'),('efi-cognitive-problems',1,'E002z00',NULL,'Sen.dement.-depr./paranoid NOS'),('efi-cognitive-problems',1,'E003.',NULL,'Senile dementia + delirium'),('efi-cognitive-problems',1,'E003.00',NULL,'Senile dementia + delirium'),('efi-cognitive-problems',1,'E004.',NULL,'Arteriosclerotic dementia'),('efi-cognitive-problems',1,'E004.00',NULL,'Arteriosclerotic dementia'),('efi-cognitive-problems',1,'E0040',NULL,'Arterioscl.dementia-uncomplic.'),('efi-cognitive-problems',1,'E004000',NULL,'Arterioscl.dementia-uncomplic.'),('efi-cognitive-problems',1,'E0041',NULL,'Arterioscl.dementia+delirium'),('efi-cognitive-problems',1,'E004100',NULL,'Arterioscl.dementia+delirium'),('efi-cognitive-problems',1,'E0042',NULL,'Arterioscl.dementia+paranoia'),('efi-cognitive-problems',1,'E004200',NULL,'Arterioscl.dementia+paranoia'),('efi-cognitive-problems',1,'E0043',NULL,'Arterioscl.dementia+depression'),('efi-cognitive-problems',1,'E004300',NULL,'Arterioscl.dementia+depression'),('efi-cognitive-problems',1,'E004z',NULL,'Arteriosclerotic dementia NOS'),('efi-cognitive-problems',1,'E004z00',NULL,'Arteriosclerotic dementia NOS'),('efi-cognitive-problems',1,'E012.',NULL,'Other alcoholic dementia'),('efi-cognitive-problems',1,'E012.00',NULL,'Other alcoholic dementia'),('efi-cognitive-problems',1,'E041.',NULL,'Dementia in conditions EC'),('efi-cognitive-problems',1,'E041.00',NULL,'Dementia in conditions EC'),('efi-cognitive-problems',1,'E2A10',NULL,'Mild memory disturbance'),('efi-cognitive-problems',1,'E2A1000',NULL,'Mild memory disturbance'),('efi-cognitive-problems',1,'E2A11',NULL,'Organic memory impairment'),('efi-cognitive-problems',1,'E2A1100',NULL,'Organic memory impairment'),('efi-cognitive-problems',1,'Eu00.',NULL,'[X]Dementia in Alzheimers'),('efi-cognitive-problems',1,'Eu00.00',NULL,'[X]Dementia in Alzheimers'),('efi-cognitive-problems',1,'Eu000',NULL,'[X]Early onset Alzheim dement'),('efi-cognitive-problems',1,'Eu00000',NULL,'[X]Early onset Alzheim dement'),('efi-cognitive-problems',1,'Eu001',NULL,'[X]Late onset Alzheim dementia'),('efi-cognitive-problems',1,'Eu00100',NULL,'[X]Late onset Alzheim dementia'),('efi-cognitive-problems',1,'Eu002',NULL,'[X]Atypical/mixed Alzheimers'),('efi-cognitive-problems',1,'Eu00200',NULL,'[X]Atypical/mixed Alzheimers'),('efi-cognitive-problems',1,'Eu00z',NULL,'[X]Alzheimers disease unspec'),('efi-cognitive-problems',1,'Eu00z00',NULL,'[X]Alzheimers disease unspec'),('efi-cognitive-problems',1,'Eu01.',NULL,'[X]Vascular dementia'),('efi-cognitive-problems',1,'Eu01.00',NULL,'[X]Vascular dementia'),('efi-cognitive-problems',1,'Eu010',NULL,'[X]Vascular dement acute onset'),('efi-cognitive-problems',1,'Eu01000',NULL,'[X]Vascular dement acute onset'),('efi-cognitive-problems',1,'Eu011',NULL,'[X]Multi-infarct dementia'),('efi-cognitive-problems',1,'Eu01100',NULL,'[X]Multi-infarct dementia'),('efi-cognitive-problems',1,'Eu012',NULL,'[X]Subcortical vascular dement'),('efi-cognitive-problems',1,'Eu01200',NULL,'[X]Subcortical vascular dement'),('efi-cognitive-problems',1,'Eu013',NULL,'[X]Mix cort/subcor vasc dement'),('efi-cognitive-problems',1,'Eu01300',NULL,'[X]Mix cort/subcor vasc dement'),('efi-cognitive-problems',1,'Eu01y',NULL,'[X]Other vascular dementia'),('efi-cognitive-problems',1,'Eu01y00',NULL,'[X]Other vascular dementia'),('efi-cognitive-problems',1,'Eu01z',NULL,'[X]Vascular dementia unspecif'),('efi-cognitive-problems',1,'Eu01z00',NULL,'[X]Vascular dementia unspecif'),('efi-cognitive-problems',1,'Eu02.',NULL,'[X]Dementia in disease EC'),('efi-cognitive-problems',1,'Eu02.00',NULL,'[X]Dementia in disease EC'),('efi-cognitive-problems',1,'Eu020',NULL,'[X]Dementia in Picks disease'),('efi-cognitive-problems',1,'Eu02000',NULL,'[X]Dementia in Picks disease'),('efi-cognitive-problems',1,'Eu021',NULL,'[X]Dement in Creutzfeld-Jakob'),('efi-cognitive-problems',1,'Eu02100',NULL,'[X]Dement in Creutzfeld-Jakob'),('efi-cognitive-problems',1,'Eu022',NULL,'[X]Dementia in Huntingtons'),('efi-cognitive-problems',1,'Eu02200',NULL,'[X]Dementia in Huntingtons'),('efi-cognitive-problems',1,'Eu023',NULL,'[X]Dementia in Parkinsons'),
('efi-cognitive-problems',1,'Eu02300',NULL,'[X]Dementia in Parkinsons'),('efi-cognitive-problems',1,'Eu024',NULL,'[X]Dementia in HIV disease'),('efi-cognitive-problems',1,'Eu02400',NULL,'[X]Dementia in HIV disease'),('efi-cognitive-problems',1,'Eu025',NULL,'[X]Lewy body dementia'),('efi-cognitive-problems',1,'Eu02500',NULL,'[X]Lewy body dementia'),('efi-cognitive-problems',1,'Eu02y',NULL,'[X]Dement,oth sp dis cl elsewh'),('efi-cognitive-problems',1,'Eu02y00',NULL,'[X]Dement,oth sp dis cl elsewh'),('efi-cognitive-problems',1,'Eu02z',NULL,'[X] Unspecified dementia'),('efi-cognitive-problems',1,'Eu02z00',NULL,'[X] Unspecified dementia'),('efi-cognitive-problems',1,'Eu041',NULL,'[X]Delirium superimp dementia'),('efi-cognitive-problems',1,'Eu04100',NULL,'[X]Delirium superimp dementia'),('efi-cognitive-problems',1,'Eu057',NULL,'[X]Mild cognitive disorder'),('efi-cognitive-problems',1,'Eu05700',NULL,'[X]Mild cognitive disorder'),('efi-cognitive-problems',1,'F110.',NULL,'Alzheimers disease'),('efi-cognitive-problems',1,'F110.00',NULL,'Alzheimers disease'),('efi-cognitive-problems',1,'F1100',NULL,'Alzheimer dis wth early onset'),('efi-cognitive-problems',1,'F110000',NULL,'Alzheimer dis wth early onset'),('efi-cognitive-problems',1,'F1101',NULL,'Alzheimers dis wth late onset'),('efi-cognitive-problems',1,'F110100',NULL,'Alzheimers dis wth late onset'),('efi-cognitive-problems',1,'F116.',NULL,'Lewy body disease'),('efi-cognitive-problems',1,'F116.00',NULL,'Lewy body disease'),('efi-cognitive-problems',1,'F21y2',NULL,'Binswangers disease'),('efi-cognitive-problems',1,'F21y200',NULL,'Binswangers disease'),('efi-cognitive-problems',1,'R00z0',NULL,'[D]Amnesia (retrograde)'),('efi-cognitive-problems',1,'R00z000',NULL,'[D]Amnesia (retrograde)');
INSERT INTO #codesreadv2
VALUES ('efi-dizziness',1,'1491.',NULL,'H/O: vertigo/Menieres disease'),('efi-dizziness',1,'1491.00',NULL,'H/O: vertigo/Menieres disease'),('efi-dizziness',1,'1B5..',NULL,'Incoordination symptom'),('efi-dizziness',1,'1B5..00',NULL,'Incoordination symptom'),('efi-dizziness',1,'1B53.',NULL,'Dizziness present'),('efi-dizziness',1,'1B53.00',NULL,'Dizziness present'),('efi-dizziness',1,'F56..',NULL,'Vestibular syndromes/disorders'),('efi-dizziness',1,'F56..00',NULL,'Vestibular syndromes/disorders'),('efi-dizziness',1,'F561.',NULL,'Other peripheral vertigo'),('efi-dizziness',1,'F561.00',NULL,'Other peripheral vertigo'),('efi-dizziness',1,'F5610',NULL,'Peripheral vertigo, unspecif.'),('efi-dizziness',1,'F561000',NULL,'Peripheral vertigo, unspecif.'),('efi-dizziness',1,'F5611',NULL,'Benign paroxysm.posit.vertigo'),('efi-dizziness',1,'F561100',NULL,'Benign paroxysm.posit.vertigo'),('efi-dizziness',1,'F5614',NULL,'Otogenic vertigo'),('efi-dizziness',1,'F561400',NULL,'Otogenic vertigo'),('efi-dizziness',1,'F561z',NULL,'Other peripheral vertigo NOS'),('efi-dizziness',1,'F561z00',NULL,'Other peripheral vertigo NOS'),('efi-dizziness',1,'F562.',NULL,'Vertigo of central origin'),('efi-dizziness',1,'F562.00',NULL,'Vertigo of central origin'),('efi-dizziness',1,'F562z',NULL,'Vertigo of central origin NOS'),('efi-dizziness',1,'F562z00',NULL,'Vertigo of central origin NOS'),('efi-dizziness',1,'FyuQ1',NULL,'[X]Other peripheral vertigo'),('efi-dizziness',1,'FyuQ100',NULL,'[X]Other peripheral vertigo'),('efi-dizziness',1,'R004.',NULL,'[D]Dizziness and giddiness'),('efi-dizziness',1,'R004.00',NULL,'[D]Dizziness and giddiness'),('efi-dizziness',1,'R0040',NULL,'[D]Dizziness'),('efi-dizziness',1,'R004000',NULL,'[D]Dizziness'),('efi-dizziness',1,'R0043',NULL,'[D]Vertigo NOS'),('efi-dizziness',1,'R004300',NULL,'[D]Vertigo NOS'),('efi-dizziness',1,'R0044',NULL,'[D]Acute vertigo'),('efi-dizziness',1,'R004400',NULL,'[D]Acute vertigo');
INSERT INTO #codesreadv2
VALUES ('efi-dyspnoea',1,'173..',NULL,'Breathlessness'),('efi-dyspnoea',1,'173..00',NULL,'Breathlessness'),('efi-dyspnoea',1,'1732.',NULL,'Breathless - moderate exertion'),('efi-dyspnoea',1,'1732.00',NULL,'Breathless - moderate exertion'),('efi-dyspnoea',1,'1733.',NULL,'Breathless - mild exertion'),('efi-dyspnoea',1,'1733.00',NULL,'Breathless - mild exertion'),('efi-dyspnoea',1,'1734.',NULL,'Breathless - at rest'),('efi-dyspnoea',1,'1734.00',NULL,'Breathless - at rest'),('efi-dyspnoea',1,'1738.',NULL,'Difficulty breathing'),('efi-dyspnoea',1,'1738.00',NULL,'Difficulty breathing'),('efi-dyspnoea',1,'1739.',NULL,'Shortness of breath'),('efi-dyspnoea',1,'1739.00',NULL,'Shortness of breath'),('efi-dyspnoea',1,'173C.',NULL,'Short of breath on exertion'),('efi-dyspnoea',1,'173C.00',NULL,'Short of breath on exertion'),('efi-dyspnoea',1,'173K.',NULL,'MRC Breathless Scale: grade 4'),('efi-dyspnoea',1,'173K.00',NULL,'MRC Breathless Scale: grade 4'),('efi-dyspnoea',1,'173Z.',NULL,'Breathlessness NOS'),('efi-dyspnoea',1,'173Z.00',NULL,'Breathlessness NOS'),('efi-dyspnoea',1,'2322.',NULL,'O/E - dyspnoea'),('efi-dyspnoea',1,'2322.00',NULL,'O/E - dyspnoea'),('efi-dyspnoea',1,'R0608',NULL,'[D]Shortness of breath'),('efi-dyspnoea',1,'R060800',NULL,'[D]Shortness of breath'),('efi-dyspnoea',1,'R060A',NULL,'[D]Dyspnoea'),('efi-dyspnoea',1,'R060A00',NULL,'[D]Dyspnoea');
INSERT INTO #codesreadv2
VALUES ('efi-falls',1,'16D..',NULL,'Falls'),('efi-falls',1,'16D..00',NULL,'Falls'),('efi-falls',1,'16D1.',NULL,'Recurrent falls'),('efi-falls',1,'16D1.00',NULL,'Recurrent falls'),('efi-falls',1,'8HTl.',NULL,'Ref elderly fall prevent clinc'),('efi-falls',1,'8HTl.00',NULL,'Ref elderly fall prevent clinc'),('efi-falls',1,'8Hk1.',NULL,'Referral to falls service'),('efi-falls',1,'8Hk1.00',NULL,'Referral to falls service'),('efi-falls',1,'8O9..',NULL,'Prov tele community alarm serv'),('efi-falls',1,'8O9..00',NULL,'Prov tele community alarm serv'),('efi-falls',1,'R200.',NULL,'[D]Old age'),('efi-falls',1,'R200.00',NULL,'[D]Old age'),('efi-falls',1,'TC...',NULL,'Accidental falls'),('efi-falls',1,'TC...00',NULL,'Accidental falls'),('efi-falls',1,'TC5..',NULL,'Fall on same level-slip,trip'),('efi-falls',1,'TC5..00',NULL,'Fall on same level-slip,trip'),('efi-falls',1,'TCz..',NULL,'Accidental falls NOS'),('efi-falls',1,'TCz..00',NULL,'Accidental falls NOS');
INSERT INTO #codesreadv2
VALUES ('efi-housebound',1,'13CA.',NULL,'Housebound'),('efi-housebound',1,'13CA.00',NULL,'Housebound'),('efi-housebound',1,'8HL..',NULL,'Domiciliary visit received'),('efi-housebound',1,'8HL..00',NULL,'Domiciliary visit received'),('efi-housebound',1,'9N1C.',NULL,'Seen in own home'),('efi-housebound',1,'9N1C.00',NULL,'Seen in own home'),('efi-housebound',1,'9NF..',NULL,'Home visit admin'),('efi-housebound',1,'9NF..00',NULL,'Home visit admin'),('efi-housebound',1,'9NF1.',NULL,'Home visit request by patient'),('efi-housebound',1,'9NF1.00',NULL,'Home visit request by patient'),('efi-housebound',1,'9NF2.',NULL,'Home visit planned by doctor'),('efi-housebound',1,'9NF2.00',NULL,'Home visit planned by doctor'),('efi-housebound',1,'9NF3.',NULL,'Home visit request by relative'),('efi-housebound',1,'9NF3.00',NULL,'Home visit request by relative'),('efi-housebound',1,'9NF8.',NULL,'Acute home visit'),('efi-housebound',1,'9NF8.00',NULL,'Acute home visit'),('efi-housebound',1,'9NF9.',NULL,'Chronic home visit'),('efi-housebound',1,'9NF9.00',NULL,'Chronic home visit'),('efi-housebound',1,'9NFB.',NULL,'Home visit elderly assessment'),('efi-housebound',1,'9NFB.00',NULL,'Home visit elderly assessment'),('efi-housebound',1,'9NFM.',NULL,'Home visit planned by HCP'),('efi-housebound',1,'9NFM.00',NULL,'Home visit planned by HCP');
INSERT INTO #codesreadv2
VALUES ('efi-mobility-problems',1,'1381.',NULL,'Exercise physically impossible'),('efi-mobility-problems',1,'1381.00',NULL,'Exercise physically impossible'),('efi-mobility-problems',1,'13C2.',NULL,'Mobile outside with aid'),('efi-mobility-problems',1,'13C2.00',NULL,'Mobile outside with aid'),('efi-mobility-problems',1,'13C4.',NULL,'Needs walking aid in home'),('efi-mobility-problems',1,'13C4.00',NULL,'Needs walking aid in home'),('efi-mobility-problems',1,'13CD.',NULL,'Mobility very poor'),('efi-mobility-problems',1,'13CD.00',NULL,'Mobility very poor'),('efi-mobility-problems',1,'13CE.',NULL,'Mobility poor'),('efi-mobility-problems',1,'13CE.00',NULL,'Mobility poor'),('efi-mobility-problems',1,'398A.',NULL,'Depend on help push wheelchair'),('efi-mobility-problems',1,'398A.00',NULL,'Depend on help push wheelchair'),('efi-mobility-problems',1,'39B..',NULL,'Walking aid use'),('efi-mobility-problems',1,'39B..00',NULL,'Walking aid use'),('efi-mobility-problems',1,'8D4..',NULL,'Locomotory aid'),('efi-mobility-problems',1,'8D4..00',NULL,'Locomotory aid'),('efi-mobility-problems',1,'8O15.',NULL,'Provision of locomotory aid'),('efi-mobility-problems',1,'8O15.00',NULL,'Provision of locomotory aid'),('efi-mobility-problems',1,'N097.',NULL,'Difficulty in walking'),('efi-mobility-problems',1,'N097.00',NULL,'Difficulty in walking'),('efi-mobility-problems',1,'ZV4L0',NULL,'[V]Reduced mobility'),('efi-mobility-problems',1,'ZV4L000',NULL,'[V]Reduced mobility');
INSERT INTO #codesreadv2
VALUES ('efi-sleep-disturbance',1,'1B1B.',NULL,'Cannot sleep - insomnia'),('efi-sleep-disturbance',1,'1B1B.00',NULL,'Cannot sleep - insomnia'),('efi-sleep-disturbance',1,'1B1Q.',NULL,'Poor sleep pattern'),('efi-sleep-disturbance',1,'1B1Q.00',NULL,'Poor sleep pattern'),('efi-sleep-disturbance',1,'E274.',NULL,'Non-organic sleep disorders'),('efi-sleep-disturbance',1,'E274.00',NULL,'Non-organic sleep disorders'),('efi-sleep-disturbance',1,'Eu51.',NULL,'[X]Nonorganic sleep disorders'),('efi-sleep-disturbance',1,'Eu51.00',NULL,'[X]Nonorganic sleep disorders'),('efi-sleep-disturbance',1,'Fy02.',NULL,'Disorders/sleep-wake schedule'),('efi-sleep-disturbance',1,'Fy02.00',NULL,'Disorders/sleep-wake schedule'),('efi-sleep-disturbance',1,'R005.',NULL,'[D]Sleep disturbances'),('efi-sleep-disturbance',1,'R005.00',NULL,'[D]Sleep disturbances'),('efi-sleep-disturbance',1,'R0050',NULL,'[D]Sleep disturbance, unspecif'),('efi-sleep-disturbance',1,'R005000',NULL,'[D]Sleep disturbance, unspecif'),('efi-sleep-disturbance',1,'R0052',NULL,'[D]Insomnia NOS'),('efi-sleep-disturbance',1,'R005200',NULL,'[D]Insomnia NOS');
INSERT INTO #codesreadv2
VALUES ('efi-social-vulnerability',1,'1335.',NULL,'Widowed'),('efi-social-vulnerability',1,'1335.00',NULL,'Widowed'),('efi-social-vulnerability',1,'133P.',NULL,'Vulnerable adult'),('efi-social-vulnerability',1,'133P.00',NULL,'Vulnerable adult'),('efi-social-vulnerability',1,'133V.',NULL,'Widowed/surviving civil partnr'),('efi-social-vulnerability',1,'133V.00',NULL,'Widowed/surviving civil partnr'),('efi-social-vulnerability',1,'13EH.',NULL,'Housing problems'),('efi-social-vulnerability',1,'13EH.00',NULL,'Housing problems'),('efi-social-vulnerability',1,'13F3.',NULL,'Lives alone -no help available'),('efi-social-vulnerability',1,'13F3.00',NULL,'Lives alone -no help available'),('efi-social-vulnerability',1,'13G4.',NULL,'Social worker involved'),('efi-social-vulnerability',1,'13G4.00',NULL,'Social worker involved'),('efi-social-vulnerability',1,'13M1.',NULL,'Death of spouse'),('efi-social-vulnerability',1,'13M1.00',NULL,'Death of spouse'),('efi-social-vulnerability',1,'13MF.',NULL,'Death of partner'),('efi-social-vulnerability',1,'13MF.00',NULL,'Death of partner'),('efi-social-vulnerability',1,'13Z8.',NULL,'Social problem'),('efi-social-vulnerability',1,'13Z8.00',NULL,'Social problem'),('efi-social-vulnerability',1,'1B1K.',NULL,'Lonely'),('efi-social-vulnerability',1,'1B1K.00',NULL,'Lonely'),('efi-social-vulnerability',1,'8H75.',NULL,'Refer to social worker'),('efi-social-vulnerability',1,'8H75.00',NULL,'Refer to social worker'),('efi-social-vulnerability',1,'8HHB.',NULL,'Referral to Social Services'),('efi-social-vulnerability',1,'8HHB.00',NULL,'Referral to Social Services'),('efi-social-vulnerability',1,'8I5..',NULL,'Care/help refused by patient'),('efi-social-vulnerability',1,'8I5..00',NULL,'Care/help refused by patient'),('efi-social-vulnerability',1,'918V.',NULL,'Does not have a carer'),('efi-social-vulnerability',1,'918V.00',NULL,'Does not have a carer'),('efi-social-vulnerability',1,'9NNV.',NULL,'Under care of social services'),('efi-social-vulnerability',1,'9NNV.00',NULL,'Under care of social services'),('efi-social-vulnerability',1,'ZV603',NULL,'[V]Person living alone'),('efi-social-vulnerability',1,'ZV60300',NULL,'[V]Person living alone');
INSERT INTO #codesreadv2
VALUES ('efi-urinary-incontinence',1,'1593.',NULL,'H/O: stress incontinence'),('efi-urinary-incontinence',1,'1593.00',NULL,'H/O: stress incontinence'),('efi-urinary-incontinence',1,'16F..',NULL,'Double incontinence'),('efi-urinary-incontinence',1,'16F..00',NULL,'Double incontinence'),('efi-urinary-incontinence',1,'1A23.',NULL,'Incontinence of urine'),('efi-urinary-incontinence',1,'1A23.00',NULL,'Incontinence of urine'),('efi-urinary-incontinence',1,'1A24.',NULL,'Stress incontinence'),('efi-urinary-incontinence',1,'1A24.00',NULL,'Stress incontinence'),('efi-urinary-incontinence',1,'1A26.',NULL,'Urge incontinence of urine'),('efi-urinary-incontinence',1,'1A26.00',NULL,'Urge incontinence of urine'),('efi-urinary-incontinence',1,'3940.',NULL,'Bladder: incontinent'),('efi-urinary-incontinence',1,'3940.00',NULL,'Bladder: incontinent'),('efi-urinary-incontinence',1,'3941.',NULL,'Bladder: occasional accident'),('efi-urinary-incontinence',1,'3941.00',NULL,'Bladder: occasional accident'),('efi-urinary-incontinence',1,'7B338',NULL,'Ins ret dev str urin incon NEC'),('efi-urinary-incontinence',1,'7B33800',NULL,'Ins ret dev str urin incon NEC'),('efi-urinary-incontinence',1,'7B33C',NULL,'Ins ret de fe str urin inc NEC'),('efi-urinary-incontinence',1,'7B33C00',NULL,'Ins ret de fe str urin inc NEC'),('efi-urinary-incontinence',1,'7B421',NULL,'Insert bulbar ureth prosthesis'),('efi-urinary-incontinence',1,'7B42100',NULL,'Insert bulbar ureth prosthesis'),('efi-urinary-incontinence',1,'8D7..',NULL,'Urinary bladder control'),('efi-urinary-incontinence',1,'8D7..00',NULL,'Urinary bladder control'),('efi-urinary-incontinence',1,'8D71.',NULL,'Incontinence control'),('efi-urinary-incontinence',1,'8D71.00',NULL,'Incontinence control'),('efi-urinary-incontinence',1,'8HTX.',NULL,'Referral to incontinence clin'),('efi-urinary-incontinence',1,'8HTX.00',NULL,'Referral to incontinence clin'),('efi-urinary-incontinence',1,'K198.',NULL,'Stress incontinence'),('efi-urinary-incontinence',1,'K198.00',NULL,'Stress incontinence'),('efi-urinary-incontinence',1,'K586.',NULL,'Stress incontinence - female'),('efi-urinary-incontinence',1,'K586.00',NULL,'Stress incontinence - female'),('efi-urinary-incontinence',1,'Kyu5A',NULL,'[X]Oth spcf urinary incontince'),('efi-urinary-incontinence',1,'Kyu5A00',NULL,'[X]Oth spcf urinary incontince'),('efi-urinary-incontinence',1,'R083.',NULL,'[D]Incontinence of urine'),('efi-urinary-incontinence',1,'R083.00',NULL,'[D]Incontinence of urine'),('efi-urinary-incontinence',1,'R0831',NULL,'[D]Urethral sphinct.incontin.'),('efi-urinary-incontinence',1,'R083100',NULL,'[D]Urethral sphinct.incontin.'),('efi-urinary-incontinence',1,'R0832',NULL,'[D] Urge incontinence'),('efi-urinary-incontinence',1,'R083200',NULL,'[D] Urge incontinence'),('efi-urinary-incontinence',1,'R083z',NULL,'[D]Incontinence of urine NOS'),('efi-urinary-incontinence',1,'R083z00',NULL,'[D]Incontinence of urine NOS');
INSERT INTO #codesreadv2
VALUES ('efi-weight-loss',1,'1612.',NULL,'Appetite loss - anorexia'),('efi-weight-loss',1,'1612.00',NULL,'Appetite loss - anorexia'),('efi-weight-loss',1,'1615.',NULL,'Reduced appetite'),('efi-weight-loss',1,'1615.00',NULL,'Reduced appetite'),('efi-weight-loss',1,'1623.',NULL,'Weight decreasing'),('efi-weight-loss',1,'1623.00',NULL,'Weight decreasing'),('efi-weight-loss',1,'1625.',NULL,'Abnormal weight loss'),('efi-weight-loss',1,'1625.00',NULL,'Abnormal weight loss'),('efi-weight-loss',1,'1D1A.',NULL,'Complaining of weight loss'),('efi-weight-loss',1,'1D1A.00',NULL,'Complaining of weight loss'),('efi-weight-loss',1,'22A8.',NULL,'Weight loss frm baselne weight'),('efi-weight-loss',1,'22A8.00',NULL,'Weight loss frm baselne weight'),('efi-weight-loss',1,'R0300',NULL,'[D]Appetite loss'),('efi-weight-loss',1,'R030000',NULL,'[D]Appetite loss'),('efi-weight-loss',1,'R032.',NULL,'[D]Abnormal loss of weight'),('efi-weight-loss',1,'R032.00',NULL,'[D]Abnormal loss of weight')

INSERT INTO #AllCodes
SELECT [concept], [version], [code], [description] from #codesreadv2;

IF OBJECT_ID('tempdb..#codesctv3') IS NOT NULL DROP TABLE #codesctv3;
CREATE TABLE #codesctv3 (
  [concept] [varchar](255) NOT NULL,
  [version] INT NOT NULL,
	[code] [varchar](20) COLLATE Latin1_General_CS_AS NOT NULL,
	[term] [varchar](20) COLLATE Latin1_General_CS_AS NULL,
	[description] [varchar](255) NULL
) ON [PRIMARY];

INSERT INTO #codesctv3
VALUES ('efi-arthritis',1,'XE1DV',NULL,'Osteoarthritis'),('efi-arthritis',1,'N040.',NULL,'Rheumatoid arthritis'),('efi-arthritis',1,'14G1.',NULL,'H/O: rheumatoid arthritis'),('efi-arthritis',1,'X701i',NULL,'Seronegative rheumatoid arthritis'),('efi-arthritis',1,'XaN2K',NULL,'Disease activity score in rheumatoid arthritis'),('efi-arthritis',1,'X701h',NULL,'Seropositive rheumatoid arthritis'),('efi-arthritis',1,'N040T',NULL,'Flare of rheumatoid arthritis'),('efi-arthritis',1,'Nyu1G',NULL,'[X]Seropositive rheumatoid arthritis, unspecified'),('efi-arthritis',1,'Xa3gL',NULL,'Rheumatoid arthritis - multiple joint'),('efi-arthritis',1,'Xa3gP',NULL,'Rheumatoid arthritis NOS'),('efi-arthritis',1,'XM1XV',NULL,'Rheumatoid arthritis monitoring'),('efi-arthritis',1,'N04..',NULL,'Inflamm polyarthropathy: (& [rheumatoid arthrit] or [other])'),('efi-arthritis',1,'N040D',NULL,'Rheumatoid arthritis of knee'),('efi-arthritis',1,'XaBMO',NULL,'Seropositive errosive rheumatoid arthritis'),('efi-arthritis',1,'XE1DU',NULL,'Rheumatoid arthritis and other inflammatory polyarthropathy'),('efi-arthritis',1,'N0407',NULL,'Rheumatoid arthritis of wrist'),('efi-arthritis',1,'N0506',NULL,'Erosive osteoarthrosis'),('efi-arthritis',1,'Xa3gM',NULL,'Rheumatoid arthritis - hand joint'),('efi-arthritis',1,'N040B',NULL,'Rheumatoid arthritis of hip'),('efi-arthritis',1,'X7038',NULL,'Idiopathic osteoarthritis'),('efi-arthritis',1,'N0402',NULL,'Rheumatoid arthritis of shoulder'),('efi-arthritis',1,'N0405',NULL,'Rheumatoid arthritis of elbow'),('efi-arthritis',1,'N0408',NULL,'Rheumatoid arthritis of metacarpophalangeal joint'),('efi-arthritis',1,'Xa3gN',NULL,'Rheumatoid arthritis - ankle/foot'),('efi-arthritis',1,'N0400',NULL,'Rheumatoid arthritis of cervical spine'),('efi-arthritis',1,'Nyu11',NULL,'[X]Other seropositive rheumatoid arthritis'),('efi-arthritis',1,'N0401',NULL,'Other rheumatoid arthritis of spine'),('efi-arthritis',1,'N040A',NULL,'Rheumatoid arthritis of DIP joint of finger'),('efi-arthritis',1,'N0409',NULL,'Rheumatoid arthritis of PIP joint of finger'),('efi-arthritis',1,'N040F',NULL,'Rheumatoid arthritis of ankle'),('efi-arthritis',1,'N0404',NULL,'Rheumatoid arthritis of acromioclavicular joint'),('efi-arthritis',1,'N040L',NULL,'Rheumatoid arthritis of lesser metatarsophalangeal joint'),('efi-arthritis',1,'N040C',NULL,'Rheumatoid arthritis of sacroiliac joint'),('efi-arthritis',1,'N040G',NULL,'Rheumatoid arthritis of subtalar joint'),('efi-arthritis',1,'Nyu12',NULL,'[X]Other specified rheumatoid arthritis'),('efi-arthritis',1,'X701m',NULL,'Rheumatoid arthritis with multisystem involvement'),('efi-arthritis',1,'N040H',NULL,'Rheumatoid arthritis of talonavicular joint'),('efi-arthritis',1,'N040K',NULL,'Rheumatoid arthritis of first metatarsophalangeal joint'),('efi-arthritis',1,'N040M',NULL,'Rheumatoid arthritis of interphalangeal joint of toe'),('efi-arthritis',1,'N040J',NULL,'Rheumatoid arthritis of other tarsal joint'),('efi-arthritis',1,'Nyu10',NULL,'[X]Rheumatoid arthritis+involvement/other organs or systems'),('efi-arthritis',1,'N0310',NULL,'Arthropathy in ulcerative colitis'),('efi-arthritis',1,'N05zL',NULL,'Osteoarthritis NOS, of knee'),('efi-arthritis',1,'C34z.',NULL,'Gout NOS'),('efi-arthritis',1,'N05zJ',NULL,'Osteoarthritis NOS, of hip'),('efi-arthritis',1,'X703L',NULL,'Osteoarthritis of knee'),('efi-arthritis',1,'N05..',NULL,'Osteoarthritis (& [allied disorders])'),('efi-arthritis',1,'N050.',NULL,'Generalised osteoarthritis'),('efi-arthritis',1,'X703K',NULL,'Osteoarthritis of hip'),('efi-arthritis',1,'14G2.',NULL,'H/O: osteoarthritis'),('efi-arthritis',1,'XM0u9',NULL,'Arthritis/arthrosis'),('efi-arthritis',1,'52A71',NULL,'Plain X-ray knee abnormal'),('efi-arthritis',1,'N0502',NULL,'Generalised osteoarthritis of multiple sites'),('efi-arthritis',1,'N05z1',NULL,'Osteoarthritis NOS, of shoulder region'),('efi-arthritis',1,'N05z6',NULL,'Osteoarthritis NOS: [lower leg] or [knee]'),('efi-arthritis',1,'52A31',NULL,'Plain X-ray hip joint abnormal'),('efi-arthritis',1,'X703B',NULL,'Osteoarthritis of shoulder joint'),('efi-arthritis',1,'X7006',NULL,'Knee arthritis NOS'),('efi-arthritis',1,'N05z9',NULL,'Osteoarthritis NOS, of shoulder'),('efi-arthritis',1,'X7007',NULL,'Hip arthritis NOS'),('efi-arthritis',1,'XE1Dd',NULL,'Osteoarthritis NOS, of the hand'),('efi-arthritis',1,'N023.',NULL,'Gouty arthritis'),('efi-arthritis',1,'XM0Ai',NULL,'Inflammatory arthritis'),('efi-arthritis',1,'Y8080',NULL,'Osteoarthritis - knee joint'),('efi-arthritis',1,'Xa3gQ',NULL,'Osteoarthritis - hand joint'),('efi-arthritis',1,'C340.',NULL,'Gouty arthropathy'),('efi-arthritis',1,'XE08w',NULL,'Total prosthetic replacement of knee joint using cement'),('efi-arthritis',1,'XE090',NULL,'Other total prosthetic replacement of knee joint'),('efi-arthritis',1,'7K30.',NULL,'Cemented knee arthroplasty (& total (& named variants))'),('efi-arthritis',1,'XM1RU',NULL,'H/O: arthritis'),('efi-arthritis',1,'Xa87F',NULL,'Injection of steroid into knee joint'),('efi-arthritis',1,'7K3..',NULL,'Knee joint operations'),('efi-arthritis',1,'7K6Z3',NULL,'Injection into joint NEC'),('efi-arthritis',1,'N06z.',NULL,'(Arthropathy NOS) or (arthritis)'),('efi-arthritis',1,'N11..',NULL,'(Spondyl & allied dis) or (arthr spine) or (osteoarth spine)'),('efi-arthritis',1,'X00OE',NULL,'Injection into joint');
INSERT INTO #codesctv3
VALUES ('efi-atrial-fibrillation',1,'G5730',NULL,'Atrial fibrillation'),('efi-atrial-fibrillation',1,'3272.',NULL,'ECG: atrial fibrillation'),('efi-atrial-fibrillation',1,'XaIIT',NULL,'Atrial fibrillation monitoring'),('efi-atrial-fibrillation',1,'Xa2E8',NULL,'Paroxysmal atrial fibrillation'),('efi-atrial-fibrillation',1,'G573.',NULL,'Atrial fibrillation and flutter'),('efi-atrial-fibrillation',1,'XaDv6',NULL,'H/O: atrial fibrillation'),('efi-atrial-fibrillation',1,'G573z',NULL,'Atrial fibrillation and flutter NOS'),('efi-atrial-fibrillation',1,'XaMGD',NULL,'Atrial fibrillation annual review'),('efi-atrial-fibrillation',1,'XaEga',NULL,'Rapid atrial fibrillation'),('efi-atrial-fibrillation',1,'Xa7nI',NULL,'Controlled atrial fibrillation'),('efi-atrial-fibrillation',1,'XaOfa',NULL,'Persistent atrial fibrillation'),('efi-atrial-fibrillation',1,'XaOft',NULL,'Permanent atrial fibrillation'),('efi-atrial-fibrillation',1,'X202R',NULL,'Lone atrial fibrillation'),('efi-atrial-fibrillation',1,'XE0Wk',NULL,'(Atrial fibrillation) or (atrial flutter)'),('efi-atrial-fibrillation',1,'X202S',NULL,'Non-rheumatic atrial fibrillation'),('efi-atrial-fibrillation',1,'XaMDH',NULL,'Atrial fibrillation monitoring second letter'),('efi-atrial-fibrillation',1,'7936A',NULL,'Implant intravenous pacemaker for atrial fibrillation'),('efi-atrial-fibrillation',1,'XaLFi',NULL,'Except from atr fib quality indicators: Patient unsuitable'),('efi-atrial-fibrillation',1,'XaLFj',NULL,'Excepted from atrial fibrillation qual indic: Inform dissent'),('efi-atrial-fibrillation',1,'3272.',NULL,'ECG: atrial fibrillation'),('efi-atrial-fibrillation',1,'2432.',NULL,'O/E - pulse irregularly irreg.'),('efi-atrial-fibrillation',1,'G5731',NULL,'Atrial flutter'),('efi-atrial-fibrillation',1,'3273.',NULL,'ECG: atrial flutter');
INSERT INTO #codesctv3
VALUES ('efi-chd',1,'G33..',NULL,'Angina'),('efi-chd',1,'XE0Uh',NULL,'Acute myocardial infarction'),('efi-chd',1,'14A5.',NULL,'H/O: angina pectoris'),('efi-chd',1,'G33z.',NULL,'Angina pectoris NOS'),('efi-chd',1,'G3...',NULL,'Ischaemic heart disease (& [arteriosclerotic])'),('efi-chd',1,'G30z.',NULL,'Acute myocardial infarction NOS'),('efi-chd',1,'G3z..',NULL,'Ischaemic heart disease NOS'),('efi-chd',1,'G30..',NULL,'(Myocard inf (& [ac][silent][card rupt])) or (coron thromb)'),('efi-chd',1,'G340.',NULL,'Coronary (atheroscl or artery dis) or triple vess dis heart'),('efi-chd',1,'Ua1eH',NULL,'Ischaemic chest pain'),('efi-chd',1,'X200C',NULL,'Myocardial ischaemia'),('efi-chd',1,'3222.',NULL,'ECG:shows myocardial ischaemia'),('efi-chd',1,'G3y..',NULL,'Other specified ischaemic heart disease'),('efi-chd',1,'322..',NULL,'ECG: myocardial ischaemia'),('efi-chd',1,'XM0rN',NULL,'Coronary atherosclerosis'),('efi-chd',1,'X200B',NULL,'Coronary spasm'),('efi-chd',1,'14A..',NULL,'H/O: cardiovasc disease (& [heart disord][myocard problem])'),('efi-chd',1,'G30y.',NULL,'Other acute myocardial infarction'),('efi-chd',1,'G34y1',NULL,'Chronic myocardial ischaemia'),('efi-chd',1,'X200D',NULL,'Silent myocardial ischaemia'),('efi-chd',1,'XE0WC',NULL,'Acute/subacute ischaemic heart disease NOS'),('efi-chd',1,'322Z.',NULL,'ECG: myocardial ischaemia NOS'),('efi-chd',1,'G34z.',NULL,'Other chronic ischaemic heart disease NOS'),('efi-chd',1,'XE0WG',NULL,'Chronic ischaemic heart disease NOS'),('efi-chd',1,'Gyu30',NULL,'[X]Other forms of angina pectoris'),('efi-chd',1,'G31y2',NULL,'Subendocardial ischaemia'),('efi-chd',1,'G30yz',NULL,'Other acute myocardial infarction NOS'),('efi-chd',1,'XaNxN',NULL,'Admit ischaemic heart disease emergency'),('efi-chd',1,'G31yz',NULL,'Other acute and subacute ischaemic heart disease NOS'),('efi-chd',1,'XE0WA',NULL,'Myocardial infarction (& [acute]) or coronary thrombosis'),('efi-chd',1,'G36..',NULL,'Certain current complication follow acute myocardial infarct'),('efi-chd',1,'G361.',NULL,'Atrial septal defect/curr comp folow acut myocardal infarct'),('efi-chd',1,'G34yz',NULL,'Other specified chronic ischaemic heart disease NOS'),('efi-chd',1,'bl...',NULL,'Vasodilators used in angina pectoris'),('efi-chd',1,'XaFx7',NULL,'Diab mellit insulin-glucose infus acute myocardial infarct'),('efi-chd',1,'X200d',NULL,'Post-infarction ventricular septal defect'),('efi-chd',1,'X200c',NULL,'Cardiac syndrome X'),('efi-chd',1,'X75rV',NULL,'Crushing chest pain'),('efi-chd',1,'Xa0wX',NULL,'Central crushing chest pain'),('efi-chd',1,'XaNMH',NULL,'Cardiovascular disease annual review declined'),('efi-chd',1,'XaFsH',NULL,'Transient myocardial ischaemia'),('efi-chd',1,'XE2uV',NULL,'Ischaemic heart disease'),('efi-chd',1,'XaI9h',NULL,'Coronary heart disease annual review'),('efi-chd',1,'662K0',NULL,'Angina control - good'),('efi-chd',1,'X2009',NULL,'Unstable angina'),('efi-chd',1,'7928.',NULL,'Percutaneous balloon angioplasty of coronary artery'),('efi-chd',1,'X2006',NULL,'Triple vessel disease of the heart'),('efi-chd',1,'G308.',NULL,'Inferior myocardial infarction NOS'),('efi-chd',1,'X2008',NULL,'Stable angina'),('efi-chd',1,'Y3657',NULL,'H/O: Ischaemic heart disease'),('efi-chd',1,'662K3',NULL,'Angina control - worsening'),('efi-chd',1,'X00tU',NULL,'Insertion of coronary artery stent'),('efi-chd',1,'662K1',NULL,'Angina control - poor'),('efi-chd',1,'Xa7nH',NULL,'Exercise-induced angina'),('efi-chd',1,'X200E',NULL,'Myocardial infarction'),('efi-chd',1,'XaIwY',NULL,'Acute non-ST segment elevation myocardial infarction'),('efi-chd',1,'X00tE',NULL,'Coronary artery bypass grafting'),('efi-chd',1,'792..',NULL,'Coronary artery operations (& bypass)'),('efi-chd',1,'14A4.',NULL,'H/O: myocardial infarct at greater than 60'),('efi-chd',1,'Y6999',NULL,'H/O: myocardial infarct >60'),('efi-chd',1,'XE2aA',NULL,'Old myocardial infarction'),('efi-chd',1,'XaIOW',NULL,'Coronary heart disease review');
INSERT INTO #codesctv3
VALUES ('efi-ckd',1,'C1090',NULL,'Type II diabetes mellitus with renal complications'),('efi-ckd',1,'XaIzR',NULL,'Type II diabetes mellitus with persistent microalbuminuria'),('efi-ckd',1,'XaF05',NULL,'Type II diabetes mellitus with nephropathy'),('efi-ckd',1,'XaIzQ',NULL,'Type II diabetes mellitus with persistent proteinuria'),('efi-ckd',1,'XE10G',NULL,'Diabetes mellitus with renal manifestation'),('efi-ckd',1,'C104.',NULL,'Diabetes mellitus: [with renal manifestatn] or [nephropathy]'),('efi-ckd',1,'C1093',NULL,'Type II diabetes mellitus with multiple complications'),('efi-ckd',1,'XaIzM',NULL,'Type 1 diabetes mellitus with persistent proteinuria'),('efi-ckd',1,'C1080',NULL,'Type I diabetes mellitus with renal complications'),('efi-ckd',1,'XaIz0',NULL,'Diabetes mellitus with persistent proteinuria'),('efi-ckd',1,'XaIyz',NULL,'Diabetes mellitus with persistent microalbuminuria'),('efi-ckd',1,'XaF04',NULL,'Type I diabetes mellitus with nephropathy'),('efi-ckd',1,'C104z',NULL,'Diabetes mellitus with nephropathy NOS'),('efi-ckd',1,'XaIzN',NULL,'Type 1 diabetes mellitus with persistent microalbuminuria'),('efi-ckd',1,'C104y',NULL,'Other specified diabetes mellitus with renal complications'),('efi-ckd',1,'Cyu23',NULL,'[X]Unspecified diabetes mellitus with renal complications'),('efi-ckd',1,'K05..',NULL,'Renal failure: [chronic] or [end stage]'),('efi-ckd',1,'PD13.',NULL,'Multicystic kidney'),('efi-ckd',1,'X30In',NULL,'Chronic renal impairment'),('efi-ckd',1,'XaLHI',NULL,'Chronic kidney disease stage 3'),('efi-ckd',1,'XaLHJ',NULL,'Chronic kidney disease stage 4'),('efi-ckd',1,'XaLHK',NULL,'Chronic kidney disease stage 5'),('efi-ckd',1,'XaNbn',NULL,'Chronic kidney disease stage 3A'),('efi-ckd',1,'XaNbo',NULL,'Chronic kidney disease stage 3B'),('efi-ckd',1,'XaO3t',NULL,'Chronic kidney disease stage 3 with proteinuria'),('efi-ckd',1,'XaO3u',NULL,'Chronic kidney disease stage 3 without proteinuria'),('efi-ckd',1,'XaO3v',NULL,'Chronic kidney disease stage 3A with proteinuria'),('efi-ckd',1,'XaO3w',NULL,'Chronic kidney disease stage 3A without proteinuria'),('efi-ckd',1,'XaO3x',NULL,'Chronic kidney disease stage 3B with proteinuria'),('efi-ckd',1,'XaO3y',NULL,'Chronic kidney disease stage 3B without proteinuria'),('efi-ckd',1,'XaO3z',NULL,'Chronic kidney disease stage 4 with proteinuria'),('efi-ckd',1,'XaO40',NULL,'Chronic kidney disease stage 4 without proteinuria'),('efi-ckd',1,'XaO41',NULL,'Chronic kidney disease stage 5 with proteinuria'),('efi-ckd',1,'XaO42',NULL,'Chronic kidney disease stage 5 without proteinuria'),('efi-ckd',1,'XaXTz',NULL,'H/O: chronic kidney disease'),('efi-ckd',1,'XaLHI',NULL,'Chronic kidney disease stage 3'),('efi-ckd',1,'XaNbn',NULL,'Chronic kidney disease stage 3A'),('efi-ckd',1,'4677.',NULL,'Urine protein test = ++++'),('efi-ckd',1,'X30In',NULL,'Chronic renal impairment'),('efi-ckd',1,'XaNbo',NULL,'Chronic kidney disease stage 3B'),('efi-ckd',1,'XaO3t',NULL,'Chronic kidney disease stage 3 with proteinuria'),('efi-ckd',1,'XaO3y',NULL,'Chronic kidney disease stage 3B without proteinuria'),('efi-ckd',1,'R110.',NULL,'[D]Proteinuria'),('efi-ckd',1,'XaO3u',NULL,'Chronic kidney disease stage 3 without proteinuria'),('efi-ckd',1,'XaMGE',NULL,'Chronic kidney disease annual review'),('efi-ckd',1,'XaO3w',NULL,'Chronic kidney disease stage 3A without proteinuria'),('efi-ckd',1,'XaLHJ',NULL,'Chronic kidney disease stage 4'),('efi-ckd',1,'XaLFm',NULL,'Except chronic kidney disease qual indic: Patient unsuitable'),('efi-ckd',1,'XaLFn',NULL,'Exc chronic kidney disease quality indicators: Inform dissen');
INSERT INTO #codesctv3
VALUES ('efi-diabetes',1,'X40J5',NULL,'Type II diabetes mellitus'),('efi-diabetes',1,'XaIIj',NULL,'Diabetic retinopathy screening'),('efi-diabetes',1,'XaIyt',NULL,'Diabetic peripheral neuropathy screening'),('efi-diabetes',1,'F4200',NULL,'Background diabetic retinopathy'),('efi-diabetes',1,'F420.',NULL,'Diabetic retinopathy'),('efi-diabetes',1,'XaJLa',NULL,'Diabetic retinopathy 12 month review'),('efi-diabetes',1,'XaMFF',NULL,'Referral for diabetic retinopathy screening'),('efi-diabetes',1,'XaIP5',NULL,'Non proliferative diabetic retinopathy'),('efi-diabetes',1,'XaE5T',NULL,'Mild non proliferative diabetic retinopathy'),('efi-diabetes',1,'XaJOj',NULL,'O/E - left eye preproliferative diabetic retinopathy'),('efi-diabetes',1,'XaJOi',NULL,'O/E - right eye preproliferative diabetic retinopathy'),('efi-diabetes',1,'XaIeK',NULL,'O/E - Left diabetic foot - ulcerated'),('efi-diabetes',1,'M2710',NULL,'Ischaemic ulcer diabetic foot'),('efi-diabetes',1,'XaJOk',NULL,'O/E - right eye proliferative diabetic retinopathy'),('efi-diabetes',1,'XaJLb',NULL,'Diabetic retinopathy 6 month review'),('efi-diabetes',1,'C101.',NULL,'Diabetic ketoacidosis'),('efi-diabetes',1,'C1097',NULL,'Type II diabetes mellitus - poor control'),('efi-diabetes',1,'XaELQ',NULL,'Type II diabetes mellitus without complication'),('efi-diabetes',1,'C106.',NULL,'Diab mell + neuro manif: (& [amyotroph][neurop][polyneurop])'),('efi-diabetes',1,'XE10I',NULL,'Diabetes mellitus with peripheral circulatory disorder'),('efi-diabetes',1,'C1090',NULL,'Type II diabetes mellitus with renal complications'),('efi-diabetes',1,'XaIzR',NULL,'Type II diabetes mellitus with persistent microalbuminuria'),('efi-diabetes',1,'XE10H',NULL,'Diabetes mellitus with neurological manifestation'),('efi-diabetes',1,'XaXZR',NULL,'H/O: diabetes mellitus type 2'),('efi-diabetes',1,'F3721',NULL,'Chronic painful diabetic neuropathy'),('efi-diabetes',1,'XaF05',NULL,'Type II diabetes mellitus with nephropathy'),('efi-diabetes',1,'XaIzQ',NULL,'Type II diabetes mellitus with persistent proteinuria'),('efi-diabetes',1,'F4640',NULL,'Diabetic cataract'),('efi-diabetes',1,'C105.',NULL,'Diabetes mellitus with ophthalmic manifestation'),('efi-diabetes',1,'C1088',NULL,'Type I diabetes mellitus - poor control'),('efi-diabetes',1,'C101z',NULL,'Diabetes mellitus NOS with ketoacidosis'),('efi-diabetes',1,'C100.',NULL,'Diabetes mellitus with no mention of complication'),('efi-diabetes',1,'XaE5U',NULL,'Moderate non proliferative diabetic retinopathy'),('efi-diabetes',1,'F3722',NULL,'Asymptomatic diabetic neuropathy'),('efi-diabetes',1,'XaE5c',NULL,'Diabetic macular oedema'),('efi-diabetes',1,'F1711',NULL,'Diabetic autonomic neuropathy'),('efi-diabetes',1,'XaE5V',NULL,'Severe non proliferative diabetic retinopathy'),('efi-diabetes',1,'XE10G',NULL,'Diabetes mellitus with renal manifestation'),('efi-diabetes',1,'F3720',NULL,'Acute painful diabetic neuropathy'),('efi-diabetes',1,'F372.',NULL,'Diabetic neuropathy &/or diabetic polyneuropathy'),('efi-diabetes',1,'C104.',NULL,'Diabetes mellitus: [with renal manifestatn] or [nephropathy]'),('efi-diabetes',1,'C1093',NULL,'Type II diabetes mellitus with multiple complications'),('efi-diabetes',1,'XE15k',NULL,'Diabetic polyneuropathy'),('efi-diabetes',1,'C1096',NULL,'Type II diabetes mellitus with retinopathy'),('efi-diabetes',1,'C1091',NULL,'Type II diabetes mellitus with ophthalmic complications'),('efi-diabetes',1,'C1089',NULL,'Type I diabetes mellitus maturity onset'),('efi-diabetes',1,'XaIzM',NULL,'Type 1 diabetes mellitus with persistent proteinuria'),('efi-diabetes',1,'C1010',NULL,'Type 1 diabetes mellitus with ketoacidosis'),('efi-diabetes',1,'XaFn7',NULL,'Type II diabetes mellitus with peripheral angiopathy'),('efi-diabetes',1,'XaELP',NULL,'Type I diabetes mellitus without complication'),('efi-diabetes',1,'C1092',NULL,'Type II diabetes mellitus with neurological complications'),('efi-diabetes',1,'XaXbW',NULL,'Symptomatic diabetic peripheral neuropathy'),('efi-diabetes',1,'C1080',NULL,'Type I diabetes mellitus with renal complications'),('efi-diabetes',1,'C1011',NULL,'Type 2 diabetes mellitus with ketoacidosis'),('efi-diabetes',1,'XaXZv',NULL,'H/O: diabetes mellitus type 1'),('efi-diabetes',1,'XaIz0',NULL,'Diabetes mellitus with persistent proteinuria'),('efi-diabetes',1,'X00Aj',NULL,'Diabetic chronic painful polyneuropathy'),('efi-diabetes',1,'C1087',NULL,'Type I diabetes mellitus with retinopathy'),('efi-diabetes',1,'XE12I',NULL,'Diabetes + neuropathy (& [amyotrophy])'),('efi-diabetes',1,'XaIyz',NULL,'Diabetes mellitus with persistent microalbuminuria'),('efi-diabetes',1,'C1082',NULL,'Type I diabetes mellitus with neurological complications'),('efi-diabetes',1,'C1081',NULL,'Type I diabetes mellitus with ophthalmic complications'),('efi-diabetes',1,'C1083',NULL,'Type I diabetes mellitus with multiple complications'),('efi-diabetes',1,'XaF04',NULL,'Type I diabetes mellitus with nephropathy'),('efi-diabetes',1,'C107.',NULL,'Diabetes mellitus with: [gangrene] or [periph circul disord]'),('efi-diabetes',1,'C104z',NULL,'Diabetes mellitus with nephropathy NOS'),('efi-diabetes',1,'XaFmA',NULL,'Type II diabetes mellitus with diabetic cataract'),('efi-diabetes',1,'XE12A',NULL,'Diabetes mellitus: [adult onset] or [noninsulin dependent]'),('efi-diabetes',1,'X40JY',NULL,'Insulin-dependent diabetes mellitus secretory diarrhoea synd'),('efi-diabetes',1,'X00Al',NULL,'Diabetic mononeuropathy'),('efi-diabetes',1,'C100z',NULL,'Diabetes mellitus NOS with no mention of complication'),('efi-diabetes',1,'XaIzN',NULL,'Type 1 diabetes mellitus with persistent microalbuminuria'),('efi-diabetes',1,'XaEnq',NULL,'Type II diabetes mellitus with polyneuropathy'),('efi-diabetes',1,'f8...',NULL,'Diabetic neuropathy treatment [no drugs here]'),('efi-diabetes',1,'C106z',NULL,'Diabetes mellitus NOS with neurological manifestation'),('efi-diabetes',1,'C1061',NULL,'Diabetes mellitus, adult onset, + neurological manifestation'),('efi-diabetes',1,'X40JI',NULL,'Diabetes mellitus autosomal dominant'),('efi-diabetes',1,'XaFWG',NULL,'Type I diabetes mellitus with hypoglycaemic coma'),('efi-diabetes',1,'C103.',NULL,'Diabetes mellitus with ketoacidotic coma'),('efi-diabetes',1,'XE128',NULL,'Diabetes mellitus (& [ketoacidosis])'),('efi-diabetes',1,'C10zz',NULL,'Diabetes mellitus NOS with unspecified complication'),('efi-diabetes',1,'XaKyW',NULL,'Type 1 diabetes mellitus with gastroparesis'),('efi-diabetes',1,'XaKyX',NULL,'Type II diabetes mellitus with gastroparesis'),('efi-diabetes',1,'X40JJ',NULL,'Diabetes mellitus autosomal dominant type 2'),('efi-diabetes',1,'C10z.',NULL,'Diabetes mellitus with unspecified complication'),('efi-diabetes',1,'C106y',NULL,'Other specified diabetes mellitus with neurological comps'),('efi-diabetes',1,'C107z',NULL,'Diabetes mellitus NOS with peripheral circulatory disorder'),('efi-diabetes',1,'XaFn8',NULL,'Type II diabetes mellitus with arthropathy'),('efi-diabetes',1,'C1030',NULL,'Type 1 diabetes mellitus with ketoacidotic coma'),('efi-diabetes',1,'C102.',NULL,'Diabetes mellitus with hyperosmolar coma'),('efi-diabetes',1,'C101y',NULL,'Other specified diabetes mellitus with ketoacidosis'),('efi-diabetes',1,'XaEnp',NULL,'Type II diabetes mellitus with mononeuropathy'),('efi-diabetes',1,'XaEnq',NULL,'Type II diabetes mellitus with polyneuropathy'),('efi-diabetes',1,'Xa0lK',NULL,'Diabetic (femoral mononeuropathy) & (Diabetic amyotrophy)'),('efi-diabetes',1,'XaFn9',NULL,'Type II diabetes mellitus with neuropathic arthropathy'),('efi-diabetes',1,'XaFWI',NULL,'Type II diabetes mellitus with hypoglycaemic coma'),('efi-diabetes',1,'XaOPu',NULL,'Latent autoimmune diabetes mellitus in adult'),('efi-diabetes',1,'C10y.',NULL,'Diabetes mellitus with other specified manifestation'),('efi-diabetes',1,'X00Ai',NULL,'Diabetic acute painful polyneuropathy'),('efi-diabetes',1,'X00Ah',NULL,'Diabetic distal sensorimotor polyneuropathy'),('efi-diabetes',1,'C1031',NULL,'Type II diabetes mellitus with ketoacidotic coma'),('efi-diabetes',1,'C103y',NULL,'Other specified diabetes mellitus with coma'),('efi-diabetes',1,'C108y',NULL,'Other specified diabetes mellitus with multiple comps'),('efi-diabetes',1,'C10A1',NULL,'Malnutrition-related diabetes mellitus with ketoacidosis'),('efi-diabetes',1,'Cyu23',NULL,'[X]Unspecified diabetes mellitus with renal complications'),('efi-diabetes',1,'C10yy',NULL,'Other specified diabetes mellitus with other spec comps'),('efi-diabetes',1,'C108z',NULL,'Unspecified diabetes mellitus with multiple complications'),('efi-diabetes',1,'F420z',NULL,'Diabetic retinopathy NOS'),('efi-diabetes',1,'C102z',NULL,'Diabetes mellitus NOS with hyperosmolar coma'),('efi-diabetes',1,'XaFmM',NULL,'Type I diabetes mellitus with neuropathic arthropathy'),('efi-diabetes',1,'C10B0',NULL,'Steroid-induced diabetes mellitus without complication'),('efi-diabetes',1,'XaJUI',NULL,'Diabetes mellitus induced by non-steroid drugs'),('efi-diabetes',1,'C1087',NULL,'Type I diabetes mellitus with retinopathy'),('efi-diabetes',1,'C107.',NULL,'Diabetes mellitus with: [gangrene] or [periph circul disord]'),('efi-diabetes',1,'XE12G',NULL,'Diabetes + eye manifestation (& [cataract] or [retinopathy])'),('efi-diabetes',1,'XM1Qx',NULL,'Diabetes mellitus with gangrene'),('efi-diabetes',1,'C1086',NULL,'Type I diabetes mellitus with gangrene'),('efi-diabetes',1,'C1095',NULL,'Type II diabetes mellitus with gangrene'),('efi-diabetes',1,'XaJQp',NULL,'Type II diabetes mellitus with exudative maculopathy'),('efi-diabetes',1,'XaJSr',NULL,'Type 1 diabetes mellitus with exudative maculopathy'),('efi-diabetes',1,'C1085',NULL,'Type I diabetes mellitus with ulcer'),('efi-diabetes',1,'C1094',NULL,'Type II diabetes mellitus with ulcer'),('efi-diabetes',1,'C104y',NULL,'Other specified diabetes mellitus with renal complications'),('efi-diabetes',1,'XaFm8',NULL,'Type I diabetes mellitus with diabetic cataract'),('efi-diabetes',1,'XaEnn',NULL,'Type I diabetes mellitus with mononeuropathy'),
('efi-diabetes',1,'XaEno',NULL,'Type I diabetes mellitus with polyneuropathy'),('efi-diabetes',1,'C105y',NULL,'Other specified diabetes mellitus with ophthalmic complicatn'),('efi-diabetes',1,'C105z',NULL,'Diabetes mellitus NOS with ophthalmic manifestation'),('efi-diabetes',1,'C1086',NULL,'Type I diabetes mellitus with gangrene'),('efi-diabetes',1,'C10..',NULL,'Diabetes mellitus'),('efi-diabetes',1,'66AS.',NULL,'Diabetic annual review'),('efi-diabetes',1,'66A..',NULL,'Diabetic monitoring'),('efi-diabetes',1,'66A4.',NULL,'Diabetic on oral treatment'),('efi-diabetes',1,'XaJO9',NULL,'Under care of diabetic foot screener'),('efi-diabetes',1,'66A5.',NULL,'Diabetic on insulin'),('efi-diabetes',1,'XaJ5j',NULL,'Patient on maximal tolerated therapy for diabetes'),('efi-diabetes',1,'XaPQH',NULL,'Diabetic foot screen'),('efi-diabetes',1,'66AD.',NULL,'Fundoscopy - diabetic check'),('efi-diabetes',1,'XaCES',NULL,'HbA1 - diabetic control'),('efi-diabetes',1,'XaJK3',NULL,'Diabetic medicine'),('efi-diabetes',1,'XaIIe',NULL,'Diabetes care by hospital only'),('efi-diabetes',1,'Y1286',NULL,'Diabetic Clinic'),('efi-diabetes',1,'XE10F',NULL,'Diabetes mellitus, adult onset, no mention of complication'),('efi-diabetes',1,'XaIIj',NULL,'Diabetic retinopathy screening'),('efi-diabetes',1,'XE12M',NULL,'Diabetes with other complications'),('efi-diabetes',1,'XaBLn',NULL,'Self-monitoring of blood glucose'),('efi-diabetes',1,'XaJ4h',NULL,'Excepted from diabetes qual indicators: Patient unsuitable'),('efi-diabetes',1,'9OL1.',NULL,'Attends diabetes monitoring'),('efi-diabetes',1,'X40J6',NULL,'Insulin treated Type 2 diabetes mellitus'),('efi-diabetes',1,'XaKwQ',NULL,'Diabetic 6 month review'),('efi-diabetes',1,'XE1T3',NULL,'Diabetic - poor control'),('efi-diabetes',1,'X40J4',NULL,'Type I diabetes mellitus'),('efi-diabetes',1,'C1001',NULL,'Diab mell: [adult ons, no ment comp][mat onset][non-ins dep]'),('efi-diabetes',1,'66AZ.',NULL,'Diabetic monitoring NOS'),('efi-diabetes',1,'66AR.',NULL,'Diabetes management plan given'),('efi-diabetes',1,'XaKT5',NULL,'Diabetic patient unsuitable for digital retinal photography'),('efi-diabetes',1,'42W3.',NULL,'Hb. A1C > 10% - bad control'),('efi-diabetes',1,'66AH0',NULL,'Conversion to insulin'),('efi-diabetes',1,'XaJYg',NULL,'Diabetes clinical management plan'),('efi-diabetes',1,'Y3579',NULL,'Diabetic review'),('efi-diabetes',1,'XaE46',NULL,'Referral to diabetes nurse'),('efi-diabetes',1,'XaJ4i',NULL,'Excepted from diabetes quality indicators: Informed dissent'),('efi-diabetes',1,'XaJ4Q',NULL,'Exception reporting: diabetes quality indicators'),('efi-diabetes',1,'X00dG',NULL,'Diabetic maculopathy'),('efi-diabetes',1,'XaIuE',NULL,'Diabetic foot examination'),('efi-diabetes',1,'XaJLa',NULL,'Diabetic retinopathy 12 month review');
INSERT INTO #codesctv3
VALUES ('efi-foot-problems',1,'M2000',NULL,'Hard corn'),('efi-foot-problems',1,'Y3059',NULL,'Chiropody appointment for corns & callus'),('efi-foot-problems',1,'9N1y7',NULL,'Seen in chiropody clinic'),('efi-foot-problems',1,'XaAhW',NULL,'Referral to community-based podiatrist'),('efi-foot-problems',1,'Y1700',NULL,'Referral to chiropodist'),('efi-foot-problems',1,'M20..',NULL,'Corns and callus'),('efi-foot-problems',1,'13G8.',NULL,'Domiciliary chiropody'),('efi-foot-problems',1,'XaAUY',NULL,'Seen by community-based podiatrist'),('efi-foot-problems',1,'Xa4fZ',NULL,'Able to perform nail care activities');
INSERT INTO #codesctv3
VALUES ('efi-fragility-fracture',1,'XA0GW',NULL,'Fracture of radius NOS'),('efi-fragility-fracture',1,'S31z.',NULL,'Fracture of femur, NOS'),('efi-fragility-fracture',1,'XE1l3',NULL,'Fracture of neck of femur'),('efi-fragility-fracture',1,'XA0Gb',NULL,'Fracture of distal end of radius'),('efi-fragility-fracture',1,'XA0HE',NULL,'Fracture of proximal end of femur'),('efi-fragility-fracture',1,'XE1l9',NULL,'Closed fracture of neck of femur NOS'),('efi-fragility-fracture',1,'S30..',NULL,'Fracture: [neck of femur] or [hip]'),('efi-fragility-fracture',1,'S2341',NULL,'Closed fracture: [Colles] or [Smiths]'),('efi-fragility-fracture',1,'XaIUB',NULL,'H/O: hip fracture'),('efi-fragility-fracture',1,'XaIIp',NULL,'Fragility fracture due to unspecified osteoporosis'),('efi-fragility-fracture',1,'Xa1vl',NULL,'Wedge fracture of lumbar vertebra'),('efi-fragility-fracture',1,'Xa1vb',NULL,'Wedge fracture of thoracic vertebra'),('efi-fragility-fracture',1,'XaFCz',NULL,'Wedge fracture of vertebra'),('efi-fragility-fracture',1,'S1021',NULL,'Closed fracture thoracic vertebra, wedge'),('efi-fragility-fracture',1,'XE1kx',NULL,'Open Colles fracture'),('efi-fragility-fracture',1,'XE1kt',NULL,'Closed fracture of radius and ulna, lower end'),('efi-fragility-fracture',1,'XA0HI',NULL,'Intertrochanteric fracture of femur'),('efi-fragility-fracture',1,'S1041',NULL,'Closed fracture lumbar vertebra, wedge'),('efi-fragility-fracture',1,'XA0HJ',NULL,'Subtrochanteric fracture of femur'),('efi-fragility-fracture',1,'S30y.',NULL,'(Closed fracture of neck of femur) or (hip fracture NOS)'),('efi-fragility-fracture',1,'XaD4J',NULL,'Collapse of thoracic vertebra due to osteoporosis'),('efi-fragility-fracture',1,'XaEJD',NULL,'Closed reduction of intracapsular # NOF internal fixat DHS'),('efi-fragility-fracture',1,'XaD4I',NULL,'Collapse of lumbar vertebra due to osteoporosis'),('efi-fragility-fracture',1,'XaD4K',NULL,'Collapse of vertebra due to osteoporosis NOS'),('efi-fragility-fracture',1,'7K1L4',NULL,'Closed reduction of fracture of hip'),('efi-fragility-fracture',1,'7K1D0',NULL,'Pr op rd & fx #NOF & vars: [scrw]/ [nail]/ [plt]/ [mult pin]'),('efi-fragility-fracture',1,'XM1Ne',NULL,'Closed fracture of femur, subcapital'),('efi-fragility-fracture',1,'XaD2s',NULL,'Collapse of cervical vertebra due to osteoporosis'),('efi-fragility-fracture',1,'N331A',NULL,'Osteoporosis with pathological fracture cervical vertebrae'),('efi-fragility-fracture',1,'XE1ku',NULL,'Closed Colles fracture'),('efi-fragility-fracture',1,'XE1ks',NULL,'Fracture of radius and ulna'),('efi-fragility-fracture',1,'XaIUA',NULL,'H/O: fragility fracture'),('efi-fragility-fracture',1,'XaNSP',NULL,'Fragility fracture'),('efi-fragility-fracture',1,'XA0GV',NULL,'Fracture of radius'),('efi-fragility-fracture',1,'XA0Gc',NULL,'Colles fracture'),('efi-fragility-fracture',1,'X601M',NULL,'Dynamic hip screw primary fixation of neck of femur'),('efi-fragility-fracture',1,'XA0HK',NULL,'Hip fracture NOS'),('efi-fragility-fracture',1,'XA0Gn',NULL,'Fracture of distal end of radius and ulna'),('efi-fragility-fracture',1,'7K1LL',NULL,'Closed reduction of fracture of radius and or ulna'),('efi-fragility-fracture',1,'S23..',NULL,'Fracture of radius &/or ulna'),('efi-fragility-fracture',1,'XA0HJ',NULL,'Subtrochanteric fracture of femur'),('efi-fragility-fracture',1,'N331.',NULL,'(Fract: [path][spon]) or (collapse: [spine NOS][vertebra &])'),('efi-fragility-fracture',1,'Xa7nz',NULL,'Fracture of greater trochanter'),('efi-fragility-fracture',1,'XA0HF',NULL,'Subcapital fracture of neck of femur'),('efi-fragility-fracture',1,'XaBDU',NULL,'Closed fracture of femur, intertrochanteric'),('efi-fragility-fracture',1,'S3004',NULL,'Closed fracture head of femur'),('efi-fragility-fracture',1,'S4E0.',NULL,'Closed fracture dislocation, hip joint'),('efi-fragility-fracture',1,'S302.',NULL,'Closed fracture of proximal femur, pertrochanteric'),('efi-fragility-fracture',1,'XaAzf',NULL,'Anterior wedge fracture of vertebra'),('efi-fragility-fracture',1,'XM1Ng',NULL,'Closed fracture of femur, greater trochanter'),('efi-fragility-fracture',1,'S3000',NULL,'Cls # prox femur, intracapsular section, unspecified'),('efi-fragility-fracture',1,'S3005',NULL,'Cls # prox femur, subcapital, Garden grade unspec.'),('efi-fragility-fracture',1,'XA0ED',NULL,'Fracture dislocation of hip joint'),('efi-fragility-fracture',1,'XE1l7',NULL,'Cls # proximal femur, trochanteric section, unspecified'),('efi-fragility-fracture',1,'S300.',NULL,'Closed fracture proximal femur, transcervical'),('efi-fragility-fracture',1,'S3022',NULL,'Closed fracture proximal femur, subtrochanteric'),('efi-fragility-fracture',1,'XE08S',NULL,'Cls red+int fxn proximal femoral #+screw/nail device alone'),('efi-fragility-fracture',1,'7K1D6',NULL,'Prmy open red+int fxn prox femoral #+screw/nail device alone'),('efi-fragility-fracture',1,'7K1J0',NULL,'Cl red and int fix prox fem # with screw/nail (& named vars)'),('efi-fragility-fracture',1,'S300y',NULL,'Closed fract femur: [proximal, oth transcerv] or [subcapit]'),('efi-fragility-fracture',1,'S4500',NULL,'Closed traumatic dislocation of hip, unspecified'),('efi-fragility-fracture',1,'X601P',NULL,'Cls red+int fxn prox femoral #+Richards cannulat hip screw'),('efi-fragility-fracture',1,'S3021',NULL,'Closed fracture proximal femur, intertrochanteric, two part'),('efi-fragility-fracture',1,'S4E..',NULL,'Fracture dislocation or subluxation hip'),('efi-fragility-fracture',1,'S304.',NULL,'Pertrochanteric fracture'),('efi-fragility-fracture',1,'X601T',NULL,'Prim open reduct # neck femur & op fix - Holt nail'),('efi-fragility-fracture',1,'S2351',NULL,'Open fracture: [Colles] or [Smiths]'),('efi-fragility-fracture',1,'XA0HH',NULL,'Basicervical fracture of neck of femur'),('efi-fragility-fracture',1,'X601I',NULL,'Prim op red # nck femur & op fix - Deyerle multiple hip pin'),('efi-fragility-fracture',1,'X601L',NULL,'Prim op red # nck femur & op fix- Charnley compression screw'),('efi-fragility-fracture',1,'S30z.',NULL,'Open fracture of neck of femur NOS'),('efi-fragility-fracture',1,'Xa1vS',NULL,'Crush fracture of cervical vertebra'),('efi-fragility-fracture',1,'XaBDT',NULL,'Open fracture of femur, intertrochanteric'),('efi-fragility-fracture',1,'Xa1vR',NULL,'Wedge fracture of cervical vertebra'),('efi-fragility-fracture',1,'X601S',NULL,'Cl red intracaps fract neck femur fix - Smith-Petersen nail'),('efi-fragility-fracture',1,'S3020',NULL,'Clos frac fem:[prox,troch sect,uns][great troch][less troch]'),('efi-fragility-fracture',1,'S3023',NULL,'Cls # proximal femur, intertrochanteric, comminuted'),('efi-fragility-fracture',1,'S4E2.',NULL,'Closed fracture subluxation, hip joint'),('efi-fragility-fracture',1,'S302z',NULL,'Cls # of proximal femur, pertrochanteric section, NOS'),('efi-fragility-fracture',1,'S300z',NULL,'Closed fracture proximal femur, transcervical, NOS'),('efi-fragility-fracture',1,'S3009',NULL,'Closed fracture proximal femur, subcapital, Garden grade IV'),('efi-fragility-fracture',1,'X601N',NULL,'Prim open reduct # neck femur & op fix - Richards screw'),('efi-fragility-fracture',1,'Xa8AO',NULL,'Fracture subluxation of hip joint'),('efi-fragility-fracture',1,'XM1Nj',NULL,'Open fracture of femur, greater trochanter'),('efi-fragility-fracture',1,'XA0HG',NULL,'Midcervical fracture of neck of femur'),('efi-fragility-fracture',1,'X601U',NULL,'Prim open reduct # neck femur & op fix - Ross Brown nail'),('efi-fragility-fracture',1,'7K1H8',NULL,'Rvsn to opn red+int fxtn prox fem #+ scrw/nail+plate device'),('efi-fragility-fracture',1,'7K1J8',NULL,'Revisn to int fxn(no red) prox fem #+screw/nail device alone'),('efi-fragility-fracture',1,'7K1JB',NULL,'Primary cls red+int fxn prox fem #+screw/nail device alone'),('efi-fragility-fracture',1,'S3006',NULL,'Closed fracture proximal femur, subcapital, Garden grade I'),('efi-fragility-fracture',1,'S1031',NULL,'Open fracture thoracic vertebra, wedge'),('efi-fragility-fracture',1,'7K1JD',NULL,'Primary cls red+int fxn prox fem #+screw/nail+plate device'),('efi-fragility-fracture',1,'7K1J6',NULL,'Primary int fxn(no red) prox fem #+scrw/nail+intramed device'),('efi-fragility-fracture',1,'7K1H6',NULL,'Revsn to opn red+int fxtn prox fem #+screw/nail device alone'),('efi-fragility-fracture',1,'XaPtb',NULL,'Remanip intracap fract neck fem and fix using nail or screw'),('efi-fragility-fracture',1,'XE1l3',NULL,'Fracture of neck of femur'),('efi-fragility-fracture',1,'S3010',NULL,'Opn # proximal femur, intracapsular section, unspecified'),('efi-fragility-fracture',1,'S3015',NULL,'Open fracture proximal femur,subcapital, Garden grade unspec'),('efi-fragility-fracture',1,'S303.',NULL,'Open fracture of proximal femur, pertrochanteric'),('efi-fragility-fracture',1,'S3032',NULL,'Open fracture proximal femur, subtrochanteric'),('efi-fragility-fracture',1,'S3007',NULL,'Closed fracture proximal femur, subcapital, Garden grade II'),('efi-fragility-fracture',1,'S3001',NULL,'Closed fracture proximal femur, transepiphyseal'),('efi-fragility-fracture',1,'Xa1vm',NULL,'Crush fracture of lumbar vertebra'),('efi-fragility-fracture',1,'Xa1vc',NULL,'Crush fracture of thoracic vertebra'),('efi-fragility-fracture',1,'XA0GN',NULL,'Fracture of lumbar spine'),('efi-fragility-fracture',1,'XA0GM',NULL,'Fracture of thoracic spine'),('efi-fragility-fracture',1,'XA0G8',NULL,'Fracture of vertebra'),('efi-fragility-fracture',1,'S23x1',NULL,'Fracture of radius: [closed (alone), unspecified] or [NOS]'),('efi-fragility-fracture',1,'XaIUC',NULL,'H/O: vertebral fracture'),('efi-fragility-fracture',1,'S104.',NULL,'Closed fracture lumbar vertebra'),('efi-fragility-fracture',1,'XE08J',NULL,'Prmy open red+int fxn prox femoral #+screw/nail+plate device'),('efi-fragility-fracture',1,'XE1kW',NULL,'Fracture of vertebra without spinal cord lesion'),('efi-fragility-fracture',1,'S102.',NULL,'Closed fracture thoracic vertebra'),('efi-fragility-fracture',1,'S1040',NULL,'Closed fracture lumbar vertebra, burst'),
('efi-fragility-fracture',1,'S100H',NULL,'Closed fracture cervical vertebra, wedge'),('efi-fragility-fracture',1,'NyuB0',NULL,'[X]Other osteoporosis with pathological fracture'),('efi-fragility-fracture',1,'N1y1.',NULL,'Fatigue fracture of vertebra'),('efi-fragility-fracture',1,'XE2Qf',NULL,'Pathological fracture of lumbar vertebra'),('efi-fragility-fracture',1,'S2351',NULL,'Open fracture: [Colles] or [Smiths]'),('efi-fragility-fracture',1,'S1145',NULL,'Closed spinal fracture with cauda equina lesion'),('efi-fragility-fracture',1,'S112.',NULL,'Closed fracture of thoracic spine with spinal cord lesion'),('efi-fragility-fracture',1,'S1042',NULL,'Closed fracture lumbar vertebra, spondylolysis'),('efi-fragility-fracture',1,'S4E1.',NULL,'Open fracture dislocation, hip joint'),('efi-fragility-fracture',1,'S23y.',NULL,'Open fracture of radius and ulna, unspecified part'),('efi-fragility-fracture',1,'XM0vO',NULL,'Fracture of lumbar spine - no cord lesion'),('efi-fragility-fracture',1,'S150.',NULL,'Multiple fractures of thoracic spine'),('efi-fragility-fracture',1,'S10B6',NULL,'Multiple fractures of lumbar spine and pelvis'),('efi-fragility-fracture',1,'XE1kc',NULL,'Closed fracture of fifth cervical vertebra'),('efi-fragility-fracture',1,'XE1ke',NULL,'Closed fracture of seventh cervical vertebra'),('efi-fragility-fracture',1,'S10B.',NULL,'Fracture of lumbar spine and pelvis'),('efi-fragility-fracture',1,'S1000',NULL,'Closed fracture of unspecified cervical vertebra'),('efi-fragility-fracture',1,'S100K',NULL,'Closed fracture cervical vertebra, spinous process'),('efi-fragility-fracture',1,'XA0GI',NULL,'C6 vertebra closed fracture without spinal cord lesion'),('efi-fragility-fracture',1,'Xa1vd',NULL,'Burst fracture of thoracic vertebra'),('efi-fragility-fracture',1,'XaD30',NULL,'Closed multiple fractures of thoracic spine'),('efi-fragility-fracture',1,'S10A0',NULL,'Fracture of first cervical vertebra'),('efi-fragility-fracture',1,'XE1kd',NULL,'Closed fracture of sixth cervical vertebra'),('efi-fragility-fracture',1,'S1020',NULL,'Closed fracture thoracic vertebra, burst'),('efi-fragility-fracture',1,'S102z',NULL,'Closed fracture thoracic vertebra not otherwise specified'),('efi-fragility-fracture',1,'XaFCy',NULL,'Burst fracture of vertebra'),('efi-fragility-fracture',1,'S114.',NULL,'Closed fracture of lumbar spine with spinal cord lesion'),('efi-fragility-fracture',1,'S102y',NULL,'Other specified closed fracture thoracic vertebra'),('efi-fragility-fracture',1,'S2346',NULL,'Closed fracture radius and ulna, distal'),('efi-fragility-fracture',1,'XA0Gb',NULL,'Fracture of distal end of radius'),('efi-fragility-fracture',1,'S234.',NULL,'Closed fracture of: [radius and ulna, lower end] or [wrist])'),('efi-fragility-fracture',1,'XA0GV',NULL,'Fracture of radius'),('efi-fragility-fracture',1,'XA0GW',NULL,'Fracture of radius NOS');
INSERT INTO #codesctv3
VALUES ('efi-hearing-loss',1,'XE0s9',NULL,'Hearing loss'),('efi-hearing-loss',1,'XE17N',NULL,'Sensorineural hearing loss'),('efi-hearing-loss',1,'XE17P',NULL,'Deafness NOS'),('efi-hearing-loss',1,'F590.',NULL,'Conductive hearing loss'),('efi-hearing-loss',1,'F5801',NULL,'Presbyacusis'),('efi-hearing-loss',1,'XM0Cb',NULL,'Deafness symptom'),('efi-hearing-loss',1,'1C133',NULL,'Bilateral deafness'),('efi-hearing-loss',1,'1C131',NULL,'Unilateral deafness'),('efi-hearing-loss',1,'F59..',NULL,'Hearing loss (& [deafness])'),('efi-hearing-loss',1,'1C13.',NULL,'Deafness (& symptom)'),('efi-hearing-loss',1,'Ub0iR',NULL,'Hearing disability'),('efi-hearing-loss',1,'1C132',NULL,'Partial deafness'),('efi-hearing-loss',1,'X00kO',NULL,'Chronic deafness'),('efi-hearing-loss',1,'F592.',NULL,'Mixed conductive and sensorineural hearing loss'),('efi-hearing-loss',1,'X00kP',NULL,'High frequency deafness'),('efi-hearing-loss',1,'F591.',NULL,'Sensorineural hearing loss (& [deafn: [high freq][low freq])'),('efi-hearing-loss',1,'2BM2.',NULL,'O/E -tune fork=conductive deaf'),('efi-hearing-loss',1,'F5912',NULL,'Neural hearing loss'),('efi-hearing-loss',1,'F59z.',NULL,'Deafness: [chronic] or [NOS]'),('efi-hearing-loss',1,'2BM4.',NULL,'O/E - High tone deafness'),('efi-hearing-loss',1,'2BM3.',NULL,'O/E tune fork=perceptive deaf'),('efi-hearing-loss',1,'XE1AH',NULL,'Presbyacusis (& [senile &/or other])'),('efi-hearing-loss',1,'X00kQ',NULL,'Low frequency deafness'),('efi-hearing-loss',1,'XE1AL',NULL,'Deafness: [sensorineur] or [nerve] or [perceptive - diagnos]'),('efi-hearing-loss',1,'X00kW',NULL,'Non-organic hearing loss'),('efi-hearing-loss',1,'XE17O',NULL,'Ototoxicity - deafness'),('efi-hearing-loss',1,'XE1jy',NULL,'O/E - perceptive deaf (&tune fork=)'),('efi-hearing-loss',1,'8E3..',NULL,'Deafness remedial therapy'),('efi-hearing-loss',1,'1C12.',NULL,'Hearing difficulty'),('efi-hearing-loss',1,'8HT2.',NULL,'Refer to hearing aid clinic'),('efi-hearing-loss',1,'X79ms',NULL,'Hearing aid'),('efi-hearing-loss',1,'F5916',NULL,'Sensorineural hearing loss, bilateral'),('efi-hearing-loss',1,'Xa0LN',NULL,'Hearing aid worn'),('efi-hearing-loss',1,'8HT3.',NULL,'Referral to audiology clinic'),('efi-hearing-loss',1,'XM0F9',NULL,'Aid to hearing'),('efi-hearing-loss',1,'31340',NULL,'Audiogram bilateral abnormality'),('efi-hearing-loss',1,'ZV532',NULL,'[V]Fitting or adjustment of hearing aid'),('efi-hearing-loss',1,'Y2773',NULL,'Impaired hearing'),('efi-hearing-loss',1,'8HR2.',NULL,'Refer for audiometry'),('efi-hearing-loss',1,'XaFo1',NULL,'Deteriorating hearing'),('efi-hearing-loss',1,'XM1UX',NULL,'Audiogram abnormal');
INSERT INTO #codesctv3
VALUES ('efi-heart-failure',1,'XE2QG',NULL,'Left ventricular failure'),('efi-heart-failure',1,'G58..',NULL,'Heart failure'),('efi-heart-failure',1,'XE0V8',NULL,'Biventricular failure'),('efi-heart-failure',1,'XaKNN',NULL,'Seen in heart failure clinic'),('efi-heart-failure',1,'G580.',NULL,'Heart failure: [right] or [congestive]'),('efi-heart-failure',1,'G5801',NULL,'Chronic congestive heart failure'),('efi-heart-failure',1,'XaLNA',NULL,'Heart failure care plan discussed with patient'),('efi-heart-failure',1,'14A6.',NULL,'H/O: heart failure'),('efi-heart-failure',1,'XaLMw',NULL,'Heart failure information given to patient'),('efi-heart-failure',1,'XaIQM',NULL,'Heart failure follow-up'),('efi-heart-failure',1,'XaKNX',NULL,'Referral to heart failure nurse'),('efi-heart-failure',1,'XaKNa',NULL,'Seen by community heart failure nurse'),('efi-heart-failure',1,'XE0V9',NULL,'Heart failure NOS'),('efi-heart-failure',1,'XaIIU',NULL,'Congestive heart failure monitoring'),('efi-heart-failure',1,'XaNUf',NULL,'Heart failure education'),('efi-heart-failure',1,'G5800',NULL,'Acute congestive heart failure'),('efi-heart-failure',1,'X202l',NULL,'Right ventricular failure'),('efi-heart-failure',1,'XaIQN',NULL,'Heart failure annual review'),('efi-heart-failure',1,'XaLMx',NULL,'Referral to heart failure exercise programme'),('efi-heart-failure',1,'XaIpn',NULL,'Heart failure confirmed'),('efi-heart-failure',1,'G582.',NULL,'Acute heart failure'),('efi-heart-failure',1,'XaO5n',NULL,'Congestive heart failure due to valvular disease'),('efi-heart-failure',1,'G581.',NULL,'(L ventric:[fail][imp func]) or (card asth) or (ac pulm oed)'),('efi-heart-failure',1,'XaBwi',NULL,'H/O: Heart failure in last year'),('efi-heart-failure',1,'XE0Wo',NULL,'(Conges card fail)(dropsy)(card insuf)(R hrt fail)(LV fail)'),('efi-heart-failure',1,'XaKNW',NULL,'Admit heart failure emergency'),('efi-heart-failure',1,'XaWyi',NULL,'Heart failure with normal ejection fraction'),('efi-heart-failure',1,'XaQdP',NULL,'Heart failure self management plan'),('efi-heart-failure',1,'XaLon',NULL,'Heart failure 6 month review'),('efi-heart-failure',1,'X202k',NULL,'Heart failure as a complication of care'),('efi-heart-failure',1,'G58z.',NULL,'Heart: [weak] or [failure NOS]'),('efi-heart-failure',1,'XaMGu',NULL,'Heart failure monitoring third letter'),('efi-heart-failure',1,'XE0WE',NULL,'Heart disease: [arteriosclerotic] or [chronic ischaemic NOS]'),('efi-heart-failure',1,'XaEgY',NULL,'Refractory heart failure'),('efi-heart-failure',1,'G5y4z',NULL,'Post cardiac operation heart failure NOS'),('efi-heart-failure',1,'bm...',NULL,'Vasodilators in heart failure [no drugs here]'),('efi-heart-failure',1,'XaXgq',NULL,'Referral to heart failure exercise programme declined'),('efi-heart-failure',1,'XaMJA',NULL,'Excepted heart failure quality indicators: Patient unsuitabl'),('efi-heart-failure',1,'XaIL7',NULL,'New York Heart Assoc classification heart failure symptoms'),('efi-heart-failure',1,'XaMJB',NULL,'Excepted heart failure quality indicators: Informed dissent'),('efi-heart-failure',1,'XaLN7',NULL,'Heart failure review completed'),('efi-heart-failure',1,'XaLCj',NULL,'Referred by heart failure nurse specialist'),('efi-heart-failure',1,'XaMHD',NULL,'Did not attend heart failure clinic'),('efi-heart-failure',1,'XaLGJ',NULL,'Did not attend practice nurse heart failure clinic'),('efi-heart-failure',1,'XaXIR',NULL,'Referral to heart failure education group declined'),('efi-heart-failure',1,'X102Y',NULL,'Acute cardiac pulmonary oedema'),('efi-heart-failure',1,'XM1Qn',NULL,'Impaired left ventricular function'),('efi-heart-failure',1,'XaJ98',NULL,'Echocardiogram shows left ventricular systolic dysfunction'),('efi-heart-failure',1,'1736.',NULL,'Paroxysmal nocturnal dyspnoea'),('efi-heart-failure',1,'XaIIq',NULL,'Left ventricular systolic dysfunction'),('efi-heart-failure',1,'XaJ9I',NULL,'New York Heart Association classification - class III'),('efi-heart-failure',1,'XaJ9H',NULL,'New York Heart Association classification - class II');
INSERT INTO #codesctv3
VALUES ('efi-heart-valve-disease',1,'G543.',NULL,'Pulmonary valve disease'),('efi-heart-valve-disease',1,'G540.',NULL,'Mitral valve: [regurgitation] or [prolapse]'),('efi-heart-valve-disease',1,'X2011',NULL,'Aortic stenosis');
INSERT INTO #codesctv3
VALUES ('efi-hypertension',1,'XE0Uc',NULL,'Essential hypertension'),('efi-hypertension',1,'XE0Ub',NULL,'Hypertension'),('efi-hypertension',1,'14A2.',NULL,'H/O: hypertension'),('efi-hypertension',1,'9N1y2',NULL,'Seen in hypertension clinic'),('efi-hypertension',1,'XaQaV',NULL,'Lifestyle advice regarding hypertension'),('efi-hypertension',1,'XE0Ud',NULL,'Essential hypertension NOS'),('efi-hypertension',1,'Xa8HD',NULL,'On treatment for hypertension'),('efi-hypertension',1,'G201.',NULL,'Benign essential hypertension'),('efi-hypertension',1,'G202.',NULL,'Systolic hypertension'),('efi-hypertension',1,'G20..',NULL,'High blood pressure (& [essential hypertension])'),('efi-hypertension',1,'6628.',NULL,'Poor hypertension control'),('efi-hypertension',1,'662F.',NULL,'Hypertension treatm. started'),('efi-hypertension',1,'6627.',NULL,'Good hypertension control'),('efi-hypertension',1,'G24..',NULL,'Secondary hypertension'),('efi-hypertension',1,'8HT5.',NULL,'Referral to hypertension clinic'),('efi-hypertension',1,'G20z.',NULL,'Hypertension NOS (& [essential])'),('efi-hypertension',1,'G200.',NULL,'Malignant essential hypertension'),('efi-hypertension',1,'Xa0Cs',NULL,'Labile hypertension'),('efi-hypertension',1,'Xa0kX',NULL,'Renovascular hypertension'),('efi-hypertension',1,'Xa3fQ',NULL,'Malignant hypertension'),('efi-hypertension',1,'G22z.',NULL,'(Renal hypertension) or (hypertensive renal disease NOS)'),('efi-hypertension',1,'XaIyC',NULL,'Hypertension treatment refused'),('efi-hypertension',1,'XaIy8',NULL,'Moderate hypertension control'),('efi-hypertension',1,'G24z.',NULL,'Secondary hypertension NOS'),('efi-hypertension',1,'XE0W8',NULL,'(Hypertensive disease) or (hypertension)'),('efi-hypertension',1,'Gyu21',NULL,'[X]Hypertension secondary to other renal disorders'),('efi-hypertension',1,'Gyu20',NULL,'[X]Other secondary hypertension'),('efi-hypertension',1,'G240.',NULL,'Malignant secondary hypertension'),('efi-hypertension',1,'G240z',NULL,'Secondary malignant hypertension NOS'),('efi-hypertension',1,'G241.',NULL,'Secondary benign hypertension'),('efi-hypertension',1,'G244.',NULL,'Hypertension secondary to endocrine disorders'),('efi-hypertension',1,'XaJ4P',NULL,'Exception reporting: hypertension quality indicators'),('efi-hypertension',1,'XSDSb',NULL,'Diastolic hypertension'),('efi-hypertension',1,'XaJYi',NULL,'Hypertension clinical management plan'),('efi-hypertension',1,'G24z1',NULL,'Hypertension secondary to drug'),('efi-hypertension',1,'G24z0',NULL,'Secondary renovascular hypertension NOS'),('efi-hypertension',1,'F4211',NULL,'Hypertensive retinopathy'),('efi-hypertension',1,'G241z',NULL,'Secondary benign hypertension NOS'),('efi-hypertension',1,'G2...',NULL,'Hypertensive disease'),('efi-hypertension',1,'G2z..',NULL,'Hypertensive disease NOS'),('efi-hypertension',1,'XaJ4e',NULL,'Excepted from hypertension qual indicators: Patient unsuit'),('efi-hypertension',1,'XaJ4f',NULL,'Excepted from hypertension qual indicators: Informed dissent');
INSERT INTO #codesctv3
VALUES ('efi-hypotension',1,'XM06a',NULL,'Fainting'),('efi-hypotension',1,'R0021',NULL,'[D]Fainting'),('efi-hypotension',1,'XE2pZ',NULL,'[D]: [fainting] or [collapse]'),('efi-hypotension',1,'G870.',NULL,'Orthostatic hypotension'),('efi-hypotension',1,'G87..',NULL,'Hypotension'),('efi-hypotension',1,'X208R',NULL,'Drug-induced hypotension'),('efi-hypotension',1,'G87z.',NULL,'Hypotension NOS'),('efi-hypotension',1,'G872.',NULL,'Idiopathic hypotension'),('efi-hypotension',1,'XaQi4',NULL,'History of hypotension'),('efi-hypotension',1,'G871.',NULL,'Chronic hypotension'),('efi-hypotension',1,'X70qY',NULL,'Induced hypotension'),('efi-hypotension',1,'F1303',NULL,'Parkinsonism with orthostatic hypotension'),('efi-hypotension',1,'X00CT',NULL,'Sympathotonic orthostatic hypotension'),('efi-hypotension',1,'XM06c',NULL,'Collapse'),('efi-hypotension',1,'XE2ah',NULL,'Had a collapse'),('efi-hypotension',1,'1B62.',NULL,'Syncope/vasovagal faint'),('efi-hypotension',1,'XaJDf',NULL,'Dizziness on standing up'),('efi-hypotension',1,'R002.',NULL,'[D]Syncope and collapse'),('efi-hypotension',1,'1B68.',NULL,'Felt faint'),('efi-hypotension',1,'XM010',NULL,'Syncope'),('efi-hypotension',1,'XM06b',NULL,'Vasovagal syncope'),('efi-hypotension',1,'XM06g',NULL,'Light-headedness'),('efi-hypotension',1,'X769i',NULL,'Vasovagal symptom'),('efi-hypotension',1,'R0023',NULL,'[D]Collapse'),('efi-hypotension',1,'R0042',NULL,'[D]Light-headedness'),('efi-hypotension',1,'79370',NULL,'Implantation of cardiac pacemaker system NEC'),('efi-hypotension',1,'R0022',NULL,'[D]Vasovagal attack'),('efi-hypotension',1,'XM06a',NULL,'Fainting');
INSERT INTO #codesctv3
VALUES ('efi-osteoporosis',1,'Xa0AZ',NULL,'Primary osteoporosis'),('efi-osteoporosis',1,'XaC12',NULL,'Osteoporosis localised to spine'),('efi-osteoporosis',1,'N3319',NULL,'Osteoporosis with pathological fracture thoracic vertebrae'),('efi-osteoporosis',1,'N3318',NULL,'Osteoporosis with pathological fracture of lumbar vertebrae'),('efi-osteoporosis',1,'XaD4K',NULL,'Collapse of vertebra due to osteoporosis NOS'),('efi-osteoporosis',1,'NyuB1',NULL,'[X]Other osteoporosis'),('efi-osteoporosis',1,'N3305',NULL,'Drug-induced osteoporosis'),('efi-osteoporosis',1,'X70Av',NULL,'Secondary generalised osteoporosis'),('efi-osteoporosis',1,'XaISh',NULL,'Osteoporosis treatment stopped'),('efi-osteoporosis',1,'XaISi',NULL,'Osteoporosis treatment changed'),('efi-osteoporosis',1,'XaISj',NULL,'Osteoporosis - no treatment'),('efi-osteoporosis',1,'XaIP4',NULL,'Osteoporosis due to corticosteroids'),('efi-osteoporosis',1,'NyuB0',NULL,'[X]Other osteoporosis with pathological fracture'),('efi-osteoporosis',1,'NyuB8',NULL,'[X]Unspecified osteoporosis with pathological fracture'),('efi-osteoporosis',1,'N331B',NULL,'Postmenopausal osteoporosis with pathological fracture'),('efi-osteoporosis',1,'N3304',NULL,'Disuse osteoporosis'),('efi-osteoporosis',1,'XaQRT',NULL,'Bone sparing drug treatment offered for osteoporosis'),('efi-osteoporosis',1,'XaISo',NULL,'Osteoporosis - treatment response'),('efi-osteoporosis',1,'N3316',NULL,'Idiopathic osteoporosis with pathological fracture'),('efi-osteoporosis',1,'N330A',NULL,'Osteoporosis in endocrine disorders'),('efi-osteoporosis',1,'X70At',NULL,'Adult idiopathic generalised osteoporosis'),('efi-osteoporosis',1,'N3312',NULL,'Postoophorectomy osteoporosis with pathological fracture'),('efi-osteoporosis',1,'N3315',NULL,'Drug-induced osteoporosis with pathological fracture'),('efi-osteoporosis',1,'N3308',NULL,'Localised osteoporosis - Lequesne'),('efi-osteoporosis',1,'N3306',NULL,'Postoophorectomy osteoporosis'),('efi-osteoporosis',1,'N330.',NULL,'Osteoporosis'),('efi-osteoporosis',1,'XaISl',NULL,'Osteoporosis - dietary assessment'),('efi-osteoporosis',1,'XaISk',NULL,'Osteoporosis - dietary advice'),('efi-osteoporosis',1,'XaISm',NULL,'Osteoporosis - exercise advice'),('efi-osteoporosis',1,'XaISx',NULL,'Seen in osteoporosis clinic'),('efi-osteoporosis',1,'XaJdn',NULL,'Referral to osteoporosis clinic'),('efi-osteoporosis',1,'XaQgT',NULL,'History of osteoporosis'),('efi-osteoporosis',1,'N330z',NULL,'Osteoporosis NOS'),('efi-osteoporosis',1,'XaISg',NULL,'Osteoporosis treatment started'),('efi-osteoporosis',1,'N330B',NULL,'Vertebral osteoporosis'),('efi-osteoporosis',1,'N3301',NULL,'Senile osteoporosis'),('efi-osteoporosis',1,'N3300',NULL,'Osteoporosis, unspecified'),('efi-osteoporosis',1,'N3302',NULL,'Postmenopausal osteoporosis'),('efi-osteoporosis',1,'XaISn',NULL,'Osteoporosis - falls prevention'),('efi-osteoporosis',1,'X7038',NULL,'Idiopathic osteoarthritis'),('efi-osteoporosis',1,'XaX3U',NULL,'Excepted osteoporosis quality indicators: patient unsuitable'),('efi-osteoporosis',1,'X70B0',NULL,'Secondary localised osteoporosis'),('efi-osteoporosis',1,'Xa1k0',NULL,'Regional osteoporosis'),('efi-osteoporosis',1,'XaX3W',NULL,'Excepted osteoporosis quality indicators: informed dissent'),('efi-osteoporosis',1,'N3307',NULL,'Post-surgical malabsorption osteoporosis'),('efi-osteoporosis',1,'X70Ax',NULL,'Transient osteoporosis of hip'),('efi-osteoporosis',1,'XaISQ',NULL,'Attends osteoporosis monitoring'),('efi-osteoporosis',1,'XaISS',NULL,'Osteoporosis monitoring default'),('efi-osteoporosis',1,'N3303',NULL,'Idiopathic generalised osteoporosis'),('efi-osteoporosis',1,'XaISd',NULL,'Osteoporosis monitoring'),('efi-osteoporosis',1,'XaISt',NULL,'Refer to osteoporosis specialist'),('efi-osteoporosis',1,'XaIT0',NULL,'At risk of osteoporotic fracture'),('efi-osteoporosis',1,'XaCDT',NULL,'Bone densimetry abnormal'),('efi-osteoporosis',1,'XaE5D',NULL,'Osteopenia'),('efi-osteoporosis',1,'XaITc',NULL,'Lumbar DXA scan result osteopenic');
INSERT INTO #codesctv3
VALUES ('efi-parkinsons',1,'F12..',NULL,'Parkinsons disease'),('efi-parkinsons',1,'F12z.',NULL,'Parkinsons disease NOS'),('efi-parkinsons',1,'XaBfN',NULL,'Parkinsonian tremor'),('efi-parkinsons',1,'XaIn7',NULL,'Parkinsonism'),('efi-parkinsons',1,'XM04E',NULL,'Parkinsonian flexion posture'),('efi-parkinsons',1,'X769G',NULL,'Parkinsonian facies'),('efi-parkinsons',1,'297A.',NULL,'O/E - Parkinsonian tremor'),('efi-parkinsons',1,'XaQwf',NULL,'History of Parkinsons disease'),('efi-parkinsons',1,'Xa2VZ',NULL,'Parkinsons disease nurse'),('efi-parkinsons',1,'XE1hs',NULL,'O/E-festination-Parkinson gait'),('efi-parkinsons',1,'X003j',NULL,'Vascular parkinsonism'),('efi-parkinsons',1,'2987.',NULL,'O/E -Parkinson flexion posture'),('efi-parkinsons',1,'Fyu29',NULL,'[X]Secondary parkinsonism, unspecified'),('efi-parkinsons',1,'Fyu22',NULL,'[X]Parkinsonism in diseases classified elsewhere'),('efi-parkinsons',1,'X003b',NULL,'Secondary parkinsonism'),('efi-parkinsons',1,'X003Z',NULL,'Disorders presenting primarily with parkinsonism'),('efi-parkinsons',1,'F1303',NULL,'Parkinsonism with orthostatic hypotension'),('efi-parkinsons',1,'2994.',NULL,'O/E - festination (& [Parkinson gait])'),('efi-parkinsons',1,'Fyu21',NULL,'[X]Other secondary parkinsonism'),('efi-parkinsons',1,'XaQwg',NULL,'History of parkinsonism'),('efi-parkinsons',1,'X76px',NULL,'Parkinsonian ataxia'),('efi-parkinsons',1,'XaOfZ',NULL,'Cerebral degeneration in Parkinsons disease'),('efi-parkinsons',1,'F121.',NULL,'Drug-induced parkinsonism'),('efi-parkinsons',1,'Xa9zw',NULL,'Parkinsonian features'),('efi-parkinsons',1,'Fyu20',NULL,'[X]Other drug-induced secondary parkinsonism'),('efi-parkinsons',1,'A94y1',NULL,'Syphilitic parkinsonism'),('efi-parkinsons',1,'Fyu2B',NULL,'[X]Secondary parkinsonism due to other external agents'),('efi-parkinsons',1,'U6067',NULL,'[X]Antiparkinsonism drugs caus advers effects in therap use'),('efi-parkinsons',1,'TJ64.',NULL,'Adverse reaction to antiparkinsonism drug'),('efi-parkinsons',1,'dq...',NULL,'Dopaminergic drugs used in parkinsonism'),('efi-parkinsons',1,'dr...',NULL,'Parkinsonism-anticholinergics'),('efi-parkinsons',1,'X003A',NULL,'Lewy body disease'),('efi-parkinsons',1,'X7684',NULL,'Expressionless face'),('efi-parkinsons',1,'F13..',NULL,'Extrapyramid dis: [excl Parkinson][oth and abn movem disord]'),('efi-parkinsons',1,'R0103',NULL,'[D]Tremor NOS');
INSERT INTO #codesctv3
VALUES ('efi-peptic-ulcer',1,'J12..',NULL,'Duodenal ulcer'),('efi-peptic-ulcer',1,'XE0aP',NULL,'Gastric ulcer'),('efi-peptic-ulcer',1,'J12z.',NULL,'Duodenal ulcer NOS'),('efi-peptic-ulcer',1,'XE0qB',NULL,'H/O: peptic ulcer'),('efi-peptic-ulcer',1,'XE0aR',NULL,'Peptic ulcer - (PU) site unspecified'),('efi-peptic-ulcer',1,'XE0aQ',NULL,'Gastric ulcer NOS'),('efi-peptic-ulcer',1,'XM0BZ',NULL,'Peptic ulcer disease'),('efi-peptic-ulcer',1,'XM1RN',NULL,'H/O: duodenal ulcer'),('efi-peptic-ulcer',1,'1956.',NULL,'Peptic ulcer symptoms'),('efi-peptic-ulcer',1,'Xa84h',NULL,'Pyloric ulcer'),('efi-peptic-ulcer',1,'J121.',NULL,'Chronic duodenal ulcer'),('efi-peptic-ulcer',1,'J11z.',NULL,'Gastric: [erosions] or [multiple ulcers] or [ulcer NOS]'),('efi-peptic-ulcer',1,'X302Q',NULL,'Perforation of duodenal ulcer'),('efi-peptic-ulcer',1,'76270',NULL,'Closure of perforated duodenal ulcer'),('efi-peptic-ulcer',1,'J13..',NULL,'Ulcer: [peptic (PU) site unspecified] or [stress NOS]'),('efi-peptic-ulcer',1,'J1201',NULL,'Acute duodenal ulcer with haemorrhage'),('efi-peptic-ulcer',1,'XM1RO',NULL,'H/O: gastric ulcer'),('efi-peptic-ulcer',1,'J121z',NULL,'Chronic duodenal ulcer NOS'),('efi-peptic-ulcer',1,'X302b',NULL,'Duodenal ulcer disease'),('efi-peptic-ulcer',1,'J120.',NULL,'Acute duodenal ulcer'),('efi-peptic-ulcer',1,'Xa6ot',NULL,'Prepyloric gastric ulcer'),('efi-peptic-ulcer',1,'J1202',NULL,'Acute duodenal ulcer with perforation'),('efi-peptic-ulcer',1,'J111.',NULL,'Chronic gastric ulcer'),('efi-peptic-ulcer',1,'J1212',NULL,'Chronic duodenal ulcer with perforation'),('efi-peptic-ulcer',1,'X30Bh',NULL,'Bleeding duodenal ulcer'),('efi-peptic-ulcer',1,'X302X',NULL,'Peptic ulcer of stomach'),('efi-peptic-ulcer',1,'J1101',NULL,'Acute gastric ulcer with haemorrhage'),('efi-peptic-ulcer',1,'14C1.',NULL,'H/O: peptic ulcer (& [duodenal] or [gastric])'),('efi-peptic-ulcer',1,'J110.',NULL,'Acute gastric ulcer'),('efi-peptic-ulcer',1,'J12y2',NULL,'Unspecified duodenal ulcer with perforation'),('efi-peptic-ulcer',1,'J124.',NULL,'Recurrent duodenal ulcer'),('efi-peptic-ulcer',1,'XaELE',NULL,'Multiple gastric ulcers'),('efi-peptic-ulcer',1,'X30Bg',NULL,'Bleeding gastric ulcer'),('efi-peptic-ulcer',1,'J130.',NULL,'Acute peptic ulcer'),('efi-peptic-ulcer',1,'J1211',NULL,'Chronic duodenal ulcer with haemorrhage'),('efi-peptic-ulcer',1,'J131.',NULL,'Chronic peptic ulcer'),('efi-peptic-ulcer',1,'J1302',NULL,'Acute peptic ulcer with perforation'),('efi-peptic-ulcer',1,'J120z',NULL,'Acute duodenal ulcer NOS'),('efi-peptic-ulcer',1,'J12y1',NULL,'Unspecified duodenal ulcer with haemorrhage'),('efi-peptic-ulcer',1,'J1301',NULL,'Acute peptic ulcer with haemorrhage'),('efi-peptic-ulcer',1,'J1102',NULL,'Acute gastric ulcer with perforation'),('efi-peptic-ulcer',1,'J1111',NULL,'Chronic gastric ulcer with haemorrhage'),('efi-peptic-ulcer',1,'X301o',NULL,'Perforation of gastric ulcer'),('efi-peptic-ulcer',1,'761J0',NULL,'Closure of perforated gastric ulcer'),('efi-peptic-ulcer',1,'J13y.',NULL,'Unspecified peptic ulcer'),('efi-peptic-ulcer',1,'J11y.',NULL,'Unspecified gastric ulcer'),('efi-peptic-ulcer',1,'J12y.',NULL,'Unspecified duodenal ulcer'),('efi-peptic-ulcer',1,'XM0sI',NULL,'Perforated peptic ulcer'),('efi-peptic-ulcer',1,'7627.',NULL,'Duodenal ulcer operation'),('efi-peptic-ulcer',1,'J17y8',NULL,'Healed gastric ulcer leaving a scar'),('efi-peptic-ulcer',1,'J14..',NULL,'Ulcer: [gastrojej]/[anast]/[gastrocol]/[jej]/[margin]/[stom]'),('efi-peptic-ulcer',1,'J121y',NULL,'Chronic duodenal ulcer unspecified'),('efi-peptic-ulcer',1,'761J.',NULL,'Gastric ulcer operation'),('efi-peptic-ulcer',1,'J1112',NULL,'Chronic gastric ulcer with perforation'),('efi-peptic-ulcer',1,'X20Vu',NULL,'Oversewing perforated duodenal ulcer'),('efi-peptic-ulcer',1,'J12y0',NULL,'Unspecified duodenal ulcer without mention of complication'),('efi-peptic-ulcer',1,'J1100',NULL,'Acute gastric ulcer without mention of complication'),('efi-peptic-ulcer',1,'J1210',NULL,'Chronic duodenal ulcer without mention of complication'),('efi-peptic-ulcer',1,'J13y1',NULL,'Unspecified peptic ulcer with haemorrhage'),('efi-peptic-ulcer',1,'J130z',NULL,'Acute peptic ulcer NOS'),('efi-peptic-ulcer',1,'XaBmb',NULL,'Bleeding peptic ulcer'),('efi-peptic-ulcer',1,'XaB9d',NULL,'Repair of perforated pyloric ulcer'),('efi-peptic-ulcer',1,'J1203',NULL,'Acute duodenal ulcer with haemorrhage and perforation'),('efi-peptic-ulcer',1,'J110z',NULL,'Acute gastric ulcer NOS'),('efi-peptic-ulcer',1,'J111z',NULL,'Chronic gastric ulcer NOS'),('efi-peptic-ulcer',1,'J13yz',NULL,'Unspecified peptic ulcer NOS'),('efi-peptic-ulcer',1,'J1401',NULL,'Acute gastrojejunal ulcer with haemorrhage'),('efi-peptic-ulcer',1,'J12yz',NULL,'Unspecified duodenal ulcer NOS'),('efi-peptic-ulcer',1,'J11y1',NULL,'Unspecified gastric ulcer with haemorrhage'),('efi-peptic-ulcer',1,'J1200',NULL,'Acute duodenal ulcer without mention of complication'),('efi-peptic-ulcer',1,'7627z',NULL,'Operation on duodenal ulcer NOS'),('efi-peptic-ulcer',1,'XaFBs',NULL,'Endoscopic injection haemostasis of gastric ulcer'),('efi-peptic-ulcer',1,'XaMO5',NULL,'Non steroidal anti inflammatory drug induced gastric ulcer'),('efi-peptic-ulcer',1,'J14z.',NULL,'Gastrojejunal ulcer NOS'),('efi-peptic-ulcer',1,'J1311',NULL,'Chronic peptic ulcer with haemorrhage'),('efi-peptic-ulcer',1,'XE0c1',NULL,'Perforated DU (& [acute])'),('efi-peptic-ulcer',1,'XE0c3',NULL,'Ulcer: [peptic NOS]/[gastrojejunal]/[stomal]/[anastomotic]'),('efi-peptic-ulcer',1,'XE0aS',NULL,'Gastrojejunal ulcer'),('efi-peptic-ulcer',1,'X301J',NULL,'Chronic peptic ulcer of stomach'),('efi-peptic-ulcer',1,'X301E',NULL,'Acute peptic ulcer of stomach'),('efi-peptic-ulcer',1,'XaLWq',NULL,'Anti-platelet induced gastric ulcer'),('efi-peptic-ulcer',1,'761Jz',NULL,'Operation on gastric ulcer NOS'),('efi-peptic-ulcer',1,'76271',NULL,'Suture of duodenal ulcer not elsewhere classified'),('efi-peptic-ulcer',1,'J130y',NULL,'Acute peptic ulcer unspecified'),('efi-peptic-ulcer',1,'J131z',NULL,'Chronic peptic ulcer NOS'),('efi-peptic-ulcer',1,'J1310',NULL,'Chronic peptic ulcer without mention of complication'),('efi-peptic-ulcer',1,'XaMO7',NULL,'Non steroidal anti inflammatory drug induced duodenal ulcer'),('efi-peptic-ulcer',1,'XaLdV',NULL,'Oversew of blood vessel of duodenal ulcer'),('efi-peptic-ulcer',1,'X301G',NULL,'Stress ulcer of stomach'),('efi-peptic-ulcer',1,'XaCLu',NULL,'[V] Personal history of gastric ulcer'),('efi-peptic-ulcer',1,'XaB15',NULL,'Laparoscopic closure of perforated gastric ulcer'),('efi-peptic-ulcer',1,'XaBel',NULL,'Bleeding stress ulcer of stomach'),('efi-peptic-ulcer',1,'X20VN',NULL,'Oversewing perforated gastric ulcer'),('efi-peptic-ulcer',1,'J131y',NULL,'Chronic peptic ulcer unspecified'),('efi-peptic-ulcer',1,'J1300',NULL,'Acute peptic ulcer without mention of complication'),('efi-peptic-ulcer',1,'J1110',NULL,'Chronic gastric ulcer without mention of complication'),('efi-peptic-ulcer',1,'J11yz',NULL,'Unspecified gastric ulcer NOS'),('efi-peptic-ulcer',1,'J11y0',NULL,'Unspecified gastric ulcer without mention of complication'),('efi-peptic-ulcer',1,'J120y',NULL,'Acute duodenal ulcer unspecified'),('efi-peptic-ulcer',1,'J110y',NULL,'Acute gastric ulcer unspecified'),('efi-peptic-ulcer',1,'J1214',NULL,'Chronic duodenal ulcer with obstruction'),('efi-peptic-ulcer',1,'Xa1qC',NULL,'Gastrocolic ulcer'),('efi-peptic-ulcer',1,'XaB8q',NULL,'Oversewing of bleeding duodenal ulcer'),('efi-peptic-ulcer',1,'Xa3ti',NULL,'Perforated peptic ulcer closure'),('efi-peptic-ulcer',1,'X302c',NULL,'Peptic ulcer of duodenum'),('efi-peptic-ulcer',1,'X301F',NULL,'Acute drug-induced ulcer of stomach'),('efi-peptic-ulcer',1,'X302A',NULL,'Acute peptic ulcer of duodenum'),('efi-peptic-ulcer',1,'X302F',NULL,'Chronic peptic ulcer of duodenum'),('efi-peptic-ulcer',1,'7627y',NULL,'Other specified operation on duodenal ulcer'),('efi-peptic-ulcer',1,'761Jy',NULL,'Other specified operation on gastric ulcer'),('efi-peptic-ulcer',1,'J1312',NULL,'Chronic peptic ulcer with perforation'),('efi-peptic-ulcer',1,'J1104',NULL,'Acute gastric ulcer with obstruction'),('efi-peptic-ulcer',1,'J11y2',NULL,'Unspecified gastric ulcer with perforation'),('efi-peptic-ulcer',1,'J13y2',NULL,'Unspecified peptic ulcer with perforation'),('efi-peptic-ulcer',1,'J1411',NULL,'Chronic gastrojejunal ulcer with haemorrhage'),('efi-peptic-ulcer',1,'J14y.',NULL,'Unspecified gastrojejunal ulcer'),('efi-peptic-ulcer',1,'J57y8',NULL,'Primary ulcer of intestine'),('efi-peptic-ulcer',1,'J1114',NULL,'Chronic gastric ulcer with obstruction'),('efi-peptic-ulcer',1,'J111y',NULL,'Chronic gastric ulcer unspecified'),('efi-peptic-ulcer',1,'J1103',NULL,'Acute gastric ulcer with haemorrhage and perforation'),('efi-peptic-ulcer',1,'J13y0',NULL,'Unspecified peptic ulcer without mention of complication'),('efi-peptic-ulcer',1,'J1303',NULL,'Acute peptic ulcer with haemorrhage and perforation'),('efi-peptic-ulcer',1,'J12y3',NULL,'Unspecified duodenal ulcer with haemorrhage and perforation'),('efi-peptic-ulcer',1,'J12y4',NULL,'Unspecified duodenal ulcer with obstruction'),('efi-peptic-ulcer',1,'J12yy',NULL,'Unspec duodenal ulcer; unspec haemorrhage and/or perforation'),('efi-peptic-ulcer',1,'J1213',NULL,'Chronic duodenal ulcer with haemorrhage and perforation'),('efi-peptic-ulcer',1,'XE0Cr',NULL,'Closure of gastric ulcer NEC'),('efi-peptic-ulcer',1,'XE0c5',NULL,'Perforated peptic ulcer (& [acute PU])'),('efi-peptic-ulcer',1,'XE0bz',NULL,'Perforated GU (& [acute])'),('efi-peptic-ulcer',1,'Xa3u7',NULL,'Stomach ulcer excision'),('efi-peptic-ulcer',1,'XaB9e',NULL,'Omental patch repair of perforated pyloric ulcer'),('efi-peptic-ulcer',1,'XaB2R',NULL,'Suture of duodenal ulcer'),('efi-peptic-ulcer',1,'J11..',NULL,'Gastric ulcer (& [prepyloric] or [pyloric])'),('efi-peptic-ulcer',1,'J13z.',NULL,'Peptic ulcer NOS'),('efi-peptic-ulcer',1,'J1020',NULL,'Gastro-oesophageal reflux disease with ulceration'),('efi-peptic-ulcer',1,'XaFBq',NULL,'Endoscopic injection haemostasis of duodenal ulcer'),
('efi-peptic-ulcer',1,'XaBlw',NULL,'Gastric ulcer sample'),('efi-peptic-ulcer',1,'XaMO6',NULL,'Non steroidal anti inflammatory drug induced gastric ulc NOS'),('efi-peptic-ulcer',1,'XaMO8',NULL,'Non steroidal anti inflammatory drug induced duoden ulc NOS'),('efi-peptic-ulcer',1,'XaLWs',NULL,'Anti-platelet induced duodenal ulcer'),('efi-peptic-ulcer',1,'ZV127',NULL,'[V]Pers hist digest syst disease (& [pept ulcer (& [duod])])');
INSERT INTO #codesctv3
VALUES ('efi-pvd',1,'M2710',NULL,'Ischaemic ulcer diabetic foot'),('efi-pvd',1,'Xa0lV',NULL,'Peripheral vascular disease'),('efi-pvd',1,'XE10I',NULL,'Diabetes mellitus with peripheral circulatory disorder'),('efi-pvd',1,'X203T',NULL,'Lower limb ischaemia'),('efi-pvd',1,'G73..',NULL,'(Peri vasc dis (& [isch][oth])) or (isch leg) or (peri isch)'),('efi-pvd',1,'X203R',NULL,'Upper limb ischaemia'),('efi-pvd',1,'XaVyB',NULL,'History of peripheral vascular disease'),('efi-pvd',1,'XaFn7',NULL,'Type II diabetes mellitus with peripheral angiopathy'),('efi-pvd',1,'X203M',NULL,'Arterial ischaemia'),('efi-pvd',1,'X203S',NULL,'Critical upper limb ischaemia'),('efi-pvd',1,'X203U',NULL,'Critical lower limb ischaemia'),('efi-pvd',1,'Xa7lT',NULL,'Ischaemia of feet'),('efi-pvd',1,'X203Q',NULL,'Peripheral ischaemia'),('efi-pvd',1,'XaE3G',NULL,'Critical ischaemia of foot'),('efi-pvd',1,'C107.',NULL,'Diabetes mellitus with: [gangrene] or [periph circul disord]'),('efi-pvd',1,'XM1Qx',NULL,'Diabetes mellitus with gangrene'),('efi-pvd',1,'G670.',NULL,'Atherosclerosis: [precerebral] or [cerebral]'),('efi-pvd',1,'X203K',NULL,'Abdominal aortic atherosclerosis'),('efi-pvd',1,'C1086',NULL,'Type I diabetes mellitus with gangrene'),('efi-pvd',1,'G73z.',NULL,'Peripheral vascular disease NOS'),('efi-pvd',1,'24E9.',NULL,'O/E - R.dorsalis pedis absent'),('efi-pvd',1,'24F9.',NULL,'O/E - L.dorsalis pedis absent'),('efi-pvd',1,'XaBL8',NULL,'O/E - Absent right foot pulses'),('efi-pvd',1,'XaJD3',NULL,'O/E - Right dorsalis pedis abnormal');
INSERT INTO #codesctv3
VALUES ('efi-respiratory-disease',1,'XE0Um',NULL,'Pulmonary embolus'),('efi-respiratory-disease',1,'G410.',NULL,'Primary pulmonary hypertension'),('efi-respiratory-disease',1,'G41y0',NULL,'Secondary pulmonary hypertension'),('efi-respiratory-disease',1,'XaOYV',NULL,'Recurrent pulmonary embolism'),('efi-respiratory-disease',1,'XaBMd',NULL,'[V] Personal history of pulmonary embolism'),('efi-respiratory-disease',1,'X701k',NULL,'Fibrosing alveolitis associated with rheumatoid arthritis'),('efi-respiratory-disease',1,'X102j',NULL,'Cryptogenic organising pneumonitis'),('efi-respiratory-disease',1,'X202y',NULL,'Acute massive pulmonary embolism'),('efi-respiratory-disease',1,'X203A',NULL,'Thromboembolic pulmonary hypertension'),('efi-respiratory-disease',1,'N04y0',NULL,'(Rheum lung) or (Caplan synd) or (fibr alveolit assoc arthr)'),('efi-respiratory-disease',1,'Xa0Cy',NULL,'Pulmonary hypertension with occult mitral stenosis'),('efi-respiratory-disease',1,'X202z',NULL,'Subacute massive pulmonary embolism'),('efi-respiratory-disease',1,'G401.',NULL,'(Pulmonary embolus) or (pulmonary infarction)'),('efi-respiratory-disease',1,'X2033',NULL,'Pulmonary hypertension'),('efi-respiratory-disease',1,'XE0WI',NULL,'(Pulmonary embolism) or (pulmonary infarct)'),('efi-respiratory-disease',1,'X203G',NULL,'Pulmonary hypertension associated with septal defect / shunt'),('efi-respiratory-disease',1,'X203I',NULL,'Pulmonary hypertension secondary to left sided heart disease'),('efi-respiratory-disease',1,'XE0WK',NULL,'Pulmonary hypertension (& [primary])'),('efi-respiratory-disease',1,'X2035',NULL,'Small vessel pulmonary hypertension'),('efi-respiratory-disease',1,'X203B',NULL,'Post-arteritic pulmonary hypertension'),('efi-respiratory-disease',1,'X71a1',NULL,'Long-term oxygen therapy'),('efi-respiratory-disease',1,'XaLL8',NULL,'Ambulatory oxygen therapy'),('efi-respiratory-disease',1,'XM1Xg',NULL,'Chronic respiratory disease monitoring'),('efi-respiratory-disease',1,'1712.',NULL,'Dry cough'),('efi-respiratory-disease',1,'1713.',NULL,'Productive cough -clear sputum'),('efi-respiratory-disease',1,'1715.',NULL,'Productive cough-yellow sputum'),('efi-respiratory-disease',1,'R062.',NULL,'[D]Cough'),('efi-respiratory-disease',1,'171A.',NULL,'Chronic cough'),('efi-respiratory-disease',1,'14B..',NULL,'H/O: respiratory disease'),('efi-respiratory-disease',1,'H....',NULL,'Respiratory disorder'),('efi-respiratory-disease',1,'H33..',NULL,'Asthma'),('efi-respiratory-disease',1,'XaIeq',NULL,'Asthma annual review'),('efi-respiratory-disease',1,'XaIfK',NULL,'Asthma medication review'),('efi-respiratory-disease',1,'663U.',NULL,'Asthma management plan given'),('efi-respiratory-disease',1,'XE2Nb',NULL,'Asthma monitoring check done'),('efi-respiratory-disease',1,'663O.',NULL,'Asthma not disturbing sleep'),('efi-respiratory-disease',1,'663Q.',NULL,'Asthma not limiting activities'),('efi-respiratory-disease',1,'XM1Xb',NULL,'Asthma monitoring'),('efi-respiratory-disease',1,'XaINa',NULL,'Asthma never causes daytime symptoms'),('efi-respiratory-disease',1,'XaIer',NULL,'Asthma follow-up'),('efi-respiratory-disease',1,'Xa1hD',NULL,'Exacerbation of asthma'),('efi-respiratory-disease',1,'663O0',NULL,'Asthma never disturbs sleep'),('efi-respiratory-disease',1,'XaIIZ',NULL,'Asthma daytime symptoms'),('efi-respiratory-disease',1,'663f.',NULL,'Asthma never restricts exercise'),('efi-respiratory-disease',1,'663N.',NULL,'Asthma disturbing sleep'),('efi-respiratory-disease',1,'14B4.',NULL,'H/O: asthma'),('efi-respiratory-disease',1,'XaIu5',NULL,'Asthma monitoring by nurse'),('efi-respiratory-disease',1,'XaINd',NULL,'Asthma causes daytime symptoms most days'),('efi-respiratory-disease',1,'663P.',NULL,'Asthma limiting activities'),('efi-respiratory-disease',1,'XaLIm',NULL,'Asthma trigger - respiratory infection'),('efi-respiratory-disease',1,'663e0',NULL,'Asthma sometimes restricts exercise'),('efi-respiratory-disease',1,'9N1d.',NULL,'Seen in asthma clinic'),('efi-respiratory-disease',1,'XaINb',NULL,'Asthma causes daytime symptoms 1 to 2 times per month'),('efi-respiratory-disease',1,'XaINc',NULL,'Asthma causes daytime symptoms 1 to 2 times per week'),('efi-respiratory-disease',1,'XaIIX',NULL,'Asthma treatment compliance satisfactory'),('efi-respiratory-disease',1,'XaObj',NULL,'Asthma trigger - exercise'),('efi-respiratory-disease',1,'8795.',NULL,'Asthma control step 2'),('efi-respiratory-disease',1,'XaLJS',NULL,'Asthma trigger - cold air'),('efi-respiratory-disease',1,'XaJ50',NULL,'Excepted from asthma quality indicators: Informed dissent'),('efi-respiratory-disease',1,'XaIu6',NULL,'Asthma monitoring by doctor'),('efi-respiratory-disease',1,'8796.',NULL,'Asthma control step 3'),('efi-respiratory-disease',1,'XaLIn',NULL,'Asthma trigger - seasonal'),('efi-respiratory-disease',1,'XaEIV',NULL,'Mild chronic obstructive pulmonary disease'),('efi-respiratory-disease',1,'XaObl',NULL,'Asthma trigger - tobacco smoke'),('efi-respiratory-disease',1,'X1020',NULL,'Hay fever with asthma'),('efi-respiratory-disease',1,'XaINh',NULL,'Number of asthma exacerbations in past year'),('efi-respiratory-disease',1,'679J.',NULL,'Health education - asthma'),('efi-respiratory-disease',1,'XaLJT',NULL,'Asthma trigger - damp'),('efi-respiratory-disease',1,'XaIww',NULL,'Asthma trigger'),('efi-respiratory-disease',1,'663V.',NULL,'Asthma severity'),('efi-respiratory-disease',1,'XaLJU',NULL,'Asthma trigger - emotion'),('efi-respiratory-disease',1,'XaJYe',NULL,'Asthma clinical management plan'),('efi-respiratory-disease',1,'XaLIr',NULL,'Asthma trigger - animals'),('efi-respiratory-disease',1,'8794.',NULL,'Asthma control step 1'),('efi-respiratory-disease',1,'XaIoE',NULL,'Asthma night-time symptoms'),('efi-respiratory-disease',1,'XE0YX',NULL,'Asthma NOS'),('efi-respiratory-disease',1,'663e.',NULL,'Asthma restricts exercise'),('efi-respiratory-disease',1,'173A.',NULL,'Exercise-induced asthma'),('efi-respiratory-disease',1,'XaJ2A',NULL,'Did not attend asthma clinic'),('efi-respiratory-disease',1,'XE0YW',NULL,'Asthma attack'),('efi-respiratory-disease',1,'663N2',NULL,'Asthma disturbs sleep frequently'),('efi-respiratory-disease',1,'XaObk',NULL,'Asthma trigger - pollen'),('efi-respiratory-disease',1,'663N0',NULL,'Asthma causing night waking'),('efi-respiratory-disease',1,'H33z.',NULL,'Asthma unspecified'),('efi-respiratory-disease',1,'663W.',NULL,'Asthma prophylactic medication used'),('efi-respiratory-disease',1,'9OJ1.',NULL,'Attends asthma monitoring'),('efi-respiratory-disease',1,'9OJ2.',NULL,'Refuses asthma monitoring'),('efi-respiratory-disease',1,'H330.',NULL,'Asthma: [extrins - atop][allerg][pollen][childh][+ hay fev]'),('efi-respiratory-disease',1,'663N1',NULL,'Asthma disturbs sleep weekly'),('efi-respiratory-disease',1,'663V1',NULL,'Mild asthma'),('efi-respiratory-disease',1,'XaIIY',NULL,'Asthma treatment compliance unsatisfactory'),('efi-respiratory-disease',1,'8H2P.',NULL,'Emergency admission, asthma'),('efi-respiratory-disease',1,'XaIQD',NULL,'Step up change in asthma management plan'),('efi-respiratory-disease',1,'XaBAQ',NULL,'Recent asthma management'),('efi-respiratory-disease',1,'XaIQE',NULL,'Step down change in asthma management plan'),('efi-respiratory-disease',1,'Xa0lZ',NULL,'Asthmatic bronchitis'),('efi-respiratory-disease',1,'9OJ7.',NULL,'Asthma monitoring call verbal invite'),('efi-respiratory-disease',1,'XaIIW',NULL,'Asthma accident and emergency attendance since last visit'),('efi-respiratory-disease',1,'XaDvL',NULL,'Asthma - currently dormant'),('efi-respiratory-disease',1,'663V0',NULL,'Occasional asthma'),('efi-respiratory-disease',1,'9OJ3.',NULL,'Asthma monitor offer default'),('efi-respiratory-disease',1,'H33zz',NULL,'(Asthma:[exerc ind][allerg NEC][NOS]) or (allerg bronch NEC)'),('efi-respiratory-disease',1,'X101x',NULL,'Allergic asthma'),('efi-respiratory-disease',1,'XaINZ',NULL,'Asthma causes night symptoms 1 to 2 times per month'),('efi-respiratory-disease',1,'663e1',NULL,'Asthma severely restricts exercise'),('efi-respiratory-disease',1,'XaDvK',NULL,'Asthma - currently active'),('efi-respiratory-disease',1,'XaObm',NULL,'Asthma trigger - warm air'),('efi-respiratory-disease',1,'XE0YQ',NULL,'Allergic atopic asthma'),('efi-respiratory-disease',1,'XaIRN',NULL,'Asthma monitoring due'),('efi-respiratory-disease',1,'XaINf',NULL,'Asthma limits walking up hills or stairs'),('efi-respiratory-disease',1,'663V2',NULL,'Moderate asthma'),('efi-respiratory-disease',1,'8797.',NULL,'Asthma control step 4'),('efi-respiratory-disease',1,'XaNKw',NULL,'Royal College of Physicians asthma assessment'),('efi-respiratory-disease',1,'X101u',NULL,'Late onset asthma'),('efi-respiratory-disease',1,'Xa9zf',NULL,'Acute asthma'),('efi-respiratory-disease',1,'XE0YT',NULL,'Non-allergic asthma'),('efi-respiratory-disease',1,'663d.',NULL,'Emergency asthma admission since last appointment'),('efi-respiratory-disease',1,'8793.',NULL,'Asthma control step 0'),('efi-respiratory-disease',1,'XaObi',NULL,'Asthma trigger - airborne dust'),('efi-respiratory-disease',1,'XE0YV',NULL,'Status asthmaticus NOS'),('efi-respiratory-disease',1,'H33z1',NULL,'Asthma attack (& NOS)'),('efi-respiratory-disease',1,'XE0ZR',NULL,'Asthma: [intrinsic] or [late onset]'),('efi-respiratory-disease',1,'8798.',NULL,'Asthma control step 5'),('efi-respiratory-disease',1,'XM0s2',NULL,'Asthma attack NOS'),('efi-respiratory-disease',1,'H33z0',NULL,'(Severe asthma attack) or (status asthmaticus NOS)'),('efi-respiratory-disease',1,'XaRFi',NULL,'Patient has a written asthma personal action plan'),('efi-respiratory-disease',1,'H332.',NULL,'Mixed asthma'),('efi-respiratory-disease',1,'H3120',NULL,'Chronic asthmatic bronchitis'),('efi-respiratory-disease',1,'XaIuG',NULL,'Asthma confirmed'),('efi-respiratory-disease',1,'c7...',NULL,'Asthma prophylaxis'),('efi-respiratory-disease',1,'663V3',NULL,'Severe asthma'),('efi-respiratory-disease',1,'XaINg',NULL,'Asthma limits walking on the flat'),
('efi-respiratory-disease',1,'XaLPE',NULL,'Nocturnal asthma'),('efi-respiratory-disease',1,'XaXZm',NULL,'Asthma causes night time symptoms 1 to 2 times per week'),('efi-respiratory-disease',1,'XaIQ4',NULL,'Change in asthma management plan'),('efi-respiratory-disease',1,'H330z',NULL,'Extrinsic asthma NOS'),('efi-respiratory-disease',1,'XaXZp',NULL,'Asthma causes symptoms most nights'),('efi-respiratory-disease',1,'XaR8K',NULL,'Did not attend asthma review'),('efi-respiratory-disease',1,'XaJtu',NULL,'Referral to asthma clinic'),('efi-respiratory-disease',1,'H331z',NULL,'Intrinsic asthma NOS'),('efi-respiratory-disease',1,'Ua1AX',NULL,'Brittle asthma'),('efi-respiratory-disease',1,'XE0YR',NULL,'Extrinsic asthma without status asthmaticus'),('efi-respiratory-disease',1,'XE0ZP',NULL,'Extrinsic asthma - atopy (& pollen)'),('efi-respiratory-disease',1,'XaJuw',NULL,'Does not have asthma management plan'),('efi-respiratory-disease',1,'H3310',NULL,'Intrinsic asthma without status asthmaticus'),('efi-respiratory-disease',1,'H3300',NULL,'(Hay fever + asthma) or (extr asthma without status asthmat)'),('efi-respiratory-disease',1,'XaQig',NULL,'Asthma control questionnaire'),('efi-respiratory-disease',1,'X101z',NULL,'Allergic asthma NEC'),('efi-respiratory-disease',1,'XE0ZT',NULL,'Asthma: [NOS] or [attack]'),('efi-respiratory-disease',1,'X102D',NULL,'Status asthmaticus'),('efi-respiratory-disease',1,'X101y',NULL,'Extrinsic asthma with asthma attack'),('efi-respiratory-disease',1,'XaXZx',NULL,'Asthma limits activities most days'),('efi-respiratory-disease',1,'XaXZu',NULL,'Asthma limits activities 1 to 2 times per week'),('efi-respiratory-disease',1,'Xa8Hn',NULL,'Asthma control steps'),('efi-respiratory-disease',1,'XaXZs',NULL,'Asthma limits activities 1 to 2 times per month'),('efi-respiratory-disease',1,'X1023',NULL,'Drug-induced asthma'),('efi-respiratory-disease',1,'XE0YS',NULL,'Extrinsic asthma with status asthmaticus'),('efi-respiratory-disease',1,'X1021',NULL,'Allergic non-atopic asthma'),('efi-respiratory-disease',1,'XaQij',NULL,'Under care of asthma specialist nurse'),('efi-respiratory-disease',1,'H3311',NULL,'Intrins asthma with: [asthma attack] or [status asthmaticus]'),('efi-respiratory-disease',1,'x02IG',NULL,'Corticosteroids used in the treatment of asthma'),('efi-respiratory-disease',1,'XaRFk',NULL,'Health education - structured asthma discussion'),('efi-respiratory-disease',1,'X1024',NULL,'Aspirin-sensitive asthma with nasal polyps'),('efi-respiratory-disease',1,'TJF73',NULL,'Adverse reaction to theophylline - asthma'),('efi-respiratory-disease',1,'X1022',NULL,'Intrinsic asthma with asthma attack'),('efi-respiratory-disease',1,'XE0YU',NULL,'Intrinsic asthma with status asthmaticus'),('efi-respiratory-disease',1,'H3301',NULL,'Extrins asthma with: [asthma attack] or [status asthmaticus]'),('efi-respiratory-disease',1,'XaJ4z',NULL,'Excepted from asthma quality indicators: Patient unsuitable'),('efi-respiratory-disease',1,'XaQHq',NULL,'Asthma control test'),('efi-respiratory-disease',1,'XaX3n',NULL,'Asthma review using Roy Colleg of Physicians three questions'),('efi-respiratory-disease',1,'XaIOV',NULL,'Asthma finding'),('efi-respiratory-disease',1,'XaRFl',NULL,'Health education - structured patient focused asthma discuss'),('efi-respiratory-disease',1,'U60F6',NULL,'[X]Antiasthmats caus adverse effects in therapeut use, NEC'),('efi-respiratory-disease',1,'XaJFG',NULL,'Aspirin-induced asthma'),('efi-respiratory-disease',1,'XaRFj',NULL,'Health education - asthma self management'),('efi-respiratory-disease',1,'H3...',NULL,'Chronic obstructive lung disease'),('efi-respiratory-disease',1,'XaIet',NULL,'Chronic obstructive pulmonary disease annual review'),('efi-respiratory-disease',1,'H3122',NULL,'Acute exacerbation of chronic obstructive airways disease'),('efi-respiratory-disease',1,'XaIQT',NULL,'Chronic obstructive pulmonary disease monitoring'),('efi-respiratory-disease',1,'XaIUt',NULL,'COPD self-management plan given'),('efi-respiratory-disease',1,'XaEIW',NULL,'Moderate chronic obstructive pulmonary disease'),('efi-respiratory-disease',1,'H3z..',NULL,'Chronic obstructive airways disease NOS'),('efi-respiratory-disease',1,'XaK8U',NULL,'Number of COPD exacerbations in past year'),('efi-respiratory-disease',1,'XaIes',NULL,'Chronic obstructive pulmonary disease follow-up'),('efi-respiratory-disease',1,'XaEIY',NULL,'Severe chronic obstructive pulmonary disease'),('efi-respiratory-disease',1,'X101i',NULL,'Chron obstruct pulmonary dis wth acute exacerbation, unspec'),('efi-respiratory-disease',1,'XaLJz',NULL,'Chronic obstructive pulmonary disease monitoring status'),('efi-respiratory-disease',1,'XaJDW',NULL,'Did not attend chronic obstructive pulmonary disease clinic'),('efi-respiratory-disease',1,'XaXCb',NULL,'Chronic obstructive pulmonary disease 6 monthly review'),('efi-respiratory-disease',1,'XaJYf',NULL,'Chronic obstructive pulmonary disease clini management plan'),('efi-respiratory-disease',1,'XaJlW',NULL,'Chronic obstructive pulmonary disease monitoring verb invite'),('efi-respiratory-disease',1,'XaKv9',NULL,'Chronic obstructive pulmonary disease does not disturb sleep'),('efi-respiratory-disease',1,'H3y..',NULL,'Other specified chronic obstructive airways disease'),('efi-respiratory-disease',1,'XaXCa',NULL,'Chronic obstructive pulmonary disease 3 monthly review'),('efi-respiratory-disease',1,'XaN4a',NULL,'Very severe chronic obstructive pulmonary disease'),('efi-respiratory-disease',1,'XaPZH',NULL,'COPD patient unsuitable for pulmonary rehabilitation'),('efi-respiratory-disease',1,'XaLqj',NULL,'Health education - chronic obstructive pulmonary disease'),('efi-respiratory-disease',1,'XaIRO',NULL,'Chronic obstructive pulmonary disease monitoring due'),('efi-respiratory-disease',1,'XaK8Q',NULL,'Chronic obstructive pulmonary disease finding'),('efi-respiratory-disease',1,'XaIu8',NULL,'Chronic obstructive pulmonary disease monitoring by doctor'),('efi-respiratory-disease',1,'H3y0.',NULL,'Chronic obstruct pulmonary dis with acute lower resp infectn'),('efi-respiratory-disease',1,'XaKv8',NULL,'Chronic obstructive pulmonary disease disturbs sleep'),('efi-respiratory-disease',1,'XaK8S',NULL,'Emergency COPD admission since last appointment'),('efi-respiratory-disease',1,'Hyu31',NULL,'[X]Other specified chronic obstructive pulmonary disease'),('efi-respiratory-disease',1,'H31..',NULL,'Chronic bronchitis'),('efi-respiratory-disease',1,'H31z.',NULL,'Chronic bronchitis NOS'),('efi-respiratory-disease',1,'H310.',NULL,'Simple chronic bronchitis'),('efi-respiratory-disease',1,'XaK8R',NULL,'COPD accident and emergency attendance since last visit'),('efi-respiratory-disease',1,'H312z',NULL,'Obstructive chronic bronchitis NOS'),('efi-respiratory-disease',1,'XaIu7',NULL,'Chronic obstructive pulmonary disease monitoring by nurse'),('efi-respiratory-disease',1,'XE0ZL',NULL,'(Simple chron bronchitis)/(smok cough)/(sen tracheobronchit)'),('efi-respiratory-disease',1,'H311.',NULL,'Mucopurulent chronic bronchitis'),('efi-respiratory-disease',1,'XaX3c',NULL,'Discussion about COPD exacerbation plan'),('efi-respiratory-disease',1,'XaPzu',NULL,'At risk of chronic obstructive pulmonary diseas exacerbation'),('efi-respiratory-disease',1,'XaKzy',NULL,'Multiple COPD emergency hospital admissions'),('efi-respiratory-disease',1,'XaPio',NULL,'COPD enhanced services administration'),('efi-respiratory-disease',1,'XE0YM',NULL,'Purulent chronic bronchitis'),('efi-respiratory-disease',1,'XaRCH',NULL,'Step up change in COPD management plan'),('efi-respiratory-disease',1,'XaRCG',NULL,'Step down change in COPD management plan'),('efi-respiratory-disease',1,'H31yz',NULL,'Other chronic bronchitis NOS'),('efi-respiratory-disease',1,'H31y.',NULL,'Other chronic bronchitis'),('efi-respiratory-disease',1,'H310z',NULL,'Simple chronic bronchitis NOS'),('efi-respiratory-disease',1,'XaW9D',NULL,'Issue of chronic obstructive pulmonary disease rescue pack'),('efi-respiratory-disease',1,'XaF6d',NULL,'FEV1/FVC < 70% of predicted'),('efi-respiratory-disease',1,'H32..',NULL,'Emphysema'),('efi-respiratory-disease',1,'3399.',NULL,'FEV1/FVC ratio abnormal'),('efi-respiratory-disease',1,'Xa35l',NULL,'Acute infective exacerbation chronic obstruct airway disease'),('efi-respiratory-disease',1,'XaJFu',NULL,'Admit COPD emergency'),('efi-respiratory-disease',1,'XaIf9',NULL,'Referral to pulmonary rehabilitation'),('efi-respiratory-disease',1,'XS7qP',NULL,'Pulmonary rehabilitation'),('efi-respiratory-disease',1,'Ub1ni',NULL,'Pulmonary rehabilitation class'),('efi-respiratory-disease',1,'XaEES',NULL,'Spacer device in use'),('efi-respiratory-disease',1,'XaJ4l',NULL,'Excepted from COPD quality indicators: Informed dissent'),('efi-respiratory-disease',1,'Y1498',NULL,'COPD monitoring check done'),('efi-respiratory-disease',1,'Y5284',NULL,'Acute exacerbation COAD'),('efi-respiratory-disease',1,'8764.',NULL,'Nebuliser therapy'),('efi-respiratory-disease',1,'663J.',NULL,'Airways obstruction reversible'),('efi-respiratory-disease',1,'XaIUq',NULL,'Pulmonary rehabilitation programme commenced'),('efi-respiratory-disease',1,'Y0024',NULL,'Asthma Control'),('efi-respiratory-disease',1,'XaFrW',NULL,'Spirometry reversibility negative'),('efi-respiratory-disease',1,'XE2Pp',NULL,'H/O: chr.obstr. airway disease');
INSERT INTO #codesctv3
VALUES ('efi-skin-ulcer',1,'XE1BP',NULL,'Decubitus ulcer'),('efi-skin-ulcer',1,'XaPoG',NULL,'EPUAP (European pressure ulcer advisory panel) grade 2 ulcer'),('efi-skin-ulcer',1,'Ua1dn',NULL,'Pressure sore on sacrum'),('efi-skin-ulcer',1,'Ua1do',NULL,'Pressure sore on buttocks'),('efi-skin-ulcer',1,'XaPoF',NULL,'EPUAP (European pressure ulcer advisory panel) grade 1 ulcer'),('efi-skin-ulcer',1,'Ua1dm',NULL,'Pressure sore on heel'),('efi-skin-ulcer',1,'XaPoH',NULL,'EPUAP (European pressure ulcer advisory panel) grade 3 ulcer'),('efi-skin-ulcer',1,'XaWyj',NULL,'Hospital acquired pressure ulcer'),('efi-skin-ulcer',1,'XaPoI',NULL,'EPUAP (European pressure ulcer advisory panel) grade 4 ulcer'),('efi-skin-ulcer',1,'M270.',NULL,'(Ulcer: [decubitus, press][plaster]) or (sore: [bed][press])'),('efi-skin-ulcer',1,'XaXEE',NULL,'Pressure ulcer acquired in own home'),('efi-skin-ulcer',1,'XaX8w',NULL,'Residential home acquired pressure ulcer'),('efi-skin-ulcer',1,'Xa7ng',NULL,'Decubitus ulcer of hip'),('efi-skin-ulcer',1,'Ua1dg',NULL,'Pressure sore on shoulder'),('efi-skin-ulcer',1,'XaWyk',NULL,'Nursing home acquired pressure ulcer'),('efi-skin-ulcer',1,'Xa7nh',NULL,'Decubitus ulcer of ankle'),('efi-skin-ulcer',1,'Xa7nk',NULL,'Decubitus ulcer of dorsum of foot'),('efi-skin-ulcer',1,'XaWym',NULL,'Hospice acquired pressure ulcer'),('efi-skin-ulcer',1,'Xa7nj',NULL,'Decubitus ulcer of natal cleft'),('efi-skin-ulcer',1,'XaXP0',NULL,'Multiple pressure ulcers'),('efi-skin-ulcer',1,'XaX98',NULL,'Pressure ulcer on knee'),('efi-skin-ulcer',1,'Ua1c5',NULL,'Skin at risk of breakdown'),('efi-skin-ulcer',1,'M2711',NULL,'Neuropathic diabetic ulcer - foot'),('efi-skin-ulcer',1,'M2712',NULL,'Mixed diabetic ulcer - foot'),('efi-skin-ulcer',1,'XaIeK',NULL,'O/E - Left diabetic foot - ulcerated'),('efi-skin-ulcer',1,'XaIeJ',NULL,'O/E - Right diabetic foot - ulcerated'),('efi-skin-ulcer',1,'XaKHi',NULL,'O/E - left chronic diabetic foot ulcer'),('efi-skin-ulcer',1,'XaKHh',NULL,'O/E - right chronic diabetic foot ulcer'),('efi-skin-ulcer',1,'C1094',NULL,'Type II diabetes mellitus with ulcer'),('efi-skin-ulcer',1,'81H1.',NULL,'Dressing of ulcer'),('efi-skin-ulcer',1,'X75u4',NULL,'Leg ulcer'),('efi-skin-ulcer',1,'X50Bb',NULL,'Leg ulcer NOS'),('efi-skin-ulcer',1,'X50Ba',NULL,'Foot ulcer'),('efi-skin-ulcer',1,'X50Bd',NULL,'Venous ulcer of leg'),('efi-skin-ulcer',1,'7G2E5',NULL,'Dressing of skin ulcer NEC'),('efi-skin-ulcer',1,'Xa8Qn',NULL,'Dressing of skin ulcer'),('efi-skin-ulcer',1,'XaE22',NULL,'Debridement of ulcer'),('efi-skin-ulcer',1,'M27..',NULL,'Chronic skin ulcer'),('efi-skin-ulcer',1,'M27z.',NULL,'Chronic skin ulcer NOS'),('efi-skin-ulcer',1,'M2711',NULL,'Neuropathic diabetic ulcer - foot'),('efi-skin-ulcer',1,'G830.',NULL,'Varicose veins of the leg with ulcer'),('efi-skin-ulcer',1,'XaDzM',NULL,'Two layer compression bandage for skin ulcer'),('efi-skin-ulcer',1,'XM05p',NULL,'Skin ulcer'),('efi-skin-ulcer',1,'M2712',NULL,'Mixed diabetic ulcer - foot'),('efi-skin-ulcer',1,'XaBLa',NULL,'O/E - Left foot ulcer'),('efi-skin-ulcer',1,'XaBLZ',NULL,'O/E - Right foot ulcer'),('efi-skin-ulcer',1,'2FF..',NULL,'O/E - skin ulcer'),('efi-skin-ulcer',1,'XaDzN',NULL,'Four layer compression bandaging for skin ulcer'),('efi-skin-ulcer',1,'XaEY8',NULL,'Three layer compression bandage for skin ulcer'),('efi-skin-ulcer',1,'4JG3.',NULL,'Skin ulcer swab taken'),('efi-skin-ulcer',1,'XaPAU',NULL,'Leg ulcer care management'),('efi-skin-ulcer',1,'X50Be',NULL,'Mixed arteriovenous leg ulcer'),('efi-skin-ulcer',1,'X50Bf',NULL,'Ischaemic leg ulcer'),('efi-skin-ulcer',1,'XE1BQ',NULL,'Non-pressure ulcer lower limb'),('efi-skin-ulcer',1,'M2710',NULL,'Ischaemic ulcer diabetic foot'),('efi-skin-ulcer',1,'X50BW',NULL,'Infected skin ulcer'),('efi-skin-ulcer',1,'XaIex',NULL,'O/E - ankle ulcer'),('efi-skin-ulcer',1,'Xa7nq',NULL,'Ulcer of malleolus'),('efi-skin-ulcer',1,'M271.',NULL,'Ulcer: [named variants, lower limb]'),('efi-skin-ulcer',1,'Xa7nl',NULL,'Ulcer of foot'),('efi-skin-ulcer',1,'XaBfM',NULL,'Ulcer of shin'),('efi-skin-ulcer',1,'G832.',NULL,'Varicose veins of the leg with ulcer and eczema'),('efi-skin-ulcer',1,'XaR4c',NULL,'Skin ulcer with punched out edge'),('efi-skin-ulcer',1,'XaKjC',NULL,'Referral to leg ulcer clinic'),('efi-skin-ulcer',1,'2FF2.',NULL,'O/E - skin ulcer present'),('efi-skin-ulcer',1,'XaItv',NULL,'H/O: venous leg ulcer'),('efi-skin-ulcer',1,'Xa7nm',NULL,'Ulcer of toe'),('efi-skin-ulcer',1,'G835.',NULL,'Infected varicose ulcer'),('efi-skin-ulcer',1,'Xa7no',NULL,'Ulcer of calf'),('efi-skin-ulcer',1,'X50Bk',NULL,'Neuroischaemic foot ulcer'),('efi-skin-ulcer',1,'14F3.',NULL,'H/O: chronic skin ulcer'),('efi-skin-ulcer',1,'XaMhL',NULL,'Seen in primary care leg ulcer clinic'),('efi-skin-ulcer',1,'X50Bj',NULL,'Neuropathic foot ulcer'),('efi-skin-ulcer',1,'XaE1F',NULL,'Debridement of foot ulcer'),('efi-skin-ulcer',1,'2FFZ.',NULL,'O/E - skin ulcer NOS'),('efi-skin-ulcer',1,'Xa7nn',NULL,'Ulcer of heel'),('efi-skin-ulcer',1,'X50Bg',NULL,'Ischaemic foot ulcer'),('efi-skin-ulcer',1,'X7ABr',NULL,'Skin ulcer swab'),('efi-skin-ulcer',1,'XaLwY',NULL,'Leg ulcer compression therapy started'),('efi-skin-ulcer',1,'XaBfC',NULL,'Ulcer of lateral malleolus'),('efi-skin-ulcer',1,'XaMAQ',NULL,'Attending leg ulcer clinic'),('efi-skin-ulcer',1,'XaVz4',NULL,'Superficial ulcer of lower limb'),('efi-skin-ulcer',1,'XaBfD',NULL,'Ulcer of medial malleolus'),('efi-skin-ulcer',1,'XaBZ8',NULL,'Ulcer of big toe'),('efi-skin-ulcer',1,'XC0td',NULL,'Number of ulcers'),('efi-skin-ulcer',1,'XaJWD',NULL,'O/E - depth of ulcer'),('efi-skin-ulcer',1,'X75uC',NULL,'Discharge from skin ulcer'),('efi-skin-ulcer',1,'XaR75',NULL,'Ulcerated skin'),('efi-skin-ulcer',1,'2924.',NULL,'O/E - trophic skin ulceration'),('efi-skin-ulcer',1,'M27y.',NULL,'Chronic ulcer of skin, other specified sites'),('efi-skin-ulcer',1,'Xa40L',NULL,'Varicose ulcer and inflammation'),('efi-skin-ulcer',1,'XE2AU',NULL,'Skin ulcer swab (& taken)'),('efi-skin-ulcer',1,'X50Bi',NULL,'Neuropathic leg ulcer'),('efi-skin-ulcer',1,'XaLwZ',NULL,'Leg ulcer compression therapy finished'),('efi-skin-ulcer',1,'XaE1E',NULL,'Debridement of leg ulcer'),('efi-skin-ulcer',1,'pJ...',NULL,'Venous ulcer compression hosiery'),('efi-skin-ulcer',1,'pJ1..',NULL,'Venous ulcer compression stocking'),('efi-skin-ulcer',1,'Xa7n3',NULL,'Skin ulcer of dorsum of foot'),('efi-skin-ulcer',1,'Xa7n5',NULL,'Skin ulcer of calf'),('efi-skin-ulcer',1,'XaXTp',NULL,'H/O: foot ulcer'),('efi-skin-ulcer',1,'X50BX',NULL,'Neurotrophic ulcer'),('efi-skin-ulcer',1,'XaPoG',NULL,'EPUAP (European pressure ulcer advisory panel) grade 2 ulcer'),('efi-skin-ulcer',1,'Y1906',NULL,'Evidence of pressure mattress, cushion in use'),('efi-skin-ulcer',1,'Y2621',NULL,'Pressure ulcer'),('efi-skin-ulcer',1,'Y2367',NULL,'Pressure sore'),('efi-skin-ulcer',1,'Ua1R1',NULL,'Pressure sore care'),('efi-skin-ulcer',1,'Ua1Cj',NULL,'Dressing of pressure sore'),('efi-skin-ulcer',1,'XE1BP',NULL,'Decubitus ulcer'),('efi-skin-ulcer',1,'Ua1dn',NULL,'Pressure sore on sacrum'),('efi-skin-ulcer',1,'Ua1do',NULL,'Pressure sore on buttocks'),('efi-skin-ulcer',1,'XaPoF',NULL,'EPUAP (European pressure ulcer advisory panel) grade 1 ulcer'),('efi-skin-ulcer',1,'XaPoH',NULL,'EPUAP (European pressure ulcer advisory panel) grade 3 ulcer'),('efi-skin-ulcer',1,'Ua1dm',NULL,'Pressure sore on heel'),('efi-skin-ulcer',1,'Ua1R1',NULL,'Pressure sore care');
INSERT INTO #codesctv3
VALUES ('efi-stroke-tia',1,'XE0VK',NULL,'Transient ischaemic attack'),('efi-stroke-tia',1,'XE2aB',NULL,'Stroke and cerebrovascular accident unspecified'),('efi-stroke-tia',1,'662M.',NULL,'Stroke monitoring'),('efi-stroke-tia',1,'X00D1',NULL,'Cerebrovascular accident'),('efi-stroke-tia',1,'G65z.',NULL,'Transient cerebral ischaemia NOS'),('efi-stroke-tia',1,'XE2te',NULL,'H/O: CVA/stroke'),('efi-stroke-tia',1,'G66..',NULL,'CVA - cerebrovascular accident (& unspecified [& stroke])'),('efi-stroke-tia',1,'XM1R3',NULL,'H/O: stroke'),('efi-stroke-tia',1,'XaIzF',NULL,'Stroke/CVA annual review'),('efi-stroke-tia',1,'XaEGq',NULL,'Stroke NOS'),('efi-stroke-tia',1,'XE0VF',NULL,'Cerebral parenchymal haemorrhage'),('efi-stroke-tia',1,'X00DA',NULL,'Lacunar infarction'),('efi-stroke-tia',1,'14A7.',NULL,'H/O: CVA &/or stroke'),('efi-stroke-tia',1,'X00D7',NULL,'Partial anterior cerebral circulation infarction'),('efi-stroke-tia',1,'G61..',NULL,'Intracerebral haemorrhage (& [cerebrovasc accident due to])'),('efi-stroke-tia',1,'XSAbR',NULL,'Stroke rehabilitation'),('efi-stroke-tia',1,'G640.',NULL,'Cerebral thrombosis'),('efi-stroke-tia',1,'X00D6',NULL,'Total anterior cerebral circulation infarction'),('efi-stroke-tia',1,'X00DI',NULL,'Haemorrhagic cerebral infarction'),('efi-stroke-tia',1,'XE2w4',NULL,'Non-traumatic subdural haematoma'),('efi-stroke-tia',1,'G664.',NULL,'Cerebellar stroke syndrome'),('efi-stroke-tia',1,'G6711',NULL,'Chronic cerebral ischaemia'),('efi-stroke-tia',1,'G663.',NULL,'Brainstem stroke syndrome'),('efi-stroke-tia',1,'G621.',NULL,'Subdural haemorrhage - nontraumatic'),('efi-stroke-tia',1,'XE0X2',NULL,'(Cereb infarc)(cerebrovas acc)(undef stroke/CVA)(stroke NOS)'),('efi-stroke-tia',1,'XaKba',NULL,'Stroke/transient ischaemic attack monitoring verbal invitati'),('efi-stroke-tia',1,'S628.',NULL,'Traumatic subdural haemorrhage'),('efi-stroke-tia',1,'X00DT',NULL,'Posterior circulation stroke of uncertain pathology'),('efi-stroke-tia',1,'S622.',NULL,'Closed traumatic subdural haemorrhage'),('efi-stroke-tia',1,'XE1m2',NULL,'Traumatic intracranial haemorrhage'),('efi-stroke-tia',1,'G64..',NULL,'Cereb art occl (& [cerebvasc acc][stroke]) or (cereb infarc)'),('efi-stroke-tia',1,'XaKcm',NULL,'Stroke/transient ischaemic attack monitoring invitation'),('efi-stroke-tia',1,'XA0BH',NULL,'Traumatic subarachnoid haemorrhage'),('efi-stroke-tia',1,'X00DR',NULL,'Stroke of uncertain pathology'),('efi-stroke-tia',1,'XaBL3',NULL,'H/O: Stroke in last year'),('efi-stroke-tia',1,'Xa1hE',NULL,'Extension of cerebrovascular accident'),('efi-stroke-tia',1,'X00DS',NULL,'Anterior circulation stroke of uncertain pathology'),('efi-stroke-tia',1,'X003j',NULL,'Vascular parkinsonism'),('efi-stroke-tia',1,'XaLtA',NULL,'Delivery of rehabilitation for stroke'),('efi-stroke-tia',1,'XA0BE',NULL,'Traumatic intracranial subdural haematoma'),('efi-stroke-tia',1,'Gyu6C',NULL,'[X]Sequelae of stroke,not specfd as hmorrhage or infarction'),('efi-stroke-tia',1,'XaKSH',NULL,'Haemorrhagic stroke monitoring'),('efi-stroke-tia',1,'XaJwA',NULL,'Stroke/transient ischaemic attack monitoring status'),('efi-stroke-tia',1,'XE1m3',NULL,'Closed traumatic subarachnoid haemorrhage'),('efi-stroke-tia',1,'XA0BG',NULL,'Traumatic intracerebral haemorrhage'),('efi-stroke-tia',1,'XA0BI',NULL,'Traumatic intracranial subarachnoid haemorrhage'),('efi-stroke-tia',1,'S620.',NULL,'Haemorrh: [closed traum subarach] or [mid mening follow inj]'),('efi-stroke-tia',1,'G682.',NULL,'Sequelae of other non-traumatic intracranial haemorrhage'),('efi-stroke-tia',1,'Xa1uU',NULL,'Non-traumatic intracranial subdural haematoma'),('efi-stroke-tia',1,'XaLKH',NULL,'Seen in stroke clinic'),('efi-stroke-tia',1,'XaJ4c',NULL,'Excepted from stroke quality indicators: Informed dissent'),('efi-stroke-tia',1,'XaAsR',NULL,'Seen by stroke service'),('efi-stroke-tia',1,'XaAsI',NULL,'Referral to stroke service'),('efi-stroke-tia',1,'XA0BD',NULL,'Traumatic subdural haematoma'),('efi-stroke-tia',1,'XaR68',NULL,'Stroke/cerebrovascular accident 6 month review'),('efi-stroke-tia',1,'XaJDX',NULL,'Did not attend stroke clinic'),('efi-stroke-tia',1,'XE0VL',NULL,'Cerebral atherosclerosis'),('efi-stroke-tia',1,'XaMGv',NULL,'Stroke/transient ischaemic attack monitoring telephone invte'),('efi-stroke-tia',1,'XE0X0',NULL,'(Trans isch attacks) or (vert-basil insuf) or (drop attacks)'),('efi-stroke-tia',1,'XaAsJ',NULL,'Admission to stroke unit'),('efi-stroke-tia',1,'Xa0Ml',NULL,'Central post-stroke pain'),('efi-stroke-tia',1,'XaJuY',NULL,'Stroke/transient ischaemic attack monitoring third letter'),('efi-stroke-tia',1,'G65y.',NULL,'Other transient cerebral ischaemia'),('efi-stroke-tia',1,'XaR8M',NULL,'Did not attend stroke review'),('efi-stroke-tia',1,'G65z1',NULL,'Intermittent cerebral ischaemia'),('efi-stroke-tia',1,'XaFsk',NULL,'Traumatic subdural haematoma without open intracranial wound'),('efi-stroke-tia',1,'G670.',NULL,'Atherosclerosis: [precerebral] or [cerebral]'),('efi-stroke-tia',1,'F4236',NULL,'Amaurosis fugax'),('efi-stroke-tia',1,'XaJi5',NULL,'Ref to multidisciplinary stroke function improvement service'),('efi-stroke-tia',1,'X00E5',NULL,'Spinal cord stroke'),('efi-stroke-tia',1,'XaJ4b',NULL,'Excepted from stroke quality indicators: Patient unsuitable'),('efi-stroke-tia',1,'XaJYc',NULL,'Referral to stroke clinic'),('efi-stroke-tia',1,'XaJkS',NULL,'Stroke / transient ischaemic attack referral'),('efi-stroke-tia',1,'XM1R2',NULL,'H/O: CVA'),('efi-stroke-tia',1,'G6...',NULL,'Cerebrovascular disease'),('efi-stroke-tia',1,'G634.',NULL,'Carotid artery stenosis'),('efi-stroke-tia',1,'14AB.',NULL,'H/O: TIA'),('efi-stroke-tia',1,'XaJuX',NULL,'Stroke/transient ischaemic attack monitoring second letter'),('efi-stroke-tia',1,'G667.',NULL,'Left sided cerebral hemisphere cerebrovascular accident');
INSERT INTO #codesctv3
VALUES ('efi-thyroid-disorders',1,'X40IQ',NULL,'Hypothyroidism'),('efi-thyroid-disorders',1,'XE108',NULL,'Acquired hypothyroidism'),('efi-thyroid-disorders',1,'XE104',NULL,'Thyrotoxicosis'),('efi-thyroid-disorders',1,'XE10A',NULL,'Hypothyroidism NOS'),('efi-thyroid-disorders',1,'1432.',NULL,'H/O: hypothyroidism'),('efi-thyroid-disorders',1,'C04..',NULL,'Hypothyroidism: &/or (acquired)'),('efi-thyroid-disorders',1,'C04y.',NULL,'Other acquired hypothyroidism'),('efi-thyroid-disorders',1,'1431.',NULL,'H/O: hyperthyroidism'),('efi-thyroid-disorders',1,'C02..',NULL,'([Thyrotoxicosis] or [hyperthyroidism]) or (toxic goitre)'),('efi-thyroid-disorders',1,'Xa3ed',NULL,'Acquired hypothyroidism NOS'),('efi-thyroid-disorders',1,'X40HE',NULL,'Autoimmune hypothyroidism'),('efi-thyroid-disorders',1,'C040.',NULL,'Hypothyroidism: [postsurgical] or [post ablative]'),('efi-thyroid-disorders',1,'C04z.',NULL,'Hypothyroid (& [pretib myxoed][acq goitr][NOS][thyr insuf])'),('efi-thyroid-disorders',1,'Xa3ec',NULL,'Hypothyroidism - congenital and acquired'),('efi-thyroid-disorders',1,'XaOjl',NULL,'Hypothyroidism annual review'),('efi-thyroid-disorders',1,'XaLUg',NULL,'Hypothyroidism review'),('efi-thyroid-disorders',1,'C0410',NULL,'Irradiation hypothyroidism'),('efi-thyroid-disorders',1,'X40HL',NULL,'Iatrogenic hypothyroidism'),('efi-thyroid-disorders',1,'X40HF',NULL,'Hypothyroidism due to Hashimotos thyroiditis'),('efi-thyroid-disorders',1,'C041z',NULL,'Postablative hypothyroidism NOS'),('efi-thyroid-disorders',1,'Cyu11',NULL,'[X]Other specified hypothyroidism'),('efi-thyroid-disorders',1,'C043.',NULL,'Other iatrogenic hypothyroidism'),('efi-thyroid-disorders',1,'X40HM',NULL,'Postablative hypothyroidism'),('efi-thyroid-disorders',1,'X40HO',NULL,'Drug-induced hypothyroidism'),('efi-thyroid-disorders',1,'C043z',NULL,'Iatrogenic hypothyroidism NOS'),('efi-thyroid-disorders',1,'C041.',NULL,'Other postablative hypothyroidism'),('efi-thyroid-disorders',1,'XaJDU',NULL,'Did not attend hyperthyroidism clinic'),('efi-thyroid-disorders',1,'XE122',NULL,'Thyrotoxicosis: [+/- goitr][tox goitr][Graves dis][thyr nod]'),('efi-thyroid-disorders',1,'XaJYj',NULL,'Hypothyroidism clinical management plan'),('efi-thyroid-disorders',1,'X40HG',NULL,'Hypothyroidism due to TSH receptor blocking antibody'),('efi-thyroid-disorders',1,'X40HP',NULL,'Post-infectious hypothyroidism'),('efi-thyroid-disorders',1,'X40Hv',NULL,'Hypothyroidism due to iodide trapping defect'),('efi-thyroid-disorders',1,'X40Hz',NULL,'Hypothyroidism due to thyroglobulin synthesis defect'),('efi-thyroid-disorders',1,'XE109',NULL,'Post-surgical hypothyroidism'),('efi-thyroid-disorders',1,'C042.',NULL,'Iodine hypothyroidism'),('efi-thyroid-disorders',1,'C1343',NULL,'TSH deficiency'),('efi-thyroid-disorders',1,'X40HN',NULL,'Radioactive iodine-induced hypothyroidism'),('efi-thyroid-disorders',1,'X40HI',NULL,'Compensated hypothyroidism'),('efi-thyroid-disorders',1,'XE124',NULL,'Hypothyroidism - congen and acquir (& [cretinism][myxoedem])'),('efi-thyroid-disorders',1,'XE27u',NULL,'Thyroid stimulating hormone (& level)'),('efi-thyroid-disorders',1,'66BZ.',NULL,'Thyroid disease monitoring NOS'),('efi-thyroid-disorders',1,'XaJuM',NULL,'Hypothyroidism monitoring first letter'),('efi-thyroid-disorders',1,'XE100',NULL,'Disorder of thyroid gland'),('efi-thyroid-disorders',1,'4422.',NULL,'Thyroid hormone tests high'),('efi-thyroid-disorders',1,'XaDtf',NULL,'Thyroid function tests abnormal');
INSERT INTO #codesctv3
VALUES ('efi-urinary-system-disease',1,'XE0e6',NULL,'Benign prostatic hyperplasia'),('efi-urinary-system-disease',1,'K....',NULL,'Genitourinary system diseases'),('efi-urinary-system-disease',1,'K1971',NULL,'Painful haematuria'),('efi-urinary-system-disease',1,'Kz...',NULL,'Genitourinary disease NOS'),('efi-urinary-system-disease',1,'XE0qF',NULL,'H/O: urinary disease'),('efi-urinary-system-disease',1,'XE2Rb',NULL,'Prostate: [benign hypertrophy] or [adenoma]'),('efi-urinary-system-disease',1,'XE0f1',NULL,'Genitourinary system diseases (& [kidney] or [urinary])'),('efi-urinary-system-disease',1,'14D..',NULL,'H/O: urinary disease (& [kidney])'),('efi-urinary-system-disease',1,'14DZ.',NULL,'H/O: urinary disease NOS'),('efi-urinary-system-disease',1,'Ky...',NULL,'Other specified diseases of genitourinary system'),('efi-urinary-system-disease',1,'XE0e0',NULL,'Infection of urinary tract'),('efi-urinary-system-disease',1,'8H5B.',NULL,'Referred to urologist'),('efi-urinary-system-disease',1,'K190z',NULL,'Urinary tract infection, site not specified NOS'),('efi-urinary-system-disease',1,'1A13.',NULL,'Nocturia'),('efi-urinary-system-disease',1,'1A55.',NULL,'Dysuria'),('efi-urinary-system-disease',1,'1A1Z.',NULL,'Micturition frequency NOS'),('efi-urinary-system-disease',1,'R082.',NULL,'[D]Retention of urine'),('efi-urinary-system-disease',1,'K190.',NULL,'Urinary tract infection: [site not specified] or [recurrent]'),('efi-urinary-system-disease',1,'K1903',NULL,'Recurrent urinary tract infection'),('efi-urinary-system-disease',1,'XM1Oy',NULL,'Blocked catheter'),('efi-urinary-system-disease',1,'R0822',NULL,'[D]Acute retention of urine'),('efi-urinary-system-disease',1,'K1973',NULL,'Frank haematuria'),('efi-urinary-system-disease',1,'8156.',NULL,'Attention to urinary catheter'),('efi-urinary-system-disease',1,'1A1..',NULL,'(Frequency of micturition) or (polyuria)'),('efi-urinary-system-disease',1,'X30O4',NULL,'Acute retention of urine'),('efi-urinary-system-disease',1,'XaB9O',NULL,'Lower urinary tract symptoms'),('efi-urinary-system-disease',1,'X30Nk',NULL,'Bladder muscle dysfunction - overactive'),('efi-urinary-system-disease',1,'K16y4',NULL,'Detrusor instability'),('efi-urinary-system-disease',1,'7B390',NULL,'Transurethral prostatectomy'),('efi-urinary-system-disease',1,'XE0e0',NULL,'Infection of urinary tract'),('efi-urinary-system-disease',1,'1AA..',NULL,'Prostatism'),('efi-urinary-system-disease',1,'R08..',NULL,'[D]Urinary system symptoms'),('efi-urinary-system-disease',1,'K155.',NULL,'Recurrent cystitis');
INSERT INTO #codesctv3
VALUES ('efi-vision-problems',1,'F46..',NULL,'Cataract'),('efi-vision-problems',1,'F466.',NULL,'Bilateral cataracts'),('efi-vision-problems',1,'XE18j',NULL,'Age-related macular degeneration'),('efi-vision-problems',1,'22E5.',NULL,'O/E - cataract present'),('efi-vision-problems',1,'F4607',NULL,'Nuclear cataract'),('efi-vision-problems',1,'F4251',NULL,'Atrophic age-related macular degeneration'),('efi-vision-problems',1,'Xa9BN',NULL,'Macular degeneration'),('efi-vision-problems',1,'XaBLP',NULL,'O/E - Left cataract present'),('efi-vision-problems',1,'XaBLO',NULL,'O/E - Right cataract present'),('efi-vision-problems',1,'F42y9',NULL,'Macular oedema'),('efi-vision-problems',1,'F4610',NULL,'Unspecified senile cataract'),('efi-vision-problems',1,'F4250',NULL,'Unspecified senile macular degeneration'),('efi-vision-problems',1,'F425.',NULL,'(Degeneratn macula & posterior pole) or (senile macul degen)'),('efi-vision-problems',1,'F461.',NULL,'Age-related cataract'),('efi-vision-problems',1,'F4605',NULL,'Cortical cataract'),('efi-vision-problems',1,'F46z.',NULL,'Cataract NOS'),('efi-vision-problems',1,'1483.',NULL,'H/O: cataract'),('efi-vision-problems',1,'F4252',NULL,'Subretinal neovascularisation of macula'),('efi-vision-problems',1,'Ub0iW',NULL,'Visual disability'),('efi-vision-problems',1,'1B75.',NULL,'Blindness'),('efi-vision-problems',1,'F49..',NULL,'Impaired vision (& [blindness &/or low] or [partial sight])'),('efi-vision-problems',1,'F4H40',NULL,'Ischaemic optic neuropathy'),('efi-vision-problems',1,'F4615',NULL,'Immature cataract NOS'),('efi-vision-problems',1,'F490.',NULL,'Blindness - both eyes'),('efi-vision-problems',1,'XaG29',NULL,'Posterior subcapsular cataract'),('efi-vision-problems',1,'P3311',NULL,'Subcapsular cataract'),('efi-vision-problems',1,'F4950',NULL,'Blindness, one eye, unspecified'),('efi-vision-problems',1,'X75n0',NULL,'Macular subretinal haemorrhage'),('efi-vision-problems',1,'F4254',NULL,'Degeneration macular due to cyst &/or hole &/or pseudohole'),('efi-vision-problems',1,'XE15y',NULL,'Degeneration of macula due to cyst, hole or pseudohole'),('efi-vision-problems',1,'F4619',NULL,'Nuclear senile cataract'),('efi-vision-problems',1,'XE1im',NULL,'O/E: [cataract present] or [lens opacity]'),('efi-vision-problems',1,'P3310',NULL,'Capsular cataract'),('efi-vision-problems',1,'XaE5J',NULL,'Myopic macular degeneration'),('efi-vision-problems',1,'X75kW',NULL,'Cataract observation'),('efi-vision-problems',1,'X00do',NULL,'Branch retinal vein occlusion with macular oedema'),('efi-vision-problems',1,'F4604',NULL,'Posterior subcapsular polar cataract'),('efi-vision-problems',1,'F463.',NULL,'Cataract secondary to ocular disease'),('efi-vision-problems',1,'F461z',NULL,'Senile cataract NOS'),('efi-vision-problems',1,'F422z',NULL,'Proliferative retinopathy NOS'),('efi-vision-problems',1,'F46y.',NULL,'Other cataract'),('efi-vision-problems',1,'XaCGX',NULL,'Blindness certification'),('efi-vision-problems',1,'72661',NULL,'Discission of cataract'),('efi-vision-problems',1,'P331.',NULL,'Capsular and subcapsular cataract'),('efi-vision-problems',1,'F422.',NULL,'Other proliferative retinopathy'),('efi-vision-problems',1,'X75m8',NULL,'Macular branch retinal vein occlusion'),('efi-vision-problems',1,'X008h',NULL,'Non-arteritic ischaemic optic neuropathy'),('efi-vision-problems',1,'F49z.',NULL,'(Visual loss NOS) or (acquired blindness)'),('efi-vision-problems',1,'P331z',NULL,'Capsular or subcapsular cataract NOS'),('efi-vision-problems',1,'XaE5b',NULL,'Clinically significant macular oedema'),('efi-vision-problems',1,'XaE6t',NULL,'Acquired blindness, one eye'),('efi-vision-problems',1,'F4H73',NULL,'Cortical blindness'),('efi-vision-problems',1,'X75mb',NULL,'Atrophic macular change'),('efi-vision-problems',1,'X75km',NULL,'Mature cataract'),('efi-vision-problems',1,'XaD2a',NULL,'Immature cortical cataract'),('efi-vision-problems',1,'XE195',NULL,'Blindness or low vision NOS'),('efi-vision-problems',1,'XaF41',NULL,'Drusen plus pigment change stage macular degeneration'),('efi-vision-problems',1,'X00dg',NULL,'Central retinal vein occlusion with macular oedema'),('efi-vision-problems',1,'S813.',NULL,'Avulsion of eye'),('efi-vision-problems',1,'X00gN',NULL,'Acquired blindness'),('efi-vision-problems',1,'F46yz',NULL,'Other cataract NOS'),('efi-vision-problems',1,'XaJSr',NULL,'Type 1 diabetes mellitus with exudative maculopathy'),('efi-vision-problems',1,'FyuF7',NULL,'[X]Other proliferative retinopathy'),('efi-vision-problems',1,'XaE0a',NULL,'Full thickness macular hole stage III'),('efi-vision-problems',1,'XaE5l',NULL,'Postoperative cystoid macular oedema'),('efi-vision-problems',1,'F4617',NULL,'Posterior subcapsular polar senile cataract'),('efi-vision-problems',1,'Ua1ez',NULL,'Painful blind eye'),('efi-vision-problems',1,'F464.',NULL,'Cataract due to other disorder'),('efi-vision-problems',1,'X00dC',NULL,'Proliferative vitreoretinopathy'),('efi-vision-problems',1,'XaE0b',NULL,'Full thickness macular hole stage IV'),('efi-vision-problems',1,'F461y',NULL,'Other senile cataract'),('efi-vision-problems',1,'F460z',NULL,'Nonsenile cataract NOS'),('efi-vision-problems',1,'F490z',NULL,'Blindness both eyes NOS'),('efi-vision-problems',1,'X008g',NULL,'Arteritic ischaemic optic neuropathy'),('efi-vision-problems',1,'F4042',NULL,'(Blind hypertensive eye) or (glaucoma absolute)'),('efi-vision-problems',1,'XaFTm',NULL,'Mixed type cataract'),('efi-vision-problems',1,'XaE0Z',NULL,'Full thickness macular hole stage II'),('efi-vision-problems',1,'XE16G',NULL,'Hypermature cataract'),('efi-vision-problems',1,'F4603',NULL,'Anterior subcapsular polar cataract'),('efi-vision-problems',1,'F464z',NULL,'Cataract due to other disorder NOS'),('efi-vision-problems',1,'FyuL.',NULL,'[X]Visual disturbances and blindness'),('efi-vision-problems',1,'F4618',NULL,'Cortical senile cataract'),('efi-vision-problems',1,'X74Wt',NULL,'England and Wales blind certification'),('efi-vision-problems',1,'XaG28',NULL,'Anterior subcapsular cataract'),('efi-vision-problems',1,'F462z',NULL,'Traumatic cataract NOS'),('efi-vision-problems',1,'F4606',NULL,'Lamellar zonular cataract'),('efi-vision-problems',1,'F4650',NULL,'Unspecified secondary cataract'),('efi-vision-problems',1,'F4900',NULL,'Unspecified blindness both eyes'),('efi-vision-problems',1,'FyuE1',NULL,'[X]Other specified cataract'),('efi-vision-problems',1,'X00dm',NULL,'Hemispheric retinal vein occlusion with macular oedema'),('efi-vision-problems',1,'F4602',NULL,'Unspecified presenile cataract'),('efi-vision-problems',1,'X75md',NULL,'Macular diffuse atrophy'),('efi-vision-problems',1,'X75n2',NULL,'Macular subretinal fibrosis'),('efi-vision-problems',1,'F465z',NULL,'After cataract NOS'),('efi-vision-problems',1,'F4633',NULL,'Cataract with neovascularisation'),('efi-vision-problems',1,'F4634',NULL,'Cataract in degenerative disorder'),('efi-vision-problems',1,'F4644',NULL,'Drug-induced cataract'),('efi-vision-problems',1,'SJ0z.',NULL,'(Optic nerve or pathway inj NOS) or (traumat blindness NOS)'),('efi-vision-problems',1,'F4646',NULL,'Radiation cataract'),('efi-vision-problems',1,'F4647',NULL,'Cataract due to other physical inflammation'),('efi-vision-problems',1,'F4642',NULL,'Myotonic cataract'),('efi-vision-problems',1,'F463z',NULL,'Cataract secondary to ocular disorder NOS'),('efi-vision-problems',1,'F494.',NULL,'Legal blindness USA'),('efi-vision-problems',1,'F461A',NULL,'Total, mature senile cataract'),('efi-vision-problems',1,'F422y',NULL,'Other specified other proliferative retinopathy'),('efi-vision-problems',1,'XaE6s',NULL,'Acquired blindness, both eyes'),('efi-vision-problems',1,'X74Wx',NULL,'Scottish partially sighted certifn - blindness likely > 16'),('efi-vision-problems',1,'XM04s',NULL,'Vasoproliferative retinopathy'),('efi-vision-problems',1,'F4257',NULL,'Drusen'),('efi-vision-problems',1,'X00d1',NULL,'Macular hole'),('efi-vision-problems',1,'F4252',NULL,'Subretinal neovascularisation of macula'),('efi-vision-problems',1,'F4332',NULL,'Other macular scars'),('efi-vision-problems',1,'F4253',NULL,'Cystoid macular oedema'),('efi-vision-problems',1,'X75mp',NULL,'Macular drusen'),('efi-vision-problems',1,'P330.',NULL,'Congenital cataract, unspecified'),('efi-vision-problems',1,'XaE7V',NULL,'Macular disorder'),('efi-vision-problems',1,'F462.',NULL,'Traumatic cataract'),('efi-vision-problems',1,'X00c9',NULL,'Congenital cataract'),('efi-vision-problems',1,'XaKDJ',NULL,'O/E - left eye clinically significant macular oedema'),('efi-vision-problems',1,'XE1Ju',NULL,'Congenital cataract and lens anomalies'),('efi-vision-problems',1,'XaKDI',NULL,'O/E - right eye clinically significant macular oedema'),('efi-vision-problems',1,'F4H34',NULL,'Toxic optic neuropathy'),('efi-vision-problems',1,'F4614',NULL,'Incipient cataract NOS'),('efi-vision-problems',1,'F465.',NULL,'After-cataract'),('efi-vision-problems',1,'X75kX',NULL,'Cataract form'),('efi-vision-problems',1,'F427C',NULL,'Vitelliform macular dystrophy'),('efi-vision-problems',1,'X75mw',NULL,'Macular pigment epithelial detachment'),('efi-vision-problems',1,'X00dp',NULL,'Adult vitelliform macular dystrophy'),('efi-vision-problems',1,'E2011',NULL,'Dissociative blindness'),('efi-vision-problems',1,'F4K2D',NULL,'Vitreous syndrome following cataract surgery'),('efi-vision-problems',1,'F4305',NULL,'Macular focal chorioretinitis'),('efi-vision-problems',1,'F4A24',NULL,'Macular keratitis NOS'),('efi-vision-problems',1,'XaE5R',NULL,'Macular pseudohole'),('efi-vision-problems',1,'XaE5o',NULL,'Uveitis related cystoid macular oedema'),('efi-vision-problems',1,'XaF99',NULL,'Alcohol related optic neuropathy'),('efi-vision-problems',1,'X75kk',NULL,'Cataract maturity'),('efi-vision-problems',1,'8F6..',NULL,'Specific disability rehabilitation (& blind)'),('efi-vision-problems',1,'F4640',NULL,'Diabetic cataract'),('efi-vision-problems',1,'XaE5c',NULL,'Diabetic macular oedema'),('efi-vision-problems',1,'XaKcS',NULL,'O/E - sight threatening diabetic retinopathy'),
('efi-vision-problems',1,'XaFmA',NULL,'Type II diabetes mellitus with diabetic cataract'),('efi-vision-problems',1,'XaJQp',NULL,'Type II diabetes mellitus with exudative maculopathy'),('efi-vision-problems',1,'XaFm8',NULL,'Type I diabetes mellitus with diabetic cataract'),('efi-vision-problems',1,'XaPjK',NULL,'Excluded from diabetic retinopathy screening as blind'),('efi-vision-problems',1,'X00dF',NULL,'Visually threatening diabetic retinopathy'),('efi-vision-problems',1,'XaPen',NULL,'Impaired vision due to diabetic retinopathy'),('efi-vision-problems',1,'8H52.',NULL,'Referral to ophthalmology service'),('efi-vision-problems',1,'Ua1jQ',NULL,'Wears glasses'),('efi-vision-problems',1,'6689.',NULL,'Registered blind'),('efi-vision-problems',1,'Y2774',NULL,'Impaired eyesight'),('efi-vision-problems',1,'F4250',NULL,'Unspecified senile macular degeneration'),('efi-vision-problems',1,'F4239',NULL,'Branch retinal vein occlusion'),('efi-vision-problems',1,'F4840',NULL,'Unspecified visual field defect'),('efi-vision-problems',1,'Xa7nF',NULL,'Registered partially sighted'),('efi-vision-problems',1,'XE16L',NULL,'Impaired vision'),('efi-vision-problems',1,'XE16M',NULL,'Visual loss NOS');
INSERT INTO #codesctv3
VALUES ('efi-activity-limitation',1,'13O5.',NULL,'Attendance allowance'),('efi-activity-limitation',1,'9EB5.',NULL,'DS 1500 Disability living allowance completed'),('efi-activity-limitation',1,'Y3502',NULL,'Allowance / DLA applied for'),('efi-activity-limitation',1,'Y3501',NULL,'Already receiving attendance allowance / DLA'),('efi-activity-limitation',1,'Y0700',NULL,'Physical - motor disability'),('efi-activity-limitation',1,'Y1558',NULL,'Blue Badge disabled driver'),('efi-activity-limitation',1,'13V8.',NULL,'Has disabled driver badge'),('efi-activity-limitation',1,'13VC.',NULL,'Disability');
INSERT INTO #codesctv3
VALUES ('efi-anaemia',1,'145..',NULL,'H/O: blood disorder (& [anaemia])'),('efi-anaemia',1,'1451.',NULL,'H/O: anaemia - iron deficient'),('efi-anaemia',1,'1452.',NULL,'H/O: Anaemia vit.B12 deficient'),('efi-anaemia',1,'1453.',NULL,'H/O: haemolytic anaemia'),('efi-anaemia',1,'1454.',NULL,'H/O: anaemia NOS'),('efi-anaemia',1,'B9370',NULL,'Refractory anaemia without sideroblasts, so stated'),('efi-anaemia',1,'B9371',NULL,'Refractory anaemia with sideroblasts'),('efi-anaemia',1,'B9372',NULL,'Refractory anaemia with excess of blasts'),('efi-anaemia',1,'B9373',NULL,'Refractory anaemia with excess of blasts with transformation'),('efi-anaemia',1,'BBmA.',NULL,'[M] Refractory anaemia with sideroblasts'),('efi-anaemia',1,'BBmB.',NULL,'[M]Refractory anaemia+excess of blasts with transformation'),('efi-anaemia',1,'ByuHC',NULL,'[X]Refractory anaemia, unspecified'),('efi-anaemia',1,'D0...',NULL,'Deficiency anaemiasm (& [asiderotic] or [sideropenic])'),('efi-anaemia',1,'D00..',NULL,'Iron deficiency anaemias (& [hypochromic - microcytic])'),('efi-anaemia',1,'D000.',NULL,'Anaemia due chron blood loss: [iron defic] or [normocytic]'),('efi-anaemia',1,'D001.',NULL,'Iron deficiency anaemia due to dietary causes'),('efi-anaemia',1,'D00y.',NULL,'(Kelly-Patersons)/(Plumm-Vinsons)/(oth sp iron def anaem)'),('efi-anaemia',1,'D00y1',NULL,'Microcytic hypochromic anaemia'),('efi-anaemia',1,'D00yz',NULL,'Other specified iron deficiency anaemia NOS'),('efi-anaemia',1,'D00z.',NULL,'Unspecified iron deficiency anaemia'),('efi-anaemia',1,'D00z0',NULL,'Achlorhydric anaemia'),('efi-anaemia',1,'D00z1',NULL,'Chlorotic anaemia'),('efi-anaemia',1,'D00z2',NULL,'Idiopathic hypochromic anaemia'),('efi-anaemia',1,'D00zz',NULL,'Iron deficiency anaemia NOS'),('efi-anaemia',1,'D01..',NULL,'Anaemia: [megaloblastic] or [other deficiency]'),('efi-anaemia',1,'D010.',NULL,'Pernicious anaemia (& [Biermers][congen def intrins factor])'),('efi-anaemia',1,'D011.',NULL,'Vitamin B12 deficiency anaemia (& pleural)'),('efi-anaemia',1,'D0110',NULL,'Vit B12 def anaem: [diet][Imersl-Grasbeck][Imerslund][Vegan]'),('efi-anaemia',1,'D0111',NULL,'Vit B12 defic anaemia due to malabsorption with proteinuria'),('efi-anaemia',1,'D011z',NULL,'Other vitamin B12 deficiency anaemia NOS'),('efi-anaemia',1,'D012.',NULL,'Folate-deficient megaloblastic anaemia'),('efi-anaemia',1,'D0121',NULL,'Anaemia: [folate def or megaloblast, diet cause]/[goat milk]'),('efi-anaemia',1,'D0122',NULL,'Folate deficiency anaemia, drug-induced'),('efi-anaemia',1,'D0123',NULL,'Folate deficiency anaemia due to malabsorption'),('efi-anaemia',1,'D0124',NULL,'Folate deficiency anaemia due to liver disorders'),('efi-anaemia',1,'D012z',NULL,'Folate deficiency anaemia NOS'),('efi-anaemia',1,'D013.',NULL,'Other specified megaloblastic anaemia NEC'),('efi-anaemia',1,'D0130',NULL,'Combined B12 and folate deficiency anaemia'),('efi-anaemia',1,'D013z',NULL,'Other specified megaloblastic anaemia NEC NOS'),('efi-anaemia',1,'D014.',NULL,'Protein-deficiency anaemia'),('efi-anaemia',1,'D0140',NULL,'Amino acid deficiency anaemia'),('efi-anaemia',1,'D014z',NULL,'Protein-deficiency anaemia NOS'),('efi-anaemia',1,'D01y.',NULL,'Other specified nutritional deficiency anaemia'),('efi-anaemia',1,'D01yy',NULL,'Other specified other nutritional deficiency anaemia'),('efi-anaemia',1,'D01yz',NULL,'Other specified nutritional deficiency anaemia NOS'),('efi-anaemia',1,'D01z.',NULL,'Anaemia NOS: [other deficiency] or [megaloblastic]'),('efi-anaemia',1,'D01z0',NULL,'[X]Megaloblastic anaemia NOS'),('efi-anaemia',1,'D0y..',NULL,'Other specified deficiency anaemias'),('efi-anaemia',1,'D0z..',NULL,'Deficiency anaemias NOS'),('efi-anaemia',1,'D1...',NULL,'Haemolytic anaemia'),('efi-anaemia',1,'D104.',NULL,'(Thalassaemia (& Mediterr anaemia)) or (leptocytosis, hered)'),('efi-anaemia',1,'D1040',NULL,'Thalassaemia major: [NEC] or [Cooleys anaemia]'),('efi-anaemia',1,'D1047',NULL,'Beta thalassaemia major'),('efi-anaemia',1,'D104z',NULL,'(Mediterranean anaemia) or (thalassaemia NOS)'),('efi-anaemia',1,'D106.',NULL,'Sickle cell anaemia'),('efi-anaemia',1,'D1060',NULL,'Sickle cell anaemia of unspecified type'),('efi-anaemia',1,'D1061',NULL,'Sickle cell anaemia with no crisis'),('efi-anaemia',1,'D1062',NULL,'Sickle cell anaemia with crisis'),('efi-anaemia',1,'D106z',NULL,'Sickle cell anaemia NOS'),('efi-anaemia',1,'D11..',NULL,'Acquired haemolytic anaemia'),('efi-anaemia',1,'D110.',NULL,'(Autoimmun haemolyt anaemia) or (Coombs positive haemolysis)'),('efi-anaemia',1,'D1100',NULL,'Primary cold-type haemolytic anaemia'),('efi-anaemia',1,'D1101',NULL,'Primary warm-type haemolytic anaemia'),('efi-anaemia',1,'D1102',NULL,'Secondary cold-type haemolytic anaemia'),('efi-anaemia',1,'D1103',NULL,'Secondary warm-type haemolytic anaemia'),('efi-anaemia',1,'D110z',NULL,'Autoimmune haemolytic anaemia NOS'),('efi-anaemia',1,'D111.',NULL,'Non-autoimmune haemolytic anaemia'),('efi-anaemia',1,'D1110',NULL,'Mechanical haemolytic anaemia'),('efi-anaemia',1,'D1111',NULL,'Microangiopathic haemolytic anaemia'),('efi-anaemia',1,'D1112',NULL,'Toxic haemolytic anaemia'),('efi-anaemia',1,'D1114',NULL,'Drug-induced haemolytic anaemia'),('efi-anaemia',1,'D1115',NULL,'Infective haemolytic anaemia'),('efi-anaemia',1,'D111y',NULL,'Other specified non-autoimmune haemolytic anaemia'),('efi-anaemia',1,'D111z',NULL,'Non-autoimmune haemolytic anaemia NOS'),('efi-anaemia',1,'D11z.',NULL,'Acquired haemolytic anaemia NOS'),('efi-anaemia',1,'D1y..',NULL,'Other specified haemolytic anaemias'),('efi-anaemia',1,'D1z..',NULL,'Haemolytic anaemias NOS'),('efi-anaemia',1,'D2...',NULL,'Aplastic and other anaemias'),('efi-anaemia',1,'D20..',NULL,'Aplastic anaemia'),('efi-anaemia',1,'D210.',NULL,'Sideroblastic anaemia'),('efi-anaemia',1,'D2101',NULL,'Acquired sideroblastic anaemia'),('efi-anaemia',1,'D2002',NULL,'(Constit aplas anaem with malf) or (pancytopenia - dysmelia)'),('efi-anaemia',1,'D200y',NULL,'Other specified constitutional aplastic anaemia'),('efi-anaemia',1,'D200z',NULL,'Constitutional aplastic anaemia NOS'),('efi-anaemia',1,'D201.',NULL,'Anaemia: [acquired aplastic] or [normocytic due to aplasia]'),('efi-anaemia',1,'D2010',NULL,'Aplastic anaemia due to chronic disease'),('efi-anaemia',1,'D2011',NULL,'Anaemia: [aplast due drug][hypoplast due drug or chem subst]'),('efi-anaemia',1,'D2012',NULL,'Aplastic anaemia due to infection'),('efi-anaemia',1,'D2013',NULL,'Aplastic anaemia due to radiation'),('efi-anaemia',1,'D2014',NULL,'Aplastic anaemia due to toxic cause'),('efi-anaemia',1,'D2017',NULL,'Transient hypoplastic anaemia'),('efi-anaemia',1,'D201z',NULL,'Anaemia: [named variants (& [NOS] or [NEC])]'),('efi-anaemia',1,'D204.',NULL,'Idiopathic aplastic anaemia'),('efi-anaemia',1,'D20z.',NULL,'Aplastic anaemia NOS'),('efi-anaemia',1,'D21..',NULL,'Other and unspecified anaemia'),('efi-anaemia',1,'D2103',NULL,'Secondary sideroblastic anaemia due to disease'),('efi-anaemia',1,'D2104',NULL,'Secondary sideroblastic anaemia due to drugs and toxins'),('efi-anaemia',1,'D210z',NULL,'Sideroblastic anaemia NOS'),('efi-anaemia',1,'D211.',NULL,'Acute posthaemorrhagic anaemia (& normocytic )'),('efi-anaemia',1,'D212.',NULL,'Anaemia in neoplastic disease'),('efi-anaemia',1,'D214.',NULL,'Chronic anaemia'),('efi-anaemia',1,'D21yy',NULL,'Other specified other anaemia'),('efi-anaemia',1,'D21yz',NULL,'Other specified anaemia NOS'),('efi-anaemia',1,'D21z.',NULL,'Anaemia: [unsp][secondary NOS][normocyt/macrocyt unsp cause]'),('efi-anaemia',1,'D2y..',NULL,'Other specified anaemias'),('efi-anaemia',1,'D2z..',NULL,'Other anaemias NOS'),('efi-anaemia',1,'Dyu0.',NULL,'[X]Nutritional anaemias'),('efi-anaemia',1,'Dyu00',NULL,'[X]Other iron deficiency anaemias'),('efi-anaemia',1,'Dyu01',NULL,'[X]Other dietary vitamin B12 deficiency anaemia'),('efi-anaemia',1,'Dyu02',NULL,'[X]Other vitamin B12 deficiency anaemias'),('efi-anaemia',1,'Dyu03',NULL,'[X]Other folate deficiency anaemias'),('efi-anaemia',1,'Dyu04',NULL,'[X]Other megaloblastic anaemias, not elsewhere classified'),('efi-anaemia',1,'Dyu05',NULL,'[X]Anaem(nonmegaloblast)assoc+oth specfd nutrition deficiens'),('efi-anaemia',1,'Dyu06',NULL,'[X]Vitamin B12 deficiency anaemia, unspecified'),('efi-anaemia',1,'Dyu1.',NULL,'[X]Haemolytic anaemias'),('efi-anaemia',1,'Dyu15',NULL,'[X]Other autoimmune haemolytic anaemias'),('efi-anaemia',1,'Dyu16',NULL,'[X]Other nonautoimmune haemolytic anaemias'),('efi-anaemia',1,'Dyu17',NULL,'[X]Other acquired haemolytic anaemias'),('efi-anaemia',1,'Dyu2.',NULL,'[X]Aplastic and other anaemias'),('efi-anaemia',1,'Dyu21',NULL,'[X]Other specified aplastic anaemias'),('efi-anaemia',1,'Dyu22',NULL,'[X]Anaemia in other chronic diseases classified elsewhere'),('efi-anaemia',1,'Dyu23',NULL,'[X]Other sideroblastic anaemias'),('efi-anaemia',1,'Dyu24',NULL,'[X]Other specified anaemias'),('efi-anaemia',1,'X20Bp',NULL,'Normocytic anaemia due to unspecified cause'),('efi-anaemia',1,'X20Bq',NULL,'Normocytic anaemia due to aplasia'),('efi-anaemia',1,'X20Br',NULL,'Secondary anaemia NOS'),('efi-anaemia',1,'X20Bu',NULL,'Anaemia of chronic disorder'),('efi-anaemia',1,'X20Bv',NULL,'Anaemia of renal disease'),('efi-anaemia',1,'X20Bw',NULL,'Microcytic anaemia'),('efi-anaemia',1,'X20C6',NULL,'Macrocytic anaemia'),('efi-anaemia',1,'X20C7',NULL,'Macrocytic anaemia of unspecified cause'),('efi-anaemia',1,'X20C8',NULL,'Megaloblastic anaemia'),('efi-anaemia',1,'X20C9',NULL,'Megaloblastic anaemia NOS'),('efi-anaemia',1,'X20CA',NULL,'Megaloblastic anaemia due to dietary causes'),('efi-anaemia',1,'X20CG',NULL,'Combined deficiency anaemia'),('efi-anaemia',1,'X20CI',NULL,'Alcohol-related sideroblastic anaemia'),('efi-anaemia',1,'X20CJ',NULL,'Drug-induced sideroblastic anaemia'),('efi-anaemia',1,'X20CK',NULL,'Refractory anaemia'),('efi-anaemia',1,'X20CP',NULL,'Constitutional aplastic anaemia without malformation'),('efi-anaemia',1,'X20Ca',NULL,'Acquired haemolytic anaemia with haemoglobinuria NEC'),
('efi-anaemia',1,'X20Ce',NULL,'Warm autoimmune haemolytic anaemia'),('efi-anaemia',1,'XE13b',NULL,'Deficiency anaemias'),('efi-anaemia',1,'XE13c',NULL,'Iron deficiency anaemia'),('efi-anaemia',1,'XE13d',NULL,'Iron deficiency anaemia due to chronic blood loss'),('efi-anaemia',1,'XE13e',NULL,'Other specified iron deficiency anaemia'),('efi-anaemia',1,'XE13f',NULL,'Other deficiency anaemias'),('efi-anaemia',1,'XE13g',NULL,'Other vitamin B12 deficiency anaemias'),('efi-anaemia',1,'XE13h',NULL,'Vitamin B12 deficiency anaemia due to dietary causes'),('efi-anaemia',1,'XE13i',NULL,'Folate deficiency anaemia due to dietary causes'),('efi-anaemia',1,'XE13j',NULL,'Other deficiency anaemias NOS'),('efi-anaemia',1,'XE13o',NULL,'Autoimmune haemolytic anaemia'),('efi-anaemia',1,'XE13q',NULL,'Constitutional aplastic anaemia'),('efi-anaemia',1,'XE13r',NULL,'Constitutional aplastic anaemia with malformation'),('efi-anaemia',1,'XE13t',NULL,'Acquired aplastic anaemia'),('efi-anaemia',1,'XE13u',NULL,'Aplastic anaemia due to drugs'),('efi-anaemia',1,'XE13w',NULL,'Acquired aplastic anaemia NOS'),('efi-anaemia',1,'XE13x',NULL,'Acute posthaemorrhagic anaemia'),('efi-anaemia',1,'XE140',NULL,'Anaemia unspecified'),('efi-anaemia',1,'XE14S',NULL,'(Anaem: [iron def][microcyt]) or (Kelly-Pat) or (Plumm-Vins)'),('efi-anaemia',1,'XE14U',NULL,'Anaemia: [deficiency excluding iron] or [megaloblastic]'),('efi-anaemia',1,'XE14W',NULL,'B12 deficiency anaemia (& other)'),('efi-anaemia',1,'XE14i',NULL,'Other anaemias'),('efi-anaemia',1,'XE2ro',NULL,'Pernicious anaemia'),('efi-anaemia',1,'XM05A',NULL,'Anaemia'),('efi-anaemia',1,'Xa05o',NULL,'Idiopathic sideroblastic anaemia'),('efi-anaemia',1,'Xa0Se',NULL,'Refractory anaemia with ringed sideroblasts'),('efi-anaemia',1,'Xa0Sf',NULL,'Refractory anaemia with excess blasts'),('efi-anaemia',1,'Xa0Sg',NULL,'Refractory anaemia with excess blasts in transformation'),('efi-anaemia',1,'Xa36n',NULL,'Cold autoimmune haemolytic anaemia'),('efi-anaemia',1,'Xa3eu',NULL,'Deficiency anaemias, excluding iron'),('efi-anaemia',1,'Xa3ev',NULL,'Nutritional anaemias NOS'),('efi-anaemia',1,'Xa7n0',NULL,'Normocytic anaemia'),('efi-anaemia',1,'Xa9Aw',NULL,'Vitamin B12-deficient megaloblastic anaemia'),('efi-anaemia',1,'Xa9FH',NULL,'Normocytic anaemia following acute bleed'),('efi-anaemia',1,'XaBC5',NULL,'[M] Refractory anaemia with excess of blasts'),('efi-anaemia',1,'XaBDS',NULL,'Anaemia in ovarian carcinoma'),('efi-anaemia',1,'XaC0z',NULL,'Drug-induced autoimmune haemolytic anaemia'),('efi-anaemia',1,'XaCLx',NULL,'Anaemia secondary to renal failure'),('efi-anaemia',1,'XaCLy',NULL,'Anaemia secondary to chronic renal failure'),('efi-anaemia',1,'XaM6S',NULL,'Hypoplastic haemolytic and renal anaemia drugs Band 1'),('efi-anaemia',1,'XaM6T',NULL,'Hypoplastic haemolytic and renal anaemia drugs Band 2'),('efi-anaemia',1,'XaQi5',NULL,'History of sickle cell anaemia'),('efi-anaemia',1,'XaYv2',NULL,'Refractory anaemia with multilineage dysplasia'),('efi-anaemia',1,'Xaa65',NULL,'Recurrent anaemia'),('efi-anaemia',1,'i1...',NULL,'Oral iron for iron-deficiency anaemias'),('efi-anaemia',1,'i2...',NULL,'Parenteral iron for iron-deficiency anaemias'),('efi-anaemia',1,'XM05A',NULL,'Anaemia'),('efi-anaemia',1,'XE140',NULL,'Anaemia unspecified'),('efi-anaemia',1,'D00y1',NULL,'Microcytic hypochromic anaemia'),('efi-anaemia',1,'Dyu06',NULL,'[X]Vitamin B12 deficiency anaemia, unspecified'),('efi-anaemia',1,'D00zz',NULL,'Iron deficiency anaemia NOS'),('efi-anaemia',1,'42R41',NULL,'Ferritin level low'),('efi-anaemia',1,'i312.',NULL,'Hydroxocobalamin 1mg/1mL injection'),('efi-anaemia',1,'66E5.',NULL,'B12 injections - at surgery'),('efi-anaemia',1,'C2621',NULL,'Cobalamin deficiency'),('efi-anaemia',1,'42T2.',NULL,'Serum vitamin B12 low'),('efi-anaemia',1,'D00..',NULL,'Iron deficiency anaemias (& [hypochromic - microcytic])'),('efi-anaemia',1,'C2620',NULL,'Folic acid deficiency'),('efi-anaemia',1,'D00z.',NULL,'Unspecified iron deficiency anaemia');
INSERT INTO #codesctv3
VALUES ('efi-care-requirement',1,'918F.',NULL,'Has a carer'),('efi-care-requirement',1,'13F61',NULL,'Lives in a nursing home'),('efi-care-requirement',1,'9N1G.',NULL,'Seen in nursing home'),('efi-care-requirement',1,'XaMFG',NULL,'Lives in care home'),('efi-care-requirement',1,'XE2ta',NULL,'Provision of home help'),('efi-care-requirement',1,'Ua0Lj',NULL,'Lives in staffed home'),('efi-care-requirement',1,'XaN0N',NULL,'Eligible for funded nursing care'),('efi-care-requirement',1,'13F6.',NULL,'Nursing or other home'),('efi-care-requirement',1,'13WJ.',NULL,'Help by relatives'),('efi-care-requirement',1,'Y3101',NULL,'Carers involved'),('efi-care-requirement',1,'13G61',NULL,'Home help attends'),('efi-care-requirement',1,'13G6.',NULL,'Home help: [person] or [provision]'),('efi-care-requirement',1,'8GEB.',NULL,'Care from friends');
INSERT INTO #codesctv3
VALUES ('efi-cognitive-problems',1,'XaMGF',NULL,'Dementia annual review'),('efi-cognitive-problems',1,'X002w',NULL,'Dementia'),('efi-cognitive-problems',1,'X75xU',NULL,'Memory impairment'),('efi-cognitive-problems',1,'XaJua',NULL,'Referral to memory clinic'),('efi-cognitive-problems',1,'1461.',NULL,'H/O: dementia'),('efi-cognitive-problems',1,'X00R2',NULL,'Senile dementia'),('efi-cognitive-problems',1,'XE1Xs',NULL,'Vascular dementia'),('efi-cognitive-problems',1,'1B1A.',NULL,'Memory disturbance (& amnesia (& symptom))'),('efi-cognitive-problems',1,'X75xH',NULL,'Poor short-term memory'),('efi-cognitive-problems',1,'Eu00.',NULL,'[X]Dementia in Alzheimers disease'),('efi-cognitive-problems',1,'E000.',NULL,'Uncomplicated senile dementia'),('efi-cognitive-problems',1,'Eu01z',NULL,'[X]Vascular dementia, unspecified'),('efi-cognitive-problems',1,'E2A10',NULL,'Mild memory disturbance'),('efi-cognitive-problems',1,'X0030',NULL,'Dementia in Alzheimers disease with late onset'),('efi-cognitive-problems',1,'E004.',NULL,'Arteriosclerotic dementia (including [multi infarct dement])'),('efi-cognitive-problems',1,'Eu002',NULL,'[X]Dementia in Alzheimers dis, atypical or mixed type'),('efi-cognitive-problems',1,'XaMJC',NULL,'Dementia monitoring'),('efi-cognitive-problems',1,'Xa0lH',NULL,'Multi-infarct dementia'),('efi-cognitive-problems',1,'Eu02z',NULL,'[X] Dementia: [unspecified] or [named variants (& NOS)]'),('efi-cognitive-problems',1,'X00RT',NULL,'Age-associated memory impairment'),('efi-cognitive-problems',1,'Eu00z',NULL,'[X]Dementia in Alzheimers disease, unspecified'),('efi-cognitive-problems',1,'Eu023',NULL,'[X]Dementia in Parkinsons disease'),('efi-cognitive-problems',1,'X002x',NULL,'Dementia in Alzheimers disease with early onset'),('efi-cognitive-problems',1,'XaKyY',NULL,'[X]Lewy body dementia'),('efi-cognitive-problems',1,'E001.',NULL,'Presenile dementia'),('efi-cognitive-problems',1,'X003A',NULL,'Lewy body disease'),('efi-cognitive-problems',1,'Xa1GB',NULL,'Cerebral degeneration presenting primarily with dementia'),('efi-cognitive-problems',1,'E004z',NULL,'Arteriosclerotic dementia NOS'),('efi-cognitive-problems',1,'XE1Z6',NULL,'[X]Unspecified dementia'),('efi-cognitive-problems',1,'X75xC',NULL,'Poor long-term memory'),('efi-cognitive-problems',1,'XaE74',NULL,'Senile dementia of the Lewy body type'),('efi-cognitive-problems',1,'E2A11',NULL,'Organic memory impairment'),('efi-cognitive-problems',1,'E0021',NULL,'Senile dementia with depression'),('efi-cognitive-problems',1,'E0020',NULL,'Senile dementia with paranoia'),('efi-cognitive-problems',1,'X003V',NULL,'Mixed cortical and subcortical vascular dementia'),('efi-cognitive-problems',1,'Xa25J',NULL,'Alcoholic dementia'),('efi-cognitive-problems',1,'XaMGG',NULL,'Dementia monitoring second letter'),('efi-cognitive-problems',1,'Eu011',NULL,'[X]Dementia: [multi-infarct] or [predominantly cortical]'),('efi-cognitive-problems',1,'Eu01y',NULL,'[X]Other vascular dementia'),('efi-cognitive-problems',1,'Eu041',NULL,'[X]Delirium superimposed on dementia'),('efi-cognitive-problems',1,'X0034',NULL,'Frontotemporal dementia'),('efi-cognitive-problems',1,'E041.',NULL,'Dementia in conditions EC'),('efi-cognitive-problems',1,'E001z',NULL,'Presenile dementia NOS'),('efi-cognitive-problems',1,'E002.',NULL,'Senile dementia with depressive or paranoid features'),('efi-cognitive-problems',1,'X003T',NULL,'Subcortical vascular dementia'),('efi-cognitive-problems',1,'Xa3ez',NULL,'Other senile/presenile dementia'),('efi-cognitive-problems',1,'X00Rk',NULL,'Alcoholic dementia NOS'),('efi-cognitive-problems',1,'Xa0sE',NULL,'Dementia of frontal lobe type'),('efi-cognitive-problems',1,'X003R',NULL,'Vascular dementia of acute onset'),('efi-cognitive-problems',1,'Eu020',NULL,'[X]Dementia in Picks disease'),('efi-cognitive-problems',1,'Eu022',NULL,'[X]Dementia in Huntingtons disease'),('efi-cognitive-problems',1,'Eu02.',NULL,'[X]Dementia in other diseases classified elsewhere'),('efi-cognitive-problems',1,'E003.',NULL,'Senile dementia with delirium'),('efi-cognitive-problems',1,'XE1bq',NULL,'Memory disturbance: [mild]'),('efi-cognitive-problems',1,'E0040',NULL,'Uncomplicated arteriosclerotic dementia'),('efi-cognitive-problems',1,'X003X',NULL,'Patchy dementia'),('efi-cognitive-problems',1,'Ua190',NULL,'Distortion of memory'),('efi-cognitive-problems',1,'E0010',NULL,'Uncomplicated presenile dementia'),('efi-cognitive-problems',1,'E002z',NULL,'Senile dementia with depressive or paranoid features NOS'),('efi-cognitive-problems',1,'XaKUo',NULL,'Disturbance of memory for order of events'),('efi-cognitive-problems',1,'E0041',NULL,'Arteriosclerotic dementia with delirium'),('efi-cognitive-problems',1,'XaJPy',NULL,'Anti-dementia drug therapy'),('efi-cognitive-problems',1,'XE1aG',NULL,'Dementia (& [presenile] or [senile])'),('efi-cognitive-problems',1,'E0043',NULL,'Arteriosclerotic dementia with depression'),('efi-cognitive-problems',1,'E0012',NULL,'Presenile dementia with paranoia'),('efi-cognitive-problems',1,'X003W',NULL,'Semantic dementia'),('efi-cognitive-problems',1,'Eu02y',NULL,'[X]Dementia in other specified diseases classif elsewhere'),('efi-cognitive-problems',1,'XE1Xu',NULL,'Other alcoholic dementia'),('efi-cognitive-problems',1,'E0013',NULL,'Presenile dementia with depression'),('efi-cognitive-problems',1,'E0011',NULL,'Presenile dementia with delirium'),('efi-cognitive-problems',1,'X002m',NULL,'Amyotrophic lateral sclerosis with dementia'),('efi-cognitive-problems',1,'Ub1T6',NULL,'Language disorder of dementia'),('efi-cognitive-problems',1,'X003P',NULL,'Acquired immune deficiency syndrome dementia complex'),('efi-cognitive-problems',1,'E0042',NULL,'Arteriosclerotic dementia with paranoia'),('efi-cognitive-problems',1,'E012.',NULL,'Alcoholic dementia: [other] or [NOS]'),('efi-cognitive-problems',1,'XaNbm',NULL,'Seen in memory clinic'),('efi-cognitive-problems',1,'XaLFo',NULL,'Excepted from dementia quality indicators: Patient unsuitabl'),('efi-cognitive-problems',1,'Ua196',NULL,'Minor memory lapses'),('efi-cognitive-problems',1,'R00z0',NULL,'[D]Amnesia (retrograde)'),('efi-cognitive-problems',1,'X75xG',NULL,'Amnesia for recent events'),('efi-cognitive-problems',1,'3A40.',NULL,'Memory: present year not known'),('efi-cognitive-problems',1,'3A60.',NULL,'Memory: present month not knwn'),('efi-cognitive-problems',1,'XaLFp',NULL,'Excepted from dementia quality indicators: Informed dissent'),('efi-cognitive-problems',1,'3A10.',NULL,'Memory: own age not known'),('efi-cognitive-problems',1,'3A30.',NULL,'Memory: present place not knwn'),('efi-cognitive-problems',1,'3AA1.',NULL,'Memory: address recall unsucc.'),('efi-cognitive-problems',1,'3A70.',NULL,'Memory: important event not kn'),('efi-cognitive-problems',1,'3A91.',NULL,'Memory: count down unsuccess.'),('efi-cognitive-problems',1,'3A80.',NULL,'Memory: import.person not knwn'),('efi-cognitive-problems',1,'3A50.',NULL,'Memory: own DOB not known'),('efi-cognitive-problems',1,'X75xD',NULL,'Amnesia for remote events'),('efi-cognitive-problems',1,'XaLFf',NULL,'Exception reporting: dementia quality indicators'),('efi-cognitive-problems',1,'F21y2',NULL,'Binswangers disease'),('efi-cognitive-problems',1,'XaMGJ',NULL,'Dementia monitoring verbal invite'),('efi-cognitive-problems',1,'XaMGK',NULL,'Dementia monitoring telephone invite'),('efi-cognitive-problems',1,'XaMGI',NULL,'Dementia monitoring third letter'),('efi-cognitive-problems',1,'XaJBQ',NULL,'Global deterioration scale: assessment of prim deg dementia'),('efi-cognitive-problems',1,'Xa2Ve',NULL,'Impairment of registration'),('efi-cognitive-problems',1,'Ua197',NULL,'Memory lapses'),('efi-cognitive-problems',1,'3A20.',NULL,'Memory: present time not known'),('efi-cognitive-problems',1,'Eu021',NULL,'[X]Dementia in Creutzfeldt-Jakob disease'),('efi-cognitive-problems',1,'XaMFy',NULL,'Dementia monitoring administration'),('efi-cognitive-problems',1,'F110.',NULL,'Alzheimers disease'),('efi-cognitive-problems',1,'Xa3f0',NULL,'Confusional state'),('efi-cognitive-problems',1,'2841.',NULL,'Confused'),('efi-cognitive-problems',1,'1461.',NULL,'H/O: dementia'),('efi-cognitive-problems',1,'XaPpE',NULL,'Lacks capacity to give consent (Mental Capacity Act 2005)'),('efi-cognitive-problems',1,'X00RS',NULL,'Mild cognitive disorder'),('efi-cognitive-problems',1,'XaPpE',NULL,'Lacks capacity to give consent (Mental Capacity Act 2005)'),('efi-cognitive-problems',1,'3A30.',NULL,'Memory: present place not knwn'),('efi-cognitive-problems',1,'XaMGF',NULL,'Dementia annual review');
INSERT INTO #codesctv3
VALUES ('efi-dizziness',1,'XM06h',NULL,'Vertigo NOS'),('efi-dizziness',1,'R0043',NULL,'[D]Vertigo NOS'),('efi-dizziness',1,'F5611',NULL,'Benign paroxysmal positional vertigo or nystagmus'),('efi-dizziness',1,'Xa9Bo',NULL,'Benign paroxysmal positional vertigo'),('efi-dizziness',1,'R0044',NULL,'[D]Acute vertigo'),('efi-dizziness',1,'XM1RJ',NULL,'H/O: vertigo'),('efi-dizziness',1,'F561.',NULL,'Other and unspecified peripheral vertigo'),('efi-dizziness',1,'XE0q7',NULL,'H/O: vertigo/Menieres disease'),('efi-dizziness',1,'F5614',NULL,'Otogenic vertigo'),('efi-dizziness',1,'Xa0Qo',NULL,'Peripheral positional vertigo'),('efi-dizziness',1,'X00jo',NULL,'Peripheral vestibular vertigo'),('efi-dizziness',1,'F5610',NULL,'Unspecified peripheral vertigo'),('efi-dizziness',1,'F562.',NULL,'Central vestibular vertigo'),('efi-dizziness',1,'X00jh',NULL,'Vertebrobasilar ischaemic vertigo'),('efi-dizziness',1,'1491.',NULL,'H/O: vertigo &/or Menieres disease'),('efi-dizziness',1,'XaBCM',NULL,'Benign paroxysmal positional vertigo nystagmus'),('efi-dizziness',1,'X00jc',NULL,'Benign recurrent vertigo'),('efi-dizziness',1,'XM0ys',NULL,'Vertigo NEC        [D]'),('efi-dizziness',1,'X00jb',NULL,'Migrainous vertigo'),('efi-dizziness',1,'F562z',NULL,'Vertigo of central origin NOS'),('efi-dizziness',1,'Xa0Qp',NULL,'Central positional vertigo'),('efi-dizziness',1,'FyuQ1',NULL,'[X]Other peripheral vertigo'),('efi-dizziness',1,'F561z',NULL,'Other peripheral vertigo NOS'),('efi-dizziness',1,'X00jl',NULL,'Psychogenic vertigo'),('efi-dizziness',1,'XE1A9',NULL,'Central nystagmus &/or vertigo'),('efi-dizziness',1,'X00jg',NULL,'Ocular vertigo'),('efi-dizziness',1,'X00ji',NULL,'Cervical vertigo'),('efi-dizziness',1,'XC07f',NULL,'Dizziness'),('efi-dizziness',1,'R0040',NULL,'[D]Dizziness'),('efi-dizziness',1,'1B53.',NULL,'Dizziness present'),('efi-dizziness',1,'R004.',NULL,'[D]Dizziness and giddiness'),('efi-dizziness',1,'XaFsA',NULL,'Dizzy spells'),('efi-dizziness',1,'F56..',NULL,'Disorders of the vestibular system and vertiginous syndromes');
INSERT INTO #codesctv3
VALUES ('efi-dyspnoea',1,'XE0qq',NULL,'Dyspnoea'),('efi-dyspnoea',1,'X76Gz',NULL,'Dyspnoea on exertion'),('efi-dyspnoea',1,'R0608',NULL,'[D]Shortness of breath'),('efi-dyspnoea',1,'173..',NULL,'(Symptom: [SOB]/[breathless]/[dyspnoea]) or (breathlessness)'),('efi-dyspnoea',1,'1734.',NULL,'Dyspnoea at rest'),('efi-dyspnoea',1,'173Z.',NULL,'Breathlessness NOS'),('efi-dyspnoea',1,'1732.',NULL,'Breathless - moderate exertion'),('efi-dyspnoea',1,'1733.',NULL,'Breathless - mild exertion'),('efi-dyspnoea',1,'XaIUn',NULL,'MRC Breathlessness Scale: grade 4'),('efi-dyspnoea',1,'1738.',NULL,'Difficulty breathing'),('efi-dyspnoea',1,'1734.',NULL,'Dyspnoea at rest'),('efi-dyspnoea',1,'R060A',NULL,'[D]Dyspnoea'),('efi-dyspnoea',1,'Y9125',NULL,'Shortness of breath        [D]'),('efi-dyspnoea',1,'2322.',NULL,'O/E - dyspnoea');
INSERT INTO #codesctv3
VALUES ('efi-falls',1,'Y3356',NULL,'Unable to get off floor'),('efi-falls',1,'TC...',NULL,'Accidental fall'),('efi-falls',1,'16D..',NULL,'Falls'),('efi-falls',1,'Xa6uG',NULL,'Observation of falls'),('efi-falls',1,'TCz..',NULL,'Accidental falls NOS'),('efi-falls',1,'Xa1GP',NULL,'Recurrent falls'),('efi-falls',1,'Xa6uH',NULL,'Elderly fall'),('efi-falls',1,'TC5..',NULL,'Fall on same level from slipping, tripping or stumbling'),('efi-falls',1,'XaLqJ',NULL,'Referral to falls service'),('efi-falls',1,'XaMGj',NULL,'Referral to elderly falls prevention clinic'),('efi-falls',1,'XaN4s',NULL,'Provision of telecare community alarm service'),('efi-falls',1,'YA756',NULL,'Has pendant alarm services');
INSERT INTO #codesctv3
VALUES ('efi-housebound',1,'13CA.',NULL,'Housebound'),('efi-housebound',1,'9NF1.',NULL,'Home visit request by patient'),('efi-housebound',1,'Xa8Jx',NULL,'Unable to transfer'),('efi-housebound',1,'9NF3.',NULL,'Home visit request by relative'),('efi-housebound',1,'9NF8.',NULL,'Acute home visit'),('efi-housebound',1,'9NF2.',NULL,'Home visit planned by doctor'),('efi-housebound',1,'XaJLP',NULL,'Home visit planned by healthcare professional'),('efi-housebound',1,'Ua2Cd',NULL,'Joint home visit'),('efi-housebound',1,'9NF9.',NULL,'Chronic home visit'),('efi-housebound',1,'9N1C.',NULL,'(Seen in own home) or (home visit)'),('efi-housebound',1,'9NFB.',NULL,'Home visit elderly assessment'),('efi-housebound',1,'Xa9Tg',NULL,'Unable to change position'),('efi-housebound',1,'9NF..',NULL,'Home visit admin'),('efi-housebound',1,'8HL..',NULL,'Domiciliary visit received'),('efi-housebound',1,'XaBQf',NULL,'Home visit');
INSERT INTO #codesctv3
VALUES ('efi-mobility-problems',1,'Ua1nH',NULL,'Reduced mobility'),('efi-mobility-problems',1,'Xa81L',NULL,'Unable to manage steps'),('efi-mobility-problems',1,'1381.',NULL,'Exercise physically impossible'),('efi-mobility-problems',1,'8D4..',NULL,'Mobility aids'),('efi-mobility-problems',1,'Ub0sN',NULL,'Provision of pressure relief equipment'),('efi-mobility-problems',1,'YA136',NULL,'Unable to get in car'),('efi-mobility-problems',1,'YA137',NULL,'Unable to get out of car'),('efi-mobility-problems',1,'Xa82K',NULL,'Unable to get off a bed'),('efi-mobility-problems',1,'Xa82E',NULL,'Unable to get on a bed'),('efi-mobility-problems',1,'XaJi6',NULL,'Dependent on helper pushing wheelchair'),('efi-mobility-problems',1,'Xa2F9',NULL,'Ability to stand from sitting'),('efi-mobility-problems',1,'Xa822',NULL,'Unable to get out of a chair'),('efi-mobility-problems',1,'X74UI',NULL,'Provision of mobility device'),('efi-mobility-problems',1,'Xa20j',NULL,'Unable to walk'),('efi-mobility-problems',1,'Xa82W',NULL,'Unable to roll over in bed'),('efi-mobility-problems',1,'Xa80X',NULL,'Ability to mobilise outside'),('efi-mobility-problems',1,'Xa80x',NULL,'Unable to manage stairs'),('efi-mobility-problems',1,'Y1906',NULL,'Evidence of pressure mattress, cushion in use'),('efi-mobility-problems',1,'Xa8Jx',NULL,'Unable to transfer'),('efi-mobility-problems',1,'13CE.',NULL,'Mobility poor'),('efi-mobility-problems',1,'13C2.',NULL,'Mobile outside with aid'),('efi-mobility-problems',1,'13C4.',NULL,'Needs walking aid in home'),('efi-mobility-problems',1,'39B..',NULL,'Walking aid use'),('efi-mobility-problems',1,'Xa8Aa',NULL,'Difficulty mobilising'),('efi-mobility-problems',1,'Xa3UL',NULL,'Unable to carry prepared food'),('efi-mobility-problems',1,'Xa80l',NULL,'Unable to mobilise using wheelchair'),('efi-mobility-problems',1,'N097.',NULL,'Difficulty in walking'),('efi-mobility-problems',1,'Xa21f',NULL,'Unable to initiate walking'),('efi-mobility-problems',1,'Xa2FB',NULL,'Unable to stand from sitting'),('efi-mobility-problems',1,'Xa2F5',NULL,'Unable to stand up alone'),('efi-mobility-problems',1,'Y0a72',NULL,'Mobility - Slightly Limited'),('efi-mobility-problems',1,'13CD.',NULL,'Mobility very poor'),('efi-mobility-problems',1,'Xa82c',NULL,'Unable to move up and down bed'),('efi-mobility-problems',1,'Xa2Ei',NULL,'Unable to maintain a standing position');
INSERT INTO #codesctv3
VALUES ('efi-sleep-disturbance',1,'R005.',NULL,'[D]Sleep disturbances'),('efi-sleep-disturbance',1,'R0050',NULL,'[D]Sleep disturbance, unspecified'),('efi-sleep-disturbance',1,'XE2cd',NULL,'[D]Sleep disturbances (& [hypersomnia] or [insomnia])'),('efi-sleep-disturbance',1,'XaFqr',NULL,'Poor sleep pattern'),('efi-sleep-disturbance',1,'R0052',NULL,'[D]Insomnia NOS'),('efi-sleep-disturbance',1,'XE0ux',NULL,'Insomnia (& symptom) or somnolence'),('efi-sleep-disturbance',1,'E274.',NULL,'Non-organic sleep disorders (& [hypersomnia] or [insomnia])'),('efi-sleep-disturbance',1,'XM0CT',NULL,'C/O - insomnia'),('efi-sleep-disturbance',1,'1B1B.',NULL,'Insomnia (& C/O)'),('efi-sleep-disturbance',1,'XE2Pv',NULL,'Insomnia'),('efi-sleep-disturbance',1,'XE2Q5',NULL,'Non-organic sleep disorder');
INSERT INTO #codesctv3
VALUES ('efi-social-vulnerability',1,'1335.',NULL,'Widowed'),('efi-social-vulnerability',1,'ZV603',NULL,'[V]Person living alone'),('efi-social-vulnerability',1,'13M1.',NULL,'Death of spouse'),('efi-social-vulnerability',1,'XaAey',NULL,'Referral to Social Services'),('efi-social-vulnerability',1,'XaLKF',NULL,'Under care of social services'),('efi-social-vulnerability',1,'Y1095',NULL,'Service Involved: Social services'),('efi-social-vulnerability',1,'XaJvD',NULL,'Does not have a carer'),('efi-social-vulnerability',1,'XaMz6',NULL,'Widowed/surviving civil partner'),('efi-social-vulnerability',1,'XM1Zk',NULL,'No carer'),('efi-social-vulnerability',1,'13G4.',NULL,'Social worker involved'),('efi-social-vulnerability',1,'XaKXv',NULL,'Vulnerable adult'),('efi-social-vulnerability',1,'13F3.',NULL,'Lives alone -no help available'),('efi-social-vulnerability',1,'YA791',NULL,'Lives in temporary accommodation'),('efi-social-vulnerability',1,'XM0Ct',NULL,'Lives alone'),('efi-social-vulnerability',1,'XaBSr',NULL,'Referral to social worker'),('efi-social-vulnerability',1,'8I5..',NULL,'Care/help refused by patient'),('efi-social-vulnerability',1,'13Z8.',NULL,'Social problem'),('efi-social-vulnerability',1,'XE0oy',NULL,'Housing problems'),('efi-social-vulnerability',1,'XaINl',NULL,'Death of partner');
INSERT INTO #codesctv3
VALUES ('efi-urinary-incontinence',1,'1A23.',NULL,'Urinary incontinence'),('efi-urinary-incontinence',1,'1A26.',NULL,'Urge incontinence of urine'),('efi-urinary-incontinence',1,'XE0rR',NULL,'Genuine stress incontinence'),('efi-urinary-incontinence',1,'K586.',NULL,'Stress incontinence - female'),('efi-urinary-incontinence',1,'1593.',NULL,'H/O: stress incontinence'),('efi-urinary-incontinence',1,'R083.',NULL,'[D]Incontinence of urine'),('efi-urinary-incontinence',1,'R0832',NULL,'[D] Urge incontinence'),('efi-urinary-incontinence',1,'1A24.',NULL,'Stress incontinence (& symptom)'),('efi-urinary-incontinence',1,'X76Xh',NULL,'Frequency of incontinence'),('efi-urinary-incontinence',1,'XaJtx',NULL,'Referral to incontinence clinic'),('efi-urinary-incontinence',1,'X30ON',NULL,'Post-micturition incontinence'),('efi-urinary-incontinence',1,'X30C5',NULL,'Double incontinence'),('efi-urinary-incontinence',1,'X30OI',NULL,'Giggle incontinence of urine'),('efi-urinary-incontinence',1,'R083z',NULL,'[D]Incontinence of urine NOS'),('efi-urinary-incontinence',1,'X30OK',NULL,'Reflex incontinence of urine'),('efi-urinary-incontinence',1,'X30OJ',NULL,'Overflow incontinence of urine'),('efi-urinary-incontinence',1,'Kyu5A',NULL,'[X]Other specified urinary incontinence'),('efi-urinary-incontinence',1,'q3...',NULL,'Incontinence sheath'),('efi-urinary-incontinence',1,'gd...',NULL,'Drugs for enuresis, urinary frequency and incontinence'),('efi-urinary-incontinence',1,'XE0gn',NULL,'Stress incontinence (& [female])'),('efi-urinary-incontinence',1,'R0831',NULL,'[D]Urethral sphincter incontinence'),('efi-urinary-incontinence',1,'X30OH',NULL,'Cough - urge incontinence of urine'),('efi-urinary-incontinence',1,'X30F3',NULL,'Bladder neck operation for female stress incontinence'),('efi-urinary-incontinence',1,'8D7..',NULL,'Incontinence control (& bladder)'),('efi-urinary-incontinence',1,'X30OL',NULL,'Urinary sphincter weakness incontinence'),('efi-urinary-incontinence',1,'x00oF',NULL,'Incontinence sheath+self adhesive liner'),('efi-urinary-incontinence',1,'Xa3t7',NULL,'Urinary incontinence/sling operation'),('efi-urinary-incontinence',1,'X30OP',NULL,'Urinary incontinence of non-organic origin'),('efi-urinary-incontinence',1,'X30OQ',NULL,'Dependency urinary incontinence'),('efi-urinary-incontinence',1,'XE0Gh',NULL,'Implantation of bulbar urethral prosthesis for incontinence'),('efi-urinary-incontinence',1,'Xa9G7',NULL,'Bladder neck incompetence'),('efi-urinary-incontinence',1,'XaMAm',NULL,'Insertion retropubic device stress urinary incontinence NEC'),('efi-urinary-incontinence',1,'XaMtf',NULL,'Insertion retropubic dev fem stress urinary incontinence NEC'),('efi-urinary-incontinence',1,'X30Fl',NULL,'Activation of bulbar urethral prosthesis for incontinence'),('efi-urinary-incontinence',1,'X30OO',NULL,'Postural urinary incontinence'),('efi-urinary-incontinence',1,'X30OR',NULL,'Psychogenic urinary incontinence'),('efi-urinary-incontinence',1,'X76Xj',NULL,'Unaware of passing urine'),('efi-urinary-incontinence',1,'3941.',NULL,'Bladder: occasional accident'),('efi-urinary-incontinence',1,'3940.',NULL,'Bladder: incontinent');
INSERT INTO #codesctv3
VALUES ('efi-weight-loss',1,'X76CA',NULL,'Weight loss'),('efi-weight-loss',1,'XE0qb',NULL,'Abnormal weight loss'),('efi-weight-loss',1,'1625.',NULL,'Abnormal weight loss (& [symptom])'),('efi-weight-loss',1,'XaKwR',NULL,'Complaining of weight loss'),('efi-weight-loss',1,'XaQgK',NULL,'Unexplained weight loss'),('efi-weight-loss',1,'XaXTs',NULL,'Unintentional weight loss'),('efi-weight-loss',1,'XaIxC',NULL,'Weight loss from baseline weight'),('efi-weight-loss',1,'XE0uH',NULL,'Weight loss (& abnormal)'),('efi-weight-loss',1,'XaBmk',NULL,'Excessive weight loss'),('efi-weight-loss',1,'Ua1iv',NULL,'Decrease in appetite'),('efi-weight-loss',1,'1623.',NULL,'Weight decreasing'),('efi-weight-loss',1,'R032.',NULL,'[D]Abnormal loss of weight'),('efi-weight-loss',1,'XE24f',NULL,'Appetite loss - anorexia'),('efi-weight-loss',1,'R0300',NULL,'[D]Appetite loss')

INSERT INTO #AllCodes
SELECT [concept], [version], [code], [description] from #codesctv3;

IF OBJECT_ID('tempdb..#codessnomed') IS NOT NULL DROP TABLE #codessnomed;
CREATE TABLE #codessnomed (
  [concept] [varchar](255) NOT NULL,
  [version] INT NOT NULL,
	[code] [varchar](20) COLLATE Latin1_General_CS_AS NOT NULL,
	[term] [varchar](20) COLLATE Latin1_General_CS_AS NULL,
	[description] [varchar](255) NULL
) ON [PRIMARY];



INSERT INTO #AllCodes
SELECT [concept], [version], [code], [description] from #codessnomed;

IF OBJECT_ID('tempdb..#codesemis') IS NOT NULL DROP TABLE #codesemis;
CREATE TABLE #codesemis (
  [concept] [varchar](255) NOT NULL,
  [version] INT NOT NULL,
	[code] [varchar](20) COLLATE Latin1_General_CS_AS NOT NULL,
	[term] [varchar](20) COLLATE Latin1_General_CS_AS NULL,
	[description] [varchar](255) NULL
) ON [PRIMARY];



INSERT INTO #AllCodes
SELECT [concept], [version], [code], [description] from #codesemis;


IF OBJECT_ID('tempdb..#TempRefCodes') IS NOT NULL DROP TABLE #TempRefCodes;
CREATE TABLE #TempRefCodes (FK_Reference_Coding_ID BIGINT NOT NULL, concept VARCHAR(255) NOT NULL, version INT NOT NULL, [description] VARCHAR(255));

-- Read v2 codes
INSERT INTO #TempRefCodes
SELECT PK_Reference_Coding_ID, dcr.concept, dcr.[version], dcr.[description]
FROM [SharedCare].[Reference_Coding] rc
INNER JOIN #codesreadv2 dcr on dcr.code = rc.MainCode
WHERE CodingType='ReadCodeV2'
AND (dcr.term IS NULL OR dcr.term = rc.Term)
and PK_Reference_Coding_ID != -1;

-- CTV3 codes
INSERT INTO #TempRefCodes
SELECT PK_Reference_Coding_ID, dcc.concept, dcc.[version], dcc.[description]
FROM [SharedCare].[Reference_Coding] rc
INNER JOIN #codesctv3 dcc on dcc.code = rc.MainCode
WHERE CodingType='CTV3'
and PK_Reference_Coding_ID != -1;

-- EMIS codes with a FK Reference Coding ID
INSERT INTO #TempRefCodes
SELECT FK_Reference_Coding_ID, ce.concept, ce.[version], ce.[description]
FROM [SharedCare].[Reference_Local_Code] rlc
INNER JOIN #codesemis ce on ce.code = rlc.LocalCode
WHERE FK_Reference_Coding_ID != -1;

IF OBJECT_ID('tempdb..#TempSNOMEDRefCodes') IS NOT NULL DROP TABLE #TempSNOMEDRefCodes;
CREATE TABLE #TempSNOMEDRefCodes (FK_Reference_SnomedCT_ID BIGINT NOT NULL, concept VARCHAR(255) NOT NULL, [version] INT NOT NULL, [description] VARCHAR(255));

-- SNOMED codes
INSERT INTO #TempSNOMEDRefCodes
SELECT PK_Reference_SnomedCT_ID, dcs.concept, dcs.[version], dcs.[description]
FROM SharedCare.Reference_SnomedCT rs
INNER JOIN #codessnomed dcs on dcs.code = rs.ConceptID;

-- EMIS codes with a FK SNOMED ID but without a FK Reference Coding ID
INSERT INTO #TempSNOMEDRefCodes
SELECT FK_Reference_SnomedCT_ID, ce.concept, ce.[version], ce.[description]
FROM [SharedCare].[Reference_Local_Code] rlc
INNER JOIN #codesemis ce on ce.code = rlc.LocalCode
WHERE FK_Reference_Coding_ID = -1
AND FK_Reference_SnomedCT_ID != -1;

-- De-duped tables
IF OBJECT_ID('tempdb..#CodeSets') IS NOT NULL DROP TABLE #CodeSets;
CREATE TABLE #CodeSets (FK_Reference_Coding_ID BIGINT NOT NULL, concept VARCHAR(255) NOT NULL, [description] VARCHAR(255));

IF OBJECT_ID('tempdb..#SnomedSets') IS NOT NULL DROP TABLE #SnomedSets;
CREATE TABLE #SnomedSets (FK_Reference_SnomedCT_ID BIGINT NOT NULL, concept VARCHAR(255) NOT NULL, [description] VARCHAR(255));

IF OBJECT_ID('tempdb..#VersionedCodeSets') IS NOT NULL DROP TABLE #VersionedCodeSets;
CREATE TABLE #VersionedCodeSets (FK_Reference_Coding_ID BIGINT NOT NULL, Concept VARCHAR(255), [Version] INT, [description] VARCHAR(255));

IF OBJECT_ID('tempdb..#VersionedSnomedSets') IS NOT NULL DROP TABLE #VersionedSnomedSets;
CREATE TABLE #VersionedSnomedSets (FK_Reference_SnomedCT_ID BIGINT NOT NULL, Concept VARCHAR(255), [Version] INT, [description] VARCHAR(255));

INSERT INTO #VersionedCodeSets
SELECT DISTINCT * FROM #TempRefCodes;

INSERT INTO #VersionedSnomedSets
SELECT DISTINCT * FROM #TempSNOMEDRefCodes;

INSERT INTO #CodeSets
SELECT FK_Reference_Coding_ID, c.concept, [description]
FROM #VersionedCodeSets c
INNER JOIN (
  SELECT concept, MAX(version) AS maxVersion FROM #VersionedCodeSets
  GROUP BY concept)
sub ON sub.concept = c.concept AND c.version = sub.maxVersion;

INSERT INTO #SnomedSets
SELECT FK_Reference_SnomedCT_ID, c.concept, [description]
FROM #VersionedSnomedSets c
INNER JOIN (
  SELECT concept, MAX(version) AS maxVersion FROM #VersionedSnomedSets
  GROUP BY concept)
sub ON sub.concept = c.concept AND c.version = sub.maxVersion;

--#endregion

-- >>> Following code sets injected: efi-arthritis v1

-- To optimise the patient event data table further (as there are so many patients),
-- we can initially split it into 3:
-- 1. Patients with a SuppliedCode in our list
IF OBJECT_ID('tempdb..#PatientEventData1') IS NOT NULL DROP TABLE #PatientEventData1;
SELECT 
  FK_Patient_Link_ID,
  CAST(EventDate AS DATE) AS EventDate,
  SuppliedCode,
  FK_Reference_SnomedCT_ID,
  FK_Reference_Coding_ID,
  [Value]
INTO #PatientEventData1
FROM [SharedCare].GP_Events
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND	SuppliedCode IN (SELECT Code FROM #AllCodes)
AND EventDate < '2022-06-01';
-- 1m

-- 2. Patients with a FK_Reference_Coding_ID in our list
IF OBJECT_ID('tempdb..#PatientEventData2') IS NOT NULL DROP TABLE #PatientEventData2;
SELECT 
  FK_Patient_Link_ID,
  CAST(EventDate AS DATE) AS EventDate,
  SuppliedCode,
  FK_Reference_SnomedCT_ID,
  FK_Reference_Coding_ID,
  [Value]
INTO #PatientEventData2
FROM [SharedCare].GP_Events
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND	FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets)
AND EventDate < '2022-06-01';
--29s

-- 3. Patients with a FK_Reference_SnomedCT_ID in our list
IF OBJECT_ID('tempdb..#PatientEventData3') IS NOT NULL DROP TABLE #PatientEventData3;
SELECT 
  FK_Patient_Link_ID,
  CAST(EventDate AS DATE) AS EventDate,
  SuppliedCode,
  FK_Reference_SnomedCT_ID,
  FK_Reference_Coding_ID,
  [Value]
INTO #PatientEventData3
FROM [SharedCare].GP_Events
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets)
AND EventDate < '2022-06-01';

IF OBJECT_ID('tempdb..#PatientEventData') IS NOT NULL DROP TABLE #PatientEventData;
SELECT * INTO #PatientEventData FROM #PatientEventData1
UNION
SELECT * FROM #PatientEventData2
UNION
SELECT * FROM #PatientEventData3;

-- Improve performance later with an index (creates in ~1 minute - saves loads more than that)
DROP INDEX IF EXISTS eventData ON #PatientEventData;
CREATE INDEX eventData ON #PatientEventData (SuppliedCode) INCLUDE (FK_Patient_Link_ID, EventDate, [Value]);

-- Get the EFI over time
--┌────────────────────────────────────┐
--│ Calcluate Electronic Frailty Index │
--└────────────────────────────────────┘

-- OBJECTIVE: To calculate the EFI for all patients and how it has changed over time

-- INPUT: Takes one parameter
--	- gp-events-table: string - (table name) the name of the table containing the GP events. Usually is "SharedCare.GP_Events" but can be anything with the columns: FK_Patient_Link_ID, EventDate, and SuppliedCode
-- And assumes there is a temp table #Patients (this can't be run on all patients at present as it takes too long)

-- OUTPUT: One temp tables as follows:
--	#PatientEFIOverTime (FK_Patient_Link_ID, NumberOfDeficits, DateFrom)
--	- FK_Patient_Link_ID - unique patient id
--	- DateFrom - the date from which the patient had this number of deficits
--	- NumberOfDeficits - the number of deficits (e.g. 3)

-- Most of the logic occurs in the following subquery, which is also used
-- in the query-patients-calculate-efi-on-date.sql query
--┌────────────────────────────────────────┐
--│ Electronic Frailty Index common queries│
--└────────────────────────────────────────┘

-- OBJECTIVE: The common logic for 2 EFI queries. This is unlikely to be executed directly, but is used by the other queries.

-- INPUT: Takes three parameters
--	- gp-events-table: string - (table name) the name of the table containing the GP events. Usually is "SharedCare.GP_Events" but can be anything with the columns: FK_Patient_Link_ID, EventDate, and SuppliedCode

-- OUTPUT: Two temp tables as follows:
--	#EfiEvents (FK_Patient_Link_ID,	Deficit, EventDate)
--	- FK_Patient_Link_ID - unique patient id
--	- Deficit - the deficit (e.g. 'diabetes/hypertension/falls')
--	- EventDate - the first occurance of the deficit
--
--	#PolypharmacyPeriods (FK_Patient_Link_ID,	DateFrom,	DateTo)
--	- FK_Patient_Link_ID - unique patient id
--	- DateFrom - the start date of the polypharmacy period
--	- DateTo - the end date of the polypharmacy period

-- First we load all the EFI specific code sets
-- >>> Following code sets injected: efi-activity-limitation v1/efi-anaemia v1/efi-arthritis v1/efi-atrial-fibrillation v1/efi-chd v1/efi-ckd v1
-- >>> Following code sets injected: efi-diabetes v1/efi-dizziness v1/efi-dyspnoea v1/efi-falls v1/efi-foot-problems v1/efi-fragility-fracture v1
-- >>> Following code sets injected: efi-hearing-loss v1/efi-heart-failure v1/efi-heart-valve-disease v1/efi-housebound v1/efi-hypertension v1
-- >>> Following code sets injected: efi-hypotension v1/efi-cognitive-problems v1/efi-mobility-problems v1/efi-osteoporosis v1
-- >>> Following code sets injected: efi-parkinsons v1/efi-peptic-ulcer v1/efi-pvd v1/efi-care-requirement v1/efi-respiratory-disease v1
-- >>> Following code sets injected: efi-skin-ulcer v1/efi-sleep-disturbance v1/efi-social-vulnerability v1/efi-stroke-tia v1/efi-thyroid-disorders v1
-- >>> Following code sets injected: efi-urinary-incontinence v1/efi-urinary-system-disease v1/efi-vision-problems v1/efi-weight-loss v1

-- Temp table for holding results of the subqueries below
IF OBJECT_ID('tempdb..#EfiEvents') IS NOT NULL DROP TABLE #EfiEvents;
CREATE TABLE #EfiEvents (
	FK_Patient_Link_ID BIGINT,
	Deficit VARCHAR(50),
	EventDate DATE
);

--#region EFI deficits (non-medication - and non-value)
-- The following finds the first date for each (non-medication) deficit for each patient and adds them to the #EfiEvents table.

INSERT INTO #EfiEvents
SELECT FK_Patient_Link_ID, 'activity-limitation' AS Deficit, MIN(CONVERT(DATE, [EventDate])) AS EventDate
FROM #PatientEventData
WHERE SuppliedCode IN (
  select Code from #AllCodes 
  where Concept = 'efi-activity-limitation'
  AND Version = 1
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate <= GETDATE()
GROUP BY FK_Patient_Link_ID;

INSERT INTO #EfiEvents
SELECT FK_Patient_Link_ID, 'anaemia' AS Deficit, MIN(CONVERT(DATE, [EventDate])) AS EventDate
FROM #PatientEventData
WHERE SuppliedCode IN (
  select Code from #AllCodes 
  where Concept = 'efi-anaemia'
  AND Version = 1
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate <= GETDATE()
GROUP BY FK_Patient_Link_ID;

INSERT INTO #EfiEvents
SELECT FK_Patient_Link_ID, 'arthritis' AS Deficit, MIN(CONVERT(DATE, [EventDate])) AS EventDate
FROM #PatientEventData
WHERE SuppliedCode IN (
  select Code from #AllCodes 
  where Concept = 'efi-arthritis'
  AND Version = 1
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate <= GETDATE()
GROUP BY FK_Patient_Link_ID;

INSERT INTO #EfiEvents
SELECT FK_Patient_Link_ID, 'atrial-fibrillation' AS Deficit, MIN(CONVERT(DATE, [EventDate])) AS EventDate
FROM #PatientEventData
WHERE SuppliedCode IN (
  select Code from #AllCodes 
  where Concept = 'efi-atrial-fibrillation'
  AND Version = 1
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate <= GETDATE()
GROUP BY FK_Patient_Link_ID;

INSERT INTO #EfiEvents
SELECT FK_Patient_Link_ID, 'chd' AS Deficit, MIN(CONVERT(DATE, [EventDate])) AS EventDate
FROM #PatientEventData
WHERE SuppliedCode IN (
  select Code from #AllCodes 
  where Concept = 'efi-chd'
  AND Version = 1
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate <= GETDATE()
GROUP BY FK_Patient_Link_ID;

INSERT INTO #EfiEvents
SELECT FK_Patient_Link_ID, 'ckd' AS Deficit, MIN(CONVERT(DATE, [EventDate])) AS EventDate
FROM #PatientEventData
WHERE SuppliedCode IN (
  select Code from #AllCodes 
  where Concept = 'efi-ckd'
  AND Version = 1
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate <= GETDATE()
GROUP BY FK_Patient_Link_ID;

INSERT INTO #EfiEvents
SELECT FK_Patient_Link_ID, 'diabetes' AS Deficit, MIN(CONVERT(DATE, [EventDate])) AS EventDate
FROM #PatientEventData
WHERE SuppliedCode IN (
  select Code from #AllCodes 
  where Concept = 'efi-diabetes'
  AND Version = 1
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate <= GETDATE()
GROUP BY FK_Patient_Link_ID;

INSERT INTO #EfiEvents
SELECT FK_Patient_Link_ID, 'dizziness' AS Deficit, MIN(CONVERT(DATE, [EventDate])) AS EventDate
FROM #PatientEventData
WHERE SuppliedCode IN (
  select Code from #AllCodes 
  where Concept = 'efi-dizziness'
  AND Version = 1
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate <= GETDATE()
GROUP BY FK_Patient_Link_ID;

INSERT INTO #EfiEvents
SELECT FK_Patient_Link_ID, 'dyspnoea' AS Deficit, MIN(CONVERT(DATE, [EventDate])) AS EventDate
FROM #PatientEventData
WHERE SuppliedCode IN (
  select Code from #AllCodes 
  where Concept = 'efi-dyspnoea'
  AND Version = 1
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate <= GETDATE()
GROUP BY FK_Patient_Link_ID;

INSERT INTO #EfiEvents
SELECT FK_Patient_Link_ID, 'falls' AS Deficit, MIN(CONVERT(DATE, [EventDate])) AS EventDate
FROM #PatientEventData
WHERE SuppliedCode IN (
  select Code from #AllCodes 
  where Concept = 'efi-falls'
  AND Version = 1
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate <= GETDATE()
GROUP BY FK_Patient_Link_ID;

INSERT INTO #EfiEvents
SELECT FK_Patient_Link_ID, 'foot-problems' AS Deficit, MIN(CONVERT(DATE, [EventDate])) AS EventDate
FROM #PatientEventData
WHERE SuppliedCode IN (
  select Code from #AllCodes 
  where Concept = 'efi-foot-problems'
  AND Version = 1
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate <= GETDATE()
GROUP BY FK_Patient_Link_ID;

INSERT INTO #EfiEvents
SELECT FK_Patient_Link_ID, 'fragility-fracture' AS Deficit, MIN(CONVERT(DATE, [EventDate])) AS EventDate
FROM #PatientEventData
WHERE SuppliedCode IN (
  select Code from #AllCodes 
  where Concept = 'efi-fragility-fracture'
  AND Version = 1
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate <= GETDATE()
GROUP BY FK_Patient_Link_ID;

INSERT INTO #EfiEvents
SELECT FK_Patient_Link_ID, 'hearing-loss' AS Deficit, MIN(CONVERT(DATE, [EventDate])) AS EventDate
FROM #PatientEventData
WHERE SuppliedCode IN (
  select Code from #AllCodes 
  where Concept = 'efi-hearing-loss'
  AND Version = 1
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate <= GETDATE()
GROUP BY FK_Patient_Link_ID;

INSERT INTO #EfiEvents
SELECT FK_Patient_Link_ID, 'heart-failure' AS Deficit, MIN(CONVERT(DATE, [EventDate])) AS EventDate
FROM #PatientEventData
WHERE SuppliedCode IN (
  select Code from #AllCodes 
  where Concept = 'efi-heart-failure'
  AND Version = 1
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate <= GETDATE()
GROUP BY FK_Patient_Link_ID;

INSERT INTO #EfiEvents
SELECT FK_Patient_Link_ID, 'heart-valve-disease' AS Deficit, MIN(CONVERT(DATE, [EventDate])) AS EventDate
FROM #PatientEventData
WHERE SuppliedCode IN (
  select Code from #AllCodes 
  where Concept = 'efi-heart-valve-disease'
  AND Version = 1
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate <= GETDATE()
GROUP BY FK_Patient_Link_ID;

INSERT INTO #EfiEvents
SELECT FK_Patient_Link_ID, 'housebound' AS Deficit, MIN(CONVERT(DATE, [EventDate])) AS EventDate
FROM #PatientEventData
WHERE SuppliedCode IN (
  select Code from #AllCodes 
  where Concept = 'efi-housebound'
  AND Version = 1
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate <= GETDATE()
GROUP BY FK_Patient_Link_ID;

INSERT INTO #EfiEvents
SELECT FK_Patient_Link_ID, 'hypertension' AS Deficit, MIN(CONVERT(DATE, [EventDate])) AS EventDate
FROM #PatientEventData
WHERE SuppliedCode IN (
  select Code from #AllCodes 
  where Concept = 'efi-hypertension'
  AND Version = 1
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate <= GETDATE()
GROUP BY FK_Patient_Link_ID;

INSERT INTO #EfiEvents
SELECT FK_Patient_Link_ID, 'hypotension' AS Deficit, MIN(CONVERT(DATE, [EventDate])) AS EventDate
FROM #PatientEventData
WHERE SuppliedCode IN (
  select Code from #AllCodes 
  where Concept = 'efi-hypotension'
  AND Version = 1
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate <= GETDATE()
GROUP BY FK_Patient_Link_ID;

INSERT INTO #EfiEvents
SELECT FK_Patient_Link_ID, 'cognitive-problems' AS Deficit, MIN(CONVERT(DATE, [EventDate])) AS EventDate
FROM #PatientEventData
WHERE SuppliedCode IN (
  select Code from #AllCodes 
  where Concept = 'efi-cognitive-problems'
  AND Version = 1
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate <= GETDATE()
GROUP BY FK_Patient_Link_ID;

INSERT INTO #EfiEvents
SELECT FK_Patient_Link_ID, 'mobility-problems' AS Deficit, MIN(CONVERT(DATE, [EventDate])) AS EventDate
FROM #PatientEventData
WHERE SuppliedCode IN (
  select Code from #AllCodes 
  where Concept = 'efi-mobility-problems'
  AND Version = 1
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate <= GETDATE()
GROUP BY FK_Patient_Link_ID;

INSERT INTO #EfiEvents
SELECT FK_Patient_Link_ID, 'osteoporosis' AS Deficit, MIN(CONVERT(DATE, [EventDate])) AS EventDate
FROM #PatientEventData
WHERE SuppliedCode IN (
  select Code from #AllCodes 
  where Concept = 'efi-osteoporosis'
  AND Version = 1
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate <= GETDATE()
GROUP BY FK_Patient_Link_ID;

INSERT INTO #EfiEvents
SELECT FK_Patient_Link_ID, 'parkinsons' AS Deficit, MIN(CONVERT(DATE, [EventDate])) AS EventDate
FROM #PatientEventData
WHERE SuppliedCode IN (
  select Code from #AllCodes 
  where Concept = 'efi-parkinsons'
  AND Version = 1
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate <= GETDATE()
GROUP BY FK_Patient_Link_ID;

INSERT INTO #EfiEvents
SELECT FK_Patient_Link_ID, 'peptic-ulcer' AS Deficit, MIN(CONVERT(DATE, [EventDate])) AS EventDate
FROM #PatientEventData
WHERE SuppliedCode IN (
  select Code from #AllCodes 
  where Concept = 'efi-peptic-ulcer'
  AND Version = 1
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate <= GETDATE()
GROUP BY FK_Patient_Link_ID;

INSERT INTO #EfiEvents
SELECT FK_Patient_Link_ID, 'pvd' AS Deficit, MIN(CONVERT(DATE, [EventDate])) AS EventDate
FROM #PatientEventData
WHERE SuppliedCode IN (
  select Code from #AllCodes 
  where Concept = 'efi-pvd'
  AND Version = 1
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate <= GETDATE()
GROUP BY FK_Patient_Link_ID;

INSERT INTO #EfiEvents
SELECT FK_Patient_Link_ID, 'care-requirement' AS Deficit, MIN(CONVERT(DATE, [EventDate])) AS EventDate
FROM #PatientEventData
WHERE SuppliedCode IN (
  select Code from #AllCodes 
  where Concept = 'efi-care-requirement'
  AND Version = 1
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate <= GETDATE()
GROUP BY FK_Patient_Link_ID;

INSERT INTO #EfiEvents
SELECT FK_Patient_Link_ID, 'respiratory-disease' AS Deficit, MIN(CONVERT(DATE, [EventDate])) AS EventDate
FROM #PatientEventData
WHERE SuppliedCode IN (
  select Code from #AllCodes 
  where Concept = 'efi-respiratory-disease'
  AND Version = 1
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate <= GETDATE()
GROUP BY FK_Patient_Link_ID;

INSERT INTO #EfiEvents
SELECT FK_Patient_Link_ID, 'skin-ulcer' AS Deficit, MIN(CONVERT(DATE, [EventDate])) AS EventDate
FROM #PatientEventData
WHERE SuppliedCode IN (
  select Code from #AllCodes 
  where Concept = 'efi-skin-ulcer'
  AND Version = 1
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate <= GETDATE()
GROUP BY FK_Patient_Link_ID;

INSERT INTO #EfiEvents
SELECT FK_Patient_Link_ID, 'sleep-disturbance' AS Deficit, MIN(CONVERT(DATE, [EventDate])) AS EventDate
FROM #PatientEventData
WHERE SuppliedCode IN (
  select Code from #AllCodes 
  where Concept = 'efi-sleep-disturbance'
  AND Version = 1
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate <= GETDATE()
GROUP BY FK_Patient_Link_ID;

INSERT INTO #EfiEvents
SELECT FK_Patient_Link_ID, 'social-vulnerability' AS Deficit, MIN(CONVERT(DATE, [EventDate])) AS EventDate
FROM #PatientEventData
WHERE SuppliedCode IN (
  select Code from #AllCodes 
  where Concept = 'efi-social-vulnerability'
  AND Version = 1
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate <= GETDATE()
GROUP BY FK_Patient_Link_ID;

INSERT INTO #EfiEvents
SELECT FK_Patient_Link_ID, 'stroke-tia' AS Deficit, MIN(CONVERT(DATE, [EventDate])) AS EventDate
FROM #PatientEventData
WHERE SuppliedCode IN (
  select Code from #AllCodes 
  where Concept = 'efi-stroke-tia'
  AND Version = 1
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate <= GETDATE()
GROUP BY FK_Patient_Link_ID;

INSERT INTO #EfiEvents
SELECT FK_Patient_Link_ID, 'thyroid-disorders' AS Deficit, MIN(CONVERT(DATE, [EventDate])) AS EventDate
FROM #PatientEventData
WHERE SuppliedCode IN (
  select Code from #AllCodes 
  where Concept = 'efi-thyroid-disorders'
  AND Version = 1
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate <= GETDATE()
GROUP BY FK_Patient_Link_ID;

INSERT INTO #EfiEvents
SELECT FK_Patient_Link_ID, 'urinary-incontinence' AS Deficit, MIN(CONVERT(DATE, [EventDate])) AS EventDate
FROM #PatientEventData
WHERE SuppliedCode IN (
  select Code from #AllCodes 
  where Concept = 'efi-urinary-incontinence'
  AND Version = 1
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate <= GETDATE()
GROUP BY FK_Patient_Link_ID;

INSERT INTO #EfiEvents
SELECT FK_Patient_Link_ID, 'urinary-system-disease' AS Deficit, MIN(CONVERT(DATE, [EventDate])) AS EventDate
FROM #PatientEventData
WHERE SuppliedCode IN (
  select Code from #AllCodes 
  where Concept = 'efi-urinary-system-disease'
  AND Version = 1
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate <= GETDATE()
GROUP BY FK_Patient_Link_ID;

INSERT INTO #EfiEvents
SELECT FK_Patient_Link_ID, 'vision-problems' AS Deficit, MIN(CONVERT(DATE, [EventDate])) AS EventDate
FROM #PatientEventData
WHERE SuppliedCode IN (
  select Code from #AllCodes 
  where Concept = 'efi-vision-problems'
  AND Version = 1
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate <= GETDATE()
GROUP BY FK_Patient_Link_ID;

INSERT INTO #EfiEvents
SELECT FK_Patient_Link_ID, 'weight-loss' AS Deficit, MIN(CONVERT(DATE, [EventDate])) AS EventDate
FROM #PatientEventData
WHERE SuppliedCode IN (
  select Code from #AllCodes 
  where Concept = 'efi-weight-loss'
  AND Version = 1
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate <= GETDATE()
GROUP BY FK_Patient_Link_ID;
--#endregion

--#region EFI deficits from values rather than diagnoses
-- First populate a temp table with values for codes of interest
IF OBJECT_ID('tempdb..#EfiValueData') IS NOT NULL DROP TABLE #EfiValueData;
SELECT FK_Patient_Link_ID, CONVERT(DATE, [EventDate]) AS EventDate, SuppliedCode, [Value]
INTO #EfiValueData
FROM #PatientEventData
WHERE SuppliedCode IN ('16D2.','246V.','246W.','38DE.','39F..','3AD3.','423..','442A.','442W.','44lD.','451E.','451F.','46N..','46N4.','46N7.','46TC.','46W..','585a.','58EE.','66Yf.','687C.','XaJLG','XaF4O','XaF4b','XaP9J','Y1259','Y1258','XaIup','XaK8U','YA310','Y01e7','XaJv3','XE2eH','XE2eG','XaEMS','XE2eI','XE2n3','XE2bw','XSFyN','XaIz7','XaITU','XE2wy','XaELV','39C..','XC0tc','XM0an','XE2m6','Xa96v','Y3351','XaISO','XaZpN','XaK8y','XaMDA','XacUJ','XacUK')
AND [Value] IS NOT NULL AND UPPER([Value]) NOT LIKE '%[A-Z]%'  -- EXTRA CHECKS IN CASE ANY NULL OR TEXT VALUES REMAINED
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate <= GETDATE();

-- Some value ranges depend on the patient's sex
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
FROM SharedCare.Patient p
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND Sex IS NOT NULL;


-- If patients have a tenancy id of 2 we take this as their most likely Sex
-- as this is the GP data feed and so most likely to be up to date
IF OBJECT_ID('tempdb..#PatientSex') IS NOT NULL DROP TABLE #PatientSex;
SELECT FK_Patient_Link_ID, MIN(Sex) as Sex INTO #PatientSex FROM #AllPatientSexs
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND FK_Reference_Tenancy_ID = 2
GROUP BY FK_Patient_Link_ID
HAVING MIN(Sex) = MAX(Sex);

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

-- Tidy up - helpful in ensuring the tempdb doesn't run out of space mid-query
DROP TABLE #AllPatientSexs;
DROP TABLE #UnmatchedSexPatients;

-- Create temp tables with all Males and all Females
IF OBJECT_ID('tempdb..#MalePatients') IS NOT NULL DROP TABLE #MalePatients;
SELECT FK_Patient_Link_ID INTO #MalePatients FROM #PatientSex
WHERE Sex = 'M'
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients);

IF OBJECT_ID('tempdb..#FemalePatients') IS NOT NULL DROP TABLE #FemalePatients;
SELECT FK_Patient_Link_ID INTO #FemalePatients FROM #PatientSex
WHERE Sex = 'F'
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients);

-- FALLS included if the "number of falls in last 12 months" is >0

INSERT INTO #EfiEvents
SELECT FK_Patient_Link_ID, 'falls' AS Deficit, MIN(CONVERT(DATE, [EventDate])) AS EventDate
FROM #EfiValueData
WHERE SuppliedCode IN ('Y3351','XaISO','16D2.')
AND TRY_CONVERT(NUMERIC (18,5), [Value]) > 0
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate <= GETDATE()
GROUP BY FK_Patient_Link_ID;

-- HYPERTENSION included if avg 24hr diastolic >85

INSERT INTO #EfiEvents
SELECT FK_Patient_Link_ID, 'hypertension' AS Deficit, MIN(CONVERT(DATE, [EventDate])) AS EventDate
FROM #EfiValueData
WHERE SuppliedCode IN ('246V.','XaF4b')
AND TRY_CONVERT(NUMERIC (18,5), [Value]) > 85
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate <= GETDATE()
GROUP BY FK_Patient_Link_ID;

-- HYPERTENSION included if avg 24hr systolic >135

INSERT INTO #EfiEvents
SELECT FK_Patient_Link_ID, 'hypertension' AS Deficit, MIN(CONVERT(DATE, [EventDate])) AS EventDate
FROM #EfiValueData
WHERE SuppliedCode IN ('246W.','XaF4O')
AND TRY_CONVERT(NUMERIC (18,5), [Value]) > 135
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate <= GETDATE()
GROUP BY FK_Patient_Link_ID;

-- AF included if any score

INSERT INTO #EfiEvents
SELECT FK_Patient_Link_ID, 'atrial-fibrillation' AS Deficit, MIN(CONVERT(DATE, [EventDate])) AS EventDate
FROM #EfiValueData
WHERE SuppliedCode IN ('38DE.','XaP9J')
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate <= GETDATE()
GROUP BY FK_Patient_Link_ID;

-- ACTIVITY LIMITATION if Barthel<=18 then deficit

INSERT INTO #EfiEvents
SELECT FK_Patient_Link_ID, 'activity-limitation' AS Deficit, MIN(CONVERT(DATE, [EventDate])) AS EventDate
FROM #EfiValueData
WHERE SuppliedCode IN ('39F..','XM0an')
AND TRY_CONVERT(NUMERIC (18,5), [Value]) < 18.1
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate <= GETDATE()
GROUP BY FK_Patient_Link_ID;

-- Memory & cognitive problems if Six item cognitive impairment test >=8

INSERT INTO #EfiEvents
SELECT FK_Patient_Link_ID, 'cognitive-problems' AS Deficit, MIN(CONVERT(DATE, [EventDate])) AS EventDate
FROM #EfiValueData
WHERE SuppliedCode IN ('3AD3.','XaJLG')
AND TRY_CONVERT(NUMERIC (18,5), [Value]) > 7.9
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate <= GETDATE()
GROUP BY FK_Patient_Link_ID;

-- Anaemia if haemaglobin is below reference range. (From Andy Clegg)
-- - Males <13, >25, <130, Females <11.5, >25, <115 (to take account of unit changes)

INSERT INTO #EfiEvents
SELECT FK_Patient_Link_ID, 'anaemia' AS Deficit, MIN(CONVERT(DATE, [EventDate])) AS EventDate
FROM #EfiValueData
WHERE SuppliedCode IN ('423..','XE2m6','Xa96v')
AND TRY_CONVERT(NUMERIC (18,5), [Value]) > 25
AND TRY_CONVERT(NUMERIC (18,5), [Value]) < 130
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #MalePatients)
AND EventDate <= GETDATE()
GROUP BY FK_Patient_Link_ID;

INSERT INTO #EfiEvents
SELECT FK_Patient_Link_ID, 'anaemia' AS Deficit, MIN(CONVERT(DATE, [EventDate])) AS EventDate
FROM #EfiValueData
WHERE SuppliedCode IN ('423..','XE2m6','Xa96v')
AND TRY_CONVERT(NUMERIC (18,5), [Value]) > 0
AND TRY_CONVERT(NUMERIC (18,5), [Value]) < 13
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #MalePatients)
AND EventDate <= GETDATE()
GROUP BY FK_Patient_Link_ID;

INSERT INTO #EfiEvents
SELECT FK_Patient_Link_ID, 'anaemia' AS Deficit, MIN(CONVERT(DATE, [EventDate])) AS EventDate
FROM #EfiValueData
WHERE SuppliedCode IN ('423..','XE2m6','Xa96v')
AND TRY_CONVERT(NUMERIC (18,5), [Value]) > 25
AND TRY_CONVERT(NUMERIC (18,5), [Value]) < 115
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #FemalePatients)
AND EventDate <= GETDATE()
GROUP BY FK_Patient_Link_ID;

INSERT INTO #EfiEvents
SELECT FK_Patient_Link_ID, 'anaemia' AS Deficit, MIN(CONVERT(DATE, [EventDate])) AS EventDate
FROM #EfiValueData
WHERE SuppliedCode IN ('423..','XE2m6','Xa96v')
AND TRY_CONVERT(NUMERIC (18,5), [Value]) > 0
AND TRY_CONVERT(NUMERIC (18,5), [Value]) < 11.5
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #FemalePatients)
AND EventDate <= GETDATE()
GROUP BY FK_Patient_Link_ID;

-- Thyroid problems if TSH outside of 0.36-5.5

INSERT INTO #EfiEvents
SELECT FK_Patient_Link_ID, 'thyroid-disorders' AS Deficit, MIN(CONVERT(DATE, [EventDate])) AS EventDate
FROM #EfiValueData
WHERE SuppliedCode IN ('442A.','442W.','XE2wy','XaELV')
AND TRY_CONVERT(NUMERIC (18,5), [Value]) > 0
AND TRY_CONVERT(NUMERIC (18,5), [Value]) < 0.36
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate <= GETDATE()
GROUP BY FK_Patient_Link_ID;

INSERT INTO #EfiEvents
SELECT FK_Patient_Link_ID, 'thyroid-disorders' AS Deficit, MIN(CONVERT(DATE, [EventDate])) AS EventDate
FROM #EfiValueData
WHERE SuppliedCode IN ('442A.','442W.','XE2wy','XaELV')
AND TRY_CONVERT(NUMERIC (18,5), [Value]) > 5.5
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate <= GETDATE()
GROUP BY FK_Patient_Link_ID;

-- Chronic kidney disease if Glomerular filtration rate <60

INSERT INTO #EfiEvents
SELECT FK_Patient_Link_ID, 'ckd' AS Deficit, MIN(CONVERT(DATE, [EventDate])) AS EventDate
FROM #EfiValueData
WHERE SuppliedCode IN ('451E.','451F.','XSFyN','XaZpN','XaK8y','XaMDA','XacUJ','XacUK')
AND TRY_CONVERT(NUMERIC (18,5), [Value]) > 0
AND TRY_CONVERT(NUMERIC (18,5), [Value]) < 60
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate <= GETDATE()
GROUP BY FK_Patient_Link_ID;

-- Chronic kidney disease if Urine protein (from AC) >150mg/24hr

INSERT INTO #EfiEvents
SELECT FK_Patient_Link_ID, 'ckd' AS Deficit, MIN(CONVERT(DATE, [EventDate])) AS EventDate
FROM #EfiValueData
WHERE SuppliedCode IN ('46N..','XE2eH','XE2eG')
AND TRY_CONVERT(NUMERIC (18,5), [Value]) > 150
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate <= GETDATE()
GROUP BY FK_Patient_Link_ID;

-- Chronic kidney disease if Urine albumin (from AC) >20mg/24hr

INSERT INTO #EfiEvents
SELECT FK_Patient_Link_ID, 'ckd' AS Deficit, MIN(CONVERT(DATE, [EventDate])) AS EventDate
FROM #EfiValueData
WHERE SuppliedCode IN ('XE2eI','46N4.')
AND TRY_CONVERT(NUMERIC (18,5), [Value]) > 20
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate <= GETDATE()
GROUP BY FK_Patient_Link_ID;

-- Chronic kidney disease if Urine protein/creatinine index (from AC) >50mg/mmol

INSERT INTO #EfiEvents
SELECT FK_Patient_Link_ID, 'ckd' AS Deficit, MIN(CONVERT(DATE, [EventDate])) AS EventDate
FROM #EfiValueData
WHERE SuppliedCode IN ('46N7.','XaIz7','XaEMS')
AND TRY_CONVERT(NUMERIC (18,5), [Value]) > 50
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate <= GETDATE()
GROUP BY FK_Patient_Link_ID;

-- Chronic kidney disease if Urine albumin:creatinine ratio (from AC) >3mg/mmol

INSERT INTO #EfiEvents
SELECT FK_Patient_Link_ID, 'ckd' AS Deficit, MIN(CONVERT(DATE, [EventDate])) AS EventDate
FROM #EfiValueData
WHERE SuppliedCode IN ('XE2n3','46TC.')
AND TRY_CONVERT(NUMERIC (18,5), [Value]) > 3
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate <= GETDATE()
GROUP BY FK_Patient_Link_ID;

-- Chronic kidney disease if Urine microalbumin (from AC) >3mg/mmol

INSERT INTO #EfiEvents
SELECT FK_Patient_Link_ID, 'ckd' AS Deficit, MIN(CONVERT(DATE, [EventDate])) AS EventDate
FROM #EfiValueData
WHERE SuppliedCode IN ('46W..','XE2bw')
AND TRY_CONVERT(NUMERIC (18,5), [Value]) > 3
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate <= GETDATE()
GROUP BY FK_Patient_Link_ID;


-- Peripheral vascular disease if ABPI < 0.95

INSERT INTO #EfiEvents
SELECT FK_Patient_Link_ID, 'pvd' AS Deficit, MIN(CONVERT(DATE, [EventDate])) AS EventDate
FROM #EfiValueData
WHERE SuppliedCode IN ('585a.','Y1259','Y1258','XaIup')
AND TRY_CONVERT(NUMERIC (18,5), [Value]) > 0
AND TRY_CONVERT(NUMERIC (18,5), [Value]) < 0.95
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate <= GETDATE()
GROUP BY FK_Patient_Link_ID;

-- Osteoporosis if Hip DXA scan T score <= -2.5

INSERT INTO #EfiEvents
SELECT FK_Patient_Link_ID, 'osteoporosis' AS Deficit, MIN(CONVERT(DATE, [EventDate])) AS EventDate
FROM #EfiValueData
WHERE SuppliedCode IN ('XaITU','58EE.')
AND TRY_CONVERT(NUMERIC (18,5), [Value]) < -2.499
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate <= GETDATE()
GROUP BY FK_Patient_Link_ID;

-- Respiratory problems if Number of COPD exacerbations in past year OR Number of hours of oxygen therapy per day OR
-- Number of unscheduled encounters for COPD in the last 12 months >= 1

INSERT INTO #EfiEvents
SELECT FK_Patient_Link_ID, 'respiratory-disease' AS Deficit, MIN(CONVERT(DATE, [EventDate])) AS EventDate
FROM #EfiValueData
WHERE SuppliedCode IN ('66Yf.','XaK8U','YA310','Y01e7')
AND TRY_CONVERT(NUMERIC (18,5), [Value]) > 0.9
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate <= GETDATE()
GROUP BY FK_Patient_Link_ID;

-- Weight loss/anorexia if Malnutrition universal screening tool score >= 1

INSERT INTO #EfiEvents
SELECT FK_Patient_Link_ID, 'weight-loss' AS Deficit, MIN(CONVERT(DATE, [EventDate])) AS EventDate
FROM #EfiValueData
WHERE SuppliedCode IN ('687C.','XaJv3')
AND TRY_CONVERT(NUMERIC (18,5), [Value]) > 0.9999
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate <= GETDATE()
GROUP BY FK_Patient_Link_ID;
--#endregion

--#region Polypharmacy - the 36th EFI deficit

-- UPDATE Andy Clegg algorithm is for 5 different meds in a 12 month period. Maybe
-- we should define it in both ways - and allow sensitivity analysis
-- The following is a look back so gives number of meds in 12 months prior to a prescription

--┌──────────────────────────────────────────┐
--│ Patient medication data splitter for EFI │
--└──────────────────────────────────────────┘

-- OBJECTIVE: Split the medication data into chunks to improve performance

-- First get the medication data for this chunk of patients
IF OBJECT_ID('tempdb..#PatientMedicationData0') IS NOT NULL DROP TABLE [#PatientMedicationData0];
SELECT 
  FK_Patient_Link_ID,
  CAST(MedicationDate AS DATE) AS MedicationDate,
  SuppliedCode
INTO [#PatientMedicationData0]
FROM [SharedCare].GP_Medications
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND ABS(FK_Patient_Link_ID) % 10 = 0
AND MedicationDate < '2022-06-01'; --TODO TEMP POST COPI FIX

-- Improve performance later with an index
DROP INDEX IF EXISTS [medData0] ON [#PatientMedicationData0];
CREATE INDEX [medData0] ON [#PatientMedicationData0] (FK_Patient_Link_ID, MedicationDate) INCLUDE (SuppliedCode);

IF OBJECT_ID('tempdb..#PatientMedDataTempTable0') IS NOT NULL DROP TABLE [#PatientMedDataTempTable0];
SELECT
  FK_Patient_Link_ID,
  SuppliedCode, 
  LAG(MedicationDate, 1) OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS PreviousDate,
  MedicationDate, 
  LEAD(MedicationDate, 1) OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS NextDate,
  ROW_NUMBER() OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS rn
INTO [#PatientMedDataTempTable0]
FROM [#PatientMedicationData0];
-- 56s

DELETE FROM [#PatientMedDataTempTable0]
WHERE DATEDIFF(YEAR, PreviousDate, NextDate) = 0
AND rn % 2 = 0;
--25s

DECLARE @LastDeletedNumber0 INT; 
SET @LastDeletedNumber0=10001;
WHILE ( @LastDeletedNumber0 > 10000)
BEGIN
  IF OBJECT_ID('tempdb..#PatientMedDataTempTableHolding0') IS NOT NULL DROP TABLE [#PatientMedDataTempTableHolding0];
  SELECT FK_Patient_Link_ID, SuppliedCode, 
        LAG(MedicationDate, 1) OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS PreviousDate  ,MedicationDate, 
      LEAD(MedicationDate, 1) OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS NextDate ,
      ROW_NUMBER() OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS rn
  INTO [#PatientMedDataTempTableHolding0]
  FROM [#PatientMedDataTempTable0];

  DELETE FROM [#PatientMedDataTempTableHolding0]
  WHERE DATEDIFF(YEAR, PreviousDate, NextDate) = 0
  AND rn % 2 = 0;

  TRUNCATE TABLE #PatientMedDataTempTable0;
  INSERT INTO #PatientMedDataTempTable0
  SELECT FK_Patient_Link_ID, SuppliedCode, 
        LAG(MedicationDate, 1) OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS PreviousDate  ,MedicationDate, 
      LEAD(MedicationDate, 1) OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS NextDate ,
      ROW_NUMBER() OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS rn
  FROM [#PatientMedDataTempTableHolding0];

  DELETE FROM [#PatientMedDataTempTable0]
  WHERE DATEDIFF(YEAR, PreviousDate, NextDate) = 0
  AND rn % 2 = 0;

  SELECT @LastDeletedNumber0=@@ROWCOUNT;
END

-- Improve performance later with an index
DROP INDEX IF EXISTS [xx0] ON [#PatientMedDataTempTable0];
CREATE INDEX [xx0] ON [#PatientMedDataTempTable0] (FK_Patient_Link_ID, MedicationDate) INCLUDE (SuppliedCode);

IF OBJECT_ID('tempdb..#PolypharmDates5InLastYear0') IS NOT NULL DROP TABLE #PolypharmDates5InLastYear0;
SELECT m1.FK_Patient_Link_ID, m1.[MedicationDate] AS PotentialPolypharmStartDate
INTO #PolypharmDates5InLastYear0
FROM [#PatientMedDataTempTable0] m1
LEFT OUTER JOIN [#PatientMedDataTempTable0] m2
	ON m1.FK_Patient_Link_ID = m2.FK_Patient_Link_ID
	AND m1.[MedicationDate] >= m2.[MedicationDate]
	AND m1.[MedicationDate] < DATEADD(year, 1, m2.[MedicationDate])
GROUP BY m1.FK_Patient_Link_ID, m1.[MedicationDate]
HAVING COUNT(DISTINCT m2.SuppliedCode) >= 5;

-- Next is a look forward from the day after a medication. This will deal with the stop events
IF OBJECT_ID('tempdb..#PolypharmStopDates5InLastYear0') IS NOT NULL DROP TABLE #PolypharmStopDates5InLastYear0;
SELECT m1.FK_Patient_Link_ID, DATEADD(year, 1, m1.[MedicationDate]) AS PotentialPolypharmEndDate
INTO #PolypharmStopDates5InLastYear0
FROM [#PatientMedDataTempTable0] m1
LEFT OUTER JOIN [#PatientMedDataTempTable0] m2
	ON m1.FK_Patient_Link_ID = m2.FK_Patient_Link_ID
	AND DATEADD(year, 1, m1.[MedicationDate]) >= m2.[MedicationDate]
	AND DATEADD(year, 1, m1.[MedicationDate]) < DATEADD(year, 1, m2.[MedicationDate])
GROUP BY m1.FK_Patient_Link_ID, DATEADD(year, 1, m1.[MedicationDate])
HAVING COUNT(DISTINCT m2.SuppliedCode) < 5;
--┌──────────────────────────────────────────┐
--│ Patient medication data splitter for EFI │
--└──────────────────────────────────────────┘

-- OBJECTIVE: Split the medication data into chunks to improve performance

-- First get the medication data for this chunk of patients
IF OBJECT_ID('tempdb..#PatientMedicationData1') IS NOT NULL DROP TABLE [#PatientMedicationData1];
SELECT 
  FK_Patient_Link_ID,
  CAST(MedicationDate AS DATE) AS MedicationDate,
  SuppliedCode
INTO [#PatientMedicationData1]
FROM [SharedCare].GP_Medications
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND ABS(FK_Patient_Link_ID) % 10 = 1
AND MedicationDate < '2022-06-01'; --TODO TEMP POST COPI FIX

-- Improve performance later with an index
DROP INDEX IF EXISTS [medData1] ON [#PatientMedicationData1];
CREATE INDEX [medData1] ON [#PatientMedicationData1] (FK_Patient_Link_ID, MedicationDate) INCLUDE (SuppliedCode);

IF OBJECT_ID('tempdb..#PatientMedDataTempTable1') IS NOT NULL DROP TABLE [#PatientMedDataTempTable1];
SELECT
  FK_Patient_Link_ID,
  SuppliedCode, 
  LAG(MedicationDate, 1) OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS PreviousDate,
  MedicationDate, 
  LEAD(MedicationDate, 1) OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS NextDate,
  ROW_NUMBER() OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS rn
INTO [#PatientMedDataTempTable1]
FROM [#PatientMedicationData1];
-- 56s

DELETE FROM [#PatientMedDataTempTable1]
WHERE DATEDIFF(YEAR, PreviousDate, NextDate) = 0
AND rn % 2 = 0;
--25s

DECLARE @LastDeletedNumber1 INT; 
SET @LastDeletedNumber1=10001;
WHILE ( @LastDeletedNumber1 > 10000)
BEGIN
  IF OBJECT_ID('tempdb..#PatientMedDataTempTableHolding1') IS NOT NULL DROP TABLE [#PatientMedDataTempTableHolding1];
  SELECT FK_Patient_Link_ID, SuppliedCode, 
        LAG(MedicationDate, 1) OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS PreviousDate  ,MedicationDate, 
      LEAD(MedicationDate, 1) OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS NextDate ,
      ROW_NUMBER() OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS rn
  INTO [#PatientMedDataTempTableHolding1]
  FROM [#PatientMedDataTempTable1];

  DELETE FROM [#PatientMedDataTempTableHolding1]
  WHERE DATEDIFF(YEAR, PreviousDate, NextDate) = 0
  AND rn % 2 = 0;

  TRUNCATE TABLE #PatientMedDataTempTable1;
  INSERT INTO #PatientMedDataTempTable1
  SELECT FK_Patient_Link_ID, SuppliedCode, 
        LAG(MedicationDate, 1) OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS PreviousDate  ,MedicationDate, 
      LEAD(MedicationDate, 1) OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS NextDate ,
      ROW_NUMBER() OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS rn
  FROM [#PatientMedDataTempTableHolding1];

  DELETE FROM [#PatientMedDataTempTable1]
  WHERE DATEDIFF(YEAR, PreviousDate, NextDate) = 0
  AND rn % 2 = 0;

  SELECT @LastDeletedNumber1=@@ROWCOUNT;
END

-- Improve performance later with an index
DROP INDEX IF EXISTS [xx1] ON [#PatientMedDataTempTable1];
CREATE INDEX [xx1] ON [#PatientMedDataTempTable1] (FK_Patient_Link_ID, MedicationDate) INCLUDE (SuppliedCode);

IF OBJECT_ID('tempdb..#PolypharmDates5InLastYear1') IS NOT NULL DROP TABLE #PolypharmDates5InLastYear1;
SELECT m1.FK_Patient_Link_ID, m1.[MedicationDate] AS PotentialPolypharmStartDate
INTO #PolypharmDates5InLastYear1
FROM [#PatientMedDataTempTable1] m1
LEFT OUTER JOIN [#PatientMedDataTempTable1] m2
	ON m1.FK_Patient_Link_ID = m2.FK_Patient_Link_ID
	AND m1.[MedicationDate] >= m2.[MedicationDate]
	AND m1.[MedicationDate] < DATEADD(year, 1, m2.[MedicationDate])
GROUP BY m1.FK_Patient_Link_ID, m1.[MedicationDate]
HAVING COUNT(DISTINCT m2.SuppliedCode) >= 5;

-- Next is a look forward from the day after a medication. This will deal with the stop events
IF OBJECT_ID('tempdb..#PolypharmStopDates5InLastYear1') IS NOT NULL DROP TABLE #PolypharmStopDates5InLastYear1;
SELECT m1.FK_Patient_Link_ID, DATEADD(year, 1, m1.[MedicationDate]) AS PotentialPolypharmEndDate
INTO #PolypharmStopDates5InLastYear1
FROM [#PatientMedDataTempTable1] m1
LEFT OUTER JOIN [#PatientMedDataTempTable1] m2
	ON m1.FK_Patient_Link_ID = m2.FK_Patient_Link_ID
	AND DATEADD(year, 1, m1.[MedicationDate]) >= m2.[MedicationDate]
	AND DATEADD(year, 1, m1.[MedicationDate]) < DATEADD(year, 1, m2.[MedicationDate])
GROUP BY m1.FK_Patient_Link_ID, DATEADD(year, 1, m1.[MedicationDate])
HAVING COUNT(DISTINCT m2.SuppliedCode) < 5;
--┌──────────────────────────────────────────┐
--│ Patient medication data splitter for EFI │
--└──────────────────────────────────────────┘

-- OBJECTIVE: Split the medication data into chunks to improve performance

-- First get the medication data for this chunk of patients
IF OBJECT_ID('tempdb..#PatientMedicationData2') IS NOT NULL DROP TABLE [#PatientMedicationData2];
SELECT 
  FK_Patient_Link_ID,
  CAST(MedicationDate AS DATE) AS MedicationDate,
  SuppliedCode
INTO [#PatientMedicationData2]
FROM [SharedCare].GP_Medications
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND ABS(FK_Patient_Link_ID) % 10 = 2
AND MedicationDate < '2022-06-01'; --TODO TEMP POST COPI FIX

-- Improve performance later with an index
DROP INDEX IF EXISTS [medData2] ON [#PatientMedicationData2];
CREATE INDEX [medData2] ON [#PatientMedicationData2] (FK_Patient_Link_ID, MedicationDate) INCLUDE (SuppliedCode);

IF OBJECT_ID('tempdb..#PatientMedDataTempTable2') IS NOT NULL DROP TABLE [#PatientMedDataTempTable2];
SELECT
  FK_Patient_Link_ID,
  SuppliedCode, 
  LAG(MedicationDate, 1) OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS PreviousDate,
  MedicationDate, 
  LEAD(MedicationDate, 1) OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS NextDate,
  ROW_NUMBER() OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS rn
INTO [#PatientMedDataTempTable2]
FROM [#PatientMedicationData2];
-- 56s

DELETE FROM [#PatientMedDataTempTable2]
WHERE DATEDIFF(YEAR, PreviousDate, NextDate) = 0
AND rn % 2 = 0;
--25s

DECLARE @LastDeletedNumber2 INT; 
SET @LastDeletedNumber2=10001;
WHILE ( @LastDeletedNumber2 > 10000)
BEGIN
  IF OBJECT_ID('tempdb..#PatientMedDataTempTableHolding2') IS NOT NULL DROP TABLE [#PatientMedDataTempTableHolding2];
  SELECT FK_Patient_Link_ID, SuppliedCode, 
        LAG(MedicationDate, 1) OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS PreviousDate  ,MedicationDate, 
      LEAD(MedicationDate, 1) OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS NextDate ,
      ROW_NUMBER() OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS rn
  INTO [#PatientMedDataTempTableHolding2]
  FROM [#PatientMedDataTempTable2];

  DELETE FROM [#PatientMedDataTempTableHolding2]
  WHERE DATEDIFF(YEAR, PreviousDate, NextDate) = 0
  AND rn % 2 = 0;

  TRUNCATE TABLE #PatientMedDataTempTable2;
  INSERT INTO #PatientMedDataTempTable2
  SELECT FK_Patient_Link_ID, SuppliedCode, 
        LAG(MedicationDate, 1) OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS PreviousDate  ,MedicationDate, 
      LEAD(MedicationDate, 1) OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS NextDate ,
      ROW_NUMBER() OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS rn
  FROM [#PatientMedDataTempTableHolding2];

  DELETE FROM [#PatientMedDataTempTable2]
  WHERE DATEDIFF(YEAR, PreviousDate, NextDate) = 0
  AND rn % 2 = 0;

  SELECT @LastDeletedNumber2=@@ROWCOUNT;
END

-- Improve performance later with an index
DROP INDEX IF EXISTS [xx2] ON [#PatientMedDataTempTable2];
CREATE INDEX [xx2] ON [#PatientMedDataTempTable2] (FK_Patient_Link_ID, MedicationDate) INCLUDE (SuppliedCode);

IF OBJECT_ID('tempdb..#PolypharmDates5InLastYear2') IS NOT NULL DROP TABLE #PolypharmDates5InLastYear2;
SELECT m1.FK_Patient_Link_ID, m1.[MedicationDate] AS PotentialPolypharmStartDate
INTO #PolypharmDates5InLastYear2
FROM [#PatientMedDataTempTable2] m1
LEFT OUTER JOIN [#PatientMedDataTempTable2] m2
	ON m1.FK_Patient_Link_ID = m2.FK_Patient_Link_ID
	AND m1.[MedicationDate] >= m2.[MedicationDate]
	AND m1.[MedicationDate] < DATEADD(year, 1, m2.[MedicationDate])
GROUP BY m1.FK_Patient_Link_ID, m1.[MedicationDate]
HAVING COUNT(DISTINCT m2.SuppliedCode) >= 5;

-- Next is a look forward from the day after a medication. This will deal with the stop events
IF OBJECT_ID('tempdb..#PolypharmStopDates5InLastYear2') IS NOT NULL DROP TABLE #PolypharmStopDates5InLastYear2;
SELECT m1.FK_Patient_Link_ID, DATEADD(year, 1, m1.[MedicationDate]) AS PotentialPolypharmEndDate
INTO #PolypharmStopDates5InLastYear2
FROM [#PatientMedDataTempTable2] m1
LEFT OUTER JOIN [#PatientMedDataTempTable2] m2
	ON m1.FK_Patient_Link_ID = m2.FK_Patient_Link_ID
	AND DATEADD(year, 1, m1.[MedicationDate]) >= m2.[MedicationDate]
	AND DATEADD(year, 1, m1.[MedicationDate]) < DATEADD(year, 1, m2.[MedicationDate])
GROUP BY m1.FK_Patient_Link_ID, DATEADD(year, 1, m1.[MedicationDate])
HAVING COUNT(DISTINCT m2.SuppliedCode) < 5;
--┌──────────────────────────────────────────┐
--│ Patient medication data splitter for EFI │
--└──────────────────────────────────────────┘

-- OBJECTIVE: Split the medication data into chunks to improve performance

-- First get the medication data for this chunk of patients
IF OBJECT_ID('tempdb..#PatientMedicationData3') IS NOT NULL DROP TABLE [#PatientMedicationData3];
SELECT 
  FK_Patient_Link_ID,
  CAST(MedicationDate AS DATE) AS MedicationDate,
  SuppliedCode
INTO [#PatientMedicationData3]
FROM [SharedCare].GP_Medications
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND ABS(FK_Patient_Link_ID) % 10 = 3
AND MedicationDate < '2022-06-01'; --TODO TEMP POST COPI FIX

-- Improve performance later with an index
DROP INDEX IF EXISTS [medData3] ON [#PatientMedicationData3];
CREATE INDEX [medData3] ON [#PatientMedicationData3] (FK_Patient_Link_ID, MedicationDate) INCLUDE (SuppliedCode);

IF OBJECT_ID('tempdb..#PatientMedDataTempTable3') IS NOT NULL DROP TABLE [#PatientMedDataTempTable3];
SELECT
  FK_Patient_Link_ID,
  SuppliedCode, 
  LAG(MedicationDate, 1) OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS PreviousDate,
  MedicationDate, 
  LEAD(MedicationDate, 1) OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS NextDate,
  ROW_NUMBER() OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS rn
INTO [#PatientMedDataTempTable3]
FROM [#PatientMedicationData3];
-- 56s

DELETE FROM [#PatientMedDataTempTable3]
WHERE DATEDIFF(YEAR, PreviousDate, NextDate) = 0
AND rn % 2 = 0;
--25s

DECLARE @LastDeletedNumber3 INT; 
SET @LastDeletedNumber3=10001;
WHILE ( @LastDeletedNumber3 > 10000)
BEGIN
  IF OBJECT_ID('tempdb..#PatientMedDataTempTableHolding3') IS NOT NULL DROP TABLE [#PatientMedDataTempTableHolding3];
  SELECT FK_Patient_Link_ID, SuppliedCode, 
        LAG(MedicationDate, 1) OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS PreviousDate  ,MedicationDate, 
      LEAD(MedicationDate, 1) OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS NextDate ,
      ROW_NUMBER() OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS rn
  INTO [#PatientMedDataTempTableHolding3]
  FROM [#PatientMedDataTempTable3];

  DELETE FROM [#PatientMedDataTempTableHolding3]
  WHERE DATEDIFF(YEAR, PreviousDate, NextDate) = 0
  AND rn % 2 = 0;

  TRUNCATE TABLE #PatientMedDataTempTable3;
  INSERT INTO #PatientMedDataTempTable3
  SELECT FK_Patient_Link_ID, SuppliedCode, 
        LAG(MedicationDate, 1) OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS PreviousDate  ,MedicationDate, 
      LEAD(MedicationDate, 1) OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS NextDate ,
      ROW_NUMBER() OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS rn
  FROM [#PatientMedDataTempTableHolding3];

  DELETE FROM [#PatientMedDataTempTable3]
  WHERE DATEDIFF(YEAR, PreviousDate, NextDate) = 0
  AND rn % 2 = 0;

  SELECT @LastDeletedNumber3=@@ROWCOUNT;
END

-- Improve performance later with an index
DROP INDEX IF EXISTS [xx3] ON [#PatientMedDataTempTable3];
CREATE INDEX [xx3] ON [#PatientMedDataTempTable3] (FK_Patient_Link_ID, MedicationDate) INCLUDE (SuppliedCode);

IF OBJECT_ID('tempdb..#PolypharmDates5InLastYear3') IS NOT NULL DROP TABLE #PolypharmDates5InLastYear3;
SELECT m1.FK_Patient_Link_ID, m1.[MedicationDate] AS PotentialPolypharmStartDate
INTO #PolypharmDates5InLastYear3
FROM [#PatientMedDataTempTable3] m1
LEFT OUTER JOIN [#PatientMedDataTempTable3] m2
	ON m1.FK_Patient_Link_ID = m2.FK_Patient_Link_ID
	AND m1.[MedicationDate] >= m2.[MedicationDate]
	AND m1.[MedicationDate] < DATEADD(year, 1, m2.[MedicationDate])
GROUP BY m1.FK_Patient_Link_ID, m1.[MedicationDate]
HAVING COUNT(DISTINCT m2.SuppliedCode) >= 5;

-- Next is a look forward from the day after a medication. This will deal with the stop events
IF OBJECT_ID('tempdb..#PolypharmStopDates5InLastYear3') IS NOT NULL DROP TABLE #PolypharmStopDates5InLastYear3;
SELECT m1.FK_Patient_Link_ID, DATEADD(year, 1, m1.[MedicationDate]) AS PotentialPolypharmEndDate
INTO #PolypharmStopDates5InLastYear3
FROM [#PatientMedDataTempTable3] m1
LEFT OUTER JOIN [#PatientMedDataTempTable3] m2
	ON m1.FK_Patient_Link_ID = m2.FK_Patient_Link_ID
	AND DATEADD(year, 1, m1.[MedicationDate]) >= m2.[MedicationDate]
	AND DATEADD(year, 1, m1.[MedicationDate]) < DATEADD(year, 1, m2.[MedicationDate])
GROUP BY m1.FK_Patient_Link_ID, DATEADD(year, 1, m1.[MedicationDate])
HAVING COUNT(DISTINCT m2.SuppliedCode) < 5;
--┌──────────────────────────────────────────┐
--│ Patient medication data splitter for EFI │
--└──────────────────────────────────────────┘

-- OBJECTIVE: Split the medication data into chunks to improve performance

-- First get the medication data for this chunk of patients
IF OBJECT_ID('tempdb..#PatientMedicationData4') IS NOT NULL DROP TABLE [#PatientMedicationData4];
SELECT 
  FK_Patient_Link_ID,
  CAST(MedicationDate AS DATE) AS MedicationDate,
  SuppliedCode
INTO [#PatientMedicationData4]
FROM [SharedCare].GP_Medications
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND ABS(FK_Patient_Link_ID) % 10 = 4
AND MedicationDate < '2022-06-01'; --TODO TEMP POST COPI FIX

-- Improve performance later with an index
DROP INDEX IF EXISTS [medData4] ON [#PatientMedicationData4];
CREATE INDEX [medData4] ON [#PatientMedicationData4] (FK_Patient_Link_ID, MedicationDate) INCLUDE (SuppliedCode);

IF OBJECT_ID('tempdb..#PatientMedDataTempTable4') IS NOT NULL DROP TABLE [#PatientMedDataTempTable4];
SELECT
  FK_Patient_Link_ID,
  SuppliedCode, 
  LAG(MedicationDate, 1) OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS PreviousDate,
  MedicationDate, 
  LEAD(MedicationDate, 1) OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS NextDate,
  ROW_NUMBER() OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS rn
INTO [#PatientMedDataTempTable4]
FROM [#PatientMedicationData4];
-- 56s

DELETE FROM [#PatientMedDataTempTable4]
WHERE DATEDIFF(YEAR, PreviousDate, NextDate) = 0
AND rn % 2 = 0;
--25s

DECLARE @LastDeletedNumber4 INT; 
SET @LastDeletedNumber4=10001;
WHILE ( @LastDeletedNumber4 > 10000)
BEGIN
  IF OBJECT_ID('tempdb..#PatientMedDataTempTableHolding4') IS NOT NULL DROP TABLE [#PatientMedDataTempTableHolding4];
  SELECT FK_Patient_Link_ID, SuppliedCode, 
        LAG(MedicationDate, 1) OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS PreviousDate  ,MedicationDate, 
      LEAD(MedicationDate, 1) OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS NextDate ,
      ROW_NUMBER() OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS rn
  INTO [#PatientMedDataTempTableHolding4]
  FROM [#PatientMedDataTempTable4];

  DELETE FROM [#PatientMedDataTempTableHolding4]
  WHERE DATEDIFF(YEAR, PreviousDate, NextDate) = 0
  AND rn % 2 = 0;

  TRUNCATE TABLE #PatientMedDataTempTable4;
  INSERT INTO #PatientMedDataTempTable4
  SELECT FK_Patient_Link_ID, SuppliedCode, 
        LAG(MedicationDate, 1) OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS PreviousDate  ,MedicationDate, 
      LEAD(MedicationDate, 1) OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS NextDate ,
      ROW_NUMBER() OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS rn
  FROM [#PatientMedDataTempTableHolding4];

  DELETE FROM [#PatientMedDataTempTable4]
  WHERE DATEDIFF(YEAR, PreviousDate, NextDate) = 0
  AND rn % 2 = 0;

  SELECT @LastDeletedNumber4=@@ROWCOUNT;
END

-- Improve performance later with an index
DROP INDEX IF EXISTS [xx4] ON [#PatientMedDataTempTable4];
CREATE INDEX [xx4] ON [#PatientMedDataTempTable4] (FK_Patient_Link_ID, MedicationDate) INCLUDE (SuppliedCode);

IF OBJECT_ID('tempdb..#PolypharmDates5InLastYear4') IS NOT NULL DROP TABLE #PolypharmDates5InLastYear4;
SELECT m1.FK_Patient_Link_ID, m1.[MedicationDate] AS PotentialPolypharmStartDate
INTO #PolypharmDates5InLastYear4
FROM [#PatientMedDataTempTable4] m1
LEFT OUTER JOIN [#PatientMedDataTempTable4] m2
	ON m1.FK_Patient_Link_ID = m2.FK_Patient_Link_ID
	AND m1.[MedicationDate] >= m2.[MedicationDate]
	AND m1.[MedicationDate] < DATEADD(year, 1, m2.[MedicationDate])
GROUP BY m1.FK_Patient_Link_ID, m1.[MedicationDate]
HAVING COUNT(DISTINCT m2.SuppliedCode) >= 5;

-- Next is a look forward from the day after a medication. This will deal with the stop events
IF OBJECT_ID('tempdb..#PolypharmStopDates5InLastYear4') IS NOT NULL DROP TABLE #PolypharmStopDates5InLastYear4;
SELECT m1.FK_Patient_Link_ID, DATEADD(year, 1, m1.[MedicationDate]) AS PotentialPolypharmEndDate
INTO #PolypharmStopDates5InLastYear4
FROM [#PatientMedDataTempTable4] m1
LEFT OUTER JOIN [#PatientMedDataTempTable4] m2
	ON m1.FK_Patient_Link_ID = m2.FK_Patient_Link_ID
	AND DATEADD(year, 1, m1.[MedicationDate]) >= m2.[MedicationDate]
	AND DATEADD(year, 1, m1.[MedicationDate]) < DATEADD(year, 1, m2.[MedicationDate])
GROUP BY m1.FK_Patient_Link_ID, DATEADD(year, 1, m1.[MedicationDate])
HAVING COUNT(DISTINCT m2.SuppliedCode) < 5;
--┌──────────────────────────────────────────┐
--│ Patient medication data splitter for EFI │
--└──────────────────────────────────────────┘

-- OBJECTIVE: Split the medication data into chunks to improve performance

-- First get the medication data for this chunk of patients
IF OBJECT_ID('tempdb..#PatientMedicationData5') IS NOT NULL DROP TABLE [#PatientMedicationData5];
SELECT 
  FK_Patient_Link_ID,
  CAST(MedicationDate AS DATE) AS MedicationDate,
  SuppliedCode
INTO [#PatientMedicationData5]
FROM [SharedCare].GP_Medications
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND ABS(FK_Patient_Link_ID) % 10 = 5
AND MedicationDate < '2022-06-01'; --TODO TEMP POST COPI FIX

-- Improve performance later with an index
DROP INDEX IF EXISTS [medData5] ON [#PatientMedicationData5];
CREATE INDEX [medData5] ON [#PatientMedicationData5] (FK_Patient_Link_ID, MedicationDate) INCLUDE (SuppliedCode);

IF OBJECT_ID('tempdb..#PatientMedDataTempTable5') IS NOT NULL DROP TABLE [#PatientMedDataTempTable5];
SELECT
  FK_Patient_Link_ID,
  SuppliedCode, 
  LAG(MedicationDate, 1) OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS PreviousDate,
  MedicationDate, 
  LEAD(MedicationDate, 1) OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS NextDate,
  ROW_NUMBER() OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS rn
INTO [#PatientMedDataTempTable5]
FROM [#PatientMedicationData5];
-- 56s

DELETE FROM [#PatientMedDataTempTable5]
WHERE DATEDIFF(YEAR, PreviousDate, NextDate) = 0
AND rn % 2 = 0;
--25s

DECLARE @LastDeletedNumber5 INT; 
SET @LastDeletedNumber5=10001;
WHILE ( @LastDeletedNumber5 > 10000)
BEGIN
  IF OBJECT_ID('tempdb..#PatientMedDataTempTableHolding5') IS NOT NULL DROP TABLE [#PatientMedDataTempTableHolding5];
  SELECT FK_Patient_Link_ID, SuppliedCode, 
        LAG(MedicationDate, 1) OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS PreviousDate  ,MedicationDate, 
      LEAD(MedicationDate, 1) OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS NextDate ,
      ROW_NUMBER() OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS rn
  INTO [#PatientMedDataTempTableHolding5]
  FROM [#PatientMedDataTempTable5];

  DELETE FROM [#PatientMedDataTempTableHolding5]
  WHERE DATEDIFF(YEAR, PreviousDate, NextDate) = 0
  AND rn % 2 = 0;

  TRUNCATE TABLE #PatientMedDataTempTable5;
  INSERT INTO #PatientMedDataTempTable5
  SELECT FK_Patient_Link_ID, SuppliedCode, 
        LAG(MedicationDate, 1) OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS PreviousDate  ,MedicationDate, 
      LEAD(MedicationDate, 1) OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS NextDate ,
      ROW_NUMBER() OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS rn
  FROM [#PatientMedDataTempTableHolding5];

  DELETE FROM [#PatientMedDataTempTable5]
  WHERE DATEDIFF(YEAR, PreviousDate, NextDate) = 0
  AND rn % 2 = 0;

  SELECT @LastDeletedNumber5=@@ROWCOUNT;
END

-- Improve performance later with an index
DROP INDEX IF EXISTS [xx5] ON [#PatientMedDataTempTable5];
CREATE INDEX [xx5] ON [#PatientMedDataTempTable5] (FK_Patient_Link_ID, MedicationDate) INCLUDE (SuppliedCode);

IF OBJECT_ID('tempdb..#PolypharmDates5InLastYear5') IS NOT NULL DROP TABLE #PolypharmDates5InLastYear5;
SELECT m1.FK_Patient_Link_ID, m1.[MedicationDate] AS PotentialPolypharmStartDate
INTO #PolypharmDates5InLastYear5
FROM [#PatientMedDataTempTable5] m1
LEFT OUTER JOIN [#PatientMedDataTempTable5] m2
	ON m1.FK_Patient_Link_ID = m2.FK_Patient_Link_ID
	AND m1.[MedicationDate] >= m2.[MedicationDate]
	AND m1.[MedicationDate] < DATEADD(year, 1, m2.[MedicationDate])
GROUP BY m1.FK_Patient_Link_ID, m1.[MedicationDate]
HAVING COUNT(DISTINCT m2.SuppliedCode) >= 5;

-- Next is a look forward from the day after a medication. This will deal with the stop events
IF OBJECT_ID('tempdb..#PolypharmStopDates5InLastYear5') IS NOT NULL DROP TABLE #PolypharmStopDates5InLastYear5;
SELECT m1.FK_Patient_Link_ID, DATEADD(year, 1, m1.[MedicationDate]) AS PotentialPolypharmEndDate
INTO #PolypharmStopDates5InLastYear5
FROM [#PatientMedDataTempTable5] m1
LEFT OUTER JOIN [#PatientMedDataTempTable5] m2
	ON m1.FK_Patient_Link_ID = m2.FK_Patient_Link_ID
	AND DATEADD(year, 1, m1.[MedicationDate]) >= m2.[MedicationDate]
	AND DATEADD(year, 1, m1.[MedicationDate]) < DATEADD(year, 1, m2.[MedicationDate])
GROUP BY m1.FK_Patient_Link_ID, DATEADD(year, 1, m1.[MedicationDate])
HAVING COUNT(DISTINCT m2.SuppliedCode) < 5;
--┌──────────────────────────────────────────┐
--│ Patient medication data splitter for EFI │
--└──────────────────────────────────────────┘

-- OBJECTIVE: Split the medication data into chunks to improve performance

-- First get the medication data for this chunk of patients
IF OBJECT_ID('tempdb..#PatientMedicationData6') IS NOT NULL DROP TABLE [#PatientMedicationData6];
SELECT 
  FK_Patient_Link_ID,
  CAST(MedicationDate AS DATE) AS MedicationDate,
  SuppliedCode
INTO [#PatientMedicationData6]
FROM [SharedCare].GP_Medications
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND ABS(FK_Patient_Link_ID) % 10 = 6
AND MedicationDate < '2022-06-01'; --TODO TEMP POST COPI FIX

-- Improve performance later with an index
DROP INDEX IF EXISTS [medData6] ON [#PatientMedicationData6];
CREATE INDEX [medData6] ON [#PatientMedicationData6] (FK_Patient_Link_ID, MedicationDate) INCLUDE (SuppliedCode);

IF OBJECT_ID('tempdb..#PatientMedDataTempTable6') IS NOT NULL DROP TABLE [#PatientMedDataTempTable6];
SELECT
  FK_Patient_Link_ID,
  SuppliedCode, 
  LAG(MedicationDate, 1) OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS PreviousDate,
  MedicationDate, 
  LEAD(MedicationDate, 1) OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS NextDate,
  ROW_NUMBER() OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS rn
INTO [#PatientMedDataTempTable6]
FROM [#PatientMedicationData6];
-- 56s

DELETE FROM [#PatientMedDataTempTable6]
WHERE DATEDIFF(YEAR, PreviousDate, NextDate) = 0
AND rn % 2 = 0;
--25s

DECLARE @LastDeletedNumber6 INT; 
SET @LastDeletedNumber6=10001;
WHILE ( @LastDeletedNumber6 > 10000)
BEGIN
  IF OBJECT_ID('tempdb..#PatientMedDataTempTableHolding6') IS NOT NULL DROP TABLE [#PatientMedDataTempTableHolding6];
  SELECT FK_Patient_Link_ID, SuppliedCode, 
        LAG(MedicationDate, 1) OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS PreviousDate  ,MedicationDate, 
      LEAD(MedicationDate, 1) OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS NextDate ,
      ROW_NUMBER() OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS rn
  INTO [#PatientMedDataTempTableHolding6]
  FROM [#PatientMedDataTempTable6];

  DELETE FROM [#PatientMedDataTempTableHolding6]
  WHERE DATEDIFF(YEAR, PreviousDate, NextDate) = 0
  AND rn % 2 = 0;

  TRUNCATE TABLE #PatientMedDataTempTable6;
  INSERT INTO #PatientMedDataTempTable6
  SELECT FK_Patient_Link_ID, SuppliedCode, 
        LAG(MedicationDate, 1) OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS PreviousDate  ,MedicationDate, 
      LEAD(MedicationDate, 1) OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS NextDate ,
      ROW_NUMBER() OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS rn
  FROM [#PatientMedDataTempTableHolding6];

  DELETE FROM [#PatientMedDataTempTable6]
  WHERE DATEDIFF(YEAR, PreviousDate, NextDate) = 0
  AND rn % 2 = 0;

  SELECT @LastDeletedNumber6=@@ROWCOUNT;
END

-- Improve performance later with an index
DROP INDEX IF EXISTS [xx6] ON [#PatientMedDataTempTable6];
CREATE INDEX [xx6] ON [#PatientMedDataTempTable6] (FK_Patient_Link_ID, MedicationDate) INCLUDE (SuppliedCode);

IF OBJECT_ID('tempdb..#PolypharmDates5InLastYear6') IS NOT NULL DROP TABLE #PolypharmDates5InLastYear6;
SELECT m1.FK_Patient_Link_ID, m1.[MedicationDate] AS PotentialPolypharmStartDate
INTO #PolypharmDates5InLastYear6
FROM [#PatientMedDataTempTable6] m1
LEFT OUTER JOIN [#PatientMedDataTempTable6] m2
	ON m1.FK_Patient_Link_ID = m2.FK_Patient_Link_ID
	AND m1.[MedicationDate] >= m2.[MedicationDate]
	AND m1.[MedicationDate] < DATEADD(year, 1, m2.[MedicationDate])
GROUP BY m1.FK_Patient_Link_ID, m1.[MedicationDate]
HAVING COUNT(DISTINCT m2.SuppliedCode) >= 5;

-- Next is a look forward from the day after a medication. This will deal with the stop events
IF OBJECT_ID('tempdb..#PolypharmStopDates5InLastYear6') IS NOT NULL DROP TABLE #PolypharmStopDates5InLastYear6;
SELECT m1.FK_Patient_Link_ID, DATEADD(year, 1, m1.[MedicationDate]) AS PotentialPolypharmEndDate
INTO #PolypharmStopDates5InLastYear6
FROM [#PatientMedDataTempTable6] m1
LEFT OUTER JOIN [#PatientMedDataTempTable6] m2
	ON m1.FK_Patient_Link_ID = m2.FK_Patient_Link_ID
	AND DATEADD(year, 1, m1.[MedicationDate]) >= m2.[MedicationDate]
	AND DATEADD(year, 1, m1.[MedicationDate]) < DATEADD(year, 1, m2.[MedicationDate])
GROUP BY m1.FK_Patient_Link_ID, DATEADD(year, 1, m1.[MedicationDate])
HAVING COUNT(DISTINCT m2.SuppliedCode) < 5;
--┌──────────────────────────────────────────┐
--│ Patient medication data splitter for EFI │
--└──────────────────────────────────────────┘

-- OBJECTIVE: Split the medication data into chunks to improve performance

-- First get the medication data for this chunk of patients
IF OBJECT_ID('tempdb..#PatientMedicationData7') IS NOT NULL DROP TABLE [#PatientMedicationData7];
SELECT 
  FK_Patient_Link_ID,
  CAST(MedicationDate AS DATE) AS MedicationDate,
  SuppliedCode
INTO [#PatientMedicationData7]
FROM [SharedCare].GP_Medications
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND ABS(FK_Patient_Link_ID) % 10 = 7
AND MedicationDate < '2022-06-01'; --TODO TEMP POST COPI FIX

-- Improve performance later with an index
DROP INDEX IF EXISTS [medData7] ON [#PatientMedicationData7];
CREATE INDEX [medData7] ON [#PatientMedicationData7] (FK_Patient_Link_ID, MedicationDate) INCLUDE (SuppliedCode);

IF OBJECT_ID('tempdb..#PatientMedDataTempTable7') IS NOT NULL DROP TABLE [#PatientMedDataTempTable7];
SELECT
  FK_Patient_Link_ID,
  SuppliedCode, 
  LAG(MedicationDate, 1) OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS PreviousDate,
  MedicationDate, 
  LEAD(MedicationDate, 1) OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS NextDate,
  ROW_NUMBER() OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS rn
INTO [#PatientMedDataTempTable7]
FROM [#PatientMedicationData7];
-- 56s

DELETE FROM [#PatientMedDataTempTable7]
WHERE DATEDIFF(YEAR, PreviousDate, NextDate) = 0
AND rn % 2 = 0;
--25s

DECLARE @LastDeletedNumber7 INT; 
SET @LastDeletedNumber7=10001;
WHILE ( @LastDeletedNumber7 > 10000)
BEGIN
  IF OBJECT_ID('tempdb..#PatientMedDataTempTableHolding7') IS NOT NULL DROP TABLE [#PatientMedDataTempTableHolding7];
  SELECT FK_Patient_Link_ID, SuppliedCode, 
        LAG(MedicationDate, 1) OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS PreviousDate  ,MedicationDate, 
      LEAD(MedicationDate, 1) OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS NextDate ,
      ROW_NUMBER() OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS rn
  INTO [#PatientMedDataTempTableHolding7]
  FROM [#PatientMedDataTempTable7];

  DELETE FROM [#PatientMedDataTempTableHolding7]
  WHERE DATEDIFF(YEAR, PreviousDate, NextDate) = 0
  AND rn % 2 = 0;

  TRUNCATE TABLE #PatientMedDataTempTable7;
  INSERT INTO #PatientMedDataTempTable7
  SELECT FK_Patient_Link_ID, SuppliedCode, 
        LAG(MedicationDate, 1) OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS PreviousDate  ,MedicationDate, 
      LEAD(MedicationDate, 1) OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS NextDate ,
      ROW_NUMBER() OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS rn
  FROM [#PatientMedDataTempTableHolding7];

  DELETE FROM [#PatientMedDataTempTable7]
  WHERE DATEDIFF(YEAR, PreviousDate, NextDate) = 0
  AND rn % 2 = 0;

  SELECT @LastDeletedNumber7=@@ROWCOUNT;
END

-- Improve performance later with an index
DROP INDEX IF EXISTS [xx7] ON [#PatientMedDataTempTable7];
CREATE INDEX [xx7] ON [#PatientMedDataTempTable7] (FK_Patient_Link_ID, MedicationDate) INCLUDE (SuppliedCode);

IF OBJECT_ID('tempdb..#PolypharmDates5InLastYear7') IS NOT NULL DROP TABLE #PolypharmDates5InLastYear7;
SELECT m1.FK_Patient_Link_ID, m1.[MedicationDate] AS PotentialPolypharmStartDate
INTO #PolypharmDates5InLastYear7
FROM [#PatientMedDataTempTable7] m1
LEFT OUTER JOIN [#PatientMedDataTempTable7] m2
	ON m1.FK_Patient_Link_ID = m2.FK_Patient_Link_ID
	AND m1.[MedicationDate] >= m2.[MedicationDate]
	AND m1.[MedicationDate] < DATEADD(year, 1, m2.[MedicationDate])
GROUP BY m1.FK_Patient_Link_ID, m1.[MedicationDate]
HAVING COUNT(DISTINCT m2.SuppliedCode) >= 5;

-- Next is a look forward from the day after a medication. This will deal with the stop events
IF OBJECT_ID('tempdb..#PolypharmStopDates5InLastYear7') IS NOT NULL DROP TABLE #PolypharmStopDates5InLastYear7;
SELECT m1.FK_Patient_Link_ID, DATEADD(year, 1, m1.[MedicationDate]) AS PotentialPolypharmEndDate
INTO #PolypharmStopDates5InLastYear7
FROM [#PatientMedDataTempTable7] m1
LEFT OUTER JOIN [#PatientMedDataTempTable7] m2
	ON m1.FK_Patient_Link_ID = m2.FK_Patient_Link_ID
	AND DATEADD(year, 1, m1.[MedicationDate]) >= m2.[MedicationDate]
	AND DATEADD(year, 1, m1.[MedicationDate]) < DATEADD(year, 1, m2.[MedicationDate])
GROUP BY m1.FK_Patient_Link_ID, DATEADD(year, 1, m1.[MedicationDate])
HAVING COUNT(DISTINCT m2.SuppliedCode) < 5;
--┌──────────────────────────────────────────┐
--│ Patient medication data splitter for EFI │
--└──────────────────────────────────────────┘

-- OBJECTIVE: Split the medication data into chunks to improve performance

-- First get the medication data for this chunk of patients
IF OBJECT_ID('tempdb..#PatientMedicationData8') IS NOT NULL DROP TABLE [#PatientMedicationData8];
SELECT 
  FK_Patient_Link_ID,
  CAST(MedicationDate AS DATE) AS MedicationDate,
  SuppliedCode
INTO [#PatientMedicationData8]
FROM [SharedCare].GP_Medications
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND ABS(FK_Patient_Link_ID) % 10 = 8
AND MedicationDate < '2022-06-01'; --TODO TEMP POST COPI FIX

-- Improve performance later with an index
DROP INDEX IF EXISTS [medData8] ON [#PatientMedicationData8];
CREATE INDEX [medData8] ON [#PatientMedicationData8] (FK_Patient_Link_ID, MedicationDate) INCLUDE (SuppliedCode);

IF OBJECT_ID('tempdb..#PatientMedDataTempTable8') IS NOT NULL DROP TABLE [#PatientMedDataTempTable8];
SELECT
  FK_Patient_Link_ID,
  SuppliedCode, 
  LAG(MedicationDate, 1) OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS PreviousDate,
  MedicationDate, 
  LEAD(MedicationDate, 1) OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS NextDate,
  ROW_NUMBER() OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS rn
INTO [#PatientMedDataTempTable8]
FROM [#PatientMedicationData8];
-- 56s

DELETE FROM [#PatientMedDataTempTable8]
WHERE DATEDIFF(YEAR, PreviousDate, NextDate) = 0
AND rn % 2 = 0;
--25s

DECLARE @LastDeletedNumber8 INT; 
SET @LastDeletedNumber8=10001;
WHILE ( @LastDeletedNumber8 > 10000)
BEGIN
  IF OBJECT_ID('tempdb..#PatientMedDataTempTableHolding8') IS NOT NULL DROP TABLE [#PatientMedDataTempTableHolding8];
  SELECT FK_Patient_Link_ID, SuppliedCode, 
        LAG(MedicationDate, 1) OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS PreviousDate  ,MedicationDate, 
      LEAD(MedicationDate, 1) OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS NextDate ,
      ROW_NUMBER() OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS rn
  INTO [#PatientMedDataTempTableHolding8]
  FROM [#PatientMedDataTempTable8];

  DELETE FROM [#PatientMedDataTempTableHolding8]
  WHERE DATEDIFF(YEAR, PreviousDate, NextDate) = 0
  AND rn % 2 = 0;

  TRUNCATE TABLE #PatientMedDataTempTable8;
  INSERT INTO #PatientMedDataTempTable8
  SELECT FK_Patient_Link_ID, SuppliedCode, 
        LAG(MedicationDate, 1) OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS PreviousDate  ,MedicationDate, 
      LEAD(MedicationDate, 1) OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS NextDate ,
      ROW_NUMBER() OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS rn
  FROM [#PatientMedDataTempTableHolding8];

  DELETE FROM [#PatientMedDataTempTable8]
  WHERE DATEDIFF(YEAR, PreviousDate, NextDate) = 0
  AND rn % 2 = 0;

  SELECT @LastDeletedNumber8=@@ROWCOUNT;
END

-- Improve performance later with an index
DROP INDEX IF EXISTS [xx8] ON [#PatientMedDataTempTable8];
CREATE INDEX [xx8] ON [#PatientMedDataTempTable8] (FK_Patient_Link_ID, MedicationDate) INCLUDE (SuppliedCode);

IF OBJECT_ID('tempdb..#PolypharmDates5InLastYear8') IS NOT NULL DROP TABLE #PolypharmDates5InLastYear8;
SELECT m1.FK_Patient_Link_ID, m1.[MedicationDate] AS PotentialPolypharmStartDate
INTO #PolypharmDates5InLastYear8
FROM [#PatientMedDataTempTable8] m1
LEFT OUTER JOIN [#PatientMedDataTempTable8] m2
	ON m1.FK_Patient_Link_ID = m2.FK_Patient_Link_ID
	AND m1.[MedicationDate] >= m2.[MedicationDate]
	AND m1.[MedicationDate] < DATEADD(year, 1, m2.[MedicationDate])
GROUP BY m1.FK_Patient_Link_ID, m1.[MedicationDate]
HAVING COUNT(DISTINCT m2.SuppliedCode) >= 5;

-- Next is a look forward from the day after a medication. This will deal with the stop events
IF OBJECT_ID('tempdb..#PolypharmStopDates5InLastYear8') IS NOT NULL DROP TABLE #PolypharmStopDates5InLastYear8;
SELECT m1.FK_Patient_Link_ID, DATEADD(year, 1, m1.[MedicationDate]) AS PotentialPolypharmEndDate
INTO #PolypharmStopDates5InLastYear8
FROM [#PatientMedDataTempTable8] m1
LEFT OUTER JOIN [#PatientMedDataTempTable8] m2
	ON m1.FK_Patient_Link_ID = m2.FK_Patient_Link_ID
	AND DATEADD(year, 1, m1.[MedicationDate]) >= m2.[MedicationDate]
	AND DATEADD(year, 1, m1.[MedicationDate]) < DATEADD(year, 1, m2.[MedicationDate])
GROUP BY m1.FK_Patient_Link_ID, DATEADD(year, 1, m1.[MedicationDate])
HAVING COUNT(DISTINCT m2.SuppliedCode) < 5;
--┌──────────────────────────────────────────┐
--│ Patient medication data splitter for EFI │
--└──────────────────────────────────────────┘

-- OBJECTIVE: Split the medication data into chunks to improve performance

-- First get the medication data for this chunk of patients
IF OBJECT_ID('tempdb..#PatientMedicationData9') IS NOT NULL DROP TABLE [#PatientMedicationData9];
SELECT 
  FK_Patient_Link_ID,
  CAST(MedicationDate AS DATE) AS MedicationDate,
  SuppliedCode
INTO [#PatientMedicationData9]
FROM [SharedCare].GP_Medications
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND ABS(FK_Patient_Link_ID) % 10 = 9
AND MedicationDate < '2022-06-01'; --TODO TEMP POST COPI FIX

-- Improve performance later with an index
DROP INDEX IF EXISTS [medData9] ON [#PatientMedicationData9];
CREATE INDEX [medData9] ON [#PatientMedicationData9] (FK_Patient_Link_ID, MedicationDate) INCLUDE (SuppliedCode);

IF OBJECT_ID('tempdb..#PatientMedDataTempTable9') IS NOT NULL DROP TABLE [#PatientMedDataTempTable9];
SELECT
  FK_Patient_Link_ID,
  SuppliedCode, 
  LAG(MedicationDate, 1) OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS PreviousDate,
  MedicationDate, 
  LEAD(MedicationDate, 1) OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS NextDate,
  ROW_NUMBER() OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS rn
INTO [#PatientMedDataTempTable9]
FROM [#PatientMedicationData9];
-- 56s

DELETE FROM [#PatientMedDataTempTable9]
WHERE DATEDIFF(YEAR, PreviousDate, NextDate) = 0
AND rn % 2 = 0;
--25s

DECLARE @LastDeletedNumber9 INT; 
SET @LastDeletedNumber9=10001;
WHILE ( @LastDeletedNumber9 > 10000)
BEGIN
  IF OBJECT_ID('tempdb..#PatientMedDataTempTableHolding9') IS NOT NULL DROP TABLE [#PatientMedDataTempTableHolding9];
  SELECT FK_Patient_Link_ID, SuppliedCode, 
        LAG(MedicationDate, 1) OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS PreviousDate  ,MedicationDate, 
      LEAD(MedicationDate, 1) OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS NextDate ,
      ROW_NUMBER() OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS rn
  INTO [#PatientMedDataTempTableHolding9]
  FROM [#PatientMedDataTempTable9];

  DELETE FROM [#PatientMedDataTempTableHolding9]
  WHERE DATEDIFF(YEAR, PreviousDate, NextDate) = 0
  AND rn % 2 = 0;

  TRUNCATE TABLE #PatientMedDataTempTable9;
  INSERT INTO #PatientMedDataTempTable9
  SELECT FK_Patient_Link_ID, SuppliedCode, 
        LAG(MedicationDate, 1) OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS PreviousDate  ,MedicationDate, 
      LEAD(MedicationDate, 1) OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS NextDate ,
      ROW_NUMBER() OVER (PARTITION BY FK_Patient_Link_ID, SuppliedCode ORDER BY MedicationDate) AS rn
  FROM [#PatientMedDataTempTableHolding9];

  DELETE FROM [#PatientMedDataTempTable9]
  WHERE DATEDIFF(YEAR, PreviousDate, NextDate) = 0
  AND rn % 2 = 0;

  SELECT @LastDeletedNumber9=@@ROWCOUNT;
END

-- Improve performance later with an index
DROP INDEX IF EXISTS [xx9] ON [#PatientMedDataTempTable9];
CREATE INDEX [xx9] ON [#PatientMedDataTempTable9] (FK_Patient_Link_ID, MedicationDate) INCLUDE (SuppliedCode);

IF OBJECT_ID('tempdb..#PolypharmDates5InLastYear9') IS NOT NULL DROP TABLE #PolypharmDates5InLastYear9;
SELECT m1.FK_Patient_Link_ID, m1.[MedicationDate] AS PotentialPolypharmStartDate
INTO #PolypharmDates5InLastYear9
FROM [#PatientMedDataTempTable9] m1
LEFT OUTER JOIN [#PatientMedDataTempTable9] m2
	ON m1.FK_Patient_Link_ID = m2.FK_Patient_Link_ID
	AND m1.[MedicationDate] >= m2.[MedicationDate]
	AND m1.[MedicationDate] < DATEADD(year, 1, m2.[MedicationDate])
GROUP BY m1.FK_Patient_Link_ID, m1.[MedicationDate]
HAVING COUNT(DISTINCT m2.SuppliedCode) >= 5;

-- Next is a look forward from the day after a medication. This will deal with the stop events
IF OBJECT_ID('tempdb..#PolypharmStopDates5InLastYear9') IS NOT NULL DROP TABLE #PolypharmStopDates5InLastYear9;
SELECT m1.FK_Patient_Link_ID, DATEADD(year, 1, m1.[MedicationDate]) AS PotentialPolypharmEndDate
INTO #PolypharmStopDates5InLastYear9
FROM [#PatientMedDataTempTable9] m1
LEFT OUTER JOIN [#PatientMedDataTempTable9] m2
	ON m1.FK_Patient_Link_ID = m2.FK_Patient_Link_ID
	AND DATEADD(year, 1, m1.[MedicationDate]) >= m2.[MedicationDate]
	AND DATEADD(year, 1, m1.[MedicationDate]) < DATEADD(year, 1, m2.[MedicationDate])
GROUP BY m1.FK_Patient_Link_ID, DATEADD(year, 1, m1.[MedicationDate])
HAVING COUNT(DISTINCT m2.SuppliedCode) < 5;


-- This will deal with the start events.
IF OBJECT_ID('tempdb..#PolypharmDates5InLastYear') IS NOT NULL DROP TABLE #PolypharmDates5InLastYear;
SELECT * INTO #PolypharmDates5InLastYear FROM #PolypharmDates5InLastYear0
UNION
SELECT * FROM #PolypharmDates5InLastYear1
UNION
SELECT * FROM #PolypharmDates5InLastYear2
UNION
SELECT * FROM #PolypharmDates5InLastYear3
UNION
SELECT * FROM #PolypharmDates5InLastYear4
UNION
SELECT * FROM #PolypharmDates5InLastYear5
UNION
SELECT * FROM #PolypharmDates5InLastYear6
UNION
SELECT * FROM #PolypharmDates5InLastYear7
UNION
SELECT * FROM #PolypharmDates5InLastYear8
UNION
SELECT * FROM #PolypharmDates5InLastYear9;

-- Next is a look forward from the day after a medication. This will deal with the stop events
IF OBJECT_ID('tempdb..#PolypharmStopDates5InLastYear') IS NOT NULL DROP TABLE #PolypharmStopDates5InLastYear;
SELECT * INTO #PolypharmStopDates5InLastYear FROM #PolypharmStopDates5InLastYear0
UNION
SELECT * FROM #PolypharmStopDates5InLastYear1
UNION
SELECT * FROM #PolypharmStopDates5InLastYear2
UNION
SELECT * FROM #PolypharmStopDates5InLastYear3
UNION
SELECT * FROM #PolypharmStopDates5InLastYear4
UNION
SELECT * FROM #PolypharmStopDates5InLastYear5
UNION
SELECT * FROM #PolypharmStopDates5InLastYear6
UNION
SELECT * FROM #PolypharmStopDates5InLastYear7
UNION
SELECT * FROM #PolypharmStopDates5InLastYear8
UNION
SELECT * FROM #PolypharmStopDates5InLastYear9;


-- Now convert to desired format (PatientId / DateFrom / DateTo)

-- Temp holiding table for loop below
IF OBJECT_ID('tempdb..#PolypharmacyPeriodsYearTEMP') IS NOT NULL DROP TABLE #PolypharmacyPeriodsYearTEMP;
CREATE TABLE #PolypharmacyPeriodsYearTEMP (
	FK_Patient_Link_ID BIGINT,
	DateFrom DATE,
	DateTo DATE
);

-- Populate initial start and end dates
IF OBJECT_ID('tempdb..#PolypharmacyPeriods5In1Year') IS NOT NULL DROP TABLE #PolypharmacyPeriods5In1Year;
SELECT a.FK_Patient_Link_ID, PotentialPolypharmStartDate AS DateFrom, MIN(PotentialPolypharmEndDate) AS DateTo
INTO #PolypharmacyPeriods5In1Year
FROM #PolypharmDates5InLastYear a
LEFT OUTER JOIN #PolypharmStopDates5InLastYear b
	ON a.FK_Patient_Link_ID = b.FK_Patient_Link_ID
	AND PotentialPolypharmStartDate < PotentialPolypharmEndDate
GROUP BY a.FK_Patient_Link_ID, PotentialPolypharmStartDate;

-- All end dates are now correct, but each one has multiple start dates. Pick the earliest 
-- in each case
IF OBJECT_ID('tempdb..#PolypharmacyPeriods') IS NOT NULL DROP TABLE #PolypharmacyPeriods;
SELECT FK_Patient_Link_ID, MIN(DateFrom) AS DateFrom, DateTo
INTO #PolypharmacyPeriods
FROM #PolypharmacyPeriods5In1Year
GROUP BY FK_Patient_Link_ID, DateTo;

-- NB - The below is an alternative method to calculate polypharmacy. This was RWs best guess
--	prior to receiving instruction from Andy Clegg. It is kept in case useful. However, it has
--	not been tested exhaustively and so should be prior to use.

-- -- Polypharmacy is defined as 5 different med codes on a single day. This then lasts for 6 weeks
-- -- (most Rx for 4 weeks, so add some padding to ensure people on 5 meds permanently, but with
-- -- small variation in time differences are classed as always poly rather than flipping in/out).
-- -- Overlapping periods are then combined.

-- -- Get all the dates that people were prescribed 5 or more meds
-- IF OBJECT_ID('tempdb..#PolypharmDates5OnOneDay') IS NOT NULL DROP TABLE #PolypharmDates5OnOneDay;
-- SELECT FK_Patient_Link_ID, CONVERT(DATE, [MedicationDate]) AS MedicationDate
-- INTO #PolypharmDates5OnOneDay
-- FROM #PatientMedicationData
-- GROUP BY FK_Patient_Link_ID, CONVERT(DATE, [MedicationDate])
-- HAVING COUNT(DISTINCT SuppliedCode) >= 5;

-- -- Now convert to desired format (PatientId / DateFrom / DateTo)

-- -- Temp holiding table for loop below
-- IF OBJECT_ID('tempdb..#PolypharmacyPeriodsTEMP') IS NOT NULL DROP TABLE #PolypharmacyPeriodsTEMP;
-- CREATE TABLE #PolypharmacyPeriodsTEMP (
-- 	FK_Patient_Link_ID BIGINT,
-- 	DateFrom DATE,
-- 	DateTo DATE
-- );

-- -- Populate initial start and end dates
-- IF OBJECT_ID('tempdb..#PolypharmacyPeriods') IS NOT NULL DROP TABLE #PolypharmacyPeriods;
-- SELECT FK_Patient_Link_ID, MedicationDate As DateFrom, DATEADD(day, 42, MedicationDate) AS DateTo
-- INTO #PolypharmacyPeriods
-- FROM #PolypharmDates5OnOneDay;

-- DECLARE @NumberDeleted INT;
-- SET @NumberDeleted=1;
-- WHILE ( @NumberDeleted > 0)
-- BEGIN

-- 	-- PHASE 1
-- 	-- Populate the temp table with overlapping periods. If there is no overlapping period,
-- 	-- we just retain the initial period. If a period overlaps, then this populate the widest
-- 	-- [DateFrom, DateTo] range.
-- 	-- Grapically we go from:
-- 	-- |------|
-- 	--     |-----|
-- 	--      |-------|
-- 	--              |-----|
-- 	--                      |-----|
-- 	-- to:
-- 	-- |------|
-- 	-- |---------|
-- 	-- |------------|
-- 	--     |-----|
-- 	--     |--------|
-- 	--      |-------|
-- 	--      |-------------|
-- 	--              |-----|
-- 	--                      |-----|
-- 	--
-- 	TRUNCATE TABLE #PolypharmacyPeriodsTEMP;
-- 	INSERT INTO #PolypharmacyPeriodsTEMP
-- 	select p1.FK_Patient_Link_ID, p1.DateFrom, ISNULL(p2.DateTo, p1.DateTo) AS DateTo
-- 	from #PolypharmacyPeriods p1
-- 	left outer join #PolypharmacyPeriods p2 on
-- 		p1.FK_Patient_Link_ID = p2.FK_Patient_Link_ID and 
-- 		p2.DateFrom <= p1.DateTo and 
-- 		p2.DateFrom > p1.DateFrom;

-- 	-- Make both polypharm period tables the same
-- 	TRUNCATE TABLE #PolypharmacyPeriods;
-- 	INSERT INTO #PolypharmacyPeriods
-- 	SELECT * FROM #PolypharmacyPeriodsTEMP;

-- 	-- PHASE 2
-- 	-- The above will have resulted in overlapping periods. Here we remove any that are
-- 	-- contained in other periods.
-- 	-- Continuing the above graphical example, we go from:
-- 	-- |------|
-- 	-- |---------|
-- 	-- |------------|
-- 	--     |-----|
-- 	--     |--------|
-- 	--      |-------|
-- 	--      |-------------|
-- 	--              |-----|
-- 	--                      |-----|
-- 	-- to:
-- 	-- |------------|
-- 	--      |-------------|
-- 	--                      |-----|
-- 	DELETE p
-- 	FROM #PolypharmacyPeriods p
-- 	JOIN (
-- 	SELECT p1.* FROM #PolypharmacyPeriodsTEMP p1
-- 	INNER JOIN #PolypharmacyPeriodsTEMP p2 ON
-- 		p1.FK_Patient_Link_ID = p2.FK_Patient_Link_ID AND
-- 		(
-- 			(p1.DateFrom >= p2.DateFrom AND	p1.DateTo < p2.DateTo) OR
-- 			(p1.DateFrom > p2.DateFrom AND p1.DateTo <= p2.DateTo)
-- 		)
-- 	) sub ON sub.FK_Patient_Link_ID = p.FK_Patient_Link_ID and sub.DateFrom = p.DateFrom and sub.DateTo = p.DateTo;

-- 	SELECT @NumberDeleted=@@ROWCOUNT;

-- 	-- Provided we removed some periods, we need to re-run the loop. For our example, the 
-- 	-- next iteration will first go from:
-- 	-- |------------|
-- 	--      |-------------|
-- 	--                      |-----|
-- 	-- to:
-- 	-- |------------|
-- 	-- |------------------|
-- 	--      |-------------|
-- 	--                      |-----|
-- 	-- during PHASE 1, then during PHASE 2, 2 periods will be deleted leaving:
-- 	-- |------------------|
-- 	--                      |-----|
-- 	-- One more iteration will occur, but nothing will change, so we'll exit the loop with the final
-- 	-- two non-overlapping periods
-- END




-- count on each day
IF OBJECT_ID('tempdb..#DeficitCountsTEMP') IS NOT NULL DROP TABLE #DeficitCountsTEMP;
SELECT FK_Patient_Link_ID, EventDate, count(*) AS DailyDeficitIncrease
INTO #DeficitCountsTEMP
FROM #EfiEvents
GROUP BY FK_Patient_Link_ID, EventDate;

-- add polypharmacy
INSERT INTO #DeficitCountsTEMP
SELECT FK_Patient_Link_ID, DateFrom, 1 FROM #PolypharmacyPeriods -- we add 1 to the deficit on the date from
UNION
SELECT FK_Patient_Link_ID, DateTo, -1 FROM #PolypharmacyPeriods; -- we subtract 1 on the date to

-- Will have introduced some duplicate dates - remove them by summing
IF OBJECT_ID('tempdb..#DeficitCounts') IS NOT NULL DROP TABLE #DeficitCounts;
SELECT FK_Patient_Link_ID, EventDate, SUM(DailyDeficitIncrease) AS DailyDeficitIncrease
INTO #DeficitCounts
FROM #DeficitCountsTEMP
GROUP BY FK_Patient_Link_ID, EventDate;

IF OBJECT_ID('tempdb..#PatientEFIOverTime') IS NOT NULL DROP TABLE #PatientEFIOverTime;
SELECT t1.FK_Patient_Link_ID, t1.EventDate AS DateFrom, sum(t2.DailyDeficitIncrease) AS NumberOfDeficits
INTO #PatientEFIOverTime
FROM #DeficitCounts t1
LEFT OUTER JOIN #DeficitCounts t2
	ON t1.FK_Patient_Link_ID = t2.FK_Patient_Link_ID
	AND t2.EventDate <= t1.EventDate
GROUP BY t1.FK_Patient_Link_ID, t1.EventDate
ORDER BY t1.FK_Patient_Link_ID,t1.EventDate;

-- Finally we just select from the EFI table with the required fields
SELECT
  FK_Patient_Link_ID AS PatientId,
  DateFrom,
  NumberOfDeficits
FROM #PatientEFIOverTime
ORDER BY FK_Patient_Link_ID, DateFrom;