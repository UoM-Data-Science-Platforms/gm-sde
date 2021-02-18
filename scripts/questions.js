const inquirer =require('inquirer');

const { evaulateCodeSets, createCodeSetSQL} = require('./code-sets');
const { generateReusableQueryDocs } = require('./docs');

const choices = {
  EVALUATE_CODE_SETS: 'Evaluate the existing code sets',
  CODE_SET_SQL: 'Create the clinical code set reusable SQL',
  SEP1: new inquirer.Separator(),
  DOCS: 'Generate documentation for the reusable SQL queries',
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
  
  switch(answer.action) {
    case choices.EVALUATE_CODE_SETS:
      await evaulateCodeSets();
      break;
    case choices.CODE_SET_SQL:
      await createCodeSetSQL()
      break;
    case choices.DOCS:
      await generateReusableQueryDocs()
      break;
    default:
      console.log('You seem to have selected something that I wasn\'t expecting');
  }
}

module.exports = { initialMenu };