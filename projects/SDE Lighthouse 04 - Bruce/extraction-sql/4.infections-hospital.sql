USE SCHEMA SDE_REPOSITORY.SHARED_UTILITIES;

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

-- >>> Codesets required... Inserting the code set code
-- >>> Codesets extracted into 0.code-sets.sql
-- >>> Following code sets injected: infections v2
-- >>> Following code sets injected: bone-infection v1/cardiovascular-infection v1/cellulitis v1/diverticulitis v1
-- >>> Following code sets injected: gastrointestinal-infections v1/genital-tract-infections v1/hepatobiliary-infection v1
-- >>> Following code sets injected: infection-other v1/lrti v1/muscle-infection v1/neurological-infection v1/peritonitis v1
-- >>> Following code sets injected: puerpural-infection v1/pyelonephritis v1/urti-bacterial v1/urti-viral v1/uti v2

DROP TABLE IF EXISTS SDE_REPOSITORY.SHARED_UTILITIES."LH004-4_infections_hospital";
CREATE TABLE SDE_REPOSITORY.SHARED_UTILITIES."LH004-4_infections_hospital" AS
SELECT
	SUBSTRING("Der_Pseudo_NHS_Number", 2)::INT AS "PatientID",
	b.concept AS "Infection",
	b.description AS "InfectionDescription",
	"Admission_Date"
FROM INTERMEDIATE.national_flows_apc."tbl_Data_SUS_APCE" a
LEFT OUTER JOIN SDE_REPOSITORY.SHARED_UTILITIES."Code_Sets_SDE_Lighthouse_04_Bruce" b ON b.code = a."Der_Primary_Diagnosis_Code"
where "APCS_First_Ep_Ind"='1'
and b.terminology='icd10'
and b.concept != 'infections'
AND SUBSTRING("Der_Pseudo_NHS_Number", 2)::INT IN (SELECT "GmPseudo" FROM SDE_REPOSITORY.SHARED_UTILITIES."Cohort_SDE_Lighthouse_04_Bruce");