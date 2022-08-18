--┌────────────────────────────────────┐
--│ Calcluate Electronic Frailty Index │
--└────────────────────────────────────┘

-- OBJECTIVE: To calculate the EFI for all patients and how it has changed over time

-- INPUT: Takes three parameters
--	-	all-patients: boolean - (true/false) if true, then all patients are included, otherwise only those in the pre-existing #Patients table.
--	- gp-events-table: string - (table name) the name of the table containing the GP events. Usually is "RLS.vw_GP_Events" but can be anything with the columns: FK_Patient_Link_ID, EventDate, and SuppliedCode
--	- gp-medications-table: string - (table name) the name of the table containing the GP medications. Usually is "RLS.vw_GP_Medications" but can be anything with the columns: FK_Patient_Link_ID, MedicationDate, and SuppliedCode

-- OUTPUT: One temp tables as follows:
--	#PatientEFIOverTime (FK_Patient_Link_ID, NumberOfDeficits, DateFrom)
--	- FK_Patient_Link_ID - unique patient id
--	- NumberOfDeficits - the number of deficits (e.g. 3)
--	- DateFrom - the date from which the patient had this number of deficits

-- Most of the logic occurs in the following subquery, which is also used
-- in the query-patients-calculate-efi-on-date.sql query
--> EXECUTE subquery-efi-common.sql all-patients:{param:all-patients} gp-events-table:{param:gp-events-table} gp-medications-table:{param:gp-medications-table}

TODO something like this:

select
	FK_Patient_Link_ID,
	EventDate,
	1 AS Deficit
into #deficitsummer
from EfiEvents
union all
select FK_Patient_Link_ID, DateFrom, 1 from #PolypharmacyPeriods
union all
select FK_Patient_Link_ID, DateTo, -1 from #PolypharmacyPeriods
order by FK_Patient_Link_ID, EventDate

select * from #deficitsummer
order by FK_Patient_Link_ID,
	EventDate

select d1.FK_Patient_Link_ID, d1.EventDate, SUM(d2.Deficit) from #deficitsummer d1
inner join #deficitsummer d2 on d2.EventDate <= d1.EventDate and d1.FK_Patient_Link_ID = d2.FK_Patient_Link_ID
group by d1.FK_Patient_Link_ID, d1.EventDate
order by d1.FK_Patient_Link_ID, d1.EventDate;