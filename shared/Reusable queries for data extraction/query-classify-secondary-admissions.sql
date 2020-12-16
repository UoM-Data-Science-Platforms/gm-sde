--┌───────────────────────────────┐
--│ CLASSIFY SECONDARY ADMISSIONS │
--└───────────────────────────────┘

-- OUTPUT: A temp table as follows:
-- #AdmissionTypes (FK_Patient_Link_ID, AdmissionDate, AcuteProvider, AdmissionType)
-- 	- FK_Patient_Link_ID - unique patient id
--	- AdmissionDate - date of admission (YYYY-MM-DD)
--	- AcuteProvider - Bolton, SRFT, Stockport etc..
--	- AdmissionType - One of: Maternity/Unplanned/Planned/Transfer/Unknown

-- For each acute admission we find the type. If multiple admissions on same day
-- we group and take the 'highest' category e.g.
-- choose Unplanned, then Planned, then Maternity, then Transfer, then Unknown
IF OBJECT_ID('tempdb..#AdmissionTypes') IS NOT NULL DROP TABLE #AdmissionTypes;
SELECT 
	FK_Patient_Link_ID, AdmissionDate, 
	CASE 
		WHEN AdmissionId = 5 THEN 'Maternity' 
		WHEN AdmissionId = 4 THEN 'Unplanned' 
		WHEN AdmissionId = 3 THEN 'Planned' 
		WHEN AdmissionId = 2 THEN 'Transfer' 
		WHEN AdmissionId = 1 THEN 'Unknown' 
	END as AdmissionType,
	AcuteProvider 
INTO #AdmissionTypes FROM (
	SELECT 
		FK_Patient_Link_ID, CONVERT(DATE, AdmissionDate) as AdmissionDate, 
		MAX(
			CASE 
				WHEN AdmissionTypeCode IN ('PL','11','WL','13','12','BL','TR','IPPlannedAd') THEN 3 --'Planned'
				WHEN AdmissionTypeCode IN ('AE','21','22','23','EM','28','2D','24','AI','BB','DO','2A','A+E Admission','Emerg GP') THEN 4 --'Unplanned'
				WHEN AdmissionTypeCode IN ('31','BH','AN','82','PN','32','BHOSP','83') THEN 5 --'Maternity'
				WHEN AdmissionTypeCode IN ('81', 'ET','T','HospTran') THEN 2 --'Transfer'
				ELSE 1 --'Unknown'
			END
		)	AS AdmissionId,
		t.TenancyName AS AcuteProvider
	FROM RLS.vw_Acute_Inpatients i
	LEFT OUTER JOIN SharedCare.Reference_Tenancy t ON t.PK_Reference_Tenancy_ID = i.FK_Reference_Tenancy_ID
	WHERE EventType = 'Admission'
	AND AdmissionDate >= @StartDate
	GROUP BY FK_Patient_Link_ID, CONVERT(DATE, AdmissionDate), t.TenancyName
) sub;
-- 523477 rows	523477 rows
-- 00:00:16		00:00:45