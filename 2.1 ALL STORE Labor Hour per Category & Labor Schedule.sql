---FOR ALL STORES

DECLARE @STARTDATE AS DATETIME
SET @STARTDATE = '01/10/2018'
DECLARE @ENDDATE AS DATETIME
SET @ENDDATE  = '07/11/2019'

---Labor Schedule: employee and their scheduled locations for ALL STORES
 select d.BusinessDate, l.StoreKey, e.EmployeeNum, l.StartTime 'ScheduleStart', l.EndTime 'ScheduleEnd', l.ShiftName, j.JobName, lc.LaborCategoryName, l.StartTime, l.EndTime, l.LocationName
 from edw..factDailyScheduleLabor l 
 join edw..DimCalendar d
 on  l.DateKey = d.DateKey
 join edw..dimJobCode j
 on j.JobCodeKey = l.JobCodeKey
 join edw..dimLaborCategory lc
 on lc.LaborCategoryKey = l.LaborCategoryKey
 join edw..dimEmployee e
 on l.Employeekey = e.EmployeeKey
 where d.BusinessDate >= @STARTDATE and d.BusinessDate <= @ENDDATE
 order by d.BusinessDate, l.Employeekey
 ---Save the above result in the format of: employee_station_20180103-20190711



-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------


--- Hourly Actual Labor Hours per Category for ALL STORES 
select c.BusinessDate, l.StoreKey, lc.LaborCategoryName, l.HourDescription, l.ActualLaborHrs
from edw..aggHourlyActualLabor l
left join edw..DimCalendar c
on l.datekey = c.datekey
left join edw..dimLaborCategory lc
on lc.LaborCategoryKey = l.LaborCategoryKey
where l.storekey <>-1 and l.StoreKey <>-2 and BusinessDate >= @STARTDATE and c.BusinessDate <=@ENDDATE
---Save the above result in the format of: labor_20180103-20190711.csv

