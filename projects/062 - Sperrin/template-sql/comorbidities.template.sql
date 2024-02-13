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
WHERE FK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #Patients)
	AND SuppliedCode IN (SELECT code FROM #AllCodes);

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


-- Create the final table==========================================================================================================
IF OBJECT_ID('tempdb..#Final') IS NOT NULL DROP TABLE #Final;
SELECT * INTO #Final FROM #BackProblems
UNION
SELECT * FROM #BreastCancer
UNION
SELECT * FROM #BreastCancerScreening
UNION
SELECT * FROM #CHD
UNION
SELECT * FROM #ColorectalCancer
UNION 
SELECT * FROM #ColorectalCancerScreening
UNION
SELECT * FROM #COPD
UNION 
SELECT * FROM #Dementia
UNION
SELECT * FROM #Diabetes
UNION
SELECT * FROM #Falls
UNION
SELECT * FROM #FluVaccine
UNION
SELECT * FROM #LungCancer
UNION
SELECT * FROM #PancreaticCancer
UNION
SELECT * FROM #PneumococcalVaccine
UNION
SELECT * FROM #PostherpeticNeuralgia
UNION
SELECT * FROM #RTI
UNION
SELECT * FROM #Shingles
UNION
SELECT * FROM #Stroke

SELECT * FROM #Final
ORDER BY PatientID, EventDate;