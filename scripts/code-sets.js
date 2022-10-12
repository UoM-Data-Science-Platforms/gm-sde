const inquirer = require('inquirer');
const chalk = require('chalk');
const { readdirSync, readFileSync, writeFileSync, mkdirSync, existsSync } = require('fs');
const { join } = require('path');
const { log, warn, setSilence, getSilence } = require('./log');
const { GITHUB_BASE_URL, GITHUB_REPO } = require('./config');

const CODE_SET_PARENT_DIR = join(__dirname, '..', 'shared', 'clinical-code-sets');
const EMIS = 'emis';
const SNOMED = 'snomed';
const READv2 = 'readv2';
const CTV3 = 'ctv3';
const terminologies = [EMIS, SNOMED, READv2, CTV3];
let clinicalCodesByTerminology;
let clinicalCodesByConcept;

function initializeClinicalCodeObjects() {
  clinicalCodesByTerminology = {};
  terminologies.forEach((terminology) => {
    clinicalCodesByTerminology[terminology] = {};
  });
  clinicalCodesByConcept = {};
}

const createCodeSet = (type, codeSetName) => {
  // Create the code set directory
  const CODE_SET_DIR = join(CODE_SET_PARENT_DIR, type, codeSetName);
  mkdirSync(CODE_SET_DIR);

  const VERSION_DIR = join(CODE_SET_DIR, '1');
  // Create the first version
  mkdirSync(VERSION_DIR);

  // Create the skeleton files
  writeFileSync(join(VERSION_DIR, `${codeSetName}.ctv3.txt`), '');
  writeFileSync(join(VERSION_DIR, `${codeSetName}.readv2.txt`), '');
  writeFileSync(join(VERSION_DIR, `${codeSetName}.snomed.txt`), '');
  writeFileSync(join(VERSION_DIR, `README.md`), '');

  log(`
The code set directory and skeleton files have been created.

Please fill out the code sets in:

${VERSION_DIR}
`);
};

const getCodesetType = (codeSet) => {
  const codeSetTypes = getClinicalCodeSetTypes();
  for (let i = 0; i < codeSetTypes.length; i++) {
    const codeSetDir = join(CODE_SET_PARENT_DIR, codeSetTypes[i], codeSet);
    if (existsSync(codeSetDir)) {
      return codeSetTypes[i];
    }
  }
  return false;
};

/**
 * Method to check that a code set exists
 * @param {Object} config
 * @param {string} config.codeSet - The hyphen-delimited code set name
 * @param {string} [config.version] - The code set version
 * @returns {Boolean} Whether the code set exists
 */
const theCodeSetExists = ({ codeSet, version }) => {
  const codeSetType = getCodesetType(codeSet);
  if (!codeSetType) return false; // can't find the code set type so doesn't exist
  if (!version) return true; // code set type exists, therefore it does and version is unimportant

  // If here, then we are looking for a particular version of an existing code set
  const codeSetVersionDir = join(CODE_SET_PARENT_DIR, codeSetType, codeSet, version);
  return existsSync(codeSetVersionDir);
};

const getCodeSets = ({ codeSet, type = getCodesetType(codeSet), version }) => {
  const codeSetVersionDir = join(CODE_SET_PARENT_DIR, type, codeSet, version);
  const codeSetFiles = readdirSync(codeSetVersionDir)
    .map((filename) => {
      const [txt, terminology, ...codeSetName] = filename.split('.').reverse();
      if (txt !== 'txt') return false;
      if (!codeSetName || codeSetName.length === 0) return false;
      if (terminologies.indexOf(terminology) < 0) {
        warn(
          `Unknown code set type for [${codeSet} v${version}]. Expecting one of [${terminologies.join(
            '|'
          )}], but instead found "${terminology}"`
        );
        return false;
      }
      const file = readFileSync(join(codeSetVersionDir, filename), 'utf8').replace(/\r/g, ''); // remove any carriage returns
      return { terminology, file };
    })
    .filter(Boolean);
  return codeSetFiles;
};

const getCodeSet = (codeSet) => {
  const type = getCodesetType(codeSet);
  const versions = getCodeSetVersions(type, codeSet);
  const codeSetObject = {};
  versions.forEach((version) => {
    codeSetObject[version] = getCodeSets({ codeSet, type, version });
  });

  return codeSetObject;
};

/**
 * Method to validate and evaulate the existing clinical code sets.
 */
const evaluateCodeSets = async (isSingle = false) => {
  log(isSingle ? '\nEvaluating a single code set' : '\nEvaluating the code sets...');
  initializeClinicalCodeObjects();

  const codeSetTypes = getClinicalCodeSetTypes();

  log(`
There are ${codeSetTypes.length} code set types. They are: ${codeSetTypes
    .map((x) => chalk.bgWhite.black(x))
    .join(' ')}.`);

  if (!isSingle) {
    for (const codeSetType of codeSetTypes) {
      const codeSets = getClinicalCodeSets(codeSetType);
      for (const codeSetName of codeSets) {
        const versions = getCodeSetVersions(codeSetType, codeSetName);
        for (const version of versions) {
          checkForUnexpectedFiles(codeSetType, codeSetName, version);
          await processFiles(codeSetType, codeSetName, version);
        }
      }
    }

    const longestConceptLength = Object.keys(clinicalCodesByConcept).sort(
      (a, b) => b.length - a.length
    )[0].length;
    const spacing = '                                                    ';
    function spaceIt(concept) {
      return (spacing + concept).substr(
        (spacing + concept).length - longestConceptLength,
        longestConceptLength
      );
    }

    log(`
  The code sets found are as follows:

  ${Object.keys(clinicalCodesByConcept)
    .map(
      (concept) =>
        `  ${chalk.cyan(spaceIt(concept))}: ${Object.keys(clinicalCodesByConcept[concept])
          .map((x) => {
            if (x === 'emis') return chalk.bgRed.bold(x);
            if (x === 'readv2') return chalk.bgGreen.bold(x);
            if (x === 'ctv3') return chalk.bgYellow.black(x);
            if (x === 'snomed') return chalk.bgWhite.black(x);
            return x;
          })
          .join(' ')}`
    )
    .join('\n')}

  The code sets look ok. 
  If there were any major issues you wouldn't see this message.
  If there are minor issues they will appear above this message.
    `);
  } else {
    const { codeSetType } = await inquirer.prompt([
      {
        type: 'list',
        name: 'codeSetType',
        message: `Which code set type?`,
        choices: codeSetTypes.map((x) => ({ name: x, value: x })),
      },
    ]);
    const { codeSetName } = await inquirer.prompt([
      {
        type: 'list',
        name: 'codeSetName',
        message: `Which code set?`,
        choices: getClinicalCodeSets(codeSetType).map((x) => ({ name: x, value: x })),
      },
    ]);
    const versions = getCodeSetVersions(codeSetType, codeSetName);
    for (const version of versions) {
      checkForUnexpectedFiles(codeSetType, codeSetName, version);
      await processFiles(codeSetType, codeSetName, version);
    }
  }
};

/**
 * Method to create the reusable clinical code set SQL file
 */
const createCodeSetSQL = async (conditions = []) => {
  setSilence(true);
  await evaluateCodeSets();

  setSilence(false);

  log(`
Generating the SQL...`);

  const SQL = `--
--┌────────────────────┐
--│ Clinical code sets │
--└────────────────────┘

-- OBJECTIVE: To populate temporary tables with the existing clinical code sets.
--            See the [SQL-generation-process.md](SQL-generation-process.md) for more details.

-- INPUT: No pre-requisites

-- OUTPUT: Five temp tables as follows:
--  #AllCodes (Concept, Version, Code)
--  #CodeSets (FK_Reference_Coding_ID, Concept)
--  #SnomedSets (FK_Reference_SnomedCT_ID, FK_SNOMED_ID)
--  #VersionedCodeSets (FK_Reference_Coding_ID, Concept, Version)
--  #VersionedSnomedSets (FK_Reference_SnomedCT_ID, Version, FK_SNOMED_ID)

--!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
--!!! DO NOT EDIT THIS FILE MANUALLY !!!
--!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

IF OBJECT_ID('tempdb..#AllCodes') IS NOT NULL DROP TABLE #AllCodes;
CREATE TABLE #AllCodes (
  [Concept] [varchar](255) NOT NULL,
  [Version] INT NOT NULL,
  [Code] [varchar](20) COLLATE Latin1_General_CS_AS NOT NULL,
  [description] [varchar] (255) NULL 
);

${['readv2', 'ctv3', 'snomed', 'emis']
  .map(
    (
      terminology
    ) => `IF OBJECT_ID('tempdb..#codes${terminology}') IS NOT NULL DROP TABLE #codes${terminology};
CREATE TABLE #codes${terminology} (
  [concept] [varchar](255) NOT NULL,
  [version] INT NOT NULL,
	[code] [varchar](20) COLLATE Latin1_General_CS_AS NOT NULL,
	[term] [varchar](20) COLLATE Latin1_General_CS_AS NULL,
	[description] [varchar](255) NULL
) ON [PRIMARY];

${Object.keys(clinicalCodesByTerminology[terminology])
  .filter(
    (concept) => conditions.length === 0 || conditions.map((x) => x.codeSet).indexOf(concept) > -1
  )
  .map((concept) => {
    const usedCodes = Object.keys(clinicalCodesByTerminology[terminology][concept])
      .filter(
        (version) =>
          conditions.map((x) => x.codeSet + '_' + x.version).indexOf(concept + '_' + version) > -1
      )
      .map((version) =>
        clinicalCodesByTerminology[terminology][concept][version].map(
          (item) =>
            `('${concept}',${version},'${item.code}',${item.term ? `'${item.term}'` : 'NULL'},'${
              item.description
            }')`
        )
      );
    return usedCodes.length === 0
      ? false
      : usedCodes
          .flat()
          .reduce(
            (soFar, nextValue) => {
              if (soFar.itemCount === 999) {
                // SQL only allows 1000 items to be inserted after each INSERT INTO statememt
                // so need to start again
                soFar.sql = `${soFar.sql.slice(0, -1)};\nINSERT INTO #codes${terminology}\nVALUES `;
                soFar.lineLength = 7;
                soFar.itemCount = 0;
              }
              if (soFar.lineLength > 9900) {
                // the sql management studio doesn't style lines much longer than this
                soFar.sql += `\n${nextValue},`;
                soFar.lineLength = nextValue.length + 1;
              } else {
                soFar.sql += `${nextValue},`;
                soFar.lineLength += nextValue.length + 1;
              }
              soFar.itemCount += 1;
              return soFar;
            },
            { sql: `INSERT INTO #codes${terminology}\nVALUES `, itemCount: 0, lineLength: 7 }
          )
          .sql.slice(0, -1);
  })
  .filter(Boolean)
  .join(';\n')}

INSERT INTO #AllCodes
SELECT [concept], [version], [code], [description] from #codes${terminology};
`
  )
  .join('\n')}

IF OBJECT_ID('tempdb..#TempRefCodes') IS NOT NULL DROP TABLE #TempRefCodes;
CREATE TABLE #TempRefCodes (FK_Reference_Coding_ID BIGINT NOT NULL, concept VARCHAR(255) NOT NULL, version INT NOT NULL, [description] VARCHAR(255));

-- Read v2 codes
INSERT INTO #TempRefCodes
SELECT PK_Reference_Coding_ID, dcr.concept, dcr.[version], dcr.[description]
FROM [SharedCare].[Reference_Coding] rc
INNER JOIN #codesreadv2 dcr on dcr.code = rc.MainCode
WHERE CodingType='ReadCodeV2'
AND (dcr.term IS NULL OR dcr.term = rc.Term)
and PK_Reference_Coding_ID != -1;

-- CTV3 codes
INSERT INTO #TempRefCodes
SELECT PK_Reference_Coding_ID, dcc.concept, dcc.[version], dcc.[description]
FROM [SharedCare].[Reference_Coding] rc
INNER JOIN #codesctv3 dcc on dcc.code = rc.MainCode
WHERE CodingType='CTV3'
and PK_Reference_Coding_ID != -1;

-- EMIS codes with a FK Reference Coding ID
INSERT INTO #TempRefCodes
SELECT FK_Reference_Coding_ID, ce.concept, ce.[version], ce.[description]
FROM [SharedCare].[Reference_Local_Code] rlc
INNER JOIN #codesemis ce on ce.code = rlc.LocalCode
WHERE FK_Reference_Coding_ID != -1;

IF OBJECT_ID('tempdb..#TempSNOMEDRefCodes') IS NOT NULL DROP TABLE #TempSNOMEDRefCodes;
CREATE TABLE #TempSNOMEDRefCodes (FK_Reference_SnomedCT_ID BIGINT NOT NULL, concept VARCHAR(255) NOT NULL, [version] INT NOT NULL, [description] VARCHAR(255));

-- SNOMED codes
INSERT INTO #TempSNOMEDRefCodes
SELECT PK_Reference_SnomedCT_ID, dcs.concept, dcs.[version], dcs.[description]
FROM SharedCare.Reference_SnomedCT rs
INNER JOIN #codessnomed dcs on dcs.code = rs.ConceptID;

-- EMIS codes with a FK SNOMED ID but without a FK Reference Coding ID
INSERT INTO #TempSNOMEDRefCodes
SELECT FK_Reference_SnomedCT_ID, ce.concept, ce.[version], ce.[description]
FROM [SharedCare].[Reference_Local_Code] rlc
INNER JOIN #codesemis ce on ce.code = rlc.LocalCode
WHERE FK_Reference_Coding_ID = -1
AND FK_Reference_SnomedCT_ID != -1;

-- De-duped tables
IF OBJECT_ID('tempdb..#CodeSets') IS NOT NULL DROP TABLE #CodeSets;
CREATE TABLE #CodeSets (FK_Reference_Coding_ID BIGINT NOT NULL, concept VARCHAR(255) NOT NULL, [description] VARCHAR(255));

IF OBJECT_ID('tempdb..#SnomedSets') IS NOT NULL DROP TABLE #SnomedSets;
CREATE TABLE #SnomedSets (FK_Reference_SnomedCT_ID BIGINT NOT NULL, concept VARCHAR(255) NOT NULL, [description] VARCHAR(255));

IF OBJECT_ID('tempdb..#VersionedCodeSets') IS NOT NULL DROP TABLE #VersionedCodeSets;
CREATE TABLE #VersionedCodeSets (FK_Reference_Coding_ID BIGINT NOT NULL, Concept VARCHAR(255), [Version] INT, [description] VARCHAR(255));

IF OBJECT_ID('tempdb..#VersionedSnomedSets') IS NOT NULL DROP TABLE #VersionedSnomedSets;
CREATE TABLE #VersionedSnomedSets (FK_Reference_SnomedCT_ID BIGINT NOT NULL, Concept VARCHAR(255), [Version] INT, [description] VARCHAR(255));

INSERT INTO #VersionedCodeSets
SELECT DISTINCT * FROM #TempRefCodes;

INSERT INTO #VersionedSnomedSets
SELECT DISTINCT * FROM #TempSNOMEDRefCodes;

INSERT INTO #CodeSets
SELECT FK_Reference_Coding_ID, c.concept, [description]
FROM #VersionedCodeSets c
INNER JOIN (
  SELECT concept, MAX(version) AS maxVersion FROM #VersionedCodeSets
  GROUP BY concept)
sub ON sub.concept = c.concept AND c.version = sub.maxVersion;

INSERT INTO #SnomedSets
SELECT FK_Reference_SnomedCT_ID, c.concept, [description]
FROM #VersionedSnomedSets c
INNER JOIN (
  SELECT concept, MAX(version) AS maxVersion FROM #VersionedSnomedSets
  GROUP BY concept)
sub ON sub.concept = c.concept AND c.version = sub.maxVersion;
`;
  return SQL;
};

async function processFiles(codeSetType, codeSetName, version) {
  const CODE_SET_DIR = join(CODE_SET_PARENT_DIR, codeSetType, codeSetName, version);

  // Find the files
  const codeSetFiles = readdirSync(CODE_SET_DIR, { withFileTypes: true }) // read all children of the CODE_SET_DIR
    .filter((item) => item.isFile()) // ..then filter to just files
    .map((file) => file.name) // ..then return the file name
    .filter((filename) => isValidCodeSetFile(filename)); // ..then return the valid code set files

  for (const codeSetFile of codeSetFiles) {
    const codeSetData = readFileSync(join(CODE_SET_DIR, codeSetFile), 'utf8').replace(/\r/g, '');
    const [, terminology] = codeSetFile.split('.');
    const codeSet = await parseCodeSet(
      version,
      CODE_SET_DIR,
      codeSetData,
      codeSetName,
      codeSetFile,
      terminology
    );
    if (
      clinicalCodesByTerminology[terminology][codeSetName] &&
      clinicalCodesByTerminology[terminology][codeSetName][version]
    ) {
      throw new Error(`
Attempting to add a code set ${codeSetName} from the file ${codeSetFile}.
However there appears to already by a code set for ${codeSetName} and ${terminology} with version ${version}.
      `);
    }
    if (!clinicalCodesByTerminology[terminology][codeSetName]) {
      clinicalCodesByTerminology[terminology][codeSetName] = {};
    }
    clinicalCodesByTerminology[terminology][codeSetName][version] = codeSet;
    if (!clinicalCodesByConcept[codeSetName]) {
      clinicalCodesByConcept[codeSetName] = {};
    }
    if (
      clinicalCodesByConcept[codeSetName][terminology] &&
      clinicalCodesByConcept[codeSetName][terminology][version]
    ) {
      throw new Error(`
Attempting to add a code set ${codeSetName} from the file ${codeSetFile}.
However there appears to already by a code set for ${codeSetName} and ${terminology} with version ${version}.
      `);
    }
    if (!clinicalCodesByConcept[codeSetName][terminology]) {
      clinicalCodesByConcept[codeSetName][terminology] = {};
    }
    clinicalCodesByConcept[codeSetName][terminology][version] = codeSet;
  }
}

let mismatchDescriptionTempIgnoreAll = false;
const mismatchDescriptionTempIgnore = {};

let missingReadv2RootCodeTempIgnoreAll = false;
const missingReadv2RootCodeTempIgnore = {};

async function parseCodeSet(version, CODE_SET_DIR, codeSetData, name, codeSetFile, terminology) {
  if (
    codeSetData.toLowerCase().indexOf(name.split('-').join(' ')) < 0 &&
    !mismatchDescriptionTempIgnoreAll &&
    !mismatchDescriptionTempIgnore[name] &&
    !getSilence()
  ) {
    // Check for permanent ignore file
    const ignoreFile = join(CODE_SET_DIR, '.ignore-mismatch-description');
    const ignoredTerminologies = existsSync(ignoreFile)
      ? readFileSync(ignoreFile, 'utf8')
          .split('\n')
          .map((x) => x.trim())
      : [];
    if (!ignoredTerminologies.includes(terminology)) {
      const answer = await inquirer.prompt([
        {
          type: 'list',
          name: 'action',
          message: `v${version} of code set ${codeSetFile} does not appear to have any descriptions that match "${name
            .split('-')
            .join(' ')}".`,
          choices: [
            { name: `Temporarily ignore this warning for the ${name} codeset`, value: 'just_now' },
            { name: `Temporarily ignore this warning for all code sets`, value: 'all' },
            {
              name: `I've checked and this is fine. Never ask me again for the ${name} ${terminology} codeset`,
              value: 'just_forever',
            },
          ],
        },
      ]);
      if (answer.action === 'all') {
        mismatchDescriptionTempIgnoreAll = true;
      } else if (answer.action === 'just_now') {
        mismatchDescriptionTempIgnore[name] = true;
      } else if (answer.action === 'just_forever') {
        ignoredTerminologies.push(terminology);
        writeFileSync(ignoreFile, ignoredTerminologies.join('\n'), 'utf8');
      }
    }
  }

  const rows = codeSetData
    .replace(/\r/g, '') // Get rid of windows carriage returns
    .split('\n') // ..then split into rows
    .map((x) => x.trim()) // ..then trim blank space from each line
    .filter((x) => x.length > 0); // ..then get rid of empty lines

  rows.forEach((row, i) => {
    if (!isValidDataRow(row)) {
      throw new Error(`
The data rows in the code sets should contain 2 tab separated values: the code and the description.

Row ${i} in ${codeSetFile} in ${name} is not of this format.

The broken row is:

${row}
      `);
    }
  });

  if (rows.length === 0) {
    throw new Error(`
The code set ${codeSetFile} in ${name} appears to be empty.
    `);
  }

  const codes = [];

  // Occasionally we may want a synonym in Read (when digits 6 and 7 are present and aren't ='00')
  // but not the main code (7 digiti ending in '00'). If we find that we first flag it to the end
  // user in case it is an ommission. Assuming it isn't we need to deal with the SQL differently.
  const readv2TermChecker = {};

  for (const row of rows) {
    const [code, description] = row.split('\t');
    if (terminology === 'readv2') {
      if (code.length === 5) {
        readv2TermChecker[code] = { description: description.replace(/'/g, '') };
      } else if (code.length === 7) {
        const term = code.substring(5, 7);
        const rootCode = code.substring(0, 5);

        // Deal with the term codes
        if (term === '00') {
          readv2TermChecker[rootCode] = { description: description.replace(/'/g, '') };
        } else {
          if (!readv2TermChecker[rootCode]) {
            // we don't already have the root code for this synonym
            readv2TermChecker[rootCode] = [
              {
                term,
                description: description.replace(/'/g, ''),
              },
            ];
          } else if (readv2TermChecker[rootCode].description) {
            // Already have the root code so do nothing
          } else {
            // Currently only have synonyms, so add another
            readv2TermChecker[rootCode].push({
              term,
              description: description.replace(/'/g, ''),
            });
          }
        }
      }
    } else {
      codes.push({ code, description: description.replace(/'/g, '') });
    }
  }

  if (terminology === 'readv2') {
    for (const [code, value] of Object.entries(readv2TermChecker)) {
      if (value.description) {
        // This means we have the root code
        codes.push({ code, description: value.description });
        codes.push({ code: `${code}00`, description: value.description });
      } else if (!missingReadv2RootCodeTempIgnore[name] && !missingReadv2RootCodeTempIgnoreAll) {
        // Check for permanent ignore file
        const ignoreFile = join(CODE_SET_DIR, '.ignore-missing-readv2-root-codes');
        const ignoredCodes = existsSync(ignoreFile)
          ? readFileSync(ignoreFile, 'utf8')
              .split('\n')
              .map((x) => x.trim())
          : [];
        if (ignoredCodes.includes(code) || getSilence()) {
          value.forEach((x) => {
            codes.push({ code, term: x.term, description: x.description });
          });
        } else {
          const codesAffected = value.map((x) => `${code}${x.term} - ${x.description}`).join('\n');

          const answer = await inquirer.prompt([
            {
              type: 'list',
              name: 'action',
              message: `v${version} of the Readv2 code set in ${name} contains synonyms (7 digit codes not ending in 00)
without the root code. This is often fine, but worth double checking. The affected ${
                value.length > 1 ? 'codes are' : 'code is'
              }:\n\n${codesAffected}\n\n`,
              choices: [
                {
                  name: `Temporarily ignore this warning for all codes in the ${name} codeset`,
                  value: 'just_now',
                },
                { name: `Temporarily ignore this warning for all code sets`, value: 'all' },
                {
                  name: `I've checked the root code (${code}) and it's not needed. Never ask me again.`,
                  value: 'just_forever',
                },
                { name: 'Let me exit so I can double check this', value: 'exit' },
              ],
            },
          ]);
          if (answer.action === 'all') {
            missingReadv2RootCodeTempIgnoreAll = true;
          } else if (answer.action === 'just_now') {
            missingReadv2RootCodeTempIgnore[name] = true;
          } else if (answer.action === 'just_forever') {
            ignoredCodes.push(code);
            writeFileSync(ignoreFile, ignoredCodes.join('\n'), 'utf8');
          } else {
            process.exit(0);
          }
        }
        value.forEach((x) => {
          codes.push({ code, term: x.term, description: x.description });
        });
      }
    }
  }

  return codes;
}

/**
 * Validates and returns the version numbers for the code set
 * @param {string} codeSetType Such as "conditions", "medications" or "tests"
 * @param {string} codeSetName Such as "hypertension", "methotrexate" or "ethnicity"
 * @param {string} version Such as "1", "2" or "3"
 */
function checkForUnexpectedFiles(codeSetType, codeSetName, version) {
  const CODE_SET_DIR = join(CODE_SET_PARENT_DIR, codeSetType, codeSetName, version);
  // Should only be files in the code set directory
  const folders = readdirSync(CODE_SET_DIR, { withFileTypes: true }) // read all children of the CODE_SET_DIR
    .filter((item) => item.isDirectory()) // ..then filter to just folders
    .map((dir) => dir.name); // ..then return the folder name

  if (folders && folders.length > 0) {
    throw new Error(
      `There should only be files in the ${CODE_SET_DIR} directory. However there appear to be the following directories: ${folders.join(
        ', '
      )}.`
    );
  }
  // Find the files
  const codeSetFiles = readdirSync(CODE_SET_DIR, { withFileTypes: true }) // read all children of the CODE_SET_DIR
    .filter((item) => item.isFile()) // ..then filter to just files
    .map((file) => file.name); // ..then return the file name

  // Find any that don't conform to the naming convention
  const invalidNames = codeSetFiles.filter(
    (codeSetFile) =>
      !isValidCodeSetFile(codeSetFile) &&
      !isValidCodeSetMetadataFile(codeSetFile) &&
      !isValidIgnoreFile(codeSetFile)
  );

  if (invalidNames.length > 0) {
    throw new Error(`
The file names in the ${CODE_SET_DIR} directory should either be:

- a code set ("name.[ctv3|readv2|snomed|emis].txt")
- metadata ("name.[ctv3|readv2|snomed|emis].metadata.[txt|json]")
- or a readme ("README.md")

The following file names do not conform:\n\n${invalidNames.join('\n')}\n\n`);
  }

  return codeSetFiles;
}

/**
 * Validates and returns the version numbers for the code set
 * @param {string} codeSetType Such as "conditions", "medications" or "tests"
 * @param {*} codeSet Such as "hypertension", "methotrexate" or "ethnicity"
 */
function getCodeSetVersions(codeSetType, codeSetName) {
  const CODE_SET_DIR = join(CODE_SET_PARENT_DIR, codeSetType, codeSetName);
  // Should only be folders in the code set directory
  const files = readdirSync(CODE_SET_DIR, { withFileTypes: true }) // read all children of the CODE_SET_DIR
    .filter((item) => item.isFile()) // ..then filter to just files
    .map((file) => file.name); // ..then return the file name

  if (files && files.length > 0) {
    throw new Error(
      `There should only be directories in the ${CODE_SET_DIR} directory. However there appear to be the following files: ${files.join(
        ', '
      )}.`
    );
  }
  // Find clinical code sets versions
  const codeSetVersions = readdirSync(CODE_SET_DIR, { withFileTypes: true }) // read all children of the CODE_SET_DIR
    .filter((item) => item.isDirectory()) // ..then filter to just directories
    .map((dir) => dir.name); // ..then return the folder name

  // Find any that don't conform to the naming convention
  const invalidNames = codeSetVersions.filter((codeSetVersion) => !isValidVersion(codeSetVersion));

  if (invalidNames.length > 0) {
    throw new Error(
      `The directory names in the ${CODE_SET_DIR} directory should all be numbers starting at 1. The following directory names do not conform:\n\n${invalidNames.join(
        '\n'
      )}\n\n`
    );
  }

  return codeSetVersions;
}

/**
 * Finds all examples of the particular code set type.
 * @param {string} codeSetType Such as "conditions", "medications" or "tests"
 */
function getClinicalCodeSets(codeSetType) {
  const CODE_SET_DIR = join(CODE_SET_PARENT_DIR, codeSetType);
  // Should only be folders in the code set directory
  const files = readdirSync(CODE_SET_DIR, { withFileTypes: true }) // read all children of the CODE_SET_DIR
    .filter((item) => item.isFile()) // ..then filter to just files
    .map((file) => file.name); // ..then return the file name

  if (files && files.length > 0) {
    throw new Error(
      `There should only be directories in the ${CODE_SET_DIR} directory. However there appear to be the following files: ${files.join(
        ', '
      )}.`
    );
  }
  // Find clinical code sets
  const clinicalCodeSets = readdirSync(CODE_SET_DIR, { withFileTypes: true }) // read all children of the CODE_SET_DIR
    .filter((item) => item.isDirectory()) // ..then filter to just directories
    .map((dir) => dir.name); // ..then return the folder name

  // Find any that don't conform to the naming convention
  const invalidNames = clinicalCodeSets.filter((codeSet) => !isValidCodeSet(codeSet));

  if (invalidNames.length > 0) {
    throw new Error(
      `The directory names in the ${CODE_SET_DIR} directory should be lower case, alphanumeric, with spaces replaced with "-"s. The following directory names do not conform:\n\n${invalidNames.join(
        '\n'
      )}\n\n`
    );
  }

  return clinicalCodeSets;
}

/**
 * Gets the clinical code set types. E.g. medications, diagnoses, tests etc..
 */
function getClinicalCodeSetTypes() {
  // Should only be folders in the code set directory
  const files = readdirSync(CODE_SET_PARENT_DIR, { withFileTypes: true }) // read all children of the CODE_SET_PARENT_DIR
    .filter((item) => item.isFile()) // ..then filter to just files
    .map((file) => file.name); // ..then return the file name

  if (files && files.length > 0) {
    throw new Error(
      `There should only be directories in the ${CODE_SET_PARENT_DIR} directory. However there appear to be the following files: ${files.join(
        ', '
      )}.`
    );
  }
  // Find type of clinical code sets
  return readdirSync(CODE_SET_PARENT_DIR, { withFileTypes: true }) // read all children of the CODE_SET_PARENT_DIR
    .filter((item) => item.isDirectory()) // ..then filter to just directories
    .map((dir) => dir.name); // ..then return the folder name
}

/**
 * Tests that the version directory is a non-zero padded number
 * @param {sting} version
 */
function isValidVersion(version) {
  return version.match(/^[1-9][0-9]*$/);
}

/**
 * Tests that the code set directory is like "atrial-fibrillation" or "type-2-diabetes"
 * @param {sting} codeSet
 */
function isValidCodeSet(codeSet) {
  return codeSet.match(/^[a-z][a-z0-9-]*[a-z0-9]$/);
}

/**
 * Tests that the code set filename is valid
 * @param {sting} version
 */
function isValidCodeSetFile(codeSet) {
  return codeSet.match(/\.(ctv3|emis|readv2|snomed)\.txt$/);
}

/**
 * Tests that the code set metadata filename is valid
 * @param {sting} codeSet
 */
function isValidCodeSetMetadataFile(codeSet) {
  return (
    codeSet.match(/\.(ctv3|emis|readv2|snomed)\.metadata\.(txt|json)$/) || codeSet === 'README.md'
  );
}

/**
 * Tests that the code set ignore files are valid
 * @param {sting} codeSet
 */
function isValidIgnoreFile(codeSet) {
  return codeSet.match(/^\.ignore/);
}

/**
 * Tests that the code set data row is valid. Two fields tab separated.
 * @param {sting} version
 */
function isValidDataRow(row) {
  return row.match(/^[^\t]+\t[^\t]+$/);
}

function getReadMe(codeSet, version) {
  const codeSetTypes = getClinicalCodeSetTypes();
  for (let i = 0; i < codeSetTypes.length; i++) {
    if (existsSync(join(CODE_SET_PARENT_DIR, codeSetTypes[i], codeSet, version))) {
      const readmeFile = join(CODE_SET_PARENT_DIR, codeSetTypes[i], codeSet, version, 'README.md');
      if (existsSync(readmeFile)) {
        return {
          link: `${GITHUB_BASE_URL}/shared/clinical-code-sets/${codeSetTypes[i]}/${codeSet}/${version}`,
          linkName: `${GITHUB_REPO}/.../${codeSetTypes[i]}/${codeSet}/${version}`,
          file: readFileSync(readmeFile, 'utf8'),
        };
      } else {
        warn(
          `You are using version ${version} of the ${codeSet} code set, but that doesn't have a README.md file.`
        );
        return false;
      }
    }
  }
  warn(`The version ${version} of the ${codeSet} code set doesn't seem to exist.`);
  return false;
}

function getReadMes(codeSets) {
  return codeSets.map((x) => getReadMe(x.codeSet, x.version)).filter(Boolean);
}

module.exports = {
  evaluateCodeSets,
  createCodeSetSQL,
  getClinicalCodeSetTypes,
  getClinicalCodeSets,
  isValidCodeSet,
  createCodeSet,
  theCodeSetExists,
  getReadMes,
  getCodeSet,
};
