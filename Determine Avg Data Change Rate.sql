
/*
This script started as a response to a query from Tim Gentry as to how much data changes in teh DBs across all servers 
ie. what is he data change rate

This isn't an easy question to answer, so this solution looks at teh Differential backups and compares the 
Time (T) and Time (T-1) differentials to see how much they have changed. Obviously this means compensating for hte first 
differential of the week and we don't want to be comparing first and last diffs over a full backup

We then take all those numbers, average them out and them sum the averages to see the average data change across
the server as a whole in one day.

*/
----------------

/*
 select database_name, type, backup_start_date, backup_size/1024/1024 AS BackupSizeMB
   from msdb.dbo.backupset
  where type <> 'L'
    AND database_name NOT IN ('master','model','msdb')
    and backup_start_date > CAST('2017-01-04 14:00:00.000' AS DATETIME)
 ORDER BY database_name ASC, backup_start_date DESC
*/

DROP TABLE #tbackup

SELECT database_name AS DBName, 
	   CAST(backup_start_date AS DATE) AS BackupDate, 
	   backup_size/1024/1024 AS BackupSizeMB
  INTO #tbackup
  from msdb.dbo.backupset
 WHERE type = 'I'
   AND backup_start_date BETWEEN CAST('2017-01-04 14:00:00.000' AS DATETIME) AND CAST('2017-02-17 14:00:00.000' AS DATETIME)
   AND database_name NOT IN ('master','model','msdb')
 ORDER BY database_name ASC, backup_start_date DESC

--SELECT * 
--  FROM #tbackup
  
/* 
-- original PIVOT idea dropepd for sequential updats to a temp table
DROP TABLE #tpivot

SELECT DBName, [2017-02-16] AS [16], [2017-02-15] AS [15], [2017-02-14] AS [14], [2017-02-13] AS [13]
  INTO #tpivot
  FROM #tbackup 
PIVOT (SUM(backupsizeMB) FOR BackupDate IN ([2017-02-16], [2017-02-15], [2017-02-14], [2017-02-13]) ) AS b

SELECT * FROM #tpivot
 WHERE DBName = 'tdxrmis'

SELECT
	DBName,
	[16]-[15] AS [T],
	[15]-[14] AS [T-1],
	[15]-[13] AS [T-2]
  FROM #tpivot
------------------

SELECT * 
  FROM #tbackup

select * from #tsize
 order by dbname, [date] desc

*/

DROP TABLE #tSize

SELECT t.DBName, MAX(t.BackupDate) AS [Date], CAST(NULL AS DATE) AS [PrevBackup], CAST(0 AS NUMERIC(20,3)) AS [BackupSize], CAST(NULL AS NUMERIC(20,3)) AS [BackupDiff]
	--(SELECT MAX(backupDate) FROM #tbackup b WHERE b.BackupDate < t.BackupDate)
  INTO #tSize
  FROM #tbackup t
 GROUP BY t.DBName

WHILE ((SELECT MIN([Date]) FROM #tsize) > (SELECT MIN(BackupDate) FROM #tbackup))
BEGIN
	INSERT #tSize
	SELECT t.DBName, MAX(t.BackupDate), NULL, CAST(0 AS NUMERIC(20,3)), CAST(NULL AS NUMERIC(20,3))
		--(SELECT MAX(backupDate) FROM #tbackup b WHERE b.BackupDate < t.BackupDate)
	  FROM #tbackup t
	 WHERE t.BackupDate < (SELECT MIN([Date]) FROM #tsize)
	 GROUP BY t.DBName
END      

UPDATE #tSize
   SET PrevBackup = (SELECT MAX(backupDate) FROM #tbackup WHERE BackupDate < [Date] AND #tbackup.DBName = #tSize.DBName)
  FROM #tSize

UPDATE #tSize  
   SET backupSize = BackupSizeMB 
  FROM #tSize s
  INNER JOIN #tbackup t ON t.DBName = s.DBName AND t.BackupDate = s.[Date]

UPDATE #tSize  
   SET backupDiff = BackupSize - t.BackupSizeMB
  FROM #tSize s
  INNER JOIN #tbackup t ON t.DBName = s.DBName AND t.BackupDate = s.PrevBackup
  WHERE DATEDIFF(DAY,PrevBackup,[date]) = 1



--SELECT * FROM #tSize
-- ORDER BY DBName, [date] desc

DROP TABLE #tAvg

SELECT DBName, AVG(BackupDiff) AS AvgDiff, MAX(BackupDiff) AS MaxDiff
  INTO #tAvg
  FROM #tSize
 WHERE BackupDiff IS NOT NULL
   AND BackupDiff > 0
 GROUP BY DBName
 ORDER BY DBName

--SELECT * FROM #tSize
-- WHERE DBName = 'tdxrmis'
-- ORDER BY DBName, [date] desc

SELECT @@SERVERNAME AS [Server], 
	SUM(avgDiff) AS AvgDailyDataChangeMB, 
	SUM(maxDiff) AS MaxDailyDataChangeMB
  FROM #tAvg

/*
Server			AvgDailyDataChangeMB	MaxDailyDataChangeMB
TDXHLWSQL01		14537.878085			28063.252
TDXHLWSQL02		2645.164287				11138.001
TDXHLWSQL03		4000.791821				25623.511
TDXHLWSQL06\ETC	1353.067321				4412.064
TDXHLWSQL07		21561.094107			91384.198


Server		AvgDailyDataChangeMB
TDXHLWSQL01	14537.878085
TDXHLWSQL02	2645.164287
TDXHLWSQL03	4000.791821
TDXHLWSQL06 - no Differential backups
TDXHLWSQL06\ETC	1353.067321
TDXHLWSQL07	21561.094107


Server	MaxDailyDataChangeMB

TDXHLWSQL07	21286.734920

*/