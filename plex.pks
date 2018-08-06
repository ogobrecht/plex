CREATE OR REPLACE PACKAGE plex AUTHID current_user IS
c_plex_name        CONSTANT VARCHAR2(30 CHAR) := 'PLEX - PL/SQL export utilities';
c_plex_version     CONSTANT VARCHAR2(10 CHAR) := '0.14.0';
c_plex_url         CONSTANT VARCHAR2(40 CHAR) := 'https://github.com/ogobrecht/plex';
c_plex_license     CONSTANT VARCHAR2(10 CHAR) := 'MIT';
c_plex_license_url CONSTANT VARCHAR2(60 CHAR) := 'https://github.com/ogobrecht/plex/blob/master/LICENSE.txt';
c_plex_author      CONSTANT VARCHAR2(20 CHAR) := 'Ottmar Gobrecht';
/*******************************************************************************

PLEX - PL/SQL Export Utilities
==============================

- [BackApp_to_collection](#backapp_to_collection) - main function
- [BackApp_to_zip](#backapp_to_zip) - main function
- [Add_query](#add_query) - helper procedure
- [Queries_to_csv_collection](#queries_to_csv_collection) - main function
- [Queries_to_csv_zip](#queries_to_csv_zip) - main function
- [View_runtime_log](#view_runtime_log) - helper function

STANDARDS

- All main functions (see list above) are overloaded
  - One implementation returning a file collection
  - The other implementation returning a zip file (blob)
- All main functions have a parameter to include a runtime log in the zip file (default: true)
- All main functions setting the session module and action infos while procssing their work

DEPENDENCIES

- APEX 5.1.4 because we use the APEX_EXPORT package

[Feedback is welcome](https://github.com/ogobrecht/plex/issues/new).

*******************************************************************************/


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



/*******************************************************************************

BackApp_to_collection
---------------------

Get a file collection of an APEX application (or the current user/schema only) including:

- The app export SQL files splitted ready to use for version control and deployment
- Optional the DDL scripts for all objects and grants
- Optional the data in csv files - useful for small applications in cloud environments for a logical backup
- Everything in a (hopefully) nice directory structure

EXAMPLE

```sql
DECLARE
  l_files   apex_t_export_files;
BEGIN
  l_files   := plex.backapp_to_collection(
    p_app_id               => 100,
    p_include_object_ddl   => true
  );
  
  -- do something with the files collection
END;
```
*******************************************************************************/
FUNCTION backapp_to_collection (
  p_app_id                    IN NUMBER   DEFAULT null,  -- If null, we simply skip the APEX app export.
  p_app_date                  IN BOOLEAN  DEFAULT true,  -- If true, include export date and time in the result.
  p_app_public_reports        IN BOOLEAN  DEFAULT true,  -- If true, include public reports that a user saved.
  p_app_private_reports       IN BOOLEAN  DEFAULT false, -- If true, include private reports that a user saved.
  p_app_notifications         IN BOOLEAN  DEFAULT false, -- If true, include report notifications.
  p_app_translations          IN BOOLEAN  DEFAULT true,  -- If true, include application translation mappings and all text from the translation repository.
  p_app_pkg_app_mapping       IN BOOLEAN  DEFAULT false, -- If true, export installed packaged applications with references to the packaged application definition. If FALSE, export them as normal applications.
  p_app_original_ids          IN BOOLEAN  DEFAULT true,  -- If true, export with the IDs as they were when the application was imported.
  p_app_subscriptions         IN BOOLEAN  DEFAULT true,  -- If true, components contain subscription references.
  p_app_comments              IN BOOLEAN  DEFAULT true,  -- If true, include developer comments.
  p_app_supporting_objects    IN VARCHAR2 DEFAULT null,  -- If 'Y', export supporting objects. If 'I', automatically install on import. If 'N', do not export supporting objects. If null, the application's include in export deployment value is used.
  p_app_include_single_file   IN BOOLEAN  DEFAULT false, -- If true, the single sql install file is also included beside the splitted files.
  p_app_build_status_run_only IN BOOLEAN  DEFAULT false, -- If true, the build status of the app will be overwritten to RUN_ONLY.

  p_include_object_ddl        IN BOOLEAN  DEFAULT false, -- If true, include DDL of current user/schema and all its objects.
  p_object_filter_regex       IN VARCHAR2 DEFAULT null,  -- Filter the schema objects with the provided object prefix.

  p_include_data              IN BOOLEAN  DEFAULT false, -- If true, include CSV data of each table.
  p_data_as_of_minutes_ago    IN NUMBER   DEFAULT 0,     -- Read consistent data with the resulting timestamp(SCN).
  p_data_max_rows             IN NUMBER   DEFAULT 1000,  -- Maximum number of rows per table.
  p_data_table_filter_regex   IN VARCHAR2 DEFAULT null,  -- Filter user_tables with the given regular expression.

  p_include_templates         IN BOOLEAN  DEFAULT true,  -- If true, include templates for README.md, export and install scripts.
  p_include_runtime_log       IN BOOLEAN  DEFAULT true   -- If true, generate file plex_backapp_log.md with runtime statistics.
) RETURN apex_t_export_files;



/*******************************************************************************

BackApp_to_zip
--------------

Get a zip file for an APEX application (or the current user/schema only) including:

- The app export SQL files splitted ready to use for version control and deployment
- Optional the DDL scripts for all objects and grants
- Optional the data in csv files - useful for small applications in cloud environments for a logical backup
- Everything in a (hopefully) nice directory structure

EXAMPLE

```sql
DECLARE
  l_files   BLOB;
BEGIN
  l_files   := plex.backapp_to_zip(
    p_app_id               => 100,
    p_include_object_ddl   => true
  );
  
  -- do something with the zip file
END;
```
*******************************************************************************/
FUNCTION backapp_to_zip (
  p_app_id                    IN NUMBER   DEFAULT null,  -- If null, we simply skip the APEX app export.
  p_app_date                  IN BOOLEAN  DEFAULT true,  -- If true, include export date and time in the result.
  p_app_public_reports        IN BOOLEAN  DEFAULT true,  -- If true, include public reports that a user saved.
  p_app_private_reports       IN BOOLEAN  DEFAULT false, -- If true, include private reports that a user saved.
  p_app_notifications         IN BOOLEAN  DEFAULT false, -- If true, include report notifications.
  p_app_translations          IN BOOLEAN  DEFAULT true,  -- If true, include application translation mappings and all text from the translation repository.
  p_app_pkg_app_mapping       IN BOOLEAN  DEFAULT false, -- If true, export installed packaged applications with references to the packaged application definition. If FALSE, export them as normal applications.
  p_app_original_ids          IN BOOLEAN  DEFAULT true,  -- If true, export with the IDs as they were when the application was imported.
  p_app_subscriptions         IN BOOLEAN  DEFAULT true,  -- If true, components contain subscription references.
  p_app_comments              IN BOOLEAN  DEFAULT true,  -- If true, include developer comments.
  p_app_supporting_objects    IN VARCHAR2 DEFAULT null,  -- If 'Y', export supporting objects. If 'I', automatically install on import. If 'N', do not export supporting objects. If null, the application's include in export deployment value is used.
  p_app_include_single_file   IN BOOLEAN  DEFAULT false, -- If true, the single sql install file is also included beside the splitted files.
  p_app_build_status_run_only IN BOOLEAN  DEFAULT false, -- If true, the build status of the app will be overwritten to RUN_ONLY.

  p_include_object_ddl        IN BOOLEAN  DEFAULT false, -- If true, include DDL of current user/schema and all its objects.
  p_object_filter_regex       IN VARCHAR2 DEFAULT null,  -- Filter the schema objects with the provided object prefix.

  p_include_data              IN BOOLEAN  DEFAULT false, -- If true, include CSV data of each table.
  p_data_as_of_minutes_ago    IN NUMBER   DEFAULT 0,     -- Read consistent data with the resulting timestamp(SCN).
  p_data_max_rows             IN NUMBER   DEFAULT 1000,  -- Maximum number of rows per table.
  p_data_table_filter_regex   IN VARCHAR2 DEFAULT null,  -- Filter user_tables with the given regular expression.

  p_include_templates         IN BOOLEAN  DEFAULT true,  -- If true, include templates for README.md, export and install scripts.
  p_include_runtime_log       IN BOOLEAN  DEFAULT true   -- If true, generate file plex_backapp_log.md with runtime statistics.
) RETURN BLOB;



/*******************************************************************************

Add_query
---------

Add a query to be processed by the method queries_to_csv. You can add as many
queries as you like.

EXAMPLE

```sql
BEGIN
  plex.add_query(
    p_query       => 'select * from user_tables',
    p_file_name   => 'user_tables'
  );
END;
```
*******************************************************************************/
PROCEDURE add_query (
  p_query     IN VARCHAR2,             -- The query itself
  p_file_name IN VARCHAR2,             -- File name like 'Path/to/your/file-name-without-extension'.
  p_max_rows  IN NUMBER   DEFAULT 1000 -- The maximum number of rows to be included in your file.
);



/*******************************************************************************

Queries_to_csv_collection
-------------------------

Export one or more queries as CSV data within a file collection.

EXAMPLE

```sql
DECLARE
  l_files apex_t_export_files;
BEGIN

  --fill the queries array
  plex.add_query(
    p_query       => 'select * from user_tables',
    p_file_name   => 'user_tables'
  );
  plex.add_query(
    p_query       => 'select * from user_tab_columns',
    p_file_name   => 'user_tab_columns',
    p_max_rows    => 10000
  );

  -- process the queries
  l_files := plex.queries_to_csv_collection;

  -- do something with the file collection...

END;
```
*******************************************************************************/
FUNCTION queries_to_csv_collection (
  p_delimiter                 IN VARCHAR2 DEFAULT ',',   -- The column delimiter - there is also plex.tab as a helper function.
  p_quote_mark                IN VARCHAR2 DEFAULT '"',   -- Used when the data contains the delimiter character.
  p_header_prefix             IN VARCHAR2 DEFAULT NULL,  -- Prefix the header line with this text.
  p_include_runtime_log       IN BOOLEAN  DEFAULT true   -- Generate plex_queries_to_csv_log.md in the root of the zip file.
) RETURN apex_t_export_files;



/*******************************************************************************

Queries_to_csv_zip
------------------

Export one or more queries as CSV data within a zip file.

EXAMPLE

```sql
DECLARE
  l_zip BLOB;
BEGIN

  --fill the queries array
  plex.add_query(
    p_query       => 'select * from user_tables',
    p_file_name   => 'user_tables'
  );
  plex.add_query(
    p_query       => 'select * from user_tab_columns',
    p_file_name   => 'user_tab_columns',
    p_max_rows    => 10000
  );

  -- process the queries
  l_zip := plex.queries_to_csv_zip;

  -- do something with the zip file...

END;
```
*******************************************************************************/
FUNCTION queries_to_csv_zip (
  p_delimiter                 IN VARCHAR2 DEFAULT ',',   -- The column delimiter - there is also plex.tab as a helper function.
  p_quote_mark                IN VARCHAR2 DEFAULT '"',   -- Used when the data contains the delimiter character.
  p_header_prefix             IN VARCHAR2 DEFAULT NULL,  -- Prefix the header line with this text.
  p_include_runtime_log       IN BOOLEAN  DEFAULT true   -- Generate plex_queries_to_csv_log.md in the root of the zip file.
) RETURN BLOB;



/*******************************************************************************

View_runtime_log
----------------

View the log from the last plex run. The internal array for the runtime log
is cleared after each call of BackApp or Queries_to_CSV.

EXAMPLE

```sql
SELECT * FROM TABLE(plex.view_runtime_log);
```
*******************************************************************************/
FUNCTION view_runtime_log RETURN tab_runtime_log PIPELINED;



END plex;
/