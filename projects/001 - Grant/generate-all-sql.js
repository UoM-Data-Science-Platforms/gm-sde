const { readFileSync, readdirSync, writeFileSync } = require('fs');
const { join } = require('path');

const OUTPUT_DIRECTORY = join(__dirname, 'extraction-sql');
const TEMPLATE_DIRECTORY = join(__dirname);
const REUSABLE_DIRECTORY = join(__dirname, 'reusable');

// Find templates
const templates = findTemplates();

// Warning if no templates found
warnIfNoTemplatesFound();

// Generate sql to execute on server
generateSql();


//
// FUNCTIONS
//

function findTemplates() {
  return readdirSync(TEMPLATE_DIRECTORY, { withFileTypes: true }) // read all children of this directory
    .filter(item => item.isFile()) // ..then filter to just directories under LTC_DIRECTORY
    .map(file => file.name) // ..then return the file name
    .filter(filename => filename.toLowerCase().match(/^.+-file-[0-9]+.sql$/));
}

function warnIfNoTemplatesFound() {
  if(templates.length === 0) {
    console.error(`There are no template files in ${TEMPLATE_DIRECTORY}.`);
    console.log('There should be at least one file with a name like: [group]-file-[n].sql.');
    console.log('E.g. "secondary-utilisation-file-1.sql');
  }
}

function generateSql() {
  templates.forEach((templateName) => {
    const filename = join(__dirname, templateName);
    const sql = processFile(filename)

    writeFileSync(join(OUTPUT_DIRECTORY, templateName), sql);
  });
}

function processFile(filename) {
  const sqlLines = readFileSync(filename, 'utf8').split('\n');
  const generatedSql = sqlLines
    .map((line) => {
      if(line.trim().match(/^--> EXECUTE.+\.sql/)) {
        const sqlFileToInsert = line.trim().split(' ').slice(-1)[0];
        const sqlToInsert = processFile(join(REUSABLE_DIRECTORY, sqlFileToInsert));
        return sqlToInsert;
      } else {
        return line;
      }
    })
    .join('\n');
  return generatedSql;
}