--┌────────────────────────────────────┐
--│ LH004 Smear tests' results         │
--└────────────────────────────────────┘

-- From application:
--	PneumococcalVaccination (ever recorded y/n) [5.vaccinations]
--	PneumoVacDate [5.vaccinations]
--	InfluenzaVaccination (in past 12 months y/n) [5.vaccinations]
--	FluVacDate [5.vaccinations]
--	COVIDVaccination (in past 12 months y/n) [5.vaccinations]
--	COVIDVacDate [5.vaccinations]
--	ShinglesVaccination [5.vaccinations]
--	ShinglesVacDate [5.vaccinations]
--	BCGVaccination [5.vaccinations]
--	BCGVacDate [5.vaccinations]
--	HPVVaccination [5.vaccinations]
--	HPVVacDate [5.vaccinations]
--	Infection (from list below) [4.infections-gp] [4.infections-hospital]
--	InfectionDate (for each recorded infection) [4.infections-gp]
--	HospitalAdmissionForInfection (if available) [4.infections-hospital]
--	HospitalAdmissionDate [4.infections-hospital]
--	PreviousSmear (ever y/n) [6.smears]
--	SmearDates [6.smears]
--	SmearResults (for each smear documented) [6.smears]
-- Infections from : 
-- https://data.bris.ac.uk/datasets/2954m5h0ync672u8yzx16xxj7l/infection_master_published.txt

-- PI agreed to separate files for infections, vaccinations and smear tests


set(StudyEndDate)   = to_date('2024-12-31');


-- Create temp tables of all the vaccine codes for speeding up future queries
DROP TABLE IF EXISTS TEMP_LH004_SMEAR_RECORDS;
CREATE TEMPORARY TABLE TEMP_LH004_SMEAR_RECORDS AS
SELECT "FK_Patient_ID", CAST("EventDate" AS DATE) AS "EventDate", SCTID, "Term"
FROM intermediate.gp_record."Combined_EventsMedications_Clusters_SecondaryUses"
WHERE "Field_ID" = 'SMEAR_COD'
AND "FK_Patient_ID" IN (SELECT "FK_Patient_ID" FROM {{cohort-table}});

{{create-output-table::"LH004-6_smears"}}
SELECT DISTINCT "GmPseudo", "EventDate","Term" AS "SmearDescription"
FROM TEMP_LH004_SMEAR_RECORDS smear
INNER JOIN {{cohort-table}} c ON c."FK_Patient_ID" = smear."FK_Patient_ID"
WHERE "EventDate" <= $StudyEndDate
ORDER BY "GmPseudo", "EventDate";