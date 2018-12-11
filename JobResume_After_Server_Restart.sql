DECLARE @i INT --Iterator
DECLARE @iRwCnt INT --Rowcount
DECLARE @jobname NVARCHAR(300)
DECLARE @stepname NVARCHAR(100)
DECLARE @day INT
DECLARE @hr INT

SET @i = 1 --Initialize
SET @day = (SELECT CAST(CONVERT(CHAR(8), sqlserver_start_time, 112) AS INT) FROM sys.dm_os_sys_info)
SET @hr = (SELECT DATEPART(HOUR, sqlserver_start_time)FROM sys.dm_os_sys_info)

CREATE TABLE #failedjobsteps (ID INT IDENTITY(1,1), jobid NVARCHAR(200), jobname NVARCHAR(300), stepid INT, stepname NVARCHAR(100), rundate DATE)

INSERT INTO #failedjobsteps
SELECT sj.job_id, sj.name, sjh.step_id, sjh.step_name, CONVERT(DATE, CONVERT(CHAR(10),run_date)) AS rundate
FROM msdb.dbo.sysjobhistory sjh
INNER JOIN msdb.dbo.sysjobs sj ON sjh.job_id = sj.job_id
WHERE run_status IN (0, 3) AND step_id <> 0 AND  run_date = @hr AND run_time/10000 = @hr

SET @iRwCnt = @@ROWCOUNT

WHILE @i <= @iRwCnt
BEGIN

SELECT @jobname = jobname, @stepname = stepname FROM #failedjobsteps WHERE ID = @i
--print 'Jobname is: '+@jobname+' and step is: '+@stepname
EXEC msdb.dbo.sp_start_job 
  @job_name = @jobname
  ,@server_name  = '<ServerName>'
  ,@step_name = @stepname

SET @i = @i + 1
END

DROP TABLE #failedjobsteps