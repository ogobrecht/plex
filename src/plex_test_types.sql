timing start test_export
set verify off feedback off heading off
set trimout on trimspool on pagesize 0 linesize 5000 long 100000000 longchunksize 32767
whenever sqlerror exit sql.sqlcode rollback
whenever oserror continue
variable zip clob

prompt
prompt PLEX Test Export Format INSERT With Multiple Data Types
prompt =======================================================

--prompt Drop existing test objects
--begin
--  for i in (
--    select object_type, object_name
--      from user_objects
--     where object_type = 'TABLE'   and object_name = 'PLEX_TEST_MULTIPLE_DATATYPES'
--        or object_type = 'PACKAGE' and object_name = 'PLEX_TEST_MULTIPLE_DATATYPES_API')
--  loop
--    execute immediate 'drop ' || i.object_type || ' ' || i.object_name;
--  end loop;
--end;
--/
--
--prompt Create table plex_test_multiple_datatypes
--begin
--  for i in (
--    select 'PLEX_TEST_MULTIPLE_DATATYPES' from dual
--    minus
--    select object_name from user_objects)
--  loop
--    execute immediate q'[
--      create table plex_test_multiple_datatypes (
--        ptmd_id             integer                         generated always as identity,
--        ptmd_varchar        varchar2(15 char)                         ,
--        ptmd_char           char(1 char)                    not null  ,
--        ptmd_integer        integer                                   ,
--        ptmd_number         number                                    ,
--        ptmd_number_x_5     number(*,5)                               ,
--        ptmd_number_20_5    number(20,5)                              ,
--        ptmd_float          float                                     ,
--        ptmd_float_size_30  float(30)                                 ,
--        ptmd_xmltype        xmltype                                   ,
--        ptmd_clob           clob                                      ,
--        ptmd_blob           blob                                      ,
--        ptmd_date           date                                      ,
--        ptmd_timestamp      timestamp                                 ,
--        ptmd_timestamp_tz   timestamp with time zone                  ,
--        ptmd_timestamp_ltz  timestamp with local time zone            ,
--        --
--        primary key (ptmd_id),
--        unique (ptmd_varchar)
--      )
--    ]';
--  end loop;
--end;
--/
--
--prompt Create table API for plex_test_multiple_datatypes
--begin
--  for i in (
--    select 'PLEX_TEST_MULTIPLE_DATATYPES_API' from dual
--    minus
--    select object_name from user_objects)
--  loop
--    om_tapigen.compile_api(
--      p_table_name             => 'PLEX_TEST_MULTIPLE_DATATYPES',
--      p_enable_custom_defaults => true);
--  end loop;
--end;
--/
--
--prompt Insert 100 rows into plex_test_multiple_datatypes
--declare
--  l_rows_tab       plex_test_multiple_datatypes_api.t_rows_tab;
--  l_number_records pls_integer := 100;
--begin
--  l_rows_tab := plex_test_multiple_datatypes_api.t_rows_tab();
--  l_rows_tab.extend(l_number_records);
--  for i in 1 .. l_number_records loop
--    l_rows_tab(i) := plex_test_multiple_datatypes_api.get_a_row;
--  end loop;
--  plex_test_multiple_datatypes_api.create_rows(l_rows_tab);
--  commit;
--end;
--/

prompt Run plex.backapp (this can take some time...)
BEGIN
  :zip := plex.to_base64(plex.to_zip(plex.backapp(
      p_app_id               => null, --100,
      p_include_object_ddl   => false,
      p_include_ords_modules => false,
      p_include_data         => true,
      p_data_format          => 'csv,insert',
      p_data_table_name_like => 'PLEX_TEST_MULTIPLE_DATATYPES',
      p_include_templates    => true)));
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
prompt =======================================================
prompt Done :-)
prompt

