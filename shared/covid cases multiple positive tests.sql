-- Find the all the positive tests for each patient. We convert the EventDate
-- to a Date (rather than a DateTime) to ensure that multiple test results on the
-- same day (probably a duplication, but definitely related to the same spell) only
-- get counted once.
IF OBJECT_ID('tempdb..#COVIDPatientDiagnoses') IS NOT NULL DROP TABLE #COVIDPatientDiagnoses;
SELECT c.FK_Patient_Link_ID, CONVERT(DATE, EventDate) as [Date] INTO #COVIDPatientDiagnoses
FROM RLS.vw_COVID19 c
  INNER JOIN RLS.vw_Patient p ON p.FK_Patient_Link_ID = c.FK_Patient_Link_ID
WHERE FK_Reference_Tenancy_ID = 2
  -- If looking for tests rather than positive cases can use 'Tested' and 'Tested for immunity'
  -- but we just want confirmed cases at the moment.
  AND GroupDescription IN ('Confirmed') 
  AND EventDate > '2020-03-01' -- There are plenty of +Ve results prior to this which we can assume are erroneous
GROUP BY c.FK_Patient_Link_ID, CONVERT(DATE, EventDate);

-- Find how many people had their first and last +ve result within a certain time period
SELECT CASE WHEN Days = 0 THEN 'Same day' WHEN Days < 7 THEN 'Within 1 week' WHEN DAYS < 14 THEN 'Within 2 weeks' WHEN DAYS < 21 THEN 'Within 3 weeks' WHEN DAYS < 28 THEN 'Within 4 weeks' ELSE 'Over 4 weeks' END as Weeks , count(*) FROM (
SELECT FK_Patient_Link_ID, DATEDIFF(day,MIN([DATE]),MAX([DATE])) as Days FROM #COVIDPatientDiagnoses
GROUP BY FK_Patient_Link_ID) sub
GROUP BY CASE WHEN Days = 0 THEN 'Same day' WHEN Days < 7 THEN 'Within 1 week' WHEN DAYS < 14 THEN 'Within 2 weeks' WHEN DAYS < 21 THEN 'Within 3 weeks' WHEN DAYS < 28 THEN 'Within 4 weeks' ELSE 'Over 4 weeks' END;

-- Find patients with the largest time gap
SELECT FK_Patient_Link_ID, DATEDIFF(day,MIN([DATE]),MAX([DATE])) as Days FROM #COVIDPatientDiagnoses
GROUP BY FK_Patient_Link_ID
ORDER BY  DATEDIFF(day,MIN([DATE]),MAX([DATE])) desc

