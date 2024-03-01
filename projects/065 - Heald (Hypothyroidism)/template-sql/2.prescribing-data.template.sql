--┌──────────────────┐
--│ Prescribing data │
--└──────────────────┘

-- OUTPUT:
--  Patient ID
--  GP Practice Code (NB this field is blank in the database so we can only provide the patients current GP in file #3)
--  Prescription Date
--  Thyroid Hormone Prescribed BNF 060201 (Levothyroxine sodium (0602010V0), Levothyroxine sodium and liothyronine (0602010Z0), Liothyronine sodium (0602010M0))
--  Method Tablet liquid inj etc
--  Dose mcg/tablet
--  Quantity Tablets

-- Just want the output, not the messages
SET NOCOUNT ON;

-- Get the cohort of patients
--> EXECUTE query-build-rq065-cohort.sql
-- 2m43
--> EXECUTE query-build-rq065-cohort-medications.sql
-- 2m37

--> CODESET levothyroxine:1 liothyronine:1

SELECT FK_Patient_Link_ID AS PatientId, MedicationDate, a.description AS Medication, Units AS Method, Dosage As DosageInstruction, Quantity
FROM #PatientMedicationData m
LEFT OUTER JOIN #AllCodes a ON a.Code = SuppliedCode
WHERE SuppliedCode IN (SELECT [Code] FROM #AllCodes WHERE [Concept] IN ('levothyroxine','liothyronine') AND [Version] = 1);