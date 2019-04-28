@echo off
set NLS_LANG=AMERICAN_AMERICA.AL32UTF8
echo exit | sqlplus -S plex_light/oracle@localhost/v181 @plex_install.sql
