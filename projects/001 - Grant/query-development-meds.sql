-- We can group by FK_Reference_Coding_ID - BUT often have the same drug with different ids
-- We can group by SuppliedCode but a patient on the same drug with an EMIS code then a Read code
-- counts the second as a new drug

select FK_Patient_Link_ID, MIN(MedicationDate), FK_Reference_Coding_ID from RLS.vw_GP_Medications
where FK_Reference_Coding_ID != -1
group by FK_Patient_Link_ID, FK_Reference_Coding_ID
having MIN(MedicationDate) >= @StartDate;

--3350942 rows
--00:06:38 elapsed