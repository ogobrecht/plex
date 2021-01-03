# Changelog

## 2.4.0 (2021-01-03)

- Function BackApp:
  - Improve run performance of generated load scripts for data export format INSERT
  - Generate a deployment script for data export format INSERT
  - Make all base paths configurable - new parameters p_base_path_docs, p_base_path_tests, p_base_path_scripts, p_base_path_script_logs, p_scripts_working_directory

## 2.3.0 (2020-11-29)

- Function BackApp:
  - Rework table data export format INSERT - thanks to Connor McDonald for his blog post [Generating INSERT scripts that run fast!](https://connor-mcdonald.com/2019/05/17/hacking-together-faster-inserts/)

## 2.2.0 (2020-10-25)

- Function BackApp:
  - Fixed: #4 - plex.backapp throws "ORA-00904: DBMS_JAVA.LONGNAME: invalid identifier" in Oracle instances without a JVM
  - Fixed: #5 - plex.backapp throws "ORA-03113: end-of-file on communication channel" in Oracle 19.6
  - Table data can now be exported in two formats: CSV and INSERT (p_data_format)

## 2.1.0 (2019-12-30)

- Function BackApp:
  - New parameter to include ORDS modules (p_include_ords_modules)
  - New parameter to remove the outer column list on views, which is added by the compiler (p_object_view_remove_col_list); this was done in the past implicitly and can now be switched off; thanks to twitter.com/JKaschuba for the hint
  - Object DDL: Comments for tables and views are now included
  - Script templates: Improved export speed by using a base64 encoded zip file instead of a global temporary table to unload the files
  - Fixed: Unable to export JAVA objects on systems with 30 character object names; thanks to twitter.com/JKaschuba for the hint
  - Fixed: Views appears two times in resulting collection, each double file is postfixed with "_2" and empty
  - Fixed: Tables and indices of materialized view definitions are exported (should be hidden)
- New function to_base64:
  - convert BLOB into base64 encoded CLOB - this is helpful to download a BLOB file (like a zip file) with SQL*Plus

## 2.0.2 (2019-08-16)

- Fixed: Function BackApp throws error on large APEX UI install files (ORA-06502: PL/SQL: numeric or value error: character string buffer too small)

## 2.0.1 (2019-07-09)

- Fixed: Compile error when DB version is lower then 18.1 (PLS-00306: wrong number or types of arguments in call to 'REC_EXPORT_FILE')

## 2.0.0 (2019-06-20)

- Package is now independend from APEX to be able to export schema object DDL and table data without an APEX installation
  - ATTENTION: The return type of functions BackApp and Queries_to_CSV has changed from `apex_t_export_files` to `plex.tab_export_files`
- Function BackApp:
  - New parameters to filter for object types
  - New parameters to change base paths for backend, frontend and data

## 1.2.1 (2019-03-13)

- Fixed: Script templates for function BackApp used old/invalid parameters
- Add install and uninstall scripts for PLEX itself

## 1.2.0 (2018-10-31)

- Function BackApp:
  - All like/not like parameters are now translated internally with the escape character set to backslash like so `... like 'YourExpression' escape '\'`
- Function Queries_to_CSV:
  - Binary data type columns (raw, long_raw, blob, bfile) should no longer break the export

## 1.1.0 (2018-09-23)

- Function BackApp:
  - Change filter parameter from regular expression to list of like expressions for easier handling

## 1.0.0 (2018-08-26)

- First public release
