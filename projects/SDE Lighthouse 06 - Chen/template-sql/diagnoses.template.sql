--┌──────────────────────────────────────────┐
--│ SDE Lighthouse study 06 - Chen           │
--└──────────────────────────────────────────┘

set(StartDate) = to_date('2017-01-01');
set(EndDate)   = to_date('2023-12-31');

--> EXECUTE query-build-lh006-cohort.sql

--> CODESET chronic-pain:1 rheumatoid-arthritis:1 osteoarthritis:1 back-problems:1 neck-problems:1 neuropathic-pain:1 chest-pain:1
--> CODESET post-herpetic-neuralgia:1 ankylosing-spondylitis:1 
--> CODESET psoriatic-arthritis:1 fibromyalgia:1 temporomandibular-pain:1

-- !!NOTE!! : many codes will feature in both the 'chronic pain' code set and the more specific code set, and therefore feature twice in the final table.

-- find diagnoses for chronic pain conditions

SELECT 
	"FK_Patient_ID" AS PatientId, 
	TO_DATE("EventDate") AS CodingDate,
    "SuppliedCode" AS Code, 
	a.Concept,
	a.description AS CodeDescription  
FROM INTERMEDIATE.GP_RECORD."GP_Events_SecondaryUses" gp
INNER JOIN AllCodes a ON gp.SuppliedCode = a.Code
WHERE a.Code NOT IN ('cancer', 'opioid-analgesics') 
	AND gp."EventDate" BETWEEN $StartDate AND $EndDate
	AND gp."FK_Patient_ID" IN (SELECT "FK_Patient_ID" FROM Cohort)
