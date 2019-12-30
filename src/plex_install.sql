set define off feedback off
whenever sqlerror exit sql.sqlcode rollback

prompt
prompt Installing PL/SQL Export Utilities
prompt ==================================

prompt Set compiler flags
DECLARE
  v_apex_installed VARCHAR2(5) := 'FALSE'; -- Do not change (is set dynamically).
  v_ords_installed VARCHAR2(5) := 'FALSE'; -- Do not change (is set dynamically).
  v_utils_public   VARCHAR2(5) := 'FALSE'; -- Make utilities public available (for testing or other usages).
  v_debug_on       VARCHAR2(5) := 'FALSE'; -- Object DDL: extract only one object per type to find problematic ones and save time in big schemas like APEX_XXX.
BEGIN
  FOR i IN (SELECT *
              FROM all_objects
             WHERE object_type = 'SYNONYM'
               AND object_name = 'APEX_EXPORT') LOOP
    v_apex_installed := 'TRUE';
  END LOOP;
  FOR i IN (SELECT *
              FROM all_objects
             WHERE object_type = 'SYNONYM'
               AND object_name = 'ORDS_EXPORT') LOOP
    v_ords_installed := 'TRUE';
  END LOOP;
  -- Show unset compiler flags as errors (results for example in errors like "PLW-06003: unknown inquiry directive '$$UTILS_PUBLIC'")
  EXECUTE IMMEDIATE 'alter session set plsql_warnings = ''ENABLE:6003''';
  -- Finally set compiler flags
  EXECUTE IMMEDIATE 'alter session set plsql_ccflags = '''
    || 'apex_installed:' || v_apex_installed || ','
    || 'ords_installed:' || v_ords_installed || ','
    || 'utils_public:'   || v_utils_public   || ','
    || 'debug_on:'       || v_debug_on       || '''';
END;
/

prompt Compile package plex (spec)
@plex.pks
show errors

prompt Compile package plex (body)
@plex.pkb
show errors

prompt ==================================
prompt Installation Done
prompt
