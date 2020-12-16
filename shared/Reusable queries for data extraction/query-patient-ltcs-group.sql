--
-- ┌────────────────────────────┐
-- │ GET LTC Groups per patient │
-- └────────────────────────────┘

-- INPUT: Assumes there exists a temp table as follows:
-- #PatientsWithLTCs (FK_Patient_Link_ID, LTC)
-- Therefore this is run after query-patient-ltcs.sql

-- OUTPUT: A temp table with a row for each patient and ltc group combo
-- #LTCGroups (FK_Patient_Link_ID, LTCGroup)

-- Calculate the LTC groups for each patient
IF OBJECT_ID('tempdb..#LTCGroups') IS NOT NULL DROP TABLE #LTCGroups;
SELECT 
  DISTINCT FK_Patient_Link_ID, 
  CASE
    WHEN LTC IN ('atrial fibrillation','heart failure','hypertension','stroke & transient ischaemic attack') THEN 'Cardiovascular'
		WHEN LTC IN ('diabetes','thyroid disorders') THEN 'Endocrine'
		WHEN LTC IN ('chronic liver disease','chronic liver disease and viral hepatitis','constipation (treated)','diverticular disease of intestine','dyspepsia (treated)','inflammatory bowel disease','peptic ulcer disease') THEN 'Gastrointestinal'
		WHEN LTC IN ('psoriasis','psoriasis or eczema medcodes','psoriasis or eczema prodcodes','rheumatoid arthritis, other inflammatory polyarthropathies & systematic connective tissue disorders','rheumatoid arthritis, sle') THEN 'Musculoskeletal or Skin'
		WHEN LTC IN ('multiple sclerosis','other neurological conditions','parkinsons disease') THEN 'Neurological'
		WHEN LTC IN ('dementia','depression','depression medcodes','depression prodcodes','schizophrenia (and related non-organic psychosis) or bipolar disorder','schizophrenia (and related non-organic psychosis) or bipolar disorder medcodes','schizophrenia (and related non-organic psychosis) or bipolar disorder prodcodes') THEN 'Psychiatric'
		WHEN LTC IN ('chronic kidney disease') THEN 'Renal or Urological'
		WHEN LTC IN ('asthma (currently treated) medcodes','asthma (currently treated) prodcodes','asthma','asthma diagnosis','bronchiectasis','copd') THEN 'Respiratory'
		WHEN LTC IN ('learning disability') THEN 'Sensory Impairment or Learning Disability'
		WHEN LTC IN ('') THEN 'Substance Abuse'
  END AS LTCGroup INTO #LTCGroups
FROM #PatientsWithLTCs;
