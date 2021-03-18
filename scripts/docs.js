const { readFileSync, readdirSync, writeFileSync } = require('fs');
const { join } = require('path');

const REUSABLE_QUERY_DIRECTORY = join(
  __dirname,
  '..',
  'shared',
  'Reusable queries for data extraction'
);

module.exports = { generateReusableQueryDocs };

function generateReusableQueryDocs() {
  // A list of the reusable queries
  const queries = getListOfQueries();

  // Validate the sql templates
  const objectives = [];

  queries.forEach((query) => {
    const properties = parseQuery(query);

    if (!properties.NAME) {
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
      objectives.push({
        name: properties.NAME,
        query,
        text: properties.OBJECTIVE,
        output: properties.OUTPUT,
      });
    } else {
      objectives.push({
        name: properties.NAME,
        query,
        text: properties.OBJECTIVE,
        output: properties.OUTPUT,
        input: properties.INPUT,
      });
    }
  });

  // Write the README describing the reusable queries
  writeReadme(objectives);
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
  const props = {};
  while (trimmedLine === '' || trimmedLine.indexOf('--') === 0) {
    if (trimmedLine.indexOf('--│') === 0 || trimmedLine.indexOf('--|') === 0) {
      props.NAME = trimmedLine.substr(3).replace(/[|│]/g, '').trim();
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
          let [isNew, text] = content
            .substr(2)
            .trim()
            .match(/^-\s*(.+)$/) || [false, content.substr(2).trim()];
          if (isNew) {
            // new item
            props[currentField].push(text.trim());
          } else {
            props[currentField][props[currentField].length - 1] += ` ${text.trim()}`;
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

function writeReadme(objectives) {
  const readme = `# Reusable queries

***Do not manually edit this file. To recreate run \`npm start\` and follow the onscreen instructions.***

---

This document describes the SQL query components that have potential to be reused. Each one has a brief objective, an optional
input, and an output. The inputs and outputs are in the form of temporary SQL tables.

---

${objectives
  .sort((a, b) => {
    if (a.name > b.name) return 1;
    return a.name === b.name ? 0 : -1;
  })
  .map(
    (o) => `## ${o.name}
${o.text}

_Input_
\`\`\`
${o.input}
\`\`\`

_Output_
\`\`\`
${o.output}
\`\`\`
_File_: \`${o.query}\`
`
  )
  .join('\n---\n')}`;

  writeFileSync(join(__dirname, '..', 'docs', 'Reusable-SQL-query-reference.md'), readme);
}
