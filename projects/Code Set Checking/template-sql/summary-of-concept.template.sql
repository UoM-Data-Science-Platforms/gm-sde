--┌──────────────────────────────────────────────┐
--│ Provides a summary for a particular code set │
--└──────────────────────────────────────────────┘

-- OBJECTIVE: To provide a summary of a code set to help determine if there are sufficient
--						cases for a particular analysis. The intention is that some of the outputs of
--						this would be provided to the end user who could then decide whether to apply
--						for a data extract.

-- INPUT: No pre-requisites

-- OUTPUT:
--		1) A table showing the prevalence of individual clinical codes
--		2) A table showing yearly incidence for the concept (how many get it for the first time)
--		3) A table showing yearly prevalence for the concept (how many people alive with it)
--		4) A table showing monthly incidence for the concept
--		5) A table showing monthly prevalence for the concept

--Just want the output, not the messages
SET NOCOUNT ON;

--> CODESET insert-concept-here:1

IF OBJECT_ID('tempdb..#Occurrences1') IS NOT NULL DROP TABLE #Occurrences1;
SELECT FK_Patient_Link_ID, SuppliedCode, FK_Reference_Coding_ID, FK_Reference_SnomedCT_ID, CAST(EventDate AS DATE) AS DateOfConcept
INTO #Occurrences1
FROM RLS.vw_GP_Events
WHERE FK_Reference_Coding_ID IN (SELECT FK_Reference_Coding_ID FROM #VersionedCodeSets)
AND EventDate IS NOT NULL;

IF OBJECT_ID('tempdb..#Occurrences2') IS NOT NULL DROP TABLE #Occurrences2;
SELECT FK_Patient_Link_ID, SuppliedCode, FK_Reference_Coding_ID, FK_Reference_SnomedCT_ID, CAST(EventDate AS DATE) AS DateOfConcept
INTO #Occurrences2
FROM RLS.vw_GP_Events
WHERE FK_Reference_SnomedCT_ID IN (SELECT FK_Reference_SnomedCT_ID FROM #VersionedSnomedSets)
AND EventDate IS NOT NULL;

IF OBJECT_ID('tempdb..#FirstOccurrences') IS NOT NULL DROP TABLE #FirstOccurrences;
SELECT FK_Patient_Link_ID, MIN(DateOfConcept) AS FirstDate
INTO #FirstOccurrences
FROM (
	SELECT * FROM #Occurrences1
	UNION
	SELECT * FROM #Occurrences2
) sub
GROUP BY FK_Patient_Link_ID;

IF OBJECT_ID('tempdb..#Years') IS NOT NULL DROP TABLE #Years;
CREATE TABLE #Years (
	[Year] INT
);
IF OBJECT_ID('tempdb..#Months') IS NOT NULL DROP TABLE #Months;
CREATE TABLE #Months (
	[Year] INT,
	[Month] INT
);
DECLARE @Year INT 
SET @Year=2000
DECLARE @Month INT 
SET @Month=1
WHILE ( @Year <= YEAR(GETDATE()))
BEGIN
    INSERT INTO #Years VALUES (@Year)
	WHILE(@Month <= 12)
	BEGIN
		INSERT INTO #Months VALUES (@Year, @Month)
		SET @Month = @Month + 1
	END
	SET @Month=1
    SET @Year = @Year + 1
END

IF OBJECT_ID('tempdb..#AllOccurrences') IS NOT NULL DROP TABLE #AllOccurrences;
SELECT * INTO #AllOccurrences FROM #Occurrences1
UNION
SELECT * FROM #Occurrences2;

-- This attempts to show for each clinical code how frequently it occurs.
IF OBJECT_ID('tempdb..#CodePrevalence') IS NOT NULL DROP TABLE #CodePrevalence;
SELECT 
	CASE WHEN Term IS NULL THEN MainCode ELSE CONCAT(MainCode,Term) END AS Code,
	CodingType,
	CASE
		WHEN FullDescription IS NOT NULL AND  FullDescription!='' THEN FullDescription COLLATE Latin1_General_CS_AS
		WHEN Term198 IS NOT NULL AND  Term198!='' THEN Term198 COLLATE Latin1_General_CS_AS
		WHEN Term60 IS NOT NULL AND  Term60!='' THEN Term60 COLLATE Latin1_General_CS_AS
		ELSE Term30 COLLATE Latin1_General_CS_AS
	END AS Description, Frequency
INTO #CodePrevalence
FROM (
	SELECT 
		CASE WHEN s1.FK_Reference_Coding_ID IS NULL THEN s2.FK_Reference_Coding_ID ELSE s1.FK_Reference_Coding_ID END AS FK_Reference_Coding_ID,
		CASE
			WHEN s1.Frequency IS NULL THEN s2.Frequency
			WHEN s2.Frequency IS NULL THEN s1.Frequency
			ELSE s1.Frequency + s2.Frequency
		END AS Frequency
	FROM (
	SELECT FK_Reference_Coding_ID, COUNT(*) AS Frequency FROM #AllOccurrences
	WHERE FK_Reference_Coding_ID != -1
	AND SuppliedCode IN (SELECT Code FROM #AllCodes)
	GROUP BY FK_Reference_Coding_ID ) s1
	FULL OUTER JOIN  (SELECT FK_Reference_Coding_ID, COUNT(*) AS Frequency FROM #AllOccurrences
	WHERE FK_Reference_Coding_ID != -1
	AND SuppliedCode NOT IN (SELECT Code FROM #AllCodes)
	GROUP BY FK_Reference_Coding_ID ) s2 on s1.FK_Reference_Coding_ID = s2.FK_Reference_Coding_ID
) sub
left outer join SharedCare.Reference_Coding r on (r.PK_Reference_Coding_ID = sub.FK_Reference_Coding_ID)
union
SELECT ConceptID, 'SNOMED', Term, Frequency FROM (
	SELECT FK_Reference_SnomedCT_ID, COUNT(*) AS Frequency FROM #AllOccurrences
	WHERE FK_Reference_Coding_ID = -1
	AND FK_Reference_SnomedCT_ID != -1
	GROUP BY FK_Reference_SnomedCT_ID
) sub
left outer join SharedCare.Reference_SnomedCT s on (s.PK_Reference_SnomedCT_ID = sub.FK_Reference_SnomedCT_ID)
order by Frequency desc;

IF OBJECT_ID('tempdb..#FirstOccurrencesYearBreakdown') IS NOT NULL DROP TABLE #FirstOccurrencesYearBreakdown;
SELECT y.[Year], CASE WHEN Occurrences IS NULL OR Occurrences < 10 THEN '0-9' ELSE CAST(Occurrences AS VARCHAR) END AS Occurrences
INTO #FirstOccurrencesYearBreakdown
FROM #Years y
LEFT OUTER JOIN (
	select YEAR(FirstDate) AS [Year], count(*) AS Occurrences from #FirstOccurrences
	group by YEAR(FirstDate)
) sub ON sub.[Year] = y.[Year];


IF OBJECT_ID('tempdb..#FirstOccurrencesMonthBreakdown') IS NOT NULL DROP TABLE #FirstOccurrencesMonthBreakdown;
SELECT m.[Year], m.[Month], CASE WHEN Occurrences IS NULL OR Occurrences < 10 THEN '0-9' ELSE CAST(Occurrences AS VARCHAR) END AS Occurrences
INTO #FirstOccurrencesMonthBreakdown
FROM #Months m
LEFT OUTER JOIN (
	select YEAR(FirstDate) AS [Year], MONTH(FirstDate) AS [Month], count(*) AS Occurrences from #FirstOccurrences
	group by YEAR(FirstDate), MONTH(FirstDate)
) sub ON sub.[Year] = m.[Year] AND sub.[Month] = m.[Month];

IF OBJECT_ID('tempdb..#Deaths') IS NOT NULL DROP TABLE #Deaths;
SELECT PK_Patient_Link_ID AS FK_Patient_Link_ID, DeathDate 
INTO #Deaths
FROM RLS.vw_Patient_Link
WHERE PK_Patient_Link_ID IN (SELECT FK_Patient_Link_ID FROM #FirstOccurrences);

IF OBJECT_ID('tempdb..#PrevalenceYearBreakdown') IS NOT NULL DROP TABLE #PrevalenceYearBreakdown;
select [Year], count(*) AS Prevalence
into #PrevalenceYearBreakdown 
from #Years
left outer join (
	SELECT fo.FK_Patient_Link_ID, fo.FirstDate, d.DeathDate FROM #FirstOccurrences fo
	left outer join #Deaths d on d.FK_Patient_Link_ID = fo.FK_Patient_Link_ID
) sub on YEAR(sub.FirstDate) < [Year] and (DeathDate is null or YEAR(DeathDate) >= [Year])
group by [Year];

IF OBJECT_ID('tempdb..#PrevalenceMonthBreakdown') IS NOT NULL DROP TABLE #PrevalenceMonthBreakdown;
select [Year], [Month], count(*) AS Prevalence
into #PrevalenceMonthBreakdown 
from #Months
left outer join (
	SELECT fo.FK_Patient_Link_ID, fo.FirstDate, d.DeathDate FROM #FirstOccurrences fo
	left outer join #Deaths d on d.FK_Patient_Link_ID = fo.FK_Patient_Link_ID
) sub on sub.FirstDate < DATEFROMPARTS([Year], [Month], 1) and (DeathDate is null or DeathDate >= DATEFROMPARTS([Year], [Month], 1))
group by [Year], [Month];


DECLARE @NewLineChar AS CHAR(2) = CHAR(13) + CHAR(10)
DECLARE @TabChar AS CHAR(1) = CHAR(9);

SELECT * FROM #CodePrevalence

select 'Table 1: The number of people who have this concept in their record for the first time per year (incidence)' + @NewLineChar + @NewLineChar
union all
select 'Year' + @TabChar + 'Incidence'
union all
select CONCAT(Year, @TabChar, Occurrences) from #FirstOccurrencesYearBreakdown;


select 'Table 2: The number of people who have this concept in their record for the first time per month (incidence)' + @NewLineChar + @NewLineChar
union all
select 'Year' + @TabChar + 'Month' + @TabChar + 'Incidence'
union all
select CONCAT(Year, @TabChar, Month, @TabChar, Occurrences) from #FirstOccurrencesMonthBreakdown;

select 'Table 3: The number of living people at the start of each year who have this concept earlier in their record (prevalence)' + @NewLineChar + @NewLineChar
union all
select 'Year' + @TabChar + 'Prevalence'
union all
select CONCAT(p1.Year, @TabChar, CASE 
		WHEN p1.Prevalence < 10 THEN '0-9'
		WHEN p1.Prevalence - p2.Prevalence < 10 AND p1.Prevalence - p2.Prevalence >= 0 THEN N'? <10'
		WHEN p1.Prevalence - p2.Prevalence > -10 AND p1.Prevalence - p2.Prevalence <= 0 THEN N'? <10'
		ELSE CAST(p1.Prevalence AS VARCHAR) END)
from #PrevalenceYearBreakdown p1	
left outer join #PrevalenceYearBreakdown p2 on p1.Year = p2.Year + 1;


select [Text] FROM (
select 'Table 4: The number of living people at the start of each month who have this concept earlier in their record (prevalence)' + @NewLineChar + @NewLineChar as [Text], -1 as rn
union all
select 'Year' + @TabChar + 'Month' + @TabChar + 'Prevalence', 0
union all
select CONCAT(p1.Year, @TabChar,p1.Month, @TabChar, CASE 
		WHEN p1.Prevalence < 3 THEN '0-9'
		WHEN p1.Prevalence - p2.Prevalence < 3 AND p1.Prevalence - p2.Prevalence >= 0 THEN N'? <10'
		WHEN p1.Prevalence - p2.Prevalence > -3 AND p1.Prevalence - p2.Prevalence <= 0 THEN N'? <10'
		ELSE CAST(p1.Prevalence AS VARCHAR) END) as thing, p1.Year*100 + p1.Month
from #PrevalenceMonthBreakdown p1	
left outer join #PrevalenceMonthBreakdown p2 on (p1.Year = p2.Year AND p1.Month = p2.Month + 1) OR (p1.Year = p2.Year + 1 and p1.Month = 1 and p2.Month = 12)
) sub ORDER BY sub.rn;