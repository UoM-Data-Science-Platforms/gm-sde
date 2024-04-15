--┌──────────────────────────────────────────┐
--│ SDE Lighthouse study 06 - Chen           │
--└──────────────────────────────────────────┘

--Just want the output, not the messages
SET NOCOUNT ON;

DECLARE @StartDate datetime;
DECLARE @EndDate datetime;
SET @StartDate = '2017-01-01';
SET @EndDate = '2023-12-31';

--> EXECUTE query-build-lh006-cohort.sql

--> CODESET chronic-pain:1 rheumatoid-arthritis:1 osteoarthritis:1 back-problems:2 neck-problems:1 
--> CODESET post-herpetic-neuralgia:1 ankylosing-spondylitis:1 neuropathic-pain:1 chest-pain:1
--> CODESET psoriatic-arthritis:1 fibromyalgia:1 temporomandibular-pain:1

-- !!NOTE!! : many codes will feature in both the 'chronic pain' code set and the more specific code set, aned therefore feature twice in the final table.

-- find diagnoses for chronic pain conditions

SELECT 
	PatientId = FK_Patient_Link_ID, 
	CodingDate = CAST(EventDate AS DATE), 
    Code = SuppliedCode, 
	Concept = a.c
	CodeDescription = a.description  
FROM SharedCare.GP_Events gp
LEFT OUTER JOIN #AllCodes a ON gp.SuppliedCode = a.Code
WHERE SuppliedCode IN (SELECT Code FROM #AllCodes WHERE (Concept NOT IN ('cancer', 'opoid-analgesics'))) 
	AND gp.EventDate BETWEEN @StartDate AND @EndDate
	AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Cohort)
