-- Number of practices per system
SELECT [System], count(*) FROM #PracticeSystemLookup
GROUP BY [System];
--EMIS..	358
--Vision	48
--TPP...	33

-- Number of patients per practice system
SELECT [System], count(*) FROM RLS.vw_Patient p
INNER JOIN #PracticeSystemLookup s on s.PracticeId = p.GPPracticeCode
WHERE FK_Reference_Tenancy_ID = 2
GROUP BY [System];
--EMIS..	2664271
--Vision	339043
--TPP...	214072

-- Patients per practice per system
--EMIS..	7442
--Vision	7063
--TPP...	6487

-- Number of encounters per system
SELECT p.[System], count(*) FROM RLS.vw_GP_Encounters e INNER JOIN #PracticeSystemLookup p on p.PracticeId = e.GPPracticeCode
WHERE EncounterDate >= '2020-01-01'
AND EncounterDate <= '2020-11-30'
GROUP BY p.[System];
--TPP	6090274
--EMIS	924494