--- Store Level Data Extraction 
DECLARE @STARTDATE AS DATETIME
SET @STARTDATE = '04/01/2019'
DECLARE @ENDDATE AS DATETIME
SET @ENDDATE = '06/30/2019'
DECLARE @STARTSTORE AS INTEGER
SET @STARTSTORE = 100
DECLARE @ENDSTORE AS INTEGER
SET @ENDSTORE = 160


 --- Employee & Actual Labor Hours worked in every hour
 SELECT d.BusinessDate, l.StoreKey, l.Hour, l.EmployeeKey, j.JobName, lc.LaborCategoryName, l.ActualLaborMinutes
 FROM edw..factHourlyActualLabor l 
 JOIN edw..DimCalendar d
 ON  l.DateKey = d.DateKey
 JOIN edw..dimJobCode j
 ON j.JobCodeKey = l.JobCodeKey
 JOIN edw..dimLaborCategory lc
 ON lc.LaborCategoryKey = l.LaborCategoryKey
 WHERE d.BusinessDate >= @STARTDATE AND d.BusinessDate <=@ENDDATE AND l.StoreKey >= @STARTSTORE AND l.StoreKey <= @ENDSTORE AND LaborCategoryName = 'Cook'

 






