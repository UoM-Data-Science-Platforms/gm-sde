# GP population size over time

## Quick summary

If someone wants to know the size of the population of each GP practice broken down by age and sex then give them the file `output/gp-population-data-by-sex-and-age.zip`.

If that file doesn't exist, then run the following:

```
node --max-old-space-size=4096 main.js generate
```

If you need to update the file with more recent data then execute:

```
node --max-old-space-size=4096 main.js
```

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
4. Creates a final output and writes it into files of 2M lines each. These chunks ensure that we can commit them to github.
5. Combines the chunks into a single output file
6. Compresses the output to a zip file
7. Validates the output to check things like:
   - whether there are sudden increases or decreases in practice size
   - whether practices disappear

**_NB The two output files (`output/gp-population-data-by-sex-and-age.csv` and `output/gp-population-data-by-sex-and-age.zip`) do not get committed to the repository because the csv file exceeds the file size limit for GitHub, and the zip file is a binary and so not usefully committed._**

It is possible to run a single component of the above pipeline, as follows:

- To force the download of the files from NHS digital and overwrite the existing ones execute: `node main.js download`
- To process the downloaded csv files into the processed json files (found under `cached-data-files/XXXX/processed/`) execute: `node main.js process`
- To load the processed files and create the output file chunks execute: `node main.js chunk`
- To combine the chunks into a single file execute: `node main.js combine`
- To compress the output file execute: `node main.js compress`
- To combine the chunks and compress the output at the same time execute: `node main.js generate`
- To validate the output execute: `node main.js validate`

## Notes

- Prior to October 2014 the breakdown was only in 5 year groups e.g. number of males between 0-5, number between 5-10 etc.
- The data is publically available via NHS digital so it is ok to host on our github page as well. This caching means we do not need to download hundreds of data files each time we rerun this script.
- Prior to April 2017 there were 12 CCGs in Greater Manchester. In 2017, Central Manchester CCG, South Manchester CCG and North Manchester CCG merged into simply Manchester CCG. The old CCG id codes will be in this file for those practices prior to April 2017
