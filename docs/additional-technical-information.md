## Index

- [Overview](../README.md)
- [Data description](index.md)
- [Current projects](current-projects.md)
- [Clinical code sets](clinical-code-sets.md)
- **ADDITIONAL TECHNICAL INFORMATION**
  - [Research Data Engineer process](process-for-research-data-engineers.md)
  - [SQL generation process](SQL-generation-process.md)

# Greater Manchester Care Record - additional technical information

This is primarily intended for Research Data Engineers (RDEs) working on the GMCR, but may also be useful to other people. The information about how to setup the project is below. Other useful information for RDEs is available in the **Index** above.

## Setup

Several parts of the process are automated. For example the generation of SQL for extracting data, and the inserting of clinical code sets.

### Prerequisites

[nodejs](https://nodejs.org/en/) should be installed and available to execute from a terminal/command line.

Once installed execute the following from a terminal/command line in the root of the project to install the dependencies:

```
npm install
```

### Execution

Most things like this can be accessed by executing the following command:

```
npm start
```

This launches a command line interface that allows you to specify what you want to do. Currently the options are:

- Evaulate the existing code sets to check they conform to our standards (such as naming convention, file format etc..)
- Create a new clinical code set
- Generate the SQL specific to long term conditions
- Generate documentation for the reusable SQL queries
