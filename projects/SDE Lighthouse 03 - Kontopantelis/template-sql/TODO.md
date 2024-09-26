**_Notes for the PI when we give them the data_**

# General

- Previously any code set used would be automatically extracted and put into the `clincial-code-sets.csv` file in the project root. This is still the case for any code sets used in the normal way. However we now can make use of NHS refsets (clusters in snowflake). For all projects we should either inform the PI which clusters have been used, or pull off the SNOMED codes for each cluster used. NB this is also needed for the code sets that are used to populate the "LongTermConditionRegister_SecondaryUses" table.

# Project specific

- We need to explain to the PI that the GP encounters are a proxy. Each code is classified in terms of whether it likely means a consultation took place. E.g. measurements like BMI or blood pressure, or things like medication reviews. If a person has any of these codes on a day, then it is taken as a GP encounter. This was developed by NHS GM and further detail can be provided (from Matthew Conroy) if needed by the PI.
- Remind PI that "Z drugs" (zopiclone, zolpidem and zaleplon) come under the category "Benzodiazipine related"
- Tell PI the following "nice to have" outcomes were unavailable:
  - continuity of care
  - carer type
  - carer review
  - missed appointment

  TEST
