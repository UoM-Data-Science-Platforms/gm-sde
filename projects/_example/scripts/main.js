const msRestNodeAuth = require('@azure/ms-rest-nodeauth');
const { Connection, Request } = require('tedious');
const inquirer = require('inquirer');
const {
  readdirSync,
  readFileSync,
  createWriteStream,
  writeFileSync,
  existsSync,
  rmdirSync,
  mkdirSync,
} = require('fs');
const { join } = require('path');
const Stream = require('stream');
const chalk = require('chalk');
require('clear')();
const { version } = require('./package.json');

const EXTRACTION_DIR = join(__dirname, '..', 'extraction-sql');
const OUTPUT_DIR = join(__dirname, '..', 'output-for-analysts');
const store = {};

// Catch any attempt to kill the process e.g. CTRL-C / CMD-C and exit gracefully
process.kill = () => {
  process.stdout.write('\n\n');
  log('Exiting... Goodbye!');
  process.exit();
};

confirmClearOutputDirectory()
  .then(getQueriesToRun)
  .then(getQueryContent)
  .then(executeSql)
  .then(() => {
    console.log(
      chalk.yellowBright(`
All data files have now been written. You can now copy the contents of the directory:

${OUTPUT_DIR}

to the study shared folder. This will have the form ${chalk.cyanBright(
        'gmcr-rqxxx-name'
      )} and be located under ${chalk.cyanBright('This PC')} in ${chalk.cyanBright(
        'File Explorer'
      )}.
		`)
    );
  })
  .catch((err) => {
    log('An error occurred.');
    log(err.message);
    log(err);
  });

function executeSql(sqlFiles) {
  console.log(`
You're about to execute the following files:

${chalk.bold(sqlFiles.map((x) => x.filename).join('\n'))}
	
First you need to be authenticated.
`);
  return authenticate().then(() => Promise.all(sqlFiles.map(executeSqlFile)));
}

function executeSqlFile(sqlFile) {
  return doQuery(sqlFile);
}

/**
 * Authenticate with Azure via multi-factor authentication
 * @returns {Promise}
 */
function authenticate() {
  return msRestNodeAuth
    .interactiveLoginWithAuthResponse({ tokenAudience: 'https://database.windows.net/' })
    .then(({ credentials }) => credentials.getToken())
    .then(saveTokens);
}

function getQueryContent(files) {
  return files.map((file) => ({
    filename: file,
    sql: readFileSync(join(EXTRACTION_DIR, file), 'utf8'),
  }));
}

function confirmClearOutputDirectory() {
  if (!existsSync(OUTPUT_DIR)) {
    createDirectoryStructure();
    return Promise.resolve();
  }
  console.log(
    chalk.bold(`This will first empty the output directory:

${chalk.green(OUTPUT_DIR)}
`)
  );
  return inquirer
    .prompt([
      {
        type: 'confirm',
        name: 'isClearOK',
        message: `Is that ok?`,
        default: false,
      },
    ])
    .then(({ isClearOK }) => {
      if (isClearOK) {
        createDirectoryStructure();
        return true;
      }
      console.log('Ok. Goodbye.');
      process.exit(0);
    });
}

/**
 * Select which SQL queries to execute
 * @returns {Promise}
 */
function getQueriesToRun() {
  const files = readdirSync(EXTRACTION_DIR).filter((x) => x.match(/.+\.sql$/));
  return runAllOrSome().then((shouldRunAll) => {
    if (shouldRunAll) return files;
    return inquirer
      .prompt([
        {
          type: 'checkbox',
          name: 'sql',
          message: 'Which files do you want to execute?',
          choices: files,
          validate: (input) => input.length > 0,
        },
      ])
      .then(({ sql }) => sql);
  });
}

/**
 * CLI prompt to get whether to run all or just some SQL files
 * @returns {Promise}
 */
function runAllOrSome() {
  const choices = {
    RUN_ALL: 'Execute all SQL files',
    RUN_SOME: 'Execute some SQL files (can choose which ones next)',
  };
  return inquirer
    .prompt([
      {
        type: 'list',
        name: 'choice',
        message: 'What do you want to do?',
        choices: Object.values(choices),
      },
    ])
    .then(({ choice }) => {
      if (choice === choices.RUN_ALL) return true;
      return false;
    });
}

// Not used at present but this is how to obtain a new accessToken from the refreshToken
// const msal = require('@azure/msal-node');
// function refresh() {
//   const pca = new msal.ClientApplication();
// 	return pca
//     .acquireTokenByRefreshToken({ refreshToken: store.refreshToken })
// 		.then(saveTokens);
// }

/**
 * Persist the access/refresh tokens for future requests
 * @param {Object} token
 */
function saveTokens({ refreshToken, accessToken, expiresOn }) {
  if (refreshToken) store.refreshToken = refreshToken;
  store.accessToken = accessToken;
  store.expiresOn = expiresOn;
}

/**
 * Take an SQL file, execute against the database, and write
 * to an output file
 * @param {Object} config filename, sql
 * @returns {Promise}
 */
function doQuery({ filename, sql }) {
  log(`Executing ${filename}...`);
  return new Promise((resolve) => {
    const outputStream = createWriteStream(join(OUTPUT_DIR, 'data', 'raw', `${filename}.txt`));
    const readable = new Stream.Readable({
      read(size) {
        return !!size;
      },
    });
    readable.pipe(outputStream);

    outputStream.on('finish', () => {
      log(`${filename} - Output written. All Done!`);
      return resolve();
    });

    const connection = new Connection({
      server: 'GM-ccbi-live-01.database.windows.net',
      authentication: {
        type: 'azure-active-directory-access-token',
        options: { token: store.accessToken },
      },
      options: { encrypt: true, database: 'HDM_Research' },
    });

    connection.on('connect', (err) => {
      if (err) {
        logError(`Connection Failed for ${filename}`);
        throw err;
      }

      executeStatement();
    });

    connection.connect();

    function executeStatement() {
      const request = new Request(sql, (err) => {
        if (err) {
          throw err;
        }
        connection.close();
        log(filename + ' request done');
        readable.push(null);
      });

      request.setTimeout(0);

      // Pipe the rows to the output stream
      request.on('row', (columns) => {
        const row = [];
        columns.forEach((column) => {
          if (column.value === null) {
            row.push('NULL');
          } else if (column.value.toISOString) {
            row.push(column.value.toISOString().substr(0, 10));
          } else {
            row.push(column.value);
          }
        });
        readable.push(row.join(',') + '\n');
      });

      // Add the header row from the column metadata
      request.on('columnMetadata', (columns) => {
        readable.push(
          columns
            .map((column, i) => {
              if (!column.colName) {
                logWarning(
                  `${filename} doesn't have a name for the ${nth(
                    i + 1
                  )} column. Please make sure the final SELECT statement has an "AS COLUMN_NAME" for this column.`
                );
                return '';
              }
              return column.colName;
            })
            .join(',') + '\n'
        );
      });

      request.on('doneInProc', (rowCount) => {
        if (rowCount || rowCount === 0) {
          log(chalk.bold(`${filename} has completed. ${rowCount} rows were returned.`));
        }
      });

      connection.execSql(request);
    }
  });
}

function createDirectoryStructure() {
  console.log(
    chalk.bold(`
Creating the output directory structure...`)
  );
  if (existsSync(OUTPUT_DIR)) {
    rmdirSync(OUTPUT_DIR, { recursive: true });
  }
  if (existsSync(OUTPUT_DIR)) {
    console.log(
      chalk.bold(`
Failed. This usually means you have a file open from within the output directory:

${chalk.green(OUTPUT_DIR)}

Please close any files and try again.`)
    );
    process.exit(0);
  }
  mkdirSync(OUTPUT_DIR);
  mkdirSync(join(OUTPUT_DIR, 'code'));
  mkdirSync(join(OUTPUT_DIR, 'data'));
  mkdirSync(join(OUTPUT_DIR, 'data', 'raw'));
  mkdirSync(join(OUTPUT_DIR, 'data', 'processed'));
  mkdirSync(join(OUTPUT_DIR, 'doc'));
  mkdirSync(join(OUTPUT_DIR, 'output'));
  mkdirSync(join(OUTPUT_DIR, 'output', 'approved'));
  mkdirSync(join(OUTPUT_DIR, 'output', 'check'));
  mkdirSync(join(OUTPUT_DIR, 'output', 'export'));
  writeReadme();
  console.log(
    chalk.bold(`Done.
`)
  );
}

function writeReadme() {
  writeFileSync(
    join(OUTPUT_DIR, '_README_FIRST.txt'),
    `* Data from the RDEs will be in the data/raw folder. Do not edit the contents of this folder.

* Data that you have processed through your scripts goes in the data/processed folder.

* Code goes in the 'code' folder.

* ***For any summary data or figures that you wish to export you MUST conform to the following:

  1. Files for export should first be placed in the output/check folder.
  2. They should then be checked by another analyst for disclosure control risk. 
  3. Once approved by another analyst they should then be placed in the output/approved folder. 
  4. When files are exported from the VDE they should be placed in a subdirectory of output/export with a datestamp prior to copying off the machine.

E.g. the folder structure will look as follows:

output
  |- export
      |- 2021-05-12
      |   |- file1.png
      |   |- file2.png
      |   |- file3.txt
      |- 2021-06-30
      |   |- fileA.png
      |   |- fileB.csv

Files should not be deleted from the 'output/export' folder***

* Anything else (e.g. documentation that is not code) goes in the 'doc' folder.

v${version}`
  );
}

/**
 * Converts 1, 2, 3... into 1st, 2nd, 3rd etc..
 * @param {Number} n The number to nth
 * @returns {String}
 */
function nth(n) {
  if (n % 100 === 11 || n % 100 === 12 || n % 100 === 13) return `${n}th`;
  if (n % 10 === 1) return `${n}st`;
  if (n % 10 === 2) return `${n}nd`;
  if (n % 10 === 3) return `${n}rd`;
  return `${n}th`;
}

function log(message) {
  console.log(`${chalk.blueBright(timestamp())}: ${message}`);
}

function logError(message) {
  console.log(`${chalk.blueBright(timestamp())}: ${chalk.white.bgRed.bold(message)}`);
}

function logWarning(message) {
  console.log(`${chalk.blueBright(timestamp())}: ${chalk.yellow(message)}`);
}

/**
 * Timestamp in format YYYY-MM-DDThh:mm:ss.nnn"
 * @returns {String} Timestamp
 */
function timestamp() {
  return new Date().toISOString().substr(0, 23);
}
