timing start test_data
set verify off feedback off heading off
set trimout on trimspool on pagesize 0 linesize 5000 long 100000000 longchunksize 32767
whenever sqlerror exit sql.sqlcode rollback
whenever oserror continue
variable zip clob

prompt
prompt Test Data Export: Create Data
prompt ================================================================================

prompt Truncate table plex_test_multiple_datatypes
truncate table PLEX_TEST_MULTIPLE_DATATYPES;

prompt Insert &1 rows into plex_test_multiple_datatypes
declare
  l_rows_tab       plex_test_multiple_datatypes_api.t_rows_tab;
  l_number_records pls_integer := &1;
begin
  l_rows_tab := plex_test_multiple_datatypes_api.t_rows_tab();
  l_rows_tab.extend(l_number_records);
  for i in 1 .. l_number_records loop
    l_rows_tab(i) := plex_test_multiple_datatypes_api.get_a_row;
  end loop;
  plex_test_multiple_datatypes_api.create_rows(l_rows_tab);
  commit;
end;
/

timing stop
prompt ================================================================================
prompt Done :-)
prompt
