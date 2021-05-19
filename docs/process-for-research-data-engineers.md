## Index

- [Overview](../README.md)
- [Data description](index.md)
- [Current projects](current-projects.md)
- [Clinical code sets](clinical-code-sets.md)
- [Additional technical information](additional-technical-information.md)
  - **RESEARCH DATA ENGINEER PROCESS**
  - [SQL generation process](SQL-generation-process.md)

# Research Data Engineer processes

All processes involving a Research Data Engineer (RDE) are explained in more detail here. For a high level overview of the end to end process please see the documentation [here](https://drive.google.com/file/d/1Pp9Z3yGq259m9fGXwZfWNI40HJ-oqMKL/view?usp=sharing).

## Overview

An RDE will be assigned to work with the group of researchers who wish to obtain a data extract. The RDE will help determine the precise requirements for the data extract, and, once approved, will extract the data and transfer it to a virtual machine that the researchers will have access to.

## SOPs

Most of the processes below are covered by SOPs. These can be found in the `SOPs for GMCR research ROG` google document.

## Stage I

Stage I of the proposal form allows PIs to describe their research question.

- The RDE lead will assign an RDE to assist the PI.
- Once submitted the RDE reviews the eligibility and feasibility of the study.
- If unclear, the RDE adds comments to the proposal form, and returns to the PI.
- After one or more cycles the proposal is eventually withdrawn or accepted.
- If accepted, the RDE:
  - completes the ROG box at the end of stage I
  - adds the date of "Stage I completed" to the revision log at the top of the document
  - creates a pdf copy entitled "Stage I complete - RQXXX - NAME"
  - updates the portfolio log to reflect tasks completed and status
  - sends an email to the PI (see email template 1.3 in the `SOPs for GMCR research ROG` document) requesting they complete Stage IIa and IIb, and informing them of the remaining process steps.

## Stage IIa

Stage IIa of the proposal form allows PIs to specify precisely what their research question is, and what data is required.

### Determining the data to be extracted

The research teams will have differing levels of knowledge of working with routinely collected data. They will also likely not be familiar with the GMCR. Therefore the role of the RDE is to help them understand what data is available so they can best determine what should be in their data extract.

### GM IDCR data dictionary

The data dictionary is available here: [https://confluence.systemc.com/pages/viewpage.action?pageId=61344193](https://confluence.systemc.com/pages/viewpage.action?pageId=61344193)

However it is password protected. A common login is available for researchers on request.

Typically this isn't useful to researchers as a lot of the information is redacted. The RDEs are likely better at guiding PIs as to what is possible, rather than giving access to this document.

### Stage IIa process

- The PI and RDE collaborate to complete stage IIa (RDE may differ from stage I)
- The PI and RDE agree that stage IIa is complete and PI informed that it will now go through the ERG process. RDE confirms to PI the date of the ERG meeting it is expected to be presented at.
- The RDE adds the date of "Stage IIa submitted to ERG" into the document's Revision Log
- The RDE creates a pdf copy named "Stage IIa complete pending approval - RQXXX - NAME", informs ROG Core team that it is ready for ERG approval, and updates the portfolio log.
- RDE submits pdf to ERG admin for next ERG meeting agenda and informs PI.
- The outcome is captured in the ERG minutes.
- RDE records the outcome of the meeting in the proposal form in box at the end of Stage IIa. Four outcome processes are possible:

  - APPROVED:

    - RDE updates the proposal including any minor comments or stipulations
    - RDE adds the date of "Stage IIa approved by ERG" to the Revision Log
    - RDE creates pdf copy named "Stage IIa approved - RQXXX - NAME"
    - RDE updates the "Data spec approved by ERG" column in the portfolio log
    - RDE / Ops informs PI

  - APPROVED WITH AMENDMENTS/CAVEATS:

    - RDE updates the proposal including any comments or stipulations
    - RDE adds the date of "Stage IIa approved with caveats by ERG" to the Revision Log
    - RDE creates pdf copy named "Stage IIa approved - RQXXX - NAME"
    - RDE updates portfolio log
    - RDE / Ops informs PI
    - ROG team ensure all amends/caveats in place before Stage III commences. Update ERG on status of amendments/caveats as required.

  - NOT APPROVED - INVITED RESUBMISSION

    - RDE Admin adds the details of ERG comments/revision requested to IIa yellow box, and adds a second clean yellow box below it.
    - RDE adds the date of "Stage IIa not approved - invited resubmission by ERG" to the Revision Log
    - RDE creates pdf copy "Stage IIa not approved - invited resubmission RQ-XXX NAME""
    - RDE/ERG chair informs the PI
    - PI works with RDE to update the form responding to the revision requests until ROG agrees it is revised.
    - New pdf copy is created "Stage XX revisions complete ready for review..." This retriggers Stage IIa and update portfolio log

  - REJECTED
    - RDE adds the date of "Stage IIa rejected by ERG" to the Revision Log
    - RDE Updates the proposal and creates pdf copy named "RQXXX - NAME - Stage IIb rejected"
    - RDE updates portfolio log
    - ERG chair informs PI

## Stage IIb

Stage IIb allows the PI to describe their methodology and who the data analysts will be. There is nothing for the RDE to do here, but Stage III does not occur until stages IIa and IIb have both been approved.

## Stage III

In Stage III the study is approved and the data extract can commence.

### Data extract

The steps required to perform a data extract are as follows:

- Create a new project folder under `.\projects` by copying the `_example` directory and giving it an appropriate name.
- Create one `.template.sql` file in the `template-sql` directory for each data file requested by the PI
- Populate the `.template.sql` files by reusing existing SQL and clinical code sets, or creating new ones. Full details on the process to generate SQL to extract data is found here [SQL-generation-process.md](SQL-generation-process.md)
- Once the SQL is ready it must be reviewed by another RDE
- The RDE should review the contents of the `template-sql` directory, and also any reusable SQL or code sets that are used and that haven't already been approved.
- Approval is confirmed by the RDE adding their name and date to the top of each file.
- Once approved the `Data Extract Status` sheet of the `VDE and Data Extract Tracker` google sheet should be updated with the date that the data was ready.
- Once approved, and once the study analysts have access to a VDE and a file share (see below), then the data can be copied across:
  - Ensure the extraction SQL is up to date by running either `generate-sql-windows.bat` or `generate-sql.sh` from inside the project directory
  - Connect to the RDE VDE
  - Copy and paste the entire `XXX - Name` project directory onto the machine
  - Execute the `extract-data.bat` file and follow onscreen instructions
  - The data is created in a directory called `output-for-analysts`
  - The entire contents of `output-for-analysts` should be copied into the file share that has been set up for this project (see below for instructions on setting up the file share).
  - The `Data Extract Status` sheet of the `VDE and Data Extract Tracker` google sheet should be updated with the date that the data extract was made availalble. Also, if not already done, the `File Share Request by User` sheet of the `VDE and Data Extract Tracker` google sheet should be updated with the date that access was granted to the file share.

### Virtual desktop environments (VDEs)

Each study analyst requires a VDE. The analysts must complete a "Safe Analyst Test" prior to gaining access to ensure export controls are correctly followed when analysing data in a remote environment. The process to get these set up is not the responsibility of the RDE.

### Shared drive

In order to get the data extract to the study analysts a shared drive is created. The request for this comes from the RDE and follows this process:

Pre-requisite: All users must have a VDE and appear in the list of names on the first sheet of the `VDE and Data Extract Tracker` google sheet.

- Open the proposal form for the project to get the list of analyst names who will work on the data
- Open the `VDE and Data Extract Tracker` google sheet.
- Select the `VDE Accounts - All User Status` sheet and confirm that all the users in the proposal are listed here and that they have been granted access to a VDE
- Assuming they have, then navigate to the `Data Extract Status` sheet to add the project name to the list of `Study IDs`
- Navigate to the `File Share Request by User` sheet.
- Complete one row per person who requires access. The first 4 columns need completing. The `Person Name` and `Study ID` are dropdowns populated by the other two sheets. If the person name or the study id do not appear then please check the earlier steps in this section.
- Once done you can now make the request to GraphNet for the file share.
- First obtain the email addresses that the analysts have been assigned when their VDE was created. This will be of the form `firstname.secondname@grhapp.com`. You will also need the grhapp email address for the RDE who will extract and send the data.
- Make a note of the RQ number and PI name as the name of the file share will have these in it.
- Navigate to the [GMSS service desk](https://nwcsu.service-now.com/gmss) and login (Firefox doesn't seem to work but Chrome does).
- Select `IDCR Portal` from the top menu bar
- Select `Request something`
- Select `GM Care Record General Request`
- Complete the form:

  - Company: `The University of Manchester`
  - Organisations: `Health Innovation Manchester`
  - General Request: `Other`
  - General Information: `Please set up a file share, with the name "GMCR-RQXXX-[PI name]", accessible by the following users: [insert list of emails for all the analysts and the RDE who will send the data]`
  - E.g. the general information box will look like: `Please set up a file share, with the name "GMCR-RQ027-Williams", accessible by the following users: richard.william@grhapp.com another.user@grhapp.com one.more@grhapp.com`

- Click `Add to cart`
- Click the `HERE` hyperlink in the popup
- Close the popup
- Click `Order`
- Once confirmation is received that this has been set up, the `File Share Request by User` sheet of the `VDE and Data Extract Tracker` google sheet should be updated with the date that access was granted.

**NB sometimes the file share is not visible in the VDE. If that happens try the following steps:**

- Open Windows Explorer and navigate to "This PC"
- Right click anywhere in "This PC"
- Select "Add a network location"
- Follow the onscreen prompts, entering "\\\\gmvdireportstorage.file.core.windows.net\\gmcr-rqXXX-[PI name]" as the "Internet or Network Address".
- Enter "gmcr-rqXXX-[PI name]" as the file share name when prompted
- If the file share has been correctly set up you will now be able to access it. Otherwise you'll need to re-open the support ticket with GMSS/GraphNet

### Clinical code sets

Where researchers already have clinical code sets for the conditions they are interested in, these can be used. Permission should be requested from the researchers that they are happy for these code sets to be made publically accessible by inclusion within this repository.

We will save all clinical code sets within this repository.

If researchers do not have clinical code sets then the assigned RDE should work with the researchers to construct them - or to reuse existing ones within this repository.

We have developed a tool [GetSet](https://getset.ga) for creating clinical code sets. Where appropriate this can be used for creating code sets that do not yet exist.

Further details on how to store code sets within this repository can be found here [SQL-generation-process.md](SQL-generation-process.md).
