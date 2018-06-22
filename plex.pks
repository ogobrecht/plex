CREATE     OR REPLACE PACKAGE plex AUTHID current_user IS
  /* 
  
  PL/SQL Export Utilities: 
  
   - Depends on APEX 5 because of the used APEX_ZIP package
   - License: MIT
   - URL: https://github.com/ogobrecht/plex 
   
  One word regarding the parameters in this package: To be usable in the SQL
  and PL/SQL context all boolean parameters are coded as varchars. We check
  only the uppercased first character:
  
  - 1 (one), Y [ES], T [RUE] will be parsed as TRUE
  - 0 (zero), N [O], F [ALSE] will be parsed as FALSE
  - If we can't find a match the default for the parameter is used
  - This means the following keywords are also correct ;-)
    - `yes please`
    - `no thanks`
    - `yeah`
    - `nope`
    - `Yippie Yippie Yeah Yippie Yeah`
    - `time goes by...` - that is true, right?
    - All that fun only because Oracle does not support boolean values in pure
      SQL context...
      
  */
  c_plex CONSTANT VARCHAR2(30 CHAR) := 'PLEX - PL/SQL export utils';
  c_plex_version CONSTANT VARCHAR2(10 CHAR) := '0.6.0';
  c_tab CONSTANT VARCHAR2(2) := chr(9);
  c_lf CONSTANT VARCHAR2(2) := chr(10);
  c_cr CONSTANT VARCHAR2(2) := chr(13);
  c_crlf CONSTANT VARCHAR2(2) := chr(13)
                                    || chr(10);
  c_length_application_info CONSTANT PLS_INTEGER := 64;
  SUBTYPE application_info_text IS VARCHAR2(64);
  TYPE t_debug_view_row IS RECORD ( overall_start_time DATE,
  overall_run_time NUMBER,
  step INTEGER,
  elapsed NUMBER,
  execution NUMBER,
  module application_info_text,
  action application_info_text );
  TYPE t_debug_view_tab IS
    TABLE OF t_debug_view_row;

  /*
  Helper for common delimiter and line terminators.
  */
  FUNCTION tab RETURN VARCHAR2;

  FUNCTION lf RETURN VARCHAR2;

  FUNCTION cr RETURN VARCHAR2;

  FUNCTION crlf RETURN VARCHAR2;

  /* 
  Get a zip file for an APEX application (or the current user/schema only)
  including:

  - The app export SQL file - full and splitted ready to use for version
    control
  - All objects and grants DDL
  - Optional the data in csv files - useful for small applications in cloud
    environments for a logical backup
  - Everything in a (hopefully) nice directory structure 
  */

  FUNCTION backapp (
    p_app_id                     IN NUMBER DEFAULT NULL, -- If not provided we simply skip the APEX app export.
    p_app_public_reports         IN VARCHAR2 DEFAULT 'Y', -- Include public reports in your application export.
    p_app_private_reports        IN VARCHAR2 DEFAULT 'N', -- Include private reports in your application export.
    p_app_report_subscriptions   IN VARCHAR2 DEFAULT 'N', -- Include IRt or IG subscription settings in your application export.
    p_app_translations           IN VARCHAR2 DEFAULT 'Y', -- Include translations in your application export.
    p_app_subscriptions          IN VARCHAR2 DEFAULT 'Y', -- Include component subscriptions.
    p_app_original_ids           IN VARCHAR2 DEFAULT 'N', -- Include original workspace id, application id and component ids.
    p_app_packaged_app_mapping   IN VARCHAR2 DEFAULT 'N', -- Include mapping between the application and packaged application if it exists.                        
    p_include_object_ddl         IN VARCHAR2 DEFAULT 'Y', -- Include DDL of current user/schema and its objects.
    p_object_prefix              IN VARCHAR2 DEFAULT NULL, -- Filter the schema objects with the provided object prefix.                        
    p_include_data               IN VARCHAR2 DEFAULT 'N', -- Include CSV data of each table.
    p_data_as_of_minutes_ago     IN NUMBER DEFAULT 0, -- Read consistent data with the resulting timestamp(SCN).
    p_data_max_rows              IN NUMBER DEFAULT 1000, -- Maximal number of rows per table.                        
    p_include_runtime_log        IN VARCHAR2 DEFAULT 'Y' -- Generate plex_backapp_log.md in the root of the zip file.
  ) RETURN BLOB;

  /* 
  Add a query to an internal array to be processed by the method queries_to_csv
  */

  PROCEDURE add_query (
    p_query       VARCHAR2,
    p_file_name   VARCHAR2,
    p_max_rows    NUMBER DEFAULT 100000
  );

  /* 
  Export one or more queries as CSV data within a zip file
  */

  FUNCTION queries_to_csv (
    p_delimiter             IN VARCHAR2 DEFAULT ',', -- The column delimiter - there is also plex.tab as a helper function.
    p_quote_mark            IN VARCHAR2 DEFAULT '"', -- Used when the data contains the delimiter character.
    p_line_terminator       IN VARCHAR2 DEFAULT lf, -- Default is line feed (plex.lf) - there are also plex.crlf and plex.cr as helpers.
    p_header_prefix         IN VARCHAR2 DEFAULT NULL, -- Prefix the header line with this text.
    p_include_runtime_log   IN VARCHAR2 DEFAULT 'Y' -- Generate plex_queries_to_csv_log.md in the root of the zip file.
  ) RETURN BLOB;

  /* 
  View the debug details from the last run.
  Example: SELECT * FROM TABLE(plex.view_runtime_log); 
  */

  FUNCTION view_runtime_log RETURN t_debug_view_tab
    PIPELINED;

END plex;
/