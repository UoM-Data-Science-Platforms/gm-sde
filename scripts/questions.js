const inquirer = require('inquirer');
const chalk = require('chalk');

const {
  evaulateCodeSets,
  createCodeSet,
  createCodeSetSQL,
  getClinicalCodeSetTypes,
  getClinicalCodeSets,
  isValidCodeSet,
} = require('./code-sets');
const { createLtcSql } = require('./create-ltc-sql');
const { generateReusableQueryDocs } = require('./docs');

const choices = {
  EVALUATE_CODE_SETS: 'Evaluate the existing code sets',
  CREATE_CODE_SET: 'Create a new code set',
  CODE_SET_SQL: 'Create the clinical code set reusable SQL',
  LTC_SQL: 'Create the long-term conditions reusable SQL',
  SEP1: new inquirer.Separator(),
  DOCS: 'Generate documentation for the reusable SQL queries',
};

const getCodeSetName = async (codeSets) => {
  const { codeSetName } = await inquirer.prompt([
    {
      type: 'input',
      name: 'codeSetName',
      message: 'If you still want to add a code set please enter its name now',
    },
  ]);

  const formattedName = codeSetName.toLowerCase().trim().replace(/ +/g, '-');
  if (!isValidCodeSet(formattedName)) {
    console.log(
      chalk.red.bold(
        'That name is invalid. It must be lower case alphanumeric with spaces substituted with "-"s.'
      )
    );
    return await getCodeSetName(codeSets);
  }
  if (codeSets.indexOf(formattedName) > -1) {
    throw new Error('There is already a code set with that name.');
  }
  return formattedName;
};

const initCreateCodeSet = async () => {
  const { type } = await inquirer.prompt([
    {
      type: 'list',
      name: 'type',
      message: 'What type of code set do you want?',
      choices: getClinicalCodeSetTypes(),
    },
  ]);

  const codeSets = getClinicalCodeSets(type);

  console.log(`
We currently have the following code sets:

${codeSets.map((x) => ` ${chalk.cyan.bold(x)}`).join('\n')}
`);

  const codeSetName = await getCodeSetName(codeSets);

  createCodeSet(type, codeSetName);
};

const initialMenu = async () => {
  const answer = await inquirer.prompt([
    {
      type: 'list',
      name: 'action',
      message: 'What do you want to do?',
      choices: Object.values(choices),
    },
  ]);

  switch (answer.action) {
    case choices.EVALUATE_CODE_SETS:
      await evaulateCodeSets();
      break;
    case choices.CREATE_CODE_SET:
      await initCreateCodeSet();
      break;
    case choices.CODE_SET_SQL:
      await createCodeSetSQL();
      break;
    case choices.LTC_SQL:
      await createLtcSql();
      break;
    case choices.DOCS:
      await generateReusableQueryDocs();
      break;
    default:
      console.log("You seem to have selected something that I wasn't expecting");
  }
};

module.exports = { initialMenu };
