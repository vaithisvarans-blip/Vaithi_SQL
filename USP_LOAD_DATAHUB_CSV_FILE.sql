CREATE OR REPLACE PROCEDURE UAT_STAGING.PUBLIC.USP_LOAD_DATAHUB_CSV_FILE("STAGENAME" VARCHAR(16777216), "FILENAME" VARCHAR(16777216), "COLUMN_NAMING_FUNCTION" VARCHAR(16777216))
RETURNS VARCHAR(16777216)
LANGUAGE JAVASCRIPT
EXECUTE AS CALLER
AS' 
/******************************************************************************
Author  : Emily Nelson
Created	: 2021-06-10
Updated : 2021-07-22 / Francisco Andujar
Reason	: SP for uploading csv files and writing to the audit table
Example	: call USP_LOAD_DATAHUB_CSV_FILE(''dp_b2b_blackrock_inbound'', ''Liberty_Loans_'');
*******************************************************************************/

/* default COLUMN_NAMING_FUNCTION if not defined*/
if (COLUMN_NAMING_FUNCTION === undefined) {
	COLUMN_NAMING_FUNCTION = "UDF_AF_VALIDATE_COLUMN_NAMING";
}

/* get path of the stage to remove unnecessary files from final list*/
var sql_get_stage_desc = " desc stage " + STAGENAME + "; ";
var stmt_get_stage_desc = snowflake.createStatement(
  {sqlText: sql_get_stage_desc}
);

var sql_get_stage_root = " select replace(replace(replace(t.\\"property_value\\", ''[''), '']''), ''\\"'') from table(result_scan(last_query_id())) as t where t.\\"property\\" = ''URL''; ";
var stmt_get_stage_root = snowflake.createStatement(
  {sqlText: sql_get_stage_root}
);

/* try root folder of the stage */
try {
    var rs_stage_desc = stmt_get_stage_desc.execute();
    var rs_stage_root = stmt_get_stage_root.execute();
	rs_stage_root.next();
	var sroot = rs_stage_root.getColumnValue(1);
}
catch (err) {
    return "Failed : " + err + " | SQL: " + stmt_get_stage_desc.getSqlText() + stmt_get_stage_root.getSqlText();
}

/* here we''ll define steps in SQL queries*/
/* getting list of files to be loaded */
var sql_list_stage = " list @" + STAGENAME + "; ";
var stmt_list_stage = snowflake.createStatement(
  {sqlText: sql_list_stage}
);

/* get only files to upload: using "ADM"."PROCESS_LOG" */
var sql_get_needed_files = " SELECT t.\\"name\\", t.\\"md5\\", regexp_substr(t.\\"name\\", ''^(.+)\\/([^\\/]+)$'', 1, 1, ''e'', 1) as fpath, regexp_substr(t.\\"name\\", ''^(.+)\\/([^\\/]+)$'', 1, 1, ''e'', 2) as fname "
sql_get_needed_files += "         , c.TARGET_TABLE, coalesce(c.TARGET_SCHEMA_NAME, ''PUBLIC'') as TARGET_SCHEMA_NAME_CURRENT, c.ROW_NODE, c.INTERNAL_FNAME_PATTERN, c.FILE_FORMAT, sum(coalesce(p.PROCESS_STATUS, -1)) as ProcessStatusAgg, c.START_LINE, C.END_LINE, C.NODE_COLUMNS "
sql_get_needed_files += "    FROM table(result_scan(last_query_id())) as t "
sql_get_needed_files += "          join \\"ADM\\".\\"CONFIG\\" c on t.\\"name\\" like ''%''||c.FNAME_PATTERN||''%'' "
sql_get_needed_files += "          left join \\"ADM\\".\\"PROCESS_LOG\\" p on p.SOURCE_NAME = regexp_substr(t.\\"name\\", ''^(.+)\\/([^\\/]+)$'', 1, 1, ''e'', 2) "
sql_get_needed_files += "                                                     and p.\\"SOURCE_MD5\\" = t.\\"md5\\" "
sql_get_needed_files += "    where fpath||''/'' = ''" + sroot + "'' "
if (FILENAME) {
	sql_get_needed_files += "  and (regexp_substr(t.\\"name\\", ''^(.+)\\/([^\\/]+)$'', 1, 1, ''e'', 2) like ''%" + FILENAME + "%'' or ''" + FILENAME + "'' = '''')"
}
sql_get_needed_files += "    and TARGET_SCHEMA_NAME_CURRENT = current_schema() "
sql_get_needed_files += "    group by t.\\"name\\", t.\\"md5\\", c.TARGET_TABLE, TARGET_SCHEMA_NAME_CURRENT, c.ROW_NODE, c.INTERNAL_FNAME_PATTERN, c.FILE_FORMAT, c.START_LINE, c.END_LINE, c.NODE_COLUMNS"
sql_get_needed_files += "    having ProcessStatusAgg <= 0 "
sql_get_needed_files += "    order by fname, TARGET_TABLE, TARGET_SCHEMA_NAME_CURRENT, ROW_NODE;";
var stmt_get_needed_files = snowflake.createStatement(
  {sqlText: sql_get_needed_files}
);

var processedCount = 0;
var skippedCount = 0;
var warningCount = 0;


/* try get files to upload */
try {
    var rs_list_stage = stmt_list_stage.execute();
    var rs_get_needed_files = stmt_get_needed_files.execute();
}
catch (err) {
//Hard Stop for this stage, without this scripts processing can''t start
    return "Failed : " + err + "| SQL: " + stmt_list_stage.getSqlText() + stmt_get_needed_files.getSqlText();
}

/* parametrized string for USP_MODIFY_PROCESS_LOG call */
var sql_modify_processlog = "call adm.USP_MODIFY_PROCESSLOG (:1, :2, :3, :4, :5, :6, :7, :8, :9, :10, :11);";


/* parametrized string for USP_LOG_ERROR call */
var sql_log_error = ''call adm.USP_LOG_ERROR (:1, :2, :3, :4, :5, :6, :7, :8);'';

var nFname = '''';
/* loop through all files for processing */
while (rs_get_needed_files.next()) {
	var fname = rs_get_needed_files.getColumnValue(4);
	if(fname != nFname && nFname != '''') {
		/* update PROCESSLOG for previous archive */
		snowflake.execute(
			{
			  sqlText: sql_modify_processlog, 
			  binds: [batchKey, nFname, fMD5, fpath, '' '','''', 0, 0, 2, '''', '''']
			}
		);
		nFname = '''';
	}
	
	var fpath = rs_get_needed_files.getColumnValue(3);
	var targetTable = rs_get_needed_files.getColumnValue(5);
	var targetSchema = rs_get_needed_files.getColumnValue(6);
	var internalFname = rs_get_needed_files.getColumnValue(8);
	var fileFormat = rs_get_needed_files.getColumnValue(9);
	var fMD5 = rs_get_needed_files.getColumnValue(2);
	var startLine = rs_get_needed_files.getColumnValue(11);
	var endLine = rs_get_needed_files.getColumnValue(12);
	var nodeColumns = rs_get_needed_files.getColumnValue(13);
    var fileFormatHeaders = "UNCOMPRESSED_CSVFMT";
    
    /* create statement to get delimiter from file format in Config Table*/
    /* execute Describe*/
    var sql_get_delimiter_desc = " DESC FILE FORMAT " + fileFormat + ";   ";
    var stmt_get_delimiter_desc = snowflake.createStatement(
      {sqlText: sql_get_delimiter_desc}
    );
    
    /* create statement to get delimiter from file format in Config Table*/
    /* execute last_query_id*/
    var sql_get_delimiter_last_query = " select \\"property_value\\" from table(result_scan(last_query_id())) where \\"property\\" = ''FIELD_DELIMITER''; ";
    var stmt_get_delimiter_last_query = snowflake.createStatement(
      {sqlText: sql_get_delimiter_last_query}
    );
    try {	
        var rs_get_delimiter_desc = stmt_get_delimiter_desc.execute();
		var rs_get_delimiter_last_query = stmt_get_delimiter_last_query.execute();
        rs_get_delimiter_last_query.next();
        var fileFormatDelimiter = rs_get_delimiter_last_query.getColumnValue(1);
	}
	catch (err) {
		//return "Failed : " + err + "| SQL: " + stmt_get_delimiter_desc.getSqlText() + stmt_get_delimiter_last_query.getSqlText();
		snowflake.execute(
			{
			  sqlText: sql_log_error, 
			  binds: [0, ''GetFileDelimiter'', 10001, err.toString().replace(/''/g, ""), stmt_get_delimiter_desc.getSqlText().replace(/''/g, ""), 1, fname, null]
			}
		);
	}
    
	/* check file status for parallel processing */
	var sql_check_file_status = " select SOURCE_NAME, TARGET_NAME, \\"SOURCE_MD5\\", sum(coalesce(PROCESS_STATUS, -1)) as ProcessStatusAgg from \\"ADM\\".\\"PROCESS_LOG\\"  "
	sql_check_file_status += "    where upper(SOURCE_NAME) = upper(''" + fname + "'') and upper(TARGET_NAME) = upper(''" + targetTable + "'') and \\"SOURCE_MD5\\" = ''" + fMD5 + "'' "
	sql_check_file_status += "    group by SOURCE_NAME, TARGET_NAME, \\"SOURCE_MD5\\" having ProcessStatusAgg >= 1";
	var stmt_check_file_status = snowflake.createStatement(
	  {sqlText: sql_check_file_status}
	);
	try {	
		var rs_check_file_status = stmt_check_file_status.execute();
		if (rs_check_file_status.next()){
			skippedCount++;
			continue;
		}
	}
	catch (err) {
		/* return "Failed: " + err + "| SQL: " + stmt_check_file_status.getSqlText(); */
        snowflake.execute(
			{
			  sqlText: sql_log_error, 
			  binds: [0, ''GetFileStatus'', 10001, err.toString().replace(/''/g, ""), stmt_check_file_status.getSqlText().replace(/''/g, ""), 1, fname, null]
			}
		);
	}
	
	/* get start and end of file in case of multiple files in the zip */
	var sof = 0;
	if (internalFname) {
		/* create batch key and insert into PROCESSLOG */
		if(fname != nFname) {
			nFname = fname;
			var rs_insert_prlog = snowflake.execute(
				{
				  sqlText: sql_modify_processlog, 
				  binds: [null, fname, fMD5, fpath, '' '','''', 0, 0, 1, '''', '''']
				}
			);

			if(rs_insert_prlog.next()) {
				var batchres = rs_insert_prlog.getColumnValue(1);
				var columns = batchres.split(":");
				batchKey = columns[2];
				processKey = columns[2];
			} 
			else {
				/* return "something wrong with process log insert, process is not started"; */
                snowflake.execute(
					{
					  sqlText: sql_log_error, 
					  binds: [0, ''GetNewProcessKey'', 10002, "something wrong with process log insert, process is not started", sql_modify_processlog, 1, fname, null]
					}
				);
			}
		}
	
		var sql_get_seof = " select sof, eof, fname from ( "
		sql_get_seof += "   select METADATA$FILE_ROW_NUMBER -1 as sof, lead(METADATA$FILE_ROW_NUMBER) over (order by METADATA$FILE_ROW_NUMBER)-1  as eof, raw_csv.$1 rec, REGEXP_SUBSTR(raw_csv.$1, ''\\\\\\\\d?+\\\\\\\\w?+[.]?\\\\\\\\w?+[.]?\\\\\\\\w?+[.]?\\\\\\\\w?+[.]?\\\\\\\\w+[.]?\\\\\\\\d?+[.]csv'', 1, 1) as fname "
		sql_get_seof += "   from @" + STAGENAME + "/" + fname + " (file_format =>" + fileFormat + ") as raw_csv "
		sql_get_seof += "   where raw_csv.$1 like ''%.csv%'' "
		sql_get_seof += "   ) as files "
		sql_get_seof += " where fname like ''%" + internalFname + "%'' "
		var stmt_get_seof = snowflake.createStatement(
		  {sqlText: sql_get_seof}
		);
		var rs_get_seof = stmt_get_seof.execute();
		
		if(rs_get_seof.next()) {
			var sof = rs_get_seof.getColumnValue(1);
			var eof = rs_get_seof.getColumnValue(2);
			internalFname = "/" + rs_get_seof.getColumnValue(3);
			
			/* get internal processKey key and insert into PROCESSLOG */
			var rs_insert_prlog = snowflake.execute(
				{
				  sqlText: sql_modify_processlog, 
				  binds: [batchKey, fname + internalFname, fMD5, fpath, targetTable,'''', 0, 0, 1, '''', '''']
				}
			);
			
			rs_insert_prlog.next();
			var batchres = rs_insert_prlog.getColumnValue(1);
			var columns = batchres.split(":")
			
			if (columns[0] == "Insert Succeded")
				processKey = columns[2];
		}
		else {
			/* if specific internal file is not found going to the next one */
			skippedCount++;
			snowflake.execute(
				{
				  sqlText: sql_modify_processlog, 
				  binds: [batchKey, fname + internalFname, fMD5, fpath, targetTable,'''', 0, 0, 2, '''', '''']
				}
			);
			continue;
		}
	}
	else
	{
		var rs_insert_prlog = snowflake.execute(
			{
			  sqlText: sql_modify_processlog, 
			  binds: [null, fname, fMD5, fpath, targetTable,'''', 0, 0, 1, '''', '''']
			}
		);

		if(rs_insert_prlog.next()) {
			var batchres = rs_insert_prlog.getColumnValue(1);
			var columns = batchres.split(":");
			batchKey = columns[2];
			processKey = columns[2];
		} 
		else {
			//return "something wrong with process log insert, process is not started";
            snowflake.execute(
				{
				  sqlText: sql_log_error, 
				  binds: [0, ''GetNewProcessKey'', 10002, "something wrong with process log insert, process is not started", sql_modify_processlog, 1, fname, null]
				}
			);
		}

		internalFname = "";
	}
	
	/*Get end of file line if last file in the zip*/
	if(!eof && endLine != 0) {
		var sql_get_new_eof =" select max(METADATA$FILE_ROW_NUMBER)-1 as calc_eof ";
		sql_get_new_eof +=  "  from @"+ STAGENAME + "/"+  fname +" ";
		sql_get_new_eof += " (file_format => " + fileFormat + ") as raw_csv ";
		
		var stmt_sql_get_new_eof = snowflake.createStatement(
		  {sqlText: sql_get_new_eof}
		);
		
		try {
			var rs_sql_get_new_eof = stmt_sql_get_new_eof.execute();
		}
		catch (err) {
			//return "Failed: " + err + "| SQL: " + stmt_sql_get_new_eof.getSqlText();
		
			/* update PROCESSLOG */
			snowflake.execute(
				{
				  sqlText: sql_modify_processlog, 
				  binds: [batchKey, fname + internalFname, fMD5, fpath, targetTable, '''', 0, 0, 0, stmt_sql_get_new_eof.getSqlText().replace(/''/g, ""), '''']
				}
			);
			
			if(nFname != '''') {
			/* update PROCESSLOG for previous archive */
				snowflake.execute(
					{
					  sqlText: sql_modify_processlog, 
					  binds: [batchKey, nFname, fMD5, fpath, '' '', '''', 0, 0, 0, '''', '''']
					}
				);
			}

      /* logging current error */
			snowflake.execute(
				{
				  sqlText: sql_log_error, 
				  binds: [processKey, ''GetNewEndOfFile'', 10003, err.toString().replace(/''/g, ""), stmt_sql_get_new_eof.getSqlText().replace(/''/g, ""), 2, fname, null]
				}
			);

			skippedCount++;
			continue;	
        
		}
		
		rs_sql_get_new_eof.next();
		var eof =  rs_sql_get_new_eof.getColumnValue(1);
	}
	
	/* Getting column headers and t.$ values to build insert statement */
	var sql_meta_column_headers = "select  REGEXP_REPLACE(rtrim(val) , ''\\\\\\s*,\\\\\\s*$'', '''') as val_key, col_hd from( ";
	sql_meta_column_headers += " select listagg(case ";
	sql_meta_column_headers += " when col.DATA_TYPE  like ''TIMESTAMP%'' then ''case when (t.$''||(c.INDEX+1)::int || '' ilike ''''%nan%'''' or t.$''||(c.INDEX+1)::int || '' ilike ''''%#NAME?%'''' or coalesce(TRY_TO_TIMESTAMP(t.$''||(c.INDEX+1)::int || ''), TRY_TO_TIMESTAMP(t.$''||(c.INDEX+1)::int || '', ''''MM/DD/YYYY HH24:MI:SS.FF''''), TRY_TO_TIMESTAMP(t.$''||(c.INDEX+1)::int || '', ''''MM/DD/YYYY HH12:MI:SS AM''''), TRY_TO_TIMESTAMP(t.$''||(c.INDEX+1)::int || '', ''''YYYYMMDD.FF'''')) is null) then NULL else coalesce(TRY_TO_TIMESTAMP(t.$''||(c.INDEX+1)::int || ''), TRY_TO_TIMESTAMP(t.$''||(c.INDEX+1)::int || '', ''''MM/DD/YYYY HH24:MI:SS.FF''''), TRY_TO_TIMESTAMP(t.$''||(c.INDEX+1)::int || '', ''''MM/DD/YYYY HH12:MI:SS AM''''), TRY_TO_TIMESTAMP(t.$''||(c.INDEX+1)::int || '', ''''YYYYMMDD.FF'''')) end'' ";
	sql_meta_column_headers += " when col.DATA_TYPE = ''NUMBER'' then ''case when (t.$''||(c.INDEX+1)::int || '' ilike ''''%nan%'''' or t.$''||(c.INDEX+1)::int || '' ilike ''''%#NAME?%'''' or len(split_part(t.$''||(c.INDEX+1)::int || '',''''.'''', 1)) > '' || col.NUMERIC_PRECISION || '') then NULL WHEN t.$'' ||(c.INDEX+1) || '' LIKE ''''%,%'''' THEN TRY_TO_NUMBER(REPLACE(t.$''||(c.INDEX+1) || '', '''','''')'' || '', '' || col.NUMERIC_PRECISION || '','' || NUMERIC_SCALE || '') else TRY_TO_NUMBER(t.$''||(c.INDEX+1)::int || '', '' || col.NUMERIC_PRECISION || '','' || NUMERIC_SCALE || '') end'' ";
	sql_meta_column_headers += " when col.DATA_TYPE = ''FLOAT'' then ''case when (t.$''||(c.INDEX+1)::int || '' ilike ''''%nan%'''' or t.$''||(c.INDEX+1)::int || '' ilike ''''%#NAME?%'''') then NULL WHEN t.$''||(c.INDEX+1) || '' LIKE ''''%,%'''' THEN TRY_TO_DOUBLE(REPLACE(t.$''||(c.INDEX+1) || '', '''','''')'' || '') else TRY_TO_DOUBLE(t.$''||(c.INDEX+1)::int || '') end '' ";
	sql_meta_column_headers += " when col.DATA_TYPE = ''DATE'' then ''case when (t.$''||(c.INDEX+1)::int || '' ilike ''''%nan%'''' or t.$''||(c.INDEX+1)::int || '' ilike ''''%#NAME?%'''')  then NULL else TRY_TO_DATE(t.$''||(c.INDEX+1)::int || '') end '' ";
	sql_meta_column_headers += " else ''case when (len(t.$''||(c.INDEX+1)::int || '') > '' || coalesce(col.CHARACTER_MAXIMUM_LENGTH, 16777216) || '') then NULL else t.$''||(c.INDEX+1)::int || '' end '' end  || '' ";
    sql_meta_column_headers += " as ''|| " + COLUMN_NAMING_FUNCTION + "(replace(c.value, ''\\"\\'')), '','') as val, ";
	sql_meta_column_headers += " '' PROCESS_KEY, BATCH_KEY, BUSINESS_DATE, FNAME, '' || LISTAGG(" + COLUMN_NAMING_FUNCTION + "(replace(c.value, ''\\"\\'')), '', '') as col_hd ";
	sql_meta_column_headers += " from (select c.value, c.index, METADATA$FILE_ROW_NUMBER from @"+ STAGENAME + "/"+  fname +" (file_format => " + fileFormatHeaders + ") t, ";
	sql_meta_column_headers += " lateral flatten(input=>SPLIT(t.$1, ''" + fileFormatDelimiter + "'' )) c ) c";
	sql_meta_column_headers += " left join \\"INFORMATION_SCHEMA\\".\\"COLUMNS\\" col on col.table_name = ''" + targetTable + "'' AND col.table_schema =''" + targetSchema + "'' AND col.COLUMN_NAME = " + COLUMN_NAMING_FUNCTION + "(replace(c.value, ''\\"'')) ";
	sql_meta_column_headers += " where METADATA$FILE_ROW_NUMBER = (" + sof + " + " + startLine + ")";
	sql_meta_column_headers += " AND C.VALUE <> '''' AND C.VALUE IS NOT NULL  )"
	
	/* get data from headers */
	if (nodeColumns)
	{
		var sql_meta_column_upper_headers = "select  REGEXP_REPLACE(rtrim(val) , ''\\\\\\s*,\\\\\\s*$'', '''') as val_key, col_hd from( ";
		sql_meta_column_upper_headers += " select listagg('' coalesce( '''''''''''''''' ||'' || case ";
		sql_meta_column_upper_headers += " when col.DATA_TYPE  like ''TIMESTAMP%'' then ''case when (t.$''||(c.INDEX+1)::int || '' ilike ''''%nan%'''' or t.$''||(c.INDEX+1)::int || '' ilike ''''%#NAME?%'''' or coalesce(TRY_TO_TIMESTAMP(t.$''||(c.INDEX+1)::int || ''), TRY_TO_TIMESTAMP(t.$''||(c.INDEX+1)::int || '', ''''MM/DD/YYYY HH24:MI:SS.FF''''), TRY_TO_TIMESTAMP(t.$''||(c.INDEX+1)::int || '', ''''MM/DD/YYYY HH12:MI:SS AM''''), TRY_TO_TIMESTAMP(t.$''||(c.INDEX+1)::int || '', ''''YYYYMMDD.FF'''')) is null) then NULL else coalesce(TRY_TO_TIMESTAMP(t.$''||(c.INDEX+1)::int || ''), TRY_TO_TIMESTAMP(t.$''||(c.INDEX+1)::int || '', ''''MM/DD/YYYY HH24:MI:SS.FF''''), TRY_TO_TIMESTAMP(t.$''||(c.INDEX+1)::int || '', ''''MM/DD/YYYY HH12:MI:SS AM''''), TRY_TO_TIMESTAMP(t.$''||(c.INDEX+1)::int || '', ''''YYYYMMDD.FF'''')) end || '''''''''''' as  '' || " + COLUMN_NAMING_FUNCTION + "(replace(c.value, ''\\"\\'')) || '' , ''''  ,  ''''NULL AS '' || " + COLUMN_NAMING_FUNCTION + "(replace(c.value, ''\\"\\'')) || '','''')'' ";
		sql_meta_column_upper_headers += " when col.DATA_TYPE = ''NUMBER'' then ''case when (t.$''||(c.INDEX+1)::int || '' ilike ''''%nan%'''' or t.$''||(c.INDEX+1)::int || '' ilike ''''%#NAME?%'''' or len(split_part(t.$''||(c.INDEX+1)::int || '',''''.'''', 1)) > '' || col.NUMERIC_PRECISION || '') then NULL WHEN t.$'' ||(c.INDEX+1) || '' LIKE ''''%,%'''' THEN TRY_TO_NUMBER(REPLACE(t.$''||(c.INDEX+1) || '', '''','''')'' || '', '' || col.NUMERIC_PRECISION || '','' || NUMERIC_SCALE || '') else TRY_TO_NUMBER(t.$''||(c.INDEX+1)::int || '', '' || col.NUMERIC_PRECISION || '','' || NUMERIC_SCALE || '') end || '''''''''''' as  '' || " + COLUMN_NAMING_FUNCTION + "(replace(c.value, ''\\"\\'')) || '' , ''''  ,  ''''NULL AS '' || " + COLUMN_NAMING_FUNCTION + "(replace(c.value, ''\\"\\'')) || '','''')''  ";
		sql_meta_column_upper_headers += " when col.DATA_TYPE = ''FLOAT'' then ''case when (t.$''||(c.INDEX+1)::int || '' ilike ''''%nan%'''' or t.$''||(c.INDEX+1)::int || '' ilike ''''%#NAME?%'''') then NULL WHEN t.$''||(c.INDEX+1) || '' LIKE ''''%,%'''' THEN TRY_TO_DOUBLE(REPLACE(t.$''||(c.INDEX+1) || '', '''','''')'' || '') else TRY_TO_DOUBLE(t.$''||(c.INDEX+1)::int || '') end || '''''''''''' as  '' || " + COLUMN_NAMING_FUNCTION + "(replace(c.value, ''\\"\\'')) || '' , ''''  ,  ''''NULL AS '' || " + COLUMN_NAMING_FUNCTION + "(replace(c.value, ''\\"\\'')) || '','''')''   ";
		sql_meta_column_upper_headers += " when col.DATA_TYPE = ''DATE'' then ''case when (t.$''||(c.INDEX+1)::int || '' ilike ''''%nan%'''' or t.$''||(c.INDEX+1)::int || '' ilike ''''%#NAME?%'''')  then NULL else TRY_TO_DATE(t.$''||(c.INDEX+1)::int || '') end || '''''''''''' as  '' || " + COLUMN_NAMING_FUNCTION + "(replace(c.value, ''\\"\\'')) || '' , ''''  ,  ''''NULL AS '' || " + COLUMN_NAMING_FUNCTION + "(replace(c.value, ''\\"\\'')) || '','''')''   ";
		sql_meta_column_upper_headers += " else ''case when (len(t.$''||(c.INDEX+1)::int || '') > '' || coalesce(col.CHARACTER_MAXIMUM_LENGTH, 16777216) || '') then ''''NULL'''' else t.$''||(c.INDEX+1)::int || '' end || '''''''''''' as  '' || " + COLUMN_NAMING_FUNCTION + "(replace(c.value, ''\\"\\'')) || '' , ''''  ,  ''''NULL AS '' || " + COLUMN_NAMING_FUNCTION + "(replace(c.value, ''\\"\\'')) || '','''')''   end  ";
		sql_meta_column_upper_headers += " , '','') as val, ";
		sql_meta_column_upper_headers += " LISTAGG(" + COLUMN_NAMING_FUNCTION + "(replace(c.value, ''\\"\\'')), '', '') as col_hd "
		sql_meta_column_upper_headers += " from (select c.value, c.index, METADATA$FILE_ROW_NUMBER from @"+ STAGENAME + "/"+  fname +" (file_format => " + fileFormatHeaders + ") t, ";
		sql_meta_column_upper_headers += " lateral flatten(input=>SPLIT(t.$1, ''" + fileFormatDelimiter + "'' )) c ) c";
		sql_meta_column_upper_headers += " join \\"INFORMATION_SCHEMA\\".\\"COLUMNS\\" col on col.table_name = ''" + targetTable + "'' AND col.table_schema =''" + targetSchema + "'' AND col.COLUMN_NAME = " + COLUMN_NAMING_FUNCTION + "(replace(c.value, ''\\"'')) ";
		sql_meta_column_upper_headers += " where METADATA$FILE_ROW_NUMBER = (" + sof + " + " + nodeColumns + " )";
		sql_meta_column_upper_headers += " AND C.VALUE <> '''' AND C.VALUE IS NOT NULL ORDER BY C.INDEX)"
	}
    
	var stmt_meta_sql_column_headers = snowflake.createStatement(
	  {sqlText: sql_meta_column_headers}
	);
    
	if (nodeColumns)
	{
		var stmt_meta_sql_column_upper_headers = snowflake.createStatement(
		  {sqlText: sql_meta_column_upper_headers}
		);
	}
	
   try {
		var rs_sql_meta_column_headers = stmt_meta_sql_column_headers.execute();
		if (nodeColumns)
		{	
			var rs_sql_meta_column_upper_headers = stmt_meta_sql_column_upper_headers.execute();
		}
	}
    catch (err) {
		/* update PROCESSLOG */
		snowflake.execute(
			{
			  sqlText: sql_modify_processlog, 
			  binds: [batchKey, fname + internalFname, fMD5, fpath, targetTable, '''', 0, 0, 0, stmt_meta_sql_column_headers.getSqlText().replace(/''/g, ""), '''']
			}
		);
		
		if(nFname != '''' ) {
			/* update PROCESSLOG for previous archive */
				snowflake.execute(
					{
					  sqlText: sql_modify_processlog, 
					  binds: [batchKey, nFname, fMD5, fpath, '' '','''', 0, 0, 0, '''', '''']
					}
				);
		}
		
		//return "Failed: " + err + "| SQL: " + stmt_meta_sql_column_headers.getSqlText();
        snowflake.execute(
			{
			  sqlText: sql_log_error, 
			  binds: [processKey, ''GetColumnsHeaders'', 10003, err.toString().replace(/''/g, ""), stmt_meta_sql_column_headers.getSqlText().replace(/''/g, ""), 2, fname, null]
			}
		);

		skippedCount++;
		continue;
   }
   
   rs_sql_meta_column_headers.next();
   var column_headers_meta = rs_sql_meta_column_headers.getColumnValue(1);
   var column_headers_static = rs_sql_meta_column_headers.getColumnValue(2);
   
   if (nodeColumns)
   {
	   rs_sql_meta_column_upper_headers.next();
	   var column_headers_upper_meta = rs_sql_meta_column_upper_headers.getColumnValue(1);
	   var column_headers_upper_static = rs_sql_meta_column_upper_headers.getColumnValue(2);
   }
   
   

	/* Check and change metadata of target table if needed */
	var sql_check_metadata = " CALL USP_MANAGE_TARGET_TABLE (''" + targetSchema + "." + targetTable + "'', ''" + column_headers_static.replace(/"/g, '''', "") + "'', ''" + COLUMN_NAMING_FUNCTION + "'') ";
	
	var stmt_check_metadata = snowflake.createStatement(
	  {sqlText: sql_check_metadata}
	);
	var rs_check_metadata = stmt_check_metadata.execute();
	rs_check_metadata.next();

	/* Cleanup previously inserted data if we have some */
	var sql_cleanup_table = " call USP_CLEANUP_TARGET_TABLE(''" + targetSchema + "." + targetTable + "'', ''" + fname + "''); ";
	var stmt_cleanup_table = snowflake.createStatement(
	  {sqlText: sql_cleanup_table}
	);
	try {
		var rs_cleanup_table = stmt_cleanup_table.execute();
	}
	catch (err) {
		/* update PROCESSLOG */
		snowflake.execute(
			{
			  sqlText: sql_modify_processlog, 
			  binds: [batchKey, fname + internalFname, fMD5, fpath, targetTable, '''', 0, 0, 0, stmt_cleanup_table.getSqlText().replace(/''/g, ""), '''']
			}
		);
		
		if(nFname != '''') {
			/* update PROCESSLOG for previous archive */
				snowflake.execute(
					{
					  sqlText: sql_modify_processlog, 
					  binds: [batchKey, nFname, fMD5, fpath, '' '', '''', 0, 0, 0, '''', '''']
					}
				);
		}		

		//return "Failed: " + err + " step | SQL cleanup text : " + sql_cleanup_table + " | check metadata: " + sql_check_metadata + " | metadata resultset: " + rs_check_metadata.getColumnValue(1) + " | sql get metadata: " + sql_get_child_columns_metadata;
	    snowflake.execute(
			{
			  sqlText: sql_log_error, 
			  binds: [processKey, ''CleanupTable'', 10004, err.toString().replace(/''/g, ""), stmt_cleanup_table.getSqlText().replace(/''/g, ""), 2, fname, null]
			}
		);
    }
	if (nodeColumns)
	{
		if(column_headers_upper_meta.trim() == ''''){
			/* update PROCESSLOG*/
				snowflake.execute(
					{
					  sqlText: sql_modify_processlog, 
					  binds: [batchKey, fname + internalFname, fMD5, fpath, targetTable, '''', 0, 0, 0, '''', '''']
					}
				);
		

		/* logging current error */
		snowflake.execute(
				{
				  sqlText: sql_log_error, 
				  binds: [processKey, ''GetColumnsHeaders'', 10003, "The file is blank" , stmt_meta_sql_column_headers.getSqlText().replace(/''/g, ""), 2, fname, null]
				}
			);
	}
	
		var sql_get_data_from_headers  = "   select rtrim(concat(" + column_headers_upper_meta;
		sql_get_data_from_headers 	  += "   ) , '' ,'') from @"+ STAGENAME + "/"+  fname +" (file_format => " + fileFormat +") t ";
		sql_get_data_from_headers     += "   where METADATA$FILE_ROW_NUMBER > (" + sof + " + " + nodeColumns + " )"
		sql_get_data_from_headers     += "   and METADATA$FILE_ROW_NUMBER < ( "+ startLine + " ) ";
		
		var stmt_get_data_from_headers = snowflake.createStatement(
			{sqlText: sql_get_data_from_headers}
		);
	
	
		var rs_get_data_from_headers = stmt_get_data_from_headers.execute();
		rs_get_data_from_headers.next()
		var headerdata =  rs_get_data_from_headers.getColumnValue(1)
	}
	
	
	
	
		/* Insert data that we have to upload */
	if (nodeColumns)
	{
		var sql_insert_into_table = " insert into " + targetSchema + "." + targetTable + " ";
		sql_insert_into_table += "   (  " + column_headers_static + ", " + column_headers_upper_static + "  ) ";
		sql_insert_into_table += "   select " + processKey + " as PROCESS_KEY, " + batchKey + " as BATCH_KEY, UDF_SF_GET_DATE_FROM_FILENAME(''"+  fname +"'') as BUSINESS_DATE, ''"+  fname +"'' as FNAME, " + column_headers_meta  + " , " + headerdata;
		sql_insert_into_table += "   from @"+ STAGENAME + "/"+  fname +" (file_format => " + fileFormat +") t ";
		sql_insert_into_table += "   where METADATA$FILE_ROW_NUMBER > (" + sof + " + " + startLine +")"
		if(eof) {
			sql_insert_into_table += "      and METADATA$FILE_ROW_NUMBER <=( " + eof + " - " + endLine +")"
		}
    }
	else
	{
		var sql_insert_into_table = " insert into " + targetSchema + "." + targetTable + " ";
		sql_insert_into_table += "   (  " + column_headers_static +  "  ) ";
		sql_insert_into_table += "   select " + processKey + " as PROCESS_KEY, " + batchKey + " as BATCH_KEY, UDF_SF_GET_DATE_FROM_FILENAME(''"+  fname +"'') as BUSINESS_DATE, ''"+  fname +"'' as FNAME, " + column_headers_meta;
		sql_insert_into_table += "   from @"+ STAGENAME + "/"+  fname +" (file_format => " + fileFormat +") t ";
		sql_insert_into_table += "   where METADATA$FILE_ROW_NUMBER > (" + sof + " + " + startLine +")"
		if(eof) {
			sql_insert_into_table += "      and METADATA$FILE_ROW_NUMBER <=( " + eof + " - " + endLine +")"
		}
	}
	

	var stmt_insert_into_table = snowflake.createStatement(
	  {sqlText: sql_insert_into_table}
	);	
	
	
	try {
		var rs_insert_into_table = stmt_insert_into_table.execute();
	}
	catch (err) {
		/* update PROCESSLOG */
		snowflake.execute(
			{
			  sqlText: sql_modify_processlog, 
			  binds: [batchKey, fname + internalFname, fMD5, fpath, targetTable, '''', 0, 0, 0, stmt_insert_into_table.getSqlText().replace(/''/g, ""), '''']
			}
		);
		
		if(nFname != '''') {
			/* update PROCESSLOG for previous archive */
				snowflake.execute(
					{
					  sqlText: sql_modify_processlog, 
					  binds: [batchKey, nFname, fMD5, fpath, '' '', '''', 0, 0, 0, '''', '''']
					}
				);
		}
		
		
		//return "Failed: " + err + "| sql_insert_into_table: " + sql_insert_into_table + "| sql_meta_column_headers: " + sql_meta_column_headers;		
		snowflake.execute(
			{
			  sqlText: sql_log_error, 
			  binds: [processKey, ''InsertData'', 10005, err.toString().replace(/''/g, ""), stmt_insert_into_table.getSqlText().replace(/''/g, ""), 2, fname, null]
			}
		);
		
		skippedCount++;
		continue;
	}
    
    rs_insert_into_table.next(); 
	var row_count = rs_insert_into_table.getColumnValue(1);
	
	if(row_count == 0){
			/* update PROCESSLOG*/
				snowflake.execute(
					{
					  sqlText: sql_modify_processlog, 
					  binds: [batchKey, fname + internalFname, fMD5, fpath, targetTable, '''', 0, 0, 0, '''', '''']
					}
				);
		

		/* logging current error */
		snowflake.execute(
				{
				  sqlText: sql_log_error, 
				  binds: [processKey, ''GetColumnsHeaders'', 10003, "The file is blank" , stmt_meta_sql_column_headers.getSqlText().replace(/''/g, ""), 2, fname, null]
				}
			);
	}
	
	
	/* update PROCESSLOG */
	snowflake.execute(
		{
		  sqlText: sql_modify_processlog, 
		  binds: [batchKey, fname + internalFname, fMD5, fpath, targetTable, '''', row_count,  row_count, 2, sql_meta_column_headers.replace(/''/g, ""), sql_insert_into_table.replace(/''/g, "")]
		}
	);
	
	
	
	var sql_replancements_with_null = " select  REGEXP_REPLACE(rtrim(val) , ''\\\\\\s*,\\\\\\s*$'', '''') as val_key, col_hd, col_fin_hd, col_len from( ";
	sql_replancements_with_null += " select listagg(case ";
	sql_replancements_with_null += " when col.DATA_TYPE  like ''TIMESTAMP%'' then ''case when ((t.$''||(c.INDEX+1)::int || '' is not null and t.$''||(c.INDEX+1)::int || '' != '''''''') and (t.$''||(c.INDEX+1)::int || '' ilike ''''%nan%'''' or t.$''||(c.INDEX+1)::int || '' ilike ''''%#NAME?%'''') or coalesce(TRY_TO_TIMESTAMP(t.$''||(c.INDEX+1)::int || ''), TRY_TO_TIMESTAMP(t.$''||(c.INDEX+1)::int || '', ''''MM/DD/YYYY HH24:MI:SS.FF''''),TRY_TO_TIMESTAMP(t.$''||(c.INDEX+1)::int || '', ''''MM/DD/YYYY HH12:MI:SS AM''''), TRY_TO_TIMESTAMP(t.$''||(c.INDEX+1)::int || '', ''''YYYYMMDD.FF'''')) is null) then t.$''||(c.INDEX+1)::int || '' end'' "
	sql_replancements_with_null += " when col.DATA_TYPE = ''NUMBER'' then ''case when ((t.$''||(c.INDEX+1)::int || '' is not null and t.$'' ||(c.INDEX+1) || '' not LIKE ''''%,%'''' and t.$''||(c.INDEX+1)::int || '' != '''''''') and (t.$''||(c.INDEX+1)::int || '' ilike ''''%nan%'''' or t.$''||(c.INDEX+1)::int || '' ilike ''''%#NAME?%'''') or len(split_part(t.$''||(c.INDEX+1)::int || '',''''.'''', 1)) > '' || col.NUMERIC_PRECISION || '' or len(split_part(t.$''||(c.INDEX+1)::int || '',''''.'''', 2)) > '' || col.NUMERIC_SCALE  ||'' or TRY_TO_NUMBER(t.$''||(c.INDEX+1)::int || '', '' || col.NUMERIC_PRECISION || '','' || NUMERIC_SCALE || '') is null and t.$'' ||(c.INDEX+1) || '' not LIKE ''''%,%'''' ) then  t.$''||(c.INDEX+1)::int || '' end''"
	sql_replancements_with_null += " when col.DATA_TYPE = ''FLOAT'' then ''case when ((t.$''||(c.INDEX+1)::int || '' is not null and t.$'' ||(c.INDEX+1) || '' not LIKE ''''%,%'''' and t.$''||(c.INDEX+1)::int || '' != '''''''') and (t.$''||(c.INDEX+1)::int || '' ilike ''''%nan%'''' or t.$''||(c.INDEX+1)::int || '' ilike ''''%#NAME?%'''') or TRY_TO_DOUBLE(t.$''||(c.INDEX+1)::int || '') is null and t.$'' ||(c.INDEX+1) || '' not LIKE ''''%,%'''' )  then  t.$''||(c.INDEX+1)::int  || '' end '' ";
	sql_replancements_with_null += " when col.DATA_TYPE = ''DATE'' then ''case when ((t.$''||(c.INDEX+1)::int || '' is not null and t.$''||(c.INDEX+1)::int || '' != '''''''') and (t.$''||(c.INDEX+1)::int || '' ilike ''''%nan%'''' or t.$''||(c.INDEX+1)::int || '' ilike ''''%#NAME?%'''') or TRY_TO_DATE(t.$''||(c.INDEX+1)::int || '') is null )  then  t.$''||(c.INDEX+1)::int || '' end '' ";
	sql_replancements_with_null += " else ''case when (len(t.$''||(c.INDEX+1)::int || '') > '' || coalesce(col.CHARACTER_MAXIMUM_LENGTH, 16777216) || '') then  t.$''||(c.INDEX+1)::int || '' end '' end  || ''  as '' || " + COLUMN_NAMING_FUNCTION + "(replace(c.value, ''\\"\\'')), '', '') as val  "
	sql_replancements_with_null += " ,''concat_ws ( ''''  '''', '' || LISTAGG(concat('' '''' '', ''\\"'', " + COLUMN_NAMING_FUNCTION + " (replace(c.value, ''\\"\\'')), ''\\"'', ''  : '''' ,'' || ''coalesce('' || " + COLUMN_NAMING_FUNCTION + "(replace(c.value, ''\\"\\'')) ||'', '''''''')''), '', '') || '')'' as col_hd";
	sql_replancements_with_null += " ,''trim(concat_ws ( ''''  '''', '' || LISTAGG(''iff('' || concat(''\\"'', " + COLUMN_NAMING_FUNCTION + " (replace(c.value, ''\\"\\'')), ''\\"'') || '' is not null, ('' || concat('' '''' ''," +  COLUMN_NAMING_FUNCTION + "(replace(c.value, ''\\"\\'')), '':'''' ||'' || ''coalesce('' ||" + COLUMN_NAMING_FUNCTION + "(replace(c.value, ''\\"\\'')) || '', '''''''')'') || ''), '''''''' )'', '' , '') || ''))''  as col_fin_hd  "		
	sql_replancements_with_null += " ,''len(concat_ws ( ''''  '''', '' || LISTAGG(concat('' '''' '' , ''\\"'', " + COLUMN_NAMING_FUNCTION + "((c.value)),  ''\\"'',  ''  : '''' ,'' || '' '''''''' ''), '', '') || ''))''  as col_len "
	sql_replancements_with_null += " from (select c.value, c.index, METADATA$FILE_ROW_NUMBER from @"+ STAGENAME + "/"+  fname +" (file_format => " + fileFormatHeaders + ") t, ";
	sql_replancements_with_null += " lateral flatten(input=>SPLIT(t.$1, ''" + fileFormatDelimiter + "'' )) c ) c ";
	sql_replancements_with_null += " left join \\"INFORMATION_SCHEMA\\".\\"COLUMNS\\" col on col.table_name = ''" + targetTable + "'' AND col.table_schema =''" + targetSchema + "'' AND col.COLUMN_NAME = " + COLUMN_NAMING_FUNCTION + "(replace(c.value, ''\\"'')) ";
	sql_replancements_with_null += " where METADATA$FILE_ROW_NUMBER = (" + sof + " + " + startLine + ")";
	sql_replancements_with_null += " AND C.VALUE <> '''' AND C.VALUE IS NOT NULL  )"

	
	var stmt_replancements_with_null = snowflake.createStatement(
	  {sqlText: sql_replancements_with_null}
	);
	
	var rs_replancements_with_null = stmt_replancements_with_null.execute()
	rs_replancements_with_null.next()
	replancements_with_null = rs_replancements_with_null.getColumnValue(1)
	rs_get_cols_stmt = rs_replancements_with_null.getColumnValue(2)
	rs_get_cols_final_stmt = rs_replancements_with_null.getColumnValue(3)
	rs_get_cols_len_stmt = rs_replancements_with_null.getColumnValue(4)
	
	var sql_replancements_with_null_columns = " insert into \\"ADM\\".\\"WARNING_LOG\\" "
	sql_replancements_with_null_columns += "with cols_replaced as ("
	sql_replancements_with_null_columns += "select METADATA$FILE_ROW_NUMBER as row_num, "
	sql_replancements_with_null_columns += replancements_with_null + ", "
	sql_replancements_with_null_columns += rs_get_cols_len_stmt + " as len_col, "
	sql_replancements_with_null_columns += rs_get_cols_stmt + "as warning_col "
	sql_replancements_with_null_columns += "   from @"+ STAGENAME + "/"+  fname +" (file_format => " + fileFormat +") t ";
	sql_replancements_with_null_columns += "   where METADATA$FILE_ROW_NUMBER > (" + sof + " + " + startLine +")"
	 if(eof) {
		sql_replancements_with_null_columns += "      and METADATA$FILE_ROW_NUMBER <=( " + eof + " - " + endLine +")"
	}
	sql_replancements_with_null_columns += ") "
	sql_replancements_with_null_columns += "select " + processKey + " as PROCESS_KEY, " + batchKey + " as BATCH_KEY, UDF_SF_GET_DATE_FROM_FILENAME(''"+  fname +"'') as BUSINESS_DATE, ''"+  fname +"'' as FNAME, ''" + targetTable + "'' as TARGET_NAME, ''" + targetSchema + "'' as TARGET_SCHEMA_NAME, " ;
    sql_replancements_with_null_columns += "row_num as FRNUM, " + rs_get_cols_final_stmt + " as WARNING_COLUMN "
	sql_replancements_with_null_columns += "from cols_replaced "
	sql_replancements_with_null_columns += "where len(warning_col) != len_col and trim(WARNING_COLUMN) != '''' "
	
	var stmt_replancements_with_null_columns = snowflake.createStatement(
	  {sqlText: sql_replancements_with_null_columns}
	);
	
	try {
		var rs_replancements_with_null_columns = stmt_replancements_with_null_columns.execute()
	}
	catch (err) {
		
		//return "Failed: " + err + "| sql_insert_into_warning_table: " + sql_insert_into_table + "| sql_replancements_with_null_columns: " + sql_replancements_with_null_columns;		
		snowflake.execute(
			{
			  sqlText: sql_log_error, 
			  binds: [processKey, ''InsertData'', 10005, err.toString().replace(/''/g, ""), stmt_replancements_with_null_columns.getSqlText().replace(/''/g, ""), 2, fname, null]
			}
		);
		continue
	}
	
	rs_replancements_with_null_columns.next()
	
	if (rs_replancements_with_null_columns.getColumnValue(1) != 0) 
		warningCount++;
    processedCount++;
} /* END loop through all files for processing */

if(nFname != '''') { 
	/* update PROCESSLOG for previous archive */
	snowflake.execute(
		{
		  sqlText: sql_modify_processlog, 
		  binds: [batchKey, nFname, fMD5, fpath, '' '', '''', 0, 0, 2, '''', '''']
		}
	);
}

/* call external function */
if (processedCount > 0) {
/* call external function */
var sql_call_external_function = "with prep_json as ( "
sql_call_external_function +=  "select QUERY_ID, START_TIME, END_TIME, SESSION_ID, "       
sql_call_external_function +=  "OBJECT_CONSTRUCT_KEEP_NULL(''START_TIME'', START_TIME, ''ERROR_CODE'', ERROR_CODE, ''QUERY_TAG'', QUERY_TAG, ''DATABASE_NAME'', DATABASE_NAME, ''ERROR_MESSAGE'', ERROR_MESSAGE, ''QUERY_TEXT'', QUERY_TEXT , ''WAREHOUSE_NAME'', WAREHOUSE_NAME, ''USER_NAME'', USER_NAME, ''ROLE_NAME'', ROLE_NAME, ''END_TIME'', END_TIME, ''TOTAL_ELAPSED_TIME'', TOTAL_ELAPSED_TIME, ''QUERY_ID'', QUERY_ID)::string as body, "        
sql_call_external_function +=  "((sum(length(OBJECT_CONSTRUCT_KEEP_NULL(''START_TIME'', START_TIME, ''ERROR_CODE'', ERROR_CODE, ''QUERY_TAG'', QUERY_TAG, ''DATABASE_NAME'', DATABASE_NAME, ''ERROR_MESSAGE'', ERROR_MESSAGE, ''QUERY_TEXT'', QUERY_TEXT, ''WAREHOUSE_NAME'', WAREHOUSE_NAME, ''USER_NAME'', USER_NAME, ''ROLE_NAME'', ROLE_NAME, ''END_TIME'', END_TIME, ''TOTAL_ELAPSED_TIME'', TOTAL_ELAPSED_TIME, ''QUERY_ID'', QUERY_ID)::string )) "
sql_call_external_function +=  "over (order by QUERY_ID, START_TIME, END_TIME, SESSION_ID desc))/2000000)::int as r_num "
sql_call_external_function +=  "from table(information_schema.query_history_by_session(result_limit => 10000)) "
sql_call_external_function +=  "where user_name in (''ADM_BATCH_DEV'', ''ADM_BATCH_PROD'') and (TOTAL_ELAPSED_TIME > 900000) and START_TIME is not null and END_TIME is not null) " 
sql_call_external_function +=  "select UDF_EF_SPLUNK_LOGGER(listagg(replace(body, '''''''', ''''), '','')) as v_json from prep_json group by r_num ;"

var stmt_call_external_function = snowflake.createStatement(
	{sqlText: sql_call_external_function}
);

var rs_call_external_function = stmt_call_external_function.execute()
}
if (warningCount == 0){
	return "Files processed: " + processedCount + " | Files skipped : " + skippedCount + " | Warnings : " + warningCount
}
else {
	return "Files processed: " + processedCount + " | Files skipped : " + skippedCount + " | Warnings : " + warningCount + " - Notification required" ; 
}

';