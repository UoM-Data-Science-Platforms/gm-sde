const chalk = require('chalk');

let isSilent = false;
const log = (msg) => {
  if (!isSilent) console.log(msg);
};

const warn = (msg) => {
  if (!isSilent) console.log(chalk.yellow(msg));
};

const error = (msg) => {
  console.log(chalk.white.bgRed.bold(msg));
};

const setSilence = (shouldBeSilent) => {
  isSilent = shouldBeSilent;
};

const getSilence = () => isSilent;

module.exports = { log, warn, error, setSilence, getSilence };
