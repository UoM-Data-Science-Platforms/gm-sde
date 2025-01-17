--┌───────────────────────┐
--│ Patient GP encounters │
--└───────────────────────┘

-- OBJECTIVE: To produce a table of GP encounters for a list of patients.
-- This script uses many codes related to observations (e.g. blood pressure), symptoms, and diagnoses, to infer when GP encounters occured.
-- This script includes face to face and telephone encounters - it will need copying and editing if you don't require both.

-- ASSUMPTIONS:
--	- multiple codes on the same day will be classed as one encounter (so max daily encounters per patient is 1)

-- INPUT: Assumes there exists a temp table as follows:
-- #Patients (FK_Patient_Link_ID)
--  A distinct list of FK_Patient_Link_IDs for each patient in the cohort

-- Also takes parameters:
--	-	all-patients: boolean - (true/false) if true, then all patients are included, otherwise only those in the pre-existing #Patients table.
--	- gp-events-table: string - (table name) the name of the table containing the GP events. Usually is "RLS.vw_GP_Events" but can be anything with the columns: FK_Patient_Link_ID, EventDate, FK_Reference_Coding_ID, and FK_Reference_SnomedCT_ID
--  - start-date: string - (YYYY-MM-DD) the date to count encounters from.
--  - end-date: string - (YYYY-MM-DD) the date to count encounters to.


-- OUTPUT: A temp table as follows:
-- #GPEncounters (FK_Patient_Link_ID, EncounterDate)
--	- FK_Patient_Link_ID - unique patient id
--	- EncounterDate - date the patient had a GP encounter


-- Create a table with all GP encounters ========================================================================================================

IF OBJECT_ID('tempdb..#CodingClassifier') IS NOT NULL DROP TABLE #CodingClassifier;
SELECT 'Face2face' AS EncounterType, PK_Reference_Coding_ID, FK_Reference_SnomedCT_ID
INTO #CodingClassifier
FROM SharedCare.Reference_Coding
WHERE CodingType='ReadCodeV2'
AND (
	MainCode like '1%'
	or MainCode like '2%'
	or MainCode in ('6A2..','6A9..','6AA..','6AB..','662d.','662e.','66AS.','66AS0','66AT.','66BB.','66f0.','66YJ.','66YM.','661Q.','66480','6AH..','6A9..','66p0.','6A2..','66Ay.','66Az.','69DC.')
	or MainCode like '6A%'
	or MainCode like '65%'
	or MainCode like '8B31[356]%'
	or MainCode like '8B3[3569ADEfilOqRxX]%'
	or MainCode in ('8BS3.')
	or MainCode like '8H[4-8]%' 
	or MainCode like '94Z%'
	or MainCode like '9N1C%' 
	or MainCode like '9N21%'
	or MainCode in ('9kF1.','9kR..','9HB5.')
	or MainCode like '9H9%'
);

INSERT INTO #CodingClassifier
SELECT 'Telephone', PK_Reference_Coding_ID, FK_Reference_SnomedCT_ID
FROM SharedCare.Reference_Coding
WHERE CodingType='ReadCodeV2'
AND (
	MainCode like '8H9%'
	or MainCode like '9N31%'
	or MainCode like '9N3A%'
);

-- Add the equivalent CTV3 codes
INSERT INTO #CodingClassifier
SELECT 'Face2face', PK_Reference_Coding_ID, FK_Reference_SnomedCT_ID FROM SharedCare.Reference_Coding
WHERE FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #CodingClassifier WHERE EncounterType='Face2face' AND FK_Reference_SnomedCT_ID != -1)
AND CodingType='CTV3';

INSERT INTO #CodingClassifier
SELECT 'Telephone', PK_Reference_Coding_ID, FK_Reference_SnomedCT_ID FROM SharedCare.Reference_Coding
WHERE FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #CodingClassifier WHERE EncounterType='Telephone' AND FK_Reference_SnomedCT_ID != -1)
AND CodingType='CTV3';

-- Add the equivalent EMIS codes
INSERT INTO #CodingClassifier
SELECT 'Face2face', FK_Reference_Coding_ID, FK_Reference_SnomedCT_ID FROM SharedCare.Reference_Local_Code
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #CodingClassifier WHERE EncounterType='Face2face' AND FK_Reference_SnomedCT_ID != -1) OR
	FK_Reference_Coding_ID IN (SELECT PK_Reference_Coding_ID FROM #CodingClassifier WHERE EncounterType='Face2face' AND PK_Reference_Coding_ID != -1)
);
INSERT INTO #CodingClassifier
SELECT 'Telephone', FK_Reference_Coding_ID, FK_Reference_SnomedCT_ID FROM SharedCare.Reference_Local_Code
WHERE (
	FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #CodingClassifier WHERE EncounterType='Telephone' AND FK_Reference_SnomedCT_ID != -1) OR
	FK_Reference_Coding_ID IN (SELECT PK_Reference_Coding_ID FROM #CodingClassifier WHERE EncounterType='Telephone' AND PK_Reference_Coding_ID != -1)
);

-- All above takes ~30s

IF OBJECT_ID('tempdb..#GPEncounters') IS NOT NULL DROP TABLE #GPEncounters;
CREATE TABLE #GPEncounters (
	FK_Patient_Link_ID BIGINT,
	EncounterDate DATE
);

BEGIN
  IF '{param:all-patients}'='true'
    INSERT INTO #GPEncounters 
    SELECT DISTINCT FK_Patient_Link_ID, CAST(EventDate AS DATE) AS EncounterDate
    FROM {param:gp-events-table}
    WHERE 
      FK_Reference_Coding_ID IN (SELECT PK_Reference_Coding_ID FROM #CodingClassifier WHERE PK_Reference_Coding_ID != -1)
      AND EventDate BETWEEN '{param:start-date}' AND '{param:end-date}'
  ELSE 
    INSERT INTO #GPEncounters 
    SELECT DISTINCT FK_Patient_Link_ID, CAST(EventDate AS DATE) AS EncounterDate
    FROM {param:gp-events-table}
    WHERE 
      FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
      AND FK_Reference_Coding_ID IN (SELECT PK_Reference_Coding_ID FROM #CodingClassifier WHERE PK_Reference_Coding_ID != -1)
      AND EventDate BETWEEN '{param:start-date}' AND '{param:end-date}'
  END