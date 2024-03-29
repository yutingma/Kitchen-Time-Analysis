

DECLARE @STARTDATE AS DATETIME
SET @STARTDATE = '01/03/2018'

DECLARE @STORE AS INTEGER
SET @STORE = 34

IF OBJECT_ID('tempdb..#BASE') IS NOT NULL DROP TABLE #BASE
IF OBJECT_ID('tempdb..#BASE1') IS NOT NULL DROP TABLE #BASE1
IF OBJECT_ID('tempdb..#BASE2') IS NOT NULL DROP TABLE #BASE2
IF OBJECT_ID('tempdb..#BASE3') IS NOT NULL DROP TABLE #BASE3
---IF OBJECT_ID('tempdb..##BASE3') IS NOT NULL DROP TABLE ##BASE3
---IF OBJECT_ID('tempdb..##BASE3') IS NOT NULL DROP TABLE ##BASE4
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
o.StoreKey, o.BusinessDate, o.TimeKey, o.CheckNum, o.ProductKey,o.CourseName, 
o.SentTime, o.NormalDateTime,o.CookingDateTime,o.BumpedDateTime, o.EmployeeKey, o.OrderStartDateTime, o.StationKey,o.DateKey
INTO #BASE1
from edw..factKitchenOrderLineItem o 
join edw..DimCalendar c on o.DateKey = c.DateKey
WHERE c.BusinessDate >= @STARTDATE and o.storekey = @STORE 



--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
---Select Needed Varibles, Remove Exlusions 
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------


SELECT o.StoreKey, 
--Day & Time
o.BusinessDate, o.DateKey, DATENAME(weekday,o.BusinessDate) DayOfWeek, o.TimeKey, FLOOR((o.TimeKey-1) / 4) FullHour, (FLOOR((o.TimeKey-1)/2)/2.0) HalfHour, (o.TimeKey-1)/4.0 QuarterHour,t.StartTime,
CASE WHEN NatHolidayDesc LIKE '[0-9][0-9]/[0-9][0-9]/[0-9]%' THEN 0 ELSE 1 END AS Holiday, 
---Order
o.CheckNum, s.GuestCount, s.TableOpenMinutes, s.OpenHour, s.OpenMinute, s.CloseHour, s.CloseMinute, ch.ChannelKey, ch.TypeofServiceNum,
---Item
o.ProductKey,o.CourseName, p.IXIName,p.MajorCodeName,p.MinorCodeName, o.StationKey,st.StationName, o.SentTime, 
---Round OrderStartDateTime to minute + Other DateTime (to make sure one batch of order has the same order time). OrderStartDateTime is used to separate different batches of order within one check. 
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
---Exlude employee meal checks
em.Employeekey IS NULL AND 
---Keep only ENTREE Course
o.CourseName = 'ENTREES' AND 
---Exclude records on EXPO station screen
st.StationName <> 'KMEXPO' AND 
---Exclude Non-Kitchen Items
p.MajorCodeName not in ('BEVERAGES','Beverages','BEER','Beer','Desserts','Desserts','DESSERTS2','G/C ETC','G/C etc','Groceries','Liquor','LIQUOR','Not in Table','Whole Cakes','WHOLE CAKES','Wine' ,'WINE','SLICES','Slices','SIDES') 
and p.MinorCodeName not in ('Sides','Soups','SOUPS','SIDES','BREAKFAST SIDES')





--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
---Multi-Station Removal
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

---Estimate number of the same item ordered within a check (max # cooked at the same station) 
SELECT OrderStartDateTime, CheckNum, BusinessDate, ProductKey, StationKey,  MAX(RNK) 'STATION_COUNT'
INTO #BCOUNT
FROM #BASE BASE
GROUP BY StoreKey, CheckNum, BusinessDate, ProductKey, StationKey, OrderStartDateTime


---Remove Multi-Station
SELECT BASE.*
INTO #BASE2
FROM #BASE BASE
JOIN #BCOUNT C ON BASE.OrderStartDateTime = C.OrderStartDateTime AND BASE.CheckNum = C.CheckNum AND BASE.BusinessDate = C.BusinessDate AND BASE.ProductKey = C.ProductKey AND BASE.StationKey = C.StationKey
---Keep the Nth longest cook time for the same item in a check: N is the # same items ordered in a check
WHERE BASE.PROD_RNK <= C.STATION_COUNT 



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




--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
---Join Concurrent Count to Item Table
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------


SELECT BASE3.*,SERVICECAT.TypeofServiceCat,ch.ChannelName,t.StartTime,
ISNULL(OFFSITEC.ORDERCOUNT,0)  'OffSiteOrder',
ISNULL(ONSITEC.ORDERCOUNT,0)  'OnSiteOrder',
ISNULL(OFFSITEC.ORDERCOUNT,0) + ISNULL(ONSITEC.ORDERCOUNT,0) 'TotalOrder',
ISNULL(ONSITEPRODC.PRODCOUNT,0) 'OnSiteItem',
ISNULL(OFFSITEPRODC.PRODCOUNT,0) 'OffSiteItem',
ISNULL(ONSITEPRODC.PRODCOUNT,0) + ISNULL(OFFSITEPRODC.PRODCOUNT,0) 'TotalItem'
FROM #BASE3 BASE3
---#Concurrent Off-Premise Order
LEFT JOIN #ORDERS2 OFFSITEC ON BASE3.CheckNum = OFFSITEC.CheckNum AND BASE3.OrderStartDateTime = OFFSITEC.OrderStartDateTime AND OFFSITEC.TypeofServiceNum = 1
---#Concurrent On-Premise Order
LEFT JOIN #ORDERS2 ONSITEC ON BASE3.CheckNum = ONSITEC.CheckNum AND BASE3.OrderStartDateTime = ONSITEC.OrderStartDateTime AND ONSITEC.TypeofServiceNum = 0
---#Concurrent Off-Premise Item
LEFT JOIN #PRODCOUNT OFFSITEPRODC ON BASE3.CheckNum = OFFSITEPRODC.CheckNum AND BASE3.OrderStartDateTime = OFFSITEPRODC.OrderStartDateTime  AND OFFSITEPRODC.TypeofServiceNum = 1
---#Concurrent On-Premise Item
LEFT JOIN #PRODCOUNT ONSITEPRODC ON BASE3.CheckNum = ONSITEPRODC.CheckNum  AND BASE3.OrderStartDateTime = ONSITEPRODC.OrderStartDateTime  AND ONSITEPRODC.TypeofServiceNum = 0
JOIN EDW..DimCalendar c ON c.DateKey = BASE3.DateKey
JOIN edw..dimChannel ch on BASE3.ChannelKey = ch.ChannelKey
JOIN #SERVICECAT SERVICECAT on BASE3.TypeofServiceNum = SERVICECAT.TypeofServiceNum
JOIN edw..DimTime t ON BASE3.TimeKey = t.TimeID




