CREATE OR REPLACE PACKAGE plex IS
  /**
  
  Generic PL/SQL export utility
  
  Example for backup of an APEX application
  
  begin
    plex.g_channel_apex_mail := 'ottmar.gobrecht@gmail.com';
    plex.apex_backapp(
      p_app_id        => 134399,
      p_object_prefix => 'YL_'
      p_include_data  => true,
    );
  end;
  
  */

  -- The global file variables. The result of your export is saved here.
  g_file_blob BLOB;
  g_file_name VARCHAR2(128);
  g_mime_type VARCHAR2(128);

  -- If you like to have a different file name then the generated one, you can set the 
  -- following variables before you call any of the export procedures. This custom variables
  -- will be reset after the file was delivered to the output channels.
  g_custom_file_name VARCHAR2(128);
  g_custom_mime_type VARCHAR2(128);

  -- The global output channels (all disabled by default, you choose...)
  -- The export file is delivered automatically to all activated output channels.
  -- If you want to pickup the file by yourself, then disable all output channels and take 
  -- the file from the global variable above (g_file_blob)
  
  g_channel_apex_mail VARCHAR2(1000);
  -- activate by set to an email adress (multiple adresses separated by a comma)
  -- deactivate by set to null
  g_channel_apex_mail_from VARCHAR2(128);
  -- from adress is optional, default is the first adress in g_channel_apex_mail

  g_channel_apex_download BOOLEAN := FALSE;
  -- activate by set to true
  -- deactivate by set to false

  g_channel_apex_collection VARCHAR2(128);
  -- activate by set to a collection name
  -- deactivate by set to null

  g_channel_table_column VARCHAR2(1000);
  -- activate by set to 'table_name:column_blob:column_file_name:column_mime_type'
  -- deactivate by set to null

  g_channel_ora_dir VARCHAR2(128);
  -- activate by set to an Oracle directory name
  -- deactivate by set to null

  g_channel_ip_fs VARCHAR2(128);
  -- activate by set to an remote directory name (needs the additional project plipfs, which is in planning phase and using Node.js as backend technology...)
  -- deactivate by set to null

  -- Our first export procedure
  -- The target here is to get a complete snapshot of an application including
  -- 1. The app export sql file (full and splitted ready to use for version control)
  -- 2. All object DDL
  -- 3. Optional the data (useful for small applications in cloud environments for a logical backup)
  -- 4. Everything in a (hopefully) nice directory structure
  PROCEDURE apex_backapp(p_app_id             NUMBER DEFAULT v('APP_ID'),
                         p_object_prefix      VARCHAR2 DEFAULT NULL,
                         p_include_data       BOOLEAN DEFAULT FALSE,
                         p_max_rows_per_table NUMBER DEFAULT 100000);

END plex;
/
