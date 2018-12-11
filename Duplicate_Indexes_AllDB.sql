/****Find Duplicate Indexes ***/

-- =============================================
-- Author:      HariKumar Mindi
-- Create date: 2018-02-28
-- Description:	This script will find the duplicate indexes with similar key columns where one index might be an exact match or might have key columns of another index
-- =============================================

--Create Temp Table
IF OBJECT_ID('Tempdb.dbo.Index_Duplicates') IS NOT NULL
DROP TABLE TempDB.dbo.Index_Duplicates
CREATE TABLE TempDB.dbo.Index_Duplicates (DBName VARCHAR(200), Schemaname VARCHAR(100), TableName VARCHAR(200), Indexname VARCHAR(300), Index_Type VARCHAR(100), KeyCols VARCHAR(500), InlcudeCols VARCHAR(600))

--Insert all the indexes along with key columns and included column details into the table
DECLARE @sql VARCHAR(max)
SET @sql =
'USE [?];
IF DB_ID(''?'')>4
SELECT ''?'' AS DBName, 
Sch.name as SchemaName, Tab.[name] AS TableName,
Ind.[name] AS IndexName,
Ind.[type_desc] AS IndexType,
SUBSTRING(( SELECT '', '' + AC.name
FROM sys.[tables] AS T
INNER JOIN sys.[indexes] I
ON T.[object_id] = I.[object_id]
INNER JOIN sys.[index_columns] IC
ON I.[object_id] = IC.[object_id]
AND I.[index_id] = IC.[index_id]
INNER JOIN sys.[all_columns] AC
ON T.[object_id] = AC.[object_id]
AND IC.[column_id] = AC.[column_id]
WHERE Ind.[object_id] = I.[object_id]
AND Ind.index_id = I.index_id
AND IC.is_included_column = 0
ORDER BY IC.key_ordinal
FOR
XML PATH('''')
), 2, 8000) AS KeyCols,
SUBSTRING(( SELECT '', '' + AC.name
FROM sys.[tables] AS T
INNER JOIN sys.[indexes] I
ON T.[object_id] = I.[object_id]
INNER JOIN sys.[index_columns] IC
ON I.[object_id] = IC.[object_id]
AND I.[index_id] = IC.[index_id]
INNER JOIN sys.[all_columns] AC
ON T.[object_id] = AC.[object_id]
AND IC.[column_id] = AC.[column_id]
WHERE Ind.[object_id] = I.[object_id]
AND Ind.index_id = I.index_id
AND IC.is_included_column = 1
ORDER BY IC.key_ordinal
FOR
XML PATH('''')
), 2, 8000) AS IncludeCols
FROM sys.[indexes] Ind
INNER JOIN sys.[tables] AS Tab
ON Tab.[object_id] = Ind.[object_id]
INNER JOIN sys.[schemas] AS Sch
ON Sch.[schema_id] = Tab.[schema_id]
WHERE Ind.[name] IS NOT NULL
ORDER BY TableName'

INSERT INTO TempDB.dbo.Index_Duplicates
EXEC sp_MSforeachdb @sql

--Find the duplicate indexes having exactly similar key columns.
SELECT * from TempDB.dbo.Index_Duplicates id1
WHERE EXISTS
(Select * from TempDB.dbo.Index_Duplicates id2
Where id1.DBName = id2.DBName
and id1.schemaname = id2.schemaname
and id1.tablename = id2.tablename
--and id1.KeyCols = id2.KeyCols  
and (id1.KeyCols LIKE LEFT(id2.KeyCols, LEN(id1.KeyCols)) OR id2.KeyCols LIKE LEFT(id1.KeyCols, LEN(id2.KeyCols)))
and id1.indexname <> id2.indexname)
