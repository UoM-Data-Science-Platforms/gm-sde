
--┌─────────────────────────────────────┐
--│ Define Cohort for LH015: gp events  │
--└─────────────────────────────────────┘

-------- RESEARCH DATA ENGINEER CHECK ------------

--------------------------------------------------

-- OBJECTIVE: To provide all GP events, except any sensitive codes, for the study cohort and matched controls

set(StudyStartDate) = to_date('2015-03-01');
set(StudyEndDate)   = to_date('2022-03-31');

-- SELECT ALL GP EVENTS 

SELECT c."GmPseudo" 
	"MedicationDate", 
	"SCTID", 
	"SuppliedCode", 
	"MedicationDescription", 
	"Quantity", 
	"Dosage",
	"Units",
	"MedicationStartDate",
	"MedicationEndDate"
FROM INTERMEDIATE.GP_RECORD."GP_Medications_SecondaryUses" gp  
INNER JOIN {{cohort-table}} c ON c."FK_Patient_ID" = gp."FK_Patient_ID"
WHERE "MedicationDate" BETWEEN $StudyStartDate and $StudyEndDate
	AND "SCTID" NOT IN (SELECT "SCTID" FROM INTERMEDIATE.GP_RECORD."ExcludedCodes_SecondaryUses");