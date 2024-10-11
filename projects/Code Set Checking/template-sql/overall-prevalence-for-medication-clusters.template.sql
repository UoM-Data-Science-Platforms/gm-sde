--┌─────────────────────────────────────────────────────┐
--│ Prevalence for each medication cluster in snowflake │
--└─────────────────────────────────────────────────────┘

-- OBJECTIVE: To provide a report on the proportion of patients who have a particular
--            clinical concept in their record

-- INPUT: No pre-requisites

-- OUTPUT: 
-- 	- Cluster - the medication codeset 
--  - All_Patients - count of all patients in the database
--  - Alive_Patients - count of all alive patients in the database
--  - Patients_Prescribed_Med - the number of patients with a clinical code for this code set in their record
--  - PercentageOfPatients  - the percentage of patients for this system supplier with this concept
--  - ReadMeText - Text to paste into the README file

-- GET ALL PATIENTS THAT EXIST IN THE PRIMARY CARE DATA

DROP TABLE IF EXISTS AllPatients;
CREATE TEMPORARY TABLE AllPatients AS
SELECT DISTINCT "FK_Patient_ID"
FROM INTERMEDIATE.GP_RECORD."DemographicsProtectedCharacteristics";


-- SAME AS ABOVE BUT FOR CURRENTLY ALIVE PATIENTS ONLY

DROP TABLE IF EXISTS AllPatientsAlive;
CREATE TEMPORARY TABLE AllPatientsAlive AS
SELECT DISTINCT "FK_Patient_ID"
FROM INTERMEDIATE.GP_RECORD."DemographicsProtectedCharacteristics" d
LEFT JOIN PRESENTATION.NATIONAL_FLOWS_PCMD."DS1804_Pcmd" dth
    ON dth."GmPseudo" = d."GmPseudo"
WHERE dth."GmPseudo" IS NULL;

-- GET ALL PATIENTS THAT HAVE EVER HAD A PRESCRIPTION WITHIN EACH MEDICATION CLUSTER 

DROP TABLE IF EXISTS prescriptions;
CREATE TEMPORARY TABLE prescriptions AS
SELECT DISTINCT
      "FK_Patient_ID",
      "Cluster_ID"
FROM INTERMEDIATE.GP_RECORD."MedicationsClusters";

-- DECLARE A VARIABLE SO THAT THE TOTAL NUMBER OF PATIENTS CAN BE ACCESSED

DECLARE AllPatientCount INT;
        AllPatientsAliveCount INT;

BEGIN
AllPatientCount := (select count(*) from ALLPATIENTS); 
AllPatientsAliveCount := (select count(*) from ALLPATIENTSALIVE);

-- CREATE A TABLE WITH TOTAL PATIENTS, PATIENTS EVER PRESCRIBED MED, AND PERCENTAGE OF TOTAL

DROP TABLE IF EXISTS Final;
CREATE TEMPORARY TABLE Final AS 
SELECT 
    Cluster,
    :AllPatientCount AS "All_Patients",
    :AllPatientsAliveCount AS "Alive_Patients",
    SUM(CASE WHEN PrescriptionsID IS NOT NULL THEN 1 ELSE 0 END) AS "Patients_Prescribed_Med",
    ROUND(SUM(CASE WHEN PrescriptionsID IS NOT NULL THEN 1 ELSE 0 END) / :AllPatientCount * 100,2) AS "Percentage",
    ROUND(SUM(CASE WHEN PrescriptionsID IS NOT NULL THEN 1 ELSE 0 END) / :AllPatientsAliveCount * 100,2) AS "PercentageOfAlivePatients",
    CONCAT(CURRENT_DATE(), ' | ',  :AllPatientCount, ' | ', :AllPatientsAliveCount, ' | ', 
           SUM(CASE WHEN PrescriptionsID IS NOT NULL THEN 1 ELSE 0 END), ' | ',
           ROUND(SUM(CASE WHEN PrescriptionsID IS NOT NULL THEN 1 ELSE 0 END) / :AllPatientCount * 100,2), ' |',
           ROUND(SUM(CASE WHEN PrescriptionsID IS NOT NULL THEN 1 ELSE 0 END) / :AllPatientsAliveCount * 100,2), ' | ') AS "ReadMeText"
FROM (
    SELECT ap."FK_Patient_ID" AS AllPatientsID, p."FK_Patient_ID" AS PrescriptionsID, p."Cluster_ID" AS Cluster
    FROM AllPatients ap
    LEFT OUTER JOIN prescriptions p ON p."FK_Patient_ID" = ap."FK_Patient_ID"
    ) SUB
GROUP BY Cluster;

END; 

SELECT * FROM Final;


{{no-output-table}}