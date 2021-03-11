DECLARE @conceptId nvarchar(64);
SET @conceptId = '391193001';

IF OBJECT_ID('tempdb..#SNOMED') IS NOT NULL DROP TABLE #SNOMED;
SELECT DISTINCT ConceptID, Term INTO #SNOMED FROM SharedCare.Reference_SnomedCT
WHERE ConceptID = @conceptId;

WHILE (@@ROWCOUNT > 0)
BEGIN
	INSERT INTO #SNOMED
	select distinct ConceptID, Term from SharedCare.Reference_SnomedCT
	where ConceptID in (
	select SourceConceptID COLLATE Latin1_General_CS_AS from SharedCare.Reference_SnomedCT_Relationships
	where DestinationConceptID IN (SELECT ConceptID COLLATE SQL_Latin1_General_CP1_CI_AS FROM #SNOMED)
	and RelationshipTypeConceptID='116680003')
	and ConceptID NOT IN (SELECT ConceptID COLLATE SQL_Latin1_General_CP1_CI_AS FROM #SNOMED);
END

select * from #SNOMED