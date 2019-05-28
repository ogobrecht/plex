@echo off
set NLS_LANG=AMERICAN_AMERICA.AL32UTF8
echo exit | sqlplus -S sys/oracle@localhost/v181 as sysdba @plex_install.sql
