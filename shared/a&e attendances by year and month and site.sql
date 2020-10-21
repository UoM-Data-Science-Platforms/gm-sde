-- Get the number of A&E attendances broken down by month and year and site (tenancy)
SELECT TenancyName, YEAR(AttendanceDate), MONTH(AttendanceDate), count(*)
  FROM [RLS].[vw_Acute_AE] a
INNER JOIN SharedCare.Reference_Tenancy r on r.PK_Reference_Tenancy_ID = FK_Reference_Tenancy_ID
  WHERE EventType = 'Attendance'
  AND AttendanceDate >= '2015-01-01'
  GROUP BY TenancyName, YEAR(AttendanceDate), MONTH(AttendanceDate)
  ORDER BY YEAR(AttendanceDate), MONTH(AttendanceDate),TenancyName

-- As can be seen below not all hospitals have reported for all time.

-- Example output
-- Central Manchester University Hospitals	2020	1	9667
-- Pennine Acute Hospitals	2020	1	19684
-- Tameside Hospital - TGICFT	2020	1	22513
-- University Hospital of South Manchester	2020	1	3800
-- Central Manchester University Hospitals	2020	2	8162
-- Pennine Acute Hospitals	2020	2	15868
-- Tameside Hospital - TGICFT	2020	2	20069
-- University Hospital of South Manchester	2020	2	3183
-- Central Manchester University Hospitals	2020	3	9099
-- Pennine Acute Hospitals	2020	3	16366
-- Tameside Hospital - TGICFT	2020	3	21146
-- University Hospital of South Manchester	2020	3	3576
-- Central Manchester University Hospitals	2020	4	7871
-- Pennine Acute Hospitals	2020	4	14927
-- Tameside Hospital - TGICFT	2020	4	7858
-- University Hospital of South Manchester	2020	4	4533
-- Central Manchester University Hospitals	2020	5	9425
-- Pennine Acute Hospitals	2020	5	20024
-- Salford Royal NHS Foundation Trust	2020	5	2
-- Tameside Hospital - TGICFT	2020	5	17665
-- University Hospital of South Manchester	2020	5	6116
-- Wrightington Wigan and Leigh NHSFT	2020	5	2428
-- Central Manchester University Hospitals	2020	6	10488
-- Pennine Acute Hospitals	2020	6	22918
-- Salford Royal NHS Foundation Trust	2020	6	1
-- Tameside Hospital - TGICFT	2020	6	17233
-- University Hospital of South Manchester	2020	6	6771
-- Wrightington Wigan and Leigh NHSFT	2020	6	7178
-- Central Manchester University Hospitals	2020	7	12279
-- Pennine Acute Hospitals	2020	7	25310
-- Salford Royal NHS Foundation Trust	2020	7	2655
-- Tameside Hospital - TGICFT	2020	7	16700
-- University Hospital of South Manchester	2020	7	7627
-- Wrightington Wigan and Leigh NHSFT	2020	7	6008
-- Central Manchester University Hospitals	2020	8	12443
-- Pennine Acute Hospitals	2020	8	25993
-- Salford Royal NHS Foundation Trust	2020	8	7384
-- Tameside Hospital - TGICFT	2020	8	22812
-- University Hospital of South Manchester	2020	8	8018
-- Wrightington Wigan and Leigh NHSFT	2020	8	8059
-- Central Manchester University Hospitals	2020	9	12154
-- Pennine Acute Hospitals	2020	9	26140
-- Salford Royal NHS Foundation Trust	2020	9	11070
-- Tameside Hospital - TGICFT	2020	9	21744
-- University Hospital of South Manchester	2020	9	7839
-- Wrightington Wigan and Leigh NHSFT	2020	9	7927
-- Central Manchester University Hospitals	2020	10	7057
-- Pennine Acute Hospitals	2020	10	15624
-- Salford Royal NHS Foundation Trust	2020	10	6220
-- Tameside Hospital - TGICFT	2020	10	13390
-- University Hospital of South Manchester	2020	10	4996
-- Wrightington Wigan and Leigh NHSFT	2020	10	4654