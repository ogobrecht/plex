CREATE     OR REPLACE PACKAGE plex AUTHID current_user IS
/**
  
PL/SQL export utilities: 
- Delivers zip files to all activated output channels (e.g. mail, download, ora dir...)
- Depends on APEX 5 because of used APEX_ZIP and APEX_MAIL packages
- License: MIT
- URL: https://github.com/ogobrecht/plex

Example for backup of an APEX application:
  
BEGIN
  plex.set_apex_workspace('your_workspace_name');
  plex.set_channels(p_apex_mail   => 'email@example.com');
  plex.apex_backapp(
    p_app_id          => your_app_id,
    p_object_prefix   => 'AB_',
    p_include_data    => true
  );
END;
/

Example for export one or more queries as csv data within a zip file:

BEGIN
  plex.set_apex_workspace('your_workspace_name');
  plex.set_channels(p_apex_mail   => 'email@example.com');
  plex.add_query(
    p_query       => 'select * from user_tables',
    p_file_name   => 'user_tables'
  );
  plex.add_query(
    p_query       => 'select * from user_tab_columns',
    p_file_name   => 'user_tab_columns',
    p_max_rows    => 1000
  );
  plex.queries_to_csv(p_zip_file_name => 'user-tables');
END;
/
  
*/

  -- All output channels are disabled by default.
  -- To disable previously activated channels simply call set_channels without parameters.
  -- The export file is delivered automatically to all activated output channels.
  -- If you want to handle the file by yourself please use the getter methods
  -- get_file_blob, get_file_name and get_file_mime_type or implement an own output_channel.
  PROCEDURE set_channels (
    p_apex_mail        VARCHAR2 DEFAULT NULL, -- multiple adresses separated by a comma
    p_apex_mail_from   VARCHAR2 DEFAULT NULL, -- from adress is optional, default is the first adress in p_apex_mail
    p_apex_download    BOOLEAN DEFAULT false -- ,
    -- not yet implemented: p_apex_collection VARCHAR2 DEFAULT NULL,
    -- not yet implemented: p_table_column    VARCHAR2 DEFAULT NULL, -- 'table_name:file_blob_column:file_name_column:file_mime_type_column' (table must manage primary key by itself)
    -- not yet implemented: p_ora_dir         VARCHAR2 DEFAULT NULL, -- Oracle directory name
    -- not yet implemented: p_ip_fs           VARCHAR2 DEFAULT NULL -- a remote directory name (needs the additional project plipfs, which is in planning phase and using Node.js as backend technology...)
  );

  PROCEDURE set_csv_options (
    p_csv_delimiter         VARCHAR2 DEFAULT ',',
    p_csv_quote_mark        VARCHAR2 DEFAULT '"',
    p_csv_line_terminator   VARCHAR2 DEFAULT chr(10)
  );

  -- A helper method to be able to send mails with APEX_MAIL in pure PL/SQL context without an APEX session

  PROCEDURE set_apex_workspace (
    p_workspace VARCHAR2
  );

  -- A helper method to get the resulting file BLOB

  FUNCTION get_file_blob RETURN BLOB;

  -- A helper method to get the resulting file name

  FUNCTION get_file_name RETURN VARCHAR2;

  -- A helper method to get the resulting file mime type

  FUNCTION get_file_mime_type RETURN VARCHAR2;

  -- Our first export procedure to get a complete snapshot (zip file) of an APEX application including:
  -- 1. All objects DDL (currently only tables)
  -- 2. Optional the data (useful for small applications in cloud environments for a logical backup)
  -- 3. (not yet implemented) The app export SQL file (full and splitted ready to use for version control)
  -- 4. (not yet implemented) A reverse engineered quick SQL file for the tables - thank you Dimitri Gielis :-) http://dgielis.blogspot.com/2017/12/reverse-engineer-existing-oracle-tables.html
  -- 5. Everything in a (hopefully) nice directory structure

  PROCEDURE apex_backapp (
    p_app_id               NUMBER DEFAULT v('APP_ID'),
    p_object_prefix        VARCHAR2 DEFAULT NULL,
    p_include_data         BOOLEAN DEFAULT false,
    p_max_rows_per_table   NUMBER DEFAULT 100000
  );

  -- A helper method to add one or more queries to process by the export method queries_to_csv

  PROCEDURE add_query (
    p_query       VARCHAR2,
    p_file_name   VARCHAR2,
    p_max_rows    NUMBER DEFAULT 100000
  );

  -- A method to export one or more queries as csv data within a zip file

  PROCEDURE queries_to_csv (
    p_zip_file_name VARCHAR2 DEFAULT 'csv-data'
  );

--

END plex;
/