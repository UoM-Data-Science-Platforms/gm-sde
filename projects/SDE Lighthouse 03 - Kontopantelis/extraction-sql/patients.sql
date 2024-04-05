--┌──────────────────────────────────────────┐
--│ SDELS03 - Kontopantelis - Demographics   │
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
('dementia',1,'F111.00',NULL,'Picks disease'),('dementia',1,'F116.',NULL,'Lewy body disease'),('dementia',1,'F116.00',NULL,'Lewy body disease'),('dementia',1,'F118.',NULL,'Frontotemporal degeneration'),('dementia',1,'F118.00',NULL,'Frontotemporal degeneration'),('dementia',1,'F11x7',NULL,'Cerebral degeneration due to Jakob - Creutzfeldt disease'),('dementia',1,'F11x700',NULL,'Cerebral degeneration due to Jakob - Creutzfeldt disease'),('dementia',1,'F11x8',NULL,'Cerebral degeneration due to progressive multifocal leucoencephalopathy'),('dementia',1,'F11x800',NULL,'Cerebral degeneration due to progressive multifocal leucoencephalopathy'),('dementia',1,'F21y2',NULL,'Binswangers disease'),('dementia',1,'F21y200',NULL,'Binswangers disease'),('dementia',1,'Fyu30',NULL,'[X]Other Alzheimers disease'),('dementia',1,'Fyu3000',NULL,'[X]Other Alzheimers disease')

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
VALUES ('dementia',1,'1461.',NULL,'H/O: dementia'),('dementia',1,'A410.',NULL,'Kuru'),('dementia',1,'A411.',NULL,'Creutzfeldt-Jakob disease'),('dementia',1,'E00..',NULL,'Senile and presenile organic psychot conditions (& dementia)'),('dementia',1,'E000.',NULL,'Uncomplicated senile dementia'),('dementia',1,'E001.',NULL,'Presenile dementia'),('dementia',1,'E0010',NULL,'Uncomplicated presenile dementia'),('dementia',1,'E0011',NULL,'Presenile dementia with delirium'),('dementia',1,'E0012',NULL,'Presenile dementia with paranoia'),('dementia',1,'E0013',NULL,'Presenile dementia with depression'),('dementia',1,'E001z',NULL,'Presenile dementia NOS'),('dementia',1,'E002.',NULL,'Senile dementia with depressive or paranoid features'),('dementia',1,'E0020',NULL,'Senile dementia with paranoia'),('dementia',1,'E0021',NULL,'Senile dementia with depression'),('dementia',1,'E002z',NULL,'Senile dementia with depressive or paranoid features NOS'),('dementia',1,'E003.',NULL,'Senile dementia with delirium'),('dementia',1,'E004.',NULL,'Arteriosclerotic dementia (including [multi infarct dement])'),('dementia',1,'E0040',NULL,'Uncomplicated arteriosclerotic dementia'),('dementia',1,'E0041',NULL,'Arteriosclerotic dementia with delirium'),('dementia',1,'E0042',NULL,'Arteriosclerotic dementia with paranoia'),('dementia',1,'E0043',NULL,'Arteriosclerotic dementia with depression'),('dementia',1,'E004z',NULL,'Arteriosclerotic dementia NOS'),('dementia',1,'E00y.',NULL,'(Oth senile/presen org psychoses) or (presbyophren psychos)'),('dementia',1,'E00z.',NULL,'Senile or presenile psychoses NOS'),('dementia',1,'E011.',NULL,'Korsakov psychosis'),('dementia',1,'E0110',NULL,'Korsakov psychosis'),('dementia',1,'E0111',NULL,'Korsakovs alcoholic psychosis with peripheral neuritis'),('dementia',1,'E0112',NULL,'Wernicke-Korsakov syndrome'),('dementia',1,'E011z',NULL,'Alcohol amnestic syndrome NOS'),('dementia',1,'E012.',NULL,'Alcoholic dementia: [other] or [NOS]'),('dementia',1,'E040.',NULL,'Korsakoffs syndrome - non-alcoholic'),('dementia',1,'E041.',NULL,'Dementia in conditions EC'),('dementia',1,'Eu00.',NULL,'[X]Dementia in Alzheimers disease'),('dementia',1,'Eu001',NULL,'Dementia in Alzheimers disease with late onset'),('dementia',1,'Eu002',NULL,'[X]Dementia in Alzheimers dis, atypical or mixed type'),('dementia',1,'Eu00z',NULL,'[X]Dementia in Alzheimers disease, unspecified'),('dementia',1,'Eu01.',NULL,'Vascular dementia'),('dementia',1,'Eu011',NULL,'[X]Dementia: [multi-infarct] or [predominantly cortical]'),('dementia',1,'Eu01y',NULL,'[X]Other vascular dementia'),('dementia',1,'Eu01z',NULL,'[X]Vascular dementia, unspecified'),('dementia',1,'Eu02.',NULL,'[X]Dementia in other diseases classified elsewhere'),('dementia',1,'Eu020',NULL,'[X]Dementia in Picks disease'),('dementia',1,'Eu021',NULL,'[X]Dementia in Creutzfeldt-Jakob disease'),('dementia',1,'Eu022',NULL,'[X]Dementia in Huntingtons disease'),('dementia',1,'Eu023',NULL,'[X]Dementia in Parkinsons disease'),('dementia',1,'Eu02y',NULL,'[X]Dementia in other specified diseases classif elsewhere'),('dementia',1,'Eu02z',NULL,'[X] Dementia: [unspecified] or [named variants (& NOS)]'),('dementia',1,'Eu041',NULL,'[X]Delirium superimposed on dementia'),('dementia',1,'F110.',NULL,'Alzheimers disease'),('dementia',1,'F1100',NULL,'Dementia in Alzheimers disease with early onset'),('dementia',1,'F1101',NULL,'Dementia in Alzheimers disease with late onset'),('dementia',1,'F111.',NULL,'Picks disease'),('dementia',1,'F11x7',NULL,'Cerebral degeneration due to Creutzfeldt-Jakob disease'),('dementia',1,'F11x8',NULL,'Cerebral degeneration due to multifocal leucoencephalopathy'),('dementia',1,'F21y2',NULL,'Binswangers disease'),('dementia',1,'Fyu30',NULL,'[X]Other Alzheimers disease'),('dementia',1,'Ub1T6',NULL,'Language disorder of dementia'),('dementia',1,'X002m',NULL,'Amyotrophic lateral sclerosis with dementia'),('dementia',1,'X002w',NULL,'Dementia'),('dementia',1,'X002x',NULL,'Dementia in Alzheimers disease with early onset'),('dementia',1,'X002y',NULL,'Familial Alzheimers disease of early onset'),('dementia',1,'X002z',NULL,'Non-familial Alzheimers disease of early onset'),('dementia',1,'X0030',NULL,'Dementia in Alzheimers disease with late onset'),('dementia',1,'X0031',NULL,'Familial Alzheimers disease of late onset'),('dementia',1,'X0032',NULL,'Non-familial Alzheimers disease of late onset'),('dementia',1,'X0033',NULL,'Focal Alzheimers disease'),('dementia',1,'X0034',NULL,'Frontotemporal dementia'),('dementia',1,'X0035',NULL,'Picks disease with Pick bodies'),('dementia',1,'X0036',NULL,'Picks disease with Pick cells and no Pick bodies'),('dementia',1,'X0037',NULL,'Frontotemporal degeneration'),('dementia',1,'X0039',NULL,'Frontal lobe degeneration with motor neurone disease'),('dementia',1,'X003A',NULL,'Lewy body disease'),('dementia',1,'X003G',NULL,'Progressive aphasia in Alzheimers disease'),('dementia',1,'X003H',NULL,'Argyrophilic brain disease'),('dementia',1,'X003I',NULL,'Post-traumatic dementia'),('dementia',1,'X003J',NULL,'Punch drunk syndrome'),('dementia',1,'X003K',NULL,'Spongiform encephalopathy'),('dementia',1,'X003L',NULL,'Prion protein disease'),('dementia',1,'X003M',NULL,'Gerstmann-Straussler-Scheinker syndrome'),('dementia',1,'X003P',NULL,'Acquired immune deficiency syndrome dementia complex'),('dementia',1,'X003R',NULL,'Vascular dementia of acute onset'),('dementia',1,'X003T',NULL,'Subcortical vascular dementia'),('dementia',1,'X003V',NULL,'Mixed cortical and subcortical vascular dementia'),('dementia',1,'X003W',NULL,'Semantic dementia'),('dementia',1,'X003X',NULL,'Patchy dementia'),('dementia',1,'X003Y',NULL,'Epileptic dementia'),('dementia',1,'X003l',NULL,'Parkinsons disease - dementia complex on Guam'),('dementia',1,'X00R0',NULL,'Presbyophrenic psychosis'),('dementia',1,'X00R2',NULL,'Senile dementia'),('dementia',1,'X00Rk',NULL,'Alcoholic dementia NOS'),('dementia',1,'X73mf',NULL,'Creutzfeldt-Jakob disease agent'),('dementia',1,'X73mj',NULL,'Bovine spongiform encephalopathy agent'),('dementia',1,'XE1Xr',NULL,'Senile and presenile organic psychotic conditions'),('dementia',1,'XE1Xs',NULL,'Vascular dementia'),('dementia',1,'XE1Xt',NULL,'Other senile and presenile organic psychoses'),('dementia',1,'XE1Xu',NULL,'Other alcoholic dementia'),('dementia',1,'XE1Z6',NULL,'[X]Unspecified dementia'),('dementia',1,'XE1aG',NULL,'Dementia (& [presenile] or [senile])'),('dementia',1,'Xa0lH',NULL,'Multi-infarct dementia'),('dementia',1,'Xa0sC',NULL,'Frontal lobe degeneration'),('dementia',1,'Xa0sE',NULL,'Dementia of frontal lobe type'),('dementia',1,'Xa1GB',NULL,'Cerebral degeneration presenting primarily with dementia'),('dementia',1,'Xa25J',NULL,'Alcoholic dementia'),('dementia',1,'Xa3ez',NULL,'Other senile/presenile dementia'),('dementia',1,'XaA1S',NULL,'New variant of Creutzfeldt-Jakob disease'),('dementia',1,'XaE74',NULL,'Senile dementia of the Lewy body type'),('dementia',1,'XaIKB',NULL,'Alzheimers disease with early onset'),('dementia',1,'XaIKC',NULL,'Alzheimers disease with late onset'),('dementia',1,'XaKyY',NULL,'[X]Lewy body dementia'),('dementia',1,'XaLFf',NULL,'Exception reporting: dementia quality indicators'),('dementia',1,'XaLFo',NULL,'Excepted from dementia quality indicators: Patient unsuitabl'),('dementia',1,'XaLFp',NULL,'Excepted from dementia quality indicators: Informed dissent'),('dementia',1,'XaMAo',NULL,'Prion protein markers for Creutzfeldt-Jakob disease'),('dementia',1,'XaMFy',NULL,'Dementia monitoring administration'),('dementia',1,'XaMG0',NULL,'Dementia monitoring first letter'),('dementia',1,'XaMGF',NULL,'Dementia annual review'),('dementia',1,'XaMGG',NULL,'Dementia monitoring second letter'),('dementia',1,'XaMGI',NULL,'Dementia monitoring third letter'),('dementia',1,'XaMGJ',NULL,'Dementia monitoring verbal invite'),('dementia',1,'XaMGK',NULL,'Dementia monitoring telephone invite'),('dementia',1,'XaMJC',NULL,'Dementia monitoring'),('dementia',1,'XaZWz',NULL,'Participates in Butterfly Scheme for dementia'),('dementia',1,'XaZX0',NULL,'Butterfly Scheme for dementia declined'),('dementia',1,'XabVp',NULL,'Sporadic Creutzfeldt-Jakob disease'),('dementia',1,'XabtQ',NULL,'Dementia medication review'),('dementia',1,'Xaghb',NULL,'Predominantly cortical dementia'),('dementia',1,'Y000c',NULL,'Dementia review done'),('dementia',1,'Y1f1d',NULL,'Dementia monitoring invitation'),('dementia',1,'Y1f22',NULL,'Dementia monitoring invitation'),('dementia',1,'Y1f98',NULL,'Quality and Outcomes Framework dementia quality indicator-related care invitation (procedure)'),('dementia',1,'Y23fb',NULL,'Mixed dementia'),('dementia',1,'Y6230',NULL,'Creutzfeldt - Jakob disease'),('dementia',1,'Y8180',NULL,'Other senile/presenile dement.'),('dementia',1,'Y9086',NULL,'Senile dementia - simple type'),('dementia',1,'Y9087',NULL,'Senile dementia-acute confused'),('dementia',1,'Eu106',NULL,'[X]Korsakovs psychosis, alcohol-induced'),('dementia',1,'Eu107',NULL,'[X]Alcoholic dementia NOS'),('dementia',1,'XE17j',NULL,'Alzheimers disease'),('dementia',1,'XE1aI',NULL,'Korsakov psychosis')

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

INSERT INTO #codesemis
VALUES ('dementia',1,'^ESCTAC697343',NULL,'Acquired immune deficiency syndrome-related dementia'),('dementia',1,'^ESCTAC697346',NULL,'Acquired immune deficiency syndrome dementia complex'),('dementia',1,'^ESCTAD697345',NULL,'ADC - Acquired immune deficiency syndrome dementia complex'),('dementia',1,'^ESCTAI697344',NULL,'AIDS - Acquired immune deficiency syndrome dementia complex'),('dementia',1,'^ESCTDE697342',NULL,'Dementia associated with AIDS'),('dementia',1,'^ESCTDE697347',NULL,'Dementia associated with acquired immunodeficiency syndrome'),('dementia',1,'EMISICD10|F0000',NULL,'Dementia in Alzheimers disease with early onset, without additional symptoms'),('dementia',1,'EMISICD10|F0001',NULL,'Dementia in Alzheimers disease with early onset, other symptoms, predominantly delusional'),('dementia',1,'EMISICD10|F0002',NULL,'Dementia in Alzheimers disease with early onset, other symptoms, predominantly hallucinatory'),('dementia',1,'EMISICD10|F0003',NULL,'Dementia in Alzheimers disease with early onset, other symptoms, predominantly depressive'),('dementia',1,'EMISICD10|F0004',NULL,'Dementia in Alzheimers disease with early onset, other mixed symptoms'),('dementia',1,'EMISICD10|F0010',NULL,'Dementia in Alzheimers disease with late onset, without additional symptoms'),('dementia',1,'EMISICD10|F0011',NULL,'Dementia in Alzheimers disease with late onset, other symptoms, predominantly delusional'),('dementia',1,'EMISICD10|F0012',NULL,'Dementia in Alzheimers disease with late onset, other symptoms, predominantly hallucinatory'),('dementia',1,'EMISICD10|F0013',NULL,'Dementia in Alzheimers disease with late onset, other symptoms, predominantly depressive'),('dementia',1,'EMISICD10|F0014',NULL,'Dementia in Alzheimers disease with late onset, other mixed symptoms'),('dementia',1,'EMISICD10|F0020',NULL,'Dementia in Alzheimers dis, atypical or mixed type, without additional symptoms'),('dementia',1,'EMISICD10|F0021',NULL,'Dementia in Alzheimers dis, atypical or mixed type, other symptoms, predominantly delusional'),('dementia',1,'EMISICD10|F0022',NULL,'Dementia in Alzheimers dis, atypical or mixed type, other symptoms, predominantly hallucinatory'),('dementia',1,'EMISICD10|F0023',NULL,'Dementia in Alzheimers dis, atypical or mixed type, other symptoms, predominantly depressive'),('dementia',1,'EMISICD10|F0024',NULL,'Dementia in Alzheimers dis, atypical or mixed type, other mixed symptoms'),('dementia',1,'EMISICD10|F0090',NULL,'Dementia in Alzheimers disease, unspecified, without additional symptoms'),('dementia',1,'EMISICD10|F0091',NULL,'Dementia in Alzheimers disease, unspecified, other symptoms, predominantly delusional'),('dementia',1,'EMISICD10|F0092',NULL,'Dementia in Alzheimers disease, unspecified, other symptoms, predominantly hallucinatory'),('dementia',1,'EMISICD10|F0093',NULL,'Dementia in Alzheimers disease, unspecified, other symptoms, predominantly depressive'),('dementia',1,'EMISICD10|F0094',NULL,'Dementia in Alzheimers disease, unspecified, other mixed symptoms'),('dementia',1,'EMISICD10|F0100',NULL,'Vascular dementia of acute onset, without additional symptoms'),('dementia',1,'EMISICD10|F0101',NULL,'Vascular dementia of acute onset, other symptoms, predominantly delusional'),('dementia',1,'EMISICD10|F0102',NULL,'Vascular dementia of acute onset, other symptoms, predominantly hallucinatory'),('dementia',1,'EMISICD10|F0103',NULL,'Vascular dementia of acute onset, other symptoms, predominantly depressive'),('dementia',1,'EMISICD10|F0104',NULL,'Vascular dementia of acute onset, other mixed symptoms'),('dementia',1,'EMISICD10|F0110',NULL,'Multi-infarct dementia, without additional symptoms'),('dementia',1,'EMISICD10|F0111',NULL,'Multi-infarct dementia, other symptoms, predominantly delusional'),('dementia',1,'EMISICD10|F0112',NULL,'Multi-infarct dementia, other symptoms, predominantly hallucinatory'),('dementia',1,'EMISICD10|F0113',NULL,'Multi-infarct dementia, other symptoms, predominantly depressive'),('dementia',1,'EMISICD10|F0114',NULL,'Multi-infarct dementia, other mixed symptoms'),('dementia',1,'EMISICD10|F0120',NULL,'Subcortical vascular dementia, without additional symptoms'),('dementia',1,'EMISICD10|F0121',NULL,'Subcortical vascular dementia, other symptoms, predominantly delusional'),('dementia',1,'EMISICD10|F0122',NULL,'Subcortical vascular dementia, other symptoms, predominantly hallucinatory'),('dementia',1,'EMISICD10|F0123',NULL,'Subcortical vascular dementia, other symptoms, predominantly depressive'),('dementia',1,'EMISICD10|F0124',NULL,'Subcortical vascular dementia, other mixed symptoms'),('dementia',1,'EMISICD10|F0130',NULL,'Mixed cortical and subcortical vascular dementia, without additional symptoms'),('dementia',1,'EMISICD10|F0131',NULL,'Mixed cortical and subcortical vascular dementia, other symptoms, predominantly delusional'),('dementia',1,'EMISICD10|F0132',NULL,'Mixed cortical and subcortical vascular dementia, other symptoms, predominantly hallucinatory'),('dementia',1,'EMISICD10|F0133',NULL,'Mixed cortical and subcortical vascular dementia, other symptoms, predominantly depressive'),('dementia',1,'EMISICD10|F0134',NULL,'Mixed cortical and subcortical vascular dementia, other mixed symptoms'),('dementia',1,'EMISICD10|F0180',NULL,'Other vascular dementia, without additional symptoms'),('dementia',1,'EMISICD10|F0181',NULL,'Other vascular dementia, other symptoms, predominantly delusional'),('dementia',1,'EMISICD10|F0182',NULL,'Other vascular dementia, other symptoms, predominantly hallucinatory'),('dementia',1,'EMISICD10|F0183',NULL,'Other vascular dementia, other symptoms, predominantly depressive'),('dementia',1,'EMISICD10|F0184',NULL,'Other vascular dementia, other mixed symptoms'),('dementia',1,'EMISICD10|F0190',NULL,'Vascular dementia, unspecified, without additional symptoms'),('dementia',1,'EMISICD10|F0191',NULL,'Vascular dementia, unspecified, other symptoms, predominantly delusional'),('dementia',1,'EMISICD10|F0192',NULL,'Vascular dementia, unspecified, other symptoms, predominantly hallucinatory'),('dementia',1,'EMISICD10|F0193',NULL,'Vascular dementia, unspecified, other symptoms, predominantly depressive'),('dementia',1,'EMISICD10|F0194',NULL,'Vascular dementia, unspecified, other mixed symptoms'),('dementia',1,'EMISICD10|F03X0',NULL,'Unspecified dementia, without additional symptoms'),('dementia',1,'EMISICD10|F03X1',NULL,'Unspecified dementia, other symptoms, predominantly delusional'),('dementia',1,'EMISICD10|F03X2',NULL,'Unspecified dementia, other symptoms, predominantly hallucinatory'),('dementia',1,'EMISICD10|F03X3',NULL,'Unspecified dementia, other symptoms, predominantly depressive'),('dementia',1,'EMISICD10|F03X4',NULL,'Unspecified dementia, other mixed symptoms'),('dementia',1,'^ESCT1171773',NULL,'Predominantly cortical dementia'),('dementia',1,'^ESCT1381019',NULL,'SDLT - senile dementia of Lewy body type'),('dementia',1,'^ESCT1407776',NULL,'Senile Lewy body dementia'),('dementia',1,'^ESCTAL250298',NULL,'Alcohol-induced persisting dementia'),('dementia',1,'^ESCTAL293125',NULL,'Alzheimer dementia'),('dementia',1,'^ESCTAM500542',NULL,'Amyotrophic lateral sclerosis with dementia'),('dementia',1,'^ESCTBI396461',NULL,'Binswangers dementia'),('dementia',1,'^ESCTBO500582',NULL,'Boxers dementia'),('dementia',1,'^ESCTBU828470',NULL,'Butterfly Scheme for dementia declined'),('dementia',1,'^ESCTDE250297',NULL,'Dementia associated with alcoholism'),('dementia',1,'^ESCTDE380265',NULL,'Dementia of the Lewy body type'),('dementia',1,'^ESCTDE500577',NULL,'Dementia due to head trauma'),('dementia',1,'^ESCTDE500580',NULL,'Dementia pugilistica'),('dementia',1,'^ESCTDE561826',NULL,'Dementia of frontal lobe type'),('dementia',1,'^ESCTDE689724',NULL,'Dementia of the Alzheimers type with early onset'),('dementia',1,'^ESCTDE689727',NULL,'Dementia in Alzheimers disease - type 2'),('dementia',1,'^ESCTDE690020',NULL,'Dementia of the Alzheimers type, late onset'),('dementia',1,'^ESCTDE690024',NULL,'Dementia in Alzheimers disease - type 1'),('dementia',1,'^ESCTDE704365',NULL,'Dementia associated with Parkinsons Disease'),('dementia',1,'^ESCTDE704366',NULL,'Dementia associated with Parkinson Disease'),('dementia',1,'^ESCTDE710360',NULL,'Dementia due to Creutzfeldt-Jakob disease'),('dementia',1,'^ESCTDE726301',NULL,'Dementia due to Huntington disease'),('dementia',1,'^ESCTDE726302',NULL,'Dementia due to Huntingtons disease'),('dementia',1,'^ESCTDE800952',NULL,'Dementia due to Picks disease'),('dementia',1,'^ESCTDE800953',NULL,'Dementia due to Pick disease'),('dementia',1,'^ESCTDE800954',NULL,'Dementia co-occurrent and due to Picks disease'),('dementia',1,'^ESCTDF561827',NULL,'DFT - Dementia frontal lobe type'),('dementia',1,'^ESCTEP786368',NULL,'Epilepsy co-occurrent and due to dementia'),('dementia',1,'^ESCTEP786369',NULL,'Epileptic dementia'),('dementia',1,'^ESCTEP786370',NULL,'Epilepsy with dementia'),('dementia',1,'^ESCTFR500560',NULL,'Frontotemporal dementia'),('dementia',1,'^ESCTHI453987',NULL,'History of dementia'),('dementia',1,'^ESCTLA499781',NULL,'Language disorder of dementia'),('dementia',1,'^ESCTLE602407',NULL,'Lewy body dementia'),('dementia',1,'^ESCTMI341423',NULL,'MID - Multi-infarct dementia'),('dementia',1,'^ESCTMU341426',NULL,'Multi infarct dementia'),('dementia',1,'^ESCTOR335044',NULL,'Organic dementia'),('dementia',1,'^ESCTPA351118',NULL,'Parkinson-dementia complex of Guam'),('dementia',1,'^ESCTPA351119',NULL,'Parkinsons disease - dementia complex on Guam'),('dementia',1,'^ESCTPA500588',NULL,'Patchy dementia'),('dementia',1,'^ESCTPA828469',NULL,'Participates in Butterfly Scheme for dementia'),('dementia',1,'^ESCTPO500575',NULL,'Post-traumatic dementia'),('dementia',1,'^ESCTPR689721',NULL,'Primary degenerative dementia of the Alzheimer type, presenile onset'),('dementia',1,'^ESCTPR689722',NULL,'Primary degenerative dementia of the Alzheimer type, early onset'),('dementia',1,'^ESCTPR689725',NULL,'Presenile dementia, Alzheimers type'),
('dementia',1,'^ESCTPR690018',NULL,'Primary degenerative dementia of the Alzheimer type, senile onset'),('dementia',1,'^ESCTPR690019',NULL,'Primary degenerative dementia of the Alzheimer type, late onset'),('dementia',1,'^ESCTPR801011',NULL,'Primary degenerative dementia'),('dementia',1,'^ESCTSD274844',NULL,'SD - Senile dementia'),('dementia',1,'^ESCTSD380263',NULL,'SDLT - Senile dementia of the Lewy body type'),('dementia',1,'^ESCTSD690022',NULL,'SDAT - Senile dementia, Alzheimers type'),('dementia',1,'^ESCTSE500587',NULL,'Semantic dementia'),('dementia',1,'^ESCTSE602406',NULL,'Senile dementia of the Lewy body type'),('dementia',1,'^ESCTSE634806',NULL,'Senile dementia with psychosis'),('dementia',1,'^ESCTSU396466',NULL,'Subcortical atherosclerotic dementia'),('dementia',1,'^ESCTTR251100',NULL,'Transmissible virus dementia'),('dementia',1,'^ESCTVA341425',NULL,'VAD - Vascular dementia'),('dementia',1,'EMISNQDE41',NULL,'Dementia monitoring in primary care'),('dementia',1,'EMISNQDE42',NULL,'Dementia monitoring in secondary care'),('dementia',1,'^ESCTAD293123',NULL,'AD - Alzheimers disease'),('dementia',1,'^ESCTAL293124',NULL,'Alzheimer disease'),('dementia',1,'^ESCTFA500550',NULL,'Familial Alzheimers disease of early onset'),('dementia',1,'^ESCTFA500551',NULL,'Familial Alzheimer disease of early onset'),('dementia',1,'^ESCTFA500554',NULL,'Familial Alzheimers disease of late onset'),('dementia',1,'^ESCTFA500555',NULL,'Familial Alzheimer disease of late onset'),('dementia',1,'^ESCTFO500558',NULL,'Focal Alzheimers disease'),('dementia',1,'^ESCTFO500559',NULL,'Focal Alzheimer disease'),('dementia',1,'^ESCTLE380262',NULL,'Lewy body variant of Alzheimers disease'),('dementia',1,'^ESCTNO500552',NULL,'Non-familial Alzheimers disease of early onset'),('dementia',1,'^ESCTNO500553',NULL,'Non-familial Alzheimer disease of early onset'),('dementia',1,'^ESCTNO500556',NULL,'Non-familial Alzheimers disease of late onset'),('dementia',1,'^ESCTNO500557',NULL,'Non-familial Alzheimer disease of late onset'),('dementia',1,'^ESCTPR500571',NULL,'Progressive aphasia in Alzheimers disease'),('dementia',1,'^ESCTPR500572',NULL,'Progressive aphasia in Alzheimer disease'),('dementia',1,'^ESCTCE476898',NULL,'Cerebral degeneration due to Creutzfeldt-Jakob disease'),('dementia',1,'^ESCTCJ251098',NULL,'CJD - Creutzfeldt-Jakob disease'),('dementia',1,'^ESCTCR251095',NULL,'Creutzfeldt-Jakob disease'),('dementia',1,'^ESCTCR251101',NULL,'Creutzfeldt Jakob disease'),('dementia',1,'^ESCTCR393867',NULL,'Creutzfeldt-Jakob agent'),('dementia',1,'^ESCTCR393869',NULL,'Creutzfeldt-Jakob disease agent'),('dementia',1,'^ESCTCR593165',NULL,'Creutzfeldt-Jakob variant disease'),('dementia',1,'^ESCTJA393868',NULL,'Jakob-Creutzfeldt agent'),('dementia',1,'^ESCTJC251099',NULL,'JCD - Jakob-Creutzfeldt disease'),('dementia',1,'^ESCTNV593163',NULL,'nvCJD - New variant of Creutzfeldt-Jakob disease'),('dementia',1,'^ESCTPR839987',NULL,'Prion protein markers for CJD (Creutzfeldt-Jakob disease)'),('dementia',1,'^ESCTSP769925',NULL,'Sporadic Jakob-Creutzfeldt disease'),('dementia',1,'^ESCTVC593164',NULL,'vCJD - variant Creutzfeldt-Jakob disease'),('dementia',1,'EMISNQSP44',NULL,'Sporadic Creutzfeldt-Jakob disease'),('dementia',1,'EMISNQVA13',NULL,'Variant Creutzfeldt-Jakob disease'),('dementia',1,'^ESCT1407239',NULL,'Picks disease'),('dementia',1,'^ESCT1407240',NULL,'Picks disease'),('dementia',1,'^ESCTAL363017',NULL,'Alcoholic amnestic syndrome'),('dementia',1,'^ESCTAL368893',NULL,'Alcohol-induced persisting amnestic disorder'),('dementia',1,'^ESCTAM363010',NULL,'Amnestic syndrome of Wernickes disease'),('dementia',1,'^ESCTAM363016',NULL,'Amnesic syndrome due to alcohol'),('dementia',1,'^ESCTAR500573',NULL,'Argyrophilic grain disease'),('dementia',1,'^ESCTBO361688',NULL,'Bovine spongiform encephalopathy agent'),('dementia',1,'^ESCTCE476900',NULL,'Cerebral degeneration due to progressive multifocal leukoencephalopathy'),('dementia',1,'^ESCTCH396467',NULL,'Chronic progressive subcortical encephalopathy'),('dementia',1,'^ESCTCI270765',NULL,'Circumscribed cerebral atrophy'),('dementia',1,'^ESCTCL380268',NULL,'CLBD - Cortical Lewy body disease'),('dementia',1,'^ESCTCO380267',NULL,'Cortical Lewy body disease'),('dementia',1,'^ESCTDL380266',NULL,'DLBD - Diffuse Lewy body disease'),('dementia',1,'^ESCTEN396462',NULL,'Encephalitis subcorticalis chronica'),('dementia',1,'^ESCTFR500567',NULL,'Frontal lobe degeneration with motor neurone disease'),('dementia',1,'^ESCTFR561823',NULL,'Frontal lobe degeneration'),('dementia',1,'^ESCTGE359182',NULL,'Gerstmann-Straussler-Scheinker syndrome'),('dementia',1,'^ESCTGS359183',NULL,'GSS - Gerstmann-Straussler-Scheinker syndrome'),('dementia',1,'^ESCTKO277383',NULL,'Korsakovs syndrome - non-alcoholic'),('dementia',1,'^ESCTKO363012',NULL,'Korsakoff psychosis'),('dementia',1,'^ESCTKO363014',NULL,'Korsakov syndrome - alcoholic'),('dementia',1,'^ESCTKO363015',NULL,'Korsakov psychosis'),('dementia',1,'^ESCTKO476314',NULL,'Korsakov alcoholic psychosis with peripheral neuritis'),('dementia',1,'^ESCTLB380264',NULL,'LBD - Lewy body disease'),('dementia',1,'^ESCTLO500566',NULL,'Lobar atrophy'),('dementia',1,'^ESCTNO277380',NULL,'Non-alcoholic Korsakoffs psychosis'),('dementia',1,'^ESCTNO277384',NULL,'Non-alcoholic Korsakoff psychosis'),('dementia',1,'^ESCTPI270766',NULL,'Pick disease'),('dementia',1,'^ESCTPI270767',NULL,'Picks disease'),('dementia',1,'^ESCTPI500561',NULL,'Picks disease with Pick bodies'),('dementia',1,'^ESCTPI500562',NULL,'Pick disease with Pick bodies'),('dementia',1,'^ESCTPI500563',NULL,'Picks disease with Pick cells and no Pick bodies'),('dementia',1,'^ESCTPI500564',NULL,'Pick disease with Pick cells and no Pick bodies'),('dementia',1,'^ESCTPO500576',NULL,'Post-traumatic brain syndrome'),('dementia',1,'^ESCTPR282554',NULL,'Prion disease'),('dementia',1,'^ESCTPU500578',NULL,'Punch drunk syndrome'),('dementia',1,'^ESCTPU500579',NULL,'Punchdrunk encephalopathy'),('dementia',1,'^ESCTPU500581',NULL,'Punch drunk'),('dementia',1,'^ESCTSE476308',NULL,'Senile delirium'),('dementia',1,'^ESCTSP500583',NULL,'Spongiform encephalopathy'),('dementia',1,'^ESCTSU251097',NULL,'Subacute spongiform encephalopathy'),('dementia',1,'^ESCTSU396459',NULL,'Subcortical leucoencephalopathy'),('dementia',1,'^ESCTSU396460',NULL,'Subcortical leukoencephalopathy'),('dementia',1,'^ESCTSU396465',NULL,'Subcortical arteriosclerotic encephalopathy'),('dementia',1,'^ESCTTR500574',NULL,'Traumatic encephalopathy'),('dementia',1,'^ESCTWE363009',NULL,'Wernicke-Korsakoff syndrome')

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
--	- LSOA_Code - nationally recognised LSOA identifier

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
FROM SharedCare.Patient p
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND LSOA_Code IS NOT NULL;


-- If patients have a tenancy id of 2 we take this as their most likely LSOA_Code
-- as this is the GP data feed and so most likely to be up to date
IF OBJECT_ID('tempdb..#PatientLSOA') IS NOT NULL DROP TABLE #PatientLSOA;
SELECT FK_Patient_Link_ID, MIN(LSOA_Code) as LSOA_Code INTO #PatientLSOA FROM #AllPatientLSOAs
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND FK_Reference_Tenancy_ID = 2
GROUP BY FK_Patient_Link_ID
HAVING MIN(LSOA_Code) = MAX(LSOA_Code);

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

-- Tidy up - helpful in ensuring the tempdb doesn't run out of space mid-query
DROP TABLE #AllPatientLSOAs;
DROP TABLE #UnmatchedLsoaPatients;
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
FROM SharedCare.Patient p
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

-- Date of first dementia diagnosis
SELECT PatientId, MIN(EventDate) as FirstDiagnosis
INTO #FirstDementiaDiagnosis
FROM #DementiaCodes 
GROUP BY PatientId

--bring together for final output
SELECT	 PatientId = m.FK_Patient_Link_ID
		,YearOfBirth
		,Sex
		,LSOA_Code
		,EthnicGroupDescription
		,IMD2019Decile1IsMostDeprived10IsLeastDeprived
		,YearAndMonthOfDeath = FORMAT(DeathDate, 'yyyy-MM')
		,FirstDementiaDiagnosisSince2006 = FORMAT(CONVERT(DATE,fdd.FirstDiagnosis), 'yyyy-MM')
FROM #Cohort m
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientLSOA lsoa ON lsoa.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientIMDDecile imd ON imd.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #FirstDementiaDiagnosis fdd ON fdd.PatientId = m.FK_Patient_Link_ID