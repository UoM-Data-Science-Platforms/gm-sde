const { readFileSync, readdirSync, writeFileSync } = require('fs');
const { join, basename } = require('path');
const { createCodeSetSQL, checkCodeSetExists } = require('./code-sets');

const EXTRACTION_SQL_DIR = 'extraction-sql';
const TEMPLATE_SQL_DIR = 'template-sql';
const REUSABLE_DIRECTORY = join(__dirname, '..', 'shared', 'Reusable queries for data extraction');

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

    writeFileSync(join(OUTPUT_DIRECTORY, outputName), codesetSql + sql);
  });
}

function processParams(line, params) {
  const parameters = {};
  params.forEach((param) => {
    if (!param.match(/^[^ :]+:[^ :]+$/)) {
      console.log('The following line has invalid parameters:');
      console.log(line);
      console.log('They should appear as follows:');
      console.log('--> EXECUTE query.sql param-1-name:param1value param-2-name:param2value');
      process.exit();
    }
    const [name, value] = param.split(':');
    parameters[name] = value;
  });
  return parameters;
}

function processFile(filename, requiredCodeSets = [], parameters) {
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
        requiredCodeSets = requiredCodeSets.concat(foundCodeSets);
        return `-- >>> Following codesets injected: ${foundCodeSets.join('/')}`;
      } else if (line.trim().match(/^--> EXECUTE.+\.sql/)) {
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
        if (params && params.length > 0) {
          const processedParameters = processParams(line, params);
          const { sql: sqlToInsert, codesets } = processFile(
            join(REUSABLE_DIRECTORY, sqlFileToInsert),
            requiredCodeSets,
            processedParameters
          );
          requiredCodeSets = codesets;
          return sqlToInsert;
        }
        const { sql: sqlToInsert, codesets } = processFile(
          join(REUSABLE_DIRECTORY, sqlFileToInsert),
          requiredCodeSets
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
//stitch(join(__dirname, '..', 'projects', '020 - Heald'));
module.exports = { stitch };
