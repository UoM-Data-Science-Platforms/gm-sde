/*
  The NHS publish population level statistics per practice. This includes the number of patients
  for each age and sex in each practice on a month by month basis. This script attempts to simplify
  the process of downloading the monthly spreadsheets
*/
const fs = require('fs');
const { join } = require('path');
const {
  populateDateArray,
  getDataFileUrls,
  getDataFiles,
  processDataFiles,
  combineFiles,
} = require('./lib');

// Currently the earliest these go back to is 2013
let startDate = new Date(2013, 0, 1);
let endDate = new Date();
const datesToGetDataFor = populateDateArray(startDate, endDate);

const instruction = process.argv[2];

if (instruction === 'download') {
  // Force a download of all files, overwriting the existing ones
  getDataFileUrls(datesToGetDataFor).then((fileUrls) => {
    getDataFiles(fileUrls, true);
  });
} else {
  getDataFileUrls(datesToGetDataFor)
    .then(getDataFiles)
    .then(processDataFiles)
    .then(combineFiles)
    .then((outputData) => {
      fs.writeFileSync(
        join(__dirname, 'output', 'gp-population-data-by-sex-and-age.csv'),
        'Year,Month,LocalityId,PracticeId,Sex,Age,Frequency\n' + outputData.join('\n')
      );
    })
    .catch((err) => {
      console.log(err);
    });
}

// TODO
/*
- Perform validation
  - practices that appear / disappear
  - counts don't change by more than x%
*/
