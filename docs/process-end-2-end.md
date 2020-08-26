## Index

1. [Overview](../README.md)
1. [Terms of reference](terms-of-reference.md)
1. **Full end to end process**
1. [Research data engineer process](process-for-research-data-engineers.md)

# Full end to end process

This shows the high level end to end process for analysts wishing to use the GM-IDCR for COVID-19 research purposes.

## People

### > Researchers

Any academic researchers within Greater Manchester who wish to make use of the GM IDCR for research.

### > Operations Group (OG)

A group within the University of Manchester, led by **_John Ainsworth?_**, responsible for the **_TODO_**...

### > Research Governance Group (RGG)

A group within Health Innovation Manchester, led by Niels Peek, responsible for the approval and prioritisation of individual studies making use of the GM IDCR.

### > Research Data Engineers (RDE)

A group within the University of Manchester, led by [Richard Williams](https://www.research.manchester.ac.uk/portal/richard.williams.html), with access to the full anonymised version of the GM IDCR.

### > Secondary Usage Governance Group (SUGG)

A group within the Greater Manchester Health and Social Care Partnership, led by Guy Lucchi, that provide approval for access to the GM IDCR for secondary usage.

### > GraphNet

The organisation responsible for the creation and maintenance of the GM IDCR.

## Process

This is the process for researchers wishing to analyse **anonymised data extracts**.

1. **_Researchers_** submit a proposal to the **_OG_**
2. If the **_OG_** reject the proposal it is sent back to the **_researchers_** - return to step 1. If approved goto step 3.
3. The **_OG_** approve the proposal and add it to a list based on priority
4. When the proposal is at the top of the priority list it is passed to the **_RDEs_**
5. An **_RDE_** is assigned to the proposal and works with the **_researchers_** to determine what data is required.
6. Provided the IDCR has the necessary data, a detailed description of what data is to be extracted is produced.
7. This is signed off by a different **_RDE_** before being sent back to the **_RGG_** for approval.
8. On approval by the **_RGG_**, database queries are written by the assigned **_RDE_** to extract the data. These queries may already have been written as part of step 6.
9. The queries and data extract are approved by a second **_RDE_**.
10. **_GraphNet_** create a new virtual machine and provide access to the **_researchers_** and the **_RDE_**.
11. The **_RDE_** transfers the data to the new virtual machine.

## Non-anonymised data

The GM IDCR also contains pseudonymised data and patient identifiable data (PID). The pseudonymised data itself contains nothing identifiable, but **_Graphnet_** have the ability to re-identify patients in this data so it is not truely anonymised.

It is not expected that researchers will require access to pseudonymised or PID. However, if there are studies that do require this, then approval must be undertaken by the **_SUGG_**.
