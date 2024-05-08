--┌──────────────────────────────────────────┐
--│ SDE Lighthouse study 03 - Kontopantelis  │
--└──────────────────────────────────────────┘

--Just want the output, not the messages
SET NOCOUNT ON;

DECLARE @StartDate datetime;
DECLARE @EndDate datetime;
SET @StartDate = '2006-01-01';
SET @EndDate = '2023-10-31';

--┌───────────────────────────────────────────────────────────────────┐
--│ Define Cohort for LH003: patients that had a dementia diagnosis   │
--└───────────────────────────────────────────────────────────────────┘

-- OBJECTIVE: To build the cohort of patients needed for LH003. This reduces duplication of code in the template scripts.

-- COHORT: Any patient with a dementia diagnosis between start and end date.

-- INPUT: assumes there exists one temp table as follows:
-- #Patients (FK_Patient_Link_ID)
--  A distinct list of FK_Patient_Link_IDs for each patient in the cohort

-- OUTPUT: Temp tables as follows:
-- #Cohort

--┌───────────────────────────────────────────────────────────┐
--│ Create table of patients who are registered with a GM GP  │
--└───────────────────────────────────────────────────────────┘

-- INPUT REQUIREMENTS: @StartDate

-- Find all patients alive at start date
IF OBJECT_ID('tempdb..#PossiblePatients') IS NOT NULL DROP TABLE #PossiblePatients;
SELECT PK_Patient_Link_ID as FK_Patient_Link_ID, EthnicMainGroup, EthnicGroupDescription, DeathDate INTO #PossiblePatients FROM [SharedCare].Patient_Link
WHERE 
	(DeathDate IS NULL OR (DeathDate >= @StartDate))

-- Find all patients registered with a GP
IF OBJECT_ID('tempdb..#PatientsWithGP') IS NOT NULL DROP TABLE #PatientsWithGP;
SELECT DISTINCT FK_Patient_Link_ID INTO #PatientsWithGP FROM [SharedCare].Patient
where FK_Reference_Tenancy_ID = 2;

-- Make cohort from patients alive at start date and registered with a GP
IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT pp.* INTO #Patients FROM #PossiblePatients pp
INNER JOIN #PatientsWithGP gp on gp.FK_Patient_Link_ID = pp.FK_Patient_Link_ID;

------------------------------------------

-- OUTPUT: #Patients
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
VALUES ('dementia',1,'1461.',NULL,'H/O: dementia'),('dementia',1,'1461.00',NULL,'H/O: dementia'),('dementia',1,'4L49.',NULL,'Prion protein markers for Creutzfeldt-Jakob disease'),('dementia',1,'4L49.00',NULL,'Prion protein markers for Creutzfeldt-Jakob disease'),('dementia',1,'66h..',NULL,'Dementia monitoring'),('dementia',1,'66h..00',NULL,'Dementia monitoring'),('dementia',1,'6AB..',NULL,'Dementia annual review'),('dementia',1,'6AB..00',NULL,'Dementia annual review'),('dementia',1,'8BM02',NULL,'Dementia medication review'),('dementia',1,'8BM0200',NULL,'Dementia medication review'),('dementia',1,'9hD..',NULL,'Exception reporting: dementia quality indicators'),('dementia',1,'9hD..00',NULL,'Exception reporting: dementia quality indicators'),('dementia',1,'9hD0.',NULL,'Excepted from dementia quality indicators: Patient unsuitable'),('dementia',1,'9hD0.00',NULL,'Excepted from dementia quality indicators: Patient unsuitable'),('dementia',1,'9hD1.',NULL,'Excepted from dementia quality indicators: Informed dissent'),('dementia',1,'9hD1.00',NULL,'Excepted from dementia quality indicators: Informed dissent'),('dementia',1,'9Ou..',NULL,'Dementia monitoring administration'),('dementia',1,'9Ou..00',NULL,'Dementia monitoring administration'),('dementia',1,'9Ou1.',NULL,'Dementia monitoring first letter'),('dementia',1,'9Ou1.00',NULL,'Dementia monitoring first letter'),('dementia',1,'9Ou2.',NULL,'Dementia monitoring second letter'),('dementia',1,'9Ou2.00',NULL,'Dementia monitoring second letter'),('dementia',1,'9Ou3.',NULL,'Dementia monitoring third letter'),('dementia',1,'9Ou3.00',NULL,'Dementia monitoring third letter'),('dementia',1,'9Ou4.',NULL,'Dementia monitoring verbal invite'),('dementia',1,'9Ou4.00',NULL,'Dementia monitoring verbal invite'),('dementia',1,'9Ou5.',NULL,'Dementia monitoring telephone invite'),('dementia',1,'9Ou5.00',NULL,'Dementia monitoring telephone invite'),('dementia',1,'A410.',NULL,'Kuru'),('dementia',1,'A410.00',NULL,'Kuru'),('dementia',1,'A411.',NULL,'Jakob-Creutzfeldt disease'),('dementia',1,'A411.00',NULL,'Jakob-Creutzfeldt disease'),('dementia',1,'A4110',NULL,'Sporadic Creutzfeldt-Jakob disease'),('dementia',1,'A411000',NULL,'Sporadic Creutzfeldt-Jakob disease'),('dementia',1,'E00..',NULL,'Senile and presenile organic psychotic conditions'),('dementia',1,'E00..00',NULL,'Senile and presenile organic psychotic conditions'),('dementia',1,'E000.',NULL,'Uncomplicated senile dementia'),('dementia',1,'E000.00',NULL,'Uncomplicated senile dementia'),('dementia',1,'E001.',NULL,'Presenile dementia'),('dementia',1,'E001.00',NULL,'Presenile dementia'),('dementia',1,'E0010',NULL,'Uncomplicated presenile dementia'),('dementia',1,'E001000',NULL,'Uncomplicated presenile dementia'),('dementia',1,'E0011',NULL,'Presenile dementia with delirium'),('dementia',1,'E001100',NULL,'Presenile dementia with delirium'),('dementia',1,'E0012',NULL,'Presenile dementia with paranoia'),('dementia',1,'E001200',NULL,'Presenile dementia with paranoia'),('dementia',1,'E0013',NULL,'Presenile dementia with depression'),('dementia',1,'E001300',NULL,'Presenile dementia with depression'),('dementia',1,'E001z',NULL,'Presenile dementia NOS'),('dementia',1,'E001z00',NULL,'Presenile dementia NOS'),('dementia',1,'E002.',NULL,'Senile dementia with depressive or paranoid features'),('dementia',1,'E002.00',NULL,'Senile dementia with depressive or paranoid features'),('dementia',1,'E0020',NULL,'Senile dementia with paranoia'),('dementia',1,'E002000',NULL,'Senile dementia with paranoia'),('dementia',1,'E0021',NULL,'Senile dementia with depression'),('dementia',1,'E002100',NULL,'Senile dementia with depression'),('dementia',1,'E002z',NULL,'Senile dementia with depressive or paranoid features NOS'),('dementia',1,'E002z00',NULL,'Senile dementia with depressive or paranoid features NOS'),('dementia',1,'E003.',NULL,'Senile dementia with delirium'),('dementia',1,'E003.00',NULL,'Senile dementia with delirium'),('dementia',1,'E004.',NULL,'Arteriosclerotic dementia'),('dementia',1,'E004.00',NULL,'Arteriosclerotic dementia'),('dementia',1,'E0040',NULL,'Uncomplicated arteriosclerotic dementia'),('dementia',1,'E004000',NULL,'Uncomplicated arteriosclerotic dementia'),('dementia',1,'E0041',NULL,'Arteriosclerotic dementia with delirium'),('dementia',1,'E004100',NULL,'Arteriosclerotic dementia with delirium'),('dementia',1,'E0042',NULL,'Arteriosclerotic dementia with paranoia'),('dementia',1,'E004200',NULL,'Arteriosclerotic dementia with paranoia'),('dementia',1,'E0043',NULL,'Arteriosclerotic dementia with depression'),('dementia',1,'E004300',NULL,'Arteriosclerotic dementia with depression'),('dementia',1,'E004z',NULL,'Arteriosclerotic dementia NOS'),('dementia',1,'E004z00',NULL,'Arteriosclerotic dementia NOS'),('dementia',1,'E00y.',NULL,'Other senile and presenile organic psychoses'),('dementia',1,'E00y.00',NULL,'Other senile and presenile organic psychoses'),('dementia',1,'E00z.',NULL,'Senile or presenile psychoses NOS'),('dementia',1,'E00z.00',NULL,'Senile or presenile psychoses NOS'),('dementia',1,'E011.',NULL,'Alcohol amnestic syndrome'),('dementia',1,'E011.00',NULL,'Alcohol amnestic syndrome'),('dementia',1,'E0110',NULL,'Korsakovs alcoholic psychosis'),('dementia',1,'E011000',NULL,'Korsakovs alcoholic psychosis'),('dementia',1,'E0111',NULL,'Korsakovs alcoholic psychosis with peripheral neuritis'),('dementia',1,'E011100',NULL,'Korsakovs alcoholic psychosis with peripheral neuritis'),('dementia',1,'E0112',NULL,'Wernicke-Korsakov syndrome'),('dementia',1,'E011200',NULL,'Wernicke-Korsakov syndrome'),('dementia',1,'E011z',NULL,'Alcohol amnestic syndrome NOS'),('dementia',1,'E011z00',NULL,'Alcohol amnestic syndrome NOS'),('dementia',1,'E012.',NULL,'Other alcoholic dementia'),('dementia',1,'E012.00',NULL,'Other alcoholic dementia'),('dementia',1,'E040.',NULL,'Non-alcoholic amnestic syndrome'),('dementia',1,'E040.00',NULL,'Non-alcoholic amnestic syndrome'),('dementia',1,'E041.',NULL,'Dementia in conditions EC'),('dementia',1,'E041.00',NULL,'Dementia in conditions EC'),('dementia',1,'Eu00.',NULL,'[X]Dementia in Alzheimers disease'),('dementia',1,'Eu00.00',NULL,'[X]Dementia in Alzheimers disease'),('dementia',1,'Eu000',NULL,'[X]Dementia in Alzheimers disease with early onset'),('dementia',1,'Eu00000',NULL,'[X]Dementia in Alzheimers disease with early onset'),('dementia',1,'Eu001',NULL,'[X]Dementia in Alzheimers disease with late onset'),('dementia',1,'Eu00100',NULL,'[X]Dementia in Alzheimers disease with late onset'),('dementia',1,'Eu002',NULL,'[X]Dementia in Alzheimers dis, atypical or mixed type'),('dementia',1,'Eu00200',NULL,'[X]Dementia in Alzheimers dis, atypical or mixed type'),('dementia',1,'Eu00z',NULL,'[X]Dementia in Alzheimers disease, unspecified'),('dementia',1,'Eu00z00',NULL,'[X]Dementia in Alzheimers disease, unspecified'),('dementia',1,'Eu01.',NULL,'[X]Vascular dementia'),('dementia',1,'Eu01.00',NULL,'[X]Vascular dementia'),('dementia',1,'Eu010',NULL,'[X]Vascular dementia of acute onset'),('dementia',1,'Eu01000',NULL,'[X]Vascular dementia of acute onset'),('dementia',1,'Eu011',NULL,'[X]Multi-infarct dementia'),('dementia',1,'Eu01100',NULL,'[X]Multi-infarct dementia'),('dementia',1,'Eu012',NULL,'[X]Subcortical vascular dementia'),('dementia',1,'Eu01200',NULL,'[X]Subcortical vascular dementia'),('dementia',1,'Eu013',NULL,'[X]Mixed cortical and subcortical vascular dementia'),('dementia',1,'Eu01300',NULL,'[X]Mixed cortical and subcortical vascular dementia'),('dementia',1,'Eu01y',NULL,'[X]Other vascular dementia'),('dementia',1,'Eu01y00',NULL,'[X]Other vascular dementia'),('dementia',1,'Eu01z',NULL,'[X]Vascular dementia, unspecified'),('dementia',1,'Eu01z00',NULL,'[X]Vascular dementia, unspecified'),('dementia',1,'Eu02.',NULL,'[X]Dementia in other diseases classified elsewhere'),('dementia',1,'Eu02.00',NULL,'[X]Dementia in other diseases classified elsewhere'),('dementia',1,'Eu020',NULL,'[X]Dementia in Picks disease'),('dementia',1,'Eu02000',NULL,'[X]Dementia in Picks disease'),('dementia',1,'Eu021',NULL,'[X]Dementia in Creutzfeldt-Jakob disease'),('dementia',1,'Eu02100',NULL,'[X]Dementia in Creutzfeldt-Jakob disease'),('dementia',1,'Eu022',NULL,'[X]Dementia in Huntingtons disease'),('dementia',1,'Eu02200',NULL,'[X]Dementia in Huntingtons disease'),('dementia',1,'Eu023',NULL,'[X]Dementia in Parkinsons disease'),('dementia',1,'Eu02300',NULL,'[X]Dementia in Parkinsons disease'),('dementia',1,'Eu024',NULL,'[X]Dementia in human immunodef virus [HIV] disease'),('dementia',1,'Eu02400',NULL,'[X]Dementia in human immunodef virus [HIV] disease'),('dementia',1,'Eu025',NULL,'[X]Lewy body dementia'),('dementia',1,'Eu02500',NULL,'[X]Lewy body dementia'),('dementia',1,'Eu02y',NULL,'[X]Dementia in other specified diseases classif elsewhere'),('dementia',1,'Eu02y00',NULL,'[X]Dementia in other specified diseases classif elsewhere'),('dementia',1,'Eu02z',NULL,'[X] Unspecified dementia'),('dementia',1,'Eu02z00',NULL,'[X] Unspecified dementia'),('dementia',1,'Eu041',NULL,'[X]Delirium superimposed on dementia'),('dementia',1,'Eu04100',NULL,'[X]Delirium superimposed on dementia'),('dementia',1,'Eu106',NULL,'[X]Mental and behavioural disorders due to use of alcohol: amnesic syndrome'),('dementia',1,'Eu10600',NULL,'[X]Mental and behavioural disorders due to use of alcohol: amnesic syndrome'),('dementia',1,'Eu107','11','[X]Alcoholic dementia NOS'),('dementia',1,'Eu107','11','[X]Alcoholic dementia NOS'),('dementia',1,'F0300',NULL,'Encephalitis due to kuru'),('dementia',1,'F030000',NULL,'Encephalitis due to kuru'),('dementia',1,'F110.',NULL,'Alzheimers disease'),('dementia',1,'F110.00',NULL,'Alzheimers disease'),('dementia',1,'F1100',NULL,'Alzheimers disease with early onset'),('dementia',1,'F110000',NULL,'Alzheimers disease with early onset'),('dementia',1,'F1101',NULL,'Alzheimers disease with late onset'),('dementia',1,'F110100',NULL,'Alzheimers disease with late onset'),('dementia',1,'F111.',NULL,'Picks disease'),
('dementia',1,'F111.00',NULL,'Picks disease'),('dementia',1,'F116.',NULL,'Lewy body disease'),('dementia',1,'F116.00',NULL,'Lewy body disease'),('dementia',1,'F118.',NULL,'Frontotemporal degeneration'),('dementia',1,'F118.00',NULL,'Frontotemporal degeneration'),('dementia',1,'F11x7',NULL,'Cerebral degeneration due to Jakob - Creutzfeldt disease'),('dementia',1,'F11x700',NULL,'Cerebral degeneration due to Jakob - Creutzfeldt disease'),('dementia',1,'F11x8',NULL,'Cerebral degeneration due to progressive multifocal leucoencephalopathy'),('dementia',1,'F11x800',NULL,'Cerebral degeneration due to progressive multifocal leucoencephalopathy'),('dementia',1,'F21y2',NULL,'Binswangers disease'),('dementia',1,'F21y200',NULL,'Binswangers disease'),('dementia',1,'Fyu30',NULL,'[X]Other Alzheimers disease'),('dementia',1,'Fyu3000',NULL,'[X]Other Alzheimers disease');
INSERT INTO #codesreadv2
VALUES ('alcohol-heavy-drinker',1,'136b.',NULL,'Feels should cut down drinking'),('alcohol-heavy-drinker',1,'136b.00',NULL,'Feels should cut down drinking'),('alcohol-heavy-drinker',1,'136c.',NULL,'Higher risk drinking'),('alcohol-heavy-drinker',1,'136c.00',NULL,'Higher risk drinking'),('alcohol-heavy-drinker',1,'136K.',NULL,'Alcohol intake above recommended sensible limits'),('alcohol-heavy-drinker',1,'136K.00',NULL,'Alcohol intake above recommended sensible limits'),('alcohol-heavy-drinker',1,'136P.',NULL,'Heavy drinker'),('alcohol-heavy-drinker',1,'136P.00',NULL,'Heavy drinker'),('alcohol-heavy-drinker',1,'136Q.',NULL,'Very heavy drinker'),('alcohol-heavy-drinker',1,'136Q.00',NULL,'Very heavy drinker'),('alcohol-heavy-drinker',1,'136R.',NULL,'Binge drinker'),('alcohol-heavy-drinker',1,'136R.00',NULL,'Binge drinker'),('alcohol-heavy-drinker',1,'136S.',NULL,'Hazardous alcohol use'),('alcohol-heavy-drinker',1,'136S.00',NULL,'Hazardous alcohol use'),('alcohol-heavy-drinker',1,'136T.',NULL,'Harmful alcohol use'),('alcohol-heavy-drinker',1,'136T.00',NULL,'Harmful alcohol use'),('alcohol-heavy-drinker',1,'136W.',NULL,'Alcohol misuse'),('alcohol-heavy-drinker',1,'136W.00',NULL,'Alcohol misuse'),('alcohol-heavy-drinker',1,'136Y.',NULL,'Drinks in morning to get rid of hangover'),('alcohol-heavy-drinker',1,'136Y.00',NULL,'Drinks in morning to get rid of hangover'),('alcohol-heavy-drinker',1,'E23..','12','Alcohol problem drinking'),('alcohol-heavy-drinker',1,'E23..','12','Alcohol problem drinking');
INSERT INTO #codesreadv2
VALUES ('alcohol-light-drinker',1,'1362.',NULL,'Trivial drinker - <1u/day'),('alcohol-light-drinker',1,'1362.00',NULL,'Trivial drinker - <1u/day'),('alcohol-light-drinker',1,'136N.',NULL,'Light drinker'),('alcohol-light-drinker',1,'136N.00',NULL,'Light drinker'),('alcohol-light-drinker',1,'136d.',NULL,'Lower risk drinking'),('alcohol-light-drinker',1,'136d.00',NULL,'Lower risk drinking');
INSERT INTO #codesreadv2
VALUES ('alcohol-moderate-drinker',1,'136O.',NULL,'Moderate drinker'),('alcohol-moderate-drinker',1,'136O.00',NULL,'Moderate drinker'),('alcohol-moderate-drinker',1,'136F.',NULL,'Spirit drinker'),('alcohol-moderate-drinker',1,'136F.00',NULL,'Spirit drinker'),('alcohol-moderate-drinker',1,'136G.',NULL,'Beer drinker'),('alcohol-moderate-drinker',1,'136G.00',NULL,'Beer drinker'),('alcohol-moderate-drinker',1,'136H.',NULL,'Drinks beer and spirits'),('alcohol-moderate-drinker',1,'136H.00',NULL,'Drinks beer and spirits'),('alcohol-moderate-drinker',1,'136I.',NULL,'Drinks wine'),('alcohol-moderate-drinker',1,'136I.00',NULL,'Drinks wine'),('alcohol-moderate-drinker',1,'136J.',NULL,'Social drinker'),('alcohol-moderate-drinker',1,'136J.00',NULL,'Social drinker'),('alcohol-moderate-drinker',1,'136L.',NULL,'Alcohol intake within recommended sensible limits'),('alcohol-moderate-drinker',1,'136L.00',NULL,'Alcohol intake within recommended sensible limits'),('alcohol-moderate-drinker',1,'136Z.',NULL,'Alcohol consumption NOS'),('alcohol-moderate-drinker',1,'136Z.00',NULL,'Alcohol consumption NOS'),('alcohol-moderate-drinker',1,'136a.',NULL,'Increasing risk drinking'),('alcohol-moderate-drinker',1,'136a.00',NULL,'Increasing risk drinking');
INSERT INTO #codesreadv2
VALUES ('alcohol-non-drinker',1,'1361.',NULL,'Teetotaller'),('alcohol-non-drinker',1,'1361.00',NULL,'Teetotaller'),('alcohol-non-drinker',1,'136M.',NULL,'Current non drinker'),('alcohol-non-drinker',1,'136M.00',NULL,'Current non drinker');
INSERT INTO #codesreadv2
VALUES ('alcohol-weekly-intake',1,'136V.',NULL,'Alcohol units per week'),('alcohol-weekly-intake',1,'136V.00',NULL,'Alcohol units per week'),('alcohol-weekly-intake',1,'136..',NULL,'Alcohol consumption'),('alcohol-weekly-intake',1,'136..00',NULL,'Alcohol consumption');
INSERT INTO #codesreadv2
VALUES ('bmi',2,'22K..',NULL,'Body Mass Index'),('bmi',2,'22K..00',NULL,'Body Mass Index'),('bmi',2,'22KB.',NULL,'Baseline body mass index'),('bmi',2,'22KB.00',NULL,'Baseline body mass index');
INSERT INTO #codesreadv2
VALUES ('smoking-status-current',1,'137P.',NULL,'Cigarette smoker'),('smoking-status-current',1,'137P.00',NULL,'Cigarette smoker'),('smoking-status-current',1,'13p3.',NULL,'Smoking status at 52 weeks'),('smoking-status-current',1,'13p3.00',NULL,'Smoking status at 52 weeks'),('smoking-status-current',1,'1374.',NULL,'Moderate smoker - 10-19 cigs/d'),('smoking-status-current',1,'1374.00',NULL,'Moderate smoker - 10-19 cigs/d'),('smoking-status-current',1,'137G.',NULL,'Trying to give up smoking'),('smoking-status-current',1,'137G.00',NULL,'Trying to give up smoking'),('smoking-status-current',1,'137R.',NULL,'Current smoker'),('smoking-status-current',1,'137R.00',NULL,'Current smoker'),('smoking-status-current',1,'1376.',NULL,'Very heavy smoker - 40+cigs/d'),('smoking-status-current',1,'1376.00',NULL,'Very heavy smoker - 40+cigs/d'),('smoking-status-current',1,'1375.',NULL,'Heavy smoker - 20-39 cigs/day'),('smoking-status-current',1,'1375.00',NULL,'Heavy smoker - 20-39 cigs/day'),('smoking-status-current',1,'1373.',NULL,'Light smoker - 1-9 cigs/day'),('smoking-status-current',1,'1373.00',NULL,'Light smoker - 1-9 cigs/day'),('smoking-status-current',1,'137M.',NULL,'Rolls own cigarettes'),('smoking-status-current',1,'137M.00',NULL,'Rolls own cigarettes'),('smoking-status-current',1,'137o.',NULL,'Waterpipe tobacco consumption'),('smoking-status-current',1,'137o.00',NULL,'Waterpipe tobacco consumption'),('smoking-status-current',1,'137m.',NULL,'Failed attempt to stop smoking'),('smoking-status-current',1,'137m.00',NULL,'Failed attempt to stop smoking'),('smoking-status-current',1,'137h.',NULL,'Minutes from waking to first tobacco consumption'),('smoking-status-current',1,'137h.00',NULL,'Minutes from waking to first tobacco consumption'),('smoking-status-current',1,'137g.',NULL,'Cigarette pack-years'),('smoking-status-current',1,'137g.00',NULL,'Cigarette pack-years'),('smoking-status-current',1,'137f.',NULL,'Reason for restarting smoking'),('smoking-status-current',1,'137f.00',NULL,'Reason for restarting smoking'),('smoking-status-current',1,'137e.',NULL,'Smoking restarted'),('smoking-status-current',1,'137e.00',NULL,'Smoking restarted'),('smoking-status-current',1,'137d.',NULL,'Not interested in stopping smoking'),('smoking-status-current',1,'137d.00',NULL,'Not interested in stopping smoking'),('smoking-status-current',1,'137c.',NULL,'Thinking about stopping smoking'),('smoking-status-current',1,'137c.00',NULL,'Thinking about stopping smoking'),('smoking-status-current',1,'137b.',NULL,'Ready to stop smoking'),('smoking-status-current',1,'137b.00',NULL,'Ready to stop smoking'),('smoking-status-current',1,'137C.',NULL,'Keeps trying to stop smoking'),('smoking-status-current',1,'137C.00',NULL,'Keeps trying to stop smoking'),('smoking-status-current',1,'137J.',NULL,'Cigar smoker'),('smoking-status-current',1,'137J.00',NULL,'Cigar smoker'),('smoking-status-current',1,'137H.',NULL,'Pipe smoker'),('smoking-status-current',1,'137H.00',NULL,'Pipe smoker'),('smoking-status-current',1,'137a.',NULL,'Pipe tobacco consumption'),('smoking-status-current',1,'137a.00',NULL,'Pipe tobacco consumption'),('smoking-status-current',1,'137Z.',NULL,'Tobacco consumption NOS'),('smoking-status-current',1,'137Z.00',NULL,'Tobacco consumption NOS'),('smoking-status-current',1,'137Y.',NULL,'Cigar consumption'),('smoking-status-current',1,'137Y.00',NULL,'Cigar consumption'),('smoking-status-current',1,'137X.',NULL,'Cigarette consumption'),('smoking-status-current',1,'137X.00',NULL,'Cigarette consumption'),('smoking-status-current',1,'137V.',NULL,'Smoking reduced'),('smoking-status-current',1,'137V.00',NULL,'Smoking reduced'),('smoking-status-current',1,'137Q.',NULL,'Smoking started'),('smoking-status-current',1,'137Q.00',NULL,'Smoking started');
INSERT INTO #codesreadv2
VALUES ('smoking-status-currently-not',1,'137L.',NULL,'Current non-smoker'),('smoking-status-currently-not',1,'137L.00',NULL,'Current non-smoker');
INSERT INTO #codesreadv2
VALUES ('smoking-status-ex',1,'137l.',NULL,'Ex roll-up cigarette smoker'),('smoking-status-ex',1,'137l.00',NULL,'Ex roll-up cigarette smoker'),('smoking-status-ex',1,'137j.',NULL,'Ex-cigarette smoker'),('smoking-status-ex',1,'137j.00',NULL,'Ex-cigarette smoker'),('smoking-status-ex',1,'137S.',NULL,'Ex smoker'),('smoking-status-ex',1,'137S.00',NULL,'Ex smoker'),('smoking-status-ex',1,'137O.',NULL,'Ex cigar smoker'),('smoking-status-ex',1,'137O.00',NULL,'Ex cigar smoker'),('smoking-status-ex',1,'137N.',NULL,'Ex pipe smoker'),('smoking-status-ex',1,'137N.00',NULL,'Ex pipe smoker'),('smoking-status-ex',1,'137F.',NULL,'Ex-smoker - amount unknown'),('smoking-status-ex',1,'137F.00',NULL,'Ex-smoker - amount unknown'),('smoking-status-ex',1,'137B.',NULL,'Ex-very heavy smoker (40+/day)'),('smoking-status-ex',1,'137B.00',NULL,'Ex-very heavy smoker (40+/day)'),('smoking-status-ex',1,'137A.',NULL,'Ex-heavy smoker (20-39/day)'),('smoking-status-ex',1,'137A.00',NULL,'Ex-heavy smoker (20-39/day)'),('smoking-status-ex',1,'1379.',NULL,'Ex-moderate smoker (10-19/day)'),('smoking-status-ex',1,'1379.00',NULL,'Ex-moderate smoker (10-19/day)'),('smoking-status-ex',1,'1378.',NULL,'Ex-light smoker (1-9/day)'),('smoking-status-ex',1,'1378.00',NULL,'Ex-light smoker (1-9/day)'),('smoking-status-ex',1,'137K.',NULL,'Stopped smoking'),('smoking-status-ex',1,'137K.00',NULL,'Stopped smoking'),('smoking-status-ex',1,'137K0',NULL,'Recently stopped smoking'),('smoking-status-ex',1,'137K000',NULL,'Recently stopped smoking'),('smoking-status-ex',1,'137T.',NULL,'Date ceased smoking'),('smoking-status-ex',1,'137T.00',NULL,'Date ceased smoking'),('smoking-status-ex',1,'13p4.',NULL,'Smoking free weeks'),('smoking-status-ex',1,'13p4.00',NULL,'Smoking free weeks');
INSERT INTO #codesreadv2
VALUES ('smoking-status-ex-trivial',1,'1377.',NULL,'Ex-trivial smoker (<1/day)'),('smoking-status-ex-trivial',1,'1377.00',NULL,'Ex-trivial smoker (<1/day)');
INSERT INTO #codesreadv2
VALUES ('smoking-status-never',1,'1371.',NULL,'Never smoked tobacco'),('smoking-status-never',1,'1371.00',NULL,'Never smoked tobacco');
INSERT INTO #codesreadv2
VALUES ('smoking-status-passive',1,'137I.',NULL,'Passive smoker'),('smoking-status-passive',1,'137I.00',NULL,'Passive smoker'),('smoking-status-passive',1,'137I0',NULL,'Exposed to tobacco smoke at home'),('smoking-status-passive',1,'137I000',NULL,'Exposed to tobacco smoke at home'),('smoking-status-passive',1,'13WF4',NULL,'Passive smoking risk'),('smoking-status-passive',1,'13WF400',NULL,'Passive smoking risk');
INSERT INTO #codesreadv2
VALUES ('smoking-status-trivial',1,'1372.',NULL,'Trivial smoker - < 1 cig/day'),('smoking-status-trivial',1,'1372.00',NULL,'Trivial smoker - < 1 cig/day')

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
VALUES ('dementia',1,'1461.',NULL,'H/O: dementia'),('dementia',1,'A410.',NULL,'Kuru'),('dementia',1,'A411.',NULL,'Creutzfeldt-Jakob disease'),('dementia',1,'E00..',NULL,'Senile and presenile organic psychot conditions (& dementia)'),('dementia',1,'E000.',NULL,'Uncomplicated senile dementia'),('dementia',1,'E001.',NULL,'Presenile dementia'),('dementia',1,'E0010',NULL,'Uncomplicated presenile dementia'),('dementia',1,'E0011',NULL,'Presenile dementia with delirium'),('dementia',1,'E0012',NULL,'Presenile dementia with paranoia'),('dementia',1,'E0013',NULL,'Presenile dementia with depression'),('dementia',1,'E001z',NULL,'Presenile dementia NOS'),('dementia',1,'E002.',NULL,'Senile dementia with depressive or paranoid features'),('dementia',1,'E0020',NULL,'Senile dementia with paranoia'),('dementia',1,'E0021',NULL,'Senile dementia with depression'),('dementia',1,'E002z',NULL,'Senile dementia with depressive or paranoid features NOS'),('dementia',1,'E003.',NULL,'Senile dementia with delirium'),('dementia',1,'E004.',NULL,'Arteriosclerotic dementia (including [multi infarct dement])'),('dementia',1,'E0040',NULL,'Uncomplicated arteriosclerotic dementia'),('dementia',1,'E0041',NULL,'Arteriosclerotic dementia with delirium'),('dementia',1,'E0042',NULL,'Arteriosclerotic dementia with paranoia'),('dementia',1,'E0043',NULL,'Arteriosclerotic dementia with depression'),('dementia',1,'E004z',NULL,'Arteriosclerotic dementia NOS'),('dementia',1,'E00y.',NULL,'(Oth senile/presen org psychoses) or (presbyophren psychos)'),('dementia',1,'E00z.',NULL,'Senile or presenile psychoses NOS'),('dementia',1,'E011.',NULL,'Korsakov psychosis'),('dementia',1,'E0110',NULL,'Korsakov psychosis'),('dementia',1,'E0111',NULL,'Korsakovs alcoholic psychosis with peripheral neuritis'),('dementia',1,'E0112',NULL,'Wernicke-Korsakov syndrome'),('dementia',1,'E011z',NULL,'Alcohol amnestic syndrome NOS'),('dementia',1,'E012.',NULL,'Alcoholic dementia: [other] or [NOS]'),('dementia',1,'E040.',NULL,'Korsakoffs syndrome - non-alcoholic'),('dementia',1,'E041.',NULL,'Dementia in conditions EC'),('dementia',1,'Eu00.',NULL,'[X]Dementia in Alzheimers disease'),('dementia',1,'Eu001',NULL,'Dementia in Alzheimers disease with late onset'),('dementia',1,'Eu002',NULL,'[X]Dementia in Alzheimers dis, atypical or mixed type'),('dementia',1,'Eu00z',NULL,'[X]Dementia in Alzheimers disease, unspecified'),('dementia',1,'Eu01.',NULL,'Vascular dementia'),('dementia',1,'Eu011',NULL,'[X]Dementia: [multi-infarct] or [predominantly cortical]'),('dementia',1,'Eu01y',NULL,'[X]Other vascular dementia'),('dementia',1,'Eu01z',NULL,'[X]Vascular dementia, unspecified'),('dementia',1,'Eu02.',NULL,'[X]Dementia in other diseases classified elsewhere'),('dementia',1,'Eu020',NULL,'[X]Dementia in Picks disease'),('dementia',1,'Eu021',NULL,'[X]Dementia in Creutzfeldt-Jakob disease'),('dementia',1,'Eu022',NULL,'[X]Dementia in Huntingtons disease'),('dementia',1,'Eu023',NULL,'[X]Dementia in Parkinsons disease'),('dementia',1,'Eu02y',NULL,'[X]Dementia in other specified diseases classif elsewhere'),('dementia',1,'Eu02z',NULL,'[X] Dementia: [unspecified] or [named variants (& NOS)]'),('dementia',1,'Eu041',NULL,'[X]Delirium superimposed on dementia'),('dementia',1,'F110.',NULL,'Alzheimers disease'),('dementia',1,'F1100',NULL,'Dementia in Alzheimers disease with early onset'),('dementia',1,'F1101',NULL,'Dementia in Alzheimers disease with late onset'),('dementia',1,'F111.',NULL,'Picks disease'),('dementia',1,'F11x7',NULL,'Cerebral degeneration due to Creutzfeldt-Jakob disease'),('dementia',1,'F11x8',NULL,'Cerebral degeneration due to multifocal leucoencephalopathy'),('dementia',1,'F21y2',NULL,'Binswangers disease'),('dementia',1,'Fyu30',NULL,'[X]Other Alzheimers disease'),('dementia',1,'Ub1T6',NULL,'Language disorder of dementia'),('dementia',1,'X002m',NULL,'Amyotrophic lateral sclerosis with dementia'),('dementia',1,'X002w',NULL,'Dementia'),('dementia',1,'X002x',NULL,'Dementia in Alzheimers disease with early onset'),('dementia',1,'X002y',NULL,'Familial Alzheimers disease of early onset'),('dementia',1,'X002z',NULL,'Non-familial Alzheimers disease of early onset'),('dementia',1,'X0030',NULL,'Dementia in Alzheimers disease with late onset'),('dementia',1,'X0031',NULL,'Familial Alzheimers disease of late onset'),('dementia',1,'X0032',NULL,'Non-familial Alzheimers disease of late onset'),('dementia',1,'X0033',NULL,'Focal Alzheimers disease'),('dementia',1,'X0034',NULL,'Frontotemporal dementia'),('dementia',1,'X0035',NULL,'Picks disease with Pick bodies'),('dementia',1,'X0036',NULL,'Picks disease with Pick cells and no Pick bodies'),('dementia',1,'X0037',NULL,'Frontotemporal degeneration'),('dementia',1,'X0039',NULL,'Frontal lobe degeneration with motor neurone disease'),('dementia',1,'X003A',NULL,'Lewy body disease'),('dementia',1,'X003G',NULL,'Progressive aphasia in Alzheimers disease'),('dementia',1,'X003H',NULL,'Argyrophilic brain disease'),('dementia',1,'X003I',NULL,'Post-traumatic dementia'),('dementia',1,'X003J',NULL,'Punch drunk syndrome'),('dementia',1,'X003K',NULL,'Spongiform encephalopathy'),('dementia',1,'X003L',NULL,'Prion protein disease'),('dementia',1,'X003M',NULL,'Gerstmann-Straussler-Scheinker syndrome'),('dementia',1,'X003P',NULL,'Acquired immune deficiency syndrome dementia complex'),('dementia',1,'X003R',NULL,'Vascular dementia of acute onset'),('dementia',1,'X003T',NULL,'Subcortical vascular dementia'),('dementia',1,'X003V',NULL,'Mixed cortical and subcortical vascular dementia'),('dementia',1,'X003W',NULL,'Semantic dementia'),('dementia',1,'X003X',NULL,'Patchy dementia'),('dementia',1,'X003Y',NULL,'Epileptic dementia'),('dementia',1,'X003l',NULL,'Parkinsons disease - dementia complex on Guam'),('dementia',1,'X00R0',NULL,'Presbyophrenic psychosis'),('dementia',1,'X00R2',NULL,'Senile dementia'),('dementia',1,'X00Rk',NULL,'Alcoholic dementia NOS'),('dementia',1,'X73mf',NULL,'Creutzfeldt-Jakob disease agent'),('dementia',1,'X73mj',NULL,'Bovine spongiform encephalopathy agent'),('dementia',1,'XE1Xr',NULL,'Senile and presenile organic psychotic conditions'),('dementia',1,'XE1Xs',NULL,'Vascular dementia'),('dementia',1,'XE1Xt',NULL,'Other senile and presenile organic psychoses'),('dementia',1,'XE1Xu',NULL,'Other alcoholic dementia'),('dementia',1,'XE1Z6',NULL,'[X]Unspecified dementia'),('dementia',1,'XE1aG',NULL,'Dementia (& [presenile] or [senile])'),('dementia',1,'Xa0lH',NULL,'Multi-infarct dementia'),('dementia',1,'Xa0sC',NULL,'Frontal lobe degeneration'),('dementia',1,'Xa0sE',NULL,'Dementia of frontal lobe type'),('dementia',1,'Xa1GB',NULL,'Cerebral degeneration presenting primarily with dementia'),('dementia',1,'Xa25J',NULL,'Alcoholic dementia'),('dementia',1,'Xa3ez',NULL,'Other senile/presenile dementia'),('dementia',1,'XaA1S',NULL,'New variant of Creutzfeldt-Jakob disease'),('dementia',1,'XaE74',NULL,'Senile dementia of the Lewy body type'),('dementia',1,'XaIKB',NULL,'Alzheimers disease with early onset'),('dementia',1,'XaIKC',NULL,'Alzheimers disease with late onset'),('dementia',1,'XaKyY',NULL,'[X]Lewy body dementia'),('dementia',1,'XaLFf',NULL,'Exception reporting: dementia quality indicators'),('dementia',1,'XaLFo',NULL,'Excepted from dementia quality indicators: Patient unsuitabl'),('dementia',1,'XaLFp',NULL,'Excepted from dementia quality indicators: Informed dissent'),('dementia',1,'XaMAo',NULL,'Prion protein markers for Creutzfeldt-Jakob disease'),('dementia',1,'XaMFy',NULL,'Dementia monitoring administration'),('dementia',1,'XaMG0',NULL,'Dementia monitoring first letter'),('dementia',1,'XaMGF',NULL,'Dementia annual review'),('dementia',1,'XaMGG',NULL,'Dementia monitoring second letter'),('dementia',1,'XaMGI',NULL,'Dementia monitoring third letter'),('dementia',1,'XaMGJ',NULL,'Dementia monitoring verbal invite'),('dementia',1,'XaMGK',NULL,'Dementia monitoring telephone invite'),('dementia',1,'XaMJC',NULL,'Dementia monitoring'),('dementia',1,'XaZWz',NULL,'Participates in Butterfly Scheme for dementia'),('dementia',1,'XaZX0',NULL,'Butterfly Scheme for dementia declined'),('dementia',1,'XabVp',NULL,'Sporadic Creutzfeldt-Jakob disease'),('dementia',1,'XabtQ',NULL,'Dementia medication review'),('dementia',1,'Xaghb',NULL,'Predominantly cortical dementia'),('dementia',1,'Y000c',NULL,'Dementia review done'),('dementia',1,'Y1f1d',NULL,'Dementia monitoring invitation'),('dementia',1,'Y1f22',NULL,'Dementia monitoring invitation'),('dementia',1,'Y1f98',NULL,'Quality and Outcomes Framework dementia quality indicator-related care invitation (procedure)'),('dementia',1,'Y23fb',NULL,'Mixed dementia'),('dementia',1,'Y6230',NULL,'Creutzfeldt - Jakob disease'),('dementia',1,'Y8180',NULL,'Other senile/presenile dement.'),('dementia',1,'Y9086',NULL,'Senile dementia - simple type'),('dementia',1,'Y9087',NULL,'Senile dementia-acute confused'),('dementia',1,'Eu106',NULL,'[X]Korsakovs psychosis, alcohol-induced'),('dementia',1,'Eu107',NULL,'[X]Alcoholic dementia NOS'),('dementia',1,'XE17j',NULL,'Alzheimers disease'),('dementia',1,'XE1aI',NULL,'Korsakov psychosis');
INSERT INTO #codesctv3
VALUES ('alcohol-heavy-drinker',1,'136K.',NULL,'Alcohol intake above recommended sensible limits'),('alcohol-heavy-drinker',1,'E23..',NULL,'Alcohol problem drinking'),('alcohol-heavy-drinker',1,'Eu101',NULL,'[X]Mental and behavioural disorders due to use of alcohol: harmful use'),('alcohol-heavy-drinker',1,'Ub0lO',NULL,'Drinks heavily'),('alcohol-heavy-drinker',1,'Ub0lP',NULL,'Very heavy drinker'),('alcohol-heavy-drinker',1,'Ub0lt',NULL,'Drinks in morning to get rid of hangover'),('alcohol-heavy-drinker',1,'Ub0ly',NULL,'Binge drinker'),('alcohol-heavy-drinker',1,'Ub0mj',NULL,'Feels should cut down drinking'),('alcohol-heavy-drinker',1,'Xa1yZ',NULL,'Alcohol abuse'),('alcohol-heavy-drinker',1,'XaA1V',NULL,'Ethanol abuse'),('alcohol-heavy-drinker',1,'XaKvA',NULL,'Hazardous alcohol use'),('alcohol-heavy-drinker',1,'XaKvB',NULL,'Harmful alcohol use'),('alcohol-heavy-drinker',1,'XaXje',NULL,'Higher risk drinking'),('alcohol-heavy-drinker',1,'XE1YQ',NULL,'Alcohol problem drinking');
INSERT INTO #codesctv3
VALUES ('alcohol-light-drinker',1,'1362.00',NULL,'Trivial drinker - <1u/day');
INSERT INTO #codesctv3
VALUES ('alcohol-moderate-drinker',1,'136F.',NULL,'Spirit drinker'),('alcohol-moderate-drinker',1,'136G.',NULL,'Beer drinker'),('alcohol-moderate-drinker',1,'136H.',NULL,'Drinks beer and spirits'),('alcohol-moderate-drinker',1,'136I.',NULL,'Drinks wine'),('alcohol-moderate-drinker',1,'136J.',NULL,'Social drinker'),('alcohol-moderate-drinker',1,'136L.',NULL,'Alcohol intake within recommended sensible limits'),('alcohol-moderate-drinker',1,'136Z.',NULL,'Alcohol consumption NOS'),('alcohol-moderate-drinker',1,'Ub0lM',NULL,'Moderate drinker'),('alcohol-moderate-drinker',1,'XaXjd',NULL,'Increasing risk drinking'),('alcohol-moderate-drinker',1,'XaXjd',NULL,'Increasing risk drinking');
INSERT INTO #codesctv3
VALUES ('alcohol-non-drinker',1,'1361.',NULL,'Teetotaller'),('alcohol-non-drinker',1,'136M.',NULL,'Current non-drinker');
INSERT INTO #codesctv3
VALUES ('alcohol-weekly-intake',1,'136..',NULL,'AI - Alcohol intake'),('alcohol-weekly-intake',1,'Ub173',NULL,'Alcohol units per week');
INSERT INTO #codesctv3
VALUES ('bmi',2,'22K..',NULL,'Body Mass Index'),('bmi',2,'X76CO',NULL,'Quetelet index'),('bmi',2,'Xa7wG',NULL,'Observation of body mass index'),('bmi',2,'XaZcl',NULL,'Baseline body mass index');
INSERT INTO #codesctv3
VALUES ('smoking-status-current',1,'1373.',NULL,'Lt cigaret smok, 1-9 cigs/day'),('smoking-status-current',1,'1374.',NULL,'Mod cigaret smok, 10-19 cigs/d'),('smoking-status-current',1,'1375.',NULL,'Hvy cigaret smok, 20-39 cigs/d'),('smoking-status-current',1,'1376.',NULL,'Very hvy cigs smoker,40+cigs/d'),('smoking-status-current',1,'137C.',NULL,'Keeps trying to stop smoking'),('smoking-status-current',1,'137D.',NULL,'Admitted tobacco cons untrue ?'),('smoking-status-current',1,'137G.',NULL,'Trying to give up smoking'),('smoking-status-current',1,'137H.',NULL,'Pipe smoker'),('smoking-status-current',1,'137J.',NULL,'Cigar smoker'),('smoking-status-current',1,'137M.',NULL,'Rolls own cigarettes'),('smoking-status-current',1,'137P.',NULL,'Cigarette smoker'),('smoking-status-current',1,'137Q.',NULL,'Smoking started'),('smoking-status-current',1,'137R.',NULL,'Current smoker'),('smoking-status-current',1,'137Z.',NULL,'Tobacco consumption NOS'),('smoking-status-current',1,'Ub1tI',NULL,'Cigarette consumption'),('smoking-status-current',1,'Ub1tJ',NULL,'Cigar consumption'),('smoking-status-current',1,'Ub1tK',NULL,'Pipe tobacco consumption'),('smoking-status-current',1,'XaBSp',NULL,'Smoking restarted'),('smoking-status-current',1,'XaIIu',NULL,'Smoking reduced'),('smoking-status-current',1,'XaIkW',NULL,'Thinking about stop smoking'),('smoking-status-current',1,'XaIkX',NULL,'Ready to stop smoking'),('smoking-status-current',1,'XaIkY',NULL,'Not interested stop smoking'),('smoking-status-current',1,'XaItg',NULL,'Reason for restarting smoking'),('smoking-status-current',1,'XaIuQ',NULL,'Cigarette pack-years'),('smoking-status-current',1,'XaJX2',NULL,'Min from wake to 1st tobac con'),('smoking-status-current',1,'XaWNE',NULL,'Failed attempt to stop smoking'),('smoking-status-current',1,'XaZIE',NULL,'Waterpipe tobacco consumption'),('smoking-status-current',1,'XE0og',NULL,'Tobacco smoking consumption'),('smoking-status-current',1,'XE0oq',NULL,'Cigarette smoker'),('smoking-status-current',1,'XE0or',NULL,'Smoking started');
INSERT INTO #codesctv3
VALUES ('smoking-status-currently-not',1,'Ub0oq',NULL,'Non-smoker'),('smoking-status-currently-not',1,'137L.',NULL,'Current non-smoker');
INSERT INTO #codesctv3
VALUES ('smoking-status-ex',1,'1378.',NULL,'Ex-light smoker (1-9/day)'),('smoking-status-ex',1,'1379.',NULL,'Ex-moderate smoker (10-19/day)'),('smoking-status-ex',1,'137A.',NULL,'Ex-heavy smoker (20-39/day)'),('smoking-status-ex',1,'137B.',NULL,'Ex-very heavy smoker (40+/day)'),('smoking-status-ex',1,'137F.',NULL,'Ex-smoker - amount unknown'),('smoking-status-ex',1,'137K.',NULL,'Stopped smoking'),('smoking-status-ex',1,'137N.',NULL,'Ex-pipe smoker'),('smoking-status-ex',1,'137O.',NULL,'Ex-cigar smoker'),('smoking-status-ex',1,'137T.',NULL,'Date ceased smoking'),('smoking-status-ex',1,'Ub1na',NULL,'Ex-smoker'),('smoking-status-ex',1,'Xa1bv',NULL,'Ex-cigarette smoker'),('smoking-status-ex',1,'XaIr7',NULL,'Smoking free weeks'),('smoking-status-ex',1,'XaKlS',NULL,'[V]PH of tobacco abuse'),('smoking-status-ex',1,'XaQ8V',NULL,'Ex roll-up cigarette smoker'),('smoking-status-ex',1,'XaQzw',NULL,'Recently stopped smoking'),('smoking-status-ex',1,'XE0ok',NULL,'Ex-light cigaret smok, 1-9/day'),('smoking-status-ex',1,'XE0ol',NULL,'Ex-mod cigaret smok, 10-19/day'),('smoking-status-ex',1,'XE0om',NULL,'Ex-heav cigaret smok,20-39/day'),('smoking-status-ex',1,'XE0on',NULL,'Ex-very hv cigaret smk,40+/day');
INSERT INTO #codesctv3
VALUES ('smoking-status-ex-trivial',1,'XE0oj',NULL,'Ex-triv cigaret smoker, <1/day'),('smoking-status-ex-trivial',1,'1377.',NULL,'Ex-trivial smoker (<1/day)');
INSERT INTO #codesctv3
VALUES ('smoking-status-never',1,'XE0oh',NULL,'Never smoked tobacco'),('smoking-status-never',1,'1371.',NULL,'Never smoked tobacco');
INSERT INTO #codesctv3
VALUES ('smoking-status-passive',1,'137I.',NULL,'Passive smoker'),('smoking-status-passive',1,'Ub0pe',NULL,'Exposed to tobacco smoke at work'),('smoking-status-passive',1,'Ub0pf',NULL,'Exposed to tobacco smoke at home'),('smoking-status-passive',1,'Ub0pg',NULL,'Exposed to tobacco smoke in public places'),('smoking-status-passive',1,'13WF4',NULL,'Passive smoking risk');
INSERT INTO #codesctv3
VALUES ('smoking-status-trivial',1,'XagO3',NULL,'Occasional tobacco smoker'),('smoking-status-trivial',1,'XE0oi',NULL,'Triv cigaret smok, < 1 cig/day'),('smoking-status-trivial',1,'1372.',NULL,'Trivial smoker - < 1 cig/day')

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

INSERT INTO #codessnomed
VALUES ('alcohol-heavy-drinker',1,'15167005',NULL,'Alcohol abuse (disorder)'),('alcohol-heavy-drinker',1,'160592001',NULL,'Alcohol intake above recommended sensible limits (finding)'),('alcohol-heavy-drinker',1,'198421000000108',NULL,'Hazardous alcohol use (observable entity)'),('alcohol-heavy-drinker',1,'198431000000105',NULL,'Harmful alcohol use (observable entity)'),('alcohol-heavy-drinker',1,'228279004',NULL,'Very heavy drinker (life style)'),('alcohol-heavy-drinker',1,'228310006',NULL,'Drinks in morning to get rid of hangover (finding)'),('alcohol-heavy-drinker',1,'228315001',NULL,'Binge drinker (finding)'),('alcohol-heavy-drinker',1,'228362008',NULL,'Feels should cut down drinking (finding)'),('alcohol-heavy-drinker',1,'7200002',NULL,'Alcoholism (disorder)'),('alcohol-heavy-drinker',1,'777651000000101',NULL,'Higher risk alcohol drinking (finding)'),('alcohol-heavy-drinker',1,'86933000',NULL,'Heavy drinker (life style)');
INSERT INTO #codessnomed
VALUES ('alcohol-light-drinker',1,'228276006',NULL,'Occasional drinker (life style)'),('alcohol-light-drinker',1,'228277002',NULL,'Light drinker (life style)'),('alcohol-light-drinker',1,'266917007',NULL,'Trivial drinker - <1u/day (life style)'),('alcohol-light-drinker',1,'777671000000105',NULL,'Lower risk alcohol drinking (finding)');
INSERT INTO #codessnomed
VALUES ('alcohol-moderate-drinker',1,'160588008',NULL,'Spirit drinker (life style)'),('alcohol-moderate-drinker',1,'160589000',NULL,'Beer drinker (life style)'),('alcohol-moderate-drinker',1,'160590009',NULL,'Drinks beer and spirits (life style)'),('alcohol-moderate-drinker',1,'160591008',NULL,'Drinks wine (life style)'),('alcohol-moderate-drinker',1,'160593006',NULL,'Alcohol intake within recommended sensible limits (finding)'),('alcohol-moderate-drinker',1,'28127009',NULL,'Social drinker (life style)'),('alcohol-moderate-drinker',1,'43783005',NULL,'Moderate drinker (life style)');
INSERT INTO #codessnomed
VALUES ('alcohol-non-drinker',1,'105542008',NULL,'Teetotaller (life style)');
INSERT INTO #codessnomed
VALUES ('alcohol-weekly-intake',1,'160573003',NULL,'Alcohol intake (observable entity)'),('alcohol-weekly-intake',1,'228958009',NULL,'alcohol units/week (qualifier value)');
INSERT INTO #codessnomed
VALUES ('bmi',2,'301331008',NULL,'Finding of body mass index (finding)'),('bmi',2,'60621009',NULL,'Body mass index (observable entity)'),('bmi',2,'846931000000101',NULL,'Baseline body mass index (observable entity)');
INSERT INTO #codessnomed
VALUES ('smoking-status-current',1,'266929003',NULL,'Smoking started (life style)'),('smoking-status-current',1,'836001000000109',NULL,'Waterpipe tobacco consumption (observable entity)'),('smoking-status-current',1,'77176002',NULL,'Smoker (life style)'),('smoking-status-current',1,'65568007',NULL,'Cigarette smoker (life style)'),('smoking-status-current',1,'394873005',NULL,'Not interested in stopping smoking (finding)'),('smoking-status-current',1,'394872000',NULL,'Ready to stop smoking (finding)'),('smoking-status-current',1,'394871007',NULL,'Thinking about stopping smoking (observable entity)'),('smoking-status-current',1,'266918002',NULL,'Tobacco smoking consumption (observable entity)'),('smoking-status-current',1,'230057008',NULL,'Cigar consumption (observable entity)'),('smoking-status-current',1,'230056004',NULL,'Cigarette consumption (observable entity)'),('smoking-status-current',1,'160623006',NULL,'Smoking: [started] or [restarted]'),('smoking-status-current',1,'160622001',NULL,'Smoker (& cigarette)'),('smoking-status-current',1,'160619003',NULL,'Rolls own cigarettes (finding)'),('smoking-status-current',1,'160616005',NULL,'Trying to give up smoking (finding)'),('smoking-status-current',1,'160612007',NULL,'Keeps trying to stop smoking (finding)'),('smoking-status-current',1,'160606002',NULL,'Very heavy cigarette smoker (40+ cigs/day) (life style)'),('smoking-status-current',1,'160605003',NULL,'Heavy cigarette smoker (20-39 cigs/day) (life style)'),('smoking-status-current',1,'160604004',NULL,'Moderate cigarette smoker (10-19 cigs/day) (life style)'),('smoking-status-current',1,'160603005',NULL,'Light cigarette smoker (1-9 cigs/day) (life style)'),('smoking-status-current',1,'59978006',NULL,'Cigar smoker (life style)'),('smoking-status-current',1,'446172000',NULL,'Failed attempt to stop smoking (finding)'),('smoking-status-current',1,'413173009',NULL,'Minutes from waking to first tobacco consumption (observable entity)'),('smoking-status-current',1,'401201003',NULL,'Cigarette pack-years (observable entity)'),('smoking-status-current',1,'401159003',NULL,'Reason for restarting smoking (observable entity)'),('smoking-status-current',1,'308438006',NULL,'Smoking restarted (life style)'),('smoking-status-current',1,'230058003',NULL,'Pipe tobacco consumption (observable entity)'),('smoking-status-current',1,'134406006',NULL,'Smoking reduced (observable entity)'),('smoking-status-current',1,'82302008',NULL,'Pipe smoker (life style)');
INSERT INTO #codessnomed
VALUES ('smoking-status-currently-not',1,'160618006',NULL,'Current non-smoker (life style)'),('smoking-status-currently-not',1,'8392000',NULL,'Non-smoker (life style)');
INSERT INTO #codessnomed
VALUES ('smoking-status-ex',1,'160617001',NULL,'Stopped smoking (life style)'),('smoking-status-ex',1,'160620009',NULL,'Ex-pipe smoker (life style)'),('smoking-status-ex',1,'160621008',NULL,'Ex-cigar smoker (life style)'),('smoking-status-ex',1,'160625004',NULL,'Date ceased smoking (observable entity)'),('smoking-status-ex',1,'266922007',NULL,'Ex-light cigarette smoker (1-9/day) (life style)'),('smoking-status-ex',1,'266923002',NULL,'Ex-moderate cigarette smoker (10-19/day) (life style)'),('smoking-status-ex',1,'266924008',NULL,'Ex-heavy cigarette smoker (20-39/day) (life style)'),('smoking-status-ex',1,'266925009',NULL,'Ex-very heavy cigarette smoker (40+/day) (life style)'),('smoking-status-ex',1,'281018007',NULL,'Ex-cigarette smoker (life style)'),('smoking-status-ex',1,'395177003',NULL,'Smoking free weeks (observable entity)'),('smoking-status-ex',1,'492191000000103',NULL,'Ex roll-up cigarette smoker (finding)'),('smoking-status-ex',1,'517211000000106',NULL,'Recently stopped smoking (finding)'),('smoking-status-ex',1,'8517006',NULL,'Ex-smoker (life style)');
INSERT INTO #codessnomed
VALUES ('smoking-status-ex-trivial',1,'266921000',NULL,'Ex-trivial cigarette smoker (<1/day) (life style)');
INSERT INTO #codessnomed
VALUES ('smoking-status-never',1,'160601007',NULL,'Non-smoker (& [never smoked tobacco])'),('smoking-status-never',1,'266919005',NULL,'Never smoked tobacco (life style)');
INSERT INTO #codessnomed
VALUES ('smoking-status-passive',1,'43381005',NULL,'Passive smoker (finding)'),('smoking-status-passive',1,'161080002',NULL,'Passive smoking risk (environment)'),('smoking-status-passive',1,'228523000',NULL,'Exposed to tobacco smoke at work (finding)'),('smoking-status-passive',1,'228524006',NULL,'Exposed to tobacco smoke at home (finding)'),('smoking-status-passive',1,'228525007',NULL,'Exposed to tobacco smoke in public places (finding)'),('smoking-status-passive',1,'713142003',NULL,'At risk from passive smoking (finding)'),('smoking-status-passive',1,'722451000000101',NULL,'Passive smoking (qualifier value)');
INSERT INTO #codessnomed
VALUES ('smoking-status-trivial',1,'266920004',NULL,'Trivial cigarette smoker (less than one cigarette/day) (life style)'),('smoking-status-trivial',1,'428041000124106',NULL,'Occasional tobacco smoker (finding)')

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

INSERT INTO #codesemis
VALUES ('dementia',1,'^ESCTAC697343',NULL,'Acquired immune deficiency syndrome-related dementia'),('dementia',1,'^ESCTAC697346',NULL,'Acquired immune deficiency syndrome dementia complex'),('dementia',1,'^ESCTAD697345',NULL,'ADC - Acquired immune deficiency syndrome dementia complex'),('dementia',1,'^ESCTAI697344',NULL,'AIDS - Acquired immune deficiency syndrome dementia complex'),('dementia',1,'^ESCTDE697342',NULL,'Dementia associated with AIDS'),('dementia',1,'^ESCTDE697347',NULL,'Dementia associated with acquired immunodeficiency syndrome'),('dementia',1,'EMISICD10|F0000',NULL,'Dementia in Alzheimers disease with early onset, without additional symptoms'),('dementia',1,'EMISICD10|F0001',NULL,'Dementia in Alzheimers disease with early onset, other symptoms, predominantly delusional'),('dementia',1,'EMISICD10|F0002',NULL,'Dementia in Alzheimers disease with early onset, other symptoms, predominantly hallucinatory'),('dementia',1,'EMISICD10|F0003',NULL,'Dementia in Alzheimers disease with early onset, other symptoms, predominantly depressive'),('dementia',1,'EMISICD10|F0004',NULL,'Dementia in Alzheimers disease with early onset, other mixed symptoms'),('dementia',1,'EMISICD10|F0010',NULL,'Dementia in Alzheimers disease with late onset, without additional symptoms'),('dementia',1,'EMISICD10|F0011',NULL,'Dementia in Alzheimers disease with late onset, other symptoms, predominantly delusional'),('dementia',1,'EMISICD10|F0012',NULL,'Dementia in Alzheimers disease with late onset, other symptoms, predominantly hallucinatory'),('dementia',1,'EMISICD10|F0013',NULL,'Dementia in Alzheimers disease with late onset, other symptoms, predominantly depressive'),('dementia',1,'EMISICD10|F0014',NULL,'Dementia in Alzheimers disease with late onset, other mixed symptoms'),('dementia',1,'EMISICD10|F0020',NULL,'Dementia in Alzheimers dis, atypical or mixed type, without additional symptoms'),('dementia',1,'EMISICD10|F0021',NULL,'Dementia in Alzheimers dis, atypical or mixed type, other symptoms, predominantly delusional'),('dementia',1,'EMISICD10|F0022',NULL,'Dementia in Alzheimers dis, atypical or mixed type, other symptoms, predominantly hallucinatory'),('dementia',1,'EMISICD10|F0023',NULL,'Dementia in Alzheimers dis, atypical or mixed type, other symptoms, predominantly depressive'),('dementia',1,'EMISICD10|F0024',NULL,'Dementia in Alzheimers dis, atypical or mixed type, other mixed symptoms'),('dementia',1,'EMISICD10|F0090',NULL,'Dementia in Alzheimers disease, unspecified, without additional symptoms'),('dementia',1,'EMISICD10|F0091',NULL,'Dementia in Alzheimers disease, unspecified, other symptoms, predominantly delusional'),('dementia',1,'EMISICD10|F0092',NULL,'Dementia in Alzheimers disease, unspecified, other symptoms, predominantly hallucinatory'),('dementia',1,'EMISICD10|F0093',NULL,'Dementia in Alzheimers disease, unspecified, other symptoms, predominantly depressive'),('dementia',1,'EMISICD10|F0094',NULL,'Dementia in Alzheimers disease, unspecified, other mixed symptoms'),('dementia',1,'EMISICD10|F0100',NULL,'Vascular dementia of acute onset, without additional symptoms'),('dementia',1,'EMISICD10|F0101',NULL,'Vascular dementia of acute onset, other symptoms, predominantly delusional'),('dementia',1,'EMISICD10|F0102',NULL,'Vascular dementia of acute onset, other symptoms, predominantly hallucinatory'),('dementia',1,'EMISICD10|F0103',NULL,'Vascular dementia of acute onset, other symptoms, predominantly depressive'),('dementia',1,'EMISICD10|F0104',NULL,'Vascular dementia of acute onset, other mixed symptoms'),('dementia',1,'EMISICD10|F0110',NULL,'Multi-infarct dementia, without additional symptoms'),('dementia',1,'EMISICD10|F0111',NULL,'Multi-infarct dementia, other symptoms, predominantly delusional'),('dementia',1,'EMISICD10|F0112',NULL,'Multi-infarct dementia, other symptoms, predominantly hallucinatory'),('dementia',1,'EMISICD10|F0113',NULL,'Multi-infarct dementia, other symptoms, predominantly depressive'),('dementia',1,'EMISICD10|F0114',NULL,'Multi-infarct dementia, other mixed symptoms'),('dementia',1,'EMISICD10|F0120',NULL,'Subcortical vascular dementia, without additional symptoms'),('dementia',1,'EMISICD10|F0121',NULL,'Subcortical vascular dementia, other symptoms, predominantly delusional'),('dementia',1,'EMISICD10|F0122',NULL,'Subcortical vascular dementia, other symptoms, predominantly hallucinatory'),('dementia',1,'EMISICD10|F0123',NULL,'Subcortical vascular dementia, other symptoms, predominantly depressive'),('dementia',1,'EMISICD10|F0124',NULL,'Subcortical vascular dementia, other mixed symptoms'),('dementia',1,'EMISICD10|F0130',NULL,'Mixed cortical and subcortical vascular dementia, without additional symptoms'),('dementia',1,'EMISICD10|F0131',NULL,'Mixed cortical and subcortical vascular dementia, other symptoms, predominantly delusional'),('dementia',1,'EMISICD10|F0132',NULL,'Mixed cortical and subcortical vascular dementia, other symptoms, predominantly hallucinatory'),('dementia',1,'EMISICD10|F0133',NULL,'Mixed cortical and subcortical vascular dementia, other symptoms, predominantly depressive'),('dementia',1,'EMISICD10|F0134',NULL,'Mixed cortical and subcortical vascular dementia, other mixed symptoms'),('dementia',1,'EMISICD10|F0180',NULL,'Other vascular dementia, without additional symptoms'),('dementia',1,'EMISICD10|F0181',NULL,'Other vascular dementia, other symptoms, predominantly delusional'),('dementia',1,'EMISICD10|F0182',NULL,'Other vascular dementia, other symptoms, predominantly hallucinatory'),('dementia',1,'EMISICD10|F0183',NULL,'Other vascular dementia, other symptoms, predominantly depressive'),('dementia',1,'EMISICD10|F0184',NULL,'Other vascular dementia, other mixed symptoms'),('dementia',1,'EMISICD10|F0190',NULL,'Vascular dementia, unspecified, without additional symptoms'),('dementia',1,'EMISICD10|F0191',NULL,'Vascular dementia, unspecified, other symptoms, predominantly delusional'),('dementia',1,'EMISICD10|F0192',NULL,'Vascular dementia, unspecified, other symptoms, predominantly hallucinatory'),('dementia',1,'EMISICD10|F0193',NULL,'Vascular dementia, unspecified, other symptoms, predominantly depressive'),('dementia',1,'EMISICD10|F0194',NULL,'Vascular dementia, unspecified, other mixed symptoms'),('dementia',1,'EMISICD10|F03X0',NULL,'Unspecified dementia, without additional symptoms'),('dementia',1,'EMISICD10|F03X1',NULL,'Unspecified dementia, other symptoms, predominantly delusional'),('dementia',1,'EMISICD10|F03X2',NULL,'Unspecified dementia, other symptoms, predominantly hallucinatory'),('dementia',1,'EMISICD10|F03X3',NULL,'Unspecified dementia, other symptoms, predominantly depressive'),('dementia',1,'EMISICD10|F03X4',NULL,'Unspecified dementia, other mixed symptoms'),('dementia',1,'^ESCT1171773',NULL,'Predominantly cortical dementia'),('dementia',1,'^ESCT1381019',NULL,'SDLT - senile dementia of Lewy body type'),('dementia',1,'^ESCT1407776',NULL,'Senile Lewy body dementia'),('dementia',1,'^ESCTAL250298',NULL,'Alcohol-induced persisting dementia'),('dementia',1,'^ESCTAL293125',NULL,'Alzheimer dementia'),('dementia',1,'^ESCTAM500542',NULL,'Amyotrophic lateral sclerosis with dementia'),('dementia',1,'^ESCTBI396461',NULL,'Binswangers dementia'),('dementia',1,'^ESCTBO500582',NULL,'Boxers dementia'),('dementia',1,'^ESCTBU828470',NULL,'Butterfly Scheme for dementia declined'),('dementia',1,'^ESCTDE250297',NULL,'Dementia associated with alcoholism'),('dementia',1,'^ESCTDE380265',NULL,'Dementia of the Lewy body type'),('dementia',1,'^ESCTDE500577',NULL,'Dementia due to head trauma'),('dementia',1,'^ESCTDE500580',NULL,'Dementia pugilistica'),('dementia',1,'^ESCTDE561826',NULL,'Dementia of frontal lobe type'),('dementia',1,'^ESCTDE689724',NULL,'Dementia of the Alzheimers type with early onset'),('dementia',1,'^ESCTDE689727',NULL,'Dementia in Alzheimers disease - type 2'),('dementia',1,'^ESCTDE690020',NULL,'Dementia of the Alzheimers type, late onset'),('dementia',1,'^ESCTDE690024',NULL,'Dementia in Alzheimers disease - type 1'),('dementia',1,'^ESCTDE704365',NULL,'Dementia associated with Parkinsons Disease'),('dementia',1,'^ESCTDE704366',NULL,'Dementia associated with Parkinson Disease'),('dementia',1,'^ESCTDE710360',NULL,'Dementia due to Creutzfeldt-Jakob disease'),('dementia',1,'^ESCTDE726301',NULL,'Dementia due to Huntington disease'),('dementia',1,'^ESCTDE726302',NULL,'Dementia due to Huntingtons disease'),('dementia',1,'^ESCTDE800952',NULL,'Dementia due to Picks disease'),('dementia',1,'^ESCTDE800953',NULL,'Dementia due to Pick disease'),('dementia',1,'^ESCTDE800954',NULL,'Dementia co-occurrent and due to Picks disease'),('dementia',1,'^ESCTDF561827',NULL,'DFT - Dementia frontal lobe type'),('dementia',1,'^ESCTEP786368',NULL,'Epilepsy co-occurrent and due to dementia'),('dementia',1,'^ESCTEP786369',NULL,'Epileptic dementia'),('dementia',1,'^ESCTEP786370',NULL,'Epilepsy with dementia'),('dementia',1,'^ESCTFR500560',NULL,'Frontotemporal dementia'),('dementia',1,'^ESCTHI453987',NULL,'History of dementia'),('dementia',1,'^ESCTLA499781',NULL,'Language disorder of dementia'),('dementia',1,'^ESCTLE602407',NULL,'Lewy body dementia'),('dementia',1,'^ESCTMI341423',NULL,'MID - Multi-infarct dementia'),('dementia',1,'^ESCTMU341426',NULL,'Multi infarct dementia'),('dementia',1,'^ESCTOR335044',NULL,'Organic dementia'),('dementia',1,'^ESCTPA351118',NULL,'Parkinson-dementia complex of Guam'),('dementia',1,'^ESCTPA351119',NULL,'Parkinsons disease - dementia complex on Guam'),('dementia',1,'^ESCTPA500588',NULL,'Patchy dementia'),('dementia',1,'^ESCTPA828469',NULL,'Participates in Butterfly Scheme for dementia'),('dementia',1,'^ESCTPO500575',NULL,'Post-traumatic dementia'),('dementia',1,'^ESCTPR689721',NULL,'Primary degenerative dementia of the Alzheimer type, presenile onset'),('dementia',1,'^ESCTPR689722',NULL,'Primary degenerative dementia of the Alzheimer type, early onset'),('dementia',1,'^ESCTPR689725',NULL,'Presenile dementia, Alzheimers type'),
('dementia',1,'^ESCTPR690018',NULL,'Primary degenerative dementia of the Alzheimer type, senile onset'),('dementia',1,'^ESCTPR690019',NULL,'Primary degenerative dementia of the Alzheimer type, late onset'),('dementia',1,'^ESCTPR801011',NULL,'Primary degenerative dementia'),('dementia',1,'^ESCTSD274844',NULL,'SD - Senile dementia'),('dementia',1,'^ESCTSD380263',NULL,'SDLT - Senile dementia of the Lewy body type'),('dementia',1,'^ESCTSD690022',NULL,'SDAT - Senile dementia, Alzheimers type'),('dementia',1,'^ESCTSE500587',NULL,'Semantic dementia'),('dementia',1,'^ESCTSE602406',NULL,'Senile dementia of the Lewy body type'),('dementia',1,'^ESCTSE634806',NULL,'Senile dementia with psychosis'),('dementia',1,'^ESCTSU396466',NULL,'Subcortical atherosclerotic dementia'),('dementia',1,'^ESCTTR251100',NULL,'Transmissible virus dementia'),('dementia',1,'^ESCTVA341425',NULL,'VAD - Vascular dementia'),('dementia',1,'EMISNQDE41',NULL,'Dementia monitoring in primary care'),('dementia',1,'EMISNQDE42',NULL,'Dementia monitoring in secondary care'),('dementia',1,'^ESCTAD293123',NULL,'AD - Alzheimers disease'),('dementia',1,'^ESCTAL293124',NULL,'Alzheimer disease'),('dementia',1,'^ESCTFA500550',NULL,'Familial Alzheimers disease of early onset'),('dementia',1,'^ESCTFA500551',NULL,'Familial Alzheimer disease of early onset'),('dementia',1,'^ESCTFA500554',NULL,'Familial Alzheimers disease of late onset'),('dementia',1,'^ESCTFA500555',NULL,'Familial Alzheimer disease of late onset'),('dementia',1,'^ESCTFO500558',NULL,'Focal Alzheimers disease'),('dementia',1,'^ESCTFO500559',NULL,'Focal Alzheimer disease'),('dementia',1,'^ESCTLE380262',NULL,'Lewy body variant of Alzheimers disease'),('dementia',1,'^ESCTNO500552',NULL,'Non-familial Alzheimers disease of early onset'),('dementia',1,'^ESCTNO500553',NULL,'Non-familial Alzheimer disease of early onset'),('dementia',1,'^ESCTNO500556',NULL,'Non-familial Alzheimers disease of late onset'),('dementia',1,'^ESCTNO500557',NULL,'Non-familial Alzheimer disease of late onset'),('dementia',1,'^ESCTPR500571',NULL,'Progressive aphasia in Alzheimers disease'),('dementia',1,'^ESCTPR500572',NULL,'Progressive aphasia in Alzheimer disease'),('dementia',1,'^ESCTCE476898',NULL,'Cerebral degeneration due to Creutzfeldt-Jakob disease'),('dementia',1,'^ESCTCJ251098',NULL,'CJD - Creutzfeldt-Jakob disease'),('dementia',1,'^ESCTCR251095',NULL,'Creutzfeldt-Jakob disease'),('dementia',1,'^ESCTCR251101',NULL,'Creutzfeldt Jakob disease'),('dementia',1,'^ESCTCR393867',NULL,'Creutzfeldt-Jakob agent'),('dementia',1,'^ESCTCR393869',NULL,'Creutzfeldt-Jakob disease agent'),('dementia',1,'^ESCTCR593165',NULL,'Creutzfeldt-Jakob variant disease'),('dementia',1,'^ESCTJA393868',NULL,'Jakob-Creutzfeldt agent'),('dementia',1,'^ESCTJC251099',NULL,'JCD - Jakob-Creutzfeldt disease'),('dementia',1,'^ESCTNV593163',NULL,'nvCJD - New variant of Creutzfeldt-Jakob disease'),('dementia',1,'^ESCTPR839987',NULL,'Prion protein markers for CJD (Creutzfeldt-Jakob disease)'),('dementia',1,'^ESCTSP769925',NULL,'Sporadic Jakob-Creutzfeldt disease'),('dementia',1,'^ESCTVC593164',NULL,'vCJD - variant Creutzfeldt-Jakob disease'),('dementia',1,'EMISNQSP44',NULL,'Sporadic Creutzfeldt-Jakob disease'),('dementia',1,'EMISNQVA13',NULL,'Variant Creutzfeldt-Jakob disease'),('dementia',1,'^ESCT1407239',NULL,'Picks disease'),('dementia',1,'^ESCT1407240',NULL,'Picks disease'),('dementia',1,'^ESCTAL363017',NULL,'Alcoholic amnestic syndrome'),('dementia',1,'^ESCTAL368893',NULL,'Alcohol-induced persisting amnestic disorder'),('dementia',1,'^ESCTAM363010',NULL,'Amnestic syndrome of Wernickes disease'),('dementia',1,'^ESCTAM363016',NULL,'Amnesic syndrome due to alcohol'),('dementia',1,'^ESCTAR500573',NULL,'Argyrophilic grain disease'),('dementia',1,'^ESCTBO361688',NULL,'Bovine spongiform encephalopathy agent'),('dementia',1,'^ESCTCE476900',NULL,'Cerebral degeneration due to progressive multifocal leukoencephalopathy'),('dementia',1,'^ESCTCH396467',NULL,'Chronic progressive subcortical encephalopathy'),('dementia',1,'^ESCTCI270765',NULL,'Circumscribed cerebral atrophy'),('dementia',1,'^ESCTCL380268',NULL,'CLBD - Cortical Lewy body disease'),('dementia',1,'^ESCTCO380267',NULL,'Cortical Lewy body disease'),('dementia',1,'^ESCTDL380266',NULL,'DLBD - Diffuse Lewy body disease'),('dementia',1,'^ESCTEN396462',NULL,'Encephalitis subcorticalis chronica'),('dementia',1,'^ESCTFR500567',NULL,'Frontal lobe degeneration with motor neurone disease'),('dementia',1,'^ESCTFR561823',NULL,'Frontal lobe degeneration'),('dementia',1,'^ESCTGE359182',NULL,'Gerstmann-Straussler-Scheinker syndrome'),('dementia',1,'^ESCTGS359183',NULL,'GSS - Gerstmann-Straussler-Scheinker syndrome'),('dementia',1,'^ESCTKO277383',NULL,'Korsakovs syndrome - non-alcoholic'),('dementia',1,'^ESCTKO363012',NULL,'Korsakoff psychosis'),('dementia',1,'^ESCTKO363014',NULL,'Korsakov syndrome - alcoholic'),('dementia',1,'^ESCTKO363015',NULL,'Korsakov psychosis'),('dementia',1,'^ESCTKO476314',NULL,'Korsakov alcoholic psychosis with peripheral neuritis'),('dementia',1,'^ESCTLB380264',NULL,'LBD - Lewy body disease'),('dementia',1,'^ESCTLO500566',NULL,'Lobar atrophy'),('dementia',1,'^ESCTNO277380',NULL,'Non-alcoholic Korsakoffs psychosis'),('dementia',1,'^ESCTNO277384',NULL,'Non-alcoholic Korsakoff psychosis'),('dementia',1,'^ESCTPI270766',NULL,'Pick disease'),('dementia',1,'^ESCTPI270767',NULL,'Picks disease'),('dementia',1,'^ESCTPI500561',NULL,'Picks disease with Pick bodies'),('dementia',1,'^ESCTPI500562',NULL,'Pick disease with Pick bodies'),('dementia',1,'^ESCTPI500563',NULL,'Picks disease with Pick cells and no Pick bodies'),('dementia',1,'^ESCTPI500564',NULL,'Pick disease with Pick cells and no Pick bodies'),('dementia',1,'^ESCTPO500576',NULL,'Post-traumatic brain syndrome'),('dementia',1,'^ESCTPR282554',NULL,'Prion disease'),('dementia',1,'^ESCTPU500578',NULL,'Punch drunk syndrome'),('dementia',1,'^ESCTPU500579',NULL,'Punchdrunk encephalopathy'),('dementia',1,'^ESCTPU500581',NULL,'Punch drunk'),('dementia',1,'^ESCTSE476308',NULL,'Senile delirium'),('dementia',1,'^ESCTSP500583',NULL,'Spongiform encephalopathy'),('dementia',1,'^ESCTSU251097',NULL,'Subacute spongiform encephalopathy'),('dementia',1,'^ESCTSU396459',NULL,'Subcortical leucoencephalopathy'),('dementia',1,'^ESCTSU396460',NULL,'Subcortical leukoencephalopathy'),('dementia',1,'^ESCTSU396465',NULL,'Subcortical arteriosclerotic encephalopathy'),('dementia',1,'^ESCTTR500574',NULL,'Traumatic encephalopathy'),('dementia',1,'^ESCTWE363009',NULL,'Wernicke-Korsakoff syndrome');
INSERT INTO #codesemis
VALUES ('alcohol-heavy-drinker',1,'^ESCTAA274036',NULL,'AA - Alcohol abuse'),('alcohol-heavy-drinker',1,'^ESCTAL261465',NULL,'Alcoholism'),('alcohol-heavy-drinker',1,'^ESCTBO497845',NULL,'Bout drinker'),('alcohol-heavy-drinker',1,'^ESCTDR391332',NULL,'Drinks heavily'),('alcohol-heavy-drinker',1,'^ESCTEP497846',NULL,'Episodic drinker'),('alcohol-heavy-drinker',1,'^ESCTET274035',NULL,'Ethanol abuse'),('alcohol-heavy-drinker',1,'^ESCTEX453343',NULL,'Excessive ethanol consumption'),('alcohol-heavy-drinker',1,'^ESCTEX453345',NULL,'Excessive alcohol consumption'),('alcohol-heavy-drinker',1,'^ESCTEX453346',NULL,'Excessive alcohol use'),('alcohol-heavy-drinker',1,'^ESCTXS453342',NULL,'XS - Excessive ethanol consumption'),('alcohol-heavy-drinker',1,'^ESCTXS453344',NULL,'XS - Excessive alcohol consumption');
INSERT INTO #codesemis
VALUES ('alcohol-light-drinker',1,'^ESCTDR497797',NULL,'Drinks on special occasions');
INSERT INTO #codesemis
VALUES ('alcohol-moderate-drinker',1,'^ESCTDR453336',NULL,'Drinker of hard liquor'),('alcohol-moderate-drinker',1,'^ESCTDR453339',NULL,'Drinks beer and hard liquor');
INSERT INTO #codesemis
VALUES ('alcohol-non-drinker',1,'^ESCTAB412032',NULL,'Abstinent'),('alcohol-non-drinker',1,'^ESCTCU412038',NULL,'Current non-drinker of alcohol'),('alcohol-non-drinker',1,'^ESCTDO412035',NULL,'Does not drink alcohol'),('alcohol-non-drinker',1,'^ESCTNE412034',NULL,'Never drinks'),('alcohol-non-drinker',1,'^ESCTNO412037',NULL,'Non - drinker alcohol');
INSERT INTO #codesemis
VALUES ('alcohol-weekly-intake',1,'^ESCT1192867',NULL,'Alcohol units per week'),('alcohol-weekly-intake',1,'^ESCTAI453315',NULL,'AI - Alcohol intake'),('alcohol-weekly-intake',1,'^ESCTAL453314',NULL,'Alcohol intake'),('alcohol-weekly-intake',1,'^ESCTAL453319',NULL,'Alcoholic drink intake'),('alcohol-weekly-intake',1,'^ESCTAL498716',NULL,'alcohol units/week'),('alcohol-weekly-intake',1,'^ESCTET453316',NULL,'Ethanol intake'),('alcohol-weekly-intake',1,'^ESCTET453317',NULL,'ETOH - Alcohol intake'),('alcohol-weekly-intake',1,'EGTON418',NULL,'Alcohol intake');
INSERT INTO #codesemis
VALUES ('bmi',2,'^ESCT1192336',NULL,'Finding of body mass index'),('bmi',2,'^ESCTBA828699',NULL,'Baseline BMI (body mass index)'),('bmi',2,'^ESCTBM348480',NULL,'BMI - Body mass index'),('bmi',2,'^ESCTBO348478',NULL,'Body mass index'),('bmi',2,'^ESCTFI589221',NULL,'Finding of BMI (body mass index)'),('bmi',2,'^ESCTOB589220',NULL,'Observation of body mass index'),('bmi',2,'^ESCTQU348481',NULL,'Quetelet index')

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

-- >>> Following code sets injected: dementia v1

-- table of dementia coding events

IF OBJECT_ID('tempdb..#DementiaCodes') IS NOT NULL DROP TABLE #DementiaCodes;
SELECT FK_Patient_Link_ID AS PatientId, EventDate, COUNT(*) AS NumberOfDementiaCodes
INTO #DementiaCodes
FROM SharedCare.GP_Events
WHERE (
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE Concept = 'dementia' AND Version = 1) OR
  FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE Concept = 'dementia' AND Version = 1)
)
AND EventDate >= '2006-01-01' -- when dementia was added to QOF
GROUP BY FK_Patient_Link_ID, EventDate

-- create cohort of patients with a dementia diagnosis in the study period

IF OBJECT_ID('tempdb..#Cohort') IS NOT NULL DROP TABLE #Cohort;
SELECT
	 p.FK_Patient_Link_ID
	,yob.YearOfBirth
	,p.EthnicGroupDescription 
	,p.DeathDate
INTO #Cohort
FROM #Patients p
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = p.FK_Patient_Link_ID
WHERE p.FK_Patient_Link_ID IN 
	(SELECT DISTINCT PatientId
	 FROM #DementiaCodes
	 WHERE NumberOfDementiaCodes >= 1)
AND YEAR(@StartDate) - YearOfBirth > 18


---------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------


-- >>> Following code sets injected: bmi v2/alcohol-weekly-intake v1/alcohol-heavy-drinker v1
-- >>> Following code sets injected: alcohol-light-drinker v1/alcohol-moderate-drinker v1/alcohol-non-drinker v1
-- >>> Following code sets injected: smoking-status-current v1/smoking-status-currently-not v1/smoking-status-ex v1/smoking-status-ex-trivial v1/smoking-status-never v1/smoking-status-passive v1/smoking-status-trivial v1


--bring together for final output

IF OBJECT_ID('tempdb..#observations') IS NOT NULL DROP TABLE #observations;
SELECT 
	FK_Patient_Link_ID,
	CAST(EventDate AS DATE) AS EventDate,
	Concept = CASE WHEN sn.Concept IS NOT NULL THEN sn.Concept ELSE co.Concept END,
	[Value],
	[Units]
INTO #observations
FROM SharedCare.GP_Events gp 
LEFT JOIN #VersionedSnomedSets sn ON sn.FK_Reference_SnomedCT_ID = gp.FK_Reference_SnomedCT_ID
LEFT JOIN #VersionedCodeSets co ON co.FK_Reference_Coding_ID = gp.FK_Reference_Coding_ID
WHERE
	(
	gp.FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE	Concept NOT IN ('dementia')) OR
    gp.FK_Reference_Coding_ID   IN (SELECT FK_Reference_Coding_ID   FROM #VersionedCodeSets WHERE Concept NOT IN ('dementia')) 
	)
AND gp.FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Cohort)
AND EventDate BETWEEN @StartDate and @EndDate


-- BRING TOGETHER FOR FINAL OUTPUT AND REMOVE USELESS RECORDS

SELECT DISTINCT
	PatientId = o.FK_Patient_Link_ID
	,TestName = o.Concept
	,TestDate = o.EventDate
	,TestResult = TRY_CONVERT(NUMERIC (18,5), [Value]) -- convert to numeric so no text can appear.
	,TestUnit = o.[Units]
FROM #observations o
WHERE UPPER([Value]) NOT LIKE '%[A-Z]%'  -- REMOVES ANY TEXT VALUES
