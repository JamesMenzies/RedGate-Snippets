DROP TABLE IF EXISTS #columnInfo;
DECLARE @schemaName NVARCHAR(128) = N'dbo';
DECLARE @tableName NVARCHAR(128) = N'table_name';

DECLARE @schematableName NVARCHAR(256) = QUOTENAME ( @schemaName ) + N'.' + QUOTENAME ( @tableName );

-- Create a temporary table to store intermediate results
CREATE TABLE #columnInfo
(
   columnName                   NVARCHAR(255) NOT NULL
 , dataType                     NVARCHAR(255) NOT NULL
 , maxLength                    INT           NULL
 , nullCount                    INT           NULL
 , distinctValueCount           INT           NULL
 , longValuesCount              INT           NULL
 , uniqueValuesCount            INT           NULL
 , largestNonNullDuplicateCount INT           NULL
 , averageDuplicateCount        FLOAT         NULL
 , stdDevDuplicateCount         FLOAT         NULL
);

-- Loop through all columns in the given table
DECLARE @columnName                   NVARCHAR(255)
      , @dataType                     NVARCHAR(255)
      , @maxLength                    INT
      , @nullCount                    INT
      , @distinctValueCount           INT
      , @longValuesCount              INT
      , @uniqueValuesCount            INT
      , @largestNonNullDuplicateCount INT
      , @averageDuplicateCount        FLOAT
      , @stdDevDuplicateCount         FLOAT;

DECLARE @sql NVARCHAR(MAX);

DECLARE column_cursor CURSOR FOR
   SELECT   c.name                 [Column Name]
          , UPPER ( t.name ) + CASE
                                  WHEN t.name IN ( 'char', 'varchar', 'nchar', 'nvarchar' ) THEN
                                     '(' + CASE
                                              WHEN c.max_length = -1 THEN
                                                 'MAX'
                                              ELSE
                                                 CONVERT ( VARCHAR(4), CASE WHEN t.name IN ( 'nchar', 'nvarchar' ) THEN c.max_length / 2 ELSE c.max_length END )
                                           END + ')'
                                  WHEN t.name IN ( 'decimal', 'numeric' ) THEN
                                     '(' + CONVERT ( VARCHAR(4), c.precision ) + ',' + CONVERT ( VARCHAR(4), c.scale ) + ')'
                                  ELSE
                                     ''
                               END [DDL name]
   FROM  sys.columns                 c
   INNER JOIN sys.types              t ON c.user_type_id = t.user_type_id
   LEFT OUTER JOIN sys.index_columns ic ON ic.object_id = c.object_id
                                           AND  ic.column_id = c.column_id
   LEFT OUTER JOIN sys.indexes       i ON ic.object_id = i.object_id
                                          AND ic.index_id = i.index_id
   WHERE c.object_id = OBJECT_ID ( @schematableName );

OPEN column_cursor;

FETCH NEXT FROM column_cursor
INTO @columnName
   , @dataType;

WHILE @@FETCH_STATUS = 0
BEGIN
   -- Create dynamic SQL statement
   SET @sql =
      N'
        SET @maxLength = (
            SELECT MAX(LEN(CONVERT(NVARCHAR(MAX), COALESCE(' + QUOTENAME ( @columnName ) + N', ''''))))
            FROM ' + @schematableName + N'
        );

        SET @nullCount = (
            SELECT COUNT(*)
            FROM ' + @schematableName + N'
            WHERE ' + QUOTENAME ( @columnName ) + N' IS NULL
        );

        SET @distinctValueCount = (
            SELECT COUNT(DISTINCT ' + QUOTENAME ( @columnName ) + N')
            FROM ' + @schematableName + N'
			WHERE ' + QUOTENAME ( @columnName )
      + N' IS NOT NULL
        );

		SET @longValuesCount = 0
        IF @dataType = ''VARCHAR(MAX)'' OR @dataType = ''NVARCHAR(MAX)''
        BEGIN
            SET @longValuesCount = (
                SELECT COUNT(*)
                FROM ' + @schematableName + N'
                WHERE ' + QUOTENAME ( @columnName ) + N' IS NOT NULL
                  AND LEN(CONVERT(NVARCHAR(MAX), ' + QUOTENAME ( @columnName )
      + N')) > 255
            );
        END
		ELSE
		BEGIN
			SET @longValuesCount = NULL
		END;

		-- Calculate LargestNonNullDuplicateCount, AverageDuplicateCount, and StdDevDuplicateCount
        WITH DuplicateCounts AS (
            SELECT
                [' + @columnName + N'] AS ColumnValue,
                COUNT(*) AS DuplicateCount
            FROM ' + @schematableName + N'
            WHERE ' + QUOTENAME ( @columnName ) + N' IS NOT NULL
            GROUP BY ' + QUOTENAME ( @columnName )
      + N'
        )
        SELECT @largestNonNullDuplicateCount = MAX(DuplicateCount),
               @averageDuplicateCount = AVG(DuplicateCount * 1.0),
               @stdDevDuplicateCount = STDEVP(DuplicateCount * 1.0)
        FROM DuplicateCounts;

        SET @uniqueValuesCount = (
            SELECT COUNT(*)
            FROM (
                SELECT ' + QUOTENAME ( @columnName ) + N'
                FROM ' + @schematableName + N'
				WHERE ' + QUOTENAME ( @columnName ) + N' IS NOT NULL
                GROUP BY ' + QUOTENAME ( @columnName ) + N'
                HAVING COUNT(*) = 1
            ) AS uniqueValues
        );';

   --PRINT @sql
   -- Execute dynamic SQL
   EXEC sys.sp_executesql @sql
                        , N'@dataType NVARCHAR(255) OUTPUT, @maxLength INT OUTPUT, @nullCount INT OUTPUT, @distinctValueCount INT OUTPUT, @longValuesCount INT OUTPUT, @uniqueValuesCount INT OUTPUT, @largestNonNullDuplicateCount INT OUTPUT, @averageDuplicateCount FLOAT OUTPUT, @stdDevDuplicateCount FLOAT OUTPUT'
                        , @dataType OUTPUT
                        , @maxLength OUTPUT
                        , @nullCount OUTPUT
                        , @distinctValueCount OUTPUT
                        , @longValuesCount OUTPUT
                        , @uniqueValuesCount OUTPUT
                        , @largestNonNullDuplicateCount OUTPUT
                        , @averageDuplicateCount OUTPUT
                        , @stdDevDuplicateCount OUTPUT;

   -- Insert the results into the temporary table
   INSERT INTO #columnInfo
   (
      columnName
    , dataType
    , maxLength
    , nullCount
    , distinctValueCount
    , longValuesCount
    , uniqueValuesCount
    , largestNonNullDuplicateCount
    , averageDuplicateCount
    , stdDevDuplicateCount
   )
   VALUES
   (
      @columnName
    , @dataType
    , @maxLength
    , @nullCount
    , @distinctValueCount
    , @longValuesCount
    , @uniqueValuesCount
    , @largestNonNullDuplicateCount
    , @averageDuplicateCount
    , @stdDevDuplicateCount
   );

   FETCH NEXT FROM column_cursor
   INTO @columnName
      , @dataType;
END;

CLOSE column_cursor;
DEALLOCATE column_cursor;

-- Display the report
SELECT   * FROM   #columnInfo;

-- Clean up temporary table
DROP TABLE #columnInfo;
