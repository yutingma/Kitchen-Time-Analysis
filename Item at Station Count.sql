
IF OBJECT_ID('tempdb..#BASE') IS NOT NULL DROP TABLE #BASE
IF OBJECT_ID('tempdb..#BASE1') IS NOT NULL DROP TABLE #BASE1
IF OBJECT_ID('tempdb..#STATIONCOUNT') IS NOT NULL DROP TABLE #STATIONCOUNT
IF OBJECT_ID('tempdb..#STATIONCOUNT1') IS NOT NULL DROP TABLE #STATIONCOUNT1

DECLARE @STARTDATE AS DATETIME
SET @STARTDATE = '04/01/2019'
DECLARE @ENDDATE AS DATETIME
SET @ENDDATE = '06/30/2019'

DECLARE @STARTSTORE AS INTEGER
SET @STARTSTORE = 100
DECLARE @ENDSTORE AS INTEGER
SET @ENDSTORE = 160

SELECT DISTINCT
o.StoreKey, o.BusinessDate, o.TimeKey, o.CheckNum, o.ProductKey,o.CourseName, 
o.SentTime, o.NormalDateTime,o.CookingDateTime,o.BumpedDateTime, o.EmployeeKey, o.OrderStartDateTime, o.StationKey,o.DateKey
INTO #BASE1
from edw..factKitchenOrderLineItem o 
join edw..DimCalendar c on o.DateKey = c.DateKey
WHERE StoreKey >= @STARTSTORE AND StoreKey <= @ENDSTORE AND c.BusinessDate >= @STARTDATE AND c.BusinessDate <= @ENDDATE

SELECT o.StoreKey, 
--Day & Time
o.BusinessDate, o.DateKey, DATENAME(weekday,o.BusinessDate) DayOfWeek, o.TimeKey, FLOOR((o.TimeKey-1) / 4) FullHour, (FLOOR((o.TimeKey-1)/2)/2.0) HalfHour, (o.TimeKey-1)/4.0 QuarterHour,t.StartTime,
CASE WHEN NatHolidayDesc LIKE '[0-9][0-9]/[0-9][0-9]/[0-9]%' THEN 0 ELSE 1 END AS Holiday, 
---Order
o.CheckNum, s.GuestCount, s.TableOpenMinutes, s.OpenHour, s.OpenMinute, s.CloseHour, s.CloseMinute, ch.ChannelKey, ch.TypeofServiceNum,
---Item
o.ProductKey,o.StationKey,st.StationName, o.SentTime, 
--p.MajorCodeName,p.MinorCodeName, 
---Round OrderStartDateTime to minute + Other DateTime
DATEADD(minute, DATEDIFF(minute, 0, o.OrderStartDateTime), 0) 'OrderStartDateTime',o.NormalDateTime,o.CookingDateTime,o.BumpedDateTime, c.NatHolidayDesc, o.EmployeeKey,
---Calculate TicketTime
DATEDIFF(SECOND,o.NormalDateTime,o.BumpedDateTime) 'TicketTime',
DATEDIFF(SECOND,o.CookingDateTime, o.BumpedDateTime) 'CookTime',
DATEDIFF(SECOND,o.OrderStartDateTime, o.BumpedDateTime) 'OrderTime', 
---Rank within order, item, station: # of same item ordered in an check
ROW_NUMBER() OVER (PARTITION BY o.CheckNum, o.BusinessDate, o.ProductKey, o.StationKey,  DATEADD(minute, DATEDIFF(minute, 0, o.OrderStartDateTime), 0)  ORDER BY DATEDIFF(SECOND,o.NormalDateTime,o.BumpedDateTime) DESC) 'RNK',
---Rank within order, item: the slowest Item-Station
ROW_NUMBER() OVER (PARTITION BY o.CheckNum, o.BusinessDate, o.ProductKey, DATEADD(minute, DATEDIFF(minute, 0, o.OrderStartDateTime), 0)  ORDER BY DATEDIFF(SECOND,o.NormalDateTime,o.BumpedDateTime) DESC) 'PROD_RNK'
INTO #BASE
FROM #BASE1 o 
JOIN edw..factsalestxn s 
ON o.DateKey = s.DateKey and o.StoreKey=s.StoreKey and o.CheckNum=s.CheckNum
JOIN edw..dimChannel ch 
ON s.ChannelKey = ch.ChannelKey
LEFT JOIN edw..factEmployeeMeal em
ON o.DateKey = em.Datekey and o.StoreKey = em.Storekey and o.CheckNum = em.Checknum
JOIN edw..dimStation st
ON o.StationKey = st.StationKey
JOIN edw..DimTime t
ON o.TimeKey = t.TimeID
JOIN edw..DimCalendar c
ON o.DateKey = c.DateKey
--JOIN edw..dimProduct p
--ON o.ProductKey = p.ProductKey
WHERE em.Employeekey IS NULL AND o.CourseName = 'ENTREES' AND st.StationName <> 'KMEXPO' 
--AND p.MajorCodeName not in ('BEVERAGES','Beverages','BEER','Beer','Desserts','Desserts','DESSERTS2','G/C ETC','G/C etc','Groceries','Liquor','LIQUOR','Not in Table','Whole Cakes','WHOLE CAKES','Wine' ,'WINE','SLICES','Slices','SIDES') 
--and p.MinorCodeName not in ('Sides','Soups','SOUPS','SIDES','BREAKFAST SIDES')

SELECT #BASE.StoreKey, #BASE.BusinessDate, #BASE.Holiday, #BASE.FullHour, #BASE.CheckNum, #BASE.ProductKey, #BASE.NormalDateTime, #BASE.CookingDateTime, #BASE.BumpedDateTime, #BASE.StationName 'ProdStation', #BASE.TicketTime, #BASE.CookTime, #BASE.OrderTime, PRODCOUNT.StationName,
COUNT(PRODCOUNT.ProductKey) 'ITEMCOUNT'
INTO #STATIONCOUNT
FROM #BASE 
JOIN #BASE PRODCOUNT ON 
    #BASE.StoreKey = PRODCOUNT.StoreKey AND 
    #BASE.BusinessDate = PRODCOUNT.BusinessDate AND
	PRODCOUNT.BumpedDateTime > #BASE.CookingDateTime AND 
	PRODCOUNT.CookingDateTime < #BASE.CookingDateTime
GROUP BY #BASE.StoreKey, #BASE.BusinessDate, #BASE.Holiday, #BASE.FullHour, #BASE.CheckNum, #BASE.ProductKey, #BASE.NormalDateTime, #BASE.CookingDateTime, #BASE.BumpedDateTime, #BASE.StationName, #BASE.TicketTime, #BASE.CookTime, #BASE.OrderTime, PRODCOUNT.StationName

SELECT StoreKey, BusinessDate, FullHour, Holiday, CheckNum, ProductKey, StationName, TicketTime, CookTime, OrderTime, ITEMCOUNT AS ItemAtStation
INTO #STATIONCOUNT1
FROM #STATIONCOUNT
WHERE ProdStation = StationName

SELECT StationName, ItemAtStation, AVG(TicketTime) AvgTicketTime, AVG(CookTime) AvgCookTime, AVG(OrderTime) AvgOrderTime, COUNT(ProductKey) Count
FROM #STATIONCOUNT1
WHERE Holiday = 1
GROUP BY StationName, ItemAtStation
ORDER BY StationName, ItemAtStation

SELECT StationName, ItemAtStation, AVG(TicketTime) AvgTicketTime, AVG(CookTime) AvgCookTime, AVG(OrderTime) AvgOrderTime, COUNT(ProductKey) Count
FROM #STATIONCOUNT1
WHERE Holiday = 0
GROUP BY StationName, ItemAtStation
ORDER BY StationName, ItemAtStation

SELECT StationName, ItemAtStation, AVG(TicketTime) AvgTicketTime, AVG(CookTime) AvgCookTime, AVG(OrderTime) AvgOrderTime, COUNT(ProductKey) Count
FROM #STATIONCOUNT1
GROUP BY StationName, ItemAtStation
ORDER BY StationName, ItemAtStation

select top 2000000 * from #STATIONCOUNT1 ORDER BY  RAND(convert(varbinary, newid()


