--┌────────────────────────────────────────────────────────────────────────────┐
--│ Create listing tables for each GP events - RQ062                           │
--└────────────────────────────────────────────────────────────────────────────┘
-- OBJECTIVE: To build the tables listing each requested GP events for RQ062. This reduces duplication of code in the template scripts.

-- COHORT: RQ062 cohort created from query-build-rq062-cohort.sql

-- NOTE: Need to fill the '{param:condition}' and '{param:version}' and {param:conditionname}

-- INPUT: Assumes there exists one temp table as follows:
-- #GPEvents (FK_Patient_Link_ID, EventDate, FK_Reference_Coding_ID, FK_Reference_SnomedCT_ID, SuppliedCode)

-- OUTPUT: A temp table #{param:conditionname} with columns:
-- - PatientId
-- - EventDate
-- - EventCode
-- - EventDescription
-- - EventCodeSystem (SNOMED, EMIS, ReadV2, CTV3)


------------------------------------------------------------------------------------------------------------------------------------------------------------
--> CODESET {param:condition}:{param:version}

IF OBJECT_ID('tempdb..#{param:conditionname}') IS NOT NULL DROP TABLE #{param:conditionname};
CREATE TABLE #{param:conditionname} (PatientId BIGINT NOT NULL, EventDate DATE, 
EventCode VARCHAR(255), EventDescription VARCHAR(255), EventCodeSystem VARCHAR(255));


INSERT INTO #{param:conditionname} (PatientId, EventDate, EventCode, EventDescription)
SELECT	FK_Patient_Link_ID, 
		CONVERT(date, EventDate),
		SuppliedCode,
		a.description
FROM #GPEvents gp
LEFT OUTER JOIN #AllCodes a ON gp.SuppliedCode = a.Code
WHERE (SuppliedCode IN (SELECT Code FROM #AllCodes WHERE (Concept = '{param:condition}' AND [Version] = {param:version}))) AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
ORDER BY SuppliedCode;

UPDATE #{param:conditionname}
SET EventCodeSystem = 'ReadV2/CTV3'

UPDATE #{param:conditionname}
SET EventCodeSystem = 'SNOMED'
WHERE UPPER(EventCode) LIKE '[0-9][0-9][0-9][0-9][0-9][0-9]%'

UPDATE #{param:conditionname}
SET EventCodeSystem = 'EMIS'
WHERE UPPER(EventCode) LIKE '%EMIS%' OR UPPER(EventCode) LIKE '%ESCT%'