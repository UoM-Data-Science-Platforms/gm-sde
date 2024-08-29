--┌─────────────────────────────┐
--│ Adverse Drug Reactions      │
--└─────────────────────────────┘

set(StartDate) = to_date('2012-01-01');
set(EndDate) = to_date('2024-06-30');

--> CODESET adverse-drug-reaction:1

-- find adverse reactions from GP events table

SELECT DISTINCT
	e."FK_Patient_ID"
	, to_date("EventDate") AS "DiagnosisDate"
	, e."SCTID" AS "SnomedCode"
	, 'adverse-drug-reaction' AS "Concept"
	, e."Term" AS "Description"
FROM INTERMEDIATE.GP_RECORD."GP_Events_SecondaryUses" e
WHERE "SuppliedCode" IN (SELECT code FROM {{code-set-table}} WHERE concept = 'adverse-drug-reaction')
	AND "FK_Patient_ID" IN (SELECT "FK_Patient_ID" FROM {{cohort-table}})
	AND TO_DATE("EventDate") BETWEEN $StartDate AND $EndDate;