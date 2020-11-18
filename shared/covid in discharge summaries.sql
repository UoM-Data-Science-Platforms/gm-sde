-- Discovering all covid related codes in the Acute coding table
SELECT [Code], [CodingDescription], [CodingSystem], [FK_Reference_Coding_ID], [FK_Reference_SnomedCT_ID], count(*) as Frequency
FROM [RLS].[vw_Acute_Coding]
where (lower(CodingDescription) like '%wuhan%'
or lower(CodingDescription) like '%coronavirus%'
or lower(CodingDescription) like '%covid%'
or lower(CodingDescription) like '%ncov%')
GROUP BY [Code], [CodingDescription], [CodingSystem], [FK_Reference_Coding_ID], [FK_Reference_SnomedCT_ID]

-- Code	CodingDescription	CodingSystem	FK_Reference_Coding_ID	FK_Reference_SnomedCT_ID	Frequency
-- 1240751000000100	Disease caused by 2019-nCoV (novel coronavirus)	NULL	-1	-1	6
-- B972	Coronavirus as cause of dis classified to other chapters	I10	173541	177835	161
-- B972	Coronavirus as the cause of diseases classified to other chapters	ICD 20160401	173541	177835	263
-- U071	2019-nCoV (acute respiratory disease)	I10	190536	-1	275
-- U072	Suspected COVID-19	I10	190537	-1	13

-- To get the date best to link back to either the A&E or the inpatients table (they are currently the only tables
-- that the acute_coding table links to for covid codes.

-- Getting detail of codes relating to A&E
SELECT a.FK_Patient_Link_ID,Type, Code, CodingDescription,ae.SourceDate, ae.EventType, AttendanceDate, DischargeDate
FROM [RLS].[vw_Acute_Coding] a
inner join [RLS].vw_Acute_AE ae on ae.PK_Acute_AE_ID = a.FK_Acute_AE_ID
where Code in ('1240751000000100','B972','U071','U072')
and FK_Acute_AE_ID != -2528422764485075390 -- seems to be instead of null
--6

-- Getting detail of codes relating to inpatient stays
SELECT a.FK_Patient_Link_ID,Type, Code, CodingDescription,ai.SourceDate, ai.EventType, AdmissionDate, DischargeDate
FROM [RLS].[vw_Acute_Coding] a
inner join [RLS].vw_Acute_Inpatients ai on ai.PK_Acute_Inpatients_ID = a.FK_Acute_Inpatients_ID
where Code in ('1240751000000100','B972','U071','U072')
and FK_Acute_Inpatients_ID != -2528422764485075390 -- seems to be instead of null
--1155

-- Now looking at numbers of codes per trust
SELECT TenancyName, count(*) as Frequency
FROM [RLS].[vw_Acute_Coding] ac
inner join SharedCare.Reference_Tenancy r on r.PK_Reference_Tenancy_ID = FK_Reference_Tenancy_ID
where Code in ('1240751000000100','B972','U071','U072')
GROUP BY TenancyName
-- TenancyName	Frequency
-- Tameside Hospital - TGICFT	675
-- University Hospital of South Manchester	486


-- Now looking at numbers of codes per trust per month/year
select TenancyName, YEAR(EventDate) as [Year], MONTH(EventDate) as [Month], count(*) as Frequency from (
	SELECT TenancyName, case when AdmissionDate is null then DischargeDate else DischargeDate end as EventDate
	FROM [RLS].[vw_Acute_Coding] ac
	inner join SharedCare.Reference_Tenancy r on r.PK_Reference_Tenancy_ID = FK_Reference_Tenancy_ID
	inner join [RLS].vw_Acute_Inpatients ai on ai.PK_Acute_Inpatients_ID = ac.FK_Acute_Inpatients_ID
	where Code in ('1240751000000100','B972','U071','U072')
) sub
group by TenancyName, YEAR(EventDate), MONTH(EventDate)
order by TenancyName, YEAR(EventDate), MONTH(EventDate);
-- TenancyName	Year	Month	Frequency
-- Tameside Hospital - TGICFT	NULL	NULL	6
-- Tameside Hospital - TGICFT	2020	8	5
-- Tameside Hospital - TGICFT	2020	9	258
-- Tameside Hospital - TGICFT	2020	10	197
-- Tameside Hospital - TGICFT	2020	11	209
-- University Hospital of South Manchester	NULL	NULL	18
-- University Hospital of South Manchester	2020	8	2
-- University Hospital of South Manchester	2020	9	14
-- University Hospital of South Manchester	2020	10	198
-- University Hospital of South Manchester	2020	11	254
