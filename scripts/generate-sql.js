const { readFileSync, readdirSync, writeFileSync, existsSync, mkdirSync } = require('fs');
const { join, basename } = require('path');
const {
  createCodeSetSQL: createCodeSetSQLSnowflake,
  createNationalCodeSetSQL,
  theCodeSetExists,
} = require('./code-sets');
const { createCodeSetSQL: createCodeSetSQLGMCR } = require('./code-sets-gmcr');
const { generateProjectSupplementaryReadme, generateCodeSetCsv } = require('./docs');
const md = require('markdown-it')();

let createCodeSetSQL;
const EXTRACTION_SQL_DIR = 'extraction-sql';
const TEMPLATE_SQL_DIR = 'template-sql';
const README_NAME = 'README';
const SHARED_DIRECTORY = join(__dirname, '..', 'shared');
const SCRIPTS_DIRECTORY = join(__dirname, '..', 'scripts');
const REUSABLE_DIRECTORY = join(SHARED_DIRECTORY, 'Reusable queries for data extraction');
const CODESET_MARKER = '[[[{{{(((CODESET_SQL)))}}}]]]';

const includedSqlFiles = [];
const includedSqlFilesSoFar = {};
let isProjectDirectory = false;

const stitch = async (projectDirectory, isSnowflake) => {
  createCodeSetSQL = isSnowflake ? createCodeSetSQLSnowflake : createCodeSetSQLGMCR;
  console.log('Moving analyst-guidance file...');
  const readmeFirstFile = readFileSync(
    join(SHARED_DIRECTORY, 'documents', 'analyst-guidance.md'),
    'utf8'
  );
  const localScriptsDir = join(projectDirectory, 'scripts');
  if (!existsSync(localScriptsDir)) {
    mkdirSync(localScriptsDir);
  }
  writeFileSync(join(localScriptsDir, 'analyst-guidance.md'), readmeFirstFile);

  console.log('Moving main js file...');
  const mainJsFile = readFileSync(join(SCRIPTS_DIRECTORY, 'main-data-extract.js'), 'utf8');
  writeFileSync(join(projectDirectory, 'scripts', 'main.js'), mainJsFile);

  console.log('Moving package.json file...');
  const mainJSONFile = readFileSync(
    join(SCRIPTS_DIRECTORY, 'main-data-extract-node-config.json'),
    'utf8'
  );
  writeFileSync(join(projectDirectory, 'scripts', 'package.json'), mainJSONFile);

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
    isProjectDirectory = projectName.match(/^SDE Lighthouse [0-9]+ *-/);
    if (isProjectDirectory) {
      console.log(
        `
${projectName} is of the form "SDE Lighthouse XX - Name" so I'm assuming it's a project directory.`
      );
    } else {
      isProjectDirectory = projectName.match(/^Industry - [0-9]+ *-/);
      if (isProjectDirectory) {
        console.log(
          `
${projectName} is of the form "Industry - XXX - Name" so I'm assuming it's a project directory.`
        );
      } else {
        console.log(
          `
${projectName} is NOT of the form "XXX - Name" so I'm assuming it's a non-project directory e.g. the _example or the Reports directories.`
        );
      }
    }
  }

  // Warning if no templates found
  warnIfNoTemplatesFound(projectDirectory, templates);

  const configFile = join(projectDirectory, 'config.json');
  let isValidConfig = false;
  let config;
  if (existsSync(configFile)) {
    try {
      config = JSON.parse(readFileSync(configFile, 'utf8'));
      isValidConfig =
        !!config.PROJECT_SPECIFIC_SCHEMA_PRIVATE_TO_RDES &&
        !!config.PROJECT_SPECIFIC_SCHEMA_FOR_DATA;
    } catch (e) {
      isValidConfig = false;
    }
  }
  if (!isValidConfig) {
    console.log(`
!!!! ERRROR !!!!

Snowflake projects now require a config.json file to be located directly under the project directory e.g.

${projectName}/config.json

The contents should be:

{
  "PROJECT_SPECIFIC_SCHEMA_PRIVATE_TO_RDES": "<INSERT DB NAME>.<INSERT SCHEMA NAME>",
  "PROJECT_SPECIFIC_SCHEMA_FOR_DATA": "<INSERT DB NAME>.<INSERT SCHEMA NAME>"
}
`);
    process.exit();
  }

  console.log(`
The following template files were found:

${templates.join('\n')}

Stitching them together...
`);

  // Generate sql to execute on server
  await generateSql(projectDirectory, projectName, templates, isSnowflake, config);

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

function processNextOutputTable(sql, templateName, config, projectNameChunked) {
  //{{create-output-table::"1_Patients"::"GmPseudo"}}
  //{{create-output-table-no-gmpseudo-ids::"1_Patients"}
  const outputTableRegex = /\{\{create-output-table::([^}:]*)\}\}/;
  const outputTableNoIdsRegex = /\{\{create-output-table-no-gmpseudo-ids::([^}:]*)\}\}/;
  const outputTableMatchedCohortRegex = /\{\{create-output-table-matched-cohort::([^}:]*)\}\}/;

  let isMatch = false;

  const outputTableMatch = outputTableRegex.exec(sql);
  const outputTableNoIdsMatch = outputTableNoIdsRegex.exec(sql);
  const outputTableMatchedCohortMatch = outputTableMatchedCohortRegex.exec(sql);
  if (outputTableMatch) {
    isMatch = true;
    let needSemiColon = false;

    const indexOfOutputTable = sql.indexOf('{{create-output-table');
    let indexOfFinalSemiColon = sql.indexOf(';', indexOfOutputTable);
    if (indexOfFinalSemiColon < 0) {
      needSemiColon = true;
      indexOfFinalSemiColon = sql.length - 1;
    }

    const [, tableName] = outputTableMatch;
    const tableNameNoQuotes = tableName.match(/^"?([^"]+)"?$/)[1];

    const replacedSql =
      sql.substring(indexOfOutputTable, indexOfFinalSemiColon + 1).replace(
        outputTableRegex,
        `
-- ... processing ${outputTableMatch[0].replace(/\{/g, '[').replace(/\}/g, ']')} ... 
-- ... Need to create an output table called ${tableName} and replace 
-- ... the GmPseudo column with a study-specific random patient id.

-- First we create a table in an area only visible to the RDEs which contains
-- the GmPseudos. THESE CANNOT BE RELEASED TO END USERS.
DROP TABLE IF EXISTS ${
          config.PROJECT_SPECIFIC_SCHEMA_PRIVATE_TO_RDES
        }."${tableNameNoQuotes}_WITH_IDENTIFIER";
CREATE TABLE ${
          config.PROJECT_SPECIFIC_SCHEMA_PRIVATE_TO_RDES
        }."${tableNameNoQuotes}_WITH_IDENTIFIER" AS`
      ) + (needSemiColon ? ';' : '');

    const finalSql = `

-- Then we check to see if there are any new GmPseudo ids. We do this by making a temp table 
-- of all "new" GmPseudo ids. I.e. any GmPseudo ids that we've already got a unique id for
-- for this study are excluded
DROP TABLE IF EXISTS "AllPseudos_${projectNameChunked.join('_')}";
CREATE TEMPORARY TABLE "AllPseudos_${projectNameChunked.join('_')}" AS
SELECT DISTINCT "GmPseudo" FROM ${
      config.PROJECT_SPECIFIC_SCHEMA_PRIVATE_TO_RDES
    }."${tableNameNoQuotes}_WITH_IDENTIFIER"
EXCEPT
SELECT "GmPseudo" FROM "Patient_ID_Mapping_${projectNameChunked.join('_')}";

-- Find the highest currently assigned id. Ids are given incrementally, so now ones
-- need to start at +1 of the current highest
SET highestPatientId = (
    SELECT IFNULL(MAX("StudyPatientPseudoId"),0) FROM "Patient_ID_Mapping_${projectNameChunked.join(
      '_'
    )}"
);

-- Make a study specific hash for each new GmPseudo and insert it
-- into the patient lookup table
INSERT INTO "Patient_ID_Mapping_${projectNameChunked.join('_')}"
SELECT
    "GmPseudo", -- the GM SDE patient ids for patients in this cohort
    SHA2(CONCAT('${projectNameChunked.join(
      '_'
    )}', "GmPseudo")) AS "Hash", -- used to provide a random (study-specific) ordering for the patient ids we provide
    $highestPatientId + ROW_NUMBER() OVER (ORDER BY "Hash") -- the patient id that we provide to the analysts
FROM "AllPseudos_${projectNameChunked.join('_')}";

-- Finally, we select from the output table which includes the GmPseudos, in order
-- to populate the table for the end users where the GmPseudo fields are redacted via a function
-- created in the 0.code-sets.sql file
DROP TABLE IF EXISTS ${config.PROJECT_SPECIFIC_SCHEMA_FOR_DATA}.${tableName};
CREATE TABLE ${config.PROJECT_SPECIFIC_SCHEMA_FOR_DATA}.${tableName} AS
SELECT ${config.PROJECT_SPECIFIC_SCHEMA_PRIVATE_TO_RDES}.gm_pseudo_hash_${projectNameChunked.join('_')}("GmPseudo") AS "PatientID",
	* EXCLUDE "GmPseudo"
FROM ${config.PROJECT_SPECIFIC_SCHEMA_PRIVATE_TO_RDES}."${tableNameNoQuotes}_WITH_IDENTIFIER";`;

    sql =
      sql.substring(0, indexOfOutputTable) +
      replacedSql +
      finalSql +
      sql.substring(indexOfFinalSemiColon + 1);
  } else if (outputTableMatchedCohortMatch) {
    isMatch = true;
    let needSemiColon = false;

    const indexOfOutputTable = sql.indexOf('{{create-output-table-matched-cohort');
    let indexOfFinalSemiColon = sql.indexOf(';', indexOfOutputTable);
    if (indexOfFinalSemiColon < 0) {
      needSemiColon = true;
      indexOfFinalSemiColon = sql.length - 1;
    }

    const [, tableName] = outputTableMatchedCohortMatch;
    const tableNameNoQuotes = tableName.match(/^"?([^"]+)"?$/)[1];

    const replacedSql =
      sql.substring(indexOfOutputTable, indexOfFinalSemiColon + 1).replace(
        outputTableMatchedCohortRegex,
        `
-- ... processing ${outputTableMatchedCohortMatch[0].replace(/\{/g, '[').replace(/\}/g, ']')} ... 
-- ... Need to create an output table called ${tableName} and replace 
-- ... the GmPseudo column with a study-specific random patient id.

-- First we create a table in an area only visible to the RDEs which contains
-- the GmPseudos. THESE CANNOT BE RELEASED TO END USERS.
DROP TABLE IF EXISTS ${
          config.PROJECT_SPECIFIC_SCHEMA_PRIVATE_TO_RDES
        }."${tableNameNoQuotes}_WITH_IDENTIFIER";
CREATE TABLE ${
          config.PROJECT_SPECIFIC_SCHEMA_PRIVATE_TO_RDES
        }."${tableNameNoQuotes}_WITH_IDENTIFIER" AS`
      ) + (needSemiColon ? ';' : '');

    const finalSql = `

-- Then we check to see if there are any new GmPseudo ids. We do this by making a temp table 
-- of all "new" GmPseudo ids from either the main column or the matched column. I.e. any GmPseudo ids that 
-- we've already got a unique id for for this study are excluded

DROP TABLE IF EXISTS "AllPseudos_${projectNameChunked.join('_')}";
CREATE TEMPORARY TABLE "AllPseudos_${projectNameChunked.join('_')}" AS
(
SELECT DISTINCT "GmPseudo" FROM ${
      config.PROJECT_SPECIFIC_SCHEMA_PRIVATE_TO_RDES
    }."${tableNameNoQuotes}_WITH_IDENTIFIER"
UNION 
SELECT DISTINCT "MainCohortMatchedGmPseudo" FROM ${
      config.PROJECT_SPECIFIC_SCHEMA_PRIVATE_TO_RDES
    }."${tableNameNoQuotes}_WITH_IDENTIFIER"
)
EXCEPT
SELECT "GmPseudo" FROM "Patient_ID_Mapping_${projectNameChunked.join('_')}";

-- Find the highest currently assigned id. Ids are given incrementally, so now ones
-- need to start at +1 of the current highest
SET highestPatientId = (
    SELECT IFNULL(MAX("StudyPatientPseudoId"),0) FROM "Patient_ID_Mapping_${projectNameChunked.join(
      '_'
    )}"
);

-- Make a study specific hash for each new GmPseudo and insert it
-- into the patient lookup table
INSERT INTO "Patient_ID_Mapping_${projectNameChunked.join('_')}"
SELECT
    "GmPseudo", -- the GM SDE patient ids for patients in this cohort
    SHA2(CONCAT('${projectNameChunked.join(
      '_'
    )}', "GmPseudo")) AS "Hash", -- used to provide a random (study-specific) ordering for the patient ids we provide
    $highestPatientId + ROW_NUMBER() OVER (ORDER BY "Hash") -- the patient id that we provide to the analysts
FROM "AllPseudos_${projectNameChunked.join('_')}";

-- Finally, we select from the output table which includes the GmPseudos, in order
-- to populate the table for the end users where the GmPseudo fields are redacted via a function
-- created in the 0.code-sets.sql file
DROP TABLE IF EXISTS ${config.PROJECT_SPECIFIC_SCHEMA_FOR_DATA}.${tableName};
CREATE TABLE ${config.PROJECT_SPECIFIC_SCHEMA_FOR_DATA}.${tableName} AS
SELECT ${config.PROJECT_SPECIFIC_SCHEMA_PRIVATE_TO_RDES}.gm_pseudo_hash_${projectNameChunked.join('_')}("GmPseudo") AS "PatientID",
	${config.PROJECT_SPECIFIC_SCHEMA_PRIVATE_TO_RDES}.gm_pseudo_hash_${projectNameChunked.join('_')}("MainCohortMatchedGmPseudo") AS "MainCohortMatchedPatientID",
	* EXCLUDE ("GmPseudo", "MainCohortMatchedGmPseudo")
FROM ${config.PROJECT_SPECIFIC_SCHEMA_PRIVATE_TO_RDES}."${tableNameNoQuotes}_WITH_IDENTIFIER";`;

    sql =
      sql.substring(0, indexOfOutputTable) +
      replacedSql +
      finalSql +
      sql.substring(indexOfFinalSemiColon + 1);
 
} else if (outputTableNoIdsMatch) {
    isMatch = true;
    let needSemiColon = false;

    const indexOfOutputTable = sql.indexOf('{{create-output-table-no-gmpseudo-ids');
    let indexOfFinalSemiColon = sql.indexOf(';', indexOfOutputTable);
    if (indexOfFinalSemiColon < 0) {
      needSemiColon = true;
      indexOfFinalSemiColon = sql.length - 1;
    }

    const [, tableName] = outputTableNoIdsMatch;

    const replacedSql =
      sql.substring(indexOfOutputTable, indexOfFinalSemiColon + 1).replace(
        outputTableNoIdsRegex,
        `
-- There are no patient ids ("GmPseudo") so we don't need to 
-- obfuscate them. Instead we just create a table, readable by the analysts
-- where we put the data.
DROP TABLE IF EXISTS ${config.PROJECT_SPECIFIC_SCHEMA_FOR_DATA}.${tableName};
CREATE TABLE ${config.PROJECT_SPECIFIC_SCHEMA_FOR_DATA}.${tableName} AS`
      ) + (needSemiColon ? ';' : '');

    sql =
      sql.substring(0, indexOfOutputTable) + replacedSql + sql.substring(indexOfFinalSemiColon + 1);
  }
  if (isMatch) return sql;
  else return false;
}

async function generateSql(project, projectName, templates, isSnowflake, config) {
  const OUTPUT_DIRECTORY = join(project, EXTRACTION_SQL_DIR);
  const allCodeSets = {};
  const projectNameChunked = projectName.replace(/[^a-zA-Z0-9]+/g, '_').split('_');
  const codeSetTableName = `${
    config.PROJECT_SPECIFIC_SCHEMA_PRIVATE_TO_RDES
  }."Code_Sets_${projectNameChunked.join('_')}"`;
  const cohortTableName = `${
    config.PROJECT_SPECIFIC_SCHEMA_PRIVATE_TO_RDES
  }."Cohort_${projectNameChunked.join('_')}"`;
  for (const templateName of templates) {
    const filename = join(project, TEMPLATE_SQL_DIR, templateName);
    const { sql, codeSets } = processFile(filename, [], {}, [], isSnowflake);

    codeSets.forEach(({ codeSet, version }) => {
      if (!allCodeSets[codeSet]) {
        allCodeSets[codeSet] = new Set([version]);
      } else {
        allCodeSets[codeSet].add(version);
      }
    });

    const outputName = templateName.replace('.template', '');

    let finalSQL;
    if (isSnowflake) {
      if (sql.match(/\{\{no-output-table\}\}/)) {
        finalSQL = sql.replace(
          /\{\{no-output-table\}\}/,
          '-- No output table required for this script'
        );
      } else {
        finalSQL = processNextOutputTable(sql, templateName, config, projectNameChunked);
        if (!finalSQL) {
          console.log(`${templateName} does not contain one of the following:
  {{create-output-table::table-name}}                       -- the typical sql template that writes output data to a table
  {{create-output-table-no-gmpseudo-ids::table-name}}       -- sql templates where the output does not include patient ids ("GmPseudo")
  {{no-output-table}}                                       -- for sql templates that don't have an output`);
          process.exit();
        }
        let anyMoreSQL = true;
        while (anyMoreSQL) {
          anyMoreSQL = processNextOutputTable(finalSQL, templateName, config, projectNameChunked);
          if (anyMoreSQL) {
            finalSQL = anyMoreSQL;
          }
        }
      }

      finalSQL = `USE SCHEMA ${config.PROJECT_SPECIFIC_SCHEMA_PRIVATE_TO_RDES};\n\n${finalSQL
        .replace(/\{\{code-set-table\}\}/g, codeSetTableName)
        .replace(/\{\{cohort-table\}\}/g, cohortTableName)
        .replace(/\{\{project-schema\}\}/g, config.PROJECT_SPECIFIC_SCHEMA_FOR_DATA)}`;

      writeFileSync(join(OUTPUT_DIRECTORY, outputName), finalSQL);
    } else {
      let codeSetSql = await (codeSets.length > 0 ? createCodeSetSQL(codeSets) : '');
      finalSQL = sql.replace(CODESET_MARKER, codeSetSql);

      writeFileSync(join(OUTPUT_DIRECTORY, outputName), finalSQL);
    }
  }
  const flattenedCodeSets = Object.keys(allCodeSets)
    .map((codeSet) => Array.from(allCodeSets[codeSet]).map((version) => ({ codeSet, version })))
    .flat();
  if (flattenedCodeSets.length > 0 && isSnowflake) {
    // we have some codesets so write the file to populate the code set tables
    const { sql, csv } = await (flattenedCodeSets.length > 0
      ? createCodeSetSQL(flattenedCodeSets, projectNameChunked, config)
      : '');
    // codeSetSql.forEach((sql, i) => {
    //   const id = `0${i + 1}`.slice(-2);
    //   writeFileSync(join(OUTPUT_DIRECTORY, `0.${id}.code-sets.sql`), sql);
    // });

    writeFileSync(join(OUTPUT_DIRECTORY, `0.code-sets.sql`), sql);
    // And one big csv file
    writeFileSync(join(OUTPUT_DIRECTORY, `0.code-sets.csv`), csv);
  }

  if (isProjectDirectory) {
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

function processFile(
  filename,
  requiredCodeSets = [],
  alreadyProcessed = {},
  parameters = [],
  isSnowflake
) {
  // Allow file to be processed twice if the parameters are different
  alreadyProcessed[filename + JSON.stringify(parameters)] = true;
  const sqlLines = readFileSync(filename, 'utf8').replace(/\r/g, '').split('\n');
  const conditionalStatments = [];

  let excludeFromIndex = -1;
  const generatedSql = sqlLines
    .map((line) => {
      // First let's process the conditional logic. This is where there is a block
      // of code like:
      // {if:param}
      //    // Code if param "param" exists
      // {endif:param}
      // We restrict it so that the "if" and "endif" statements must be the only
      // thing on a line.
      // Also allow the variant:
      // {if:param=blah}
      //    // Code if param "param" exists and equals "blah"
      // {endif:param}

      // See if there are any conditional statements.
      // For now this logic only allows at most one opening
      // or closing condition per line. Should be enough.
      const possibleConditionStatement = new RegExp('^(.*){if:([^}=]+)(?:=([^}]+))?}(.*)$');
      if (line.match(possibleConditionStatement)) {
        const possibleConditionMatch = line.match(possibleConditionStatement);
        const [, preText, paramName, optinalParamValue, postText] = possibleConditionMatch;
        if ((preText && preText.length > 0) || (postText && postText.length > 0)) {
          console.log(
            `The file ${basename(filename)} has an if statement for the parameter: ${paramName}`
          );
          console.log('However the syntax is incorrect. The {if:xxx} block should be the only');
          console.log('thing on the line. E.g. nothing before or after - including whitespace');
          process.exit();
        }
        if (
          (parameters[paramName] || parameters[paramName] === 0) &&
          (!optinalParamValue || parameters[paramName] === optinalParamValue)
        ) {
          const isIncluding = excludeFromIndex < 0; // condition is met so include UNLESS currently excluding
          conditionalStatments.push({ paramName, isIncluding });
        } else {
          //
          const isIncluding = false; // condition is not met so exclude from here onwards
          if (excludeFromIndex < 0) excludeFromIndex = conditionalStatments.length;
          conditionalStatments.push({ paramName, isIncluding });
        }
        return false;
      }

      // Now let's check for the closure of any conditional statements e.g.
      // the end of blocks like this:
      // {if:param}
      //    // Code if param "param" exists
      // {endif:param}
      const possibleConditionEnd = new RegExp('^(.*){endif:([^}]+)}(.*)$');
      if (line.match(possibleConditionEnd)) {
        const possibleConditionMatch = line.match(possibleConditionEnd);
        const [, preText, paramName, postText] = possibleConditionMatch;
        if ((preText && preText.length > 0) || (postText && postText.length > 0)) {
          console.log(
            `The file ${basename(filename)} has an endif statement for the parameter: ${paramName}`
          );
          console.log('However the syntax is incorrect. The {endif:xxx} block should be the only');
          console.log('thing on the line. E.g. nothing before or after - including whitespace');
          process.exit();
        }
        // Must equal the last if statement
        if (
          conditionalStatments.length > 0 &&
          conditionalStatments[conditionalStatments.length - 1].paramName === paramName
        ) {
          // all is well
          conditionalStatments.pop();
          if (conditionalStatments.length === excludeFromIndex) {
            excludeFromIndex = -1;
          }
        } else {
          console.log(
            `The file ${basename(filename)} has an endif statement for the parameter: ${paramName}`
          );
          console.log('However the param for the opening {if:xx} statement does not match.');
          console.log('You can nest if statements inside other if statements, but you cannot');
          console.log('close an if statement out of sequence.');
          process.exit();
        }
        return false;
      }

      if (excludeFromIndex > -1) {
        // We're excluding so return blank
        return false;
      }

      // Now let's replace any parameters
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
${isSnowflake ? '-- >>> Codesets extracted into 0.code-sets.sql' : CODESET_MARKER}
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
            processedParameters,
            isSnowflake
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
          alreadyProcessed,
          [],
          isSnowflake
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
    .filter((x) => x !== false) // remove the "false" entries to avoid blank lines
    .join('\n');
  return { sql: generatedSql, codeSets: requiredCodeSets };
}
// stitch(join(__dirname, '..', 'projects', 'SDE Lighthouse 04 - Bruce'), true);
// stitch(join(__dirname, '..', 'projects', '001 - Grant'));
//stitch(join(__dirname, '..', 'projects', '046 - Gupta'));
module.exports = { stitch };
