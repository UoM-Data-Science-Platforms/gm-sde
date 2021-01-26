-- Number of unique patients in the platform
SELECT
    [PK_Patient_Link_ID],
    count(1) as occ

FROM [RLS].[vw_Patient_Link]
GROUP BY [PK_Patient_Link_ID]
ORDER BY occ ASC
-- 5230026 rows (on 23rd Nov 2020)
-- This includes patients not living in GM but had an event in a GM Trust. 
-- ONS estimates the GM population in 2020 to be 2.835.686


-- Number of COVID positive patients in the sample

WITH
    ConfirmedCases
    AS
    (
        SELECT c.FK_Patient_Link_ID
        FROM RLS.vw_COVID19 c
            INNER JOIN RLS.vw_Patient p ON p.FK_Patient_Link_ID = c.FK_Patient_Link_ID
        WHERE p.FK_Reference_Tenancy_ID = 2
            AND GroupDescription IN ('Confirmed')
        GROUP BY c.FK_Patient_Link_ID
    ),

    UniquePositivePatients
    AS
    (
        Select distinct FK_Patient_Link_ID
        FROM ConfirmedCases
    )

SELECT count(1) as TotalUniquePositivePatients
FROM UniquePositivePatients
-- 102658 rows (as of 8th DEC 2020)
-- This includes only patients with the status ‘Confirmed’  
-- Excludes suspected cases.



-- Number of unique patients who were positive and have a deceased flag
WITH
    UniquePositivePatientsDeceased
AS
(
        SELECT c.FK_Patient_Link_ID
FROM RLS.vw_COVID19 c
    INNER JOIN RLS.vw_Patient p ON p.FK_Patient_Link_ID = c.FK_Patient_Link_ID
WHERE p.FK_Reference_Tenancy_ID = 2
    AND c.GroupDescription IN ('Confirmed')
    AND c.DeceasedFlag IN ('Y')
GROUP BY c.FK_Patient_Link_ID
    )

SELECT count(1) TotalPositivePatientsDeceased
FROM UniquePositivePatientsDeceased 
-- 2354 (as of 23rd Nov 2020)
-- public figure of COVIDdeaths in GM is 3378 - as of 19 Nov 2020 https://www.manchestereveningnews.co.uk/news/greater-manchester-news/coronavirus-death-toll-greater-manchesters-19309592 
-- These are not deaths by COVID. We will get a death by Covid flag from Graphnet. 


-- Number of unique patients who were alive on 1st Feb 2020
WITH 
    fun
    as
    (
	    SELECT pl.*, CONVERT(DATE, DeathDate) as [DeathDateOnly]
        FROM RLS.vw_Patient_Link pl
            INNER JOIN RLS.vw_Patient p ON p.FK_Patient_Link_ID = pl.PK_Patient_Link_ID
        WHERE p.FK_Reference_Tenancy_ID = 2
	)

select count(1)
from fun
where  (Deceased IN ('N') AND DeathDateOnly is NULL)
    OR (Deceased IN ('Y') AND DeathDateOnly > '2020-02-01')
    OR (Deceased is NULL AND DeathDateOnly > '2020-02-01')
-- 3.426.526 (as of 8th Dec 2020)
--This includes deceased patients with a death date after the index date.
--Also, includes patients with a NULL decease flag 
--Excludes patients with deceased flag = N and death date > index date.

WITH
    fun
    as
    (
        SELECT pl.*, CONVERT(DATE, DeathDate) as [DeathDateOnly]
        FROM RLS.vw_Patient_Link pl
            INNER JOIN RLS.vw_Patient p ON p.FK_Patient_Link_ID = pl.PK_Patient_Link_ID
        --WHERE p.FK_Reference_Tenancy_ID = 2
    )
select count(1)
from fun
where  (Deceased IN ('N') AND DeathDateOnly is NULL)
    OR (Deceased IN ('Y') AND DeathDateOnly > '2020-02-01')
    OR (Deceased is NULL AND DeathDateOnly > '2020-02-01')
-- 1.1060.656 rows




-- Number of cancer patients in the sample




-- Number of high risk shielding patients in GP_Events
WITH
    TotalNoHighRiskPatients
    AS
    (

        SELECT [FK_Patient_Link_ID],
            Count(1) as occ
        FROM [RLS].[vw_GP_Events]
        WHERE [FK_Reference_SnomedCT_ID] = '994208'
        Group by [FK_Patient_Link_ID]
    )

select count(1)
from TotalNoHighRiskPatients;
-- 100477 (as of 7th Dec 2020)
-- SNOMED CT codes = 
-- 1300561000000107 (High risk category) = shielded patients
-- [PK_Reference_SnomedCT_ID] = 994208 in GP_Events
-- 1300571000000100 (Moderate risk category) = not shielded: but some risk
-- [PK_Reference_SnomedCT_ID] = 994209 in GP_Events 




-- Number of moderate risk patients in GP_Events
WITH
    TotalNoModerateRiskPatients
    AS
    (

        SELECT [FK_Patient_Link_ID],
            Count(1) as occ
        FROM [RLS].[vw_GP_Events]
        WHERE [FK_Reference_SnomedCT_ID] = '994209'
        Group by [FK_Patient_Link_ID]
    )

select count(1)
from TotalNoModerateRiskPatients;
-- 30455 (as of 7th Dec 2020)