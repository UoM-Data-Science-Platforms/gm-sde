## Index

- [Overview](../README.md)
- [Data description](index.md)
- [Current projects](current-projects.md)
- [Clinical code sets](clinical-code-sets.md)
- [Additional technical information](additional-technical-information.md)
  - **RESEARCH DATA ENGINEER PROCESS**
  - [SQL generation process](SQL-generation-process.md)

# Research Data Engineer processes

All processes involving a Research Data Engineer (RDE) are explained in more detail here. For a high level overview of the end to end process please see the documentation [here](process-end-2-end.md).

## Overview

An RDE will be assigned to work with the group of researchers who wish to obtain a data extract. The RDE will help determine the precise requirements for the data extract, and, once approved, will extract the data and transfer it to a virtual machine that the researchers will have access to.

1. Create a new project folder under `.\projects` by copying the `_example` directory and giving it an appropriate name.
2. Work with the researchers to determine the data to be extracted. This may involve:
   - Re-using clinical code sets from the researchers, or from this repository in `.\shared\clinical-code-sets`
   - Creating new clinical codesets
3. Full details on the process to generate SQL to extract data is found here [SQL-generation-process.md](SQL-generation-process.md)
4. A separate process ensures that any study analysts have access to a secure virtual machine.
5. A file share between the RDE and the study analysts is requested from GraphNet
6. The data extract should be signed off by a second RDE prior to transfer to the file share

## Determining the data to be extracted

The research teams will have differing levels of knowledge of working with routinely collected data. They will also likely not be familiar with the GM IDCR. Therefore the role of the RDE is to help them understand what data is available so they can best determine what should be in their data extract.

### GM IDCR data dictionary

The data dictionary is available here: [https://confluence.systemc.com/pages/viewpage.action?pageId=61344193](https://confluence.systemc.com/pages/viewpage.action?pageId=61344193)

However it is password protected. A common login is available for researchers on request.

### Data sources

The following data sources are available within the GM IDCR to varying degrees:

- Primary care (GP) data
- Secondary care (acute) data
- Cancer (Christie) data

### Clinical code sets

Where researchers already have clinical code sets for the conditions they are interested in, these can be used. Permission should be requested from the researchers that they are happy for these code sets to be made publically accessible by inclusion within this repository.

We will save all clinical code sets within this repository.

If researchers do not have clinical code sets then the assigned RDE should work with the researchers to construct them - or to reuse existing ones within this repository.

We have developed a tool [GetSet](https://getset.ga) for creating clinical code sets. Where appropriate this can be used for creating code sets that do not yet exist.

Further details on how to store code sets within this repository can be found here [SQL-generation-process.md](SQL-generation-process.md).

### File share request

Pre-requisite: All users must have a VDE and appear in the list of names on the first sheet of the `VDE and Data Extract Tracker` google sheet.

- Open the proposal form for the project to get the list of analyst names who will work on the data
- Open the `VDE and Data Extract Tracker` google sheet.
- Select the `VDE Accounts - All User Status` sheet and confirm that all the users in the proposal are listed here and that they have been granted access to a VDE
- Assuming they have, then navigate to the `Data Extract Status` sheet to add the project name to the list of `Study IDs`
- Navigate to the `File Share Request by User` sheet.
- Complete one row per person who requires access. The first 4 columns need completing. The `Person Name` and `Study ID` are dropdowns populated by the other two sheets. If the person name or the study id do not appear then please check the earlier steps in this section.
- Once done you can now make the request to GraphNet for the file share. For the rest of this process we will assume the project has an id of `123`, a PI called `Macauley`, and two analysts called `Sophie Kalyana` and `Léon Burke` who have been given the usernames `sophie.kalyana@grhapp.com` and `léon.burke@grhapp.com` as part of their VDE setup.
- First obtain the email addresses that the analysts have been assigned when their VDE was created. This will be of the form `firstname.secondname@grhapp.com`. You will also need the grhapp email address for the RDE who will send the data.
- Make a note of the RQ number and PI name as the name of the fileshare will have these in it.
- Navigate to the [GMSS service desk](https://nwcsu.service-now.com/gmss) and login (Firefox doesn't seem to work but Chrome does).
- Select `IDCR Portal` from the top menu bar
- Select `Request something`
- Select `GM Care Record General Request`
- Complete the form:

  - Company: `The University of Manchester`
  - Organisations: `Health Innovation Manchester`
  - General Request: `Other`
  - General Information: `Please set up a fileshare, with the name "GMCR-RQXXX-[PI name]", accessible by the following users: [insert list of emails for all the analysts and the RDE who will send the data]`

- Click `Add to cart`
- Click the `HERE` hyperlink in the popup
- Close the popup
- Click `Order`
