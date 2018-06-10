CREATE OR REPLACE PACKAGE plex AUTHID CURRENT_USER IS
  /*
    
  PL/SQL export utilities: 
  - Depends on APEX 5 because of the used APEX_ZIP package
  - License: MIT
  - URL: https://github.com/ogobrecht/plex
  
  */

  TYPE file IS RECORD(
    blob_content BLOB,
    file_name    VARCHAR2(256 CHAR),
    mime_type    VARCHAR2(64 CHAR));

  -- The first export procedure to get a complete snapshot (zip file) of an APEX application including:
  -- 1. All objects DDL
  -- 2. Optional the data (useful for small applications in cloud environments for a logical backup)
  -- 3. The app export SQL file (full and splitted ready to use for version control)
  -- 4. (not yet implemented) A reverse engineered quick SQL file for the tables - thank you Dimitri Gielis :-) http://dgielis.blogspot.com/2017/12/reverse-engineer-existing-oracle-tables.html
  -- 5. Everything in a (hopefully) nice directory structure
  PROCEDURE apex_backapp
  (
    p_app_id IN NUMBER, -- The app id from the app to export. Be sure to be logged in as the parsing schema of this app, otherwise dbms_metadata could throw errors 
    p_file   IN OUT plex.file, -- The file is a record with blob_content, file_name and mime_type columns (if blob_content is no temporary, this will be done by plex - so be sure to free this temporary when no longer needed)
    -- the options:
    p_include_app_ddl          IN BOOLEAN DEFAULT TRUE, -- Include the SQL export file for the APEX application
    p_app_public_reports       IN BOOLEAN DEFAULT TRUE, -- Include public reports in your application export.
    p_app_private_reports      IN BOOLEAN DEFAULT FALSE, -- Include private reports in your application export.
    p_app_report_subscriptions IN BOOLEAN DEFAULT FALSE, -- Include Interactive Report or Interactive Grid subscription settings in your application export.
    p_app_translations         IN BOOLEAN DEFAULT TRUE, -- Include translations in your application export.
    p_app_subscriptions        IN BOOLEAN DEFAULT TRUE, -- Include component subscriptions.
    p_app_original_ids         IN BOOLEAN DEFAULT FALSE, -- Include original workspace id, application id and component ids. Otherwise, use the current ids. Setting this flag to true helps to diff/merge changes from different workspaces.
    p_app_packaged_app_mapping IN BOOLEAN DEFAULT FALSE, -- Include mapping between the application and packaged application if it exists.
    --
    p_include_object_ddl IN BOOLEAN DEFAULT TRUE, -- Include DDL of all parsing schema objects
    p_object_prefix      IN VARCHAR2 DEFAULT NULL, -- Filter the schema objects with the provided object prefix. Useful, if a schema contains multiple apps separated by an object prefix.
    --
    p_include_data  IN BOOLEAN DEFAULT FALSE, -- Include CSV data of each table.
    p_data_max_rows IN NUMBER DEFAULT 1000 -- Maximal number of rows per table.
  );

  -- A helper method to add one or more queries to process by the export method queries_to_csv
  PROCEDURE add_query
  (
    p_query     VARCHAR2,
    p_file_name VARCHAR2,
    p_max_rows  NUMBER DEFAULT 100000
  );

  --The second export procedure to export one or more queries as csv data within a zip file
  PROCEDURE queries_to_csv(p_file IN OUT plex.file, -- The file is a record with blob_content, file_name and mime_type columns (if blob_content is no temporary, this will be done by plex - so be sure to free this temporary when no longer needed)
                           -- the options:
                           p_delimiter       IN VARCHAR2 DEFAULT ',',
                           p_quote_mark      IN VARCHAR2 DEFAULT '"',
                           p_line_terminator IN VARCHAR2 DEFAULT chr(10),
                           p_header_prefix   IN VARCHAR2 DEFAULT NULL);

END plex;
/
