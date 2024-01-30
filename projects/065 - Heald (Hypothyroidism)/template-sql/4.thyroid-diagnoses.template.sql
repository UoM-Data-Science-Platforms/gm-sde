--┌────────────────────────────┐
--│ Thyroid disorder diagnoses │
--└────────────────────────────┘

-- OUTPUT:
--  PatientID
--  EventDate
--  ThyroidDisorder (hypothyroidism / other-thyroid-disorder)
--  Specific description

-- Just want the output, not the messages
SET NOCOUNT ON;

-- Get the cohort of patients
--> EXECUTE query-build-rq065-cohort.sql
--> EXECUTE query-build-rq065-cohort-events-small.sql

--> CODESET hypothyroidism:1 thyroid-disorders:1

-- First let's combine the thyroid disorder code sets. The thyroid
-- disorder codeset also includes hypothyroidism, so we want to 
-- deduplicate those codes and ensure they are classified as
-- hypothyroidism

-- Relies on the fact that "hypothyroidism" is alphabetically higher
-- than "thyroid-disorder". The definitions should be the same so 
-- doesn't matter if we take the MIN or MAX
IF OBJECT_ID('tempdb..#CodeDefinitions') IS NOT NULL DROP TABLE #CodeDefinitions;
SELECT Code, MAX(Concept) AS Concept, MAX([definition]) AS [Definition]
INTO #CodeDefinitions
FROM #AllCodes
GROUP BY Code;

SELECT
	FK_Patient_Link_ID AS PatientID,
	EventDate,
	Concept AS ThyroidDisorder,
	[Definition]
FROM #PatientEventData e
LEFT OUTER JOIN #CodeDefinitions d ON d.Code = e.SuppliedCode