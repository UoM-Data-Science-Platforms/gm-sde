## Index

1. [Overview](../README.md)
2. **Full end to end process**
3. [Research data engineer process](process-for-research-data-engineers.md)

# Full end to end process

This shows the high level end to end process for analysts wishing to use the GM-IDCR for COVID-19 research purposes.

## People

### > Researchers
Any researchers within the University of Manchester **(?)** who wish to make use of the GM IDCR for research.

### > Research Governance Group (RGG)
A group within the University of Manchester, led by **TBA**, responsible for the approval and prioritisation of individual studies making use of the GM IDCR.

### > Research Data Engineers (RDE)
A group within the University of Manchester, led by [Richard Williams](https://www.research.manchester.ac.uk/portal/richard.williams.html), with access to the full anonymised version of the GM IDCR.

### > Secondary Usage Governance Group (SUGG)
A group within the Greater Manchester Health and Social Care Partnership, led by Guy Lucchi, that provide approval for access to the GM IDCR.

### > GraphNet
The organisation responsible for the creation and maintenance of the GM IDCR.

## Process

This is the process for researchers wishing to analyse **anonymised data extracts**.

1. ***Researchers*** submit a proposal to the ***RGG***
2. If the ***RGG*** reject the proposal it is sent back to the ***researchers*** - return to step 1. If approved goto step 3.
3. The ***RGG*** approve the proposal and add it to a list based on priority
4. When the proposal is at the top of the priority list it is passed to the ***RDEs***
5. An ***RDE*** is assigned to the proposal and works with the ***researchers*** to determine what data is required.
6. Provided the IDCR has the necessary data, a detailed description of what data is to be extracted is produced.
7. This is signed off by a different ***RDE*** before being sent back to the ***RGG*** for approval.
8. On approval by the ***RGG***, database queries are written by the assigned ***RDE*** to extract the data. These queries may already have been written as part of step 6.
9. The queries and data extract are approved by a second ***RDE***.
10. ***GraphNet*** create a new virtual machine and provide access to the ***researchers*** and the ***RDE***.
11. The ***RDE*** transfers the data to the new virtual machine.

## Non-anonymised data

The GM IDCR also contains pseudonymised data and patient identifiable data (PID). The pseudonymised data itself contains nothing identifiable, but ***Graphnet*** have the ability to re-identify patients in this data so it is not truely anonymised.

It is not expected that researchers will require access to pseudonymised or PID. However, if there are studies that do require this, then approval must be undertaken by the ***SUGG***.

