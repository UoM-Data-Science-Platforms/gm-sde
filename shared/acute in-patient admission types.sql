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
-- 11	Elective - Waiting List	154376
-- 12	Elective - Booked	35929
-- 13	Elective - Planned	55318
-- BL	ELECTIVE BOOKED	33532
-- IPPlannedAd	IP Planned Admission	142
-- PL	ELECTIVE PLANNED	187587
-- TR	PLAN TRANS TO TRUST	2766
-- WL	ELECTIVE WL	70331

-- UNKNOWN
-- 18	CHILDRENS ONLY	938
-- 31	Maternity ante-partum	74248
-- 32	Maternity post-partum	2003
-- 81	Transfer from other hosp (not A&E)	3266
-- 82	Birth in this Health Care Provider	11062
-- AN	MATERNITY ANTENATAL	34248
-- BH	BABY BORN IN HOSP	60438
-- BHOSP	Birth in this Health Care Provider	1646
-- ET	EM TRAN (OTHER PROV)	1395
-- GP	GP OR LOCUM GP	29044
-- HospTran	Transfer from other NHS Hospital	455
-- IC	INTERMEDIATE CARE	107
-- Medical	 Medical	237
-- NSP	Not Specified	451
-- OP	DIRECT OUTPAT CLINIC	1369
-- PN	MATERNITY POST NATAL	2778
-- T	TRANSFER	434

-- NON-ELECTIVE
-- 21	Emergency - Local A&E	238721
-- 22	Emergency - GP	25199
-- 23	Emergency - Bed Bureau	24242
-- 24	Emergency - Clinic	5740
-- 28	Emergency - Other (inc other provider A&E)	7102
-- 2A	A+E Department of another provider where the Patient has not been admitted	272
-- 2D	Emergency - Other	6466
-- A+E Admission	 A+E Admission	243
-- AE	AE.DEPT.OF PROVIDER	294024
-- AI	ACUTE TO INTMED CARE	2579
-- BB	EMERGENCY BED BUREAU	889
-- DO	EMERGENCY DOMICILE	813
-- EM	EMERGENCY OTHER	10334
-- Emerg GP	Emergency GP Patient	141

