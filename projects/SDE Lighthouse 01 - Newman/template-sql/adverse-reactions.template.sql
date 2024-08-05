--┌─────────────────────────────┐
--│ Adverse Drug Reactions      │
--└─────────────────────────────┘

--> EXECUTE query-build-lh001-cohort.sql
USE INTERMEDIATE.GP_RECORD;

set(StartDate) = to_date('2012-01-01');
set(EndDate) = to_date('2024-06-30');

-- find adverse reactions from GP events table

SELECT DISTINCT
	e."FK_Patient_ID"
	, to_date("EventDate") AS "DiagnosisDate"
	, e."SCTID" AS "SnomedCode"
	, co.concept AS "Concept"
	, e."Term" AS "Description"
FROM INTERMEDIATE.GP_RECORD."GP_Events_SecondaryUses" e
LEFT JOIN SDE_REPOSITORY.SHARED_UTILITIES.AllCodesPermanent co ON co.CODE = e."SCTID"
WHERE co.concept = 'adverse-reaction'
--AND e."FK_Patient_ID" IN (SELECT "FK_Patient_ID" FROM Cohort)
AND TO_DATE("EventDate") BETWEEN $StartDate AND $EndDate;

