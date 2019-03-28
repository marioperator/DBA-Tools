
-- TDE queries
-- G. Harris
--
-- Covers :
-- Checking TDE, dropping TDE, adding TDE, copying TDE for a restore of an encrypted backup and changing keys


--------------------------------------------------------------------------------------------
-- 

use master
go

-- list certificates
select name, start_date, subject, pvt_key_encryption_type_desc
from sys.certificates
where name not like '##%'

-- List databases that are encrypted, their key types, certificates and encryption state.
-- DB that are not encrypted will not be listed
--
SELECT db.name AS [Database],
		dbe.key_algorithm AS [Algorithm],
		dbe.key_length AS [Key Length],
		c.name AS [Certificate],
		case dbe.encryption_state 
			when 0 then 'No database encryption key present, no encryption'
			when 1 then 'Unencrypted'
			when 2 then 'Encryption in progress'
			when 3 then 'Encrypted'
			when 4 then 'Key change in progress'
			when 5 then 'Decryption in progress'
			when 6 then 'Protection change in progress (The certificate or asymmetric key that is encrypting the database encryption key is being changed.)'
		end AS EncryptionState,
		dbe.create_date AS [Encryption Date]
		--, dbe.percent_complete
from sys.dm_database_encryption_keys dbe
inner join sys.databases db on db.database_id = dbe.database_id
INNER JOIN sys.certificates c on dbe.encryptor_thumbprint = c.thumbprint
order by 4, 1
go

SELECT * FROM sys.dm_database_encryption_keys

--------------------------------------------------------------------------------------------------------------
--
-- Comparing Encryption
--
SELECT db.name AS [Database],
		dbe.key_algorithm AS [Algorithm],
		dbe.key_length AS [Key Length],
		c.name AS [Certificate],
		dbe.create_date AS [Encryption Date]
		--, dbe.percent_complete
from sys.dm_database_encryption_keys dbe
inner join sys.databases db on db.database_id = dbe.database_id
INNER JOIN sys.certificates c on dbe.encryptor_thumbprint = c.thumbprint
order by 1
GO

-- list all unencrypted databases
SELECT db.name
  FROM sys.databases db
 WHERE db.database_id NOT IN (SELECT database_id FROM sys.dm_database_encryption_keys)
   AND db.name NOT IN ('distribution','master','model','tempdb','msdb','ReportServer','ReportServerTempDB')
 ORDER BY 1

--------------------------------------------------------------------------------------------
-- 
-- DROP Encryption
--
ALTER DATABASE [ODMCommunicationAnalysis_Archive] SET ENCRYPTION OFF
GO

-- wait for it to complete
SELECT db.name AS [Database],
		case dbe.encryption_state 
			when 0 then 'No database encryption key present, no encryption'
			when 1 then 'Unencrypted'
			when 2 then 'Encryption in progress'
			when 3 then 'Encrypted'
			when 4 then 'Key change in progress'
			when 5 then 'Decryption in progress'
			when 6 then 'Protection change in progress (The certificate or asymmetric key that is encrypting the database encryption key is being changed.)'
		end AS EncryptionState
		--, dbe.percent_complete
from sys.dm_database_encryption_keys dbe
inner join sys.databases db on db.database_id = dbe.database_id
INNER JOIN sys.certificates c on dbe.encryptor_thumbprint = c.thumbprint
order by 1
GO

USE <DB>
GO

DROP DATABASE ENCRYPTION KEY  
GO

--------------------------------------------------------------------------------------------
--
-- Set Up TDE on a new server/db
--
use master
go

-- Server Master key
CREATE MASTER KEY ENCRYPTION BY PASSWORD = '<PW #1>';
GO

-- Encrypt ODM dbs
CREATE CERTIFICATE PlatoODMCert WITH SUBJECT = 'My DEK Certificate for the ODM databases'
GO

-- PLATO
USE [ODMCommunicationAnalysis_Archive]
GO 
CREATE DATABASE ENCRYPTION KEY WITH ALGORITHM = AES_256 ENCRYPTION BY SERVER CERTIFICATE PlatoODMCert
GO 
ALTER DATABASE [ODMCommunicationAnalysis_Archive] SET ENCRYPTION ON
GO

-- backup master key, local cert & database key
USE master
GO

BACKUP SERVICE MASTER KEY TO FILE = 'path_to_file' 
    ENCRYPTION BY PASSWORD = 'password'
GO

BACKUP CERTIFICATE PlatoODMCert TO FILE = 'C:\TDE\PlatoODMCert_File.cer' 
WITH PRIVATE KEY (FILE = 'C:\TDE\PlatoODMCert_Key.pvk' , ENCRYPTION BY PASSWORD = '<PW #2>') 
GO

--- Then record the passwords in teh DBA password doc
-- and copy/move the cert & key files to the relevant TDE folder in the DBA secure folder


--------------------------------------------------------------------------------------------
--
-- Set Up TDE on a replacement server/db by copying TDE certificate across
--

USE [master]
GO

CREATE MASTER KEY ENCRYPTION BY PASSWORD = '<New Password Here>'

CREATE CERTIFICATE PlatoCertificate
FROM FILE = 'C:\TDE\PlatoCert_File.cer'     
WITH PRIVATE KEY (FILE = 'C:\TDE\PlatoCert_Key.pvk', 
DECRYPTION BY PASSWORD = '<PW>')

USE [TDXRMIS]
GO 
CREATE DATABASE ENCRYPTION KEY WITH ALGORITHM = AES_256 ENCRYPTION BY SERVER CERTIFICATE [PlatoCertificate]
GO 
ALTER DATABASE [TDXRMIS] SET ENCRYPTION ON
GO


--------------------------------------------------------------------------------------------
--
-- Changing the encryption key per protocols, e.g. after a DBA leaves
--

-- PLATO
USE [ODMCommunicationAnalysis_Archive]
GO 

ALTER DATABASE ENCRYPTION KEY 
  REGENERATE WITH ALGORITHM = AES_256 
  ENCRYPTION BY SERVER CERTIFICATE PlatoODMCert
GO 
