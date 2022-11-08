const { readFileSync, readdirSync, writeFileSync, existsSync } = require('fs');
const { join, basename } = require('path');
const { createCodeSetSQL, createNationalCodeSetSQL, theCodeSetExists } = require('./code-sets');
const { generateProjectSupplementaryReadme, generateCodeSetCsv } = require('./docs');
const md = require('markdown-it')();

const EXTRACTION_SQL_DIR = 'extraction-sql';
const TEMPLATE_SQL_DIR = 'template-sql';
const README_NAME = 'README';
const SHARED_DIRECTORY = join(__dirname, '..', 'shared');
const REUSABLE_DIRECTORY = join(SHARED_DIRECTORY, 'Reusable queries for data extraction');
const CODESET_MARKER = '[[[{{{(((CODESET_SQL)))}}}]]]';

const includedSqlFiles = [];
const includedSqlFilesSoFar = {};
let isProjectDirectory = false;

const stitch = async (projectDirectory) => {
  console.log('Moving analyst-guidance file...');
  const readmeFirstFile = readFileSync(
    join(SHARED_DIRECTORY, 'documents', 'analyst-guidance.md'),
    'utf8'
  );
  writeFileSync(join(projectDirectory, 'scripts', 'analyst-guidance.md'), readmeFirstFile);

  console.log(`Finding templates in ${join(projectDirectory, TEMPLATE_SQL_DIR)}...`);
  const templates = findTemplates(projectDirectory);

  const projectName = basename(projectDirectory);
  isProjectDirectory = projectName.match(/^[0-9]+ *-/);
  if (isProjectDirectory) {
    console.log(
      `
${projectName} is of the form "XXX - Name" so I'm assuming it's a project directory.`
    );
  } else {
    console.log(
      `
${projectName} is NOT of the form "XXX - Name" so I'm assuming it's a non-project directory e.g. the _example or the Reports directories.`
    );
  }

  // Warning if no templates found
  warnIfNoTemplatesFound(projectDirectory, templates);

  console.log(`
The following template files were found:

${templates.join('\n')}

Stitching them together...
`);

  // Generate sql to execute on server
  await generateSql(projectDirectory, projectName, templates);

  if (isProjectDirectory) {
    const readmeMarkdown = join(projectDirectory, `${README_NAME}.md`);
    const readmeHTML = join(projectDirectory, `${README_NAME}.html`);
    const style = `<style>${readFileSync(join(__dirname, 'style.css'), 'utf8')}</style>`;
    const html = style + md.render(readFileSync(readmeMarkdown, 'utf8'));
    writeFileSync(readmeHTML, html);
  }

  console.log(`
Unless there were errors, you should find your extraction SQL files in ${join(
    projectDirectory,
    EXTRACTION_SQL_DIR
  )}.
`);
};

const nationalStitch = async (projectDirectory) => {
  console.log(`Finding templates in ${join(projectDirectory, TEMPLATE_SQL_DIR)}...`);
  const templates = findTemplates(projectDirectory);

  const projectName = basename(projectDirectory);

  // Warning if no templates found
  warnIfNoTemplatesFound(true, templates);

  console.log(`
The following template files were found:

${templates.join('\n')}

Stitching them together...
`);

  // Generate sql to execute on server
  await generateNationalSql(projectDirectory, projectName, templates);

  const readmeMarkdown = join(projectDirectory, `${README_NAME}.md`);
  const readmeHTML = join(projectDirectory, `${README_NAME}.html`);
  const style = `<style>${readFileSync(join(__dirname, 'style.css'), 'utf8')}</style>`;
  const html = style + md.render(readFileSync(readmeMarkdown, 'utf8'));
  writeFileSync(readmeHTML, html);

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
    .filter((filename) => filename.toLowerCase().match(/\.template\.(sql|py)$/)); // Filename must end ".template.sql" or "template.py"
}

function warnIfNoTemplatesFound(project, templates) {
  if (templates.length === 0) {
    console.error(`There are no template files in ${project}.`);
    console.log('There should be at least one file with a name ending: .template.sql.');
    console.log('E.g. "secondary-utilisation-file.template.sql');
    process.exit(0);
  }
}

async function generateSql(project, projectName, templates) {
  const OUTPUT_DIRECTORY = join(project, EXTRACTION_SQL_DIR);
  const allCodeSets = {};
  for (const templateName of templates) {
    const filename = join(project, TEMPLATE_SQL_DIR, templateName);
    const { sql, codeSets } = processFile(filename);

    codeSets.forEach(({ codeSet, version }) => {
      if (!allCodeSets[codeSet]) {
        allCodeSets[codeSet] = new Set([version]);
      } else {
        allCodeSets[codeSet].add(version);
      }
    });

    let codeSetSql = await (codeSets.length > 0 ? createCodeSetSQL(codeSets) : '');
    const outputName = templateName.replace('.template', '');

    const finalSQL = sql.replace(CODESET_MARKER, codeSetSql);

    writeFileSync(join(OUTPUT_DIRECTORY, outputName), finalSQL);
  }

  if (isProjectDirectory) {
    const flattenedCodeSets = Object.keys(allCodeSets)
      .map((codeSet) => Array.from(allCodeSets[codeSet]).map((version) => ({ codeSet, version })))
      .flat();

    const disclaimer = '_This file is autogenerated. Please do not edit._\n\n';
    // Get the "about.md" file
    const aboutFile = join(project, 'about.md');
    const about = existsSync(aboutFile) ? readFileSync(aboutFile, 'utf8').trim() + '\n\n' : '';

    const readmeContent = generateProjectSupplementaryReadme({
      codeSets: flattenedCodeSets,
      includedSqlFiles: includedSqlFiles.reverse(),
      projectName,
    });
    writeFileSync(join(project, `${README_NAME}.md`), disclaimer + about + readmeContent);

    if (flattenedCodeSets && flattenedCodeSets.length > 0) {
      const codeSetCsvContent = generateCodeSetCsv(flattenedCodeSets);
      try {
        writeFileSync(join(project, `clinical-code-sets.csv`), codeSetCsvContent);
      } catch (error) {
        console.error('Failed to write the code set csv. Perhaps you have it open in Excel?');
        process.exit(0);
      }
    }
  }
}

async function generateNationalSql(project, projectName, templates) {
  const projectLabel = project.split(' - ')[1];
  const OUTPUT_DIRECTORY = join(project, EXTRACTION_SQL_DIR);
  const LOCAL_CODE_SET_DIR = join(project, 'code-sets');
  const codeSetLookup = {};
  readdirSync(LOCAL_CODE_SET_DIR).forEach((file) => {
    const codeSetName = file.split('.')[0];
    codeSetLookup[codeSetName] = {};
    readFileSync(join(LOCAL_CODE_SET_DIR, file), 'utf8')
      .split('\n')
      .forEach((x) => {
        const bits = x.trim().split('\t');
        if (bits.length > 1) {
          codeSetLookup[codeSetName][bits[0]] = bits[1];
        }
      });
  });
  const allCodeSets = {};
  for (const templateName of templates) {
    const filename = join(project, TEMPLATE_SQL_DIR, templateName);
    const { sql, codeSets } = processFile(filename);

    codeSets.forEach(({ codeSet }) => {
      if (!allCodeSets[codeSet]) {
        allCodeSets[codeSet] = true;
      }
    });

    let codeSetSql = await (codeSets.length > 0
      ? createNationalCodeSetSQL(projectLabel, codeSetLookup)
      : '');
    const outputName = templateName.replace('.template', '');

    let interimSql = sql;
    Object.keys(codeSetLookup).forEach((codeSet) => {
      const regex = new RegExp(`\\/\\*--${codeSet}--\\*\\/`, `g`);
      const codes = Object.keys(codeSetLookup[codeSet]).join("','");
      interimSql = interimSql.replace(regex, `--${codeSet} codeset inserted\n'${codes}'`);
    });

    const formattedDate = new Date().toISOString().split('T')[0];
    interimSql = interimSql.replace(/\/\*__date__\*\//, formattedDate);

    const finalSQL = interimSql.replace(CODESET_MARKER, codeSetSql);

    writeFileSync(join(OUTPUT_DIRECTORY, outputName), finalSQL);
  }

  const flattenedCodeSets = Object.keys(allCodeSets)
    .map((codeSet) => Array.from(allCodeSets[codeSet]).map((version) => ({ codeSet, version })))
    .flat();

  const disclaimer = '_This file is autogenerated. Please do not edit._\n\n';
  // Get the "about.md" file
  const aboutFile = join(project, 'about.md');
  const about = existsSync(aboutFile) ? readFileSync(aboutFile, 'utf8').trim() + '\n\n' : '';

  const readmeContent = generateProjectSupplementaryReadme({
    codeSets: flattenedCodeSets,
    includedSqlFiles: includedSqlFiles.reverse(),
    projectName,
  });
  writeFileSync(join(project, `${README_NAME}.md`), disclaimer + about + readmeContent);

  if (flattenedCodeSets && flattenedCodeSets.length > 0) {
    const codeSetCsvContent = generateCodeSetCsv(flattenedCodeSets);
    try {
      writeFileSync(join(project, `clinical-code-sets.csv`), codeSetCsvContent);
    } catch (error) {
      console.error('Failed to write the code set csv. Perhaps you have it open in Excel?');
      process.exit(0);
    }
  }
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

function processFile(filename, requiredCodeSets = [], alreadyProcessed = {}, parameters = []) {
  // Allow file to be processed twice if the parameters are different
  alreadyProcessed[filename + JSON.stringify(parameters)] = true;
  const sqlLines = readFileSync(filename, 'utf8').split('\n');
  const generatedSql = sqlLines
    .map((line) => {
      // First let's replace any parameters
      const possibleParamRegex = new RegExp('{param:([^}]+)}');
      if (line.match(possibleParamRegex)) {
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
      }

      // Now process the line itself
      if (line.trim().match(/^--> CODESETS? /)) {
        const codeSets = line
          .replace(/^--> CODESETS? +/, '')
          .trim()
          .split(' ')
          .map((x) => {
            const [codeSet, version] = x.split(':');
            if (!version) {
              console.log('The following line has invalid code sets:');
              console.log(line);
              console.log(
                `The code set: ${codeSet} does not have a version number. It should be like this:`
              );
              console.log('--> CODESET [space separated list of code sets and versions required]');
              console.log('');
              console.log('E.g. --> CODESET diabetes-type-i:1 hba1c:1 smoking-status:2');
              process.exit();
            }
            return { codeSet, version };
          });
        const foundCodeSets = codeSets.filter(({ codeSet, version }) =>
          theCodeSetExists({ codeSet, version })
        );
        const notFoundCodeSets = codeSets.filter(
          ({ codeSet, version }) => !theCodeSetExists({ codeSet, version })
        );

        if (
          notFoundCodeSets.length === 1 &&
          notFoundCodeSets[0].codeSet.match(/^insert-concepts?-here$/)
        ) {
          console.log('Ignoring "insert-concept-here" code set...');
        } else if (notFoundCodeSets.length > 0) {
          console.log('The following line has invalid code sets:');
          console.log(line);
          console.log(
            `The code set(s): ${notFoundCodeSets
              .map((x) => `${x.codeSet} v${x.version}`)
              .join('/')} do not appear in the clinical-code-sets directory`
          );
          process.exit();
        }
        const textToReturn =
          requiredCodeSets.length === 0
            ? `-- >>> Codesets required... Inserting the code set code
${CODESET_MARKER}
-- >>> Following code sets injected: ${foundCodeSets
                .map((x) => `${x.codeSet} v${x.version}`)
                .join('/')}`
            : `-- >>> Following code sets injected: ${foundCodeSets
                .map((x) => `${x.codeSet} v${x.version}`)
                .join('/')}`;
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
          console.log('--> CODESET [space separated list of code sets and versions required]');
          console.log('');
          console.log('E.g. --> CODESET diabetes-type-i:1 hba1c:1 smoking-status:2');
          process.exit();
        }
        const fileToInject = join(REUSABLE_DIRECTORY, sqlFileToInsert);
        const processedParameters =
          params && params.length > 0 ? processParams(line, params.join(' ')) : [];
        if (alreadyProcessed[fileToInject + JSON.stringify(processedParameters)]) {
          return `-- >>> Ignoring following query as already injected: ${sqlFileToInsert}`;
        }
        if (params && params.length > 0) {
          const { sql: sqlToInsert, codeSets } = processFile(
            fileToInject,
            requiredCodeSets,
            alreadyProcessed,
            processedParameters
          );
          requiredCodeSets = codeSets;
          if (!includedSqlFilesSoFar[sqlFileToInsert]) {
            includedSqlFilesSoFar[sqlFileToInsert] = true;
            includedSqlFiles.push({ file: sqlFileToInsert, params: processedParameters });
          }
          return sqlToInsert;
        }
        const { sql: sqlToInsert, codeSets } = processFile(
          fileToInject,
          requiredCodeSets,
          alreadyProcessed
        );
        requiredCodeSets = codeSets;
        if (!includedSqlFilesSoFar[sqlFileToInsert]) {
          includedSqlFilesSoFar[sqlFileToInsert] = true;
          includedSqlFiles.push({ file: sqlFileToInsert, params: [] });
        }
        return sqlToInsert;
      } else {
        return line;
      }
    })
    .join('\n');
  return { sql: generatedSql, codeSets: requiredCodeSets };
}
//stitch(join(__dirname, '..', 'projects', '017 - Humphreys'));
//stitch(join(__dirname, '..', 'projects', '001 - Grant'));
//nationalStitch(join(__dirname, '..', 'projects', 'NATIONAL - CCU040 - Diabetes'));
module.exports = { stitch, nationalStitch };
