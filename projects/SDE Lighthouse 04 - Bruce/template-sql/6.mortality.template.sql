--┌──────────────────────────────────────┐
--│ LH004 Mortality file                 │
--└──────────────────────────────────────┘

--> EXECUTE query-build-lh004-cohort.sql

SELECT "RegisteredDateOfDeath", "DiagnosisUnderlyingCode" FROM PRESENTATION.NATIONAL_FLOWS_PCMD."DS1804_Pcmd"
WHERE "GmPseudo" IN (SELECT "GmPseudo" FROM LH004_Cohort);