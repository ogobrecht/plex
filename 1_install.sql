SET DEFINE OFF FEEDBACK OFF
WHENEVER SQLERROR EXIT sql.sqlcode ROLLBACK
prompt
prompt Installing PL/SQL Export Utilities
prompt ==================================
prompt - Set compiler flags
DECLARE
  v_utils_public     VARCHAR2(5) := 'true'; -- make utilities public available (for testing or other usages)
  v_apex_installed   VARCHAR2(5) := 'false'; -- do not change (is set dynamically)
  v_ords_installed   VARCHAR2(5) := 'false'; -- do not change (is set dynamically)
BEGIN
  FOR i IN (
    SELECT *
      FROM all_objects
     WHERE object_name = 'APEX_EXPORT'
  ) LOOP v_apex_installed := 'true';
  END LOOP;
  FOR i IN (
    SELECT *
      FROM all_objects
     WHERE object_name = 'ORDS_EXPORT'
  ) LOOP v_ords_installed := 'true';
  END LOOP;
  EXECUTE IMMEDIATE q'[alter session set plsql_ccflags='utils_public:]' || v_utils_public || q'[']';
  EXECUTE IMMEDIATE q'[alter session set plsql_ccflags='apex_installed:]' || v_apex_installed || q'[']';
  EXECUTE IMMEDIATE q'[alter session set plsql_ccflags='ords_installed:]' || v_ords_installed || q'[']';
END;
/
prompt - Compile package plex (spec)
@plex.pks
prompt - Compile package plex (body)
@plex.pkb
prompt ==================================
prompt Installation Done :-)
prompt
