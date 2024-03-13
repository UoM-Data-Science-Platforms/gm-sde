--+--------------------------------------------------------------------------------+
--¦ Patient information                                                            ¦
--+--------------------------------------------------------------------------------+
-- !!! NEED TO DO: WHEN WE HAVE WEEK OF BIRTH, PLEASE CHANGE THE QUERY-BUILD-RQ062-COHORT.SQL TO UPDATE THE COHORT. ALSO ADD WEEK OF BRTH FOR THE TABLE BELOW.
-- !!! NEED TO DO: DISCUSS TO MAKE SURE THE PROVIDED DATA IS NOT IDENTIFIABLE.

-------- RESEARCH DATA ENGINEER CHECK ---------


-- OUTPUT: Data with the following fields
-- - PatientId
-- - EventDate
-- - EventCode
-- - EventDescription
-- - EventCodeSystem (SNOMED, EMIS, ReadV2/CTV3)


--Just want the output, not the messages
SET NOCOUNT ON;


--> EXECUTE query-build-rq062-cohort.sql


-- Creat a smaller version of GP event table------------------------------------------------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#GPEvents') IS NOT NULL DROP TABLE #GPEvents;
SELECT FK_Patient_Link_ID, EventDate, FK_Reference_Coding_ID, FK_Reference_SnomedCT_ID, SuppliedCode
INTO #GPEvents
FROM SharedCare.GP_Events
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients);

--- create index on GP events table
DROP INDEX IF EXISTS GPEventIndex ON #GPEvents;
CREATE INDEX GPEventIndex ON #GPEvents (SuppliedCode) INCLUDE (FK_Patient_Link_ID, EventDate);


--> EXECUTE query-build-rq062-gp-events.sql version:1 conditionname:Shingles condition:shingles
--> EXECUTE query-build-rq062-gp-events.sql version:1 conditionname:PostherpeticNeuralgia condition:post-herpetic-neuralgia
--> EXECUTE query-build-rq062-gp-events.sql version:1 conditionname:CHD condition:coronary-heart-disease
--> EXECUTE query-build-rq062-gp-events.sql version:1 conditionname:Stroke condition:stroke
--> EXECUTE query-build-rq062-gp-events.sql version:1 conditionname:Dementia condition:dementia
--> EXECUTE query-build-rq062-gp-events.sql version:1 conditionname:COPD condition:copd
--> EXECUTE query-build-rq062-gp-events.sql version:1 conditionname:LungCancer condition:lung-cancer
--> EXECUTE query-build-rq062-gp-events.sql version:1 conditionname:PancreaticCancer condition:pancreatic-cancer
--> EXECUTE query-build-rq062-gp-events.sql version:1 conditionname:ColorectalCancer condition:colorectal-cancer
--> EXECUTE query-build-rq062-gp-events.sql version:1 conditionname:BreastCancer condition:breast-cancer
--> EXECUTE query-build-rq062-gp-events.sql version:1 conditionname:Falls condition:falls
--> EXECUTE query-build-rq062-gp-events.sql version:1 conditionname:BackProblems condition:back-problems
--> EXECUTE query-build-rq062-gp-events.sql version:1 conditionname:Diabetes condition:diabetes
--> EXECUTE query-build-rq062-gp-events.sql version:1 conditionname:FluVaccine condition:flu-vaccination
--> EXECUTE query-build-rq062-gp-events.sql version:1 conditionname:PneumococcalVaccine condition:pneumococcal-vaccination
--> EXECUTE query-build-rq062-gp-events.sql version:1 conditionname:BreastCancerScreening condition:breast-cancer-screening
--> EXECUTE query-build-rq062-gp-events.sql version:1 conditionname:ColorectalCancerScreening condition:colorectal-cancer-screening
--> EXECUTE query-build-rq062-gp-events.sql version:1 conditionname:RTI condition:respiratory-tract-infection
--> EXECUTE query-build-rq062-gp-events.sql version:1 conditionname:ShinglesVaccine condition:shingles-vaccination


--> CODESET flu-vaccine:1

DROP TABLE #GPEvents

-- get all vaccination records from GP_Medications table to add to the event codes later on

-- first for flu vaccination meds
IF OBJECT_ID('tempdb..#FluVaccineMed') IS NOT NULL DROP TABLE #FluVaccineMed;
CREATE TABLE #FluVaccineMed (PatientId BIGINT NOT NULL, EventDate DATE, 
EventCode VARCHAR(255), EventDescription VARCHAR(255) COLLATE Latin1_General_CS_AS /*, EventCodeSystem VARCHAR(255)*/);

INSERT INTO #FluVaccineMed (PatientId, EventDate, EventCode, EventDescription)
SELECT FK_Patient_Link_ID, 
		CAST(MedicationDate AS DATE), 
		SuppliedCode,
		a.description
FROM SharedCare.GP_Medications gp
LEFT OUTER JOIN #AllCodes a ON gp.SuppliedCode = a.Code
WHERE SuppliedCode IN 
	(SELECT Code FROM #AllCodes WHERE (Concept = 'flu-vaccine' AND [Version] = 1)) 
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)

-- second for shingles vaccination meds
IF OBJECT_ID('tempdb..#ShinglesVaccineMed') IS NOT NULL DROP TABLE #ShinglesVaccineMed;
CREATE TABLE #ShinglesVaccineMed (PatientId BIGINT NOT NULL, EventDate DATE, 
EventCode VARCHAR(255), EventDescription VARCHAR(255) COLLATE Latin1_General_CS_AS /*, EventCodeSystem VARCHAR(255)*/);

INSERT INTO #ShinglesVaccineMed (PatientId, EventDate, EventCode, EventDescription)
SELECT FK_Patient_Link_ID, 
		CAST(MedicationDate AS DATE), 
		SuppliedCode,
		a.description
FROM SharedCare.GP_Medications gp
LEFT OUTER JOIN #AllCodes a ON gp.SuppliedCode = a.Code
WHERE SuppliedCode IN 
	(SELECT Code FROM #AllCodes WHERE (Concept = 'shingles-vaccination' AND [Version] = 1)) 
AND FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)

-- Create the final table==========================================================================================================
IF OBJECT_ID('tempdb..#Final') IS NOT NULL DROP TABLE #Final;
SELECT *, 'back-problems' as Condition INTO #Final FROM #BackProblems
UNION
SELECT *, 'breast-cancer' as Condition FROM #BreastCancer
UNION
SELECT *, 'breast-cancer-screening' as Condition FROM #BreastCancerScreening
UNION
SELECT *, 'coronary-heart-disease' as Condition FROM #CHD
UNION
SELECT *, 'colorectal-cancer' as Condition FROM #ColorectalCancer
UNION 
SELECT *, 'colorectal-cancer-screening' as Condition FROM #ColorectalCancerScreening
UNION
SELECT *, 'copd' as Condition FROM #COPD
UNION 
SELECT *, 'dementia' as Condition FROM #Dementia
UNION
SELECT *, 'diabetes' as Condition FROM #Diabetes
UNION
SELECT *, 'falls' as Condition FROM #Falls
UNION
SELECT *, 'flu-vaccine' as Condition FROM #FluVaccine
UNION
SELECT *, 'lung-cancer' as Condition FROM #LungCancer
UNION
SELECT *, 'pancreatic-cancer' as Condition FROM #PancreaticCancer
UNION
SELECT *, 'pneumococcal-vaccine' as Condition FROM #PneumococcalVaccine
UNION
SELECT *, 'postherpetic-neuralgia' as Condition  FROM #PostherpeticNeuralgia
UNION
SELECT *, 'respiratory-tract-infection' as Condition  FROM #RTI
UNION
SELECT *, 'shingles' as Condition  FROM #Shingles
UNION
SELECT *, 'stroke' as Condition  FROM #Stroke
UNION
SELECT *, 'shingles-vaccination' as Condition  FROM #ShinglesVaccine
UNION 
SELECT *, 'flu-vaccine' as Condition FROM #FluVaccineMed
UNION 
SELECT *, 'shingles-vaccination' as Condition FROM #ShinglesVaccineMed

DROP TABLE #Shingles, #PostherpeticNeuralgia, #CHD, #Stroke, #Dementia, #COPD, #LungCancer, 
#PancreaticCancer, #ColorectalCancer, #BreastCancer, #Falls, #BackProblems, #Diabetes, #FluVaccine, 
#PneumococcalVaccine, #BreastCancerScreening, #ColorectalCancerScreening, #RTI, #ShinglesVaccine,
#FluVaccineMed 

SELECT PatientId,
	EventYearAndMonth = DATEADD(dd, -( DAY(EventDate) -1 ), EventDate), -- hide the day of the event by setting to first of the month,
	EventCode,
	EventCategory = Condition,
	EventDescription = REPLACE(EventDescription, ',',  '|') -- remove commas so they don't mess up CSV files
	--EventCodeSystem 
FROM #Final
ORDER BY PatientID, EventDate;