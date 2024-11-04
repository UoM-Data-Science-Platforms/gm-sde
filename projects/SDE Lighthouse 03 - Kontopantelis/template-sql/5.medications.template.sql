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
--> CODESET donepezil:1 galantamine:1 rivastigmine:1 memantine:1 

-- Anticholinergic score 1
--> CODESET alimemazine:1 alprazolam:1 alverine:1 atenolol:1 beclometasone:1 bupropion:1 captopril:1
--> CODESET cimetidine:1 clorazepate:1 codeine:1 colchicine:1 dextropropoxyphene:1 diazepam:1 digoxin:1
--> CODESET dipyridamole:1 disopyramide-phosphate:1 fentanyl:1 fluvoxamine:1 furosemide:1 haloperidol:1
--> CODESET hydralazine:1 hydrocortisone:1 isosorbide:1 loperamide:1 metoprolol:1 morphine:1 nifedipine:1
--> CODESET prednisolone:1 prednisone:1 quinine:1 ranitidine:1 theophylline:1 timolol:1 trazodone:1
--> CODESET triamterene:1 warfarin:1

-- Anticholinergic score 2
--> CODESET amantadine:1 belladona:1 carbamazepine:1 cyclobenzaprine:1 cyproheptadine:1 loxapine:1
--> CODESET pethidine:1 levomepromazine:1 oxcarbazepine:1 pimozide:1

-- Anticholinergic score 3
--> CODESET amitriptyline:1 amoxapine:1 atropine:1 benztropine:1 chlorphenamine:1 chlorpromazine:1
--> CODESET clemastine:1 clomipramine:1 clozapine:1 darifenacin:1 desipramine:1 dicyclomine:1
--> CODESET diphenhydramine:1 doxepin:1 flavoxate:1 hydroxyzine:1 imipramine:1 meclozine:1 mepyramine:1
--> CODESET nortriptyline:1 orphenadrine:1 oxybutynin:1 paroxetine:1 perphenazine:1 procyclidine:1
--> CODESET promazine:1 promethazine:1 propantheline:1 scopolamine:1 solifenacin:1 tolterodine:1
--> CODESET trifluoperazine:1 trihexyphenidyl:1 trimipramine:1 trospium:1

-- Populate a temp table with all the drugs without refsets that we get from GP_Medications
DROP TABLE IF EXISTS "LH003_Medication_Codes";
CREATE TEMPORARY TABLE "LH003_Medication_Codes" AS
SELECT "GmPseudo", "SuppliedCode", to_date("MedicationDate") as "MedicationDate"
FROM {{cohort-table}} cohort
LEFT OUTER JOIN INTERMEDIATE.GP_RECORD."GP_Medications_SecondaryUses" meds 
    ON meds."FK_Patient_ID" = cohort."FK_Patient_ID"
WHERE "SuppliedCode" IN (SELECT code FROM {{code-set-table}} WHERE concept IN('donepezil','galantamine','rivastigmine','memantine','alimemazine',
'alprazolam','alverine','atenolol','beclometasone','bupropion','captopril','cimetidine','clorazepate','codeine','colchicine',
'dextropropoxyphene','diazepam','digoxin','dipyridamole','disopyramide-phosphate','fentanyl','fluvoxamine','furosemide','haloperidol','hydralazine',
'hydrocortisone','isosorbide','loperamide','metoprolol','morphine','nifedipine','prednisolone','prednisone','quinine','ranitidine',
'theophylline','timolol','trazodone','triamterene','warfarin','amantadine','belladona','carbamazepine','cyclobenzaprine',
'cyproheptadine','loxapine','pethidine','levomepromazine','oxcarbazepine','pimozide','amitriptyline','amoxapine',
'atropine','benztropine','chlorphenamine','chlorpromazine','clemastine','clomipramine','clozapine','darifenacin',
'desipramine','dicyclomine','diphenhydramine','doxepin','flavoxate','hydroxyzine','imipramine','meclozine','mepyramine',
'nortriptyline','orphenadrine','oxybutynin','paroxetine','perphenazine','procyclidine','promazine','promethazine','propantheline',
'scopolamine','solifenacin','tolterodine','trifluoperazine','trihexyphenidyl','trimipramine','trospium'));


{{create-output-table::"LH003-5_Medications"}}
-- For antidementia and anticholinergic (no refsets) we query the data from the temp table above
SELECT
    x."GmPseudo",
	"MedicationDate" AS "PrescriptionDate",
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
FROM "LH003_Medication_Codes" x
LEFT OUTER JOIN {{code-set-table}} c 
ON c.code = x."SuppliedCode"
WHERE "MedicationDate" >= '2006-01-01'
UNION
-- Link the above to the data from the Refset clusters
SELECT cohort."GmPseudo", TO_DATE("MedicationDate"), 
    CASE
        WHEN "Field_ID" = 'BENZODRUG_COD' THEN 'Benzodiazipine related'
        WHEN "Field_ID" = 'ANTIPSYDRUG_COD' THEN 'Antipsychotic'
    END, -- "MedicationCategory",
		-- to get the medication the quickest way is to just split the description by ' ' and take the first part
    split_part(
        regexp_replace( -- this replace removes characters at the start e.g. "~DRUGNAME"
            regexp_replace( -- this replace removes certain trailing characters
								-- to lower case so that CAPITAL and capital come out the same
                lower("Term"), '[_,\.\\(0-9]', ' ' 
            ), 
            '[\*\\]~\\[]',
            ''
        ), 
    ' ', 1), -- "MedicationType",
    "Term" -- "Medication"
FROM {{cohort-table}} cohort
LEFT OUTER JOIN INTERMEDIATE.GP_RECORD."Combined_EventsMedications_Clusters_SecondaryUses" meds 
    ON meds."FK_Patient_ID" = cohort."FK_Patient_ID"
WHERE "Field_ID" IN ('ANTIPSYDRUG_COD','BENZODRUG_COD')
AND TO_DATE("MedicationDate") >= '2006-01-01';