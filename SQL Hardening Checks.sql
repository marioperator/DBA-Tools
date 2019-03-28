
-----------------------------------------------------------------
-- Ad Hoc Distributed Queries
--
-- CHECK
SELECT name,
CAST(value as int) as value_configured,
CAST(value_in_use as int) as value_in_use
FROM sys.configurations
WHERE name = 'Ad Hoc Distributed Queries';

-- change
EXECUTE sp_configure 'show advanced options', 1;
RECONFIGURE;
EXECUTE sp_configure 'Ad Hoc Distributed Queries', 0;
RECONFIGURE;
GO
EXECUTE sp_configure 'show advanced options', 0;
RECONFIGURE;

-----------------------------------------------------------------
-- CLR Enabled
-- 
-- CHECK
SELECT name,
CAST(value as int) as value_configured,
CAST(value_in_use as int) as value_in_use
FROM sys.configurations
WHERE name = 'clr enabled';

-- Change
EXECUTE sp_configure 'clr enabled', 0;
RECONFIGURE;

-----------------------------------------------------------------
-- Cross DB Ownership Chaining
--
-- CHECK 
SELECT name,
CAST(value as int) as value_configured,
CAST(value_in_use as int) as value_in_use
FROM sys.configurations
WHERE name = 'cross db ownership chaining';

-- Change
EXECUTE sp_configure 'cross db ownership chaining', 0;
RECONFIGURE;
GO

-----------------------------------------------------------------
-- Database Mail XPs
--
-- CHECK
SELECT name,
CAST(value as int) as value_configured,
CAST(value_in_use as int) as value_in_use
FROM sys.configurations
WHERE name = 'Database Mail XPs';

-- Change
EXECUTE sp_configure 'show advanced options', 1;
RECONFIGURE;
EXECUTE sp_configure 'Database Mail XPs', 0;
RECONFIGURE;
GO
EXECUTE sp_configure 'show advanced options', 0;
RECONFIGURE;

-----------------------------------------------------------------
-- OLE Automation Procedures
--
-- CHECK
SELECT name,
CAST(value as int) as value_configured,
CAST(value_in_use as int) as value_in_use
FROM sys.configurations
WHERE name = 'Ole Automation Procedures';

-- Change
EXECUTE sp_configure 'show advanced options', 1;
RECONFIGURE;
EXECUTE sp_configure 'Ole Automation Procedures', 0;
RECONFIGURE;
GO
EXECUTE sp_configure 'show advanced options', 0;
RECONFIGURE;

-----------------------------------------------------------------
-- Remote Access
--
-- CHECK
SELECT name,
CAST(value as int) as value_configured,
CAST(value_in_use as int) as value_in_use
FROM sys.configurations
WHERE name = 'remote access';

-- CHANGE
EXECUTE sp_configure 'show advanced options', 1;
RECONFIGURE;
EXECUTE sp_configure 'remote access', 0;
RECONFIGURE;
GO
EXECUTE sp_configure 'show advanced options', 0;
RECONFIGURE;

-----------------------------------------------------------------
-- Remote Admin Connections (DAC)
--
-- CHECK
USE master;
GO
SELECT name,
CAST(value as int) as value_configured,
CAST(value_in_use as int) as value_in_use
FROM sys.configurations
WHERE name = 'remote admin connections'
AND SERVERPROPERTY('IsClustered') = 0;

-- Change
EXECUTE sp_configure 'remote admin connections', 0;
RECONFIGURE;
GO

-----------------------------------------------------------------
-- Scan for startup procs
--
-- check
SELECT name,
CAST(value as int) as value_configured,
CAST(value_in_use as int) as value_in_use
FROM sys.configurations
WHERE name = 'scan for startup procs';

-- change
EXECUTE sp_configure 'show advanced options', 1;
RECONFIGURE;
EXECUTE sp_configure 'scan for startup procs', 0;
RECONFIGURE;
GO
EXECUTE sp_configure 'show advanced options', 0;
RECONFIGURE;

-----------------------------------------------------------------
-- Trustworthy
--
-- CHECK
SELECT name
FROM sys.databases
WHERE is_trustworthy_on = 1
AND name != 'msdb';

-- CHANGE
ALTER DATABASE [<database_name>] SET TRUSTWORTHY OFF;

-----------------------------------------------------------------
-- Port configurations
--
-- Can be read from registry
--

DECLARE @value nvarchar(256);
EXECUTE master.dbo.xp_instance_regread
N'HKEY_LOCAL_MACHINE',
N'SOFTWARE\Microsoft\Microsoft SQL
Server\MSSQLServer\SuperSocketNetLib\Tcp\IPAll',
N'TcpPort',
@value OUTPUT,
N'no_output';
SELECT @value AS TCP_Port WHERE @value = '1433';

-----------------------------------------------------------------
-- Hide INSTANCES
--
-- CHECK
DECLARE @getValue INT;

EXEC master..xp_instance_regread
@rootkey = N'HKEY_LOCAL_MACHINE',
@key = N'SOFTWARE\Microsoft\Microsoft SQL
Server\MSSQLServer\SuperSocketNetLib',
@value_name = N'HideInstance',
@value = @getValue OUTPUT;

SELECT @getValue;

-----------------------------------------------------------------
-- Disable/Rename 'sa'

-----------------------------------------------------------------
-- Disable xp_cmdshell
--
-- CHECK
SELECT name,
CAST(value as int) as value_configured,
CAST(value_in_use as int) as value_in_use
FROM sys.configurations
WHERE name = 'xp_cmdshell';

-- Change
EXECUTE sp_configure 'show advanced options', 1;
RECONFIGURE;
EXECUTE sp_configure 'xp_cmdshell', 0;
RECONFIGURE;
GO
EXECUTE sp_configure 'show advanced options', 0;
RECONFIGURE;

-----------------------------------------------------------------
-- Revoke CONNECT from GUEST
-- 
-- CHECK
USE [<database_name>];
GO

SELECT DB_NAME() AS DatabaseName, 'guest' AS Database_User,
[permission_name], [state_desc]
FROM sys.database_permissions
WHERE [grantee_principal_id] = DATABASE_PRINCIPAL_ID('guest')
AND [state_desc] LIKE 'GRANT%'
AND [permission_name] = 'CONNECT'
AND DB_NAME() NOT IN ('master','tempdb','msdb');

-- CHANGE
USE [<database_name>];
GO
REVOKE CONNECT FROM guest;

-----------------------------------------------------------------
-- Remove orphaned users
-- 
-- CHECK
USE [<database_name>];
GO
EXEC sp_change_users_login @Action='Report';

-- also

SELECT dp.type_desc, dp.SID, dp.name AS user_name  
FROM sys.database_principals AS dp  
LEFT JOIN sys.server_principals AS sp  
    ON dp.SID = sp.SID  
WHERE sp.SID IS NULL  
    AND authentication_type_desc = 'INSTANCE';  
	
-- CHANGE
USE [<database_name>];
GO
DROP USER <username>;

-----------------------------------------------------------------
-- 'public' role only has default permissions
-- 
-- CHECK

SELECT *
FROM master.sys.server_permissions
WHERE (grantee_principal_id = SUSER_SID(N'public') and state_desc LIKE
'GRANT%')
AND NOT (state_desc = 'GRANT' and [permission_name] = 'VIEW ANY DATABASE'
and class_desc = 'SERVER')
AND NOT (state_desc = 'GRANT' and [permission_name] = 'CONNECT' and
class_desc = 'ENDPOINT' and major_id = 2)
AND NOT (state_desc = 'GRANT' and [permission_name] = 'CONNECT' and
class_desc = 'ENDPOINT' and major_id = 3)
AND NOT (state_desc = 'GRANT' and [permission_name] = 'CONNECT' and
class_desc = 'ENDPOINT' and major_id = 4)
AND NOT (state_desc = 'GRANT' and [permission_name] = 'CONNECT' and
class_desc = 'ENDPOINT' and major_id = 5);

-----------------------------------------------------------------
-- 'public' role has no proxy access
-- 
-- CHECK
USE [msdb]
GO
SELECT sp.name AS proxyname
FROM dbo.sysproxylogin spl
JOIN sys.database_principals dp
ON dp.sid = spl.sid
JOIN sysproxies sp
ON sp.proxy_id = spl.proxy_id
WHERE principal_id = USER_ID('public');
GO

-- fix
USE [msdb]
GO
EXEC dbo.sp_revoke_login_from_proxy @name = N'public', @proxy_name = N'<proxyname>';
GO

-----------------------------------------------------------------
-- Remove Windows BUILTIN logins
-- 
-- CHECK
SELECT pr.[name], pe.[permission_name], pe.[state_desc]
FROM sys.server_principals pr
JOIN sys.server_permissions pe
ON pr.principal_id = pe.grantee_principal_id
WHERE pr.name like 'BUILTIN%';

-- remove
USE [master];
GO
DROP LOGIN [BUILTIN\<name>];
GO

-----------------------------------------------------------------
-- Remove Windows local group logins
-- 
-- CHECK
USE [master]
GO
SELECT pr.[name] AS LocalGroupName, pe.[permission_name], pe.[state_desc]
FROM sys.server_principals pr
JOIN sys.server_permissions pe
ON pr.[principal_id] = pe.[grantee_principal_id]
WHERE pr.[type_desc] = 'WINDOWS_GROUP'
AND pr.[name] like CAST(SERVERPROPERTY('MachineName') AS nvarchar) + '%';

-- DROP
USE [master]
GO
DROP LOGIN [<name>]
GO


-----------------------------------------------------------------
-- Set maximum number of error logs
-- 
-- CHECK
DECLARE @NumErrorLogs int;
EXEC master.sys.xp_instance_regread
N'HKEY_LOCAL_MACHINE',
N'Software\Microsoft\MSSQLServer\MSSQLServer',
N'NumErrorLogs',
@NumErrorLogs OUTPUT;
SELECT ISNULL(@NumErrorLogs, -1) AS [NumberOfLogFiles];

-- Fix
EXEC master.sys.xp_instance_regwrite
N'HKEY_LOCAL_MACHINE',
N'Software\Microsoft\MSSQLServer\MSSQLServer',
N'NumErrorLogs',
REG_DWORD,
26;

-----------------------------------------------------------------
-- 'Default Trace Enabled'
-- 
-- CHECK
SELECT name,
CAST(value as int) as value_configured,
CAST(value_in_use as int) as value_in_use
FROM sys.configurations
WHERE name = 'default trace enabled';

-- change
EXECUTE sp_configure 'show advanced options', 1;
RECONFIGURE;
EXECUTE sp_configure 'default trace enabled', 1;
RECONFIGURE;
GO
EXECUTE sp_configure 'show advanced options', 0;
RECONFIGURE;

-----------------------------------------------------------------
-- Create SQL Audit Failed and Successful logins
-- 
-- CHECK
SELECT
S.name AS 'Audit Name'
, CASE S.is_state_enabled
WHEN 1 THEN 'Y'
WHEN 0 THEN 'N' END AS 'Audit Enabled'
, S.type_desc AS 'Write Location'
, SA.name AS 'Audit Specification Name'
, CASE SA.is_state_enabled
WHEN 1 THEN 'Y'
WHEN 0 THEN 'N' END AS 'Audit Specification Enabled'
, SAD.audit_action_name
, SAD.audited_result
FROM sys.server_audit_specification_details AS SAD
JOIN sys.server_audit_specifications AS SA
ON SAD.server_specification_id = SA.server_specification_id
JOIN sys.server_audits AS S
ON SA.audit_guid = S.audit_guid
WHERE SAD.audit_action_id IN ('CNAU', 'LGFL', 'LGSD');

-- create
CREATE SERVER AUDIT TrackLogins
TO APPLICATION_LOG;
GO
CREATE SERVER AUDIT SPECIFICATION TrackAllLogins
FOR SERVER AUDIT TrackLogins
ADD (FAILED_LOGIN_GROUP),
ADD (SUCCESSFUL_LOGIN_GROUP),
ADD (AUDIT_CHANGE_GROUP)
WITH (STATE = ON);
GO
ALTER SERVER AUDIT TrackLogins
WITH (STATE = ON);
GO

-----------------------------------------------------------------
-- Asymmetric key length to 2048 bits
-- 
-- CHECK
USE <database_name>;
GO
SELECT db_name() AS Database_Name, name AS Key_Name
FROM sys.asymmetric_keys
WHERE key_length < 2048
AND db_id() > 4;
GO



