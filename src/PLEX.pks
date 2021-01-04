CREATE OR REPLACE PACKAGE PLEX AUTHID current_user IS
c_plex_name        CONSTANT VARCHAR2(30 CHAR) := 'PLEX - PL/SQL Export Utilities';
c_plex_version     CONSTANT VARCHAR2(10 CHAR) := '2.4.1';
c_plex_url         CONSTANT VARCHAR2(40 CHAR) := 'https://github.com/ogobrecht/plex';
c_plex_license     CONSTANT VARCHAR2(10 CHAR) := 'MIT';
c_plex_license_url CONSTANT VARCHAR2(60 CHAR) := 'https://github.com/ogobrecht/plex/blob/master/LICENSE.txt';
c_plex_author      CONSTANT VARCHAR2(20 CHAR) := 'Ottmar Gobrecht';
/**
PL/SQL Export Utilities
=======================

PLEX was created to be able to quickstart version control for existing Oracle DB projects and has currently two main functions called **BackApp** and **Queries_to_CSV**. Queries_to_CSV is used by BackApp as a helper function, but its functionality is also useful standalone.

Also see this resources for more information:

- [Blog post on how to getting started](https://ogobrecht.github.io/posts/2018-08-26-plex-plsql-export-utilities)
- [PLEX project page on GitHub](https://github.com/ogobrecht/plex)
  - [Changelog](https://github.com/ogobrecht/plex/blob/master/CHANGELOG.md)
  - [Give feedback](https://github.com/ogobrecht/plex/issues/new)

DEPENDENCIES

The package itself is independend, but functionality varies on the following conditions:

- For APEX app export: APEX >= 5.1.4 installed
- For ORDS modules export: ORDS >= 18.3 installed (I think package ords_export is included since this version, but I don't know it)
  - ATTENTION: There seems to be a [bug in ORDS 19.2](https://community.oracle.com/thread/4292776) which prevents you to export ORDS modules via the package ords_export. Please see plex_error_log.md, if you miss your ORDS modules after an export - this is no problem of PLEX.

INSTALLATION

- Download the [latest version](https://github.com/ogobrecht/plex/releases/latest)
- Unzip it, open a shell and go into the root directory
- Start SQL*Plus (or another tool which can run SQL scripts)
- To install PLEX run the provided install script `plex_install.sql` (script provides compiler flags)
- To uninstall PLEX run the provided script `plex_uninstall.sql` or drop the package manually

**/


--------------------------------------------------------------------------------------------------------------------------------
-- CONSTANTS, TYPES
--------------------------------------------------------------------------------------------------------------------------------

c_app_info_length CONSTANT PLS_INTEGER := 64;
SUBTYPE app_info_text IS VARCHAR2(64 CHAR);
SUBTYPE file_path     IS VARCHAR2(256 CHAR);

TYPE rec_error_log IS RECORD (
  time_stamp TIMESTAMP,
  file_name  VARCHAR2(255),
  error_text VARCHAR2(200),
  call_stack VARCHAR2(500));
TYPE tab_error_log IS TABLE OF rec_error_log;

TYPE rec_runtime_log IS RECORD (
  overall_start_time TIMESTAMP,
  overall_run_time   NUMBER,
  step               INTEGER,
  elapsed            NUMBER,
  execution          NUMBER,
  module             app_info_text,
  action             app_info_text);
TYPE tab_runtime_log IS TABLE OF rec_runtime_log;

TYPE rec_export_file IS RECORD (
  name     VARCHAR2(255),
  contents CLOB);
TYPE tab_export_files IS TABLE OF rec_export_file;

TYPE tab_vc32k IS TABLE OF varchar2(32767);
TYPE tab_vc1k  IS TABLE OF VARCHAR2(1024) INDEX BY BINARY_INTEGER;


--------------------------------------------------------------------------------------------------------------------------------
-- MAIN METHODS
--------------------------------------------------------------------------------------------------------------------------------

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
  p_data_format                 IN VARCHAR2 DEFAULT 'csv', -- A comma separated list of formats - currently supported formats are CSV and INSERT - example: 'csv,insert' will export for each table a csv file and a sql file with insert statements. For insert you can also give the number of rows per "insert all" statement (defaults to 20) - example: 'csv,insert:10' or 'insert:5'.
  -- General Options:
  p_include_templates           IN BOOLEAN  DEFAULT true,  -- If true, include templates for README.md, export and install scripts.
  p_include_runtime_log         IN BOOLEAN  DEFAULT true,  -- If true, generate file plex_runtime_log.md with detailed runtime infos.
  p_include_error_log           IN BOOLEAN  DEFAULT true,  -- If true, generate file plex_error_log.md with detailed error messages.
  p_base_path_backend           IN VARCHAR2 DEFAULT 'app_backend',      -- The base path in the project root for the Schema objects.
  p_base_path_frontend          IN VARCHAR2 DEFAULT 'app_frontend',     -- The base path in the project root for the APEX app.
  p_base_path_web_services      IN VARCHAR2 DEFAULT 'app_web_services', -- The base path in the project root for the ORDS modules.
  p_base_path_data              IN VARCHAR2 DEFAULT 'app_data',         -- The base path in the project root for the table data.
  p_base_path_docs              IN VARCHAR2 DEFAULT 'docs',             -- The base path in the project root for the docs.
  p_base_path_tests             IN VARCHAR2 DEFAULT 'tests',            -- The base path in the project root for the tests.
  p_base_path_scripts           IN VARCHAR2 DEFAULT 'scripts',          -- The base path in the project root for the generated deploy scripts.
  p_base_path_script_logs       IN VARCHAR2 DEFAULT 'scripts/logs',     -- The base path in the project root for the deploy script log files.
  p_scripts_working_directory   IN VARCHAR2 DEFAULT 'scripts')          -- The working directory of the shell (relative to the project root) where deploy scripts will be called. Set this to null if you run the deploy scripts from the project root.
RETURN tab_export_files;
/**
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
{{/}}
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
{{/}}
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
{{/}}
set termout off
spool "app_100.zip.base64"
print contents
spool off
set termout on
```
**/



PROCEDURE add_query (
  p_query     IN VARCHAR2,                -- The query itself
  p_file_name IN VARCHAR2,                -- File name like 'Path/to/your/file-without-extension'.
  p_max_rows  IN NUMBER    DEFAULT 1000); -- The maximum number of rows to be included in your file.
/**
Add a query to be processed by the method queries_to_csv. You can add as many queries as you like.

EXAMPLE

```sql
BEGIN
  plex.add_query(
    p_query     => 'select * from user_tables',
    p_file_name => 'user_tables');
END;
{{/}}
```
**/



FUNCTION queries_to_csv (
  p_delimiter                 IN VARCHAR2 DEFAULT ',',   -- The column delimiter.
  p_quote_mark                IN VARCHAR2 DEFAULT '"',   -- Used when the data contains the delimiter character.
  p_header_prefix             IN VARCHAR2 DEFAULT NULL,  -- Prefix the header line with this text.
  p_include_runtime_log       IN BOOLEAN  DEFAULT true,  -- If true, generate file plex_runtime_log.md with runtime statistics.
  p_include_error_log         IN BOOLEAN  DEFAULT true)  -- If true, generate file plex_error_log.md with detailed error messages.
RETURN tab_export_files;
/**
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
{{/}}
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
{{/}}
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
{{/}}
spool "metadata.zip.base64"
print contents
spool off
```
**/



FUNCTION to_zip (
  p_file_collection IN tab_export_files) -- The file collection to zip.
RETURN BLOB;
/**
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
**/

FUNCTION to_base64(
  p_blob IN BLOB) -- The BLOB to convert.
RETURN CLOB;
/**
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
**/

FUNCTION view_error_log RETURN tab_error_log PIPELINED;
/**
View the error log from the last plex run. The internal array for the error log is cleared on each call of BackApp or Queries_to_CSV.

EXAMPLE

```sql
SELECT * FROM TABLE(plex.view_error_log);
```
**/

FUNCTION view_runtime_log RETURN tab_runtime_log PIPELINED;
/**
View the runtime log from the last plex run. The internal array for the runtime log is cleared on each call of BackApp or Queries_to_CSV.

EXAMPLE

```sql
SELECT * FROM TABLE(plex.view_runtime_log);
```
**/


--------------------------------------------------------------------------------------------------------------------------------
-- UTILITIES (only available when v_utils_public is set to 'true' in install script plex_install.sql)
--------------------------------------------------------------------------------------------------------------------------------

$if $$utils_public $then

FUNCTION util_bool_to_string (p_bool IN BOOLEAN) RETURN VARCHAR2;

FUNCTION util_string_to_bool (
  p_bool_string IN VARCHAR2,
  p_default     IN BOOLEAN)
RETURN BOOLEAN;

FUNCTION util_split (
  p_string    IN VARCHAR2,
  p_delimiter IN VARCHAR2 DEFAULT ',')
RETURN tab_vc32k;

FUNCTION util_join (
  p_array     IN tab_vc32k,
  p_delimiter IN VARCHAR2 DEFAULT ',')
RETURN VARCHAR2;

FUNCTION util_clob_to_blob (p_clob CLOB) RETURN BLOB;

/*
ZIP UTILS
- The following four zip utilities are copied from this article:
    - Blog: https://technology.amis.nl/2010/03/13/utl_compress-gzip-and-zlib/
    - Source: https://technology.amis.nl/wp-content/uploads/2010/06/as_zip10.txt
- Copyright (c) 2010, 2011 by Anton Scheffer (MIT license)
- Thank you for sharing this Anton :-)
*/
FUNCTION util_zip_blob_to_num (
  p_blob IN BLOB,
  p_len  IN INTEGER,
  p_pos  IN INTEGER)
RETURN NUMBER;

FUNCTION util_zip_little_endian (
  p_big   IN NUMBER,
  p_bytes IN PLS_INTEGER := 4)
RETURN RAW;

PROCEDURE util_zip_add_file (
  p_zipped_blob IN OUT BLOB,
  p_name        IN     VARCHAR2,
  p_content     IN     BLOB);

PROCEDURE util_zip_finish (p_zipped_blob IN OUT BLOB);

FUNCTION util_multi_replace (
  p_source_string VARCHAR2,
  p_01_find VARCHAR2 DEFAULT NULL, p_01_replace VARCHAR2 DEFAULT NULL,
  p_02_find VARCHAR2 DEFAULT NULL, p_02_replace VARCHAR2 DEFAULT NULL,
  p_03_find VARCHAR2 DEFAULT NULL, p_03_replace VARCHAR2 DEFAULT NULL,
  p_04_find VARCHAR2 DEFAULT NULL, p_04_replace VARCHAR2 DEFAULT NULL,
  p_05_find VARCHAR2 DEFAULT NULL, p_05_replace VARCHAR2 DEFAULT NULL,
  p_06_find VARCHAR2 DEFAULT NULL, p_06_replace VARCHAR2 DEFAULT NULL,
  p_07_find VARCHAR2 DEFAULT NULL, p_07_replace VARCHAR2 DEFAULT NULL,
  p_08_find VARCHAR2 DEFAULT NULL, p_08_replace VARCHAR2 DEFAULT NULL,
  p_09_find VARCHAR2 DEFAULT NULL, p_09_replace VARCHAR2 DEFAULT NULL,
  p_10_find VARCHAR2 DEFAULT NULL, p_10_replace VARCHAR2 DEFAULT NULL,
  p_11_find VARCHAR2 DEFAULT NULL, p_11_replace VARCHAR2 DEFAULT NULL,
  p_12_find VARCHAR2 DEFAULT NULL, p_12_replace VARCHAR2 DEFAULT NULL)
RETURN VARCHAR2;

FUNCTION util_set_build_status_run_only (p_app_export_sql IN CLOB) RETURN CLOB;

FUNCTION util_calc_data_timestamp (p_as_of_minutes_ago IN NUMBER) RETURN TIMESTAMP;

PROCEDURE util_setup_dbms_metadata (
  p_pretty               IN BOOLEAN DEFAULT true,
  p_constraints          IN BOOLEAN DEFAULT true,
  p_ref_constraints      IN BOOLEAN DEFAULT false,
  p_partitioning         IN BOOLEAN DEFAULT true,
  p_tablespace           IN BOOLEAN DEFAULT false,
  p_storage              IN BOOLEAN DEFAULT false,
  p_segment_attributes   IN BOOLEAN DEFAULT false,
  p_sqlterminator        IN BOOLEAN DEFAULT true,
  p_constraints_as_alter IN BOOLEAN DEFAULT false,
  p_emit_schema          IN BOOLEAN DEFAULT false);

FUNCTION util_to_xlsx_datetime (
    p_date IN DATE)
RETURN NUMBER;

--------------------------------------------------------------------------------------------------------------------------------
-- The following tools are working on the global private package variables g_clob, g_clob_varchar_cache, g_runlog and g_queries
--------------------------------------------------------------------------------------------------------------------------------

PROCEDURE util_clob_append (p_content IN VARCHAR2);

PROCEDURE util_clob_append (p_content IN CLOB);

PROCEDURE util_clob_replace (
  p_search  VARCHAR2,
  p_replace VARCHAR2);

PROCEDURE util_clob_flush_cache;

PROCEDURE util_clob_add_to_export_files (
  p_export_files IN OUT NOCOPY tab_export_files,
  p_name IN VARCHAR2);

PROCEDURE util_clob_query_to_csv (
  p_query         IN VARCHAR2,
  p_max_rows      IN NUMBER DEFAULT 1000,
  p_delimiter     IN VARCHAR2 DEFAULT ',',
  p_quote_mark    IN VARCHAR2 DEFAULT '"',
  p_header_prefix IN VARCHAR2 DEFAULT NULL);

PROCEDURE util_clob_table_to_insert (
  p_table_name      IN VARCHAR2,
  p_data_scn        IN NUMBER,
  p_max_rows        IN NUMBER DEFAULT 1000,
  p_insert_all_size IN NUMBER DEFAULT 10);

PROCEDURE util_clob_create_runtime_log (p_export_files IN OUT NOCOPY tab_export_files);

PROCEDURE util_clob_create_error_log (p_export_files IN OUT NOCOPY tab_export_files);

PROCEDURE util_ensure_unique_file_names (
  p_export_files    IN OUT NOCOPY tab_export_files,
  p_path_to_scripts IN VARCHAR2 DEFAULT NULL);

PROCEDURE util_log_init (p_module IN VARCHAR2);

PROCEDURE util_log_start (p_action IN VARCHAR2);

PROCEDURE util_log_error (p_name VARCHAR2);

PROCEDURE util_log_stop;

FUNCTION util_log_get_runtime (
  p_start IN TIMESTAMP,
  p_stop  IN TIMESTAMP)
RETURN NUMBER;

PROCEDURE util_log_calc_runtimes;

$end

END plex;
/