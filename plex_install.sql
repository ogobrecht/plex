SET DEFINE OFF FEEDBACK OFF
WHENEVER SQLERROR EXIT sql.sqlcode ROLLBACK
prompt
prompt Installing PL/SQL Export Utilities
prompt ==================================
prompt Set compiler flags
DECLARE
  v_utils_public     VARCHAR2(5) := 'TRUE'; -- make utilities public available (for testing or other usages)
  v_apex_installed   VARCHAR2(5) := 'FALSE'; -- do not change (is set dynamically)
  v_ords_installed   VARCHAR2(5) := 'FALSE'; -- do not change (is set dynamically)
BEGIN
  FOR i IN (
    SELECT *
      FROM all_objects
     WHERE object_type = 'SYNONYM'
       AND object_name = 'APEX_EXPORT'
  ) LOOP v_apex_installed := 'TRUE';
  END LOOP;

  FOR i IN (
    SELECT *
      FROM all_objects
     WHERE object_type = 'SYNONYM'
       AND object_name = 'ORDS_EXPORT'
  ) LOOP v_ords_installed := 'TRUE';
  END LOOP;
  
  EXECUTE IMMEDIATE 'alter session set plsql_ccflags = ''' || 
    'utils_public:'   || v_utils_public   || ', ' || 
    'apex_installed:' || v_apex_installed || ', ' || 
    'ords_installed:' || v_ords_installed || '''';
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
