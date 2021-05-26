## Index

- [Overview](../README.md)
- [Data description](index.md)
- [Current projects](current-projects.md)
- **CLINICAL CODE SETS**
- [Additional technical information](additional-technical-information.md)

# Greater Manchester Care Record - clinical code sets

Clinical code sets are shared lists of codes that are used in place of longer names or explanations.
Medical professionals use these codes to quickly record the following types of information for patients:
- Diagnoses
- Treatments, procedures and tests
- Medical equipment and supplies
- Medications

As the sharing of code sets is becoming more important for research, several online repositories have been developed:
- [OpenCodelists](https://www.opencodelists.org/) (created by OpenSAFELY)
- [ClinicalCodes](https://clinicalcodes.rss.mhs.man.ac.uk/)
- [Value Set Authority Center (VSAC)](https://vsac.nlm.nih.gov/)

There are also several published papers that describe different methods for creating, managing and sharing clinical code sets:

1. [Clinical code set engineering for reusing EHR data for research: A review.
Williams, R., Kontopantelis, E., Buchan, I. & Peek, N., Jun 2017, Journal of
Biomedical Informatics. 70, p. 1-13.](https://pubmed.ncbi.nlm.nih.gov/28442434/)

2. [Term sets: A transparent and reproducible representation of clinical code sets.
Williams, R., Brown, B., Kontopantelis, E., Van Staa, T., Peek, N., 2019, PLoS ONE.
14, 2, p. e0212291.](https://journals.plos.org/plosone/article?id=10.1371/journal.pone.0212291)

**_Needs writing_**

auto generated list of code sets

## Creating Clinical Code Sets

The Research Data Engineer (RDE) must find, or create, at least one set of codes for the concept that they are interested in. 
This text file can either be SNOMED, CTV3, ReadV2, or EMIS codes.
The file/s should be stored at [.shared/clinical-code-sets] in the relevant folder based on the type of concept.

The typical file structure for a code set looks like:

```js
1
├─ asthma.ctv3.txt
├─ asthma.readv2.txt
├─ asthma.snomed.txt
├─ asthma.emis.txt
├─ README.md
```

The number, in this case '1' refers to the version. If there are multiple versions, this is because different studies have required slightly
different definitions/scopes for the code set.

The README.md file is used to provide information about the code set, including how broad it is in scope, the source of the codes, and prevalence (see below section on validation).

## Loading code sets into SQL scripts



## Validating Clinical Code Sets

This process is designed to provide an idea of how well represented a condition is across each GP system. If the prevalence of the code among the 
three systems is relatively similar (within 10%) then it would seem that the code sets are suitably complete. If there are discrepancies, then
there may be missing codes from one or more code sets.

The clinical code sets that have been created by the RDEs can be validated using the [.projects/Reports] directory. The directory structure is as follows:

```js
Reports
├─ extraction-sql
│  ├─ concepts-per-clinical-system.sql
│  ├─ moderate-covid-vulnerability-investigation.sql
├─ output-data-files
│  ├─ .gitignore
│  ├─ README.md
├─ template-sql
│  ├─ concepts-per-clinical-system.template.sql
│  ├─ moderate-covid-vulnerability-investigation.template.sql
├─ extract-data.bat
├─ generate-sql.sh
├─ generate-sql-windows.bat
├─ README.md
```

### Investigating prevalence of a code set across GP systems

If you want to investigate the prevalence of the codeset across each GP system (TPP, Vision, EMIS):

1. Open 'concepts-per-clinical-system.template.sql' 
2. Edit line 29 by adding the name of the code set/s that you are interested in, with spaces inbetween terms. The code should then look something like:

```sql
	--> CODESET antipsychotics bipolar recurrent-depressive
```
 
4. Save and close the file.
5. Run the file 'generate-sql-windows.bat'.
6. Open 'concepts-per-clinical-system.sql' and copy the contents into a new SQL query on your VDE.
7. Run the query, and the output will be three tables:
   - Prevalence of **medication** codes across the GP systems
   - Prevalence of **event** codes (that aren't associated with a value, such as diagnoses) across the GP systems
   - Prevalence of **event** codes (that have associated values, such as BMI) across the GP systems

You should hopefully know which table is relevant for your code set/s. For example if you are just looking at
diagnoses like 'Bipolar', then you would only be interested in the second table (events with no associated value).

### Searching for potential missing codes for a code set

Once the above process has been followed, if you wish to investigate further and look for potential missing codes for a particular code set, follow the below processes.

**For Events:**

1. Scroll down to line 188 on the query that has just finished running.
2. Insert the name of the code set you're interested in on line 196 so it looks something like:

```sql
	set @concept = 'bipolar';
```

3. Run the query from 'BEGIN' on line 188 to 'END' on line 247.
4. The output will be a list of potential **Events** codes (CTV3, EMIS, SNOMED, or READV2) that are missing from the code set.
5. The missing codes (if they look sensible/relevant) can then be copy and pasted into the relevant code set text files at [.shared/clinical-code-sets].

**For Medications:**

1. Scroll down to line 250 on the query that has just finished running.
2. Insert the name of the code set you're interested in on line 258 so it looks something like:

```sql
	set @medicationconcept = 'bipolar';
```

3. Run the query from 'BEGIN' on line 250 to 'END' on line 309.
4. The output will be a list of potential **Medications** codes (CTV3, EMIS, SNOMED, or READV2) that are missing from the code set.
5. The missing codes (if they look sensible/relevant) can then be copy and pasted into the relevant code set text files at [.shared/clinical-code-sets]

### Documenting the prevalence of a code set

As code sets will be reused by RDEs, it is important to be clear what they represent, where codes originated, and what the prevalence is.

Within each individual code set folder there should be a 'README.md' file (if not, please create a new one). This file is is used to:

1. Explain what the code set is
2. State where the codes originated from
3. State any inclusions/exclusions and assumptions that would be useful for future users
4. Document the prevalence of the code set on specific dates

An example of a prevalence log table:

| Date       | Practice system | Population | Patients from ID | Patient from code |
| ---------- | --------------- | ---------- | ---------------: | ----------------: |
| 2021-03-31 | EMIS            | 2604007    | 1917797 (73.65%) |  1917707 (73.64%) |
| 2021-03-31 | TPP             | 210535     |  143525 (68.17%) |   143525 (68.17%) |
| 2021-03-31 | Vision          | 333730     |  244403 (73.23%) |   244403 (73.23%) |




