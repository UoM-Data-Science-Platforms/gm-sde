# GPES during COVID-19

The General Practice Extraction Service ([GPES](https://digital.nhs.uk/services/general-practice-extraction-service)) collects a variety of data from all practices in ?England?. It is collected every 2 weeks. It is collected for a variety of reasons, one of which is for QOF payments. Some data is anonymised and some is patient identifiable.

During the COVID-19 pandemic they have extended the list of SNOMED codes that get extracted from each practice.

Doesn't get data from patients who opt out of sharing data for secondary purposes (type 1 opt out) so the same as for GMCR.

Specifically for COVID (described as pandemic planning) there are 3 groups of codes.

1. A list of medications
2. A list of codes that are extracted regardless of when they were recorded
3. A list of codes that are extracted but only if they occurred in the last 2 years

For each patient you get:

- NHS number
- date of birth
- sex
- full name
- address
- ethnicity
- date of death (if applicable).

For each SNOMED code from the relevant groups you get (not sure what all of these mean yet):

- Dates
- Record dates
- Codes
- Episodes Condition
- Episodes Prescription
- Value Condition 1s
- Value Condition 2s
- Value Prescription 1
- Value Prescription 2
- Links

| 1234                                                                                                                       | 1234                                                                                                                                                | 1234                                                                 |
| -------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------- |
| Ambulatory blood pressure codes                                                                                            | Abdominal aortic aneurysm diagnosis codes                                                                                                           | Angiotensin-converting enzyme (ACE) inhibitor prescription codes     |
| Codes indicating the patient has chosen not to receive angiotensin-converting enzyme (ACE) inhibitor                       | History of atrial fibrillation or flutter                                                                                                           | Angiotensin II receptor blockers (ARB) prescription codes            |
| Invite for atrial fibrillation care review codes                                                                           | Atrial fibrillation codes                                                                                                                           | Antihypertensive medications                                         |
| Codes indicating the patient has chosen not to receive atrial fibrillation quality indicator care                          | Atrial fibrillation resolved codes                                                                                                                  | Antipsychotic drug codes                                             |
| Codes for atrial fibrillation quality indicator care unsuitable for patient                                                | Alcohol consumption codes                                                                                                                           | Asthma-related drug treatment codes                                  |
| Atrial fibrillation monitoring and review codes                                                                            | Left foot amputation codes                                                                                                                          | Asthma inhaled corticosteroids codes                                 |
| Codes indicating the patient has chosen not to receive angiotensin II receptor blockers (ARB)                              | Right foot amputation codes                                                                                                                         | Bone sparing agent drug codes                                        |
| Brief intervention for excessive alcohol consumption codes                                                                 | Angina diagnosis codes                                                                                                                              | Severe asthma drug treatment codes                                   |
| Brief intervention for excessive alcohol consumption declined codes                                                        | Asthma diagnosis codes                                                                                                                              | Chronic obstructive pulmonary disease (COPD) drug codes              |
| Alcohol consumption screening refused codes                                                                                | Asthma resolved codes                                                                                                                               | Corticosteroid drug codes                                            |
| Extended intervention for excessive alcohol consumption codes                                                              | Autism diagnosis codes                                                                                                                              | Severe immunosuppression drug codes                                  |
| Extended intervention for excessive alcohol consumption declined codes                                                     | Body mass index (BMI) codes                                                                                                                         | Prednisolone drug codes                                              |
| Alcohol Intervention and Advice                                                                                            | Body mass index (BMI) codes >= 30 without an associated BMI value                                                                                   | Clopidogrel drug codes                                               |
| Alcohol screening and assessment declined codes                                                                            | Down syndrome body mass index (BMI) codes                                                                                                           | Constipation treatment codes                                         |
| Referral to specialist alcohol treatment service codes                                                                     | Body mass index (BMI) healthy codes                                                                                                                 | Dipyridamole prescription codes                                      |
| Referral to specialist alcohol treatment service declined codes                                                            | Body mass index (BMI) obese codes                                                                                                                   | Diabetes mellitus drugs codes                                        |
| Angina referral to specialist codes                                                                                        | Body mass index (BMI) overweight codes                                                                                                              | Drug treatment for epilepsy                                          |
| Codes indicating the patient has chosen not to receive antihypertensive treatment                                          | Body mass index (BMI) underweight codes                                                                                                             | Product containing ezetimibe (medicinal product)                     |
| Anxiety screening codes                                                                                                    | Body mass index (BMI) codes with an associated BMI value                                                                                            | Flu vaccine drug codes                                               |
| Anxiety screening declined codes                                                                                           | Severe asthma and dust related lung disease codes                                                                                                   | Immunosuppression drugs                                              |
| Anxiety support and treatment codes                                                                                        | Non-haematological cancer diagnosis codes with or without associated treatment                                                                      | Licensed beta-blocker prescription codes                             |
| Codes for Albumin Creatinine and Protein Creatinine Ratio for chronic kidney disease (CKD)                                 | Chronic obstructive pulmonary disease (COPD), emphysema, and associated lung diseases codes                                                         | Lithium prescription codes                                           |
| Asthma emergency admission codes                                                                                           | Haematological cancer codes                                                                                                                         | MenACWY vaccine codes                                                |
| Invite for asthma care review codes                                                                                        | Congenital heart disease codes                                                                                                                      | Men B vaccine drug codes                                             |
| Codes indicating the patient has chosen not to receive asthma monitoring                                                   | Pregnant patients at any stage of pregnancy                                                                                                         | Metformin drug codes                                                 |
| Codes indicating the patient has chosen not to receive asthma quality indicator care                                       | Non-asthma and non-COPD chronic respiratory disease codes                                                                                           | MMR vaccine codes                                                    |
| Codes for asthma quality indicator care unsuitable for patient                                                             | Rare genetic, metabolic and autoimmune disease codes                                                                                                | Oral anticoagulant drug codes                                        |
| Asthma quality indicator service unavailable codes                                                                         | Transplant codes                                                                                                                                    | PCSK9 Inhibitors                                                     |
| Spirometry codes for asthma                                                                                                | Codes for relevant malignancies                                                                                                                     | Pharmacotherapy drug codes                                           |
| Alcohol Use Disorders Identification Test (AUDIT) codes                                                                    | Coronary heart disease (CHD) codes                                                                                                                  | Pneumococcal vaccine drug codes                                      |
| Alcohol Use Disorder Identification Test Consumption (AUDIT C) codes                                                       | Chronic heart disease codes                                                                                                                         | Dissent from secondary use of GP patient identifiable data           |
| Codes indicating the patient has chosen not to receive a blood test                                                        | Chronic kidney disease (CKD) stage 3-5 codes                                                                                                        | Dissent withdrawn from secondary use of GP patient identifiable data |
| Codes indicating the patient has chosen not to have their body mass index (BMI) measured                                   | Chronic kidney disease (CKD) stage 1-2 codes                                                                                                        | Salicylate prescription codes                                        |
| Codes for body mass index (BMI) measurement unsuitable for patient                                                         | Chronic kidney disease (CKD) stage 1 and 2 codes                                                                                                    | Seasonal influenza inactivated vaccine codes                         |
| Blood pressure (BP) recording codes                                                                                        | Chronic kidney disease (CKD) stage 4 and 5 codes                                                                                                    | Statin codes                                                         |
| Codes indicating the patient has chosen not to have blood pressure procedure                                               | Chronic kidney disease (CKD) stage 3, 4 and 5 codes                                                                                                 | Hypothyroidism treatment codes                                       |
| Breast cancer screening codes                                                                                              | Chronic kidney disease (CKD) resolved codes                                                                                                         | Unlicensed beta-blocker prescription codes                           |
| Bone sparing therapy codes                                                                                                 | Chronic liver disease (CLD) codes                                                                                                                   |                                                                      |
| COVID19 activity codes                                                                                                     | Chronic neurological disease (CND) codes                                                                                                            |                                                                      |
| Provision of high dose corticosteroid safety card codes                                                                    | Chronic obstructive pulmonary disease (COPD) codes                                                                                                  |                                                                      |
| Flu-like symptoms and upper and lower respiratory tract infection codes                                                    | Chronic obstructive pulmonary disease (COPD) resolved codes                                                                                         |                                                                      |
| COVID19 risk category codes                                                                                                | Spirometry codes for chronic obstructive pulmonary disease (COPD)                                                                                   |                                                                      |
| Calcium test result codes                                                                                                  | Chronic respiratory disease codes                                                                                                                   |                                                                      |
| Invite for cancer care review codes                                                                                        | Chronic respiratory disease (CRD) codes                                                                                                             |                                                                      |
| Codes indicating the patient has chosen not to receive cancer quality indicator care                                       | Patient deceased codes                                                                                                                              |                                                                      |
| Codes for cancer quality indicator care unsuitable for patient                                                             | Codes for dementia                                                                                                                                  |                                                                      |
| Cockcroft Gault - estimated glomerular filtration rate                                                                     | Depression diagnosis codes                                                                                                                          |                                                                      |
| Stroke risk assessment using CHADS2                                                                                        | Depression resolved codes                                                                                                                           |                                                                      |
| Stroke risk assessment using CHA2DS2-VASc                                                                                  | Diabetes nephropathy codes                                                                                                                          |                                                                      |
| Invite for coronary heart disease (CHD) care review codes                                                                  | Diabetes mellitus codes                                                                                                                             |                                                                      |
| Codes indicating the patient has chosen not to receive coronary heart disease (CHD) quality indicator care                 | Diabetes mellitus codes for pneumococcal service                                                                                                    |                                                                      |
| Codes for coronary heart disease (CHD) quality indicator care unsuitable for patient                                       | Codes for diabetes (non–type 1)                                                                                                                     |                                                                      |
| Codes for exception from serum cholesterol target (persisting)                                                             | Diabetes resolved codes                                                                                                                             |                                                                      |
| Total cholesterol codes                                                                                                    | Codes for type 1 diabetes                                                                                                                           |                                                                      |
| Total cholesterol                                                                                                          | Diabetes Type 1 codes used in National Audit                                                                                                        |                                                                      |
| Codes indicating the patient is on maximum tolerated cholesterol lowering treatment                                        | Codes for diabetes type 2                                                                                                                           |                                                                      |
| Codes for proteinuria for chronic kidney disease (CKD)                                                                     | Diabetes Type 2 codes used in National Audit                                                                                                        |                                                                      |
| Clopidogrel prophylaxis codes                                                                                              | Down’s syndrome codes                                                                                                                               |                                                                      |
| Codes indicating the patient has chosen not to receive clopidogrel                                                         | Dysphagia diagnosis codes                                                                                                                           |                                                                      |
| Colorectal cancer screening codes                                                                                          | Electrocardiogram (ECG) indicating atrial fibrillation or flutter codes                                                                             |                                                                      |
| Invite for chronic obstructive pulmonary disease (COPD) care review codes                                                  | Epilepsy diagnosis codes                                                                                                                            |                                                                      |
| Codes indicating the patient has chosen not to receive chronic obstructive pulmonary disease (COPD) quality indicator care | Epilepsy resolved codes                                                                                                                             |                                                                      |
| Codes for chronic obstructive pulmonary disease (COPD) quality indicator care unsuitable for patient                       | Asian or Asian British Bangladeshi ethnicity group codes (NHS Digital 2016 grouping)                                                                |                                                                      |
| Chronic obstructive pulmonary disease (COPD) quality indicator service unavailable codes                                   | Asian or Asian British Chinese ethnicity group codes (NHS Digital 2016 grouping)                                                                    |                                                                      |
| Codes for chronic obstructive pulmonary disease (COPD) review                                                              | Asian or Asian British Indian ethnicity group codes (NHS Digital 2016 grouping)                                                                     |                                                                      |
| Codes for serum creatinine                                                                                                 | Asian or Asian British Any other Asian background ethnicity group codes (NHS Digital 2016 grouping)                                                 |                                                                      |
| Codes indicating the patient has chosen not to receive cervical smear                                                      | Asian or Asian British Pakistani ethnicity group codes (NHS Digital 2016 grouping)                                                                  |                                                                      |
| Patient not responded to three invites for cervical screening codes                                                        | Black or African or Caribbean or Black British African ethnicity group codes (NHS Digital 2016 grouping)                                            |                                                                      |
| Codes for cervical screening quality indicator care unsuitable for patient                                                 | Black or African or Caribbean or Black British Caribbean ethnicity group codes (NHS Digital 2016 grouping)                                          |                                                                      |
| Cardiovascular disease (CVD) risk assessment codes greater than 20 per cent                                                | Black or African or Caribbean or Black British Any other Black or African or Caribbean background ethnicity group codes (NHS Digital 2016 grouping) |                                                                      |
| Cardiovascular disease (CVD) risk assessment codes                                                                         | Mixed or multiple ethnic groups Any other Mixed or multiple ethnic background ethnicity group codes (NHS Digital 2016 grouping)                     |                                                                      |
| Codes indicating the patient has chosen not to receive cardiovascular disease (CVD) risk assessment                        | Mixed or multiple ethnic groups White and Asian ethnicity group codes (NHS Digital 2016 grouping)                                                   |                                                                      |
| Codes indicating cardiovascular disease (CVD) risk assessment was deemed unsuitable for the patient                        | Mixed or multiple ethnic groups White and Black African ethnicity group codes (NHS Digital 2016 grouping)                                           |                                                                      |
| Invite for cardiovascular disease (CVD) care review codes                                                                  | Mixed or multiple ethnic groups White and Black Caribbean ethnicity group codes (NHS Digital 2016 grouping)                                         |                                                                      |
| Codes indicating the patient has chosen not to receive quality indicator cardiovascular disease (CVD) care                 | Not stated ethnicity group codes (NHS Digital 2016 grouping)                                                                                        |                                                                      |
| Codes for cardiovascular disease (CVD) quality indicator care unsuitable for patient                                       | Other ethnic group Arab ethnicity group codes (NHS Digital 2016 grouping)                                                                           |                                                                      |
| Evidence of diabetic retinopathy screening attendance codes                                                                | Other ethnic group Any other ethnic group ethnicity group codes (NHS Digital 2016 grouping)                                                         |                                                                      |
| Cardiovascular disease (CVD) risk assessment done                                                                          | White English or Welsh or Scottish or Northern Irish or British ethnicity group codes (NHS Digital 2016 grouping)                                   |                                                                      |
| Assessment for dementia codes                                                                                              | White Gypsy or Irish Traveller ethnicity group codes (NHS Digital 2016 grouping)                                                                    |                                                                      |
| Dementia care plan codes                                                                                                   | White Irish ethnicity group codes (NHS Digital 2016 grouping)                                                                                       |                                                                      |
| Codes indicating the patient has chosen not to receive dementia care plan                                                  | White Any other White background ethnicity group codes (NHS Digital 2016 grouping)                                                                  |                                                                      |
| Dementia care plan review codes                                                                                            | Active and inactive ethnicity codes                                                                                                                 |                                                                      |
| Codes indicating the patient has chosen not to receive dementia care plan review                                           | Excessive alcohol consumption codes                                                                                                                 |                                                                      |
| Invite for dementia care review codes                                                                                      | Code for ex-smoker                                                                                                                                  |                                                                      |
| Dementia medication review codes                                                                                           | Falls codes                                                                                                                                         |                                                                      |
| Codes indicating the patient has chosen not to receive dementia quality indicator care                                     | Fragility fracture codes                                                                                                                            |                                                                      |
| Codes for dementia quality indicator care unsuitable for patient                                                           | Familial hypercholesterolemia diagnostic codes                                                                                                      |                                                                      |
| Invite for depression care review codes                                                                                    | Genetically proven familial hypercholesterolaemia codes                                                                                             |                                                                      |
| Codes indicating the patient has chosen not to receive depression quality indicator care                                   | Flu vaccination codes                                                                                                                               |                                                                      |
| Codes for depression quality indicator care unsuitable for patient                                                         | Familial and non-familial hypercholesterolemia diagnosis codes                                                                                      |                                                                      |
| Depression review codes                                                                                                    | Gestational Diabetes Codes                                                                                                                          |                                                                      |
| Depression screening codes                                                                                                 | Codes for the completing Hepatitis B vaccination dose                                                                                               |                                                                      |
| Depression screening declined codes                                                                                        | First hepatitis B vaccination codes                                                                                                                 |                                                                      |
| Depression support and treatment codes                                                                                     | Second hepatitis B vaccination codes                                                                                                                |                                                                      |
| Diet Intervention and Advice                                                                                               | Heart failure codes                                                                                                                                 |                                                                      |
| Codes indicating the patient has chosen not to receive dipyridamole                                                        | Codes for heart failure due to left ventricular systolic dysfunction (LVSD)                                                                         |                                                                      |
| Invite for diabetes care review codes                                                                                      | Haemophilus influenzae type B Meningitis C (HibMenC) vaccination codes                                                                              |                                                                      |
| Codes for maximum tolerated diabetes treatment                                                                             | HPV vaccination codes                                                                                                                               |                                                                      |
| Codes indicating the patient has chosen not to receive diabetes quality indicator care                                     | Haemorrhagic stroke codes                                                                                                                           |                                                                      |
| Codes for diabetes quality indicator care unsuitable for patient                                                           | Hypertension diagnosis codes                                                                                                                        |                                                                      |
| Referral to NHS diabetes prevention programme attended                                                                     | Hypertension resolved codes                                                                                                                         |                                                                      |
| Referral to NHS diabetes prevention programme completed                                                                    | Immunosuppression codes (persisting)                                                                                                                |                                                                      |
| Referral to NHS diabetes prevention programme offered or declined                                                          | Immunosuppression resolved codes                                                                                                                    |                                                                      |
| Diabetic retinopathy screening attendance codes                                                                            | Immunosuppression procedure codes                                                                                                                   |                                                                      |
| Referred for diabetes structured education programme                                                                       | Intranasal seasonal influenza vaccine ‘first’ dose given codes                                                                                      |                                                                      |
| Codes indicating the patient has chosen not to have diabetes structured education programme                                | Intranasal seasonal influenza vaccine ‘second’ dose codes                                                                                           |                                                                      |
| Codes for diabetes structured education programme unsuitable for the patient                                               | Intranasal seasonal influenza vaccination ‘first’ dose given by other healthcare provider codes                                                     |                                                                      |
| Diabetes structured education programme service unavailable codes                                                          | Intranasal seasonal influenza vaccination ‘second’ dose given by other healthcare provider codes                                                    |                                                                      |
| Dutch Lipid Clinic Network Codes                                                                                           | Body mass index (BMI) codes                                                                                                                         |                                                                      |
| Dual energy X-ray absorptiometry (DXA) scan result of osteoporotic without a value                                         | Body mass index (BMI) codes >= 40 without an associated BMI value                                                                                   |                                                                      |
| Dual energy X-ray absorptiometry (DXA) scan result with a T score value                                                    | Learning disability (LD) codes                                                                                                                      |                                                                      |
| Codes indicating the patient has chosen not to have an echocardiogram                                                      | Code for stopped lithium                                                                                                                            |                                                                      |
| Echocardiogram (Echo) codes                                                                                                | Smoker codes                                                                                                                                        |                                                                      |
| Echocardiography service unavailable codes                                                                                 | Seizure free for over 12 months codes                                                                                                               |                                                                      |
| Codes for echocardiogram unsuitable for the patient                                                                        | Epilepsy seizure frequency codes                                                                                                                    |                                                                      |
| Estimated glomerular filtration rate                                                                                       | MenACWY GP vaccination codes                                                                                                                        |                                                                      |
| Contraceptive counselling codes for people with epilepsy                                                                   | MenACWY other healthcare provider vaccination codes                                                                                                 |                                                                      |
| Contraceptive counselling for people with epilepsy inappropriate or declined exception codes                               | First Men B vaccination codes                                                                                                                       |                                                                      |
| Pregnancy advice codes for people with epilepsy                                                                            | Second Men B vaccination codes                                                                                                                      |                                                                      |
| Pregnancy advice for people with epilepsy inappropriate or declined exception codes                                        | Booster Men B vaccination codes                                                                                                                     |                                                                      |
| Pre-conception advice codes for people with epilepsy                                                                       | First Men B vaccination codes by another healthcare provider                                                                                        |                                                                      |
| Pre-conception advice inappropriate or declined exception codes                                                            | Second Men B vaccination codes by another healthcare provider                                                                                       |                                                                      |
| Exercise intervention and advice                                                                                           | Booster Men B vaccination codes by another healthcare provider                                                                                      |                                                                      |
| Falls discussion codes                                                                                                     | Psychosis and schizophrenia and bipolar affective disease codes                                                                                     |                                                                      |
| Falls discussion declined codes                                                                                            | Codes for in remission from serious mental illness                                                                                                  |                                                                      |
| Referral to falls service codes                                                                                            | Myocardial infarction (MI) diagnosis codes                                                                                                          |                                                                      |
| Fasting plasma glucose codes                                                                                               | Mild frailty diagnosis codes                                                                                                                        |                                                                      |
| Codes indicating the patient has chosen not to have a foot examination                                                     | MMR first dose vaccination codes                                                                                                                    |                                                                      |
| Codes for foot examination unsuitable for patient                                                                          | MMR second dose vaccination codes                                                                                                                   |                                                                      |
| Codes indicating the patient has chosen not to receive a flu vaccination                                                   | Moderate frailty diagnosis codes                                                                                                                    |                                                                      |
| Flu vaccine contraindications (expiring)                                                                                   | National diabetes audit (NDA) body mass index (BMI) codes                                                                                           |                                                                      |
| Flu vaccination no consent codes                                                                                           | National diabetes audit (NDA) diabetes mellitus diagnosis codes                                                                                     |                                                                      |
| Feet examination (neuropathy testing or peripheral pulses) codes                                                           | National diabetes audit (NDA) diabetes mellitus codes to determine diabetes type for the audit                                                      |                                                                      |
| Frailty assessment codes                                                                                                   | Persistent proteinuria codes                                                                                                                        |                                                                      |
| Frailty assessment declined codes                                                                                          | National diabetes audit (NDA) smoking habit codes                                                                                                   |                                                                      |
| Foot risk classification codes                                                                                             | Codes that indicate complete removal of the cervix                                                                                                  |                                                                      |
| Gamma-glutamyl transferase test results                                                                                    | Code for never smoked                                                                                                                               |                                                                      |
| Glucose test recording                                                                                                     | Osteoporosis codes                                                                                                                                  |                                                                      |
| HASBLED score codes                                                                                                        | Non-haemorrhagic stroke codes                                                                                                                       |                                                                      |
| Haemoglobin test results                                                                                                   | Non Type 1 or Type 2 diabetes mellitus codes used in National audit                                                                                 |                                                                      |
| Healthcare worker codes                                                                                                    | Peripheral arterial disease (PAD) diagnostic codes                                                                                                  |                                                                      |
| HDL cholesterol test result codes                                                                                          | Palliative care codes                                                                                                                               |                                                                      |
| Hepatitis B blood test codes                                                                                               | Pneumococcal (PCV) vaccination codes                                                                                                                |                                                                      |
| Invite for heart failure care review codes                                                                                 | Pertussis vaccination in pregnancy codes                                                                                                            |                                                                      |
| Codes indicating the patient has chosen not to receive heart failure quality indicator care                                | Pertussis vaccination in pregnancy given by other healthcare provider codes                                                                         |                                                                      |
| Codes for heart failure quality indicator care unsuitable for patient                                                      | Pneumococcal vaccination codes                                                                                                                      |                                                                      |
| Heart failure quality indicator service unavailable codes                                                                  | Pneumococcal vaccination given by other healthcare provider codes                                                                                   |                                                                      |
| Learning disability (LD) health check codes                                                                                | Possible Familial Hypercholesterolaemia                                                                                                             |                                                                      |
| Codes for maximal blood pressure (BP) therapy                                                                              | Pre-diabetes codes                                                                                                                                  |                                                                      |
| Invite for hypertension care review codes                                                                                  | Codes indicating the patient is pregnant                                                                                                            |                                                                      |
| Codes indicating the patient has chosen not to receive hypertension quality indicator care                                 | Rheumatoid arthritis diagnosis codes                                                                                                                |                                                                      |
| Codes for hypertension quality indicator care unsuitable for patient                                                       | Requires interpreter codes                                                                                                                          |                                                                      |
| IFCC HbA1c monitoring range codes                                                                                          | Rotavirus vaccination 1st dose given codes                                                                                                          |                                                                      |
| Immunosuppression codes (expiring)                                                                                         | Rotavirus vaccination 2nd dose given codes                                                                                                          |                                                                      |
| Codes indicating the patient has chosen not to receive beta blocker                                                        | Severe frailty diagnosis codes                                                                                                                      |                                                                      |
| Low density lipoprotein (LDL) cholesterol test results                                                                     | Severe and malignant Hypertension                                                                                                                   |                                                                      |
| Liver function test results                                                                                                | Seasonal influenza inactivated vaccine first dose codes                                                                                             |                                                                      |
| Lifestyle intervention and advice codes                                                                                    | Seasonal influenza inactivated vaccine second dose codes                                                                                            |                                                                      |
| Lifestyle advice codes                                                                                                     | Seasonal influenza inactivated vaccine first dose given by other healthcare provider codes                                                          |                                                                      |
| Codes for microalbuminuria                                                                                                 | Seasonal influenza inactivated vaccine second dose given by other healthcare provider codes                                                         |                                                                      |
| Code for maximal anticonvulsant therapy                                                                                    | Shingles GP vaccination codes                                                                                                                       |                                                                      |
| Code for cancer care review                                                                                                | Shingles other healthcare provider vaccination codes                                                                                                |                                                                      |
| Medication review codes                                                                                                    | Smoking habit codes                                                                                                                                 |                                                                      |
| Initial memory assessment codes                                                                                            | Stroke diagnosis codes                                                                                                                              |                                                                      |
| Codes indicating the patient has chosen not to receive initial memory assessment                                           | Supraventricular tachycardia (SVT) Codes                                                                                                            |                                                                      |
| Referral to memory clinic codes                                                                                            | Hypothyroidism diagnosis codes                                                                                                                      |                                                                      |
| Codes indicating the patient has chosen not to accept referral to memory clinic                                            | Transient ischaemic attack (TIA) codes                                                                                                              |                                                                      |
| Codes indicating the patient chose not to receive a MenACWY vaccination                                                    |                                                                                                                                                     |                                                                      |
| Men B vaccination contraindicated codes                                                                                    |                                                                                                                                                     |                                                                      |
| Codes indicating the patient chose not to receive a first Men B vaccination                                                |                                                                                                                                                     |                                                                      |
| Codes indicating the patient chose not to receive a second Men B vaccination                                               |                                                                                                                                                     |                                                                      |
| Codes indicating the patient chose not to receive a Men B booster vaccination                                              |                                                                                                                                                     |                                                                      |
| Invite mental health care review codes                                                                                     |                                                                                                                                                     |                                                                      |
| Codes for mental health care plan                                                                                          |                                                                                                                                                     |                                                                      |
| Codes indicating the patient has chosen not to receive mental health quality indicator care                                |                                                                                                                                                     |                                                                      |
| Codes for mental health quality indicator care unsuitable for patient                                                      |                                                                                                                                                     |                                                                      |
| Codes for Medical Research Council (MRC) breathlessness scale score                                                        |                                                                                                                                                     |                                                                      |
| Codes for Medical Research Council (MRC) breathlessness scale score greater than or equal to 3                             |                                                                                                                                                     |                                                                      |
| Urine albumin codes                                                                                                        |                                                                                                                                                     |                                                                      |
| National diabetes audit (NDA) blood pressure (BP) codes                                                                    |                                                                                                                                                     |                                                                      |
| Height measured                                                                                                            |                                                                                                                                                     |                                                                      |
| Attended diabetes structured education programme codes                                                                     |                                                                                                                                                     |                                                                      |
| Offered diabetes structured education programme codes                                                                      |                                                                                                                                                     |                                                                      |
| Weight measured                                                                                                            |                                                                                                                                                     |                                                                      |
| Requires influenza virus vaccination codes                                                                                 |                                                                                                                                                     |                                                                      |
| Non-HDL cholesterol test result codes                                                                                      |                                                                                                                                                     |                                                                      |
| Cholesterol codes without a value                                                                                          |                                                                                                                                                     |                                                                      |
| Codes indicating the patient has chosen not to have a neuropathy assessment                                                |                                                                                                                                                     |                                                                      |
| Codes for neuropathy assessment unsuitable for patient                                                                     |                                                                                                                                                     |                                                                      |
| Oral anticoagulant prophylaxis codes                                                                                       |                                                                                                                                                     |                                                                      |
| Codes indicating the patient has chosen not to receive oral anticoagulant                                                  |                                                                                                                                                     |                                                                      |
| Oral Anticoagulant review                                                                                                  |                                                                                                                                                     |                                                                      |
| Over the counter (OTC) salicylate codes                                                                                    |                                                                                                                                                     |                                                                      |
| Palliative care not clinically indicated codes                                                                             |                                                                                                                                                     |                                                                      |
| Peak expiratory flow rate (PEFR) codes                                                                                     |                                                                                                                                                     |                                                                      |
| Codes indicating patient chose not to receive a Pertussis vaccination in pregnancy                                         |                                                                                                                                                     |                                                                      |
| Pharmacotherapy codes                                                                                                      |                                                                                                                                                     |                                                                      |
| Pneumococcal vaccination persisting contraindication codes                                                                 |                                                                                                                                                     |                                                                      |
| Codes indicating the patient chose not to receive a pneumococcal vaccination                                               |                                                                                                                                                     |                                                                      |
| Pneumococcal vaccination expiring contraindication codes                                                                   |                                                                                                                                                     |                                                                      |
| Pneumococcal vaccination no consent codes                                                                                  |                                                                                                                                                     |                                                                      |
| Codes for proteinuria                                                                                                      |                                                                                                                                                     |                                                                      |
| Codes indicating attendance at a pulmonary rehabilitation programme                                                        |                                                                                                                                                     |                                                                      |
| Codes for patient chose not to be referred to a pulmonary rehabilitation programme                                         |                                                                                                                                                     |                                                                      |
| Codes indicating an offer of referral to a pulmonary rehabilitation programme                                              |                                                                                                                                                     |                                                                      |
| Codes indicating that a referral to a pulmonary rehabilitation programme is not suitable for the patient                   |                                                                                                                                                     |                                                                      |
| Codes for pulmonary rehabilitation programme unavailable                                                                   |                                                                                                                                                     |                                                                      |
| Invite for rheumatoid arthritis care review codes                                                                          |                                                                                                                                                     |                                                                      |
| Codes indicating the patient has chosen not to receive rheumatoid arthritis quality indicator care                         |                                                                                                                                                     |                                                                      |
| Codes for rheumatoid arthritis quality indicator care unsuitable for patient                                               |                                                                                                                                                     |                                                                      |
| Rheumatoid arthritis review codes                                                                                          |                                                                                                                                                     |                                                                      |
| Asthma day symptom codes                                                                                                   |                                                                                                                                                     |                                                                      |
| Asthma exercise codes                                                                                                      |                                                                                                                                                     |                                                                      |
| Asthma sleep codes                                                                                                         |                                                                                                                                                     |                                                                      |
| Support and refer stop smoking service and advisor codes                                                                   |                                                                                                                                                     |                                                                      |
| Requires pneumococcal vaccination codes                                                                                    |                                                                                                                                                     |                                                                      |
| Retinal screening codes                                                                                                    |                                                                                                                                                     |                                                                      |
| National diabetes audit (NDA) retinal screening codes                                                                      |                                                                                                                                                     |                                                                      |
| Asthma review codes                                                                                                        |                                                                                                                                                     |                                                                      |
| Rotavirus vaccination exception reporting codes                                                                            |                                                                                                                                                     |                                                                      |
| Codes indicating the patient has chosen not to receive salicylate                                                          |                                                                                                                                                     |                                                                      |
| Simon Broome criteria code                                                                                                 |                                                                                                                                                     |                                                                      |
| Serum fructosamine codes                                                                                                   |                                                                                                                                                     |                                                                      |
| Codes indicating the patient chose not to receive a shingles vaccination                                                   |                                                                                                                                                     |                                                                      |
| Cervical screening codes                                                                                                   |                                                                                                                                                     |                                                                      |
| Smoking Intervention and Advice                                                                                            |                                                                                                                                                     |                                                                      |
| Invite for smoking care review codes                                                                                       |                                                                                                                                                     |                                                                      |
| Codes indicating the patient has chosen not to receive smoking quality indicator care                                      |                                                                                                                                                     |                                                                      |
| Codes for smoking quality indicator care unsuitable for patient                                                            |                                                                                                                                                     |                                                                      |
| Codes indicating the patient has chosen not to give their smoking status                                                   |                                                                                                                                                     |                                                                      |
| Codes indicating the patient has chosen not to accept referral to a social prescribing service                             |                                                                                                                                                     |                                                                      |
| Social prescribing referral codes                                                                                          |                                                                                                                                                     |                                                                      |
| Codes indicating the patient has chosen not to receive a spirometry test                                                   |                                                                                                                                                     |                                                                      |
| Diagnostic spirometry quality indicator service unavailable codes                                                          |                                                                                                                                                     |                                                                      |
| Codes for spirometry testing unsuitable for patient                                                                        |                                                                                                                                                     |                                                                      |
| Codes indicating the patient has chosen not to receive a statin prescription                                               |                                                                                                                                                     |                                                                      |
| Statin therapy offered                                                                                                     |                                                                                                                                                     |                                                                      |
| Invite for stroke care review codes                                                                                        |                                                                                                                                                     |                                                                      |
| Codes indicating the patient has chosen not to receive stroke quality indicator care                                       |                                                                                                                                                     |                                                                      |
| Codes for stroke quality indicator care unsuitable for patient                                                             |                                                                                                                                                     |                                                                      |
| Total cholesterol high-density lipoprotein (HDL) codes                                                                     |                                                                                                                                                     |                                                                      |
| Thyroid function test codes                                                                                                |                                                                                                                                                     |                                                                      |
| Hypothyroidism exception codes                                                                                             |                                                                                                                                                     |                                                                      |
| Triglyceride test result codes                                                                                             |                                                                                                                                                     |                                                                      |
| INR Time in therapeutic range                                                                                              |                                                                                                                                                     |                                                                      |
| Angiotensin-converting enzyme (ACE) inhibitor contraindications (expiring)                                                 |                                                                                                                                                     |                                                                      |
| Angiotensin II receptor blockers (ARB) contraindications (expiring)                                                        |                                                                                                                                                     |                                                                      |
| Clopidogrel contraindications (expiring)                                                                                   |                                                                                                                                                     |                                                                      |
| Dipyridamole contraindications (expiring)                                                                                  |                                                                                                                                                     |                                                                      |
| Beta-blocker contraindications (expiring)                                                                                  |                                                                                                                                                     |                                                                      |
| Oral anticoagulant contraindications (expiring)                                                                            |                                                                                                                                                     |                                                                      |
| Direct renin inhibitors contraindications (expiring)                                                                       |                                                                                                                                                     |                                                                      |
| Salicylate contraindications (expiring)                                                                                    |                                                                                                                                                     |                                                                      |
| Statin contraindications (expiring)                                                                                        |                                                                                                                                                     |                                                                      |
| Urea and Electrolytes test results                                                                                         |                                                                                                                                                     |                                                                      |
| Angiotensin-converting enzyme (ACE) inhibitor contraindications (persisting)                                               |                                                                                                                                                     |                                                                      |
| Angiotensin II receptor blockers (ARB) contraindications (persisting)                                                      |                                                                                                                                                     |                                                                      |
| Clopidogrel contraindications (persisting)                                                                                 |                                                                                                                                                     |                                                                      |
| Dipyridamole contraindications (persisting)                                                                                |                                                                                                                                                     |                                                                      |
| Flu vaccine contraindications (persisting)                                                                                 |                                                                                                                                                     |                                                                      |
| Beta-blocker contraindications (persisting)                                                                                |                                                                                                                                                     |                                                                      |
| Oral anticoagulant contraindications (persisting)                                                                          |                                                                                                                                                     |                                                                      |
| Salicylate contraindications (persisting)                                                                                  |                                                                                                                                                     |                                                                      |
| Statin contraindications (persisting)                                                                                      |                                                                                                                                                     |                                                                      |

|

### THESE CODE GROUPS ANYTIME

Abdominal aortic aneurysm diagnosis codes
History of atrial fibrillation or flutter
Atrial fibrillation codes
Atrial fibrillation resolved codes
Alcohol consumption codes
Left foot amputation codes
Right foot amputation codes
Angina diagnosis codes
Asthma diagnosis codes
Asthma resolved codes
Autism diagnosis codes
Body mass index (BMI) codes
Body mass index (BMI) codes >= 30 without an associated BMI value
Down syndrome body mass index (BMI) codes
Body mass index (BMI) healthy codes
Body mass index (BMI) obese codes
Body mass index (BMI) overweight codes
Body mass index (BMI) underweight codes
Body mass index (BMI) codes with an associated BMI value
Severe asthma and dust related lung disease codes
Non-haematological cancer diagnosis codes with or without associated treatment
Chronic obstructive pulmonary disease (COPD), emphysema, and associated lung diseases codes
Haematological cancer codes
Congenital heart disease codes
Pregnant patients at any stage of pregnancy
Non-asthma and non-COPD chronic respiratory disease codes
Rare genetic, metabolic and autoimmune disease codes
Transplant codes
Codes for relevant malignancies
Coronary heart disease (CHD) codes
Chronic heart disease codes
Chronic kidney disease (CKD) stage 3-5 codes
Chronic kidney disease (CKD) stage 1-2 codes
Chronic kidney disease (CKD) stage 1 and 2 codes
Chronic kidney disease (CKD) stage 4 and 5 codes
Chronic kidney disease (CKD) stage 3, 4 and 5 codes
Chronic kidney disease (CKD) resolved codes
Chronic liver disease (CLD) codes
Chronic neurological disease (CND) codes
Chronic obstructive pulmonary disease (COPD) codes
Chronic obstructive pulmonary disease (COPD) resolved codes
Spirometry codes for chronic obstructive pulmonary disease (COPD)
Chronic respiratory disease codes
Chronic respiratory disease (CRD) codes
Patient deceased codes
Codes for dementia
Depression diagnosis codes
Depression resolved codes
Diabetes nephropathy codes
Diabetes mellitus codes
Diabetes mellitus codes for pneumococcal service
Codes for diabetes (non–type 1)
Diabetes resolved codes
Codes for type 1 diabetes
Diabetes Type 1 codes used in National Audit
Codes for diabetes type 2
Diabetes Type 2 codes used in National Audit
Down’s syndrome codes
Dysphagia diagnosis codes
Electrocardiogram (ECG) indicating atrial fibrillation or flutter codes
Epilepsy diagnosis codes
Epilepsy resolved codes
Asian or Asian British Bangladeshi ethnicity group codes (NHS Digital 2016 grouping)
Asian or Asian British Chinese ethnicity group codes (NHS Digital 2016 grouping)
Asian or Asian British Indian ethnicity group codes (NHS Digital 2016 grouping)
Asian or Asian British Any other Asian background ethnicity group codes (NHS Digital 2016 grouping)
Asian or Asian British Pakistani ethnicity group codes (NHS Digital 2016 grouping)
Black or African or Caribbean or Black British African ethnicity group codes (NHS Digital 2016 grouping)
Black or African or Caribbean or Black British Caribbean ethnicity group codes (NHS Digital 2016 grouping)
Black or African or Caribbean or Black British Any other Black or African or Caribbean background ethnicity group codes (NHS Digital 2016 grouping)
Mixed or multiple ethnic groups Any other Mixed or multiple ethnic background ethnicity group codes (NHS Digital 2016 grouping)
Mixed or multiple ethnic groups White and Asian ethnicity group codes (NHS Digital 2016 grouping)
Mixed or multiple ethnic groups White and Black African ethnicity group codes (NHS Digital 2016 grouping)
Mixed or multiple ethnic groups White and Black Caribbean ethnicity group codes (NHS Digital 2016 grouping)
Not stated ethnicity group codes (NHS Digital 2016 grouping)
Other ethnic group Arab ethnicity group codes (NHS Digital 2016 grouping)
Other ethnic group Any other ethnic group ethnicity group codes (NHS Digital 2016 grouping)
White English or Welsh or Scottish or Northern Irish or British ethnicity group codes (NHS Digital 2016 grouping)
White Gypsy or Irish Traveller ethnicity group codes (NHS Digital 2016 grouping)
White Irish ethnicity group codes (NHS Digital 2016 grouping)
White Any other White background ethnicity group codes (NHS Digital 2016 grouping)
Active and inactive ethnicity codes
Excessive alcohol consumption codes
Code for ex-smoker
Falls codes
Fragility fracture codes
Familial hypercholesterolemia diagnostic codes
Genetically proven familial hypercholesterolaemia codes
Flu vaccination codes
Familial and non-familial hypercholesterolemia diagnosis codes
Gestational Diabetes Codes
Codes for the completing Hepatitis B vaccination dose
First hepatitis B vaccination codes
Second hepatitis B vaccination codes
Heart failure codes
Codes for heart failure due to left ventricular systolic dysfunction (LVSD)
Haemophilus influenzae type B Meningitis C (HibMenC) vaccination codes
HPV vaccination codes
Haemorrhagic stroke codes
Hypertension diagnosis codes
Hypertension resolved codes
Immunosuppression codes (persisting)
Immunosuppression resolved codes
Immunosuppression procedure codes
Intranasal seasonal influenza vaccine ‘first’ dose given codes
Intranasal seasonal influenza vaccine ‘second’ dose codes
Intranasal seasonal influenza vaccination ‘first’ dose given by other healthcare provider codes
Intranasal seasonal influenza vaccination ‘second’ dose given by other healthcare provider codes
Body mass index (BMI) codes
Body mass index (BMI) codes >= 40 without an associated BMI value
Learning disability (LD) codes
Code for stopped lithium
Smoker codes
Seizure free for over 12 months codes
Epilepsy seizure frequency codes
MenACWY GP vaccination codes
MenACWY other healthcare provider vaccination codes
First Men B vaccination codes
Second Men B vaccination codes
Booster Men B vaccination codes
First Men B vaccination codes by another healthcare provider
Second Men B vaccination codes by another healthcare provider
Booster Men B vaccination codes by another healthcare provider
Psychosis and schizophrenia and bipolar affective disease codes
Codes for in remission from serious mental illness
Myocardial infarction (MI) diagnosis codes
Mild frailty diagnosis codes
MMR first dose vaccination codes
MMR second dose vaccination codes
Moderate frailty diagnosis codes
National diabetes audit (NDA) body mass index (BMI) codes
National diabetes audit (NDA) diabetes mellitus diagnosis codes
National diabetes audit (NDA) diabetes mellitus codes to determine diabetes type for the audit
Persistent proteinuria codes
National diabetes audit (NDA) smoking habit codes
Codes that indicate complete removal of the cervix
Code for never smoked
Osteoporosis codes
Non-haemorrhagic stroke codes
Non Type 1 or Type 2 diabetes mellitus codes used in National audit
Peripheral arterial disease (PAD) diagnostic codes
Palliative care codes
Pneumococcal (PCV) vaccination codes
Pertussis vaccination in pregnancy codes
Pertussis vaccination in pregnancy given by other healthcare provider codes
Pneumococcal vaccination codes
Pneumococcal vaccination given by other healthcare provider codes
Possible Familial Hypercholesterolaemia
Pre-diabetes codes
Codes indicating the patient is pregnant
Rheumatoid arthritis diagnosis codes
Requires interpreter codes
Rotavirus vaccination 1st dose given codes
Rotavirus vaccination 2nd dose given codes
Severe frailty diagnosis codes
Severe and malignant Hypertension
Seasonal influenza inactivated vaccine first dose codes
Seasonal influenza inactivated vaccine second dose codes
Seasonal influenza inactivated vaccine first dose given by other healthcare provider codes
Seasonal influenza inactivated vaccine second dose given by other healthcare provider codes
Shingles GP vaccination codes
Shingles other healthcare provider vaccination codes
Smoking habit codes
Stroke diagnosis codes
Supraventricular tachycardia (SVT) Codes
Hypothyroidism diagnosis codes
Transient ischaemic attack (TIA) codes

### THESE CODE GROUPS IN LAST 2 YEARS

Ambulatory blood pressure codes
Codes indicating the patient has chosen not to receive angiotensin-converting enzyme (ACE) inhibitor
Invite for atrial fibrillation care review codes
Codes indicating the patient has chosen not to receive atrial fibrillation quality indicator care
Codes for atrial fibrillation quality indicator care unsuitable for patient
Atrial fibrillation monitoring and review codes
Codes indicating the patient has chosen not to receive angiotensin II receptor blockers (ARB)
Brief intervention for excessive alcohol consumption codes
Brief intervention for excessive alcohol consumption declined codes
Alcohol consumption screening refused codes
Extended intervention for excessive alcohol consumption codes
Extended intervention for excessive alcohol consumption declined codes
Alcohol Intervention and Advice
Alcohol screening and assessment declined codes
Referral to specialist alcohol treatment service codes
Referral to specialist alcohol treatment service declined codes
Angina referral to specialist codes
Codes indicating the patient has chosen not to receive antihypertensive treatment
Anxiety screening codes
Anxiety screening declined codes
Anxiety support and treatment codes
Codes for Albumin Creatinine and Protein Creatinine Ratio for chronic kidney disease (CKD)
Asthma emergency admission codes
Invite for asthma care review codes
Codes indicating the patient has chosen not to receive asthma monitoring
Codes indicating the patient has chosen not to receive asthma quality indicator care
Codes for asthma quality indicator care unsuitable for patient
Asthma quality indicator service unavailable codes
Spirometry codes for asthma
Alcohol Use Disorders Identification Test (AUDIT) codes
Alcohol Use Disorder Identification Test Consumption (AUDIT C) codes
Codes indicating the patient has chosen not to receive a blood test
Codes indicating the patient has chosen not to have their body mass index (BMI) measured
Codes for body mass index (BMI) measurement unsuitable for patient
Blood pressure (BP) recording codes
Codes indicating the patient has chosen not to have blood pressure procedure
Breast cancer screening codes
Bone sparing therapy codes
COVID19 activity codes
Provision of high dose corticosteroid safety card codes
Flu-like symptoms and upper and lower respiratory tract infection codes
COVID19 risk category codes
Calcium test result codes
Invite for cancer care review codes
Codes indicating the patient has chosen not to receive cancer quality indicator care
Codes for cancer quality indicator care unsuitable for patient
Cockcroft Gault - estimated glomerular filtration rate
Stroke risk assessment using CHADS2
Stroke risk assessment using CHA2DS2-VASc
Invite for coronary heart disease (CHD) care review codes
Codes indicating the patient has chosen not to receive coronary heart disease (CHD) quality indicator care
Codes for coronary heart disease (CHD) quality indicator care unsuitable for patient
Codes for exception from serum cholesterol target (persisting)
Total cholesterol codes
Total cholesterol
Codes indicating the patient is on maximum tolerated cholesterol lowering treatment
Codes for proteinuria for chronic kidney disease (CKD)
Clopidogrel prophylaxis codes
Codes indicating the patient has chosen not to receive clopidogrel
Colorectal cancer screening codes
Invite for chronic obstructive pulmonary disease (COPD) care review codes
Codes indicating the patient has chosen not to receive chronic obstructive pulmonary disease (COPD) quality indicator care
Codes for chronic obstructive pulmonary disease (COPD) quality indicator care unsuitable for patient
Chronic obstructive pulmonary disease (COPD) quality indicator service unavailable codes
Codes for chronic obstructive pulmonary disease (COPD) review
Codes for serum creatinine
Codes indicating the patient has chosen not to receive cervical smear
Patient not responded to three invites for cervical screening codes
Codes for cervical screening quality indicator care unsuitable for patient
Cardiovascular disease (CVD) risk assessment codes greater than 20 per cent
Cardiovascular disease (CVD) risk assessment codes
Codes indicating the patient has chosen not to receive cardiovascular disease (CVD) risk assessment
Codes indicating cardiovascular disease (CVD) risk assessment was deemed unsuitable for the patient
Invite for cardiovascular disease (CVD) care review codes
Codes indicating the patient has chosen not to receive quality indicator cardiovascular disease (CVD) care
Codes for cardiovascular disease (CVD) quality indicator care unsuitable for patient
Evidence of diabetic retinopathy screening attendance codes
Cardiovascular disease (CVD) risk assessment done
Assessment for dementia codes
Dementia care plan codes
Codes indicating the patient has chosen not to receive dementia care plan
Dementia care plan review codes
Codes indicating the patient has chosen not to receive dementia care plan review
Invite for dementia care review codes
Dementia medication review codes
Codes indicating the patient has chosen not to receive dementia quality indicator care
Codes for dementia quality indicator care unsuitable for patient
Invite for depression care review codes
Codes indicating the patient has chosen not to receive depression quality indicator care
Codes for depression quality indicator care unsuitable for patient
Depression review codes
Depression screening codes
Depression screening declined codes
Depression support and treatment codes
Diet Intervention and Advice
Codes indicating the patient has chosen not to receive dipyridamole
Invite for diabetes care review codes
Codes for maximum tolerated diabetes treatment
Codes indicating the patient has chosen not to receive diabetes quality indicator care
Codes for diabetes quality indicator care unsuitable for patient
Referral to NHS diabetes prevention programme attended
Referral to NHS diabetes prevention programme completed
Referral to NHS diabetes prevention programme offered or declined
Diabetic retinopathy screening attendance codes
Referred for diabetes structured education programme
Codes indicating the patient has chosen not to have diabetes structured education programme
Codes for diabetes structured education programme unsuitable for the patient
Diabetes structured education programme service unavailable codes
Dutch Lipid Clinic Network Codes
Dual energy X-ray absorptiometry (DXA) scan result of osteoporotic without a value
Dual energy X-ray absorptiometry (DXA) scan result with a T score value
Codes indicating the patient has chosen not to have an echocardiogram
Echocardiogram (Echo) codes
Echocardiography service unavailable codes
Codes for echocardiogram unsuitable for the patient
Estimated glomerular filtration rate
Contraceptive counselling codes for people with epilepsy
Contraceptive counselling for people with epilepsy inappropriate or declined exception codes
Pregnancy advice codes for people with epilepsy
Pregnancy advice for people with epilepsy inappropriate or declined exception codes
Pre-conception advice codes for people with epilepsy
Pre-conception advice inappropriate or declined exception codes
Exercise intervention and advice
Falls discussion codes
Falls discussion declined codes
Referral to falls service codes
Fasting plasma glucose codes
Codes indicating the patient has chosen not to have a foot examination
Codes for foot examination unsuitable for patient
Codes indicating the patient has chosen not to receive a flu vaccination
Flu vaccine contraindications (expiring)
Flu vaccination no consent codes
Feet examination (neuropathy testing or peripheral pulses) codes
Frailty assessment codes
Frailty assessment declined codes
Foot risk classification codes
Gamma-glutamyl transferase test results
Glucose test recording
HASBLED score codes
Haemoglobin test results
Healthcare worker codes
HDL cholesterol test result codes
Hepatitis B blood test codes
Invite for heart failure care review codes
Codes indicating the patient has chosen not to receive heart failure quality indicator care
Codes for heart failure quality indicator care unsuitable for patient
Heart failure quality indicator service unavailable codes
Learning disability (LD) health check codes
Codes for maximal blood pressure (BP) therapy
Invite for hypertension care review codes
Codes indicating the patient has chosen not to receive hypertension quality indicator care
Codes for hypertension quality indicator care unsuitable for patient
IFCC HbA1c monitoring range codes
Immunosuppression codes (expiring)
Codes indicating the patient has chosen not to receive beta blocker
Low density lipoprotein (LDL) cholesterol test results
Liver function test results
Lifestyle intervention and advice codes
Lifestyle advice codes
Codes for microalbuminuria
Code for maximal anticonvulsant therapy
Code for cancer care review
Medication review codes
Initial memory assessment codes
Codes indicating the patient has chosen not to receive initial memory assessment
Referral to memory clinic codes
Codes indicating the patient has chosen not to accept referral to memory clinic
Codes indicating the patient chose not to receive a MenACWY vaccination
Men B vaccination contraindicated codes
Codes indicating the patient chose not to receive a first Men B vaccination
Codes indicating the patient chose not to receive a second Men B vaccination
Codes indicating the patient chose not to receive a Men B booster vaccination
Invite mental health care review codes
Codes for mental health care plan
Codes indicating the patient has chosen not to receive mental health quality indicator care
Codes for mental health quality indicator care unsuitable for patient
Codes for Medical Research Council (MRC) breathlessness scale score
Codes for Medical Research Council (MRC) breathlessness scale score greater than or equal to 3
Urine albumin codes
National diabetes audit (NDA) blood pressure (BP) codes
Height measured
Attended diabetes structured education programme codes
Offered diabetes structured education programme codes
Weight measured
Requires influenza virus vaccination codes
Non-HDL cholesterol test result codes
Cholesterol codes without a value
Codes indicating the patient has chosen not to have a neuropathy assessment
Codes for neuropathy assessment unsuitable for patient
Oral anticoagulant prophylaxis codes
Codes indicating the patient has chosen not to receive oral anticoagulant
Oral Anticoagulant review
Over the counter (OTC) salicylate codes
Palliative care not clinically indicated codes
Peak expiratory flow rate (PEFR) codes
Codes indicating patient chose not to receive a Pertussis vaccination in pregnancy
Pharmacotherapy codes
Pneumococcal vaccination persisting contraindication codes
Codes indicating the patient chose not to receive a pneumococcal vaccination
Pneumococcal vaccination expiring contraindication codes
Pneumococcal vaccination no consent codes
Codes for proteinuria
Codes indicating attendance at a pulmonary rehabilitation programme
Codes for patient chose not to be referred to a pulmonary rehabilitation programme
Codes indicating an offer of referral to a pulmonary rehabilitation programme
Codes indicating that a referral to a pulmonary rehabilitation programme is not suitable for the patient
Codes for pulmonary rehabilitation programme unavailable
Invite for rheumatoid arthritis care review codes
Codes indicating the patient has chosen not to receive rheumatoid arthritis quality indicator care
Codes for rheumatoid arthritis quality indicator care unsuitable for patient
Rheumatoid arthritis review codes
Asthma day symptom codes
Asthma exercise codes
Asthma sleep codes
Support and refer stop smoking service and advisor codes
Requires pneumococcal vaccination codes
Retinal screening codes
National diabetes audit (NDA) retinal screening codes
Asthma review codes
Rotavirus vaccination exception reporting codes
Codes indicating the patient has chosen not to receive salicylate
Simon Broome criteria code
Serum fructosamine codes
Codes indicating the patient chose not to receive a shingles vaccination
Cervical screening codes
Smoking Intervention and Advice
Invite for smoking care review codes
Codes indicating the patient has chosen not to receive smoking quality indicator care
Codes for smoking quality indicator care unsuitable for patient
Codes indicating the patient has chosen not to give their smoking status
Codes indicating the patient has chosen not to accept referral to a social prescribing service
Social prescribing referral codes
Codes indicating the patient has chosen not to receive a spirometry test
Diagnostic spirometry quality indicator service unavailable codes
Codes for spirometry testing unsuitable for patient
Codes indicating the patient has chosen not to receive a statin prescription
Statin therapy offered
Invite for stroke care review codes
Codes indicating the patient has chosen not to receive stroke quality indicator care
Codes for stroke quality indicator care unsuitable for patient
Total cholesterol high-density lipoprotein (HDL) codes
Thyroid function test codes
Hypothyroidism exception codes
Triglyceride test result codes
INR Time in therapeutic range
Angiotensin-converting enzyme (ACE) inhibitor contraindications (expiring)
Angiotensin II receptor blockers (ARB) contraindications (expiring)
Clopidogrel contraindications (expiring)
Dipyridamole contraindications (expiring)
Beta-blocker contraindications (expiring)
Oral anticoagulant contraindications (expiring)
Direct renin inhibitors contraindications (expiring)
Salicylate contraindications (expiring)
Statin contraindications (expiring)
Urea and Electrolytes test results
Angiotensin-converting enzyme (ACE) inhibitor contraindications (persisting)
Angiotensin II receptor blockers (ARB) contraindications (persisting)
Clopidogrel contraindications (persisting)
Dipyridamole contraindications (persisting)
Flu vaccine contraindications (persisting)
Beta-blocker contraindications (persisting)
Oral anticoagulant contraindications (persisting)
Salicylate contraindications (persisting)
Statin contraindications (persisting)

### THESE DRUGS

Angiotensin-converting enzyme (ACE) inhibitor prescription codes
Angiotensin II receptor blockers (ARB) prescription codes
Antihypertensive medications
Antipsychotic drug codes
Asthma-related drug treatment codes
Asthma inhaled corticosteroids codes
Bone sparing agent drug codes
Severe asthma drug treatment codes
Chronic obstructive pulmonary disease (COPD) drug codes
Corticosteroid drug codes
Severe immunosuppression drug codes
Prednisolone drug codes
Clopidogrel drug codes
Constipation treatment codes
Dipyridamole prescription codes
Diabetes mellitus drugs codes
Drug treatment for epilepsy
Product containing ezetimibe (medicinal product)
Flu vaccine drug codes
Immunosuppression drugs
Licensed beta-blocker prescription codes
Lithium prescription codes
MenACWY vaccine codes
Men B vaccine drug codes
Metformin drug codes
MMR vaccine codes
Oral anticoagulant drug codes
PCSK9 Inhibitors
Pharmacotherapy drug codes
Pneumococcal vaccine drug codes
Dissent from secondary use of GP patient identifiable data
Dissent withdrawn from secondary use of GP patient identifiable data
Salicylate prescription codes
Seasonal influenza inactivated vaccine codes
Statin codes
Hypothyroidism treatment codes
Unlicensed beta-blocker prescription codes
