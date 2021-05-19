with cancerRelatedCodingReferenceIds as (

    SELECT 
        [PK_Reference_Coding_ID],
		[FullDescription]
    FROM [SharedCare].[Reference_Coding]
    WHERE 
        ( ICD10Code LIKE 'C[0-8][0-9]' or ICD10Code LIKE 'C9[0-6]' or ICD10Code = 'C7A' or ICD10Code = 'C7B')
        and ICD10Code not LIKE 'C2[7-9]'

),

readcodeV2 as (
select [pk_reference_coding_id], [fulldescription]
 FROM [SharedCare].[Reference_Coding]
  where codingType = 'readcodev2'
  and mainCode like 'B34%'
  
  -- add mainCode related to cancer
  
  )

SELECT top(10)
    *
FROM 
[RLS].[vw_GP_Events] events
--[RLS].[vw_Acute_Coding] events
INNER JOIN readcodeV2 
ON events.[FK_Reference_Coding_ID] = readcodeV2.PK_Reference_Coding_ID
