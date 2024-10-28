-- This is a work in progress to assess how to classify GP encounters.
-- We can't use the GP_Appointment table as that is only TPP systems (i.e. not EMIS or Vision)

-- Populate a temp table with all distinct codes in the encounters table
SELECT [SuppliedCode], count(*) as freq into #encounters
  FROM [RLS].[vw_GP_Encounters]
  group by [SuppliedCode];
--1537

-- Use to find possible candidates in the table
select SuppliedCode, freq, Term30, Term60, Term198 from #encounters e
left outer join SharedCare.Reference_Coding r on r.Reference_Coding_ID = SuppliedCode
where (
	lower(Term30) like '%seen%' OR
	lower(Term60) like '%seen%' OR
	lower(Term198) like '%seen%'
	)
and SuppliedCode not in ('9N3F.','9N3A.','9N31.','9N311','9N310','9Nf9.','9Nf4.',
'8CAN.','8CAK.','9b0o.','9b0n.','9b0m.','8CAR0','8H9..','8H90.','615M.','6A...',
'9NkF.','9NkE.','9N11.','8CB..','9Na..','9N1C.','9N0l.')
order by freq desc

-- Need to further classify codes in #encounters
-- Issue: "Seen in practice" - probably face to face, but
-- "consultation", or "seen by GP", inconclusive - could be remote
select case 
	when SuppliedCode in ('9N3F.','9N3A.','9N31.','9N311','9N310','9Nf9.','9Nf4.','8CAN.','8CAK.','9b0o.','9b0n.','9b0m.','8CAR0','8H9..','8H90.','615M.') then 'Telephone' 
	when SuppliedCode in ('6A...') then 'Review' 
	when SuppliedCode in ('9NkF.','9NkE.','9N11.') then 'F2F' 
	when SuppliedCode in ('8CB..','9Na..') then 'Consultation' 
	when SuppliedCode in ('9N1C.') then 'HomeVisit' 
	when SuppliedCode in ('9N0l.') then 'OOH' 
	else 'Other' end, sum(freq) from #encounters e
left outer join SharedCare.Reference_Coding r on r.Reference_Coding_ID = SuppliedCode
where CodingType = 'ReadCodeV2'
group by case 
	when SuppliedCode in ('9N3F.','9N3A.','9N31.','9N311','9N310','9Nf9.','9Nf4.','8CAN.','8CAK.','9b0o.','9b0n.','9b0m.','8CAR0','8H9..','8H90.','615M.') then 'Telephone' 
	when SuppliedCode in ('6A...') then 'Review' 
	when SuppliedCode in ('9NkF.','9NkE.','9N11.') then 'F2F' 
	when SuppliedCode in ('8CB..','9Na..') then 'Consultation' 
	when SuppliedCode in ('9N1C.') then 'HomeVisit' 
	when SuppliedCode in ('9N0l.') then 'OOH' 
	else 'Other' end;
