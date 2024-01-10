const fs = require('fs');
const path = require('path');

const CODE_DIR = path.join(__dirname, '..', '..', 'shared', 'clinical-code-sets');
const codeCategories = fs.readdirSync(CODE_DIR);

const codeSets = [];

codeCategories.forEach((category) => {
  console.log(`> Doing all code sets under [${category}]`);
  const CAT_DIR = path.join(CODE_DIR, category);
  const codeSetNames = fs.readdirSync(CAT_DIR);

  codeSetNames.forEach((codeSetName) => {
    const CODE_SET_DIR = path.join(CAT_DIR, codeSetName);
    const versions = fs.readdirSync(CODE_SET_DIR);

    versions.forEach((version) => {
      const CODE_SET_VERSION_DIR = path.join(CODE_SET_DIR, version);
      const README = path.join(CODE_SET_VERSION_DIR, 'README.md');
      //66291
      if (fs.existsSync(README)) {
        const readme = fs.readFileSync(README, 'utf8');
        const header = readme.split('\n')[0];
        if (!header.match(/^# .+$/)) {
          console.log(
            `Header row in ${codeSetName} (version ${version}) is not of the format "# Heading". Skipping...`
          );
          return;
        }
        const readableName = header.substring(2);
        let readmeBits = readme
          .toLowerCase()
          .replace(/[\W_]+/g, ' ')
          .trim()
          .split(' ');
        readmeBits = [...new Set(readmeBits)];
        codeSets.push({
          category,
          codeSetName: codeSetName.split('-'),
          readmeBits,
          readableName,
          version,
        });
      }
      // TODO decide if we want to index the codes inside as well...
    });
  });
});

fs.writeFileSync(
  path.join(__dirname, '..', '..', 'gh-pages', 'code-set-readme.json'),
  JSON.stringify(codeSets, null, 2)
);
