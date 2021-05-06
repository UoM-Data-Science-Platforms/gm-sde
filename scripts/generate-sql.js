const { readFileSync, readdirSync, writeFileSync } = require('fs');
const { join, basename } = require('path');
const { createCodeSetSQL, checkCodeSetExists } = require('./code-sets');

const EXTRACTION_SQL_DIR = 'extraction-sql';
const TEMPLATE_SQL_DIR = 'template-sql';
const REUSABLE_DIRECTORY = join(__dirname, '..', 'shared', 'Reusable queries for data extraction');
const CODESET_MARKER = '[[[{{{(((CODESET_SQL)))}}}]]]';

const stitch = (projectDirectory) => {
  console.log(`Finding templates in ${join(projectDirectory, TEMPLATE_SQL_DIR)}...`);
  const templates = findTemplates(projectDirectory);

  // Warning if no templates found
  warnIfNoTemplatesFound(projectDirectory, templates);

  console.log(`
The following template files were found:

${templates.join('\n')}

Stitching them together...
`);

  // Generate sql to execute on server
  generateSql(projectDirectory, templates);

  console.log(`
Unless there were errors, you should find your extraction SQL files in ${join(
    projectDirectory,
    EXTRACTION_SQL_DIR
  )}.
`);
};

//
// FUNCTIONS
//

function findTemplates(project) {
  return readdirSync(join(project, TEMPLATE_SQL_DIR), { withFileTypes: true }) // read all children of this directory
    .filter((item) => item.isFile()) // ..then filter to just files under the project directory
    .map((file) => file.name) // ..then return the file name
    .filter((filename) => filename.toLowerCase().match(/\.template\.sql$/)); // Filename must end ".template.sql"
}

function warnIfNoTemplatesFound(project, templates) {
  if (templates.length === 0) {
    console.error(`There are no template files in ${project}.`);
    console.log('There should be at least one file with a name ending: .template.sql.');
    console.log('E.g. "secondary-utilisation-file.template.sql');
    process.exit(0);
  }
}

function generateSql(project, templates) {
  const OUTPUT_DIRECTORY = join(project, EXTRACTION_SQL_DIR);
  templates.forEach((templateName) => {
    const filename = join(project, TEMPLATE_SQL_DIR, templateName);
    const { sql, codesets } = processFile(filename);
    let codesetSql = codesets.length > 0 ? createCodeSetSQL(codesets) : '';
    const outputName = templateName.replace('.template', '');

    const finalSQL = sql.replace(CODESET_MARKER, codesetSql);

    writeFileSync(join(OUTPUT_DIRECTORY, outputName), finalSQL);
  });
}

function processParams(line, params) {
  const parameters = {};
  while (params.match(/^[^ :]+:/)) {
    const [, name, rest] = params.match(/^([^ :]+):(.*)$/);
    const singleQuoteMatch = rest.match(/^'([^']+)'(.*)$/);
    const doubleQuoteMatch = rest.match(/^"([^"]+)"(.*)$/);
    if (singleQuoteMatch) {
      const [, value, x] = singleQuoteMatch;
      parameters[name] = value;
      params = x.trim();
    } else if (doubleQuoteMatch) {
      const [, value, x] = doubleQuoteMatch;
      parameters[name] = value;
      params = x.trim();
    } else {
      const [value, ...y] = rest.split(' ');
      parameters[name] = value;
      params = y.join(' ').trim();
    }
  }
  if (params.trim().length > 0) {
    console.log('The following line has invalid parameters:');
    console.log(line);
    console.log('They should appear as follows:');
    console.log('--> EXECUTE query.sql param-1-name:param1value param-2-name:param2value');
    console.log('NB string parameters with spaces should be enclosed in "s. E.g.');
    console.log('--> EXECUTE query.sql param-1-name:"param1 value" param-2-name:"param2 value"');
    process.exit();
  }
  return parameters;
}

function processFile(filename, requiredCodeSets = [], alreadyProcessed = {}, parameters) {
  alreadyProcessed[filename] = true;
  const sqlLines = readFileSync(filename, 'utf8').split('\n');
  const generatedSql = sqlLines
    .map((line) => {
      if (line.trim().match(/^--> CODESETS? /)) {
        const codeSets = line
          .replace(/^--> CODESETS? +/, '')
          .trim()
          .split(' ');
        const foundCodeSets = codeSets.filter((codeset) => checkCodeSetExists(codeset));
        const notFoundCodeSets = codeSets.filter((codeset) => !checkCodeSetExists(codeset));

        if (notFoundCodeSets.length > 0) {
          console.log('The following line has invalid codesets:');
          console.log(line);
          console.log(
            `The codeset(s): ${notFoundCodeSets.join(
              '/'
            )} do not appear in the clinical-code-sets directory`
          );
          process.exit();
        }
        const textToReturn =
          requiredCodeSets.length === 0
            ? `-- >>> Codesets required... Inserting the code set code
${CODESET_MARKER}
-- >>> Following codesets injected: ${foundCodeSets.join('/')}`
            : `-- >>> Following codesets injected: ${foundCodeSets.join('/')}`;
        requiredCodeSets = requiredCodeSets.concat(foundCodeSets);
        return `${textToReturn}`;
      } else if (line.trim().match(/^--> EXECUTE/)) {
        const [sqlFileToInsert, ...params] = line
          .replace(/^--> EXECUTE +/, '')
          .trim()
          .split(' ');
        if (sqlFileToInsert === 'load-code-sets.sql') {
          // special case for load-code-sets
          console.log('Your code calls:');
          console.log('--> EXECUTE load-code-sets.sql');
          console.log(
            'This is the old way of doing things. Please remove this line and replace it with one or more lines as follows:'
          );
          console.log('--> CODESET [space separated list of code sets required]');
          console.log('');
          console.log('E.g. --> CODESET diabetes-type-i hba1c smoking-status');
          process.exit();
        }
        const fileToInject = join(REUSABLE_DIRECTORY, sqlFileToInsert);
        if (alreadyProcessed[fileToInject]) {
          return `-- >>> Ignoring following query as already injected: ${sqlFileToInsert}`;
        }
        if (params && params.length > 0) {
          const processedParameters = processParams(line, params.join(' '));
          const { sql: sqlToInsert, codesets } = processFile(
            fileToInject,
            requiredCodeSets,
            alreadyProcessed,
            processedParameters
          );
          requiredCodeSets = codesets;
          return sqlToInsert;
        }
        const { sql: sqlToInsert, codesets } = processFile(
          fileToInject,
          requiredCodeSets,
          alreadyProcessed
        );
        requiredCodeSets = codesets;
        return sqlToInsert;
      } else {
        const possibleParamRegex = new RegExp('{param:([^}]+)}');
        let possibleParamMatch = line.match(possibleParamRegex);
        while (possibleParamMatch) {
          const paramName = possibleParamMatch[1];
          if (!parameters[paramName] && parameters[paramName] !== 0) {
            console.log(
              `The file ${basename(filename)} requires a value for the parameter: ${paramName}`
            );
            console.log('However this is not provided. You should call it like this:');
            console.log(`--> EXECUTE ${basename(filename)} ${paramName}:value`);
            process.exit();
          }
          const reg = new RegExp(`{param:${paramName}}`, 'g');
          line = line.replace(reg, parameters[paramName]);
          possibleParamMatch = line.match(possibleParamRegex);
        }
        return line;
      }
    })
    .join('\n');
  return { sql: generatedSql, codesets: requiredCodeSets };
}
// stitch(join(__dirname, '..', 'projects', '017 - Humphreys'));
module.exports = { stitch };
