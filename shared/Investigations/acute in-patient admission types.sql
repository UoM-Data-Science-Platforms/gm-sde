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
ORDER BY MAX(a.tot) DESC

--PLANNED
-- PL	ELECTIVE PLANNED	204845
-- 11	Elective - Waiting List	161183
-- WL	ELECTIVE WL	75933
-- 13	Elective - Planned	58921
-- 12	Elective - Booked	37468
-- BL	ELECTIVE BOOKED	36475
-- D	NULL	11805
-- Endoscopy	Endoscopy	1537
-- OP	DIRECT OUTPAT CLINIC	1474
-- Venesection	X36.2 Venesection	830
-- Colonoscopy	H22.9 Colonoscopy	591
-- Medical	 Medical	486

--UNPLANNED
-- AE	AE.DEPT.OF PROVIDER	315265
-- 21	Emergency - Local A&E	252606
-- I	NULL	45379
-- GP	GP OR LOCUM GP	30651
-- 22	Emergency - GP	26028
-- 23	Emergency - Bed Bureau	25329
-- 28	Emergency - Other (inc other provider A&E)	7102
-- 2D	Emergency - Other	6466
-- 24	Emergency - Clinic	6078
-- EM	EMERGENCY OTHER	11103
-- AI	ACUTE TO INTMED CARE	2754
-- BB	EMERGENCY BED BUREAU	1028
-- DO	EMERGENCY DOMICILE	995
-- 2A	A+E Department of another provider where the Patient has not been admitted	342
-- A+E Admission	 A+E Admission	266
-- Emerg GP	Emergency GP Patient	170

--MATERNITY
-- 31	Maternity ante-partum	78648
-- BH	BABY BORN IN HOSP	67736
-- AN	MATERNITY ANTENATAL	36778
-- 82	Birth in this Health Care Provider	11062
-- PN	MATERNITY POST NATAL	3024
-- B	NULL	2494
-- 32	Maternity post-partum	2166
-- BHOSP	Birth in this Health Care Provider	1954

--TRANSFER
-- 81	Transfer from other hosp (not A&E)	3401
-- TR	PLAN TRANS TO TRUST	3164
-- ET	EM TRAN (OTHER PROV)	1652
-- HospTran	Transfer from other NHS Hospital	1074
-- T	TRANSFER	541
-- CentTrans	Transfer from CEN Site	118

--OTHER
-- 18	CHILDRENS ONLY	1053
-- NSP	Not Specified	455
-- Blood test	X36.9 Blood test	317
-- Flex sigmoidosco	H25.9 Flexible sigmoidoscopy FOS	270
-- Infliximab	X92.1 Infliximab	244
-- IPPlannedAd	IP Planned Admission	205
-- Blood transfusio	X33.9 Blood transfusion	201
-- S.I. joint inj	W90.3 S.I. joint injections	191
-- Daycase	 Daycase	190
-- Extraction Multi	F10.4 Extraction of Multi Teeth	174
-- Chemotherapy	X35.2 Chemotherapy	133
-- IC	INTERMEDIATE CARE	118
-- Total knee rep c	W40.1 Primary total prosthetic replacement of knee joint using cement	111
-- Total rep hip ce	W37.1 Primary total prosthetic replacement of hip joint using cement	111

-- "B" is classed under MATERNITY based on this query:
SELECT WardDescription, SpecialtyCode, COUNT(*) AS Frequency
FROM [RLS].[vw_Acute_Inpatients]
WHERE EventType='Admission'
AND AdmissionTypeCode = 'B'
GROUP BY WardDescription, SpecialtyCode
HAVING COUNT(*) > 20
ORDER BY COUNT(*) DESC;
-- WardDescription	SpecialtyCode	Frequency
-- Delivery Suite Cots	PAED	2006
-- Birth Centre Cots	PAED	291
-- M2 Cots	PAED	57
-- Home Address	MW	37
-- Delivery Suite Cots	MW	28
-- Home Address	PAED	25
-- Neonatal Unit	PAED	23
-- ...

SELECT WardDescription, SpecialtyCode, COUNT(*) AS Frequency
FROM [RLS].[vw_Acute_Inpatients]
WHERE EventType='Admission'
AND AdmissionTypeCode = 'D'
GROUP BY WardDescription, SpecialtyCode
ORDER BY COUNT(*) DESC;
-- WardDescription	SpecialtyCode	Frequency
-- Endoscopy Suite	SURG	1799
-- The Eye Centre	OPTH	1535
-- Laurel Suite	HAEM	967
-- Endoscopy Suite	GMED	692
-- Medical Day Case Unit	GMED	644
-- Department Of Medicine For Older People	GER	485
-- Department Of Medicine For Older People	RHEU	392
-- Maple Suite	TO	385
-- Alexandra Hospital Ward	SURG	379
-- Alexandra Hospital Ward	UROL	295
-- Ward D5	OSUR	264
-- Maple Suite	UROL	230
-- Ward D5	UROL	217
-- Ward D5	TO	214
-- Cardiac Catheterisation Suite	CARD	200
-- Jasmine Ward	GYN	178

SELECT ReasonForAdmissionCode, COUNT(*) AS Frequency
FROM [RLS].[vw_Acute_Inpatients]
WHERE EventType='Admission'
AND AdmissionTypeCode = 'D'
GROUP BY ReasonForAdmissionCode
ORDER BY COUNT(*) DESC;
-- ReasonForAdmissionCode	Frequency
-- NULL	3867
-- DI.ELEC.REF	541
-- DI.EVOLVE.LOWER	217
-- DI ELEC REF HSC2	201
-- IRON INFUSION	166
-- TR	157
-- EVOLVE LOWER PRO	146
-- DI ELEC REF	127
-- SHH	123
-- VEDOLIZUMAB INFU	122
-- EVOLVE UGI PROFO	110
-- INFLIXIMAB INFUS	105
-- EVOLVE UPPER GI 	103

SELECT WardDescription, SpecialtyCode, COUNT(*) AS Frequency
FROM [RLS].[vw_Acute_Inpatients]
WHERE EventType='Admission'
AND AdmissionTypeCode = 'I'
GROUP BY WardDescription, SpecialtyCode
ORDER BY COUNT(*) DESC;
-- WardDescription	SpecialtyCode	Frequency
-- Acute Medical Unit	GMED	15901
-- Ward D4	GMED	4183
-- Ambulatory Care Unit	GMED	2371
-- Ambulatory Care Unit	SURG	2140
-- Assessment Ward (Paediatrics)	PAED	2109
-- Delivery Suite	OBST	1806
-- Jasmine Ward	GYN	1587
-- Ward D1	SURG	1204
-- Ambulatory Care Unit	TO	999
-- Ambulatory Care Unit	UROL	914
-- Jasmine Assessment Unit	GYN	805
-- Ward A10	GER	681
-- THW	PAED	659
-- Ward A10	GMED	496
-- Ward D1	UROL	478
-- Ward D2	TO	426

SELECT ReasonForAdmissionCode, COUNT(*) AS Frequency
FROM [RLS].[vw_Acute_Inpatients]
WHERE EventType='Admission'
AND AdmissionTypeCode = 'I'
GROUP BY ReasonForAdmissionCode
ORDER BY COUNT(*) DESC;
-- ReasonForAdmissionCode	Frequency
-- NULL	30692
-- abdo pain	985
-- iol	641
-- CHEST PAIN	528
-- UNWELL	386
-- labour	384
-- scan	370
-- CVA	242
-- stroke	192
-- PV BLEED	178
-- SOB	147
-- Admission	137
-- HEAD PAIN	129
-- back pain	109
-- hyperemesis	107
-- ABCESS	103

-- "GP" is most likely UNPLANNED. All the descriptions from below
-- suggest person visits GP and is then directed to hospital
-- The "NULL" ones are questionable.
SELECT 
	REPLACE(ReasonForAdmissionCode, '? ', '?') AS ReasonForAdmissionCode,
	COUNT(*) AS Frequency
FROM [RLS].[vw_Acute_Inpatients]
WHERE EventType='Admission'
AND AdmissionTypeCode = 'GP'
GROUP BY REPLACE(ReasonForAdmissionCode, '? ', '?')
ORDER BY COUNT(*) DESC;
-- ReasonForAdmissionCode	Frequency
-- NULL	8551
-- ?DVT	2486
-- UNWELL	2250
-- ?PE	715
-- CHEST PAIN	613
-- SOB	560
-- ABDO PAIN	521
-- JAUNDICE	291
-- HEADACHE	287
-- RASH	287
-- VOMITING	279
-- COUGH	217
-- LOW HB	209
-- HEADACHES	182
-- FEVER	176
-- PYREXIA	136


--Check Endoscopy
SELECT SpecialtyDescription, count(*) AS Frequency
FROM [RLS].[vw_Acute_Inpatients]
WHERE EventType='Admission'
AND AdmissionTypeCode = 'Endoscopy'
GROUP BY SpecialtyDescription
ORDER BY count(*) DESC;
-- SpecialtyDescription	Frequency
-- ENDOSCOPY DAY CASE	1213
-- UNCLASSIFIED	324

--Check Endoscopy UNCLASSIFIED
SELECT ReasonForAdmissionDescription, COUNT(*) AS Frequency FROM [RLS].[vw_Acute_Inpatients]
WHERE EventType='Admission'
AND AdmissionTypeCode = 'Endoscopy'
AND SpecialtyDescription = 'UNCLASSIFIED'
GROUP BY ReasonForAdmissionDescription
ORDER BY COUNT(*) DESC;
-- ReasonForAdmissionDescription	Frequency
-- Elective booked	320
-- Elective Planned	2
-- Elective Waiting List	2

-- 18 - CHILDRENS ONLY
SELECT SpecialtyDescription, COUNT(*) AS Frequency
FROM [RLS].[vw_Acute_Inpatients]
WHERE EventType='Admission'
AND AdmissionTypeCode = '18'
GROUP BY SpecialtyDescription
ORDER BY COUNT(*) DESC;
-- SpecialtyDescription	Frequency
-- PAEDIATRIC MEDICAL ONCOLOGY	144
-- PAEDIATRIC HAEMATOLOGY	126
-- PAEDIATRICS	123
-- BURNS	92
-- CLINICAL HAEMATOLOGY	90
-- PAEDIATRIC PLASTIC SURGERY	59
-- PAEDIATRIC RESPIRATORY	56
-- BURNS 1	55
-- PAEDIATRIC TRAUMA ORTHOPAEDIC	41
-- BONE MARROW TRANSPLANT	38
-- ACCIDENT AND EMERGENCY	28
-- PAEDIATRIC SURGERY	23
-- PAEDIATRIC NEPHROLOGY	19
-- PAEDIATRIC UROLOGY	14
-- PLASTIC SURGERY	13
-- PAEDIATRIC RHEUMATOLOGY	12
-- BURNS 2	11

SELECT ReasonForAdmissionDescription, COUNT(*) AS Frequency
FROM [RLS].[vw_Acute_Inpatients]
WHERE EventType='Admission'
AND AdmissionTypeCode = 'Venesection'
GROUP BY ReasonForAdmissionDescription
ORDER BY COUNT(*) DESC;
-- ReasonForAdmissionDescription	Frequency
-- Elective Planned	828
-- Elective booked	2

SELECT ReasonForAdmissionDescription, COUNT(*) AS Frequency
FROM [RLS].[vw_Acute_Inpatients]
WHERE EventType='Admission'
AND AdmissionTypeCode = 'Colonoscopy'
GROUP BY ReasonForAdmissionDescription
ORDER BY COUNT(*) DESC;
-- ReasonForAdmissionDescription	Frequency
-- Elective booked	591

SELECT ReasonForAdmissionDescription, COUNT(*) AS Frequency
FROM [RLS].[vw_Acute_Inpatients]
WHERE EventType='Admission'
AND AdmissionTypeCode = 'Medical'
GROUP BY ReasonForAdmissionDescription
ORDER BY COUNT(*) DESC;
-- ReasonForAdmissionDescription	Frequency
-- Elective Planned	455
-- Elective booked	29
-- Emergency Other	2