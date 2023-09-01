# GP utilization over time

## Quick summary

If someone wants to know the number of appointments, broken down by health care professional (GP, nurse etc.) and by appointment type (face-2-face, telephone etc..) then give them the file: `output/gp-utilization-data-by-ccg.csv`.

If you need to update the file with more recent data then execute:

```
node main.js
```

## Background

NHS digital publishes a breakdown of GP appointment data, per locality (as was CCG) every month. It is broken down by:

- Appointment type (face-2-face, telephone, home visit, online/video conference)
- Healthcare professional (GP, Other)
- Status (Attended, Did not attend - DNA)

This information is not available in the GMCR, so we must use the figures from NHS digital.

## Execution

This script should be executed from a command line. First navigate to this directory (`tools\gp-utilization-from-nhs-digital`), and then execute the following:

```cli
node main.js
```

## Details

The script does the following for each month since October 2018:

1. Checks if the data zip file is already downloaded and cached locally
2. If not then it downloads the zip file from the NHS digital website and caches it locally
3. Unzips the csv file and caches it locally
4. Loads the csv file and extracts the relevant information for each locality in Greater Manchester. This information is also cached locally
5. Creates a final output csv file

It is possible to run a single component of the above pipeline, as follows:

- To force the download of the zip files from NHS digital and overwrite the existing ones execute: `node main.js download`
- To force the unzipping of the csv files from NHS digital and overwrite the existing ones execute: `node main.js unzip`
- To process the downloaded csv files into the processed json files (found under `cached-data-files/XXXX/processed/`) execute: `node main.js process`
- To combine the processed files into a single file csv execute: `node main.js combine`

## Notes

- The data is publically available via NHS digital so it is ok to host on our github page as well. This caching means we do not need to download hundreds of data files each time we rerun this script.
- Prior to April 2017 there were 12 CCGs in Greater Manchester. In 2017, Central Manchester CCG, South Manchester CCG and North Manchester CCG merged into simply Manchester CCG. However, this data is currently only available back to 2018 so this issue is not present in this data.
