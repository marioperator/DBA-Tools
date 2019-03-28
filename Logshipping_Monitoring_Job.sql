/*******Logshipping Monitoring*****/

USE [msdb]
GO

/****** Object:  Job [Logshipping Monitoring]    Script Date: 04/12/2017 09:46:35 ******/
BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0
/****** Object:  JobCategory [[Uncategorized (Local)]]    Script Date: 04/12/2017 09:46:35 ******/
IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'[Uncategorized (Local)]' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'[Uncategorized (Local)]'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END

DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'Logshipping Monitoring', 
		@enabled=0, 
		@notify_level_eventlog=0, 
		@notify_level_email=2, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'Maintenance Job for Logshipping Monitoring', 
		@category_name=N'[Uncategorized (Local)]', 
		@owner_login_name=N'sa', 
		@notify_email_operator_name=N'Dev Alerts', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [Add Rows DBA]    Script Date: 04/12/2017 09:46:35 ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Add Rows DBA', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=4, 
		@on_success_step_id=2, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'INSERT INTO DBA.dbo.Logshipping_Status
SELECT	secondary_server, secondary_database, primary_server, primary_database, 
		last_restored_latency [Latency (mins)],  
		DATEDIFF(minute, last_restored_date_utc, GETUTCDATE()) + last_restored_latency [Minutes Behind Current Time],
		GETDATE() as Date_Time 
FROM	msdb.dbo.log_shipping_monitor_secondary 
ORDER BY [Minutes Behind Current Time] desc
', 
		@database_name=N'master', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [Alert_Threshold]    Script Date: 04/12/2017 09:46:35 ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Alert_Threshold', 
		@step_id=2, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'/***** Logshipping Monitoring*****/

-- =============================================
-- Author:         HariKumar Mindi
-- Create date: 2017-01-11
-- Description:	Setup a table in DBA database to insert logshipping monitoring values on a hourly basis
--		This script will check if there are any secondary databases which are more than 60min behind primary
--		and if yes then would send email with tabular values for those that are more than 60min and also
--		if there are any databases which were out of sync for last 6 hours
-- =============================================

DECLARE @min int
SET @min = (SELECT MAX(Minutes_Behind_Prod) FROM DBA.dbo.Logshipping_Status 
	       WHERE Minutes_Behind_Prod > 50 AND DATEDIFF(MINUTE, Current_DateTime, GETDATE()) <= 60)

IF @min IS NOT NULL
BEGIN
DECLARE @xml1 nvarchar(max)
DECLARE @xml2 nvarchar(max)
DECLARE @body1 nvarchar(max)
DECLARE @body2 nvarchar(max)

SET @xml1 = CAST((	SELECT	[Secondary Server] AS ''td'','''', [Secondary_Database] as ''td'','''', [Primary_Server] AS ''td'','''', 
							[Latency(Mins)] AS ''td'','''', [Minutes_Behind_Prod] AS ''td'','''',[Current_DateTime] AS ''td''
					FROM	DBA.dbo.Logshipping_Status
					WHERE	[Minutes_Behind_Prod] > 50 and DATEDIFF(MINUTE, [Current_DateTime], GETDATE()) <= 60 
			FOR XML PATH(''tr''), ELEMENTS) AS NVARCHAR(MAX))

SET @xml2 = CAST((	SELECT	[Secondary Server] AS ''td'','''', [Secondary_Database] as ''td'','''', [Primary_Server] AS ''td'','''', 
							[Latency(Mins)] AS ''td'','''', [Minutes_Behind_Prod] AS ''td'','''',[Current_DateTime] AS ''td''
					FROM	DBA.dbo.Logshipping_Status
					WHERE	[Minutes_Behind_Prod] > 50 and DATEDIFF(MINUTE, [Current_DateTime], GETDATE()) <= 360 
			FOR XML PATH(''tr''), ELEMENTS) AS NVARCHAR(MAX))

SET @body1 = ''<html><body><H3>Logshipping Out of Sync in Last 1 hour</H3>
			 <table border = 1>
			 <tr>
			<th>Secondary Server</th><th>Secondary Database</th><th>Primary Server</th><th>Latency_Min</th><th>Minutes Behind Prod</th><th>Last Updated</th>''
SET @body1 = @body1 + @xml1 +''</table></body>''

SET @body2 = ''<html><body><H3>Logshipping Out of Sync in Last 6 hour</H3>
			 <table border = 1>
			 <tr>
			<th>Secondary Server</th><th>Secondary Database</th><th>Primary Server</th><th>Latency_Min</th><th>Minutes Behind Prod</th><th>Last Updated</th>''
SET @body2 = @body1 + @body2 + @xml2 + ''</table></body></html>''

--Send email 

	EXEC msdb.dbo.sp_send_dbmail
	@profile_name = ''TDX MailServer'',
	@Subject = ''Logshipping Alert SQL07'',
	@recipients = ''SQLDBATEAM@tdxgroup.com'',
	@body = @body2,
	@body_format = ''HTML''
END

', 
		@database_name=N'master', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'Logshipping_Alert', 
		@enabled=1, 
		@freq_type=4, 
		@freq_interval=1, 
		@freq_subday_type=8, 
		@freq_subday_interval=1, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=0, 
		@active_start_date=20171018, 
		@active_end_date=99991231, 
		@active_start_time=0, 
		@active_end_time=235959, 
		@schedule_uid=N'ce37b517-7252-4de3-832f-486bc0ff65af'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:
GO


