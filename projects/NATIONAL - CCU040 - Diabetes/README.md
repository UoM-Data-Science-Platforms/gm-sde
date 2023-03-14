_This file is autogenerated. Please do not edit._

# The factors associated with increased risk of hospitalisation and death in people with diabetes following SARS-CoV-2 infection: A national replication study.

## Summary

People with type 1 or type 2 diabetes are more likely to be admitted to hospital, and more likely to die, after getting infected with COVID-19. We have recently used data from Greater Manchester (GM) to discover why this might be. We found several things that increased the risk of poor outcomes, such as age, being male, being socially deprived, ethnicity, certain medications and certain health conditions.

We will now try to repeat these results using the national COVID-IMPACT data. Studies such as this (a replication study) where people attempt to reproduce results from other studies are important. If the results are the same, then it strengthens the findings. If different then that is important as well as it shows the initial results might not be as generalisable as previously thought and may be related to factors that may not have been considered in some of the studies. This work will also help us to understand the role of regional and national datasets and how they might be best suited to different research questions.

We also plan to extend the analysis to take advantage of any extra data that is available nationally, but that was not available in GM.

## Table of contents

- [Introduction](#introduction)
- [Methodology](#methodology)
- [Reusable queries](#reusable-queries)
- [Clinical code sets](#clinical-code-sets)

## Introduction

The aim of this document is to provide full transparency for all parts of the data extraction process.
This includes:

- The methodology around how the data extraction process is managed and quality is maintained.
- A full list of all queries used in the extraction, and their associated objectives and assumptions.
- A full list of all clinical codes used for the extraction.

## Methodology

After each proposal is approved, a Research Data Engineer (RDE) works closely with the research team to establish precisely what data they require and in what format.
The RDE has access to the entire de-identified database and so builds up an expertise as to which projects are feasible and how best to extract the relevant data.
The RDE has access to a library of resusable SQL queries for common tasks, and sets of clinical codes for different phenotypes, built up from previous studies.
Prior to data extraction, the code is checked and signed off by another RDE.

## Reusable queries
  
This project did not require any reusable queries from the local library [https://github.com/rw251/gm-idcr/tree/master/shared/Reusable queries for data extraction](https://github.com/rw251/gm-idcr/tree/master/shared/Reusable%20queries%20for%20data%20extraction).## Clinical code sets

This project did not require any clinical code sets.
# Clinical code sets

All code sets required for this analysis are available here: [https://github.com/rw251/.../NATIONAL - CCU040 - Diabetes/clinical-code-sets.csv](https://github.com/rw251/gm-idcr/tree/master/projects/NATIONAL%20-%20CCU040%20-%20Diabetes/clinical-code-sets.csv). Individual lists for each concept can also be found by using the links above.