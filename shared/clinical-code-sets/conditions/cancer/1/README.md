# Cancer
Readv2 codes from code sets published by in:

Zhu Y, Edwards D, Mant J, Payne RA, Kiddle S. Characteristics, service use and mortality of clusters of multimorbid patients in England: A population-based study. BMC Med [Internet]. 2020 Apr 10 [cited 2021 Apr 14];18(1):78. Available from: https://bmcmedicine.biomedcentral.com/articles/10.1186/s12916-020-01543-8

The above paper used the definition of LTCs as first determined in:

Barnett K, Mercer SW, Norbury M, Watt G, Wyke S, Guthrie B. Epidemiology of multimorbidity and implications for health care, research, and medical education: A cross-sectional study. Lancet [Internet]. 2012 Jul 7 [cited 2021 Apr 14];380(9836):37–43. Available from: www.thelancet.com

CTV3 and SNOMED code sets from OpenSafely.

ICD10 codes have been provided and verified by the Christie team (004). 

## Prevalence log
By examining the prevalence of codes (number of patients with the code in their record) broken down by clinical system, we can attempt to validate the clinical code sets and the reporting of the conditions. Here is a log for this code set, as of 19th July 2021.

| Concept | Version   | System    | Patients | PatientsWithConcept | PatientsWithConceptFromCode | PercentageOfPatients | PercentageOfPatientsFromCode |
| :-----: | :-------: | :-------: | :------: | :-----------------: | :-------------------------: | :------------------: | :--------------------------: |
| cancer  | 1         | EMIS      | 2615750  | 118723              | 78901                       | 4.53877473000096     | 3.01638153493262             |
| cancer  | 1         | TPP       | 211345   | 9607	               | 7280                        | 4.5456481109087      | 3.44460479311079             |
| cancer  | 1         | Vision    | 336528   | 16642               | 11427                       | 4.94520515380592     | 3.39555698188561             |

| Date       | Practice system | Population | Patients from ID | Patient from code |
| ---------- | --------------- | ---------- | ---------------: | ----------------: |
| 2024-02-22 | EMIS | 2524209 | 123626 (4.9%) | 123152 (4.88%) | 
| 2024-02-22 | TPP | 201752 | 11008 (5.46%) | 8580 (4.25%) | 
| 2024-02-22 | Vision | 335007 | 16786 (5.01%) | 16713 (4.99%) | 