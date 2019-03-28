--Logshipping Report
--HariKumar Mindi - October, 2017
--Description:	Shows how far behind the primary database in minutes

DECLARE @xml nvarchar(max)
DECLARE @body nvarchar(Max)

SET @xml = CAST((SELECT	[secondary_server] AS 'td','', [secondary_database] AS 'td','', [primary_server] AS 'td','', [primary_database] AS 'td','', 
		[last_restored_latency] AS 'td','',  
		DATEDIFF(minute, last_restored_date_utc, GETUTCDATE()) + last_restored_latency  AS 'td'
FROM	log_shipping_monitor_secondary
ORDER BY [secondary_database] 
FOR XML PATH('tr'), ELEMENTS) AS NVARCHAR(MAX))

SET @body = '<html><body><H3>Logshipping Report</H3>
<table border = 1>
<tr>
<th>Secondary Server</th><th>Secondary Database</th><th>Primary Server</th><th>Primary Database</th><th>Latency_Min</th><th>Minutes Behind Prod</th>'

SET @body = @body + @xml +'</table></body></html>'

	EXEC msdb.dbo.sp_send_dbmail
	@profile_name = 'TDX MailServer',
	@Subject = 'Logshipping Daily Report',
	@recipients = 'SQLDBATEAM@tdxgroup.com',
	@body = @body,
	@body_format = 'HTML'

