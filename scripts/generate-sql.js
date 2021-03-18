const { readFileSync, readdirSync, writeFileSync } = require('fs');
const { join } = require('path');

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
    process.exit(1);
  }
}

function generateSql(project, templates) {
  const OUTPUT_DIRECTORY = join(project, EXTRACTION_SQL_DIR);
  templates.forEach((templateName) => {
    const filename = join(project, TEMPLATE_SQL_DIR, templateName);
    const sql = processFile(filename);
    const outputName = templateName.replace('.template', '');

    writeFileSync(join(OUTPUT_DIRECTORY, outputName), sql);
  });
}

function processFile(filename) {
  const sqlLines = readFileSync(filename, 'utf8').split('\n');
  const generatedSql = sqlLines
    .map((line) => {
      if (line.trim().match(/^--> EXECUTE.+\.sql/)) {
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

module.exports = { stitch };
