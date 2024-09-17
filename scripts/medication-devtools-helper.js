var drugLowerCase = document.getElementById('input-word').value.toLowerCase();
var drugCapitalCase = drugLowerCase[0].toUpperCase() + drugLowerCase.slice(1);
var otherNames = [...document.querySelectorAll('.potential-word:has(.included)')]
  .map((x) => x.childNodes[0].nodeValue.trim())
  .sort();
var otherNamesString = otherNames.map((x) => x[0].toUpperCase() + x.slice(1)).join('/');
var dt = new Date().toISOString().substring(0, 10);

var snomedCodes = Object.entries(data.snomed.concepts)
  .map(([code, definition]) => {
    return `${code}\t${definition}`;
  })
  .join('\n');

var ctv3Codes = Object.entries(data.ctv3.concepts)
  .map(([code, definition]) => {
    return `${code}\t${definition}`;
  })
  .join('\n');

var readv2Codes = Object.entries(data.readv2.concepts)
  .map(([code, definition]) => {
    return `${code}\t${definition}`;
  })
  .join('\n');

var text = `# ${drugCapitalCase}

Any prescription of ${drugLowerCase}. Other names: ${otherNamesString}.

Code set created from SNOMED searches and then mapped to Read v2, CTV3 and EMIS.

## Prevalence log

By examining the prevalence of codes (number of patients with the code in their record) broken down by clinical system, we can attempt to validate the clinical code sets and the reporting of the conditions. Here is a log for this code set. The prevalence range \`XXX% - XXX%\` suggests that this code set is well defined, but perhaps more frequently used in the TPP practices in GM.

| Date  | Practice system | Population | Patients from ID | Patient from code |
| ----- | --------------- | ---------- | ---------------: | ----------------: |
| ${dt} | EMIS            | xxxxxxx    |                  |                   |
| ${dt} | TPP             | xxxxxxx    |                  |                   |
| ${dt} | Vision          | xxxxxxx    |                  |                   |

## Audit log

- Find_missing_codes last run ${dt}

---

${snomedCodes}

---

${ctv3Codes}

---

${readv2Codes}
`;

copy(text);
