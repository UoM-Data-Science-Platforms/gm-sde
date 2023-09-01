%md
# LSOA

**Desciption** To get the LSOA for each patient

**Author** Richard Williams

**Github** [https://github.com/rw251/gm-idcr/tree/master/projects/NATIONAL-CCU040-Diabetes](https://github.com/rw251/gm-idcr/tree/master/projects/NATIONAL%20-%20CCU040%20-%20Diabetes)

**Date last updated** /*__date__*/

## Notes

For each patient we attempt to determine their LSOA as at the date provided. This currently only uses the GDPPR feed and could be extended
to use other sources of data. For each patient we find their most recent record with an LSOA, prior to the date of interest. If the patient has
no record prior to the date, then we find their most recent one after the date. This will then give an LSOA for patients who did not have a record
prior to the date.

If someone has multiple records on the same day, we arbitrarily pick the one with the code latest alphabetically. This could be improved, but
will not occur frequently, so is deemed acceptable.

## Input
**date** In the form YYYY-MM-DD

## Output
**Table name** global_temp.CCU040_LSOA

| Column    | Type   | Description       |
| ----------| ------ | ----------------- |
| PatientId | string | Unique patient id |
| LSOA      | string | The patients LSOA |


%py from datetime import date
dbutils.widgets.text("date", date.today().strftime("%Y-%m-%d"))

CREATE OR REPLACE GLOBAL TEMPORARY VIEW CCU040_LSOA
AS
SELECT NHS_NUMBER_DEID AS PatientId, MAX(LSOA) AS LSOA
FROM dars_nic_391419_j3w9t_collab.gdppr_dars_nic_391419_j3w9t_archive g
INNER JOIN (
  SELECT
    NHS_NUMBER_DEID AS PatientId,
    MAX(CASE WHEN DATE > '$date' THEN NULL ELSE DATE END) AS FirstEventBeforeDate,
    MIN(CASE WHEN DATE <= '$date' THEN NULL ELSE DATE END) AS FirstEventAfterDate
  FROM dars_nic_391419_j3w9t_collab.gdppr_dars_nic_391419_j3w9t_archive
  WHERE LSOA IS NOT NULL
  GROUP BY NHS_NUMBER_DEID
) sub
  ON sub.PatientId = NHS_NUMBER_DEID
  AND (
    sub.FirstEventBeforeDate = g.DATE OR 
    (sub.FirstEventBeforeDate IS NULL AND sub.FirstEventAfterDate = g.DATE)
  )
GROUP BY NHS_NUMBER_DEID

