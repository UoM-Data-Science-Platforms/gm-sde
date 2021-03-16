
---- LOAD A FILE OF ALL PATIENT_LINK_IDS ALONGSIDE A SET OF RANDOMISED IDS, WHICH IS UNIQUE TO EACH STUDY

IF OBJECT_ID('tempdb..#randomised_ids') IS NOT NULL DROP TABLE #randomised_ids;

CREATE TABLE #randomised_ids (PATIENT_LINK_ID INT, RANDOM_PATIENT_ID INT)

BULK INSERT #randomised_ids FROM 'C:\Users\George\Documents\GitHub\gm-idcr\projects\_example\output-data-files\randomise-patient-id.txt' WITH (FIELDTERMINATOR = ',', FIRSTROW = 2);

SELECT * FROM #randomised_ids