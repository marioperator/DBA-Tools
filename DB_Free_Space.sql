IF exists (SELECT * FROM tempdb.sys.all_objects WHERE name = '#dbsize') 
DROP TABLE #dbsize
CREATE TABLE #dbsize
	(DBName sysname, DBStatus varchar(20), Recovery_Model varchar(20), File_Size_MB decimal(30,2),
	Space_Used decimal(30,2), Free_Space_MB decimal(30,2))
GO
INSERT INTO #dbsize(DBName, DBStatus, Recovery_Model, File_Size_MB, Space_Used, Free_Space_MB)
EXEC sp_msforeachdb
'USE [?];
SELECT	DB_Name() as DBName, 
		CONVERT(varchar(20), DATABASEPROPERTYEX(''?'', ''STATUS'')),
		CONVERT(varchar(20), DATABASEPROPERTYEX(''?'', ''RECOVERY'')),
		SUM(size)/128.0 as File_Size_MB,
		SUM(CAST(FILEPROPERTY(name, ''SpaceUsed'') AS INT))/128.0 as Space_Used_MB, 
		SUM( size)/128.0 - SUM(CAST(FILEPROPERTY(name,''SpaceUsed'') AS INT))/128.0 AS Free_Space_MB  
FROM sys.database_files  WHERE type=0 GROUP BY type'

SELECT	DBname, Dbstatus, Recovery_Model, File_Size_MB, Space_Used, 
		Free_Space_MB, ((Free_Space_MB/File_Size_MB)*100) as Free_Space_Percent FROM #dbsize

DROP TABLE #dbsize