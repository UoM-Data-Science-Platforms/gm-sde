
--┌─────────────────────────────────────────────────────────┐
--│ Long-term condition groups per patient at an index date │
--└─────────────────────────────────────────────────────────┘

-- OBJECTIVE: To provide the long-term condition group or groups for each patient. Examples
--            of long term condition groups would be: Cardiovascular, Endocrine, Respiratory
--            Provides Y/N flag for each condition at some index date unique to each person.

-- INPUT: Takes two parameters
--	- gp-events-table: string - (table name) the name of the table containing the GP events. Usually is "SharedCare.GP_Events" but can be anything with the columns: FK_Patient_Link_ID, EventDate, FK_Reference_Coding_ID and FK_Reference_SnomedCT_ID
--	- gp-medications-table: string - (table name) the name of the table containing the GP medications. Usually is "SharedCare.GP_Medications" but can be anything with the columns: FK_Patient_Link_ID, EventDate, FK_Reference_Coding_ID and FK_Reference_SnomedCT_ID
--  Assumes there exists a temp table as follows:
--    #PatientsWithIndexDates  (FK_Patient_Link_ID, IndexDate)

-- OUTPUT: A temp table with a row for each patient and 40 Y/N columns
-- #LTCOnIndexDate (PatientId, HasCOPD, HasAsthma, Has...)



-- Now for each condition make a separate table with the patient id and date
IF OBJECT_ID('tempdb..#AtrialFibrillationDxTable') IS NOT NULL DROP TABLE #AtrialFibrillationDxTable;
SELECT FK_Patient_Link_ID, EventDate INTO #AtrialFibrillationDxTable FROM {param:gp-events-table} WHERE FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #SNOMEDRefCodes WHERE condition = 'Atrial Fibrillation');
IF OBJECT_ID('tempdb..#CoronaryHeartDiseaseDxTable') IS NOT NULL DROP TABLE #CoronaryHeartDiseaseDxTable;
SELECT FK_Patient_Link_ID, EventDate INTO #CoronaryHeartDiseaseDxTable FROM {param:gp-events-table} WHERE FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #SNOMEDRefCodes WHERE condition = 'Coronary Heart Disease');
IF OBJECT_ID('tempdb..#HeartFailureDxTable') IS NOT NULL DROP TABLE #HeartFailureDxTable;
SELECT FK_Patient_Link_ID, EventDate INTO #HeartFailureDxTable FROM {param:gp-events-table} WHERE FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #SNOMEDRefCodes WHERE condition = 'Heart Failure');
IF OBJECT_ID('tempdb..#HypertensionDxTable') IS NOT NULL DROP TABLE #HypertensionDxTable;
SELECT FK_Patient_Link_ID, EventDate INTO #HypertensionDxTable FROM {param:gp-events-table} WHERE FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #SNOMEDRefCodes WHERE condition = 'Hypertension');
IF OBJECT_ID('tempdb..#PeripheralVascularDiseaseDxTable') IS NOT NULL DROP TABLE #PeripheralVascularDiseaseDxTable;
SELECT FK_Patient_Link_ID, EventDate INTO #PeripheralVascularDiseaseDxTable FROM {param:gp-events-table} WHERE FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #SNOMEDRefCodes WHERE condition = 'Peripheral Vascular Disease');
IF OBJECT_ID('tempdb..#StrokeAndTiaDxTable') IS NOT NULL DROP TABLE #StrokeAndTiaDxTable;
SELECT FK_Patient_Link_ID, EventDate INTO #StrokeAndTiaDxTable FROM {param:gp-events-table} WHERE FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #SNOMEDRefCodes WHERE condition = 'Stroke And Tia');
IF OBJECT_ID('tempdb..#DiabetesDxTable') IS NOT NULL DROP TABLE #DiabetesDxTable;
SELECT FK_Patient_Link_ID, EventDate INTO #DiabetesDxTable FROM {param:gp-events-table} WHERE FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #SNOMEDRefCodes WHERE condition = 'Diabetes');
IF OBJECT_ID('tempdb..#ThyroidDisordersDxTable') IS NOT NULL DROP TABLE #ThyroidDisordersDxTable;
SELECT FK_Patient_Link_ID, EventDate INTO #ThyroidDisordersDxTable FROM {param:gp-events-table} WHERE FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #SNOMEDRefCodes WHERE condition = 'Thyroid Disorders');
IF OBJECT_ID('tempdb..#ChronicLiverDiseaseDxTable') IS NOT NULL DROP TABLE #ChronicLiverDiseaseDxTable;
SELECT FK_Patient_Link_ID, EventDate INTO #ChronicLiverDiseaseDxTable FROM {param:gp-events-table} WHERE FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #SNOMEDRefCodes WHERE condition = 'Chronic Liver Disease');
IF OBJECT_ID('tempdb..#DiverticularDiseaseOfIntestineDxTable') IS NOT NULL DROP TABLE #DiverticularDiseaseOfIntestineDxTable;
SELECT FK_Patient_Link_ID, EventDate INTO #DiverticularDiseaseOfIntestineDxTable FROM {param:gp-events-table} WHERE FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #SNOMEDRefCodes WHERE condition = 'Diverticular Disease Of Intestine');
IF OBJECT_ID('tempdb..#InflammatoryBowelDiseaseDxTable') IS NOT NULL DROP TABLE #InflammatoryBowelDiseaseDxTable;
SELECT FK_Patient_Link_ID, EventDate INTO #InflammatoryBowelDiseaseDxTable FROM {param:gp-events-table} WHERE FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #SNOMEDRefCodes WHERE condition = 'Inflammatory Bowel Disease');
IF OBJECT_ID('tempdb..#PepticUlcerDiseaseDxTable') IS NOT NULL DROP TABLE #PepticUlcerDiseaseDxTable;
SELECT FK_Patient_Link_ID, EventDate INTO #PepticUlcerDiseaseDxTable FROM {param:gp-events-table} WHERE FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #SNOMEDRefCodes WHERE condition = 'Peptic Ulcer Disease');
IF OBJECT_ID('tempdb..#RheumatoidArthritisAndOtherInflammatoryPolyarthropathiesDxTable') IS NOT NULL DROP TABLE #RheumatoidArthritisAndOtherInflammatoryPolyarthropathiesDxTable;
SELECT FK_Patient_Link_ID, EventDate INTO #RheumatoidArthritisAndOtherInflammatoryPolyarthropathiesDxTable FROM {param:gp-events-table} WHERE FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #SNOMEDRefCodes WHERE condition = 'Rheumatoid Arthritis And Other Inflammatory Polyarthropathies');
IF OBJECT_ID('tempdb..#MultipleSclerosisDxTable') IS NOT NULL DROP TABLE #MultipleSclerosisDxTable;
SELECT FK_Patient_Link_ID, EventDate INTO #MultipleSclerosisDxTable FROM {param:gp-events-table} WHERE FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #SNOMEDRefCodes WHERE condition = 'Multiple Sclerosis');
IF OBJECT_ID('tempdb..#ParkinsonsDiseaseDxTable') IS NOT NULL DROP TABLE #ParkinsonsDiseaseDxTable;
SELECT FK_Patient_Link_ID, EventDate INTO #ParkinsonsDiseaseDxTable FROM {param:gp-events-table} WHERE FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #SNOMEDRefCodes WHERE condition = 'Parkinsons Disease');
IF OBJECT_ID('tempdb..#AnorexiaOrBulimiaDxTable') IS NOT NULL DROP TABLE #AnorexiaOrBulimiaDxTable;
SELECT FK_Patient_Link_ID, EventDate INTO #AnorexiaOrBulimiaDxTable FROM {param:gp-events-table} WHERE FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #SNOMEDRefCodes WHERE condition = 'Anorexia Or Bulimia');
IF OBJECT_ID('tempdb..#AnxietyAndOtherSomatoformDisordersDxTable') IS NOT NULL DROP TABLE #AnxietyAndOtherSomatoformDisordersDxTable;
SELECT FK_Patient_Link_ID, EventDate INTO #AnxietyAndOtherSomatoformDisordersDxTable FROM {param:gp-events-table} WHERE FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #SNOMEDRefCodes WHERE condition = 'Anxiety And Other Somatoform Disorders');
IF OBJECT_ID('tempdb..#DementiaDxTable') IS NOT NULL DROP TABLE #DementiaDxTable;
SELECT FK_Patient_Link_ID, EventDate INTO #DementiaDxTable FROM {param:gp-events-table} WHERE FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #SNOMEDRefCodes WHERE condition = 'Dementia');
IF OBJECT_ID('tempdb..#DepressionDxTable') IS NOT NULL DROP TABLE #DepressionDxTable;
SELECT FK_Patient_Link_ID, EventDate INTO #DepressionDxTable FROM {param:gp-events-table} WHERE FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #SNOMEDRefCodes WHERE condition = 'Depression');
IF OBJECT_ID('tempdb..#SchizophreniaOrBipolarDxTable') IS NOT NULL DROP TABLE #SchizophreniaOrBipolarDxTable;
SELECT FK_Patient_Link_ID, EventDate INTO #SchizophreniaOrBipolarDxTable FROM {param:gp-events-table} WHERE FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #SNOMEDRefCodes WHERE condition = 'Schizophrenia Or Bipolar');
IF OBJECT_ID('tempdb..#ChronicKidneyDiseaseDxTable') IS NOT NULL DROP TABLE #ChronicKidneyDiseaseDxTable;
SELECT FK_Patient_Link_ID, EventDate INTO #ChronicKidneyDiseaseDxTable FROM {param:gp-events-table} WHERE FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #SNOMEDRefCodes WHERE condition = 'Chronic Kidney Disease');
IF OBJECT_ID('tempdb..#ProstateDisordersDxTable') IS NOT NULL DROP TABLE #ProstateDisordersDxTable;
SELECT FK_Patient_Link_ID, EventDate INTO #ProstateDisordersDxTable FROM {param:gp-events-table} WHERE FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #SNOMEDRefCodes WHERE condition = 'Prostate Disorders');
IF OBJECT_ID('tempdb..#AsthmaDxTable') IS NOT NULL DROP TABLE #AsthmaDxTable;
SELECT FK_Patient_Link_ID, EventDate INTO #AsthmaDxTable FROM {param:gp-events-table} WHERE FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #SNOMEDRefCodes WHERE condition = 'Asthma');
IF OBJECT_ID('tempdb..#BronchiectasisDxTable') IS NOT NULL DROP TABLE #BronchiectasisDxTable;
SELECT FK_Patient_Link_ID, EventDate INTO #BronchiectasisDxTable FROM {param:gp-events-table} WHERE FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #SNOMEDRefCodes WHERE condition = 'Bronchiectasis');
IF OBJECT_ID('tempdb..#ChronicSinusitisDxTable') IS NOT NULL DROP TABLE #ChronicSinusitisDxTable;
SELECT FK_Patient_Link_ID, EventDate INTO #ChronicSinusitisDxTable FROM {param:gp-events-table} WHERE FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #SNOMEDRefCodes WHERE condition = 'Chronic Sinusitis');
IF OBJECT_ID('tempdb..#COPDDxTable') IS NOT NULL DROP TABLE #COPDDxTable;
SELECT FK_Patient_Link_ID, EventDate INTO #COPDDxTable FROM {param:gp-events-table} WHERE FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #SNOMEDRefCodes WHERE condition = 'COPD');
IF OBJECT_ID('tempdb..#BlindnessAndLowVisionDxTable') IS NOT NULL DROP TABLE #BlindnessAndLowVisionDxTable;
SELECT FK_Patient_Link_ID, EventDate INTO #BlindnessAndLowVisionDxTable FROM {param:gp-events-table} WHERE FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #SNOMEDRefCodes WHERE condition = 'Blindness And Low Vision');
IF OBJECT_ID('tempdb..#GlaucomaDxTable') IS NOT NULL DROP TABLE #GlaucomaDxTable;
SELECT FK_Patient_Link_ID, EventDate INTO #GlaucomaDxTable FROM {param:gp-events-table} WHERE FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #SNOMEDRefCodes WHERE condition = 'Glaucoma');
IF OBJECT_ID('tempdb..#HearingLossDxTable') IS NOT NULL DROP TABLE #HearingLossDxTable;
SELECT FK_Patient_Link_ID, EventDate INTO #HearingLossDxTable FROM {param:gp-events-table} WHERE FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #SNOMEDRefCodes WHERE condition = 'Hearing Loss');
IF OBJECT_ID('tempdb..#LearningDisabilityDxTable') IS NOT NULL DROP TABLE #LearningDisabilityDxTable;
SELECT FK_Patient_Link_ID, EventDate INTO #LearningDisabilityDxTable FROM {param:gp-events-table} WHERE FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #SNOMEDRefCodes WHERE condition = 'Learning Disability');
IF OBJECT_ID('tempdb..#AlcoholProblemsDxTable') IS NOT NULL DROP TABLE #AlcoholProblemsDxTable;
SELECT FK_Patient_Link_ID, EventDate INTO #AlcoholProblemsDxTable FROM {param:gp-events-table} WHERE FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #SNOMEDRefCodes WHERE condition = 'Alcohol Problems');
IF OBJECT_ID('tempdb..#PsychoactiveSubstanceAbuseDxTable') IS NOT NULL DROP TABLE #PsychoactiveSubstanceAbuseDxTable;
SELECT FK_Patient_Link_ID, EventDate INTO #PsychoactiveSubstanceAbuseDxTable FROM {param:gp-events-table} WHERE FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #SNOMEDRefCodes WHERE condition = 'Psychoactive Substance Abuse');
IF OBJECT_ID('tempdb..#CancerDxTable') IS NOT NULL DROP TABLE #CancerDxTable;
SELECT FK_Patient_Link_ID, EventDate INTO #CancerDxTable FROM {param:gp-events-table} WHERE FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #SNOMEDRefCodes WHERE condition = 'Cancer');
IF OBJECT_ID('tempdb..#EpilepsyDxTable') IS NOT NULL DROP TABLE #EpilepsyDxTable;
SELECT FK_Patient_Link_ID, EventDate INTO #EpilepsyDxTable FROM {param:gp-events-table} WHERE FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #SNOMEDRefCodes WHERE condition = 'Epilepsy');
IF OBJECT_ID('tempdb..#PsoriasisOrEczemaDxTable') IS NOT NULL DROP TABLE #PsoriasisOrEczemaDxTable;
SELECT FK_Patient_Link_ID, EventDate INTO #PsoriasisOrEczemaDxTable FROM {param:gp-events-table} WHERE FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #SNOMEDRefCodes WHERE condition = 'Psoriasis Or Eczema');
IF OBJECT_ID('tempdb..#IrritableBowelSyndromeDxTable') IS NOT NULL DROP TABLE #IrritableBowelSyndromeDxTable;
SELECT FK_Patient_Link_ID, EventDate INTO #IrritableBowelSyndromeDxTable FROM {param:gp-events-table} WHERE FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #SNOMEDRefCodes WHERE condition = 'Irritable Bowel Syndrome');

-- Now for each condition add in the codes from the reference coding id rather than the snomed one (will
-- lead to duplicates but that doesn't matter)
INSERT INTO #AtrialFibrillationDxTable
SELECT FK_Patient_Link_ID, EventDate FROM {param:gp-events-table} WHERE FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #RefCodes WHERE condition = 'Atrial Fibrillation');
INSERT INTO #CoronaryHeartDiseaseDxTable
SELECT FK_Patient_Link_ID, EventDate FROM {param:gp-events-table} WHERE FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #RefCodes WHERE condition = 'Coronary Heart Disease');
INSERT INTO #HeartFailureDxTable
SELECT FK_Patient_Link_ID, EventDate FROM {param:gp-events-table} WHERE FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #RefCodes WHERE condition = 'Heart Failure');
INSERT INTO #HypertensionDxTable
SELECT FK_Patient_Link_ID, EventDate FROM {param:gp-events-table} WHERE FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #RefCodes WHERE condition = 'Hypertension');
INSERT INTO #PeripheralVascularDiseaseDxTable
SELECT FK_Patient_Link_ID, EventDate FROM {param:gp-events-table} WHERE FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #RefCodes WHERE condition = 'Peripheral Vascular Disease');
INSERT INTO #StrokeAndTiaDxTable
SELECT FK_Patient_Link_ID, EventDate FROM {param:gp-events-table} WHERE FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #RefCodes WHERE condition = 'Stroke And Tia');
INSERT INTO #DiabetesDxTable
SELECT FK_Patient_Link_ID, EventDate FROM {param:gp-events-table} WHERE FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #RefCodes WHERE condition = 'Diabetes');
INSERT INTO #ThyroidDisordersDxTable
SELECT FK_Patient_Link_ID, EventDate FROM {param:gp-events-table} WHERE FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #RefCodes WHERE condition = 'Thyroid Disorders');
INSERT INTO #ChronicLiverDiseaseDxTable
SELECT FK_Patient_Link_ID, EventDate FROM {param:gp-events-table} WHERE FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #RefCodes WHERE condition = 'Chronic Liver Disease');
INSERT INTO #DiverticularDiseaseOfIntestineDxTable
SELECT FK_Patient_Link_ID, EventDate FROM {param:gp-events-table} WHERE FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #RefCodes WHERE condition = 'Diverticular Disease Of Intestine');
INSERT INTO #InflammatoryBowelDiseaseDxTable
SELECT FK_Patient_Link_ID, EventDate FROM {param:gp-events-table} WHERE FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #RefCodes WHERE condition = 'Inflammatory Bowel Disease');
INSERT INTO #PepticUlcerDiseaseDxTable
SELECT FK_Patient_Link_ID, EventDate FROM {param:gp-events-table} WHERE FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #RefCodes WHERE condition = 'Peptic Ulcer Disease');
INSERT INTO #RheumatoidArthritisAndOtherInflammatoryPolyarthropathiesDxTable
SELECT FK_Patient_Link_ID, EventDate FROM {param:gp-events-table} WHERE FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #RefCodes WHERE condition = 'Rheumatoid Arthritis And Other Inflammatory Polyarthropathies');
INSERT INTO #MultipleSclerosisDxTable
SELECT FK_Patient_Link_ID, EventDate FROM {param:gp-events-table} WHERE FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #RefCodes WHERE condition = 'Multiple Sclerosis');
INSERT INTO #ParkinsonsDiseaseDxTable
SELECT FK_Patient_Link_ID, EventDate FROM {param:gp-events-table} WHERE FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #RefCodes WHERE condition = 'Parkinsons Disease');
INSERT INTO #AnorexiaOrBulimiaDxTable
SELECT FK_Patient_Link_ID, EventDate FROM {param:gp-events-table} WHERE FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #RefCodes WHERE condition = 'Anorexia Or Bulimia');
INSERT INTO #AnxietyAndOtherSomatoformDisordersDxTable
SELECT FK_Patient_Link_ID, EventDate FROM {param:gp-events-table} WHERE FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #RefCodes WHERE condition = 'Anxiety And Other Somatoform Disorders');
INSERT INTO #DementiaDxTable
SELECT FK_Patient_Link_ID, EventDate FROM {param:gp-events-table} WHERE FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #RefCodes WHERE condition = 'Dementia');
INSERT INTO #DepressionDxTable
SELECT FK_Patient_Link_ID, EventDate FROM {param:gp-events-table} WHERE FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #RefCodes WHERE condition = 'Depression');
INSERT INTO #SchizophreniaOrBipolarDxTable
SELECT FK_Patient_Link_ID, EventDate FROM {param:gp-events-table} WHERE FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #RefCodes WHERE condition = 'Schizophrenia Or Bipolar');
INSERT INTO #ChronicKidneyDiseaseDxTable
SELECT FK_Patient_Link_ID, EventDate FROM {param:gp-events-table} WHERE FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #RefCodes WHERE condition = 'Chronic Kidney Disease');
INSERT INTO #ProstateDisordersDxTable
SELECT FK_Patient_Link_ID, EventDate FROM {param:gp-events-table} WHERE FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #RefCodes WHERE condition = 'Prostate Disorders');
INSERT INTO #AsthmaDxTable
SELECT FK_Patient_Link_ID, EventDate FROM {param:gp-events-table} WHERE FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #RefCodes WHERE condition = 'Asthma');
INSERT INTO #BronchiectasisDxTable
SELECT FK_Patient_Link_ID, EventDate FROM {param:gp-events-table} WHERE FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #RefCodes WHERE condition = 'Bronchiectasis');
INSERT INTO #ChronicSinusitisDxTable
SELECT FK_Patient_Link_ID, EventDate FROM {param:gp-events-table} WHERE FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #RefCodes WHERE condition = 'Chronic Sinusitis');
INSERT INTO #COPDDxTable
SELECT FK_Patient_Link_ID, EventDate FROM {param:gp-events-table} WHERE FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #RefCodes WHERE condition = 'COPD');
INSERT INTO #BlindnessAndLowVisionDxTable
SELECT FK_Patient_Link_ID, EventDate FROM {param:gp-events-table} WHERE FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #RefCodes WHERE condition = 'Blindness And Low Vision');
INSERT INTO #GlaucomaDxTable
SELECT FK_Patient_Link_ID, EventDate FROM {param:gp-events-table} WHERE FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #RefCodes WHERE condition = 'Glaucoma');
INSERT INTO #HearingLossDxTable
SELECT FK_Patient_Link_ID, EventDate FROM {param:gp-events-table} WHERE FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #RefCodes WHERE condition = 'Hearing Loss');
INSERT INTO #LearningDisabilityDxTable
SELECT FK_Patient_Link_ID, EventDate FROM {param:gp-events-table} WHERE FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #RefCodes WHERE condition = 'Learning Disability');
INSERT INTO #AlcoholProblemsDxTable
SELECT FK_Patient_Link_ID, EventDate FROM {param:gp-events-table} WHERE FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #RefCodes WHERE condition = 'Alcohol Problems');
INSERT INTO #PsychoactiveSubstanceAbuseDxTable
SELECT FK_Patient_Link_ID, EventDate FROM {param:gp-events-table} WHERE FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #RefCodes WHERE condition = 'Psychoactive Substance Abuse');
INSERT INTO #CancerDxTable
SELECT FK_Patient_Link_ID, EventDate FROM {param:gp-events-table} WHERE FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #RefCodes WHERE condition = 'Cancer');
INSERT INTO #EpilepsyDxTable
SELECT FK_Patient_Link_ID, EventDate FROM {param:gp-events-table} WHERE FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #RefCodes WHERE condition = 'Epilepsy');
INSERT INTO #PsoriasisOrEczemaDxTable
SELECT FK_Patient_Link_ID, EventDate FROM {param:gp-events-table} WHERE FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #RefCodes WHERE condition = 'Psoriasis Or Eczema');
INSERT INTO #IrritableBowelSyndromeDxTable
SELECT FK_Patient_Link_ID, EventDate FROM {param:gp-events-table} WHERE FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #RefCodes WHERE condition = 'Irritable Bowel Syndrome');

-- For medication codes we do a similar thing, but deduplicate as there is a high
-- degree of overlap, and also we don't want to count a drug twice in one day as
-- more than one drug.
IF OBJECT_ID('tempdb..#PainfulConditionRxTableA') IS NOT NULL DROP TABLE #PainfulConditionRxTableA;
SELECT FK_Patient_Link_ID, MedicationDate INTO #PainfulConditionRxTableA FROM {param:gp-medications-table} 
WHERE FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #SNOMEDRefCodes WHERE condition = 'Painful Condition');
INSERT INTO #PainfulConditionRxTableA
SELECT FK_Patient_Link_ID, MedicationDate FROM {param:gp-medications-table} 
WHERE FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #RefCodes WHERE condition = 'Painful Condition');
IF OBJECT_ID('tempdb..#PainfulConditionRxTable') IS NOT NULL DROP TABLE #PainfulConditionRxTable;
SELECT DISTINCT * INTO #PainfulConditionRxTable FROM #PainfulConditionRxTableA;
IF OBJECT_ID('tempdb..#MigraineRxTableA') IS NOT NULL DROP TABLE #MigraineRxTableA;
SELECT FK_Patient_Link_ID, MedicationDate INTO #MigraineRxTableA FROM {param:gp-medications-table} 
WHERE FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #SNOMEDRefCodes WHERE condition = 'Migraine');
INSERT INTO #MigraineRxTableA
SELECT FK_Patient_Link_ID, MedicationDate FROM {param:gp-medications-table} 
WHERE FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #RefCodes WHERE condition = 'Migraine');
IF OBJECT_ID('tempdb..#MigraineRxTable') IS NOT NULL DROP TABLE #MigraineRxTable;
SELECT DISTINCT * INTO #MigraineRxTable FROM #MigraineRxTableA;
IF OBJECT_ID('tempdb..#ConstipationRxTableA') IS NOT NULL DROP TABLE #ConstipationRxTableA;
SELECT FK_Patient_Link_ID, MedicationDate INTO #ConstipationRxTableA FROM {param:gp-medications-table} 
WHERE FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #SNOMEDRefCodes WHERE condition = 'Constipation');
INSERT INTO #ConstipationRxTableA
SELECT FK_Patient_Link_ID, MedicationDate FROM {param:gp-medications-table} 
WHERE FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #RefCodes WHERE condition = 'Constipation');
IF OBJECT_ID('tempdb..#ConstipationRxTable') IS NOT NULL DROP TABLE #ConstipationRxTable;
SELECT DISTINCT * INTO #ConstipationRxTable FROM #ConstipationRxTableA;
IF OBJECT_ID('tempdb..#EpilepsyRxTableA') IS NOT NULL DROP TABLE #EpilepsyRxTableA;
SELECT FK_Patient_Link_ID, MedicationDate INTO #EpilepsyRxTableA FROM {param:gp-medications-table} 
WHERE FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #SNOMEDRefCodes WHERE condition = 'Epilepsy');
INSERT INTO #EpilepsyRxTableA
SELECT FK_Patient_Link_ID, MedicationDate FROM {param:gp-medications-table} 
WHERE FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #RefCodes WHERE condition = 'Epilepsy');
IF OBJECT_ID('tempdb..#EpilepsyRxTable') IS NOT NULL DROP TABLE #EpilepsyRxTable;
SELECT DISTINCT * INTO #EpilepsyRxTable FROM #EpilepsyRxTableA;
IF OBJECT_ID('tempdb..#PsoriasisOrEczemaRxTableA') IS NOT NULL DROP TABLE #PsoriasisOrEczemaRxTableA;
SELECT FK_Patient_Link_ID, MedicationDate INTO #PsoriasisOrEczemaRxTableA FROM {param:gp-medications-table} 
WHERE FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #SNOMEDRefCodes WHERE condition = 'Psoriasis Or Eczema');
INSERT INTO #PsoriasisOrEczemaRxTableA
SELECT FK_Patient_Link_ID, MedicationDate FROM {param:gp-medications-table} 
WHERE FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #RefCodes WHERE condition = 'Psoriasis Or Eczema');
IF OBJECT_ID('tempdb..#PsoriasisOrEczemaRxTable') IS NOT NULL DROP TABLE #PsoriasisOrEczemaRxTable;
SELECT DISTINCT * INTO #PsoriasisOrEczemaRxTable FROM #PsoriasisOrEczemaRxTableA;
IF OBJECT_ID('tempdb..#IrritableBowelSyndromeRxTableA') IS NOT NULL DROP TABLE #IrritableBowelSyndromeRxTableA;
SELECT FK_Patient_Link_ID, MedicationDate INTO #IrritableBowelSyndromeRxTableA FROM {param:gp-medications-table} 
WHERE FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #SNOMEDRefCodes WHERE condition = 'Irritable Bowel Syndrome');
INSERT INTO #IrritableBowelSyndromeRxTableA
SELECT FK_Patient_Link_ID, MedicationDate FROM {param:gp-medications-table} 
WHERE FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #RefCodes WHERE condition = 'Irritable Bowel Syndrome');
IF OBJECT_ID('tempdb..#IrritableBowelSyndromeRxTable') IS NOT NULL DROP TABLE #IrritableBowelSyndromeRxTable;
SELECT DISTINCT * INTO #IrritableBowelSyndromeRxTable FROM #IrritableBowelSyndromeRxTableA;
IF OBJECT_ID('tempdb..#DyspepsiaRxTableA') IS NOT NULL DROP TABLE #DyspepsiaRxTableA;
SELECT FK_Patient_Link_ID, MedicationDate INTO #DyspepsiaRxTableA FROM {param:gp-medications-table} 
WHERE FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #SNOMEDRefCodes WHERE condition = 'Dyspepsia');
INSERT INTO #DyspepsiaRxTableA
SELECT FK_Patient_Link_ID, MedicationDate FROM {param:gp-medications-table} 
WHERE FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #RefCodes WHERE condition = 'Dyspepsia');
IF OBJECT_ID('tempdb..#DyspepsiaRxTable') IS NOT NULL DROP TABLE #DyspepsiaRxTable;
SELECT DISTINCT * INTO #DyspepsiaRxTable FROM #DyspepsiaRxTableA;

  -- Painful Condition >= 4 Rx in last 1 year
IF OBJECT_ID('tempdb..#PainfulConditionTable') IS NOT NULL DROP TABLE #PainfulConditionTable;
SELECT patients.FK_Patient_Link_ID, patients.IndexDate AS EventDate
INTO #PainfulConditionTable
FROM #PatientsWithIndexDates patients
LEFT OUTER JOIN #PainfulConditionRxTable medSubTable
  ON medSubTable.FK_Patient_Link_ID = patients.FK_Patient_Link_ID
  AND patients.IndexDate >= medSubTable.MedicationDate
  AND patients.IndexDate < DATEADD(year, 1, medSubTable.MedicationDate)
GROUP BY patients.FK_Patient_Link_ID, patients.IndexDate
HAVING COUNT(medSubTable.MedicationDate) >=4;

-- Migraine >= 4 Rx in last 1 year
IF OBJECT_ID('tempdb..#MigraineTable') IS NOT NULL DROP TABLE #MigraineTable;
SELECT patients.FK_Patient_Link_ID, patients.IndexDate AS EventDate
INTO #MigraineTable
FROM #PatientsWithIndexDates patients
LEFT OUTER JOIN #MigraineRxTable medSubTable
  ON medSubTable.FK_Patient_Link_ID = patients.FK_Patient_Link_ID
  AND patients.IndexDate >= medSubTable.MedicationDate
  AND patients.IndexDate < DATEADD(year, 1, medSubTable.MedicationDate)
GROUP BY patients.FK_Patient_Link_ID, patients.IndexDate
HAVING COUNT(medSubTable.MedicationDate) >=4;

-- Constipation >= 4 Rx in last 1 year
IF OBJECT_ID('tempdb..#ConstipationTable') IS NOT NULL DROP TABLE #ConstipationTable;
SELECT patients.FK_Patient_Link_ID, patients.IndexDate AS EventDate
INTO #ConstipationTable
FROM #PatientsWithIndexDates patients
LEFT OUTER JOIN #ConstipationRxTable medSubTable
  ON medSubTable.FK_Patient_Link_ID = patients.FK_Patient_Link_ID
  AND patients.IndexDate >= medSubTable.MedicationDate
  AND patients.IndexDate < DATEADD(year, 1, medSubTable.MedicationDate)
GROUP BY patients.FK_Patient_Link_ID, patients.IndexDate
HAVING COUNT(medSubTable.MedicationDate) >=4;

-- Dyspepsia >= 4 Rx in last 1 year
IF OBJECT_ID('tempdb..#DyspepsiaTable') IS NOT NULL DROP TABLE #DyspepsiaTable;
SELECT patients.FK_Patient_Link_ID, patients.IndexDate AS EventDate
INTO #DyspepsiaTable
FROM #PatientsWithIndexDates patients
LEFT OUTER JOIN #DyspepsiaRxTable medSubTable
  ON medSubTable.FK_Patient_Link_ID = patients.FK_Patient_Link_ID
  AND patients.IndexDate >= medSubTable.MedicationDate
  AND patients.IndexDate < DATEADD(year, 1, medSubTable.MedicationDate)
GROUP BY patients.FK_Patient_Link_ID, patients.IndexDate
HAVING COUNT(medSubTable.MedicationDate) >=4;

-- For most conditions we just need to know if they ever had the condition
IF OBJECT_ID('tempdb..#AtrialFibrillationTable') IS NOT NULL DROP TABLE #AtrialFibrillationTable;
SELECT FK_Patient_Link_ID, MIN(EventDate) AS EventDate INTO #AtrialFibrillationTable FROM #AtrialFibrillationDxTable GROUP BY FK_Patient_Link_ID;
IF OBJECT_ID('tempdb..#CoronaryHeartDiseaseTable') IS NOT NULL DROP TABLE #CoronaryHeartDiseaseTable;
SELECT FK_Patient_Link_ID, MIN(EventDate) AS EventDate INTO #CoronaryHeartDiseaseTable FROM #CoronaryHeartDiseaseDxTable GROUP BY FK_Patient_Link_ID;
IF OBJECT_ID('tempdb..#HeartFailureTable') IS NOT NULL DROP TABLE #HeartFailureTable;
SELECT FK_Patient_Link_ID, MIN(EventDate) AS EventDate INTO #HeartFailureTable FROM #HeartFailureDxTable GROUP BY FK_Patient_Link_ID;
IF OBJECT_ID('tempdb..#HypertensionTable') IS NOT NULL DROP TABLE #HypertensionTable;
SELECT FK_Patient_Link_ID, MIN(EventDate) AS EventDate INTO #HypertensionTable FROM #HypertensionDxTable GROUP BY FK_Patient_Link_ID;
IF OBJECT_ID('tempdb..#PeripheralVascularDiseaseTable') IS NOT NULL DROP TABLE #PeripheralVascularDiseaseTable;
SELECT FK_Patient_Link_ID, MIN(EventDate) AS EventDate INTO #PeripheralVascularDiseaseTable FROM #PeripheralVascularDiseaseDxTable GROUP BY FK_Patient_Link_ID;
IF OBJECT_ID('tempdb..#StrokeAndTiaTable') IS NOT NULL DROP TABLE #StrokeAndTiaTable;
SELECT FK_Patient_Link_ID, MIN(EventDate) AS EventDate INTO #StrokeAndTiaTable FROM #StrokeAndTiaDxTable GROUP BY FK_Patient_Link_ID;
IF OBJECT_ID('tempdb..#DiabetesTable') IS NOT NULL DROP TABLE #DiabetesTable;
SELECT FK_Patient_Link_ID, MIN(EventDate) AS EventDate INTO #DiabetesTable FROM #DiabetesDxTable GROUP BY FK_Patient_Link_ID;
IF OBJECT_ID('tempdb..#ThyroidDisordersTable') IS NOT NULL DROP TABLE #ThyroidDisordersTable;
SELECT FK_Patient_Link_ID, MIN(EventDate) AS EventDate INTO #ThyroidDisordersTable FROM #ThyroidDisordersDxTable GROUP BY FK_Patient_Link_ID;
IF OBJECT_ID('tempdb..#ChronicLiverDiseaseTable') IS NOT NULL DROP TABLE #ChronicLiverDiseaseTable;
SELECT FK_Patient_Link_ID, MIN(EventDate) AS EventDate INTO #ChronicLiverDiseaseTable FROM #ChronicLiverDiseaseDxTable GROUP BY FK_Patient_Link_ID;
IF OBJECT_ID('tempdb..#DiverticularDiseaseOfIntestineTable') IS NOT NULL DROP TABLE #DiverticularDiseaseOfIntestineTable;
SELECT FK_Patient_Link_ID, MIN(EventDate) AS EventDate INTO #DiverticularDiseaseOfIntestineTable FROM #DiverticularDiseaseOfIntestineDxTable GROUP BY FK_Patient_Link_ID;
IF OBJECT_ID('tempdb..#InflammatoryBowelDiseaseTable') IS NOT NULL DROP TABLE #InflammatoryBowelDiseaseTable;
SELECT FK_Patient_Link_ID, MIN(EventDate) AS EventDate INTO #InflammatoryBowelDiseaseTable FROM #InflammatoryBowelDiseaseDxTable GROUP BY FK_Patient_Link_ID;
IF OBJECT_ID('tempdb..#PepticUlcerDiseaseTable') IS NOT NULL DROP TABLE #PepticUlcerDiseaseTable;
SELECT FK_Patient_Link_ID, MIN(EventDate) AS EventDate INTO #PepticUlcerDiseaseTable FROM #PepticUlcerDiseaseDxTable GROUP BY FK_Patient_Link_ID;
IF OBJECT_ID('tempdb..#RheumatoidArthritisAndOtherInflammatoryPolyarthropathiesTable') IS NOT NULL DROP TABLE #RheumatoidArthritisAndOtherInflammatoryPolyarthropathiesTable;
SELECT FK_Patient_Link_ID, MIN(EventDate) AS EventDate INTO #RheumatoidArthritisAndOtherInflammatoryPolyarthropathiesTable FROM #RheumatoidArthritisAndOtherInflammatoryPolyarthropathiesDxTable GROUP BY FK_Patient_Link_ID;
IF OBJECT_ID('tempdb..#MultipleSclerosisTable') IS NOT NULL DROP TABLE #MultipleSclerosisTable;
SELECT FK_Patient_Link_ID, MIN(EventDate) AS EventDate INTO #MultipleSclerosisTable FROM #MultipleSclerosisDxTable GROUP BY FK_Patient_Link_ID;
IF OBJECT_ID('tempdb..#ParkinsonsDiseaseTable') IS NOT NULL DROP TABLE #ParkinsonsDiseaseTable;
SELECT FK_Patient_Link_ID, MIN(EventDate) AS EventDate INTO #ParkinsonsDiseaseTable FROM #ParkinsonsDiseaseDxTable GROUP BY FK_Patient_Link_ID;
IF OBJECT_ID('tempdb..#AnorexiaOrBulimiaTable') IS NOT NULL DROP TABLE #AnorexiaOrBulimiaTable;
SELECT FK_Patient_Link_ID, MIN(EventDate) AS EventDate INTO #AnorexiaOrBulimiaTable FROM #AnorexiaOrBulimiaDxTable GROUP BY FK_Patient_Link_ID;
IF OBJECT_ID('tempdb..#AnxietyAndOtherSomatoformDisordersTable') IS NOT NULL DROP TABLE #AnxietyAndOtherSomatoformDisordersTable;
SELECT FK_Patient_Link_ID, MIN(EventDate) AS EventDate INTO #AnxietyAndOtherSomatoformDisordersTable FROM #AnxietyAndOtherSomatoformDisordersDxTable GROUP BY FK_Patient_Link_ID;
IF OBJECT_ID('tempdb..#DementiaTable') IS NOT NULL DROP TABLE #DementiaTable;
SELECT FK_Patient_Link_ID, MIN(EventDate) AS EventDate INTO #DementiaTable FROM #DementiaDxTable GROUP BY FK_Patient_Link_ID;
IF OBJECT_ID('tempdb..#DepressionTable') IS NOT NULL DROP TABLE #DepressionTable;
SELECT FK_Patient_Link_ID, MIN(EventDate) AS EventDate INTO #DepressionTable FROM #DepressionDxTable GROUP BY FK_Patient_Link_ID;
IF OBJECT_ID('tempdb..#SchizophreniaOrBipolarTable') IS NOT NULL DROP TABLE #SchizophreniaOrBipolarTable;
SELECT FK_Patient_Link_ID, MIN(EventDate) AS EventDate INTO #SchizophreniaOrBipolarTable FROM #SchizophreniaOrBipolarDxTable GROUP BY FK_Patient_Link_ID;
IF OBJECT_ID('tempdb..#ChronicKidneyDiseaseTable') IS NOT NULL DROP TABLE #ChronicKidneyDiseaseTable;
SELECT FK_Patient_Link_ID, MIN(EventDate) AS EventDate INTO #ChronicKidneyDiseaseTable FROM #ChronicKidneyDiseaseDxTable GROUP BY FK_Patient_Link_ID;
IF OBJECT_ID('tempdb..#ProstateDisordersTable') IS NOT NULL DROP TABLE #ProstateDisordersTable;
SELECT FK_Patient_Link_ID, MIN(EventDate) AS EventDate INTO #ProstateDisordersTable FROM #ProstateDisordersDxTable GROUP BY FK_Patient_Link_ID;
IF OBJECT_ID('tempdb..#AsthmaTable') IS NOT NULL DROP TABLE #AsthmaTable;
SELECT FK_Patient_Link_ID, MIN(EventDate) AS EventDate INTO #AsthmaTable FROM #AsthmaDxTable GROUP BY FK_Patient_Link_ID;
IF OBJECT_ID('tempdb..#BronchiectasisTable') IS NOT NULL DROP TABLE #BronchiectasisTable;
SELECT FK_Patient_Link_ID, MIN(EventDate) AS EventDate INTO #BronchiectasisTable FROM #BronchiectasisDxTable GROUP BY FK_Patient_Link_ID;
IF OBJECT_ID('tempdb..#ChronicSinusitisTable') IS NOT NULL DROP TABLE #ChronicSinusitisTable;
SELECT FK_Patient_Link_ID, MIN(EventDate) AS EventDate INTO #ChronicSinusitisTable FROM #ChronicSinusitisDxTable GROUP BY FK_Patient_Link_ID;
IF OBJECT_ID('tempdb..#COPDTable') IS NOT NULL DROP TABLE #COPDTable;
SELECT FK_Patient_Link_ID, MIN(EventDate) AS EventDate INTO #COPDTable FROM #COPDDxTable GROUP BY FK_Patient_Link_ID;
IF OBJECT_ID('tempdb..#BlindnessAndLowVisionTable') IS NOT NULL DROP TABLE #BlindnessAndLowVisionTable;
SELECT FK_Patient_Link_ID, MIN(EventDate) AS EventDate INTO #BlindnessAndLowVisionTable FROM #BlindnessAndLowVisionDxTable GROUP BY FK_Patient_Link_ID;
IF OBJECT_ID('tempdb..#GlaucomaTable') IS NOT NULL DROP TABLE #GlaucomaTable;
SELECT FK_Patient_Link_ID, MIN(EventDate) AS EventDate INTO #GlaucomaTable FROM #GlaucomaDxTable GROUP BY FK_Patient_Link_ID;
IF OBJECT_ID('tempdb..#HearingLossTable') IS NOT NULL DROP TABLE #HearingLossTable;
SELECT FK_Patient_Link_ID, MIN(EventDate) AS EventDate INTO #HearingLossTable FROM #HearingLossDxTable GROUP BY FK_Patient_Link_ID;
IF OBJECT_ID('tempdb..#LearningDisabilityTable') IS NOT NULL DROP TABLE #LearningDisabilityTable;
SELECT FK_Patient_Link_ID, MIN(EventDate) AS EventDate INTO #LearningDisabilityTable FROM #LearningDisabilityDxTable GROUP BY FK_Patient_Link_ID;
IF OBJECT_ID('tempdb..#AlcoholProblemsTable') IS NOT NULL DROP TABLE #AlcoholProblemsTable;
SELECT FK_Patient_Link_ID, MIN(EventDate) AS EventDate INTO #AlcoholProblemsTable FROM #AlcoholProblemsDxTable GROUP BY FK_Patient_Link_ID;
IF OBJECT_ID('tempdb..#PsychoactiveSubstanceAbuseTable') IS NOT NULL DROP TABLE #PsychoactiveSubstanceAbuseTable;
SELECT FK_Patient_Link_ID, MIN(EventDate) AS EventDate INTO #PsychoactiveSubstanceAbuseTable FROM #PsychoactiveSubstanceAbuseDxTable GROUP BY FK_Patient_Link_ID;


-- Cancer only if first diagnosis in last 5 years
IF OBJECT_ID('tempdb..#CancerTable') IS NOT NULL DROP TABLE #CancerTable;
SELECT patients.FK_Patient_Link_ID, patients.IndexDate AS EventDate
INTO #CancerTable
FROM #PatientsWithIndexDates patients
LEFT OUTER JOIN #CancerDxTable dxSubTable
	ON dxSubTable.FK_Patient_Link_ID = patients.FK_Patient_Link_ID
	AND patients.IndexDate >= dxSubTable.EventDate
GROUP BY patients.FK_Patient_Link_ID, patients.IndexDate
HAVING COUNT(dxSubTable.EventDate) >=1 AND MIN(dxSubTable.EventDate) > DATEADD(year, -5, patients.IndexDate);

-- Epilepsy read code ever
IF OBJECT_ID('tempdb..#EpilepsyTable') IS NOT NULL DROP TABLE #EpilepsyTable;
SELECT patients.FK_Patient_Link_ID, patients.IndexDate AS EventDate
INTO #EpilepsyTable
FROM #PatientsWithIndexDates patients
LEFT OUTER JOIN #EpilepsyDxTable dxSubTable
  ON dxSubTable.FK_Patient_Link_ID = patients.FK_Patient_Link_ID
  AND patients.IndexDate >= dxSubTable.EventDate
GROUP BY patients.FK_Patient_Link_ID, patients.IndexDate
HAVING COUNT(dxSubTable.EventDate) >=1
--  AND Epilepsy Rx in last year
INTERSECT
SELECT patients.FK_Patient_Link_ID, patients.IndexDate FROM #PatientsWithIndexDates patients
LEFT OUTER JOIN #EpilepsyRxTable rxSubTable
  ON rxSubTable.FK_Patient_Link_ID = patients.FK_Patient_Link_ID
  AND patients.IndexDate >= rxSubTable.MedicationDate
  AND patients.IndexDate < DATEADD(year, 1, rxSubTable.MedicationDate)
GROUP BY patients.FK_Patient_Link_ID, patients.IndexDate
HAVING COUNT(rxSubTable.MedicationDate) >=1
ORDER BY patients.FK_Patient_Link_ID;

-- Psoriasis Or Eczema read code ever
IF OBJECT_ID('tempdb..#PsoriasisOrEczemaTable') IS NOT NULL DROP TABLE #PsoriasisOrEczemaTable;
SELECT patients.FK_Patient_Link_ID, patients.IndexDate AS EventDate
INTO #PsoriasisOrEczemaTable
FROM #PatientsWithIndexDates patients
LEFT OUTER JOIN #PsoriasisOrEczemaDxTable dxSubTable
  ON dxSubTable.FK_Patient_Link_ID = patients.FK_Patient_Link_ID
  AND patients.IndexDate >= dxSubTable.EventDate
GROUP BY patients.FK_Patient_Link_ID, patients.IndexDate
HAVING COUNT(dxSubTable.EventDate) >=1
--  AND Psoriasis Or Eczema Rx in last year
INTERSECT
SELECT patients.FK_Patient_Link_ID, patients.IndexDate FROM #PatientsWithIndexDates patients
LEFT OUTER JOIN #PsoriasisOrEczemaRxTable rxSubTable
  ON rxSubTable.FK_Patient_Link_ID = patients.FK_Patient_Link_ID
  AND patients.IndexDate >= rxSubTable.MedicationDate
  AND patients.IndexDate < DATEADD(year, 1, rxSubTable.MedicationDate)
GROUP BY patients.FK_Patient_Link_ID, patients.IndexDate
HAVING COUNT(rxSubTable.MedicationDate) >=4
ORDER BY patients.FK_Patient_Link_ID;

-- Irritable Bowel Syndrome read code ever
IF OBJECT_ID('tempdb..#IrritableBowelSyndromeTable') IS NOT NULL DROP TABLE #IrritableBowelSyndromeTable;
SELECT patients.FK_Patient_Link_ID, patients.IndexDate AS EventDate
INTO #IrritableBowelSyndromeTable
FROM #PatientsWithIndexDates patients
LEFT OUTER JOIN #IrritableBowelSyndromeDxTable dxSubTable
  ON dxSubTable.FK_Patient_Link_ID = patients.FK_Patient_Link_ID
  AND patients.IndexDate >= dxSubTable.EventDate
GROUP BY patients.FK_Patient_Link_ID, patients.IndexDate
HAVING COUNT(dxSubTable.EventDate) >=1
--  AND Irritable Bowel Syndrome Rx in last year
INTERSECT
SELECT patients.FK_Patient_Link_ID, patients.IndexDate FROM #PatientsWithIndexDates patients
LEFT OUTER JOIN #IrritableBowelSyndromeRxTable rxSubTable
  ON rxSubTable.FK_Patient_Link_ID = patients.FK_Patient_Link_ID
  AND patients.IndexDate >= rxSubTable.MedicationDate
  AND patients.IndexDate < DATEADD(year, 1, rxSubTable.MedicationDate)
GROUP BY patients.FK_Patient_Link_ID, patients.IndexDate
HAVING COUNT(rxSubTable.MedicationDate) >=4
ORDER BY patients.FK_Patient_Link_ID;

IF OBJECT_ID('tempdb..#LTCOnIndexDate') IS NOT NULL DROP TABLE #LTCOnIndexDate;
SELECT 
  patients.FK_Patient_Link_ID AS PatientId,
  CASE WHEN SUM(CASE WHEN atrialfibrillation.EventDate IS NULL THEN 0 ELSE 1 END) > 0 THEN 'Y' ELSE 'N' END AS HasAtrialFibrillation,
  CASE WHEN SUM(CASE WHEN coronaryheartdisease.EventDate IS NULL THEN 0 ELSE 1 END) > 0 THEN 'Y' ELSE 'N' END AS HasCoronaryHeartDisease,
  CASE WHEN SUM(CASE WHEN heartfailure.EventDate IS NULL THEN 0 ELSE 1 END) > 0 THEN 'Y' ELSE 'N' END AS HasHeartFailure,
  CASE WHEN SUM(CASE WHEN hypertension.EventDate IS NULL THEN 0 ELSE 1 END) > 0 THEN 'Y' ELSE 'N' END AS HasHypertension,
  CASE WHEN SUM(CASE WHEN peripheralvasculardisease.EventDate IS NULL THEN 0 ELSE 1 END) > 0 THEN 'Y' ELSE 'N' END AS HasPeripheralVascularDisease,
  CASE WHEN SUM(CASE WHEN strokeandtia.EventDate IS NULL THEN 0 ELSE 1 END) > 0 THEN 'Y' ELSE 'N' END AS HasStrokeAndTia,
  CASE WHEN SUM(CASE WHEN diabetes.EventDate IS NULL THEN 0 ELSE 1 END) > 0 THEN 'Y' ELSE 'N' END AS HasDiabetes,
  CASE WHEN SUM(CASE WHEN thyroiddisorders.EventDate IS NULL THEN 0 ELSE 1 END) > 0 THEN 'Y' ELSE 'N' END AS HasThyroidDisorders,
  CASE WHEN SUM(CASE WHEN chronicliverdisease.EventDate IS NULL THEN 0 ELSE 1 END) > 0 THEN 'Y' ELSE 'N' END AS HasChronicLiverDisease,
  CASE WHEN SUM(CASE WHEN diverticulardiseaseofintestine.EventDate IS NULL THEN 0 ELSE 1 END) > 0 THEN 'Y' ELSE 'N' END AS HasDiverticularDiseaseOfIntestine,
  CASE WHEN SUM(CASE WHEN inflammatoryboweldisease.EventDate IS NULL THEN 0 ELSE 1 END) > 0 THEN 'Y' ELSE 'N' END AS HasInflammatoryBowelDisease,
  CASE WHEN SUM(CASE WHEN pepticulcerdisease.EventDate IS NULL THEN 0 ELSE 1 END) > 0 THEN 'Y' ELSE 'N' END AS HasPepticUlcerDisease,
  CASE WHEN SUM(CASE WHEN rheumatoidarthritisandotherinflammatorypolyarthropathies.EventDate IS NULL THEN 0 ELSE 1 END) > 0 THEN 'Y' ELSE 'N' END AS HasRheumatoidArthritisAndOtherInflammatoryPolyarthropathies,
  CASE WHEN SUM(CASE WHEN multiplesclerosis.EventDate IS NULL THEN 0 ELSE 1 END) > 0 THEN 'Y' ELSE 'N' END AS HasMultipleSclerosis,
  CASE WHEN SUM(CASE WHEN parkinsonsdisease.EventDate IS NULL THEN 0 ELSE 1 END) > 0 THEN 'Y' ELSE 'N' END AS HasParkinsonsDisease,
  CASE WHEN SUM(CASE WHEN anorexiaorbulimia.EventDate IS NULL THEN 0 ELSE 1 END) > 0 THEN 'Y' ELSE 'N' END AS HasAnorexiaOrBulimia,
  CASE WHEN SUM(CASE WHEN anxietyandothersomatoformdisorders.EventDate IS NULL THEN 0 ELSE 1 END) > 0 THEN 'Y' ELSE 'N' END AS HasAnxietyAndOtherSomatoformDisorders,
  CASE WHEN SUM(CASE WHEN dementia.EventDate IS NULL THEN 0 ELSE 1 END) > 0 THEN 'Y' ELSE 'N' END AS HasDementia,
  CASE WHEN SUM(CASE WHEN depression.EventDate IS NULL THEN 0 ELSE 1 END) > 0 THEN 'Y' ELSE 'N' END AS HasDepression,
  CASE WHEN SUM(CASE WHEN schizophreniaorbipolar.EventDate IS NULL THEN 0 ELSE 1 END) > 0 THEN 'Y' ELSE 'N' END AS HasSchizophreniaOrBipolar,
  CASE WHEN SUM(CASE WHEN chronickidneydisease.EventDate IS NULL THEN 0 ELSE 1 END) > 0 THEN 'Y' ELSE 'N' END AS HasChronicKidneyDisease,
  CASE WHEN SUM(CASE WHEN prostatedisorders.EventDate IS NULL THEN 0 ELSE 1 END) > 0 THEN 'Y' ELSE 'N' END AS HasProstateDisorders,
  CASE WHEN SUM(CASE WHEN asthma.EventDate IS NULL THEN 0 ELSE 1 END) > 0 THEN 'Y' ELSE 'N' END AS HasAsthma,
  CASE WHEN SUM(CASE WHEN bronchiectasis.EventDate IS NULL THEN 0 ELSE 1 END) > 0 THEN 'Y' ELSE 'N' END AS HasBronchiectasis,
  CASE WHEN SUM(CASE WHEN chronicsinusitis.EventDate IS NULL THEN 0 ELSE 1 END) > 0 THEN 'Y' ELSE 'N' END AS HasChronicSinusitis,
  CASE WHEN SUM(CASE WHEN copd.EventDate IS NULL THEN 0 ELSE 1 END) > 0 THEN 'Y' ELSE 'N' END AS HasCOPD,
  CASE WHEN SUM(CASE WHEN blindnessandlowvision.EventDate IS NULL THEN 0 ELSE 1 END) > 0 THEN 'Y' ELSE 'N' END AS HasBlindnessAndLowVision,
  CASE WHEN SUM(CASE WHEN glaucoma.EventDate IS NULL THEN 0 ELSE 1 END) > 0 THEN 'Y' ELSE 'N' END AS HasGlaucoma,
  CASE WHEN SUM(CASE WHEN hearingloss.EventDate IS NULL THEN 0 ELSE 1 END) > 0 THEN 'Y' ELSE 'N' END AS HasHearingLoss,
  CASE WHEN SUM(CASE WHEN learningdisability.EventDate IS NULL THEN 0 ELSE 1 END) > 0 THEN 'Y' ELSE 'N' END AS HasLearningDisability,
  CASE WHEN SUM(CASE WHEN alcoholproblems.EventDate IS NULL THEN 0 ELSE 1 END) > 0 THEN 'Y' ELSE 'N' END AS HasAlcoholProblems,
  CASE WHEN SUM(CASE WHEN psychoactivesubstanceabuse.EventDate IS NULL THEN 0 ELSE 1 END) > 0 THEN 'Y' ELSE 'N' END AS HasPsychoactiveSubstanceAbuse,
  CASE WHEN SUM(CASE WHEN cancer.EventDate IS NULL THEN 0 ELSE 1 END) > 0 THEN 'Y' ELSE 'N' END AS HasCancer,
  CASE WHEN SUM(CASE WHEN painfulcondition.EventDate IS NULL THEN 0 ELSE 1 END) > 0 THEN 'Y' ELSE 'N' END AS HasPainfulCondition,
  CASE WHEN SUM(CASE WHEN migraine.EventDate IS NULL THEN 0 ELSE 1 END) > 0 THEN 'Y' ELSE 'N' END AS HasMigraine,
  CASE WHEN SUM(CASE WHEN constipation.EventDate IS NULL THEN 0 ELSE 1 END) > 0 THEN 'Y' ELSE 'N' END AS HasConstipation,
  CASE WHEN SUM(CASE WHEN epilepsy.EventDate IS NULL THEN 0 ELSE 1 END) > 0 THEN 'Y' ELSE 'N' END AS HasEpilepsy,
  CASE WHEN SUM(CASE WHEN psoriasisoreczema.EventDate IS NULL THEN 0 ELSE 1 END) > 0 THEN 'Y' ELSE 'N' END AS HasPsoriasisOrEczema,
  CASE WHEN SUM(CASE WHEN irritablebowelsyndrome.EventDate IS NULL THEN 0 ELSE 1 END) > 0 THEN 'Y' ELSE 'N' END AS HasIrritableBowelSyndrome,
  CASE WHEN SUM(CASE WHEN dyspepsia.EventDate IS NULL THEN 0 ELSE 1 END) > 0 THEN 'Y' ELSE 'N' END AS HasDyspepsia
INTO #LTCOnIndexDate
FROM #PatientsWithIndexDates patients
LEFT OUTER JOIN #AtrialFibrillationTable atrialfibrillation ON atrialfibrillation.FK_Patient_Link_ID = patients.FK_Patient_Link_ID AND atrialfibrillation.EventDate <= patients.IndexDate
LEFT OUTER JOIN #CoronaryHeartDiseaseTable coronaryheartdisease ON coronaryheartdisease.FK_Patient_Link_ID = patients.FK_Patient_Link_ID AND coronaryheartdisease.EventDate <= patients.IndexDate
LEFT OUTER JOIN #HeartFailureTable heartfailure ON heartfailure.FK_Patient_Link_ID = patients.FK_Patient_Link_ID AND heartfailure.EventDate <= patients.IndexDate
LEFT OUTER JOIN #HypertensionTable hypertension ON hypertension.FK_Patient_Link_ID = patients.FK_Patient_Link_ID AND hypertension.EventDate <= patients.IndexDate
LEFT OUTER JOIN #PeripheralVascularDiseaseTable peripheralvasculardisease ON peripheralvasculardisease.FK_Patient_Link_ID = patients.FK_Patient_Link_ID AND peripheralvasculardisease.EventDate <= patients.IndexDate
LEFT OUTER JOIN #StrokeAndTiaTable strokeandtia ON strokeandtia.FK_Patient_Link_ID = patients.FK_Patient_Link_ID AND strokeandtia.EventDate <= patients.IndexDate
LEFT OUTER JOIN #DiabetesTable diabetes ON diabetes.FK_Patient_Link_ID = patients.FK_Patient_Link_ID AND diabetes.EventDate <= patients.IndexDate
LEFT OUTER JOIN #ThyroidDisordersTable thyroiddisorders ON thyroiddisorders.FK_Patient_Link_ID = patients.FK_Patient_Link_ID AND thyroiddisorders.EventDate <= patients.IndexDate
LEFT OUTER JOIN #ChronicLiverDiseaseTable chronicliverdisease ON chronicliverdisease.FK_Patient_Link_ID = patients.FK_Patient_Link_ID AND chronicliverdisease.EventDate <= patients.IndexDate
LEFT OUTER JOIN #DiverticularDiseaseOfIntestineTable diverticulardiseaseofintestine ON diverticulardiseaseofintestine.FK_Patient_Link_ID = patients.FK_Patient_Link_ID AND diverticulardiseaseofintestine.EventDate <= patients.IndexDate
LEFT OUTER JOIN #InflammatoryBowelDiseaseTable inflammatoryboweldisease ON inflammatoryboweldisease.FK_Patient_Link_ID = patients.FK_Patient_Link_ID AND inflammatoryboweldisease.EventDate <= patients.IndexDate
LEFT OUTER JOIN #PepticUlcerDiseaseTable pepticulcerdisease ON pepticulcerdisease.FK_Patient_Link_ID = patients.FK_Patient_Link_ID AND pepticulcerdisease.EventDate <= patients.IndexDate
LEFT OUTER JOIN #RheumatoidArthritisAndOtherInflammatoryPolyarthropathiesTable rheumatoidarthritisandotherinflammatorypolyarthropathies ON rheumatoidarthritisandotherinflammatorypolyarthropathies.FK_Patient_Link_ID = patients.FK_Patient_Link_ID AND rheumatoidarthritisandotherinflammatorypolyarthropathies.EventDate <= patients.IndexDate
LEFT OUTER JOIN #MultipleSclerosisTable multiplesclerosis ON multiplesclerosis.FK_Patient_Link_ID = patients.FK_Patient_Link_ID AND multiplesclerosis.EventDate <= patients.IndexDate
LEFT OUTER JOIN #ParkinsonsDiseaseTable parkinsonsdisease ON parkinsonsdisease.FK_Patient_Link_ID = patients.FK_Patient_Link_ID AND parkinsonsdisease.EventDate <= patients.IndexDate
LEFT OUTER JOIN #AnorexiaOrBulimiaTable anorexiaorbulimia ON anorexiaorbulimia.FK_Patient_Link_ID = patients.FK_Patient_Link_ID AND anorexiaorbulimia.EventDate <= patients.IndexDate
LEFT OUTER JOIN #AnxietyAndOtherSomatoformDisordersTable anxietyandothersomatoformdisorders ON anxietyandothersomatoformdisorders.FK_Patient_Link_ID = patients.FK_Patient_Link_ID AND anxietyandothersomatoformdisorders.EventDate <= patients.IndexDate
LEFT OUTER JOIN #DementiaTable dementia ON dementia.FK_Patient_Link_ID = patients.FK_Patient_Link_ID AND dementia.EventDate <= patients.IndexDate
LEFT OUTER JOIN #DepressionTable depression ON depression.FK_Patient_Link_ID = patients.FK_Patient_Link_ID AND depression.EventDate <= patients.IndexDate
LEFT OUTER JOIN #SchizophreniaOrBipolarTable schizophreniaorbipolar ON schizophreniaorbipolar.FK_Patient_Link_ID = patients.FK_Patient_Link_ID AND schizophreniaorbipolar.EventDate <= patients.IndexDate
LEFT OUTER JOIN #ChronicKidneyDiseaseTable chronickidneydisease ON chronickidneydisease.FK_Patient_Link_ID = patients.FK_Patient_Link_ID AND chronickidneydisease.EventDate <= patients.IndexDate
LEFT OUTER JOIN #ProstateDisordersTable prostatedisorders ON prostatedisorders.FK_Patient_Link_ID = patients.FK_Patient_Link_ID AND prostatedisorders.EventDate <= patients.IndexDate
LEFT OUTER JOIN #AsthmaTable asthma ON asthma.FK_Patient_Link_ID = patients.FK_Patient_Link_ID AND asthma.EventDate <= patients.IndexDate
LEFT OUTER JOIN #BronchiectasisTable bronchiectasis ON bronchiectasis.FK_Patient_Link_ID = patients.FK_Patient_Link_ID AND bronchiectasis.EventDate <= patients.IndexDate
LEFT OUTER JOIN #ChronicSinusitisTable chronicsinusitis ON chronicsinusitis.FK_Patient_Link_ID = patients.FK_Patient_Link_ID AND chronicsinusitis.EventDate <= patients.IndexDate
LEFT OUTER JOIN #COPDTable copd ON copd.FK_Patient_Link_ID = patients.FK_Patient_Link_ID AND copd.EventDate <= patients.IndexDate
LEFT OUTER JOIN #BlindnessAndLowVisionTable blindnessandlowvision ON blindnessandlowvision.FK_Patient_Link_ID = patients.FK_Patient_Link_ID AND blindnessandlowvision.EventDate <= patients.IndexDate
LEFT OUTER JOIN #GlaucomaTable glaucoma ON glaucoma.FK_Patient_Link_ID = patients.FK_Patient_Link_ID AND glaucoma.EventDate <= patients.IndexDate
LEFT OUTER JOIN #HearingLossTable hearingloss ON hearingloss.FK_Patient_Link_ID = patients.FK_Patient_Link_ID AND hearingloss.EventDate <= patients.IndexDate
LEFT OUTER JOIN #LearningDisabilityTable learningdisability ON learningdisability.FK_Patient_Link_ID = patients.FK_Patient_Link_ID AND learningdisability.EventDate <= patients.IndexDate
LEFT OUTER JOIN #AlcoholProblemsTable alcoholproblems ON alcoholproblems.FK_Patient_Link_ID = patients.FK_Patient_Link_ID AND alcoholproblems.EventDate <= patients.IndexDate
LEFT OUTER JOIN #PsychoactiveSubstanceAbuseTable psychoactivesubstanceabuse ON psychoactivesubstanceabuse.FK_Patient_Link_ID = patients.FK_Patient_Link_ID AND psychoactivesubstanceabuse.EventDate <= patients.IndexDate
LEFT OUTER JOIN #CancerTable cancer ON cancer.FK_Patient_Link_ID = patients.FK_Patient_Link_ID AND cancer.EventDate <= patients.IndexDate
LEFT OUTER JOIN #PainfulConditionTable painfulcondition ON painfulcondition.FK_Patient_Link_ID = patients.FK_Patient_Link_ID AND painfulcondition.EventDate <= patients.IndexDate
LEFT OUTER JOIN #MigraineTable migraine ON migraine.FK_Patient_Link_ID = patients.FK_Patient_Link_ID AND migraine.EventDate <= patients.IndexDate
LEFT OUTER JOIN #ConstipationTable constipation ON constipation.FK_Patient_Link_ID = patients.FK_Patient_Link_ID AND constipation.EventDate <= patients.IndexDate
LEFT OUTER JOIN #EpilepsyTable epilepsy ON epilepsy.FK_Patient_Link_ID = patients.FK_Patient_Link_ID AND epilepsy.EventDate <= patients.IndexDate
LEFT OUTER JOIN #PsoriasisOrEczemaTable psoriasisoreczema ON psoriasisoreczema.FK_Patient_Link_ID = patients.FK_Patient_Link_ID AND psoriasisoreczema.EventDate <= patients.IndexDate
LEFT OUTER JOIN #IrritableBowelSyndromeTable irritablebowelsyndrome ON irritablebowelsyndrome.FK_Patient_Link_ID = patients.FK_Patient_Link_ID AND irritablebowelsyndrome.EventDate <= patients.IndexDate
LEFT OUTER JOIN #DyspepsiaTable dyspepsia ON dyspepsia.FK_Patient_Link_ID = patients.FK_Patient_Link_ID AND dyspepsia.EventDate <= patients.IndexDate
GROUP BY patients.FK_Patient_Link_ID
