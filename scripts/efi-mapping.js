// This is a one-off script to generate SNOMED lists for all the EFI code sets
//
// EFI currently only has Readv2 and CTV3 code sets. This is what is implemented
// in any system that calculates EFI. In order to be consistent with what exists
// in GP practices, we keep the Readv2 and CTV3 codes and do not attempt to
// validate them. However, now that all codes in the database are SNOMED, we need
// a way to generate the equivalent SNOMED code sets. Therefore we use the NHS
// mapping from Read and CTV to SNOMED. This script is therefore a one off process
// to create those files, but is retained here for transparency, and also in case
// a similar script is needed in future.

// Get all efi scripts
const fs = require('fs');
const { join } = require('path');

console.log('Loading lookup files...');
const ctv3ToSNOMED = {};
fs.readFileSync(
  join(__dirname, '..', 'shared', 'terminology-mapping', 'ctv3sctmap2_uk_20200401000001.txt'),
  'utf8'
)
  .split('\n')
  .slice(1)
  .map((x) => {
    const [mapId, code, termId, termType, conceptId] = x.split('\t');
    if (conceptId === '_DRUG') return;
    if (!ctv3ToSNOMED[code]) ctv3ToSNOMED[code] = [conceptId];
    else ctv3ToSNOMED[code].push(conceptId);
  });
const readv2ToSNOMED = {};
fs.readFileSync(
  join(__dirname, '..', 'shared', 'terminology-mapping', 'rcsctmap2_uk_20200401000001.txt'),
  'utf8'
)
  .split('\n')
  .slice(1)
  .map((x) => {
    const [mapId, code, termId, conceptId] = x.split('\t');
    if (!readv2ToSNOMED[code]) readv2ToSNOMED[code] = [conceptId];
    else readv2ToSNOMED[code].push(conceptId);
  });
const SNOMED_DEFINITIONS = JSON.parse(
  fs.readFileSync(
    join(__dirname, '..', '..', 'nhs-snomed', 'files', 'processed', 'latest', 'defs-single.json'),
    'utf8'
  )
);

console.log('Processing EFI files...');
const CODE_SET_DIR = join(__dirname, '..', 'shared', 'clinical-code-sets');
fs.readdirSync(CODE_SET_DIR).forEach((dir) => {
  fs.readdirSync(join(CODE_SET_DIR, dir)).forEach((condition) => {
    if (condition.indexOf('efi') === 0) {
      const snomedCodes = {};
      fs.readFileSync(join(CODE_SET_DIR, dir, condition, '1', `${condition}.ctv3.txt`), 'utf8')
        .split('\n')
        .map((x) => {
          if (x.trim().length < 3) return;
          const [code] = x.trim().split('\t');
          if (!ctv3ToSNOMED[code]) {
            console.log(`No mapping for ctv3 code ${code} in ${condition}`);
          } else {
            ctv3ToSNOMED[code].forEach((conceptId) => {
              snomedCodes[conceptId] = true;
            });
          }
        });
      fs.readFileSync(join(CODE_SET_DIR, dir, condition, '1', `${condition}.readv2.txt`), 'utf8')
        .split('\n')
        .map((x) => {
          if (x.trim().length < 3) return;
          const [code] = x.trim().split('\t');
          if (!readv2ToSNOMED[code]) {
            console.log(`No mapping for readv2 code ${code} in ${condition}`);
          } else {
            readv2ToSNOMED[code].forEach((conceptId) => {
              snomedCodes[conceptId] = true;
            });
          }
        });
      fs.writeFileSync(
        join(CODE_SET_DIR, dir, condition, '1', `${condition}.snomed.txt`),
        Object.keys(snomedCodes)
          .map((x) => {
            if (!SNOMED_DEFINITIONS[x]) {
              console.log(`No defintion for ${x}`);
              process.exit();
            }
            return `${x}\t${SNOMED_DEFINITIONS[x]}`;
          })
          .join('\n')
      );
    }
  });
});
