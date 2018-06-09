CREATE OR REPLACE PACKAGE BODY plex IS

  TYPE t_row_queries IS RECORD(
    query     VARCHAR2(32767 CHAR),
    file_name VARCHAR2(256 CHAR),
    max_rows  NUMBER DEFAULT 100000);
  TYPE t_tab_queries IS TABLE OF t_row_queries INDEX BY PLS_INTEGER;

  --

  g_file_blob      BLOB;
  g_file_name      VARCHAR2(256 CHAR);
  g_file_mime_type VARCHAR2(64 CHAR);

  g_file_clob          CLOB;
  g_file_varchar_cache VARCHAR2(32767char);

  g_csv_delimiter       VARCHAR2(1 CHAR);
  g_csv_quote_mark      VARCHAR2(1 CHAR);
  g_csv_line_terminator VARCHAR2(1 CHAR);
  g_csv_header_prefix   VARCHAR(100 CHAR);

  g_ba_include_app_ddl          BOOLEAN;
  g_ba_app_public_reports       BOOLEAN;
  g_ba_app_private_reports      BOOLEAN;
  g_ba_app_report_subscriptions BOOLEAN;
  g_ba_app_translations         BOOLEAN;
  g_ba_app_subscriptions        BOOLEAN;
  g_ba_app_original_ids         BOOLEAN;
  g_ba_app_packaged_app_mapping BOOLEAN;
  g_ba_include_object_ddl       BOOLEAN;
  g_ba_object_prefix            VARCHAR2(100 CHAR);
  g_ba_include_data             BOOLEAN;
  g_ba_data_max_rows            NUMBER;

  g_channel_apex_mail_to           VARCHAR2(1000 CHAR);
  g_channel_apex_mail_from         VARCHAR2(128 CHAR);
  g_channel_apex_mail_workspace_id VARCHAR2(128 CHAR);
  g_channel_apex_download          BOOLEAN := FALSE;
  g_channel_apex_collection        VARCHAR2(128 CHAR);
  g_channel_table_column           VARCHAR2(1000 CHAR);
  g_channel_ora_dir                VARCHAR2(128 CHAR);
  g_channel_ip_fs                  VARCHAR2(256 CHAR);

  g_queries_array t_tab_queries;

  --

  PROCEDURE util_setup_dbms_metadata
  (
    p_pretty               IN BOOLEAN DEFAULT TRUE,
    p_constraints          IN BOOLEAN DEFAULT TRUE,
    p_ref_constraints      IN BOOLEAN DEFAULT TRUE,
    p_partitioning         IN BOOLEAN DEFAULT TRUE,
    p_tablespace           IN BOOLEAN DEFAULT FALSE,
    p_storage              IN BOOLEAN DEFAULT FALSE,
    p_segment_attributes   IN BOOLEAN DEFAULT FALSE,
    p_sqlterminator        IN BOOLEAN DEFAULT TRUE,
    p_constraints_as_alter IN BOOLEAN DEFAULT FALSE,
    p_emit_schema          IN BOOLEAN DEFAULT TRUE
  ) IS
  BEGIN
    dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'PRETTY', p_pretty);
    dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'CONSTRAINTS', p_constraints);
    dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'REF_CONSTRAINTS', p_ref_constraints);
    dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'PARTITIONING', p_partitioning);
    dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'TABLESPACE', p_tablespace);
    dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'STORAGE', p_storage);
    dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'SEGMENT_ATTRIBUTES', p_segment_attributes);
    dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'SQLTERMINATOR', p_sqlterminator);
    dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'CONSTRAINTS_AS_ALTER', p_constraints_as_alter);
    dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'EMIT_SCHEMA', p_emit_schema);
  END util_setup_dbms_metadata;

  --

  PROCEDURE util_file_clob_reset IS
  BEGIN
    g_file_clob          := NULL;
    g_file_varchar_cache := NULL;
  END util_file_clob_reset;

  --

  PROCEDURE util_file_clob_flush_cache IS
  BEGIN
    IF g_file_varchar_cache IS NOT NULL THEN
      IF g_file_clob IS NULL THEN
        g_file_clob := g_file_varchar_cache;
      ELSE
        dbms_lob.append(g_file_clob, g_file_varchar_cache);
      END IF;
    
      g_file_varchar_cache := NULL;
    END IF;
  END util_file_clob_flush_cache;

  --

  PROCEDURE util_file_clob_append(p_content IN VARCHAR2) IS
  BEGIN
    g_file_varchar_cache := g_file_varchar_cache || p_content;
  EXCEPTION
    WHEN value_error THEN
      IF g_file_clob IS NULL THEN
        g_file_clob := g_file_varchar_cache;
      ELSE
        dbms_lob.append(g_file_clob, g_file_varchar_cache);
      END IF;
    
      g_file_varchar_cache := p_content;
  END util_file_clob_append;

  --

  PROCEDURE util_file_clob_append(p_content IN CLOB) IS
  BEGIN
    util_file_clob_flush_cache;
    IF g_file_clob IS NULL THEN
      g_file_clob := p_content;
    ELSE
      dbms_lob.append(g_file_clob, p_content);
    END IF;
  
  END util_file_clob_append;

  --

  FUNCTION util_file_clob_to_blob RETURN BLOB IS
  
    l_blob         BLOB;
    l_dest_offset  INTEGER := 1;
    l_src_offset   INTEGER := 1;
    l_lang_context INTEGER := 0;
    l_warning      INTEGER;
  BEGIN
    util_file_clob_flush_cache;
    IF g_file_clob IS NOT NULL THEN
      dbms_lob.createtemporary(lob_loc => l_blob, cache => FALSE);
      dbms_lob.converttoblob(dest_lob     => l_blob,
                             src_clob     => g_file_clob,
                             amount       => dbms_lob.lobmaxsize,
                             dest_offset  => l_dest_offset,
                             src_offset   => l_src_offset,
                             blob_csid    => nls_charset_id('AL32UTF8'),
                             lang_context => l_lang_context,
                             warning      => l_warning);
    
    END IF;
  
    RETURN l_blob;
  END util_file_clob_to_blob;

  --

  PROCEDURE util_deliver_apex_mail IS
    l_mail_id NUMBER;
  BEGIN
    l_mail_id := apex_mail.send(p_to   => g_channel_apex_mail_to,
                                p_from => nvl(g_channel_apex_mail_from, g_channel_apex_mail_to),
                                p_subj => g_file_name,
                                p_body => g_file_name);
  
    apex_mail.add_attachment(p_mail_id    => l_mail_id,
                             p_attachment => g_file_blob,
                             p_filename   => g_file_name,
                             p_mime_type  => g_file_mime_type);
  
    COMMIT;
    apex_mail.push_queue;
  END util_deliver_apex_mail;

  --

  PROCEDURE util_deliver_apex_download IS
  BEGIN
    htp.flush;
    owa_util.mime_header(ccontent_type => g_file_mime_type, bclose_header => FALSE, ccharset => 'UTF-8');
  
    htp.print('Content-Length: ' || dbms_lob.getlength(g_file_blob));
    htp.print('Content-Disposition: attachment; filename=' || g_file_name || ';');
    owa_util.http_header_close;
    wpg_docload.download_file(g_file_blob);
  END util_deliver_apex_download;

  --

  PROCEDURE util_query_to_csv
  (
    p_query    VARCHAR2,
    p_max_rows NUMBER DEFAULT 100000
  ) IS
    -- inspired by Tim Hall: https://oracle-base.com/dba/script?category=miscellaneous&file=csv.sql
    l_cursor     PLS_INTEGER;
    l_rows       PLS_INTEGER;
    l_data_count PLS_INTEGER := 0;
    l_col_cnt    PLS_INTEGER;
    l_desc_tab   dbms_sql.desc_tab2;
    l_buffer     VARCHAR2(32767);
    --
    PROCEDURE local_temp_clob_append IS
    BEGIN
      util_file_clob_append(CASE WHEN instr(nvl(l_buffer, ' '), g_csv_delimiter) = 0 THEN l_buffer ELSE
                            g_csv_quote_mark ||
                            REPLACE(l_buffer, g_csv_quote_mark, g_csv_quote_mark || g_csv_quote_mark) ||
                            g_csv_quote_mark END);
    END local_temp_clob_append;
    --
  BEGIN
    IF p_query IS NOT NULL THEN
    
      l_cursor := dbms_sql.open_cursor;
      dbms_sql.parse(l_cursor, p_query, dbms_sql.native);
      dbms_sql.describe_columns2(l_cursor, l_col_cnt, l_desc_tab);
    
      FOR i IN 1 .. l_col_cnt LOOP
        dbms_sql.define_column(l_cursor, i, l_buffer, 32767);
      END LOOP;
    
      l_rows := dbms_sql.execute(l_cursor);
    
      -- create header
      util_file_clob_append(g_csv_header_prefix);
      FOR i IN 1 .. l_col_cnt LOOP
        IF i > 1 THEN
          util_file_clob_append(g_csv_delimiter);
        END IF;
        l_buffer := l_desc_tab(i).col_name;
        local_temp_clob_append;
      END LOOP;
    
      util_file_clob_append(g_csv_line_terminator);
    
      -- create data
      LOOP
        EXIT WHEN dbms_sql.fetch_rows(l_cursor) = 0 OR l_data_count = p_max_rows;
        FOR i IN 1 .. l_col_cnt LOOP
          IF i > 1 THEN
            util_file_clob_append(g_csv_delimiter);
          END IF;
          dbms_sql.column_value(l_cursor, i, l_buffer);
          local_temp_clob_append;
        END LOOP;
        util_file_clob_append(g_csv_line_terminator);
        l_data_count := l_data_count + 1;
      END LOOP;
    
    END IF;
  END util_query_to_csv;

  --

  -- do we need this anymore?
  /*  FUNCTION util_get_query(p_table_name VARCHAR2) RETURN VARCHAR2 IS
    v_delimiter VARCHAR2(1) := ',';
    v_return    VARCHAR2(32767) := 'select ';
  BEGIN
    FOR i IN (SELECT column_name
                FROM user_tab_columns
               WHERE table_name = p_table_name
               ORDER BY column_id) LOOP
      v_return := v_return || i.column_name || v_delimiter;
    END LOOP;
  
    RETURN rtrim(v_return, v_delimiter) || ' from ' || p_table_name;
  END util_get_query;*/

  --

  PROCEDURE util_export_start
  (
    p_file_name VARCHAR2,
    p_mime_type VARCHAR2
  ) IS
  BEGIN
    g_file_clob          := NULL;
    g_file_blob          := NULL;
    g_file_name          := p_file_name;
    g_file_mime_type     := p_mime_type;
    g_file_varchar_cache := NULL;
    IF g_channel_apex_mail_workspace_id IS NOT NULL THEN
      apex_util.set_security_group_id(apex_util.find_security_group_id(p_workspace => g_channel_apex_mail_workspace_id));
    END IF;
  END util_export_start;

  --

  PROCEDURE util_export_finish IS
  BEGIN
    apex_zip.finish(p_zipped_blob => g_file_blob);
    IF g_channel_apex_mail_to IS NOT NULL THEN
      util_deliver_apex_mail;
    END IF;
    IF g_channel_apex_download THEN
      util_deliver_apex_download;
    END IF;
  END util_export_finish;

  --

  FUNCTION util_bool_to_string(p_bool IN BOOLEAN) RETURN VARCHAR2 IS
  BEGIN
    RETURN CASE WHEN p_bool THEN 'Y' ELSE 'N' END;
  END util_bool_to_string;

  --

  PROCEDURE set_channels
  (
    p_apex_mail_to        VARCHAR2 DEFAULT NULL,
    p_apex_mail_from      VARCHAR2 DEFAULT NULL,
    p_apex_mail_workspace VARCHAR2 DEFAULT NULL,
    p_apex_download       BOOLEAN DEFAULT FALSE --,
    -- not yet implemented: apex_collection VARCHAR2 DEFAULT NULL,
    -- not yet implemented: p_table_column    VARCHAR2 DEFAULT NULL,
    -- not yet implemented: p_ora_dir         VARCHAR2 DEFAULT NULL,
    -- not yet implemented: p_ip_fs           VARCHAR2 DEFAULT NULL
  ) IS
  BEGIN
    g_channel_apex_mail_to           := p_apex_mail_to;
    g_channel_apex_mail_from         := p_apex_mail_from;
    g_channel_apex_mail_workspace_id := p_apex_mail_workspace;
    g_channel_apex_download          := p_apex_download;
    -- not yet implemented: g_channel_apex_collection := apex_collection;
    -- not yet implemented: g_channel_table_column    := p_table_column;
    -- not yet implemented: g_channel_ora_dir         := p_ora_dir;
    -- not yet implemented: g_channel_ip_fs           := p_ip_fs;
  END set_channels;

  --

  PROCEDURE set_csv_options
  (
    p_delimiter       VARCHAR2 DEFAULT ',',
    p_quote_mark      VARCHAR2 DEFAULT '"',
    p_line_terminator VARCHAR2 DEFAULT chr(10),
    p_header_prefix   VARCHAR2 DEFAULT NULL
  ) IS
  BEGIN
    g_csv_delimiter       := p_delimiter;
    g_csv_quote_mark      := p_quote_mark;
    g_csv_line_terminator := p_line_terminator;
    g_csv_header_prefix   := p_header_prefix;
  END set_csv_options;

  --

  PROCEDURE set_backapp_options
  (
    p_include_app_ddl          BOOLEAN DEFAULT TRUE,
    p_app_public_reports       BOOLEAN DEFAULT TRUE,
    p_app_private_reports      BOOLEAN DEFAULT FALSE,
    p_app_report_subscriptions BOOLEAN DEFAULT FALSE,
    p_app_translations         BOOLEAN DEFAULT TRUE,
    p_app_subscriptions        BOOLEAN DEFAULT TRUE,
    p_app_original_ids         BOOLEAN DEFAULT FALSE,
    p_app_packaged_app_mapping BOOLEAN DEFAULT FALSE,
    --
    p_include_object_ddl BOOLEAN DEFAULT TRUE,
    p_object_prefix      VARCHAR2 DEFAULT NULL,
    --
    p_include_data  BOOLEAN DEFAULT FALSE,
    p_data_max_rows NUMBER DEFAULT 1000
  ) IS
  BEGIN
    g_ba_include_app_ddl          := p_include_app_ddl;
    g_ba_app_public_reports       := p_app_public_reports;
    g_ba_app_private_reports      := p_app_private_reports;
    g_ba_app_report_subscriptions := p_app_report_subscriptions;
    g_ba_app_translations         := p_app_translations;
    g_ba_app_subscriptions        := p_app_subscriptions;
    g_ba_app_original_ids         := p_app_original_ids;
    g_ba_app_packaged_app_mapping := p_app_packaged_app_mapping;
    --
    g_ba_include_object_ddl := p_include_object_ddl;
    g_ba_object_prefix      := p_object_prefix;
    --
    g_ba_include_data  := p_include_data;
    g_ba_data_max_rows := p_data_max_rows;
  END set_backapp_options;

  --

  FUNCTION get_file_blob RETURN BLOB IS
  BEGIN
    RETURN g_file_blob;
  END get_file_blob;

  --

  FUNCTION get_file_name RETURN VARCHAR2 IS
  BEGIN
    RETURN g_file_name;
  END get_file_name;

  --

  FUNCTION get_file_mime_type RETURN VARCHAR2 IS
  BEGIN
    RETURN g_file_mime_type;
  END get_file_mime_type;

  --

  PROCEDURE apex_backapp(p_app_id NUMBER DEFAULT v('APP_ID')) IS
    l_owner              VARCHAR2(128);
    l_clob               CLOB;
    l_count              PLS_INTEGER;
    l_pattern            VARCHAR2(100 CHAR) := '^prompt --(application\/.*)$';
    l_modifier           VARCHAR2(10 CHAR) := 'm';
    l_file_content_start PLS_INTEGER;
    l_file_content_end   PLS_INTEGER;
    l_file_path          VARCHAR2(255 CHAR);
    TYPE t_install_file IS TABLE OF VARCHAR2(255) INDEX BY BINARY_INTEGER;
    l_app_install_file t_install_file;
    --    
    PROCEDURE find_owner IS
      CURSOR cur_owner IS
        SELECT owner FROM apex_applications t WHERE t.application_id = p_app_id;
    BEGIN
      OPEN cur_owner;
      FETCH cur_owner
        INTO l_owner;
      CLOSE cur_owner;
      IF l_owner IS NULL THEN
        raise_application_error(-20000,
                                'Could not find owner for application - are you sure you provided the right app_id?');
      END IF;
    END find_owner;
    --
    PROCEDURE process_apex_app IS
    BEGIN
      -- https://apexplained.wordpress.com/2012/03/20/workspace-application-and-page-export-in-plsql/
      -- unfortunately not available: wwv_flow_gen_api2.export which is used in application builder (app:4000, page:4900)
      l_clob := wwv_flow_utilities.export_application_to_clob(p_application_id            => p_app_id,
                                                              p_export_ir_public_reports  => util_bool_to_string(g_ba_app_public_reports),
                                                              p_export_ir_private_reports => util_bool_to_string(g_ba_app_private_reports),
                                                              p_export_ir_notifications   => util_bool_to_string(g_ba_app_report_subscriptions),
                                                              p_export_translations       => util_bool_to_string(g_ba_app_translations),
                                                              p_export_pkg_app_mapping    => util_bool_to_string(g_ba_app_packaged_app_mapping),
                                                              p_with_original_ids         => g_ba_app_original_ids,
                                                              p_exclude_subscriptions     => CASE
                                                                                               WHEN g_ba_app_subscriptions THEN
                                                                                                FALSE
                                                                                               ELSE
                                                                                                TRUE
                                                                                             END);
      -- save as single file
      util_file_clob_reset;
      util_file_clob_append(l_clob);
      apex_zip.add_file(p_zipped_blob => g_file_blob,
                        p_file_name   => 'App/UI/f' || p_app_id || '.sql',
                        p_content     => util_file_clob_to_blob);
      -- split into individual files                        
      l_count := regexp_count(srcstr => l_clob, pattern => l_pattern, position => 1, modifier => l_modifier);
      IF l_count > 0 THEN
      
        FOR i IN 1 .. l_count LOOP
          l_file_content_start := regexp_instr(srcstr      => l_clob,
                                               pattern     => l_pattern,
                                               position    => 1,
                                               occurrence  => i,
                                               returnparam => 0, -- start of pattern
                                               modifier    => l_modifier);
          l_file_content_end := CASE
                                  WHEN l_count = i THEN
                                   length(l_clob)
                                  ELSE
                                   regexp_instr(srcstr      => l_clob,
                                                pattern     => l_pattern,
                                                position    => 1,
                                                occurrence  => i + 1,
                                                returnparam => 0,
                                                modifier    => l_modifier) - 1
                                END;
          l_file_path          := regexp_substr(srcstr        => l_clob,
                                                pattern       => l_pattern,
                                                position      => 1,
                                                occurrence    => i,
                                                modifier      => l_modifier,
                                                subexpression => 1);
          util_file_clob_reset;
          util_file_clob_append(substr(str1 => l_clob,
                                       pos  => l_file_content_start,
                                       len  => l_file_content_end - l_file_content_start) || chr(10));
          apex_zip.add_file(p_zipped_blob => g_file_blob,
                            p_file_name   => 'App/UI/f' || p_app_id || '/' || l_file_path || '.sql',
                            p_content     => util_file_clob_to_blob);
          l_app_install_file(i) := l_file_path;
        END LOOP;
      
        -- create app install file
        util_file_clob_reset;
        FOR i IN 1 .. l_app_install_file.count LOOP
          util_file_clob_append('@' || l_app_install_file(i) || '.sql' || chr(10));
        END LOOP;
        apex_zip.add_file(p_zipped_blob => g_file_blob,
                          p_file_name   => 'App/UI/f' || p_app_id || '/install.sql',
                          p_content     => util_file_clob_to_blob);
      END IF;
    
    END process_apex_app;
    --
    PROCEDURE process_apex_workspace IS
    BEGIN
      NULL;
      -- https://apexplained.wordpress.com/2012/03/20/workspace-application-and-page-export-in-plsql/
      -- unfortunately not available: wwv_flow_gen_api2.export (used in application builder app:4000, page:4900)
      /*  FIXME: implement workspace export   
      l_clob := wwv_flow_utilities.export_application_to_clob(p_application_id            => p_app_id,
                                                              p_export_ir_public_reports  => util_bool_to_string(g_ba_app_public_reports),
                                                              p_export_ir_private_reports => util_bool_to_string(g_ba_app_private_reports),
                                                              p_export_ir_notifications   => util_bool_to_string(g_ba_app_report_subscriptions),
                                                              p_export_translations       => util_bool_to_string(g_ba_app_translations),
                                                              p_export_pkg_app_mapping    => util_bool_to_string(g_ba_app_packaged_app_mapping),
                                                              p_with_original_ids         => g_ba_app_original_ids,
                                                              p_exclude_subscriptions     => CASE
                                                                                               WHEN g_ba_app_subscriptions THEN
                                                                                                FALSE
                                                                                               ELSE
                                                                                                TRUE
                                                                                             END);
      util_file_clob_reset;
      util_file_clob_append(l_clob);
      apex_zip.add_file(p_zipped_blob => g_file_blob,
                        p_file_name   => 'App/Workspace/ws' || p_app_id || '.sql',
                        p_content     => util_file_clob_to_blob);
      l_count := regexp_count(srcstr => l_clob, pattern => '^prompt --application\/.*$', position => 1, modifier => 'm');
      IF l_count > 0 THEN
        FOR i IN 1 .. l_count LOOP
          NULL; -- FIXME: create the files here
        END LOOP;
      END IF;
      */
    END process_apex_workspace;
    --
    PROCEDURE process_object_ddl IS
    BEGIN
      FOR i IN (SELECT owner,
                       CASE --https://stackoverflow.com/questions/3235300/oracles-dbms-metadata-get-ddl-for-object-type-job
                         WHEN object_type IN ('JOB', 'PROGRAM', 'SCHEDULE') THEN
                          'PROCOBJ'
                         ELSE
                          object_type
                       END AS object_type,
                       object_name,
                       REPLACE(initcap(CASE
                                         WHEN object_type LIKE '%S' THEN
                                          object_type || 'ES'
                                         WHEN object_type LIKE '%EX' THEN
                                          regexp_replace(object_type, 'EX$', 'ICES', 1, 0, 'i')
                                         WHEN object_type LIKE '%Y' THEN
                                          regexp_replace(object_type, 'Y$', 'IES', 1, 0, 'i')
                                         ELSE
                                          object_type || 'S'
                                       END),
                               ' ',
                               NULL) AS dir_name
                  FROM all_objects
                 WHERE owner = l_owner
                   AND object_type NOT IN ('TABLE PARTITION', 'PACKAGE BODY', 'TYPE BODY', 'LOB')
                   AND object_name NOT LIKE 'SYS_PLSQL%'
                   AND object_name NOT LIKE 'ISEQ$$%'
                   AND object_name LIKE nvl(g_ba_object_prefix, '%') || '%'
                 ORDER BY object_type) LOOP
        CASE i.object_type
          WHEN 'PACKAGE' THEN
            l_clob := dbms_metadata.get_ddl(object_type => i.object_type, NAME => i.object_name, SCHEMA => i.owner);
            -- spec                                
            util_file_clob_reset;
            util_file_clob_append(ltrim(substr(l_clob,
                                               1,
                                               regexp_instr(l_clob, 'CREATE OR REPLACE( EDITIONABLE)? PACKAGE BODY') - 1),
                                        ' ' || chr(10)));
            apex_zip.add_file(p_zipped_blob => g_file_blob,
                              p_file_name   => 'App/DDL/' || i.dir_name || '/' || i.object_name || '.pks',
                              p_content     => util_file_clob_to_blob);
            -- body
            util_file_clob_reset;
            util_file_clob_append(substr(l_clob, regexp_instr(l_clob, 'CREATE OR REPLACE( EDITIONABLE)? PACKAGE BODY')));
            apex_zip.add_file(p_zipped_blob => g_file_blob,
                              p_file_name   => 'App/DDL/PackageBodies/' || i.object_name || '.pkb',
                              p_content     => util_file_clob_to_blob);
          WHEN 'VIEW' THEN
            util_file_clob_reset;
            util_file_clob_append(ltrim(regexp_replace(regexp_replace(dbms_metadata.get_ddl(object_type => i.object_type,
                                                                                            NAME        => i.object_name,
                                                                                            SCHEMA      => i.owner),
                                                                      '\(.*\) ', -- remove additional column list from the compiler
                                                                      NULL,
                                                                      1,
                                                                      1),
                                                       '^  SELECT', -- remove additional whitespace from the compiler
                                                       'SELECT',
                                                       1,
                                                       1,
                                                       'im'),
                                        ' ' || chr(10)));
            apex_zip.add_file(p_zipped_blob => g_file_blob,
                              p_file_name   => 'App/DDL/' || i.dir_name || '/' || i.object_name || '.sql',
                              p_content     => util_file_clob_to_blob);
          ELSE
            util_file_clob_reset;
            util_file_clob_append(dbms_metadata.get_ddl(object_type => i.object_type,
                                                        NAME        => i.object_name,
                                                        SCHEMA      => l_owner));
            apex_zip.add_file(p_zipped_blob => g_file_blob,
                              p_file_name   => 'App/DDL/' || i.dir_name || '/' || i.object_name || '.sql',
                              p_content     => util_file_clob_to_blob);
        END CASE;
      END LOOP;
    END process_object_ddl;
    --  
    PROCEDURE process_data IS
    BEGIN
      FOR i IN (SELECT table_name, tablespace_name
                  FROM all_tables t
                 WHERE owner = l_owner
                   AND EXTERNAL = 'NO'
                   AND table_name LIKE nvl(g_ba_object_prefix, '%') || '%') LOOP
        util_file_clob_reset;
        util_query_to_csv(p_query    => 'select * from ' || l_owner || '.' || i.table_name,
                          p_max_rows => g_ba_data_max_rows);
        apex_zip.add_file(p_zipped_blob => g_file_blob,
                          p_file_name   => 'App/Data/' || i.table_name || '.csv',
                          p_content     => util_file_clob_to_blob);
      END LOOP;
    END process_data;
    --
  BEGIN
    util_export_start(p_file_name => 'ApexApp' || p_app_id || '-' || to_char(SYSDATE, 'yyyymmdd-hh24miss') || '.zip',
                      p_mime_type => 'application/zip');
    find_owner;
    IF g_ba_include_app_ddl THEN
      process_apex_app;
    END IF;
    IF g_ba_include_object_ddl THEN
      util_setup_dbms_metadata;
      process_object_ddl;
    END IF;
    IF g_ba_include_data THEN
      process_data;
    END IF;
    util_export_finish;
  END apex_backapp;

  --

  PROCEDURE add_query
  (
    p_query     VARCHAR2,
    p_file_name VARCHAR2,
    p_max_rows  NUMBER DEFAULT 100000
  ) IS
    v_row t_row_queries;
  BEGIN
    v_row.query := p_query;
    v_row.file_name := p_file_name;
    v_row.max_rows := p_max_rows;
    g_queries_array(g_queries_array.count + 1) := v_row;
  END add_query;

  --

  PROCEDURE queries_to_csv(p_zip_file_name VARCHAR2 DEFAULT 'csv-data') IS
  BEGIN
    util_export_start(p_file_name => regexp_replace(srcstr     => p_zip_file_name,
                                                    pattern    => '\.zip$',
                                                    replacestr => NULL,
                                                    position   => 1,
                                                    occurrence => 0,
                                                    modifier   => 'i') || '.zip',
                      p_mime_type => 'application/zip');
    FOR i IN g_queries_array.first .. g_queries_array.last LOOP
      util_file_clob_reset;
      util_query_to_csv(p_query => g_queries_array(i).query, p_max_rows => g_queries_array(i).max_rows);
      apex_zip.add_file(p_zipped_blob => g_file_blob,
                        p_file_name   => regexp_replace(srcstr     => g_queries_array(i).file_name,
                                                        pattern    => '\.csv$',
                                                        replacestr => NULL,
                                                        position   => 1,
                                                        occurrence => 0,
                                                        modifier   => 'i') || '.csv',
                        p_content     => util_file_clob_to_blob);
    END LOOP;
    g_queries_array.delete;
    util_export_finish;
  END queries_to_csv;

--

BEGIN
  dbms_lob.createtemporary(lob_loc => g_file_clob, cache => FALSE);
  dbms_lob.createtemporary(lob_loc => g_file_blob, cache => FALSE);
  set_channels;
  set_csv_options;
END plex;
/
