# Full end to end process

This shows the high level end to end process for analysts wishing to use the GM-IDCR for COVID-19 research purposes.

## People

- Researchers
- Research Governance Group (RGG)
- Research Data Engineers (RDE)
- Secondary Usage Governance Group (SUGG)
- GraphNet

## Process

1. ***Researchers*** submit a proposal to the ***RGG***
2. If the ***RGG*** reject the proposal it is sent back to the ***researchers*** - return to step 1. If approved goto step 3.
3. The ***RGG*** approve the proposal and add it to a list based on priority
4. When the proposal is at the top of the priority list it is passed to the ***RDEs***
5. An ***RDE*** is assigned to the proposal and works with the ***researchers*** to determine what data is required.
6. Provided the IDCR has the necessary data, a detailed description of what data is to be extracted is produced.
7. This is signed off by a different ***RDE*** before being sent to the ***SUGG*** for approval.
8. On approval by the ***SUGG***, database queries are written by the assigned ***RDE*** to extract the data. These queries may already have been written as part of step 6.
9. The queries and data extract are approved by a second ***RDE***.
10. ***GraphNet*** create a new virtual machine and provide access to the ***researchers*** and the ***RDE***.
11. The ***RDE*** transfers the data to the new virtual machine.

