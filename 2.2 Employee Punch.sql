DECLARE @STARTDATE AS DATETIME
SET @STARTDATE = '06/03/2018'
DECLARE @ENDDATE AS DATETIME
SET @ENDDATE  = '07/11/2019'
DECLARE @STORE AS INTEGER
SET @STORE = 171
IF OBJECT_ID('tempdb..#PUNCH') IS NOT NULL DROP TABLE #PUNCH

select p.STORE 'StoreKey', e.ALT_NUM 'EmployeeNum', p.Date 'BusinessDate', p.TIME_IN, p.TIME_OUT, p.PUNCH_TYPE, 
case when p.shift = 2 then 'Lunch'
	when p.shift = 3 then 'Dinner'
	else NULL
end as 'ShiftName'
into #PUNCH
from CPR..payrpunch p
join CPR..stg_EMPFILE e
on cast(p.EMPL_NUM as int) = cast(e.EMP_NUMBER as int) and cast(p.STORE as int) = cast(e.STORE as int)
where cast(p.STORE as int) = @STORE and p.DATE >= @STARTDATE
order by p.DATE, e.ALT_NUM

--- Employee Scheduled Labor & Station
 select d.BusinessDate, l.StoreKey, e.EmployeeNum, l.StartTime 'ScheduleStart', l.EndTime 'ScheduleEnd', s.TIME_IN 'ActualStart', s.TIME_OUT 'ActualEnd', j.JobName, lc.LaborCategoryName, l.LocationName
 from edw..factDailyScheduleLabor l 
 join edw..DimCalendar d
 on  l.DateKey = d.DateKey
 join edw..dimJobCode j
 on j.JobCodeKey = l.JobCodeKey
 join edw..dimLaborCategory lc
 on lc.LaborCategoryKey = l.LaborCategoryKey
 join edw..dimEmployee e
 on l.Employeekey = e.EmployeeKey
 join #PUNCH s 
 on s.StoreKey = l.Storekey and s.EmployeeNum = e.EmployeeNum and s.BusinessDate = d.BusinessDate
 where d.BusinessDate >= @STARTDATE and d.BusinessDate <= @ENDDATE and l.Storekey = @STORE
 order by d.BusinessDate, l.Employeekey

