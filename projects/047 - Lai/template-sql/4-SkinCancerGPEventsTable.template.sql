--+--------------------------------------------------------------------------------+
--¦ Skin cancer information from the GPEvents table (cohort 1)                     ¦
--+--------------------------------------------------------------------------------+

-------- RESEARCH DATA ENGINEER CHECK ---------

-- OUTPUT: Data with the following fields
-- PatientId
-- EventDate (YYYY-MM-DD)
-- SkinCancerRelatedCode (code values)


--> CODESET skin-cancer:1


-- Set the start date
DECLARE @StartDate datetime;
DECLARE @EndDate datetime;
SET @StartDate = '2011-01-01';
SET @EndDate = '2022-06-01';

--Just want the output, not the messages
SET NOCOUNT ON;


-- Create the skin cancer cohort=====================================================================================================================================
IF OBJECT_ID('tempdb..#SkinCohort') IS NOT NULL DROP TABLE #SkinCohort;
SELECT DISTINCT FK_Patient_Link_ID
INTO #SkinCohort
FROM SharedCare.GP_Events
WHERE (SuppliedCode IN (SELECT Code FROM #AllCodes WHERE (Concept = 'skin-cancer' AND [Version] = 1)))
      AND EventDate >= @StartDate AND EventDate < @EndDate;


-- Select event date and skin cancer related codes====================================================================================================================
IF OBJECT_ID('tempdb..#SkinCohortCodes') IS NOT NULL DROP TABLE #SkinCohortCodes;
SELECT FK_Patient_Link_ID AS PatientId, EventDate, SuppliedCode AS SkinCancerRelatedCode
INTO #SkinCohortCodes
FROM SharedCare.GP_Events
WHERE (SuppliedCode IN (SELECT Code FROM #AllCodes WHERE (Concept = 'skin-cancer' AND [Version] = 1))) AND EventDate < @EndDate
ORDER BY FK_Patient_Link_ID, EventDate;


