--┌────────────────────────────────────────────────┐
--│ Prevalence for each event cluster in snowflake │
--└────────────────────────────────────────────────┘

-- OBJECTIVE: To provide a report on the proportion of patients who have a particular
--            clinical concept in their record

-- INPUT: No pre-requisites

-- OUTPUT:
-- 	- Cluster - the event codeset 
--  - All_Patients - count of all patients in the database
--  - Alive_Patients - count of all alive patients in the database
--  - Patients_With_Event - the number of patients with a clinical code for this code set in their record
--  - PercentageOfPatients  - the percentage of patients that have had a event code for each cluster
--  - PercentageOfAlivePatients - the percentage of alive patients that have had a event code for each cluster
--  - ReadMeText - Text to paste into the README file

-------- NOTE: If this takes a long time to run, consider saving in a permanent table in snowflake so 
-------- it doesn't need to be run again until it needs updating 
-------- Table currently saved as EVENTSCLUSTERSPREVALENCE in snowflake

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


-- GET ALL PATIENTS THAT HAVE EVER HAD AN EVENT FROM EACH CLUSTER

DROP TABLE IF EXISTS events;
CREATE TEMPORARY TABLE events AS
SELECT DISTINCT
      "FK_Patient_ID",
      "Cluster_ID"
FROM INTERMEDIATE.GP_RECORD."EventsClusters" ;

-- DECLARE A VARIABLE SO THAT THE TOTAL NUMBER OF PATIENTS CAN BE ACCESSED

DECLARE AllPatientCount INT;
        AllPatientsAliveCount INT;

BEGIN
AllPatientCount := (select count(*) from ALLPATIENTS); 
AllPatientsAliveCount := (select count(*) from ALLPATIENTSALIVE);

-- CREATE A TABLE WITH TOTAL PATIENTS, PATIENTS WITH EVENT, PERCENTAGE OF TOTAL, AND PERCENTAGE OF ALIVE PATIENTS

DROP TABLE IF EXISTS Final;
CREATE TEMPORARY TABLE Final AS 
SELECT 
    Cluster,
    :AllPatientCount AS "All_Patients",
    :AllPatientsAliveCount AS "Alive_Patients",
    SUM(CASE WHEN EventsID IS NOT NULL THEN 1 ELSE 0 END) AS "Patients_With_Event",
    ROUND(SUM(CASE WHEN EventsID IS NOT NULL THEN 1 ELSE 0 END) / :AllPatientCount * 100,2) AS "Percentage",
    ROUND(SUM(CASE WHEN EventsID IS NOT NULL THEN 1 ELSE 0 END) / :AllPatientsAliveCount * 100,2) AS "PercentageOfAlivePatients",
    CONCAT(CURRENT_DATE(), ' | ',  :AllPatientCount, ' | ', :AllPatientsAliveCount, ' | ', 
           SUM(CASE WHEN EventsID IS NOT NULL THEN 1 ELSE 0 END), ' | ',
           ROUND(SUM(CASE WHEN EventsID IS NOT NULL THEN 1 ELSE 0 END) / :AllPatientCount * 100,2), ' |',
           ROUND(SUM(CASE WHEN EventsID IS NOT NULL THEN 1 ELSE 0 END) / :AllPatientsAliveCount * 100,2), ' | ') AS "ReadMeText"
FROM (
    SELECT ap."FK_Patient_ID" AS AllPatientsID, p."FK_Patient_ID" AS EventsID, p."Cluster_ID" AS Cluster
    FROM AllPatients ap
    LEFT OUTER JOIN events p ON p."FK_Patient_ID" = ap."FK_Patient_ID"
    ) SUB
GROUP BY Cluster;

END; 

SELECT * 
FROM Final

{{no-output-table}}