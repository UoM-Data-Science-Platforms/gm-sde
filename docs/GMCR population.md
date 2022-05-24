# GMCR population
*Updated in February 2022*

## Overview
Analysts need to know the population(s) that the Greater Manchester Care Record (GMCR) represents. This is useful for their analyses, and for accurate reporting in publications. It is also possible that analysts might want to define their study population in different ways e.g. residents of GM vs GM healthcare users. This document aims to help explain the population(s) represented by the GMCR.


## Population
The GMCR contains data for people who have interacted with healthcare services within GM. This includes:
- Patients registered (now or previously) with a GP within GM
- Patients who have attended a hospital in GM
- Patients who have attended a tertiary care provider in GM such as the Christie

**NB1:** Patients do not need to be a resident (now or previously) of GM to have data in the GMCR.

**NB2:** Patients living in GM may not be in the GMCR if all of their healthcare engagement takes place outside GM.


## Opt outs
Patients can opt out of sharing their healthcare data. We know how many people opt out (details below), but have no other information about them.
Number of patients
As of February 2022 there are 5,791,604 patients in GMCR. This includes dead people, opt outs and duplicates. If we filter to people who are currently registered with a GP in GM (or who were registered with a GM GP at the time of their death), which should exclude many of the duplicates caused by unlinked hospital visits, and also mean we actually have clinical data for those patients, then there are 3,307,302 patients, of which 3,000,031 are alive and have not opted out of data sharing.

*Table 1 - Population counts of the GMCR as at February 2022*
| Definition                                         | Patients   | Living patients (and not opted out) |
|----------------------------------------------------|------------|-------------------------------------|
| All patients in GMCR                               | 5,791,604  |                                     |
| Registered with a GP (either inside or out of GM)* | 3,600,916  |                                     |
| Registered with a GP and lives in GM✝              | 3,393,983  |            3,087,143                |
| Registered with a GP inside GM                     | 3,307,302  |            3,000,031                |

*If we know that someone is “registered with a GP” it implies that we know their NHS number and have found a corresponding record on the national NHS spine.

✝This will not include people of no fixed abode


## Comparison with ONS estimates
The mid-2020 population estimate for GM from ONS is 2.8m. As has been described above, the population of the GMCR is not the same as the population of GM, though we would expect it to be very similar. The GMCR population estimate varies depending on how you count it, but roughly speaking there are 15% more patients in GMCR than the ONS estimate. This is in line with other national databases e.g. the COVID-IMPACT project finds many areas, and in particular cities, with many more patients than the ONS estimates. 

There are several mechanisms whereby the number of patients in the GMCR can be inflated e.g. duplication can occur where a single patient appears multiple times within the GMCR. Possible causes are discussed below.


*Patient linkage*

When a patient uses a healthcare service within GM, their details are recorded, and then passed to the GMCR. Details, such as NHS number, are then used to attempt to find that patient in the GMCR and link this new visit with an existing record. If an existing match cannot be found, then the GMCR assumes this is a new patient and adds them. If, for example, a patient in hospital did not provide an NHS number, or if the NHS number was transcribed incorrectly, then the patient would appear in the GMCR multiple times, and it would be impossible to work out that several patients in the GMCR are actually the same person.


*GP registration*

Patients should only be registered with a single GP. When a patient registers with a new GP, they provide their NHS number, or details of their previous GP. This leads to the patient being deregistered at their previous GP, and their records passed across to the new GP. However, it is possible that the previous GP cannot be found. In this case you may end up with patients simultaneously registered with two different GPs, and having 2 different NHS numbers. This might seem strange when the population of GM is only ~3 million. This is not an error, it is simply due to the way the data is collected together.


*Students*

Greater Manchester has a large student population as it includes: The University of Manchester, Manchester Metropolitan University, The University of Salford and The University of Bolton. When students attend a university in GM, they will usually register with a GP there, and so they will appear in the GMCR but their registered address for electoral purposes may remain as their family home. The ONS population estimate attempts to correct for this. However, once a student leaves university, the GMCR will retain their record for the period of time that they were resident there. Until the student registers with a new GP, the GMCR will still consider them an active member.
