-- Examines the number of records in the GP_Events and the GP_Medications
-- tables to find the date where we can safely extract and know that we
-- haven't missed any records that are yet to arrive. It looks at a rolling
-- average and tries to work out when the data is good up to. 

-- Find all events in the GP_Event table in the last month and see how many there were each day
IF OBJECT_ID('tempdb..#RecentGPEvents') IS NOT NULL DROP TABLE #RecentGPEvents;
select CAST(EventDate AS DATE) AS EventDate, count(*) AS Frequency
into #RecentGPEvents
from SharedCare.GP_Events
where EventDate > DATEADD(month, -1, GETDATE())
and EventDate < GETDATE()
group by CAST(EventDate AS DATE)
order by EventDate;
--30s

-- Limit the numbers to just weekdays. Weekends always have many fewer records as GPs are not
-- usually open. Also add a row number (ordered by EventDate) for future use
IF OBJECT_ID('tempdb..#RecentGPEventsWeekdays') IS NOT NULL DROP TABLE #RecentGPEventsWeekdays;
select EventDate, Frequency, ROW_NUMBER() OVER (order by EventDate) AS IndexNumber
into #RecentGPEventsWeekdays
from #RecentGPEvents
where DATENAME(WEEKDAY, EventDate) IN ('Monday','Tuesday','Wednesday','Thursday','Friday');

-- Using the row numbers before, for each weekday we can calculate the average of the previous 4 days.
--	-	If the number of records is below a certain threshold then it could mean they haven't arrived or
--		it could be a bank holiday
--	- If the proportion of records on a day is < 80% of the recent average, then it could mean that not
--		all of the records have arrived.
select 
	g4.EventDate, g4.Frequency,
	CASE
		WHEN g4.Frequency < 100000 THEN 'Not enough records. Either not yet arrived, or this is a public holiday'
		WHEN 
			CASE 
				WHEN (CAST(g1.Frequency + g2.Frequency + g3.Frequency + g4.Frequency AS FLOAT)/4) = 0
				THEN 0 
				ELSE  g4.Frequency/(CAST(g1.Frequency + g2.Frequency + g3.Frequency + g4.Frequency AS FLOAT)/4)
			END < 0.8 THEN 'Below 80% of recent average - could mean not all records have arrived'
		ELSE 'Seems ok'
	END AS Assessment
 from #RecentGPEventsWeekdays g4
	left outer join #RecentGPEventsWeekdays g3 on g3.IndexNumber = g4.IndexNumber-1
	left outer join #RecentGPEventsWeekdays g2 on g2.IndexNumber = g4.IndexNumber-2
	left outer join #RecentGPEventsWeekdays g1 on g1.IndexNumber = g4.IndexNumber-3;

-- Now we repeat all of the above but for the GP_Medications table
IF OBJECT_ID('tempdb..#RecentGPMedications') IS NOT NULL DROP TABLE #RecentGPMedications;
select CAST(MedicationDate AS DATE) AS MedicationDate, count(*) AS Frequency
into #RecentGPMedications
from SharedCare.GP_Medications
where MedicationDate > DATEADD(month, -1, GETDATE())
and MedicationDate < GETDATE()
group by CAST(MedicationDate AS DATE)
order by MedicationDate;
--26s

IF OBJECT_ID('tempdb..#RecentGPMedicationsWeekdays') IS NOT NULL DROP TABLE #RecentGPMedicationsWeekdays;
select MedicationDate, Frequency, ROW_NUMBER() OVER (order by MedicationDate) AS IndexNumber
into #RecentGPMedicationsWeekdays
from #RecentGPMedications
where DATENAME(WEEKDAY, MedicationDate) IN ('Monday','Tuesday','Wednesday','Thursday','Friday');

select 
	g4.MedicationDate, g4.Frequency,
	CASE
		WHEN g4.Frequency < 100000 THEN 'Not enough records. Either not yet arrived, or this is a public holiday'
		WHEN 
			CASE 
				WHEN (CAST(g1.Frequency + g2.Frequency + g3.Frequency + g4.Frequency AS FLOAT)/4) = 0
				THEN 0 
				ELSE  g4.Frequency/(CAST(g1.Frequency + g2.Frequency + g3.Frequency + g4.Frequency AS FLOAT)/4)
			END < 0.8 THEN 'Below 80% of recent average - could mean not all records have arrived'
		ELSE 'Seems ok'
	END AS Assessment
 from #RecentGPMedicationsWeekdays g4
	left outer join #RecentGPMedicationsWeekdays g3 on g3.IndexNumber = g4.IndexNumber-1
	left outer join #RecentGPMedicationsWeekdays g2 on g2.IndexNumber = g4.IndexNumber-2
	left outer join #RecentGPMedicationsWeekdays g1 on g1.IndexNumber = g4.IndexNumber-3;