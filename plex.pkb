CREATE OR REPLACE PACKAGE BODY plex IS

  g_temp_clob          CLOB;
  g_temp_varchar_cache VARCHAR2(32767);

  c_csv_delimiter       CONSTANT VARCHAR2(1) := ',';
  c_csv_quote_mark      CONSTANT VARCHAR2(1) := '"';
  c_csv_line_terminator CONSTANT VARCHAR2(1) := chr(10);

  PROCEDURE util_setup_dbms_metadata(p_pretty               IN BOOLEAN DEFAULT TRUE,
                                     p_constraints          IN BOOLEAN DEFAULT TRUE,
                                     p_refconstraints       IN BOOLEAN DEFAULT TRUE,
                                     p_partitioning         IN BOOLEAN DEFAULT TRUE,
                                     p_tablespace           IN BOOLEAN DEFAULT FALSE,
                                     p_storage              IN BOOLEAN DEFAULT FALSE,
                                     p_segment_attr         IN BOOLEAN DEFAULT FALSE,
                                     p_sqlterminator        IN BOOLEAN DEFAULT TRUE,
                                     p_constraints_as_alter IN BOOLEAN DEFAULT FALSE,
                                     p_emit_schema          IN BOOLEAN DEFAULT TRUE) IS
  BEGIN
    dbms_metadata.set_transform_param(dbms_metadata.session_transform,
                                      'PRETTY',
                                      p_pretty);
  
    dbms_metadata.set_transform_param(dbms_metadata.session_transform,
                                      'CONSTRAINTS',
                                      p_constraints);
  
    dbms_metadata.set_transform_param(dbms_metadata.session_transform,
                                      'REF_CONSTRAINTS',
                                      p_refconstraints);
  
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
                                      p_segment_attr);
  
    dbms_metadata.set_transform_param(dbms_metadata.session_transform,
                                      'SQLTERMINATOR',
                                      p_sqlterminator);
  
    dbms_metadata.set_transform_param(dbms_metadata.session_transform,
                                      'CONSTRAINTS_AS_ALTER',
                                      p_constraints_as_alter);
  
    dbms_metadata.set_transform_param(dbms_metadata.session_transform,
                                      'EMIT_SCHEMA',
                                      p_emit_schema);
  END;

  PROCEDURE util_init IS
  BEGIN
    g_temp_clob          := NULL;
    g_file_blob          := NULL;
    g_file_name          := NULL;
    g_mime_type          := NULL;
    g_temp_varchar_cache := NULL;
  END;

  PROCEDURE util_temp_clob_reset IS
  BEGIN
    g_temp_clob          := NULL;
    g_temp_varchar_cache := NULL;
  END;

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
  END;

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
  END;

  PROCEDURE util_temp_clob_append(p_content IN CLOB) IS
  BEGIN
    util_temp_clob_flush_cache;
    IF g_temp_clob IS NULL THEN
      g_temp_clob := p_content;
    ELSE
      dbms_lob.append(g_temp_clob, p_content);
    END IF;
  END;

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
  END;

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
                             p_mime_type  => g_mime_type);
    COMMIT;
    apex_mail.push_queue;
  END;

  PROCEDURE util_deliver_apex_download IS
  BEGIN
    htp.flush;
    owa_util.mime_header(ccontent_type => nvl(g_custom_mime_type,
                                              g_mime_type),
                         bclose_header => FALSE,
                         ccharset      => 'UTF-8');
    htp.print('Content-Length: ' || dbms_lob.getlength(g_file_blob));
    htp.print('Content-Disposition: attachment; filename=' ||
              nvl(g_custom_file_name, g_file_name) || ';');
    owa_util.http_header_close;
    wpg_docload.download_file(g_file_blob);
    
  END;

  PROCEDURE util_deliver_to_channels IS
  BEGIN
    apex_zip.finish(p_zipped_blob => g_file_blob);
    IF g_channel_apex_mail IS NOT NULL THEN
      util_deliver_apex_mail;
    END IF;
    IF g_channel_apex_download THEN
      util_deliver_apex_download;
    END IF;
  
    g_custom_file_name := NULL;
    g_custom_mime_type := NULL;
  END;

  PROCEDURE util_query_to_csv(p_query    VARCHAR2,
                              p_max_rows NUMBER DEFAULT 100000) IS
    -- inspired by Tim Hall: https://oracle-base.com/dba/script?category=miscellaneous&file=csv.sql
    l_cursor     PLS_INTEGER;
    l_rows       PLS_INTEGER;
    l_data_count PLS_INTEGER := 0;
    l_col_cnt    PLS_INTEGER;
    l_desc_tab   dbms_sql.desc_tab2;
    l_buffer     VARCHAR2(32767);
    PROCEDURE local_temp_clob_append IS
    BEGIN
      util_temp_clob_append(CASE WHEN
                            instr(nvl(l_buffer, ' '), c_csv_delimiter) = 0 THEN
                            l_buffer ELSE
                            c_csv_quote_mark ||
                            REPLACE(l_buffer,
                                    c_csv_quote_mark,
                                    c_csv_quote_mark || c_csv_quote_mark) ||
                            c_csv_quote_mark END);
    END;
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
          util_temp_clob_append(c_csv_delimiter);
        END IF;
        l_buffer := l_desc_tab(i).col_name;
        local_temp_clob_append;
      END LOOP;
      util_temp_clob_append(c_csv_line_terminator);
    
      -- create data
      LOOP
        EXIT WHEN dbms_sql.fetch_rows(l_cursor) = 0 OR l_data_count = p_max_rows;
        FOR i IN 1 .. l_col_cnt LOOP
          IF i > 1 THEN
            util_temp_clob_append(c_csv_delimiter);
          END IF;
          dbms_sql.column_value(l_cursor, i, l_buffer);
          local_temp_clob_append;
        END LOOP;
        util_temp_clob_append(c_csv_line_terminator);
        l_data_count := l_data_count + 1;
      END LOOP;
    END IF;
  END;

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
  END;

  PROCEDURE apex_backapp(p_app_id             NUMBER DEFAULT v('APP_ID'),
                         p_object_prefix      VARCHAR2 DEFAULT NULL,
                         p_include_data       BOOLEAN DEFAULT FALSE,
                         p_max_rows_per_table NUMBER DEFAULT 100000) IS
    l_owner VARCHAR2(128);
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
    END;
    PROCEDURE process_tables IS
    
    BEGIN
      g_file_name := 'ApexApp' || p_app_id || '-' ||
                     to_char(SYSDATE, 'yyyymmdd-hh24miss') || '.zip';
      g_mime_type := 'application/zip';
      util_setup_dbms_metadata(p_sqlterminator => FALSE);
    
      -- tables
      FOR i IN (SELECT table_name
                  FROM user_tables
                 WHERE table_name LIKE nvl(p_object_prefix, '%') || '%') LOOP
        -- DDL
        util_temp_clob_reset;
        util_temp_clob_append(dbms_metadata.get_ddl(object_type => 'TABLE',
                                                    NAME        => i.table_name,
                                                    SCHEMA      => l_owner));
        apex_zip.add_file(p_zipped_blob => g_file_blob,
                          p_file_name   => 'App/DDL/' || i.table_name ||
                                           '.sql',
                          p_content     => util_temp_clob_to_blob);
        -- data
        IF p_include_data THEN
          util_temp_clob_reset;
          util_query_to_csv(p_query    => util_get_query(p_table_name => i.table_name),
                            p_max_rows => p_max_rows_per_table);
          apex_zip.add_file(p_zipped_blob => g_file_blob,
                            p_file_name   => 'App/Data/' || i.table_name ||
                                             '.csv',
                            p_content     => util_temp_clob_to_blob);
        END IF;
      END LOOP;
      util_setup_dbms_metadata(p_sqlterminator => TRUE);
    END;
  BEGIN
    util_init;
    find_owner;
    process_tables;
    util_deliver_to_channels;
  END;

BEGIN
  dbms_lob.createtemporary(lob_loc => g_temp_clob, cache => FALSE);
  dbms_lob.createtemporary(lob_loc => g_file_blob, cache => FALSE);
END plex;
/
