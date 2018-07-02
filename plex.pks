CREATE OR REPLACE PACKAGE plex AUTHID current_user IS
/*==============================================================================

PLEX - PL/SQL Export Utilities
==============================

- [BackApp](#backapp) - main function
- [Add_Query](#add_query) - helper procedure
- [Queries_to_CSV](#queries_to_csv) - main function
- [View_runtime_log](#view_runtime_log) - helper function

STANDARDS

- All main functions (see list above) returning a blob (zip file) with the results of the export
- All main functions have a parameter to include a runtime log in the zip file (default: true)
- All main functions setting the session module and action infos while procssing their work

DEPENDENCIES

- APEX 5.1.4 because we use the packages APEX_ZIP and APEX_EXPORT

[Feedback is welcome](https://github.com/ogobrecht/plex/issues/new).

==============================================================================*/


-- CONSTANTS, TYPES

c_plex_name    CONSTANT VARCHAR2(30 CHAR) := 'PLEX - PL/SQL export utils';
c_plex_version CONSTANT VARCHAR2(10 CHAR) := '0.11.0';
c_plex_license CONSTANT VARCHAR2(10 CHAR) := 'MIT';
c_plex_url     CONSTANT VARCHAR2(40 CHAR) := 'https://github.com/ogobrecht/plex';
c_plex_author  CONSTANT VARCHAR2(40 CHAR) := 'Ottmar Gobrecht';

c_tab  CONSTANT VARCHAR2(2) := chr(9); 
c_lf   CONSTANT VARCHAR2(2) := chr(10);
c_cr   CONSTANT VARCHAR2(2) := chr(13);
c_crlf CONSTANT VARCHAR2(2) := chr(13) || chr(10);

c_length_application_info CONSTANT PLS_INTEGER := 64;
SUBTYPE application_info_text IS VARCHAR2(64 CHAR);

TYPE rec_runtime_log IS RECORD (
  overall_start_time DATE,
  overall_run_time   NUMBER,
  step               INTEGER,
  elapsed            NUMBER,
  execution          NUMBER,
  module             application_info_text,
  action             application_info_text
);
TYPE tab_runtime_log IS TABLE OF rec_runtime_log;


-- HELPER: Common delimiter and line terminators.

FUNCTION tab  RETURN VARCHAR2;
FUNCTION lf   RETURN VARCHAR2;
FUNCTION cr   RETURN VARCHAR2;
FUNCTION crlf RETURN VARCHAR2;


/*==============================================================================

BackApp
-------

Get a zip file for an APEX application (or the current user/schema only) including:

- The app export SQL file - full and splitted ready to use for version control
- Optional the DDL scripts for all objects and grants
- Optional the data in csv files - useful for small applications in cloud environments for a logical backup
- Everything in a (hopefully) nice directory structure

EXAMPLE

```sql
SELECT plex.backapp(p_app_id => 100) FROM dual;
```
==============================================================================*/
FUNCTION backapp (
  p_app_id                  IN NUMBER   DEFAULT NULL,  -- If not provided we simply skip the APEX app export.
  p_app_date                IN BOOLEAN  DEFAULT TRUE,  -- If true, include export date and time in the result.
  p_app_public_reports      IN BOOLEAN  DEFAULT TRUE,  -- If true, include public reports that a user saved.
  p_app_private_reports     IN BOOLEAN  DEFAULT FALSE, -- If true, include private reports that a user saved.
  p_app_notifications       IN BOOLEAN  DEFAULT FALSE, -- If true, include report notifications.
  p_app_translations        IN BOOLEAN  DEFAULT TRUE,  -- If true, include application translation mappings and all text from the translation repository.
  p_app_pkg_app_mapping     IN BOOLEAN  DEFAULT FALSE, -- If true, export installed packaged applications with references to the packaged application definition. If FALSE, export them as normal applications.
  p_app_original_ids        IN BOOLEAN  DEFAULT TRUE,  -- If true, export with the IDs as they were when the application was imported.
  p_app_subscriptions       IN BOOLEAN  DEFAULT TRUE,  -- If true, components contain subscription references.
  p_app_comments            IN BOOLEAN  DEFAULT TRUE,  -- If true, include developer comments.
  p_app_supporting_objects  IN VARCHAR2 DEFAULT NULL,  -- If 'Y', export supporting objects. If 'I', automatically install on import. If 'N', do not export supporting objects. If null, the application's include in export deployment value is used.
  
  p_include_object_ddl      IN BOOLEAN  DEFAULT FALSE, -- Include DDL of current user/schema and all its objects.
  p_object_filter_regex     IN VARCHAR2 DEFAULT NULL,  -- Filter the schema objects with the provided object prefix.

  p_include_data            IN BOOLEAN  DEFAULT FALSE, -- Include CSV data of each table.
  p_data_as_of_minutes_ago  IN NUMBER   DEFAULT 0,     -- Read consistent data with the resulting timestamp(SCN).
  p_data_max_rows           IN NUMBER   DEFAULT 1000,  -- Maximal number of rows per table.
  p_data_table_filter_regex IN VARCHAR2 DEFAULT NULL,  -- Filter user_tables with the given regular expression.

  p_include_runtime_log     IN BOOLEAN  DEFAULT TRUE   -- Generate plex_backapp_log.md in the root of the zip file.
) RETURN BLOB;


/*==============================================================================

Add_Query
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
/
```
==============================================================================*/
PROCEDURE add_query (
  p_query     IN VARCHAR2,             -- The query itself
  p_file_name IN VARCHAR2,             -- File name like 'Path/to/your/file-name-without-extension'.
  p_max_rows  IN NUMBER   DEFAULT 1000 -- The maximum number of rows to be included in your file.
);


/*==============================================================================

Queries_to_CSV
--------------

Export one or more queries as CSV data within a zip file.

EXAMPLE

```sql
DECLARE
  l_zip blob;
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
  l_zip := plex.queries_to_csv;

  -- do something with the zip file...

END;
/
```
==============================================================================*/
FUNCTION queries_to_csv (
  p_delimiter           IN VARCHAR2 DEFAULT ',',  -- The column delimiter - there is also plex.tab as a helper function.
  p_quote_mark          IN VARCHAR2 DEFAULT '"',  -- Used when the data contains the delimiter character.
  p_line_terminator     IN VARCHAR2 DEFAULT lf,   -- Default is line feed (plex.lf) - there are also plex.crlf and plex.cr as helpers.
  p_header_prefix       IN VARCHAR2 DEFAULT NULL, -- Prefix the header line with this text.
  p_include_runtime_log IN BOOLEAN  DEFAULT TRUE  -- Generate plex_queries_to_csv_log.md in the root of the zip file.
) RETURN BLOB;


/*==============================================================================

View_Runtime_Log
----------------

View the log from the last plex run. The internal array for the runtime log
is cleared after each call of BackApp or Queries_to_CSV.

EXAMPLE

```sql
SELECT * FROM TABLE(plex.view_runtime_log);
```
==============================================================================*/
FUNCTION view_runtime_log RETURN tab_runtime_log PIPELINED;

END plex;
/