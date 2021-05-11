## Index

- [Overview](../README.md)
- [Data description](index.md)
- [Current projects](current-projects.md)
- **CLINICAL CODE SETS**
- [Additional technical information](additional-technical-information.md)

# Greater Manchester Care Record - clinical code sets

**_Needs writing_**
Clinical code sets are...

Link to papers...

Link to clinical codes .org, opensafely, VSAC etc..

auto generated list of code sets



## Validating Code Sets

To get an idea of how well represented a condition is by 

The clinical code sets that have been created by the RDEs can be validated using the [.projects/Reports] directory. The directory structure is as follows:

```js
Reports
├─ extraction-sql
│  ├─ concepts-per-clinical-system.sql
│  ├─ concepts-per-clinical-system-individual-concept.sql
│  ├─ moderate-covid-vulnerability-investigation.sql
├─ output-data-files
│  ├─ .gitignore
│  ├─ README.md
├─ template-sql
│  ├─ concepts-per-clinical-system.template.sql
│  ├─ concepts-per-clinical-system-individual-concept.template.sql
│  ├─ moderate-covid-vulnerability-investigation.template.sql
├─ extract-data.bat
├─ generate-sql.sh
├─ generate-sql-windows.bat
├─ README.md
```

### Investigating prevalence of a code set across GP systems

If you want to investigate the prevalence of the codeset across each GP system (TPP, Vision, EMIS):

1. Open 'concepts-per-clinical-system-individual-concept.template.sql' 
2. Edit line 29 by adding the name of the code set that you are interested in. The code should then look something like:

```sql
	--> CODESET antipsychotics
```

3. Replace 'insert-concept-here' with the name of the code set on lines 213 and 368. 
4. Save and close the file.
5. Run the file 'generate-sql-windows.bat'.
6. Open 'concepts-per-clinical-system-individual-concept.sql' and copy the contents into a new SQL query on your VDE.
7. Run the query, and the output will be a table of prevalence across the GP systems.

Once the above process has been followed, if you wish to investigate further and look for potential missing codes:

1. Run the query from line 309 to line 368.
2. The output will be a list of potential codes (CTV3, EMIS, SNOMED, or READV2) that are missing from the code sets.
3. The missing codes (if they look sensible/relevant) can then be copy and pasted into the relevant code set text files at [.shared/clinical-code-sets]