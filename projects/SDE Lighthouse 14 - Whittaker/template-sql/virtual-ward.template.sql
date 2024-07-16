--┌────────────────────────────────────┐
--│ LH004 Virtual ward file            │
--└────────────────────────────────────┘
---- find the latest snapshot for each spell

create temporary table virtualWards as
select  
    dem."GmPseudo",
    vw."Unique Spell ID",
    vw."SnapshotDate",
    vw."Admission Source ID",
    adm."Admission Source Description",
    vw."Admission Date",
    vw."Discharge Date",
    vw."Length of stay",
    vw."LoS Group",
    vw."Year Of Birth",
    vw."Month Of Birth",
    vw."Age on Admission",
    vw."Age Group",
    vw."Gender Group" as Sex,
    vw."Ethnicity Group",
    vw."Postcode_LSOA_2011",
    vw."ProviderName",
    vw."Referral Group",
    vw."Referral Date",
    vw."Referral Accepted Date",
    vw."Primary ICD10 Code Group ID",
    vw."Primary ICD10 Code Group",
    vw."Ward ID",
    vw."Ward name",
    vw."WardCapacity",
    vw."Discharge Method",
    vw."Discharge Method Short",
    vw."Discharge Destination",
    vw."Discharge Destination Short",
    vw."Discharge Destination Group",
    vw."Diagnosis Pathway",
    vw."Step up or down",
    vw."Using tech-enabled service"
    
from PRESENTATION.LOCAL_FLOWS_VIRTUAL_WARDS.VIRTUAL_WARD_OCCUPANCY vw
-- join to demographics
left join INTERMEDIATE.GP_RECORD."DemographicsProtectedCharacteristics" dem
    on dem."GmPseudo" = SUBSTRING(vw."Pseudo NHS Number", 2)::INT
-- get admission source description
left join (select distinct "Admission Source ID", "Admission Source Description" 
           from PRESENTATION.LOCAL_FLOWS_VIRTUAL_WARDS.DQ_VIRTUAL_WARDS_ADMISSION_SOURCE) adm
    on adm."Admission Source ID" = vw."Admission Source ID"
-- filter to the latest snapshot for each spell
inner join (select  "Unique Spell ID", Max("SnapshotDate") "LatestRecord" 
            from PRESENTATION.LOCAL_FLOWS_VIRTUAL_WARDS.VIRTUAL_WARD_OCCUPANCY
            group by all) a 
    on a."Unique Spell ID" = vw."Unique Spell ID" and vw."SnapshotDate" = a."LatestRecord"

    
