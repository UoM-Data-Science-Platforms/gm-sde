* NB. All analysis files should be stored in this shared drive. Although it is possible to store files elsewhere on this machine e.g. the C:\ and D:\ drives, these locations are not guaranteed to persist, and you could lose your files.

* Data from the RDEs will be in the data/raw folder. Do not edit the contents of this folder.

* Data that you have processed through your scripts goes in the data/processed folder.

* In some situations (see the RStudio issue below) it may be necessary to copy data elsewhere in the VDE. In these situations the data may only be copied to the "Documents" folder. All other locations are potentially visibile to analysts not working on this project.

* Code goes in the 'code' folder.

* ***For any summary data or figures that you wish to export you MUST conform to the following:

  1. Files for export should first be placed in the output/check folder.
  2. They should then be checked by another analyst for disclosure control risk. 
  3. Once approved by another analyst they should then be placed in the output/approved folder. 
  4. When files are exported from the VDE they should be placed in a subdirectory of output/export with a datestamp prior to copying off the machine.

E.g. the folder structure will look as follows:

output
  |- export
      |- 2021-05-12
      |   |- file1.png
      |   |- file2.png
      |   |- file3.txt
      |- 2021-06-30
      |   |- fileA.png
      |   |- fileB.csv

Files should not be deleted from the 'output/export' folder***

* Anything else (e.g. documentation that is not code) goes in the 'doc' folder.

* NB. There are known issues with using RStudio on a network shared drive. If you experience slow performance please read the documentation here: https://drive.google.com/file/d/1nRuhT-FJ-Sioh0ntknktPN3kYQCc-5px/view?usp=sharing

* ***NB. All studies must submit results and outputs for review by ERG and RGG prior to submission for publication, and for non-academic outputs, such as social media outputs, prior to publication.***

v1.1.1