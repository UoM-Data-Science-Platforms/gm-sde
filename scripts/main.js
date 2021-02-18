const { initialMenu } = require('./questions');
const { stitch } = require('./generate-sql');
const { error } = require('./log');
const clear = require('clear');
clear();

async function start() {
  await initialMenu();
}

if (process.argv.length > 2 && process.argv[2] === 'stitch') {
  stitch(process.cwd());
  process.exit(0);
}

// Catch any attempt to kill the process e.g. CTRL-C / CMD-C and exit gracefully
process.kill = () => {
  process.stdout.write('\n\n');
  console.log('Exiting... Goodbye!');
  process.exit();
};

start()
  .then(() => console.log('Goodbye!'))
  .catch((err)=> {
    error(err.message);
  });
