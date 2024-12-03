--┌────────────────────────────────────┐
--│ LH004 Infections file              │
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

-- Create the final table to populate
DROP TABLE IF EXISTS "TEMP-LH004-5_vaccinations";
CREATE TEMPORARY TABLE "TEMP-LH004-5_vaccinations" (
	"PatientID" NUMBER(38,0),
	"VaccinationType" VARCHAR(255),
	"VaccinationDate" DATE
);

-- Pneumococcal / BCG / HPV all obtained from childhood vaccination table
INSERT INTO "TEMP-LH004-5_vaccinations"
SELECT
	"GmPseudo",
	CASE WHEN "Vaccination_Type" = 'BCG (Tuberculosis)' THEN 'BCG' ELSE "Vaccination_Type" END AS "Vaccination_Type",
	"EventDate"
FROM INTERMEDIATE.gp_record."Vaccination_Individual_SecondaryUses"
WHERE "Vaccination_Type" IN ('Pneumococcal','BCG (Tuberculosis)','HPV')
AND "FK_Patient_ID" IN (SELECT "FK_Patient_ID" FROM {{cohort-table}});

-- Flu, COVID and Shingles (Zoster) derived from clusters
DROP TABLE IF EXISTS TEMP_LH004_VAC_CODES;
CREATE TEMPORARY TABLE TEMP_LH004_VAC_CODES AS
SELECT "SNOMED_code",
	CASE
		WHEN "Field_ID" IN ('INTGPDRUG_COD','SFLUGPDRUG_COD','FLU_COD','INTGP1_COD','INTGP2_COD','INTOHP1_COD','INTOHP2_COD','SFLUGP1_COD','SFLUGP2_COD','SFLUOHP1_COD','SFLUOHP2_COD') THEN 'Flu'
		WHEN "Field_ID" IN ('COVIDVACBOOSTER_COD','COVID19Vaccination','COVIDVACGENERIC_COD','COVIDVAC1_COD','COVIDVAC3_COD','COVIDVAC2_COD') THEN 'COVID'
		WHEN "Field_ID" IN ('SHVACGP_COD','SHVACGP2_COD','SHVACGP1_COD','SHVACOHP_COD') THEN 'Shingles'
	END AS "VaccinationType"
FROM INTERMEDIATE.gp_record."Combined_EventsMedications_Clusters_SecondaryUses"
WHERE "Field_ID" IN (
	'INTGPDRUG_COD','SFLUGPDRUG_COD','FLU_COD','INTGP1_COD','INTGP2_COD','INTOHP1_COD','INTOHP2_COD','SFLUGP1_COD','SFLUGP2_COD','SFLUOHP1_COD','SFLUOHP2_COD',
	'COVIDVACBOOSTER_COD','COVID19Vaccination','COVIDVACGENERIC_COD','COVIDVAC1_COD','COVIDVAC3_COD','COVIDVAC2_COD',
	'SHVACGP_COD','SHVACGP2_COD','SHVACGP1_COD','SHVACOHP_COD');

-- Create temp tables of all the vaccine codes for speeding up future queries
DROP TABLE IF EXISTS TEMP_LH004_VAC_RECORDS;
CREATE TEMPORARY TABLE TEMP_LH004_VAC_RECORDS AS
SELECT "FK_Patient_ID", CAST("EventDate" AS DATE) AS "EventDate", SCTID
FROM INTERMEDIATE.gp_record."GP_Events_SecondaryUses"
WHERE SCTID IN (SELECT "SNOMED_code" FROM TEMP_LH004_VAC_CODES)
AND "FK_Patient_ID" IN (SELECT "FK_Patient_ID" FROM {{cohort-table}});

-- Similarly for meds table
DROP TABLE IF EXISTS TEMP_LH004_VAC_MED_RECORDS;
CREATE TEMPORARY TABLE TEMP_LH004_VAC_MED_RECORDS AS
SELECT "FK_Patient_ID", CAST("MedicationDate" AS DATE) AS "MedicationDate", SCTID
FROM INTERMEDIATE.gp_record."GP_Medications_SecondaryUses"
WHERE SCTID IN (SELECT "SNOMED_code" FROM TEMP_LH004_VAC_CODES)
AND "FK_Patient_ID" IN (SELECT "FK_Patient_ID" FROM {{cohort-table}});

-- now insert all the vaccinations
INSERT INTO "TEMP-LH004-5_vaccinations"
SELECT "FK_Patient_ID", 'Flu', "EventDate"
FROM TEMP_LH004_VAC_RECORDS
WHERE SCTID IN (
	SELECT "SNOMED_code" FROM TEMP_LH004_VAC_CODES
	WHERE "VaccinationType" = 'Flu'
);

INSERT INTO "TEMP-LH004-5_vaccinations"
SELECT "FK_Patient_ID", 'Flu', "MedicationDate"
FROM TEMP_LH004_VAC_MED_RECORDS
WHERE SCTID IN (
	SELECT "SNOMED_code" FROM TEMP_LH004_VAC_CODES
	WHERE "VaccinationType" = 'Flu'
);

INSERT INTO "TEMP-LH004-5_vaccinations"
SELECT "FK_Patient_ID", 'COVID', "EventDate"
FROM TEMP_LH004_VAC_RECORDS
WHERE SCTID IN (
	SELECT "SNOMED_code" FROM TEMP_LH004_VAC_CODES
	WHERE "VaccinationType" = 'COVID'
);

INSERT INTO "TEMP-LH004-5_vaccinations"
SELECT "FK_Patient_ID", 'COVID', "MedicationDate"
FROM TEMP_LH004_VAC_MED_RECORDS
WHERE SCTID IN (
	SELECT "SNOMED_code" FROM TEMP_LH004_VAC_CODES
	WHERE "VaccinationType" = 'COVID'
);

INSERT INTO "TEMP-LH004-5_vaccinations"
SELECT "FK_Patient_ID", 'Shingles', "EventDate"
FROM TEMP_LH004_VAC_RECORDS
WHERE SCTID IN (
	SELECT "SNOMED_code" FROM TEMP_LH004_VAC_CODES
	WHERE "VaccinationType" = 'Shingles'
);

INSERT INTO "TEMP-LH004-5_vaccinations"
SELECT "FK_Patient_ID", 'Shingles', "MedicationDate"
FROM TEMP_LH004_VAC_MED_RECORDS
WHERE SCTID IN (
	SELECT "SNOMED_code" FROM TEMP_LH004_VAC_CODES
	WHERE "VaccinationType" = 'Shingles'
);

{{create-output-table::"LH004-5_vaccinations"}}
SELECT DISTINCT "GmPseudo", "VaccinationType", "VaccinationDate"
FROM "TEMP-LH004-5_vaccinations" v
LEFT OUTER JOIN {{cohort-table}} c ON c."FK_Patient_ID" = v."PatientID"
ORDER BY "GmPseudo", "VaccinationDate";