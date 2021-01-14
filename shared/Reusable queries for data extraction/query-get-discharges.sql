--┌──────────────────────┐
--│ Secondary discharges │
--└──────────────────────┘

-- OBJECTIVE: To obtain a table with every secondary care discharge, along with the acute provider,
--						and the date of discharge.

-- INPUT: No pre-requisites

-- OUTPUT: A temp table as follows:
-- #Discharges (FK_Patient_Link_ID, DischargeDate, AcuteProvider)
-- 	- FK_Patient_Link_ID - unique patient id
--	- DischargeDate - date of discharge (YYYY-MM-DD)
--	- AcuteProvider - Bolton, SRFT, Stockport etc..
--  (Limited to one discharge per person per hospital per day, because if a patient has 2 discharges 
--   on the same day to the same hopsital then it's most likely data duplication rather than two short
--   hospital stays)

-- Populate temporary table with discharges
IF OBJECT_ID('tempdb..#Discharges') IS NOT NULL DROP TABLE #Discharges;
SELECT DISTINCT FK_Patient_Link_ID, CONVERT(DATE, DischargeDate) AS DischargeDate, t.TenancyName AS AcuteProvider INTO #Discharges FROM [RLS].[vw_Acute_Inpatients] i
LEFT OUTER JOIN SharedCare.Reference_Tenancy t ON t.PK_Reference_Tenancy_ID = i.FK_Reference_Tenancy_ID
WHERE EventType = 'Discharge'
AND DischargeDate >= @StartDate;
-- 535285 rows	535285 rows
-- 00:00:28		00:00:14
