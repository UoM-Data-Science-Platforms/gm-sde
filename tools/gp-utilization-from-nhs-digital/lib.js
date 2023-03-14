const rp = require('request-promise');
const cheerio = require('cheerio');
const { join } = require('path');
const fs = require('fs');
const yauzl = require('yauzl');

const CACHED_DIR = join(__dirname, 'cached-data-files');
const OUTPUT_DIR = join(__dirname, 'output');

const months = [
  'january',
  'february',
  'march',
  'april',
  'may',
  'june',
  'july',
  'august',
  'september',
  'october',
  'november',
  'december',
];

// The codes for the 10 localities in Greater Manchester. Prior to 2023 these were called CCGs.
// NB prior to 2017, there was also Central Manchester (00W), North Manchester (01M) and South
// Manchester (01N). These 3 merged into just Manchester (14L) in early 2017.
const ccgs = [
  '01G',
  '00T',
  '01D',
  '02A',
  '01W',
  '00Y',
  '02H',
  '00V',
  '14L',
  '01Y',
  '00W',
  '01M',
  '01N',
];

const baseUrl =
  'https://digital.nhs.uk/data-and-information/publications/statistical/appointments-in-general-practice/';

function getDateParts(date) {
  const month = ('0' + (date.getMonth() + 1)).slice(-2); //numeric month (1-12) left padded with zeros (01, 02,...,12)
  const monthName = months[date.getMonth()];
  const monthCamelCase = monthName[0].toUpperCase() + monthName.slice(1);
  const year4chars = date.getFullYear();
  const year2chars = date.getYear();
  const day = date.getDate();
  return { month, year4chars, year2chars, monthName, monthCamelCase, day };
}

function dateStringForUrl(date) {
  const { monthName, year4chars } = getDateParts(date);
  return `${monthName}-${year4chars}`;
}

function readableMonthDate(date) {
  const { monthCamelCase, year4chars } = getDateParts(date);
  return `${monthCamelCase} ${year4chars}`;
}

function readableDate(date) {
  const { monthCamelCase, year4chars, day } = getDateParts(date);
  return `${day} ${monthCamelCase} ${year4chars}`;
}

function urlFromDate(date) {
  const dateString = dateStringForUrl(date);
  if (dateString === 'october-2018') return `${baseUrl}oct-2018`;
  if (dateString === 'july-2019') return `${baseUrl}jul-2019`;
  return `${baseUrl}${dateString}`;
}

function populateDateArray(startDate, endDate) {
  const dates = [];
  while (startDate < endDate) {
    dates.push(new Date(startDate));
    startDate.setMonth(startDate.getMonth() + 1);
  }
  return dates;
}

async function getDataFileUrls(datesToGetDataFor) {
  return Promise.all(
    datesToGetDataFor.map((date) =>
      rp({
        uri: urlFromDate(date),
        headers: {
          Origin: 'Request-promise',
        },
      })
        .then((html) => {
          var $ = cheerio.load(html);
          var url = $('a[href*="zip"]').attr('href');
          var publicationDateString = $('[data-uipath*="ps.publication.publication-date"]').text();
          var publicationDate = new Date(publicationDateString);
          return { date, url, publicationDate };
        })
        .catch(() => {
          // guess it doesn't exist
          console.log(
            `No data found for ${readableMonthDate(
              date
            )}. This is not necessarily an error as the data wasn't released on a monthly basis in the past.`
          );
        })
    )
  );
}

async function downloadFileIfNotAlready(uri, date, force) {
  const { month, year4chars } = getDateParts(date);
  const directory = join(CACHED_DIR, '' + year4chars);
  const rawDir = join(directory, 'raw');
  if (!fs.existsSync(CACHED_DIR)) {
    fs.mkdirSync(CACHED_DIR);
  }
  if (!fs.existsSync(directory)) {
    fs.mkdirSync(directory);
  }
  if (!fs.existsSync(rawDir)) {
    fs.mkdirSync(rawDir);
  }
  const rawFile = join(rawDir, `${year4chars}-${month}.zip`);
  if (fs.existsSync(rawFile) && !force) {
    console.log(`Data for ${readableMonthDate(date)} already exists.`);
  } else {
    if (fs.existsSync(rawFile)) {
      console.log(
        `Data for ${readableMonthDate(date)} already exists, but force=true, so let's get again.`
      );
    }
    console.log(`Loading data for ${readableMonthDate(date)} from NHS digital website...`);
    const dataToCache = await rp({ uri, encoding: null });
    fs.writeFileSync(rawFile, dataToCache);
    console.log('File saved to local cache.');
  }
}

async function getDataFiles(fileUrls, force) {
  fileUrls = fileUrls.filter(Boolean); // remove undefined for months where no data
  for (const { date, url, publicationDate } of fileUrls) {
    if (!url && (!publicationDate || publicationDate < new Date())) {
      console.log(
        `For ${readableMonthDate(
          date
        )} there appears to be no url. This is unexpected and the codes needs changing to accommodate this.`
      );
      process.exit(1);
    }
    if (!url) {
      console.log(
        `For ${readableMonthDate(date)}, the data will be published on ${readableDate(
          publicationDate
        )}`
      );
      continue;
    }

    await downloadFileIfNotAlready(url, date, force);
  }
}

async function unzipDataFiles(force) {
  const years = fs.readdirSync(CACHED_DIR).reverse();
  const filesAlreadyExtracted = {};
  for (const year of years) {
    const rawDir = join(CACHED_DIR, year, 'raw');
    const extractDir = join(CACHED_DIR, year, 'extracted');
    if (!fs.existsSync(rawDir)) {
      continue;
    }
    if (!fs.existsSync(extractDir)) {
      fs.mkdirSync(extractDir);
    }
    // As each zip contains files from many previous months, we
    // only want the most up to date. We therefore reverse the
    // files in a directory so that the most recent zip file
    // dominates.
    const files = fs.readdirSync(rawDir).sort().reverse();
    for (const rawFile of files) {
      await new Promise((resolve) => {
        let filesToExtract = 0;
        let isEnd = false;
        let isClose = false;
        if (
          [
            '2021-02.zip',
            '2021-03.zip',
            '2021-04.zip',
            '2021-05.zip',
            '2021-06.zip',
            '2021-07.zip',
            '2021-08.zip',
          ].indexOf(rawFile) > -1
        ) {
          // These files use a different syntax - easiest to just ignore
          // given each montly file contains data for multiple months.
          console.log(`Ignoring ${rawFile} for known issues`);
          return resolve();
        }
        console.log(`Processing ${join(rawDir, rawFile)}`);
        yauzl.open(join(rawDir, rawFile), { lazyEntries: true }, function (err, zipfile) {
          if (err) throw err;
          zipfile.readEntry();
          zipfile.on('end', () => {
            isEnd = true;
            if (filesToExtract === 0 && isClose) return resolve();
          });
          zipfile.on('close', () => {
            isClose = true;
            if (filesToExtract === 0 && isEnd) return resolve();
          });
          zipfile.on('entry', function (entry) {
            if (/\/$/.test(entry.fileName)) {
              // Directory file names end with '/'.
              // Note that entries for directories themselves are optional.
              // An entry's fileName implicitly requires its parent directories to exist.
              zipfile.readEntry();
            } else {
              // file entry
              if (entry.fileName.toLowerCase().indexOf('appointments_gp_coverage.csv') > -1) {
                zipfile.readEntry();
                return;
              }
              const fileNameMatch = entry.fileName.match(
                /(?:CCG|SUB_ICB_LOCATION)_CSV_([A-Za-z]{3})_?([0-9]{2})/
              );
              if (!fileNameMatch) {
                console.log(
                  `There is a file called ${entry.fileName} in the ${join(
                    rawDir,
                    rawFile
                  )} file which doesn't match with expectations.`
                );
                process.exit(1);
              }
              filesToExtract++;
              const [, actualMonth, actualYear] = fileNameMatch;
              const date = new Date(Date.parse(`01 ${actualMonth} ${actualYear}`));
              const { month, year4chars } = getDateParts(date);
              const outputFile = join(
                CACHED_DIR,
                date.getFullYear().toString(),
                'extracted',
                `${year4chars}-${month}-locality-utilization.csv`
              );
              if (
                (fs.existsSync(outputFile) && !force) ||
                (force && filesAlreadyExtracted[outputFile])
              ) {
                //console.log(`- ignoring ${entry.fileName} from ${rawFile} as already extracted.`);
                filesToExtract--;
                zipfile.readEntry();
                return;
              }
              if (!fs.existsSync(join(CACHED_DIR, year4chars.toString()))) {
                fs.mkdirSync(join(CACHED_DIR, year4chars.toString()));
              }
              if (!fs.existsSync(join(CACHED_DIR, year4chars.toString(), 'extracted'))) {
                fs.mkdirSync(join(CACHED_DIR, year4chars.toString(), 'extracted'));
              }
              zipfile.openReadStream(entry, function (err, readStream) {
                if (err) throw err;
                readStream.on('end', function () {
                  zipfile.readEntry();
                });
                const file = fs.createWriteStream(outputFile);
                file.on('close', () => {
                  filesAlreadyExtracted[outputFile] = true;
                  console.log(
                    `- extracted ${year4chars}-${month}-locality-utilization.csv from ${rawFile} (file name was ${entry.fileName})`
                  );
                  filesToExtract--;
                  if (filesToExtract === 0 && isEnd && isClose) return resolve();
                });
                readStream.pipe(file);
              });
            }
          });
        });
      });
    }
  }
}

const fileFormat = {
  format1: {
    name: 'format1',
    header:
      'sub_icb_location_code,sub_icb_location_ons_code,sub_icb_location_name,icb_ons_code,region_ons_code,appointment_date,appt_status,hcp_type,appt_mode,time_between_book_and_appt,count_of_appointments',
  },
  format2: {
    name: 'format2',
    header:
      'ccg_code,ccg_ons_code,ccg_name,stp_code,subregion_ons_code,region_ons_code,appointment_date,appt_status,hcp_type,appt_mode,time_between_book_and_appt,count_of_appointments',
  },
  format3: {
    name: 'format3',
    header:
      'ccg_code,ccg_ons_code,ccg_name,stp_code,regional_local_office_ons_code,region_ons_code,appointment_date,appt_status,hcp_type,appt_mode,time_between_book_and_appt,count_of_appointments',
  },
  format4: {
    name: 'format4',
    header:
      'ccg_code,ccg_ons_code,ccg_name,stp_ons_code,region_ons_code,appointment_date,appt_status,hcp_type,appt_mode,time_between_book_and_appt,count_of_appointments',
  },
  format5: {
    name: 'format5',
    header:
      'sub_icb_location_code,sub_icb_location_ons_code,sub_icb_location,icb_ons_code,region_ons_code,appointment_date,appt_status,hcp_type,appt_mode,time_between_book_and_appt,count_of_appointments',
  },
};

const modes = {
  'Face-to-Face': 'Face-to-Face',
  Telephone: 'Telephone',
  'Home Visit': 'Home Visit',
  Unknown: 'Unknown',
  'Video Conference/Online': 'Video Conference/Online',
};
const statuses = {
  Attended: 'Attended',
  DNA: 'DNA',
  Unknown: 'Unknown',
  'Appt Status Not Provided': 'Unknown',
};
const hcpTypes = {
  'HCP Type Not Provided': 'Unknown',
  GP: 'GP',
  Unknown: 'Unknown',
  'Other Practice staff': 'Other',
};

function processFile(fileData, year, month, fileName) {
  console.log(`Processing data for ${fileName}`);
  const rows = fileData.replace(/\r/g, '').split('\n');
  const header = rows[0];
  let format;
  switch (header.toLowerCase()) {
    case fileFormat.format1.header:
      format = fileFormat.format1.name;
      break;
    case fileFormat.format2.header:
      format = fileFormat.format2.name;
      break;
    case fileFormat.format3.header:
      format = fileFormat.format3.name;
      break;
    case fileFormat.format4.header:
      format = fileFormat.format4.name;
      break;
    case fileFormat.format5.header:
      format = fileFormat.format5.name;
      break;
    default:
      console.log(
        `For the single data file for ${fileName} the header row was unexpected:\n\n${header}`
      );
      process.exit(1);
  }

  const dataProcessed = {};
  rows
    .slice(1)
    .filter((x) => x.length > 5)
    .forEach((x) => {
      // Recent files have the following headings
      let [
        ccg,
        ,
        ,
        ,
        ,
        appointment_date,
        status,
        hcpType,
        mode,
        time_between_book_and_appt,
        count_of_appointments,
        extraCol1,
      ] = x.replace(/Heywood,/, 'Heywood').split(',');

      // // above is the same for format1, format4 and format5
      // // slight difference for format2, format3
      if (format === fileFormat.format2.name || format === fileFormat.format3.name) {
        appointment_date = status;
        status = hcpType;
        hcpType = mode;
        mode = time_between_book_and_appt;
        time_between_book_and_appt = count_of_appointments;
        count_of_appointments = extraCol1;
      }

      if (ccgs.indexOf(ccg) < 0) return;

      if (!modes[mode]) {
        console.log(
          `File ${fileName} has a mode that is new:\n\n"${mode}"\n\n\nPlease change the code to accommodate it.`
        );
        process.exit(1);
      }
      if (!statuses[status]) {
        console.log(
          `File ${fileName} has a status that is new:\n\n"${status}"\n\n\nPlease change the code to accommodate it.`
        );
        process.exit(1);
      }
      if (!hcpTypes[hcpType]) {
        console.log(
          `File ${fileName} has a hcpType that is new:\n\n"${hcpType}"\n\n\nPlease change the code to accommodate it.`
        );
        process.exit(1);
      }

      const day = appointment_date.slice(0, 2);

      if (!dataProcessed[year]) dataProcessed[year] = {};
      if (!dataProcessed[year][month]) dataProcessed[year][month] = {};
      if (!dataProcessed[year][month][day]) dataProcessed[year][month][day] = {};
      if (!dataProcessed[year][month][day][ccg]) dataProcessed[year][month][day][ccg] = {};
      if (!dataProcessed[year][month][day][ccg][modes[mode]])
        dataProcessed[year][month][day][ccg][modes[mode]] = {};
      if (!dataProcessed[year][month][day][ccg][modes[mode]][hcpTypes[hcpType]])
        dataProcessed[year][month][day][ccg][modes[mode]][hcpTypes[hcpType]] = {};
      if (!dataProcessed[year][month][day][ccg][modes[mode]][hcpTypes[hcpType]][statuses[status]])
        dataProcessed[year][month][day][ccg][modes[mode]][hcpTypes[hcpType]][statuses[status]] = 0;
      dataProcessed[year][month][day][ccg][modes[mode]][hcpTypes[hcpType]][
        statuses[status]
      ] += +count_of_appointments;
    });

  return dataProcessed;
}

function processDataFiles(force) {
  console.log('Processing files...');
  fs.readdirSync(CACHED_DIR).forEach((year) => {
    const extractedDir = join(CACHED_DIR, year, 'extracted');
    const processedDir = join(CACHED_DIR, year, 'processed');
    if (!fs.existsSync(extractedDir)) {
      console.log(
        `For the cached directory for ${year} there is no 'extracted' directory. This is unexpected.`
      );
      process.exit(1);
    }
    if (!fs.existsSync(processedDir)) {
      fs.mkdirSync(processedDir);
    }
    fs.readdirSync(extractedDir).forEach((extractedFile) => {
      const extractedFileStub = extractedFile.replace('.csv', '');
      const processedFile = join(processedDir, `${extractedFileStub}.json`);
      if (fs.existsSync(processedFile)) {
        if (force) {
          console.log(
            `The extracted file ${extractedFile} has already been processed, but force=true, so we process again.`
          );
        } else {
          console.log(
            `The extracted file ${extractedFile} has already been processed. Moving on...`
          );
          return;
        }
      }

      const [year, month] = extractedFileStub.split('-');
      const extractedData = fs.readFileSync(join(extractedDir, extractedFile), 'utf8');

      const data = processFile(extractedData, year, month, extractedFile);
      fs.writeFileSync(processedFile, JSON.stringify(data, null, 2));
    });
  });
}

function combineFiles() {
  console.log('Combining files...');
  const output = [
    'Year,Month,Day,LocalityId,AppointmentMode,HealthCareProfessionalType,Status,Frequency',
  ];
  fs.readdirSync(CACHED_DIR).forEach((year) => {
    const processedDir = join(CACHED_DIR, year, 'processed');
    if (!fs.existsSync(processedDir)) {
      console.log(
        `For the cached directory for ${year} there is no 'processed' directory. This is unexpected.`
      );
      process.exit(1);
    }
    fs.readdirSync(processedDir).forEach((processedFile) => {
      console.log(`Loading and combining the data from ${processedFile}`);
      const data = JSON.parse(fs.readFileSync(join(processedDir, processedFile)));
      const [year, month] = processedFile.replace('.json', '').split('-');
      Object.keys(data[year][month])
        .sort()
        .forEach((day) => {
          Object.keys(data[year][month][day]).forEach((ccg) => {
            Object.keys(data[year][month][day][ccg]).forEach((mode) => {
              Object.keys(data[year][month][day][ccg][mode]).forEach((hcpType) => {
                Object.keys(data[year][month][day][ccg][mode][hcpType]).forEach((status) => {
                  const count = data[year][month][day][ccg][mode][hcpType][status];
                  output.push(
                    `${year},${+month},${+day},${ccg},${mode},${hcpType},${status},${count}`
                  );
                });
              });
            });
          });
        });
    });
  });
  fs.writeFileSync(join(OUTPUT_DIR, 'gp-utlization-data-by-ccg.csv'), output.join('\n'));
}

module.exports = {
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
};
