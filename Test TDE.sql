
/*
 * TDE test of database encryption on SQL 2008R2 - SQL02
 *
 * Can we TDE a db to AES-128 then overwrite it with AES-256?
 *
 */

USE master
GO

CREATE DATABASE TestDB ON PRIMARY
( NAME = N'TestDB', FILENAME = N'D:\SQLData\TestDB.mdf' , SIZE = 5120KB , FILEGROWTH = 1024KB )
 LOG ON 
( NAME = N'TestDB_log', FILENAME = N'L:\SQLLog\TestDB_log.ldf' , SIZE = 5120KB , FILEGROWTH = 1024KB )
GO

-- Current state
-- list certificates
select name, subject, pvt_key_encryption_type_desc
from sys.certificates
where name not like '##%'
/*
TDE_Bankrupt	My DEK Certificate for Bankruptcy databases	ENCRYPTED_BY_MASTER_KEY
*/

SELECT database_id, DB_NAME(database_id),key_algorithm, key_length, create_date
  FROM sys.dm_database_encryption_keys
/*
2	tempdb	AES	256	2016-05-23 07:53:43.303
34	DSTDX_Insolvency	AES	256	2016-01-19 18:11:34.963
35	TDXBankrupt	AES	256	2016-01-19 18:11:34.627
36	TDXBankrupt_Analysis	AES	256	2016-01-19 18:11:34.767
37	TDXBankrupt_Loading	AES	256	2016-01-19 18:11:34.863
*/

-- Create new certificate for test
-- secured by the database master key
CREATE CERTIFICATE TestTDECert WITH SUBJECT = 'My test DEK Certificate for the DBA database'
GO

-- PLATO
USE [TestDB]
GO 

CREATE DATABASE ENCRYPTION KEY WITH ALGORITHM = AES_128 ENCRYPTION BY SERVER CERTIFICATE TestTDECert
GO 

ALTER DATABASE [TestDB] SET ENCRYPTION ON
GO

-- Now overwriting with AES-256
CREATE DATABASE ENCRYPTION KEY WITH ALGORITHM = AES_256 ENCRYPTION BY SERVER CERTIFICATE TestTDECert
GO 

/*
!!!!!!!!!!! ERROR !!!!!!!!
Msg 33103, Level 16, State 1, Line 1
A database encryption key already exists for this database.
*/


-- You have to drop the existing encryption key
ALTER DATABASE [TestDB] SET ENCRYPTION OFF
GO

-- check for state = 1
SELECT database_id, DB_NAME(database_id), encryption_state, key_algorithm, key_length, create_date
  FROM sys.dm_database_encryption_keys


DROP DATABASE ENCRYPTION KEY;
GO
