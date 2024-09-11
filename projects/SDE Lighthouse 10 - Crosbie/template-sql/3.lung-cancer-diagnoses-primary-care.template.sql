--┌───────────────────────────────────────────────────────────────────────────┐
--│ SDE Lighthouse study 10 - Crosbie - lung cancer diagnoses in primary care │
--└───────────────────────────────────────────────────────────────────────────┘

--> CODESET lung-cancer:1

DROP TABLE IF EXISTS LungCancer ;
CREATE TEMPORARY TABLE LungCancer AS
SELECT DISTINCT
	e."FK_Patient_ID"
	, dem."GmPseudo"
	, to_date("EventDate") AS "DiagnosisDate"
	, e."SCTID" AS "SnomedCode"
	, cs.concept
	, e."Term" AS "Description"
FROM INTERMEDIATE.GP_RECORD."GP_Events_SecondaryUses" e
LEFT JOIN {{code-set-table}} cs ON cs.code = e."SuppliedCode"
LEFT OUTER JOIN PRESENTATION.GP_RECORD."DemographicsProtectedCharacteristics_SecondaryUses" dem ON dem."FK_Patient_ID" = co."FK_Patient_ID" -- join to demographics table to get GmPseudo
WHERE cs.concept IN ('lung-cancer')
	AND "FK_Patient_ID" IN (SELECT "FK_Patient_ID" FROM {{cohort-table}});
