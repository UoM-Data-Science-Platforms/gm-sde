-- Calculate the number of deaths per year for each CCG
IF OBJECT_ID('tempdb..#DeathsPerCCGPerYear') IS NOT NULL DROP TABLE #DeathsPerCCGPerYear;
SELECT Commissioner, YEAR(DeathDate) as YearOfDeath, count(*) as [NumberOfDeaths] INTO #DeathsPerCCGPerYear FROM RLS.vw_Patient p
	INNER JOIN RLS.vw_Patient_Link pl ON p.FK_Patient_Link_ID = pl.PK_Patient_Link_ID
	INNER JOIN SharedCare.Reference_GP_Practice g on g.OrganisationCode = GPPracticeCode
WHERE FK_Reference_Tenancy_ID = 2 -- org links
AND Deceased = 'Y'
GROUP BY Commissioner,YEAR(DeathDate);

-- Populate a table to lookup the ccg ids to ccg names
IF OBJECT_ID('tempdb..#CCGLookup') IS NOT NULL DROP TABLE #CCGLookup;
CREATE TABLE #CCGLookup (id nchar(3), [Name] nvarchar(20));
INSERT INTO #CCGLookup VALUES ('01G', 'Salford'); 
INSERT INTO #CCGLookup VALUES ('00T', 'Bolton'); 
INSERT INTO #CCGLookup VALUES ('01D', 'HMR'); 
INSERT INTO #CCGLookup VALUES ('02A', 'Trafford'); 
INSERT INTO #CCGLookup VALUES ('01W', 'Stockport');
INSERT INTO #CCGLookup VALUES ('00Y', 'Oldham'); 
INSERT INTO #CCGLookup VALUES ('02H', 'Wigan'); 
INSERT INTO #CCGLookup VALUES ('00V', 'Bury'); 
INSERT INTO #CCGLookup VALUES ('14L', 'Manchester'); 
INSERT INTO #CCGLookup VALUES ('01Y', 'Tameside Glossop'); 

-- Output for each CCG the number of deaths recorded per year
SELECT [Name], YearOfDeath, [NumberOfDeaths] FROM #DeathsPerCCGPerYear
INNER JOIN #CCGLookup c on c.id = Commissioner
ORDER BY Commissioner, YearOfDeath

-- From output below we can assume the following start dates for CCG data feeds:

-- Bolton 2017
-- Bury 2018
-- Oldham 2018
-- HMR 2018
-- Salford 2018
-- Stockport 2013
-- Tameside 2020
-- Trafford 2017
-- Wigan 2020
-- Manchester 2017

-- Name	YearOfDeath	NumberOfDeaths
-- Bolton	2013	3
-- Bolton	2014	6
-- Bolton	2015	11
-- Bolton	2016	12
-- Bolton	2017	763
-- Bolton	2018	2526
-- Bolton	2019	2564
-- Bolton	2020	2389
-- Bury	NULL	1
-- Bury	1996	1
-- Bury	2013	4
-- Bury	2014	5
-- Bury	2015	10
-- Bury	2016	12
-- Bury	2017	25
-- Bury	2018	586
-- Bury	2019	1799
-- Bury	2020	1636
-- Oldham	1990	1
-- Oldham	1999	1
-- Oldham	2012	1
-- Oldham	2013	6
-- Oldham	2014	7
-- Oldham	2015	9
-- Oldham	2016	4
-- Oldham	2017	14
-- Oldham	2018	311
-- Oldham	2019	1832
-- Oldham	2020	1755
-- HMR	2012	1
-- HMR	2013	1
-- HMR	2014	4
-- HMR	2015	8
-- HMR	2016	5
-- HMR	2017	26
-- HMR	2018	1161
-- HMR	2019	2045
-- HMR	2020	1783
-- Salford	NULL	2
-- Salford	1992	1
-- Salford	1996	1
-- Salford	2005	1
-- Salford	2009	1
-- Salford	2011	1
-- Salford	2012	1
-- Salford	2013	3
-- Salford	2014	11
-- Salford	2015	18
-- Salford	2016	12
-- Salford	2017	28
-- Salford	2018	918
-- Salford	2019	2048
-- Salford	2020	1928
-- Stockport	2006	1
-- Stockport	2007	1
-- Stockport	2008	1
-- Stockport	2010	4
-- Stockport	2011	3
-- Stockport	2012	33
-- Stockport	2013	2899
-- Stockport	2014	3435
-- Stockport	2015	3552
-- Stockport	2016	3400
-- Stockport	2017	2991
-- Stockport	2018	2596
-- Stockport	2019	2594
-- Stockport	2020	2498
-- Tameside Glossop	1900	14
-- Tameside Glossop	2013	19
-- Tameside Glossop	2014	33
-- Tameside Glossop	2015	34
-- Tameside Glossop	2016	30
-- Tameside Glossop	2017	32
-- Tameside Glossop	2018	64
-- Tameside Glossop	2019	104
-- Tameside Glossop	2020	1557
-- Trafford	NULL	3
-- Trafford	2002	1
-- Trafford	2005	1
-- Trafford	2006	1
-- Trafford	2013	4
-- Trafford	2014	8
-- Trafford	2015	9
-- Trafford	2016	21
-- Trafford	2017	464
-- Trafford	2018	1866
-- Trafford	2019	1875
-- Trafford	2020	1733
-- Wigan	2013	5
-- Wigan	2014	1
-- Wigan	2015	5
-- Wigan	2016	3
-- Wigan	2017	5
-- Wigan	2018	19
-- Wigan	2019	41
-- Wigan	2020	2171
-- Manchester	NULL	4
-- Manchester	1980	1
-- Manchester	1991	1
-- Manchester	1993	1
-- Manchester	1995	1
-- Manchester	1997	1
-- Manchester	1999	1
-- Manchester	2001	2
-- Manchester	2002	1
-- Manchester	2004	1
-- Manchester	2006	2
-- Manchester	2007	2
-- Manchester	2008	3
-- Manchester	2009	4
-- Manchester	2010	2
-- Manchester	2011	1
-- Manchester	2012	5
-- Manchester	2013	52
-- Manchester	2014	210
-- Manchester	2015	320
-- Manchester	2016	366
-- Manchester	2017	1015
-- Manchester	2018	3420
-- Manchester	2019	3702
-- Manchester	2020	3334