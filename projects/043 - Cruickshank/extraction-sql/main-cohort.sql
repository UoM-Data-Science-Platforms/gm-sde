--┌──────────────────┐
--│ Main cohort file │
--└──────────────────┘

---------------------- RDE CHECK ---------------------
-- Le Mai Parkes  - 10 June 2022 - via pull request --
------------------------------------------------------

-- Cohort is everyone who tested positive with COVID-19 infection. 

-- PI also wanted Occupation, but there is a higher risk of re-identification if we supply it raw
-- e.g. if person is an MP, university VC, head teacher, professional sports person etc. Also there
-- are sensitive occupations like sex worker. Agreed to supply as is, then PI can decide what processing
-- is required e.g. mapping occupations to key/non-key worker etc. Also PI is aware that occupation
-- is poorly recorded ~10% of patients.

-- UPDATE 10 June 2022 - PI requests for diabetes to be split T1/T2

-- OUTPUT: Data with the following fields
-- 	- PatientId (int)
--  - FirstCovidPositiveDate (DDMMYYYY)
--  - SecondCovidPositiveDate (DDMMYYYY)
--  - ThirdCovidPositiveDate (DDMMYYYY)
--  - FirstAdmissionPost1stCOVIDTest (DDMMYYYY)
--  - FirstAdmissionPost2ndCOVIDTest (DDMMYYYY)
--  - FirstAdmissionPost3rdCOVIDTest (DDMMYYYY)
--  - DateOfDeath (DDMMYYYY)
--  - DeathWithin28Days (Y/N)
--  - LSOA
--  - LSOAStartDate (NB - this is either when they moved there OR when the data feed started)
--  - Months at this LSOA (if possible)
--  - YearOfBirth (YYYY)
--  - Sex (M/F)
--  - Ethnicity
--  - IMD2019Decile1IsMostDeprived10IsLeastDeprived
--  - PatientHasAsthma (Y/N) (at time of 1st COVID dx)
--  - PatientHasCHD (Y/N) (at time of 1st COVID dx)
--  - PatientHasStroke (Y/N) (at time of 1st COVID dx)
--  - PatientHasT1DM (Y/N) (at time of 1st COVID dx)
--  - PatientHasT2DM (Y/N) (at time of 1st COVID dx)
--  - PatientHasCOPD (Y/N) (at time of 1st COVID dx)
--  - PatientHasHypertension (Y/N) (at time of 1st COVID dx)
--  - WorstSmokingStatus (non-smoker / trivial smoker / non-trivial smoker)
--  - CurrentSmokingStatus (non-smoker / trivial smoker / non-trivial smoker)
--  - BMI (at time of 1st COVID dx)
--  - VaccineDose1Date (DDMMYYYY)
--  - VaccineDose2Date (DDMMYYYY)
--  - VaccineDose3Date (DDMMYYYY)
--  - VaccineDose4Date (DDMMYYYY)
--  - VaccineDose5Date (DDMMYYYY)

--Just want the output, not the messages
SET NOCOUNT ON;

-- Set the start date
DECLARE @StartDate datetime;
SET @StartDate = '2020-01-01';

-- Set the temp end date until new legal basis
DECLARE @TEMPRQ043EndDate datetime;
SET @TEMPRQ043EndDate = '2022-06-01';

-- Only include patients who were first registered at a GP practice prior
-- to June 2022. This is 1 month before COPI expired and so acts as a buffer.
-- If we only looked at patients who first registered before July 2022, then
-- there is a chance that their data was processed after COPI expired.
IF OBJECT_ID('tempdb..#PatientsToInclude') IS NOT NULL DROP TABLE #PatientsToInclude;
SELECT FK_Patient_Link_ID INTO #PatientsToInclude
FROM SharedCare.Patient_GP_History
GROUP BY FK_Patient_Link_ID
HAVING MIN(StartDate) < @TEMPRQ043EndDate;

-- Get all the positive covid test patients
--┌─────────────────────┐
--│ Patients with COVID │
--└─────────────────────┘

-- OBJECTIVE: To get tables of all patients with a COVID diagnosis in their record. This now includes a table
-- that has reinfections. This uses a 90 day cut-off to rule out patients that get multiple tests for
-- a single infection. This 90 day cut-off is also used in the government COVID dashboard. In the first wave,
-- prior to widespread COVID testing, and prior to the correct clinical codes being	available to clinicians,
-- infections were recorded in a variety of ways. We therefore take the first diagnosis from any code indicative
-- of COVID. However, for subsequent infections we insist on the presence of a positive COVID test 
-- as opposed to simply a diagnosis code. This is to avoid the situation where a hospital diagnosis code gets 
-- entered into the primary care record several months after the actual infection. NB this does not include antigen (LFT) tests.

-- INPUT: Takes three parameters
--  - start-date: string - (YYYY-MM-DD) the date to count diagnoses from. Usually this should be 2020-01-01.
--	-	all-patients: boolean - (true/false) if true, then all patients are included, otherwise only those in the pre-existing #Patients table.
--	- gp-events-table: string - (table name) the name of the table containing the GP events. Usually is "RLS.vw_GP_Events" but can be anything with the columns: FK_Patient_Link_ID, EventDate, and SuppliedCode

-- OUTPUT: Three temp tables as follows:
-- #CovidPatients (FK_Patient_Link_ID, FirstCovidPositiveDate)
-- 	- FK_Patient_Link_ID - unique patient id
--	- FirstCovidPositiveDate - earliest COVID diagnosis
-- #CovidPatientsAllDiagnoses (FK_Patient_Link_ID, CovidPositiveDate)
-- 	- FK_Patient_Link_ID - unique patient id
--	- CovidPositiveDate - any COVID diagnosis
-- #CovidPatientsMultipleDiagnoses
--	-	FK_Patient_Link_ID - unique patient id
--	-	FirstCovidPositiveDate - date of first COVID diagnosis
--	-	SecondCovidPositiveDate - date of second COVID diagnosis
--	-	ThirdCovidPositiveDate - date of third COVID diagnosis
--	-	FourthCovidPositiveDate - date of fourth COVID diagnosis
--	-	FifthCovidPositiveDate - date of fifth COVID diagnosis

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
VALUES ('asthma',1,'14B4.',NULL,'H/O: asthma'),('asthma',1,'14B4.00',NULL,'H/O: asthma'),('asthma',1,'173d.',NULL,'Work aggravated asthma'),('asthma',1,'173d.00',NULL,'Work aggravated asthma'),('asthma',1,'1O2..',NULL,'Asthma confirmed'),('asthma',1,'1O2..00',NULL,'Asthma confirmed'),('asthma',1,'8H2P.',NULL,'Emergency admission, asthma'),('asthma',1,'8H2P.00',NULL,'Emergency admission, asthma'),('asthma',1,'H3120',NULL,'Chronic asthmatic bronchitis'),('asthma',1,'H312000',NULL,'Chronic asthmatic bronchitis'),('asthma',1,'H33..',NULL,'Asthma'),('asthma',1,'H33..00',NULL,'Asthma'),('asthma',1,'H330.',NULL,'Extrinsic (atopic) asthma'),('asthma',1,'H330.00',NULL,'Extrinsic (atopic) asthma'),('asthma',1,'H3300',NULL,'Extrinsic asthma - no status'),('asthma',1,'H330000',NULL,'Extrinsic asthma - no status'),('asthma',1,'H3301',NULL,'Extrinsic asthma + status'),('asthma',1,'H330100',NULL,'Extrinsic asthma + status'),('asthma',1,'H330z',NULL,'Extrinsic asthma NOS'),('asthma',1,'H330z00',NULL,'Extrinsic asthma NOS'),('asthma',1,'H331.',NULL,'Intrinsic asthma'),('asthma',1,'H331.00',NULL,'Intrinsic asthma'),('asthma',1,'H3310',NULL,'Intrinsic asthma - no status'),('asthma',1,'H331000',NULL,'Intrinsic asthma - no status'),('asthma',1,'H3311',NULL,'Intrinsic asthma + status'),('asthma',1,'H331100',NULL,'Intrinsic asthma + status'),('asthma',1,'H331z',NULL,'Intrinsic asthma NOS'),('asthma',1,'H331z00',NULL,'Intrinsic asthma NOS'),('asthma',1,'H332.',NULL,'Mixed asthma'),('asthma',1,'H332.00',NULL,'Mixed asthma'),('asthma',1,'H333.',NULL,'Acute exacerbation of asthma'),('asthma',1,'H333.00',NULL,'Acute exacerbation of asthma'),('asthma',1,'H334.',NULL,'Brittle asthma'),('asthma',1,'H334.00',NULL,'Brittle asthma'),('asthma',1,'H335.',NULL,'Chron asthm w fix airflw obstr'),('asthma',1,'H335.00',NULL,'Chron asthm w fix airflw obstr'),('asthma',1,'H33z.',NULL,'Asthma unspecified'),('asthma',1,'H33z.00',NULL,'Asthma unspecified'),('asthma',1,'H33z0',NULL,'Status asthmaticus NOS'),('asthma',1,'H33z000',NULL,'Status asthmaticus NOS'),('asthma',1,'H33z1',NULL,'Asthma attack'),('asthma',1,'H33z100',NULL,'Asthma attack'),('asthma',1,'H33z2',NULL,'Late-onset asthma'),('asthma',1,'H33z200',NULL,'Late-onset asthma'),('asthma',1,'H33zz',NULL,'Asthma NOS'),('asthma',1,'H33zz00',NULL,'Asthma NOS'),('asthma',1,'H3B..',NULL,'Asthma-COPD overlap syndrome'),('asthma',1,'H3B..00',NULL,'Asthma-COPD overlap syndrome'),('asthma',1,'H47y0',NULL,'Detergent asthma'),('asthma',1,'H47y000',NULL,'Detergent asthma'),('asthma',1,'173c.',NULL,'Occupational asthma'),('asthma',1,'173c.00',NULL,'Occupational asthma'),('asthma',1,'663V2',NULL,'Moderate asthma'),('asthma',1,'663V200',NULL,'Moderate asthma'),('asthma',1,'663V3',NULL,'Severe asthma'),('asthma',1,'663V300',NULL,'Severe asthma');
INSERT INTO #codesreadv2
VALUES ('copd',1,'8H2R.',NULL,'Admit COPD emergency'),('copd',1,'8H2R.00',NULL,'Admit COPD emergency'),('copd',1,'9kf0.',NULL,'Chronic obstructive pulmonary disease patient unsuitable for pulmonary rehabilitation'),('copd',1,'9kf0.00',NULL,'Chronic obstructive pulmonary disease patient unsuitable for pulmonary rehabilitation'),('copd',1,'H3...',NULL,'Chronic obstructive pulmonary disease'),('copd',1,'H3...00',NULL,'Chronic obstructive pulmonary disease'),('copd',1,'H31..',NULL,'Chronic bronchitis'),('copd',1,'H31..00',NULL,'Chronic bronchitis'),('copd',1,'H310.',NULL,'Simple chronic bronchitis'),('copd',1,'H310.00',NULL,'Simple chronic bronchitis'),('copd',1,'H3100',NULL,'Chronic catarrhal bronchitis'),('copd',1,'H310000',NULL,'Chronic catarrhal bronchitis'),('copd',1,'H310z',NULL,'Simple chronic bronchitis NOS'),('copd',1,'H310z00',NULL,'Simple chronic bronchitis NOS'),('copd',1,'H311.',NULL,'Mucopurulent chronic bronchitis'),('copd',1,'H311.00',NULL,'Mucopurulent chronic bronchitis'),('copd',1,'H3110',NULL,'Purulent chronic bronchitis'),('copd',1,'H311000',NULL,'Purulent chronic bronchitis'),('copd',1,'H3111',NULL,'Fetid chronic bronchitis'),('copd',1,'H311100',NULL,'Fetid chronic bronchitis'),('copd',1,'H311z',NULL,'Mucopurulent chronic bronchitis NOS'),('copd',1,'H311z00',NULL,'Mucopurulent chronic bronchitis NOS'),('copd',1,'H312.',NULL,'Obstructive chronic bronchitis'),('copd',1,'H312.00',NULL,'Obstructive chronic bronchitis'),('copd',1,'H3120',NULL,'Chronic asthmatic bronchitis'),('copd',1,'H312000',NULL,'Chronic asthmatic bronchitis'),('copd',1,'H3121',NULL,'Emphysematous bronchitis'),('copd',1,'H312100',NULL,'Emphysematous bronchitis'),('copd',1,'H3122',NULL,'Acute exacerbation of chronic obstructive airways disease'),('copd',1,'H312200',NULL,'Acute exacerbation of chronic obstructive airways disease'),('copd',1,'H3123',NULL,'Bronchiolitis obliterans'),('copd',1,'H312300',NULL,'Bronchiolitis obliterans'),('copd',1,'H312z',NULL,'Obstructive chronic bronchitis NOS'),('copd',1,'H312z00',NULL,'Obstructive chronic bronchitis NOS'),('copd',1,'H313.',NULL,'Mixed simple and mucopurulent chronic bronchitis'),('copd',1,'H313.00',NULL,'Mixed simple and mucopurulent chronic bronchitis'),('copd',1,'H31y.',NULL,'Other chronic bronchitis'),('copd',1,'H31y.00',NULL,'Other chronic bronchitis'),('copd',1,'H31y1',NULL,'Chronic tracheobronchitis'),('copd',1,'H31y100',NULL,'Chronic tracheobronchitis'),('copd',1,'H31yz',NULL,'Other chronic bronchitis NOS'),('copd',1,'H31yz00',NULL,'Other chronic bronchitis NOS'),('copd',1,'H31z.',NULL,'Chronic bronchitis NOS'),('copd',1,'H31z.00',NULL,'Chronic bronchitis NOS'),('copd',1,'H32..',NULL,'Emphysema'),('copd',1,'H32..00',NULL,'Emphysema'),('copd',1,'H320.',NULL,'Chronic bullous emphysema'),('copd',1,'H320.00',NULL,'Chronic bullous emphysema'),('copd',1,'H3200',NULL,'Segmental bullous emphysema'),('copd',1,'H320000',NULL,'Segmental bullous emphysema'),('copd',1,'H3201',NULL,'Zonal bullous emphysema'),('copd',1,'H320100',NULL,'Zonal bullous emphysema'),('copd',1,'H3202',NULL,'Giant bullous emphysema'),('copd',1,'H320200',NULL,'Giant bullous emphysema'),('copd',1,'H3203',NULL,'Bullous emphysema with collapse'),('copd',1,'H320300',NULL,'Bullous emphysema with collapse'),('copd',1,'H320z',NULL,'Chronic bullous emphysema NOS'),('copd',1,'H320z00',NULL,'Chronic bullous emphysema NOS'),('copd',1,'H321.',NULL,'Panlobular emphysema'),('copd',1,'H321.00',NULL,'Panlobular emphysema'),('copd',1,'H322.',NULL,'Centrilobular emphysema'),('copd',1,'H322.00',NULL,'Centrilobular emphysema'),('copd',1,'H32y.',NULL,'Other emphysema'),('copd',1,'H32y.00',NULL,'Other emphysema'),('copd',1,'H32y0',NULL,'Acute vesicular emphysema'),('copd',1,'H32y000',NULL,'Acute vesicular emphysema'),('copd',1,'H32y1',NULL,'Atrophic (senile) emphysema'),('copd',1,'H32y100',NULL,'Atrophic (senile) emphysema'),('copd',1,'H32y2',NULL,'MacLeods unilateral emphysema'),('copd',1,'H32y200',NULL,'MacLeods unilateral emphysema'),('copd',1,'H32yz',NULL,'Other emphysema NOS'),('copd',1,'H32yz00',NULL,'Other emphysema NOS'),('copd',1,'H32z.',NULL,'Emphysema NOS'),('copd',1,'H32z.00',NULL,'Emphysema NOS'),('copd',1,'H36..',NULL,'Mild chronic obstructive pulmonary disease'),('copd',1,'H36..00',NULL,'Mild chronic obstructive pulmonary disease'),('copd',1,'H37..',NULL,'Moderate chronic obstructive pulmonary disease'),('copd',1,'H37..00',NULL,'Moderate chronic obstructive pulmonary disease'),('copd',1,'H38..',NULL,'Severe chronic obstructive pulmonary disease'),('copd',1,'H38..00',NULL,'Severe chronic obstructive pulmonary disease'),('copd',1,'H39..',NULL,'Very severe chronic obstructive pulmonary disease'),('copd',1,'H39..00',NULL,'Very severe chronic obstructive pulmonary disease'),('copd',1,'H3A..',NULL,'End stage chronic obstructive airways disease'),('copd',1,'H3A..00',NULL,'End stage chronic obstructive airways disease'),('copd',1,'H3B..',NULL,'Asthma-chronic obstructive pulmonary disease overlap syndrome'),('copd',1,'H3B..00',NULL,'Asthma-chronic obstructive pulmonary disease overlap syndrome'),('copd',1,'H3y..',NULL,'Other specified chronic obstructive airways disease'),('copd',1,'H3y..00',NULL,'Other specified chronic obstructive airways disease'),('copd',1,'H3y0.',NULL,'Chronic obstructive pulmonary disease with acute lower respiratory infection'),('copd',1,'H3y0.00',NULL,'Chronic obstructive pulmonary disease with acute lower respiratory infection'),('copd',1,'H3y1.',NULL,'Chronic obstructive pulmonary disease with acute exacerbation, unspecified'),('copd',1,'H3y1.00',NULL,'Chronic obstructive pulmonary disease with acute exacerbation, unspecified'),('copd',1,'H3z..',NULL,'Chronic obstructive airways disease NOS'),('copd',1,'H3z..00',NULL,'Chronic obstructive airways disease NOS'),('copd',1,'H4640',NULL,'Chronic emphysema due to chemical fumes'),('copd',1,'H464000',NULL,'Chronic emphysema due to chemical fumes'),('copd',1,'H4641',NULL,'Obliterative bronchiolitis due to chemical fumes'),('copd',1,'H464100',NULL,'Obliterative bronchiolitis due to chemical fumes'),('copd',1,'H581.',NULL,'Interstitial emphysema'),('copd',1,'H581.00',NULL,'Interstitial emphysema'),('copd',1,'H5832',NULL,'Eosinophilic bronchitis'),('copd',1,'H583200',NULL,'Eosinophilic bronchitis'),('copd',1,'Hyu30',NULL,'[X]Other emphysema'),('copd',1,'Hyu3000',NULL,'[X]Other emphysema'),('copd',1,'Hyu31',NULL,'[X]Other specified chronic obstructive pulmonary disease'),('copd',1,'Hyu3100',NULL,'[X]Other specified chronic obstructive pulmonary disease');
INSERT INTO #codesreadv2
VALUES ('coronary-heart-disease',1,'G3...',NULL,'Ischaemic heart disease'),('coronary-heart-disease',1,'G3...00',NULL,'Ischaemic heart disease'),('coronary-heart-disease',1,'G3z..',NULL,'Ischaemic heart disease NOS'),('coronary-heart-disease',1,'G3z..00',NULL,'Ischaemic heart disease NOS'),('coronary-heart-disease',1,'G3y..',NULL,'Other specified ischaemic heart disease'),('coronary-heart-disease',1,'G3y..00',NULL,'Other specified ischaemic heart disease'),('coronary-heart-disease',1,'G39..',NULL,'Coronary microvascular disease'),('coronary-heart-disease',1,'G39..00',NULL,'Coronary microvascular disease'),('coronary-heart-disease',1,'G38..',NULL,'Postoperative myocardial infarction'),('coronary-heart-disease',1,'G38..00',NULL,'Postoperative myocardial infarction'),('coronary-heart-disease',1,'G38z.',NULL,'Postoperative myocardial infarction, unspecified'),('coronary-heart-disease',1,'G38z.00',NULL,'Postoperative myocardial infarction, unspecified'),('coronary-heart-disease',1,'G384.',NULL,'Postoperative subendocardial myocardial infarction'),('coronary-heart-disease',1,'G384.00',NULL,'Postoperative subendocardial myocardial infarction'),('coronary-heart-disease',1,'G383.',NULL,'Postoperative transmural myocardial infarction of unspecified site'),('coronary-heart-disease',1,'G383.00',NULL,'Postoperative transmural myocardial infarction of unspecified site'),('coronary-heart-disease',1,'G382.',NULL,'Postoperative transmural myocardial infarction of other sites'),('coronary-heart-disease',1,'G382.00',NULL,'Postoperative transmural myocardial infarction of other sites'),('coronary-heart-disease',1,'G381.',NULL,'Postoperative transmural myocardial infarction of inferior wall'),('coronary-heart-disease',1,'G381.00',NULL,'Postoperative transmural myocardial infarction of inferior wall'),('coronary-heart-disease',1,'G380.',NULL,'Postoperative transmural myocardial infarction of anterior wall'),('coronary-heart-disease',1,'G380.00',NULL,'Postoperative transmural myocardial infarction of anterior wall'),('coronary-heart-disease',1,'G37..',NULL,'Cardiac syndrome X'),('coronary-heart-disease',1,'G37..00',NULL,'Cardiac syndrome X'),('coronary-heart-disease',1,'G365.',NULL,'Rupture of papillary muscle as current complication following acute myocardial infarction'),('coronary-heart-disease',1,'G365.00',NULL,'Rupture of papillary muscle as current complication following acute myocardial infarction'),('coronary-heart-disease',1,'G364.',NULL,'Rupture of chordae tendinae as current complication following acute myocardial infarction'),('coronary-heart-disease',1,'G364.00',NULL,'Rupture of chordae tendinae as current complication following acute myocardial infarction'),('coronary-heart-disease',1,'G363.',NULL,'Rupture of cardiac wall without haemopericardium as current complication following acute myocardial infarction'),('coronary-heart-disease',1,'G363.00',NULL,'Rupture of cardiac wall without haemopericardium as current complication following acute myocardial infarction'),('coronary-heart-disease',1,'G362.',NULL,'Ventricular septal defect as current complication following acute myocardial infarction'),('coronary-heart-disease',1,'G362.00',NULL,'Ventricular septal defect as current complication following acute myocardial infarction'),('coronary-heart-disease',1,'G361.',NULL,'Atrial septal defect as current complication following acute myocardial infarction'),('coronary-heart-disease',1,'G361.00',NULL,'Atrial septal defect as current complication following acute myocardial infarction'),('coronary-heart-disease',1,'G360.',NULL,'Haemopericardium as current complication following acute myocardial infarction'),('coronary-heart-disease',1,'G360.00',NULL,'Haemopericardium as current complication following acute myocardial infarction'),('coronary-heart-disease',1,'G35..',NULL,'Subsequent myocardial infarction'),('coronary-heart-disease',1,'G35..00',NULL,'Subsequent myocardial infarction'),('coronary-heart-disease',1,'G35X.',NULL,'Subsequent myocardial infarction of unspecified site'),('coronary-heart-disease',1,'G35X.00',NULL,'Subsequent myocardial infarction of unspecified site'),('coronary-heart-disease',1,'G353.',NULL,'Subsequent myocardial infarction of other sites'),('coronary-heart-disease',1,'G353.00',NULL,'Subsequent myocardial infarction of other sites'),('coronary-heart-disease',1,'G351.',NULL,'Subsequent myocardial infarction of inferior wall'),('coronary-heart-disease',1,'G351.00',NULL,'Subsequent myocardial infarction of inferior wall'),('coronary-heart-disease',1,'G350.',NULL,'Subsequent myocardial infarction of anterior wall'),('coronary-heart-disease',1,'G350.00',NULL,'Subsequent myocardial infarction of anterior wall'),('coronary-heart-disease',1,'G34..',NULL,'Other chronic ischaemic heart disease'),('coronary-heart-disease',1,'G34..00',NULL,'Other chronic ischaemic heart disease'),('coronary-heart-disease',1,'G34z.',NULL,'Other chronic ischaemic heart disease NOS'),('coronary-heart-disease',1,'G34z.00',NULL,'Other chronic ischaemic heart disease NOS'),('coronary-heart-disease',1,'G34z0',NULL,'Asymptomatic coronary heart disease'),('coronary-heart-disease',1,'G34z000',NULL,'Asymptomatic coronary heart disease'),('coronary-heart-disease',1,'G34y.',NULL,'Other specified chronic ischaemic heart disease'),('coronary-heart-disease',1,'G34y.00',NULL,'Other specified chronic ischaemic heart disease'),('coronary-heart-disease',1,'G34yz',NULL,'Other specified chronic ischaemic heart disease NOS'),('coronary-heart-disease',1,'G34yz00',NULL,'Other specified chronic ischaemic heart disease NOS'),('coronary-heart-disease',1,'G34y1',NULL,'Chronic myocardial ischaemia'),('coronary-heart-disease',1,'G34y100',NULL,'Chronic myocardial ischaemia'),('coronary-heart-disease',1,'G34y0',NULL,'Chronic coronary insufficiency'),('coronary-heart-disease',1,'G34y000',NULL,'Chronic coronary insufficiency'),('coronary-heart-disease',1,'G344.',NULL,'Silent myocardial ischaemia'),('coronary-heart-disease',1,'G344.00',NULL,'Silent myocardial ischaemia'),('coronary-heart-disease',1,'G343.',NULL,'Ischaemic cardiomyopathy'),('coronary-heart-disease',1,'G343.00',NULL,'Ischaemic cardiomyopathy'),('coronary-heart-disease',1,'G342.',NULL,'Atherosclerotic cardiovascular disease'),('coronary-heart-disease',1,'G342.00',NULL,'Atherosclerotic cardiovascular disease'),('coronary-heart-disease',1,'G341.',NULL,'Aneurysm of heart'),('coronary-heart-disease',1,'G341.00',NULL,'Aneurysm of heart'),('coronary-heart-disease',1,'G341z',NULL,'Aneurysm of heart NOS'),('coronary-heart-disease',1,'G341z00',NULL,'Aneurysm of heart NOS'),('coronary-heart-disease',1,'G3413',NULL,'Acquired atrioventricular fistula of heart'),('coronary-heart-disease',1,'G341300',NULL,'Acquired atrioventricular fistula of heart'),('coronary-heart-disease',1,'G3412',NULL,'Aneurysm of coronary vessels'),('coronary-heart-disease',1,'G341200',NULL,'Aneurysm of coronary vessels'),('coronary-heart-disease',1,'G3411',NULL,'Other cardiac wall aneurysm'),('coronary-heart-disease',1,'G341100',NULL,'Other cardiac wall aneurysm'),('coronary-heart-disease',1,'G3410',NULL,'Ventricular cardiac aneurysm'),('coronary-heart-disease',1,'G341000',NULL,'Ventricular cardiac aneurysm'),('coronary-heart-disease',1,'G340.',NULL,'Coronary atherosclerosis'),('coronary-heart-disease',1,'G340.00',NULL,'Coronary atherosclerosis'),('coronary-heart-disease',1,'G3401',NULL,'Double coronary vessel disease'),('coronary-heart-disease',1,'G340100',NULL,'Double coronary vessel disease'),('coronary-heart-disease',1,'G3400',NULL,'Single coronary vessel disease'),('coronary-heart-disease',1,'G340000',NULL,'Single coronary vessel disease'),('coronary-heart-disease',1,'G33..',NULL,'Angina pectoris'),('coronary-heart-disease',1,'G33..00',NULL,'Angina pectoris'),('coronary-heart-disease',1,'G33z.',NULL,'Angina pectoris NOS'),('coronary-heart-disease',1,'G33z.00',NULL,'Angina pectoris NOS'),('coronary-heart-disease',1,'G33zz',NULL,'Angina pectoris NOS'),('coronary-heart-disease',1,'G33zz00',NULL,'Angina pectoris NOS'),('coronary-heart-disease',1,'G33z7',NULL,'Stable angina'),('coronary-heart-disease',1,'G33z700',NULL,'Stable angina'),('coronary-heart-disease',1,'G33z6',NULL,'New onset angina'),('coronary-heart-disease',1,'G33z600',NULL,'New onset angina'),('coronary-heart-disease',1,'G33z5',NULL,'Post infarct angina'),('coronary-heart-disease',1,'G33z500',NULL,'Post infarct angina'),('coronary-heart-disease',1,'G33z4',NULL,'Ischaemic chest pain'),('coronary-heart-disease',1,'G33z400',NULL,'Ischaemic chest pain'),('coronary-heart-disease',1,'G33z3',NULL,'Angina on effort'),('coronary-heart-disease',1,'G33z300',NULL,'Angina on effort'),('coronary-heart-disease',1,'G33z2',NULL,'Syncope anginosa'),('coronary-heart-disease',1,'G33z200',NULL,'Syncope anginosa'),('coronary-heart-disease',1,'G33z1',NULL,'Stenocardia'),('coronary-heart-disease',1,'G33z100',NULL,'Stenocardia'),('coronary-heart-disease',1,'G33z0',NULL,'Status anginosus'),('coronary-heart-disease',1,'G33z000',NULL,'Status anginosus'),('coronary-heart-disease',1,'G331.',NULL,'Prinzmetals angina'),('coronary-heart-disease',1,'G331.00',NULL,'Prinzmetals angina'),('coronary-heart-disease',1,'G330.',NULL,'Angina decubitus'),('coronary-heart-disease',1,'G330.00',NULL,'Angina decubitus'),('coronary-heart-disease',1,'G330z',NULL,'Angina decubitus NOS'),('coronary-heart-disease',1,'G330z00',NULL,'Angina decubitus NOS'),('coronary-heart-disease',1,'G3300',NULL,'Nocturnal angina'),('coronary-heart-disease',1,'G330000',NULL,'Nocturnal angina'),('coronary-heart-disease',1,'G32..',NULL,'Old myocardial infarction'),('coronary-heart-disease',1,'G32..00',NULL,'Old myocardial infarction'),('coronary-heart-disease',1,'G31..',NULL,'Other acute and subacute ischaemic heart disease'),('coronary-heart-disease',1,'G31..00',NULL,'Other acute and subacute ischaemic heart disease'),('coronary-heart-disease',1,'G31y.',NULL,'Other acute and subacute ischaemic heart disease'),
('coronary-heart-disease',1,'G31y.00',NULL,'Other acute and subacute ischaemic heart disease'),('coronary-heart-disease',1,'G31yz',NULL,'Other acute and subacute ischaemic heart disease NOS'),('coronary-heart-disease',1,'G31yz00',NULL,'Other acute and subacute ischaemic heart disease NOS'),('coronary-heart-disease',1,'G31y3',NULL,'Transient myocardial ischaemia'),('coronary-heart-disease',1,'G31y300',NULL,'Transient myocardial ischaemia'),('coronary-heart-disease',1,'G31y2',NULL,'Subendocardial ischaemia'),('coronary-heart-disease',1,'G31y200',NULL,'Subendocardial ischaemia'),('coronary-heart-disease',1,'G31y1',NULL,'Microinfarction of heart'),('coronary-heart-disease',1,'G31y100',NULL,'Microinfarction of heart'),('coronary-heart-disease',1,'G31y0',NULL,'Acute coronary insufficiency'),('coronary-heart-disease',1,'G31y000',NULL,'Acute coronary insufficiency'),('coronary-heart-disease',1,'G312.',NULL,'Coronary thrombosis not resulting in myocardial infarction'),('coronary-heart-disease',1,'G312.00',NULL,'Coronary thrombosis not resulting in myocardial infarction'),('coronary-heart-disease',1,'G311.',NULL,'Preinfarction syndrome'),('coronary-heart-disease',1,'G311.00',NULL,'Preinfarction syndrome'),('coronary-heart-disease',1,'G311z',NULL,'Preinfarction syndrome NOS'),('coronary-heart-disease',1,'G311z00',NULL,'Preinfarction syndrome NOS'),('coronary-heart-disease',1,'G3115',NULL,'Acute coronary syndrome'),('coronary-heart-disease',1,'G311500',NULL,'Acute coronary syndrome'),('coronary-heart-disease',1,'G3114',NULL,'Worsening angina'),('coronary-heart-disease',1,'G311400',NULL,'Worsening angina'),('coronary-heart-disease',1,'G3113',NULL,'Refractory angina'),('coronary-heart-disease',1,'G311300',NULL,'Refractory angina'),('coronary-heart-disease',1,'G3112',NULL,'Angina at rest'),('coronary-heart-disease',1,'G311200',NULL,'Angina at rest'),('coronary-heart-disease',1,'G3111',NULL,'Unstable angina'),('coronary-heart-disease',1,'G311100',NULL,'Unstable angina'),('coronary-heart-disease',1,'G3110',NULL,'Myocardial infarction aborted'),('coronary-heart-disease',1,'G311000',NULL,'Myocardial infarction aborted'),('coronary-heart-disease',1,'G310.',NULL,'Postmyocardial infarction syndrome'),('coronary-heart-disease',1,'G310.00',NULL,'Postmyocardial infarction syndrome'),('coronary-heart-disease',1,'G30..',NULL,'Acute myocardial infarction'),('coronary-heart-disease',1,'G30..00',NULL,'Acute myocardial infarction'),('coronary-heart-disease',1,'G30z.',NULL,'Acute myocardial infarction NOS'),('coronary-heart-disease',1,'G30z.00',NULL,'Acute myocardial infarction NOS'),('coronary-heart-disease',1,'G30y.',NULL,'Other acute myocardial infarction'),('coronary-heart-disease',1,'G30y.00',NULL,'Other acute myocardial infarction'),('coronary-heart-disease',1,'G30yz',NULL,'Other acute myocardial infarction NOS'),('coronary-heart-disease',1,'G30yz00',NULL,'Other acute myocardial infarction NOS'),('coronary-heart-disease',1,'G30y2',NULL,'Acute septal infarction'),('coronary-heart-disease',1,'G30y200',NULL,'Acute septal infarction'),('coronary-heart-disease',1,'G30y1',NULL,'Acute papillary muscle infarction'),('coronary-heart-disease',1,'G30y100',NULL,'Acute papillary muscle infarction'),('coronary-heart-disease',1,'G30y0',NULL,'Acute atrial infarction'),('coronary-heart-disease',1,'G30y000',NULL,'Acute atrial infarction'),('coronary-heart-disease',1,'G30X.',NULL,'Acute transmural myocardial infarction of unspecified site'),('coronary-heart-disease',1,'G30X.00',NULL,'Acute transmural myocardial infarction of unspecified site'),('coronary-heart-disease',1,'G30X0',NULL,'Acute ST segment elevation myocardial infarction'),('coronary-heart-disease',1,'G30X000',NULL,'Acute ST segment elevation myocardial infarction'),('coronary-heart-disease',1,'G30B.',NULL,'Acute posterolateral myocardial infarction'),('coronary-heart-disease',1,'G30B.00',NULL,'Acute posterolateral myocardial infarction'),('coronary-heart-disease',1,'G309.',NULL,'Acute Q-wave infarct'),('coronary-heart-disease',1,'G309.00',NULL,'Acute Q-wave infarct'),('coronary-heart-disease',1,'G308.',NULL,'Inferior myocardial infarction NOS'),('coronary-heart-disease',1,'G308.00',NULL,'Inferior myocardial infarction NOS'),('coronary-heart-disease',1,'G307.',NULL,'Acute subendocardial infarction'),('coronary-heart-disease',1,'G307.00',NULL,'Acute subendocardial infarction'),('coronary-heart-disease',1,'G3071',NULL,'Acute non-ST segment elevation myocardial infarction'),('coronary-heart-disease',1,'G307100',NULL,'Acute non-ST segment elevation myocardial infarction'),('coronary-heart-disease',1,'G3070',NULL,'Acute non-Q wave infarction'),('coronary-heart-disease',1,'G307000',NULL,'Acute non-Q wave infarction'),('coronary-heart-disease',1,'G306.',NULL,'True posterior myocardial infarction'),('coronary-heart-disease',1,'G306.00',NULL,'True posterior myocardial infarction'),('coronary-heart-disease',1,'G305.',NULL,'Lateral myocardial infarction NOS'),('coronary-heart-disease',1,'G305.00',NULL,'Lateral myocardial infarction NOS'),('coronary-heart-disease',1,'G304.',NULL,'Posterior myocardial infarction NOS'),('coronary-heart-disease',1,'G304.00',NULL,'Posterior myocardial infarction NOS'),('coronary-heart-disease',1,'G303.',NULL,'Acute inferoposterior infarction'),('coronary-heart-disease',1,'G303.00',NULL,'Acute inferoposterior infarction'),('coronary-heart-disease',1,'G302.',NULL,'Acute inferolateral infarction'),('coronary-heart-disease',1,'G302.00',NULL,'Acute inferolateral infarction'),('coronary-heart-disease',1,'G301.',NULL,'Other specified anterior myocardial infarction'),('coronary-heart-disease',1,'G301.00',NULL,'Other specified anterior myocardial infarction'),('coronary-heart-disease',1,'G301z',NULL,'Anterior myocardial infarction NOS'),('coronary-heart-disease',1,'G301z00',NULL,'Anterior myocardial infarction NOS'),('coronary-heart-disease',1,'G3011',NULL,'Acute anteroseptal infarction'),('coronary-heart-disease',1,'G301100',NULL,'Acute anteroseptal infarction'),('coronary-heart-disease',1,'G3010',NULL,'Acute anteroapical infarction'),('coronary-heart-disease',1,'G301000',NULL,'Acute anteroapical infarction'),('coronary-heart-disease',1,'G300.',NULL,'Acute anterolateral infarction'),('coronary-heart-disease',1,'G300.00',NULL,'Acute anterolateral infarction'),('coronary-heart-disease',1,'Gyu3.',NULL,'[X]Ischaemic heart diseases'),('coronary-heart-disease',1,'Gyu3.00',NULL,'[X]Ischaemic heart diseases'),('coronary-heart-disease',1,'Gyu33',NULL,'[X]Other forms of chronic ischaemic heart disease'),('coronary-heart-disease',1,'Gyu3300',NULL,'[X]Other forms of chronic ischaemic heart disease'),('coronary-heart-disease',1,'Gyu32',NULL,'[X]Other forms of acute ischaemic heart disease'),('coronary-heart-disease',1,'Gyu3200',NULL,'[X]Other forms of acute ischaemic heart disease'),('coronary-heart-disease',1,'Gyu30',NULL,'[X]Other forms of angina pectoris'),('coronary-heart-disease',1,'Gyu3000',NULL,'[X]Other forms of angina pectoris'),('coronary-heart-disease',1,'Gyu36',NULL,'[X]Subsequent myocardial infarction of unspecified site'),('coronary-heart-disease',1,'Gyu3600',NULL,'[X]Subsequent myocardial infarction of unspecified site'),('coronary-heart-disease',1,'Gyu35',NULL,'[X]Subsequent myocardial infarction of other sites'),('coronary-heart-disease',1,'Gyu3500',NULL,'[X]Subsequent myocardial infarction of other sites'),('coronary-heart-disease',1,'Gyu34',NULL,'[X]Acute transmural myocardial infarction of unspecified site'),('coronary-heart-disease',1,'Gyu3400',NULL,'[X]Acute transmural myocardial infarction of unspecified site'),('coronary-heart-disease',1,'14AL.',NULL,'H/O: Treatment for ischaemic heart disease'),('coronary-heart-disease',1,'14AL.00',NULL,'H/O: Treatment for ischaemic heart disease'),('coronary-heart-disease',1,'14AW.',NULL,'H/O acute coronary syndrome'),('coronary-heart-disease',1,'14AW.00',NULL,'H/O acute coronary syndrome'),('coronary-heart-disease',1,'14AJ.',NULL,'H/O: Angina in last year'),('coronary-heart-disease',1,'14AJ.00',NULL,'H/O: Angina in last year'),('coronary-heart-disease',1,'14A5.',NULL,'H/O: angina pectoris'),('coronary-heart-disease',1,'14A5.00',NULL,'H/O: angina pectoris'),('coronary-heart-disease',1,'14AH.',NULL,'H/O: Myocardial infarction in last year'),('coronary-heart-disease',1,'14AH.00',NULL,'H/O: Myocardial infarction in last year'),('coronary-heart-disease',1,'P6yy6',NULL,'Congenital aneurysm of heart'),('coronary-heart-disease',1,'P6yy600',NULL,'Congenital aneurysm of heart'),('coronary-heart-disease',1,'SP076',NULL,'Coronary artery bypass graft occlusion'),('coronary-heart-disease',1,'SP07600',NULL,'Coronary artery bypass graft occlusion'),('coronary-heart-disease',1,'G70..',NULL,'Atherosclerosis'),('coronary-heart-disease',1,'G70..00',NULL,'Atherosclerosis');
INSERT INTO #codesreadv2
VALUES ('diabetes-type-i',1,'C1000',NULL,'Diabetes mellitus, juvenile type, with no mention of complication'),('diabetes-type-i',1,'C100000',NULL,'Diabetes mellitus, juvenile type, with no mention of complication'),('diabetes-type-i',1,'C1010',NULL,'Diabetes mellitus, juvenile type, with ketoacidosis'),('diabetes-type-i',1,'C101000',NULL,'Diabetes mellitus, juvenile type, with ketoacidosis'),('diabetes-type-i',1,'C1020',NULL,'Diabetes mellitus, juvenile type, with hyperosmolar coma'),('diabetes-type-i',1,'C102000',NULL,'Diabetes mellitus, juvenile type, with hyperosmolar coma'),('diabetes-type-i',1,'C1030',NULL,'Diabetes mellitus, juvenile type, with ketoacidotic coma'),('diabetes-type-i',1,'C103000',NULL,'Diabetes mellitus, juvenile type, with ketoacidotic coma'),('diabetes-type-i',1,'C1040',NULL,'Diabetes mellitus, juvenile type, with renal manifestation'),('diabetes-type-i',1,'C104000',NULL,'Diabetes mellitus, juvenile type, with renal manifestation'),('diabetes-type-i',1,'C1050',NULL,'Diabetes mellitus, juvenile type, with ophthalmic manifestation'),('diabetes-type-i',1,'C105000',NULL,'Diabetes mellitus, juvenile type, with ophthalmic manifestation'),('diabetes-type-i',1,'C1060',NULL,'Diabetes mellitus, juvenile type, with neurological manifestation'),('diabetes-type-i',1,'C106000',NULL,'Diabetes mellitus, juvenile type, with neurological manifestation'),('diabetes-type-i',1,'C1070',NULL,'Diabetes mellitus, juvenile type, with peripheral circulatory disorder'),('diabetes-type-i',1,'C107000',NULL,'Diabetes mellitus, juvenile type, with peripheral circulatory disorder'),('diabetes-type-i',1,'C108.',NULL,'Insulin dependent diabetes mellitus'),('diabetes-type-i',1,'C108.00',NULL,'Insulin dependent diabetes mellitus'),('diabetes-type-i',1,'C1080',NULL,'Insulin-dependent diabetes mellitus with renal complications'),('diabetes-type-i',1,'C108000',NULL,'Insulin-dependent diabetes mellitus with renal complications'),('diabetes-type-i',1,'C1081',NULL,'Insulin-dependent diabetes mellitus with ophthalmic complications'),('diabetes-type-i',1,'C108100',NULL,'Insulin-dependent diabetes mellitus with ophthalmic complications'),('diabetes-type-i',1,'C1082',NULL,'Insulin-dependent diabetes mellitus with neurological complications'),('diabetes-type-i',1,'C108200',NULL,'Insulin-dependent diabetes mellitus with neurological complications'),('diabetes-type-i',1,'C1083',NULL,'Insulin dependent diabetes mellitus with multiple complications'),('diabetes-type-i',1,'C108300',NULL,'Insulin dependent diabetes mellitus with multiple complications'),('diabetes-type-i',1,'C1084',NULL,'Unstable insulin dependent diabetes mellitus'),('diabetes-type-i',1,'C108400',NULL,'Unstable insulin dependent diabetes mellitus'),('diabetes-type-i',1,'C1085',NULL,'Insulin dependent diabetes mellitus with ulcer'),('diabetes-type-i',1,'C108500',NULL,'Insulin dependent diabetes mellitus with ulcer'),('diabetes-type-i',1,'C1086',NULL,'Insulin dependent diabetes mellitus with gangrene'),('diabetes-type-i',1,'C108600',NULL,'Insulin dependent diabetes mellitus with gangrene'),('diabetes-type-i',1,'C1087',NULL,'Insulin dependent diabetes mellitus with retinopathy'),('diabetes-type-i',1,'C108700',NULL,'Insulin dependent diabetes mellitus with retinopathy'),('diabetes-type-i',1,'C1088',NULL,'Insulin dependent diabetes mellitus - poor control'),('diabetes-type-i',1,'C108800',NULL,'Insulin dependent diabetes mellitus - poor control'),('diabetes-type-i',1,'C1089',NULL,'Insulin dependent diabetes maturity onset'),('diabetes-type-i',1,'C108900',NULL,'Insulin dependent diabetes maturity onset'),('diabetes-type-i',1,'C108A',NULL,'Insulin-dependent diabetes without complication'),('diabetes-type-i',1,'C108A00',NULL,'Insulin-dependent diabetes without complication'),('diabetes-type-i',1,'C108B',NULL,'Insulin dependent diabetes mellitus with mononeuropathy'),('diabetes-type-i',1,'C108B00',NULL,'Insulin dependent diabetes mellitus with mononeuropathy'),('diabetes-type-i',1,'C108C',NULL,'Insulin dependent diabetes mellitus with polyneuropathy'),('diabetes-type-i',1,'C108C00',NULL,'Insulin dependent diabetes mellitus with polyneuropathy'),('diabetes-type-i',1,'C108D',NULL,'Insulin dependent diabetes mellitus with nephropathy'),('diabetes-type-i',1,'C108D00',NULL,'Insulin dependent diabetes mellitus with nephropathy'),('diabetes-type-i',1,'C108E',NULL,'Insulin dependent diabetes mellitus with hypoglycaemic coma'),('diabetes-type-i',1,'C108E00',NULL,'Insulin dependent diabetes mellitus with hypoglycaemic coma'),('diabetes-type-i',1,'C108F',NULL,'Insulin dependent diabetes mellitus with diabetic cataract'),('diabetes-type-i',1,'C108F00',NULL,'Insulin dependent diabetes mellitus with diabetic cataract'),('diabetes-type-i',1,'C108G',NULL,'Insulin dependent diabetes mellitus with peripheral angiopathy'),('diabetes-type-i',1,'C108G00',NULL,'Insulin dependent diabetes mellitus with peripheral angiopathy'),('diabetes-type-i',1,'C108H',NULL,'Insulin dependent diabetes mellitus with arthropathy'),('diabetes-type-i',1,'C108H00',NULL,'Insulin dependent diabetes mellitus with arthropathy'),('diabetes-type-i',1,'C108J',NULL,'Insulin dependent diabetes mellitus with neuropathic arthropathy'),('diabetes-type-i',1,'C108J00',NULL,'Insulin dependent diabetes mellitus with neuropathic arthropathy'),('diabetes-type-i',1,'C10E.',NULL,'Type 1 diabetes mellitus'),('diabetes-type-i',1,'C10E.00',NULL,'Type 1 diabetes mellitus'),('diabetes-type-i',1,'C10E0',NULL,'Type 1 diabetes mellitus with renal complications'),('diabetes-type-i',1,'C10E000',NULL,'Type 1 diabetes mellitus with renal complications'),('diabetes-type-i',1,'C10E1',NULL,'Type 1 diabetes mellitus with ophthalmic complications'),('diabetes-type-i',1,'C10E100',NULL,'Type 1 diabetes mellitus with ophthalmic complications'),('diabetes-type-i',1,'C10E2',NULL,'Type 1 diabetes mellitus with neurological complications'),('diabetes-type-i',1,'C10E200',NULL,'Type 1 diabetes mellitus with neurological complications'),('diabetes-type-i',1,'C10E3',NULL,'Type 1 diabetes mellitus with multiple complications'),('diabetes-type-i',1,'C10E300',NULL,'Type 1 diabetes mellitus with multiple complications'),('diabetes-type-i',1,'C10E4',NULL,'Unstable type 1 diabetes mellitus'),('diabetes-type-i',1,'C10E400',NULL,'Unstable type 1 diabetes mellitus'),('diabetes-type-i',1,'C10E5',NULL,'Type 1 diabetes mellitus with ulcer'),('diabetes-type-i',1,'C10E500',NULL,'Type 1 diabetes mellitus with ulcer'),('diabetes-type-i',1,'C10E6',NULL,'Type 1 diabetes mellitus with gangrene'),('diabetes-type-i',1,'C10E600',NULL,'Type 1 diabetes mellitus with gangrene'),('diabetes-type-i',1,'C10E7',NULL,'Type 1 diabetes mellitus with retinopathy'),('diabetes-type-i',1,'C10E700',NULL,'Type 1 diabetes mellitus with retinopathy'),('diabetes-type-i',1,'C10E8',NULL,'Type 1 diabetes mellitus - poor control'),('diabetes-type-i',1,'C10E800',NULL,'Type 1 diabetes mellitus - poor control'),('diabetes-type-i',1,'C10E9',NULL,'Type 1 diabetes mellitus maturity onset'),('diabetes-type-i',1,'C10E900',NULL,'Type 1 diabetes mellitus maturity onset'),('diabetes-type-i',1,'C10EA',NULL,'Type 1 diabetes mellitus without complication'),('diabetes-type-i',1,'C10EA00',NULL,'Type 1 diabetes mellitus without complication'),('diabetes-type-i',1,'C10EB',NULL,'Type 1 diabetes mellitus with mononeuropathy'),('diabetes-type-i',1,'C10EB00',NULL,'Type 1 diabetes mellitus with mononeuropathy'),('diabetes-type-i',1,'C10EC',NULL,'Type 1 diabetes mellitus with polyneuropathy'),('diabetes-type-i',1,'C10EC00',NULL,'Type 1 diabetes mellitus with polyneuropathy'),('diabetes-type-i',1,'C10ED',NULL,'Type 1 diabetes mellitus with nephropathy'),('diabetes-type-i',1,'C10ED00',NULL,'Type 1 diabetes mellitus with nephropathy'),('diabetes-type-i',1,'C10EE',NULL,'Type 1 diabetes mellitus with hypoglycaemic coma'),('diabetes-type-i',1,'C10EE00',NULL,'Type 1 diabetes mellitus with hypoglycaemic coma'),('diabetes-type-i',1,'C10EF',NULL,'Type 1 diabetes mellitus with diabetic cataract'),('diabetes-type-i',1,'C10EF00',NULL,'Type 1 diabetes mellitus with diabetic cataract'),('diabetes-type-i',1,'C10EG',NULL,'Type 1 diabetes mellitus with peripheral angiopathy'),('diabetes-type-i',1,'C10EG00',NULL,'Type 1 diabetes mellitus with peripheral angiopathy'),('diabetes-type-i',1,'C10EH',NULL,'Type 1 diabetes mellitus with arthropathy'),('diabetes-type-i',1,'C10EH00',NULL,'Type 1 diabetes mellitus with arthropathy'),('diabetes-type-i',1,'C10EJ',NULL,'Type 1 diabetes mellitus with neuropathic arthropathy'),('diabetes-type-i',1,'C10EJ00',NULL,'Type 1 diabetes mellitus with neuropathic arthropathy'),('diabetes-type-i',1,'C10EK',NULL,'Type 1 diabetes mellitus with persistent proteinuria'),('diabetes-type-i',1,'C10EK00',NULL,'Type 1 diabetes mellitus with persistent proteinuria'),('diabetes-type-i',1,'C10EL',NULL,'Type 1 diabetes mellitus with persistent microalbuminuria'),('diabetes-type-i',1,'C10EL00',NULL,'Type 1 diabetes mellitus with persistent microalbuminuria'),('diabetes-type-i',1,'C10EM',NULL,'Type 1 diabetes mellitus with ketoacidosis'),('diabetes-type-i',1,'C10EM00',NULL,'Type 1 diabetes mellitus with ketoacidosis'),('diabetes-type-i',1,'C10EN',NULL,'Type 1 diabetes mellitus with ketoacidotic coma'),('diabetes-type-i',1,'C10EN00',NULL,'Type 1 diabetes mellitus with ketoacidotic coma'),('diabetes-type-i',1,'C10EP',NULL,'Type 1 diabetes mellitus with exudative maculopathy'),('diabetes-type-i',1,'C10EP00',NULL,'Type 1 diabetes mellitus with exudative maculopathy'),('diabetes-type-i',1,'C10EQ',NULL,'Type 1 diabetes mellitus with gastroparesis'),('diabetes-type-i',1,'C10EQ00',NULL,'Type 1 diabetes mellitus with gastroparesis'),('diabetes-type-i',1,'C10y0',NULL,'Diabetes mellitus, juvenile type, with other specified manifestation'),('diabetes-type-i',1,'C10y000',NULL,'Diabetes mellitus, juvenile type, with other specified manifestation'),('diabetes-type-i',1,'C10z0',NULL,'Diabetes mellitus, juvenile type, with unspecified complication'),
('diabetes-type-i',1,'C10z000',NULL,'Diabetes mellitus, juvenile type, with unspecified complication');
INSERT INTO #codesreadv2
VALUES ('diabetes-type-ii',1,'C1001',NULL,'Diabetes mellitus, adult onset, with no mention of complication'),('diabetes-type-ii',1,'C100100',NULL,'Diabetes mellitus, adult onset, with no mention of complication'),('diabetes-type-ii',1,'C1011',NULL,'Diabetes mellitus, adult onset, with ketoacidosis'),('diabetes-type-ii',1,'C101100',NULL,'Diabetes mellitus, adult onset, with ketoacidosis'),('diabetes-type-ii',1,'C1021',NULL,'Diabetes mellitus, adult onset, with hyperosmolar coma'),('diabetes-type-ii',1,'C102100',NULL,'Diabetes mellitus, adult onset, with hyperosmolar coma'),('diabetes-type-ii',1,'C1031',NULL,'Diabetes mellitus, adult onset, with ketoacidotic coma'),('diabetes-type-ii',1,'C103100',NULL,'Diabetes mellitus, adult onset, with ketoacidotic coma'),('diabetes-type-ii',1,'C1041',NULL,'Diabetes mellitus, adult onset, with renal manifestation'),('diabetes-type-ii',1,'C104100',NULL,'Diabetes mellitus, adult onset, with renal manifestation'),('diabetes-type-ii',1,'C1051',NULL,'Diabetes mellitus, adult onset, with ophthalmic manifestation'),('diabetes-type-ii',1,'C105100',NULL,'Diabetes mellitus, adult onset, with ophthalmic manifestation'),('diabetes-type-ii',1,'C1061',NULL,'Diabetes mellitus, adult onset, with neurological manifestation'),('diabetes-type-ii',1,'C106100',NULL,'Diabetes mellitus, adult onset, with neurological manifestation'),('diabetes-type-ii',1,'C1071',NULL,'Diabetes mellitus, adult onset, with peripheral circulatory disorder'),('diabetes-type-ii',1,'C107100',NULL,'Diabetes mellitus, adult onset, with peripheral circulatory disorder'),('diabetes-type-ii',1,'C109.',NULL,'Non-insulin dependent diabetes mellitus'),('diabetes-type-ii',1,'C109.00',NULL,'Non-insulin dependent diabetes mellitus'),('diabetes-type-ii',1,'C1090',NULL,'Non-insulin-dependent diabetes mellitus with renal complications'),('diabetes-type-ii',1,'C109000',NULL,'Non-insulin-dependent diabetes mellitus with renal complications'),('diabetes-type-ii',1,'C1091',NULL,'Non-insulin-dependent diabetes mellitus with ophthalmic complications'),('diabetes-type-ii',1,'C109100',NULL,'Non-insulin-dependent diabetes mellitus with ophthalmic complications'),('diabetes-type-ii',1,'C1092',NULL,'Non-insulin-dependent diabetes mellitus with neurological complications'),('diabetes-type-ii',1,'C109200',NULL,'Non-insulin-dependent diabetes mellitus with neurological complications'),('diabetes-type-ii',1,'C1093',NULL,'Non-insulin-dependent diabetes mellitus with multiple complications'),('diabetes-type-ii',1,'C109300',NULL,'Non-insulin-dependent diabetes mellitus with multiple complications'),('diabetes-type-ii',1,'C1094',NULL,'Non-insulin dependent diabetes mellitus with ulcer'),('diabetes-type-ii',1,'C109400',NULL,'Non-insulin dependent diabetes mellitus with ulcer'),('diabetes-type-ii',1,'C1095',NULL,'Non-insulin dependent diabetes mellitus with gangrene'),('diabetes-type-ii',1,'C109500',NULL,'Non-insulin dependent diabetes mellitus with gangrene'),('diabetes-type-ii',1,'C1096',NULL,'Non-insulin-dependent diabetes mellitus with retinopathy'),('diabetes-type-ii',1,'C109600',NULL,'Non-insulin-dependent diabetes mellitus with retinopathy'),('diabetes-type-ii',1,'C1097',NULL,'Non-insulin dependent diabetes mellitus - poor control'),('diabetes-type-ii',1,'C109700',NULL,'Non-insulin dependent diabetes mellitus - poor control'),('diabetes-type-ii',1,'C1099',NULL,'Non-insulin-dependent diabetes mellitus without complication'),('diabetes-type-ii',1,'C109900',NULL,'Non-insulin-dependent diabetes mellitus without complication'),('diabetes-type-ii',1,'C109A',NULL,'Non-insulin dependent diabetes mellitus with mononeuropathy'),('diabetes-type-ii',1,'C109A00',NULL,'Non-insulin dependent diabetes mellitus with mononeuropathy'),('diabetes-type-ii',1,'C109B',NULL,'Non-insulin dependent diabetes mellitus with polyneuropathy'),('diabetes-type-ii',1,'C109B00',NULL,'Non-insulin dependent diabetes mellitus with polyneuropathy'),('diabetes-type-ii',1,'C109C',NULL,'Non-insulin dependent diabetes mellitus with nephropathy'),('diabetes-type-ii',1,'C109C00',NULL,'Non-insulin dependent diabetes mellitus with nephropathy'),('diabetes-type-ii',1,'C109D',NULL,'Non-insulin dependent diabetes mellitus with hypoglycaemic coma'),('diabetes-type-ii',1,'C109D00',NULL,'Non-insulin dependent diabetes mellitus with hypoglycaemic coma'),('diabetes-type-ii',1,'C109E',NULL,'Non-insulin dependent diabetes mellitus with diabetic cataract'),('diabetes-type-ii',1,'C109E00',NULL,'Non-insulin dependent diabetes mellitus with diabetic cataract'),('diabetes-type-ii',1,'C109F',NULL,'Non-insulin-dependent diabetes mellitus with peripheral angiopathy'),('diabetes-type-ii',1,'C109F00',NULL,'Non-insulin-dependent diabetes mellitus with peripheral angiopathy'),('diabetes-type-ii',1,'C109G',NULL,'Non-insulin dependent diabetes mellitus with arthropathy'),('diabetes-type-ii',1,'C109G00',NULL,'Non-insulin dependent diabetes mellitus with arthropathy'),('diabetes-type-ii',1,'C109H',NULL,'Non-insulin dependent diabetes mellitus with neuropathic arthropathy'),('diabetes-type-ii',1,'C109H00',NULL,'Non-insulin dependent diabetes mellitus with neuropathic arthropathy'),('diabetes-type-ii',1,'C109J',NULL,'Insulin treated Type 2 diabetes mellitus'),('diabetes-type-ii',1,'C109J00',NULL,'Insulin treated Type 2 diabetes mellitus'),('diabetes-type-ii',1,'C109K',NULL,'Hyperosmolar non-ketotic state in type 2 diabetes mellitus'),('diabetes-type-ii',1,'C109K00',NULL,'Hyperosmolar non-ketotic state in type 2 diabetes mellitus'),('diabetes-type-ii',1,'C10D.',NULL,'Diabetes mellitus autosomal dominant type 2'),('diabetes-type-ii',1,'C10D.00',NULL,'Diabetes mellitus autosomal dominant type 2'),('diabetes-type-ii',1,'C10F.',NULL,'Type 2 diabetes mellitus'),('diabetes-type-ii',1,'C10F.00',NULL,'Type 2 diabetes mellitus'),('diabetes-type-ii',1,'C10F0',NULL,'Type 2 diabetes mellitus with renal complications'),('diabetes-type-ii',1,'C10F000',NULL,'Type 2 diabetes mellitus with renal complications'),('diabetes-type-ii',1,'C10F1',NULL,'Type 2 diabetes mellitus with ophthalmic complications'),('diabetes-type-ii',1,'C10F100',NULL,'Type 2 diabetes mellitus with ophthalmic complications'),('diabetes-type-ii',1,'C10F2',NULL,'Type 2 diabetes mellitus with neurological complications'),('diabetes-type-ii',1,'C10F200',NULL,'Type 2 diabetes mellitus with neurological complications'),('diabetes-type-ii',1,'C10F3',NULL,'Type 2 diabetes mellitus with multiple complications'),('diabetes-type-ii',1,'C10F300',NULL,'Type 2 diabetes mellitus with multiple complications'),('diabetes-type-ii',1,'C10F4',NULL,'Type 2 diabetes mellitus with ulcer'),('diabetes-type-ii',1,'C10F400',NULL,'Type 2 diabetes mellitus with ulcer'),('diabetes-type-ii',1,'C10F5',NULL,'Type 2 diabetes mellitus with gangrene'),('diabetes-type-ii',1,'C10F500',NULL,'Type 2 diabetes mellitus with gangrene'),('diabetes-type-ii',1,'C10F6',NULL,'Type 2 diabetes mellitus with retinopathy'),('diabetes-type-ii',1,'C10F600',NULL,'Type 2 diabetes mellitus with retinopathy'),('diabetes-type-ii',1,'C10F7',NULL,'Type 2 diabetes mellitus - poor control'),('diabetes-type-ii',1,'C10F700',NULL,'Type 2 diabetes mellitus - poor control'),('diabetes-type-ii',1,'C10F9',NULL,'Type 2 diabetes mellitus without complication'),('diabetes-type-ii',1,'C10F900',NULL,'Type 2 diabetes mellitus without complication'),('diabetes-type-ii',1,'C10FA',NULL,'Type 2 diabetes mellitus with mononeuropathy'),('diabetes-type-ii',1,'C10FA00',NULL,'Type 2 diabetes mellitus with mononeuropathy'),('diabetes-type-ii',1,'C10FB',NULL,'Type 2 diabetes mellitus with polyneuropathy'),('diabetes-type-ii',1,'C10FB00',NULL,'Type 2 diabetes mellitus with polyneuropathy'),('diabetes-type-ii',1,'C10FC',NULL,'Type 2 diabetes mellitus with nephropathy'),('diabetes-type-ii',1,'C10FC00',NULL,'Type 2 diabetes mellitus with nephropathy'),('diabetes-type-ii',1,'C10FD',NULL,'Type 2 diabetes mellitus with hypoglycaemic coma'),('diabetes-type-ii',1,'C10FD00',NULL,'Type 2 diabetes mellitus with hypoglycaemic coma'),('diabetes-type-ii',1,'C10FE',NULL,'Type 2 diabetes mellitus with diabetic cataract'),('diabetes-type-ii',1,'C10FE00',NULL,'Type 2 diabetes mellitus with diabetic cataract'),('diabetes-type-ii',1,'C10FF',NULL,'Type 2 diabetes mellitus with peripheral angiopathy'),('diabetes-type-ii',1,'C10FF00',NULL,'Type 2 diabetes mellitus with peripheral angiopathy'),('diabetes-type-ii',1,'C10FG',NULL,'Type 2 diabetes mellitus with arthropathy'),('diabetes-type-ii',1,'C10FG00',NULL,'Type 2 diabetes mellitus with arthropathy'),('diabetes-type-ii',1,'C10FH',NULL,'Type 2 diabetes mellitus with neuropathic arthropathy'),('diabetes-type-ii',1,'C10FH00',NULL,'Type 2 diabetes mellitus with neuropathic arthropathy'),('diabetes-type-ii',1,'C10FJ',NULL,'Insulin treated Type 2 diabetes mellitus'),('diabetes-type-ii',1,'C10FJ00',NULL,'Insulin treated Type 2 diabetes mellitus'),('diabetes-type-ii',1,'C10FK',NULL,'Hyperosmolar non-ketotic state in type 2 diabetes mellitus'),('diabetes-type-ii',1,'C10FK00',NULL,'Hyperosmolar non-ketotic state in type 2 diabetes mellitus'),('diabetes-type-ii',1,'C10FL',NULL,'Type 2 diabetes mellitus with persistent proteinuria'),('diabetes-type-ii',1,'C10FL00',NULL,'Type 2 diabetes mellitus with persistent proteinuria'),('diabetes-type-ii',1,'C10FM',NULL,'Type 2 diabetes mellitus with persistent microalbuminuria'),('diabetes-type-ii',1,'C10FM00',NULL,'Type 2 diabetes mellitus with persistent microalbuminuria'),('diabetes-type-ii',1,'C10FN',NULL,'Type 2 diabetes mellitus with ketoacidosis'),('diabetes-type-ii',1,'C10FN00',NULL,'Type 2 diabetes mellitus with ketoacidosis'),('diabetes-type-ii',1,'C10FP',NULL,'Type 2 diabetes mellitus with ketoacidotic coma'),('diabetes-type-ii',1,'C10FP00',NULL,'Type 2 diabetes mellitus with ketoacidotic coma'),('diabetes-type-ii',1,'C10FQ',NULL,'Type 2 diabetes mellitus with exudative maculopathy'),('diabetes-type-ii',1,'C10FQ00',NULL,'Type 2 diabetes mellitus with exudative maculopathy'),
('diabetes-type-ii',1,'C10FR',NULL,'Type 2 diabetes mellitus with gastroparesis'),('diabetes-type-ii',1,'C10FR00',NULL,'Type 2 diabetes mellitus with gastroparesis'),('diabetes-type-ii',1,'C10y1',NULL,'Diabetes mellitus, adult onset, with other specified manifestation'),('diabetes-type-ii',1,'C10y100',NULL,'Diabetes mellitus, adult onset, with other specified manifestation'),('diabetes-type-ii',1,'C10z1',NULL,'Diabetes mellitus, adult onset, with unspecified complication'),('diabetes-type-ii',1,'C10z100',NULL,'Diabetes mellitus, adult onset, with unspecified complication');
INSERT INTO #codesreadv2
VALUES ('hypertension',1,'G2...',NULL,'Hypertensive disease'),('hypertension',1,'G2...00',NULL,'Hypertensive disease'),('hypertension',1,'G2z..',NULL,'Hypertensive disease NOS'),('hypertension',1,'G2z..00',NULL,'Hypertensive disease NOS'),('hypertension',1,'G2y..',NULL,'Other specified hypertensive disease'),('hypertension',1,'G2y..00',NULL,'Other specified hypertensive disease'),('hypertension',1,'G28..',NULL,'Stage 2 hypertension (NICE - National Institute for Health and Clinical Excellence 2011)'),('hypertension',1,'G28..00',NULL,'Stage 2 hypertension (NICE - National Institute for Health and Clinical Excellence 2011)'),('hypertension',1,'G26..',NULL,'Severe hypertension (NICE - National Institute for Health and Clinical Excellence 2011)'),('hypertension',1,'G26..00',NULL,'Severe hypertension (NICE - National Institute for Health and Clinical Excellence 2011)'),('hypertension',1,'G25..',NULL,'Stage 1 hypertension (NICE - National Institute for Health and Clinical Excellence 2011)'),('hypertension',1,'G25..00',NULL,'Stage 1 hypertension (NICE - National Institute for Health and Clinical Excellence 2011)'),('hypertension',1,'G251.',NULL,'Stage 1 hypertension (NICE 2011) with evidence of end organ damage'),('hypertension',1,'G251.00',NULL,'Stage 1 hypertension (NICE 2011) with evidence of end organ damage'),('hypertension',1,'G250.',NULL,'Stage 1 hypertension (NICE 2011) without evidence of end organ damage'),('hypertension',1,'G250.00',NULL,'Stage 1 hypertension (NICE 2011) without evidence of end organ damage'),('hypertension',1,'G24..',NULL,'Secondary hypertension'),('hypertension',1,'G24..00',NULL,'Secondary hypertension'),('hypertension',1,'G24z.',NULL,'Secondary hypertension NOS'),('hypertension',1,'G24z.00',NULL,'Secondary hypertension NOS'),('hypertension',1,'G24zz',NULL,'Secondary hypertension NOS'),('hypertension',1,'G24zz00',NULL,'Secondary hypertension NOS'),('hypertension',1,'G24z0',NULL,'Secondary renovascular hypertension NOS'),('hypertension',1,'G24z000',NULL,'Secondary renovascular hypertension NOS'),('hypertension',1,'G244.',NULL,'Hypertension secondary to endocrine disorders'),('hypertension',1,'G244.00',NULL,'Hypertension secondary to endocrine disorders'),('hypertension',1,'G241.',NULL,'Secondary benign hypertension'),('hypertension',1,'G241.00',NULL,'Secondary benign hypertension'),('hypertension',1,'G241z',NULL,'Secondary benign hypertension NOS'),('hypertension',1,'G241z00',NULL,'Secondary benign hypertension NOS'),('hypertension',1,'G2410',NULL,'Secondary benign renovascular hypertension'),('hypertension',1,'G241000',NULL,'Secondary benign renovascular hypertension'),('hypertension',1,'G240.',NULL,'Secondary malignant hypertension'),('hypertension',1,'G240.00',NULL,'Secondary malignant hypertension'),('hypertension',1,'G240z',NULL,'Secondary malignant hypertension NOS'),('hypertension',1,'G240z00',NULL,'Secondary malignant hypertension NOS'),('hypertension',1,'G2400',NULL,'Secondary malignant renovascular hypertension'),('hypertension',1,'G240000',NULL,'Secondary malignant renovascular hypertension'),('hypertension',1,'G20..',NULL,'Essential hypertension'),('hypertension',1,'G20..00',NULL,'Essential hypertension'),('hypertension',1,'G20z.',NULL,'Essential hypertension NOS'),('hypertension',1,'G20z.00',NULL,'Essential hypertension NOS'),('hypertension',1,'G203.',NULL,'Diastolic hypertension'),('hypertension',1,'G203.00',NULL,'Diastolic hypertension'),('hypertension',1,'G202.',NULL,'Systolic hypertension'),('hypertension',1,'G202.00',NULL,'Systolic hypertension'),('hypertension',1,'G201.',NULL,'Benign essential hypertension'),('hypertension',1,'G201.00',NULL,'Benign essential hypertension'),('hypertension',1,'G200.',NULL,'Malignant essential hypertension'),('hypertension',1,'G200.00',NULL,'Malignant essential hypertension'),('hypertension',1,'Gyu2.',NULL,'[X]Hypertensive diseases'),('hypertension',1,'Gyu2.00',NULL,'[X]Hypertensive diseases'),('hypertension',1,'Gyu21',NULL,'[X]Hypertension secondary to other renal disorders'),('hypertension',1,'Gyu2100',NULL,'[X]Hypertension secondary to other renal disorders'),('hypertension',1,'Gyu20',NULL,'[X]Other secondary hypertension'),('hypertension',1,'Gyu2000',NULL,'[X]Other secondary hypertension');
INSERT INTO #codesreadv2
VALUES ('stroke',1,'G602.',NULL,'Subarachnoid haemorrhage from middle cerebral artery'),('stroke',1,'G602.00',NULL,'Subarachnoid haemorrhage from middle cerebral artery'),('stroke',1,'G61..',NULL,'Intracerebral haemorrhage'),('stroke',1,'G61..00',NULL,'Intracerebral haemorrhage'),('stroke',1,'G610.',NULL,'Cortical haemorrhage'),('stroke',1,'G610.00',NULL,'Cortical haemorrhage'),('stroke',1,'G611.',NULL,'Internal capsule haemorrhage'),('stroke',1,'G611.00',NULL,'Internal capsule haemorrhage'),('stroke',1,'G612.',NULL,'Basal nucleus haemorrhage'),('stroke',1,'G612.00',NULL,'Basal nucleus haemorrhage'),('stroke',1,'G613.',NULL,'Cerebellar haemorrhage'),('stroke',1,'G613.00',NULL,'Cerebellar haemorrhage'),('stroke',1,'G614.',NULL,'Pontine haemorrhage'),('stroke',1,'G614.00',NULL,'Pontine haemorrhage'),('stroke',1,'G615.',NULL,'Bulbar haemorrhage'),('stroke',1,'G615.00',NULL,'Bulbar haemorrhage'),('stroke',1,'G616.',NULL,'External capsule haemorrhage'),('stroke',1,'G616.00',NULL,'External capsule haemorrhage'),('stroke',1,'G618.',NULL,'Intracerebral haemorrhage, multiple localized'),('stroke',1,'G618.00',NULL,'Intracerebral haemorrhage, multiple localized'),('stroke',1,'G619.',NULL,'Lobar cerebral haemorrhage'),('stroke',1,'G619.00',NULL,'Lobar cerebral haemorrhage'),('stroke',1,'G61X.',NULL,'Intracerebral haemorrhage in hemisphere, unspecified'),('stroke',1,'G61X.00',NULL,'Intracerebral haemorrhage in hemisphere, unspecified'),('stroke',1,'G61X0',NULL,'Left sided intracerebral haemorrhage, unspecified'),('stroke',1,'G61X000',NULL,'Left sided intracerebral haemorrhage, unspecified'),('stroke',1,'G61X1',NULL,'Right sided intracerebral haemorrhage, unspecified'),('stroke',1,'G61X100',NULL,'Right sided intracerebral haemorrhage, unspecified'),('stroke',1,'G61z.',NULL,'Intracerebral haemorrhage NOS'),('stroke',1,'G61z.00',NULL,'Intracerebral haemorrhage NOS'),('stroke',1,'G63..','11','Infarction - precerebral'),('stroke',1,'G63..','11','Infarction - precerebral'),('stroke',1,'G63y0',NULL,'Cerebral infarct due to thrombosis of precerebral arteries'),('stroke',1,'G63y000',NULL,'Cerebral infarct due to thrombosis of precerebral arteries'),('stroke',1,'G63y1',NULL,'Cerebral infarction due to embolism of precerebral arteries'),('stroke',1,'G63y100',NULL,'Cerebral infarction due to embolism of precerebral arteries'),('stroke',1,'G64..',NULL,'Cerebral arterial occlusion'),('stroke',1,'G64..00',NULL,'Cerebral arterial occlusion'),('stroke',1,'G640.',NULL,'Cerebral thrombosis'),('stroke',1,'G640.00',NULL,'Cerebral thrombosis'),('stroke',1,'G6400',NULL,'Cerebral infarction due to thrombosis of cerebral arteries'),('stroke',1,'G640000',NULL,'Cerebral infarction due to thrombosis of cerebral arteries'),('stroke',1,'G641.',NULL,'Cerebral embolism'),('stroke',1,'G641.00',NULL,'Cerebral embolism'),('stroke',1,'G6410',NULL,'Cerebral infarction due to embolism of cerebral arteries'),('stroke',1,'G641000',NULL,'Cerebral infarction due to embolism of cerebral arteries'),('stroke',1,'G64z.',NULL,'Cerebral infarction NOS'),('stroke',1,'G64z.00',NULL,'Cerebral infarction NOS'),('stroke',1,'G64z0',NULL,'Brainstem infarction'),('stroke',1,'G64z000',NULL,'Brainstem infarction'),('stroke',1,'G64z1',NULL,'Wallenberg syndrome'),('stroke',1,'G64z100',NULL,'Wallenberg syndrome'),('stroke',1,'G64z2',NULL,'Left sided cerebral infarction'),('stroke',1,'G64z200',NULL,'Left sided cerebral infarction'),('stroke',1,'G64z3',NULL,'Right sided cerebral infarction'),('stroke',1,'G64z300',NULL,'Right sided cerebral infarction'),('stroke',1,'G64z4',NULL,'Infarction of basal ganglia'),('stroke',1,'G64z400',NULL,'Infarction of basal ganglia'),('stroke',1,'G650.',NULL,'Basilar artery syndrome'),('stroke',1,'G650.00',NULL,'Basilar artery syndrome'),('stroke',1,'G6510',NULL,'Vertebro-basilar artery syndrome'),('stroke',1,'G651000',NULL,'Vertebro-basilar artery syndrome'),('stroke',1,'G66..',NULL,'Stroke and cerebrovascular accident unspecified'),('stroke',1,'G66..00',NULL,'Stroke and cerebrovascular accident unspecified'),('stroke',1,'G660.',NULL,'Middle cerebral artery syndrome'),('stroke',1,'G660.00',NULL,'Middle cerebral artery syndrome'),('stroke',1,'G661.',NULL,'Anterior cerebral artery syndrome'),('stroke',1,'G661.00',NULL,'Anterior cerebral artery syndrome'),('stroke',1,'G662.',NULL,'Posterior cerebral artery syndrome'),('stroke',1,'G662.00',NULL,'Posterior cerebral artery syndrome'),('stroke',1,'G663.',NULL,'Brain stem stroke syndrome'),('stroke',1,'G663.00',NULL,'Brain stem stroke syndrome'),('stroke',1,'G664.',NULL,'Cerebellar stroke syndrome'),('stroke',1,'G664.00',NULL,'Cerebellar stroke syndrome'),('stroke',1,'G665.',NULL,'Pure motor lacunar syndrome'),('stroke',1,'G665.00',NULL,'Pure motor lacunar syndrome'),('stroke',1,'G666.',NULL,'Pure sensory lacunar syndrome'),('stroke',1,'G666.00',NULL,'Pure sensory lacunar syndrome'),('stroke',1,'G667.',NULL,'Left sided CVA'),('stroke',1,'G667.00',NULL,'Left sided CVA'),('stroke',1,'G668.',NULL,'Right sided CVA'),('stroke',1,'G668.00',NULL,'Right sided CVA'),('stroke',1,'G6760',NULL,'Cerebral infarction due to cerebral venous thrombosis, nonpyogenic'),('stroke',1,'G676000',NULL,'Cerebral infarction due to cerebral venous thrombosis, nonpyogenic'),('stroke',1,'G6W..',NULL,'Cerebral infarction due to unspecified occlusion or stenosis of precerebral arteries'),('stroke',1,'G6W..00',NULL,'Cerebral infarction due to unspecified occlusion or stenosis of precerebral arteries'),('stroke',1,'G6X..',NULL,'Cerebral infarction due to unspecified occlusion or stenosis of cerebral arteries'),('stroke',1,'G6X..00',NULL,'Cerebral infarction due to unspecified occlusion or stenosis of cerebral arteries'),('stroke',1,'Gyu62',NULL,'[X]Other intracerebral haemorrhage'),('stroke',1,'Gyu6200',NULL,'[X]Other intracerebral haemorrhage'),('stroke',1,'Gyu63',NULL,'[X]Cerebral infarction due to unspecified occlusion or stenosis of cerebral arteries'),('stroke',1,'Gyu6300',NULL,'[X]Cerebral infarction due to unspecified occlusion or stenosis of cerebral arteries'),('stroke',1,'Gyu64',NULL,'[X]Other cerebral infarction'),('stroke',1,'Gyu6400',NULL,'[X]Other cerebral infarction'),('stroke',1,'Gyu65',NULL,'[X]Occlusion and stenosis of other precerebral arteries'),('stroke',1,'Gyu6500',NULL,'[X]Occlusion and stenosis of other precerebral arteries'),('stroke',1,'Gyu66',NULL,'[X]Occlusion and stenosis of other cerebral arteries'),('stroke',1,'Gyu6600',NULL,'[X]Occlusion and stenosis of other cerebral arteries'),('stroke',1,'Gyu6F',NULL,'[X]Intracerebral haemorrhage in hemisphere, unspecified'),('stroke',1,'Gyu6F00',NULL,'[X]Intracerebral haemorrhage in hemisphere, unspecified'),('stroke',1,'Gyu6G',NULL,'[X]Cerebral infarction due to unspecified occlusion or stenosis of precerebral arteries'),('stroke',1,'Gyu6G00',NULL,'[X]Cerebral infarction due to unspecified occlusion or stenosis of precerebral arteries');
INSERT INTO #codesreadv2
VALUES ('bmi',2,'22K..',NULL,'Body Mass Index'),('bmi',2,'22K..00',NULL,'Body Mass Index');
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
VALUES ('smoking-status-trivial',1,'1372.',NULL,'Trivial smoker - < 1 cig/day'),('smoking-status-trivial',1,'1372.00',NULL,'Trivial smoker - < 1 cig/day');
INSERT INTO #codesreadv2
VALUES ('covid-vaccination',1,'65F0.',NULL,'2019-nCoV (novel coronavirus) vaccination'),('covid-vaccination',1,'65F0.00',NULL,'2019-nCoV (novel coronavirus) vaccination'),('covid-vaccination',1,'65F01',NULL,'Administration of first dose of SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) vaccine'),('covid-vaccination',1,'65F0100',NULL,'Administration of first dose of SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) vaccine'),('covid-vaccination',1,'65F02',NULL,'2019-nCoV (novel coronavirus) vaccination'),('covid-vaccination',1,'65F0200',NULL,'2019-nCoV (novel coronavirus) vaccination'),('covid-vaccination',1,'65F06',NULL,'SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) vaccination'),('covid-vaccination',1,'65F0600',NULL,'SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) vaccination'),('covid-vaccination',1,'65F07',NULL,'Immunisation course to achieve immunity against SARS-CoV-2'),('covid-vaccination',1,'65F0700',NULL,'Immunisation course to achieve immunity against SARS-CoV-2'),('covid-vaccination',1,'65F08',NULL,'Immunisation course to maintain protection against SARS-CoV-2'),('covid-vaccination',1,'65F0800',NULL,'Immunisation course to maintain protection against SARS-CoV-2'),('covid-vaccination',1,'65F09',NULL,'Administration of third dose of SARS-CoV-2 vaccine'),('covid-vaccination',1,'65F0900',NULL,'Administration of third dose of SARS-CoV-2 vaccine'),('covid-vaccination',1,'65F0A',NULL,'Administration of fourth dose of SARS-CoV-2 vaccine'),('covid-vaccination',1,'65F0A00',NULL,'Administration of fourth dose of SARS-CoV-2 vaccine'),('covid-vaccination',1,'9bJ..',NULL,'COVID-19 mRNA Vaccine BNT162b2 30micrograms/0.3ml dose concentrate for suspension for injection multidose vials (Pfizer-BioNTech)'),('covid-vaccination',1,'9bJ..00',NULL,'COVID-19 mRNA Vaccine BNT162b2 30micrograms/0.3ml dose concentrate for suspension for injection multidose vials (Pfizer-BioNTech)');
INSERT INTO #codesreadv2
VALUES ('covid-positive-pcr-test',1,'4J3R6',NULL,'SARS-CoV-2 RNA pos lim detect'),('covid-positive-pcr-test',1,'4J3R600',NULL,'SARS-CoV-2 RNA pos lim detect'),('covid-positive-pcr-test',1,'A7952',NULL,'COVID-19 confirmed by laboratory test'),('covid-positive-pcr-test',1,'A795200',NULL,'COVID-19 confirmed by laboratory test'),('covid-positive-pcr-test',1,'43hF.',NULL,'Detection of SARS-CoV-2 by PCR'),('covid-positive-pcr-test',1,'43hF.00',NULL,'Detection of SARS-CoV-2 by PCR');
INSERT INTO #codesreadv2
VALUES ('covid-positive-test-other',1,'4J3R1',NULL,'2019-nCoV (novel coronavirus) detected'),('covid-positive-test-other',1,'4J3R100',NULL,'2019-nCoV (novel coronavirus) detected')

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
VALUES ('asthma',1,'14B4.',NULL,'H/O: asthma'),('asthma',1,'8H2P.',NULL,'Emergency admission, asthma'),('asthma',1,'H33..',NULL,'Asthma'),('asthma',1,'173A.',NULL,'Exercise-induced asthma'),('asthma',1,'H330.',NULL,'Asthma: [extrins - atop][allerg][pollen][childh][+ hay fev]'),('asthma',1,'H3300',NULL,'(Hay fever + asthma) or (extr asthma without status asthmat)'),('asthma',1,'H331.',NULL,'(Intrinsic asthma) or (late onset asthma)'),('asthma',1,'H332.',NULL,'Mixed asthma'),('asthma',1,'H33z.',NULL,'Asthma unspecified'),('asthma',1,'XE0YX',NULL,'Asthma NOS'),('asthma',1,'H33z0',NULL,'(Severe asthma attack) or (status asthmaticus NOS)'),('asthma',1,'H33zz',NULL,'(Asthma:[exerc ind][allerg NEC][NOS]) or (allerg bronch NEC)'),('asthma',1,'Ua1AX',NULL,'Brittle asthma'),('asthma',1,'X101t',NULL,'Childhood asthma'),('asthma',1,'X101u',NULL,'Late onset asthma'),('asthma',1,'X101x',NULL,'Allergic asthma'),('asthma',1,'XE0YQ',NULL,'Allergic atopic asthma'),('asthma',1,'XE0ZP',NULL,'Extrinsic asthma - atopy (& pollen)'),('asthma',1,'X1021',NULL,'Allergic non-atopic asthma'),('asthma',1,'H330z',NULL,'Extrinsic asthma NOS'),('asthma',1,'X101y',NULL,'Extrinsic asthma with asthma attack'),('asthma',1,'X101z',NULL,'Allergic asthma NEC'),('asthma',1,'XE0YR',NULL,'Extrinsic asthma without status asthmaticus'),('asthma',1,'XE0YS',NULL,'Extrinsic asthma with status asthmaticus'),('asthma',1,'X1023',NULL,'Drug-induced asthma'),('asthma',1,'XaJFG',NULL,'Aspirin-induced asthma'),('asthma',1,'X1024',NULL,'Aspirin-sensitive asthma with nasal polyps'),('asthma',1,'X1025',NULL,'Occupational asthma'),('asthma',1,'H47y0',NULL,'Detergent asthma'),('asthma',1,'X1026',NULL,'Bakers asthma'),('asthma',1,'X1027',NULL,'Colophony asthma'),('asthma',1,'X1028',NULL,'Grain workers asthma'),('asthma',1,'X1029',NULL,'Sulphite-induced asthma'),('asthma',1,'XE0YT',NULL,'Non-allergic asthma'),('asthma',1,'H3310',NULL,'Intrinsic asthma without status asthmaticus'),('asthma',1,'H331z',NULL,'Intrinsic asthma NOS'),('asthma',1,'X1022',NULL,'Intrinsic asthma with asthma attack'),('asthma',1,'XE0YU',NULL,'Intrinsic asthma with status asthmaticus'),('asthma',1,'H3311',NULL,'Intrins asthma with: [asthma attack] or [status asthmaticus]'),('asthma',1,'XE0YW',NULL,'Asthma attack'),('asthma',1,'XM0s2',NULL,'Asthma attack NOS'),('asthma',1,'H3301',NULL,'Extrins asthma with: [asthma attack] or [status asthmaticus]'),('asthma',1,'H33z1',NULL,'Asthma attack (& NOS)'),('asthma',1,'XE0ZR',NULL,'Asthma: [intrinsic] or [late onset]'),('asthma',1,'XE0ZT',NULL,'Asthma: [NOS] or [attack]'),('asthma',1,'Xa0lZ',NULL,'Asthmatic bronchitis'),('asthma',1,'H3120',NULL,'Chronic asthmatic bronchitis'),('asthma',1,'Xa1hD',NULL,'Exacerbation of asthma'),('asthma',1,'Xa9zf',NULL,'Acute asthma'),('asthma',1,'X102D',NULL,'Status asthmaticus'),('asthma',1,'XE0YV',NULL,'Status asthmaticus NOS'),('asthma',1,'XaKdk',NULL,'Work aggravated asthma'),('asthma',1,'XaLPE',NULL,'Nocturnal asthma'),('asthma',1,'Xaa7B',NULL,'Chronic asthma with fixed airflow obstruction'),('asthma',1,'XaIuG',NULL,'Asthma confirmed'),('asthma',1,'Xac33',NULL,'Asthma-chronic obstructive pulmonary disease overlap syndrom'),('asthma',1,'663V2',NULL,'Moderate asthma'),('asthma',1,'663V3',NULL,'Severe asthma'),('asthma',1,'X1020',NULL,'Hay fever with asthma'),('asthma',1,'Xafdj',NULL,'Acute severe exacerbation of asthma'),('asthma',1,'Xafdy',NULL,'Moderate acute exacerbation of asthma');
INSERT INTO #codesctv3
VALUES ('copd',1,'H3...',NULL,'COPD - Chronic obstructive pulmonary disease'),('copd',1,'H31..',NULL,'Chronic bronchitis'),('copd',1,'H310.',NULL,'Simple chronic bronchitis'),('copd',1,'H310z',NULL,'Simple chronic bronchitis NOS'),('copd',1,'H311.',NULL,'Mucopurulent chronic bronchitis'),('copd',1,'H311z',NULL,'Mucopurulent chronic bronchitis NOS'),('copd',1,'H3120',NULL,'Chronic asthmatic bronchitis'),('copd',1,'H3121',NULL,'Emphysematous bronchitis'),('copd',1,'H3122',NULL,'Acute exacerbation of chronic bronchitis'),('copd',1,'H312z',NULL,'Obstructive chronic bronchitis NOS'),('copd',1,'H313.',NULL,'Mixed simple and mucopurulent chronic bronchitis'),('copd',1,'H31y.',NULL,'Other chronic bronchitis'),('copd',1,'H31y1',NULL,'Chronic tracheobronchitis'),('copd',1,'H31yz',NULL,'Other chronic bronchitis NOS'),('copd',1,'H31z.',NULL,'Chronic bronchitis NOS'),('copd',1,'H32..',NULL,'Emphysema'),('copd',1,'H320.',NULL,'Chronic bullous emphysema'),('copd',1,'H3200',NULL,'Segmental bullous emphysema'),('copd',1,'H3201',NULL,'Zonal bullous emphysema'),('copd',1,'H3202',NULL,'Giant bullous emphysema'),('copd',1,'H320z',NULL,'Chronic bullous emphysema NOS'),('copd',1,'H321.',NULL,'Panlobular emphysema'),('copd',1,'H322.',NULL,'Centrilobular emphysema'),('copd',1,'H32y.',NULL,'Other emphysema'),('copd',1,'H32y0',NULL,'Acute vesicular emphysema'),('copd',1,'H32y2',NULL,'MacLeods unilateral emphysema'),('copd',1,'H32z.',NULL,'Emphysema NOS'),('copd',1,'H3y..',NULL,'Other specified chronic obstructive pulmonary disease'),('copd',1,'H3y0.',NULL,'Chronic obstructive pulmonary disease with acute lower respiratory infection'),('copd',1,'H3z..',NULL,'Chronic obstructive pulmonary disease NOS'),('copd',1,'H4640',NULL,'Chronic emphysema due to chemical fumes'),('copd',1,'H4641',NULL,'Chemical bronchiolitis obliterans'),('copd',1,'H581.',NULL,'(Emphysema: [interstitial] or [mediastinal]) or (pneumomediastinum)'),('copd',1,'Hyu30',NULL,'[X]Other emphysema'),('copd',1,'Hyu31',NULL,'[X]Other specified chronic obstructive pulmonary disease'),('copd',1,'X00Zc',NULL,'Orbital emphysema'),('copd',1,'X101i',NULL,'Chronic obstructive pulmonary disease with acute exacerbation, unspecified'),('copd',1,'X101l',NULL,'Obliterative bronchiolitis'),('copd',1,'X101m',NULL,'Drug-induced bronchiolitis obliterans'),('copd',1,'X101n',NULL,'Pulmonary emphysema'),('copd',1,'X101o',NULL,'Pulmonary emphysema in alpha-1 PI deficiency'),('copd',1,'X101p',NULL,'Toxic emphysema'),('copd',1,'X101q',NULL,'CLE - Congenital lobar emphysema'),('copd',1,'X101r',NULL,'Scar emphysema'),('copd',1,'X102z',NULL,'Bronchiolitis obliterans with usual interstitial pneumonitis'),('copd',1,'XE0YM',NULL,'Purulent chronic bronchitis'),('copd',1,'XE0YN',NULL,'Bullous emphysema with collapse'),('copd',1,'XE0YO',NULL,'Atrophic (senile) emphysema'),('copd',1,'XE0YP',NULL,'Other emphysema NOS'),('copd',1,'XE0ZN',NULL,'Tracheobronchitis - chronic'),('copd',1,'Xa35l',NULL,'Acute infective exacerbation of chronic obstructive airways disease'),('copd',1,'XaEIV',NULL,'Mild chronic obstructive pulmonary disease'),('copd',1,'XaEIW',NULL,'Moderate chronic obstructive pulmonary disease'),('copd',1,'XaEIY',NULL,'Severe chronic obstructive pulmonary disease'),('copd',1,'XaIND',NULL,'End stage chronic obstructive airways disease'),('copd',1,'XaIQg',NULL,'Interstitial pulmonary emphysema'),('copd',1,'XaJFu',NULL,'Admit COPD emergency'),('copd',1,'XaK8Q',NULL,'Chronic obstructive pulmonary disease finding'),('copd',1,'XaN4a',NULL,'Very severe chronic obstructive pulmonary disease'),('copd',1,'XaPZH',NULL,'Chronic obstructive pulmonary disease patient unsuitable for pulmonary rehabilitation'),('copd',1,'XaZd1',NULL,'Acute non-infective exacerbation of COPD (chronic obstructive pulmonary disease)'),('copd',1,'Xaa7C',NULL,'Eosinophilic bronchitis'),('copd',1,'Xac33',NULL,'Asthma-chronic obstructive pulmonary disease overlap syndrome');
INSERT INTO #codesctv3
VALUES ('coronary-heart-disease',1,'CTV3ID',NULL,'Description'),('coronary-heart-disease',1,'XaG1Q',NULL,'Asymptomatic coronary heart disease'),('coronary-heart-disease',1,'XE2uV',NULL,'Ischaemic heart disease'),('coronary-heart-disease',1,'G3...',NULL,'Ischaemic heart disease (& [arteriosclerotic])'),('coronary-heart-disease',1,'G30..',NULL,'MI - acute myocardial infarction'),('coronary-heart-disease',1,'X200d',NULL,'Ventricular septal defect as current complication following acute myocardial infarction'),('coronary-heart-disease',1,'X200e',NULL,'Cardiac rupture after acute myocardial infarction'),('coronary-heart-disease',1,'G3110',NULL,'Coronary thrombosis not leading to myocardial infarction'),('coronary-heart-disease',1,'G312.',NULL,'Coronary thrombosis not resulting in myocardial infarction'),('coronary-heart-disease',1,'X200E',NULL,'Myocardial infarction'),('coronary-heart-disease',1,'G33..',NULL,'Angina'),('coronary-heart-disease',1,'X200B',NULL,'Angina pectoris with documented spasm'),('coronary-heart-disease',1,'XaINF',NULL,'Acute coronary syndrome'),('coronary-heart-disease',1,'G3400',NULL,'Single coronary vessel disease'),('coronary-heart-disease',1,'G3401',NULL,'Two coronary vessel disease'),('coronary-heart-disease',1,'G31..',NULL,'Other acute and subacute ischaemic heart disease'),('coronary-heart-disease',1,'G34..',NULL,'Other chronic ischaemic heart disease'),('coronary-heart-disease',1,'G3y..',NULL,'Other specified ischaemic heart disease'),('coronary-heart-disease',1,'G3z..',NULL,'Ischaemic heart disease NOS'),('coronary-heart-disease',1,'G340.',NULL,'Coronary atherosclerosis'),('coronary-heart-disease',1,'G341.',NULL,'Cardiac aneurysm'),('coronary-heart-disease',1,'X2006',NULL,'Triple vessel disease of the heart'),('coronary-heart-disease',1,'X200c',NULL,'Cardiac syndrome X'),('coronary-heart-disease',1,'XE0WA',NULL,'Attack - heart'),('coronary-heart-disease',1,'G363.',NULL,'Rupture of cardiac wall without haemopericardium as current complication following acute myocardial infarction'),('coronary-heart-disease',1,'XE0Uh',NULL,'MI - Acute myocardial infarction'),('coronary-heart-disease',1,'G301.',NULL,'Other specified anterior myocardial infarction'),('coronary-heart-disease',1,'G35..',NULL,'Subsequent myocardial infarction'),('coronary-heart-disease',1,'X200a',NULL,'Silent myocardial infarction'),('coronary-heart-disease',1,'XaD2b',NULL,'Postoperative myocardial infarction'),('coronary-heart-disease',1,'XaEgZ',NULL,'Non-Q wave myocardial infarction'),('coronary-heart-disease',1,'XaIf1',NULL,'First myocardial infarction'),('coronary-heart-disease',1,'G311.',NULL,'Preinfarction syndrome'),('coronary-heart-disease',1,'G33z.',NULL,'Angina pectoris NOS'),('coronary-heart-disease',1,'Gyu30',NULL,'[X]Other forms of angina pectoris'),('coronary-heart-disease',1,'X2007',NULL,'Angina at rest'),('coronary-heart-disease',1,'X2008',NULL,'Stable angina'),('coronary-heart-disease',1,'X2009',NULL,'Unstable angina'),('coronary-heart-disease',1,'Xa7nH',NULL,'Exertional angina'),('coronary-heart-disease',1,'XaEXt',NULL,'Post infarct angina'),('coronary-heart-disease',1,'XaFsG',NULL,'Refractory angina'),('coronary-heart-disease',1,'G33z0',NULL,'Status anginosus'),('coronary-heart-disease',1,'G33z1',NULL,'Stenocardia'),('coronary-heart-disease',1,'G33z2',NULL,'Syncope anginosa'),('coronary-heart-disease',1,'G31y1',NULL,'Microinfarction of heart'),('coronary-heart-disease',1,'G31yz',NULL,'Other acute and subacute ischaemic heart disease NOS'),('coronary-heart-disease',1,'Gyu32',NULL,'[X]Other forms of acute ischaemic heart disease'),('coronary-heart-disease',1,'XE0WC',NULL,'Acute/subacute ischaemic heart disease NOS'),('coronary-heart-disease',1,'G34y.',NULL,'Other specified chronic ischaemic heart disease'),('coronary-heart-disease',1,'G34z.',NULL,'Other chronic ischaemic heart disease NOS'),('coronary-heart-disease',1,'Gyu33',NULL,'[X]Other forms of chronic ischaemic heart disease'),('coronary-heart-disease',1,'XE0WG',NULL,'Chronic ischaemic heart disease NOS'),('coronary-heart-disease',1,'G3410',NULL,'Ventricular cardiac aneurysm'),('coronary-heart-disease',1,'G3411',NULL,'Other cardiac wall aneurysm'),('coronary-heart-disease',1,'XE0Uk',NULL,'Other cardiac wall aneurysm'),('coronary-heart-disease',1,'XM1Qk',NULL,'Mural cardiac aneurysm'),('coronary-heart-disease',1,'G3413',NULL,'Acquired atrioventricular fistula of heart'),('coronary-heart-disease',1,'G341z',NULL,'Aneurysm of heart NOS'),('coronary-heart-disease',1,'XaFsH',NULL,'Transient myocardial ischaemia'),('coronary-heart-disease',1,'G31y2',NULL,'Subendocardial ischaemia'),('coronary-heart-disease',1,'G34y1',NULL,'Chronic coronary insufficiency'),('coronary-heart-disease',1,'G310.',NULL,'Dresslers syndrome'),('coronary-heart-disease',1,'G300.',NULL,'Acute anterolateral myocardial infarction'),('coronary-heart-disease',1,'G3010',NULL,'Acute anteroapical infarction'),('coronary-heart-disease',1,'G3011',NULL,'Acute anteroseptal myocardial infarction'),('coronary-heart-disease',1,'G302.',NULL,'Acute inferolateral myocardial infarction'),('coronary-heart-disease',1,'G303.',NULL,'Acute inferoposterior infarction'),('coronary-heart-disease',1,'G307.',NULL,'Acute subendocardial infarction'),('coronary-heart-disease',1,'G30y.',NULL,'Other acute myocardial infarction'),('coronary-heart-disease',1,'G30y0',NULL,'Acute atrial infarction'),('coronary-heart-disease',1,'G30y1',NULL,'Acute papillary muscle infarction'),('coronary-heart-disease',1,'G30y2',NULL,'Acute septal infarction'),('coronary-heart-disease',1,'G30z.',NULL,'Acute myocardial infarction NOS'),('coronary-heart-disease',1,'Gyu34',NULL,'[X]Acute transmural myocardial infarction of unspecified site'),('coronary-heart-disease',1,'X200K',NULL,'Acute inferior myocardial infarction'),('coronary-heart-disease',1,'X200P',NULL,'Acute lateral myocardial infarction'),('coronary-heart-disease',1,'X200S',NULL,'Acute widespread myocardial infarction'),('coronary-heart-disease',1,'X200V',NULL,'Acute posterior myocardial infarction'),('coronary-heart-disease',1,'Xa0YL',NULL,'Acute anterior myocardial infarction'),('coronary-heart-disease',1,'XaAzi',NULL,'Acute non-Q wave infarction'),('coronary-heart-disease',1,'XaIwM',NULL,'Acute ST segment elevation myocardial infarction'),('coronary-heart-disease',1,'XaIwY',NULL,'Acute non-ST segment elevation myocardial infarction'),('coronary-heart-disease',1,'XaJX0',NULL,'Acute posterolateral myocardial infarction'),('coronary-heart-disease',1,'XaAC3',NULL,'Acute Q-wave infarct'),('coronary-heart-disease',1,'G301z',NULL,'Anterior myocardial infarction NOS'),('coronary-heart-disease',1,'G350.',NULL,'Subsequent myocardial infarction of anterior wall'),('coronary-heart-disease',1,'G351.',NULL,'Subsequent myocardial infarction of inferior wall'),('coronary-heart-disease',1,'G353.',NULL,'Subsequent myocardial infarction of other sites'),('coronary-heart-disease',1,'Gyu36',NULL,'[X]Subsequent myocardial infarction of unspecified site'),('coronary-heart-disease',1,'XaD2f',NULL,'Postoperative transmural myocardial infarction of other sites'),('coronary-heart-disease',1,'XaD2g',NULL,'Postoperative transmural myocardial infarction of unspecified site'),('coronary-heart-disease',1,'XaD2h',NULL,'Postoperative subendocardial myocardial infarction'),('coronary-heart-disease',1,'XaD2i',NULL,'Postoperative myocardial infarction, unspecified'),('coronary-heart-disease',1,'X200W',NULL,'Old anterior myocardial infarction'),('coronary-heart-disease',1,'X200X',NULL,'Old inferior myocardial infarction'),('coronary-heart-disease',1,'X200Y',NULL,'Old lateral myocardial infarction'),('coronary-heart-disease',1,'X200Z',NULL,'Old posterior myocardial infarction'),('coronary-heart-disease',1,'G330.',NULL,'Angina decubitus'),('coronary-heart-disease',1,'G3300',NULL,'Nocturnal angina'),('coronary-heart-disease',1,'X200A',NULL,'New onset angina'),('coronary-heart-disease',1,'G31y0',NULL,'Acute coronary insufficiency'),('coronary-heart-disease',1,'G34yz',NULL,'Other specified chronic ischaemic heart disease NOS'),('coronary-heart-disease',1,'X200I',NULL,'Acute Q wave infarction - anterolateral'),('coronary-heart-disease',1,'X200J',NULL,'Acute non-Q wave infarction - anterolateral'),('coronary-heart-disease',1,'X200G',NULL,'Acute Q wave infarction - anteroseptal'),('coronary-heart-disease',1,'X200H',NULL,'Acute non-Q wave infarction - anteroseptal'),('coronary-heart-disease',1,'X200N',NULL,'Acute Q wave infarction - inferolateral'),('coronary-heart-disease',1,'X200O',NULL,'Acute non-Q wave infarction - inferolateral'),('coronary-heart-disease',1,'G30yz',NULL,'Other acute myocardial infarction NOS'),('coronary-heart-disease',1,'X200L',NULL,'Acute Q wave infarction - inferior'),('coronary-heart-disease',1,'X200M',NULL,'Acute non-Q wave infarction - inferior'),('coronary-heart-disease',1,'G308.',NULL,'Inferior myocardial infarction NOS'),('coronary-heart-disease',1,'XaD2e',NULL,'Postoperative transmural myocardial infarction of inferior wall'),('coronary-heart-disease',1,'X200Q',NULL,'Acute Q wave infarction - lateral'),('coronary-heart-disease',1,'X200R',NULL,'Acute non-Q wave infarction - lateral'),('coronary-heart-disease',1,'G305.',NULL,'Lateral myocardial infarction NOS'),('coronary-heart-disease',1,'X200T',NULL,'Acute Q wave infarction - widespread'),('coronary-heart-disease',1,'X200U',NULL,'Acute non-Q wave infarction - widespread'),('coronary-heart-disease',1,'G304.',NULL,'Posterior myocardial infarction NOS'),('coronary-heart-disease',1,'G306.',NULL,'True posterior myocardial infarction'),('coronary-heart-disease',1,'XaD2d',NULL,'Postoperative transmural myocardial infarction of anterior wall'),('coronary-heart-disease',1,'Gyu35',NULL,'[X]Subsequent myocardial infarction of other sites'),('coronary-heart-disease',1,'G330z',NULL,'Angina decubitus NOS'),('coronary-heart-disease',1,'G311z',NULL,'Preinfarction syndrome NOS'),
('coronary-heart-disease',1,'G360.',NULL,'Haemopericardium as current complication following acute myocardial infarction'),('coronary-heart-disease',1,'G361.',NULL,'Atrial septal defect as current complication following acute myocardial infarction'),('coronary-heart-disease',1,'XaYYq',NULL,'Coronary microvascular disease'),('coronary-heart-disease',1,'G70..',NULL,'Atherosclerotic cardiovascular disease'),('coronary-heart-disease',1,'XaBL1',NULL,'H/O: Myocardial infarction in last year'),('coronary-heart-disease',1,'14A5.',NULL,'H/O: angina pectoris'),('coronary-heart-disease',1,'XaBL2',NULL,'H/O: Angina in last year'),('coronary-heart-disease',1,'XaZKd',NULL,'H/O acute coronary syndrome'),('coronary-heart-disease',1,'XaBL4',NULL,'H/O: Treatment for ischaemic heart disease'),('coronary-heart-disease',1,'XaYWj',NULL,'Referral to coronary heart disease clinic'),('coronary-heart-disease',1,'G364.',NULL,'Rupture of chordae tendinae as current complication following acute myocardial infarction'),('coronary-heart-disease',1,'G365.',NULL,'Rupture of papillary muscle as current complication following acute myocardial infarction'),('coronary-heart-disease',1,'X00E6',NULL,'Acute arterial infarction of spinal cord'),('coronary-heart-disease',1,'Ua1eH',NULL,'Ischaemic chest pain'),('coronary-heart-disease',1,'X70MZ',NULL,'Late quaternary syphilitic coronary artery disease'),('coronary-heart-disease',1,'X203v',NULL,'Coronary artery thrombosis'),('coronary-heart-disease',1,'P6yy6',NULL,'Congenital aneurysm of heart'),('coronary-heart-disease',1,'XaJIU',NULL,'Coronary artery bypass graft occlusion');
INSERT INTO #codesctv3
VALUES ('diabetes-type-i',1,'C1000',NULL,'Diabetes mellitus, juvenile type, with no mention of complication'),('diabetes-type-i',1,'C1010',NULL,'Diabetes mellitus, juvenile type, with ketoacidosis'),('diabetes-type-i',1,'C1020',NULL,'Diabetes mellitus, juvenile type, with hyperosmolar coma'),('diabetes-type-i',1,'C1030',NULL,'Diabetes mellitus, juvenile type, with ketoacidotic coma'),('diabetes-type-i',1,'C1040',NULL,'Diabetes mellitus, juvenile type, with renal manifestation'),('diabetes-type-i',1,'C1050',NULL,'Diabetes mellitus, juvenile type, with ophthalmic manifestation'),('diabetes-type-i',1,'C1060',NULL,'Diabetes mellitus, juvenile type, with neurological manifestation'),('diabetes-type-i',1,'C1070',NULL,'Diabetes mellitus, juvenile type, with peripheral circulatory disorder'),('diabetes-type-i',1,'C1080',NULL,'Insulin-dependent diabetes mellitus with renal complications'),('diabetes-type-i',1,'C1081',NULL,'Insulin-dependent diabetes mellitus with ophthalmic complications'),('diabetes-type-i',1,'C1082',NULL,'Insulin-dependent diabetes mellitus with neurological complications'),('diabetes-type-i',1,'C1083',NULL,'Insulin-dependent diabetes mellitus with multiple complications'),('diabetes-type-i',1,'C1085',NULL,'Insulin-dependent diabetes mellitus with ulcer'),('diabetes-type-i',1,'C1086',NULL,'Insulin-dependent diabetes mellitus with gangrene'),('diabetes-type-i',1,'C1087',NULL,'IDDM - Insulin-dependent diabetes mellitus with retinopathy'),('diabetes-type-i',1,'C1088',NULL,'Insulin-dependent diabetes mellitus - poor control'),('diabetes-type-i',1,'C1089',NULL,'Insulin-dependent diabetes maturity onset'),('diabetes-type-i',1,'C10y0',NULL,'Diabetes mellitus, juvenile type, with other specified manifestation'),('diabetes-type-i',1,'C10z0',NULL,'Diabetes mellitus, juvenile type, with unspecified complication'),('diabetes-type-i',1,'X40J4',NULL,'Insulin-dependent diabetes mellitus'),('diabetes-type-i',1,'X40JY',NULL,'Congenital insulin-dependent diabetes mellitus with fatal secretory diarrhoea'),('diabetes-type-i',1,'XE10E',NULL,'Diabetes mellitus, juvenile type, with no mention of complication'),('diabetes-type-i',1,'XE12C',NULL,'Insulin dependent diabetes mel'),('diabetes-type-i',1,'XM19i',NULL,'[EDTA] Diabetes Type I (insulin dependent) associated with renal failure'),('diabetes-type-i',1,'Xa4g7',NULL,'Unstable type 1 diabetes mellitus'),('diabetes-type-i',1,'XaA6b',NULL,'Perceived control of insulin-dependent diabetes'),('diabetes-type-i',1,'XaELP',NULL,'Insulin-dependent diabetes without complication'),('diabetes-type-i',1,'XaEnn',NULL,'Type I diabetes mellitus with mononeuropathy'),('diabetes-type-i',1,'XaEno',NULL,'Insulin dependent diabetes mellitus with polyneuropathy'),('diabetes-type-i',1,'XaF04',NULL,'Type 1 diabetes mellitus with nephropathy'),('diabetes-type-i',1,'XaFWG',NULL,'Type 1 diabetes mellitus with hypoglycaemic coma'),('diabetes-type-i',1,'XaFm8',NULL,'Type 1 diabetes mellitus with diabetic cataract'),('diabetes-type-i',1,'XaFmK',NULL,'Type I diabetes mellitus with peripheral angiopathy'),('diabetes-type-i',1,'XaFmL',NULL,'Type 1 diabetes mellitus with arthropathy'),('diabetes-type-i',1,'XaFmM',NULL,'Type 1 diabetes mellitus with neuropathic arthropathy'),('diabetes-type-i',1,'XaIzM',NULL,'Type 1 diabetes mellitus with persistent proteinuria'),('diabetes-type-i',1,'XaIzN',NULL,'Type 1 diabetes mellitus with persistent microalbuminuria'),('diabetes-type-i',1,'XaJSr',NULL,'Type I diabetes mellitus with exudative maculopathy'),('diabetes-type-i',1,'XaKyW',NULL,'Type I diabetes mellitus with gastroparesis');
INSERT INTO #codesctv3
VALUES ('diabetes-type-ii',1,'C1011',NULL,'Diabetes mellitus, adult onset, with ketoacidosis'),('diabetes-type-ii',1,'C1021',NULL,'Diabetes mellitus, adult onset, with hyperosmolar coma'),('diabetes-type-ii',1,'C1031',NULL,'Diabetes mellitus, adult onset, with ketoacidotic coma'),('diabetes-type-ii',1,'C1041',NULL,'Diabetes mellitus, adult onset, with renal manifestation'),('diabetes-type-ii',1,'C1051',NULL,'Diabetes mellitus, adult onset, with ophthalmic manifestation'),('diabetes-type-ii',1,'C1061',NULL,'Diabetes mellitus, adult onset, with neurological manifestation'),('diabetes-type-ii',1,'C1071',NULL,'Diabetes mellitus, adult onset, with peripheral circulatory disorder'),('diabetes-type-ii',1,'C1090',NULL,'Non-insulin-dependent diabetes mellitus with renal complications'),('diabetes-type-ii',1,'C1091',NULL,'Non-insulin-dependent diabetes mellitus with ophthalmic complications'),('diabetes-type-ii',1,'C1092',NULL,'Non-insulin-dependent diabetes mellitus with neurological complications'),('diabetes-type-ii',1,'C1093',NULL,'Non-insulin-dependent diabetes mellitus with multiple complications'),('diabetes-type-ii',1,'C1094',NULL,'Non-insulin-dependent diabetes mellitus with ulcer'),('diabetes-type-ii',1,'C1095',NULL,'Non-insulin-dependent diabetes mellitus with gangrene'),('diabetes-type-ii',1,'C1096',NULL,'NIDDM - Non-insulin-dependent diabetes mellitus with retinopathy'),('diabetes-type-ii',1,'C1097',NULL,'Non-insulin-dependent diabetes mellitus - poor control'),('diabetes-type-ii',1,'C10y1',NULL,'Diabetes mellitus, adult onset, with other specified manifestation'),('diabetes-type-ii',1,'C10z1',NULL,'Diabetes mellitus, adult onset, with unspecified complication'),('diabetes-type-ii',1,'X40J5',NULL,'Non-insulin-dependent diabetes mellitus'),('diabetes-type-ii',1,'X40J6',NULL,'Insulin treated Type 2 diabetes mellitus'),('diabetes-type-ii',1,'X40JJ',NULL,'Diabetes mellitus autosomal dominant type 2'),('diabetes-type-ii',1,'XE10F',NULL,'Diabetes mellitus, adult onset, with no mention of complication'),('diabetes-type-ii',1,'XM19j',NULL,'[EDTA] Diabetes Type II (non-insulin-dependent) associated with renal failure'),('diabetes-type-ii',1,'XaELQ',NULL,'Non-insulin-dependent diabetes mellitus without complication'),('diabetes-type-ii',1,'XaEnp',NULL,'Type II diabetes mellitus with mononeuropathy'),('diabetes-type-ii',1,'XaEnq',NULL,'Type 2 diabetes mellitus with polyneuropathy'),('diabetes-type-ii',1,'XaF05',NULL,'Type 2 diabetes mellitus with nephropathy'),('diabetes-type-ii',1,'XaFWI',NULL,'Type II diabetes mellitus with hypoglycaemic coma'),('diabetes-type-ii',1,'XaFmA',NULL,'Type II diabetes mellitus with diabetic cataract'),('diabetes-type-ii',1,'XaFn7',NULL,'Non-insulin-dependent diabetes mellitus with peripheral angiopathy'),('diabetes-type-ii',1,'XaFn8',NULL,'Non-insulin dependent diabetes mellitus with arthropathy'),('diabetes-type-ii',1,'XaFn9',NULL,'Non-insulin dependent diabetes mellitus with neuropathic arthropathy'),('diabetes-type-ii',1,'XaIfG',NULL,'Type II diabetes on insulin'),('diabetes-type-ii',1,'XaIfI',NULL,'Type II diabetes on diet only'),('diabetes-type-ii',1,'XaIrf',NULL,'Hyperosmolar non-ketotic state in type II diabetes mellitus'),('diabetes-type-ii',1,'XaIzQ',NULL,'Type 2 diabetes mellitus with persistent proteinuria'),('diabetes-type-ii',1,'XaIzR',NULL,'Type 2 diabetes mellitus with persistent microalbuminuria'),('diabetes-type-ii',1,'XaJQp',NULL,'Type II diabetes mellitus with exudative maculopathy'),('diabetes-type-ii',1,'XaKyX',NULL,'Type II diabetes mellitus with gastroparesis');
INSERT INTO #codesctv3
VALUES ('hypertension',1,'G24..',NULL,'Secondary hypertension'),('hypertension',1,'G240.',NULL,'Malignant secondary hypertension'),('hypertension',1,'G241.',NULL,'Secondary benign hypertension'),('hypertension',1,'G244.',NULL,'Hypertension secondary to endocrine disorders'),('hypertension',1,'G24z.',NULL,'Secondary hypertension NOS'),('hypertension',1,'Gyu20',NULL,'[X]Other secondary hypertension'),('hypertension',1,'Gyu21',NULL,'[X]Hypertension secondary to other renal disorders'),('hypertension',1,'Xa0kX',NULL,'Hypertension due to renovascular disease'),('hypertension',1,'XE0Ub',NULL,'Systemic arterial hypertension'),('hypertension',1,'G2400',NULL,'Secondary malignant renovascular hypertension'),('hypertension',1,'G240z',NULL,'Secondary malignant hypertension NOS'),('hypertension',1,'G2410',NULL,'Secondary benign renovascular hypertension'),('hypertension',1,'G241z',NULL,'Secondary benign hypertension NOS'),('hypertension',1,'G24z0',NULL,'Secondary renovascular hypertension NOS'),('hypertension',1,'G20..',NULL,'Primary hypertension'),('hypertension',1,'G202.',NULL,'Systolic hypertension'),('hypertension',1,'G20z.',NULL,'Essential hypertension NOS'),('hypertension',1,'XE0Uc',NULL,'Primary hypertension'),('hypertension',1,'XE0W8',NULL,'Hypertension'),('hypertension',1,'XSDSb',NULL,'Diastolic hypertension'),('hypertension',1,'Xa0Cs',NULL,'Labile hypertension'),('hypertension',1,'Xa3fQ',NULL,'Malignant hypertension'),('hypertension',1,'XaZWm',NULL,'Stage 1 hypertension'),('hypertension',1,'XaZWn',NULL,'Severe hypertension'),('hypertension',1,'XaZbz',NULL,'Stage 2 hypertension (NICE - National Institute for Health and Clinical Excellence 2011)'),('hypertension',1,'XaZzo',NULL,'Nocturnal hypertension'),('hypertension',1,'G2...',NULL,'Hypertensive disease'),('hypertension',1,'G200.',NULL,'Malignant essential hypertension'),('hypertension',1,'G201.',NULL,'Benign essential hypertension'),('hypertension',1,'XE0Ud',NULL,'Essential hypertension NOS'),('hypertension',1,'Xa41E',NULL,'Maternal hypertension'),('hypertension',1,'Xab9L',NULL,'Stage 1 hypertension (NICE 2011) without evidence of end organ damage'),('hypertension',1,'Xab9M',NULL,'Stage 1 hypertension (NICE 2011) with evidence of end organ damage'),('hypertension',1,'G2y..',NULL,'Other specified hypertensive disease'),('hypertension',1,'G2z..',NULL,'Hypertensive disease NOS'),('hypertension',1,'Gyu2.',NULL,'[X]Hypertensive diseases'),('hypertension',1,'XM19D',NULL,'[EDTA] Renal vascular disease due to hypertension (no primary renal disease) associated with renal failure'),('hypertension',1,'XM19E',NULL,'[EDTA] Renal vascular disease due to malignant hypertension (no primary renal disease) associated with renal failure');
INSERT INTO #codesctv3
VALUES ('stroke',1,'G61..',NULL,'CVA - cerebrovascular accident due to intracerebral haemorrhage'),('stroke',1,'G610.',NULL,'Cortical haemorrhage'),('stroke',1,'G611.',NULL,'Internal capsule haemorrhage'),('stroke',1,'G612.',NULL,'Basal ganglia haemorrhage'),('stroke',1,'G613.',NULL,'Cerebellar haemorrhage'),('stroke',1,'G614.',NULL,'Pontine haemorrhage'),('stroke',1,'G615.',NULL,'Bulbar haemorrhage'),('stroke',1,'G616.',NULL,'External capsule haemorrhage'),('stroke',1,'G618.',NULL,'Intracerebral haemorrhage, multiple localised'),('stroke',1,'G61z.',NULL,'Intracerebral haemorrhage NOS'),('stroke',1,'G63..',NULL,'Infarction - precerebral'),('stroke',1,'G63y0',NULL,'Cerebral infarct due to thrombosis of precerebral arteries'),('stroke',1,'G63y1',NULL,'Cerebral infarction due to embolism of precerebral arteries'),('stroke',1,'G64..',NULL,'Infarction - cerebral'),('stroke',1,'G640.',NULL,'Cerebral thrombosis'),('stroke',1,'G6400',NULL,'Cerebral infarction due to thrombosis of cerebral arteries'),('stroke',1,'G641.',NULL,'Cerebral embolism'),('stroke',1,'G6410',NULL,'Cerebral infarction due to embolism of cerebral arteries'),('stroke',1,'G64z.',NULL,'Cerebral infarction NOS'),('stroke',1,'G650.',NULL,'Basilar artery syndrome'),('stroke',1,'G66..',NULL,'Stroke unspecified'),('stroke',1,'G660.',NULL,'Middle cerebral artery syndrome'),('stroke',1,'G661.',NULL,'Anterior cerebral artery syndrome'),('stroke',1,'G662.',NULL,'Posterior cerebral artery syndrome'),('stroke',1,'G663.',NULL,'Brainstem stroke syndrome'),('stroke',1,'G664.',NULL,'Cerebellar stroke syndrome'),('stroke',1,'G667.',NULL,'Left sided cerebral hemisphere cerebrovascular accident'),('stroke',1,'G668.',NULL,'Right sided cerebral hemisphere cerebrovascular accident'),('stroke',1,'G6760',NULL,'Cerebral infarction due to cerebral venous thrombosis, non-pyogenic'),('stroke',1,'Gyu62',NULL,'[X]Other intracerebral haemorrhage'),('stroke',1,'Gyu63',NULL,'[X]Cerebral infarction due to unspecified occlusion or stenosis of cerebral arteries'),('stroke',1,'Gyu64',NULL,'[X]Other cerebral infarction'),('stroke',1,'Gyu65',NULL,'[X]Occlusion and stenosis of other precerebral arteries'),('stroke',1,'Gyu66',NULL,'[X]Occlusion and stenosis of other cerebral arteries'),('stroke',1,'Gyu6F',NULL,'[X]Intracerebral haemorrhage in hemisphere, unspecified'),('stroke',1,'Gyu6G',NULL,'[X]Cerebral infarction due to unspecified occlusion or stenosis of precerebral arteries'),('stroke',1,'X00D1',NULL,'CVA - Cerebrovascular accident'),('stroke',1,'X00D3',NULL,'CVA - cerebrovascular accident due to cerebral artery occlusion'),('stroke',1,'X00D4',NULL,'Infarction - precerebral'),('stroke',1,'X00D5',NULL,'Anterior cerebral circulation infarction'),('stroke',1,'X00D6',NULL,'TACI - Total anterior cerebral circulation infarction'),('stroke',1,'X00D7',NULL,'Partial anterior cerebral circulation infarction'),('stroke',1,'X00D8',NULL,'Posterior cerebral circulation infarction'),('stroke',1,'X00D9',NULL,'Brainstem infarction NOS'),('stroke',1,'X00DA',NULL,'LACI - Lacunar infarction'),('stroke',1,'X00DB',NULL,'Pure motor lacunar infarction'),('stroke',1,'X00DC',NULL,'Pure sensory lacunar infarction'),('stroke',1,'X00DD',NULL,'Pure sensorimotor lacunar infarction'),('stroke',1,'X00DE',NULL,'Lacunar ataxic hemiparesis'),('stroke',1,'X00DF',NULL,'Dysarthria-clumsy hand syndrome'),('stroke',1,'X00DG',NULL,'Multi-infarct state'),('stroke',1,'X00DI',NULL,'Haemorrhagic cerebral infarction'),('stroke',1,'X00DJ',NULL,'Anterior cerebral circulation haemorrhagic infarction'),('stroke',1,'X00DK',NULL,'Posterior cerebral circulation haemorrhagic infarction'),('stroke',1,'X00DL',NULL,'Massive supratentorial cerebral haemorrhage'),('stroke',1,'X00Dm',NULL,'Cerebral venous thrombosis of cortical vein'),('stroke',1,'X00DM',NULL,'Lobar cerebral haemorrhage'),('stroke',1,'X00Dn',NULL,'Cerebral venous thrombosis of great cerebral vein'),('stroke',1,'X00DN',NULL,'Subcortical cerebral haemorrhage'),('stroke',1,'X00DO',NULL,'Thalamic haemorrhage'),('stroke',1,'X00DP',NULL,'Lacunar haemorrhage'),('stroke',1,'X00DQ',NULL,'Brainstem haemorrhage'),('stroke',1,'X00DR',NULL,'Stroke of uncertain pathology'),('stroke',1,'X00DS',NULL,'Anterior circulation stroke of uncertain pathology'),('stroke',1,'X00DT',NULL,'Posterior circulation stroke of uncertain pathology'),('stroke',1,'Xa00I',NULL,'Occipital cerebral infarction'),('stroke',1,'Xa00J',NULL,'Cerebellar infarction'),('stroke',1,'Xa00K',NULL,'Brainstem infarction'),('stroke',1,'Xa00L',NULL,'Benedict syndrome'),('stroke',1,'Xa00M',NULL,'Lateral medullary syndrome'),('stroke',1,'Xa00N',NULL,'Foville syndrome'),('stroke',1,'Xa00O',NULL,'Millard-Gubler syndrome'),('stroke',1,'Xa00P',NULL,'Weber syndrome'),('stroke',1,'Xa00Q',NULL,'Claude syndrome'),('stroke',1,'Xa00R',NULL,'Top of basilar syndrome'),('stroke',1,'Xa0Bj',NULL,'Intracerebellar and posterior fossa haemorrhage'),('stroke',1,'Xa0kZ',NULL,'CVA - Cerebral infarction'),('stroke',1,'Xa1hE',NULL,'Extension of stroke'),('stroke',1,'Xa6YV',NULL,'Embolus of circle of Willis'),('stroke',1,'XaB4Z',NULL,'Multiple lacunar infarcts'),('stroke',1,'XaBEC',NULL,'Left sided cerebral infarction'),('stroke',1,'XaBED',NULL,'Right sided cerebral infarction'),('stroke',1,'XaBM4',NULL,'Left sided intracerebral haemorrhage, unspecified'),('stroke',1,'XaBM5',NULL,'Right sided intracerebral haemorrhage, unspecified'),('stroke',1,'XaEGq',NULL,'Stroke NOS'),('stroke',1,'XaJgQ',NULL,'Infarction of basal ganglia'),('stroke',1,'XaQbK',NULL,'Pure motor lacunar syndrome'),('stroke',1,'XaQbM',NULL,'Pure sensory lacunar syndrome'),('stroke',1,'XE0VF',NULL,'Stroke due to intracerebral haemorrhage'),('stroke',1,'XE0VI',NULL,'Cerebral arterial occlusion'),('stroke',1,'XE0VJ',NULL,'Cerebral infarction NOS'),('stroke',1,'XE0Ww',NULL,'Cerebrovascular accident'),('stroke',1,'XE0Wy',NULL,'Cerebral haemorrhage NOS'),('stroke',1,'XE0X2',NULL,'Stroke/CVA - undefined'),('stroke',1,'XE2aB',NULL,'Stroke and cerebrovascular accident unspecified'),('stroke',1,'XM0rV',NULL,'Cerebral haemorrhage');
INSERT INTO #codesctv3
VALUES ('bmi',2,'22K..',NULL,'Body Mass Index');
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
VALUES ('smoking-status-trivial',1,'XagO3',NULL,'Occasional tobacco smoker'),('smoking-status-trivial',1,'XE0oi',NULL,'Triv cigaret smok, < 1 cig/day'),('smoking-status-trivial',1,'1372.',NULL,'Trivial smoker - < 1 cig/day');
INSERT INTO #codesctv3
VALUES ('covid-vaccination',1,'Y210d',NULL,'2019-nCoV (novel coronavirus) vaccination'),('covid-vaccination',1,'Y29e7',NULL,'Administration of first dose of SARS-CoV-2 vaccine'),('covid-vaccination',1,'Y29e8',NULL,'Administration of second dose of SARS-CoV-2 vaccine'),('covid-vaccination',1,'Y2a0e',NULL,'SARS-2 Coronavirus vaccine'),('covid-vaccination',1,'Y2a0f',NULL,'COVID-19 mRNA Vaccine BNT162b2 30micrograms/0.3ml dose concentrate for suspension for injection multidose vials (Pfizer-BioNTech) part 1'),('covid-vaccination',1,'Y2a3a',NULL,'COVID-19 mRNA Vaccine BNT162b2 30micrograms/0.3ml dose concentrate for suspension for injection multidose vials (Pfizer-BioNTech) part 2'),('covid-vaccination',1,'65F06',NULL,'SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) vaccination'),('covid-vaccination',1,'65F09',NULL,'Administration of third dose of SARS-CoV-2 vaccine'),('covid-vaccination',1,'65F0A',NULL,'Administration of fourth dose of SARS-CoV-2 vaccine'),('covid-vaccination',1,'9bJ..',NULL,'COVID-19 mRNA Vaccine BNT162b2 30micrograms/0.3ml dose concentrate for suspension for injection multidose vials (Pfizer-BioNTech)'),('covid-vaccination',1,'Y2a10',NULL,'COVID-19 Vac AstraZeneca (ChAdOx1 S recomb) 5x10000000000 viral particles/0.5ml dose sol for inj MDV part 1'),('covid-vaccination',1,'Y2a39',NULL,'COVID-19 Vac AstraZeneca (ChAdOx1 S recomb) 5x10000000000 viral particles/0.5ml dose sol for inj MDV part 2'),('covid-vaccination',1,'Y2b9d',NULL,'COVID-19 mRNA (nucleoside modified) Vaccine Moderna 0.1mg/0.5mL dose dispersion for injection multidose vials part 2'),('covid-vaccination',1,'Y2f45',NULL,'Administration of third dose of SARS-CoV-2 vaccine'),('covid-vaccination',1,'Y2f48',NULL,'Administration of fourth dose of SARS-CoV-2 vaccine'),('covid-vaccination',1,'Y2f57',NULL,'COVID-19 mRNA Vaccine BNT162b2 30micrograms/0.3ml dose concentrate for suspension for injection multidose vials (Pfizer-BioNTech) booster'),('covid-vaccination',1,'Y31cc',NULL,'SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) antigen vaccination'),('covid-vaccination',1,'Y31e6',NULL,'Administration of SARS-CoV-2 mRNA vaccine'),('covid-vaccination',1,'Y31e7',NULL,'Administration of first dose of SARS-CoV-2 mRNA vaccine'),('covid-vaccination',1,'Y31e8',NULL,'Administration of second dose of SARS-CoV-2 mRNA vaccine');
INSERT INTO #codesctv3
VALUES ('covid-positive-pcr-test',1,'4J3R6',NULL,'SARS-CoV-2 RNA pos lim detect'),('covid-positive-pcr-test',1,'Y240b',NULL,'Severe acute respiratory syndrome coronavirus 2 qualitative existence in specimen (observable entity)'),('covid-positive-pcr-test',1,'Y2a3b',NULL,'SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) RNA (ribonucleic acid) detection result positive'),('covid-positive-pcr-test',1,'A7952',NULL,'COVID-19 confirmed by laboratory test'),('covid-positive-pcr-test',1,'Y228d',NULL,'Coronavirus disease 19 caused by severe acute respiratory syndrome coronavirus 2 confirmed by laboratory test (situation)'),('covid-positive-pcr-test',1,'Y210e',NULL,'Detection of 2019-nCoV (novel coronavirus) using polymerase chain reaction technique'),('covid-positive-pcr-test',1,'43hF.',NULL,'Detection of SARS-CoV-2 by PCR'),('covid-positive-pcr-test',1,'Y2a3d',NULL,'SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) RNA (ribonucleic acid) detection result positive at the limit of detection');
INSERT INTO #codesctv3
VALUES ('covid-positive-test-other',1,'4J3R1',NULL,'2019-nCoV (novel coronavirus) detected'),('covid-positive-test-other',1,'Y20d1',NULL,'Confirmed 2019-nCov (Wuhan) infection'),('covid-positive-test-other',1,'Y23f7',NULL,'SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) detection result positive')

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
VALUES ('asthma',1,'304527002',NULL,'Acute asthma'),('asthma',1,'708093000',NULL,'Acute exacerbation of allergic asthma'),('asthma',1,'708038006',NULL,'Acute exacerbation of asthma'),('asthma',1,'99031000119107',NULL,'Acute exacerbation of asthma co-occurrent with allergic rhinitis'),('asthma',1,'1751000119100',NULL,'Acute exacerbation of chronic obstructive airways disease with asthma'),('asthma',1,'708094006',NULL,'Acute exacerbation of intrinsic asthma'),('asthma',1,'135181000119109',NULL,'Acute exacerbation of mild persistent asthma'),('asthma',1,'135171000119106',NULL,'Acute exacerbation of moderate persistent asthma'),('asthma',1,'708095007',NULL,'Acute severe exacerbation of allergic asthma'),('asthma',1,'708090002',NULL,'Acute severe exacerbation of asthma'),('asthma',1,'10674711000119105',NULL,'Acute severe exacerbation of asthma co-occurrent with allergic rhinitis'),('asthma',1,'708096008',NULL,'Acute severe exacerbation of intrinsic asthma'),('asthma',1,'10675911000119109',NULL,'Acute severe exacerbation of mild persistent allergic asthma'),('asthma',1,'10675991000119100',NULL,'Acute severe exacerbation of mild persistent allergic asthma co-occurrent with allergic rhinitis'),('asthma',1,'707981009',NULL,'Acute severe exacerbation of mild persistent asthma'),('asthma',1,'10676431000119103',NULL,'Acute severe exacerbation of moderate persistent allergic asthma'),('asthma',1,'707980005',NULL,'Acute severe exacerbation of moderate persistent asthma'),('asthma',1,'10676511000119109',NULL,'Acute severe exacerbation of moderate persistent asthma co-occurrent with allergic rhinitis'),('asthma',1,'10675471000119109',NULL,'Acute severe exacerbation of severe persistent allergic asthma'),('asthma',1,'707979007',NULL,'Acute severe exacerbation of severe persistent asthma'),('asthma',1,'10675551000119104',NULL,'Acute severe exacerbation of severe persistent asthma co-occurrent with allergic rhinitis'),('asthma',1,'733858005',NULL,'Acute severe refractory exacerbation of asthma'),('asthma',1,'389145006',NULL,'Allergic asthma'),('asthma',1,'703954005',NULL,'Allergic asthma due to Dermatophagoides farinae'),('asthma',1,'703953004',NULL,'Allergic asthma due to Dermatophagoides pteronyssinus'),('asthma',1,'30352005',NULL,'Allergic-infective asthma'),('asthma',1,'195967001',NULL,'Asthma'),('asthma',1,'401193004',NULL,'Asthma confirmed'),('asthma',1,'10742121000119104',NULL,'Asthma in mother complicating childbirth'),('asthma',1,'401000119107',NULL,'Asthma with irreversible airway obstruction'),('asthma',1,'55570000',NULL,'Asthma without status asthmaticus'),('asthma',1,'10692761000119107',NULL,'Asthma-chronic obstructive pulmonary disease overlap syndrome'),('asthma',1,'34015007',NULL,'Bakers asthma'),('asthma',1,'225057002',NULL,'Brittle asthma'),('asthma',1,'404806001',NULL,'Cheese-makers asthma'),('asthma',1,'92807009',NULL,'Chemical-induced asthma'),('asthma',1,'233678006',NULL,'Childhood asthma'),('asthma',1,'866881000000101',NULL,'Chronic asthma with fixed airflow obstruction'),('asthma',1,'10692721000119102',NULL,'Chronic obstructive asthma co-occurrent with acute exacerbation of asthma'),('asthma',1,'233687002',NULL,'Colophony asthma'),('asthma',1,'409663006',NULL,'Cough variant asthma'),('asthma',1,'41553006',NULL,'Detergent asthma'),('asthma',1,'93432008',NULL,'Drug-induced asthma'),('asthma',1,'183478001',NULL,'Emergency hospital admission for asthma'),('asthma',1,'281239006',NULL,'Exacerbation of asthma'),('asthma',1,'425969006',NULL,'Exacerbation of intermittent asthma'),('asthma',1,'707445000',NULL,'Exacerbation of mild persistent asthma'),('asthma',1,'707446004',NULL,'Exacerbation of moderate persistent asthma'),('asthma',1,'707447008',NULL,'Exacerbation of severe persistent asthma'),('asthma',1,'31387002',NULL,'Exercise-induced asthma'),('asthma',1,'63088003',NULL,'Extrinsic asthma without status asthmaticus'),('asthma',1,'13151001',NULL,'Flax-dressers disease'),('asthma',1,'161527007',NULL,'H/O: asthma'),('asthma',1,'233683003',NULL,'Hay fever with asthma'),('asthma',1,'424643009',NULL,'IgE-mediated allergic asthma'),('asthma',1,'427603009',NULL,'Intermittent asthma'),('asthma',1,'125021000119107',NULL,'Intermittent asthma co-occurrent with allergic rhinitis'),('asthma',1,'1741000119102',NULL,'Intermittent asthma uncontrolled'),('asthma',1,'266361008',NULL,'Intrinsic asthma'),('asthma',1,'12428000',NULL,'Intrinsic asthma without status asthmaticus'),('asthma',1,'404808000',NULL,'Isocyanate induced asthma'),('asthma',1,'233679003',NULL,'Late onset asthma'),('asthma',1,'1086701000000102',NULL,'Life threatening acute exacerbation of allergic asthma'),('asthma',1,'734904007',NULL,'Life threatening acute exacerbation of asthma'),('asthma',1,'1064821000000109',NULL,'Life threatening acute exacerbation of asthma'),('asthma',1,'1086711000000100',NULL,'Life threatening acute exacerbation of intrinsic asthma'),('asthma',1,'19849005',NULL,'Meat-wrappers asthma'),('asthma',1,'10675871000119106',NULL,'Mild persistent allergic asthma'),('asthma',1,'426979002',NULL,'Mild persistent asthma'),('asthma',1,'125011000119100',NULL,'Mild persistent asthma co-occurrent with allergic rhinitis'),('asthma',1,'11641008',NULL,'Millers asthma'),('asthma',1,'195977004',NULL,'Mixed asthma'),('asthma',1,'734905008',NULL,'Moderate acute exacerbation of asthma'),('asthma',1,'1064811000000103',NULL,'Moderate acute exacerbation of asthma'),('asthma',1,'370219009',NULL,'Moderate asthma'),('asthma',1,'10676391000119108',NULL,'Moderate persistent allergic asthma'),('asthma',1,'427295004',NULL,'Moderate persistent asthma'),('asthma',1,'125001000119103',NULL,'Moderate persistent asthma co-occurrent with allergic rhinitis'),('asthma',1,'423889005',NULL,'Non-IgE mediated allergic asthma'),('asthma',1,'57607007',NULL,'Occupational asthma'),('asthma',1,'16584951000119101',NULL,'Oral steroid-dependent asthma'),('asthma',1,'404804003',NULL,'Platinum asthma'),('asthma',1,'18041002',NULL,'Printers asthma'),('asthma',1,'445427006',NULL,'Seasonal asthma'),('asthma',1,'370221004',NULL,'Severe asthma'),('asthma',1,'10675391000119101',NULL,'Severe controlled persistent asthma'),('asthma',1,'10675431000119106',NULL,'Severe persistent allergic asthma'),('asthma',1,'426656000',NULL,'Severe persistent asthma'),('asthma',1,'124991000119109',NULL,'Severe persistent asthma co-occurrent with allergic rhinitis'),('asthma',1,'10675751000119107',NULL,'Severe uncontrolled persistent asthma'),('asthma',1,'2360001000004109',NULL,'Steroid dependent asthma'),('asthma',1,'424199006',NULL,'Substance induced asthma'),('asthma',1,'233688007',NULL,'Sulphite-induced asthma'),('asthma',1,'418395004',NULL,'Tea-makers asthma'),('asthma',1,'707444001',NULL,'Uncomplicated asthma'),('asthma',1,'707511009',NULL,'Uncomplicated mild persistent asthma'),('asthma',1,'707512002',NULL,'Uncomplicated moderate persistent asthma'),('asthma',1,'707513007',NULL,'Uncomplicated severe persistent asthma'),('asthma',1,'59786004',NULL,'Weavers cough'),('asthma',1,'56968009',NULL,'Wood asthma'),('asthma',1,'2010031000006100',NULL,'Acute infective exacerbation of asthma'),('asthma',1,'2010041000006105',NULL,'Acute non-infective exacerbation of asthma');
INSERT INTO #codessnomed
VALUES ('coronary-heart-disease',1,'snomed',NULL,'Description'),('coronary-heart-disease',1,'G3...00',NULL,'Ischaemic heart disease'),('coronary-heart-disease',1,'G3...12',NULL,'Atherosclerotic heart disease'),('coronary-heart-disease',1,'G3...13',NULL,'IHD - Ischaemic heart disease'),('coronary-heart-disease',1,'G3...11',NULL,'Arteriosclerotic heart disease'),('coronary-heart-disease',1,'G3z..00',NULL,'Ischaemic heart disease NOS'),('coronary-heart-disease',1,'G3y..00',NULL,'Other specified ischaemic heart disease'),('coronary-heart-disease',1,'G39..00',NULL,'Coronary microvascular disease'),('coronary-heart-disease',1,'G38..00',NULL,'Postoperative myocardial infarction'),('coronary-heart-disease',1,'G38z.00',NULL,'Postoperative myocardial infarction, unspecified'),('coronary-heart-disease',1,'G384.00',NULL,'Postoperative subendocardial myocardial infarction'),('coronary-heart-disease',1,'G383.00',NULL,'Postoperative transmural myocardial infarction of unspecified site'),('coronary-heart-disease',1,'G382.00',NULL,'Postoperative transmural myocardial infarction of other sites'),('coronary-heart-disease',1,'G381.00',NULL,'Postoperative transmural myocardial infarction of inferior wall'),('coronary-heart-disease',1,'G380.00',NULL,'Postoperative transmural myocardial infarction of anterior wall'),('coronary-heart-disease',1,'G37..00',NULL,'Cardiac syndrome X'),('coronary-heart-disease',1,'G365.00',NULL,'Rupture of papillary muscle as current complication following acute myocardial infarction'),('coronary-heart-disease',1,'G364.00',NULL,'Rupture of chordae tendinae as current complication following acute myocardial infarction'),('coronary-heart-disease',1,'G363.00',NULL,'Rupture of cardiac wall without haemopericardium as current complication following acute myocardial infarction'),('coronary-heart-disease',1,'G362.00',NULL,'Ventricular septal defect as current complication following acute myocardial infarction'),('coronary-heart-disease',1,'G361.00',NULL,'Atrial septal defect as current complication following acute myocardial infarction'),('coronary-heart-disease',1,'G360.00',NULL,'Haemopericardium as current complication following acute myocardial infarction'),('coronary-heart-disease',1,'G35..00',NULL,'Subsequent myocardial infarction'),('coronary-heart-disease',1,'G35X.00',NULL,'Subsequent myocardial infarction of unspecified site'),('coronary-heart-disease',1,'G353.00',NULL,'Subsequent myocardial infarction of other sites'),('coronary-heart-disease',1,'G351.00',NULL,'Subsequent myocardial infarction of inferior wall'),('coronary-heart-disease',1,'G350.00',NULL,'Subsequent myocardial infarction of anterior wall'),('coronary-heart-disease',1,'G34..00',NULL,'Other chronic ischaemic heart disease'),('coronary-heart-disease',1,'G34z.00',NULL,'Other chronic ischaemic heart disease NOS'),('coronary-heart-disease',1,'G34z000',NULL,'Asymptomatic coronary heart disease'),('coronary-heart-disease',1,'G34y.00',NULL,'Other specified chronic ischaemic heart disease'),('coronary-heart-disease',1,'G34yz00',NULL,'Other specified chronic ischaemic heart disease NOS'),('coronary-heart-disease',1,'G34y100',NULL,'Chronic myocardial ischaemia'),('coronary-heart-disease',1,'G34y000',NULL,'Chronic coronary insufficiency'),('coronary-heart-disease',1,'G344.00',NULL,'Silent myocardial ischaemia'),('coronary-heart-disease',1,'G343.00',NULL,'Ischaemic cardiomyopathy'),('coronary-heart-disease',1,'G342.00',NULL,'Atherosclerotic cardiovascular disease'),('coronary-heart-disease',1,'G341.00',NULL,'Aneurysm of heart'),('coronary-heart-disease',1,'G341.11',NULL,'Cardiac aneurysm'),('coronary-heart-disease',1,'G341z00',NULL,'Aneurysm of heart NOS'),('coronary-heart-disease',1,'G341300',NULL,'Acquired atrioventricular fistula of heart'),('coronary-heart-disease',1,'G341200',NULL,'Aneurysm of coronary vessels'),('coronary-heart-disease',1,'G341100',NULL,'Other cardiac wall aneurysm'),('coronary-heart-disease',1,'G341111',NULL,'Mural cardiac aneurysm'),('coronary-heart-disease',1,'G341000',NULL,'Ventricular cardiac aneurysm'),('coronary-heart-disease',1,'G340.00',NULL,'Coronary atherosclerosis'),('coronary-heart-disease',1,'G340.11',NULL,'Triple vessel disease of the heart'),('coronary-heart-disease',1,'G340.12',NULL,'Coronary artery disease'),('coronary-heart-disease',1,'G340100',NULL,'Double coronary vessel disease'),('coronary-heart-disease',1,'G340000',NULL,'Single coronary vessel disease'),('coronary-heart-disease',1,'G33..00',NULL,'Angina pectoris'),('coronary-heart-disease',1,'G33z.00',NULL,'Angina pectoris NOS'),('coronary-heart-disease',1,'G33zz00',NULL,'Angina pectoris NOS'),('coronary-heart-disease',1,'G33z700',NULL,'Stable angina'),('coronary-heart-disease',1,'G33z600',NULL,'New onset angina'),('coronary-heart-disease',1,'G33z500',NULL,'Post infarct angina'),('coronary-heart-disease',1,'G33z400',NULL,'Ischaemic chest pain'),('coronary-heart-disease',1,'G33z300',NULL,'Angina on effort'),('coronary-heart-disease',1,'G33z200',NULL,'Syncope anginosa'),('coronary-heart-disease',1,'G33z100',NULL,'Stenocardia'),('coronary-heart-disease',1,'G33z000',NULL,'Status anginosus'),('coronary-heart-disease',1,'G331.00',NULL,'Prinzmetals angina'),('coronary-heart-disease',1,'G331.11',NULL,'Variant angina pectoris'),('coronary-heart-disease',1,'G330.00',NULL,'Angina decubitus'),('coronary-heart-disease',1,'G330z00',NULL,'Angina decubitus NOS'),('coronary-heart-disease',1,'G330000',NULL,'Nocturnal angina'),('coronary-heart-disease',1,'G32..00',NULL,'Old myocardial infarction'),('coronary-heart-disease',1,'G32..11',NULL,'Healed myocardial infarction'),('coronary-heart-disease',1,'G31..00',NULL,'Other acute and subacute ischaemic heart disease'),('coronary-heart-disease',1,'G31y.00',NULL,'Other acute and subacute ischaemic heart disease'),('coronary-heart-disease',1,'G31yz00',NULL,'Other acute and subacute ischaemic heart disease NOS'),('coronary-heart-disease',1,'G31y300',NULL,'Transient myocardial ischaemia'),('coronary-heart-disease',1,'G31y200',NULL,'Subendocardial ischaemia'),('coronary-heart-disease',1,'G31y100',NULL,'Microinfarction of heart'),('coronary-heart-disease',1,'G31y000',NULL,'Acute coronary insufficiency'),('coronary-heart-disease',1,'G312.00',NULL,'Coronary thrombosis not resulting in myocardial infarction'),('coronary-heart-disease',1,'G311.00',NULL,'Preinfarction syndrome'),('coronary-heart-disease',1,'G311.11',NULL,'Crescendo angina'),('coronary-heart-disease',1,'G311.12',NULL,'Impending infarction'),('coronary-heart-disease',1,'G311.13',NULL,'Unstable angina'),('coronary-heart-disease',1,'G311.14',NULL,'Angina at rest'),('coronary-heart-disease',1,'G311z00',NULL,'Preinfarction syndrome NOS'),('coronary-heart-disease',1,'G311500',NULL,'Acute coronary syndrome'),('coronary-heart-disease',1,'G311400',NULL,'Worsening angina'),('coronary-heart-disease',1,'G311300',NULL,'Refractory angina'),('coronary-heart-disease',1,'G311200',NULL,'Angina at rest'),('coronary-heart-disease',1,'G311100',NULL,'Unstable angina'),('coronary-heart-disease',1,'G311000',NULL,'Myocardial infarction aborted'),('coronary-heart-disease',1,'G311011',NULL,'MI - myocardial infarction aborted'),('coronary-heart-disease',1,'G310.11',NULL,'Dresslers syndrome'),('coronary-heart-disease',1,'G30..00',NULL,'Acute myocardial infarction'),('coronary-heart-disease',1,'G30..11',NULL,'Attack - heart'),('coronary-heart-disease',1,'G30..12',NULL,'Coronary thrombosis'),('coronary-heart-disease',1,'G30..13',NULL,'Cardiac rupture following myocardial infarction (MI)'),('coronary-heart-disease',1,'G30..14',NULL,'Heart attack'),('coronary-heart-disease',1,'G30..15',NULL,'MI - acute myocardial infarction'),('coronary-heart-disease',1,'G30..16',NULL,'Thrombosis - coronary'),('coronary-heart-disease',1,'G30..17',NULL,'Silent myocardial infarction'),('coronary-heart-disease',1,'G30z.00',NULL,'Acute myocardial infarction NOS'),('coronary-heart-disease',1,'G30y.00',NULL,'Other acute myocardial infarction'),('coronary-heart-disease',1,'G30yz00',NULL,'Other acute myocardial infarction NOS'),('coronary-heart-disease',1,'G30y200',NULL,'Acute septal infarction'),('coronary-heart-disease',1,'G30y100',NULL,'Acute papillary muscle infarction'),('coronary-heart-disease',1,'G30y000',NULL,'Acute atrial infarction'),('coronary-heart-disease',1,'G30X.00',NULL,'Acute transmural myocardial infarction of unspecified site'),('coronary-heart-disease',1,'G30X000',NULL,'Acute ST segment elevation myocardial infarction'),('coronary-heart-disease',1,'G30B.00',NULL,'Acute posterolateral myocardial infarction'),('coronary-heart-disease',1,'G309.00',NULL,'Acute Q-wave infarct'),('coronary-heart-disease',1,'G308.00',NULL,'Inferior myocardial infarction NOS'),('coronary-heart-disease',1,'G307.00',NULL,'Acute subendocardial infarction'),('coronary-heart-disease',1,'G307100',NULL,'Acute non-ST segment elevation myocardial infarction'),('coronary-heart-disease',1,'G307000',NULL,'Acute non-Q wave infarction'),('coronary-heart-disease',1,'G306.00',NULL,'True posterior myocardial infarction'),('coronary-heart-disease',1,'G305.00',NULL,'Lateral myocardial infarction NOS'),('coronary-heart-disease',1,'G304.00',NULL,'Posterior myocardial infarction NOS'),('coronary-heart-disease',1,'G303.00',NULL,'Acute inferoposterior infarction'),('coronary-heart-disease',1,'G302.00',NULL,'Acute inferolateral infarction'),('coronary-heart-disease',1,'G301.00',NULL,'Other specified anterior myocardial infarction'),('coronary-heart-disease',1,'G301z00',NULL,'Anterior myocardial infarction NOS'),('coronary-heart-disease',1,'G301100',NULL,'Acute anteroseptal infarction'),('coronary-heart-disease',1,'G301000',NULL,'Acute anteroapical infarction'),('coronary-heart-disease',1,'G300.00',NULL,'Acute anterolateral infarction'),('coronary-heart-disease',1,'Gyu3.00',NULL,'[X]Ischaemic heart diseases'),('coronary-heart-disease',1,'Gyu3300',NULL,'[X]Other forms of chronic ischaemic heart disease'),
('coronary-heart-disease',1,'Gyu3200',NULL,'[X]Other forms of acute ischaemic heart disease'),('coronary-heart-disease',1,'Gyu3000',NULL,'[X]Other forms of angina pectoris'),('coronary-heart-disease',1,'Gyu3600',NULL,'[X]Subsequent myocardial infarction of unspecified site'),('coronary-heart-disease',1,'Gyu3500',NULL,'[X]Subsequent myocardial infarction of other sites'),('coronary-heart-disease',1,'Gyu3400',NULL,'[X]Acute transmural myocardial infarction of unspecified site'),('coronary-heart-disease',1,'14AL.00',NULL,'H/O: Treatment for ischaemic heart disease'),('coronary-heart-disease',1,'14AW.00',NULL,'H/O acute coronary syndrome'),('coronary-heart-disease',1,'14AJ.00',NULL,'H/O: Angina in last year'),('coronary-heart-disease',1,'14A5.00',NULL,'H/O: angina pectoris'),('coronary-heart-disease',1,'14AH.00',NULL,'H/O: Myocardial infarction in last year'),('coronary-heart-disease',1,'P6yy600',NULL,'Congenital aneurysm of heart'),('coronary-heart-disease',1,'SP07600',NULL,'Coronary artery bypass graft occlusion');
INSERT INTO #codessnomed
VALUES ('bmi',2,'301331008',NULL,'Finding of body mass index (finding)');
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
VALUES ('smoking-status-trivial',1,'266920004',NULL,'Trivial cigarette smoker (less than one cigarette/day) (life style)'),('smoking-status-trivial',1,'428041000124106',NULL,'Occasional tobacco smoker (finding)');
INSERT INTO #codessnomed
VALUES ('covid-vaccination',1,'1240491000000103',NULL,'2019-nCoV (novel coronavirus) vaccination'),('covid-vaccination',1,'2807821000000115',NULL,'2019-nCoV (novel coronavirus) vaccination'),('covid-vaccination',1,'840534001',NULL,'Severe acute respiratory syndrome coronavirus 2 vaccination (procedure)')

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
VALUES ('asthma',1,'EMISNQAC876',NULL,'Acute infective exacerbation of asthma'),('asthma',1,'EMISNQAC877',NULL,'Acute non-infective exacerbation of asthma');
INSERT INTO #codesemis
VALUES ('copd',1,'EMISNQAC878',NULL,'Acute non-infective exacerbation of chronic obstructive pulmonary disease'),('copd',1,'ESCTAC8',NULL,'Acute infective exacerbation of chronic obstructive airways disease');
INSERT INTO #codesemis
VALUES ('hypertension',1,'EMISNQST25',NULL,'Stage 2 hypertension'),('hypertension',1,'^ESCTMA364280',NULL,'Malignant hypertension'),('hypertension',1,'EMISNQST25',NULL,'Stage 2 hypertension');
INSERT INTO #codesemis
VALUES ('covid-vaccination',1,'^ESCT1348323',NULL,'Administration of first dose of SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) vaccine'),('covid-vaccination',1,'^ESCT1348324',NULL,'Administration of first dose of 2019-nCoV (novel coronavirus) vaccine'),('covid-vaccination',1,'COCO138186NEMIS',NULL,'COVID-19 mRNA Vaccine BNT162b2 30micrograms/0.3ml dose concentrate for suspension for injection multidose vials (Pfizer-BioNTech) (Pfizer-BioNTech)'),('covid-vaccination',1,'^ESCT1348325',NULL,'Administration of second dose of SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) vaccine'),('covid-vaccination',1,'^ESCT1348326',NULL,'Administration of second dose of 2019-nCoV (novel coronavirus) vaccine'),('covid-vaccination',1,'^ESCT1428354',NULL,'Administration of third dose of SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) vaccine'),('covid-vaccination',1,'^ESCT1428342',NULL,'Administration of fourth dose of SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) vaccine'),('covid-vaccination',1,'^ESCT1428348',NULL,'Administration of fifth dose of SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) vaccine'),('covid-vaccination',1,'^ESCT1348298',NULL,'SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) vaccination'),('covid-vaccination',1,'^ESCT1348301',NULL,'COVID-19 vaccination'),('covid-vaccination',1,'^ESCT1299050',NULL,'2019-nCoV (novel coronavirus) vaccination'),('covid-vaccination',1,'^ESCT1301222',NULL,'SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) vaccination'),('covid-vaccination',1,'CODI138564NEMIS',NULL,'Covid-19 mRna (nucleoside modified) Vaccine Moderna  Dispersion for injection  0.1 mg/0.5 ml dose, multidose vial'),('covid-vaccination',1,'TASO138184NEMIS',NULL,'Covid-19 Vaccine AstraZeneca (ChAdOx1 S recombinant)  Solution for injection  5x10 billion viral particle/0.5 ml multidose vial'),('covid-vaccination',1,'PCSDT18491_1375',NULL,'Administration of first dose of SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) vaccine'),('covid-vaccination',1,'PCSDT18491_1376',NULL,'Administration of second dose of SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) vaccine'),('covid-vaccination',1,'PCSDT18491_716',NULL,'Administration of second dose of SARS-CoV-2 vacc'),('covid-vaccination',1,'PCSDT18491_903',NULL,'Administration of first dose of SARS-CoV-2 vacccine'),('covid-vaccination',1,'PCSDT3370_2254',NULL,'2019-nCoV (novel coronavirus) vaccination'),('covid-vaccination',1,'PCSDT3919_2185',NULL,'Administration of first dose of SARS-CoV-2 vacccine'),('covid-vaccination',1,'PCSDT3919_662',NULL,'Administration of second dose of SARS-CoV-2 vacc'),('covid-vaccination',1,'PCSDT4803_1723',NULL,'2019-nCoV (novel coronavirus) vaccination'),('covid-vaccination',1,'PCSDT5823_2264',NULL,'Administration of second dose of SARS-CoV-2 vacc'),('covid-vaccination',1,'PCSDT5823_2757',NULL,'Administration of second dose of SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) vaccine'),('covid-vaccination',1,'PCSDT5823_2902',NULL,'Administration of first dose of SARS-CoV-2 vacccine'),('covid-vaccination',1,'^ESCT1348300',NULL,'Severe acute respiratory syndrome coronavirus 2 vaccination'),('covid-vaccination',1,'ASSO138368NEMIS',NULL,'COVID-19 Vaccine Janssen (Ad26.COV2-S [recombinant]) 0.5ml dose suspension for injection multidose vials (Janssen-Cilag Ltd)'),('covid-vaccination',1,'COCO141057NEMIS',NULL,'Comirnaty Children 5-11 years COVID-19 mRNA Vaccine 10micrograms/0.2ml dose concentrate for dispersion for injection multidose vials (Pfizer Ltd)'),('covid-vaccination',1,'COSO141059NEMIS',NULL,'COVID-19 Vaccine Covishield (ChAdOx1 S [recombinant]) 5x10,000,000,000 viral particles/0.5ml dose solution for injection multidose vials (Serum Institute of India)'),('covid-vaccination',1,'COSU138776NEMIS',NULL,'COVID-19 Vaccine Valneva (inactivated adjuvanted whole virus) 40antigen units/0.5ml dose suspension for injection multidose vials (Valneva UK Ltd)'),('covid-vaccination',1,'COSU138943NEMIS',NULL,'COVID-19 Vaccine Novavax (adjuvanted) 5micrograms/0.5ml dose suspension for injection multidose vials (Baxter Oncology GmbH)'),('covid-vaccination',1,'COSU141008NEMIS',NULL,'CoronaVac COVID-19 Vaccine (adjuvanted) 600U/0.5ml dose suspension for injection vials (Sinovac Life Sciences)'),('covid-vaccination',1,'COSU141037NEMIS',NULL,'COVID-19 Vaccine Sinopharm BIBP (inactivated adjuvanted) 6.5U/0.5ml dose suspension for injection vials (Beijing Institute of Biological Products)');
INSERT INTO #codesemis
VALUES ('covid-positive-pcr-test',1,'^ESCT1305238',NULL,'SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) RNA (ribonucleic acid) qualitative existence in specimen'),('covid-positive-pcr-test',1,'^ESCT1348314',NULL,'SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) RNA (ribonucleic acid) detection result positive'),('covid-positive-pcr-test',1,'^ESCT1305235',NULL,'SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) RNA (ribonucleic acid) detection result positive'),('covid-positive-pcr-test',1,'^ESCT1300228',NULL,'COVID-19 confirmed by laboratory test GP COVID-19'),('covid-positive-pcr-test',1,'^ESCT1348316',NULL,'2019-nCoV (novel coronavirus) ribonucleic acid detected'),('covid-positive-pcr-test',1,'^ESCT1301223',NULL,'Detection of SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) using polymerase chain reaction technique'),('covid-positive-pcr-test',1,'^ESCT1348359',NULL,'SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) RNA (ribonucleic acid) detection result positive at the limit of detection'),('covid-positive-pcr-test',1,'^ESCT1299053',NULL,'Detection of 2019-nCoV (novel coronavirus) using polymerase chain reaction technique'),('covid-positive-pcr-test',1,'^ESCT1300228',NULL,'COVID-19 confirmed by laboratory test'),('covid-positive-pcr-test',1,'^ESCT1348359',NULL,'SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) RNA (ribonucleic acid) detection result positive at the limit of detection');
INSERT INTO #codesemis
VALUES ('covid-positive-test-other',1,'^ESCT1303928',NULL,'SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) detection result positive'),('covid-positive-test-other',1,'^ESCT1299074',NULL,'2019-nCoV (novel coronavirus) detected'),('covid-positive-test-other',1,'^ESCT1301230',NULL,'SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2) detected'),('covid-positive-test-other',1,'EMISNQCO303',NULL,'Confirmed 2019-nCoV (Wuhan) infectio'),('covid-positive-test-other',1,'^ESCT1299075',NULL,'Wuhan 2019-nCoV (novel coronavirus) detected'),('covid-positive-test-other',1,'^ESCT1300229',NULL,'COVID-19 confirmed using clinical diagnostic criteria'),('covid-positive-test-other',1,'^ESCT1348575',NULL,'Detection of SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2)'),('covid-positive-test-other',1,'^ESCT1299074',NULL,'2019-nCoV (novel coronavirus) detected'),('covid-positive-test-other',1,'^ESCT1300229',NULL,'COVID-19 confirmed using clinical diagnostic criteria'),('covid-positive-test-other',1,'EMISNQCO303',NULL,'Confirmed 2019-nCoV (novel coronavirus) infection'),('covid-positive-test-other',1,'EMISNQCO303',NULL,'Confirmed 2019-nCoV (novel coronavirus) infection'),('covid-positive-test-other',1,'^ESCT1348575',NULL,'Detection of SARS-CoV-2 (severe acute respiratory syndrome coronavirus 2)')

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

-- >>> Following code sets injected: covid-positive-pcr-test v1/covid-positive-test-other v1


-- Set the temp end date until new legal basis
DECLARE @TEMPWithCovidEndDate datetime;
SET @TEMPWithCovidEndDate = '2022-06-01';

IF OBJECT_ID('tempdb..#CovidPatientsAllDiagnoses') IS NOT NULL DROP TABLE #CovidPatientsAllDiagnoses;
CREATE TABLE #CovidPatientsAllDiagnoses (
	FK_Patient_Link_ID BIGINT,
	CovidPositiveDate DATE
);
BEGIN
	IF 'true'='true'
		INSERT INTO #CovidPatientsAllDiagnoses
		SELECT DISTINCT FK_Patient_Link_ID, CONVERT(DATE, [EventDate]) AS CovidPositiveDate
		FROM [RLS].[vw_COVID19]
		WHERE (
			(GroupDescription = 'Confirmed' AND SubGroupDescription != 'Negative') OR
			(GroupDescription = 'Tested' AND SubGroupDescription = 'Positive')
		)
		AND EventDate > '2020-01-01'
		--AND EventDate <= GETDATE();
		AND EventDate <= @TEMPWithCovidEndDate
		AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsToInclude);
	ELSE 
		INSERT INTO #CovidPatientsAllDiagnoses
		SELECT DISTINCT FK_Patient_Link_ID, CONVERT(DATE, [EventDate]) AS CovidPositiveDate
		FROM [RLS].[vw_COVID19]
		WHERE (
			(GroupDescription = 'Confirmed' AND SubGroupDescription != 'Negative') OR
			(GroupDescription = 'Tested' AND SubGroupDescription = 'Positive')
		)
		AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
		AND EventDate > '2020-01-01'
		--AND EventDate <= GETDATE();
		AND EventDate <= @TEMPWithCovidEndDate;
END

-- We can rely on the GraphNet table for first diagnosis.
IF OBJECT_ID('tempdb..#CovidPatients') IS NOT NULL DROP TABLE #CovidPatients;
SELECT FK_Patient_Link_ID, MIN(CovidPositiveDate) AS FirstCovidPositiveDate INTO #CovidPatients
FROM #CovidPatientsAllDiagnoses
GROUP BY FK_Patient_Link_ID;

-- Now let's get the dates of any positive test (i.e. not things like suspected, or historic)
IF OBJECT_ID('tempdb..#AllPositiveTestsTemp') IS NOT NULL DROP TABLE #AllPositiveTestsTemp;
CREATE TABLE #AllPositiveTestsTemp (
	FK_Patient_Link_ID BIGINT,
	TestDate DATE
);
BEGIN
	IF 'true'='true'
		INSERT INTO #AllPositiveTestsTemp
		SELECT DISTINCT FK_Patient_Link_ID, CAST(EventDate AS DATE) AS TestDate
		FROM RLS.vw_GP_Events
		WHERE SuppliedCode IN (
			select Code from #AllCodes 
			where Concept in ('covid-positive-antigen-test','covid-positive-pcr-test','covid-positive-test-other') 
			AND Version = 1
		)
		AND EventDate <= @TEMPWithCovidEndDate
		AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #PatientsToInclude);
	ELSE 
		INSERT INTO #AllPositiveTestsTemp
		SELECT DISTINCT FK_Patient_Link_ID, CAST(EventDate AS DATE) AS TestDate
		FROM RLS.vw_GP_Events
		WHERE SuppliedCode IN (
			select Code from #AllCodes 
			where Concept in ('covid-positive-antigen-test','covid-positive-pcr-test','covid-positive-test-other') 
			AND Version = 1
		)
		AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
		AND EventDate <= @TEMPWithCovidEndDate;
END

IF OBJECT_ID('tempdb..#CovidPatientsMultipleDiagnoses') IS NOT NULL DROP TABLE #CovidPatientsMultipleDiagnoses;
CREATE TABLE #CovidPatientsMultipleDiagnoses (
	FK_Patient_Link_ID BIGINT,
	FirstCovidPositiveDate DATE,
	SecondCovidPositiveDate DATE,
	ThirdCovidPositiveDate DATE,
	FourthCovidPositiveDate DATE,
	FifthCovidPositiveDate DATE
);

-- Populate first diagnosis
INSERT INTO #CovidPatientsMultipleDiagnoses (FK_Patient_Link_ID, FirstCovidPositiveDate)
SELECT FK_Patient_Link_ID, MIN(FirstCovidPositiveDate) FROM
(
	SELECT * FROM #CovidPatients
	UNION
	SELECT * FROM #AllPositiveTestsTemp
) sub
GROUP BY FK_Patient_Link_ID;

-- Now let's get second tests.
UPDATE t1
SET t1.SecondCovidPositiveDate = NextTestDate
FROM #CovidPatientsMultipleDiagnoses AS t1
INNER JOIN (
SELECT cp.FK_Patient_Link_ID, MIN(apt.TestDate) AS NextTestDate FROM #CovidPatients cp
INNER JOIN #AllPositiveTestsTemp apt ON cp.FK_Patient_Link_ID = apt.FK_Patient_Link_ID AND apt.TestDate >= DATEADD(day, 90, FirstCovidPositiveDate)
GROUP BY cp.FK_Patient_Link_ID) AS sub ON sub.FK_Patient_Link_ID = t1.FK_Patient_Link_ID;

-- Now let's get third tests.
UPDATE t1
SET t1.ThirdCovidPositiveDate = NextTestDate
FROM #CovidPatientsMultipleDiagnoses AS t1
INNER JOIN (
SELECT cp.FK_Patient_Link_ID, MIN(apt.TestDate) AS NextTestDate FROM #CovidPatientsMultipleDiagnoses cp
INNER JOIN #AllPositiveTestsTemp apt ON cp.FK_Patient_Link_ID = apt.FK_Patient_Link_ID AND apt.TestDate >= DATEADD(day, 90, SecondCovidPositiveDate)
GROUP BY cp.FK_Patient_Link_ID) AS sub ON sub.FK_Patient_Link_ID = t1.FK_Patient_Link_ID;

-- Now let's get fourth tests.
UPDATE t1
SET t1.FourthCovidPositiveDate = NextTestDate
FROM #CovidPatientsMultipleDiagnoses AS t1
INNER JOIN (
SELECT cp.FK_Patient_Link_ID, MIN(apt.TestDate) AS NextTestDate FROM #CovidPatientsMultipleDiagnoses cp
INNER JOIN #AllPositiveTestsTemp apt ON cp.FK_Patient_Link_ID = apt.FK_Patient_Link_ID AND apt.TestDate >= DATEADD(day, 90, ThirdCovidPositiveDate)
GROUP BY cp.FK_Patient_Link_ID) AS sub ON sub.FK_Patient_Link_ID = t1.FK_Patient_Link_ID;

-- Now let's get fifth tests.
UPDATE t1
SET t1.FifthCovidPositiveDate = NextTestDate
FROM #CovidPatientsMultipleDiagnoses AS t1
INNER JOIN (
SELECT cp.FK_Patient_Link_ID, MIN(apt.TestDate) AS NextTestDate FROM #CovidPatientsMultipleDiagnoses cp
INNER JOIN #AllPositiveTestsTemp apt ON cp.FK_Patient_Link_ID = apt.FK_Patient_Link_ID AND apt.TestDate >= DATEADD(day, 90, FourthCovidPositiveDate)
GROUP BY cp.FK_Patient_Link_ID) AS sub ON sub.FK_Patient_Link_ID = t1.FK_Patient_Link_ID;

IF OBJECT_ID('tempdb..#Patients') IS NOT NULL DROP TABLE #Patients;
SELECT FK_Patient_Link_ID INTO #Patients
FROM #CovidPatients;

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
--┌────────────────┐
--│ Smoking status │
--└────────────────┘

-- OBJECTIVE: To get the smoking status for each patient in a cohort.

-- INPUT: Assumes there exists a temp table as follows:
-- #Patients (FK_Patient_Link_ID)
--  A distinct list of FK_Patient_Link_IDs for each patient in the cohort
-- Also takes one parameter:
--	- gp-events-table: string - (table name) the name of the table containing the GP events. Usually is "RLS.vw_GP_Events" but can be anything with the columns: FK_Patient_Link_ID, EventDate, FK_Reference_Coding_ID, and FK_Reference_SnomedCT_ID

-- OUTPUT: A temp table as follows:
-- #PatientSmokingStatus (FK_Patient_Link_ID, PassiveSmoker, WorstSmokingStatus, CurrentSmokingStatus)
--	- FK_Patient_Link_ID - unique patient id
--	- PassiveSmoker - Y/N (whether a patient has ever had a code for passive smoking)
--	- WorstSmokingStatus - [non-trivial-smoker/trivial-smoker/non-smoker]
--	- CurrentSmokingStatus - [non-trivial-smoker/trivial-smoker/non-smoker]

-- ASSUMPTIONS:
--	- We take the most recent smoking status in a patient's record to be correct
--	- However, there is likely confusion between the "non smoker" and "never smoked" codes. Especially as sometimes the synonyms for these codes overlap. Therefore, a patient wih a most recent smoking status of "never", but who has previous smoking codes, would be classed as WorstSmokingStatus=non-trivial-smoker / CurrentSmokingStatus=non-smoker

-- >>> Following code sets injected: smoking-status-current v1/smoking-status-currently-not v1/smoking-status-ex v1/smoking-status-ex-trivial v1/smoking-status-never v1/smoking-status-passive v1/smoking-status-trivial v1
-- Get all patients year of birth for the cohort
IF OBJECT_ID('tempdb..#AllPatientSmokingStatusCodes') IS NOT NULL DROP TABLE #AllPatientSmokingStatusCodes;
SELECT 
	FK_Patient_Link_ID,
	CAST(EventDate AS DATE) AS EventDate,
	FK_Reference_Coding_ID,
	FK_Reference_SnomedCT_ID
INTO #AllPatientSmokingStatusCodes
FROM RLS.vw_GP_Events
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND FK_Reference_SnomedCT_ID IN (
	SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets 
	WHERE Concept IN (
		'smoking-status-current',
		'smoking-status-currently-not',
		'smoking-status-ex',
		'smoking-status-ex-trivial',
		'smoking-status-never',
		'smoking-status-passive',
		'smoking-status-trivial'
	)
	AND [Version]=1
) 
UNION
SELECT 
	FK_Patient_Link_ID,
	CAST(EventDate AS DATE) AS EventDate,
	FK_Reference_Coding_ID,
	FK_Reference_SnomedCT_ID
FROM RLS.vw_GP_Events
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND FK_Reference_Coding_ID IN (
	SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets 
	WHERE Concept IN (
		'smoking-status-current',
		'smoking-status-currently-not',
		'smoking-status-ex',
		'smoking-status-ex-trivial',
		'smoking-status-never',
		'smoking-status-passive',
		'smoking-status-trivial'
	)
	AND [Version]=1
);

IF OBJECT_ID('tempdb..#AllPatientSmokingStatusConcept') IS NOT NULL DROP TABLE #AllPatientSmokingStatusConcept;
SELECT 
	a.FK_Patient_Link_ID,
	EventDate,
	CASE WHEN c.Concept IS NULL THEN s.Concept ELSE c.Concept END AS Concept,
	-1 AS Severity
INTO #AllPatientSmokingStatusConcept
FROM #AllPatientSmokingStatusCodes a
LEFT OUTER JOIN #VersionedCodeSets c on c.FK_Reference_Coding_ID = a.FK_Reference_Coding_ID
LEFT OUTER JOIN #VersionedSnomedSets s on s.FK_Reference_SnomedCT_ID = a.FK_Reference_SnomedCT_ID;

UPDATE #AllPatientSmokingStatusConcept
SET Severity = 2
WHERE Concept IN ('smoking-status-current');
UPDATE #AllPatientSmokingStatusConcept
SET Severity = 2
WHERE Concept IN ('smoking-status-ex');
UPDATE #AllPatientSmokingStatusConcept
SET Severity = 1
WHERE Concept IN ('smoking-status-ex-trivial');
UPDATE #AllPatientSmokingStatusConcept
SET Severity = 1
WHERE Concept IN ('smoking-status-trivial');
UPDATE #AllPatientSmokingStatusConcept
SET Severity = 0
WHERE Concept IN ('smoking-status-never');
UPDATE #AllPatientSmokingStatusConcept
SET Severity = 0
WHERE Concept IN ('smoking-status-currently-not');

-- passive smokers
IF OBJECT_ID('tempdb..#TempPassiveSmokers') IS NOT NULL DROP TABLE #TempPassiveSmokers;
select DISTINCT FK_Patient_Link_ID into #TempPassiveSmokers from #AllPatientSmokingStatusConcept
where Concept = 'smoking-status-passive';

-- For "worst" smoking status
IF OBJECT_ID('tempdb..#TempWorst') IS NOT NULL DROP TABLE #TempWorst;
SELECT 
	FK_Patient_Link_ID, 
	CASE 
		WHEN MAX(Severity) = 2 THEN 'non-trivial-smoker'
		WHEN MAX(Severity) = 1 THEN 'trivial-smoker'
		WHEN MAX(Severity) = 0 THEN 'non-smoker'
	END AS [Status]
INTO #TempWorst
FROM #AllPatientSmokingStatusConcept
WHERE Severity >= 0
GROUP BY FK_Patient_Link_ID;

-- For "current" smoking status
IF OBJECT_ID('tempdb..#TempCurrent') IS NOT NULL DROP TABLE #TempCurrent;
SELECT 
	a.FK_Patient_Link_ID, 
	CASE 
		WHEN MAX(Severity) = 2 THEN 'non-trivial-smoker'
		WHEN MAX(Severity) = 1 THEN 'trivial-smoker'
		WHEN MAX(Severity) = 0 THEN 'non-smoker'
	END AS [Status]
INTO #TempCurrent
FROM #AllPatientSmokingStatusConcept a
INNER JOIN (
	SELECT FK_Patient_Link_ID, MAX(EventDate) AS MostRecentDate FROM #AllPatientSmokingStatusConcept
	WHERE Severity >= 0
	GROUP BY FK_Patient_Link_ID
) sub ON sub.MostRecentDate = a.EventDate and sub.FK_Patient_Link_ID = a.FK_Patient_Link_ID
GROUP BY a.FK_Patient_Link_ID;

-- Bring all together in final table
IF OBJECT_ID('tempdb..#PatientSmokingStatus') IS NOT NULL DROP TABLE #PatientSmokingStatus;
SELECT 
	p.FK_Patient_Link_ID,
	CASE WHEN ps.FK_Patient_Link_ID IS NULL THEN 'N' ELSE 'Y' END AS PassiveSmoker,
	CASE WHEN w.[Status] IS NULL THEN 'unknown-smoking-status' ELSE w.[Status] END AS WorstSmokingStatus,
	CASE WHEN c.[Status] IS NULL THEN 'unknown-smoking-status' ELSE c.[Status] END AS CurrentSmokingStatus
INTO #PatientSmokingStatus FROM #Patients p
LEFT OUTER JOIN #TempPassiveSmokers ps on ps.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #TempWorst w on w.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN #TempCurrent c on c.FK_Patient_Link_ID = p.FK_Patient_Link_ID;
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
FROM RLS.vw_Patient p
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
--┌────────────────────┐
--│ COVID vaccinations │
--└────────────────────┘

-- OBJECTIVE: To obtain a table with first, second, third... etc vaccine doses per patient.

-- ASSUMPTIONS:
--	-	GP records can often be duplicated. The assumption is that if a patient receives
--    two vaccines within 14 days of each other then it is likely that both codes refer
--    to the same vaccine.
--  - The vaccine can appear as a procedure or as a medication. We assume that the
--    presence of either represents a vaccination

-- INPUT: Takes two parameters:
--	- gp-events-table: string - (table name) the name of the table containing the GP events. Usually is "RLS.vw_GP_Events" but can be anything with the columns: FK_Patient_Link_ID, EventDate, and SuppliedCode
--	- gp-medications-table: string - (table name) the name of the table containing the GP medications. Usually is "RLS.vw_GP_Medications" but can be anything with the columns: FK_Patient_Link_ID, EventDate, and SuppliedCode

-- OUTPUT: A temp table as follows:
-- #COVIDVaccinations (FK_Patient_Link_ID, VaccineDate, DaysSinceFirstVaccine)
-- 	- FK_Patient_Link_ID - unique patient id
--	- VaccineDose1Date - date of first vaccine (YYYY-MM-DD)
--	-	VaccineDose2Date - date of second vaccine (YYYY-MM-DD)
--	-	VaccineDose3Date - date of third vaccine (YYYY-MM-DD)
--	-	VaccineDose4Date - date of fourth vaccine (YYYY-MM-DD)
--	-	VaccineDose5Date - date of fifth vaccine (YYYY-MM-DD)
--	-	VaccineDose6Date - date of sixth vaccine (YYYY-MM-DD)
--	-	VaccineDose7Date - date of seventh vaccine (YYYY-MM-DD)

-- Get patients with covid vaccine and earliest and latest date
-- >>> Following code sets injected: covid-vaccination v1


IF OBJECT_ID('tempdb..#VacEvents') IS NOT NULL DROP TABLE #VacEvents;
SELECT FK_Patient_Link_ID, CONVERT(DATE, EventDate) AS EventDate into #VacEvents
FROM RLS.vw_GP_Events
WHERE SuppliedCode IN (
	SELECT [Code] FROM #AllCodes WHERE [Concept] = 'covid-vaccination' AND [Version] = 1
)
AND EventDate > '2020-12-01'
AND EventDate < '2022-06-01'; --TODO temp addition for COPI expiration

IF OBJECT_ID('tempdb..#VacMeds') IS NOT NULL DROP TABLE #VacMeds;
SELECT FK_Patient_Link_ID, CONVERT(DATE, MedicationDate) AS EventDate into #VacMeds
FROM RLS.vw_GP_Medications
WHERE SuppliedCode IN (
	SELECT [Code] FROM #AllCodes WHERE [Concept] = 'covid-vaccination' AND [Version] = 1
)
AND MedicationDate > '2020-12-01'
AND MedicationDate < '2022-06-01';--TODO temp addition for COPI expiration

IF OBJECT_ID('tempdb..#COVIDVaccines') IS NOT NULL DROP TABLE #COVIDVaccines;
SELECT FK_Patient_Link_ID, EventDate into #COVIDVaccines FROM #VacEvents
UNION
SELECT FK_Patient_Link_ID, EventDate FROM #VacMeds;
--4426892 5m03

-- Tidy up
DROP TABLE #VacEvents;
DROP TABLE #VacMeds;

-- Get first vaccine dose
IF OBJECT_ID('tempdb..#VacTemp1') IS NOT NULL DROP TABLE #VacTemp1;
select FK_Patient_Link_ID, MIN(EventDate) AS VaccineDoseDate
into #VacTemp1
from #COVIDVaccines
group by FK_Patient_Link_ID;
--2046837

-- Get second vaccine dose (if exists) - assume dose within 14 days is same dose
IF OBJECT_ID('tempdb..#VacTemp2') IS NOT NULL DROP TABLE #VacTemp2;
select c.FK_Patient_Link_ID, MIN(c.EventDate) AS VaccineDoseDate
into #VacTemp2
from #VacTemp1 v
inner join #COVIDVaccines c on c.EventDate > DATEADD(day, 14, v.VaccineDoseDate) and c.FK_Patient_Link_ID = v.FK_Patient_Link_ID
group by c.FK_Patient_Link_ID;
--1810762

-- Get third vaccine dose (if exists) - assume dose within 14 days is same dose
IF OBJECT_ID('tempdb..#VacTemp3') IS NOT NULL DROP TABLE #VacTemp3;
select c.FK_Patient_Link_ID, MIN(c.EventDate) AS VaccineDoseDate
into #VacTemp3
from #VacTemp2 v
inner join #COVIDVaccines c on c.EventDate > DATEADD(day, 14, v.VaccineDoseDate) and c.FK_Patient_Link_ID = v.FK_Patient_Link_ID
group by c.FK_Patient_Link_ID;
--578468

-- Get fourth vaccine dose (if exists) - assume dose within 14 days is same dose
IF OBJECT_ID('tempdb..#VacTemp4') IS NOT NULL DROP TABLE #VacTemp4;
select c.FK_Patient_Link_ID, MIN(c.EventDate) AS VaccineDoseDate
into #VacTemp4
from #VacTemp3 v
inner join #COVIDVaccines c on c.EventDate > DATEADD(day, 14, v.VaccineDoseDate) and c.FK_Patient_Link_ID = v.FK_Patient_Link_ID
group by c.FK_Patient_Link_ID;
--1860

-- Get fifth vaccine dose (if exists) - assume dose within 14 days is same dose
IF OBJECT_ID('tempdb..#VacTemp5') IS NOT NULL DROP TABLE #VacTemp5;
select c.FK_Patient_Link_ID, MIN(c.EventDate) AS VaccineDoseDate
into #VacTemp5
from #VacTemp4 v
inner join #COVIDVaccines c on c.EventDate > DATEADD(day, 14, v.VaccineDoseDate) and c.FK_Patient_Link_ID = v.FK_Patient_Link_ID
group by c.FK_Patient_Link_ID;
--39

-- Get sixth vaccine dose (if exists) - assume dose within 14 days is same dose
IF OBJECT_ID('tempdb..#VacTemp6') IS NOT NULL DROP TABLE #VacTemp6;
select c.FK_Patient_Link_ID, MIN(c.EventDate) AS VaccineDoseDate
into #VacTemp6
from #VacTemp5 v
inner join #COVIDVaccines c on c.EventDate > DATEADD(day, 14, v.VaccineDoseDate) and c.FK_Patient_Link_ID = v.FK_Patient_Link_ID
group by c.FK_Patient_Link_ID;
--2

-- Get seventh vaccine dose (if exists) - assume dose within 14 days is same dose
IF OBJECT_ID('tempdb..#VacTemp7') IS NOT NULL DROP TABLE #VacTemp7;
select c.FK_Patient_Link_ID, MIN(c.EventDate) AS VaccineDoseDate
into #VacTemp7
from #VacTemp6 v
inner join #COVIDVaccines c on c.EventDate > DATEADD(day, 14, v.VaccineDoseDate) and c.FK_Patient_Link_ID = v.FK_Patient_Link_ID
group by c.FK_Patient_Link_ID;
--2

IF OBJECT_ID('tempdb..#COVIDVaccinations') IS NOT NULL DROP TABLE #COVIDVaccinations;
SELECT v1.FK_Patient_Link_ID, v1.VaccineDoseDate AS VaccineDose1Date,
v2.VaccineDoseDate AS VaccineDose2Date,
v3.VaccineDoseDate AS VaccineDose3Date,
v4.VaccineDoseDate AS VaccineDose4Date,
v5.VaccineDoseDate AS VaccineDose5Date,
v6.VaccineDoseDate AS VaccineDose6Date,
v7.VaccineDoseDate AS VaccineDose7Date
INTO #COVIDVaccinations
FROM #VacTemp1 v1
LEFT OUTER JOIN #VacTemp2 v2 ON v2.FK_Patient_Link_ID = v1.FK_Patient_Link_ID
LEFT OUTER JOIN #VacTemp3 v3 ON v3.FK_Patient_Link_ID = v1.FK_Patient_Link_ID
LEFT OUTER JOIN #VacTemp4 v4 ON v4.FK_Patient_Link_ID = v1.FK_Patient_Link_ID
LEFT OUTER JOIN #VacTemp5 v5 ON v5.FK_Patient_Link_ID = v1.FK_Patient_Link_ID
LEFT OUTER JOIN #VacTemp6 v6 ON v6.FK_Patient_Link_ID = v1.FK_Patient_Link_ID
LEFT OUTER JOIN #VacTemp7 v7 ON v7.FK_Patient_Link_ID = v1.FK_Patient_Link_ID;

-- Tidy up
DROP TABLE #VacTemp1;
DROP TABLE #VacTemp2;
DROP TABLE #VacTemp3;
DROP TABLE #VacTemp4;
DROP TABLE #VacTemp5;
DROP TABLE #VacTemp6;
DROP TABLE #VacTemp7;


--┌─────────────────────────────────────────┐
--│ Secondary admissions and length of stay │
--└─────────────────────────────────────────┘

-- OBJECTIVE: To obtain a table with every secondary care admission, along with the acute provider,
--						the date of admission, the date of discharge, and the length of stay.

-- INPUT: One parameter
--	-	all-patients: boolean - (true/false) if true, then all patients are included, otherwise only those in the pre-existing #Patients table.

-- OUTPUT: Two temp table as follows:
-- #Admissions (FK_Patient_Link_ID, AdmissionDate, AcuteProvider)
-- 	- FK_Patient_Link_ID - unique patient id
--	- AdmissionDate - date of admission (YYYY-MM-DD)
--	- AcuteProvider - Bolton, SRFT, Stockport etc..
--  (Limited to one admission per person per hospital per day, because if a patient has 2 admissions 
--   on the same day to the same hopsital then it's most likely data duplication rather than two short
--   hospital stays)
-- #LengthOfStay (FK_Patient_Link_ID, AdmissionDate)
-- 	- FK_Patient_Link_ID - unique patient id
--	- AdmissionDate - date of admission (YYYY-MM-DD)
--	- AcuteProvider - Bolton, SRFT, Stockport etc..
--	- DischargeDate - date of discharge (YYYY-MM-DD)
--	- LengthOfStay - Number of days between admission and discharge. 1 = [0,1) days, 2 = [1,2) days, etc.

-- Set the temp end date until new legal basis
DECLARE @TEMPAdmissionsEndDate datetime;
SET @TEMPAdmissionsEndDate = '2022-06-01';

-- Populate temporary table with admissions
-- Convert AdmissionDate to a date to avoid issues where a person has two admissions
-- on the same day (but only one discharge)
IF OBJECT_ID('tempdb..#Admissions') IS NOT NULL DROP TABLE #Admissions;
CREATE TABLE #Admissions (
	FK_Patient_Link_ID BIGINT,
	AdmissionDate DATE,
	AcuteProvider NVARCHAR(150)
);
BEGIN
	IF 'false'='true'
		INSERT INTO #Admissions
		SELECT DISTINCT FK_Patient_Link_ID, CONVERT(DATE, AdmissionDate) AS AdmissionDate, t.TenancyName AS AcuteProvider
		FROM [RLS].[vw_Acute_Inpatients] i
		LEFT OUTER JOIN SharedCare.Reference_Tenancy t ON t.PK_Reference_Tenancy_ID = i.FK_Reference_Tenancy_ID
		WHERE EventType = 'Admission'
		AND AdmissionDate >= @StartDate
		AND AdmissionDate <= @TEMPAdmissionsEndDate;
	ELSE
		INSERT INTO #Admissions
		SELECT DISTINCT FK_Patient_Link_ID, CONVERT(DATE, AdmissionDate) AS AdmissionDate, t.TenancyName AS AcuteProvider
		FROM [RLS].[vw_Acute_Inpatients] i
		LEFT OUTER JOIN SharedCare.Reference_Tenancy t ON t.PK_Reference_Tenancy_ID = i.FK_Reference_Tenancy_ID
		WHERE EventType = 'Admission'
		AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
		AND AdmissionDate >= @StartDate
		AND AdmissionDate <= @TEMPAdmissionsEndDate;
END

--┌──────────────────────┐
--│ Secondary discharges │
--└──────────────────────┘

-- OBJECTIVE: To obtain a table with every secondary care discharge, along with the acute provider,
--						and the date of discharge.

-- INPUT: One parameter
--	-	all-patients: boolean - (true/false) if true, then all patients are included, otherwise only those in the pre-existing #Patients table.

-- OUTPUT: A temp table as follows:
-- #Discharges (FK_Patient_Link_ID, DischargeDate, AcuteProvider)
-- 	- FK_Patient_Link_ID - unique patient id
--	- DischargeDate - date of discharge (YYYY-MM-DD)
--	- AcuteProvider - Bolton, SRFT, Stockport etc..
--  (Limited to one discharge per person per hospital per day, because if a patient has 2 discharges 
--   on the same day to the same hopsital then it's most likely data duplication rather than two short
--   hospital stays)

-- Set the temp end date until new legal basis
DECLARE @TEMPDischargesEndDate datetime;
SET @TEMPDischargesEndDate = '2022-06-01';

-- Populate temporary table with discharges
IF OBJECT_ID('tempdb..#Discharges') IS NOT NULL DROP TABLE #Discharges;
CREATE TABLE #Discharges (
	FK_Patient_Link_ID BIGINT,
	DischargeDate DATE,
	AcuteProvider NVARCHAR(150)
);
BEGIN
	IF 'false'='true'
		INSERT INTO #Discharges
    SELECT DISTINCT FK_Patient_Link_ID, CONVERT(DATE, DischargeDate) AS DischargeDate, t.TenancyName AS AcuteProvider 
    FROM [RLS].[vw_Acute_Inpatients] i
    LEFT OUTER JOIN SharedCare.Reference_Tenancy t ON t.PK_Reference_Tenancy_ID = i.FK_Reference_Tenancy_ID
    WHERE EventType = 'Discharge'
    AND DischargeDate >= @StartDate
    AND DischargeDate <= @TEMPDischargesEndDate;
  ELSE
		INSERT INTO #Discharges
    SELECT DISTINCT FK_Patient_Link_ID, CONVERT(DATE, DischargeDate) AS DischargeDate, t.TenancyName AS AcuteProvider 
    FROM [RLS].[vw_Acute_Inpatients] i
    LEFT OUTER JOIN SharedCare.Reference_Tenancy t ON t.PK_Reference_Tenancy_ID = i.FK_Reference_Tenancy_ID
    WHERE EventType = 'Discharge'
		AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
    AND DischargeDate >= @StartDate
    AND DischargeDate <= @TEMPDischargesEndDate;;
END
-- 535285 rows	535285 rows
-- 00:00:28		00:00:14


-- Link admission with discharge to get length of stay
-- Length of stay is zero-indexed e.g. 
-- 1 = [0,1) days
-- 2 = [1,2) days
IF OBJECT_ID('tempdb..#LengthOfStay') IS NOT NULL DROP TABLE #LengthOfStay;
SELECT 
	a.FK_Patient_Link_ID, a.AdmissionDate, a.AcuteProvider, 
	MIN(d.DischargeDate) AS DischargeDate, 
	1 + DATEDIFF(day,a.AdmissionDate, MIN(d.DischargeDate)) AS LengthOfStay
	INTO #LengthOfStay
FROM #Admissions a
INNER JOIN #Discharges d ON d.FK_Patient_Link_ID = a.FK_Patient_Link_ID AND d.DischargeDate >= a.AdmissionDate AND d.AcuteProvider = a.AcuteProvider
GROUP BY a.FK_Patient_Link_ID, a.AdmissionDate, a.AcuteProvider
ORDER BY a.FK_Patient_Link_ID, a.AdmissionDate, a.AcuteProvider;
-- 511740 rows	511740 rows	
-- 00:00:04		00:00:05


-- Now find hospital admission following each of up to 5 covid positive tests
IF OBJECT_ID('tempdb..#PatientsAdmissionsPostTest') IS NOT NULL DROP TABLE #PatientsAdmissionsPostTest;
CREATE TABLE #PatientsAdmissionsPostTest (
  FK_Patient_Link_ID BIGINT,
  [FirstAdmissionPost1stCOVIDTest] DATE,
  [FirstAdmissionPost2ndCOVIDTest] DATE,
  [FirstAdmissionPost3rdCOVIDTest] DATE
);

-- Populate table with patient IDs
INSERT INTO #PatientsAdmissionsPostTest (FK_Patient_Link_ID)
SELECT FK_Patient_Link_ID FROM #CovidPatientsMultipleDiagnoses;

-- Find 1st hospital stay following 1st COVID positive test (but before 2nd)
UPDATE t1
SET t1.[FirstAdmissionPost1stCOVIDTest] = NextAdmissionDate
FROM #PatientsAdmissionsPostTest AS t1
INNER JOIN (
SELECT cp.FK_Patient_Link_ID, MIN(los.AdmissionDate) AS NextAdmissionDate FROM #CovidPatientsMultipleDiagnoses cp
INNER JOIN #LengthOfStay los ON cp.FK_Patient_Link_ID = los.FK_Patient_Link_ID 
	AND los.AdmissionDate >= DATEADD(day, -2, FirstCovidPositiveDate) -- hospital AFTER COVID test
	AND (los.AdmissionDate < SecondCovidPositiveDate OR SecondCovidPositiveDate IS NULL) --hospital BEFORE next COVID test
GROUP BY cp.FK_Patient_Link_ID) AS sub ON sub.FK_Patient_Link_ID = t1.FK_Patient_Link_ID;

-- Find 1st hospital stay following 2nd COVID positive test (but before 3rd)
UPDATE t1
SET t1.[FirstAdmissionPost2ndCOVIDTest] = NextAdmissionDate
FROM #PatientsAdmissionsPostTest AS t1
INNER JOIN (
SELECT cp.FK_Patient_Link_ID, MIN(los.AdmissionDate) AS NextAdmissionDate FROM #CovidPatientsMultipleDiagnoses cp
INNER JOIN #LengthOfStay los ON cp.FK_Patient_Link_ID = los.FK_Patient_Link_ID 
	AND los.AdmissionDate >= DATEADD(day, -2, SecondCovidPositiveDate) -- hospital AFTER COVID test
	AND (los.AdmissionDate < ThirdCovidPositiveDate OR ThirdCovidPositiveDate IS NULL)  --hospital BEFORE next COVID test
GROUP BY cp.FK_Patient_Link_ID) AS sub ON sub.FK_Patient_Link_ID = t1.FK_Patient_Link_ID;

-- Find 1st hospital stay following 3rd COVID positive test (but before 4th)
UPDATE t1
SET t1.[FirstAdmissionPost3rdCOVIDTest] = NextAdmissionDate
FROM #PatientsAdmissionsPostTest AS t1
INNER JOIN (
SELECT cp.FK_Patient_Link_ID, MIN(los.AdmissionDate) AS NextAdmissionDate FROM #CovidPatientsMultipleDiagnoses cp
INNER JOIN #LengthOfStay los ON cp.FK_Patient_Link_ID = los.FK_Patient_Link_ID 
	AND los.AdmissionDate >= DATEADD(day, -2, ThirdCovidPositiveDate) -- hospital AFTER COVID test
	AND (los.AdmissionDate < FourthCovidPositiveDate OR FourthCovidPositiveDate IS NULL)  --hospital BEFORE next COVID test
GROUP BY cp.FK_Patient_Link_ID) AS sub ON sub.FK_Patient_Link_ID = t1.FK_Patient_Link_ID;

-- Get length of stay for each admission just calculated
IF OBJECT_ID('tempdb..#PatientsLOSPostTest') IS NOT NULL DROP TABLE #PatientsLOSPostTest;
SELECT p.FK_Patient_Link_ID, 
		MAX(l1.LengthOfStay) AS LengthOfStayFirstAdmission1stCOVIDTest,
		MAX(l2.LengthOfStay) AS LengthOfStayFirstAdmission2ndCOVIDTest,
		MAX(l3.LengthOfStay) AS LengthOfStayFirstAdmission3rdCOVIDTest
INTO #PatientsLOSPostTest
FROM #PatientsAdmissionsPostTest p
	LEFT OUTER JOIN #LengthOfStay l1 ON p.FK_Patient_Link_ID = l1.FK_Patient_Link_ID AND p.[FirstAdmissionPost1stCOVIDTest] = l1.AdmissionDate
	LEFT OUTER JOIN #LengthOfStay l2 ON p.FK_Patient_Link_ID = l2.FK_Patient_Link_ID AND p.[FirstAdmissionPost2ndCOVIDTest] = l2.AdmissionDate
	LEFT OUTER JOIN #LengthOfStay l3 ON p.FK_Patient_Link_ID = l3.FK_Patient_Link_ID AND p.[FirstAdmissionPost3rdCOVIDTest] = l3.AdmissionDate
GROUP BY p.FK_Patient_Link_ID;

-- diagnoses
-- >>> Following code sets injected: asthma v1
IF OBJECT_ID('tempdb..#PatientDiagnosesASTHMA') IS NOT NULL DROP TABLE #PatientDiagnosesASTHMA;
SELECT DISTINCT FK_Patient_Link_ID
INTO #PatientDiagnosesASTHMA
FROM RLS.vw_GP_Events
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (Concept IN ('asthma') AND [Version]=1)) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept IN ('asthma') AND [Version]=1))
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate < @TEMPRQ043EndDate;

-- >>> Following code sets injected: coronary-heart-disease v1
IF OBJECT_ID('tempdb..#PatientDiagnosesCHD') IS NOT NULL DROP TABLE #PatientDiagnosesCHD;
SELECT DISTINCT FK_Patient_Link_ID
INTO #PatientDiagnosesCHD
FROM RLS.vw_GP_Events
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (Concept IN ('coronary-heart-disease') AND [Version]=1)) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept IN ('coronary-heart-disease') AND [Version]=1))
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate < @TEMPRQ043EndDate;

-- >>> Following code sets injected: stroke v1
IF OBJECT_ID('tempdb..#PatientDiagnosesSTROKE') IS NOT NULL DROP TABLE #PatientDiagnosesSTROKE;
SELECT DISTINCT FK_Patient_Link_ID
INTO #PatientDiagnosesSTROKE
FROM RLS.vw_GP_Events
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (Concept IN ('stroke') AND [Version]=1)) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept IN ('stroke') AND [Version]=1))
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate < @TEMPRQ043EndDate;

-- >>> Following code sets injected: diabetes-type-i v1
IF OBJECT_ID('tempdb..#PatientDiagnosesT1DM') IS NOT NULL DROP TABLE #PatientDiagnosesT1DM;
SELECT DISTINCT FK_Patient_Link_ID
INTO #PatientDiagnosesT1DM
FROM RLS.vw_GP_Events
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (Concept IN ('diabetes-type-i') AND [Version]=1)) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept IN ('diabetes-type-i') AND [Version]=1))
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate < @TEMPRQ043EndDate;

-- >>> Following code sets injected: diabetes-type-ii v1
IF OBJECT_ID('tempdb..#PatientDiagnosesT2DM') IS NOT NULL DROP TABLE #PatientDiagnosesT2DM;
SELECT DISTINCT FK_Patient_Link_ID
INTO #PatientDiagnosesT2DM
FROM RLS.vw_GP_Events
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (Concept IN ('diabetes-type-ii') AND [Version]=1)) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept IN ('diabetes-type-ii') AND [Version]=1))
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate < @TEMPRQ043EndDate;

-- >>> Following code sets injected: copd v1
IF OBJECT_ID('tempdb..#PatientDiagnosesCOPD') IS NOT NULL DROP TABLE #PatientDiagnosesCOPD;
SELECT DISTINCT FK_Patient_Link_ID
INTO #PatientDiagnosesCOPD
FROM RLS.vw_GP_Events
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (Concept IN ('copd') AND [Version]=1)) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept IN ('copd') AND [Version]=1))
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate < @TEMPRQ043EndDate;

-- >>> Following code sets injected: hypertension v1
IF OBJECT_ID('tempdb..#PatientDiagnosesHYPERTENSION') IS NOT NULL DROP TABLE #PatientDiagnosesHYPERTENSION;
SELECT DISTINCT FK_Patient_Link_ID
INTO #PatientDiagnosesHYPERTENSION
FROM RLS.vw_GP_Events
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (Concept IN ('hypertension') AND [Version]=1)) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept IN ('hypertension') AND [Version]=1))
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND EventDate < @TEMPRQ043EndDate;

-- >>> Following code sets injected: bmi v2
IF OBJECT_ID('tempdb..#PatientValuesWithIds') IS NOT NULL DROP TABLE #PatientValuesWithIds;
SELECT 
	FK_Patient_Link_ID,
	CAST(EventDate AS DATE) AS EventDate,
	[Value]
INTO #PatientValuesWithIds
FROM RLS.vw_GP_Events
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets WHERE (Concept IN ('bmi') AND [Version]=2)) OR
  FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets WHERE (Concept IN ('bmi') AND [Version]=2))
)
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND [Value] IS NOT NULL
AND [Value] != '0'
AND EventDate < @TEMPRQ043EndDate;

-- get most recent value at in the period [index date - 2 years, index date]
IF OBJECT_ID('tempdb..#PatientValuesBMI') IS NOT NULL DROP TABLE #PatientValuesBMI;
SELECT main.FK_Patient_Link_ID, MAX(main.[Value]) AS LatestValue
INTO #PatientValuesBMI
FROM #PatientValuesWithIds main
INNER JOIN (
  SELECT p.FK_Patient_Link_ID, MAX(EventDate) AS LatestDate FROM #PatientValuesWithIds pv
  INNER JOIN #CovidPatients p 
    ON p.FK_Patient_Link_ID = pv.FK_Patient_Link_ID
    AND pv.EventDate <= p.FirstCovidPositiveDate
  GROUP BY p.FK_Patient_Link_ID
) sub on sub.FK_Patient_Link_ID = main.FK_Patient_Link_ID and sub.LatestDate = main.EventDate
GROUP BY main.FK_Patient_Link_ID;

-- Not needed. Tidy up.
DROP TABLE #PatientValuesWithIds;

-- Get patient list of those with COVID death within 28 days of positive test
IF OBJECT_ID('tempdb..#COVIDDeath') IS NOT NULL DROP TABLE #COVIDDeath;
SELECT DISTINCT FK_Patient_Link_ID 
INTO #COVIDDeath FROM RLS.vw_COVID19
WHERE DeathWithin28Days = 'Y'
AND (
  (GroupDescription = 'Confirmed' AND SubGroupDescription != 'Negative') OR
  (GroupDescription = 'Tested' AND SubGroupDescription = 'Positive')
);

-- Get start date at LSOA from address history.
-- NB !! Virtually all start dates are post 2019 i.e. the start date
-- is either when they moved in OR when the data feed started OR
-- when they first registered with a GM GP. So not great, but PI is
-- aware of this.

-- First find the earliest start date for their current LSOA
IF OBJECT_ID('tempdb..#PatientLSOAEarliestStart') IS NOT NULL DROP TABLE #PatientLSOAEarliestStart;
select l.FK_Patient_Link_ID, MIN(StartDate) AS EarliestStartDate
into #PatientLSOAEarliestStart
from #PatientLSOA l
left outer join RLS.vw_Patient_Address_History h
	on h.FK_Patient_Link_ID = l.FK_Patient_Link_ID
	and h.LSOA_Code = l.LSOA_Code
WHERE StartDate < @TEMPRQ043EndDate
group by l.FK_Patient_Link_ID;

-- Now find the most recent end date for not their current LSOA
IF OBJECT_ID('tempdb..#PatientLSOALatestEnd') IS NOT NULL DROP TABLE #PatientLSOALatestEnd;
select l.FK_Patient_Link_ID, MAX(EndDate) AS LatestEndDate
into #PatientLSOALatestEnd
from #PatientLSOA l
left outer join RLS.vw_Patient_Address_History h
	on h.FK_Patient_Link_ID = l.FK_Patient_Link_ID
	and h.LSOA_Code != l.LSOA_Code
where EndDate is not null
AND EndDate < @TEMPRQ043EndDate
group by l.FK_Patient_Link_ID;

-- Bring together. Either earliest start date or most recent end date of a different LSOA (if it exists).
IF OBJECT_ID('tempdb..#PatientLSOAStartDates') IS NOT NULL DROP TABLE #PatientLSOAStartDates;
select 
	s.FK_Patient_Link_ID,
	CAST (
	CASE
		WHEN LatestEndDate is null THEN EarliestStartDate
		WHEN EarliestStartDate > LatestEndDate THEN EarliestStartDate
		ELSE LatestEndDate
	END AS DATE) AS LSOAStartDate
into #PatientLSOAStartDates
from #PatientLSOAEarliestStart s
left outer join #PatientLSOALatestEnd e
on e.FK_Patient_Link_ID = s.FK_Patient_Link_ID;

-- Get the patients gp practice so we can identify the GP system
--┌───────────────────────────────────────┐
--│ GET practice and ccg for each patient │
--└───────────────────────────────────────┘

-- OBJECTIVE:	For each patient to get the practice id that they are registered to, and 
--						the CCG name that the practice belongs to.

-- INPUT: Assumes there exists a temp table as follows:
-- #Patients (FK_Patient_Link_ID)
--  A distinct list of FK_Patient_Link_IDs for each patient in the cohort

-- OUTPUT: Two temp tables as follows:
-- #PatientPractice (FK_Patient_Link_ID, GPPracticeCode)
--	- FK_Patient_Link_ID - unique patient id
--	- GPPracticeCode - the nationally recognised practice id for the patient
-- #PatientPracticeAndCCG (FK_Patient_Link_ID, GPPracticeCode, CCG)
--	- FK_Patient_Link_ID - unique patient id
--	- GPPracticeCode - the nationally recognised practice id for the patient
--	- CCG - the name of the patient's CCG

-- If patients have a tenancy id of 2 we take this as their most likely GP practice
-- as this is the GP data feed and so most likely to be up to date
IF OBJECT_ID('tempdb..#PatientPractice') IS NOT NULL DROP TABLE #PatientPractice;
SELECT FK_Patient_Link_ID, MIN(GPPracticeCode) as GPPracticeCode INTO #PatientPractice FROM RLS.vw_Patient
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
AND FK_Reference_Tenancy_ID = 2
AND GPPracticeCode IS NOT NULL
GROUP BY FK_Patient_Link_ID;
-- 1298467 rows
-- 00:00:11

-- Find the patients who remain unmatched
IF OBJECT_ID('tempdb..#UnmatchedPatientsForPracticeCode') IS NOT NULL DROP TABLE #UnmatchedPatientsForPracticeCode;
SELECT FK_Patient_Link_ID INTO #UnmatchedPatientsForPracticeCode FROM #Patients
EXCEPT
SELECT FK_Patient_Link_ID FROM #PatientPractice;
-- 12702 rows
-- 00:00:00

-- If every GPPracticeCode is the same for all their linked patient ids then we use that
INSERT INTO #PatientPractice
SELECT FK_Patient_Link_ID, MIN(GPPracticeCode) FROM RLS.vw_Patient
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #UnmatchedPatientsForPracticeCode)
AND GPPracticeCode IS NOT NULL
GROUP BY FK_Patient_Link_ID
HAVING MIN(GPPracticeCode) = MAX(GPPracticeCode);
-- 12141
-- 00:00:00

-- Find any still unmatched patients
TRUNCATE TABLE #UnmatchedPatientsForPracticeCode;
INSERT INTO #UnmatchedPatientsForPracticeCode
SELECT FK_Patient_Link_ID FROM #Patients
EXCEPT
SELECT FK_Patient_Link_ID FROM #PatientPractice;
-- 561 rows
-- 00:00:00

-- If there is a unique most recent gp practice then we use that
INSERT INTO #PatientPractice
SELECT p.FK_Patient_Link_ID, MIN(p.GPPracticeCode) FROM RLS.vw_Patient p
INNER JOIN (
	SELECT FK_Patient_Link_ID, MAX(HDMModifDate) MostRecentDate FROM RLS.vw_Patient
	WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #UnmatchedPatientsForPracticeCode)
	GROUP BY FK_Patient_Link_ID
) sub ON sub.FK_Patient_Link_ID = p.FK_Patient_Link_ID AND sub.MostRecentDate = p.HDMModifDate
WHERE p.GPPracticeCode IS NOT NULL
GROUP BY p.FK_Patient_Link_ID
HAVING MIN(GPPracticeCode) = MAX(GPPracticeCode);
-- 15

--┌──────────────────┐
--│ CCG lookup table │
--└──────────────────┘

-- OBJECTIVE: To provide lookup table for CCG names. The GMCR provides the CCG id (e.g. '00T', '01G') but not 
--            the CCG name. This table can be used in other queries when the output is required to be a ccg 
--            name rather than an id.

-- INPUT: No pre-requisites

-- OUTPUT: A temp table as follows:
-- #CCGLookup (CcgId, CcgName)
-- 	- CcgId - Nationally recognised ccg id
--	- CcgName - Bolton, Stockport etc..

IF OBJECT_ID('tempdb..#CCGLookup') IS NOT NULL DROP TABLE #CCGLookup;
CREATE TABLE #CCGLookup (CcgId nchar(3), CcgName nvarchar(20));
INSERT INTO #CCGLookup VALUES ('01G', 'Salford'); 
INSERT INTO #CCGLookup VALUES ('00T', 'Bolton'); 
INSERT INTO #CCGLookup VALUES ('01D', 'HMR'); 
INSERT INTO #CCGLookup VALUES ('02A', 'Trafford'); 
INSERT INTO #CCGLookup VALUES ('01W', 'Stockport');
INSERT INTO #CCGLookup VALUES ('00Y', 'Oldham'); 
INSERT INTO #CCGLookup VALUES ('02H', 'Wigan'); 
INSERT INTO #CCGLookup VALUES ('00V', 'Bury'); 
INSERT INTO #CCGLookup VALUES ('14L', 'Manchester'); 
INSERT INTO #CCGLookup VALUES ('01Y', 'Tameside Glossop'); 

IF OBJECT_ID('tempdb..#PatientPracticeAndCCG') IS NOT NULL DROP TABLE #PatientPracticeAndCCG;
SELECT p.FK_Patient_Link_ID, ISNULL(pp.GPPracticeCode,'') AS GPPracticeCode, ISNULL(ccg.CcgName, '') AS CCG
INTO #PatientPracticeAndCCG
FROM #Patients p
LEFT OUTER JOIN #PatientPractice pp ON pp.FK_Patient_Link_ID = p.FK_Patient_Link_ID
LEFT OUTER JOIN SharedCare.Reference_GP_Practice gp ON gp.OrganisationCode = pp.GPPracticeCode
LEFT OUTER JOIN #CCGLookup ccg ON ccg.CcgId = gp.Commissioner;
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


SELECT 
  m.FK_Patient_Link_ID AS PatientId,
  FirstCovidPositiveDate,
  SecondCovidPositiveDate,
  ThirdCovidPositiveDate,
  FirstAdmissionPost1stCOVIDTest,
  LengthOfStayFirstAdmission1stCOVIDTest,
  FirstAdmissionPost2ndCOVIDTest,
  LengthOfStayFirstAdmission2ndCOVIDTest,
  FirstAdmissionPost3rdCOVIDTest,
  LengthOfStayFirstAdmission3rdCOVIDTest,
  CASE WHEN DeathDate < @TEMPRQ043EndDate THEN MONTH(DeathDate) ELSE NULL END AS MonthOfDeath,
  CASE WHEN DeathDate < @TEMPRQ043EndDate THEN YEAR(DeathDate) ELSE NULL END AS YearOfDeath,
  CASE WHEN covidDeath.FK_Patient_Link_ID IS NULL THEN 'N' ELSE 'Y' END AS DeathWithin28DaysCovidPositiveTest,
  LSOA_Code AS LSOA,
  lsoaStart.LSOAStartDate AS LSOAStartDate,
  YearOfBirth,
  Sex,
  EthnicCategoryDescription,
  IMD2019Decile1IsMostDeprived10IsLeastDeprived,
  CASE WHEN asthma.FK_Patient_Link_ID IS NULL THEN 'N' ELSE 'Y' END AS PatientHasASTHMA,
  CASE WHEN chd.FK_Patient_Link_ID IS NULL THEN 'N' ELSE 'Y' END AS PatientHasCHD,
  CASE WHEN stroke.FK_Patient_Link_ID IS NULL THEN 'N' ELSE 'Y' END AS PatientHasSTROKE,
  CASE WHEN t1dm.FK_Patient_Link_ID IS NULL THEN 'N' ELSE 'Y' END AS PatientHasT1DM,
  CASE WHEN t2dm.FK_Patient_Link_ID IS NULL THEN 'N' ELSE 'Y' END AS PatientHasT2DM,
  CASE WHEN copd.FK_Patient_Link_ID IS NULL THEN 'N' ELSE 'Y' END AS PatientHasCOPD,
  CASE WHEN htn.FK_Patient_Link_ID IS NULL THEN 'N' ELSE 'Y' END AS PatientHasHYPERTENSION,
  smok.WorstSmokingStatus,
  smok.CurrentSmokingStatus,
  bmi.LatestValue AS LatestBMIValue,
  VaccineDose1Date,
  VaccineDose2Date,
  VaccineDose3Date,
  VaccineDose4Date,
  VaccineDose5Date,
  sys.System
  --,Occupation
FROM #Patients m
LEFT OUTER JOIN RLS.vw_Patient_Link pl ON pl.PK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientLSOA lsoa ON lsoa.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientLSOAStartDates lsoaStart ON lsoaStart.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientSex sex ON sex.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientYearOfBirth yob ON yob.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientIMDDecile imd ON imd.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosesASTHMA asthma ON asthma.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosesCHD chd ON chd.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosesSTROKE stroke ON stroke.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosesT1DM t1dm ON t1dm.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosesT2DM t2dm ON t2dm.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosesCOPD copd ON copd.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientDiagnosesHYPERTENSION htn ON htn.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientSmokingStatus smok ON smok.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #COVIDDeath covidDeath ON covidDeath.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #COVIDVaccinations v ON v.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #CovidPatientsMultipleDiagnoses cov ON cov.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientsAdmissionsPostTest admit ON admit.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientsLOSPostTest los ON los.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientValuesBMI bmi ON bmi.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PatientPractice prac on prac.FK_Patient_Link_ID = m.FK_Patient_Link_ID
LEFT OUTER JOIN #PracticeSystemLookup sys on sys.PracticeId = ppp.GPPracticeCode;