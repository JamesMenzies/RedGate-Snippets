/* 
NAME
	Search Database for Interger

VERSION
	1.3

DESCRIPTION
	Searches All Columns of All non-MS Tables for a given interger. This is dead useful when you are hunting for relationships
	between normalised data tables.

AUTHOR
	James Menzies @ DataEngineering.Millnet (2015-10-01)

NOTES
	Loops over tables and INT and BIGINT columns Searching for all values equal to search INT.
	Per table it builds a table (@queryTable) of queries. Joins these queries (STUFF) together and runs them (sp_Exe).

CHANGE HISTORY
	v1.1 2015-10-02 - JCM
		* Exchanged union for Union All. Due to EXCEPTION:
		"The data type text cannot be used as an operand to the UNION, INTERSECT or 
		EXCEPT operators because it is not comparable."
		This occours when a TEXT, NTEXT, or other non-distincatable field crops up.
	v1.2 2015-10-05 - JCM
		* Added support for XML Encoding problems in FOR XML PATH USING THE 
		", TYPE).value('.', 'nvarchar(max)')" STUFF pattern
	v1.3 2015-10-06 - JCM
		* Added Summary of All hits reporting with rollup
		(considered CUBE but could find a use case so just left some GROUPING machinery for it)
--
*/ 

--**********************************************
--**********HERE IS WHAT WE SEARCH FOR**********
DECLARE	@SearchFor INT
SET @SearchFor = 1035357
--**********************************************


SET NOCOUNT ON

--Dynamic SQL VARS
DECLARE	@TableName sysname
  , @ColumnName sysname
  , @prams NVARCHAR(255)
SET @prams = '@baby NVARCHAR(4000)'
SET @TableName = ''

--Data Collection
DECLARE	@queryTable TABLE
(
  TableName sysname
, ColumnName sysname
, query NVARCHAR(4000) NOT NULL
, hits INT
)

--Mail Loop - once per Table
WHILE @TableName IS NOT NULL
BEGIN
	SET @ColumnName = ''
	--Get a table name without a cursor and in alpha order
	SET @TableName = (
					   SELECT	MIN(QUOTENAME(TABLE_SCHEMA) + '.' + QUOTENAME(TABLE_NAME))
					   FROM		INFORMATION_SCHEMA.TABLES
					   WHERE	TABLE_TYPE = 'BASE TABLE'
								AND QUOTENAME(TABLE_SCHEMA) + '.' + QUOTENAME(TABLE_NAME) > @TableName
								AND OBJECTPROPERTY(OBJECT_ID(QUOTENAME(TABLE_SCHEMA) + '.' + QUOTENAME(TABLE_NAME)), 'IsMSShipped') = 0
					 )
	--Inner loop once per colunm where column type is in list of acceptable types
	-- if you change the acceptable type list make sure that @SearchFor has implicit conversion
	WHILE ( @TableName IS NOT NULL )
		AND ( @ColumnName IS NOT NULL )
	BEGIN
		--Select here is also in column order. if I was feelin hardcore I should change it to table order but meh
		SET @ColumnName = (
							SELECT	MIN(QUOTENAME(COLUMN_NAME))
							FROM	INFORMATION_SCHEMA.COLUMNS
							WHERE	TABLE_SCHEMA = PARSENAME(@TableName, 2)
									AND TABLE_NAME = PARSENAME(@TableName, 1)
									AND DATA_TYPE IN ( 'int', 'bigint' )
									AND QUOTENAME(COLUMN_NAME) > @ColumnName
						  )
		--FIX upgrade from alpha order to table column order.

		--If we have a column 
		IF @ColumnName IS NOT NULL
		BEGIN
			DECLARE	@baby NVARCHAR(4000)
			  , @localquery NVARCHAR(4000)
			--build a query to search the column.
			SET @baby = 'SELECT [TableName]=''' + @TableName + ''', [ColumnName] = ''' + @ColumnName + ''', tbl.*  FROM ' + @TableName + ' tbl (NOLOCK) '
				+ ' WHERE ' + @ColumnName + ' = ' + CAST(@SearchFor AS NVARCHAR(25))
			--build a query to TEST if the query is needed. AND report on hits.
			SET @localquery = 'IF EXISTS (SELECT 1 FROM ' + @TableName + 'WHERE ' + @ColumnName + ' = ' + CAST(@SearchFor AS NVARCHAR(25)) + ')'
				+ ' SELECT  [TableName]=''' + @TableName + ''', [ColumnName] = ''' + @ColumnName + ''', query =  @baby, hits = ' + '(SELECT COUNT('
				+ @ColumnName + ') FROM ' + @TableName + 'WHERE ' + @ColumnName + ' = ' + CAST(@SearchFor AS NVARCHAR(25)) + ')'
			--PRINT @localquery
			--RUN local query 
			INSERT	INTO @queryTable
					EXEC sys.sp_executesql
						@localquery
					  , @prams = @prams
					  , @baby = @baby
		END --IF @ColumnName IS NOT NULL
	END    
	--Next Column


	IF EXISTS ( SELECT	query
				FROM	@queryTable )
	BEGIN
		DECLARE	@tableBaby NVARCHAR(4000)
		SELECT	@tableBaby = STUFF(
		(SELECT	' UNION ALL ' + query
		 FROM	@queryTable
		 WHERE	TableName = @TableName --Control to only select current table
				FOR				   XML PATH('')
									 , TYPE).value('.', 'nvarchar(max)'), 1, 11, '')
		PRINT @tableBaby
		EXEC sys.sp_executesql
			@tableBaby
	END --IF EXISTS 

END
--Next Table

--Final Reporting
SELECT	TableName = CASE WHEN GROUPING(qt.TableName) = 1 THEN 'ALL'
						 ELSE qt.TableName
					END
	  , ColumnName = CASE WHEN GROUPING(qt.ColumnName) = 1 THEN 'ALL'
						  ELSE qt.ColumnName
					 END
	  , hits = SUM(qt.hits)
FROM	@queryTable qt
GROUP BY ROLLUP(qt.TableName, qt.ColumnName)

