CREATE OR REPLACE PACKAGE PLEX AUTHID current_user IS
c_plex_name        CONSTANT VARCHAR2(30 CHAR) := 'PLEX - PL/SQL Export Utilities';
c_plex_version     CONSTANT VARCHAR2(10 CHAR) := '1.2.1';
c_plex_url         CONSTANT VARCHAR2(40 CHAR) := 'https://github.com/ogobrecht/plex';
c_plex_license     CONSTANT VARCHAR2(10 CHAR) := 'MIT';
c_plex_license_url CONSTANT VARCHAR2(60 CHAR) := 'https://github.com/ogobrecht/plex/blob/master/LICENSE.txt';
c_plex_author      CONSTANT VARCHAR2(20 CHAR) := 'Ottmar Gobrecht';
/**
PL/SQL Export Utilities

PLEX was created to be able to quickstart version control for existing (APEX) apps and has currently two main functions called __BackApp__ and __Queries_to_CSV__. Queries_to_CSV is used by BackApp as a helper function, but its functionality is also useful standalone. 

See also this resources for more information:

- PLEX project page on [GitHub](https://github.com/ogobrecht/plex)
- Blog post on how to [getting started](https://ogobrecht.github.io/posts/2018-08-26-plex-plsql-export-utilities)

[Feedback is welcome](https://github.com/ogobrecht/plex/issues/new).


STANDARDS

- All main functions returning a file collection of type tab_export_files
- All main functions setting the session module and action infos while processing their work


DEPENDENCIES

- APEX 5.1.4 because we use the packages APEX_EXPORT and APEX_ZIP
**/


-- CONSTANTS, TYPES

c_app_info_length  CONSTANT PLS_INTEGER := 64;

SUBTYPE app_info_text IS VARCHAR2(64 CHAR);

TYPE rec_runtime_log IS RECORD ( 
  overall_start_time DATE,
  overall_run_time NUMBER,
  step INTEGER,
  elapsed NUMBER,
  execution NUMBER,
  module app_info_text,
  action app_info_text );

TYPE tab_runtime_log IS TABLE OF rec_runtime_log;

TYPE rec_export_file IS RECORD (
  name     VARCHAR2(255),
  contents CLOB
);

TYPE tab_export_files IS TABLE OF rec_export_file;

TYPE tab_varchar2 IS TABLE OF varchar2(32767);



FUNCTION backapp (
$if $$apex_exists $then
  -- App related options:
  p_app_id                    IN NUMBER   DEFAULT null,  -- If null, we simply skip the APEX app export.
  p_app_date                  IN BOOLEAN  DEFAULT true,  -- If true, include export date and time in the result.
  p_app_public_reports        IN BOOLEAN  DEFAULT true,  -- If true, include public reports that a user saved.
  p_app_private_reports       IN BOOLEAN  DEFAULT false, -- If true, include private reports that a user saved.
  p_app_notifications         IN BOOLEAN  DEFAULT false, -- If true, include report notifications.
  p_app_translations          IN BOOLEAN  DEFAULT true,  -- If true, include application translation mappings and all text from the translation repository.
  p_app_pkg_app_mapping       IN BOOLEAN  DEFAULT false, -- If true, export installed packaged applications with references to the packaged application definition. If FALSE, export them as normal applications.
  p_app_original_ids          IN BOOLEAN  DEFAULT false, -- If true, export with the IDs as they were when the application was imported.
  p_app_subscriptions         IN BOOLEAN  DEFAULT true,  -- If true, components contain subscription references.
  p_app_comments              IN BOOLEAN  DEFAULT true,  -- If true, include developer comments.
  p_app_supporting_objects    IN VARCHAR2 DEFAULT null,  -- If 'Y', export supporting objects. If 'I', automatically install on import. If 'N', do not export supporting objects. If null, the application's include in export deployment value is used.
  p_app_include_single_file   IN BOOLEAN  DEFAULT false, -- If true, the single sql install file is also included beside the splitted files.
  p_app_build_status_run_only IN BOOLEAN  DEFAULT false, -- If true, the build status of the app will be overwritten to RUN_ONLY.
$end
  -- Object related options:
  p_include_object_ddl        IN BOOLEAN  DEFAULT false, -- If true, include DDL of current user/schema and all its objects.
  p_object_name_like          IN VARCHAR2 DEFAULT null,  -- A comma separated list of like expressions to filter the objects - example: 'EMP%,DEPT%' will be translated to: where ... and (object_name like 'EMP%' escape '\' or object_name like 'DEPT%' escape '\').
  p_object_name_not_like      IN VARCHAR2 DEFAULT null,  -- A comma separated list of not like expressions to filter the objects - example: 'EMP%,DEPT%' will be translated to: where ... and (object_name not like 'EMP%' escape '\' and object_name not like 'DEPT%' escape '\').
  -- Data related options:
  p_include_data              IN BOOLEAN  DEFAULT false, -- If true, include CSV data of each table.
  p_data_as_of_minutes_ago    IN NUMBER   DEFAULT 0,     -- Read consistent data with the resulting timestamp(SCN).
  p_data_max_rows             IN NUMBER   DEFAULT 1000,  -- Maximum number of rows per table.
  p_data_table_name_like      IN VARCHAR2 DEFAULT null,  -- A comma separated list of like expressions to filter the tables - example: 'EMP%,DEPT%' will be translated to: where ... and (table_name like 'EMP%' escape '\' or table_name like 'DEPT%' escape '\').
  p_data_table_name_not_like  IN VARCHAR2 DEFAULT null,  -- A comma separated list of not like expressions to filter the tables - example: 'EMP%,DEPT%' will be translated to: where ... and (table_name not like 'EMP%' escape '\' and table_name not like 'DEPT%' escape '\').
  -- Miscellaneous options:
  p_include_templates         IN BOOLEAN  DEFAULT true,  -- If true, include templates for README.md, export and install scripts.
  p_include_runtime_log       IN BOOLEAN  DEFAULT true   -- If true, generate file plex_backapp_log.md with runtime statistics.
) RETURN tab_export_files;
/**
Get a file collection of an APEX application (or the current user/schema only) including:

- The app export SQL files splitted ready to use for version control and deployment
- Optional the DDL scripts for all objects and grants
- Optional the data in CSV files (this option was implemented to track catalog tables, can be used as logical backup, has the typical CSV limitations...)
- Everything in a (hopefully) nice directory structure

EXAMPLE

```sql
DECLARE
  l_file_collection tab_export_files;
BEGIN
  l_file_collection := plex.backapp(
    p_app_id             => 100,
    p_include_object_ddl => false,
    p_include_data       => false
  );

  -- do something with the file collection
  FOR i IN 1..l_file_collection.count LOOP
    dbms_output.put_line(
         i 
      || ' | ' 
      || lpad(round(length(l_file_collection(i).contents) / 1024), 3) || ' kB' 
      || ' | '
      || l_file_collection(i).name 
      );
  END LOOP;
END;
```
**/



PROCEDURE add_query (
  p_query     IN VARCHAR2,             -- The query itself
  p_file_name IN VARCHAR2,             -- File name like 'Path/to/your/file-name-without-extension'.
  p_max_rows  IN NUMBER   DEFAULT 1000 -- The maximum number of rows to be included in your file.
);
/**
Add a query to be processed by the method queries_to_csv. You can add as many queries as you like.

EXAMPLE

```sql
BEGIN
  plex.add_query(
    p_query     => 'select * from user_tables',
    p_file_name => 'user_tables'
  );
END;
```
**/



FUNCTION queries_to_csv (
  p_delimiter                 IN VARCHAR2 DEFAULT ',',   -- The column delimiter.
  p_quote_mark                IN VARCHAR2 DEFAULT '"',   -- Used when the data contains the delimiter character.
  p_header_prefix             IN VARCHAR2 DEFAULT NULL,  -- Prefix the header line with this text.
  p_include_runtime_log       IN BOOLEAN  DEFAULT true   -- If true, generate file plex_queries_to_csv_log.md with runtime statistics.
) RETURN tab_export_files;
/**
Export one or more queries as CSV data within a file collection.

EXAMPLE

```sql
DECLARE
  l_file_collection tab_export_files;
BEGIN

  --fill the queries array
  plex.add_query(
    p_query     => 'select * from user_tables',
    p_file_name => 'user_tables'
  );
  plex.add_query(
    p_query     => 'select * from user_tab_columns',
    p_file_name => 'user_tab_columns',
    p_max_rows  => 10000
  );

  -- process the queries
  l_file_collection := plex.queries_to_csv;

  -- do something with the file collection
  FOR i IN 1..l_file_collection.count LOOP
    dbms_output.put_line(
         i 
      || ' | ' 
      || lpad(round(length(l_file_collection(i).contents) / 1024), 3) || ' kB' 
      || ' | '
      || l_file_collection(i).name 
      );
  END LOOP;
END;
```
**/



FUNCTION to_zip (
  p_file_collection IN tab_export_files -- The file collection to process with APEX_ZIP.
) RETURN BLOB;
/**
Convert a file collection to a zip file.

EXAMPLE

```sql
DECLARE
  l_zip BLOB;
BEGIN
    l_zip := plex.to_zip(plex.backapp(
      p_app_id             => 100,
      p_include_object_ddl => true
    ));

  -- do something with the zip file...
END;
```
***/



FUNCTION view_runtime_log RETURN tab_runtime_log PIPELINED;
/**
View the log from the last plex run. The internal array for the runtime log is cleared after each call of  BackApp or Queries_to_CSV.

EXAMPLE

```sql
SELECT * FROM TABLE(plex.view_runtime_log);
```
**/



END plex;
/