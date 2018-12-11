-- Linked server to the subscriber with "DATA ACCESS = TRUE" needs to be created.
--There might be errors if database collation settings are different in publisher and subscriber
IF OBJECT_ID('tempdb..#tempTransReplication') IS NOT NULL 
 DROP TABLE #tempTransReplication

CREATE TABLE #tempTransReplication
 (
 publisher_id INT,
 publisher_srv VARCHAR(255),
 publisher_db VARCHAR(255),
 publication VARCHAR(255),
 subscriber_id INT,
 subscriber_srv VARCHAR(255),
 subscriber_db VARCHAR(255),
 object_type VARCHAR(255),
 source_owner VARCHAR(255),
 source_object VARCHAR(255),
 destination_owner VARCHAR(255),
 destination_object VARCHAR(255),
 rowcount_publisher INT,
 rowcount_subscriber INT,
 rowcount_diff INT
 )

INSERT INTO #tempTransReplication
 SELECT s.publisher_id,
 ss2.data_source,
 a.publisher_db,
 p.publication,
 s.subscriber_id,
 ss.data_source,
 s.subscriber_db,
 NULL,
 a.source_owner,
 a.source_object,
 ISNULL(a.destination_owner, a.source_owner), -- if NULL, schema name remains same at subscriber side
 a.destination_object,
 NULL,
 NULL,
 NULL
 FROM distribution.dbo.MSarticles AS a
 INNER JOIN distribution.dbo.MSsubscriptions AS s 
ON a.publication_id = s.publication_id
 AND a.article_id = s.article_id
 INNER JOIN [master].sys.servers AS ss 
ON s.subscriber_id = ss.server_id
 INNER JOIN distribution.dbo.MSpublications AS p 
ON s.publication_id = p.publication_id
 LEFT OUTER JOIN [master].sys.servers AS ss2 
ON p.publisher_id = ss2.server_id
 WHERE s.subscriber_db <> 'virtual'

 IF OBJECT_ID('tempdb..#tempPublishedArticles') IS NOT NULL 
 DROP TABLE #tempPublishedArticles

CREATE TABLE #tempPublishedArticles
 (
 publisher_db VARCHAR(255),
 source_owner VARCHAR(255),
 source_object VARCHAR(255),
 object_type VARCHAR(255),
 rowcount_publisher INT
 )

DECLARE @pub_db VARCHAR(255),
 @strSQL_P VARCHAR(4000)

DECLARE db_cursor_p CURSOR
 FOR SELECT DISTINCT
 publisher_db
 FROM distribution.dbo.MSpublications

OPEN db_cursor_p 
FETCH NEXT FROM db_cursor_p INTO @pub_db

WHILE @@FETCH_STATUS = 0 
    BEGIN
        SET @strSQL_P = 'SELECT ' + '''' + @pub_db + ''''
            + ' AS publisher_db, s.name AS source_owner, o.name AS source_object, o.Type_Desc AS object_type, i.rowcnt AS rowcount_publisher 
 FROM ' + @pub_db + '.sys.objects AS o 
 INNER JOIN ' + @pub_db + '.sys.schemas AS s 
on o.schema_id = s.schema_id 
 LEFT OUTER JOIN ' + @pub_db + '.dbo.sysindexes AS i 
on o.object_id = i.id 
 WHERE ' + '''' + @pub_db + '''' 
+ ' + ' + '''' + '.' + '''' + ' + s.name'
            + ' + ' + '''' + '.' + '''' + ' + o.name'
            + ' IN (SELECT publisher_db + ' + '''' + '.' + ''''
            + ' + source_owner + ' + '''' + '.' + ''''
            + ' + source_object FROM #tempTransReplication) 
 AND ISNULL(i.indid, 0) IN (0, 1)
 ORDER BY i.rowcnt DESC'
-- heap (indid=0); clustered index (indix=1)
INSERT INTO #tempPublishedArticles
 EXEC ( @strSQL_P
 )
 
 FETCH NEXT FROM db_cursor_p INTO @pub_db 
 END
CLOSE db_cursor_p 
DEALLOCATE db_cursor_p

IF OBJECT_ID('tempdb..#tempSubscribedArticles') IS NOT NULL 
 DROP TABLE #tempSubscribedArticles

CREATE TABLE #tempSubscribedArticles
 (
 subscriber_srv VARCHAR(255),
 subscriber_db VARCHAR(255),
 destination_owner VARCHAR(255),
 destination_object VARCHAR(255),
 object_type VARCHAR(255),
 rowcount_subscriber INT
 )

DECLARE @sub_srv VARCHAR(255),
 @sub_db VARCHAR(255),
 @strSQL_S VARCHAR(4000)

DECLARE db_cursor_s CURSOR
 FOR SELECT DISTINCT
 subscriber_srv,
 subscriber_db
 FROM #tempTransReplication

OPEN db_cursor_s
FETCH NEXT FROM db_cursor_s INTO @sub_srv, @sub_db

WHILE @@FETCH_STATUS = 0 
 BEGIN
SET @strSQL_S = 'SELECT ' + '''' + @sub_srv + ''''
 + ' AS subscriber_srv, ' + '''' + @sub_db + ''''
 + ' AS subscriber_db, '
 + 's.name AS destination_owner, o.name AS destination_object, o.Type_Desc AS object_type, i.rowcnt AS rowcount_subscriber 
FROM ' + @sub_srv + '.' + @sub_db + '.sys.objects AS o 
INNER JOIN ' + @sub_srv + '.' + @sub_db
 + '.sys.schemas AS s on o.schema_id = s.schema_id
LEFT OUTER JOIN ' + @sub_srv + '.' + @sub_db
 + '.dbo.sysindexes AS i on o.object_id = i.id
WHERE ' + '''' + @sub_srv + '.' + @sub_db + '''' 
+ ' + ' + '''' + '.' + ''''
 + ' + s.name' + ' + ' + '''' + '.' + '''' + ' + o.name'
 + ' IN (SELECT subscriber_srv + ' + '''' + '.' + ''''
 + ' + subscriber_db + ' + '''' + '.' + ''''
 + ' + destination_owner + ' + '''' + '.' + ''''
 + ' + destination_object FROM #tempTransReplication) 
AND ISNULL(i.indid, 0) IN (0, 1) 
ORDER BY i.rowcnt DESC'
-- heap (indid=0); clustered index (indix=1)
INSERT INTO #tempSubscribedArticles
 EXEC ( @strSQL_S
 )
 
 FETCH NEXT FROM db_cursor_s INTO @sub_srv, @sub_db
 END 
CLOSE db_cursor_s
DEALLOCATE db_cursor_s

UPDATE t
SET rowcount_publisher = p.rowcount_publisher,
 object_type = p.object_type
FROM #tempTransReplication AS t
 INNER JOIN #tempPublishedArticles AS p ON t.publisher_db = p.publisher_db
 AND t.source_owner = p.source_owner
 AND t.source_object = p.source_object

UPDATE t
SET rowcount_subscriber = s.rowcount_subscriber
FROM #tempTransReplication AS t
 INNER JOIN #tempSubscribedArticles AS s ON t.subscriber_srv = s.subscriber_srv
 AND t.subscriber_db = s.subscriber_db
 AND t.destination_owner = s.destination_owner
 AND t.destination_object = s.destination_object

UPDATE #tempTransReplication
SET rowcount_diff = ABS(rowcount_publisher - rowcount_subscriber)

-- rowcount result by replicated database
SELECT publisher_srv,
 publisher_db,
 subscriber_srv,
 subscriber_db,
 sum(rowcount_diff) AS rowcount_diff
FROM #tempTransReplication
WHERE object_type = 'USER_TABLE' -- tables only
GROUP BY publisher_srv,
 publisher_db,
 subscriber_srv,
 subscriber_db
HAVING sum(rowcount_diff) > 0 -- only show those databases which fall behind
ORDER BY rowcount_diff DESC

-- rowcount result by publication
SELECT publisher_srv,
 publisher_db,
 publication,
 subscriber_srv,
 subscriber_db,
 sum(rowcount_diff) AS rowcount_diff
FROM #tempTransReplication
WHERE object_type = 'USER_TABLE' -- tables only
GROUP BY publisher_srv,
 publisher_db,
 publication,
 subscriber_srv,
 subscriber_db
HAVING sum(rowcount_diff) > 0 -- only show those publications which fall behind
ORDER BY rowcount_diff DESC

-- rowcount result by table
SELECT publisher_srv,
 publisher_db,
 subscriber_srv,
 subscriber_db,
 publication,
 object_type,
 ( source_owner + '.' + source_object ) AS source_objectname,
 ( destination_owner + '.' + destination_object ) AS destination_objectname,
 rowcount_diff AS rowcount_diff
FROM #tempTransReplication
WHERE object_type = 'USER_TABLE' -- tables only 
AND rowcount_diff > 0 -- only show those tables which fall behind
ORDER BY rowcount_diff DESC
