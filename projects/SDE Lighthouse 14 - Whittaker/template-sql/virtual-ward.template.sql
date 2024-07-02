--┌────────────────────────────────────┐
--│ LH004 Virtual ward file            │
--└────────────────────────────────────┘

select 
"Unique Spell ID", 
"Provider Code", 
"Pseudo NHS Number", 
"Admission Source ID", 
"Admission Source", 
"Referral Date", 
"Referral Accepted Date", 
"Admission Date", 
"Ward ID", 
"Diagnosis Pathway ID", 
"Diagnosis Pathway", 
"On Boarding Method ID", 
"On Boarding Method", 
"Year Of Birth", 
"Month Of Birth", 
"Age on Admission", 
"Postcode_LSOA_2011", 
"Postcode Trimmed", 
"Ethnic Category", 
"Gender", 
"GP Code", 
"Discharge Destination", 
"Discharge Date", 
"Discharge Method", 
"Primary ICD10", 
"Primary ICD10 Code Group ID",
"Primary ICD10 Code Group", 
 SNAPSHOT_DATE

from INTERMEDIATE.LOCAL_FLOWS_VIRTUAL_WARDS.VIRTUAL_WARD_OCCUPANCY

