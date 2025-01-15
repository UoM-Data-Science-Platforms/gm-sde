-- Preliminary work on identifying the patients with Hodgkin lymphoma or
-- diffuse large B-cell lymphoma within GM. The matched cohort for this
-- project is anyone with one of these lymphoma's who was not treated
-- by the Christie.

USE INTERMEDIATE.GP_RECORD;

-- Create a table to capture the results from the queries so we can
-- keep track of the numbers
drop table if exists "LymphomaStats";
create temporary table "LymphomaStats" (
	"Order" INT,
	"Category" VARCHAR(255),
	"Number" INT
);

-- First let's find anyone from the HES APC data who has a diagnosis
-- of Hodgkin lymphoma
drop table if exists "PatsWithHodgkinLymphoma";
create temporary table "PatsWithHodgkinLymphoma" as
select distinct "GmPseudo"
from presentation.national_flows_apc."DS708_Apcs"
where lower("DerDiagnosisAllAcrossAllEpisodes") like ('%c81%'); -- C81.* = Hodgkin lymphoma (ICD10 code)

-- Add the number to the tracking table
insert into "LymphomaStats"
select 1, 'Patients with Hodgkin Lymphoma from hospital APC table', count(*)
from "PatsWithHodgkinLymphoma";

-- However, we probably only want to include them it they also have a
-- primary care record. ADAPT is about long-term management of the 
-- patients when they are discharged into primary care, so we should
-- exclude people who don't have a GP record (because of living outside
-- GM or any other reason).
drop table if exists "PatsWithHodgkinLymphomaFromSUSWithGPRecord";
create temporary table "PatsWithHodgkinLymphomaFromSUSWithGPRecord" as
select distinct p."GmPseudo" from presentation.gp_record."DemographicsProtectedCharacteristics_SecondaryUses" d
inner join "PatsWithHodgkinLymphoma" p on p."GmPseudo" = d."GmPseudo";

-- Add the number to the tracking table
insert into "LymphomaStats"
select 2, '     - of which who also have a primary care record', count(*)
from "PatsWithHodgkinLymphomaFromSUSWithGPRecord";


-- Now we do the same as above but for patients with diffuse large B-cell
-- lymphoma
drop table if exists "PatsWithDLBCL";
create temporary table "PatsWithDLBCL" as
select distinct "GmPseudo"
from presentation.national_flows_apc."DS708_Apcs"
where lower("DerDiagnosisAllAcrossAllEpisodes")like ('%c833%'); -- C83.3 Diffuse large B-cell lymphoma (ICD10 code)

-- Add the number to the tracking table
insert into "LymphomaStats"
select 3, 'Patients with diffuse large B-cell Lymphoma from hospital APC table', count(*)
from "PatsWithDLBCL";

-- And again filter to those with a primary care record
drop table if exists "PatsWithDLBCLFromSUSWithGPRecord";
create temporary table "PatsWithDLBCLFromSUSWithGPRecord" as
select distinct p."GmPseudo" from presentation.gp_record."DemographicsProtectedCharacteristics_SecondaryUses" d
inner join "PatsWithDLBCL" p on p."GmPseudo" = d."GmPseudo";

-- Add the number to the tracking table
insert into "LymphomaStats"
select 4, '     - of which who also have a primary care record', count(*)
from "PatsWithDLBCLFromSUSWithGPRecord";

-- Now we join the two groups together to see how many people
-- have either Hodgkin or diffuse large b-cell in HES data,
-- and a primary care record.
drop table if exists "PatsFromSUSWithGPRecord";
create temporary table "PatsFromSUSWithGPRecord" as
select * from "PatsWithHodgkinLymphomaFromSUSWithGPRecord"
UNION
select * from "PatsWithDLBCLFromSUSWithGPRecord";

-- Add the number to the tracking table
insert into "LymphomaStats"
select 5, 'Patients with either Lymphoma from hospital APC table who also have a primary care record', count(*)
from "PatsFromSUSWithGPRecord";

-- Now let's look in the GP_Events table. The SNOMED codes are from a simple
-- search in the hierarchy, but should be double checked in the usual way
-- before actual use. This should give a good approximation of the numbers
-- though as it includes all the main codes.
drop table if exists "GPPatsWithDLBCL";
create temporary table "GPPatsWithDLBCL" as
select distinct "FK_Patient_ID" from INTERMEDIATE.GP_RECORD."GP_Events_SecondaryUses" e
left join SDE_REPOSITORY.SHARED_UTILITIES."Code_Sets_SDE_Lighthouse_15_Radford_Adapt" cs on cs.code = e.sctid
where cs.concept = 'diffuse-large-b-cell-lymphoma';

insert into "LymphomaStats"
select 6, 'Patients with diffuse large b-cell lymphoma from primary care record', count(*)
from "GPPatsWithDLBCL";

-- And for Hodgkin Lymphoma
drop table if exists "GPPatsWithHodgkinLymphoma";
create temporary table "GPPatsWithHodgkinLymphoma" as
select distinct "FK_Patient_ID" from INTERMEDIATE.GP_RECORD."GP_Events_SecondaryUses" e
left join SDE_REPOSITORY.SHARED_UTILITIES."Code_Sets_SDE_Lighthouse_15_Radford_Adapt" cs on cs.code = e.sctid
where cs.concept = 'hodgkin-lymphoma';

insert into "LymphomaStats"
select 7, 'Patients with Hodgkin lymphoma from primary care record', count(*)
from "GPPatsWithHodgkinLymphoma";

-- Now we find any patients with one or both, and link to demographics
-- table to get the GmPseudo
drop table if exists "PatsFromGPRecord";
create temporary table "PatsFromGPRecord" as
select "GmPseudo" from "GPPatsWithDLBCL" d
inner join presentation.gp_record."DemographicsProtectedCharacteristics_SecondaryUses" dpc on dpc."FK_Patient_ID" = d."FK_Patient_ID"
UNION
select "GmPseudo" from "GPPatsWithHodgkinLymphoma" h
inner join presentation.gp_record."DemographicsProtectedCharacteristics_SecondaryUses" dpc on dpc."FK_Patient_ID" = h."FK_Patient_ID";

insert into "LymphomaStats"
select 8, 'Patients with either lymphoma from primary care record', count(*)
from "PatsFromGPRecord";

insert into "LymphomaStats"
select 9,'Patients with lymphoma in GP record BUT NOT in HES APC data', count(*) 
from (select * from "PatsFromGPRecord" except select * from "PatsFromSUSWithGPRecord");

insert into "LymphomaStats"
select 10,'Patients with lymphoma in GP record AND in HES APC data', count(*) 
from (select * from "PatsFromGPRecord" intersect select * from "PatsFromSUSWithGPRecord");

insert into "LymphomaStats"
select 11,'Patients with lymphoma in HES APC data BUT NOT the GP record', count(*) 
from (select * from "PatsFromSUSWithGPRecord" except select * from "PatsFromGPRecord");

insert into "LymphomaStats"
select 12,'Patients with lymphoma in HES APC data OR the GP record', count(*) 
from (select * from "PatsFromSUSWithGPRecord" union select * from "PatsFromGPRecord");

select "Category", "Number" from "LymphomaStats"
order by "Order";
