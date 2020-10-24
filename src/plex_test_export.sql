timing start test_export
set verify off feedback off heading off timing on
set trimout on trimspool on pagesize 0 linesize 5000 long 100000000 longchunksize 32767
whenever sqlerror exit sql.sqlcode rollback
whenever oserror continue
variable zip clob

prompt
prompt PLEX Test Export
prompt ==================================================

prompt Run plex.backapp (this can take some time...)
BEGIN
  :zip := plex.to_base64(plex.to_zip(plex.backapp(
      p_app_id               => 100,
      p_include_object_ddl   => true,
      p_include_ords_modules => true,
      p_include_data         => true,
      p_data_format          => 'csv,insert',
      p_include_templates    => true)));
END;
/

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
prompt ==================================================
prompt Done :-)
prompt

