const { readFileSync, readdirSync, writeFileSync } = require('fs');
const { join } = require('path');

const PROJECT_DIRECTORY = join(__dirname, '..', 'projects');
const REUSABLE_DIRECTORY = join(__dirname, '..', 'shared', 'Reusable queries for data extraction');

// Find projects
const projects = findProjects();

projects.forEach((project) => {
  // Find templates
  const templates = findTemplates(project);

  // Warning if no templates found
  warnIfNoTemplatesFound(project, templates);

  // Generate sql to execute on server
  generateSql(project, templates);
})

//
// FUNCTIONS
//

function findProjects() {
  return readdirSync(PROJECT_DIRECTORY, { withFileTypes: true }) // read all children of this directory
    .filter(item => item.isDirectory()) // ..then filter to just directories under PROJECT_DIRECTORY
    .map(dir => dir.name) // ..then return the directory name
    .filter(filename => filename.toLowerCase().match(/^[0-9]+ - .+$/)); // Must be of the form "NNN - [Name]"
}

function findTemplates(project) {
  return readdirSync(join(PROJECT_DIRECTORY, project), { withFileTypes: true }) // read all children of this directory
    .filter(item => item.isFile()) // ..then filter to just files under the project directory
    .map(file => file.name) // ..then return the file name
    .filter(filename => filename.toLowerCase().match(/^.+-file-[0-9]+.sql$/));// Filename must end "-file-NN.sql"
}

function warnIfNoTemplatesFound(project, templates) {
  if(templates.length === 0) {
    console.error(`There are no template files in ${project}.`);
    console.log('There should be at least one file with a name like: [group]-file-[n].sql.');
    console.log('E.g. "secondary-utilisation-file-1.sql');
  }
}

function generateSql(project, templates) {
  const OUTPUT_DIRECTORY = join(PROJECT_DIRECTORY, project, 'extraction-sql');
  templates.forEach((templateName) => {
    const filename = join(PROJECT_DIRECTORY, project, templateName);
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