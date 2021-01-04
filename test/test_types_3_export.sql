timing start test_export
set verify off feedback off heading off serveroutput on
set trimout on trimspool on pagesize 0 linesize 5000 long 100000000 longchunksize 32767
whenever sqlerror exit sql.sqlcode rollback
whenever oserror continue
variable filecontent clob

prompt
prompt Test Data Export: Export Data
prompt ================================================================================

prompt Set NLS parameters
alter session set nls_numeric_characters  = '.,';
alter session set nls_date_format         = 'yyyy-mm-dd hh24:mi:ss';
alter session set nls_timestamp_format    = 'yyyy-mm-dd hh24:mi:ssxff';
alter session set nls_timestamp_tz_format = 'yyyy-mm-dd hh24:mi:ssxff tzr';

prompt Run plex.backapp
DECLARE
  l_file_collection plex.tab_export_files;
BEGIN
  l_file_collection := plex.backapp(
    p_include_data         => true,
    p_data_format          => 'insert:20',
    p_data_table_name_like => 'PLEX_TEST_MULTIPLE_DATATYPES',
    p_include_templates    => false,
    p_include_runtime_log  => false,
    p_include_error_log    => false);
  -- Since we exported only one table and omitted all log files (optional) we
  -- get the file data on the first collection position.
  :filecontent := l_file_collection(1).contents;
END;
/

prompt Spool data to file test_types_3_export_file.sql
set termout off
spool "test_types_3_export_file.sql"
print filecontent
spool off
set termout on

timing stop
prompt ================================================================================
prompt Done :-)
prompt