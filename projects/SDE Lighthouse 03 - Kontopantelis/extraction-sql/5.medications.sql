--┌─────────────┐
--│ Medications │
--└─────────────┘

-- From application:
--  Table 5: Primary Care Medications (2006 to present)
--  - PatientID
--  - PrescriptionDate
--  - MedicationGroup
-- Medications included: antipsychotics, anti-dementia meds, anticholinergics, benzodiazepines, z-drugs and sedating antihistamines

-- NB1 - PI confirmed wants columns PatientID, PrescriptionDate, MedicationGroup, MedicationType, Medication
--  e.g. 1234,2024-08-16,Antipsychotic,risperidone,Risperidone 250microgram tablets
-- NB2 - PI provided list of anticholinergics and confirmed that all sedating antihistamines are included within this group so no
--       need to have them separately
-- NB3 - Benzodiazepines and z-drugs are combined as there is an existing NHS drug refset for benzo related drugs which includes z-drugs

-- Anti dementia drugs
-- >>> Codesets required... Inserting the code set code
-- >>> Codesets extracted into 0.code-sets.sql
-- >>> Following code sets injected: donepezil v1/galantamine v1/rivastigmine v1/memantine v1

-- Anticholinergic score 1
-- >>> Following code sets injected: alimemazine v1/alprazolam v1/alverine v1/atenolol v1/beclometasone v1/bupropion v1/captopril v1
-- >>> Following code sets injected: cimetidine v1/clorazepate v1/codeine v1/colchicine v1/dextropropoxyphene v1/diazepam v1/digoxin v1
-- >>> Following code sets injected: dipyridamole v1/disopyramide-phosphate v1/fentanyl v1/fluvoxamine v1/furosemide v1/haloperidol v1
-- >>> Following code sets injected: hydralazine v1/hydrocortisone v1/isosorbide v1/loperamide v1/metoprolol v1/morphine v1/nifedipine v1
-- >>> Following code sets injected: prednisolone v1/prednisone v1/quinine v1/ranitidine v1/theophylline v1/timolol v1/trazodone v1
-- >>> Following code sets injected: triamterene v1/warfarin v1

-- Anticholinergic score 2
-- >>> Following code sets injected: amantadine v1/belladona v1/carbamazepine v1/cyclobenzaprine v1/cyproheptadine v1/loxapine v1
-- >>> Following code sets injected: pethidine v1/levomepromazine v1/oxcarbazepine v1/pimozide v1

-- Anticholinergic score 3
-- >>> Following code sets injected: amitriptyline v1/amoxapine v1/atropine v1/benztropine v1/chlorphenamine v1/chlorpromazine v1
-- >>> Following code sets injected: clemastine v1/clomipramine v1/clozapine v1/darifenacin v1/desipramine v1/dicyclomine v1
-- >>> Following code sets injected: diphenhydramine v1/doxepin v1/flavoxate v1/hydroxyzine v1/imipramine v1/meclozine v1/mepyramine v1
-- >>> Following code sets injected: nortriptyline v1/orphenadrine v1/oxybutynin v1/paroxetine v1/perphenazine v1/procyclidine v1
-- >>> Following code sets injected: promazine v1/promethazine v1/propantheline v1/scopolamine v1/solifenacin v1/tolterodine v1
-- >>> Following code sets injected: trifluoperazine v1/trihexyphenidyl v1/trimipramine v1/trospium v1

-- Populate a temp table with all the drugs without refsets that we get from GP_Medications
DROP TABLE IF EXISTS LH003_Medication_Codes;
CREATE TEMPORARY TABLE LH003_Medication_Codes AS
SELECT GmPseudo, "SuppliedCode", to_date("MedicationDate") as MedicationDate
FROM SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_03_Kontopantelis" cohort
LEFT OUTER JOIN INTERMEDIATE.GP_RECORD."GP_Medications_SecondaryUses" meds 
    ON meds."FK_Patient_ID" = cohort.FK_Patient_ID
WHERE "SuppliedCode" IN (SELECT code FROM SDE_REPOSITORY.SHARED_UTILITIES."Code_Sets_SDE_Lighthouse_03_Kontopantelis" WHERE concept IN('donepezil','galantamine','rivastigmine','memantine','alimemazine',
'alprazolam','alverine','atenolol','beclometasone','bupropion','captopril','cimetidine','clorazepate','codeine','colchicine',
'dextropropoxyphene','diazepam','digoxin','dipyridamole','disopyramide-phosphate','fentanyl','fluvoxamine','furosemide','haloperidol','hydralazine',
'hydrocortisone','isosorbide','loperamide','metoprolol','morphine','nifedipine','prednisolone','prednisone','quinine','ranitidine',
'theophylline','timolol','trazodone','triamterene','warfarin','amantadine','belladona','carbamazepine','cyclobenzaprine',
'cyproheptadine','loxapine','pethidine','levomepromazine','oxcarbazepine','pimozide','amitriptyline','amoxapine',
'atropine','benztropine','chlorphenamine','chlorpromazine','clemastine','clomipramine','clozapine','darifenacin',
'desipramine','dicyclomine','diphenhydramine','doxepin','flavoxate','hydroxyzine','imipramine','meclozine','mepyramine',
'nortriptyline','orphenadrine','oxybutynin','paroxetine','perphenazine','procyclidine','promazine','promethazine','propantheline',
'scopolamine','solifenacin','tolterodine','trifluoperazine','trihexyphenidyl','trimipramine','trospium'));

DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."5_Medications";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."5_Medications" AS
-- For antidementia and anticholinergic (no refsets) we query the data from the temp table above
SELECT
    GmPseudo AS "PatientID",
	MedicationDate AS "PrescriptionDate",
    CASE
        WHEN concept='donepezil' THEN 'Antidementia drug'
        WHEN concept='galantamine' THEN 'Antidementia drug'
        WHEN concept='rivastigmine' THEN 'Antidementia drug'
        WHEN concept='memantine' THEN 'Antidementia drug'
        WHEN concept='alimemazine' THEN 'ACB1'
        WHEN concept='alprazolam' THEN 'ACB1'
        WHEN concept='alverine' THEN 'ACB1'
        WHEN concept='atenolol' THEN 'ACB1'
        WHEN concept='beclometasone' THEN 'ACB1'
        WHEN concept='bupropion' THEN 'ACB1'
        WHEN concept='captopril' THEN 'ACB1'
        WHEN concept='cimetidine' THEN 'ACB1'
        WHEN concept='clorazepate' THEN 'ACB1'
        WHEN concept='codeine' THEN 'ACB1'
        WHEN concept='colchicine' THEN 'ACB1'
        WHEN concept='dextropropoxyphene' THEN 'ACB1'
        WHEN concept='diazepam' THEN 'ACB1'
        WHEN concept='digoxin' THEN 'ACB1'
        WHEN concept='dipyridamole' THEN 'ACB1'
        WHEN concept='disopyramide-phosphate' THEN 'ACB1'
        WHEN concept='fentanyl' THEN 'ACB1'
        WHEN concept='fluvoxamine' THEN 'ACB1'
        WHEN concept='furosemide' THEN 'ACB1'
        WHEN concept='haloperidol' THEN 'ACB1'
        WHEN concept='hydralazine' THEN 'ACB1'
        WHEN concept='hydrocortisone' THEN 'ACB1'
        WHEN concept='isosorbide' THEN 'ACB1'
        WHEN concept='loperamide' THEN 'ACB1'
        WHEN concept='metoprolol' THEN 'ACB1'
        WHEN concept='morphine' THEN 'ACB1'
        WHEN concept='nifedipine' THEN 'ACB1'
        WHEN concept='prednisolone' THEN 'ACB1'
        WHEN concept='prednisone' THEN 'ACB1'
        WHEN concept='quinine' THEN 'ACB1'
        WHEN concept='ranitidine' THEN 'ACB1'
        WHEN concept='theophylline' THEN 'ACB1'
        WHEN concept='timolol' THEN 'ACB1'
        WHEN concept='trazodone' THEN 'ACB1'
        WHEN concept='triamterene' THEN 'ACB1'
        WHEN concept='warfarin' THEN 'ACB1'
        WHEN concept='amantadine' THEN 'ACB2'
        WHEN concept='belladona' THEN 'ACB2'
        WHEN concept='carbamazepine' THEN 'ACB2'
        WHEN concept='cyclobenzaprine' THEN 'ACB2'
        WHEN concept='cyproheptadine' THEN 'ACB2'
        WHEN concept='loxapine' THEN 'ACB2'
        WHEN concept='pethidine' THEN 'ACB2'
        WHEN concept='levomepromazine' THEN 'ACB2'
        WHEN concept='oxcarbazepine' THEN 'ACB2'
        WHEN concept='pimozide' THEN 'ACB2'
        WHEN concept='amitriptyline' THEN 'ACB3'
        WHEN concept='amoxapine' THEN 'ACB3'
        WHEN concept='atropine' THEN 'ACB3'
        WHEN concept='benztropine' THEN 'ACB3'
        WHEN concept='chlorphenamine' THEN 'ACB3'
        WHEN concept='chlorpromazine' THEN 'ACB3'
        WHEN concept='clemastine' THEN 'ACB3'
        WHEN concept='clomipramine' THEN 'ACB3'
        WHEN concept='clozapine' THEN 'ACB3'
        WHEN concept='darifenacin' THEN 'ACB3'
        WHEN concept='desipramine' THEN 'ACB3'
        WHEN concept='dicyclomine' THEN 'ACB3'
        WHEN concept='diphenhydramine' THEN 'ACB3'
        WHEN concept='doxepin' THEN 'ACB3'
        WHEN concept='flavoxate' THEN 'ACB3'
        WHEN concept='hydroxyzine' THEN 'ACB3'
        WHEN concept='imipramine' THEN 'ACB3'
        WHEN concept='meclozine' THEN 'ACB3'
        WHEN concept='mepyramine' THEN 'ACB3'
        WHEN concept='nortriptyline' THEN 'ACB3'
        WHEN concept='orphenadrine' THEN 'ACB3'
        WHEN concept='oxybutynin' THEN 'ACB3'
        WHEN concept='paroxetine' THEN 'ACB3'
        WHEN concept='perphenazine' THEN 'ACB3'
        WHEN concept='procyclidine' THEN 'ACB3'
        WHEN concept='promazine' THEN 'ACB3'
        WHEN concept='promethazine' THEN 'ACB3'
        WHEN concept='propantheline' THEN 'ACB3'
        WHEN concept='scopolamine' THEN 'ACB3'
        WHEN concept='solifenacin' THEN 'ACB3'
        WHEN concept='tolterodine' THEN 'ACB3'
        WHEN concept='trifluoperazine' THEN 'ACB3'
        WHEN concept='trihexyphenidyl' THEN 'ACB3'
        WHEN concept='trimipramine' THEN 'ACB3'
        WHEN concept='trospium' THEN 'ACB3'
    END AS "MedicationGroup",
    concept AS "MedicationType",
    description AS "Medication"
FROM LH003_Medication_Codes x
LEFT OUTER JOIN SDE_REPOSITORY.SHARED_UTILITIES."Code_Sets_SDE_Lighthouse_03_Kontopantelis" c 
ON c.code = x."SuppliedCode"
WHERE MedicationDate >= '2006-01-01'
UNION
-- Link the above to the data from the Refset clusters
SELECT GmPseudo, TO_DATE("MedicationDate") AS "MedicationDate", 
    CASE
        WHEN "Field_ID" = 'BENZODRUG_COD' THEN 'Benzodiazipine related'
        WHEN "Field_ID" = 'ANTIPSYDRUG_COD' THEN 'Antipsychotic'
    END AS "MedicationCategory",
		-- to get the medication the quickest way is to just split the description by ' ' and take the first part
    split_part(
        regexp_replace( -- this replace removes characters at the start e.g. "~DRUGNAME"
            regexp_replace( -- this replace removes certain trailing characters
								-- to lower case so that CAPITAL and capital come out the same
                lower("MedicationDescription"), '[_,\.\\(0-9]', ' ' 
            ), 
            '[\*\\]~\\[]',
            ''
        ), 
    ' ', 1) AS "MedicationType",
    "MedicationDescription" AS "Medication"
FROM SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_03_Kontopantelis" cohort
LEFT OUTER JOIN INTERMEDIATE.GP_RECORD."MedicationsClusters" meds 
    ON meds."FK_Patient_ID" = cohort.FK_Patient_ID
WHERE "Field_ID" IN ('ANTIPSYDRUG_COD','BENZODRUG_COD')
AND TO_DATE("MedicationDate") >= '2006-01-01';