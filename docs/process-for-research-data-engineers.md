## Index

1. [Overview](../README.md)
2. [Full end to end process](process-end-2-end.md)
3. **Research data engineer process**

# Research Data Engineer processes

All processes involving a Research Data Engineer (RDE) are explained in more detail here. For a high level overview of the end to end process please see the documentation [here](process-end-2-end.md).

## Overview

An RDE will be assigned to work with the group of researchers who wish to obtain a data extract. The RDE will help determine the precise requirements for the data extract, and, once approved, will extract the data and transfer it to a virtual machine that the researchers will have access to.

1. Create a new project folder under `.\projects` by copying the `_example` directory and giving it an appropriate name.
2. Work with the researchers to determine the data to be extracted. This may involve:
    - Re-using clinical code sets from the researchers, or from this repository in `.\code-sets`
    - Creating new clinical codesets
3. Once completed update the projects `README.md` document (e.g. `./projects/_example/README.md`) to describe the data to be extracted.
4. The project `README.md`, and any associated queries and code sets should be approved by a second RDE, before the README.md data definition is passed to the RGG.
5. Once approved by the RGG the actual data extraction can be performed.
6. A virtual machine, with access granted to the RDEs and the researchers, should be requested from GraphNet
7. The data extract should be signed off by a second RDE prior to transfer to the virtual machine

## Determining the data to be extracted

The research teams will have differing levels of knowledge of working with routinely collected data. They will also likely not be familiar with the GM IDCR. Therefore the role of the RDE is to help them understand what data is available so they can best determine what should be in their data extract.

### GM IDCR data dictionary

The data dictionary is available here: [https://confluence.systemc.com/pages/viewpage.action?pageId=61344193](https://confluence.systemc.com/pages/viewpage.action?pageId=61344193)

However it is password protected. A common login is available for researchers on request.

### Data sources

The following data sources are available within the GM IDCR to varying degrees:

- Primary care (GP) data
- Secondary care (acute) data
- Mental health trust data
- Social care data
- Out of hours data
- Cancer (Christie) data

### Clinical code sets

Where researchers already have clinical code sets for the conditions they are interested in, these can be used. Permission should be requested from the researchers that they are happy for these code sets to be made publically accessible by inclusion within this repository.

We will save all clinical code sets within this repository.

If researchers do not have clinical code sets then the assigned RDE should work with the researchers to construct them - or to reuse existing ones within this repository.

Clinical coding within the GM IDCR is standardised to SNOMED-CT. If researchers have existing Read v2 or CTV3 code sets then these can be mapped to SNOMED-CT using the mappings files available from [https://isd.digital.nhs.uk/trud3](https://isd.digital.nhs.uk/trud3).

We have developed a tool [GetSet](https://getset.ga) for creating clinical code sets. Where appropriate this can be used for creating code sets that do not yet exist.