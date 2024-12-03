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

{{create-output-table::"LH004-4_infections_hospital"}}
SELECT
	SUBSTRING("Der_Pseudo_NHS_Number", 2)::INT AS "GmPseudo",
	b.concept AS "Infection",
	b.description AS "InfectionDescription",
	"Admission_Date"
FROM INTERMEDIATE.NATIONAL_FLOWS_APC."tbl_Data_SUS_APCS" a
LEFT OUTER JOIN {{code-set-table}} b ON CHARINDEX(UPPER(b.code), UPPER(a."Der_Diagnosis_All")) > 0
where b.terminology='icd10'
and b.concept != 'infections'
AND SUBSTRING("Der_Pseudo_NHS_Number", 2)::INT IN (SELECT "GmPseudo" FROM {{cohort-table}});
