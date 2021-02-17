const { initialMenu } = require('./questions');

async function start() {
  const initialAction = await initialMenu();
}

start()
  .then(() => console.log('Goodbye!'))
  .catch((err)=> {
    console.log(err.message);
  });
