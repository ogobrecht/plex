timing start test_export
set verify off feedback off heading off
set trimout on trimspool on pagesize 0 linesize 5000 long 100000000 longchunksize 32767
whenever sqlerror exit sql.sqlcode rollback
whenever oserror continue
variable zip clob

prompt
prompt Test Export App Into ZIP File
prompt ================================================================================

prompt Set NLS parameters
alter session set nls_numeric_characters  = '.,';
alter session set nls_date_format         = 'yyyy-mm-dd hh24:mi:ss';
alter session set nls_timestamp_format    = 'yyyy-mm-dd hh24:mi:ssxff';
alter session set nls_timestamp_tz_format = 'yyyy-mm-dd hh24:mi:ssxff tzr';

prompt Run plex.backapp (this can take some time...)
BEGIN
  :zip := plex.to_base64(plex.to_zip(plex.backapp(
    p_app_id                    => 100,
    p_include_ords_modules      => true,
    p_include_object_ddl        => true,
    p_include_data              => true,
    --p_data_table_name_like      => 'OEHR\_%',
    p_data_max_rows             => 10000,
    p_data_format               => 'csv,insert:10',
    --
    p_base_path_backend         => 'app_backend',
    p_base_path_frontend        => 'app_frontend',
    p_base_path_web_services    => 'app_web_services',
    p_base_path_data            => 'app_data',
    p_base_path_docs            => 'documents',
    p_base_path_tests           => 'unit_tests',
    p_base_path_scripts         => 'deploy_scripts',
    p_base_path_script_logs     => 'deploy_logs',
    p_scripts_working_directory => '',
    p_include_templates         => true
  )));
END;
/

prompt Delete old zip file from previous test:
host del app_100.zip

set termout off
spool "app_100.zip.base64"
print zip
spool off
set termout on

prompt Exract zip on host operating system:
prompt Try Windows: certutil -decode app_100.zip.base64 app_100.zip
host certutil -decode app_100.zip.base64 app_100.zip
prompt Try Mac: base64 -D -i app_100.zip.base64 -o app_100.zip
host base64 -D -i app_100.zip.base64 -o app_100.zip
prompt Try Linux: base64 -d app_100.zip.base64 app_100.zip
host base64 -d app_100.zip.base64 app_100.zip

prompt Delete base64 encoded file:
prompt Windows, Mac, Linux: del app_100.zip.base64
host del app_100.zip.base64

timing stop
prompt ================================================================================
prompt Done :-)
prompt

