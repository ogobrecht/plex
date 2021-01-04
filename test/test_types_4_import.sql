timing start test_import
set verify off feedback off heading off serveroutput on
set trimout on trimspool on pagesize 0 linesize 5000 long 100000000 longchunksize 32767
whenever sqlerror exit sql.sqlcode rollback
whenever oserror continue

prompt
prompt Test Data Export: Import Previously Exported Data
prompt ================================================================================

prompt Truncate table plex_test_multiple_datatypes
TRUNCATE TABLE plex_test_multiple_datatypes;
@test_types_3_export_file.sql

timing stop
prompt ================================================================================
prompt Done :-)
prompt