timing start test_table
set verify off feedback off heading off
set trimout on trimspool on pagesize 0 linesize 5000 long 100000000 longchunksize 32767
whenever sqlerror exit sql.sqlcode rollback
whenever oserror continue
variable zip clob

prompt
prompt Test Data Export: Create Table
prompt ================================================================================

prompt Drop existing test objects
begin
  for i in (
    select object_type, object_name
      from user_objects
     where object_type = 'TABLE'   and object_name = 'PLEX_TEST_MULTIPLE_DATATYPES'
        or object_type = 'PACKAGE' and object_name = 'PLEX_TEST_MULTIPLE_DATATYPES_API')
  loop
    execute immediate 'drop ' || i.object_type || ' ' || i.object_name;
  end loop;
end;
/

prompt Create table plex_test_multiple_datatypes
begin
  for i in (
    select 'PLEX_TEST_MULTIPLE_DATATYPES' from dual
    minus
    select object_name from user_objects)
  loop
    execute immediate q'[
      create table plex_test_multiple_datatypes (
        ptmd_id                      integer                         generated by default on null as identity    ,
        ptmd_varchar                 varchar2(15 char)                                                           ,
        ptmd_char                    char(1 char)                    not null                                    ,
        ptmd_integer                 integer                                                                     ,
        ptmd_number                  number                                                                      ,
        ptmd_number_x_5              number(*,5)                                                                 ,
        ptmd_number_20_5             number(20,5)                                                                ,
        ptmd_virtual                 number                          as (ptmd_number / ptmd_number_x_5) virtual  ,
        ptmd_float                   float                                                                       ,
        ptmd_float_size_30           float(30)                                                                   ,
        ptmd_xmltype                 xmltype                                                                     ,
        ptmd_clob                    clob                                                                        ,
        ptmd_blob                    blob                                                                        ,
        ptmd_date                    date                                                                        ,
        ptmd_timestamp               timestamp                                                                   ,
        ptmd_timestamp_tz            timestamp with time zone                                                    ,
        ptmd_timestamp_ltz           timestamp with local time zone                                              ,
        ptmd_interval_day_to_second  interval day (2) to second (6)                                              ,
        ptmd_interval_year_to_month  interval year (2) to month                                                  ,
        --
        primary key (ptmd_id)
      )
    ]';
  end loop;
end;
/

prompt Create table API for plex_test_multiple_datatypes
begin
  for i in (
    select 'PLEX_TEST_MULTIPLE_DATATYPES_API' from dual
    minus
    select object_name from user_objects)
  loop
    om_tapigen.compile_api(
      p_table_name             => 'PLEX_TEST_MULTIPLE_DATATYPES',
      p_enable_custom_defaults => true);
  end loop;
end;
/

timing stop
prompt ================================================================================
prompt Done :-)
prompt
