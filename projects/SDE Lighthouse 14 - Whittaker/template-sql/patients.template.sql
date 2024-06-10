--┌────────────────────────────────────┐
--│ LH004 Patient file                 │
--└────────────────────────────────────┘

SELECT * 
FROM (
SELECT top 100 "Snapshot", "GmPseudo", "FK_Patient_ID", "DateOfBirth", LSOA11, tow.quintile, "Age", "Sex", "EthnicityLatest", "EthnicityLatest_Category", "EthnicityLatest_Record", "MarriageCivilPartership",
row_number() over (partition by "GmPseudo" order by "Snapshot" desc) rownum
FROM INTERMEDIATE.GP_RECORD."DemographicsProtectedCharacteristics" D
LEFT JOIN INTERMEDIATE.GP_RECORD.TOWNSENDSCORE_LSOA_2011 tow on tow.geo_code = D.LSOA11
)
WHERE rownum = 1
