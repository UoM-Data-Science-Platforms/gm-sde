## Index

1. **Overview**
1. [Terms of reference](docs/terms-of-reference.md)
1. [Full end to end process](docs/process-end-2-end.md)
1. [Research data engineer process](docs/process-for-research-data-engineers.md)

# Greater Manchester Integrated Digital Care Record

All extraction scripts and clinical code sets for projects involving the Greater Manchester Integrated Digital Care Record (GM IDCR).

## Overview

Due to the ongoing COVID-19 pandemic and more specifically the UK [Control of Patient Information (COPI) notice](https://digital.nhs.uk/coronavirus/coronavirus-covid-19-response-information-governance-hub/control-of-patient-information-copi-notice), researchers at the University of Manchester have access to the GM IDCR for research purposes. This repository makes available for scrutiny all aspects of the data extraction process.

## Documentation

Full documentation can be found in the [docs](docs/) folder. Specific links to individual files are available in the **Index** above.

## Things to check

There are certain things that may exist in the data that would be useful to several research groups. These should be prioritised when initially examining the data.

- To what extent we have hospital admission data
  - How many trusts across GM provide it
  - How complete is the data
  - What sort of data is captured
- Linked datasets. I.e. to what extent the following is available:
  - HES data
  - Mortality data
- COVID-19 specific stuff e.g.
  - GP diagnoses
  - RNA testing
  - Vulnerable patient flag
- Completeness and accuracy of demographic data. In particular ethnicity will be of interest due to the apparent increased risk of COVID-19 among BAME people.
- Possibilty to link to any data from the track and trace programme

### More specific questions

There are other things that individual research groups have enquired about. This list is not exhaustive but is a starting point for further investigation

- Whether national audit data for covid19 - e.g. ICNARC could be linked or already is
- Is there a way to link parents and children
- How much child / young person data is available – does there appear to be useable social / community services information, and are there any particular restrictions on data relating to children?
- Is disability / SEND data present for young people?
- How complete is mental health data (especially CAMHS for young people), and is it clear which providers have been used for MH services?

## Process

A team of research data engineers (RDE) will have access to the data. Initially they will attempt to get an understanding of the data available, before extracting the data for specific research projects. A common, documented, approach will be used in order to ensure the quality of the data extract is the same regardless of which RDE is used.
