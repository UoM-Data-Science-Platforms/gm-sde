--┌────────────────────────────────────┐
--│ LH004 GP Contact Proxy             │
--└────────────────────────────────────┘

SELECT "FK_Patient_ID", 
"GmPseudo", 
"PracticeCode", 
"GMLocality", 
"EventDate",
"TotalSNOMEDCodes", 
"IdentifiedContactCodes", 
"Contact"
FROM INTERMEDIATE.GP_RECORD."Contacts_Proxy"
