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

--> CODESET infections:2 
--> CODESET bone-infection:1 cardiovascular-infection:1 cellulitis:1 diverticulitis:1
--> CODESET gastrointestinal-infections:1 genital-tract-infections:1 hepatobiliary-infection:1
--> CODESET infection-other:1 lrti:1 muscle-infection:1 neurological-infection:1 peritonitis:1
--> CODESET puerpural-infection:1 pyelonephritis:1 urti-bacterial:1 urti-viral:1 uti:2

DROP TABLE IF EXISTS LH004_InfectionCodes;
CREATE TEMPORARY TABLE LH004_InfectionCodes AS
SELECT "FK_Patient_ID", CAST("EventDate" AS DATE) AS "EventDate", "SuppliedCode"
FROM INTERMEDIATE.GP_RECORD."GP_Events_SecondaryUses"
WHERE "SuppliedCode" IN (
	SELECT code FROM {{code-set-table}} 
	WHERE concept = 'infections' AND version = 2
)
AND "FK_Patient_ID" IN (SELECT "FK_Patient_ID" FROM {{cohort-table}});

{{create-output-table::"LH004-4_infections_gp"}}
SELECT "GmPseudo",
	CASE
		WHEN "SuppliedCode" IN (SELECT code FROM {{code-set-table}} WHERE concept = 'bone-infection') THEN 'bone-infection'
		WHEN "SuppliedCode" IN (SELECT code FROM {{code-set-table}} WHERE concept = 'cardiovascular-infection') THEN 'cardiovascular-infection'
		WHEN "SuppliedCode" IN (SELECT code FROM {{code-set-table}} WHERE concept = 'cellulitis') THEN 'cellulitis'
		WHEN "SuppliedCode" IN (SELECT code FROM {{code-set-table}} WHERE concept = 'diverticulitis') THEN 'diverticulitis'
		WHEN "SuppliedCode" IN (SELECT code FROM {{code-set-table}} WHERE concept = 'gastrointestinal-infections') THEN 'gastrointestinal-infections'
		WHEN "SuppliedCode" IN (SELECT code FROM {{code-set-table}} WHERE concept = 'genital-tract-infections') THEN 'genital-tract-infections'
		WHEN "SuppliedCode" IN (SELECT code FROM {{code-set-table}} WHERE concept = 'hepatobiliary-infection') THEN 'hepatobiliary-infection'
		WHEN "SuppliedCode" IN (SELECT code FROM {{code-set-table}} WHERE concept = 'infection-other') THEN 'infection-other'
		WHEN "SuppliedCode" IN (SELECT code FROM {{code-set-table}} WHERE concept = 'lrti') THEN 'lrti'
		WHEN "SuppliedCode" IN (SELECT code FROM {{code-set-table}} WHERE concept = 'muscle-infection') THEN 'muscle-infection'
		WHEN "SuppliedCode" IN (SELECT code FROM {{code-set-table}} WHERE concept = 'neurological-infection') THEN 'neurological-infection'
		WHEN "SuppliedCode" IN (SELECT code FROM {{code-set-table}} WHERE concept = 'peritonitis') THEN 'peritonitis'
		WHEN "SuppliedCode" IN (SELECT code FROM {{code-set-table}} WHERE concept = 'puerpural-infection') THEN 'puerpural-infection'
		WHEN "SuppliedCode" IN (SELECT code FROM {{code-set-table}} WHERE concept = 'pyelonephritis') THEN 'pyelonephritis'
		WHEN "SuppliedCode" IN (SELECT code FROM {{code-set-table}} WHERE concept = 'urti-bacterial') THEN 'urti-bacterial'
		WHEN "SuppliedCode" IN (SELECT code FROM {{code-set-table}} WHERE concept = 'urti-viral') THEN 'urti-viral'
		WHEN "SuppliedCode" IN (SELECT code FROM {{code-set-table}} WHERE concept = 'uti') THEN 'uti'
	END AS "Infection",
	"EventDate" AS "InfectionDate"
FROM LH004_InfectionCodes ic
LEFT OUTER JOIN SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_04_Bruce" c ON c."FK_Patient_ID" = ic."FK_Patient_ID";
