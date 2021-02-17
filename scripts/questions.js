const { evaulateCodeSets, createCodeSetSQL} = require('./code-sets');
const inquirer =require('inquirer');

const choices = {
  CREATE_SQL: 'Create SQL from a template',
  EVALUATE_CODE_SETS: 'Evaluate the existing code sets',
  CODE_SET_SQL: 'Create the clinical code set reusable SQL',
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
    case choices.CREATE_SQL:
      console.log('create sql');
      break;
    case choices.EVALUATE_CODE_SETS:
      await evaulateCodeSets();
      break;
    case choices.CODE_SET_SQL:
      await createCodeSetSQL()
      break;
    default:
      console.log('You seem to have selected something that I wasn\'t expecting');
  }
}

module.exports = { initialMenu };