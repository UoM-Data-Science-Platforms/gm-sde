# GP population size over time

## Background

NHS digital publishes a breakdown of GP population size every month. It is broken down into sex and single age categories. This information is often useful as a denominator for studies using the GMCR. However due to the way the information is stored in the GMCR it is impossible to determine the historic GP populations. Therefore we must use the figures from NHS digital.

## Execution

This script should be executed from a command line. First navigate to this directory (`tools\gp-population-size-from-nhs-digital`), and then execute the following:

```cli
node main.js
```

## Details

The script does the following for each month since April 2013:

1. Checks if the data file is already downloaded and cached locally
2. If not then it downloads the data file or files (prior to 2017 the male/female split was in the same file, subsequently they are in separate files) from the NHS digital website and caches it locally
3. Loads the file and extracts the sex/age number of patients for each GP in Greater Manchester
4. Writes the output to a file

## Notes

- Prior to **_TODO_** the breakdown was only in 5 year groups e.g. number of males between 0-5, number between 5-10 etc.
- The data is publically available via NHS digital so it is ok to host on our github page as well. This caching means we do not need to download hundreds of data files each time we rerun this script.
