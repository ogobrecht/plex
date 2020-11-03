<!-- DO NOT EDIT THIS FILE DIRECTLY - it is generated from source file src/PLEX.pks -->
<!-- markdownlint-disable MD003 MD012 MD033 -->

PL/SQL Export Utilities
=======================

- [Package PLEX](#plex)
- [Function backapp](#backapp)
- [Procedure add_query](#add_query)
- [Function queries_to_csv](#queries_to_csv)
- [Function to_zip](#to_zip)
- [Function to_base64](#to_base64)
- [Function view_error_log](#view_error_log)
- [Function view_runtime_log](#view_runtime_log)


<h2><a id="plex"></a>Package PLEX</h2>
<!----------------------------------->

PLEX was created to be able to quickstart version control for existing Oracle DB projects and has currently two main functions called **BackApp** and **Queries_to_CSV**. Queries_to_CSV is used by BackApp as a helper function, but its functionality is also useful standalone.

Also see this resources for more information:

- [Blog post on how to getting started](https://ogobrecht.github.io/posts/2018-08-26-plex-plsql-export-utilities)
- [PLEX project page on GitHub](https://github.com/ogobrecht/plex)
- [Give feedback on GitHub](https://github.com/ogobrecht/plex/issues/new).


DEPENDENCIES

The package itself is independend, but functionality varies on the following conditions:

- For APEX app export: APEX >= 5.1.4 installed
- For ORDS modules export: ORDS >= 18.3 installed (I think package ords_export is included since this version, but I don't know it)
    - ATTENTION: There seems to be a bug in ORDS 19.2 which prevents you to export ORDS modules via the package ords_export: https://community.oracle.com/thread/4292776; please see plex_error_log.md, if you miss your ORDS modules after an export - this is no problem of PLEX


INSTALLATION

- Download the [latest version](https://github.com/ogobrecht/plex/releases/latest)
- Unzip it, open a shell and go into the root directory
- Start SQL*Plus (or another tool which can run SQL scripts)
- To install PLEX run the provided install script `plex_install.sql` (script provides compiler flags)
- To uninstall PLEX run the provided script `plex_uninstall.sql` or drop the package manually


CHANGELOG

- 2.2.0 (2020-10-25)
  - Function BackApp:
    - Fixed: #4 - plex.backapp throws "ORA-00904: DBMS_JAVA.LONGNAME: invalid identifier" in Oracle instances without a JVM
    - Fixed: #5 - plex.backapp throws "ORA-03113: end-of-file on communication channel" in Oracle 19.6
    - Table data can now be exported in two formats: CSV and INSERT (p_data_format)
- 2.1.0 (2019-12-30)
  - Function BackApp:
    - New parameter to include ORDS modules (p_include_ords_modules)
    - New parameter to remove the outer column list on views, which is added by the compiler (p_object_view_remove_col_list); this was done in the past implicitly and can now be switched off; thanks to twitter.com/JKaschuba for the hint
    - Object DDL: Comments for tables and views are now included
    - Script templates: Improved export speed by using a base64 encoded zip file instead of a global temporary table to unload the files
    - Fixed: Unable to export JAVA objects on systems with 30 character object names; thanks to twitter.com/JKaschuba for the hint
    - Fixed: Views appears two times in resulting collection, each double file is postfixed with "_2" and empty
    - Fixed: Tables and indices of materialized view definitions are exported (should be hidden)
  - New function to_base64: convert BLOB into base64 encoded CLOB - this is helpful to download a BLOB file (like a zip file) with SQL*Plus
- 2.0.2 (2019-08-16)
  - Fixed: Function BackApp throws error on large APEX UI install files (ORA-06502: PL/SQL: numeric or value error: character string buffer too small)
- 2.0.1 (2019-07-09)
  - Fixed: Compile error when DB version is lower then 18.1 (PLS-00306: wrong number or types of arguments in call to 'REC_EXPORT_FILE')
- 2.0.0 (2019-06-20)
  - Package is now independend from APEX to be able to export schema object DDL and table data without an APEX installation
    - ATTENTION: The return type of functions BackApp and Queries_to_CSV has changed from `apex_t_export_files` to `plex.tab_export_files`
  - Function BackApp:
    - New parameters to filter for object types
    - New parameters to change base paths for backend, frontend and data
- 1.2.1 (2019-03-13)
  - Fixed: Script templates for function BackApp used old/invalid parameters
  - Add install and uninstall scripts for PLEX itself
- 1.2.0 (2018-10-31)
  - Function BackApp: All like/not like parameters are now translated internally with the escape character set to backslash like so `... like 'YourExpression' escape '\'`
  - Function Queries_to_CSV: Binary data type columns (raw, long_raw, blob, bfile) should no longer break the export
- 1.1.0 (2018-09-23)
  - Function BackApp: Change filter parameter from regular expression to list of like expressions for easier handling
- 1.0.0 (2018-08-26)
  - First public release

SIGNATURE

```sql
PACKAGE PLEX AUTHID current_user IS
c_plex_name        CONSTANT VARCHAR2(30 CHAR) := 'PLEX - PL/SQL Export Utilities';
c_plex_version     CONSTANT VARCHAR2(10 CHAR) := '2.2.0.1';
c_plex_url         CONSTANT VARCHAR2(40 CHAR) := 'https://github.com/ogobrecht/plex';
c_plex_license     CONSTANT VARCHAR2(10 CHAR) := 'MIT';
c_plex_license_url CONSTANT VARCHAR2(60 CHAR) := 'https://github.com/ogobrecht/plex/blob/master/LICENSE.txt';
c_plex_author      CONSTANT VARCHAR2(20 CHAR) := 'Ottmar Gobrecht';
```


<h2><a id="backapp"></a>Function backapp</h2>
<!------------------------------------------>

Get a file collection of an APEX application (or the current user/schema only) including:

- The app export SQL files splitted ready to use for version control and deployment
- Optional the DDL scripts for all objects and grants
- Optional the data in CSV files (this option was implemented to track catalog tables, can be used as logical backup, has the typical CSV limitations...)
- Everything in a (hopefully) nice directory structure

EXAMPLE BASIC USAGE

```sql
DECLARE
  l_file_collection plex.tab_export_files;
BEGIN
  l_file_collection := plex.backapp(
    p_app_id               => 100,  -- parameter only available when APEX is installed
    p_include_ords_modules => true, -- parameter only available when ORDS is installed
    p_include_object_ddl   => false,
    p_include_data         => false,
    p_include_templates    => false);

  -- do something with the file collection
  FOR i IN 1..l_file_collection.count LOOP
    dbms_output.put_line(i || ' | '
      || lpad(round(length(l_file_collection(i).contents) / 1024), 3) || ' kB' || ' | '
      || l_file_collection(i).name);
  END LOOP;
END;
/
```

EXAMPLE ZIP FILE PL/SQL

```sql
DECLARE
  l_zip_file BLOB;
BEGIN
  l_zip_file := plex.to_zip(plex.backapp(
    p_app_id               => 100,  -- parameter only available when APEX is installed
    p_include_ords_modules => true, -- parameter only available when ORDS is installed
    p_include_object_ddl   => true,
    p_include_data         => false,
    p_include_templates    => true));
  -- do something with the zip file
  -- Your code here...
END;
/
```

EXAMPLE ZIP FILE SQL

```sql
-- Inline function because of boolean parameters (needs Oracle 12c or higher).
-- Alternative create a helper function and call that in a SQL context.
WITH
  FUNCTION backapp RETURN BLOB IS
  BEGIN
    RETURN plex.to_zip(plex.backapp(
      p_app_id               => 100,  -- parameter only available when APEX is installed
      p_include_ords_modules => true, -- parameter only available when ORDS is installed
      p_include_object_ddl   => true,
      p_include_data         => false,
      p_include_templates    => true));
  END backapp;
SELECT backapp FROM dual;
```

EXAMPLE ZIP FILE SQL*Plus

```sql
-- SQL*Plus can only handle CLOBs, no BLOBs - so we are forced to create a CLOB
-- for spooling the content to the client disk. You need to decode the base64
-- encoded file before you are able to unzip the content. Also see this blog
-- post how to do this on different operating systems:
-- https://www.igorkromin.net/index.php/2017/04/26/base64-encode-or-decode-on-the-command-line-without-installing-extra-tools-on-linux-windows-or-macos/
-- Example Windows: certutil -decode app_100.zip.base64 app_100.zip
-- Example Mac:     base64 -D -i app_100.zip.base64 -o app_100.zip
-- Example Linux:   base64 -d app_100.zip.base64 > app_100.zip
set verify off feedback off heading off
set trimout on trimspool on pagesize 0 linesize 5000 long 100000000 longchunksize 32767
whenever sqlerror exit sql.sqlcode rollback
variable contents clob
BEGIN
  :contents := plex.to_base64(plex.to_zip(plex.backapp(
    p_app_id               => 100,  -- parameter only available when APEX is installed
    p_include_ords_modules => true, -- parameter only available when ORDS is installed
    p_include_object_ddl   => true,
    p_include_data         => false,
    p_include_templates    => true)));
END;
/
set termout off
spool "app_100.zip.base64"
print contents
spool off
set termout on
```

SIGNATURE

```sql
FUNCTION backapp (
  $if $$apex_installed $then
  -- APEX App:
  p_app_id                      IN NUMBER   DEFAULT null,  -- If null, we simply skip the APEX app export.
  p_app_date                    IN BOOLEAN  DEFAULT true,  -- If true, include export date and time in the result.
  p_app_public_reports          IN BOOLEAN  DEFAULT true,  -- If true, include public reports that a user saved.
  p_app_private_reports         IN BOOLEAN  DEFAULT false, -- If true, include private reports that a user saved.
  p_app_notifications           IN BOOLEAN  DEFAULT false, -- If true, include report notifications.
  p_app_translations            IN BOOLEAN  DEFAULT true,  -- If true, include application translation mappings and all text from the translation repository.
  p_app_pkg_app_mapping         IN BOOLEAN  DEFAULT false, -- If true, export installed packaged applications with references to the packaged application definition. If FALSE, export them as normal applications.
  p_app_original_ids            IN BOOLEAN  DEFAULT false, -- If true, export with the IDs as they were when the application was imported.
  p_app_subscriptions           IN BOOLEAN  DEFAULT true,  -- If true, components contain subscription references.
  p_app_comments                IN BOOLEAN  DEFAULT true,  -- If true, include developer comments.
  p_app_supporting_objects      IN VARCHAR2 DEFAULT null,  -- If 'Y', export supporting objects. If 'I', automatically install on import. If 'N', do not export supporting objects. If null, the application's include in export deployment value is used.
  p_app_include_single_file     IN BOOLEAN  DEFAULT false, -- If true, the single sql install file is also included beside the splitted files.
  p_app_build_status_run_only   IN BOOLEAN  DEFAULT false, -- If true, the build status of the app will be overwritten to RUN_ONLY.
  $end
  $if $$ords_installed $then
  -- ORDS Modules:
  p_include_ords_modules        IN BOOLEAN  DEFAULT false, -- If true, include ORDS modules of current user/schema.
  $end
  -- Schema Objects:
  p_include_object_ddl          IN BOOLEAN  DEFAULT false, -- If true, include DDL of current user/schema and all its objects.
  p_object_type_like            IN VARCHAR2 DEFAULT null,  -- A comma separated list of like expressions to filter the objects - example: '%BODY,JAVA%' will be translated to: ... from user_objects where ... and (object_type like '%BODY' escape '\' or object_type like 'JAVA%' escape '\').
  p_object_type_not_like        IN VARCHAR2 DEFAULT null,  -- A comma separated list of not like expressions to filter the objects - example: '%BODY,JAVA%' will be translated to: ... from user_objects where ... and (object_type not like '%BODY' escape '\' and object_type not like 'JAVA%' escape '\').
  p_object_name_like            IN VARCHAR2 DEFAULT null,  -- A comma separated list of like expressions to filter the objects - example: 'EMP%,DEPT%' will be translated to: ... from user_objects where ... and (object_name like 'EMP%' escape '\' or object_name like 'DEPT%' escape '\').
  p_object_name_not_like        IN VARCHAR2 DEFAULT null,  -- A comma separated list of not like expressions to filter the objects - example: 'EMP%,DEPT%' will be translated to: ... from user_objects where ... and (object_name not like 'EMP%' escape '\' and object_name not like 'DEPT%' escape '\').
  p_object_view_remove_col_list IN BOOLEAN  DEFAULT true,  -- If true, the outer column list, added by Oracle on views during compilation, is removed
  -- Table Data:
  p_include_data                IN BOOLEAN  DEFAULT false, -- If true, include CSV data of each table.
  p_data_as_of_minutes_ago      IN NUMBER   DEFAULT 0,     -- Read consistent data with the resulting timestamp(SCN).
  p_data_max_rows               IN NUMBER   DEFAULT 1000,  -- Maximum number of rows per table.
  p_data_table_name_like        IN VARCHAR2 DEFAULT null,  -- A comma separated list of like expressions to filter the tables - example: 'EMP%,DEPT%' will be translated to: where ... and (table_name like 'EMP%' escape '\' or table_name like 'DEPT%' escape '\').
  p_data_table_name_not_like    IN VARCHAR2 DEFAULT null,  -- A comma separated list of not like expressions to filter the tables - example: 'EMP%,DEPT%' will be translated to: where ... and (table_name not like 'EMP%' escape '\' and table_name not like 'DEPT%' escape '\').
  p_data_format                 IN VARCHAR2 DEFAULT 'csv', -- A comma separated list of formats - currently supported formats are CSV and INSERT - eaxample: 'csv,insert' will export for each table a csv file and a sql file with insert statements.
  -- General Options:
  p_include_templates           IN BOOLEAN  DEFAULT true,  -- If true, include templates for README.md, export and install scripts.
  p_include_runtime_log         IN BOOLEAN  DEFAULT true,  -- If true, generate file plex_runtime_log.md with detailed runtime infos.
  p_include_error_log           IN BOOLEAN  DEFAULT true,  -- If true, generate file plex_error_log.md with detailed error messages.
  p_base_path_backend           IN VARCHAR2 DEFAULT 'app_backend',      -- The base path in the project root for the Schema objects.
  p_base_path_frontend          IN VARCHAR2 DEFAULT 'app_frontend',     -- The base path in the project root for the APEX app.
  p_base_path_web_services      IN VARCHAR2 DEFAULT 'app_web_services', -- The base path in the project root for the ORDS modules.
  p_base_path_data              IN VARCHAR2 DEFAULT 'app_data')         -- The base path in the project root for the table data.
RETURN tab_export_files;
```


<h2><a id="add_query"></a>Procedure add_query</h2>
<!----------------------------------------------->

Add a query to be processed by the method queries_to_csv. You can add as many queries as you like.

EXAMPLE

```sql
BEGIN
  plex.add_query(
    p_query     => 'select * from user_tables',
    p_file_name => 'user_tables');
END;
/
```

SIGNATURE

```sql
PROCEDURE add_query (
  p_query     IN VARCHAR2,                -- The query itself
  p_file_name IN VARCHAR2,                -- File name like 'Path/to/your/file-without-extension'.
  p_max_rows  IN NUMBER    DEFAULT 1000); -- The maximum number of rows to be included in your file.
```


<h2><a id="queries_to_csv"></a>Function queries_to_csv</h2>
<!-------------------------------------------------------->

Export one or more queries as CSV data within a file collection.

EXAMPLE BASIC USAGE

```sql
DECLARE
  l_file_collection plex.tab_export_files;
BEGIN
  --fill the queries array
  plex.add_query(
    p_query     => 'select * from user_tables',
    p_file_name => 'user_tables');
  plex.add_query(
    p_query     => 'select * from user_tab_columns',
    p_file_name => 'user_tab_columns',
    p_max_rows  => 10000);
  -- process the queries
  l_file_collection := plex.queries_to_csv;
  -- do something with the file collection
  FOR i IN 1..l_file_collection.count LOOP
    dbms_output.put_line(i || ' | '
      || lpad(round(length(l_file_collection(i).contents) / 1024), 3) || ' kB' || ' | '
      || l_file_collection(i).name);
  END LOOP;
END;
/
```

EXAMPLE EXPORT ZIP FILE PL/SQL

```sql
DECLARE
  l_zip_file BLOB;
BEGIN
  --fill the queries array
  plex.add_query(
    p_query     => 'select * from user_tables',
    p_file_name => 'user_tables');
  plex.add_query(
    p_query     => 'select * from user_tab_columns',
    p_file_name => 'user_tab_columns',
    p_max_rows  => 10000);
  -- process the queries
  l_zip_file := plex.to_zip(plex.queries_to_csv);
  -- do something with the zip file
  -- Your code here...
END;
/
```

EXAMPLE EXPORT ZIP FILE SQL

```sql
WITH
  FUNCTION queries_to_csv_zip RETURN BLOB IS
    v_return BLOB;
  BEGIN
    plex.add_query(
      p_query     => 'select * from user_tables',
      p_file_name => 'user_tables');
    plex.add_query(
      p_query     => 'select * from user_tab_columns',
      p_file_name => 'user_tab_columns',
      p_max_rows  => 10000);
    v_return := plex.to_zip(plex.queries_to_csv);
    RETURN v_return;
  END queries_to_csv_zip;
SELECT queries_to_csv_zip FROM dual;
```

EXAMPLE ZIP FILE SQL*Plus

```sql
-- SQL*Plus can only handle CLOBs, no BLOBs - so we are forced to create a CLOB
-- for spooling the content to the client disk. You need to decode the base64
-- encoded file before you are able to unzip the content. Also see this blog
-- post how to do this on the different operating systems:
-- https://www.igorkromin.net/index.php/2017/04/26/base64-encode-or-decode-on-the-command-line-without-installing-extra-tools-on-linux-windows-or-macos/
-- Example Windows: certutil -decode metadata.zip.base64 metadata.zip
-- Example Mac: base64 -D -i metadata.zip.base64 -o metadata.zip
-- Example Linux: base64 -d metadata.zip.base64 > metadata.zip
set verify off feedback off heading off termout off
set trimout on trimspool on pagesize 0 linesize 5000 long 100000000 longchunksize 32767
whenever sqlerror exit sql.sqlcode rollback
variable contents clob
BEGIN
  --fill the queries array
  plex.add_query(
    p_query     => 'select * from user_tables',
    p_file_name => 'user_tables');
  plex.add_query(
    p_query     => 'select * from user_tab_columns',
    p_file_name => 'user_tab_columns',
    p_max_rows  => 10000);
  -- process the queries
  :contents := plex.to_base64(plex.to_zip(plex.queries_to_csv));
END;
/
spool "metadata.zip.base64"
print contents
spool off
```

SIGNATURE

```sql
FUNCTION queries_to_csv (
  p_delimiter                 IN VARCHAR2 DEFAULT ',',   -- The column delimiter.
  p_quote_mark                IN VARCHAR2 DEFAULT '"',   -- Used when the data contains the delimiter character.
  p_header_prefix             IN VARCHAR2 DEFAULT NULL,  -- Prefix the header line with this text.
  p_include_runtime_log       IN BOOLEAN  DEFAULT true,  -- If true, generate file plex_runtime_log.md with runtime statistics.
  p_include_error_log         IN BOOLEAN  DEFAULT true)  -- If true, generate file plex_error_log.md with detailed error messages.
RETURN tab_export_files;
```


<h2><a id="to_zip"></a>Function to_zip</h2>
<!---------------------------------------->

Convert a file collection to a zip file.

EXAMPLE

```sql
DECLARE
  l_zip BLOB;
BEGIN
  l_zip := plex.to_zip(plex.backapp(
    p_app_id             => 100,
    p_include_object_ddl => true));
  -- do something with the zip file...
END;
```

SIGNATURE

```sql
FUNCTION to_zip (
  p_file_collection IN tab_export_files) -- The file collection to zip.
RETURN BLOB;
```


<h2><a id="to_base64"></a>Function to_base64</h2>
<!---------------------------------------------->

Encodes a BLOB into a Base64 CLOB for transfers over a network (like with SQL*Plus). For encoding on the client side see [this blog article](https://www.igorkromin.net/index.php/2017/04/26/base64-encode-or-decode-on-the-command-line-without-installing-extra-tools-on-linux-windows-or-macos/).

```sql
DECLARE
  l_clob CLOB;
BEGIN
  l_clob := plex.to_base64(plex.to_zip(plex.backapp(
    p_app_id             => 100,
    p_include_object_ddl => true)));
  -- do something with the clob...
END;
```

SIGNATURE

```sql
FUNCTION to_base64(
  p_blob IN BLOB) -- The BLOB to convert.
RETURN CLOB;
```


<h2><a id="view_error_log"></a>Function view_error_log</h2>
<!-------------------------------------------------------->

View the error log from the last plex run. The internal array for the error log is cleared on each call of BackApp or Queries_to_CSV.

EXAMPLE

```sql
SELECT * FROM TABLE(plex.view_error_log);
```

SIGNATURE

```sql
FUNCTION view_error_log RETURN tab_error_log PIPELINED;
```


<h2><a id="view_runtime_log"></a>Function view_runtime_log</h2>
<!------------------------------------------------------------>

View the runtime log from the last plex run. The internal array for the runtime log is cleared on each call of BackApp or Queries_to_CSV.

EXAMPLE

```sql
SELECT * FROM TABLE(plex.view_runtime_log);
```

SIGNATURE

```sql
FUNCTION view_runtime_log RETURN tab_runtime_log PIPELINED;
```


