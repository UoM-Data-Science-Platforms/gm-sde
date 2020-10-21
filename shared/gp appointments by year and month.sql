-- Number of appointments per month
select YEAR(AppointmentDate), MONTH(AppointmentDate), count(*) from RLS.vw_GP_Appointments
where AppointmentDate >= '2020-01-01'
GROUP BY YEAR(AppointmentDate), MONTH(AppointmentDate)
ORDER BY YEAR(AppointmentDate), MONTH(AppointmentDate)


-- Example output

-- 2020	1	112045
-- 2020	2	99954
-- 2020	3	104058
-- 2020	4	60825
-- 2020	5	52751
-- 2020	6	64320
-- 2020	7	70151
-- 2020	8	63343
-- 2020	9	93956
-- 2020	10	70981
