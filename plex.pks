CREATE OR REPLACE PACKAGE plex AUTHID CURRENT_USER IS
  /* 
  PL/SQL export utilities: 
   - Depends on APEX 5 because of the used APEX_ZIP package
   - License: MIT
   - URL: https://github.com/ogobrecht/plex  
  */

  c_plex         CONSTANT VARCHAR2(30 CHAR) := 'PLEX - PL/SQL export utils';
  c_plex_version CONSTANT VARCHAR2(10 CHAR) := '0.3.0';

  c_length_application_info PLS_INTEGER := 64;
  SUBTYPE application_info_text IS VARCHAR2(64);

  TYPE t_debug_view_row IS RECORD(
    overall_start_time DATE,
    overall_run_time   NUMBER,
    step               INTEGER,
    elapsed            NUMBER,
    execution          NUMBER,
    module             application_info_text,
    action             application_info_text);
  TYPE t_debug_view_tab IS TABLE OF t_debug_view_row;

  /* 
  Get a zip file for an APEX application including:
  - The app export SQL file - full and splitted ready to use for version control
  - All objects DDL, object grants DDL
  - Optional the data in csv files - useful for small applications in cloud environments for a logical backup
  - Everything in a (hopefully) nice directory structure 
  */
  FUNCTION backapp
  (
    p_app_id                   IN NUMBER DEFAULT NULL, -- If not provided we simply skip the APEX app export.
    p_include_app_ddl          IN BOOLEAN DEFAULT TRUE, -- Include the SQL export file for the APEX application.
    p_app_public_reports       IN BOOLEAN DEFAULT TRUE, -- Include public reports in your application export.
    p_app_private_reports      IN BOOLEAN DEFAULT FALSE, -- Include private reports in your application export.
    p_app_report_subscriptions IN BOOLEAN DEFAULT FALSE, -- Include IRt or IG subscription settings in your application export.
    p_app_translations         IN BOOLEAN DEFAULT TRUE, -- Include translations in your application export.
    p_app_subscriptions        IN BOOLEAN DEFAULT TRUE, -- Include component subscriptions.
    p_app_original_ids         IN BOOLEAN DEFAULT FALSE, -- Include original workspace id, application id and component ids.
    p_app_packaged_app_mapping IN BOOLEAN DEFAULT FALSE, -- Include mapping between the application and packaged application if it exists.                        
    p_include_object_ddl       IN BOOLEAN DEFAULT TRUE, -- Include DDL of current user/schema objects and their grants.
    p_object_prefix            IN VARCHAR2 DEFAULT NULL, -- Filter the schema objects with the provided object prefix.                        
    p_include_data             IN BOOLEAN DEFAULT FALSE, -- Include CSV data of each table.
    p_data_max_rows            IN NUMBER DEFAULT 1000, -- Maximal number of rows per table.                        
    p_debug                    BOOLEAN DEFAULT FALSE -- Generate debug_log.md in the root of the zip file.
  ) RETURN BLOB;

  /* 
  Add a query to an internal array to be processed by the method queries_to_csv
  */
  PROCEDURE add_query
  (
    p_query     VARCHAR2,
    p_file_name VARCHAR2,
    p_max_rows  NUMBER DEFAULT 100000
  );

  /* 
  Export one or more queries as CSV data within a zip file
  */
  FUNCTION queries_to_csv
  (
    p_delimiter       IN VARCHAR2 DEFAULT ',',
    p_quote_mark      IN VARCHAR2 DEFAULT '"',
    p_line_terminator IN VARCHAR2 DEFAULT chr(10),
    p_header_prefix   IN VARCHAR2 DEFAULT NULL,
    p_debug           BOOLEAN DEFAULT FALSE -- Generate debug_log.md in the root of the zip file.
  ) RETURN BLOB;

  /* 
  View the debug details from the last run.
  Example: SELECT * FROM TABLE(plex.view_debug_log); 
  */
  FUNCTION view_debug_log RETURN t_debug_view_tab
    PIPELINED;

END plex;
/
