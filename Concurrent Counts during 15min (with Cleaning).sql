DECLARE @STARTDATE AS DATETIME  SET @STARTDATE = '04/01/2019'
DECLARE @ENDDATE AS DATETIME    SET @ENDDATE = '06/30/2019'
DECLARE @MINTIME AS INTEGER     SET @MINTIME = 90 
DECLARE @MINRATIO AS FLOAT      SET @MINRATIO = 0.3
DECLARE @MAXRATIO AS FLOAT      SET @MAXRATIO = 5
DECLARE @STORE AS INTEGER       SET @STORE = 1      ---Begin Store (outputs include this store) 
DECLARE @STOREMAX AS INTEGER    SET @STOREMAX = 100  ---End Store (output includes this store)
DECLARE @sqlCommand varchar(1000)
DECLARE @sqlCommand1 varchar(1000)
DECLARE @sqlCommand2 varchar(1000)
DECLARE @sqlCommand3 varchar(1000)
DECLARE @GROUPBY varchar(75)
DECLARE @HOLIDAY varchar(75)

IF OBJECT_ID('tempdb..#DAYTIME') IS NOT NULL DROP TABLE #DAYTIME
IF OBJECT_ID('tempdb..#DAYTIME1') IS NOT NULL DROP TABLE #DAYTIME1
IF OBJECT_ID('tempdb..#BASE') IS NOT NULL DROP TABLE #BASE
IF OBJECT_ID('tempdb..#BASE1') IS NOT NULL DROP TABLE #BASE1
IF OBJECT_ID('tempdb..#BASE2') IS NOT NULL DROP TABLE #BASE2
IF OBJECT_ID('tempdb..#BASE3') IS NOT NULL DROP TABLE #BASE3
IF OBJECT_ID('tempdb..#BASE4') IS NOT NULL DROP TABLE #BASE4
IF OBJECT_ID('tempdb..##BASE3') IS NOT NULL DROP TABLE ##BASE3
IF OBJECT_ID('tempdb..##BASE4') IS NOT NULL DROP TABLE ##BASE4
IF OBJECT_ID('tempdb..#GUEST') IS NOT NULL DROP TABLE #GUEST
IF OBJECT_ID('tempdb..##TABLE') IS NOT NULL DROP TABLE ##TABLE
IF OBJECT_ID('tempdb..##TABLE1') IS NOT NULL DROP TABLE ##TABLE1
IF OBJECT_ID('tempdb..#BCOUNT') IS NOT NULL DROP TABLE #BCOUNT
IF OBJECT_ID('tempdb..#ORDERS') IS NOT NULL DROP TABLE #ORDERS
IF OBJECT_ID('tempdb..#ORDERS2') IS NOT NULL DROP TABLE #ORDERS2
IF OBJECT_ID('tempdb..#PRODCOUNT') IS NOT NULL DROP TABLE #PRODCOUNT
IF OBJECT_ID('tempdb..#PRODCOUNT2') IS NOT NULL DROP TABLE #PRODCOUNT2
--IF OBJECT_ID('tempdb..#SERVICECAT') IS NOT NULL DROP TABLE #SERVICECAT
IF OBJECT_ID('tempdb..#GUESTCOUNT') IS NOT NULL DROP TABLE #GUESTCOUNT
IF OBJECT_ID('tempdb..#T1') IS NOT NULL DROP TABLE #T1
IF OBJECT_ID('tempdb..#T2') IS NOT NULL DROP TABLE #T2
--IF OBJECT_ID('tempdb..#T3') IS NOT NULL DROP TABLE #T3

/*
SELECT 0 AS TypeofServiceNum, 'OnSite' as TypeofServiceCat
INTO #SERVICECAT
UNION SELECT 1 AS TypeofServiceNum, 'OffSite' as TypeofServiceCat
UNION SELECT 2 AS TypeofServiceNum, 'Banquet' as TypeofServiceCat*/

---TimeFrame
SELECT DISTINCT o.StoreKey, o.BusinessDate, o.TimeKey, s.Zip, s.State, s.GeoRegion, s.RegionName
INTO #DAYTIME1
FROM edw..factKitchenOrderLineItem o
JOIN edw..DimCalendar c on o.DateKey = c.DateKey
JOIN edw..DimStore s on s.StoreKey = o.StoreKey
JOIN edw..DimTables tb on tb.StoreKey = o.StoreKey
WHERE s.OpenFlag=1 AND c.BusinessDate >= @STARTDATE AND c.BusinessDate <= @ENDDATE AND o.StoreKey = @STORE

SELECT DISTINCT d.StoreKey, BusinessDate, DATENAME(weekday,BusinessDate) DayOfWeek,
CAST((TimeKey-1) AS FLOAT) /4.0 QuarterHour, 
---FLOOR((TimeKey-1) / 4) FullHour,
---CAST((CAST(FLOOR((TimeKey-1) / 4) AS VARCHAR) + ':' + '00') AS TIME) AS 'STIME',
---CAST((CAST(FLOOR((TimeKey-1) / 4) AS VARCHAR) + ':' + '59') AS TIME) AS 'ETIME',
CAST(LEFT(t.StartTime,2) + ':' + RIGHT(t.StartTime,2) AS TIME) as 'STIME',
DATEADD(SECOND, 59.99, CAST(LEFT(t.EndTime,2) + ':' + RIGHT(t.EndTime,2) AS TIME)) as 'ETIME',
d.Zip, d.State, d.GeoRegion, d.RegionName
INTO #DAYTIME
FROM #DAYTIME1 d
JOIN edw..DimTime t on t.TimeID = d.TimeKey
JOIN edw..DimTables tb on tb.StoreKey = d.StoreKey
TRUNCATE TABLE #DAYTIME1

---BASE1
SELECT DISTINCT
o.StoreKey, o.BusinessDate, o.TimeKey, o.CheckNum, o.ProductKey,
o.SentTime, cast(o.NormalDateTime as time) NormalDateTime,cast(o.CookingDateTime as time) CookingDateTime,cast(o.BumpedDateTime as time)BumpedDateTime, o.EmployeeKey, cast(o.OrderStartDateTime as time) OrderStartDateTime, o.StationKey,o.DateKey, c.NatHolidayDesc
INTO #BASE1
from edw..factKitchenOrderLineItem o 
join edw..DimCalendar c on o.DateKey = c.DateKey
WHERE c.BusinessDate >= @STARTDATE  AND c.BusinessDate <= @ENDDATE AND o.StoreKey = @Store AND o.CourseName = 'ENTREES'

---Select Variables (including Mulisation) #BASE
SELECT o.StoreKey, 
--Day & Time
o.BusinessDate, DATENAME(weekday,o.BusinessDate) DayOfWeek, o.TimeKey, FLOOR((o.TimeKey-1) / 4) FullHour, (FLOOR((o.TimeKey-1)/2)/2.0) HalfHour, (o.TimeKey-1)/4.0 QuarterHour,
CASE WHEN o.NatHolidayDesc LIKE '[0-9][0-9]/[0-9][0-9]/[0-9]%' THEN 0 ELSE 1 END AS Holiday, 
---Order
o.CheckNum, s.GuestCount, s.TableOpenMinutes, s.OpenHour, s.OpenMinute, ch.TypeofServiceNum,
---Item
o.ProductKey, st.StationName, o.SentTime, 
---Round OrderStartDateTime to minute + Other DateTime
DATEADD(minute, DATEDIFF(minute, 0, o.OrderStartDateTime), 0) 'OrderStartDateTime',o.NormalDateTime,o.CookingDateTime,o.BumpedDateTime, o.EmployeeKey,
---Calculate TicketTime
DATEDIFF(SECOND,o.NormalDateTime,o.BumpedDateTime) 'TicketTime',
---Rank within order, item, station: # of same item orders in an check
ROW_NUMBER() OVER (PARTITION BY o.CheckNum, o.BusinessDate, o.ProductKey, DATEADD(minute, DATEDIFF(minute, 0, o.OrderStartDateTime), 0)  ORDER BY DATEDIFF(SECOND,o.NormalDateTime,o.BumpedDateTime) DESC) 'RNK',
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
JOIN edw..dimProduct p
ON o.ProductKey = p.ProductKey
WHERE em.Employeekey IS NULL AND st.StationName <> 'KMEXPO' 
AND p.MajorCodeName not in ('BEVERAGES','Beverages','BEER','Beer','Desserts','Desserts','DESSERTS2','G/C ETC','G/C etc','Groceries','Liquor','LIQUOR','Not in Table','Whole Cakes','WHOLE CAKES','Wine' ,'WINE','SLICES','Slices','SIDES') 
and p.MinorCodeName not in ('Sides','Soups','SOUPS','SIDES','BREAKFAST SIDES')

---Number of the same Item ordered within a check (max # cooked at the same station) #BCOUNT
SELECT OrderStartDateTime, CheckNum, BusinessDate, ProductKey, StationName,  MAX(RNK) 'STATION_COUNT'
INTO #BCOUNT
FROM #BASE
GROUP BY StoreKey, CheckNum, BusinessDate, ProductKey, StationName, OrderStartDateTime

---Multi-Station Removal
---Defining Invalid TicketTime: using parameter @MinTime, @MinRatio, @MaxRatio
SELECT BASE.*, 
CASE WHEN BASE.TicketTime <= @MINTIME THEN NULL
	WHEN BASE.TicketTime * @MINRATIO < BASE.SentTime THEN NULL 
	WHEN BASE.TicketTime *@MAXRATIO > BASE.SentTime THEN NULL
	ELSE BASE.TicketTime
	END AS TicketTime_invalid, 
CASE WHEN BASE.TableOpenMinutes <= 30 THEN NULL 
	WHEN BASE.TableOpenMinutes >= 240 THEN NULL 
	ELSE BASE.TableOpenMinutes 
	END AS TableOpenMinutes_invalid,
CASE WHEN BASE.DayOfWeek IN ('Monday','Tuesday', 'Wednesday', 'Thursday') OR (BASE.DayOfWeek = 'Sunday' AND BASE.FullHour >= 20) THEN 1
		ELSE 0 
		END AS Weekday
INTO #BASE2
FROM #BASE BASE
JOIN #BCOUNT C ON BASE.OrderStartDateTime = C.OrderStartDateTime AND BASE.CheckNum = C.CheckNum AND BASE.BusinessDate = C.BusinessDate AND BASE.ProductKey = C.ProductKey AND BASE.StationName = C.StationName
---Keep the Nth slowest item-station in a check: N is the # same items ordered in a check
WHERE BASE.PROD_RNK <= C.STATION_COUNT 

TRUNCATE TABLE #BASE
TRUNCATE TABLE #BASE1
TRUNCATE TABLE #BCOUNT

---Table
SELECT StoreKey, BusinessDate, CheckNum, AVG(GuestCount) GuestCount, AVG(TableOpenMinutes_invalid) TableOpenMinutes_invalid, AVG(OpenHour) OpenHour, AVG(OpenMinute) OpenMinute
INTO ##TABLE
FROM #BASE2 
WHERE TypeofServiceNum = 0
GROUP BY StoreKey, BusinessDate, CheckNum

---Fill Table Time
SET @sqlCommand2 = '
SELECT ##TABLE.*, COUNT(TableOpenMinutes_invalid) OVER (PARTITION BY '+@GROUPBY+') Count_valid, 
	COUNT(CheckNum) OVER (PARTITION BY '+@GROUPBY+') Count_total,
	PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY TabelOpenMinutes_invalid) OVER (PARTITION BY '+@GROUPBY+') Median
INTO ##TABLE1
FROM ##TABLE

UPDATE ##TABLE1
SET ##TABLE1.TabelOpenMinutes_invalid = ##TABLE1.median
WHERE ##TABLE1.TabelOpenMinutes_invalid IS NULL AND Holiday = '+@HOLIDAY+' AND 
	Count_valid >= 25 AND CAST(CAST(Count_valid as float) / CAST(Count_total as float) as float) >= 0.6
ALTER TABLE ##TABLE1 DROP COLUMN Count_valid, Count_total, Median
DROP TABLE ##TABLE

SELECT * 
INTO ##TABLE
FROM ##TABLE1
DROP TABLE ##TABLE1'

---Fill in Holiday
SET @HOLIDAY = 1
SET @GROUPBY = 'StoreKey, Holiday, GuestCount, HalfHour' EXEC (@sqlCommand2)
SET @GROUPBY = 'StoreKey, Holiday, GuestCount, FullHour' EXEC (@sqlCommand2)
SET @GROUPBY = 'StoreKey, Holiday, GuestCount'           EXEC (@sqlCommand2)
---Fill in Non-Holiday
SET @HOLIDAY = 0
SET @GROUPBY = 'StoreKey, Holiday, GuestCount, DayOfWeek, HalfHour' EXEC (@sqlCommand2)
SET @GROUPBY = 'StoreKey, Holiday, GuestCount, DayOfWeek, FullHour' EXEC (@sqlCommand2)
SET @GROUPBY = 'StoreKey, Holiday, GuestCount, Weekday, HalfHour'   EXEC (@sqlCommand2)
SET @GROUPBY = 'StoreKey, Holiday, GuestCount, Weekday, FullHour'   EXEC (@sqlCommand2)
---Fll in All Day
SET @sqlCommand3 = '
SELECT ##TABLE.*, COUNT(TableOpenMinutes_invalid) OVER (PARTITION BY '+@GROUPBY+') Count_valid, 
	COUNT(CheckNum) OVER (PARTITION BY '+@GROUPBY+') Count_total,
	PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY TabelOpenMinutes_invalid) OVER (PARTITION BY '+@GROUPBY+') Median
INTO ##TABLE1
FROM ##TABLE

UPDATE ##TABLE1
SET ##TABLE1.TabelOpenMinutes_invalid = ##TABLE1.median
WHERE ##TABLE1.TabelOpenMinutes_invalid IS NULL AND 
	Count_valid >= 25 AND CAST(CAST(Count_valid as float) / CAST(Count_total as float) as float) >= 0.6
ALTER TABLE ##TABLE1 DROP COLUMN Count_valid, Count_total, Median
DROP TABLE ##TABLE

SELECT * 
INTO ##TABLE
FROM ##TABLE1
DROP TABLE ##TABLE1'

SET @GROUPBY = 'StoreKey, GuestCount, DayOfWeek, HalfHour' EXEC (@sqlCommand2)
SET @GROUPBY = 'StoreKey, GuestCount, DayOfWeek, FullHour' EXEC (@sqlCommand2)
SET @GROUPBY = 'StoreKey, GuestCount, Weekday, HalfHour'   EXEC (@sqlCommand2)
SET @GROUPBY = 'StoreKey, GuestCount, Weekday, FullHour'   EXEC (@sqlCommand2)

---Update to #TABLE & Create Time Variable
SELECT StoreKey, BusinessDate, CheckNum,GuestCount, 
CAST(CAST(OpenHour as VARCHAR)+':'+CAST(OpenMinute as varchar) as time) OpenTime,
DATEADD(minute, TableOpenMinutes_invalid, CAST(CAST(OpenHour as VARCHAR)+':'+CAST(OpenMinute as varchar) as time)) CloseTime
INTO #GUEST FROM ##TABLE
TRUNCATE TABLE ##TABLE

---Count of Concurrent Guest during 15 min (OnSite
SELECT DAYTIME.StoreKey,DAYTIME.BusinessDate, DAYTIME.QuarterHour, DAYTIME.STIME,
SUM(TABLECOUNT.GuestCount) 'GUESTCOUNT'
INTO #GUESTCOUNT
FROM #DAYTIME DAYTIME
JOIN #GUEST TABLECOUNT ON 
	TABLECOUNT.StoreKey = DAYTIME.StoreKey AND 
	TABLECOUNT.BusinessDate = DAYTIME.BusinessDate 
	AND TABLECOUNT.OpenTime < DAYTIME.ETIME AND  TABLECOUNT.CloseTime > DAYTIME.STIME 
GROUP BY DAYTIME.StoreKey,DAYTIME.BusinessDate, DAYTIME.QuarterHour, DAYTIME.STIME
TRUNCATE TABLE #GUEST

-----------------------------------------------------------------------------------------------------------------------------------------------------
---Filling Invalid TicketTime 
-----------------------------------------------------------------------------------------------------------------------------------------------------

SELECT *
INTO ##BASE4
FROM #BASE2
TRUNCATE TABLE #BASE2

---Fill in Holiday: 
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
SET @HOLIDAY = 1
SET @GROUPBY = 'StoreKey, Holiday, ProductKey, HalfHour' EXEC (@sqlCommand)
SET @GROUPBY = 'StoreKey, Holiday, ProductKey, FullHour' EXEC (@sqlCommand)
SET @GROUPBY = 'StoreKey, Holiday, ProductKey'           EXEC (@sqlCommand)

---Fill in NonHoliday
SET @HOLIDAY = 0
SET @GROUPBY = 'StoreKey, Holiday, ProductKey, DayOfWeek, HalfHour' EXEC (@sqlCommand)
SET @GROUPBY = 'StoreKey, Holiday, ProductKey, DayOfWeek, FullHour' EXEC (@sqlCommand)
SET @GROUPBY = 'StoreKey, Holiday, ProductKey, Weekday, HalfHour'   EXEC (@sqlCommand)
SET @GROUPBY = 'StoreKey, Holiday, ProductKey, Weekday, FullHour'   EXEC (@sqlCommand)
SET @GROUPBY = 'StoreKey, Holiday, ProductKey, Weekday, FullHour'   EXEC (@sqlCommand)

---Fill in All Day
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
SET @GROUPBY = 'StoreKey, ProductKey, DayOfWeek, HalfHour' EXEC (@sqlCommand1)
SET @GROUPBY = 'StoreKey, ProductKey, DayOfWeek, FullHour' EXEC (@sqlCommand1)
SET @GROUPBY = 'StoreKey, ProductKey, Weekday, FullHour'   EXEC (@sqlCommand1)
SET @GROUPBY = 'StoreKey, ProductKey, Weekday, HalfHour'   EXEC (@sqlCommand1)

---Fill in with Sent Time
UPDATE ##BASE4
SET ##BASE4.TicketTime_invalid = ##BASE4.SentTime
WHERE ##BASE4.TicketTime_invalid IS NULL

---Update BASE4
UPDATE ##BASE4
SET BumpedDateTime = DATEADD(second, TicketTime_invalid, NormalDateTime)

SELECT * 
INTO #BASE4
FROM ##BASE4
TRUNCATE TABLE ##BASE4

---Rank of Product Within Order
SELECT #BASE4.*, ROW_NUMBER() OVER (PARTITION BY StoreKey, CheckNum, BusinessDate, OrderStartDateTime  ORDER BY BumpedDateTime DESC) 'ORDER_RNK'
INTO #BASE3
FROM #BASE4
TRUNCATE TABLE #BASE4

---Aggregate to Order: Keep longest 
SELECT StoreKey, BusinessDate,Holiday, CheckNum, OrderStartDateTime, BumpedDateTime, TypeofServiceNum
INTO #ORDERS
FROM #BASE3
WHERE #BASE3.ORDER_RNK = 1 

---Count of Concurrent Order during 15min (OnSite and OffSite)
SELECT DAYTIME.StoreKey,DAYTIME.BusinessDate, DAYTIME.QuarterHour, DAYTIME.STIME, ORDERC.TypeofServiceNum, ORDERC.Holiday, 
COUNT(ORDERC.CheckNum) 'ORDERCOUNT'
INTO #ORDERS2
FROM #DAYTIME DAYTIME
JOIN #ORDERS ORDERC ON 
	ORDERC.StoreKey = DAYTIME.StoreKey AND 
	ORDERC.BusinessDate = DAYTIME.BusinessDate  
	AND cast(ORDERC.OrderStartDateTime as time) < DAYTIME.ETIME AND  ORDERC.BumpedDateTime > DAYTIME.STIME 
GROUP BY DAYTIME.StoreKey,DAYTIME.BusinessDate, DAYTIME.QuarterHour, DAYTIME.STIME, ORDERC.TypeofServiceNum, ORDERC.Holiday
TRUNCATE TABLE #ORDERS

---Count of Concurrent Item during 15 min (OnSite and OffSite)
SELECT DAYTIME.StoreKey,DAYTIME.BusinessDate, DAYTIME.QuarterHour, DAYTIME.STIME, PRODCOUNT.TypeofServiceNum, PRODCOUNT.Holiday,
COUNT(PRODCOUNT.CheckNum) 'PRODCOUNT'
INTO #PRODCOUNT
FROM #DAYTIME DAYTIME
JOIN #BASE3 PRODCOUNT ON 
	PRODCOUNT.StoreKey = DAYTIME.StoreKey AND 
	PRODCOUNT.BusinessDate = DAYTIME.BusinessDate 
	AND cast(PRODCOUNT.OrderStartDateTime as time) < DAYTIME.ETIME AND  PRODCOUNT.BumpedDateTime > DAYTIME.STIME 
GROUP BY DAYTIME.StoreKey,DAYTIME.BusinessDate, DAYTIME.QuarterHour, DAYTIME.STIME, PRODCOUNT.TypeofServiceNum, PRODCOUNT.Holiday

/*
---Count of Concurrent Item during 15 min (by Station)
SELECT DAYTIME.StoreKey,
DAYTIME.BusinessDate, DAYTIME.STIME, PRODCOUNT.StationName,PRODCOUNT.Holiday, 
COUNT(PRODCOUNT.CheckNum) 'PRODCOUNT'
/* ISNULL((SELECT
	COUNT(*)
	FROM #BASE2 B
	WHERE B.BusinessDate = ORDERS.BusinessDate 
	AND B.CheckNum <> ORDERS.CheckNum 
	AND B.BumpedDateTime >= ORDERS.OrderStartDateTime 
	AND B.OrderStartDateTime <= ORDERS.OrderStartDateTime
	AND B.TypeofServiceNum = ORDERS.TypeofServiceNum),0) 'PRODCOUNT'*/
INTO #PRODCOUNT2
FROM #DAYTIME DAYTIME
JOIN #BASE3 PRODCOUNT ON 
	PRODCOUNT.BusinessDate = DAYTIME.BusinessDate 
	AND cast(PRODCOUNT.OrderStartDateTime as time) < DAYTIME.ETIME AND  cast(PRODCOUNT.BumpedDateTime as time) > DAYTIME.STIME 
GROUP BY DAYTIME.StoreKey,DAYTIME.BusinessDate, DAYTIME.STIME, PRODCOUNT.StationName, PRODCOUNT.Holiday
*/
TRUNCATE TABLE #BASE3

SELECT DAYTIME.StoreKey, DayTime.DayOfWeek, DAYTIME.QuarterHour, DAYTIME.STIME, DAYTIME.Zip, DAYTIME.State, DAYTIME.GeoRegion, DAYTIME.RegionName,
---STATIONPRODC.StationName, 
AVG(ISNULL(OFFSITEC.ORDERCOUNT,0))'OffSiteOrder',
AVG(ISNULL(ONSITEC.ORDERCOUNT,0))  'OnSiteOrder',
AVG(ISNULL(OFFSITEC.ORDERCOUNT,0) + ISNULL(ONSITEC.ORDERCOUNT,0))'TotalOrder',
AVG(ISNULL(ONSITEPRODC.PRODCOUNT,0)) 'OnSiteItem',
AVG(ISNULL(OFFSITEPRODC.PRODCOUNT,0)) 'OffSiteItem',
AVG(ISNULL(ONSITEPRODC.PRODCOUNT,0) + ISNULL(OFFSITEPRODC.PRODCOUNT,0)) 'TotalItem',
AVG(ISNULL(GUESTCOUNT.GUESTCOUNT,0)) 'OnSiteGuest'
---,AVG(ISNULL(STATIONPRODC.PRODCOUNT,0)) 'StationItem'
INTO #T1
FROM #DAYTIME DAYTIME 
LEFT JOIN #ORDERS2 OFFSITEC ON DAYTIME.StoreKey = OFFSITEC.StoreKey AND DAYTIME.BusinessDate = OFFSITEC.BusinessDate AND DAYTIME.QuarterHour = OFFSITEC.QuarterHour AND OFFSITEC.TypeofServiceNum = 1
LEFT JOIN #ORDERS2 ONSITEC ON DAYTIME.StoreKey = ONSITEC.StoreKey AND DAYTIME.BusinessDate = ONSITEC.BusinessDate AND DAYTIME.QuarterHour = ONSITEC.QuarterHour AND OFFSITEC.TypeofServiceNum = 0
LEFT JOIN #PRODCOUNT OFFSITEPRODC ON DAYTIME.StoreKey = OFFSITEC.StoreKey AND DAYTIME.BusinessDate = OFFSITEPRODC.BusinessDate AND DAYTIME.QuarterHour = OFFSITEPRODC.QuarterHour  AND OFFSITEPRODC.TypeofServiceNum = 1
LEFT JOIN #PRODCOUNT ONSITEPRODC ON DAYTIME.StoreKey = ONSITEC.StoreKey AND DAYTIME.BusinessDate = ONSITEPRODC.BusinessDate  AND DAYTIME.QuarterHour = ONSITEPRODC.QuarterHour  AND ONSITEPRODC.TypeofServiceNum = 0
---FULL OUTER JOIN #PRODCOUNT2 STATIONPRODC ON DAYTIME.StoreKey = STATIONPRODC.StoreKey AND DAYTIME.BusinessDate = STATIONPRODC.BusinessDate AND DAYTIME.FullHour = STATIONPRODC.FullHour
LEFT JOIN #GUESTCOUNT GUESTCOUNT ON DAYTIME.StoreKey = GUESTCOUNT.StoreKey AND DAYTIME.BusinessDate = GUESTCOUNT.BusinessDate AND DAYTIME.QuarterHour = GUESTCOUNT.QuarterHour
GROUP BY DAYTIME.StoreKey, DAYTIME.DayOfWeek, DAYTIME.QuarterHour, DAYTIME.STIME, Zip, State, GeoRegion, RegionName
---, STATIONPRODC.StationName


TRUNCATE TABLE #DAYTIME
TRUNCATE TABLE #ORDERS2
TRUNCATE TABLE #PRODCOUNT
---TRUNCATE TABLE #PRODCOUNT2
TRUNCATE TABLE #GUESTCOUNT

------------------------------------------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------------------------------------------
--START LOOPING
-------------------------------------------------------------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------------------------------------------------------------

SET @STORE = @STORE + 1

WHILE (@STORE <= @STOREMAX) 
BEGIN

---TimeFrame
INSERT INTO #DAYTIME1 (StoreKey, BusinessDate, TimeKey,Zip, State, GeoRegion, RegionName)
SELECT DISTINCT o.StoreKey, o.BusinessDate, o.TimeKey, s.Zip, s.State, s.GeoRegion, s.RegionName
FROM edw..factKitchenOrderLineItem o
JOIN edw..DimCalendar c on o.DateKey = c.DateKey
JOIN edw..DimStore s on s.StoreKey = o.StoreKey
JOIN edw..DimTables tb on tb.StoreKey = o.StoreKey
WHERE s.OpenFlag=1 AND c.BusinessDate >= @STARTDATE AND c.BusinessDate <= @ENDDATE AND o.StoreKey = @STORE

INSERT INTO #DAYTIME (StoreKey, BusinessDate, DayOfWeek,QuarterHour,STIME, ETIME,Zip, State, GeoRegion, RegionName)
SELECT DISTINCT d.StoreKey, BusinessDate, DATENAME(weekday,BusinessDate) DayOfWeek,
CAST((TimeKey-1) AS FLOAT) /4.0 QuarterHour, 
---FLOOR((TimeKey-1) / 4) FullHour,
---CAST((CAST(FLOOR((TimeKey-1) / 4) AS VARCHAR) + ':' + '00') AS TIME) AS 'STIME',
---CAST((CAST(FLOOR((TimeKey-1) / 4) AS VARCHAR) + ':' + '59') AS TIME) AS 'ETIME',
CAST(LEFT(t.StartTime,2) + ':' + RIGHT(t.StartTime,2) AS TIME) as 'STIME',
DATEADD(SECOND, 59.99, CAST(LEFT(t.EndTime,2) + ':' + RIGHT(t.EndTime,2) AS TIME)) as 'ETIME',
d.Zip, d.State, d.GeoRegion, d.RegionName
FROM #DAYTIME1 d
JOIN edw..DimTime t on t.TimeID = d.TimeKey
JOIN edw..DimTables tb on tb.StoreKey = d.StoreKey
TRUNCATE TABLE #DAYTIME1

---BASE1
INSERT INTO #BASE1 (StoreKey, BusinessDate, TimeKey, CheckNum, ProductKey, SentTime, NormalDateTime, CookingDateTime, BumpedDateTime, EmployeeKey, 
OrderStartDateTime, StationKey, DateKey, NatHolidayDesc)
SELECT DISTINCT
o.StoreKey, o.BusinessDate, o.TimeKey, o.CheckNum, o.ProductKey,
o.SentTime, cast(o.NormalDateTime as time) NormalDateTime,cast(o.CookingDateTime as time) CookingDateTime,cast(o.BumpedDateTime as time)BumpedDateTime, o.EmployeeKey, cast(o.OrderStartDateTime as time) OrderStartDateTime, o.StationKey,o.DateKey, c.NatHolidayDesc
from edw..factKitchenOrderLineItem o 
join edw..DimCalendar c on o.DateKey = c.DateKey
WHERE c.BusinessDate >= @STARTDATE  AND c.BusinessDate <= @ENDDATE AND o.StoreKey = @Store AND o.CourseName = 'ENTREES'

---Select Variables (including Mulisation) #BASE
INSERT INTO #BASE (StoreKey, BusinessDate, DayOfWeek, TimeKey, FullHour, HalfHour, QuarterHour, Holiday, CheckNum, GuestCount, TableOpenMinutes, OpenHour, OpenMinute, TypeofServiceNum, ProductKey, StationName, SentTime, 
OrderStartDateTime, NormalDateTime, CookingDateTime, BumpedDateTime, EmployeeKey, TicketTime, RNK, PROD_RNK)
SELECT o.StoreKey, 
--Day & Time
o.BusinessDate, DATENAME(weekday,o.BusinessDate) DayOfWeek, o.TimeKey, FLOOR((o.TimeKey-1) / 4) FullHour, (FLOOR((o.TimeKey-1)/2)/2.0) HalfHour, (o.TimeKey-1)/4.0 QuarterHour,
CASE WHEN o.NatHolidayDesc LIKE '[0-9][0-9]/[0-9][0-9]/[0-9]%' THEN 1 ELSE 0 END AS Holiday, 
---Order
o.CheckNum, s.GuestCount, s.TableOpenMinutes, s.OpenHour, s.OpenMinute, ch.TypeofServiceNum,
---Item
o.ProductKey, st.StationName, o.SentTime, 
---Round OrderStartDateTime to minute + Other DateTime
DATEADD(minute, DATEDIFF(minute, 0, o.OrderStartDateTime), 0) 'OrderStartDateTime',o.NormalDateTime,o.CookingDateTime,o.BumpedDateTime, o.EmployeeKey,
---Calculate TicketTime
DATEDIFF(SECOND,o.NormalDateTime,o.BumpedDateTime) 'TicketTime',
---Rank within order, item, station: # of same item orders in an check
ROW_NUMBER() OVER (PARTITION BY o.CheckNum, o.BusinessDate, o.ProductKey, DATEADD(minute, DATEDIFF(minute, 0, o.OrderStartDateTime), 0)  ORDER BY DATEDIFF(SECOND,o.NormalDateTime,o.BumpedDateTime) DESC) 'RNK',
---Rank within order, item: the slowest Item-Station
ROW_NUMBER() OVER (PARTITION BY o.CheckNum, o.BusinessDate, o.ProductKey, DATEADD(minute, DATEDIFF(minute, 0, o.OrderStartDateTime), 0)  ORDER BY DATEDIFF(SECOND,o.NormalDateTime,o.BumpedDateTime) DESC) 'PROD_RNK'
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
JOIN edw..dimProduct p
ON o.ProductKey = p.ProductKey
WHERE em.Employeekey IS NULL AND st.StationName <> 'KMEXPO' 
AND p.MajorCodeName not in ('BEVERAGES','Beverages','BEER','Beer','Desserts','Desserts','DESSERTS2','G/C ETC','G/C etc','Groceries','Liquor','LIQUOR','Not in Table','Whole Cakes','WHOLE CAKES','Wine' ,'WINE','SLICES','Slices','SIDES') 
AND p.MinorCodeName not in ('Sides','Soups','SOUPS','SIDES','BREAKFAST SIDES')

---Number of the same Item ordered within a check (max # cooked at the same station) #BCOUNT
INSERT INTO #BCOUNT (OrderStartDateTime, CheckNum, BusinessDate, ProductKey, StationName, STATION_COUNT)
SELECT OrderStartDateTime, CheckNum, BusinessDate, ProductKey, StationName,  MAX(RNK) 'STATION_COUNT'
FROM #BASE
GROUP BY StoreKey, CheckNum, BusinessDate, ProductKey, StationName, OrderStartDateTime

---Multi-Station Removal #BASE2
---Defining Invalid TicketTime: using parameter @MinTime, @MinRatio, @MaxRatio
INSERT INTO #BASE2 (StoreKey, BusinessDate, DayOfWeek, TimeKey, FullHour, HalfHour, QuarterHour, Holiday,CheckNum, GuestCount, TableOpenMinutes, OpenHour, OpenMinute,
TypeofServiceNum, ProductKey, StationName, SentTime, OrderStartDateTime, NormalDateTime,CookingDateTime, BumpedDateTime, 
EmployeeKey, TicketTime, RNK, PROD_RNK, TicketTime_invalid, TableOpenMinutes_invalid, Weekday)
SELECT BASE.*, 
CASE WHEN BASE.TicketTime <= @MINTIME THEN NULL
	WHEN BASE.TicketTime * @MINRATIO < BASE.SentTime THEN NULL 
	WHEN BASE.TicketTime * @MAXRATIO > BASE.SentTime THEN NULL
	ELSE BASE.TicketTime
	END AS TicketTime_invalid, 
CASE WHEN BASE.TableOpenMinutes <= 30 THEN NULL 
	WHEN BASE.TableOpenMinutes >= 240 THEN NULL 
	ELSE BASE.TableOpenMinutes 
	END AS TableOpenMinutes_invalid,
CASE WHEN BASE.DayOfWeek IN ('Monday','Tuesday', 'Wednesday', 'Thursday') OR (BASE.DayOfWeek = 'Sunday' AND BASE.FullHour >= 20) THEN 1
		ELSE 0 
		END AS Weekday
FROM #BASE BASE
JOIN #BCOUNT C ON BASE.OrderStartDateTime = C.OrderStartDateTime AND BASE.CheckNum = C.CheckNum AND BASE.BusinessDate = C.BusinessDate AND BASE.ProductKey = C.ProductKey AND BASE.StationName = C.StationName
---Keep the Nth slowest item-station in a check: N is the # same items ordered in a check
WHERE BASE.PROD_RNK <= C.STATION_COUNT 
TRUNCATE TABLE #BASE
TRUNCATE TABLE #BASE1
TRUNCATE TABLE #BCOUNT

---Table
INSERT INTO ##TABLE(StoreKey, BusinessDate, CheckNum, GuestCount, TableOpenMinutes_invalid, OpenHour, OpenMinute)
SELECT StoreKey, BusinessDate, CheckNum, AVG(GuestCount) GuestCount, AVG(TableOpenMinutes_invalid) TableOpenMinutes_invalid, AVG(OpenHour) OpenHour, AVG(OpenMinute) OpenMinute
FROM #BASE2 
WHERE TypeofServiceNum = 0
GROUP BY StoreKey, BusinessDate, CheckNum

---Fill Table Time
---Fill in Holiday
SET @HOLIDAY = 1
SET @GROUPBY = 'StoreKey, Holiday, GuestCount, HalfHour' EXEC (@sqlCommand2)
SET @GROUPBY = 'StoreKey, Holiday, GuestCount, FullHour' EXEC (@sqlCommand2)
SET @GROUPBY = 'StoreKey, Holiday, GuestCount'           EXEC (@sqlCommand2)
---Fill in Non-Holiday
SET @HOLIDAY = 0
SET @GROUPBY = 'StoreKey, Holiday, GuestCount, DayOfWeek, HalfHour' EXEC (@sqlCommand2)
SET @GROUPBY = 'StoreKey, Holiday, GuestCount, DayOfWeek, FullHour' EXEC (@sqlCommand2)
SET @GROUPBY = 'StoreKey, Holiday, GuestCount, Weekday, HalfHour'   EXEC (@sqlCommand2)
SET @GROUPBY = 'StoreKey, Holiday, GuestCount, Weekday, FullHour'   EXEC (@sqlCommand2)
---Fll in All Day
SET @GROUPBY = 'StoreKey, GuestCount, DayOfWeek, HalfHour' EXEC (@sqlCommand2)
SET @GROUPBY = 'StoreKey, GuestCount, DayOfWeek, FullHour' EXEC (@sqlCommand2)
SET @GROUPBY = 'StoreKey, GuestCount, Weekday, HalfHour'   EXEC (@sqlCommand2)
SET @GROUPBY = 'StoreKey, GuestCount, Weekday, FullHour'   EXEC (@sqlCommand2)

---Update to #TABLE & Create Time Variable
INSERT INTO #GUEST (StoreKey, BusinessDate, CheckNum, GuestCount, OpenTime, CloseTime) 
SELECT StoreKey, BusinessDate, CheckNum,GuestCount, 
CAST(CAST(OpenHour as VARCHAR)+':'+CAST(OpenMinute as varchar) as time) OpenTime,
DATEADD(minute, TableOpenMinutes_invalid, CAST(CAST(OpenHour as VARCHAR)+':'+CAST(OpenMinute as varchar) as time)) CloseTime
FROM ##TABLE
TRUNCATE TABLE ##TABLE

---Count of Concurrent Guest during 15 min (OnSite
INSERT INTO #GUESTCOUNT (StoreKey, BusinessDate, QuarterHour, STIME, GUESTCOUNT)
SELECT DAYTIME.StoreKey,DAYTIME.BusinessDate, DAYTIME.QuarterHour, DAYTIME.STIME,
SUM(TABLECOUNT.GuestCount) 'GUESTCOUNT'
FROM #DAYTIME DAYTIME
JOIN #GUEST TABLECOUNT ON 
	TABLECOUNT.StoreKey = DAYTIME.StoreKey AND 
	TABLECOUNT.BusinessDate = DAYTIME.BusinessDate 
	AND TABLECOUNT.OpenTime < DAYTIME.ETIME AND  TABLECOUNT.CloseTime > DAYTIME.STIME 
GROUP BY DAYTIME.StoreKey,DAYTIME.BusinessDate, DAYTIME.QuarterHour, DAYTIME.STIME
TRUNCATE TABLE #GUEST

-----------------------------------------------------------------------------------------------------------------------------------------------------
---Filling Invalid TicketTime 
-----------------------------------------------------------------------------------------------------------------------------------------------------
INSERT INTO ##BASE4 (StoreKey, BusinessDate, DayOfWeek, TimeKey, FullHour, HalfHour, QuarterHour, Holiday,CheckNum, GuestCount, TableOpenMinutes, OpenHour, OpenMinute, 
TypeofServiceNum, ProductKey, StationName, SentTime, OrderStartDateTime, NormalDateTime,CookingDateTime, BumpedDateTime, 
EmployeeKey, TicketTime, RNK, PROD_RNK, TicketTime_invalid, TableOpenMinutes_invalid, Weekday)
SELECT *
FROM #BASE2
TRUNCATE TABLE #BASE2

---Fill in Holiday
SET @HOLIDAY = 1
SET @GROUPBY = 'StoreKey, Holiday, ProductKey, HalfHour' EXEC (@sqlCommand)
SET @GROUPBY = 'StoreKey, Holiday, ProductKey, FullHour' EXEC (@sqlCommand)
SET @GROUPBY = 'StoreKey, Holiday, ProductKey'           EXEC (@sqlCommand)

---Fill in NonHoliday
SET @HOLIDAY = 0
SET @GROUPBY = 'StoreKey, Holiday, ProductKey, DayOfWeek, HalfHour' EXEC (@sqlCommand)
SET @GROUPBY = 'StoreKey, Holiday, ProductKey, DayOfWeek, FullHour' EXEC (@sqlCommand)
SET @GROUPBY = 'StoreKey, Holiday, ProductKey, Weekday, HalfHour'   EXEC (@sqlCommand)
SET @GROUPBY = 'StoreKey, Holiday, ProductKey, Weekday, FullHour'   EXEC (@sqlCommand)
SET @GROUPBY = 'StoreKey, Holiday, ProductKey, Weekday, FullHour'   EXEC (@sqlCommand)

---Fill in All Days
SET @GROUPBY = 'StoreKey, ProductKey, DayOfWeek, HalfHour' EXEC (@sqlCommand1)
SET @GROUPBY = 'StoreKey, ProductKey, DayOfWeek, FullHour' EXEC (@sqlCommand1)
SET @GROUPBY = 'StoreKey, ProductKey, Weekday, FullHour'   EXEC (@sqlCommand1)
SET @GROUPBY = 'StoreKey, ProductKey, Weekday, HalfHour'   EXEC (@sqlCommand1)

---Fill in with Sent Time
UPDATE ##BASE4
SET ##BASE4.TicketTime_invalid = ##BASE4.SentTime
WHERE ##BASE4.TicketTime_invalid IS NULL

---Update BASE4
UPDATE ##BASE4
SET BumpedDateTime = DATEADD(second, TicketTime_invalid, NormalDateTime)

INSERT INTO #BASE4 (StoreKey, BusinessDate, DayOfWeek, TimeKey, FullHour, HalfHour, QuarterHour, Holiday,CheckNum, GuestCount, TableOpenMinutes, OpenHour, OpenMinute, 
TypeofServiceNum, ProductKey, StationName, SentTime, OrderStartDateTime, NormalDateTime,CookingDateTime, BumpedDateTime, 
EmployeeKey, TicketTime, RNK, PROD_RNK, TicketTime_invalid,TableOpenMinutes_invalid, Weekday)
SELECT *
FROM ##BASE4
TRUNCATE TABLE ##BASE4

---Rank of Product Within Order
INSERT INTO #BASE3 (StoreKey, BusinessDate, DayOfWeek, TimeKey, FullHour, HalfHour, QuarterHour, Holiday,CheckNum, GuestCount, TableOpenMinutes, OpenHour, OpenMinute, 
TypeofServiceNum, ProductKey, StationName, SentTime, OrderStartDateTime, NormalDateTime,CookingDateTime, BumpedDateTime, 
EmployeeKey, TicketTime, RNK, PROD_RNK, TicketTime_invalid, TableOpenMinutes_invalid, Weekday, ORDER_RNK)
SELECT #BASE4.*, 
ROW_NUMBER() OVER (PARTITION BY StoreKey, CheckNum, BusinessDate, OrderStartDateTime  ORDER BY BumpedDateTime DESC) 'ORDER_RNK'
FROM #BASE4
TRUNCATE TABLE #BASE4

---Aggregate to Order: Keep longest 

INSERT INTO #ORDERS (StoreKey, BusinessDate,Holiday, CheckNum, OrderStartDateTime, BumpedDateTime, TypeofServiceNum)
SELECT StoreKey, BusinessDate,Holiday, CheckNum, OrderStartDateTime, BumpedDateTime, TypeofServiceNum
FROM #BASE3 BASE3
WHERE BASE3.ORDER_RNK =1 

---Count of Concurrent Order during 15min (OnSite and OffSite)
INSERT INTO #ORDERS2 (StoreKey, BusinessDate, QuarterHour, STIME, TypeofServiceNum, Holiday, ORDERCOUNT)
SELECT DAYTIME.StoreKey,
DAYTIME.BusinessDate, DAYTIME.QuarterHour, DAYTIME.STIME, ORDERC.TypeofServiceNum, ORDERC.Holiday, 
COUNT(ORDERC.CheckNum) 'ORDERCOUNT'
FROM #DAYTIME DAYTIME
JOIN #ORDERS ORDERC ON ORDERC.BusinessDate = DAYTIME.BusinessDate 
	AND ORDERC.StoreKey = DAYTIME.StoreKey
	AND cast(ORDERC.OrderStartDateTime as time) < DAYTIME.ETIME AND  ORDERC.BumpedDateTime > DAYTIME.STIME 
GROUP BY DAYTIME.StoreKey,DAYTIME.BusinessDate,DAYTIME.QuarterHour, DAYTIME.STIME, ORDERC.TypeofServiceNum, ORDERC.Holiday
TRUNCATE TABLE #ORDERS


---Count of Concurrent Item during 15 min (OnSite and OffSite)
INSERT INTO #PRODCOUNT (StoreKey, BusinessDate,QuarterHour, STIME,TypeofServiceNum,Holiday,PRODCOUNT)
SELECT DAYTIME.StoreKey,
DAYTIME.BusinessDate, DAYTIME.QuarterHour,  DAYTIME.STIME, PRODCOUNT.TypeofServiceNum, PRODCOUNT.Holiday,
COUNT(PRODCOUNT.CheckNum) 'PRODCOUNT'
FROM #DAYTIME DAYTIME
JOIN #BASE3 PRODCOUNT ON 
	PRODCOUNT.BusinessDate = DAYTIME.BusinessDate 
	AND cast(PRODCOUNT.OrderStartDateTime as time) < DAYTIME.ETIME AND  PRODCOUNT.BumpedDateTime > DAYTIME.STIME 
GROUP BY DAYTIME.StoreKey,DAYTIME.BusinessDate, DAYTIME.QuarterHour, DAYTIME.STIME, PRODCOUNT.TypeofServiceNum, PRODCOUNT.Holiday

/*
---Count of Concurrent Item during 15 min (by Station)
INSERT INTO #PRODCOUNT2 (StoreKey,BusinessDate,STIME,StationName,Holiday,PRODCOUNT)
SELECT DAYTIME.StoreKey,
DAYTIME.BusinessDate, DAYTIME.STIME, PRODCOUNT.StationName,PRODCOUNT.Holiday, 
COUNT(PRODCOUNT.CheckNum) 'PRODCOUNT'
/* ISNULL((SELECT
	COUNT(*)
	FROM #BASE2 B
	WHERE B.BusinessDate = ORDERS.BusinessDate 
	AND B.CheckNum <> ORDERS.CheckNum 
	AND B.BumpedDateTime >= ORDERS.OrderStartDateTime 
	AND B.OrderStartDateTime <= ORDERS.OrderStartDateTime
	AND B.TypeofServiceNum = ORDERS.TypeofServiceNum),0) 'PRODCOUNT'*/
FROM #DAYTIME DAYTIME
JOIN #BASE3 PRODCOUNT ON 
	PRODCOUNT.BusinessDate = DAYTIME.BusinessDate 
	AND cast(PRODCOUNT.OrderStartDateTime as time) < DAYTIME.ETIME AND  cast(PRODCOUNT.BumpedDateTime as time) > DAYTIME.STIME 
GROUP BY DAYTIME.StoreKey,DAYTIME.BusinessDate, DAYTIME.STIME, PRODCOUNT.StationName, PRODCOUNT.Holiday
*/
TRUNCATE TABLE #BASE3

INSERT INTO #T1 (StoreKey, DayOfWeek, QuarterHour, STIME, Zip, State, GeoRegion, RegionName, OffSiteOrder, OnSiteOrder, TotalOrder, OnSiteItem, OffSiteItem, TotalItem, OnSiteGuest)
SELECT DAYTIME.StoreKey, DayTime.DayOfWeek, DAYTIME.QuarterHour, DAYTIME.STIME, DAYTIME.Zip, DAYTIME.State, DAYTIME.GeoRegion, DAYTIME.RegionName,
---STATIONPRODC.StationName, 
AVG(ISNULL(OFFSITEC.ORDERCOUNT,0))'OffSiteOrder',
AVG(ISNULL(ONSITEC.ORDERCOUNT,0))  'OnSiteOrder',
AVG(ISNULL(OFFSITEC.ORDERCOUNT,0) + ISNULL(ONSITEC.ORDERCOUNT,0))'TotalOrder',
AVG(ISNULL(ONSITEPRODC.PRODCOUNT,0)) 'OnSiteItem',
AVG(ISNULL(OFFSITEPRODC.PRODCOUNT,0)) 'OffSiteItem',
AVG(ISNULL(ONSITEPRODC.PRODCOUNT,0) + ISNULL(OFFSITEPRODC.PRODCOUNT,0)) 'TotalItem',
AVG(ISNULL(GUESTCOUNT.GUESTCOUNT,0)) 'OnSiteGuest'
---,AVG(ISNULL(STATIONPRODC.PRODCOUNT,0)) 'StationItem'
FROM #DAYTIME DAYTIME 
LEFT JOIN #ORDERS2 OFFSITEC ON DAYTIME.StoreKey = OFFSITEC.StoreKey AND DAYTIME.BusinessDate = OFFSITEC.BusinessDate AND DAYTIME.QuarterHour = OFFSITEC.QuarterHour AND OFFSITEC.TypeofServiceNum = 1
LEFT JOIN #ORDERS2 ONSITEC ON DAYTIME.StoreKey = ONSITEC.StoreKey AND DAYTIME.BusinessDate = ONSITEC.BusinessDate AND DAYTIME.QuarterHour = ONSITEC.QuarterHour AND OFFSITEC.TypeofServiceNum = 0
LEFT JOIN #PRODCOUNT OFFSITEPRODC ON DAYTIME.StoreKey = OFFSITEC.StoreKey AND DAYTIME.BusinessDate = OFFSITEPRODC.BusinessDate AND DAYTIME.QuarterHour = OFFSITEPRODC.QuarterHour  AND OFFSITEPRODC.TypeofServiceNum = 1
LEFT JOIN #PRODCOUNT ONSITEPRODC ON DAYTIME.StoreKey = ONSITEC.StoreKey AND DAYTIME.BusinessDate = ONSITEPRODC.BusinessDate  AND DAYTIME.QuarterHour = ONSITEPRODC.QuarterHour  AND ONSITEPRODC.TypeofServiceNum = 0
---FULL OUTER JOIN #PRODCOUNT2 STATIONPRODC ON DAYTIME.StoreKey = STATIONPRODC.StoreKey AND DAYTIME.BusinessDate = STATIONPRODC.BusinessDate AND DAYTIME.FullHour = STATIONPRODC.FullHour
LEFT JOIN #GUESTCOUNT GUESTCOUNT ON DAYTIME.StoreKey = GUESTCOUNT.StoreKey AND DAYTIME.BusinessDate = GUESTCOUNT.BusinessDate AND DAYTIME.QuarterHour = GUESTCOUNT.QuarterHour
GROUP BY DAYTIME.StoreKey, DAYTIME.DayOfWeek, DAYTIME.QuarterHour, DAYTIME.STIME, Zip, State, GeoRegion, RegionName
---, STATIONPRODC.StationName

TRUNCATE TABLE #DAYTIME
TRUNCATE TABLE #ORDERS2
TRUNCATE TABLE #PRODCOUNT
---TRUNCATE TABLE #PRODCOUNT2
TRUNCATE TABLE #GUESTCOUNT

SET @STORE = @STORE+1
END

SELECT * FROM #T1



