set define off
set serveroutput on
set verify off
set feedback off
set linesize 240
set trimout on
set trimspool on
whenever sqlerror exit sql.sqlcode rollback

prompt
prompt Uninstalling PL/SQL Export Utilities
prompt ============================================================
prompt Drop package plex if exists (body)
begin
  for i in (select object_type,
                   object_name
              from user_objects
             where object_type = 'PACKAGE body'
               and object_name = 'PLEX') loop
    execute immediate 'drop ' || i.object_type || ' ' || i.object_name;
  end loop;
end;
/
prompt Drop package plex if exists (spec)
begin
  for i in (select object_type,
                   object_name
              from user_objects
             where object_type = 'PACKAGE'
               and object_name = 'PLEX') loop
    execute immediate 'drop ' || i.object_type || ' ' || i.object_name;
  end loop;
end;
/
prompt ============================================================
prompt Uninstallation Done
prompt
