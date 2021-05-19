-- Search for a particular SNOMED code in a table. In this case table GP_Events.
SELECT gpevents.*
FROM [SharedCare].[Reference_SnomedCT]
INNER JOIN [RLS].[vw_GP_Events] gpevents 
  ON ([PK_Reference_SnomedCT_ID] = gpevents.FK_Reference_SnomedCT_ID)
WHERE ConceptID = '1300571000000100';