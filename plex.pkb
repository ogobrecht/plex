CREATE OR REPLACE PACKAGE BODY plex IS

  -- TYPES

  TYPE t_queries_row IS RECORD(
    query     VARCHAR2(32767 CHAR),
    file_name VARCHAR2(256 CHAR),
    max_rows  NUMBER DEFAULT 100000);
  TYPE t_queries_tab IS TABLE OF t_queries_row INDEX BY PLS_INTEGER;

  TYPE t_debug_step_row IS RECORD(
    action     application_info_text,
    start_time TIMESTAMP(6),
    stop_time  TIMESTAMP(6));
  TYPE t_debug_step_tab IS TABLE OF t_debug_step_row INDEX BY BINARY_INTEGER;

  TYPE t_debug_row IS RECORD(
    module     application_info_text,
    enabled    BOOLEAN,
    start_time TIMESTAMP(6),
    stop_time  TIMESTAMP(6),
    data       t_debug_step_tab);

  -- GLOBAL VARIABLES

  g_clob               CLOB;
  g_clob_varchar_cache VARCHAR2(32767char);
  g_queries            t_queries_tab;
  g_debug              t_debug_row;

  -- CODE

  FUNCTION tab RETURN VARCHAR2 IS
  BEGIN
    RETURN c_tab;
  END;

  FUNCTION lf RETURN VARCHAR2 IS
  BEGIN
    RETURN c_lf;
  END;

  FUNCTION cr RETURN VARCHAR2 IS
  BEGIN
    RETURN c_cr;
  END;

  FUNCTION crlf RETURN VARCHAR2 IS
  BEGIN
    RETURN c_crlf;
  END;

  --

  FUNCTION util_bool_to_string(p_bool IN BOOLEAN) RETURN VARCHAR2 IS
  BEGIN
    RETURN CASE WHEN p_bool THEN 'Y' ELSE 'N' END;
  END util_bool_to_string;

  --

  FUNCTION util_string_to_bool
  (
    p_bool_string IN VARCHAR2,
    p_default     IN BOOLEAN
  ) RETURN BOOLEAN IS
    l_bool_string VARCHAR2(1 CHAR);
    l_return      BOOLEAN;
  BEGIN
    l_bool_string := upper(substr(p_bool_string, 1, 1));
    l_return := CASE
                  WHEN l_bool_string IN ('1', 'Y', 'T') THEN
                   TRUE
                  WHEN l_bool_string IN ('0', 'N', 'F') THEN
                   FALSE
                  ELSE
                   p_default
                END;
    RETURN l_return;
  END util_string_to_bool;

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

  PROCEDURE util_g_clob_createtemporary IS
  BEGIN
    dbms_lob.createtemporary(g_clob, TRUE);
  END util_g_clob_createtemporary;

  --

  PROCEDURE util_g_clob_freetemporary IS
  BEGIN
    dbms_lob.freetemporary(g_clob);
  END util_g_clob_freetemporary;

  --

  PROCEDURE util_g_clob_flush_cache IS
  BEGIN
    IF g_clob_varchar_cache IS NOT NULL THEN
      IF g_clob IS NULL THEN
        g_clob := g_clob_varchar_cache;
      ELSE
        dbms_lob.append(g_clob, g_clob_varchar_cache);
      END IF;
      g_clob_varchar_cache := NULL;
    END IF;
  END util_g_clob_flush_cache;

  --

  PROCEDURE util_g_clob_append(p_content IN VARCHAR2) IS
  BEGIN
    g_clob_varchar_cache := g_clob_varchar_cache || p_content;
  EXCEPTION
    WHEN value_error THEN
      IF g_clob IS NULL THEN
        g_clob := g_clob_varchar_cache;
      ELSE
        dbms_lob.append(g_clob, g_clob_varchar_cache);
      END IF;
      g_clob_varchar_cache := p_content;
  END util_g_clob_append;

  --

  PROCEDURE util_g_clob_append(p_content IN CLOB) IS
  BEGIN
    util_g_clob_flush_cache;
    IF g_clob IS NULL THEN
      g_clob := p_content;
    ELSE
      dbms_lob.append(g_clob, p_content);
    END IF;
  
  END util_g_clob_append;

  --

  FUNCTION util_g_clob_to_blob RETURN BLOB IS
    l_blob         BLOB;
    l_lang_context INTEGER := dbms_lob.default_lang_ctx;
    l_warning      INTEGER := dbms_lob.warn_inconvertible_char;
    l_dest_offset  INTEGER := 1;
    l_src_offset   INTEGER := 1;
  BEGIN
    util_g_clob_flush_cache;
    IF g_clob IS NOT NULL THEN
      dbms_lob.createtemporary(l_blob, TRUE);
      dbms_lob.converttoblob(dest_lob     => l_blob,
                             src_clob     => g_clob,
                             amount       => dbms_lob.lobmaxsize,
                             dest_offset  => l_dest_offset,
                             src_offset   => l_src_offset,
                             blob_csid    => nls_charset_id('AL32UTF8'),
                             lang_context => l_lang_context,
                             warning      => l_warning);
    END IF;
    RETURN l_blob;
  END util_g_clob_to_blob;

  --

  PROCEDURE util_g_clob_query_to_csv
  (
    p_query    VARCHAR2,
    p_max_rows NUMBER DEFAULT 100000,
    --
    p_delimiter       VARCHAR2 DEFAULT ',',
    p_quote_mark      VARCHAR2 DEFAULT '"',
    p_line_terminator VARCHAR2 DEFAULT chr(10),
    p_header_prefix   VARCHAR2 DEFAULT NULL
  ) IS
    -- inspired by Tim Hall: https://oracle-base.com/dba/script?category=miscellaneous&file=csv.sql
    l_cursor     PLS_INTEGER;
    l_rows       PLS_INTEGER;
    l_data_count PLS_INTEGER := 0;
    l_col_cnt    PLS_INTEGER;
    l_desc_tab   dbms_sql.desc_tab2;
    l_buffer     VARCHAR2(32767);
    --
    PROCEDURE local_g_clob_append IS
    BEGIN
      util_g_clob_append(CASE WHEN instr(nvl(l_buffer, ' '), p_delimiter) = 0 THEN l_buffer ELSE
                         p_quote_mark || REPLACE(l_buffer, p_quote_mark, p_quote_mark || p_quote_mark) || p_quote_mark END);
    END local_g_clob_append;
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
      util_g_clob_append(p_header_prefix);
      FOR i IN 1 .. l_col_cnt LOOP
        IF i > 1 THEN
          util_g_clob_append(p_delimiter);
        END IF;
        l_buffer := l_desc_tab(i).col_name;
        local_g_clob_append;
      END LOOP;
    
      util_g_clob_append(p_line_terminator);
    
      -- create data
      LOOP
        EXIT WHEN dbms_sql.fetch_rows(l_cursor) = 0 OR l_data_count = p_max_rows;
        FOR i IN 1 .. l_col_cnt LOOP
          IF i > 1 THEN
            util_g_clob_append(p_delimiter);
          END IF;
          dbms_sql.column_value(l_cursor, i, l_buffer);
          local_g_clob_append;
        END LOOP;
        util_g_clob_append(p_line_terminator);
        l_data_count := l_data_count + 1;
      END LOOP;
    
    END IF;
  END util_g_clob_query_to_csv;

  --

  PROCEDURE util_ilog_init
  (
    p_module VARCHAR2,
    p_debug  BOOLEAN
  ) IS
  BEGIN
    g_debug        := NULL;
    g_debug.module := substr(p_module, 1, c_length_application_info);
    IF p_debug THEN
      g_debug.enabled    := TRUE;
      g_debug.start_time := systimestamp;
    END IF;
  END util_ilog_init;

  --

  PROCEDURE util_ilog_exit IS
  BEGIN
    IF g_debug.enabled THEN
      g_debug.stop_time := systimestamp;
      g_debug.enabled   := FALSE;
    END IF;
  END util_ilog_exit;

  --

  PROCEDURE util_ilog_start(p_action VARCHAR2) IS
    l_index PLS_INTEGER;
  BEGIN
    dbms_application_info.set_module(module_name => g_debug.module, action_name => p_action);
    IF g_debug.enabled THEN
      l_index := g_debug.data.count + 1;
      g_debug.data(l_index).action := substr(p_action, 1, plex.c_length_application_info);
      g_debug.data(l_index).start_time := systimestamp;
    END IF;
  END util_ilog_start;

  --

  PROCEDURE util_ilog_append_action_text(p_text VARCHAR2) IS
    l_index PLS_INTEGER;
  BEGIN
    IF g_debug.enabled THEN
      l_index := g_debug.data.count;
      g_debug.data(l_index).action := substr(g_debug.data(l_index).action || p_text, 1, plex.c_length_application_info);
    END IF;
  END util_ilog_append_action_text;

  --

  PROCEDURE util_ilog_stop IS
  BEGIN
    dbms_application_info.set_module(module_name => NULL, action_name => NULL);
    IF g_debug.enabled THEN
      g_debug.data(g_debug.data.count).stop_time := systimestamp;
    END IF;
  END util_ilog_stop;

  --

  FUNCTION util_ilog_get_runtime
  (
    p_start TIMESTAMP,
    p_stop  TIMESTAMP
  ) RETURN NUMBER IS
  BEGIN
    RETURN SYSDATE +((p_stop - p_start) * 86400) - SYSDATE;
    --sysdate + (interval_difference * 86400) - sysdate
    --https://stackoverflow.com/questions/10092032/extracting-the-total-number-of-seconds-from-an-interval-data-type  
  END util_ilog_get_runtime;

  --

  PROCEDURE util_ilog_get_md_tab IS
  BEGIN
    util_g_clob_append('
| Step |   Elapsed |   Execution | Action                                                           |
|-----:|----------:|------------:|:-----------------------------------------------------------------|
');
    FOR i IN 1 .. g_debug.data.count LOOP
      util_g_clob_append( --step
                         '| ' || lpad(to_char(i), 4) || ' | ' ||
                         --elapsed
                          lpad(TRIM(to_char(util_ilog_get_runtime(g_debug.start_time, g_debug.data(i).stop_time),
                                            '99990D000')),
                               9) || ' | ' ||
                         --execution
                          lpad(TRIM(to_char(util_ilog_get_runtime(g_debug.data(i).start_time, g_debug.data(i).stop_time),
                                            '9990D000000')),
                               11) || ' | ' ||
                         --action
                          rpad(g_debug.data(i).action, 64) || ' |' || chr(10));
    END LOOP;
  END;

  --

  FUNCTION backapp
  (
    p_app_id                   IN NUMBER DEFAULT NULL,
    p_app_public_reports       IN BOOLEAN DEFAULT TRUE,
    p_app_private_reports      IN BOOLEAN DEFAULT FALSE,
    p_app_report_subscriptions IN BOOLEAN DEFAULT FALSE,
    p_app_translations         IN BOOLEAN DEFAULT TRUE,
    p_app_subscriptions        IN BOOLEAN DEFAULT TRUE,
    p_app_original_ids         IN BOOLEAN DEFAULT FALSE,
    p_app_packaged_app_mapping IN BOOLEAN DEFAULT FALSE,
    p_include_object_ddl       IN BOOLEAN DEFAULT TRUE,
    p_object_prefix            IN VARCHAR2 DEFAULT NULL,
    p_include_data             IN BOOLEAN DEFAULT FALSE,
    p_data_max_rows            IN NUMBER DEFAULT 1000,
    p_debug                    IN BOOLEAN DEFAULT FALSE
  ) RETURN BLOB IS
    l_zip          BLOB;
    l_current_user user_objects.object_name%TYPE;
    l_app_owner    user_objects.object_name%TYPE;
    l_the_point    VARCHAR2(30) := '. < this is the point ;-)';
    --    
    PROCEDURE check_owner IS
      CURSOR cur_owner IS
        SELECT owner FROM apex_applications t WHERE t.application_id = p_app_id;
    BEGIN
      util_ilog_start('check_owner');
      l_current_user := nvl(apex_application.g_flow_owner, USER);
      IF p_app_id IS NOT NULL THEN
        OPEN cur_owner;
        FETCH cur_owner
          INTO l_app_owner;
        CLOSE cur_owner;
      END IF;
      IF p_app_id IS NOT NULL AND l_app_owner IS NULL THEN
        raise_application_error(-20101,
                                'Could not find owner for application - are you sure you provided the right app_id?');
      ELSIF p_app_id IS NOT NULL AND l_app_owner != l_current_user THEN
        raise_application_error(-20102, 'You are not the owner of the app - please login as the owner.');
      END IF;
      util_ilog_stop;
    END check_owner;
    --
    PROCEDURE process_apex_app IS
      l_app_file            CLOB;
      l_count               PLS_INTEGER := 0;
      l_pattern             VARCHAR2(30) := 'prompt --application';
      l_content_start_pos   PLS_INTEGER := 0;
      l_content_stop_pos    PLS_INTEGER;
      l_content_length      PLS_INTEGER;
      l_file_path_start_pos PLS_INTEGER;
      l_file_path_stop_pos  PLS_INTEGER;
      l_file_path_length    PLS_INTEGER;
      l_file_path           VARCHAR2(255 CHAR);
      TYPE t_install_file IS TABLE OF VARCHAR2(255) INDEX BY BINARY_INTEGER;
      l_app_install_file t_install_file;
      --
      PROCEDURE get_positions IS
      BEGIN
        l_content_start_pos   := instr(l_app_file, l_pattern, l_content_start_pos + 1); --> +1: find the next pattern after the current start pos      
        l_content_stop_pos    := instr(l_app_file, l_pattern, l_content_start_pos + 1) - 1; --> +1: find the next next pattern after the current start pos (which is the next, see line before)
        l_file_path_start_pos := l_content_start_pos + 9; --> without "prompt --"
        l_file_path_stop_pos  := instr(l_app_file, chr(10), l_file_path_start_pos);
        l_content_length := CASE
                              WHEN l_content_stop_pos > 0 THEN
                               l_content_stop_pos
                              ELSE
                               length(l_app_file) + 1
                            END - l_content_start_pos;
        l_file_path_length    := l_file_path_stop_pos - l_file_path_start_pos;
      END get_positions;
      --    
    BEGIN
      util_ilog_start('app:export_application');
      dbms_lob.createtemporary(l_app_file, TRUE);
      -- https://apexplained.wordpress.com/2012/03/20/workspace-application-and-page-export-in-plsql/
      -- unfortunately not available: wwv_flow_gen_api2.export which is used in application builder (app:4000, page:4900)
      l_app_file := wwv_flow_utilities.export_application_to_clob(p_application_id            => p_app_id,
                                                                  p_export_ir_public_reports  => util_bool_to_string(p_app_public_reports),
                                                                  p_export_ir_private_reports => util_bool_to_string(p_app_private_reports),
                                                                  p_export_ir_notifications   => util_bool_to_string(p_app_report_subscriptions),
                                                                  p_export_translations       => util_bool_to_string(p_app_translations),
                                                                  p_export_pkg_app_mapping    => util_bool_to_string(p_app_packaged_app_mapping),
                                                                  p_with_original_ids         => p_app_original_ids,
                                                                  p_exclude_subscriptions     => CASE
                                                                                                   WHEN p_app_subscriptions THEN
                                                                                                    FALSE
                                                                                                   ELSE
                                                                                                    TRUE
                                                                                                 END);
      util_ilog_stop;
      -- save as single file 
      util_ilog_start('app:save_single_file');
      util_g_clob_createtemporary;
      util_g_clob_append(l_app_file);
      apex_zip.add_file(p_zipped_blob => l_zip,
                        p_file_name   => 'App/UI/f' || p_app_id || '.sql',
                        p_content     => util_g_clob_to_blob);
      util_g_clob_freetemporary;
      util_ilog_stop;
      -- split into individual files
      get_positions;
      WHILE l_content_start_pos > 0 LOOP
        l_count := l_count + 1;
        util_ilog_start('app:' || to_char(l_count));
        l_file_path := substr(str1 => l_app_file, pos => l_file_path_start_pos, len => l_file_path_length) || '.sql';
        util_ilog_append_action_text(':' || l_file_path);
        util_g_clob_createtemporary;
        util_g_clob_append(substr(str1 => l_app_file, pos => l_content_start_pos, len => l_content_length) || chr(10));
        apex_zip.add_file(p_zipped_blob => l_zip,
                          p_file_name   => 'App/UI/f' || p_app_id || '/' || l_file_path,
                          p_content     => util_g_clob_to_blob);
        util_g_clob_freetemporary;
        l_app_install_file(l_count) := l_file_path;
        get_positions;
        util_ilog_stop;
      END LOOP;
      -- create app install file
      util_ilog_start('app:create_app_install_file');
      util_g_clob_createtemporary;
      FOR i IN 1 .. l_app_install_file.count LOOP
        util_g_clob_append('@' || l_app_install_file(i) || chr(10));
      END LOOP;
      apex_zip.add_file(p_zipped_blob => l_zip,
                        p_file_name   => 'App/UI/f' || p_app_id || '/install.sql',
                        p_content     => util_g_clob_to_blob);
      util_g_clob_freetemporary;
      util_ilog_stop;
      -- END IF;
      dbms_lob.freetemporary(l_app_file);
    END process_apex_app;
    --  
    PROCEDURE process_user_ddl IS
    BEGIN
      -- user itself
      util_ilog_start('ddl:USER:' || l_current_user);
      util_g_clob_createtemporary;
      util_g_clob_append(dbms_metadata.get_ddl('USER', l_current_user));
      apex_zip.add_file(p_zipped_blob => l_zip,
                        p_file_name   => 'App/DDL/User/' || l_current_user || '.sql',
                        p_content     => util_g_clob_to_blob);
      util_g_clob_freetemporary;
      util_ilog_stop;
      -- roles
      util_ilog_start('ddl:USER:' || l_current_user || ':roles');
      util_g_clob_createtemporary;
      FOR i IN ( -- ensure we get no dbms_metadata error when no role privs exists
                SELECT DISTINCT username FROM user_role_privs) LOOP
        util_g_clob_append(dbms_metadata.get_granted_ddl('ROLE_GRANT', l_current_user));
      END LOOP;
      apex_zip.add_file(p_zipped_blob => l_zip,
                        p_file_name   => 'App/DDL/User/' || l_current_user || '_roles.sql',
                        p_content     => util_g_clob_to_blob);
      util_g_clob_freetemporary;
      util_ilog_stop;
      -- system privileges
      util_ilog_start('ddl:USER:' || l_current_user || ':system_privileges');
      util_g_clob_createtemporary;
      FOR i IN ( -- ensure we get no dbms_metadata error when no sys privs exists
                SELECT DISTINCT username FROM user_sys_privs) LOOP
        util_g_clob_append(dbms_metadata.get_granted_ddl('SYSTEM_GRANT', l_current_user));
      END LOOP;
      apex_zip.add_file(p_zipped_blob => l_zip,
                        p_file_name   => 'App/DDL/User/' || l_current_user || '_system_privileges.sql',
                        p_content     => util_g_clob_to_blob);
      util_g_clob_freetemporary;
      util_ilog_stop;
      -- object privileges
      util_ilog_start('ddl:USER:' || l_current_user || ':object_privileges');
      util_g_clob_createtemporary;
      FOR i IN ( -- ensure we get no dbms_metadata error when no object grants exists
                SELECT DISTINCT grantee FROM user_tab_privs WHERE grantee = l_current_user) LOOP
        util_g_clob_append(dbms_metadata.get_granted_ddl('OBJECT_GRANT', l_current_user));
      END LOOP;
      apex_zip.add_file(p_zipped_blob => l_zip,
                        p_file_name   => 'App/DDL/User/' || l_current_user || '_object_privileges.sql',
                        p_content     => util_g_clob_to_blob);
      util_g_clob_freetemporary;
      util_ilog_stop;
    END process_user_ddl;
    --
    PROCEDURE process_object_ddl IS
      l_ddl_file CLOB;
    BEGIN
      dbms_lob.createtemporary(l_ddl_file, TRUE);
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
                                          regexp_replace(object_type, 'EX$', 'ICES', 1, 0, 'i')
                                         WHEN object_type LIKE '%Y' THEN
                                          regexp_replace(object_type, 'Y$', 'IES', 1, 0, 'i')
                                         ELSE
                                          object_type || 'S'
                                       END),
                               ' ',
                               NULL) AS dir_name
                  FROM user_objects
                 WHERE object_type NOT IN ('TABLE PARTITION', 'PACKAGE BODY', 'TYPE BODY', 'LOB')
                   AND object_name NOT LIKE 'SYS_PLSQL%'
                   AND object_name NOT LIKE 'ISEQ$$%'
                   AND object_name LIKE nvl(p_object_prefix, '%') || '%'
                 ORDER BY object_type, object_name) LOOP
        util_ilog_start('ddl:' || i.object_type || ':' || i.object_name);
        CASE i.object_type
          WHEN 'PACKAGE' THEN
            l_ddl_file := dbms_metadata.get_ddl(object_type => i.object_type,
                                                NAME        => i.object_name,
                                                SCHEMA      => l_current_user);
          
            -- spec   
            util_g_clob_createtemporary;
            util_g_clob_append(ltrim(substr(l_ddl_file,
                                            1,
                                            regexp_instr(l_ddl_file, 'CREATE OR REPLACE( EDITIONABLE)? PACKAGE BODY') - 1),
                                     ' ' || chr(10)));
            apex_zip.add_file(p_zipped_blob => l_zip,
                              p_file_name   => 'App/DDL/' || i.dir_name || '/' || i.object_name || '.pks',
                              p_content     => util_g_clob_to_blob);
            util_g_clob_freetemporary;
            -- body          
            util_g_clob_createtemporary;
            util_g_clob_append(substr(l_ddl_file,
                                      regexp_instr(l_ddl_file, 'CREATE OR REPLACE( EDITIONABLE)? PACKAGE BODY')));
            apex_zip.add_file(p_zipped_blob => l_zip,
                              p_file_name   => 'App/DDL/PackageBodies/' || i.object_name || '.pkb',
                              p_content     => util_g_clob_to_blob);
            util_g_clob_freetemporary;
          WHEN 'VIEW' THEN
            util_g_clob_createtemporary;
            util_g_clob_append(ltrim(regexp_replace(regexp_replace(dbms_metadata.get_ddl(object_type => i.object_type,
                                                                                         NAME        => i.object_name,
                                                                                         SCHEMA      => l_current_user),
                                                                   '\(.*\) ', -- remove additional column list from the compiler
                                                                   NULL,
                                                                   1,
                                                                   1),
                                                    '^\s*SELECT', -- remove additional whitespace from the compiler
                                                    'SELECT',
                                                    1,
                                                    1,
                                                    'im'),
                                     ' ' || chr(10)));
            apex_zip.add_file(p_zipped_blob => l_zip,
                              p_file_name   => 'App/DDL/' || i.dir_name || '/' || i.object_name || '.sql',
                              p_content     => util_g_clob_to_blob);
            util_g_clob_freetemporary;
          ELSE
            util_g_clob_createtemporary;
            util_g_clob_append(dbms_metadata.get_ddl(object_type => i.object_type,
                                                     NAME        => i.object_name,
                                                     SCHEMA      => l_current_user));
            apex_zip.add_file(p_zipped_blob => l_zip,
                              p_file_name   => 'App/DDL/' || i.dir_name || '/' || i.object_name || '.sql',
                              p_content     => util_g_clob_to_blob);
            util_g_clob_freetemporary;
        END CASE;
        util_ilog_stop;
      END LOOP;
      dbms_lob.freetemporary(l_ddl_file);
    END process_object_ddl;
    --  
    PROCEDURE process_object_grants IS
    BEGIN
      FOR i IN (SELECT DISTINCT p.grantor, p.privilege, p.table_name AS object_name
                  FROM user_tab_privs p
                  JOIN user_objects o ON p.table_name = o.object_name
                 ORDER BY privilege, object_name) LOOP
        util_ilog_start('ddl:GRANT:' || i.privilege || ':' || i.object_name);
        util_g_clob_createtemporary;
        util_g_clob_append(dbms_metadata.get_dependent_ddl('OBJECT_GRANT', i.object_name, i.grantor));
        apex_zip.add_file(p_zipped_blob => l_zip,
                          p_file_name   => 'App/DDL/Grants/' || i.privilege || '_on_' || i.object_name || '.sql',
                          p_content     => util_g_clob_to_blob);
        util_g_clob_freetemporary;
        util_ilog_stop;
      END LOOP;
    END process_object_grants;
    --
    PROCEDURE process_data IS
    BEGIN
      FOR i IN (SELECT table_name, tablespace_name
                  FROM user_tables t
                 WHERE EXTERNAL = 'NO'
                   AND table_name LIKE nvl(p_object_prefix, '%') || '%'
                 ORDER BY table_name) LOOP
        util_ilog_start('data:' || i.table_name);
        util_g_clob_createtemporary;
        util_g_clob_query_to_csv(p_query => 'select * from ' || i.table_name, p_max_rows => p_data_max_rows);
        apex_zip.add_file(p_zipped_blob => l_zip,
                          p_file_name   => 'App/Data/' || i.table_name || '.csv',
                          p_content     => util_g_clob_to_blob);
        util_g_clob_freetemporary;
        util_ilog_stop;
      END LOOP;
    END process_data;
    --
    PROCEDURE process_docs_folder IS
    BEGIN
      util_ilog_start('folder:Docs');
      util_g_clob_createtemporary;
      util_g_clob_append(l_the_point);
      apex_zip.add_file(p_zipped_blob => l_zip,
                        p_file_name   => 'Docs/_save_your_docs_here',
                        p_content     => util_g_clob_to_blob);
      util_g_clob_freetemporary;
      util_ilog_stop;
    END process_docs_folder;
    --
    PROCEDURE process_scripts_folder IS
    BEGIN
      util_ilog_start('folder:Scripts');
      util_g_clob_createtemporary;
      util_g_clob_append(l_the_point);
      apex_zip.add_file(p_zipped_blob => l_zip,
                        p_file_name   => 'Scripts/_save_your_scripts_here',
                        p_content     => util_g_clob_to_blob);
      util_g_clob_freetemporary;
      util_ilog_stop;
    END process_scripts_folder;
    --
    PROCEDURE process_tests_folder IS
    BEGIN
      util_ilog_start('folder:Tests');
      util_g_clob_createtemporary;
      util_g_clob_append(l_the_point);
      apex_zip.add_file(p_zipped_blob => l_zip,
                        p_file_name   => 'Tests/_save_your_tests_here',
                        p_content     => util_g_clob_to_blob);
      util_g_clob_freetemporary;
      util_ilog_stop;
    END process_tests_folder;
    --
    PROCEDURE process_readme_dist IS
    BEGIN
      util_ilog_start('README.dist.md');
      util_g_clob_createtemporary;
      util_g_clob_append('# Your global README file
      
It is a good practice to have a README file in the root of your project with
a high level overview of your application. Put the more detailed docs in the 
Docs folder.

You can start with a copy of this file. Name it README.md and try to use 
Markdown when writing your content - this has many benefits and you don''t
waist time by formatting your docs. If you are unsure have a look at some 
projects at [Github][1] or any other code hosting platform.

[1]: https://github.com
');
      apex_zip.add_file(p_zipped_blob => l_zip, p_file_name => 'README.dist.md', p_content => util_g_clob_to_blob);
      util_g_clob_freetemporary;
      util_ilog_stop;
    END process_readme_dist;
    --
    PROCEDURE create_debug_log IS
    BEGIN
      IF p_debug THEN
        util_g_clob_createtemporary;
        util_g_clob_append('# PLEX - BackApp Log

        
## Parameters

```sql
SELECT plex.backapp(
  p_app_id                   => ' || to_char(p_app_id) || ',
  p_app_public_reports       => ''' || util_bool_to_string(p_app_public_reports) || ''',
  p_app_private_reports      => ''' || util_bool_to_string(p_app_private_reports) || ''',
  p_app_report_subscriptions => ''' || util_bool_to_string(p_app_report_subscriptions) || ''',
  p_app_translations         => ''' || util_bool_to_string(p_app_translations) || ''',
  p_app_subscriptions        => ''' || util_bool_to_string(p_app_subscriptions) || ''',
  p_app_original_ids         => ''' || util_bool_to_string(p_app_original_ids) || ''',
  p_app_packaged_app_mapping => ''' || util_bool_to_string(p_app_packaged_app_mapping) || ''',
  p_include_object_ddl       => ''' || util_bool_to_string(p_include_object_ddl) || ''',
  p_object_prefix            => ' || CASE WHEN p_object_prefix IS NOT NULL THEN
                           '''' || p_object_prefix || '''' ELSE 'NULL'
                           END || ',
  p_include_data             => ''' || util_bool_to_string(p_include_data) || ''',
  p_data_max_rows            => ' || to_char(p_data_max_rows) || ',
  p_debug                    => ''' || util_bool_to_string(p_debug) || '''
)
  FROM dual;
```

## Log Entries

Export started at ' || to_char(g_debug.start_time, 'yyyy-mm-dd hh24:mi:ss') || ' and took ' ||
                           TRIM(to_char(round(util_ilog_get_runtime(g_debug.start_time, g_debug.stop_time), 3),
                                        '999G990D000')) || ' seconds to finish.                         
');
        util_ilog_get_md_tab;
        apex_zip.add_file(p_zipped_blob => l_zip,
                          p_file_name   => 'plex_backapp_log.md',
                          p_content     => util_g_clob_to_blob);
        util_g_clob_freetemporary;
      END IF;
    END create_debug_log;
    --
  BEGIN
    util_ilog_init('plex.backapp' || CASE WHEN p_app_id IS NOT NULL THEN '(' || to_char(p_app_id) || ')' END, p_debug);
    dbms_lob.createtemporary(l_zip, TRUE);
    check_owner;
    --
    IF p_app_id IS NOT NULL THEN
      process_apex_app;
    END IF;
    --
    process_user_ddl;
    --
    IF p_include_object_ddl THEN
      util_setup_dbms_metadata;
      process_object_ddl;
      process_object_grants;
    END IF;
    --
    IF p_include_data THEN
      process_data;
    END IF;
    --
    process_docs_folder;
    process_scripts_folder;
    process_tests_folder;
    process_readme_dist;
    --
    util_ilog_exit;
    create_debug_log;
    apex_zip.finish(l_zip);
    RETURN l_zip;
  END backapp;

  --

  FUNCTION backapp
  (
    p_app_id                   IN NUMBER DEFAULT NULL,
    p_app_public_reports       IN VARCHAR2 DEFAULT 'Y',
    p_app_private_reports      IN VARCHAR2 DEFAULT 'N',
    p_app_report_subscriptions IN VARCHAR2 DEFAULT 'N',
    p_app_translations         IN VARCHAR2 DEFAULT 'Y',
    p_app_subscriptions        IN VARCHAR2 DEFAULT 'Y',
    p_app_original_ids         IN VARCHAR2 DEFAULT 'N',
    p_app_packaged_app_mapping IN VARCHAR2 DEFAULT 'N',
    p_include_object_ddl       IN VARCHAR2 DEFAULT 'Y',
    p_object_prefix            IN VARCHAR2 DEFAULT NULL,
    p_include_data             IN VARCHAR2 DEFAULT 'N',
    p_data_max_rows            IN NUMBER DEFAULT 1000,
    p_debug                    IN VARCHAR2 DEFAULT 'N'
  ) RETURN BLOB IS
  BEGIN
    RETURN backapp(p_app_id                   => p_app_id,
                   p_app_public_reports       => util_string_to_bool(p_app_public_reports, TRUE),
                   p_app_private_reports      => util_string_to_bool(p_app_private_reports, FALSE),
                   p_app_report_subscriptions => util_string_to_bool(p_app_report_subscriptions, FALSE),
                   p_app_translations         => util_string_to_bool(p_app_translations, TRUE),
                   p_app_subscriptions        => util_string_to_bool(p_app_subscriptions, TRUE),
                   p_app_original_ids         => util_string_to_bool(p_app_original_ids, FALSE),
                   p_app_packaged_app_mapping => util_string_to_bool(p_app_packaged_app_mapping, FALSE),
                   p_include_object_ddl       => util_string_to_bool(p_include_object_ddl, TRUE),
                   p_object_prefix            => p_object_prefix,
                   p_include_data             => util_string_to_bool(p_include_data, FALSE),
                   p_data_max_rows            => p_data_max_rows,
                   p_debug                    => util_string_to_bool(p_debug, FALSE));
  END;

  --

  PROCEDURE add_query
  (
    p_query     VARCHAR2,
    p_file_name VARCHAR2,
    p_max_rows  NUMBER DEFAULT 100000
  ) IS
    v_row t_queries_row;
  BEGIN
    v_row.query := p_query;
    v_row.file_name := p_file_name;
    v_row.max_rows := p_max_rows;
    g_queries(g_queries.count + 1) := v_row;
  END add_query;

  --

  FUNCTION queries_to_csv
  (
    p_delimiter       IN VARCHAR2 DEFAULT ',',
    p_quote_mark      IN VARCHAR2 DEFAULT '"',
    p_line_terminator IN VARCHAR2 DEFAULT chr(10),
    p_header_prefix   IN VARCHAR2 DEFAULT NULL,
    p_debug           BOOLEAN DEFAULT FALSE
  ) RETURN BLOB IS
    l_zip BLOB;
    --
    PROCEDURE create_debug_log IS
    BEGIN
      IF p_debug THEN
        util_g_clob_createtemporary;
        util_g_clob_append('# PLEX - Queries to CSV Log

        
## Parameters

```sql
SELECT plex.queries_to_csv(
  p_delimiter       => ''' || p_delimiter || ''',
  p_quote_mark      => ''' || p_quote_mark || ''',
  p_line_terminator => ' || CASE p_line_terminator WHEN c_cr THEN 'chr(13)' WHEN c_lf THEN
                           'chr(10)' WHEN c_crlf THEN 'chr(10) || chr(13)' ELSE p_line_terminator
                           END || ',
  p_header_prefix   => ' || CASE WHEN p_header_prefix IS NOT NULL THEN
                           '''' || p_header_prefix || '''' ELSE 'NULL'
                           END || ',
  p_debug           => ''' || util_bool_to_string(p_debug) || '''
)
  FROM dual;
```

## Log Entries

Export started at ' || to_char(g_debug.start_time, 'yyyy-mm-dd hh24:mi:ss') || ' and took ' ||
                           TRIM(to_char(round(util_ilog_get_runtime(g_debug.start_time, g_debug.stop_time), 3),
                                        '999G990D000')) || ' seconds to finish.                         
');
        util_ilog_get_md_tab;
        apex_zip.add_file(p_zipped_blob => l_zip,
                          p_file_name   => 'plex_queries_to_csv_log.md',
                          p_content     => util_g_clob_to_blob);
        util_g_clob_freetemporary;
      END IF;
    END create_debug_log;
    --
  BEGIN
    IF g_queries.count = 0 THEN
      raise_application_error(-20201,
                              'You need first to add queries by using plex.add_query. Calling plex.queries_to_csv clears the global queries array for subsequent processing.');
    ELSE
      util_ilog_init('plex.queries_to_csv', p_debug);
      dbms_lob.createtemporary(l_zip, TRUE);
      FOR i IN g_queries.first .. g_queries.last LOOP
        util_ilog_start('process_query_to_csv:' || to_char(i) || ':' || g_queries(i).file_name);
        util_g_clob_createtemporary;
        util_g_clob_query_to_csv(p_query           => g_queries(i).query,
                                 p_max_rows        => g_queries(i).max_rows,
                                 p_delimiter       => p_delimiter,
                                 p_quote_mark      => p_quote_mark,
                                 p_line_terminator => p_line_terminator,
                                 p_header_prefix   => p_header_prefix);
        apex_zip.add_file(p_zipped_blob => l_zip,
                          p_file_name   => regexp_replace(srcstr     => g_queries(i).file_name,
                                                          pattern    => '\.csv$',
                                                          replacestr => NULL,
                                                          position   => 1,
                                                          occurrence => 0,
                                                          modifier   => 'i') || '.csv',
                          p_content     => util_g_clob_to_blob);
        util_g_clob_freetemporary;
        util_ilog_stop;
      END LOOP;
      g_queries.delete;
      util_ilog_exit;
      create_debug_log;
      apex_zip.finish(l_zip);
      RETURN l_zip;
    END IF;
  END queries_to_csv;

  --

  FUNCTION queries_to_csv
  (
    p_delimiter       IN VARCHAR2 DEFAULT ',',
    p_quote_mark      IN VARCHAR2 DEFAULT '"',
    p_line_terminator IN VARCHAR2 DEFAULT lf,
    p_header_prefix   IN VARCHAR2 DEFAULT NULL,
    p_debug           IN VARCHAR2 DEFAULT 'N' -- Generate plex_queries_to_csv_log.md in the root of the zip file.
  ) RETURN BLOB IS
  BEGIN
    RETURN queries_to_csv(p_delimiter       => p_delimiter,
                          p_quote_mark      => p_quote_mark,
                          p_line_terminator => p_line_terminator,
                          p_header_prefix   => p_header_prefix,
                          p_debug           => util_string_to_bool(p_debug, FALSE));
  END queries_to_csv;

  --

  FUNCTION view_debug_log RETURN t_debug_view_tab
    PIPELINED IS
    v_return t_debug_view_row;
  BEGIN
    v_return.overall_start_time := g_debug.start_time;
    v_return.overall_run_time   := round(util_ilog_get_runtime(g_debug.start_time, g_debug.stop_time), 3);
    FOR i IN 1 .. g_debug.data.count LOOP
      v_return.step      := i;
      v_return.elapsed   := round(util_ilog_get_runtime(g_debug.start_time, g_debug.data(i).stop_time), 3);
      v_return.execution := round(util_ilog_get_runtime(g_debug.data(i).start_time, g_debug.data(i).stop_time), 6);
      v_return.module    := g_debug.module;
      v_return.action    := g_debug.data(i).action;
      PIPE ROW(v_return);
    END LOOP;
  END;

--

END plex;
/
