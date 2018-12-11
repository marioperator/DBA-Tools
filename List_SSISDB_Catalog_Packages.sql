-- SQL Server 2012 SSISDB Catalog query
-- https://msdn.microsoft.com/en-us/library/hh479588(v=sql.110).aspx
-- Phil Streiff, MCDBA, MCITP, MCSA
-- 09/08/2016

USE [SSISDB];
GO
SELECT 
	pk.project_id, 
	pj.name 'folder', 
	pk.name, 
	pj.deployed_by_name 'deployed_by' 
FROM
	catalog.packages pk JOIN catalog.projects pj 
	ON (pk.project_id = pj.project_id)
ORDER BY
	folder,
	pk.name