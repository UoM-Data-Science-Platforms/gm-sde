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

--> CODESET acute-pain-service:1 social-care-prescribing:1 pain-management:1 surgery:1

--bring together for final output
--patients in main cohort
SELECT	 PatientId = FK_Patient_Link_ID
FROM #Cohort p

SELECT 
	PatientId = FK_Patient_Link_ID, 
	CodingDate = CAST(EventDate AS DATE), 
    Code = SuppliedCode, 
	Concept = a.c
	CodeDescription = a.description  
FROM SharedCare.GP_Events gp
LEFT OUTER JOIN #AllCodes a ON gp.SuppliedCode = a.Code
WHERE SuppliedCode IN (SELECT Code FROM #AllCodes WHERE (Concept NOT IN ('cancer', 'opoid-analgesics', 'chronic-pain'))) 
	AND gp.EventDate BETWEEN @StartDate AND @EndDate
	AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Cohort)

