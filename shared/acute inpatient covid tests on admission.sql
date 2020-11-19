-- Get all admissions for Wythenshawe for August onwards
IF OBJECT_ID('tempdb..#WythenshaweAdmissions') IS NOT NULL DROP TABLE #WythenshaweAdmissions;
SELECT a.[FK_Patient_Link_ID],
      [AdmissionDate] into #WythenshaweAdmissions
  FROM [RLS].[vw_Acute_Inpatients] a
  WHERE a.EventType = 'Admission'
  AND FK_Reference_Tenancy_ID = 6
  and AdmissionDate >= '2020-08-01';
--29445 admissions

-- Get count of admissions per month
IF OBJECT_ID('tempdb..#MonthlyAdmissions') IS NOT NULL DROP TABLE #MonthlyAdmissions;
SELECT MONTH(AdmissionDate) as MonthOfAdmission, count(*) as Freq INTO #MonthlyAdmissions FROM #WythenshaweAdmissions
GROUP BY MONTH(AdmissionDate)
ORDER BY MONTH(AdmissionDate);
-- MonthOfAdmission	Freq
--				8	7894
--				9	8683
--				10	9051
--				11	3817
-- (query run during November)

-- Find number of people with anything in the COVID table on same day as admission
IF OBJECT_ID('tempdb..#CovidTests') IS NOT NULL DROP TABLE #CovidTests;
SELECT MONTH(AdmissionDate) as MonthOfAdmission, count(*) as SameDayCovidTest INTO #CovidTests FROM (
	SELECT a.[FK_Patient_Link_ID], AdmissionDate
	FROM #WythenshaweAdmissions a
	INNER JOIN RLS.vw_COVID19 c on c.FK_Patient_Link_ID = a.FK_Patient_Link_ID and CONVERT(date,AdmissionDate) = CONVERT(date,EventDate)
	GROUP BY a.[FK_Patient_Link_ID], AdmissionDate
) sub
GROUP BY MONTH(AdmissionDate);

-- Find number of people with anything in the COVID table within 1 week of admission
IF OBJECT_ID('tempdb..#CovidTests1Week') IS NOT NULL DROP TABLE #CovidTests1Week;
SELECT MONTH(AdmissionDate) as MonthOfAdmission, count(*) as SameWeekCovidTest INTO #CovidTests1Week FROM (
	SELECT a.[FK_Patient_Link_ID], AdmissionDate
	FROM #WythenshaweAdmissions a
	INNER JOIN RLS.vw_COVID19 c 
		on c.FK_Patient_Link_ID = a.FK_Patient_Link_ID 
		and CONVERT(date,AdmissionDate) <= CONVERT(date,EventDate)
		and CONVERT(date,EventDate) < DATEADD(week,1,CONVERT(date,EventDate))
	GROUP BY a.[FK_Patient_Link_ID], AdmissionDate
) sub
GROUP BY MONTH(AdmissionDate);

select m.MonthOfAdmission, m.Freq as NumberOfAdmissions, c.SameDayCovidTest, w.SameWeekCovidTest from #MonthlyAdmissions m
	inner join #CovidTests c on c.MonthOfAdmission = m.MonthOfAdmission
	inner join #CovidTests1Week w on w.MonthOfAdmission = m.MonthOfAdmission
order by m.MonthOfAdmission

-- MonthOfAdmission	NumberOfAdmissions	SameDayCovidTest	SameWeekCovidTest
-- 8	7894	62	717
-- 9	8683	57	572
-- 10	9051	108	575
-- 11	3817	37	93
