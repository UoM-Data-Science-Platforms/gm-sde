%md
# Smoking status

**Desciption** To get the smoking status for each patient in a cohort.

**Author** Richard Williams

**Github** [https://github.com/rw251/gm-idcr/tree/master/projects/NATIONAL-CCU040-Diabetes](https://github.com/rw251/gm-idcr/tree/master/projects/NATIONAL%20-%20CCU040%20-%20Diabetes)

**Date last updated** /*__date__*/

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
WHERE CODE IN (/*--smoking-status-current--*/)
UNION
SELECT NHS_NUMBER_DEID AS PatientId, DATE AS EventDate, 1 AS Severity, 0 AS CurrentSmoker
FROM dars_nic_391419_j3w9t_collab.gdppr_dars_nic_391419_j3w9t_archive
WHERE CODE IN (/*--smoking-status-ex--*/)
UNION
SELECT NHS_NUMBER_DEID AS PatientId, DATE AS EventDate, 0 AS Severity, 1 AS CurrentSmoker
FROM dars_nic_391419_j3w9t_collab.gdppr_dars_nic_391419_j3w9t_archive
WHERE CODE IN (/*--smoking-status-current-trivial--*/)
UNION
SELECT NHS_NUMBER_DEID AS PatientId, DATE AS EventDate, 0 AS Severity, 0 AS CurrentSmoker
FROM dars_nic_391419_j3w9t_collab.gdppr_dars_nic_391419_j3w9t_archive
WHERE CODE IN (/*--smoking-status-ex-trivial--*/);

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
