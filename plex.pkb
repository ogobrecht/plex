CREATE     OR REPLACE PACKAGE BODY plex IS 

  --

  TYPE rec_ilog_step IS RECORD ( --

   action                 application_info_text,
  start_time             TIMESTAMP(6),
  stop_time              TIMESTAMP(6),
  elapsed                NUMBER,
  execution              NUMBER );
  TYPE tab_ilog_step IS
    TABLE OF rec_ilog_step INDEX BY BINARY_INTEGER;
    
    --
  TYPE rec_ilog IS RECORD ( --
   module                 application_info_text,
  enabled                BOOLEAN,
  start_time             TIMESTAMP(6),
  stop_time              TIMESTAMP(6),
  run_time               NUMBER,
  measured_time          NUMBER,
  unmeasured_time        NUMBER,
  data                   tab_ilog_step );
  
  --
  TYPE tab_vc1000 IS
    TABLE OF VARCHAR2(1000) INDEX BY BINARY_INTEGER;
    
    --
  TYPE rec_ddl_files IS RECORD ( --
   sequences_             tab_vc1000,
  tables_                tab_vc1000,
  ref_constraints_       tab_vc1000,
  indices_               tab_vc1000,
  views_                 tab_vc1000,
  types_                 tab_vc1000,
  type_bodies_           tab_vc1000,
  triggers_              tab_vc1000,
  functions_             tab_vc1000,
  procedures_            tab_vc1000,
  packages_              tab_vc1000,
  package_bodies_        tab_vc1000,
  grants_                tab_vc1000,
  other_objects_         tab_vc1000 );
  
    --
  TYPE rec_queries IS RECORD (--
   query                  VARCHAR2(32767 CHAR),
  file_name              VARCHAR2(256 CHAR),
  max_rows               NUMBER DEFAULT 100000 );
  TYPE tab_queries IS
    TABLE OF rec_queries INDEX BY PLS_INTEGER;
  
  -- GLOBAL VARIABLES
  g_clob                 CLOB;
  g_clob_varchar_cache   VARCHAR2(32767char);
  g_ilog                 rec_ilog;
  g_ddl_files            rec_ddl_files;
  g_queries              tab_queries;

  -- CODE

  FUNCTION tab RETURN VARCHAR2
    IS
  BEGIN
    RETURN c_tab;
  END;

  FUNCTION lf RETURN VARCHAR2
    IS
  BEGIN
    RETURN c_lf;
  END;

  FUNCTION cr RETURN VARCHAR2
    IS
  BEGIN
    RETURN c_cr;
  END;

  FUNCTION crlf RETURN VARCHAR2
    IS
  BEGIN
    RETURN c_crlf;
  END;
    
  --

  FUNCTION util_bool_to_string (
    p_bool IN BOOLEAN
  ) RETURN VARCHAR2
    IS
  BEGIN
    RETURN
      CASE
        WHEN p_bool THEN 'TRUE'
        ELSE 'FALSE'
      END;
  END util_bool_to_string;

  FUNCTION util_string_to_bool (
    p_bool_string   IN VARCHAR2,
    p_default       IN BOOLEAN
  ) RETURN BOOLEAN IS
    l_bool_string   VARCHAR2(1 CHAR);
    l_return        BOOLEAN;
  BEGIN
    l_bool_string   := upper(substr(
      p_bool_string,
      1,
      1
    ) );
    l_return        :=
      CASE
        WHEN l_bool_string IN (
          '1',
          'Y',
          'T'
        ) THEN true
        WHEN l_bool_string IN (
          '0',
          'N',
          'F'
        ) THEN false
        ELSE p_default
      END;

    RETURN l_return;
  END util_string_to_bool;

  FUNCTION util_clob_to_blob (
    p_clob CLOB
  ) RETURN BLOB IS

    l_blob           BLOB;
    l_lang_context   INTEGER := dbms_lob.default_lang_ctx;
    l_warning        INTEGER := dbms_lob.warn_inconvertible_char;
    l_dest_offset    INTEGER := 1;
    l_src_offset     INTEGER := 1;
  BEGIN
    IF
      p_clob IS NOT NULL
    THEN
      dbms_lob.createtemporary(
        l_blob,
        true
      );
      dbms_lob.converttoblob(
        dest_lob       => l_blob,
        src_clob       => p_clob,
        amount         => dbms_lob.lobmaxsize,
        dest_offset    => l_dest_offset,
        src_offset     => l_src_offset,
        blob_csid      => nls_charset_id('AL32UTF8'),
        lang_context   => l_lang_context,
        warning        => l_warning
      );

    END IF;

    RETURN l_blob;
  END util_clob_to_blob;

  FUNCTION util_multi_replace (
    p_source_string   VARCHAR2,
    p_1_find          VARCHAR2 DEFAULT NULL,
    p_1_replace       VARCHAR2 DEFAULT NULL,
    p_2_find          VARCHAR2 DEFAULT NULL,
    p_2_replace       VARCHAR2 DEFAULT NULL,
    p_3_find          VARCHAR2 DEFAULT NULL,
    p_3_replace       VARCHAR2 DEFAULT NULL,
    p_4_find          VARCHAR2 DEFAULT NULL,
    p_4_replace       VARCHAR2 DEFAULT NULL,
    p_5_find          VARCHAR2 DEFAULT NULL,
    p_5_replace       VARCHAR2 DEFAULT NULL,
    p_6_find          VARCHAR2 DEFAULT NULL,
    p_6_replace       VARCHAR2 DEFAULT NULL,
    p_7_find          VARCHAR2 DEFAULT NULL,
    p_7_replace       VARCHAR2 DEFAULT NULL,
    p_8_find          VARCHAR2 DEFAULT NULL,
    p_8_replace       VARCHAR2 DEFAULT NULL,
    p_9_find          VARCHAR2 DEFAULT NULL,
    p_9_replace       VARCHAR2 DEFAULT NULL,
    p_10_find         VARCHAR2 DEFAULT NULL,
    p_10_replace      VARCHAR2 DEFAULT NULL,
    p_11_find         VARCHAR2 DEFAULT NULL,
    p_11_replace      VARCHAR2 DEFAULT NULL,
    p_12_find         VARCHAR2 DEFAULT NULL,
    p_12_replace      VARCHAR2 DEFAULT NULL,
    p_13_find         VARCHAR2 DEFAULT NULL,
    p_13_replace      VARCHAR2 DEFAULT NULL,
    p_14_find         VARCHAR2 DEFAULT NULL,
    p_14_replace      VARCHAR2 DEFAULT NULL,
    p_15_find         VARCHAR2 DEFAULT NULL,
    p_15_replace      VARCHAR2 DEFAULT NULL,
    p_16_find         VARCHAR2 DEFAULT NULL,
    p_16_replace      VARCHAR2 DEFAULT NULL,
    p_17_find         VARCHAR2 DEFAULT NULL,
    p_17_replace      VARCHAR2 DEFAULT NULL,
    p_18_find         VARCHAR2 DEFAULT NULL,
    p_18_replace      VARCHAR2 DEFAULT NULL,
    p_19_find         VARCHAR2 DEFAULT NULL,
    p_19_replace      VARCHAR2 DEFAULT NULL,
    p_20_find         VARCHAR2 DEFAULT NULL,
    p_20_replace      VARCHAR2 DEFAULT NULL,
    p_21_find         VARCHAR2 DEFAULT NULL,
    p_21_replace      VARCHAR2 DEFAULT NULL,
    p_22_find         VARCHAR2 DEFAULT NULL,
    p_22_replace      VARCHAR2 DEFAULT NULL,
    p_23_find         VARCHAR2 DEFAULT NULL,
    p_23_replace      VARCHAR2 DEFAULT NULL,
    p_24_find         VARCHAR2 DEFAULT NULL,
    p_24_replace      VARCHAR2 DEFAULT NULL,
    p_25_find         VARCHAR2 DEFAULT NULL,
    p_25_replace      VARCHAR2 DEFAULT NULL
  ) RETURN VARCHAR2 IS
    l_return   VARCHAR2(32767);
  BEGIN
    l_return   := p_source_string;
    IF
      p_1_find IS NOT NULL
    THEN
      l_return   := replace(
        l_return,
        p_1_find,
        p_1_replace
      );
    END IF;

    IF
      p_2_find IS NOT NULL
    THEN
      l_return   := replace(
        l_return,
        p_2_find,
        p_2_replace
      );
    END IF;

    IF
      p_3_find IS NOT NULL
    THEN
      l_return   := replace(
        l_return,
        p_3_find,
        p_3_replace
      );
    END IF;

    IF
      p_4_find IS NOT NULL
    THEN
      l_return   := replace(
        l_return,
        p_4_find,
        p_4_replace
      );
    END IF;

    IF
      p_5_find IS NOT NULL
    THEN
      l_return   := replace(
        l_return,
        p_5_find,
        p_5_replace
      );
    END IF;

    IF
      p_6_find IS NOT NULL
    THEN
      l_return   := replace(
        l_return,
        p_6_find,
        p_6_replace
      );
    END IF;

    IF
      p_7_find IS NOT NULL
    THEN
      l_return   := replace(
        l_return,
        p_7_find,
        p_7_replace
      );
    END IF;

    IF
      p_8_find IS NOT NULL
    THEN
      l_return   := replace(
        l_return,
        p_8_find,
        p_8_replace
      );
    END IF;

    IF
      p_9_find IS NOT NULL
    THEN
      l_return   := replace(
        l_return,
        p_9_find,
        p_9_replace
      );
    END IF;

    IF
      p_10_find IS NOT NULL
    THEN
      l_return   := replace(
        l_return,
        p_10_find,
        p_10_replace
      );
    END IF;

    IF
      p_11_find IS NOT NULL
    THEN
      l_return   := replace(
        l_return,
        p_11_find,
        p_11_replace
      );
    END IF;

    IF
      p_12_find IS NOT NULL
    THEN
      l_return   := replace(
        l_return,
        p_12_find,
        p_12_replace
      );
    END IF;

    IF
      p_13_find IS NOT NULL
    THEN
      l_return   := replace(
        l_return,
        p_13_find,
        p_13_replace
      );
    END IF;

    IF
      p_14_find IS NOT NULL
    THEN
      l_return   := replace(
        l_return,
        p_14_find,
        p_14_replace
      );
    END IF;

    IF
      p_15_find IS NOT NULL
    THEN
      l_return   := replace(
        l_return,
        p_15_find,
        p_15_replace
      );
    END IF;

    IF
      p_16_find IS NOT NULL
    THEN
      l_return   := replace(
        l_return,
        p_16_find,
        p_16_replace
      );
    END IF;

    IF
      p_17_find IS NOT NULL
    THEN
      l_return   := replace(
        l_return,
        p_17_find,
        p_17_replace
      );
    END IF;

    IF
      p_18_find IS NOT NULL
    THEN
      l_return   := replace(
        l_return,
        p_18_find,
        p_18_replace
      );
    END IF;

    IF
      p_19_find IS NOT NULL
    THEN
      l_return   := replace(
        l_return,
        p_19_find,
        p_19_replace
      );
    END IF;

    IF
      p_20_find IS NOT NULL
    THEN
      l_return   := replace(
        l_return,
        p_20_find,
        p_20_replace
      );
    END IF;

    IF
      p_21_find IS NOT NULL
    THEN
      l_return   := replace(
        l_return,
        p_21_find,
        p_21_replace
      );
    END IF;

    IF
      p_22_find IS NOT NULL
    THEN
      l_return   := replace(
        l_return,
        p_22_find,
        p_22_replace
      );
    END IF;

    IF
      p_23_find IS NOT NULL
    THEN
      l_return   := replace(
        l_return,
        p_23_find,
        p_23_replace
      );
    END IF;

    IF
      p_24_find IS NOT NULL
    THEN
      l_return   := replace(
        l_return,
        p_24_find,
        p_24_replace
      );
    END IF;

    IF
      p_25_find IS NOT NULL
    THEN
      l_return   := replace(
        l_return,
        p_25_find,
        p_25_replace
      );
    END IF;

    RETURN l_return;
  END util_multi_replace;

  FUNCTION util_calc_data_timestamp (
    p_as_of_minutes_ago NUMBER
  ) RETURN TIMESTAMP IS
    l_return   TIMESTAMP;
  BEGIN
    EXECUTE IMMEDIATE replace(
      'SELECT systimestamp - INTERVAL ''#MINUTES#'' MINUTE FROM dual',
      '#MINUTES#',
      TO_CHAR(p_as_of_minutes_ago)
    )
      INTO l_return;
    RETURN l_return;
  END util_calc_data_timestamp;

  PROCEDURE util_setup_dbms_metadata (
    p_pretty                 IN BOOLEAN DEFAULT true,
    p_constraints            IN BOOLEAN DEFAULT true,
    p_ref_constraints        IN BOOLEAN DEFAULT false,
    p_partitioning           IN BOOLEAN DEFAULT true,
    p_tablespace             IN BOOLEAN DEFAULT false,
    p_storage                IN BOOLEAN DEFAULT false,
    p_segment_attributes     IN BOOLEAN DEFAULT false,
    p_sqlterminator          IN BOOLEAN DEFAULT true,
    p_constraints_as_alter   IN BOOLEAN DEFAULT false,
    p_emit_schema            IN BOOLEAN DEFAULT true
  )
    IS
  BEGIN
    dbms_metadata.set_transform_param(
      dbms_metadata.session_transform,
      'PRETTY',
      p_pretty
    );
    dbms_metadata.set_transform_param(
      dbms_metadata.session_transform,
      'CONSTRAINTS',
      p_constraints
    );
    dbms_metadata.set_transform_param(
      dbms_metadata.session_transform,
      'REF_CONSTRAINTS',
      p_ref_constraints
    );
    dbms_metadata.set_transform_param(
      dbms_metadata.session_transform,
      'PARTITIONING',
      p_partitioning
    );
    dbms_metadata.set_transform_param(
      dbms_metadata.session_transform,
      'TABLESPACE',
      p_tablespace
    );
    dbms_metadata.set_transform_param(
      dbms_metadata.session_transform,
      'STORAGE',
      p_storage
    );
    dbms_metadata.set_transform_param(
      dbms_metadata.session_transform,
      'SEGMENT_ATTRIBUTES',
      p_segment_attributes
    );
    dbms_metadata.set_transform_param(
      dbms_metadata.session_transform,
      'SQLTERMINATOR',
      p_sqlterminator
    );
    dbms_metadata.set_transform_param(
      dbms_metadata.session_transform,
      'CONSTRAINTS_AS_ALTER',
      p_constraints_as_alter
    );
    dbms_metadata.set_transform_param(
      dbms_metadata.session_transform,
      'EMIT_SCHEMA',
      p_emit_schema
    );
  END util_setup_dbms_metadata;

  PROCEDURE util_g_clob_createtemporary
    IS
  BEGIN
    dbms_lob.createtemporary(
      g_clob,
      true
    );
  END util_g_clob_createtemporary;

  PROCEDURE util_g_clob_freetemporary
    IS
  BEGIN
    dbms_lob.freetemporary(g_clob);
  END util_g_clob_freetemporary;

  PROCEDURE util_g_clob_flush_cache
    IS
  BEGIN
    IF
      g_clob_varchar_cache IS NOT NULL
    THEN
      IF
        g_clob IS NULL
      THEN
        g_clob   := g_clob_varchar_cache;
      ELSE
        dbms_lob.append(
          g_clob,
          g_clob_varchar_cache
        );
      END IF;

      g_clob_varchar_cache   := NULL;
    END IF;
  END util_g_clob_flush_cache;

  PROCEDURE util_g_clob_append (
    p_content IN VARCHAR2
  )
    IS
  BEGIN
    g_clob_varchar_cache   := g_clob_varchar_cache || p_content;
  EXCEPTION
    WHEN value_error THEN
      IF
        g_clob IS NULL
      THEN
        g_clob   := g_clob_varchar_cache;
      ELSE
        dbms_lob.append(
          g_clob,
          g_clob_varchar_cache
        );
      END IF;

      g_clob_varchar_cache   := p_content;
  END util_g_clob_append;

  PROCEDURE util_g_clob_append (
    p_content IN CLOB
  )
    IS
  BEGIN
    util_g_clob_flush_cache;
    IF
      g_clob IS NULL
    THEN
      g_clob   := p_content;
    ELSE
      dbms_lob.append(
        g_clob,
        p_content
      );
    END IF;

  END util_g_clob_append;

  FUNCTION util_g_clob_to_blob RETURN BLOB IS

    l_blob           BLOB;
    l_lang_context   INTEGER := dbms_lob.default_lang_ctx;
    l_warning        INTEGER := dbms_lob.warn_inconvertible_char;
    l_dest_offset    INTEGER := 1;
    l_src_offset     INTEGER := 1;
  BEGIN
    util_g_clob_flush_cache;
    IF
      g_clob IS NOT NULL
    THEN
      dbms_lob.createtemporary(
        l_blob,
        true
      );
      dbms_lob.converttoblob(
        dest_lob       => l_blob,
        src_clob       => g_clob,
        amount         => dbms_lob.lobmaxsize,
        dest_offset    => l_dest_offset,
        src_offset     => l_src_offset,
        blob_csid      => nls_charset_id('AL32UTF8'),
        lang_context   => l_lang_context,
        warning        => l_warning
      );

    END IF;

    RETURN l_blob;
  END util_g_clob_to_blob;

  PROCEDURE util_g_clob_query_to_csv (
    p_query             VARCHAR2,
    p_max_rows          NUMBER DEFAULT 1000,
    --
    p_delimiter         VARCHAR2 DEFAULT ',',
    p_quote_mark        VARCHAR2 DEFAULT '"',
    p_line_terminator   VARCHAR2 DEFAULT lf,
    p_header_prefix     VARCHAR2 DEFAULT NULL
  ) IS
    -- inspired by Tim Hall: https://oracle-base.com/dba/script?category=miscellaneous&file=csv.sql

    l_cursor                       PLS_INTEGER;
    l_ignore                       PLS_INTEGER;
    l_data_count                   PLS_INTEGER := 0;
    l_col_cnt                      PLS_INTEGER;
    l_desc_tab                     dbms_sql.desc_tab3;
    l_buffer_varchar2              VARCHAR2(32767);
    l_buffer_clob                  CLOB;
    l_buffer_blob                  BLOB;
    c_buffer_clob_varchar2_limit   CONSTANT PLS_INTEGER := 4000;

    -- numeric type identfiers
    c_number                       CONSTANT PLS_INTEGER := 2; -- also FLOAT
    c_binary_float                 CONSTANT PLS_INTEGER := 100;
    c_binary_double                CONSTANT PLS_INTEGER := 101;
    -- string type identfiers
    c_char                         CONSTANT PLS_INTEGER := 96; -- also NCHAR
    c_varchar2                     CONSTANT PLS_INTEGER := 1; -- also NVARCHAR2
    c_long                         CONSTANT PLS_INTEGER := 8;
    c_clob                         CONSTANT PLS_INTEGER := 112; -- also NCLOB
    c_xmltype                      CONSTANT PLS_INTEGER := 109; -- also ANYDATA, ANYDATASET, ANYTYPE, Object type, VARRAY, Nested table
    c_rowid                        CONSTANT PLS_INTEGER := 11;
    c_urowid                       CONSTANT PLS_INTEGER := 208;
    -- binary type identfiers
    c_raw                          CONSTANT PLS_INTEGER := 23;
    c_long_raw                     CONSTANT PLS_INTEGER := 24;
    c_blob                         CONSTANT PLS_INTEGER := 113;
    c_bfile                        CONSTANT PLS_INTEGER := 114;
    -- date type identfiers
    c_date                         CONSTANT PLS_INTEGER := 12;
    c_timestamp                    CONSTANT PLS_INTEGER := 180;
    c_timestamp_with_time_zone     CONSTANT PLS_INTEGER := 181;
    c_timestamp_with_local_tz      CONSTANT PLS_INTEGER := 231;
    -- interval type identfiers
    c_interval_year_to_month       CONSTANT PLS_INTEGER := 182;
    c_interval_day_to_second       CONSTANT PLS_INTEGER := 183;
    -- cursor type identfiers
    c_ref                          CONSTANT PLS_INTEGER := 111;
    c_ref_cursor                   CONSTANT PLS_INTEGER := 102; -- same identfiers for strong and weak ref cursor

    PROCEDURE local_g_clob_append
      IS
    BEGIN
      l_buffer_varchar2   := replace(
        replace(
          replace(
            l_buffer_varchar2,
            c_cr,
            '\n'
          ),
          c_lf,
          '\n'
        ),
        c_crlf,
        '\n'
      );

      util_g_clob_append(
        CASE
          WHEN instr(
            nvl(
              l_buffer_varchar2,
              ' '
            ),
            p_delimiter
          ) = 0 THEN l_buffer_varchar2
          ELSE p_quote_mark || replace(
            l_buffer_varchar2,
            p_quote_mark,
            p_quote_mark || p_quote_mark
          ) || p_quote_mark
        END
      );

    END local_g_clob_append;

  BEGIN
    IF
      p_query IS NOT NULL
    THEN
      l_cursor   := dbms_sql.open_cursor;
      dbms_sql.parse(
        l_cursor,
        regexp_replace(
          p_query,
          ';\s*$',
          NULL
        ),
        dbms_sql.native
      );
      -- https://support.esri.com/en/technical-article/000010110
      -- http://bluefrog-oracle.blogspot.com/2011/11/describing-ref-cursor-using-dbmssql-api.html

      dbms_sql.describe_columns3(
        l_cursor,
        l_col_cnt,
        l_desc_tab
      );
      FOR i IN 1..l_col_cnt LOOP
        IF
          l_desc_tab(i).col_type IN (
            c_clob,
            c_xmltype
          )
        THEN
          dbms_sql.define_column(
            l_cursor,
            i,
            l_buffer_clob
          );
        ELSIF l_desc_tab(i).col_type = c_blob THEN
          dbms_sql.define_column(
            l_cursor,
            i,
            l_buffer_blob
          );
        ELSE
          dbms_sql.define_column(
            l_cursor,
            i,
            l_buffer_varchar2,
            32767
          );
        END IF;
      END LOOP;

      l_ignore   := dbms_sql.execute(l_cursor);
    
      -- create header
      util_g_clob_append(p_header_prefix);
      FOR i IN 1..l_col_cnt LOOP
        IF
          i > 1
        THEN
          util_g_clob_append(p_delimiter);
        END IF;
        l_buffer_varchar2   := l_desc_tab(i).col_name;
        local_g_clob_append;
      END LOOP;

      util_g_clob_append(p_line_terminator);
    
      -- create data
      LOOP
        EXIT WHEN dbms_sql.fetch_rows(l_cursor) = 0     OR l_data_count = p_max_rows;
        FOR i IN 1..l_col_cnt LOOP
          IF
            i > 1
          THEN
            util_g_clob_append(p_delimiter);
          END IF;
          --
          IF
            l_desc_tab(i).col_type IN (
              c_clob,
              c_xmltype
            )
          THEN
            dbms_sql.column_value(
              l_cursor,
              i,
              l_buffer_clob
            );
            IF
              length(l_buffer_clob) <= c_buffer_clob_varchar2_limit
            THEN
              l_buffer_varchar2   := substr(
                l_buffer_clob,
                1,
                c_buffer_clob_varchar2_limit
              );
              local_g_clob_append;
            ELSE
              l_buffer_varchar2   := 'CLOB value skipped - larger then ' || c_buffer_clob_varchar2_limit || ' characters';
              local_g_clob_append;
            END IF;

          ELSIF l_desc_tab(i).col_type = c_blob THEN
            dbms_sql.column_value(
              l_cursor,
              i,
              l_buffer_blob
            );
            l_buffer_varchar2   := 'BLOB value skipped - not supported for CSV';
            local_g_clob_append;
          ELSE
            dbms_sql.column_value(
              l_cursor,
              i,
              l_buffer_varchar2
            );
            local_g_clob_append;
          END IF;

        END LOOP;

        util_g_clob_append(p_line_terminator);
        l_data_count   := l_data_count + 1;
      END LOOP;

      dbms_sql.close_cursor(l_cursor);
    END IF;
  END util_g_clob_query_to_csv;

  FUNCTION util_ilog_get_runtime (
    p_start TIMESTAMP,
    p_stop TIMESTAMP
  ) RETURN NUMBER
    IS
  BEGIN
    RETURN SYSDATE + ( ( p_stop - p_start ) * 86400 ) - SYSDATE;
    --sysdate + (interval_difference * 86400) - sysdate
    --https://stackoverflow.com/questions/10092032/extracting-the-total-number-of-seconds-from-an-interval-data-type  
  END util_ilog_get_runtime;

  PROCEDURE util_ilog_init (
    p_module VARCHAR2,
    p_include_runtime_log BOOLEAN
  )
    IS
  BEGIN
    g_ilog          := NULL;
    g_ilog.module   := substr(
      p_module,
      1,
      c_length_application_info
    );
    IF
      p_include_runtime_log
    THEN
      g_ilog.enabled         := true;
      g_ilog.start_time      := systimestamp;
      g_ilog.measured_time   := 0;
    END IF;

  END util_ilog_init;

  PROCEDURE util_ilog_exit
    IS
  BEGIN
    IF
      g_ilog.enabled
    THEN
      g_ilog.stop_time         := systimestamp;
      g_ilog.run_time          := util_ilog_get_runtime(
        g_ilog.start_time,
        g_ilog.stop_time
      );
      g_ilog.unmeasured_time   := g_ilog.run_time - g_ilog.measured_time;
      g_ilog.enabled           := false;
    END IF;
  END util_ilog_exit;

  PROCEDURE util_ilog_start (
    p_action VARCHAR2
  ) IS
    l_index   PLS_INTEGER;
  BEGIN
    dbms_application_info.set_module(
      module_name   => g_ilog.module,
      action_name   => p_action
    );
    IF
      g_ilog.enabled
    THEN
      l_index                           := g_ilog.data.count + 1;
      g_ilog.data(l_index).action       := substr(
        p_action,
        1,
        plex.c_length_application_info
      );

      g_ilog.data(l_index).start_time   := systimestamp;
    END IF;

  END util_ilog_start;

  PROCEDURE util_ilog_append_action_text (
    p_text VARCHAR2
  ) IS
    l_index   PLS_INTEGER;
  BEGIN
    IF
      g_ilog.enabled
    THEN
      l_index                       := g_ilog.data.count;
      g_ilog.data(l_index).action   := substr(
        g_ilog.data(l_index).action || p_text,
        1,
        plex.c_length_application_info
      );

    END IF;
  END util_ilog_append_action_text;

  PROCEDURE util_ilog_stop IS
    l_index   PLS_INTEGER;
  BEGIN
    l_index   := g_ilog.data.count;
    dbms_application_info.set_module(
      module_name   => NULL,
      action_name   => NULL
    );
    IF
      g_ilog.enabled
    THEN
      g_ilog.data(l_index).stop_time   := systimestamp;
      g_ilog.data(l_index).elapsed     := util_ilog_get_runtime(
        g_ilog.start_time,
        g_ilog.data(l_index).stop_time
      );

      g_ilog.data(l_index).execution   := util_ilog_get_runtime(
        g_ilog.data(l_index).start_time,
        g_ilog.data(l_index).stop_time
      );

      g_ilog.measured_time             := g_ilog.measured_time + g_ilog.data(l_index).execution;
    END IF;

  END util_ilog_stop;

  PROCEDURE util_ilog_create_md_tab
    IS
  BEGIN
    util_g_clob_append('
| Step |   Elapsed |   Execution | Action                                                           |
|-----:|----------:|------------:|:-----------------------------------------------------------------|
'
);
    FOR i IN 1..g_ilog.data.count LOOP
      util_g_clob_append(util_multi_replace(
        '| #STEP# | #ELAPSED# | #EXECUTION# | #ACTION# |' || lf,
        '#STEP#',
        lpad(
          TO_CHAR(i),
          4
        ),
        '#ELAPSED#',
        lpad(
          trim(TO_CHAR(
            g_ilog.data(i).elapsed,
            '99990D000'
          ) ),
          9
        ),
        '#EXECUTION#',
        lpad(
          trim(TO_CHAR(
            g_ilog.data(i).execution,
            '9990D000000'
          ) ),
          11
        ),
        '#ACTION#',
        rpad(
          g_ilog.data(i).action,
          64
        )
      ) );
    END LOOP;

  END util_ilog_create_md_tab;

  FUNCTION backapp (
    p_app_id                    IN NUMBER DEFAULT NULL,
    p_app_date                  IN BOOLEAN DEFAULT true,
    p_app_public_reports        IN BOOLEAN DEFAULT true,
    p_app_private_reports       IN BOOLEAN DEFAULT false,
    p_app_notifications         IN BOOLEAN DEFAULT false,
    p_app_translations          IN BOOLEAN DEFAULT true,
    p_app_pkg_app_mapping       IN BOOLEAN DEFAULT false,
    p_app_original_ids          IN BOOLEAN DEFAULT true,
    p_app_subscriptions         IN BOOLEAN DEFAULT true,
    p_app_comments              IN BOOLEAN DEFAULT true,
    p_app_supporting_objects    IN VARCHAR2 DEFAULT NULL,
    p_include_object_ddl        IN BOOLEAN DEFAULT false,
    p_object_filter_regex       IN VARCHAR2 DEFAULT NULL,
    p_include_data              IN BOOLEAN DEFAULT false,
    p_data_as_of_minutes_ago    IN NUMBER DEFAULT 0,
    p_data_max_rows             IN NUMBER DEFAULT 1000,
    p_data_table_filter_regex   IN VARCHAR2 DEFAULT NULL,
    p_include_runtime_log       IN BOOLEAN DEFAULT true
  ) RETURN BLOB IS

    l_apex_version     NUMBER;
    l_data_timestamp   TIMESTAMP;
    l_data_scn         NUMBER;
    l_file_path        VARCHAR2(1000);
    l_zip              BLOB;
    l_current_user     user_objects.object_name%TYPE;
    l_app_workspace    user_objects.object_name%TYPE;
    l_app_owner        user_objects.object_name%TYPE;
    l_app_alias        user_objects.object_name%TYPE;
    -- 

    PROCEDURE get_apex_version
      IS
    BEGIN
      WITH t AS (
        SELECT substr(
          version_no,
          1,
          instr(
            version_no,
            '.',
            1,
            2
          ) - 1
        ) AS major_version,
               substr(
          version_no,
          instr(
            version_no,
            '.',
            1,
            2
          ) + 1
        ) AS minor_version
          FROM apex_release
      ) SELECT to_number(
        major_version || replace(
          minor_version,
          '.',
          NULL
        ),
        '999D999999999999',
        'NLS_NUMERIC_CHARACTERS=''.,'''
      )
        INTO l_apex_version
          FROM t;

    END get_apex_version;

    PROCEDURE check_owner IS
      CURSOR cur_owner IS SELECT workspace,
                                 owner,
                                 alias
                            FROM apex_applications t
                           WHERE t.application_id = p_app_id;

    BEGIN
      util_ilog_start('check_owner');
      l_current_user   := sys_context(
        'USERENV',
        'CURRENT_USER'
      );
      IF
        p_app_id IS NOT NULL
      THEN
        OPEN cur_owner;
        FETCH cur_owner   INTO
          l_app_workspace,
          l_app_owner,
          l_app_alias;
        CLOSE cur_owner;
      END IF;

      IF
        p_app_id IS NOT NULL    AND l_app_owner IS NULL
      THEN
        raise_application_error(
          -20101,
          'Could not find owner for application - are you sure you provided the right app_id?'
        );
      ELSIF p_app_id IS NOT NULL    AND l_app_owner != l_current_user THEN
        raise_application_error(
          -20102,
          'You are not the owner of the app - please login as the owner.'
        );
      END IF;

      util_ilog_stop;
    END check_owner;

    PROCEDURE process_apex_app IS
      l_files   apex_t_export_files;
    BEGIN
      util_ilog_start('app:export_application:single_file');
      l_files       := apex_export.get_application(
        p_application_id            => p_app_id,
        p_split                     => false,
        p_with_date                 => p_app_date,
        p_with_ir_public_reports    => p_app_public_reports,
        p_with_ir_private_reports   => p_app_private_reports,
        p_with_ir_notifications     => p_app_notifications,
        p_with_translations         => p_app_translations,
        p_with_pkg_app_mapping      => p_app_pkg_app_mapping,
        p_with_original_ids         => p_app_original_ids,
        p_with_no_subscriptions     =>
          CASE
            WHEN p_app_subscriptions THEN false
            ELSE true
          END,
        p_with_comments             => p_app_comments,
        p_with_supporting_objects   => p_app_supporting_objects
      );

      util_ilog_stop;

      -- save as single file 
      util_ilog_start('app:save_single_file');
      util_g_clob_createtemporary;
      util_g_clob_append(l_files(1).contents);
      l_file_path   := 'App/UI/' || l_files(1).name;
      apex_zip.add_file(
        p_zipped_blob   => l_zip,
        p_file_name     => l_file_path,
        p_content       => util_g_clob_to_blob
      );

      util_g_clob_freetemporary;
      l_files.DELETE;
      util_ilog_stop;

      -- save as individual files
      util_ilog_start('app:export_application:individual_files');
      l_files       := apex_export.get_application(
        p_application_id            => p_app_id,
        p_split                     => true,
        p_with_date                 => p_app_date,
        p_with_ir_public_reports    => p_app_public_reports,
        p_with_ir_private_reports   => p_app_private_reports,
        p_with_ir_notifications     => p_app_notifications,
        p_with_translations         => p_app_translations,
        p_with_pkg_app_mapping      => p_app_pkg_app_mapping,
        p_with_original_ids         => p_app_original_ids,
        p_with_no_subscriptions     =>
          CASE
            WHEN p_app_subscriptions THEN false
            ELSE true
          END,
        p_with_comments             => p_app_comments,
        p_with_supporting_objects   => p_app_supporting_objects
      );

      util_ilog_stop;
      FOR i IN 1..l_files.count LOOP
        l_file_path   := 'App/UI/' || l_files(i).name;
        util_ilog_start(l_file_path);
        util_g_clob_createtemporary;
        util_g_clob_append(l_files(i).contents);
        apex_zip.add_file(
          p_zipped_blob   => l_zip,
          p_file_name     => l_file_path,
          p_content       => util_g_clob_to_blob
        );

        util_g_clob_freetemporary;
        util_ilog_stop;
      END LOOP;

      l_files.DELETE;
    END process_apex_app;

    PROCEDURE create_frontend_install_files
      IS
    BEGIN
    
    -- file one
      l_file_path   := 'App/UI/f' || TO_CHAR(p_app_id) || '/install-script-frontend.dist.sql';
      util_ilog_start(l_file_path);
      util_g_clob_createtemporary;
      util_g_clob_append(util_multi_replace(
        '
set termout off define on verify off feedback off
whenever sqlerror exit sql.sqlcode rollback

column hn new_val host_name
column db new_val db_name
column dt new_val date_time
select sys_context(''userenv'', ''host'') hn,
       sys_context(''userenv'', ''db_name'') db, 
       to_char(sysdate, ''yyyymmdd-hh24miss'') dt
  from dual;
spool install-UI-&host_name.-&db_name.-&date_time..log
set termout on define off

prompt
prompt 
prompt 
prompt Start #APP_ALIAS# frontend installation
prompt ==================================================

prompt Setup environment
BEGIN
   apex_application_install.set_workspace_id( APEX_UTIL.find_security_group_id( ''#APP_WORKSPACE#'' ) );
   apex_application_install.set_application_alias( ''#APP_ALIAS#'' );
   apex_application_install.set_application_id( #APP_ID# );
   apex_application_install.set_schema( ''#APP_OWNER#'' );
   apex_application_install.generate_offset;
END;
/

prompt Call APEX install script
@install.sql

prompt ==================================================
prompt #APP_ALIAS# frontend installation DONE :-)
prompt
prompt 
prompt
'
,
        '#APP_ALIAS#',
        l_app_alias,
        '#APP_WORKSPACE#',
        l_app_workspace,
        '#APP_ID#',
        TO_CHAR(p_app_id),
        '#APP_OWNER#',
        l_app_owner
      ) );

      apex_zip.add_file(
        p_zipped_blob   => l_zip,
        p_file_name     => l_file_path,
        p_content       => util_g_clob_to_blob
      );

      util_g_clob_freetemporary;
      util_ilog_stop;
      
      -- file two
      l_file_path   := 'Scripts/deploy-UI-to-PROD.dist.bat';
      util_ilog_start(l_file_path);
      util_g_clob_createtemporary;
      util_g_clob_append(util_multi_replace(
        '
@echo off

rem If you want to use this script file you have to do some alignments:
rem 
rem - Copy this file to "deploy-UI-to-INT.bat" and "deploy-UI-to-PROD.bat" 
rem   without the `.dist` portion, modify it to your needs and replace all occurences 
rem   of "#SOME_TEXT#" with your specific configuration
rem - Do the same with the called script file "App\UI\f#APP_ID#\install-script-frontend.dist.sql"
rem - We do the directory changing here on the OS level, because SQL*plus can''t change 
rem   the directory when running scripts
rem - Feedback is welcome under https://github.com/ogobrecht/plex/issues/new
rem - Have fun :-)

setlocal
set areyousure = N

:PROMPT
set /p areyousure=Deploy UI of #APP_ALIAS# to #YOUR_COMMON_INT_OR_PROD_SYSTEM_DESCRIPTION# (Y/N)?
if /i %areyousure% neq y goto END

set NLS_LANG=AMERICAN_AMERICA.AL32UTF8
set /p password_db_user=Please enter password for #APP_OWNER# on #YOUR_COMMON_INT_OR_PROD_SYSTEM_DESCRIPTION#:
cd ..\App\UI\f#APP_ID#
echo exit | sqlplus -S #APP_OWNER#/%password_db_user%@#YOUR_HOST#:#YOUR_PORT#/#YOUR_SID# @install-script-frontend.sql
cd ..\..\..\Scripts

:END
pause
'
,
        '#APP_ID#',
        TO_CHAR(p_app_id),
        '#APP_ALIAS#',
        l_app_alias,
        '#APP_OWNER#',
        l_app_owner
      ) );

      apex_zip.add_file(
        p_zipped_blob   => l_zip,
        p_file_name     => l_file_path,
        p_content       => util_g_clob_to_blob
      );

      util_g_clob_freetemporary;
      util_ilog_stop;
      
      -- file three
      l_file_path   := 'Scripts/export_UI_from_DEV.dist.bat';
      util_ilog_start(l_file_path);
      util_g_clob_createtemporary;
      util_g_clob_append(util_multi_replace(
        '
@echo off

rem If you want to use this script file you have to do some alignments:
rem 
rem - Copy this file to "export_UI_from_DEV.bat" without the `.dist` portion, modify it to your
rem   needs and replace all occurences of "#SOME_TEXT#" with your specific configuration
rem - We do the directory changing here on the OS level, because SQL*plus can''t change 
rem   the directory when running scripts
rem - Feedback is welcome under https://github.com/ogobrecht/plex/issues/new
rem - Have fun :-)

rem Some blog posts regarding APEX export and Oracle instant client setup
rem http://www.oracle.com/webfolder/technetwork/de/community/apex/tipps/export-script/index.html
rem https://ruepprich.wordpress.com/2011/07/15/exporting-an-apex-application-via-command-line/
rem https://tedstruik-oracle.nl/ords/f?p=25384:1083
rem https://apexplained.wordpress.com/2013/11/25/apexexport-a-walkthrough/
rem https://apextips.blogspot.com/2017/12/windows-instant-client-setup.html

rem We use here the Oracle instant client and reference the needed Java classes from 
rem different places then described in the (german) blog article above (first link).
rem With this setup you are independend from any installation program - you need just to unzip
rem all the needed stuff - this results in a portable solution.

rem Storing the password in a batch file is a bad idea, especially when using version control...
set /p password_db_user=Please enter password for #APP_ALIAS# on DEV:
set NLS_LANG=AMERICAN_AMERICA.AL32UTF8

rem All instant client downloads are placed in one directory:
rem - Basic Light Package
rem - SQL*Plus Package
rem - Tools Package
rem - JDBC Supplement Package
rem - Downloads: http://www.oracle.com/technetwork/topics/winx64soft-089540.html
rem
rem The Oracle APEX install files are placed in a subdirectory named apex-5.1.4 (or newer):
rem - We need at least the subdirectory ../apex-5.1.4/utilities which contains relevant Java classes
rem - Use always the latest available APEX install file (at least the version you have installed)
rem - Downloads: http://www.oracle.com/technetwork/developer-tools/apex/downloads/index.html
rem
rem The resulting directory structure under oracle-instant-client-12.2 looks like this:
rem
rem - apex-5.1.4
rem   - builder
rem   - core
rem   - images
rem   - utilities
rem     - debug
rem     - oracle
rem       - apex
rem         - APEXExport.class          # Relevant Java classes
rem         - APEXExportSplitter.class  # DEPRECATED
rem     - support
rem     - templates
rem     - ...
rem     - readme.txt                    # Useful informations for the splitter
rem     - ...
rem - network
rem - sdk
rem - vc14
rem - ...
rem - ojdbc8.jar                        # JDBC driver for the connection
rem - ...
rem
rem We set finally the ORACLE_HOME path to our download instant client directory 
set ORACLE_HOME=C:\og\Apps\oracle-instant-client-12.2

rem For the Java runtime we reusing here the SQL Developer integrated JDK, you can use whatever you like...
set JAVA_HOME=C:\og\Apps\sqldeveloper\jdk\jre\bin

rem Setup needed Java classes
set CLASSPATH=%ORACLE_HOME%\ojdbc8.jar;%ORACLE_HOME%\apex-5.1.4\utilities;.

rem Change current directory to store the export file there
cd ..\App\UI

rem Export the application as one single file
"%JAVA_HOME%\java.exe" oracle.apex.APEXExport ^
  -db #YOUR_HOST#:#YOUR_PORT#/#YOUR_SID# ^
  -user #APP_OWNER# ^
  -password %password_db_user% ^
  -applicationid #APP_ID# ^
  -expPubReports ^
  -expTranslations

rem Splitting an existing export file into individual files (the subdirectory f#APP_ID# is created by the splitter):
rem - DEPRECATED since APEX 5.1.4
rem - Use instead the option -split (see command below)
"%JAVA_HOME%\java.exe" oracle.apex.APEXExportSplitter f#APP_ID#.sql

rem Export the application directly as individual files:
rem - Has an error in APEX 5.1.4: The file ./f#APP_ID#/application/create_application.sql is not generated :-(
rem "%JAVA_HOME%\java.exe" oracle.apex.APEXExport 
rem   -db #YOUR_HOST#:#YOUR_PORT#/#YOUR_SID# ^
rem   -user #APP_OWNER# ^
rem   -password %password_db_user% ^
rem   -applicationid #APP_ID# ^
rem   -expPubReports ^
rem   -expTranslations ^
rem   -split

rem Change current directory back to Scripts
cd ..\..\Scripts

pause
'
,
        '#APP_ID#',
        TO_CHAR(p_app_id),
        '#APP_ALIAS#',
        l_app_alias,
        '#APP_OWNER#',
        l_app_owner
      ) );

      apex_zip.add_file(
        p_zipped_blob   => l_zip,
        p_file_name     => l_file_path,
        p_content       => util_g_clob_to_blob
      );

      util_g_clob_freetemporary;
      util_ilog_stop;
    END create_frontend_install_files;

    PROCEDURE process_user_ddl IS
      exception_occured   BOOLEAN := false;
    BEGIN
      -- user itself
      BEGIN
        l_file_path   := 'App/DDL/_User/' || l_current_user || '.sql';
        util_ilog_start(l_file_path);
        util_g_clob_createtemporary;
        util_g_clob_append(replace(
          '
BEGIN 
  FOR i IN (SELECT ''#CURRENT_USER#'' AS username FROM dual MINUS SELECT username FROM dba_users) LOOP
    EXECUTE IMMEDIATE q''[
--------------------------------------------------------------------------------
'
,
          '#CURRENT_USER#',
          l_current_user
        ) );
        BEGIN
          util_g_clob_append(dbms_metadata.get_ddl(
            'USER',
            l_current_user
          ) );
        EXCEPTION
          WHEN OTHERS THEN
            exception_occured   := true;
            util_ilog_append_action_text(' ' || sqlerrm);
            util_g_clob_append(sqlerrm);
        END;

        util_g_clob_append('
--------------------------------------------------------------------------------
    ]'';
  END LOOP;
END;
/
'
);
        apex_zip.add_file(
          p_zipped_blob   => l_zip,
          p_file_name     => l_file_path,
          p_content       => util_g_clob_to_blob
        );

        util_g_clob_freetemporary;
        util_ilog_stop;
      END;

      -- roles

      BEGIN
        l_file_path   := 'App/DDL/_User/' || l_current_user || '_roles.sql';
        util_ilog_start(l_file_path);
        util_g_clob_createtemporary;
        FOR i IN (
     -- ensure we get no dbms_metadata error when no role privs exists
          SELECT DISTINCT username
            FROM user_role_privs
        ) LOOP
          BEGIN
            util_g_clob_append(dbms_metadata.get_granted_ddl(
              'ROLE_GRANT',
              l_current_user
            ) );
          EXCEPTION
            WHEN OTHERS THEN
              exception_occured   := true;
              util_ilog_append_action_text(' ' || sqlerrm);
              util_g_clob_append(sqlerrm);
          END;
        END LOOP;

        apex_zip.add_file(
          p_zipped_blob   => l_zip,
          p_file_name     => l_file_path,
          p_content       => util_g_clob_to_blob
        );

        util_g_clob_freetemporary;
        util_ilog_stop;
      END;

      -- system privileges

      BEGIN
        l_file_path   := 'App/DDL/_User/' || l_current_user || '_system_privileges.sql';
        util_ilog_start(l_file_path);
        util_g_clob_createtemporary;
        FOR i IN (
     -- ensure we get no dbms_metadata error when no sys privs exists
          SELECT DISTINCT username
            FROM user_sys_privs
        ) LOOP
          BEGIN
            util_g_clob_append(dbms_metadata.get_granted_ddl(
              'SYSTEM_GRANT',
              l_current_user
            ) );
          EXCEPTION
            WHEN OTHERS THEN
              exception_occured   := true;
              util_ilog_append_action_text(' ' || sqlerrm);
              util_g_clob_append(sqlerrm);
          END;
        END LOOP;

        apex_zip.add_file(
          p_zipped_blob   => l_zip,
          p_file_name     => l_file_path,
          p_content       => util_g_clob_to_blob
        );

        util_g_clob_freetemporary;
        util_ilog_stop;
      END;

      -- object privileges

      BEGIN
        l_file_path   := 'App/DDL/_User/' || l_current_user || '_object_privileges.sql';
        util_ilog_start(l_file_path);
        util_g_clob_createtemporary;
        FOR i IN (
     -- ensure we get no dbms_metadata error when no object grants exists
          SELECT DISTINCT grantee
            FROM user_tab_privs
           WHERE grantee = l_current_user
        ) LOOP
          BEGIN
            util_g_clob_append(dbms_metadata.get_granted_ddl(
              'OBJECT_GRANT',
              l_current_user
            ) );
          EXCEPTION
            WHEN OTHERS THEN
              exception_occured   := true;
              util_ilog_append_action_text(' ' || sqlerrm);
              util_g_clob_append(sqlerrm);
          END;
        END LOOP;

        apex_zip.add_file(
          p_zipped_blob   => l_zip,
          p_file_name     => l_file_path,
          p_content       => util_g_clob_to_blob
        );

        util_g_clob_freetemporary;
        util_ilog_stop;
      END;

      IF
        exception_occured
      THEN
        l_file_path   := 'App/DDL/_User/_ERROR_on_DDL_creation_occured.md';
        util_ilog_start(l_file_path);
        util_g_clob_createtemporary;
        util_g_clob_append('
ERRORS on User DDL Creation
===========================

There were errors during the creation of one or more user DDL files. This 
could happen without sufficient rights. Normally these files are created:

- USERNAME.sql
- USERNAME_roles.sql
- USERNAME_system_privileges.sql
- USERNAME_object_privileges.sql

Please have a look in these files and check for errors.

'
);
        apex_zip.add_file(
          p_zipped_blob   => l_zip,
          p_file_name     => l_file_path,
          p_content       => util_g_clob_to_blob
        );

        util_g_clob_freetemporary;
        util_ilog_stop;
      END IF;

    END process_user_ddl;

    PROCEDURE process_object_ddl IS

      l_ddl_file         CLOB;
      l_file_path_body   VARCHAR2(1000 CHAR);
      l_pattern          VARCHAR2(100);
      l_position         PLS_INTEGER;
      CURSOR l_cur IS SELECT
        CASE
     --https://stackoverflow.com/questions/3235300/oracles-dbms-metadata-get-ddl-for-object-type-job
          WHEN object_type IN (
            'JOB',
            'PROGRAM',
            'SCHEDULE'
          ) THEN 'PROCOBJ'
          ELSE object_type
        END
      AS object_type,
        object_name,
        'App/DDL/' || replace(
        initcap(
          CASE
            WHEN object_type LIKE '%S' THEN object_type || 'ES'
            WHEN object_type LIKE '%EX' THEN regexp_replace(
              object_type,
              'EX$',
              'ICES',
              1,
              0,
              'i'
            )
            WHEN object_type LIKE '%Y' THEN regexp_replace(
              object_type,
              'Y$',
              'IES',
              1,
              0,
              'i'
            )
            ELSE object_type || 'S'
          END
        ),
        ' ',
        NULL
      ) || '/' || object_name ||
        CASE object_type
          WHEN 'PACKAGE'     THEN '.pks'
          WHEN 'FUNCTION'    THEN '.fnc'
          WHEN 'PROCEDURE'   THEN '.prc'
          WHEN 'TRIGGER'     THEN '.trg'
          WHEN 'TYPE'        THEN '.typ'
          ELSE '.sql'
        END
      AS file_path
                        FROM user_objects
                       WHERE object_type NOT IN (
        'TABLE PARTITION',
        'PACKAGE BODY',
        'TYPE BODY',
        'LOB'
      )
         AND object_name NOT LIKE 'SYS_PLSQL%'
         AND object_name NOT LIKE 'SYS_IL%$$'
         AND object_name NOT LIKE 'SYS_C%'
         AND object_name NOT LIKE 'ISEQ$$%'
         AND REGEXP_LIKE ( object_name,
                           nvl(
        p_object_filter_regex,
        '.*'
      ),
                           'i' )
       ORDER BY object_type,
                object_name;

      l_rec              l_cur%rowtype;
    BEGIN
      util_setup_dbms_metadata;
      dbms_lob.createtemporary(
        l_ddl_file,
        true
      );
      util_ilog_start('ddl:open_objects_cursor');
      OPEN l_cur;
      util_ilog_stop;
      LOOP
        FETCH l_cur   INTO l_rec;
        EXIT WHEN l_cur%notfound;
        util_ilog_start(l_rec.file_path);
        CASE
          l_rec.object_type
          WHEN 'SEQUENCE' THEN
            g_ddl_files.sequences_(g_ddl_files.sequences_.count + 1) := l_rec.file_path;
          WHEN 'TABLE' THEN
            g_ddl_files.tables_(g_ddl_files.tables_.count + 1) := l_rec.file_path;
          WHEN 'INDEX' THEN
            g_ddl_files.indices_(g_ddl_files.indices_.count + 1) := l_rec.file_path;
          WHEN 'VIEW' THEN
            g_ddl_files.views_(g_ddl_files.views_.count + 1) := l_rec.file_path;
          WHEN 'TYPE' THEN
            g_ddl_files.types_(g_ddl_files.types_.count + 1) := l_rec.file_path;
          WHEN 'TRIGGER' THEN
            g_ddl_files.triggers_(g_ddl_files.triggers_.count + 1) := l_rec.file_path;
          WHEN 'FUNCTION' THEN
            g_ddl_files.functions_(g_ddl_files.functions_.count + 1) := l_rec.file_path;
          WHEN 'PROCEDURE' THEN
            g_ddl_files.procedures_(g_ddl_files.procedures_.count + 1) := l_rec.file_path;
          WHEN 'PACKAGE' THEN
            g_ddl_files.packages_(g_ddl_files.packages_.count + 1) := l_rec.file_path;
          ELSE
            g_ddl_files.other_objects_(g_ddl_files.other_objects_.count + 1) := l_rec.file_path;
        END CASE;

        CASE
          WHEN l_rec.object_type IN (
            'PACKAGE',
            'TYPE'
          ) THEN
            l_ddl_file   := dbms_metadata.get_ddl(
              object_type   => l_rec.object_type,
              name          => l_rec.object_name,
              schema        => l_current_user
            );

            l_pattern    := 'CREATE OR REPLACE( EDITIONABLE)? (PACKAGE|TYPE) BODY';
            l_position   := regexp_instr(
              l_ddl_file,
              l_pattern
            );
            -- SPEC
            util_g_clob_createtemporary;
            util_g_clob_append(ltrim(
              CASE
                WHEN l_position = 0 THEN l_ddl_file
                ELSE substr(
                  l_ddl_file,
                  1,
                  l_position - 1
                )
              END,
              ' ' || lf
            ) );

            apex_zip.add_file(
              p_zipped_blob   => l_zip,
              p_file_name     => l_rec.file_path,
              p_content       => util_g_clob_to_blob
            );

            util_g_clob_freetemporary;
            
            -- BODY - only when existing
            IF
              l_position > 0
            THEN
              l_file_path_body   := util_multi_replace(
                p_source_string   => l_rec.file_path,
                p_1_find          => '/Packages/',
                p_1_replace       => '/PackageBodies/',
                p_2_find          => '.pks',
                p_2_replace       => '.pkb',
                p_3_find          => '/Types/',
                p_3_replace       => '/TypeBodies/'
              );

              CASE
                l_rec.object_type
                WHEN 'TYPE' THEN
                  g_ddl_files.type_bodies_(g_ddl_files.type_bodies_.count + 1) := l_file_path_body;
                WHEN 'PACKAGE' THEN
                  g_ddl_files.package_bodies_(g_ddl_files.package_bodies_.count + 1) := l_file_path_body;
              END CASE;

              util_g_clob_createtemporary;
              util_g_clob_append(substr(
                l_ddl_file,
                l_position
              ) );
              apex_zip.add_file(
                p_zipped_blob   => l_zip,
                p_file_name     => l_file_path_body,
                p_content       => util_g_clob_to_blob
              );

              util_g_clob_freetemporary;
            END IF;

          WHEN l_rec.object_type = 'VIEW' THEN
            util_g_clob_createtemporary;
            util_g_clob_append(ltrim(
              regexp_replace(
                regexp_replace(
                  dbms_metadata.get_ddl(
                    object_type   => l_rec.object_type,
                    name          => l_rec.object_name,
                    schema        => l_current_user
                  ),
                  '\(.*\) ',
     -- remove additional column list from the compiler
                  NULL,
                  1,
                  1
                ),
                '^\s*SELECT',
     -- remove additional whitespace from the compiler
                'SELECT',
                1,
                1,
                'im'
              ),
              ' ' || lf
            ) );

            apex_zip.add_file(
              p_zipped_blob   => l_zip,
              p_file_name     => l_rec.file_path,
              p_content       => util_g_clob_to_blob
            );

            util_g_clob_freetemporary;
          WHEN l_rec.object_type IN (
            'TABLE',
            'INDEX',
            'SEQUENCE'
          ) THEN
            util_g_clob_createtemporary;
            util_setup_dbms_metadata(p_sqlterminator   => false);
            util_g_clob_append(replace(
              '
BEGIN
  FOR i IN (SELECT ''#OBJECT_NAME#'' AS object_name FROM dual 
            MINUS
            SELECT object_name FROM user_objects) LOOP
    EXECUTE IMMEDIATE q''[
--------------------------------------------------------------------------------
'
,
              '#OBJECT_NAME#',
              l_rec.object_name
            ) );
            util_g_clob_append(dbms_metadata.get_ddl(
              object_type   => l_rec.object_type,
              name          => l_rec.object_name,
              schema        => l_current_user
            ) );

            util_g_clob_append('
--------------------------------------------------------------------------------
    ]'';
  END LOOP;
END;
/

-- Put your ALTER statements below in the same style as before to ensure that
-- the script is restartable.
'
);
            util_setup_dbms_metadata(p_sqlterminator   => true);
            apex_zip.add_file(
              p_zipped_blob   => l_zip,
              p_file_name     => l_rec.file_path,
              p_content       => util_g_clob_to_blob
            );

            util_g_clob_freetemporary;
          ELSE
            util_g_clob_createtemporary;
            util_g_clob_append(dbms_metadata.get_ddl(
              object_type   => l_rec.object_type,
              name          => l_rec.object_name,
              schema        => l_current_user
            ) );

            apex_zip.add_file(
              p_zipped_blob   => l_zip,
              p_file_name     => l_rec.file_path,
              p_content       => util_g_clob_to_blob
            );

            util_g_clob_freetemporary;
        END CASE;

        util_ilog_stop;
      END LOOP;

      CLOSE l_cur;
      dbms_lob.freetemporary(l_ddl_file);
    END process_object_ddl;

    PROCEDURE process_object_grants IS

      CURSOR l_cur IS SELECT DISTINCT p.grantor,
                                      p.privilege,
                                      p.table_name AS object_name,
                                      'App/DDL/Grants/' || p.privilege || '_on_' || p.table_name || '.sql' AS file_path
                        FROM user_tab_privs p
        JOIN user_objects o ON p.table_name = o.object_name
                       WHERE REGEXP_LIKE ( o.object_name,
                                           nvl(
        p_object_filter_regex,
        '.*'
      ),
                                           'i' )
       ORDER BY privilege,
                object_name;

      l_rec   l_cur%rowtype;
    BEGIN
      util_ilog_start('ddl:grants:open_cursor');
      OPEN l_cur;
      util_ilog_stop;
      LOOP
        FETCH l_cur   INTO l_rec;
        EXIT WHEN l_cur%notfound;
        util_ilog_start(l_rec.file_path);
        util_g_clob_createtemporary;
        util_g_clob_append(dbms_metadata.get_dependent_ddl(
          'OBJECT_GRANT',
          l_rec.object_name,
          l_rec.grantor
        ) );
        g_ddl_files.grants_(g_ddl_files.grants_.count + 1) := l_rec.file_path;
        apex_zip.add_file(
          p_zipped_blob   => l_zip,
          p_file_name     => l_rec.file_path,
          p_content       => util_g_clob_to_blob
        );

        util_g_clob_freetemporary;
        util_ilog_stop;
      END LOOP;

      CLOSE l_cur;
    END process_object_grants;

    PROCEDURE process_ref_constraints IS

      CURSOR l_cur IS SELECT table_name,
                             constraint_name,
                             'App/DDL/TabRefConstraints/' || constraint_name || '.sql' AS file_path
                        FROM user_constraints
                       WHERE constraint_type = 'R'
         AND REGEXP_LIKE ( table_name,
                           nvl(
        p_object_filter_regex,
        '.*'
      ),
                           'i' )
       ORDER BY table_name,
                constraint_name;

      l_rec   l_cur%rowtype;
    BEGIN
      util_ilog_start('ddl:ref_constraints:open_cursor');
      OPEN l_cur;
      util_ilog_stop;
      LOOP
        FETCH l_cur   INTO l_rec;
        EXIT WHEN l_cur%notfound;
        util_ilog_start(l_rec.file_path);
        util_g_clob_createtemporary;
        util_setup_dbms_metadata(p_sqlterminator   => false);
        util_g_clob_append(replace(
          '
BEGIN
  FOR i IN (SELECT ''#CONSTRAINT_NAME#'' AS constraint_name FROM dual
            MINUS
            SELECT constraint_name FROM user_constraints) LOOP
    EXECUTE IMMEDIATE q''[
--------------------------------------------------------------------------------
'
,
          '#CONSTRAINT_NAME#',
          l_rec.constraint_name
        ) );
        util_g_clob_append(dbms_metadata.get_ddl(
          'REF_CONSTRAINT',
          l_rec.constraint_name
        ) );
        util_g_clob_append('
--------------------------------------------------------------------------------
    ]'';
  END LOOP;
END;
/
'
);
        util_setup_dbms_metadata(p_sqlterminator   => true);
        g_ddl_files.ref_constraints_(g_ddl_files.ref_constraints_.count + 1) := l_rec.file_path;
        apex_zip.add_file(
          p_zipped_blob   => l_zip,
          p_file_name     => l_rec.file_path,
          p_content       => util_g_clob_to_blob
        );

        util_g_clob_freetemporary;
        util_ilog_stop;
      END LOOP;

      CLOSE l_cur;
    END process_ref_constraints;

    PROCEDURE create_backend_install_files IS

      FUNCTION get_script_line (
        p_file_path VARCHAR2
      ) RETURN VARCHAR2
        IS
      BEGIN
        RETURN 'prompt --' || p_file_path || lf || '@' || replace(
          p_file_path,
          'App/DDL/',
          NULL
        ) || lf || lf;
      END get_script_line;

    BEGIN
    
    -- file one
      l_file_path   := 'App/DDL/install.sql';
      util_ilog_start(l_file_path);
      util_g_clob_createtemporary;
      util_g_clob_append('set define off verify off feedback off' || lf || 'whenever sqlerror exit sql.sqlcode rollback' || lf || lf);
      FOR i IN 1..g_ddl_files.sequences_.count LOOP
        util_g_clob_append(get_script_line(g_ddl_files.sequences_(i) ) );
      END LOOP;

      FOR i IN 1..g_ddl_files.tables_.count LOOP
        util_g_clob_append(get_script_line(g_ddl_files.tables_(i) ) );
      END LOOP;

      FOR i IN 1..g_ddl_files.ref_constraints_.count LOOP
        util_g_clob_append(get_script_line(g_ddl_files.ref_constraints_(i) ) );
      END LOOP;

      FOR i IN 1..g_ddl_files.indices_.count LOOP
        util_g_clob_append(get_script_line(g_ddl_files.indices_(i) ) );
      END LOOP;

      FOR i IN 1..g_ddl_files.views_.count LOOP
        util_g_clob_append(get_script_line(g_ddl_files.views_(i) ) );
      END LOOP;

      FOR i IN 1..g_ddl_files.types_.count LOOP
        util_g_clob_append(get_script_line(g_ddl_files.types_(i) ) );
      END LOOP;

      FOR i IN 1..g_ddl_files.type_bodies_.count LOOP
        util_g_clob_append(get_script_line(g_ddl_files.type_bodies_(i) ) );
      END LOOP;

      FOR i IN 1..g_ddl_files.triggers_.count LOOP
        util_g_clob_append(get_script_line(g_ddl_files.triggers_(i) ) );
      END LOOP;

      FOR i IN 1..g_ddl_files.functions_.count LOOP
        util_g_clob_append(get_script_line(g_ddl_files.functions_(i) ) );
      END LOOP;

      FOR i IN 1..g_ddl_files.procedures_.count LOOP
        util_g_clob_append(get_script_line(g_ddl_files.procedures_(i) ) );
      END LOOP;

      FOR i IN 1..g_ddl_files.packages_.count LOOP
        util_g_clob_append(get_script_line(g_ddl_files.packages_(i) ) );
      END LOOP;

      FOR i IN 1..g_ddl_files.package_bodies_.count LOOP
        util_g_clob_append(get_script_line(g_ddl_files.package_bodies_(i) ) );
      END LOOP;

      FOR i IN 1..g_ddl_files.grants_.count LOOP
        util_g_clob_append(get_script_line(g_ddl_files.grants_(i) ) );
      END LOOP;

      FOR i IN 1..g_ddl_files.other_objects_.count LOOP
        util_g_clob_append(get_script_line(g_ddl_files.other_objects_(i) ) );
      END LOOP;

      apex_zip.add_file(
        p_zipped_blob   => l_zip,
        p_file_name     => l_file_path,
        p_content       => util_g_clob_to_blob
      );

      util_g_clob_freetemporary;
      util_ilog_stop;    
       
    -- file two
      l_file_path   := 'App/DDL/install-script-backend.dist.sql';
      util_ilog_start(l_file_path);
      util_g_clob_createtemporary;
      util_g_clob_append(util_multi_replace(
        '
set termout off define on verify off feedback off
whenever sqlerror exit sql.sqlcode rollback

column hn new_val host_name
column db new_val db_name
column dt new_val date_time
select sys_context(''userenv'', ''host'') hn,
       sys_context(''userenv'', ''db_name'') db, 
       to_char(sysdate, ''yyyymmdd-hh24miss'') dt
  from dual;
spool install-BACKEND-&host_name.-&db_name.-&date_time..log
set termout on define off

prompt
prompt 
prompt 
prompt Start #APP_ALIAS# backend installation
prompt ==================================================

prompt Call DDL install script
@install.sql

prompt compile invalid objects
BEGIN
  dbms_utility.compile_schema(
    schema           => user,
    compile_all      => false,
    reuse_settings   => true
  );
END;
/

prompt check invalid objects
DECLARE
  v_count   PLS_INTEGER;
  v_objects VARCHAR2(4000);
BEGIN
  SELECT COUNT(*),
         listagg(object_name,
                 '', '') within GROUP(ORDER BY object_name)
    INTO v_count,
         v_objects
    FROM user_objects
   WHERE status = ''INVALID'';
  IF v_count > 0
  THEN
    raise_application_error(-20000,
                            ''Found '' || v_count || '' invalid object'' || CASE
                              WHEN v_count > 1 THEN
                               ''s''
                            END || '' :-( '' || v_objects);
  END IF;
END;
/

prompt ==================================================
prompt #APP_ALIAS# backend installation DONE :-)
prompt
prompt 
prompt
'
,
        '#APP_ALIAS#',
        l_app_alias
      ) );
      apex_zip.add_file(
        p_zipped_blob   => l_zip,
        p_file_name     => l_file_path,
        p_content       => util_g_clob_to_blob
      );

      util_g_clob_freetemporary;
      util_ilog_stop;
      
      -- file three
      l_file_path   := 'Scripts/deploy-BACKEND-to-PROD.dist.bat';
      util_ilog_start(l_file_path);
      util_g_clob_createtemporary;
      util_g_clob_append(util_multi_replace(
        '
@echo off

rem If you want to use this script file you have to do some alignments:
rem 
rem - Copy this file to "deploy-BACKEND-to-INT.bat" and "deploy-BACKEND-to-PROD.bat" 
rem   without the `.dist` portion, modify it to your needs and replace all occurences 
rem   of "#SOME_TEXT#" with your specific configuration
rem - Do the same with the called script file "App\DDL\install-script-backend.dist.sql"
rem - We do the directory changing here on the OS level, because SQL*plus can''t change 
rem   the directory when running scripts
rem - Feedback is welcome under https://github.com/ogobrecht/plex/issues/new
rem - Have fun :-)

setlocal
set areyousure = N

:PROMPT
set /p areyousure=Deploy BACKEND of #APP_ALIAS# to #YOUR_COMMON_INT_OR_PROD_SYSTEM_DESCRIPTION# (Y/N)?
if /i %areyousure% neq y goto END

set NLS_LANG=AMERICAN_AMERICA.AL32UTF8
set /p password_db_user=Please enter password for #APP_OWNER# on #YOUR_COMMON_INT_OR_PROD_SYSTEM_DESCRIPTION#:
cd ..\App\DDL
echo exit | sqlplus -S #APP_OWNER#/%password_db_user%@#YOUR_HOST#:#YOUR_PORT#/#YOUR_SID# @install-script-backend.sql
cd ..\..\Scripts

:END
pause
'
,
        '#APP_ID#',
        TO_CHAR(p_app_id),
        '#APP_ALIAS#',
        l_app_alias,
        '#APP_OWNER#',
        l_app_owner
      ) );

      apex_zip.add_file(
        p_zipped_blob   => l_zip,
        p_file_name     => l_file_path,
        p_content       => util_g_clob_to_blob
      );

      util_g_clob_freetemporary;
      util_ilog_stop;
    END create_backend_install_files;

    PROCEDURE process_data IS

      CURSOR l_cur IS SELECT table_name,
                             (
        SELECT
          LISTAGG(column_name,
                    ', ') WITHIN  GROUP(
             ORDER BY position
          )
          FROM user_cons_columns
         WHERE constraint_name = (
          SELECT constraint_name
            FROM user_constraints c
           WHERE constraint_type = 'P'
             AND c.table_name = t.table_name
        )
      ) AS pk_columns
                        FROM user_tables t
                       WHERE table_name IN (
        SELECT table_name
          FROM user_tables
        MINUS
        SELECT table_name
          FROM user_external_tables
      )
         AND REGEXP_LIKE ( table_name,
                           nvl(
        p_data_table_filter_regex,
        '.*'
      ),
                           'i' )
       ORDER BY table_name;

      l_rec   l_cur%rowtype;
    BEGIN
      util_ilog_start('data:open_tables_cursor');
      OPEN l_cur;
      util_ilog_stop;
      util_ilog_start('data:get_scn');
      l_data_timestamp   := util_calc_data_timestamp(nvl(
        p_data_as_of_minutes_ago,
        0
      ) );
      l_data_scn         := timestamp_to_scn(l_data_timestamp);
      util_ilog_stop;
      LOOP
        FETCH l_cur   INTO l_rec;
        EXIT WHEN l_cur%notfound;
        l_file_path   := 'App/Data/' || l_rec.table_name || '.csv';
        util_ilog_start(l_file_path);
        util_g_clob_createtemporary;
        util_g_clob_query_to_csv(
          p_query      => 'SELECT * FROM ' || l_rec.table_name || ' AS OF SCN ' || l_data_scn || CASE
            WHEN l_rec.pk_columns IS NOT NULL THEN ' ORDER BY ' || l_rec.pk_columns
            ELSE NULL
          END,
          p_max_rows   => p_data_max_rows
        );

        apex_zip.add_file(
          p_zipped_blob   => l_zip,
          p_file_name     => l_file_path,
          p_content       => util_g_clob_to_blob
        );

        util_g_clob_freetemporary;
        util_ilog_stop;
      END LOOP;

      CLOSE l_cur;
    END process_data;

    PROCEDURE create_supporting_files IS

      l_the_point   VARCHAR2(30) := '. < this is the point ;-)';

      PROCEDURE create_file (
        p_path VARCHAR2,
        p_content VARCHAR2
      )
        IS
      BEGIN
        util_ilog_start(p_path);
        util_g_clob_createtemporary;
        util_g_clob_append(p_content);
        apex_zip.add_file(
          p_zipped_blob   => l_zip,
          p_file_name     => p_path,
          p_content       => util_g_clob_to_blob
        );

        util_g_clob_freetemporary;
        util_ilog_stop;
      END create_file;

      PROCEDURE create_readme_dist
        IS
      BEGIN
        create_file(
          p_path      => 'README.dist.md',
          p_content   => util_multi_replace(
            '
Your Global README File
=======================
      
It is a good practice to have a README file in the root of your project with
a high level overview of your application. Put the more detailed docs in the 
Docs folder.

You can start with a copy of this file. Name it README.md and try to use 
Markdown when writing your content - this has many benefits and you don''t
waist time by formatting your docs. If you are unsure have a look at some 
projects at [Github](https://github.com) or any other code hosting platform.

Have also a look at the provided deploy scripts - these could be a starting
point for you to do some basic scripting. If you have already some sort of
CI/CD up and running then ignore simply the files. Depending on your options
when calling `plex.backapp` these files are generated for you:

- App/DDL/install-script-backend.dist.sql
- App/UI/f#APP_ID#/install-script-frontend.dist.sql
- Scripts/deploy-BACKEND-to-PROD.dist.bat
- Scripts/deploy-UI-to-PROD.dist.bat
- Scripts/export_UI_from_DEV.dist.bat

If you want to use these files please make a copy of it without the `.dist`
portion and modify it to your needs. Doing it this way your changes are 
overwrite save.

[Feedback is welcome](#PLEX_URL#/issues/new)
'
,
            '#APP_ID#',
              CASE
                WHEN p_app_id IS NOT NULL THEN TO_CHAR(p_app_id)
                ELSE 'YourAppID'
              END,
            '#PLEX_URL#',
            c_plex_url
          )
        );
      END create_readme_dist;

    BEGIN
      create_file(
        'Docs/_save_your_docs_here',
        l_the_point
      );
      create_file(
        'Scripts/_save_your_scripts_here',
        l_the_point
      );
      create_file(
        'Tests/_save_your_tests_here',
        l_the_point
      );
      create_readme_dist;
    END create_supporting_files;

    PROCEDURE create_runtime_log
      IS
    BEGIN
      util_g_clob_createtemporary;
      util_g_clob_append(util_multi_replace(
        '
PLEX - BackApp - Runtime Log
============================

Export started at #START_TIME# and took #RUN_TIME# seconds to finish.
#DATA_EXTRACTION#

Parameters
----------

- The used plex version was #PLEX_VERSION#
- More infos here: [PLEX on GitHub](#PLEX_URL#)

```sql
DECLARE
  zip BLOB;
BEGIN
  zip := plex.backapp(
    p_app_id                   => #P_APP_ID#,
    p_app_date                 => #P_APP_DATE#,
    p_app_public_reports       => #P_APP_PUBLIC_REPORTS#,
    p_app_private_reports      => #P_APP_PRIVATE_REPORTS#,
    p_app_notifications        => #P_APP_NOTIFICATIONS#,
    p_app_translations         => #P_APP_TRANSLATIONS#,
    p_app_pkg_app_mapping      => #P_APP_PKG_APP_MAPPING#,
    p_app_original_ids         => #P_APP_ORIGINAL_IDS#,
    p_app_subscriptions        => #P_APP_SUBSCRIPTIONS#,
    p_app_comments             => #P_APP_COMMENTS#,
    p_app_supporting_objects   => #P_APP_SUPPORTING_OBJECTS#,
    --
    p_include_object_ddl       => #P_INCLUDE_OBJECT_DDL#,
    p_object_filter_regex      => #P_OBJECT_FILTER_REGEX#,
    --
    p_include_data             => #P_INCLUDE_DATA#,
    p_data_as_of_minutes_ago   => #P_DATA_AS_OF_MINUTES_AGO#,
    p_data_max_rows            => #P_DATA_MAX_ROWS#,
    p_data_table_filter_regex  => #P_DATA_TABLE_FILTER_REGEX#
    --
    p_include_runtime_log      => #P_INCLUDE_RUNTIME_LOG#
  );
END;
```

Log Entries
-----------

Unmeasured execution time because of system waits, missing log calls or log
overhead was #UNMEASURED_TIME# seconds.
'
,
        '#START_TIME#',
        TO_CHAR(
          g_ilog.start_time,
          'yyyy-mm-dd hh24:mi:ss'
        ),
        '#RUN_TIME#',
        trim(TO_CHAR(
          g_ilog.run_time,
          '999G990D000'
        ) ),
        '#DATA_EXTRACTION#',
          CASE
            WHEN p_include_data THEN lf || 'Data extraction started at ' || TO_CHAR(
              l_data_timestamp,
              'yyyy-mm-dd hh24:mi:ss.ff6'
            ) || ' with SCN ' || TO_CHAR(l_data_scn) || '.' || lf
            ELSE NULL
          END,
        '#PLEX_VERSION#',
        c_plex_version,
        '#PLEX_URL#',
        c_plex_url,
        '#P_APP_ID#',
        TO_CHAR(p_app_id),
        '#P_APP_DATE#',
        util_bool_to_string(p_app_date),
        '#P_APP_PUBLIC_REPORTS#',
        util_bool_to_string(p_app_public_reports),
        '#P_APP_PRIVATE_REPORTS#',
        util_bool_to_string(p_app_private_reports),
        '#P_APP_NOTIFICATIONS#',
        util_bool_to_string(p_app_notifications),
        '#P_APP_TRANSLATIONS#',
        util_bool_to_string(p_app_translations),
        '#P_APP_PKG_APP_MAPPING#',
        util_bool_to_string(p_app_pkg_app_mapping),
        '#P_APP_ORIGINAL_IDS#',
        util_bool_to_string(p_app_original_ids),
        '#P_APP_SUBSCRIPTIONS#',
        util_bool_to_string(p_app_subscriptions),
        '#P_APP_COMMENTS#',
        util_bool_to_string(p_app_comments),
        '#P_APP_SUPPORTING_OBJECTS#',
          CASE
            WHEN p_app_supporting_objects IS NULL THEN 'NULL'
            ELSE '''' || p_app_supporting_objects || ''''
          END,
        '#P_INCLUDE_OBJECT_DDL#',
        util_bool_to_string(p_include_object_ddl),
        '#P_OBJECT_FILTER_REGEX#',
          CASE
            WHEN p_object_filter_regex IS NULL THEN 'NULL'
            ELSE '''' || p_object_filter_regex || ''''
          END,
        '#P_INCLUDE_DATA#',
        util_bool_to_string(p_include_data),
        '#P_DATA_AS_OF_MINUTES_AGO#',
        TO_CHAR(p_data_as_of_minutes_ago),
        '#P_DATA_MAX_ROWS#',
        TO_CHAR(p_data_max_rows),
        '#P_DATA_TABLE_FILTER_REGEX#',
          CASE
            WHEN p_data_table_filter_regex IS NULL THEN 'NULL'
            ELSE '''' || p_data_table_filter_regex || ''''
          END,
        '#P_INCLUDE_RUNTIME_LOG#',
        util_bool_to_string(p_include_runtime_log),
        '#UNMEASURED_TIME#',
        trim(TO_CHAR(
          g_ilog.unmeasured_time,
          '999G990D000000'
        ) )
      ) );

      util_ilog_create_md_tab;
      apex_zip.add_file(
        p_zipped_blob   => l_zip,
        p_file_name     => 'plex_runtime_log.md',
        p_content       => util_g_clob_to_blob
      );

      util_g_clob_freetemporary;
    END create_runtime_log;

  BEGIN
    util_ilog_init(
      'plex.backapp' || CASE
        WHEN p_app_id IS NOT NULL THEN '(' || TO_CHAR(p_app_id) || ')'
      END,
      p_include_runtime_log
    );

    dbms_lob.createtemporary(
      l_zip,
      true
    );
    g_ddl_files   := NULL;
    get_apex_version;
    check_owner;
    --
    IF
      p_app_id IS NOT NULL
    THEN
      process_apex_app;
      create_frontend_install_files;
    END IF;
    --
    IF
      p_include_object_ddl
    THEN
      process_user_ddl;
      process_object_ddl;
      process_object_grants;
      process_ref_constraints;
      create_backend_install_files;
    END IF;
    --
    IF
      p_include_data
    THEN
      process_data;
    END IF;
    --
    create_supporting_files;
    --
    util_ilog_exit;
    --
    IF
      p_include_runtime_log
    THEN
      create_runtime_log;
    END IF;
    --
    apex_zip.finish(l_zip);
    RETURN l_zip;
  END backapp;

  PROCEDURE add_query (
    p_query       VARCHAR2,
    p_file_name   VARCHAR2,
    p_max_rows    NUMBER DEFAULT 1000
  ) IS
    l_index   PLS_INTEGER;
  BEGIN
    l_index                        := g_queries.count + 1;
    g_queries(l_index).query       := p_query;
    g_queries(l_index).file_name   := p_file_name;
    g_queries(l_index).max_rows    := p_max_rows;
  END add_query;

  FUNCTION queries_to_csv (
    p_delimiter             IN VARCHAR2 DEFAULT ',',
    p_quote_mark            IN VARCHAR2 DEFAULT '"',
    p_line_terminator       IN VARCHAR2 DEFAULT lf,
    p_header_prefix         IN VARCHAR2 DEFAULT NULL,
    p_include_runtime_log   IN BOOLEAN DEFAULT true
  ) RETURN BLOB IS

    l_zip   BLOB;
    --

    PROCEDURE create_runtime_log
      IS
    BEGIN
      util_g_clob_createtemporary;
      util_g_clob_append(util_multi_replace(
        '
PLEX - Queries to CSV - Runtime Log
===================================

Export started at #START_TIME# and took #RUN_TIME# seconds to finish.

Parameters
----------

- The used plex version was #PLEX_VERSION#
- More infos here: [PLEX on GitHub](#PLEX_URL#)

```sql
DECLARE
  zip BLOB;
BEGIN
  zip := plex.queries_to_csv(
    p_delimiter           => #P_DELIMITER#,
    p_quote_mark          => #P_QUOTE_MARK#,
    p_line_terminator     => #P_LINE_TERMINATOR#,
    p_header_prefix       => #P_HEADER_PREFIX#,
    p_include_runtime_log => #P_INCLUDE_RUNTIME_LOG#
  );
END;
```

Log Entries
-----------

Unmeasured execution time because of system waits, missing log calls or log
overhead was #UNMEASURED_TIME# seconds.
'
,
        '#START_TIME#',
        TO_CHAR(
          g_ilog.start_time,
          'yyyy-mm-dd hh24:mi:ss'
        ),
        '#RUN_TIME#',
        trim(TO_CHAR(
          g_ilog.run_time,
          '999G990D000'
        ) ),
        '#PLEX_VERSION#',
        c_plex_version,
        '#PLEX_URL#',
        c_plex_url,
        '#P_DELIMITER#',
        '''' || p_delimiter || '''',
        '#P_QUOTE_MARK#',
        '''' || p_quote_mark || '''',
        '#P_LINE_TERMINATOR#',
          CASE p_line_terminator
            WHEN c_cr THEN 'chr(13)'
            WHEN c_lf THEN 'chr(10)'
            WHEN c_crlf THEN 'chr(10) || chr(13)'
            ELSE '''' || p_line_terminator || ''''
          END,
        '#P_HEADER_PREFIX#',
          CASE
            WHEN p_header_prefix IS NULL THEN 'NULL'
            ELSE '''' || p_header_prefix || ''''
          END,
        '#P_INCLUDE_RUNTIME_LOG#',
        util_bool_to_string(p_include_runtime_log),
        '#UNMEASURED_TIME#',
        trim(TO_CHAR(
          g_ilog.unmeasured_time,
          '999G990D000000'
        ) )
      ) );

      util_ilog_create_md_tab;
      apex_zip.add_file(
        p_zipped_blob   => l_zip,
        p_file_name     => 'plex_runtime_log.md',
        p_content       => util_g_clob_to_blob
      );

      util_g_clob_freetemporary;
    END create_runtime_log;
    --

  BEGIN
    IF
      g_queries.count = 0
    THEN
      raise_application_error(
        -20201,
        'You need first to add queries by using plex.add_query. Calling plex.queries_to_csv clears the global queries array for subsequent processing.'
      );
    ELSE
      util_ilog_init(
        'plex.queries_to_csv',
        p_include_runtime_log
      );
      dbms_lob.createtemporary(
        l_zip,
        true
      );
      FOR i IN g_queries.first..g_queries.last LOOP
        util_ilog_start('process_query_to_csv:' || TO_CHAR(i) || ':' || g_queries(i).file_name);

        util_g_clob_createtemporary;
        util_g_clob_query_to_csv(
          p_query             => g_queries(i).query,
          p_max_rows          => g_queries(i).max_rows,
          p_delimiter         => p_delimiter,
          p_quote_mark        => p_quote_mark,
          p_line_terminator   => p_line_terminator,
          p_header_prefix     => p_header_prefix
        );

        apex_zip.add_file(
          p_zipped_blob   => l_zip,
          p_file_name     => g_queries(i).file_name || '.csv',
          p_content       => util_g_clob_to_blob
        );

        util_g_clob_freetemporary;
        util_ilog_stop;
      END LOOP;

      g_queries.DELETE;
      util_ilog_exit;
      IF
        p_include_runtime_log
      THEN
        create_runtime_log;
      END IF;
      apex_zip.finish(l_zip);
      RETURN l_zip;
    END IF;
  END queries_to_csv;

  FUNCTION view_runtime_log RETURN tab_runtime_log
    PIPELINED
  IS
    v_return   rec_runtime_log;
  BEGIN
    v_return.overall_start_time   := g_ilog.start_time;
    v_return.overall_run_time     := round(
      g_ilog.run_time,
      3
    );
    FOR i IN 1..g_ilog.data.count LOOP
      v_return.step        := i;
      v_return.elapsed     := round(
        g_ilog.data(i).elapsed,
        3
      );

      v_return.execution   := round(
        g_ilog.data(i).execution,
        6
      );

      v_return.module      := g_ilog.module;
      v_return.action      := g_ilog.data(i).action;
      PIPE ROW ( v_return );
    END LOOP;

  END view_runtime_log;

END plex;
/