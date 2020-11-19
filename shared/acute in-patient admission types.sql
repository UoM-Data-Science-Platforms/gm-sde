-- Get all AdmissionTypeCodes and descriptions that occur more than
-- 100 times (to avoid data quality issues)
IF OBJECT_ID('tempdb..#AdmissionTypeCounts') IS NOT NULL DROP TABLE #AdmissionTypeCounts;
SELECT AdmissionTypeCode, AdmissionTypeDescription, count(*) as tot INTO #AdmissionTypeCounts
FROM [RLS].[vw_Acute_Inpatients]
where EventType ='Admission'
and AdmissionTypeCode is not null
group by AdmissionTypeCode, AdmissionTypeDescription
having count(*) > 100;

-- Link table to itself to get for each unique AdmissionTypeCode the most
-- frequently occurring description
SELECT a.AdmissionTypeCode, MAX(a.AdmissionTypeDescription) as [Description], MAX(a.tot) as [Count] FROM #AdmissionTypeCounts a
INNER JOIN (
	SELECT AdmissionTypeCode, MAX(tot) as maxCount 
	FROM #AdmissionTypeCounts 
	GROUP BY AdmissionTypeCode
) b ON b.AdmissionTypeCode = a.AdmissionTypeCode AND a.tot = b.maxCount
GROUP BY a.AdmissionTypeCode

-- Current (Oct 2020) data below split into elective / non-elective

-- ELECTIVE
-- PL	ELECTIVE PLANNED	187587
-- 11	Elective - Waiting List	154376
-- WL	ELECTIVE WL	70331
-- 13	Elective - Planned	55318
-- 12	Elective - Booked	35929
-- BL	ELECTIVE BOOKED	33532
-- TR	PLAN TRANS TO TRUST	2766
-- IPPlannedAd	IP Planned Admission	142

-- UNKNOWN
-- 31	Maternity ante-partum	74248
-- BH	BABY BORN IN HOSP	60438
-- AN	MATERNITY ANTENATAL	34248
-- GP	GP OR LOCUM GP	29044
-- 82	Birth in this Health Care Provider	11062
-- 81	Transfer from other hosp (not A&E)	3266
-- PN	MATERNITY POST NATAL	2778
-- 32	Maternity post-partum	2003
-- BHOSP	Birth in this Health Care Provider	1646
-- ET	EM TRAN (OTHER PROV)	1395
-- OP	DIRECT OUTPAT CLINIC	1369
-- 18	CHILDRENS ONLY	938
-- HospTran	Transfer from other NHS Hospital	455
-- NSP	Not Specified	451
-- T	TRANSFER	434
-- Medical	 Medical	237
-- IC	INTERMEDIATE CARE	107

-- NON-ELECTIVE
-- AE	AE.DEPT.OF PROVIDER	294024
-- 21	Emergency - Local A&E	238721
-- 22	Emergency - GP	25199
-- 23	Emergency - Bed Bureau	24242
-- EM	EMERGENCY OTHER	10334
-- 28	Emergency - Other (inc other provider A&E)	7102
-- 2D	Emergency - Other	6466
-- 24	Emergency - Clinic	5740
-- AI	ACUTE TO INTMED CARE	2579
-- BB	EMERGENCY BED BUREAU	889
-- DO	EMERGENCY DOMICILE	813
-- 2A	A+E Department of another provider where the Patient has not been admitted	272
-- A+E Admission	 A+E Admission	243
-- Emerg GP	Emergency GP Patient	141

