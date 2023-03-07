const { nationalStitch } = require('./generate-sql');
const clear = require('clear');
clear();

nationalStitch(process.cwd()).then(() => {
  process.exit();
});
