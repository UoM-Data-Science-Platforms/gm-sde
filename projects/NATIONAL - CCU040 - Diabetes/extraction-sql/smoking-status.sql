%md
# Smoking status

**Desciption** To get the smoking status for each patient in a cohort.

**Author** Richard Williams

**Github** [https://github.com/rw251/gm-idcr/tree/master/projects/NATIONAL-CCU040-Diabetes](https://github.com/rw251/gm-idcr/tree/master/projects/NATIONAL%20-%20CCU040%20-%20Diabetes)

**Date last updated** 2022-09-22

## Notes

For each patient we attempt to determine their current smoking status, and their worst smoking status. Smoking
status is either: [non-trivial-smoker/trivial-smoker/non-smoker]. E.g. a person who used to smoke a non-trivial
amount, but has now quit, would have a CurrentSmokingStatus of 'non-smoker', but a WorstSmokingStatus of 'non-trivial-smoker'.
If a patient is absent it means they have always been a non-smoker.

The data is obtained from the GDPPR data feed.

## Output
**Table name** global_temp.CCU040_SmokingStatus

| Column               | Type   | Description                                    |
| -------------------- | ------ | ---------------------------------------------- |
| PatientId            | string | Unique patient id                              |
| WorstSmokingStatus   | string | [non-trivial-smoker/trivial-smoker/non-smoker] |
| CurrentSmokingStatus | string | [non-trivial-smoker/trivial-smoker/non-smoker] |


-- Give trivial smoking codes a severity score of 0, all other smoking codes
-- have a severity score of 1.
CREATE OR REPLACE GLOBAL TEMPORARY VIEW CCU040_TEMP_Smoking
AS
SELECT NHS_NUMBER_DEID AS PatientId, DATE AS EventDate, 1 AS Severity, 1 AS CurrentSmoker
FROM dars_nic_391419_j3w9t_collab.gdppr_dars_nic_391419_j3w9t_archive
WHERE CODE IN (--smoking-status-current codeset inserted
'56578002','56771006','59978006','65568007','77176002','82302008','134406006','160603005','160604004','160605003','160606002','160612007','160613002','160616005','160619003','225934006','230056004','230057008','230058003','230060001','230062009','230063004','230064005','230065006','266918002','266929003','308438006','394871007','394872000','394873005','401159003','413173009','446172000','449868002','203191000000107','836001000000109')
UNION
SELECT NHS_NUMBER_DEID AS PatientId, DATE AS EventDate, 1 AS Severity, 0 AS CurrentSmoker
FROM dars_nic_391419_j3w9t_collab.gdppr_dars_nic_391419_j3w9t_archive
WHERE CODE IN (--smoking-status-ex codeset inserted
'8517006','53896009','160617001','160620009','160621008','160625004','228486009','266922007','266923002','266924008','266925009','266928006','281018007','360890004','360900008','735112005','735128000','1092031000000108','1092041000000104','1092071000000105','1092091000000109','1092111000000104','48031000119106','492191000000103')
UNION
SELECT NHS_NUMBER_DEID AS PatientId, DATE AS EventDate, 0 AS Severity, 1 AS CurrentSmoker
FROM dars_nic_391419_j3w9t_collab.gdppr_dars_nic_391419_j3w9t_archive
WHERE CODE IN (--smoking-status-current-trivial codeset inserted
'230059006','266920004','428041000124106')
UNION
SELECT NHS_NUMBER_DEID AS PatientId, DATE AS EventDate, 0 AS Severity, 0 AS CurrentSmoker
FROM dars_nic_391419_j3w9t_collab.gdppr_dars_nic_391419_j3w9t_archive
WHERE CODE IN (--smoking-status-ex-trivial codeset inserted
'266921000','1092131000000107');

-- Get the current smoking status and also the worst smoking status
CREATE OR REPLACE GLOBAL TEMPORARY VIEW CCU040_SmokingStatus
AS
SELECT a.PatientId,
	CASE 
		WHEN MAX(CurrentSmoker) = 0 THEN 'non-smoker'
		WHEN MAX(Severity) = 1 THEN 'non-trivial-smoker'
		ELSE 'trivial-smoker'
	END AS CurrentSmokingStatus,
	CASE
		WHEN MAX(WorstSeverity) = 1 THEN 'non-trivial-smoker'
		ELSE 'trivial-smoker'
	END AS WorstSmokingStatus
FROM global_temp.CCU040_TEMP_Smoking a
INNER JOIN (
	SELECT PatientId, MAX(EventDate) AS MostRecentDate, MAX(Severity) AS WorstSeverity
	FROM global_temp.CCU040_TEMP_Smoking
	GROUP BY PatientId
) sub ON sub.MostRecentDate = a.EventDate and sub.PatientId = a.PatientId
GROUP BY a.PatientId;
