const { readFileSync, readdirSync, writeFileSync } = require('fs');
const { join } = require('path');
const { getReadMes, getCodeSet } = require('./code-sets');
const { GITHUB_BASE_URL, GITHUB_REPO } = require('./config');

const REUSABLE_QUERY_DIRECTORY = join(
  __dirname,
  '..',
  'shared',
  'Reusable queries for data extraction'
);

module.exports = {
  generateReusableQueryDocs,
  generateProjectSupplementaryReadme,
  generateCodeSetCsv,
};

/**
 * Generate a CSV file from the list of code sets
 * @param {Object[]} codeSets - List of code sets
 * @returns {string} - CSV file contents
 */
function generateCodeSetCsv(codeSets) {
  const csvHeader = `All clinical codes used by this project.
NB. This file is auto-generated.
Some clinical codes become garbled when opening csv files in MS Excel. This is because Excel attempts to convert them to a number. For example SNOMED codes above 11 digits appear in scientific notation format (1.03e11) while Read codes with a trailing decimal point such as '1371.' lose the '.' and becomes 1371
To get round this we provide the clinical codes in two columns:
- The [Code] column contains the raw values and can be used if this file is viewed in a text editor or processed by statistical software.
- The [ExcelCode] column behaves when opened in Excel and is to be used if the column needs to be copy/pasted

Name,Version,Terminology,Code,ExcelCode,Description`;
  const csv = codeSets
    .map((x) => {
      const codeSet = getCodeSet(x.codeSet);
      return codeSet[x.version]
        .map((item) =>
          item.file
            .split('\n')
            .filter((x) => x.length > 2)
            .map((row) => {
              const [code, description] = row.split('\t');
              const numericCodeForExcel = code.match(/^[0-9.]+$/) ? `"=""${code}"""` : code;
              return `"${x.codeSet}",${x.version},"${
                item.terminology
              }",${code},${numericCodeForExcel},"${description.replace(/"/g, '""')}"`;
            })
            .join('\n')
        )
        .join('\n');
    })
    .join('\n');
  return [csvHeader, csv].join('\n');
}

/**
 *
 * @param {Object} config - Config properties
 * @param {Object[]} config.codeSets - List of code sets for this readme
 * @param {string} config.another - Another property
 * @returns {string} - Markdown content string
 */
function generateProjectSupplementaryReadme({ codeSets, includedSqlFiles, projectName }) {
  const reusableQueryIntro = getReusableQueryIntro(includedSqlFiles);
  const reusableQueryBody = getReusableQueryBody(includedSqlFiles);
  const codeSetTable = getCodeSetTable(projectName);
  const codeSetIntro = getCodesetIntro(codeSets);
  const collatedCodeSetReadMe = collateCodeSetReadmes(codeSets);
  const toc = getTableOfContents();
  const finalMdString =
    toc +
    reusableQueryIntro +
    reusableQueryBody +
    codeSetIntro +
    collatedCodeSetReadMe +
    codeSetTable;
  return finalMdString.replace(/\s*$/g, '');
}

function getTableOfContents() {
  return `## Table of contents

- [Introduction](#introduction)
- [Methodology](#methodology)
- [Reusable queries](#reusable-queries)
- [Clinical code sets](#clinical-code-sets)

## Introduction

The aim of this document is to provide full transparency for all parts of the data extraction process.
This includes:

- The methodology around how the data extraction process is managed and quality is maintained.
- A full list of all queries used in the extraction, and their associated objectives and assumptions.
- A full list of all clinical codes used for the extraction.

## Methodology

After each proposal is approved, a Research Data Engineer (RDE) works closely with the research team to establish precisely what data they require and in what format.
The RDE has access to the entire de-identified database and so builds up an expertise as to which projects are feasible and how best to extract the relevant data.
The RDE has access to a library of resusable SQL queries for common tasks, and sets of clinical codes for different phenotypes, built up from previous studies.
Prior to data extraction, the code is checked and signed off by another RDE.

`;
}

function getReusableQueryIntro(includedSqlFiles) {
  const heading = `## Reusable queries
  
`;
  if (!includedSqlFiles || includedSqlFiles.length === 0) {
    return `${heading}This project did not require any reusable queries from the local library [${GITHUB_BASE_URL}/shared/Reusable queries for data extraction](${GITHUB_BASE_URL}/shared/Reusable%20queries%20for%20data%20extraction).`;
  }
  const queryMetadatas = includedSqlFiles.map((sql) => parseQuery(sql.file));
  return `${heading}This project required the following reusable queries:

${queryMetadatas.map(({ name }) => `- ${name}`).join('\n')}

Further details for each query can be found below.

`;
}

function getReusableQueryBody(includedSqlFiles) {
  return includedSqlFiles
    .map((sql) => parseQuery(sql.file))
    .map((x) => readMeTextForMetadata(x, 3))
    .join('\n---\n');
}

function getCodesetIntro(codeSets) {
  const heading = `## Clinical code sets

`;
  if (!codeSets || codeSets.length === 0) {
    return `${heading}This project did not require any clinical code sets.`;
  }
  return `${heading}This project required the following clinical code sets:

${codeSets.map(({ codeSet, version }) => `- ${codeSet} v${version}`).join('\n')}

Further details for each code set can be found below.

`;
}

function getCodeSetTable(project) {
  const link = `${GITHUB_BASE_URL}/projects/${project}/clinical-code-sets.csv`.replace(/ /g, '%20');
  const linkName = `${GITHUB_REPO}/.../${project}/clinical-code-sets.csv`;
  const tableIntro = `
# Clinical code sets

All code sets required for this analysis are available here: [${linkName}](${link}). Individual lists for each concept can also be found by using the links above.`;

  // | Clinical concept | Terminology | Code | Description |
  // | ---------------- | ----------- | ---- | ----------- |`;
  const tableContent = '';
  // RW 08/22 PDFs getting too big so removing the code sets from the pdf
  // as largely redundant given we have it in csv format.
  //
  // codeSets
  //   .map((x) => {
  //     const codeSet = getCodeSet(x.codeSet);
  //     return codeSet[x.version]
  //       .map((item) =>
  //         item.file
  //           .split('\n')
  //           .filter((x) => x.length > 2)
  //           .map((row) => {
  //             const [code, description] = row.split('\t');
  //             return `|${x.codeSet} v${x.version}|${item.terminology}|${code}|${description}|`;
  //           })
  //           .join('\n')
  //       )
  //       .join('\n');
  //   })
  //   .join('\n');
  return `${tableIntro}\n${tableContent}`;
}

function collateCodeSetReadmes(codeSets) {
  return getReadMes(codeSets)
    .map((readMe) => {
      const readMeFileHeadingsLowered = readMe.file.replace(/(?:^|\r|\n|\r\n)#/g, '###');
      return `${readMeFileHeadingsLowered}\nLINK: [${readMe.linkName}](${readMe.link})`;
    })
    .join('\n\n');
}

function generateReusableQueryDocs() {
  // A list of the reusable queries
  const queries = getListOfQueries();

  // Validate the sql templates
  const queryMetadata = [];

  queries.forEach((query) => {
    const properties = parseQuery(query);

    if (!properties.name) {
      console.error(`${query} does not have a short name/description.`);
      console.log(`The file should start with a short name/description like this:

--┌───────────────────────────┐
--│ Short name or description │
--└───────────────────────────┘
      `);
      console.log('Aborting...');
      process.exit(0);
    }
    if (!properties.OBJECTIVE) {
      console.error(`${query} does not have an OBJECTVIVE. This is required.`);
    } else if (!properties.OUTPUT) {
      console.error(`${query} does not have an OUTPUT. This is required.`);
    } else if (!properties.INPUT) {
      console.warn(
        `${query} does not have an INPUT. This is not required but is advised. If the script has no input, please add the following:`
      );
      console.log('-- INPUT: No pre-requisites');
      queryMetadata.push(properties);
    } else {
      queryMetadata.push(properties);
    }
  });

  // Write the README describing the reusable queries
  writeReadme(queryMetadata);
}

function getListOfQueries() {
  return readdirSync(REUSABLE_QUERY_DIRECTORY, { withFileTypes: true }) // read all children of the REUSABLE_QUERY_DIRECTORY
    .filter((item) => item.isFile()) // ..then filter to just files
    .map((dir) => dir.name.replace(/'/g, '')) // ..then return the file name
    .filter((filename) => filename.toLowerCase().match(/\.sql$/)); // ..then filter to sql files
}

function parseQuery(queryFilename) {
  const sqlLines = readFileSync(join(REUSABLE_QUERY_DIRECTORY, queryFilename), 'utf8').split('\n');

  // Check the contents before the SQL begins
  let sqlIndex = 0;
  let trimmedLine = sqlLines[sqlIndex].trim();
  let currentField;
  let fieldsAsString = ['OBJECTIVE'];
  let fieldsAsList = ['ASSUMPTIONS'];
  let fieldsAsIs = ['INPUT', 'OUTPUT'];
  let lastIndent = 0;
  let lastIndentSize = 0;
  const props = { queryFilename };
  while (trimmedLine === '' || trimmedLine.indexOf('--') === 0) {
    if (trimmedLine.indexOf('--│') === 0 || trimmedLine.indexOf('--|') === 0) {
      props.name = trimmedLine.substr(3).replace(/[|│]/g, '').trim();
    } else if (trimmedLine.indexOf('--') === 0) {
      let [, field, content] = trimmedLine.match(/^-- ([A-Z]+):(.*)$/) || [
        false,
        false,
        trimmedLine,
      ];
      if (field) {
        currentField = field;
        if (fieldsAsString.indexOf(field) > -1) {
          props[currentField] = content.trim();
        } else if (fieldsAsList.indexOf(field) > -1) {
          if (content.trim() === '') {
            // assume we're getting a list
            props[currentField] = [];
            lastIndent = -1;
            lastIndentSize = 0;
          } else {
            console.log(
              `In file ${queryFilename} the field ${field} should be a list but it isn't. The format is:`
            );
            console.log('-- ASSUMPTIONS:');
            console.log('-- - Item 1');
            console.log('-- - Item 2');
            props[currentField] = [];
          }
        } else if (fieldsAsIs.indexOf(field) > -1) {
          props[currentField] = content.trim();
        } else {
          console.log(
            `The file ${queryFilename} has a field in the comments (${field}) that is not recognised.`
          );
        }
      } else if (currentField) {
        if (fieldsAsString.indexOf(currentField) > -1) {
          props[currentField] += ` ${content.substr(2).trim()}`;
        } else if (fieldsAsList.indexOf(currentField) > -1) {
          let [isNew, indent, text] = content.substr(2).match(/^(\s*)-\s*(.+)$/) || [
            false,
            0,
            content.substr(2).trim(),
          ];
          if (lastIndent === -1) {
            // first item
            lastIndent = 0;
            lastIndentSize = indent.length;
          }
          if (lastIndentSize < indent.length) {
            // extra nesting
            lastIndent += 1;
          } else if (lastIndentSize > indent.length) {
            // less nesting
            lastIndent = Math.max(0, lastIndent - 1);
          }
          lastIndentSize = indent.length;
          if (isNew) {
            // new item
            props[currentField].push({ text: text.trim(), indent: lastIndent });
          } else {
            props[currentField][props[currentField].length - 1].text += ` ${text.trim()}`;
          }
        } else if (fieldsAsIs.indexOf(currentField) > -1) {
          props[currentField] += `\n${content.substr(2)}`;
        }
      }
    } else {
      currentField = false;
    }
    trimmedLine = sqlLines[++sqlIndex].trim();
  }

  return props;
}

function writeReadme(queryMetadata) {
  const readme = `# Reusable queries

***Do not manually edit this file. To recreate run \`npm start\` and follow the onscreen instructions.***

---

This document describes the SQL query components that have potential to be reused. Each one has a brief objective, an optional
input, and an output. The inputs and outputs are in the form of temporary SQL tables.

---

${queryMetadata
  .sort((a, b) => {
    if (a.name > b.name) return 1;
    return a.name === b.name ? 0 : -1;
  })
  .map((x) => readMeTextForMetadata(x, 2))
  .join('\n---\n')}`;

  writeFileSync(join(__dirname, '..', 'docs', 'Reusable-SQL-query-reference.md'), readme);
}

function readMeTextForMetadata(metadata, headingLevel) {
  return `${'#'.repeat(headingLevel)} ${metadata.name}
${metadata.OBJECTIVE}
${
  metadata.ASSUMPTIONS
    ? `
_Assumptions_

${metadata.ASSUMPTIONS.map((x) => `${'\t'.repeat(x.indent)}- ${x.text}`).join('\n')}
`
    : ''
}
_Input_
\`\`\`
${metadata.INPUT}
\`\`\`

_Output_
\`\`\`
${metadata.OUTPUT}
\`\`\`
_File_: \`${metadata.queryFilename}\`

_Link_: [${GITHUB_REPO}/.../${
    metadata.queryFilename
  }](${GITHUB_BASE_URL}/shared/Reusable%20queries%20for%20data%20extraction/${
    metadata.queryFilename
  })
`;
}
