
-- Populate temporary table with admissions
-- Convert AdmissionDate to a date to avoid issues where a person has two admissions
-- on the same day (but only one discharge)
IF OBJECT_ID('tempdb..#Admissions') IS NOT NULL DROP TABLE #Admissions;
select DISTINCT FK_Patient_Link_ID, CONVERT(DATE, AdmissionDate) as AdmissionDate into #Admissions from [RLS].[vw_Acute_Inpatients]
where EventType = 'Admission'
and AdmissionDate is not null;
-- 1227586 rows

-- Populate temporary table with discharges
IF OBJECT_ID('tempdb..#Discharges') IS NOT NULL DROP TABLE #Discharges;
select DISTINCT FK_Patient_Link_ID, CONVERT(DATE, DischargeDate) as DischargeDate into #Discharges from [RLS].[vw_Acute_Inpatients]
where EventType = 'Discharge'
and DischargeDate is not null
-- 1244024 rows

-- Link admission with discharge to get length of stay
-- Length of stay is zero-indexed e.g. 
-- < 1 day = 0
-- < 2 days = 1
SELECT a.FK_Patient_Link_ID, a.AdmissionDate, MIN(d.DischargeDate) as discharge, DATEDIFF(day,a.AdmissionDate, MIN(d.DischargeDate)) as LengthOfStay FROM #Admissions a
inner join #Discharges d on d.FK_Patient_Link_ID = a.FK_Patient_Link_ID and d.DischargeDate >= a.AdmissionDate
GROUP BY a.FK_Patient_Link_ID, a.AdmissionDate
order by a.FK_Patient_Link_ID, a.AdmissionDate
-- 1209764 rows