--┌────────────────────────────────────┐
--│ LH004 GP Contact Proxy             │
--└────────────────────────────────────┘

select "FK_Patient_ID", 
"GmPseudo", 
"PracticeCode", 
"GMLocality", 
"EventDate",
"TotalSNOMEDCodes", 
"IdentifiedContactCodes", 
"Contact"
from INTERMEDIATE.GP_RECORD."Contacts_Proxy"
