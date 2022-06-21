const fs = require('fs');
const { join } = require('path');
const rp = require('request-promise');
const cheerio = require('cheerio');
const yauzl = require('yauzl');
const xlsx = require('node-xlsx');
const { parse } = require('csv-parse/sync');

const URL_ROOT = 'https://www.nhsbsa.nhs.uk';
const RESOURCE_DIR = join(__dirname, '..', 'resources');
const MAPPING_DIR = join(RESOURCE_DIR, 'mappings');
const bnfHierarchyVersion = '20220501_1651411051526_BNF_Code_Information';
const BNF_FILE = join(RESOURCE_DIR, 'hierarchies', `${bnfHierarchyVersion}.csv`);
// An attempt to generate lists of snomed codes from BNF chapters

// BNF code hierarchy behind a guest login
// https://applications.nhsbsa.nhs.uk/infosystems/data/downloadAvailableReport.zip?requestId=REQ0068519

// Method to get the latest BNF-SNOMED mapping
// Assumes this page exists: https://www.nhsbsa.nhs.uk/prescription-data/understanding-our-data/bnf-snomed-mapping
// And contains a link to a zip file like this: /sites/default/files/2022-05/BNF%20Snomed%20Mapping%20data%2020220516.zip
async function getLatestMappingFileLink() {
  console.log('Getting html from nhsbsa...');
  return rp({
    uri: `${URL_ROOT}/prescription-data/understanding-our-data/bnf-snomed-mapping`,
    headers: {
      Origin: 'Request-promise',
    },
  }).then((html) => {
    const zipLinks = cheerio
      .load(html)('a')
      .toArray()
      .map((x) => x.attribs.href)
      .filter((x) => x.endsWith('.zip'))
      .map((x) => {
        const bits = x.split('/');
        const name = decodeURI(bits[bits.length - 1]);
        const dateBits = name.match(/([0-9]{8})/g);
        if (dateBits && dateBits[0]) {
          const date = new Date(
            dateBits[0].substr(0, 4),
            dateBits[0].substr(4, 2) - 1,
            dateBits[0].substr(6, 2)
          );
          return { url: x, name, date };
        }
        return false;
      })
      .filter(Boolean)
      .sort((a, b) => b.date - a.date);
    console.log('\tHtml retrieved.');
    console.log(
      'Latest BNF-SNOMED mapping is from:',
      zipLinks[0].date.toISOString().substring(0, 10)
    );
    return zipLinks[0];
  });
}

function getBNFHierarchy() {
  const records = parse(fs.readFileSync(BNF_FILE, 'utf-8').replace(/\r/g, ''), {
    columns: true,
    skip_empty_lines: true,
  });
  const bnf = {};
  const all = {};
  const freq = {};
  // Check necessary columns
  const cName = {
    Chpt: 'BNF Chapter',
    ChptCode: 'BNF Chapter Code',
    Sec: 'BNF Section',
    SecCode: 'BNF Section Code',
    Para: 'BNF Paragraph',
    ParaCode: 'BNF Paragraph Code',
    SubPara: 'BNF Subparagraph',
    SubParaCode: 'BNF Subparagraph Code',
    Chem: 'BNF Chemical Substance',
    ChemCode: 'BNF Chemical Substance Code',
    Prod: 'BNF Product',
    ProdCode: 'BNF Product Code',
    Pres: 'BNF Presentation',
    PresCode: 'BNF Presentation Code',
  };
  Object.values(cName).forEach((column) => {
    if (!records[0][column]) {
      console.log(
        `The BNF hierarchy csv should have a ${column} column, but it seems to be missing.`
      );
      process.exit();
    }
  });
  /*
  {
  "BNF Chapter": "Gastro-Intestinal System",
  "BNF Chapter Code": "1",
  "BNF Section": "Dyspepsia and gastro-oesophageal reflux disease",
  "BNF Section Code": "101",
  "BNF Paragraph": "Antacids and simeticone",
  "BNF Paragraph Code": "10101",
  "BNF Subparagraph": "Antacids and simeticone",
  "BNF Subparagraph Code": "101010",
  "BNF Chemical Substance": "Other antacid and simeticone preparations",
  "BNF Chemical Substance Code": "10101000",
  "BNF Product": "Proprietary compound preparation BNF 0101010",
  "BNF Product Code": "010101000BB",
  "BNF Presentation": "Indigestion mixture",
  "BNF Presentation Code": "010101000BBAJA0"
}
   */
  records.forEach((record) => {
    if (record[cName.Para].toLowerCase().indexOf('dummy para') > -1) return;
    // Guard against sci notation which happens if you open and save the csv file
    if (
      record[cName.ChptCode].match(/e[+-]/gi) ||
      record[cName.SecCode].match(/e[+-]/gi) ||
      record[cName.ParaCode].match(/e[+-]/gi) ||
      record[cName.ChemCode].match(/e[+-]/gi) ||
      record[cName.ProdCode].match(/e[+-]/gi)
    ) {
      console.log(`The following record contains scientific notation:
${JSON.stringify(record, null, 2)}

This is usually because the bnf hierarchy csv has been opened in excel and saved.`);
      process.exit();
    }

    if (!all[record[cName.ChptCode]]) {
      all[record[cName.ChptCode]] = { name: record[cName.Chpt], children: new Set() };
    }
    if (!all[record[cName.SecCode]]) {
      all[record[cName.SecCode]] = { name: record[cName.Sec], children: new Set() };
    }
    if (!all[record[cName.ParaCode]]) {
      all[record[cName.ParaCode]] = { name: record[cName.Para], children: new Set() };
    }
    if (!all[record[cName.SubParaCode]]) {
      all[record[cName.SubParaCode]] = { name: record[cName.SubPara], children: new Set() };
    }
    if (!all[record[cName.ChemCode]]) {
      all[record[cName.ChemCode]] = { name: record[cName.Chem], children: new Set() };
    }
    if (!all[record[cName.ProdCode]]) {
      all[record[cName.ProdCode]] = { name: record[cName.Prod], children: new Set() };
    }
    if (!all[record[cName.PresCode]]) {
      all[record[cName.PresCode]] = { name: record[cName.Pres], children: new Set() };
    }

    all[record[cName.ChptCode]].children.add(record[cName.SecCode]);
    all[record[cName.SecCode]].children.add(record[cName.ParaCode]);
    all[record[cName.ParaCode]].children.add(record[cName.SubParaCode]);
    all[record[cName.SubParaCode]].children.add(record[cName.ChemCode]);
    all[record[cName.ChemCode]].children.add(record[cName.ProdCode]);
    all[record[cName.ProdCode]].children.add(record[cName.PresCode]);

    // const bnfChapterCode = record[cName.ChptCode];
    // if (!bnf[bnfChapterCode]) {
    //   bnf[bnfChapterCode] = { name: record[cName.Chpt] };
    // }
    // const bnfSectionCode = record[cName.SecCode].replace(bnfChapterCode, '');
    // if (!bnf[bnfChapterCode][bnfSectionCode]) {
    //   bnf[bnfChapterCode][bnfSectionCode] = { name: record[cName.Sec] };
    // }
    // const bnfParagraphCode = record[cName.ParaCode].replace(record[cName.SecCode], '');
    // if (!bnf[bnfChapterCode][bnfSectionCode][bnfParagraphCode]) {
    //   bnf[bnfChapterCode][bnfSectionCode][bnfParagraphCode] = {
    //     name: record[cName.Para],
    //   };
    // }
    // const bnfSubParagraphCode = record[cName.SubParaCode].replace(record[cName.ParaCode], '');
    // if (!bnf[bnfChapterCode][bnfSectionCode][bnfParagraphCode][bnfSubParagraphCode]) {
    //   bnf[bnfChapterCode][bnfSectionCode][bnfParagraphCode][bnfSubParagraphCode] = {
    //     name: record[cName.SubPara],
    //   };
    // }
    // const bnfChemicalCode = record[cName.ChemCode].replace(record[cName.SubParaCode], '');
    // if (
    //   !bnf[bnfChapterCode][bnfSectionCode][bnfParagraphCode][bnfSubParagraphCode][bnfChemicalCode]
    // ) {
    //   bnf[bnfChapterCode][bnfSectionCode][bnfParagraphCode][bnfSubParagraphCode][
    //     bnfChemicalCode
    //   ] = {
    //     name: record[cName.Chem],
    //   };
    // }
    // const bnfProductCode = record[cName.ProdCode].replace(record[cName.ChemCode], '');
    // if (
    //   !bnf[bnfChapterCode][bnfSectionCode][bnfParagraphCode][bnfSubParagraphCode][bnfChemicalCode][
    //     bnfProductCode
    //   ]
    // ) {
    //   bnf[bnfChapterCode][bnfSectionCode][bnfParagraphCode][bnfSubParagraphCode][bnfChemicalCode][
    //     bnfProductCode
    //   ] = {
    //     name: record[cName.Prod],
    //     products: [
    //       {
    //         name: record[cName.Pres],
    //         code: record[cName.PresCode],
    //       },
    //     ],
    //   };
    // } else {
    //   bnf[bnfChapterCode][bnfSectionCode][bnfParagraphCode][bnfSubParagraphCode][bnfChemicalCode][
    //     bnfProductCode
    //   ].products.push({
    //     name: record[cName.Pres],
    //     code: record[cName.PresCode],
    //   });
    // }

    // Text analysis
    if (record[cName.Chpt])
      record[cName.Chpt]
        .toLowerCase()
        .replace(/-/gi, '')
        .split(' ')
        .forEach((word) => {
          if (!freq[word]) {
            freq[word] = new Set();
          }
          freq[word].add(record[cName.ChptCode]);
        });
    if (record[cName.Sec])
      record[cName.Sec]
        .toLowerCase()
        .replace(/-/gi, '')
        .split(' ')
        .forEach((word) => {
          if (!freq[word]) {
            freq[word] = new Set();
          }
          freq[word].add(record[cName.SecCode]);
        });
    if (record[cName.Para])
      record[cName.Para]
        .toLowerCase()
        .replace(/-/gi, '')
        .split(' ')
        .forEach((word) => {
          if (!freq[word]) {
            freq[word] = new Set();
          }
          freq[word].add(record[cName.ParaCode]);
        });
    if (record[cName.SubPara])
      record[cName.SubPara]
        .toLowerCase()
        .replace(/-/gi, '')
        .split(' ')
        .forEach((word) => {
          if (!freq[word]) {
            freq[word] = new Set();
          }
          freq[word].add(record[cName.SubParaCode]);
        });
    if (record[cName.Chem])
      record[cName.Chem]
        .toLowerCase()
        .replace(/-/gi, '')
        .split(' ')
        .forEach((word) => {
          if (!freq[word]) {
            freq[word] = new Set();
          }
          freq[word].add(record[cName.ChemCode]);
        });
    if (record[cName.Prod])
      record[cName.Prod]
        .toLowerCase()
        .replace(/-/gi, '')
        .split(' ')
        .forEach((word) => {
          if (!freq[word]) {
            freq[word] = new Set();
          }
          freq[word].add(record[cName.ProdCode]);
        });
    if (record[cName.Pres])
      record[cName.Pres]
        .toLowerCase()
        .replace(/-/gi, '')
        .split(' ')
        .forEach((word) => {
          if (!freq[word]) {
            freq[word] = new Set();
          }
          freq[word].add(record[cName.PresCode]);
        });
  });

  displayMatches(freq, all, 'antidepressant');
  // Sort the words by frequency
}

function displayMatches(freq, all, word) {
  const normaliseWord = word.toLowerCase().replace(/-/gi, '');
  if (freq[normaliseWord]) {
    const matches = Array.from(freq[normaliseWord]);
    console.log(
      matches
        .map((x) => {
          if (all[x]) return '             '.slice(0, x.length - 2) + all[x].name;
        })
        .join('\n')
    );
  }
}

async function downloadZipFile({ url, name }) {
  const zipFileLocation = join(MAPPING_DIR, name);
  if (fs.existsSync(zipFileLocation)) {
    console.log(`Mapping zip file already exists:\n\t${zipFileLocation}`);
    return zipFileLocation;
  }
  console.log('Downloading zip file...');

  return rp({
    uri: `${URL_ROOT}${url}`,
    method: 'GET',
    encoding: 'binary', // it also works with encoding: null
    headers: {
      'Content-type': 'application/zip',
    },
  }).then(function (body) {
    return new Promise((resolve) => {
      let writeStream = fs.createWriteStream(zipFileLocation);
      writeStream.write(body, 'binary');
      writeStream.on('finish', () => {
        console.log(`Zip file downloaded:\n\t${zipFileLocation}`);
        resolve(zipFileLocation);
      });
      writeStream.end();
    });
  });
}

async function parseMapppingFile(filename) {
  let xlsxFile;
  const jsonFileName = filename.replace('.zip', '.json');
  if (fs.existsSync(jsonFileName)) {
    console.log(`JSON file already exists:\n\t${jsonFileName}`);
    return JSON.parse(fs.readFileSync(jsonFileName, 'utf8'));
  }
  return new Promise((resolve) => {
    yauzl.open(filename, { lazyEntries: true }, function (err, zipfile) {
      if (err) throw err;
      zipfile.readEntry();
      zipfile.on('close', () => {
        console.log('Xlsx file extracted. Parsing...');
        // Read the xlsx file
        const workSheetsFromFile = xlsx.parse(xlsxFile);
        console.log('Xlsx file parsed.');
        // Check data
        if (workSheetsFromFile.length !== 1) {
          console.log(`Error: expected 1 worksheet, got ${workSheetsFromFile.length}`);
          process.exit();
        }
        if (workSheetsFromFile[0].data.length < 300000) {
          console.log(
            `Error: expected at least 300000 rows, got ${workSheetsFromFile[0].data.length}`
          );
          process.exit();
        }
        const headerRow = workSheetsFromFile[0].data.shift();
        if (headerRow.indexOf('BNF Code') === -1) {
          console.log('Error: expected header row to contain "BNF Code"');
          process.exit();
        }
        if (headerRow.indexOf('SNOMED Code') === -1) {
          console.log('Error: expected header row to contain "SNOMED Code"');
          process.exit();
        }
        if (headerRow.indexOf('BNF Name') === -1) {
          console.log('Error: expected header row to contain "BNF Name"');
          process.exit();
        }
        const bnfCodeIndex = headerRow.indexOf('BNF Code');
        const snomedCodeIndex = headerRow.indexOf('SNOMED Code');
        const bnfNameIndex = headerRow.indexOf('BNF Name');
        const strength = headerRow.indexOf('Strength');
        const unitOfMeasure = headerRow.indexOf('Unit Of Measure');
        const packSize = headerRow.indexOf('Pack');

        const mapping = workSheetsFromFile[0].data.map((row) => {
          const item = {
            bnfCode: row[bnfCodeIndex],
            snomedCode: row[snomedCodeIndex],
            bnfName: row[bnfNameIndex],
          };

          // Strength, unit of measure and pack size are optional
          if (row[strength]) item.strength = row[strength];
          if (row[unitOfMeasure]) item.unitOfMeasure = row[unitOfMeasure];
          if (row[packSize]) item.packSize = row[packSize];

          return item;
        });

        // write to json file
        fs.writeFileSync(jsonFileName, JSON.stringify(mapping, null, 2));

        return resolve(mapping);
      });
      zipfile.on('entry', function (entry) {
        console.log(`Found file: ${entry.fileName}\n\tUnzipping...`);
        if (/\/$/.test(entry.fileName)) {
          // Directory file names end with '/'.
          // Note that entires for directories themselves are optional.
          // An entry's fileName implicitly requires its parent directories to exist.
          zipfile.readEntry();
        } else {
          // file entry
          zipfile.openReadStream(entry, function (err, readStream) {
            if (err) throw err;
            readStream.on('end', function () {
              zipfile.readEntry();
            });
            xlsxFile = join(MAPPING_DIR, entry.fileName);
            const writer = fs.createWriteStream(xlsxFile);
            readStream.pipe(writer);
          });
        }
      });
    });
  });
}

getBNFHierarchy();
// getLatestMappingFileLink()
//   .then(downloadZipFile)
//   .then(parseMapppingFile)
//   .then((mapping) => {
//     console.log(mapping.slice(0, 10));
//   });
