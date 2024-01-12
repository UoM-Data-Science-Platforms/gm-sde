const $input = document.getElementById('lookup');
const $results = document.getElementById('results');
const $readme = document.getElementById('readme');
const $search = document.getElementById('search-wrapper');
const $tab = document.querySelector('.tab');
let data;
let $list;

async function getData() {
  data = await fetch('code-set-readme.json').then((x) => x.json());
  $input.removeAttribute('disabled');
  $input.placeholder = 'Search for code set...';
  //$input.focus();
}

getData();

function isMatch(findThis, insideThis) {
  let matches = 0;
  for (let i = 0; i < findThis.length; i++) {
    for (let j = 0; j < insideThis.length; j++) {
      if (insideThis[j] === findThis[i]) {
        matches++;
        break;
      } else if (insideThis[j].indexOf(findThis[i]) > -1) {
        matches += 0.7;
        break;
      }
    }
  }
  return matches / findThis.length;
}

const rawUrl = 'https://raw.githubusercontent.com/rw251/gm-idcr/master/shared/clinical-code-sets';

$results.addEventListener('click', (e) => {
  const { version, category, name } = e.target.dataset;
  $list.forEach((x) => x.classList.remove('selected'));
  e.target.classList.add('selected');

  $tab.classList.remove('hide');
  openTab('Description');
  $readme.style.display = 'block';

  fetch(`${rawUrl}/${category}/${name}/${version}/README.md`)
    .then((x) => x.text())
    .then((x) => ($readme.innerHTML = markdown(x)));
});

$input.addEventListener('input', (e) => {
  const input = $input.value
    .toLowerCase()
    .replace(/[\W_]+/g, ' ')
    .trim()
    .split(' ');
  const matchesOfName = data
    .map((x) => {
      x.diff = isMatch(input, x.codeSetName);
      return x;
    })
    .filter((x) => x.diff)
    .sort((a, b) => b.diff - a.diff);
  const matchesOfReadMe = data
    .filter(
      (x) =>
        matchesOfName.filter((y) => y.codeSetName.join(' ') === x.codeSetName.join(' ')).length ===
        0
    )
    .map((x) => {
      x.diff = isMatch(input, x.readmeBits);
      return x;
    })
    .filter((x) => x.diff)
    .sort((a, b) => b.diff - a.diff);

  const exactMatchesOfName = matchesOfName.filter((x) => x.diff === 1);
  const otherMatchesOfName = matchesOfName.filter((x) => x.diff < 1);
  const exactMatchesOfReadme = matchesOfReadMe.filter((x) => x.diff === 1);
  const otherMatchesOfReadme = matchesOfReadMe.filter((x) => x.diff < 1);
  const otherMatches = otherMatchesOfName
    .concat(otherMatchesOfReadme)
    .sort((a, b) => b.diff - a.diff);

  const results = exactMatchesOfName.concat(exactMatchesOfReadme).concat(otherMatches);

  $results.innerHTML = results
    .map(
      (x) =>
        `<li data-version="${x.version}" data-category="${
          x.category
        }" data-name="${x.codeSetName.join('-')}">${x.readableName}</li>`
    )
    .join('\n');
  $list = $results.querySelectorAll('li');
});

function openTab(tabName) {
  if (window.getComputedStyle($tab).display === 'none') return;

  const tablinks = document.getElementsByClassName('tablinks');

  if (tabName === 'Description') {
    tablinks[0].classList.remove('active');
    tablinks[1].classList.add('active');
    $readme.classList.add('focus');
    $search.style.display = 'none';
  }
  if (tabName === 'Search') {
    tablinks[0].classList.add('active');
    tablinks[1].classList.remove('active');
    $readme.classList.remove('focus');
    $search.style.display = 'block';
  }
}
