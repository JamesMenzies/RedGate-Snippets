
DROP TABLE #results
CREATE TABLE #results
(
	[Schema] VARCHAR(128),
	[Table] VARCHAR(128), 
	[Column] VARCHAR(128),
	[Column Type] VARCHAR(128),
	[Field Length] INT,
	[Rows] INT,
	[Nulls] INT,
	[Text Length] INT,
	[Distinct Values] INT,
	[Is Nullable] BIT
)
DECLARE cur CURSOR LOCAL FOR
	SELECT 
	'INSERT INTO #results 
	SELECT ''' + s.Name + ''' [Schema], ' +
	+'''' + t.NAME + ''' [Table], '
	+'''' + c.name + ''' [Column], '
	+'''' + ty.name + ''' [Column Type], '+
	+CAST(c.max_length AS VARCHAR(MAX)) +' [Max Field Length], '+
	'COUNT(1) [Rows], '
	+' ISNULL(MAX(CASE WHEN '+CAST(c.system_type_id AS VARCHAR(128))+' in (35,99,167,175,231,239) THEN LEN('+ QUOTENAME(c.name) +') ELSE 0 END),0) [Longest Text],' 
	+' ISNULL(SUM(CASE WHEN ' 
	+QUOTENAME(c.name)  + ' IS NULL THEN 1 ELSE 0 END),-1) [Nulls], '
	+'ISNULL(SUM(CASE WHEN '+CAST(c.system_type_id AS VARCHAR(128))+' in (35,99,167,175,231,239) THEN LEN('+ QUOTENAME(c.name) +') ELSE 0 END),0) [Text Length],' 
	+CASE WHEN c.system_type_id NOT IN (99) THEN 'COUNT(DISTINCT '+QUOTENAME(c.name)+ ')' ELSE null END +' [Distinct Values], '
	+CAST(c.is_nullable AS CHAR(1)) + ' [Is Nullable]'
	+ ' FROM ' 
	+ QUOTENAME(s.Name) +'.'+ QUOTENAME(t.NAME) + ' '
	FROM 
		sys.tables t
	LEFT JOIN
		sys.columns c ON c.object_id = t.OBJECT_ID
	LEFT JOIN sys.types ty ON c.system_type_id = ty.system_type_id
	LEFT OUTER JOIN 
		sys.schemas s ON t.schema_id = s.schema_id
	WHERE 
		t.NAME NOT LIKE 'dt%' 
		AND t.is_ms_shipped = 0
		AND t.OBJECT_ID > 255 


OPEN CUR
DECLARE @query NVARCHAR(MAX)
FETCH NEXT FROM cur INTO @query

WHILE @@FETCH_STATUS = 0 BEGIN
	print @query
	EXEC sp_executesql  @query
	FETCH NEXT FROM cur INTO @query
END

CLOSE cur
DEALLOCATE cur
SELECT *   
	  , [Foreign Key] = (
						  SELECT	PK.TABLE_NAME + '.' + PT.COLUMN_NAME + ' (' + isrc.CONSTRAINT_NAME + ')'
						  FROM		INFORMATION_SCHEMA.REFERENTIAL_CONSTRAINTS isrc
						  INNER JOIN INFORMATION_SCHEMA.TABLE_CONSTRAINTS isfk ON isrc.CONSTRAINT_NAME = isfk.CONSTRAINT_NAME
						  INNER JOIN INFORMATION_SCHEMA.TABLE_CONSTRAINTS PK ON isrc.UNIQUE_CONSTRAINT_NAME = PK.CONSTRAINT_NAME
						  INNER JOIN INFORMATION_SCHEMA.KEY_COLUMN_USAGE CU ON isrc.CONSTRAINT_NAME = CU.CONSTRAINT_NAME
						  INNER JOIN (
									   SELECT	i1.TABLE_NAME
											  , i2.COLUMN_NAME
									   FROM		INFORMATION_SCHEMA.TABLE_CONSTRAINTS i1
									   INNER JOIN INFORMATION_SCHEMA.KEY_COLUMN_USAGE i2 ON i1.CONSTRAINT_NAME = i2.CONSTRAINT_NAME
									   WHERE	i1.CONSTRAINT_TYPE = 'PRIMARY KEY'
									 ) PT ON PT.TABLE_NAME = PK.TABLE_NAME
						  WHERE		CU.COLUMN_NAME = 	r.[Column]	   COLLATE DATABASE_DEFAULT
									AND isfk.TABLE_NAME = 	  r.[Table]		  COLLATE DATABASE_DEFAULT
						) FROM #results	  r



SELECT * FROM #results	  r
WHERE r.[Column] LIKE '%Tableid%' 


