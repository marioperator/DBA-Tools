/* 
MSSQL 2016 Health Check

Checks best practises for large databases.

v1  	- 14-05-2018 - Initial release
*/

DECLARE @log_warnings bit           = 0 -- Set to 1 to log warnings to SQL Server Log and Windows Event Log
      , @msg          nvarchar(440)

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
SET NOCOUNT ON

SELECT SERVERPROPERTY('MachineName') AS ServerName
     , SERVERPROPERTY('ServerName') AS ServerInstanceName
     , SERVERPROPERTY('InstanceName') AS Instance
     , SERVERPROPERTY('Edition') AS Edition
     , SERVERPROPERTY('ProductVersion') AS ProductVersion
     , LEFT(@@Version, CHARINDEX('-', @@version)-2) AS VersionName

-- System settings
/*
SQL Server service account must not have the ‘lock pages in memory’ priviledge on servers that host other mission-critical applications.

Locked pages in memory pros:
- SQL Server working set (BPOOL) cannot be paged by windows even when there is system wide memory pressure.

Locked pages in memory cons:
- Operating system will starve for memory when there is system wide memory pressure. 
- OS has to completely rely on SQL Server to respond to low memory notification and scale down its memory usage. 
- SQL Server may not respond fast enough to low memory condition at system level because OS is already starving for memory. 
 -LPIM prevents only the BPOOL from paging, Non-Bpool components can still be paged and we have critical portions 
    of SQL Server memory like thread stack, SQL Server Images/DLL’s  in Non-Bpool which can still be paged by OS.
*/
DECLARE @locked_page_allocations_kb int
SELECT @locked_page_allocations_kb = isnull(locked_page_allocations_kb, 0)
FROM sys.dm_os_process_memory
IF @locked_page_allocations_kb<>0
BEGIN
 SELECT @msg = 'The SQL Server service account '''+service_account+''' seems to have the ''Lock pages in memory'' group policy enabled.'
 FROM sys.dm_server_services
 WHERE servicename LIKE 'Sql Server (%'
 IF @log_warnings=1
 BEGIN
  RAISERROR(@msg, 15, 1) WITH LOG, NOWAIT
 END
 SELECT @msg AS Warning
 UNION ALL
 SELECT 'Consider disabling lock pages in memory if other mission-critical applications are hosted on the same machine as SQL Server'

 SELECT 'Disable the ''Lock pages in memory'' Windows group policy for the SQL Server service account '''+service_account+'''' AS Fix
 FROM sys.dm_server_services
 WHERE servicename LIKE 'Sql Server (%'
END
ELSE
BEGIN
 SELECT 'SQL Server service account does not have the ‘lock pages in memory’ priviledge.' AS Ok
END

-- Server settings
/*	
Maximum memory allocated for SQL server must leave sufficient memory for OS.

Calculate max. memory for SQL Server like this:
Total memory 
- 1 GB for OS 
- 4 GB for OS the first 16 GB memory
- 1 GB for OS for every additional 8 GB memory
*/
DECLARE @system_memory                 int
      , @server_max_memory             int
      , @recommended_server_max_memory int
SELECT @system_memory = total_physical_memory_kb / 1000
FROM sys.dm_os_sys_memory
SELECT @server_max_memory = CONVERT(int, value)
FROM sys.configurations
WHERE name LIKE 'max server memory%'

SELECT @recommended_server_max_memory = @system_memory - (1000 + CASE WHEN @system_memory>=16000 THEN 4000 ELSE 0 END + ((@system_memory - 16000) / 8000) * 1000)

IF ABS(@server_max_memory - @recommended_server_max_memory)>1000
BEGIN
 SELECT @msg = 'System memory is '+CAST(@system_memory AS nvarchar(10))+' MB, server max memory is '+CAST(@server_max_memory AS nvarchar(10))+' MB, it should be '+CAST(@recommended_server_max_memory AS nvarchar(10))+' MB'
 IF @log_warnings=1
 BEGIN
  RAISERROR(@msg, 15, 1) WITH LOG, NOWAIT
 END

 SELECT @msg AS Warning
 SELECT 'EXEC sp_configure ''max server memory'', '+CAST(@recommended_server_max_memory AS nvarchar(10)) AS Fix
 UNION
 SELECT 'RECONFIGURE'
END
ELSE
BEGIN
 SELECT 'Maximum memory allocated for SQL server leaves sufficient memory for the OS.' AS Ok
 UNION ALL
 SELECT 'System memory is '+CAST(@system_memory AS nvarchar(10))+' MB, server max memory is '+CAST(@server_max_memory AS nvarchar(10))+' MB' AS Ok
END

/*
These traceflags must be set for the instance: 1118, 1117, 2371, 4199.

These flags are ignored in SQL Server 2016 or higher:
TF1117 - When growing a data file grow all files at the same time so they remain the same size, reducing allocation contention points.
TF1118 - When doing allocations for user tables always allocate full extents.  Reducing contention of mixed extent allocations

This flag must be set if auto update stats is enabled:
TF2371 - Alters the behavior of auto update statistics so that it triggers at a lower percentage threshold. 

TF4199 - Enables many other query optimizer fixes. See the full list here: https://support.microsoft.com/en-us/help/974006/sql-server-query-optimizer-hotfix-trace-flag-4199-servicing-model


TF9481 - Disable New Cardinality Estimation. Whenever there is any upgrade done to SQL Server 2014 and higher and slow performance issue is reported, this is a trace flag to consider. 
		 TF2312 has the reverse behavior, forcing the query optimizer to use the new CE, even if the database compatibility is set to value lower than 120 (SQL Server 2014)
*/
DECLARE @tracestatus TABLE(TraceFlag nvarchar(40)
                         , Status    tinyint
                         , GLOBAL    tinyint
                         , SESSION   tinyint)

INSERT INTO @tracestatus
EXEC ('DBCC TRACESTATUS')

IF CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(2))<'13' -- No need to set traceflags 1117 and 1118 in SQL Server  2016 or higher
BEGIN
 IF NOT EXISTS(SELECT 1
               FROM @tracestatus
               WHERE TraceFlag='1117' AND
                     Status=1)
 BEGIN
  SELECT @msg = 'Trace flag 1117 should be set'
  IF @log_warnings=1
  BEGIN
   RAISERROR(@msg, 15, 1) WITH LOG, NOWAIT
  END
  SELECT @msg AS Warning
  SELECT 'DBCC TRACEON(1117, -1); DBCC FREEPROCCACHE' AS Fix
 END
 ELSE
 BEGIN
  SELECT 'Trace flag 1117 is set' AS Ok
 END

 IF NOT EXISTS(SELECT 1
               FROM @tracestatus
               WHERE TraceFlag='1118' AND
                     Status=1)
 BEGIN
  SELECT @msg = 'Trace flag 1118 should be set'
  IF @log_warnings=1
  BEGIN
   RAISERROR(@msg, 15, 1) WITH LOG, NOWAIT
  END
  SELECT @msg AS Warning
  SELECT 'DBCC TRACEON(1118, -1); DBCC FREEPROCCACHE' AS Fix
 END
 ELSE
 BEGIN
  SELECT 'Trace flag 1118 is set' AS Ok
 END
END

IF EXISTS(SELECT 1
          FROM sys.databases
          WHERE name=DB_NAME() AND
                compatibility_level>110 AND
                is_auto_update_stats_on=1)
BEGIN
 IF NOT EXISTS(SELECT 1
               FROM @tracestatus
               WHERE TraceFlag='2371' AND
                     Status=1)
 BEGIN
  SELECT @msg = 'Trace flag 2371 should be set'
  IF @log_warnings=1
  BEGIN
   RAISERROR(@msg, 15, 1) WITH LOG, NOWAIT
  END
  SELECT @msg AS Warning
  SELECT 'DBCC TRACEON(2371, -1); DBCC FREEPROCCACHE' AS Fix
 END
 ELSE
 BEGIN
  SELECT 'Trace flag 2371 is set' AS Ok
 END
END

IF NOT EXISTS(SELECT 1
              FROM @tracestatus
              WHERE TraceFlag='4199' AND
                    Status=1)
BEGIN
 SELECT @msg = 'Trace flag 4199 should be set'
 IF @log_warnings=1
 BEGIN
  RAISERROR(@msg, 15, 1) WITH LOG, NOWAIT
 END
 SELECT @msg AS Warning
 SELECT 'DBCC TRACEON(4199, -1); DBCC FREEPROCCACHE' AS Fix
END
ELSE
BEGIN
 SELECT 'Trace flag 4199 is set' AS Ok
END

/*
Server option 'optimize for ad hoc workloads' must be set to 1.

Motivation:
This is used to improve the efficiency of the plan cache for workloads that contain many single use ad hoc batches. 
When this option is set to 1, the Database Engine stores a small compiled plan stub in the plan cache when a batch is compiled for the first time, instead of the full compiled plan. 
This helps to relieve memory pressure by not allowing the plan cache to become filled with compiled plans that are not reused.
*/
IF NOT EXISTS(SELECT *
              FROM sys.configurations
              WHERE name='optimize for ad hoc workloads' AND
                    Value=1)
BEGIN
 SELECT @msg = 'Option ''ptimize for ad hoc workloads'' should be set'
 SELECT @msg AS Warning
 IF @log_warnings=1
 BEGIN
  RAISERROR(@msg, 15, 1) WITH LOG, NOWAIT
 END
 SELECT 'sp_configure ''optimize for ad hoc workloads'', 1' AS Fix
 UNION ALL
 SELECT 'GO'
 UNION ALL
 SELECT 'RECONFIGURE'
 UNION ALL
 SELECT 'GO'
END
ELSE
BEGIN
 SELECT 'Server option ''optimize for ad hoc workloads'' is set to 1' AS Ok
END

-- Database settings
DECLARE @db_name nvarchar(128) = DB_NAME()
EXEC sp_helpdb @db_name

IF OBJECT_ID('tblMfScInstallation') IS NULL
BEGIN
 SELECT 'You are running this script on database '+DB_NAME()+'. This script is intended for Mosaic databases.' AS Warning
 SELECT 'USE [Mosaic database name]' AS Fix
END
ELSE
BEGIN
 SELECT *
 FROM tblMfScInstallation
 WHERE Latest=1
END

/* 
The database collation must be equal to the server collation
*/
DECLARE @db_collation nvarchar(128)
DECLARE @server_collation nvarchar(128)= CAST(SERVERPROPERTY('Collation') AS nvarchar(128))

SELECT @db_collation = collation_name
FROM sys.databases
WHERE name=@db_name

IF @db_collation<>@server_collation
BEGIN
 SELECT @msg = 'Database '+@db_name+' collation is '+@db_collation+', consider changing it to server collation ' + @server_collation
 SELECT @msg AS Warning
 IF @log_warnings=1
 BEGIN
  RAISERROR(@msg, 15, 1) WITH LOG, NOWAIT
 END
END
ELSE
BEGIN
 SELECT 'Database collation must be equal to server collation' AS Ok
END

/*
The database compatibility level must be the highest supported by the server product version.

Motivation:
- Get the latest and greatest version
- Align with Microsoft support
*/
DECLARE @server_comp_level nvarchar(128)= LEFT(CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(128)), 2)+'0'

DECLARE @database_comp_level int

SELECT @database_comp_level = compatibility_level
FROM sys.databases
WHERE name=@db_name

IF CAST(@server_comp_level AS int)<>@database_comp_level
BEGIN
 SELECT @msg = 'The database compatibility level must the highest supported by the server product version. The current CL is '+CAST(@database_comp_level AS nvarchar(10))+' it should be '+CAST(@server_comp_level AS nvarchar(3))
 SELECT @msg AS Warning
 IF @log_warnings=1
 BEGIN
  RAISERROR(@msg, 15, 1) WITH LOG, NOWAIT
 END

 SELECT 'ALTER DATABASE CURRENT SET COMPATIBILITY_LEVEL = '+@server_comp_level AS Fix
END
ELSE
BEGIN
 SELECT 'The database compatibility level '+CAST(@database_comp_level AS nvarchar(10))+' is the highest supported by the server product version '+CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(128)) AS Ok
END

/*
Check that the database has been backed up within the last 7 days
*/
declare @daysSinceLastBackup int

SELECT @daysSinceLastBackup = DATEDIFF(day, MAX(msdb.dbo.backupset.backup_finish_date), current_timestamp)
FROM msdb.dbo.backupset
WHERE msdb..backupset.type='D' AND
      msdb.dbo.backupset.database_name=@db_name

IF @daysSinceLastBackup>7
BEGIN
 SELECT @msg = 'Database was not backed up within the last 7 days. Check backup configuration.'
 SELECT @msg AS Warning
 IF @log_warnings=1
 BEGIN
  RAISERROR(@msg, 15, 1) WITH LOG, NOWAIT
 END
END
ELSE
BEGIN
 SELECT 'Database backup recovery model must be FULL' AS Ok
END

/*
Log file must auto grow by 1 GB

Motivation:
When using the default setting 10% auto growth for the log file, the auto-growth amount would get bigger as the database got larger.
It is therefore recommended to use a numerical growth rate so that the log file disk does not run full.
*/
DECLARE @growth            int
      , @is_percent_growth int
      , @name              sysname
SELECT @growth = isnull(growth, 0)
     , @is_percent_growth = is_percent_growth
     , @name = name
FROM sys.database_files
WHERE type_desc='LOG'
IF @growth<120000 OR
   @growth>140000 OR
   @is_percent_growth=1
BEGIN
 SELECT @msg = 'Log file auto growth is '+CAST(@growth AS nvarchar(10))+CASE @is_percent_growth WHEN 1 THEN '%' ELSE '' END+', consider using auto growth by 1 GB'
 SELECT @msg AS Warning
 IF @log_warnings=1
 BEGIN
  RAISERROR(@msg, 15, 1) WITH LOG, NOWAIT
 END

 SELECT 'ALTER DATABASE CURRENT MODIFY FILE (NAME='+@name+',FILEGROWTH=1000MB)' AS Fix
END
ELSE
BEGIN
 SELECT 'Log file is set to auto grow by 1 GB' AS Ok
END

/*
Check database files.
*/
DECLARE @databasefiles_ok bit = 1
DECLARE @disks TABLE(db_name            sysname
                   , physical_name      nvarchar(max)
                   , volume_mount_point nvarchar(5)
                   , type_desc          nvarchar(10)
                   , state_desc         nvarchar(25)
                   , size               bigint
                   , max_size           bigint
                   , growth             bigint
                   , is_percent_growth  bit
                   , total_bytes        bigint
                   , available_bytes    bigint
                   , free_space_percent float)

INSERT INTO @disks
SELECT DB_NAME(f.database_id)
     , physical_name
     , volume_mount_point
     , type_desc
     , state_desc
     , size
     , max_size
     , growth
     , is_percent_growth
     , total_bytes
     , available_bytes
     , available_bytes * 100.0 / total_bytes
FROM
  sys.master_files AS f
CROSS APPLY
  sys.dm_os_volume_stats(f.database_id, f.file_id) AS s
WHERE DB_NAME(f.database_id) IN('master'
                              , 'model'
                              , 'msdb'
                              , 'distribution'
                              , 'tempdb'
                              , DB_NAME())

DECLARE @tempdb_files int
      , @cpu_count    int

SELECT @cpu_count = cpu_count
FROM sys.dm_os_sys_info

SELECT @tempdb_files = COUNT(*)
FROM @disks
WHERE type_desc='ROWS' AND
      db_name='tempdb'

IF @tempdb_files<=1 AND
   @cpu_count>1
BEGIN
 SELECT @msg = 'tempdb database should span more than 1 file. Consider increasing the number of tempdb files to '+CAST(@cpu_count AS nvarchar(3))
 SELECT @msg AS Warning
 IF @log_warnings=1
 BEGIN
  RAISERROR(@msg, 15, 1) WITH LOG, NOWAIT
 END
 SET @databasefiles_ok = 0
END

IF @tempdb_files>@cpu_count
BEGIN
 SELECT @msg = 'tempdb database spans '+CAST(@tempdb_files AS nvarchar(3))+' files. This is more than the number of server CPU cores; '+CAST(@tempdb_files AS nvarchar(3))+'. Consider decreasing the number of tempdb files.'
 SELECT @msg AS Warning
 IF @log_warnings=1
 BEGIN
  RAISERROR(@msg, 15, 1) WITH LOG, NOWAIT
 END
 SET @databasefiles_ok = 0
END

SET @msg = NULL
SELECT @msg = COALESCE(@msg+' ', '')+'Volume '+volume_mount_point+' has '+CAST(MIN(free_space_percent) AS nvarchar(25))+' % free space.'
FROM @disks
WHERE free_space_percent<15.0
GROUP BY volume_mount_point

IF @msg IS NOT NULL
BEGIN
 SELECT @msg AS Warning
 IF @log_warnings=1
 BEGIN
  RAISERROR(@msg, 15, 1) WITH LOG, NOWAIT
 END
 SET @databasefiles_ok = 0
END

SET @msg = NULL
SELECT @msg = COALESCE(@msg+' ', '')+db_name+CASE type_desc WHEN 'LOG' THEN ' log' ELSE '' END+' file set to '+CAST(growth AS nvarchar(25))+'% growth.'
FROM @disks
WHERE is_percent_growth=1

IF @msg IS NOT NULL
BEGIN
 SET @msg = @msg+' Consider using fixed size growth instead.'
 SELECT @msg AS Warning
 IF @log_warnings=1
 BEGIN
  RAISERROR(@msg, 15, 1) WITH LOG, NOWAIT
 END
 SET @databasefiles_ok = 0
END

DECLARE @sysdb_vol  nvarchar(5)
      , @tempdb_vol nvarchar(5)
      , @userdb_vol nvarchar(5)

SELECT @sysdb_vol = volume_mount_point
FROM @disks
WHERE db_name='master' AND
      type_desc='ROWS'

SELECT @tempdb_vol = volume_mount_point
FROM @disks
WHERE db_name='tempdb' AND
      type_desc='ROWS'

SELECT @userdb_vol = volume_mount_point
FROM @disks
WHERE db_name=DB_NAME() AND
      type_desc='ROWS'

IF @sysdb_vol=@tempdb_vol OR
   @sysdb_vol=@userdb_vol OR
   @tempdb_vol=@userdb_vol
BEGIN
 SELECT @msg = 'Consider using separate drives for system databases ('+@sysdb_vol+'), temp database ('+@tempdb_vol+') and user databases ('+@userdb_vol+').'
 SELECT @msg AS Warning
 IF @log_warnings=1
 BEGIN
  RAISERROR(@msg, 15, 1) WITH LOG, NOWAIT
 END
 SET @databasefiles_ok = 0
END

SET @msg = NULL
SELECT @msg = COALESCE(@msg+' ', '')+db_name+CASE type_desc WHEN 'LOG' THEN ' log' ELSE '' END+' file.'
FROM @disks
WHERE volume_mount_point='C:\'

IF @msg IS NOT NULL
BEGIN
 SET @msg = 'These files seems to be placed on drive C:\. Database files must not be placed on the OS disk. Consider moving '+@msg
 SELECT @msg AS Warning
 IF @log_warnings=1
 BEGIN
  RAISERROR(@msg, 15, 1) WITH LOG, NOWAIT
 END
 SET @databasefiles_ok = 0
END

IF @databasefiles_ok=1
BEGIN
 SELECT 'database fiels look OK.' AS Ok
END
ELSE
BEGIN
 SELECT *
 FROM @disks
END

/*
Database option AUTO_CLOSE must be OFF.

Motivation:
When AUTO_CLOSE is set ON, it causes performance degradation on heavily used databases by increasing overhead of opening and closing the database after each connection. 
Additionally, when it is ON, it also flushes (removes) the procedure cache after each connection. 
There are very rare scenarios when you would need this particular setting on, otherwise in most of the cases, it is a good idea to leave it OFF.
*/
DECLARE @is_auto_close_on int

SELECT @is_auto_close_on = isnull(is_auto_close_on, 0)
FROM sys.databases
WHERE name=@db_name

IF @is_auto_close_on<>0
BEGIN
 SELECT @msg = 'Database option AUTO_CLOSE should be OFF'
 SELECT @msg AS Warning
 IF @log_warnings=1
 BEGIN
  RAISERROR(@msg, 15, 1) WITH LOG, NOWAIT
 END

 SELECT 'ALTER DATABASE CURRENT SET AUTO_CLOSE OFF' AS Fix
END
ELSE
BEGIN
 SELECT 'Database option AUTO_CLOSE is OFF' AS Ok
END

/*
Database option AUTO_CREATE_STATISTICS must be ON.

Motivation:
- The statistics are automatically created for each new index.
- The statistics are automatically created for non-indexed columns that are used in your queries.
*/
DECLARE @is_auto_create_stats_on int

SELECT @is_auto_create_stats_on = is_auto_create_stats_on
FROM sys.databases
WHERE name=@db_name

IF @is_auto_create_stats_on<>1
BEGIN
 SELECT @msg = 'Database option AUTO_CREATE_STATISTICS should be ON'
 SELECT @msg AS Warning
 IF @log_warnings=1
 BEGIN
  RAISERROR(@msg, 15, 1) WITH LOG, NOWAIT
 END

 SELECT 'ALTER DATABASE CURRENT SET AUTO_CREATE_STATISTICS ON' AS Fix
END
ELSE
BEGIN
 SELECT 'Database option AUTO_CREATE_STATISTICS is ON' AS Ok
END

/*
Database option AUTO_UPDATE_STATISTICS must be OFF.

Motivation:
This recommendation is actually NOT aligned with Microsoft support.
Microsoft best practice for SQL 2016 and higher is to leave auto update stats on.
The problem is that auto update stats use a very low sampling rate (< 1%) with very large tables.
A low sampling rate may not provide a sufficient stsatistical basis for cardinality estimation, and can therefore cause ineffective execution plans.
When AUTO_UPDATE_STATISTICS is set to OFF, maintenance tasks must be set up to update statistics periodically.
*/
DECLARE @is_auto_update_stats_on int

SELECT @is_auto_update_stats_on = isnull(is_auto_update_stats_on, 0)
FROM sys.databases
WHERE name=@db_name

IF @is_auto_update_stats_on<>0
BEGIN
 SELECT @msg = 'Database option AUTO_UPDATE_STATISTICS should be OFF'
 SELECT @msg AS Warning
 IF @log_warnings=1
 BEGIN
  RAISERROR(@msg, 15, 1) WITH LOG, NOWAIT
 END

 SELECT 'ALTER DATABASE CURRENT SET AUTO_UPDATE_STATISTICS OFF' AS Fix
END
ELSE
BEGIN
 SELECT 'Database option AUTO_UPDATE_STATISTICS is OFF' AS Ok
END

/*
Database option AUTO_SHRINK must be OFF

Motivation:
Auto shrinking the database comes with a performance hit.
If you know that the space that you are reclaiming will not be needed in the future, you can reclaim the space by manually shrinking the database.
*/
DECLARE @is_auto_shrink_on int

SELECT @is_auto_shrink_on = isnull(is_auto_shrink_on, 0)
FROM sys.databases
WHERE name=@db_name

IF @is_auto_shrink_on<>0
BEGIN
 SELECT @msg = 'Database option AUTO_SHRINK should be OFF'
 SELECT @msg AS Warning
 IF @log_warnings=1
 BEGIN
  RAISERROR(@msg, 15, 1) WITH LOG, NOWAIT
 END

 SELECT 'ALTER DATABASE CURRENT SET AUTO_SHRINK OFF' AS Fix
END
ELSE
BEGIN
 SELECT 'Database option AUTO_SHRINK is OFF' AS Ok
END

-- Maintenance tasks
/*
All statistics must be updated on work days with at least 10% sampling.
All statistics must be updated every saturday with fullscan.
All statistics for filtered indexes must be updated daily with fullscan (due to a bug in SQL Server 2016)

Motivation:
This recommendation is actually NOT aligned with Microsoft support.
Microsoft best practice for SQL 2016 and higher is to leave auto update stats on.
The problem is that auto update stats use a very low sampling rate (< 1%) with very large tables.
It is therefore recommended to run periodic maintenance tasks that update stats.

It seems there is a bug in SQL Server 2016, product version 13.0.4451.0:
When running UPDATE STATISTICS table(stat) WITH SAMPLE >14 PERCENT, the stat propery rows = unfiltered rows,
this causes the optimizer to create ineffective query plans.
*/
-- Threshold value NULL means take all stats
DECLARE @days_old_threshold        int     = CASE DATEPART(weekday, current_timestamp) WHEN 2 THEN 2 ELSE 1 END
      , @modifications_threshold   int     = NULL
      , @sample_percent_threshold  float   = 9.9
      , @sample_percent_for_update int     = 10
      , @table_filter              sysname = NULL
      , @persist_sample_percent    bit     = 0

DECLARE @outdated_statistics TABLE(table_name           sysname
                                 , column_name          sysname
                                 , has_filter           bit
                                 , filter_definition    nvarchar(max)
                                 , stat_name            sysname
                                 , auto_created         bit
                                 , user_created         bit
                                 , last_updated         datetime NULL
                                 , days_old             int NULL
                                 , rows                 int NULL
                                 , rows_sampled         int NULL
                                 , modification_counter bigint NULL
                                 , sampled_percent      float NULL)

INSERT INTO @outdated_statistics
SELECT OBJECT_NAME(s.object_id) AS table_name
     , c.name AS column_name
     , s.has_filter
     , s.filter_definition
     , s.name AS stat_name
     , s.auto_created
     , s.user_created
     , stp.last_updated
     , DATEDIFF(d, STATS_DATE(s.object_id, s.stats_id), GETDATE()) AS days_old
     , stp.rows
     , stp.rows_sampled
     , stp.modification_counter
     , stp.rows_sampled * 100.0 / stp.rows AS sampled_percent
FROM
  sys.stats AS s
JOIN
  sys.stats_columns AS sc
ON sc.object_id=s.object_id AND
   sc.stats_id=s.stats_id
JOIN
  sys.columns AS c
ON c.object_id=sc.object_id AND
   c.column_id=sc.column_id
CROSS APPLY
  sys.dm_db_stats_properties(s.object_id, s.stats_id) AS stp
WHERE OBJECTPROPERTY(s.OBJECT_ID, 'IsUserTable')=1 AND
      (@table_filter IS NULL OR OBJECT_NAME(s.object_id) LIKE '%'+@table_filter+'%') AND
      (
		(@days_old_threshold IS NOT NULL AND stp.last_updated IS NOT NULL AND DATEDIFF(d, stp.last_updated, GETDATE())>@days_old_threshold) OR
		(@modifications_threshold IS NOT NULL AND stp.modification_counter>@modifications_threshold) OR
		(@sample_percent_threshold IS NOT NULL AND stp.rows_sampled * 100.0 / stp.rows<@sample_percent_threshold) OR 
		(@days_old_threshold IS NULL AND @sample_percent_threshold IS NULL AND @sample_percent_threshold IS NULL)
	  )
ORDER BY table_name
       , column_name
       , stat_name

IF EXISTS(SELECT 1
          FROM @outdated_statistics)
BEGIN
 SELECT @msg = 'Statistics seems to be outdated. Consider updating statistics.'
 SELECT @msg AS Warning
 IF @log_warnings=1
 BEGIN
  RAISERROR(@msg, 15, 1) WITH LOG, NOWAIT
 END

 SELECT *
 FROM @outdated_statistics
 ORDER BY table_name
        , column_name

 SELECT 'UPDATE STATISTICS '+table_name+' WITH '+CASE has_filter WHEN 1 THEN 'FULLSCAN' ELSE 'SAMPLE '+CAST(@sample_percent_for_update AS nvarchar(3))+' PERCENT' END+CASE @persist_sample_percent WHEN 1 THEN ', PERSIST_SAMPLE_PERCENT = ON' ELSE '' END AS Fix
 FROM(SELECT table_name
           , MAX(isnull(CAST(has_filter AS int), 0)) AS has_filter
           , MIN(last_updated) AS last_updated
      FROM @outdated_statistics
      GROUP BY table_name) AS t
 ORDER BY table_name

END
ELSE
BEGIN
 SELECT 'Statistics seems to be updated' AS Ok
END

/*
Rebuild indexes with fragmentation > 30% followed by reorganize indexes with fragmentation > 15% weekly

Rebuild indexes pros:
- Defragments all levels of the index – leaf and intermediate pages
- Also updates statistics on the table with a FULLSCAN of all the data (only tables with >30% fragmentation is processed)
- Reapplies options such as fillfactor and compression, and gives you the option to change those settings.
- Minimal logging is available under some recovery models
Rebuild indexes cons:
- Single threaded only in Standard Edition
- Rollbacks can be long and excruciating when rebuild fails or is cancelled
- Causes queries to generate new execution plans when they run again

Regorganize indexes pros:
- Tends to “trickle” changes into the log more slowly (a pro only for specific situations)	
- Fully online in every edition	
- If cancelled or killed, it just stops where it is — no giant rollback.	
- Does not cause plan recompilation	
- Honors/reapplies existing settings such as fillfactor and compression	
Regorganize indexes cons:
- Single threaded only – regardless of edition — so it’s slower.
- Defragments only the leaf level of the index
- Does not update statistics – you have to manage that yourself
- Does not allow you to change settings such as fillfactor and compression
*/
DECLARE @fragmented_indexes TABLE(table_name                   sysname
                                , index_name                   sysname
                                , avg_fragmentation_in_percent float
                                , page_count                   float)
INSERT INTO @fragmented_indexes
SELECT dbtables.name
     , isnull(dbindexes.name, 'HEAP')
     , indexstats.avg_fragmentation_in_percent
     , page_count
FROM
  sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, NULL) AS indexstats
INNER JOIN
  sys.tables AS dbtables
ON dbtables.object_id=indexstats.object_id
INNER JOIN
  sys.schemas AS dbschemas
ON dbtables.schema_id=dbschemas.schema_id
INNER JOIN
  sys.indexes AS dbindexes
ON dbindexes.object_id=indexstats.object_id AND
   indexstats.index_id=dbindexes.index_id
WHERE indexstats.avg_fragmentation_in_percent>30 AND
      page_count>1000 AND
      index_type_desc<>'HEAP'

IF EXISTS(SELECT 1
          FROM @fragmented_indexes)
BEGIN
 SELECT @msg = 'There seems to be fragmented indexes, consider rebuilding indexes'
 SELECT @msg AS Warning
 IF @log_warnings=1
 BEGIN
  RAISERROR(@msg, 15, 1) WITH LOG, NOWAIT
 END

 SELECT *
 FROM @fragmented_indexes
 ORDER BY avg_fragmentation_in_percent DESC
END
ELSE
BEGIN
 SELECT 'Indexes does not seem to fragmented' AS Ok
END

/*
Scan for fragmented heaps.

Motivation:
If you have fragmented heaps with no clustered index on the primary key, you can defrag them by creating and then dropping a clustered index on the primary key.
You should consider using clustered index as a permanent solution
*/
DECLARE @fragmented_heaps TABLE(table_name                   sysname
                              , index_name                   sysname
                              , avg_fragmentation_in_percent float
                              , page_count                   float)
INSERT INTO @fragmented_heaps
SELECT dbtables.name
     , isnull(dbindexes.name, 'HEAP')
     , indexstats.avg_fragmentation_in_percent -- This is the percentage of out-of-order extents in the leaf pages of a heap. An out-of-order extent is one for which the extent that contains the current page for a heap is not physically the next extent after the extent that contains the previous page.
     , page_count
FROM
  sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, NULL) AS indexstats
INNER JOIN
  sys.tables AS dbtables
ON dbtables.object_id=indexstats.object_id
INNER JOIN
  sys.schemas AS dbschemas
ON dbtables.schema_id=dbschemas.schema_id
INNER JOIN
  sys.indexes AS dbindexes
ON dbindexes.object_id=indexstats.object_id AND
   indexstats.index_id=dbindexes.index_id
WHERE indexstats.avg_fragmentation_in_percent>30 AND
      page_count>1000 AND
      index_type_desc='HEAP'

IF EXISTS(SELECT 1
          FROM @fragmented_heaps)
BEGIN
 SELECT @msg = 'There seems to be fragmented heaps, consider adding and then dropping clustered indexes for the heaps'
 SELECT @msg AS Warning
 IF @log_warnings=1
 BEGIN
  RAISERROR(@msg, 15, 1) WITH LOG, NOWAIT
 END

 SELECT *
 FROM @fragmented_heaps
 ORDER BY avg_fragmentation_in_percent DESC

 DECLARE curHeaps CURSOR
 FOR SELECT table_name
     FROM @fragmented_heaps
     ORDER BY avg_fragmentation_in_percent DESC

 DECLARE @fix TABLE(Fix nvarchar(max))
 DECLARE @table_name sysname

 OPEN curHeaps
 FETCH NEXT FROM curHeaps INTO @table_name
 WHILE @@FETCH_STATUS=0
 BEGIN
  DECLARE @pk_cols varchar(max) = NULL
  DECLARE @temp_index varchar(max)
  SELECT @pk_cols = COALESCE(@pk_cols+',', '')+c.COLUMN_NAME
  FROM
    INFORMATION_SCHEMA.TABLE_CONSTRAINTS AS p
  INNER JOIN
    INFORMATION_SCHEMA.KEY_COLUMN_USAGE AS c
  ON c.TABLE_NAME=p.TABLE_NAME AND
     c.CONSTRAINT_NAME=p.CONSTRAINT_NAME
  INNER JOIN
    INFORMATION_SCHEMA.COLUMNS AS cls
  ON c.TABLE_NAME=cls.TABLE_NAME AND
     c.COLUMN_NAME=cls.COLUMN_NAME
  WHERE CONSTRAINT_TYPE='PRIMARY KEY' AND
        c.TABLE_NAME=@table_name
  ORDER BY c.ORDINAL_POSITION

  SET @temp_index = 'IX_'+@table_name+'_'+replace(CAST(NEWID() AS nvarchar(128)), '-', '_')+'_TEMP'

  INSERT INTO @Fix
  SELECT 'CREATE CLUSTERED INDEX '+@temp_index+' ON '+@table_name+'('+@pk_cols+')'
  UNION ALL
  SELECT 'GO'
  UNION ALL
  SELECT 'DROP INDEX '+@table_name+'.'+@temp_index
  UNION ALL
  SELECT 'GO'
  FETCH NEXT FROM curHeaps INTO @table_name
 END -- WHILE
 CLOSE curHeaps
 DEALLOCATE curHeaps

 SELECT *
 FROM @Fix
END
ELSE
BEGIN
 SELECT 'Heaps does not seem to fragmented' AS Ok
END

/*
Server fill factor should be the default value 0 or 100 %

Motivation:
If you absolutely must change fill factor, it should be considered on induvidual indexes, not server-wide.
*/
DECLARE @server_fill_factor int

SELECT @server_fill_factor = CONVERT(int, value_in_use)
FROM sys.configurations
WHERE name='fill factor (%)'

IF NOT @server_fill_factor IN(0, 100)
BEGIN
 SELECT @msg = 'Server fill factor is '+CAST(@server_fill_factor AS nvarchar(3))+'%. Should be default value 0 or 100 %'
 SELECT @msg AS Warning
 IF @log_warnings=1
 BEGIN
  RAISERROR(@msg, 15, 1) WITH LOG, NOWAIT
 END
END
ELSE
BEGIN
 SELECT 'Server fill factor is default 100 %' AS Ok
END

/*
Check frequently updated tables, without clustered index, that have an index with fill factor > 70 % and > 100 page splits. 

Motivation:
Based on advice from http://www.itprotoday.com/what-best-value-fill-factor-index-fill-factor-and-performance-part-2

Disclaimer:
Consider changes to fill factor carefully! Escpecially if your goal is to reduce fragmentation.
The problem is that fill factor only gets applied when you rebuild an index, and you need to rebuild or reorg to apply that fill factor, and that lower fill factor is… Fragmentation!
*/
DECLARE @page_plits_sec bigint

SELECT @page_plits_sec = cntr_value
FROM MASTER.dbo.sysperfinfo
WHERE counter_name='Page Splits/sec' AND
      OBJECT_NAME LIKE '%Access methods%'

DECLARE @indexes TABLE(table_name            sysname
                     , index_name            sysname
                     , leaf_allocation_count bigint -- Cumulative count of leaf-level page allocations in the index or heap. For an index, a page allocation corresponds to a page split.
                     , leaf_insert_count     bigint
                     , leaf_update_count     bigint
                     , leaf_delete_count     bigint
                     , fill_factor           tinyint)

INSERT INTO @indexes
SELECT OBJECT_NAME(ios.object_id)
     , i.name
     , ios.leaf_allocation_count
     , ios.leaf_insert_count
     , ios.leaf_update_count
     , ios.leaf_delete_count
     , i.fill_factor
FROM
  SYS.DM_DB_INDEX_OPERATIONAL_STATS(DB_ID(N'DB_NAME'), NULL, NULL, NULL) AS IOS
JOIN
  SYS.INDEXES AS I
ON IOS.INDEX_ID=I.INDEX_ID AND
   IOS.OBJECT_ID=I.OBJECT_ID
JOIN
  SYS.OBJECTS AS O
ON IOS.OBJECT_ID=O.OBJECT_ID
WHERE ios.index_id<>0 AND
      OBJECTPROPERTY(i.object_id, 'IsUserTable')=1 AND
      i.name NOT LIKE 'sys%' AND
      OBJECT_NAME(i.object_id) NOT LIKE 'sys%' AND
      leaf_allocation_count>100 AND
      leaf_allocation_count * 1.0 / (leaf_insert_count + leaf_update_count + leaf_delete_count + 1)>.1 AND
      (fill_factor=0 OR
       fill_factor>70) AND
      NOT EXISTS(SELECT TOP 1 1
                 FROM sys.indexes
                 WHERE object_id=ios.object_id AND
                       index_id=1 AND
                       is_primary_key=1)

IF EXISTS(SELECT 1
          FROM @indexes)
BEGIN
 SELECT @msg = 'There seems to be frequently updated tables, without clustered index on primary key, that have an index with fill factor > 70 percent and > 100 page splits. Consider lowering the fill factor for these indexes with 10 percent and then review page splits after some time. Page splits per second is '+CAST(@page_plits_sec AS nvarchar(25))
 IF @log_warnings=1
 BEGIN
  RAISERROR(@msg, 15, 1) WITH LOG, NOWAIT
 END

 SELECT @msg AS Warning

 SELECT *
 FROM @indexes
 ORDER BY leaf_allocation_count DESC

 SELECT 'ALTER INDEX '+index_name+' ON '+table_name+' REBUILD PARTITION = ALL WITH (FILLFACTOR= '+CAST(CASE fill_factor WHEN 0 THEN 100 ELSE fill_factor END - 10 AS nvarchar(3))+')' AS Fix
 FROM @indexes
 ORDER BY leaf_allocation_count DESC
END
ELSE
BEGIN
 SELECT 'Checked for frequently updated tables, without clustered index on primary key, that have an index with fill factor > 70 % and > 100 page splits.' AS Ok
END
GO