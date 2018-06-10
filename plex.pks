CREATE OR REPLACE PACKAGE plex AUTHID CURRENT_USER IS
  /*
    
  PL/SQL export utilities: 
  - Delivers zip files to all activated output channels (e.g. mail, download, ora dir...)
  - Depends on APEX 5 because of used APEX_ZIP and APEX_MAIL packages
  - License: MIT
  - URL: https://github.com/ogobrecht/plex
  
  Example for backup of an APEX application:
    
  BEGIN
    plex.set_channels(
      p_apex_mail             => 'email@example.com',
      p_apex_mail_workspace   => 'YOUR_WORKSPACE_NAME' --> only needed for mail channel when running outside an APEX session
    );
    plex.apex_backapp(p_app_id   => your_app_id);
  END;
  
  Example for export one or more queries as csv data within a zip file:
  
  BEGIN
    plex.set_channels(
      p_apex_mail             => 'email@example.com',
      p_apex_mail_workspace   => 'YOUR_WORKSPACE_NAME' --> only needed for mail channel when running outside an APEX session
    );
    plex.add_query(
      p_query       => 'select * from user_tables',
      p_file_name   => 'user_tables'
    );
    plex.add_query(
      p_query       => 'select * from user_tab_columns',
      p_file_name   => 'user_tab_columns',
      p_max_rows    => 10000
    );
    plex.queries_to_csv(p_zip_file_name   => 'user-tables');
  END;  
  */

  -- All output channels are disabled by default.
  -- To disable previously activated channels simply call set_channels without parameters.
  -- The export file is delivered automatically to all activated output channels.
  -- If you want to handle the file by yourself please use the getter methods
  -- get_file_blob, get_file_name and get_file_mime_type or implement an own output_channel.
  PROCEDURE set_channels
  (
    p_apex_mail_to        VARCHAR2 DEFAULT NULL, -- multiple adresses separated by a comma
    p_apex_mail_from      VARCHAR2 DEFAULT NULL, -- from adress is optional, default is the first adress in p_apex_mail
    p_apex_mail_workspace VARCHAR2 DEFAULT NULL, -- only needed when used in pure PL/SQL context
    p_apex_download       BOOLEAN DEFAULT FALSE -- ,
    -- not yet implemented: p_apex_collection VARCHAR2 DEFAULT NULL,
    -- not yet implemented: p_table_column    VARCHAR2 DEFAULT NULL, -- 'table_name:file_blob_column:file_name_column:file_mime_type_column' (table must manage primary key by itself)
    -- not yet implemented: p_ora_dir         VARCHAR2 DEFAULT NULL -- Oracle directory name
  );

  PROCEDURE set_csv_options
  (
    p_delimiter       VARCHAR2 DEFAULT ',',
    p_quote_mark      VARCHAR2 DEFAULT '"',
    p_line_terminator VARCHAR2 DEFAULT chr(10),
    p_header_prefix   VARCHAR2 DEFAULT NULL
  );

  PROCEDURE set_backapp_options
  (
    p_include_app_ddl          BOOLEAN DEFAULT TRUE, -- Include the SQL export file for the APEX application
    p_app_public_reports       BOOLEAN DEFAULT TRUE, -- Include public reports in your application export.
    p_app_private_reports      BOOLEAN DEFAULT FALSE, -- Include private reports in your application export.
    p_app_report_subscriptions BOOLEAN DEFAULT FALSE, -- Include Interactive Report or Interactive Grid subscription settings in your application export.
    p_app_translations         BOOLEAN DEFAULT TRUE, -- Include translations in your application export.
    p_app_subscriptions        BOOLEAN DEFAULT TRUE, -- Include component subscriptions.
    p_app_original_ids         BOOLEAN DEFAULT FALSE, -- Include original workspace id, application id and component ids. Otherwise, use the current ids. Setting this flag to true helps to diff/merge changes from different workspaces.
    p_app_packaged_app_mapping BOOLEAN DEFAULT FALSE, -- Include mapping between the application and packaged application if it exists.
    --
    p_include_object_ddl BOOLEAN DEFAULT TRUE, -- Include DDL of all parsing schema objects
    p_object_prefix      VARCHAR2 DEFAULT NULL, -- Filter the schema objects with the provided object prefix. Useful, if a schema contains multiple apps separated by an object prefix.
    --
    p_include_data  BOOLEAN DEFAULT FALSE, -- Include CSV data of each table.
    p_data_max_rows NUMBER DEFAULT 1000 -- Maximal number of rows per table.
  );

  -- A helper method to get the resulting file BLOB
  FUNCTION get_file_blob RETURN BLOB;

  -- A helper method to get the resulting file name
  FUNCTION get_file_name RETURN VARCHAR2;

  -- A helper method to get the resulting file mime type
  FUNCTION get_file_mime_type RETURN VARCHAR2;

  -- The first export procedure to get a complete snapshot (zip file) of an APEX application including:
  -- 1. All objects DDL
  -- 2. Optional the data (useful for small applications in cloud environments for a logical backup)
  -- 3. The app export SQL file (full and splitted ready to use for version control)
  -- 4. (not yet implemented) A reverse engineered quick SQL file for the tables - thank you Dimitri Gielis :-) http://dgielis.blogspot.com/2017/12/reverse-engineer-existing-oracle-tables.html
  -- 5. Everything in a (hopefully) nice directory structure
  PROCEDURE apex_backapp(p_app_id NUMBER DEFAULT v('APP_ID'));

  -- A helper method to add one or more queries to process by the export method queries_to_csv
  PROCEDURE add_query
  (
    p_query     VARCHAR2,
    p_file_name VARCHAR2,
    p_max_rows  NUMBER DEFAULT 100000
  );

  -- The second export procedure to export one or more queries as csv data within a zip file
  PROCEDURE queries_to_csv(p_zip_file_name VARCHAR2 DEFAULT 'csv-data');

END plex;
/
