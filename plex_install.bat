@echo off
set NLS_LANG=AMERICAN_AMERICA.AL32UTF8
echo exit | sqlplus -S ogobrecht/oracle@localhost/v191 @plex_install.sql
