--> CODESET diabetes:1
--> CODESET diabetes-type-i:1
--> CODESET diabetes-type-ii:1

IF OBJECT_ID('tempdb..#Sample') IS NOT NULL DROP TABLE #Sample;
SELECT TOP 1000 FK_Patient_Link_ID INTO #Sample FROM SharedCare.Patient_GP_History
GROUP BY FK_Patient_Link_ID
HAVING MIN(CAST(StartDate AS DATE)) < '2022-06-01'
ORDER BY NEWID();