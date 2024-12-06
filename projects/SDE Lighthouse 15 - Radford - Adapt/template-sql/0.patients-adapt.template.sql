
--┌───────────────────────────────────────────────────────────────────────────┐
--│ LH015: provide IDs of all ADAPT patients (even those without a GP record) │
--└───────────────────────────────────────────────────────────────────────────┘

-------- RESEARCH DATA ENGINEER CHECK ------------

--------------------------------------------------

-- table of ADAPT patients
{{create-output-table::"LH015-0_AdaptPatients"}}
SELECT DISTINCT "GmPseudo", "AdaptDate"
FROM INTERMEDIATE.LOCAL_FLOWS_GM_ADAPT."Adapt";
--
