set define off feedback off
whenever sqlerror exit sql.sqlcode rollback

prompt
prompt Installing PL/SQL Export Utilities
prompt ==================================

prompt Show unset compiler flags as errors (results for example in errors like "PLW-06003: unknown inquiry directive '$$UTILS_PUBLIC'"
alter session set plsql_warnings = 'ENABLE:6003';

prompt ---

prompt Set compiler flags to apex_installed:false, ords_installed:false, utils_public:false, debug_on:false
alter session set plsql_ccflags = 'apex_installed:false, ords_installed:false, utils_public:false, debug_on:false';
prompt Compile package plex (spec)
@plex.pks
show errors
prompt Compile package plex (body)
@plex.pkb
show errors

prompt ---

prompt Set compiler flags: apex_installed:true, ords_installed:false, utils_public:false, debug_on:false
alter session set plsql_ccflags = 'apex_installed:true, ords_installed:false, utils_public:false, debug_on:false';
prompt Compile package plex (spec)
@plex.pks
show errors
prompt Compile package plex (body)
@plex.pkb
show errors

prompt ---

prompt Set compiler flags: apex_installed:false, ords_installed:true, utils_public:false, debug_on:false
alter session set plsql_ccflags = 'apex_installed:false, ords_installed:true, utils_public:false, debug_on:false';
prompt Compile package plex (spec)
@plex.pks
show errors
prompt Compile package plex (body)
@plex.pkb
show errors

prompt ---

prompt Set compiler flags: apex_installed:true, ords_installed:true, utils_public:false, debug_on:false
alter session set plsql_ccflags = 'apex_installed:true, ords_installed:true, utils_public:false, debug_on:false';
prompt Compile package plex (spec)
@plex.pks
show errors
prompt Compile package plex (body)
@plex.pkb
show errors

prompt ==================================
prompt Installation Done
prompt
