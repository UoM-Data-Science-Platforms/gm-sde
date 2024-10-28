-- Get the number of A&E attendances broken down by month and year
SELECT YEAR(AttendanceDate), MONTH(AttendanceDate), COUNT(*)
  FROM [RLS].[vw_Acute_AE]
WHERE EventType = 'Attendance'
  AND AttendanceDate >= '2015-01-01'
GROUP BY YEAR(AttendanceDate), MONTH(AttendanceDate)
ORDER BY YEAR(AttendanceDate), MONTH(AttendanceDate)

-- Not all sites have always reported
-- E.g. currently (Oct 2020) 6 acute trusts feeding in but up to May 2020 there were only 4 - hence the recent rise in admissions 

-- Example output
-- 2019	1	33672
-- 2019	2	31514
-- 2019	3	45989
-- 2019	4	46818
-- 2019	5	48363
-- 2019	6	42058
-- 2019	7	44550
-- 2019	8	50706
-- 2019	9	52124
-- 2019	10	53459
-- 2019	11	56259
-- 2019	12	55187
-- 2020	1	55664
-- 2020	2	47282
-- 2020	3	50187
-- 2020	4	35189
-- 2020	5	55660
-- 2020	6	64589
-- 2020	7	70579
-- 2020	8	84709
-- 2020	9	86874
-- 2020	10	51941