--┌───────────────────────────────────────────────────────────────────────────┐
--│ SDE Lighthouse study 10 - Crosbie - lung cancer diagnoses in primary care │
--└───────────────────────────────────────────────────────────────────────────┘

set(StudyStartDate) = to_date('2016-01-01');
set(StudyEndDate)   = to_date('2024-08-01');

--> CODESET lung-cancer:1

{{create-output-table::"LH010-3_LungCancerDiagnosesPrimaryCare"}}
SELECT DISTINCT
	e."FK_Patient_ID"
	, dem."GmPseudo"
	, to_date("Date") AS "DiagnosisDate"
	, e."SCTID" AS "SnomedCode"
	, cs.concept
	, e."Term" AS "Description"
FROM INTERMEDIATE.GP_RECORD."Combined_EventsMedications_Clusters_SecondaryUses" e
LEFT JOIN {{code-set-table}} cs ON cs.code = e."SuppliedCode"
LEFT OUTER JOIN PRESENTATION.GP_RECORD."DemographicsProtectedCharacteristics_SecondaryUses" dem ON dem."FK_Patient_ID" = co."FK_Patient_ID" -- join to demographics table to get GmPseudo
WHERE cs.concept IN ('lung-cancer')
	AND "FK_Patient_ID" IN (SELECT "FK_Patient_ID" FROM {{cohort-table}})
	AND "Date" <= $StudyEndDate;
