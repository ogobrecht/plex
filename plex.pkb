CREATE OR REPLACE PACKAGE BODY plex IS

  TYPE t_row_queries IS RECORD(
    query     VARCHAR2(32767),
    file_name VARCHAR2(256),
    max_rows  NUMBER DEFAULT 100000);
  TYPE t_tab_queries IS TABLE OF t_row_queries INDEX BY PLS_INTEGER;

  --

  g_file_blob      BLOB;
  g_file_name      VARCHAR2(256);
  g_file_mime_type VARCHAR2(64);

  g_temp_clob          CLOB;
  g_temp_varchar_cache VARCHAR2(32767);

  g_csv_delimiter       VARCHAR2(1);
  g_csv_quote_mark      VARCHAR2(1);
  g_csv_line_terminator VARCHAR2(1);

  g_channel_apex_mail       VARCHAR2(1000);
  g_channel_apex_mail_from  VARCHAR2(128);
  g_channel_apex_download   BOOLEAN := FALSE;
  g_channel_apex_collection VARCHAR2(128);
  g_channel_table_column    VARCHAR2(1000);
  g_channel_ora_dir         VARCHAR2(128);
  g_channel_ip_fs           VARCHAR2(256);

  g_queries_array t_tab_queries;

  --

  PROCEDURE util_init_export_method
  (
    p_file_name VARCHAR2,
    p_mime_type VARCHAR2
  ) IS
  BEGIN
    g_temp_clob          := NULL;
    g_file_blob          := NULL;
    g_file_name          := p_file_name;
    g_file_mime_type     := p_mime_type;
    g_temp_varchar_cache := NULL;
  END util_init_export_method;

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
    dbms_metadata.set_transform_param(dbms_metadata.session_transform,
                                      'PRETTY',
                                      p_pretty);
    dbms_metadata.set_transform_param(dbms_metadata.session_transform,
                                      'CONSTRAINTS',
                                      p_constraints);
    dbms_metadata.set_transform_param(dbms_metadata.session_transform,
                                      'REF_CONSTRAINTS',
                                      p_ref_constraints);
    dbms_metadata.set_transform_param(dbms_metadata.session_transform,
                                      'PARTITIONING',
                                      p_partitioning);
    dbms_metadata.set_transform_param(dbms_metadata.session_transform,
                                      'TABLESPACE',
                                      p_tablespace);
    dbms_metadata.set_transform_param(dbms_metadata.session_transform,
                                      'STORAGE',
                                      p_storage);
    dbms_metadata.set_transform_param(dbms_metadata.session_transform,
                                      'SEGMENT_ATTRIBUTES',
                                      p_segment_attributes);
    dbms_metadata.set_transform_param(dbms_metadata.session_transform,
                                      'SQLTERMINATOR',
                                      p_sqlterminator);
    dbms_metadata.set_transform_param(dbms_metadata.session_transform,
                                      'CONSTRAINTS_AS_ALTER',
                                      p_constraints_as_alter);
    dbms_metadata.set_transform_param(dbms_metadata.session_transform,
                                      'EMIT_SCHEMA',
                                      p_emit_schema);
  END util_setup_dbms_metadata;

  --

  PROCEDURE util_temp_clob_reset IS
  BEGIN
    g_temp_clob          := NULL;
    g_temp_varchar_cache := NULL;
  END util_temp_clob_reset;

  --

  PROCEDURE util_temp_clob_flush_cache IS
  BEGIN
    IF g_temp_varchar_cache IS NOT NULL THEN
      IF g_temp_clob IS NULL THEN
        g_temp_clob := g_temp_varchar_cache;
      ELSE
        dbms_lob.append(g_temp_clob, g_temp_varchar_cache);
      END IF;
    
      g_temp_varchar_cache := NULL;
    END IF;
  END util_temp_clob_flush_cache;

  --

  PROCEDURE util_temp_clob_append(p_content IN VARCHAR2) IS
  BEGIN
    g_temp_varchar_cache := g_temp_varchar_cache || p_content;
  EXCEPTION
    WHEN value_error THEN
      IF g_temp_clob IS NULL THEN
        g_temp_clob := g_temp_varchar_cache;
      ELSE
        dbms_lob.append(g_temp_clob, g_temp_varchar_cache);
      END IF;
    
      g_temp_varchar_cache := p_content;
  END util_temp_clob_append;

  --

  PROCEDURE util_temp_clob_append(p_content IN CLOB) IS
  BEGIN
    util_temp_clob_flush_cache;
    IF g_temp_clob IS NULL THEN
      g_temp_clob := p_content;
    ELSE
      dbms_lob.append(g_temp_clob, p_content);
    END IF;
  
  END util_temp_clob_append;

  --

  FUNCTION util_temp_clob_to_blob RETURN BLOB IS
  
    l_blob         BLOB;
    l_dest_offset  INTEGER := 1;
    l_src_offset   INTEGER := 1;
    l_lang_context INTEGER := 0;
    l_warning      INTEGER;
  BEGIN
    util_temp_clob_flush_cache;
    IF g_temp_clob IS NOT NULL THEN
      dbms_lob.createtemporary(lob_loc => l_blob, cache => FALSE);
      dbms_lob.converttoblob(dest_lob     => l_blob,
                             src_clob     => g_temp_clob,
                             amount       => dbms_lob.lobmaxsize,
                             dest_offset  => l_dest_offset,
                             src_offset   => l_src_offset,
                             blob_csid    => nls_charset_id('AL32UTF8'),
                             lang_context => l_lang_context,
                             warning      => l_warning);
    
    END IF;
  
    RETURN l_blob;
  END util_temp_clob_to_blob;

  --

  PROCEDURE util_deliver_apex_mail IS
    l_mail_id NUMBER;
  BEGIN
    l_mail_id := apex_mail.send(p_to   => g_channel_apex_mail,
                                p_from => nvl(g_channel_apex_mail_from,
                                              g_channel_apex_mail),
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
    owa_util.mime_header(ccontent_type => g_file_mime_type,
                         bclose_header => FALSE,
                         ccharset      => 'UTF-8');
  
    htp.print('Content-Length: ' || dbms_lob.getlength(g_file_blob));
    htp.print('Content-Disposition: attachment; filename=' || g_file_name || ';');
    owa_util.http_header_close;
    wpg_docload.download_file(g_file_blob);
  END util_deliver_apex_download;

  --

  PROCEDURE util_deliver_to_channels IS
  BEGIN
    apex_zip.finish(p_zipped_blob => g_file_blob);
    IF g_channel_apex_mail IS NOT NULL THEN
      util_deliver_apex_mail;
    END IF;
    IF g_channel_apex_download THEN
      util_deliver_apex_download;
    END IF;
  END util_deliver_to_channels;

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
      util_temp_clob_append(CASE WHEN
                            instr(nvl(l_buffer, ' '), g_csv_delimiter) = 0 THEN
                            l_buffer ELSE
                            g_csv_quote_mark ||
                            REPLACE(l_buffer,
                                    g_csv_quote_mark,
                                    g_csv_quote_mark || g_csv_quote_mark) ||
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
      FOR i IN 1 .. l_col_cnt LOOP
        IF i > 1 THEN
          util_temp_clob_append(g_csv_delimiter);
        END IF;
        l_buffer := l_desc_tab(i).col_name;
        local_temp_clob_append;
      END LOOP;
    
      util_temp_clob_append(g_csv_line_terminator);
    
      -- create data
      LOOP
        EXIT WHEN dbms_sql.fetch_rows(l_cursor) = 0 OR l_data_count = p_max_rows;
        FOR i IN 1 .. l_col_cnt LOOP
          IF i > 1 THEN
            util_temp_clob_append(g_csv_delimiter);
          END IF;
          dbms_sql.column_value(l_cursor, i, l_buffer);
          local_temp_clob_append;
        END LOOP;
        util_temp_clob_append(g_csv_line_terminator);
        l_data_count := l_data_count + 1;
      END LOOP;
    
    END IF;
  END util_query_to_csv;

  --

  -- do we need this anymore?
  FUNCTION util_get_query(p_table_name VARCHAR2) RETURN VARCHAR2 IS
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
  END util_get_query;

  --

  PROCEDURE set_channels
  (
    p_apex_mail      VARCHAR2 DEFAULT NULL,
    p_apex_mail_from VARCHAR2 DEFAULT NULL,
    p_apex_download  BOOLEAN DEFAULT FALSE --,
    -- not yet implemented: p_apex_collection VARCHAR2 DEFAULT NULL,
    -- not yet implemented: p_table_column    VARCHAR2 DEFAULT NULL,
    -- not yet implemented: p_ora_dir         VARCHAR2 DEFAULT NULL,
    -- not yet implemented: p_ip_fs           VARCHAR2 DEFAULT NULL
  ) IS
  BEGIN
    g_channel_apex_mail      := p_apex_mail;
    g_channel_apex_mail_from := p_apex_mail_from;
    g_channel_apex_download  := p_apex_download;
    -- not yet implemented: g_channel_apex_collection := p_apex_collection;
    -- not yet implemented: g_channel_table_column    := p_table_column;
    -- not yet implemented: g_channel_ora_dir         := p_ora_dir;
    -- not yet implemented: g_channel_ip_fs           := p_ip_fs;
  END set_channels;

  --

  PROCEDURE set_csv_options
  (
    p_csv_delimiter       VARCHAR2 DEFAULT ',',
    p_csv_quote_mark      VARCHAR2 DEFAULT '"',
    p_csv_line_terminator VARCHAR2 DEFAULT chr(10)
  ) IS
  BEGIN
    g_csv_delimiter       := p_csv_delimiter;
    g_csv_quote_mark      := p_csv_quote_mark;
    g_csv_line_terminator := p_csv_line_terminator;
  END set_csv_options;

  --

  PROCEDURE set_apex_workspace(p_workspace VARCHAR2) IS
  BEGIN
    apex_util.set_security_group_id(apex_util.find_security_group_id(p_workspace => p_workspace));
  END set_apex_workspace;

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

  PROCEDURE apex_backapp
  (
    p_app_id             NUMBER DEFAULT v('APP_ID'),
    p_object_prefix      VARCHAR2 DEFAULT NULL,
    p_include_data       BOOLEAN DEFAULT FALSE,
    p_max_rows_per_table NUMBER DEFAULT 100000
  ) IS
    l_owner VARCHAR2(128);
    --  
    PROCEDURE find_owner IS
      CURSOR cur_owner IS
        SELECT owner
          FROM apex_applications t
         WHERE t.application_id = p_app_id;
    BEGIN
      OPEN cur_owner;
      FETCH cur_owner
        INTO l_owner;
      CLOSE cur_owner;
      IF l_owner IS NULL THEN
        raise_application_error(-20000,
                                'Could not find owner for application - are you sure you provided the right app_id?');
      END IF;
      IF l_owner != USER THEN
        raise_application_error(-20000,
                                'You need to be logged on as the owner of the application schema: ' ||
                                l_owner);
      END IF;
    END find_owner;
    --  
    PROCEDURE process_tables IS
    BEGIN
      -- tables
      FOR i IN (SELECT table_name, tablespace_name
                  FROM user_tables
                 WHERE table_name LIKE nvl(p_object_prefix, '%') || '%') LOOP
        -- DDL
        util_temp_clob_reset;
        util_temp_clob_append(dbms_metadata.get_ddl(object_type => 'TABLE',
                                                    NAME        => i.table_name,
                                                    SCHEMA      => l_owner));
      
        apex_zip.add_file(p_zipped_blob => g_file_blob,
                          p_file_name   => 'App/DDL/Tables/' || i.table_name ||
                                           '.sql',
                          p_content     => util_temp_clob_to_blob);
        -- Data     
        IF p_include_data AND i.tablespace_name IS NOT NULL THEN
          util_temp_clob_reset;
          util_query_to_csv(p_query    => 'select * from ' || l_owner || '.' ||
                                          i.table_name,
                            p_max_rows => p_max_rows_per_table);
          apex_zip.add_file(p_zipped_blob => g_file_blob,
                            p_file_name   => 'App/Data/' || i.table_name ||
                                             '.csv',
                            p_content     => util_temp_clob_to_blob);
        END IF;
      END LOOP;
    END process_tables;
    --
    PROCEDURE process_all_other_objects IS
      l_clob CLOB;
    BEGIN
      FOR i IN (SELECT CASE --https://stackoverflow.com/questions/3235300/oracles-dbms-metadata-get-ddl-for-object-type-job
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
                                          regexp_replace(object_type,
                                                         'EX$',
                                                         'ICES',
                                                         1,
                                                         0,
                                                         'i')
                                         WHEN object_type LIKE '%Y' THEN
                                          regexp_replace(object_type, 'Y$', 'IES', 1, 0, 'i')
                                         ELSE
                                          object_type || 'S'
                                       END),
                               ' ',
                               NULL) AS dir_name
                  FROM user_objects
                 WHERE object_type NOT IN ('TABLE',
                                           'TABLE PARTITION',
                                           'PACKAGE BODY',
                                           'TYPE BODY',
                                           'LOB')
                   AND object_name NOT LIKE 'SYS_PLSQL%'
                   AND object_name NOT LIKE 'ISEQ$$%'
                   AND object_name LIKE nvl(p_object_prefix, '%') || '%'
                 ORDER BY object_type) LOOP
        CASE i.object_type
          WHEN 'PACKAGE' THEN
            l_clob := dbms_metadata.get_ddl(object_type => i.object_type,
                                            NAME        => i.object_name,
                                            SCHEMA      => l_owner);
            -- spec                                
            util_temp_clob_reset;
            util_temp_clob_append(ltrim(substr(l_clob,
                                               1,
                                               regexp_instr(l_clob,
                                                            'CREATE OR REPLACE( EDITIONABLE)? PACKAGE BODY') - 1),
                                        ' ' || chr(10)));
            apex_zip.add_file(p_zipped_blob => g_file_blob,
                              p_file_name   => 'App/DDL/' || i.dir_name || '/' ||
                                               i.object_name || '.sql',
                              p_content     => util_temp_clob_to_blob);
            -- body
            util_temp_clob_reset;
            util_temp_clob_append(substr(l_clob,
                                         regexp_instr(l_clob,
                                                      'CREATE OR REPLACE( EDITIONABLE)? PACKAGE BODY')));
            apex_zip.add_file(p_zipped_blob => g_file_blob,
                              p_file_name   => 'App/DDL/PackageBodies/' ||
                                               i.object_name || '.sql',
                              p_content     => util_temp_clob_to_blob);
          WHEN 'VIEW' THEN
            util_temp_clob_reset;
            util_temp_clob_append(ltrim(regexp_replace(regexp_replace(dbms_metadata.get_ddl(object_type => i.object_type,
                                                                                            NAME        => i.object_name,
                                                                                            SCHEMA      => l_owner),
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
                              p_file_name   => 'App/DDL/' || i.dir_name || '/' ||
                                               i.object_name || '.sql',
                              p_content     => util_temp_clob_to_blob);
          ELSE
            util_temp_clob_reset;
            util_temp_clob_append(dbms_metadata.get_ddl(object_type => i.object_type,
                                                        NAME        => i.object_name,
                                                        SCHEMA      => l_owner));
            apex_zip.add_file(p_zipped_blob => g_file_blob,
                              p_file_name   => 'App/DDL/' || i.dir_name || '/' ||
                                               i.object_name || '.sql',
                              p_content     => util_temp_clob_to_blob);
        END CASE;
      END LOOP;
    END process_all_other_objects;
    --  
  BEGIN
    util_init_export_method(p_file_name => 'ApexApp' || p_app_id || '-' ||
                                           to_char(SYSDATE,
                                                   'yyyymmdd-hh24miss') ||
                                           '.zip',
                            p_mime_type => 'application/zip');
    find_owner;
    util_setup_dbms_metadata;
    process_tables;
    process_all_other_objects;
    util_deliver_to_channels;
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
    util_init_export_method(p_file_name => regexp_replace(srcstr     => p_zip_file_name,
                                                          pattern    => '\.zip$',
                                                          replacestr => NULL,
                                                          position   => 1,
                                                          occurrence => 0,
                                                          modifier   => 'i') ||
                                           '.zip',
                            p_mime_type => 'application/zip');
    FOR i IN g_queries_array.first .. g_queries_array.last LOOP
      util_temp_clob_reset;
      util_query_to_csv(p_query    => g_queries_array(i).query,
                        p_max_rows => g_queries_array(i).max_rows);
      apex_zip.add_file(p_zipped_blob => g_file_blob,
                        p_file_name   => regexp_replace(srcstr     => g_queries_array(i)
                                                                      .file_name,
                                                        pattern    => '\.csv$',
                                                        replacestr => NULL,
                                                        position   => 1,
                                                        occurrence => 0,
                                                        modifier   => 'i') ||
                                         '.csv',
                        p_content     => util_temp_clob_to_blob);
    END LOOP;
    util_deliver_to_channels;
    g_queries_array.delete;
  END queries_to_csv;

--

BEGIN
  dbms_lob.createtemporary(lob_loc => g_temp_clob, cache => FALSE);
  dbms_lob.createtemporary(lob_loc => g_file_blob, cache => FALSE);
  set_channels;
  set_csv_options;
END plex;
/
