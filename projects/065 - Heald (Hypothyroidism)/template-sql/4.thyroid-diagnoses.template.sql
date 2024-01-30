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
-- 2m30
--> EXECUTE query-build-rq065-cohort-events-small.sql
-- 1m

--> CODESET hypothyroidism:1 thyroid-disorders:1

-- First let's combine the thyroid disorder code sets. The thyroid
-- disorder codeset also includes hypothyroidism, so we want to 
-- deduplicate those codes and ensure they are classified as
-- hypothyroidism

-- Relies on the fact that "hypothyroidism" is alphabetically earlier
-- than "thyroid-disorder", so MIN matches hypothyroidism before
-- thyroid-disorders. The definitions should be the same so doesn't
-- matter if we take the MIN or MAX
IF OBJECT_ID('tempdb..#CodeDefinitions') IS NOT NULL DROP TABLE #CodeDefinitions;
SELECT Code, MIN(Concept) AS Concept, MAX([description]) AS [Definition]
INTO #CodeDefinitions
FROM #AllCodes
WHERE Concept IN ('hypothyroidism','thyroid-disorders')
GROUP BY Code;
-- 0s

SELECT
	FK_Patient_Link_ID AS PatientId,
	EventDate,
	Concept AS ThyroidDisorder,
	[Definition]
FROM #PatientEventData e
INNER JOIN #CodeDefinitions d ON d.Code = e.SuppliedCode
ORDER BY FK_Patient_Link_ID, EventDate;
-- 10s