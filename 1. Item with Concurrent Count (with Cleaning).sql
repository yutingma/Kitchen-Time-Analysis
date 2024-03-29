
DECLARE @STARTDATE AS DATETIME
SET @STARTDATE = '01/03/2018'

DECLARE @STORE AS INTEGER
SET @STORE = 160

DECLARE @MINTIME AS INTEGER
SET @MINTIME = 90 

DECLARE @MINRATIO AS FLOAT
SET @MINRATIO = 0.3

DECLARE @MAXRATIO AS FLOAT
SET @MAXRATIO = 5

IF OBJECT_ID('tempdb..#BASE') IS NOT NULL DROP TABLE #BASE
IF OBJECT_ID('tempdb..#BASE1') IS NOT NULL DROP TABLE #BASE1
IF OBJECT_ID('tempdb..#BASE2') IS NOT NULL DROP TABLE #BASE2
IF OBJECT_ID('tempdb..##BASE3') IS NOT NULL DROP TABLE ##BASE3
IF OBJECT_ID('tempdb..##BASE4') IS NOT NULL DROP TABLE ##BASE4
IF OBJECT_ID('tempdb..#BCOUNT') IS NOT NULL DROP TABLE #BCOUNT
IF OBJECT_ID('tempdb..#ORDERS') IS NOT NULL DROP TABLE #ORDERS
IF OBJECT_ID('tempdb..#ORDERS2') IS NOT NULL DROP TABLE #ORDERS2
IF OBJECT_ID('tempdb..#PRODCOUNT') IS NOT NULL DROP TABLE #PRODCOUNT
IF OBJECT_ID('tempdb..#SERVICECAT') IS NOT NULL DROP TABLE #SERVICECAT


SELECT 0 AS TypeofServiceNum, 'OnSite' as TypeofServiceCat
INTO #SERVICECAT
UNION SELECT 1 AS TypeofServiceNum, 'OffSite' as TypeofServiceCat
UNION SELECT 2 AS TypeofServiceNum, 'Banquet' as TypeofServiceCat

---Remove Duplicates
SELECT DISTINCT
o.StoreKey, o.BusinessDate, o.TimeKey,  o.CheckNum, o.ProductKey,o.CourseName, 
o.SentTime, o.NormalDateTime,o.CookingDateTime,o.BumpedDateTime, o.EmployeeKey, o.OrderStartDateTime, o.StationKey,o.DateKey
INTO #BASE1
from edw..factKitchenOrderLineItem o 
join edw..DimCalendar c on o.DateKey = c.DateKey
WHERE c.BusinessDate >= @STARTDATE  and o.storekey = @STORE 



--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
---Select Needed Varibles, Remove Exlusions 
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

---Select VariablesL: #BASE
SELECT o.StoreKey, 
--Day & Time
o.BusinessDate, o.DateKey, DATENAME(weekday,o.BusinessDate) DayOfWeek, o.TimeKey, FLOOR((o.TimeKey-1) / 4) FullHour, (FLOOR((o.TimeKey-1)/2)/2.0) HalfHour, (o.TimeKey-1)/4.0 QuarterHour,
CASE WHEN NatHolidayDesc LIKE '[0-9][0-9]/[0-9][0-9]/[0-9]%' THEN 0 ELSE 1 END AS Holiday, 
---Order
o.CheckNum, s.GuestCount, s.TableOpenMinutes, s.OpenHour, s.OpenMinute, s.CloseHour, s.CloseMinute, ch.ChannelKey, ch.TypeofServiceNum,
---Item
o.ProductKey,o.CourseName, p.IXIName,p.MajorCodeName,p.MinorCodeName, o.StationKey,st.StationName, o.SentTime, 
---Round OrderStartDateTime to minute + Other DateTime
DATEADD(minute, DATEDIFF(minute, 0, o.OrderStartDateTime), 0) 'OrderStartDateTime',o.NormalDateTime,o.CookingDateTime,o.BumpedDateTime, c.NatHolidayDesc, o.EmployeeKey,
---Calculate TicketTime
DATEDIFF(SECOND,o.NormalDateTime,o.BumpedDateTime) 'TicketTime',
---Rank within order, item, station: # of same item orders in an check
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
JOIN edw..dimProduct p
ON o.ProductKey = p.ProductKey
WHERE 
---Exclude Employee Meal
em.Employeekey IS NULL AND 
---Include Only ENTREE
o.CourseName = 'ENTREES' AND st.StationName <> 'KMEXPO' AND 
---Remove Non-Kitchen Items
p.MajorCodeName not in ('BEVERAGES','Beverages','BEER','Beer','Desserts','Desserts','DESSERTS2','G/C ETC','G/C etc','Groceries','Liquor','LIQUOR','Not in Table','Whole Cakes','WHOLE CAKES','Wine' ,'WINE','SLICES','Slices','SIDES') 
and p.MinorCodeName not in ('Sides','Soups','SOUPS','SIDES','BREAKFAST SIDES')




---Estimate number of the same item ordered within a check (max # cooked at the same station) 
SELECT OrderStartDateTime, CheckNum, BusinessDate, ProductKey, StationKey,  MAX(RNK) 'STATION_COUNT'
INTO #BCOUNT
FROM #BASE BASE
GROUP BY StoreKey, CheckNum, BusinessDate, ProductKey, StationKey, OrderStartDateTime

---Multi-Station Removal
---Defining Invalid TicketTime: using parameter @MinTime, @MinRatio, @MaxRatio
SELECT
BASE.*, 
CASE WHEN BASE.TicketTime <= @MINTIME THEN NULL
		WHEN BASE.TicketTime/BASE.SentTime < @MINRATIO THEN NULL 
		WHEN BASE.TicketTime/BASE.SentTime > @MAXRATIO THEN NULL
		ELSE BASE.TicketTime
		END AS TicketTime_invalid, 
CASE WHEN BASE.DayOfWeek IN ('Monday','Tuesday', 'Wednesday', 'Thursday') OR (BASE.DayOfWeek = 'Sunday' AND BASE.FullHour >= 20) THEN 1
		ELSE 0 
		END AS Weekday
INTO #BASE2
FROM #BASE BASE
JOIN #BCOUNT C ON BASE.OrderStartDateTime = C.OrderStartDateTime AND BASE.CheckNum = C.CheckNum AND BASE.BusinessDate = C.BusinessDate AND BASE.ProductKey = C.ProductKey AND BASE.StationKey = C.StationKey
---Keep the Nth slowest item-station in a check: N is the # same items ordered in a check
WHERE BASE.PROD_RNK <= C.STATION_COUNT 






-----------------------------------------------------------------------------------------------------------------------------------------------------
---Filling Invalid TicketTime 
-----------------------------------------------------------------------------------------------------------------------------------------------------

SELECT *
INTO ##BASE4
FROM #BASE2


---Fill in Holiday: 
DECLARE @sqlCommand varchar(1000)
DECLARE @GROUPBY varchar(75)
DECLARE @HOLIDAY varchar(75)

---Given the groupby, calculate median Ticket Time within the group, and if the group has more than 25 valid records and more than 60% of all records are valid, 
---use the midian Ticket Time of the group to fill the invalid Ticket Times in the group. 
SET @sqlCommand = '
SELECT ##BASE4.*, COUNT(TicketTime_invalid) OVER (PARTITION BY '+@GROUPBY+') Count_valid, 
	COUNT(ProductKey) OVER (PARTITION BY '+@GROUPBY+') Count_total,
	PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY TicketTime_invalid) OVER (PARTITION BY '+@GROUPBY+') Median
INTO ##BASE3
FROM ##BASE4

UPDATE ##BASE3
SET ##BASE3.TicketTime_invalid = ##BASE3.median
WHERE ##BASE3.TicketTime_invalid IS NULL AND Holiday = '+@HOLIDAY+' AND 
	Count_valid >= 25 AND CAST(CAST(Count_valid as float) / CAST(Count_total as float) as float) >= 0.6

ALTER TABLE ##BASE3 DROP COLUMN Count_valid, Count_total, Median

DROP TABLE ##BASE4

SELECT * 
INTO ##BASE4
FROM ##BASE3

DROP TABLE ##BASE3'

---Fill in Holiday
SET @GROUPBY = 'StoreKey, Holiday, ProductKey, HalfHour'
SET @HOLIDAY = 1
EXEC (@sqlCommand)

SET @GROUPBY = 'StoreKey, Holiday, ProductKey, FullHour'
SET @HOLIDAY = 1
EXEC (@sqlCommand)

SET @GROUPBY = 'StoreKey, Holiday, ProductKey'
SET @HOLIDAY = 1
EXEC (@sqlCommand)

---Fill in NonHoliday
SET @GROUPBY = 'StoreKey, Holiday, ProductKey, DayOfWeek, HalfHour'
SET @HOLIDAY = 0
EXEC (@sqlCommand)

SET @GROUPBY = 'StoreKey, Holiday, ProductKey, DayOfWeek, FullHour'
SET @HOLIDAY = 0
EXEC (@sqlCommand)

SET @GROUPBY = 'StoreKey, Holiday, ProductKey, Weekday, HalfHour'
SET @HOLIDAY = 0
EXEC (@sqlCommand)

SET @GROUPBY = 'StoreKey, Holiday, ProductKey, Weekday, FullHour'
SET @HOLIDAY = 0
EXEC (@sqlCommand)

SET @GROUPBY = 'StoreKey, Holiday, ProductKey, Weekday, FullHour'
SET @HOLIDAY = 0
EXEC (@sqlCommand)



DECLARE @sqlCommand1 varchar(1000)
SET @sqlCommand1 = '
SELECT ##BASE4.*, COUNT(TicketTime_invalid) OVER (PARTITION BY '+@GROUPBY+') Count_valid, 
	COUNT(ProductKey) OVER (PARTITION BY '+@GROUPBY+') Count_total,
	PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY TicketTime_invalid) OVER (PARTITION BY '+@GROUPBY+') Median
INTO ##BASE3
FROM ##BASE4

UPDATE ##BASE3
SET ##BASE3.TicketTime_invalid = ##BASE3.median
WHERE ##BASE3.TicketTime_invalid IS NULL AND 
	Count_valid >= 25 AND CAST(CAST(Count_valid as float) / CAST(Count_total as float) as float) >= 0.6

ALTER TABLE ##BASE3 DROP COLUMN Count_valid, Count_total, Median

DROP TABLE ##BASE4

SELECT * 
INTO ##BASE4
FROM ##BASE3

DROP TABLE ##BASE3'

---Fill in All Days
SET @GROUPBY = 'StoreKey, ProductKey, DayOfWeek, HalfHour'
SET @HOLIDAY = 0
EXEC (@sqlCommand1)

SET @GROUPBY = 'StoreKey, ProductKey, DayOfWeek, FullHour'
SET @HOLIDAY = 0
EXEC (@sqlCommand1)

SET @GROUPBY = 'StoreKey, ProductKey, Weekday, FullHour'
SET @HOLIDAY = 0
EXEC (@sqlCommand1)

SET @GROUPBY = 'StoreKey, ProductKey, Weekday, HalfHour'
SET @HOLIDAY = 0
EXEC (@sqlCommand1)

---Fill in with Sent Time
UPDATE ##BASE4
SET ##BASE4.TicketTime_invalid = ##BASE4.SentTime
WHERE ##BASE4.TicketTime_invalid IS NULL

---Update BASE2	
UPDATE ##BASE4
SET BumpedDateTime = DATEADD(second, TicketTime_invalid, NormalDateTime)


TRUNCATE TABLE #BASE2
INSERT INTO #BASE2
SELECT StoreKey, BusinessDate, DateKey, DayOfWeek, TimeKey, FullHour, HalfHour, QuarterHour, Holiday, CheckNum, GuestCount, TableOpenMinutes,OpenHour, 
OpenMinute, CloseHour, CloseMinute, ChannelKey, TypeofServiceNum, ProductKey, CourseName, IXIName,MajorCodeName, MinorCodeName, StationKey, StationName,
SentTime, OrderStartDateTime, NormalDateTime, CookingDateTime, BumpedDateTime, NatHolidayDesc, EmployeeKey, TicketTime, RNK,PROD_RNK, TicketTime_invalid,Weekday
FROM ##BASE4


--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
---Fill in Table Open Time
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------



----------------------------------------------------------------------------------------------
/*
SELECT ##BASE4.*, COUNT(TicketTime_invalid) OVER (PARTITION BY StoreKey, Holiday, ProductKey, HalfHour) Count_valid, 
	COUNT(ProductKey) OVER (PARTITION BY StoreKey, Holiday, ProductKey, HalfHour) Count_total,
	PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY TicketTime_invalid) OVER (PARTITION BY StoreKey, Holiday, ProductKey, HalfHour) Median
INTO ##BASE3
FROM ##BASE4

UPDATE ##BASE3
SET ##BASE3.TicketTime_invalid = ##BASE3.median
WHERE ##BASE3.TicketTime_invalid IS NULL AND Holiday = 1 AND 
	Count_valid >= 25 AND CAST(CAST(Count_valid as float) / CAST(Count_total as float) as float) >= 0.6

ALTER TABLE ##BASE3 DROP COLUMN Count_valid, Count_total, Median

DROP TABLE ##BASE4

SELECT * 
INTO ##BASE4
FROM ##BASE3

DROP TABLE ##BASE3
*/

-------------------------------------------------------------

/*
SELECT ##BASE4.*, COUNT(TicketTime_invalid) OVER (PARTITION BY StoreKey, Holiday, ProductKey, FullHour) Count_valid, 
	COUNT(ProductKey) OVER (PARTITION BY StoreKey, Holiday, ProductKey, FullHour) Count_total,
	PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY TicketTime_invalid) OVER (PARTITION BY StoreKey, Holiday, ProductKey, FullHour) Median
INTO ##BASE3
FROM ##BASE4

UPDATE #BASE3
SET #BASE3.TicketTime_invalid = #base3.median
WHERE #BASE3.TicketTime_invalid IS NULL AND Holiday = 1 AND 
	Count_valid >= 25 AND CAST(CAST(Count_valid as float) / CAST(Count_total as float) as float) >= 0.6

ALTER TABLE #BASE3 DROP Count_valid, Count_total, Median

IF OBJECT_ID('tempdb..#BASE4') IS NOT NULL DROP TABLE #BASE4

SELECT * 
INTO #BASE4
FROM #BASE3

IF OBJECT_ID('tempdb..#BASE3') IS NOT NULL DROP TABLE #BASE3


/*
UPDATE #BASE2
SET #BASE2.TicketTime_invalid = T.Median
FROM (SELECT COUNT(TicketTime_invalid) OVER (PARTITION BY StoreKey, Holiday, ProductKey) Count_valid, 
	COUNT(ProductKey) OVER (PARTITION BY StoreKey, Holiday, ProductKey) Count_total,
	PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY TicketTime_invalid) OVER (PARTITION BY StoreKey, Holiday, ProductKey) Median
	FROM #BASE2) AS T
WHERE #BASE2.TicketTime_invalid IS NULL AND Holiday = 1 AND 
	T.Count_valid >= 25 AND CAST(CAST(T.Count_valid as float) / CAST(T.Count_total as float) as float) >= 0.6




---Non-Holiday
UPDATE #BASE2
SET #BASE2.TicketTime_invalid = T.Median
FROM (SELECT COUNT(TicketTime_invalid) OVER (PARTITION BY StoreKey, Holiday, ProductKey, DayOfWeek, HalfHour) Count_valid, 
	COUNT(ProductKey) OVER (PARTITION BY StoreKey, Holiday, ProductKey, DayOfWeek, HalfHour) Count_total,
	PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY TicketTime_invalid) OVER (PARTITION BY StoreKey, Holiday, ProductKey, DayOfWeek, HalfHour) Median
	FROM #BASE2) AS T
WHERE #BASE2.TicketTime_invalid IS NULL AND Holiday = 0 AND 
	T.Count_valid >= 25 AND CAST(CAST(T.Count_valid as float) / CAST(T.Count_total as float) as float) >= 0.6

UPDATE #BASE2
SET #BASE2.TicketTime_invalid = T.Median
FROM (SELECT COUNT(TicketTime_invalid) OVER (PARTITION BY StoreKey, Holiday, ProductKey, DayOfWeek, FullHour) Count_valid, 
	COUNT(ProductKey) OVER (PARTITION BY StoreKey, Holiday, ProductKey, DayOfWeek, FullHour) Count_total,
	PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY TicketTime_invalid) OVER (PARTITION BY StoreKey, Holiday, ProductKey, DayOfWeek, FullHour) Median
	FROM #BASE2) AS T
WHERE #BASE2.TicketTime_invalid IS NULL AND Holiday = 0 AND 
	T.Count_valid >= 25 AND CAST(CAST(T.Count_valid as float) / CAST(T.Count_total as float) as float) >= 0.6

UPDATE #BASE2
SET #BASE2.TicketTime_invalid = T.Median
FROM (SELECT COUNT(TicketTime_invalid) OVER (PARTITION BY StoreKey, Holiday, ProductKey, Weekday, HalfHour) Count_valid, 
	COUNT(ProductKey) OVER (PARTITION BY StoreKey, Holiday, ProductKey, Weekday, HalfHour) Count_total,
	PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY TicketTime_invalid) OVER (PARTITION BY StoreKey, Holiday, ProductKey, Weekday, HalfHour) Median
	FROM #BASE2) AS T
WHERE #BASE2.TicketTime_invalid IS NULL AND Holiday = 0 AND 
	T.Count_valid >= 25 AND CAST(CAST(T.Count_valid as float) / CAST(T.Count_total as float) as float) >= 0.6

UPDATE #BASE2
SET #BASE2.TicketTime_invalid = T.Median
FROM (SELECT COUNT(TicketTime_invalid) OVER (PARTITION BY StoreKey, Holiday, ProductKey, Weekday, FullHour) Count_valid, 
	COUNT(ProductKey) OVER (PARTITION BY StoreKey, Holiday, ProductKey, Weekday, FullHour) Count_total,
	PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY TicketTime_invalid) OVER (PARTITION BY StoreKey, Holiday, ProductKey, Weekday, FullHour) Median
	FROM #BASE2) AS T
WHERE #BASE2.TicketTime_invalid IS NULL AND Holiday = 0 AND 
	T.Count_valid >= 25 AND CAST(CAST(T.Count_valid as float) / CAST(T.Count_total as float) as float) >= 0.6

---Fill in Holiday&NonHoliday
UPDATE #BASE2
SET #BASE2.TicketTime_invalid = T.Median
FROM (SELECT COUNT(TicketTime_invalid) OVER (PARTITION BY StoreKey, ProductKey, DayOfWeek, HalfHour) Count_valid, 
	COUNT(ProductKey) OVER (PARTITION BY StoreKey, ProductKey, DayOfWeek, HalfHour) Count_total,
	PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY TicketTime_invalid) OVER (PARTITION BY StoreKey, ProductKey, DayOfWeek, HalfHour) Median
	FROM #BASE2) AS T
WHERE #BASE2.TicketTime_invalid IS NULL AND 
	T.Count_valid >= 25 AND CAST(CAST(T.Count_valid as float) / CAST(T.Count_total as float) as float) >= 0.6 

UPDATE #BASE2
SET #BASE2.TicketTime_invalid = T.Median
FROM (SELECT COUNT(TicketTime_invalid) OVER (PARTITION BY StoreKey, ProductKey, DayOfWeek, FullHour) Count_valid, 
	COUNT(ProductKey) OVER (PARTITION BY StoreKey, ProductKey, DayOfWeek, FullHour) Count_total,
	PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY TicketTime_invalid) OVER (PARTITION BY StoreKey, ProductKey, DayOfWeek,FullHour) Median
	FROM #BASE2) AS T
WHERE #BASE2.TicketTime_invalid IS NULL AND 
	T.Count_valid >= 25 AND CAST(CAST(T.Count_valid as float) / CAST(T.Count_total as float) as float) >= 0.6 



UPDATE #BASE2
SET #BASE2.TicketTime_invalid = T.Median
FROM (SELECT COUNT(TicketTime_invalid) OVER (PARTITION BY StoreKey, ProductKey, Weekday, HalfHour) Count_valid, 
	COUNT(ProductKey) OVER (PARTITION BY StoreKey, ProductKey, Weekday, HalfHour) Count_total,
	PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY TicketTime_invalid) OVER (PARTITION BY StoreKey, ProductKey, Weekday, HalfHour) Median
	FROM #BASE2) AS T
WHERE #BASE2.TicketTime_invalid IS NULL AND 
	T.Count_valid >= 25 AND CAST(CAST(T.Count_valid as float) / CAST(T.Count_total as float) as float) >= 0.6 

UPDATE #BASE2
SET #BASE2.TicketTime_invalid = T.Median
FROM (SELECT COUNT(TicketTime_invalid) OVER (PARTITION BY StoreKey, ProductKey, Weekday, FullHour) Count_valid, 
	COUNT(ProductKey) OVER (PARTITION BY StoreKey, ProductKey, Weekday, FullHour) Count_total,
	PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY TicketTime_invalid) OVER (PARTITION BY StoreKey, ProductKey, FullHour) Median
	FROM #BASE2) AS T
WHERE #BASE2.TicketTime_invalid IS NULL AND 
	T.Count_valid >= 25 AND CAST(CAST(T.Count_valid as float) / CAST(T.Count_total as float) as float) >= 0.6 

---Fill the Rest with SentTime
UPDATE #BASE2
SET #BASE2.TicketTime_invalid = #BASE2.SentTime
WHERE #BASE2.TicketTime_invalid IS NULL
*/

---Test All
SELECT * 
FROM #BASE2
WHERE #BASE2.TicketTime_invalid IS NULL

 ---Test Case
 /*
SELECT TicketTime_invalid, 
		COUNT(TicketTime_invalid) OVER (PARTITION BY StoreKey, ProductKey, DayOfWeek) Count_valid, 
		COUNT(ProductKey) OVER (PARTITION BY StoreKey, ProductKey, DayOfWeek) Count_total, 
		PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY TicketTime_invalid) OVER (PARTITION BY StoreKey, ProductKey, DayOfWeek) Median
FROM #BASE2
WHERE ProductKey = 3458
*/

----Update BumpedDateTime


UPDATE #BASE2
SET BumpedDateTime = DATEADD(second, TicketTime_invalid, NormalDateTime)

*/




--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
---Aggregate to Order Level
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

---Rank of Product Within Order
SELECT #BASE2.*, 
ROW_NUMBER() OVER (PARTITION BY StoreKey, CheckNum, BusinessDate, OrderStartDateTime  ORDER BY BumpedDateTime DESC) 'ORDER_RNK'
INTO #BASE3
FROM #BASE2



---Aggregate to Order: Keep the longest item in an order
SELECT BASE3.*
INTO #ORDERS
FROM #BASE3 BASE3
WHERE BASE3.ORDER_RNK =1 


--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
---Concurrent Count
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------


---Order Count: for every OrderStartDateTime, how many other Orders are in process (after OrderStartDateTime, before BumpedDateTime) 
SELECT
ORDERS.BusinessDate, ORDERS.CheckNum, ORDERS.OrderStartDateTime, ORDERC.TypeofServiceNum,
COUNT(ORDERC.CheckNum) 'ORDERCOUNT'
 /*ISNULL((SELECT
	COUNT(*)
	FROM #ORDERS O
	WHERE O.BusinessDate = ORDERS.BusinessDate 
	AND O.CheckNum <> ORDERS.CheckNum 
	AND O.BumpedDateTime >= ORDERS.OrderStartDateTime 
	AND O.OrderStartDateTime <= ORDERS.OrderStartDateTime
	AND O.TypeofServiceNum = ORDERS.TypeofServiceNum),0) 'ORDERCOUNT'*/
INTO #ORDERS2
FROM #ORDERS ORDERS
JOIN #ORDERS ORDERC ON ORDERC.BusinessDate = ORDERS.BusinessDate 
	AND ORDERC.CheckNum <> ORDERS.CheckNum 
	AND ORDERC.BumpedDateTime > ORDERS.OrderStartDateTime 
	AND ORDERC.OrderStartDateTime <= ORDERS.OrderStartDateTime
GROUP BY ORDERS.StoreKey, ORDERS.BusinessDate, ORDERS.CheckNum, ORDERS.OrderStartDateTime, ORDERC.TypeofServiceNum

---Item Count: for every OrderStartDateTime, how many other Items are in process (after OrderStartDateTime, before BumpedDateTime) 
SELECT
ORDERS.OrderStartDateTime, ORDERS.BusinessDate, ORDERS.CheckNum, PRODCOUNT.TypeofServiceNum,
COUNT(PRODCOUNT.CheckNum) 'PRODCOUNT'
/* ISNULL((SELECT
	COUNT(*)
	FROM #BASE2 B
	WHERE B.BusinessDate = ORDERS.BusinessDate 
	AND B.CheckNum <> ORDERS.CheckNum 
	AND B.BumpedDateTime >= ORDERS.OrderStartDateTime 
	AND B.OrderStartDateTime <= ORDERS.OrderStartDateTime
	AND B.TypeofServiceNum = ORDERS.TypeofServiceNum),0) 'PRODCOUNT'*/
INTO #PRODCOUNT
FROM #ORDERS ORDERS
JOIN #BASE3 PRODCOUNT ON 
	PRODCOUNT.BusinessDate = ORDERS.BusinessDate 
	AND PRODCOUNT.CheckNum <> ORDERS.CheckNum 
	AND PRODCOUNT.BumpedDateTime > ORDERS.OrderStartDateTime 
	AND PRODCOUNT.OrderStartDateTime <= ORDERS.OrderStartDateTime
GROUP BY ORDERS.StoreKey, ORDERS.OrderStartDateTime, ORDERS.BusinessDate, ORDERS.CheckNum, PRODCOUNT.TypeofServiceNum


---Join Concurrent Count
SELECT
BASE3.*,
SERVICECAT.TypeofServiceCat,
ch.ChannelName,
t.StartTime,
ISNULL(OFFSITEC.ORDERCOUNT,0)  'OffSiteOrder',
ISNULL(ONSITEC.ORDERCOUNT,0)  'OnSiteOrder',
ISNULL(OFFSITEC.ORDERCOUNT,0) + ISNULL(ONSITEC.ORDERCOUNT,0) 'TotalOrder',
ISNULL(ONSITEPRODC.PRODCOUNT,0) 'OnSiteItem',
ISNULL(OFFSITEPRODC.PRODCOUNT,0) 'OffSiteItem',
ISNULL(ONSITEPRODC.PRODCOUNT,0) + ISNULL(OFFSITEPRODC.PRODCOUNT,0) 'TotalItem'
FROM 
#BASE3 BASE3
LEFT JOIN #ORDERS2 OFFSITEC ON BASE3.CheckNum = OFFSITEC.CheckNum AND BASE3.OrderStartDateTime = OFFSITEC.OrderStartDateTime AND OFFSITEC.TypeofServiceNum = 1
LEFT JOIN #ORDERS2 ONSITEC ON BASE3.CheckNum = ONSITEC.CheckNum AND BASE3.OrderStartDateTime = ONSITEC.OrderStartDateTime AND ONSITEC.TypeofServiceNum = 0
LEFT JOIN #PRODCOUNT OFFSITEPRODC ON BASE3.CheckNum = OFFSITEPRODC.CheckNum AND BASE3.OrderStartDateTime = OFFSITEPRODC.OrderStartDateTime  AND OFFSITEPRODC.TypeofServiceNum = 1
LEFT JOIN #PRODCOUNT ONSITEPRODC ON BASE3.CheckNum = ONSITEPRODC.CheckNum  AND BASE3.OrderStartDateTime = ONSITEPRODC.OrderStartDateTime  AND ONSITEPRODC.TypeofServiceNum = 0
JOIN EDW..DimCalendar c ON c.DateKey = BASE3.DateKey
JOIN edw..dimChannel ch on BASE3.ChannelKey = ch.ChannelKey
JOIN #SERVICECAT SERVICECAT on BASE3.TypeofServiceNum = SERVICECAT.TypeofServiceNum
JOIN edw..DimTime t ON BASE3.TimeKey = t.TimeID



