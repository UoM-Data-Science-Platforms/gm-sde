--┌───────────┐
--│ ALL DATES │
--└───────────┘

-- OUTPUT: A temp table with all dates within a range.
-- #AllDates ([date])

-- Populate table with all dates from @StartDate
IF OBJECT_ID('tempdb..#AllDates') IS NOT NULL DROP TABLE #AllDates;
CREATE TABLE #AllDates ([date] DATE);
DECLARE @dt DATETIME = @StartDate
DECLARE @dtEnd DATETIME = GETDATE();
WHILE (@dt <= @dtEnd) BEGIN
    INSERT INTO #AllDates([date])
        VALUES(@dt)
    SET @dt = DATEADD(day, 1, @dt)
END;