set define off feedback off
whenever sqlerror exit sql.sqlcode rollback

prompt
prompt Uninstalling PL/SQL Export Utilities
prompt ====================================
prompt Drop package plex if exists (body)
BEGIN
  FOR i IN (SELECT object_type,
                   object_name
              FROM user_objects
             WHERE object_type = 'PACKAGE BODY'
               AND object_name = 'PLEX') LOOP
    EXECUTE IMMEDIATE 'DROP ' || i.object_type || ' ' || i.object_name;
  END LOOP;
END;
/
prompt Drop package plex if exists (spec)
BEGIN
  FOR i IN (SELECT object_type,
                   object_name
              FROM user_objects
             WHERE object_type = 'PACKAGE'
               AND object_name = 'PLEX') LOOP
    EXECUTE IMMEDIATE 'DROP ' || i.object_type || ' ' || i.object_name;
  END LOOP;
END;
/
prompt ====================================
prompt Uninstallation Done
prompt