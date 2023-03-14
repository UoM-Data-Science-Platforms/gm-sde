/*
  The NHS publish GP utilization per locality. This includes how many appointments there
  were for each type (face-to-face, telephone etc..) and for each healthcare professional
  (GP, nurse etc..). This script simplifies the process of downloading each one.
*/
const {
  populateDateArray,
  getDataFileUrls,
  getDataFiles,
  unzipDataFiles,
  processDataFiles,
  combineFiles,
  // saveChunks,
  // combineChunks,
  // compressOutput,
  // validate,
} = require('./lib');

// Currently the earliest these go back to is October 2018
let startDate = new Date(2018, 9, 1);
let endDate = new Date();
const datesToGetDataFor = populateDateArray(startDate, endDate);

const instruction = process.argv[2];

if (instruction === 'download') {
  // Force a download of all zip files, overwriting the existing ones
  getDataFileUrls(datesToGetDataFor).then((fileUrls) => {
    getDataFiles(fileUrls, true);
  });
} else if (instruction === 'unzip') {
  //Unzip the existing zip files, overwriting the xlsx files
  unzipDataFiles(true);
} else if (instruction === 'process') {
  // Combine the file chunks into the output
  processDataFiles(true);
} else if (instruction === 'combine') {
  //   // Combine the file chunks into the output
  combineFiles();
} else {
  getDataFileUrls(datesToGetDataFor)
    .then(getDataFiles)
    .then(processDataFiles)
    .then(combineFiles)
    .catch((err) => {
      console.log(err);
    });
}
