CREATE OR REPLACE PACKAGE BODY plex IS

  -- CONSTANTS, TYPES

  c_tab                  CONSTANT VARCHAR2(1) := chr(9);
  c_lf                   CONSTANT VARCHAR2(1) := chr(10);
  c_cr                   CONSTANT VARCHAR2(1) := chr(13);
  c_crlf                 CONSTANT VARCHAR2(2) := chr(13)
                                 || chr(10);
  c_slash                CONSTANT VARCHAR2(1) := '/'; -- We need it to be able to compile this package via SQL*Plus. SQL*Plus starts actions
  c_at                   CONSTANT VARCHAR2(1) := '@'; -- on these characters regardsless if they encapsulated in strings or not :-(
  c_vc2_max_size         CONSTANT PLS_INTEGER := 32767;
  
  --
  TYPE rec_ilog_step IS RECORD ( --
    action                 app_info_text,
    start_time             TIMESTAMP(6),
    stop_time              TIMESTAMP(6),
    elapsed                NUMBER,
    execution              NUMBER
  );
  TYPE tab_ilog_step IS
    TABLE OF rec_ilog_step INDEX BY BINARY_INTEGER;
    
    --
  TYPE rec_ilog IS RECORD ( --
    module                 app_info_text,
    enabled                BOOLEAN,
    start_time             TIMESTAMP(6),
    stop_time              TIMESTAMP(6),
    run_time               NUMBER,
    measured_time          NUMBER,
    unmeasured_time        NUMBER,
    data                   tab_ilog_step
  );
  
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
    other_objects_         tab_vc1000
  );
  
    --
  TYPE rec_queries IS RECORD (--
    query                  VARCHAR2(32767 CHAR),
    file_name              VARCHAR2(256 CHAR),
    max_rows               NUMBER DEFAULT 100000
  );
  TYPE tab_queries IS
    TABLE OF rec_queries INDEX BY PLS_INTEGER;
  
  -- GLOBAL VARIABLES
  g_clob                 CLOB;
  g_clob_varchar_cache   VARCHAR2(32767char);
  g_ilog                 rec_ilog;
  g_queries              tab_queries;


  -- UTILITIES

  FUNCTION util_bool_to_string (
    p_bool IN BOOLEAN
  ) RETURN VARCHAR2 IS
  BEGIN
    RETURN
      CASE
        WHEN p_bool THEN
          'TRUE'
        ELSE 'FALSE'
      END;
  END util_bool_to_string;

  FUNCTION util_string_to_bool (
    p_bool_string   IN              VARCHAR2,
    p_default       IN              BOOLEAN
  ) RETURN BOOLEAN IS
    l_bool_string   VARCHAR2(1 CHAR);
    l_return        BOOLEAN;
  BEGIN
    l_bool_string   := upper(substr(
      p_bool_string,
      1,
      1
    ));
    l_return        :=
      CASE
        WHEN l_bool_string IN (
          '1',
          'Y',
          'T'
        ) THEN
          true
        WHEN l_bool_string IN (
          '0',
          'N',
          'F'
        ) THEN
          false
        ELSE p_default
      END;

    RETURN l_return;
  END util_string_to_bool;

  FUNCTION util_split (
    p_string      IN            VARCHAR2,
    p_delimiter   IN            VARCHAR2 DEFAULT ','
  ) RETURN tab_varchar2 IS

    v_return             tab_varchar2 := tab_varchar2();
    v_offset             PLS_INTEGER := 1;
    v_index              PLS_INTEGER := instr(
      p_string,
      p_delimiter,
      v_offset
    );
    v_delimiter_length   PLS_INTEGER := length(p_delimiter);
    v_string_length      CONSTANT PLS_INTEGER := length(p_string);
    v_count              PLS_INTEGER := 1;

    PROCEDURE add_value (
      p_value VARCHAR2
    ) IS
    BEGIN
      v_return.extend;
      v_return(v_count)   := p_value;
      v_count             := v_count + 1;
    END;

  BEGIN
    WHILE v_index > 0 LOOP
      add_value(trim(substr(
        p_string,
        v_offset,
        v_index - v_offset
      )));
      v_offset   := v_index + v_delimiter_length;
      v_index    := instr(
        p_string,
        p_delimiter,
        v_offset
      );
    END LOOP;

    IF v_string_length - v_offset + 1 > 0 THEN
      add_value(trim(substr(
        p_string,
        v_offset,
        v_string_length - v_offset + 1
      )));

    END IF;

    RETURN v_return;
  END util_split;

  FUNCTION util_join (
    p_array       IN            tab_varchar2,
    p_delimiter   VARCHAR2 DEFAULT ','
  ) RETURN VARCHAR2 IS
    v_return VARCHAR2(32767);
  BEGIN
    IF p_array IS NOT NULL AND p_array.count > 0 THEN
      v_return := p_array(1);
      FOR i IN 2..p_array.count LOOP v_return := v_return
                                                 || p_delimiter
                                                 || p_array(i);
      END LOOP;

    END IF;

    RETURN v_return;
  EXCEPTION
    WHEN value_error THEN
      RETURN v_return;
  END util_join;

  FUNCTION util_clob_to_blob (
    p_clob CLOB
  ) RETURN BLOB IS

    l_blob           BLOB;
    l_lang_context   INTEGER := dbms_lob.default_lang_ctx;
    l_warning        INTEGER := dbms_lob.warn_inconvertible_char;
    l_dest_offset    INTEGER := 1;
    l_src_offset     INTEGER := 1;
  BEGIN
    IF p_clob IS NOT NULL THEN
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
    p_12_replace      VARCHAR2 DEFAULT NULL
  ) RETURN VARCHAR2 IS
    l_return VARCHAR2(32767);
  BEGIN
    l_return := p_source_string;
    IF p_1_find IS NOT NULL THEN
      l_return := replace(
        l_return,
        p_1_find,
        p_1_replace
      );
    END IF;

    IF p_2_find IS NOT NULL THEN
      l_return := replace(
        l_return,
        p_2_find,
        p_2_replace
      );
    END IF;

    IF p_3_find IS NOT NULL THEN
      l_return := replace(
        l_return,
        p_3_find,
        p_3_replace
      );
    END IF;

    IF p_4_find IS NOT NULL THEN
      l_return := replace(
        l_return,
        p_4_find,
        p_4_replace
      );
    END IF;

    IF p_5_find IS NOT NULL THEN
      l_return := replace(
        l_return,
        p_5_find,
        p_5_replace
      );
    END IF;

    IF p_6_find IS NOT NULL THEN
      l_return := replace(
        l_return,
        p_6_find,
        p_6_replace
      );
    END IF;

    IF p_7_find IS NOT NULL THEN
      l_return := replace(
        l_return,
        p_7_find,
        p_7_replace
      );
    END IF;

    IF p_8_find IS NOT NULL THEN
      l_return := replace(
        l_return,
        p_8_find,
        p_8_replace
      );
    END IF;

    IF p_9_find IS NOT NULL THEN
      l_return := replace(
        l_return,
        p_9_find,
        p_9_replace
      );
    END IF;

    IF p_10_find IS NOT NULL THEN
      l_return := replace(
        l_return,
        p_10_find,
        p_10_replace
      );
    END IF;

    IF p_11_find IS NOT NULL THEN
      l_return := replace(
        l_return,
        p_11_find,
        p_11_replace
      );
    END IF;

    IF p_12_find IS NOT NULL THEN
      l_return := replace(
        l_return,
        p_12_find,
        p_12_replace
      );
    END IF;

    RETURN l_return;
  END util_multi_replace;

  FUNCTION util_set_build_status_run_only (
    p_contents CLOB
  ) RETURN CLOB IS
    l_position PLS_INTEGER;
  BEGIN
    l_position := instr(
      p_contents,
      ',p_exact_substitutions_only'
    );
    RETURN substr(
      p_contents,
      1,
      l_position - 1
    )
           || ',p_build_status=>''RUN_ONLY'''
           || c_lf
           || substr(
      p_contents,
      l_position
    );

  END util_set_build_status_run_only;

  PROCEDURE util_export_files_append (
    p_export_files IN OUT NOCOPY tab_export_files,
    p_name       VARCHAR2,
    p_contents   CLOB
  ) IS
    l_index PLS_INTEGER;
  BEGIN
    l_index                   := p_export_files.count + 1;
    p_export_files.extend;
    p_export_files(l_index)   := rec_export_file(
      name       => p_name,
      contents   => p_contents
    );

  END util_export_files_append;

  FUNCTION util_calc_data_timestamp (
    p_as_of_minutes_ago NUMBER
  ) RETURN TIMESTAMP IS
    l_return TIMESTAMP;
  BEGIN
    EXECUTE IMMEDIATE replace(
      q'[SELECT systimestamp - INTERVAL '{{MINUTES}}' MINUTE FROM dual]',
      '{{MINUTES}}',
      TO_CHAR(p_as_of_minutes_ago)
    )
    INTO l_return;
    RETURN l_return;
  END util_calc_data_timestamp;

  PROCEDURE util_setup_dbms_metadata (
    p_pretty                 IN                       BOOLEAN DEFAULT true,
    p_constraints            IN                       BOOLEAN DEFAULT true,
    p_ref_constraints        IN                       BOOLEAN DEFAULT false,
    p_partitioning           IN                       BOOLEAN DEFAULT true,
    p_tablespace             IN                       BOOLEAN DEFAULT false,
    p_storage                IN                       BOOLEAN DEFAULT false,
    p_segment_attributes     IN                       BOOLEAN DEFAULT false,
    p_sqlterminator          IN                       BOOLEAN DEFAULT true,
    p_constraints_as_alter   IN                       BOOLEAN DEFAULT false,
    p_emit_schema            IN                       BOOLEAN DEFAULT false
  ) IS
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

  PROCEDURE util_g_clob_createtemporary IS
  BEGIN
    g_clob := NULL;
    dbms_lob.createtemporary(
      g_clob,
      true
    );
  END util_g_clob_createtemporary;

  PROCEDURE util_g_clob_freetemporary IS
  BEGIN
    dbms_lob.freetemporary(g_clob);
  END util_g_clob_freetemporary;

  PROCEDURE util_g_clob_flush_cache IS
  BEGIN
    IF g_clob_varchar_cache IS NOT NULL THEN
      IF g_clob IS NULL THEN
        g_clob := g_clob_varchar_cache;
      ELSE
        dbms_lob.append(
          g_clob,
          g_clob_varchar_cache
        );
      END IF;

      g_clob_varchar_cache := NULL;
    END IF;
  END util_g_clob_flush_cache;

  PROCEDURE util_g_clob_append (
    p_content IN VARCHAR2
  ) IS
  BEGIN
    g_clob_varchar_cache := g_clob_varchar_cache || p_content;
  EXCEPTION
    WHEN value_error THEN
      IF g_clob IS NULL THEN
        g_clob := g_clob_varchar_cache;
      ELSE
        dbms_lob.append(
          g_clob,
          g_clob_varchar_cache
        );
      END IF;

      g_clob_varchar_cache := p_content;
  END util_g_clob_append;

  PROCEDURE util_g_clob_append (
    p_content IN CLOB
  ) IS
  BEGIN
    util_g_clob_flush_cache;
    IF g_clob IS NULL THEN
      g_clob := p_content;
    ELSE
      dbms_lob.append(
        g_clob,
        p_content
      );
    END IF;

  END util_g_clob_append;

  PROCEDURE util_g_clob_query_to_csv (
    p_query           VARCHAR2,
    p_max_rows        NUMBER DEFAULT 1000,
    --
    p_delimiter       VARCHAR2 DEFAULT ',',
    p_quote_mark      VARCHAR2 DEFAULT '"',
    p_header_prefix   VARCHAR2 DEFAULT NULL
  ) IS 
    -- inspired by Tim Hall: https://oracle-base.com/dba/script?category=miscellaneous&file=csv.sql

    l_line_terminator            VARCHAR2(2) := c_crlf; -- to be compatible with Excel we need to use crlf here (multiline text uses lf and is wrapped in quotes)
    l_cursor                     PLS_INTEGER;
    l_ignore                     PLS_INTEGER;
    l_data_count                 PLS_INTEGER := 0;
    l_col_cnt                    PLS_INTEGER;
    l_desc_tab                   dbms_sql.desc_tab3;
    l_buffer_varchar2            VARCHAR2(32767 CHAR);
    l_buffer_clob                CLOB;
    l_buffer_xmltype             XMLTYPE;
    l_buffer_long                LONG;
    l_buffer_long_length         PLS_INTEGER;

    -- numeric type identfiers
    c_number                     CONSTANT PLS_INTEGER := 2; -- also FLOAT
    c_binary_float               CONSTANT PLS_INTEGER := 100;
    c_binary_double              CONSTANT PLS_INTEGER := 101;
    -- string type identfiers
    c_char                       CONSTANT PLS_INTEGER := 96; -- also NCHAR
    c_varchar2                   CONSTANT PLS_INTEGER := 1; -- also NVARCHAR2
    c_long                       CONSTANT PLS_INTEGER := 8;
    c_clob                       CONSTANT PLS_INTEGER := 112; -- also NCLOB
    c_xmltype                    CONSTANT PLS_INTEGER := 109; -- also ANYDATA, ANYDATASET, ANYTYPE, Object type, VARRAY, Nested table
    c_rowid                      CONSTANT PLS_INTEGER := 11;
    c_urowid                     CONSTANT PLS_INTEGER := 208;
    -- binary type identfiers
    c_raw                        CONSTANT PLS_INTEGER := 23;
    c_long_raw                   CONSTANT PLS_INTEGER := 24;
    c_blob                       CONSTANT PLS_INTEGER := 113;
    c_bfile                      CONSTANT PLS_INTEGER := 114;
    -- date type identfiers
    c_date                       CONSTANT PLS_INTEGER := 12;
    c_timestamp                  CONSTANT PLS_INTEGER := 180;
    c_timestamp_with_time_zone   CONSTANT PLS_INTEGER := 181;
    c_timestamp_with_local_tz    CONSTANT PLS_INTEGER := 231;
    -- interval type identfiers
    c_interval_year_to_month     CONSTANT PLS_INTEGER := 182;
    c_interval_day_to_second     CONSTANT PLS_INTEGER := 183;
    -- cursor type identfiers
    c_ref                        CONSTANT PLS_INTEGER := 111;
    c_ref_cursor                 CONSTANT PLS_INTEGER := 102; -- same identfiers for strong and weak ref cursor

    PROCEDURE escape_varchar2_buffer_for_csv IS
    BEGIN
      IF l_buffer_varchar2 IS NOT NULL THEN
        -- normalize line feeds for Excel
        l_buffer_varchar2 := replace(
          replace(
            l_buffer_varchar2,
            c_crlf,
            c_lf
          ),
          c_cr,
          c_lf
        );

        -- if we have the parameter p_force_quotes set to true or the delimiter character or 
        -- line feeds in the string then we have to wrap the text in quotes marks and escape 
        -- the quote marks inside the text by double them

        IF instr(
          l_buffer_varchar2,
          p_delimiter
        ) > 0 OR instr(
          l_buffer_varchar2,
          c_lf
        ) > 0 THEN
          l_buffer_varchar2 := p_quote_mark
                               || replace(
            l_buffer_varchar2,
            p_quote_mark,
            p_quote_mark || p_quote_mark
          )
                               || p_quote_mark;

        END IF;

      END IF;
    EXCEPTION
      WHEN value_error THEN
        l_buffer_varchar2 := 'Value skipped - escaped text larger then '
                             || c_vc2_max_size
                             || ' characters';
    END escape_varchar2_buffer_for_csv;

  BEGIN
    IF p_query IS NOT NULL THEN
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
      FOR i IN 1..l_col_cnt LOOP IF l_desc_tab(i).col_type = c_clob THEN
        dbms_sql.define_column(
          l_cursor,
          i,
          l_buffer_clob
        );
      ELSIF l_desc_tab(i).col_type = c_xmltype THEN
        dbms_sql.define_column(
          l_cursor,
          i,
          l_buffer_xmltype
        );
      ELSIF l_desc_tab(i).col_type = c_long THEN
        dbms_sql.define_column_long(
          l_cursor,
          i
        );
      ELSIF l_desc_tab(i).col_type IN (
        c_raw,
        c_long_raw,
        c_blob,
        c_bfile
      ) THEN
        NULL; --> we ignore binary data types
      ELSE
        dbms_sql.define_column(
          l_cursor,
          i,
          l_buffer_varchar2,
          c_vc2_max_size
        );
      END IF;
      END LOOP;

      l_ignore   := dbms_sql.execute(l_cursor);
    
      -- create header
      util_g_clob_append(p_header_prefix);
      FOR i IN 1..l_col_cnt LOOP
        IF i > 1 THEN
          util_g_clob_append(p_delimiter);
        END IF;
        l_buffer_varchar2 := l_desc_tab(i).col_name;
        escape_varchar2_buffer_for_csv;
        util_g_clob_append(l_buffer_varchar2);
      END LOOP;

      util_g_clob_append(l_line_terminator);
    
      -- create data
      LOOP
        EXIT WHEN dbms_sql.fetch_rows(l_cursor) = 0 OR l_data_count = p_max_rows;
        FOR i IN 1..l_col_cnt LOOP
          IF i > 1 THEN
            util_g_clob_append(p_delimiter);
          END IF;
          --
          IF l_desc_tab(i).col_type = c_clob THEN
            dbms_sql.column_value(
              l_cursor,
              i,
              l_buffer_clob
            );
            IF length(l_buffer_clob) <= c_vc2_max_size THEN
              l_buffer_varchar2 := substr(
                l_buffer_clob,
                1,
                c_vc2_max_size
              );
              escape_varchar2_buffer_for_csv;
              util_g_clob_append(l_buffer_varchar2);
            ELSE
              l_buffer_varchar2 := 'CLOB value skipped - larger then '
                                   || c_vc2_max_size
                                   || ' characters';
              util_g_clob_append(l_buffer_varchar2);
            END IF;

          ELSIF l_desc_tab(i).col_type = c_xmltype THEN
            dbms_sql.column_value(
              l_cursor,
              i,
              l_buffer_xmltype
            );
            l_buffer_clob := l_buffer_xmltype.getclobval();
            IF length(l_buffer_clob) <= c_vc2_max_size THEN
              l_buffer_varchar2 := substr(
                l_buffer_clob,
                1,
                c_vc2_max_size
              );
              escape_varchar2_buffer_for_csv;
              util_g_clob_append(l_buffer_varchar2);
            ELSE
              l_buffer_varchar2 := 'XML value skipped - larger then '
                                   || c_vc2_max_size
                                   || ' characters';
              util_g_clob_append(l_buffer_varchar2);
            END IF;

          ELSIF l_desc_tab(i).col_type = c_long THEN
            dbms_sql.column_value_long(
              l_cursor,
              i,
              c_vc2_max_size,
              0,
              l_buffer_varchar2,
              l_buffer_long_length
            );
            IF l_buffer_long_length <= c_vc2_max_size THEN
              escape_varchar2_buffer_for_csv;
              util_g_clob_append(l_buffer_varchar2);
            ELSE
              util_g_clob_append('LONG value skipped - larger then '
                                 || c_vc2_max_size
                                 || ' characters');
            END IF;

          ELSIF l_desc_tab(i).col_type IN (
            c_raw,
            c_long_raw,
            c_blob,
            c_bfile
          ) THEN
            util_g_clob_append('Binary data type skipped - not supported for CSV');
          ELSE
            dbms_sql.column_value(
              l_cursor,
              i,
              l_buffer_varchar2
            );
            escape_varchar2_buffer_for_csv;
            util_g_clob_append(l_buffer_varchar2);
          END IF;

        END LOOP;

        util_g_clob_append(l_line_terminator);
        l_data_count := l_data_count + 1;
      END LOOP;

      dbms_sql.close_cursor(l_cursor);
    END IF;
  END util_g_clob_query_to_csv;

  PROCEDURE util_g_clob_create_runtime_log IS
  BEGIN
    util_g_clob_append(util_multi_replace(
      '
{{MAIN_FUNCTION}} - Runtime Log
============================================================

- Export started at {{START_TIME}} and took {{RUN_TIME}} seconds to finish
- Unmeasured execution time because of system waits, missing log calls or log overhead was {{UNMEASURED_TIME}} seconds
- The used PLEX version was {{PLEX_VERSION}}
- More infos here: [PLEX on GitHub]({{PLEX_URL}})

'
      ,
      '{{MAIN_FUNCTION}}',
      upper(g_ilog.module),
      '{{START_TIME}}',
      TO_CHAR(
        g_ilog.start_time,
        'yyyy-mm-dd hh24:mi:ss'
      ),
      '{{RUN_TIME}}',
      trim(TO_CHAR(
        g_ilog.run_time,
        '999G990D000'
      )),
      '{{UNMEASURED_TIME}}',
      trim(TO_CHAR(
        g_ilog.unmeasured_time,
        '999G990D000000'
      )),
      '{{PLEX_VERSION}}',
      c_plex_version,
      '{{PLEX_URL}}',
      c_plex_url
    ));

    util_g_clob_append('
| Step |   Elapsed |   Execution | Action                                                           |
|-----:|----------:|------------:|:-----------------------------------------------------------------|
'

    );
    FOR i IN 1..g_ilog.data.count LOOP util_g_clob_append(util_multi_replace(
      '| {{STEP}} | {{ELAPSED}} | {{EXECUTION}} | {{ACTION}} |' || c_lf,
      '{{STEP}}',
      lpad(
        TO_CHAR(i),
        4
      ),
      '{{ELAPSED}}',
      lpad(
        trim(TO_CHAR(
          g_ilog.data(i).elapsed,
          '99990D000'
        )),
        9
      ),
      '{{EXECUTION}}',
      lpad(
        trim(TO_CHAR(
          g_ilog.data(i).execution,
          '9990D000000'
        )),
        11
      ),
      '{{ACTION}}',
      rpad(
        g_ilog.data(i).action,
        64
      )
    ));
    END LOOP;

  END util_g_clob_create_runtime_log;

  FUNCTION util_ilog_get_runtime (
    p_start TIMESTAMP,
    p_stop TIMESTAMP
  ) RETURN NUMBER IS
  BEGIN
    RETURN SYSDATE + ( ( p_stop - p_start ) * 86400 ) - SYSDATE;
    --sysdate + (interval_difference * 86400) - sysdate
    --https://stackoverflow.com/questions/10092032/extracting-the-total-number-of-seconds-from-an-interval-data-type  
  END util_ilog_get_runtime;

  PROCEDURE util_ilog_init (
    p_module VARCHAR2,
    p_include_runtime_log BOOLEAN
  ) IS
  BEGIN
    g_ilog.module            := substr(
      p_module,
      1,
      c_app_info_length
    );
    IF p_include_runtime_log THEN
      g_ilog.enabled := true;
    END IF;
    g_ilog.start_time        := systimestamp;
    g_ilog.stop_time         := NULL;
    g_ilog.run_time          := 0;
    g_ilog.measured_time     := 0;
    g_ilog.unmeasured_time   := 0;
    g_ilog.data.DELETE;
  END util_ilog_init;

  PROCEDURE util_ilog_exit IS
  BEGIN
    IF g_ilog.enabled THEN
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
    l_index PLS_INTEGER;
  BEGIN
    dbms_application_info.set_module(
      module_name   => g_ilog.module,
      action_name   => p_action
    );
    IF g_ilog.enabled THEN
      l_index                           := g_ilog.data.count + 1;
      g_ilog.data(l_index).action       := substr(
        p_action,
        1,
        plex.c_app_info_length
      );

      g_ilog.data(l_index).start_time   := systimestamp;
    END IF;

  END util_ilog_start;

  PROCEDURE util_ilog_append_action_text (
    p_text VARCHAR2
  ) IS
    l_index PLS_INTEGER;
  BEGIN
    IF g_ilog.enabled THEN
      l_index                       := g_ilog.data.count;
      g_ilog.data(l_index).action   := substr(
        g_ilog.data(l_index).action
        || p_text,
        1,
        plex.c_app_info_length
      );

    END IF;
  END util_ilog_append_action_text;

  PROCEDURE util_ilog_stop IS
    l_index PLS_INTEGER;
  BEGIN
    l_index := g_ilog.data.count;
    dbms_application_info.set_module(
      module_name   => NULL,
      action_name   => NULL
    );
    IF g_ilog.enabled THEN
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



  -- MAIN CODE

  FUNCTION backapp (
  $if $$apex_exists $then

    p_app_id                      IN                            NUMBER DEFAULT NULL,
    p_app_date                    IN                            BOOLEAN DEFAULT true,
    p_app_public_reports          IN                            BOOLEAN DEFAULT true,
    p_app_private_reports         IN                            BOOLEAN DEFAULT false,
    p_app_notifications           IN                            BOOLEAN DEFAULT false,
    p_app_translations            IN                            BOOLEAN DEFAULT true,
    p_app_pkg_app_mapping         IN                            BOOLEAN DEFAULT false,
    p_app_original_ids            IN                            BOOLEAN DEFAULT false,
    p_app_subscriptions           IN                            BOOLEAN DEFAULT true,
    p_app_comments                IN                            BOOLEAN DEFAULT true,
    p_app_supporting_objects      IN                            VARCHAR2 DEFAULT NULL,
    p_app_include_single_file     IN                            BOOLEAN DEFAULT false,
    p_app_build_status_run_only   IN                            BOOLEAN DEFAULT false,
  $end
    p_include_object_ddl          IN                            BOOLEAN DEFAULT false,
    p_object_name_like            IN                            VARCHAR2 DEFAULT NULL,
    p_object_name_not_like        IN                            VARCHAR2 DEFAULT NULL,
    p_include_data                IN                            BOOLEAN DEFAULT false,
    p_data_as_of_minutes_ago      IN                            NUMBER DEFAULT 0,
    p_data_max_rows               IN                            NUMBER DEFAULT 1000,
    p_data_table_name_like        IN                            VARCHAR2 DEFAULT NULL,
    p_data_table_name_not_like    IN                            VARCHAR2 DEFAULT NULL,
    p_include_templates           IN                            BOOLEAN DEFAULT true,
    p_include_runtime_log         IN                            BOOLEAN DEFAULT true
  ) RETURN tab_export_files IS

    l_apex_version     NUMBER;
    l_data_timestamp   TIMESTAMP;
    l_data_scn         NUMBER;
    l_file_path        VARCHAR2(255);
    l_current_user     user_objects.object_name%TYPE;
    l_app_workspace    user_objects.object_name%TYPE;
    l_app_owner        user_objects.object_name%TYPE;
    l_app_alias        user_objects.object_name%TYPE;
    -- 
    l_ddl_files        rec_ddl_files;
    l_contents         CLOB;
    l_export_files     tab_export_files;
    --
    TYPE obj_cur_typ IS REF CURSOR;
    l_cur              obj_cur_typ;
    l_query            VARCHAR2(32767);

    PROCEDURE init IS
    BEGIN
      util_ilog_init(
        p_module                => 'plex.backapp'
          $if $$apex_exists $then

                    || CASE
          WHEN p_app_id IS NOT NULL THEN
            '('
            || TO_CHAR(p_app_id)
            || ')'
        END
        $end,
        p_include_runtime_log   => p_include_runtime_log
      );
    END init;

$if $$apex_exists $then

    PROCEDURE check_owner IS
      CURSOR cur_owner IS
      SELECT
        workspace,
        owner,
        alias
      FROM
        apex_applications t
      WHERE
        t.application_id = p_app_id;

    BEGIN
      util_ilog_start('check_owner');
      l_current_user := sys_context(
        'USERENV',
        'CURRENT_USER'
      );
      IF p_app_id IS NOT NULL THEN
        OPEN cur_owner;
        FETCH cur_owner INTO
          l_app_workspace,
          l_app_owner,
          l_app_alias;
        CLOSE cur_owner;
      END IF;

      IF p_app_id IS NOT NULL AND l_app_owner IS NULL THEN
        raise_application_error(
          -20101,
          'Could not find owner for application - are you sure you provided the right app_id?'
        );
      ELSIF p_app_id IS NOT NULL AND l_app_owner != l_current_user THEN
        raise_application_error(
          -20102,
          'You are not the owner of the app - please login as the owner.'
        );
      END IF;

      util_ilog_stop;
    END check_owner;
$end

$if $$apex_exists $then

    PROCEDURE process_apex_app IS
      l_single_file tab_export_files;
    BEGIN

      -- save as individual files
      util_ilog_start('app_frontend/APEX_EXPORT:individual_files');
      l_export_files := apex_export.get_application(
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
            WHEN p_app_subscriptions THEN
              false
            ELSE true
          END,
        p_with_comments             => p_app_comments,
        p_with_supporting_objects   => p_app_supporting_objects
      );

      FOR i IN 1..l_export_files.count LOOP
        -- relocate files to own project structure
        l_export_files(i).name       := replace(
          l_export_files(i).name,
          'f'
          || p_app_id
          || '/application/',
          'app_frontend/'
        );
        -- correct prompts for relocation

        l_export_files(i).contents   := replace(
          l_export_files(i).contents,
          'prompt --application/',
          'prompt --app_frontend/'
        );
        -- special handling for install file

        IF l_export_files(i).name = 'f'
                                    || p_app_id
                                    || '/install.sql' THEN
          l_export_files(i).name       := 'scripts/install_frontend_generated_by_apex.sql';
          l_export_files(i).contents   := '-- DO NOT TOUCH THIS FILE - IT WILL BE OVERWRITTEN ON NEXT PLEX BACKAPP CALL'
                                        || c_lf
                                        || c_lf
                                        || replace(
            replace(
              l_export_files(i).contents,
              '@application/',
              '@../app_frontend/'
            ),
            'prompt --install',
            'prompt --install_frontend_generated_by_apex'
          );

        END IF;
        
        -- handle build status RUN_ONLY

        IF l_export_files(i).name = 'app_frontend/create_application.sql' AND p_app_build_status_run_only THEN
          l_export_files(i).contents := util_set_build_status_run_only(l_export_files(i).contents);
        END IF;

      END LOOP;

      util_ilog_stop;
      IF p_app_include_single_file THEN
      -- save as single file 
        util_ilog_start('app_frontend/APEX_EXPORT:single_file');
        l_single_file := apex_export.get_application(
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
              WHEN p_app_subscriptions THEN
                false
              ELSE true
            END,
          p_with_comments             => p_app_comments,
          p_with_supporting_objects   => p_app_supporting_objects
        );

        IF p_app_build_status_run_only THEN
          l_single_file(1).contents := util_set_build_status_run_only(l_single_file(1).contents);
        END IF;

        util_export_files_append(
          p_export_files   => l_export_files,
          p_name           => 'app_frontend/' || l_single_file(1).name,
          p_contents       => l_single_file(1).contents
        );

        l_single_file.DELETE;
        util_ilog_stop;
      END IF;

    END process_apex_app;
  $end

    PROCEDURE replace_query_like_expressions (
      p_like_list       VARCHAR2,
      p_not_like_list   VARCHAR2,
      p_column_name     VARCHAR2
    ) IS
      l_expression_table tab_varchar2;
    BEGIN
        -- process filter "like"
      l_expression_table   := util_split(
        p_like_list,
        ','
      );
      FOR i IN 1..l_expression_table.count LOOP l_expression_table(i) := p_column_name
                                                                         || ' like '''
                                                                         || trim(l_expression_table(i))
                                                                         || ''' escape ''\''';
      END LOOP;

      l_query              := replace(
        l_query,
        '#LIKE_EXPRESSIONS#',
        nvl(
          util_join(
            l_expression_table,
            ' or '
          ),
          '1 = 1'
        )
      );

    -- process filter "not like"

      l_expression_table   := util_split(
        p_not_like_list,
        ','
      );
      FOR i IN 1..l_expression_table.count LOOP l_expression_table(i) := p_column_name
                                                                         || ' not like '''
                                                                         || trim(l_expression_table(i))
                                                                         || ''' escape ''\''';
      END LOOP;

      l_query              := replace(
        l_query,
        '#NOT_LIKE_EXPRESSIONS#',
        nvl(
          util_join(
            l_expression_table,
            ' and '
          ),
          '1 = 1'
        )
      );

      --dbms_output.put_line(l_query);

    END replace_query_like_expressions;

    PROCEDURE process_user_ddl IS
      exception_occured BOOLEAN := false;
    BEGIN
      -- user itself
      BEGIN
        l_file_path   := 'app_backend/_user/'
                       || l_current_user
                       || '.sql';
        util_ilog_start(l_file_path);
        l_contents    := replace(
          q'^
BEGIN 
  FOR i IN (SELECT '{{CURRENT_USER}}' AS username FROM dual MINUS SELECT username FROM dba_users) LOOP
    EXECUTE IMMEDIATE q'[
--------------------------------------------------------------------------------
^'
          ,
          '{{CURRENT_USER}}',
          l_current_user
        );
        --
        util_setup_dbms_metadata(p_sqlterminator => false);
        BEGIN
          l_contents := l_contents
                        || dbms_metadata.get_ddl(
            'USER',
            l_current_user
          );
        EXCEPTION
          WHEN OTHERS THEN
            exception_occured   := true;
            util_ilog_append_action_text(' ' || sqlerrm);
            l_contents          := l_contents || sqlerrm;
        END;

        util_setup_dbms_metadata;
        --
        l_contents    := l_contents
                      || replace(
          q'^
--------------------------------------------------------------------------------
    ]'
  END LOOP;
END;
{{SLASH}}
^'
          ,
          '{{SLASH}}',
          c_slash
        );
        util_export_files_append(
          p_export_files   => l_export_files,
          p_name           => l_file_path,
          p_contents       => l_contents
        );
        util_ilog_stop;
      END;

      -- roles

      BEGIN
        l_contents    := NULL;
        l_file_path   := 'app_backend/_user/'
                       || l_current_user
                       || '_roles.sql';
        util_ilog_start(l_file_path);
        FOR i IN (
     -- ensure we get no dbms_metadata error when no role privs exists
          SELECT DISTINCT
            username
          FROM
            user_role_privs
        ) LOOP BEGIN
          l_contents := l_contents
                        || dbms_metadata.get_granted_ddl(
            'ROLE_GRANT',
            l_current_user
          );
        EXCEPTION
          WHEN OTHERS THEN
            exception_occured   := true;
            util_ilog_append_action_text(' ' || sqlerrm);
            l_contents          := l_contents || sqlerrm;
        END;
        END LOOP;

        util_export_files_append(
          p_export_files   => l_export_files,
          p_name           => l_file_path,
          p_contents       => l_contents
        );
        util_ilog_stop;
      END;

      -- system privileges

      BEGIN
        l_contents    := NULL;
        l_file_path   := 'app_backend/_user/'
                       || l_current_user
                       || '_system_privileges.sql';
        util_ilog_start(l_file_path);
        FOR i IN (
     -- ensure we get no dbms_metadata error when no sys privs exists
          SELECT DISTINCT
            username
          FROM
            user_sys_privs
        ) LOOP BEGIN
          l_contents := l_contents
                        || dbms_metadata.get_granted_ddl(
            'SYSTEM_GRANT',
            l_current_user
          );
        EXCEPTION
          WHEN OTHERS THEN
            exception_occured   := true;
            util_ilog_append_action_text(' ' || sqlerrm);
            l_contents          := l_contents || sqlerrm;
        END;
        END LOOP;

        util_export_files_append(
          p_export_files   => l_export_files,
          p_name           => l_file_path,
          p_contents       => l_contents
        );
        util_ilog_stop;
      END;

      -- object privileges

      BEGIN
        l_contents    := NULL;
        l_file_path   := 'app_backend/_user/'
                       || l_current_user
                       || '_object_privileges.sql';
        util_ilog_start(l_file_path);
        FOR i IN (
     -- ensure we get no dbms_metadata error when no object grants exists
          SELECT DISTINCT
            grantee
          FROM
            user_tab_privs
          WHERE
            grantee = l_current_user
        ) LOOP BEGIN
          l_contents := l_contents
                        || dbms_metadata.get_granted_ddl(
            'OBJECT_GRANT',
            l_current_user
          );
        EXCEPTION
          WHEN OTHERS THEN
            exception_occured   := true;
            util_ilog_append_action_text(' ' || sqlerrm);
            l_contents          := l_contents || sqlerrm;
        END;
        END LOOP;

        util_export_files_append(
          p_export_files   => l_export_files,
          p_name           => l_file_path,
          p_contents       => l_contents
        );
        util_ilog_stop;
      END;

      IF exception_occured THEN
        l_file_path := 'app_backend/_user/_ERROR_on_DDL_creation_occured.md';
        util_ilog_start(l_file_path);
        util_export_files_append(
          p_export_files   => l_export_files,
          p_name           => l_file_path,
          p_contents       => '
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
        util_ilog_stop;
      END IF;

    END process_user_ddl;

    PROCEDURE process_object_ddl IS

      l_contents    CLOB;
      TYPE obj_rec_typ IS RECORD (
        object_type   VARCHAR2(128),
        object_name   VARCHAR2(256),
        file_path     VARCHAR2(512)
      );
      l_rec         obj_rec_typ;
    BEGIN
      util_ilog_start('app_backend/open_objects_cursor');
      l_query := q'^
--https://stackoverflow.com/questions/10886450/how-to-generate-entire-ddl-of-an-oracle-schema-scriptable
--https://stackoverflow.com/questions/3235300/oracles-dbms-metadata-get-ddl-for-object-type-job
SELECT CASE object_type
         WHEN 'DATABASE LINK'        THEN 'DB_LINK'
         WHEN 'EVALUATION CONTEXT'   THEN 'PROCOBJ'
         WHEN 'JAVA CLASS'           THEN 'JAVA_CLASS'
         WHEN 'JAVA RESOURCE'        THEN 'JAVA_RESOURCE'
         WHEN 'JAVA SOURCE'          THEN 'JAVA_SOURCE'
         WHEN 'JAVA TYPE'            THEN 'JAVA_TYPE'
         WHEN 'JOB'                  THEN 'PROCOBJ'
         WHEN 'MATERIALIZED VIEW'    THEN 'MATERIALIZED_VIEW'
         WHEN 'PACKAGE BODY'         THEN 'PACKAGE_BODY'
         WHEN 'PACKAGE'              THEN 'PACKAGE_SPEC'
         WHEN 'PROGRAM'              THEN 'PROCOBJ'
         WHEN 'QUEUE'                THEN 'AQ_QUEUE'
         WHEN 'RULE SET'             THEN 'PROCOBJ'
         WHEN 'RULE'                 THEN 'PROCOBJ'
         WHEN 'SCHEDULE'             THEN 'PROCOBJ'
         WHEN 'TYPE BODY'            THEN 'TYPE_BODY'
         WHEN 'TYPE'                 THEN 'TYPE_SPEC'
         ELSE object_type
       END AS object_type,
       object_name,
       'app_backend/' || 
         replace(
           lower(
             CASE
               WHEN object_type LIKE '%S'  THEN object_type || 'ES'
               WHEN object_type LIKE '%EX' THEN regexp_replace(object_type, 'EX$', 'ICES', 1, 0, 'i')
               WHEN object_type LIKE '%Y'  THEN regexp_replace(object_type, 'Y$', 'IES', 1, 0, 'i')
               ELSE object_type || 'S'
             END
           ),
           ' ',
           '_'
         ) || '/' || object_name ||
       CASE object_type
         WHEN 'FUNCTION'       THEN '.fnc'
         WHEN 'PACKAGE BODY'   THEN '.pkb'
         WHEN 'PACKAGE'        THEN '.pks'
         WHEN 'PROCEDURE'      THEN '.prc'
         WHEN 'TRIGGER'        THEN '.trg'
         WHEN 'TYPE BODY'      THEN '.tpb'
         WHEN 'TYPE'           THEN '.tps'
         ELSE '.sql'
       END AS file_path
  FROM user_objects
 WHERE 1 = 1
       --These objects are included within other object types:
   AND object_type NOT IN ('INDEX PARTITION','INDEX SUBPARTITION','LOB','LOB PARTITION','TABLE PARTITION','TABLE SUBPARTITION')
       --Ignore system-generated types for collection processing:
   AND NOT (object_type = 'TYPE' AND object_name LIKE 'SYS_PLSQL_%')
       --Ignore system-generated sequences for identity columns:
   AND NOT (object_type = 'SEQUENCE' AND object_name LIKE 'ISEQ$$_%')                      
       --Ignore LOB indices, their DDL is part of the table:
   AND object_name NOT IN (SELECT index_name FROM user_lobs)
       --Ignore nested tables, their DDL is part of their parent table:
   AND object_name NOT IN (SELECT table_name FROM user_nested_tables)
       --Set user specific like filters:
   AND (#LIKE_EXPRESSIONS#)
   AND (#NOT_LIKE_EXPRESSIONS#)
 ORDER BY
       object_type,
       object_name
^'
      ;
      replace_query_like_expressions(
        p_like_list       => p_object_name_like,
        p_not_like_list   => p_object_name_not_like,
        p_column_name     => 'object_name'
      );
      util_setup_dbms_metadata;
      OPEN l_cur FOR l_query;

      util_ilog_stop;
      LOOP
        FETCH l_cur INTO l_rec;
        EXIT WHEN l_cur%notfound;
        util_ilog_start(l_rec.file_path);
        CASE l_rec.object_type
          WHEN 'SEQUENCE' THEN
            l_ddl_files.sequences_(l_ddl_files.sequences_.count + 1) := l_rec.file_path;
          WHEN 'TABLE' THEN
            l_ddl_files.tables_(l_ddl_files.tables_.count + 1) := l_rec.file_path;
          WHEN 'INDEX' THEN
            l_ddl_files.indices_(l_ddl_files.indices_.count + 1) := l_rec.file_path;
          WHEN 'VIEW' THEN
            l_ddl_files.views_(l_ddl_files.views_.count + 1) := l_rec.file_path;
          WHEN 'TYPE_SPEC' THEN
            l_ddl_files.types_(l_ddl_files.types_.count + 1) := l_rec.file_path;
          WHEN 'TYPE_BODY' THEN
            l_ddl_files.type_bodies_(l_ddl_files.type_bodies_.count + 1) := l_rec.file_path;
          WHEN 'TRIGGER' THEN
            l_ddl_files.triggers_(l_ddl_files.triggers_.count + 1) := l_rec.file_path;
          WHEN 'FUNCTION' THEN
            l_ddl_files.functions_(l_ddl_files.functions_.count + 1) := l_rec.file_path;
          WHEN 'PROCEDURE' THEN
            l_ddl_files.procedures_(l_ddl_files.procedures_.count + 1) := l_rec.file_path;
          WHEN 'PACKAGE_SPEC' THEN
            l_ddl_files.packages_(l_ddl_files.packages_.count + 1) := l_rec.file_path;
          WHEN 'PACKAGE_BODY' THEN
            l_ddl_files.package_bodies_(l_ddl_files.package_bodies_.count + 1) := l_rec.file_path;
          ELSE
            l_ddl_files.other_objects_(l_ddl_files.other_objects_.count + 1) := l_rec.file_path;
        END CASE;

        CASE
          WHEN l_rec.object_type = 'VIEW' THEN
            l_contents := ltrim(
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
              ' ' || c_lf
            );

            util_export_files_append(
              p_export_files   => l_export_files,
              p_name           => l_rec.file_path,
              p_contents       => l_contents
            );

          WHEN l_rec.object_type IN (
            'TABLE',
            'INDEX',
            'SEQUENCE'
          ) THEN
            util_setup_dbms_metadata(p_sqlterminator => false);
            l_contents := replace(
              q'^
BEGIN
  FOR i IN (SELECT '{{OBJECT_NAME}}' AS object_name FROM dual 
            MINUS
            SELECT object_name FROM user_objects) LOOP
    EXECUTE IMMEDIATE q'[
--------------------------------------------------------------------------------
^'
              ,
              '{{OBJECT_NAME}}',
              l_rec.object_name
            )
                          || dbms_metadata.get_ddl(
              object_type   => l_rec.object_type,
              name          => l_rec.object_name,
              schema        => l_current_user
            )
                          || replace(
              q'^
--------------------------------------------------------------------------------
    ]';
  END LOOP;
END;
{{SLASH}}

-- Put your ALTER statements below in the same style as before to ensure that
-- the script is restartable.
^'
              ,
              '{{SLASH}}',
              c_slash
            );

            util_export_files_append(
              p_export_files   => l_export_files,
              p_name           => l_rec.file_path,
              p_contents       => l_contents
            );

            util_setup_dbms_metadata(p_sqlterminator => true);
          ELSE
            l_contents := dbms_metadata.get_ddl(
              object_type   => l_rec.object_type,
              name          => l_rec.object_name,
              schema        => l_current_user
            );

            util_export_files_append(
              p_export_files   => l_export_files,
              p_name           => l_rec.file_path,
              p_contents       => l_contents
            );

        END CASE;

        util_ilog_stop;
      END LOOP;

      CLOSE l_cur;
    END process_object_ddl;

    PROCEDURE process_object_grants IS

      TYPE obj_rec_typ IS RECORD (
        grantor       VARCHAR2(128),
        privilege     VARCHAR2(128),
        object_name   VARCHAR2(256),
        file_path     VARCHAR2(512)
      );
      l_rec         obj_rec_typ;
    BEGIN
      util_ilog_start('app_backend/grants:open_cursor');
      l_query := q'^
SELECT DISTINCT 
       p.grantor,
       p.privilege,
       p.table_name as object_name,
       'app_backend/grants/' || p.privilege || '_on_' || p.table_name || '.sql' AS file_path
  FROM user_tab_privs p
  JOIN user_objects o ON p.table_name = o.object_name
 WHERE (#LIKE_EXPRESSIONS#)
   AND (#NOT_LIKE_EXPRESSIONS#)
 ORDER BY 
       privilege,
       object_name
^'
      ;
      replace_query_like_expressions(
        p_like_list       => p_object_name_like,
        p_not_like_list   => p_object_name_not_like,
        p_column_name     => 'o.object_name'
      );
      OPEN l_cur FOR l_query;

      util_ilog_stop;
      LOOP
        FETCH l_cur INTO l_rec;
        EXIT WHEN l_cur%notfound;
        util_ilog_start(l_rec.file_path);
        l_contents                                         := dbms_metadata.get_dependent_ddl(
          'OBJECT_GRANT',
          l_rec.object_name,
          l_rec.grantor
        );
        l_ddl_files.grants_(l_ddl_files.grants_.count + 1) := l_rec.file_path;
        util_export_files_append(
          p_export_files   => l_export_files,
          p_name           => l_rec.file_path,
          p_contents       => l_contents
        );

        util_ilog_stop;
      END LOOP;

      CLOSE l_cur;
    END process_object_grants;

    PROCEDURE process_ref_constraints IS

      TYPE obj_rec_typ IS RECORD (
        table_name        VARCHAR2(256),
        constraint_name   VARCHAR2(256),
        file_path         VARCHAR2(512)
      );
      l_rec             obj_rec_typ;
    BEGIN
      util_ilog_start('app_backend/ref_constraints:open_cursor');
      l_query := q'^
SELECT table_name,
       constraint_name,
       'app_backend/ref_constraints/' || constraint_name || '.sql' AS file_path
  FROM user_constraints
 WHERE constraint_type = 'R'
   AND (#LIKE_EXPRESSIONS#)
   AND (#NOT_LIKE_EXPRESSIONS#)
 ORDER BY 
       table_name,
       constraint_name
^'
      ;
      replace_query_like_expressions(
        p_like_list       => p_object_name_like,
        p_not_like_list   => p_object_name_not_like,
        p_column_name     => 'table_name'
      );
      OPEN l_cur FOR l_query;

      util_ilog_stop;
      LOOP
        FETCH l_cur INTO l_rec;
        EXIT WHEN l_cur%notfound;
        util_ilog_start(l_rec.file_path);
        util_setup_dbms_metadata(p_sqlterminator => false);
        l_contents                                                           := replace(
          q'^
BEGIN
  FOR i IN (SELECT '{{CONSTRAINT_NAME}}' AS constraint_name FROM dual
            MINUS
            SELECT constraint_name FROM user_constraints) LOOP
    EXECUTE IMMEDIATE q'[
--------------------------------------------------------------------------------
^'
          ,
          '{{CONSTRAINT_NAME}}',
          l_rec.constraint_name
        )
                      || dbms_metadata.get_ddl(
          'REF_CONSTRAINT',
          l_rec.constraint_name
        )
                      || replace(
          q'^ 
--------------------------------------------------------------------------------
    ]';
  END LOOP;
END;
{{SLASH}}
^'
          ,
          '{{SLASH}}',
          c_slash
        );

        util_setup_dbms_metadata(p_sqlterminator => true);
        l_ddl_files.ref_constraints_(l_ddl_files.ref_constraints_.count + 1) := l_rec.file_path;
        util_export_files_append(
          p_export_files   => l_export_files,
          p_name           => l_rec.file_path,
          p_contents       => l_contents
        );

        util_ilog_stop;
      END LOOP;

      CLOSE l_cur;
    END process_ref_constraints;

    PROCEDURE create_backend_install_file IS

      FUNCTION get_script_line (
        p_file_path VARCHAR2
      ) RETURN VARCHAR2 IS
      BEGIN
        RETURN 'prompt --'
               || replace(
          p_file_path,
          '.sql',
          NULL
        )
               || c_lf
               || '@'
               || '../'
               || p_file_path
               || c_lf
               || c_lf;
      END get_script_line;

    BEGIN

      
    -- file one
      l_file_path := 'scripts/install_backend_generated_by_plex.sql';
      util_ilog_start(l_file_path);
      util_g_clob_createtemporary;
      util_g_clob_append('/* A T T E N T I O N
DO NOT TOUCH THIS FILE or set the PLEX.BackApp parameter p_include_object_ddl
to false - otherwise your changes would be overwritten on next PLEX.BackApp
call. It is recommended to export your object ddl only ones on initial
repository creation and then start to use the "files first approach".
*/

set define off verify off feedback off
whenever sqlerror exit sql.sqlcode rollback

prompt --install_backend_generated_by_plex

'
      );
      FOR i IN 1..l_ddl_files.sequences_.count LOOP util_g_clob_append(get_script_line(l_ddl_files.sequences_(i)));
      END LOOP;

      FOR i IN 1..l_ddl_files.tables_.count LOOP util_g_clob_append(get_script_line(l_ddl_files.tables_(i)));
      END LOOP;

      FOR i IN 1..l_ddl_files.ref_constraints_.count LOOP util_g_clob_append(get_script_line(l_ddl_files.ref_constraints_(i)));
      END LOOP;

      FOR i IN 1..l_ddl_files.indices_.count LOOP util_g_clob_append(get_script_line(l_ddl_files.indices_(i)));
      END LOOP;

      FOR i IN 1..l_ddl_files.views_.count LOOP util_g_clob_append(get_script_line(l_ddl_files.views_(i)));
      END LOOP;

      FOR i IN 1..l_ddl_files.types_.count LOOP util_g_clob_append(get_script_line(l_ddl_files.types_(i)));
      END LOOP;

      FOR i IN 1..l_ddl_files.type_bodies_.count LOOP util_g_clob_append(get_script_line(l_ddl_files.type_bodies_(i)));
      END LOOP;

      FOR i IN 1..l_ddl_files.triggers_.count LOOP util_g_clob_append(get_script_line(l_ddl_files.triggers_(i)));
      END LOOP;

      FOR i IN 1..l_ddl_files.functions_.count LOOP util_g_clob_append(get_script_line(l_ddl_files.functions_(i)));
      END LOOP;

      FOR i IN 1..l_ddl_files.procedures_.count LOOP util_g_clob_append(get_script_line(l_ddl_files.procedures_(i)));
      END LOOP;

      FOR i IN 1..l_ddl_files.packages_.count LOOP util_g_clob_append(get_script_line(l_ddl_files.packages_(i)));
      END LOOP;

      FOR i IN 1..l_ddl_files.package_bodies_.count LOOP util_g_clob_append(get_script_line(l_ddl_files.package_bodies_(i)));
      END LOOP;

      FOR i IN 1..l_ddl_files.grants_.count LOOP util_g_clob_append(get_script_line(l_ddl_files.grants_(i)));
      END LOOP;

      FOR i IN 1..l_ddl_files.other_objects_.count LOOP util_g_clob_append(get_script_line(l_ddl_files.other_objects_(i)));
      END LOOP;

      util_g_clob_flush_cache;
      util_export_files_append(
        p_export_files   => l_export_files,
        p_name           => l_file_path,
        p_contents       => g_clob
      );
      util_g_clob_freetemporary;
      util_ilog_stop;
    END create_backend_install_file;

    PROCEDURE process_data IS

      TYPE obj_rec_typ IS RECORD (
        table_name   VARCHAR2(256),
        pk_columns   VARCHAR2(4000)
      );
      l_rec        obj_rec_typ;
    BEGIN
      util_ilog_start('app_data/open_tables_cursor');
      l_query            := q'^
SELECT table_name,
       (SELECT LISTAGG(column_name, ', ') WITHIN GROUP(ORDER BY position)
          FROM user_cons_columns
         WHERE constraint_name = (SELECT constraint_name
                                    FROM user_constraints c
                                   WHERE constraint_type = 'P'
                                     AND c.table_name = t.table_name)
       ) AS pk_columns
  FROM user_tables t
 WHERE table_name IN (SELECT table_name FROM user_tables
                       MINUS
                      SELECT table_name FROM user_external_tables)
   AND (#LIKE_EXPRESSIONS#)
   AND (#NOT_LIKE_EXPRESSIONS#)
 ORDER BY 
       table_name
^'
      ;
      replace_query_like_expressions(
        p_like_list       => p_data_table_name_like,
        p_not_like_list   => p_data_table_name_not_like,
        p_column_name     => 'table_name'
      );
      OPEN l_cur FOR l_query;

      util_ilog_stop;
      util_ilog_start('app_data/get_scn');
      l_data_timestamp   := util_calc_data_timestamp(nvl(
        p_data_as_of_minutes_ago,
        0
      ));
      l_data_scn         := timestamp_to_scn(l_data_timestamp);
      util_ilog_stop;
      LOOP
        FETCH l_cur INTO l_rec;
        EXIT WHEN l_cur%notfound;
        l_file_path := 'app_data/'
                       || l_rec.table_name
                       || '.csv';
        util_ilog_start(l_file_path);
        util_g_clob_createtemporary;
        util_g_clob_query_to_csv(
          p_query      => 'SELECT * FROM '
                     || l_rec.table_name
                     || ' AS OF SCN '
                     || l_data_scn
                     || CASE
            WHEN l_rec.pk_columns IS NOT NULL THEN
              ' ORDER BY ' || l_rec.pk_columns
            ELSE NULL
          END,
          p_max_rows   => p_data_max_rows
        );

        util_g_clob_flush_cache;
        util_export_files_append(
          p_export_files   => l_export_files,
          p_name           => l_file_path,
          p_contents       => g_clob
        );
        util_g_clob_freetemporary;
        util_ilog_stop;
      END LOOP;

      CLOSE l_cur;
    END process_data;

    PROCEDURE create_template_files IS
      l_file_template VARCHAR2(32767 CHAR);
    BEGIN
      l_file_template   := q'^
Your Global README File
=======================
      
It is a good practice to have a README file in the root of your project with
a high level overview of your application. Put the more detailed docs in the 
docs folder.

You can start with a copy of this file. Rename it to README.md and try to use
Markdown when writing your content - this has many benefits and you don't waist
time by formatting your docs. If you are unsure have a look at some projects at
[Github](https://github.com) or any other code hosting platform.

Depending on your options when calling `plex.backapp` these files are generated
for you:

- scripts/install_backend_generated_by_plex.sql
- scripts/install_frontend_generated_by_apex.sql

Do not touch these generated install files. They will be overwritten on each 
plex call. Depending on your call parameters it would be ok to modify the file
install_backend_generated_by_plex - especially when you follow the files first 
approach and export your schema DDL only ones to have a starting point for you
repository.

If you need to do modifications for the install process then have a look at the
following templates - they call the generated files and you can do your own
stuff before or after the calls.

- scripts/templates/1_export_app_from_DEV.bat
- scripts/templates/2_install_app_into_TEST.bat
- scripts/templates/3_install_app_into_PROD.bat
- scripts/templates/export_app_custom_code.sql
- scripts/templates/install_app_custom_code.sql

If you want to use these files please make a copy into the scripts directory
and modify it to your needs. Doing it this way your changes are overwrite save.

[Feedback is welcome]({{PLEX_URL}}/issues/new)
^'
      ;
      l_file_path       := 'plex_README.md';
      util_ilog_start(l_file_path);
      util_export_files_append(
        p_export_files   => l_export_files,
        p_name           => l_file_path,
        p_contents       => replace(
          l_file_template,
          '{{PLEX_URL}}',
          c_plex_url
        )
      );

      util_ilog_stop;
      l_file_template   := q'^
rem Template generated by PLEX version {{PLEX_VERSION}}
rem More infos here: {{PLEX_URL}}

{{AT}}echo off
setlocal
set "areyousure=N"

rem ### BEGIN CONFIG ###########################################################
rem Align delimiters to your operating system locale:
for /f "tokens=1-3 delims=. " %%a in ("%DATE%") do (set "mydate=%%c%%b%%a")
for /f "tokens=1-3 delims=:." %%a in ("%TIME: =0%") do (set "mytime=%%a%%b%%c")
set "systemrole={{SYSTEMROLE}}"
set "connection=localhost:1521/orcl"
set "scriptfile={{SCRIPTFILE}}"
set "app_id={{APP_ID}}"
set "app_alias={{APP_ALIAS}}"
set "app_schema={{APP_OWNER}}"
set "app_workspace={{APP_WORKSPACE}}"
set "logfile={{LOGFILE}}"
rem ### END CONFIG #############################################################

:PROMPT
echo.
echo.
set /p "areyousure=Run %scriptfile% on %app_schema%@%systemrole%(%connection%) [Y/N]? " || set "areyousure=N"
if /i %areyousure% neq y goto END
set NLS_LANG=AMERICAN_AMERICA.UTF8
set /p "password=Please enter password for %app_schema% [default = oracle]: " || set "password=oracle"
echo This is the runlog for %scriptfile% on %app_schema%@%systemrole%(%connection%) > %logfile%
echo exit | sqlplus -S %app_schema%/%password%@%connection% ^
  {{AT}}%scriptfile% ^
  %logfile% ^
  %app_id% ^
  %app_alias% ^
  %app_schema% ^
  %app_workspace%

if %errorlevel% neq 0 echo ERROR: SQL script finished with return code %errorlevel% :-( >> %logfile%
if %errorlevel% neq 0 echo ERROR: SQL script finished with return code %errorlevel% :-(

:END
rem Remove "pause" for fully automated setup:
pause
if %errorlevel% neq 0 exit /b %errorlevel%
^'
      ;
      l_file_path       := 'scripts/templates/1_export_app_from_DEV.bat';
      util_ilog_start(l_file_path);
      util_export_files_append(
        p_export_files   => l_export_files,
        p_name           => l_file_path,
        p_contents       => util_multi_replace(
          l_file_template,
          '{{PLEX_VERSION}}',
          c_plex_version,
          '{{PLEX_URL}}',
          c_plex_url,
          '{{SYSTEMROLE}}',
          'DEV',
        $if $$apex_exists $then

          '{{APP_ID}}',
          p_app_id,
          '{{APP_ALIAS}}',
          l_app_alias,
          '{{APP_OWNER}}',
          l_app_owner,
          '{{APP_WORKSPACE}}',
          l_app_workspace,
        $end
          '{{SCRIPTFILE}}',
          'export_app_custom_code.sql',
          '{{LOGFILE}}',
          'logs/export_app_%app_id%_from_%app_schema%_at_%systemrole%_%mydate%_%mytime%.log',
          '{{AT}}',
          c_at
        )
      );

      util_ilog_stop;

      --
      l_file_path       := 'scripts/templates/2_install_app_into_TEST.bat';
      util_ilog_start(l_file_path);
      util_export_files_append(
        p_export_files   => l_export_files,
        p_name           => l_file_path,
        p_contents       => util_multi_replace(
          l_file_template,
          '{{PLEX_VERSION}}',
          c_plex_version,
          '{{PLEX_URL}}',
          c_plex_url,
          '{{SYSTEMROLE}}',
          'TEST',
        $if $$apex_exists $then

          '{{APP_ID}}',
          p_app_id,
          '{{APP_ALIAS}}',
          l_app_alias,
          '{{APP_OWNER}}',
          l_app_owner,
          '{{APP_WORKSPACE}}',
          l_app_workspace,
        $end
          '{{SCRIPTFILE}}',
          'install_app_custom_code.sql',
          '{{LOGFILE}}',
          'logs/install_app_%app_id%_into_%app_schema%_at_%systemrole%_%mydate%_%mytime%.log',
          '{{AT}}',
          c_at
        )
      );

      util_ilog_stop;

      --
      l_file_path       := 'scripts/templates/3_install_app_into_PROD.bat';
      util_ilog_start(l_file_path);
      util_export_files_append(
        p_export_files   => l_export_files,
        p_name           => l_file_path,
        p_contents       => util_multi_replace(
          l_file_template,
          '{{PLEX_VERSION}}',
          c_plex_version,
          '{{PLEX_URL}}',
          c_plex_url,
          '{{SYSTEMROLE}}',
          'PROD',
        $if $$apex_exists $then

          '{{APP_ID}}',
          p_app_id,
          '{{APP_ALIAS}}',
          l_app_alias,
          '{{APP_OWNER}}',
          l_app_owner,
          '{{APP_WORKSPACE}}',
          l_app_workspace,
        $end
          '{{SCRIPTFILE}}',
          'install_app_custom_code.sql',
          '{{LOGFILE}}',
          'logs/install_app_%app_id%_into_%app_schema%_at_%systemrole%_%mydate%_%mytime%.log',
          '{{AT}}',
          c_at
        )
      );

      util_ilog_stop;

      --
      l_file_template   := q'^
-- Template generated by PLEX version {{PLEX_VERSION}}
-- More infos here: {{PLEX_URL}}

set verify off feedback off heading off 
set trimout on trimspool on pagesize 0 linesize 5000 long 100000000 longchunksize 32767
whenever sqlerror exit sql.sqlcode rollback
-- whenever oserror exit failure rollback
define logfile = "&1"
spool "&logfile" append
variable app_id        varchar2(100)
variable app_alias     varchar2(100)
variable app_schema    varchar2(100)
variable app_workspace varchar2(100)
begin
  :app_id        := &2;
  :app_alias     := '&3';
  :app_schema    := '&4';
  :app_workspace := '&5';
end;
{{SLASH}}


prompt
prompt Start Export
prompt =========================================================================
prompt Create global temporary table temp_export_files if not exist
BEGIN
  FOR i IN (SELECT 'TEMP_EXPORT_FILES' AS object_name FROM dual 
            MINUS
            SELECT object_name FROM user_objects) LOOP
    EXECUTE IMMEDIATE '
--------------------------------------------------------------------------------
CREATE GLOBAL TEMPORARY TABLE temp_export_files (
  name       VARCHAR2(255),
  contents   CLOB
) ON COMMIT DELETE ROWS
--------------------------------------------------------------------------------
    ';
  END LOOP;
END;
{{SLASH}}


prompt Do the app export, relocate files and save to temporary table
prompt ATTENTION: Depending on your options this could take some time ...
DECLARE
  l_files   tab_export_files;
BEGIN
  l_files   := plex.backapp (
  -- These are the defaults - align it to your needs:^'
      ;
$if $$apex_exists $then

      l_file_template   := l_file_template || q'^
  p_app_id                    => :app_id,
  p_app_date                  => true,
  p_app_public_reports        => true,
  p_app_private_reports       => false,
  p_app_notifications         => false,
  p_app_translations          => true,
  p_app_pkg_app_mapping       => false,
  p_app_original_ids          => true,
  p_app_subscriptions         => true,
  p_app_comments              => true,
  p_app_supporting_objects    => null,
  p_app_include_single_file   => false,
  p_app_build_status_run_only => false,^'
      ;
$end
      l_file_template   := l_file_template || q'^
  p_include_object_ddl        => true,
  p_object_name_like          => null,
  p_object_name_not_like      => null,

  p_include_data              => false,
  p_data_as_of_minutes_ago    => 0,
  p_data_max_rows             => 1000,
  p_data_table_name_like      => null,
  p_data_table_name_not_like  => null,

  p_include_templates         => true,
  p_include_runtime_log       => true );

  -- relocate files to own project structure, we are inside the scripts folder
  FOR i IN 1..l_files.count LOOP
    l_files(i).name := '../' || l_files(i).name; 
  END LOOP;
  
  FORALL i IN 1..l_files.count
    INSERT INTO temp_export_files VALUES (
      l_files(i).name,
      l_files(i).contents
    );
END;
{{SLASH}}


prompt Create intermediate script file to unload the table contents into files
spool off
set termout off serveroutput on
spool "logs/temp_export_files.sql"
BEGIN
  -- create host commands for the needed directories (spool does not create missing directories)
  FOR i IN (
    WITH t AS (
      SELECT regexp_substr(name, '^((\w|\.)+\/)+' /*path without file name*/) AS dir
        FROM temp_export_files
    )
    SELECT DISTINCT
           dir,
          -- This is for Windows to create a directory and suppress warning if it exist.
          -- Align the command to your operating system:
          'host mkdir "' || replace(dir,'/','\') || '" 2>NUL' AS mkdir
      FROM t
     WHERE dir IS NOT NULL 
  ) LOOP
    dbms_output.put_line('set termout on');
    dbms_output.put_line('spool "&logfile." append');
    dbms_output.put_line('prompt --create directory if not exist: ' || i.dir);
    dbms_output.put_line('spool off');
    dbms_output.put_line('set termout off');
    dbms_output.put_line(i.mkdir);
    dbms_output.put_line('-----');
  END LOOP;

  -- create the spool calls for unload the files
  FOR i IN (SELECT * FROM temp_export_files) LOOP
    dbms_output.put_line('set termout on');
    dbms_output.put_line('spool "&logfile." append');
    dbms_output.put_line('prompt --' || i.name);
    dbms_output.put_line('spool off');
    dbms_output.put_line('set termout off');
    dbms_output.put_line('spool "' || i.name || '"');
    dbms_output.put_line('select contents from temp_export_files where name = ''' || i.name || ''';');
    dbms_output.put_line('spool off');
    dbms_output.put_line('-----');
  END LOOP;
 
END;
{{SLASH}}
spool off
set termout on serveroutput off
spool "&logfile." append


prompt Call the intermediate script file to save the files
spool off
{{AT}}logs/temp_export_files.sql
set termout on serveroutput off
spool "&logfile." append

prompt Delete files from the global temporary table
COMMIT;


prompt =========================================================================
prompt Export DONE :-) 
prompt
^'
      ;
      l_file_path       := 'scripts/templates/export_app_custom_code.sql';
      util_ilog_start(l_file_path);
      util_export_files_append(
        p_export_files   => l_export_files,
        p_name           => l_file_path,
        p_contents       => util_multi_replace(
          l_file_template,
          '{{PLEX_VERSION}}',
          c_plex_version,
          '{{PLEX_URL}}',
          c_plex_url,
          '{{SLASH}}',
          '/',
          '{{AT}}',
          c_at
        )
      );

      util_ilog_stop;

      --
      l_file_template   := q'^
-- Template generated by PLEX version {{PLEX_VERSION}}
-- More infos here: {{PLEX_URL}}

set define on verify off feedback off
whenever sqlerror exit sql.sqlcode rollback
-- whenever oserror exit failure rollback
define logfile = "&1"
spool "&logfile" append
variable app_id        varchar2(100)
variable app_alias     varchar2(100)
variable app_schema    varchar2(100)
variable app_workspace varchar2(100)
begin
  :app_id        := &2;
  :app_alias     := '&3';
  :app_schema    := '&4';
  :app_workspace := '&5';
end;
{{SLASH}}
set define off


prompt 
prompt Start Installation
prompt =========================================================================
prompt Start backend installation


prompt Call PLEX backend install script
{{AT}}install_backend_generated_by_plex.sql


prompt Compile invalid objects
BEGIN
  dbms_utility.compile_schema(
    schema           => user,
    compile_all      => false,
    reuse_settings   => true
  );
END;
{{SLASH}}


prompt Check invalid objects
DECLARE
  v_count   PLS_INTEGER;
  v_objects VARCHAR2(4000);
BEGIN
  SELECT COUNT(*),
         listagg(object_name,
                 ', ') within GROUP(ORDER BY object_name)
    INTO v_count,
         v_objects
    FROM user_objects
   WHERE status = 'INVALID';
  IF v_count > 0
  THEN
    raise_application_error(-20000,
                            'Found ' || v_count || ' invalid object' || CASE
                              WHEN v_count > 1 THEN
                               's'
                            END || ' :-( ' || v_objects);
  END IF;
END;
{{SLASH}}


prompt Start frontend installation
BEGIN
   apex_application_install.set_workspace_id( APEX_UTIL.find_security_group_id( :app_workspace ) );
   apex_application_install.set_application_alias( :app_alias );
   apex_application_install.set_application_id( :app_id );
   apex_application_install.set_schema( :app_schema );
   apex_application_install.generate_offset;
END;
{{SLASH}}


prompt Call APEX frontend install script
{{AT}}install_frontend_generated_by_APEX.sql


prompt =========================================================================
prompt Installation DONE :-)
prompt
^'
      ;
      l_file_path       := 'scripts/templates/install_app_custom_code.sql';
      util_ilog_start(l_file_path);
      util_export_files_append(
        p_export_files   => l_export_files,
        p_name           => l_file_path,
        p_contents       => util_multi_replace(
          l_file_template,
          '{{PLEX_VERSION}}',
          c_plex_version,
          '{{PLEX_URL}}',
          c_plex_url,
          '{{SLASH}}',
          '/',
          '{{AT}}',
          c_at
        )
      );

      util_ilog_stop;
    END create_template_files;

      --

    PROCEDURE create_directory_keepers IS
      l_the_point VARCHAR2(30) := '. < this is the point ;-)';
    BEGIN
      l_file_path   := 'docs/_save_your_docs_here.txt';
      util_ilog_start(l_file_path);
      util_export_files_append(
        p_export_files   => l_export_files,
        p_name           => l_file_path,
        p_contents       => l_the_point
      );
      util_ilog_stop;

      --
      l_file_path   := 'scripts/logs/_spool_your_script_logs_here.txt';
      util_ilog_start(l_file_path);
      util_export_files_append(
        p_export_files   => l_export_files,
        p_name           => l_file_path,
        p_contents       => l_the_point
      );
      util_ilog_stop;

      --
      l_file_path   := 'tests/_save_your_tests_here.txt';
      util_ilog_start(l_file_path);
      util_export_files_append(
        p_export_files   => l_export_files,
        p_name           => l_file_path,
        p_contents       => l_the_point
      );
      util_ilog_stop;
    END create_directory_keepers;

    PROCEDURE finish IS
    BEGIN
      util_ilog_exit;
    --
      IF p_include_runtime_log THEN
        util_g_clob_createtemporary;
        util_g_clob_create_runtime_log;
        util_g_clob_flush_cache;
        util_export_files_append(
          p_export_files   => l_export_files,
          p_name           => 'plex_backapp_log.md',
          p_contents       => g_clob
        );
        util_g_clob_freetemporary;
      END IF;

    END;

  BEGIN
    init;
  $if $$apex_exists $then

    check_owner;
    --
    IF p_app_id IS NOT NULL THEN
      process_apex_app;
    ELSE
    $end
      l_export_files := NEW tab_export_files();
    $if $$apex_exists $then

    END IF;
    $end
    --

    IF p_include_object_ddl THEN
      process_user_ddl;
      process_object_ddl;
      process_object_grants;
      process_ref_constraints;
      create_backend_install_file;
    END IF;
    --
    IF p_include_data THEN
      process_data;
    END IF;
    --
    IF p_include_templates THEN
      create_template_files;
    END IF;
    --
    create_directory_keepers;
    --
    finish;
    --
    RETURN l_export_files;
  END backapp;

  PROCEDURE add_query (
    p_query       VARCHAR2,
    p_file_name   VARCHAR2,
    p_max_rows    NUMBER DEFAULT 1000
  ) IS
    l_index PLS_INTEGER;
  BEGIN
    l_index                        := g_queries.count + 1;
    g_queries(l_index).query       := p_query;
    g_queries(l_index).file_name   := p_file_name;
    g_queries(l_index).max_rows    := p_max_rows;
  END add_query;

  FUNCTION queries_to_csv (
    p_delimiter             IN                      VARCHAR2 DEFAULT ',',
    p_quote_mark            IN                      VARCHAR2 DEFAULT '"',
    p_header_prefix         IN                      VARCHAR2 DEFAULT NULL,
    p_include_runtime_log   IN                      BOOLEAN DEFAULT true
  ) RETURN tab_export_files IS

    l_export_files tab_export_files;

    PROCEDURE init IS
    BEGIN
      l_export_files := NEW tab_export_files();
      IF g_queries.count = 0 THEN
        raise_application_error(
          -20201,
          'You need first to add queries by using plex.add_query. Calling plex.queries_to_csv clears the global queries array for subsequent processing.'
        );
      END IF;
      util_ilog_init(
        p_module                => 'plex.queries_to_csv',
        p_include_runtime_log   => p_include_runtime_log
      );
    END init;

    PROCEDURE process_queries IS
    BEGIN
      FOR i IN g_queries.first..g_queries.last LOOP
        util_ilog_start('process_query:'
                        || TO_CHAR(i)
                        || ':'
                        || g_queries(i).file_name);

        util_g_clob_createtemporary;
        util_g_clob_query_to_csv(
          p_query           => g_queries(i).query,
          p_max_rows        => g_queries(i).max_rows,
          p_delimiter       => p_delimiter,
          p_quote_mark      => p_quote_mark,
          p_header_prefix   => p_header_prefix
        );

        util_g_clob_flush_cache;
        util_export_files_append(
          p_export_files   => l_export_files,
          p_name           => g_queries(i).file_name
                    || '.csv',
          p_contents       => g_clob
        );

        util_g_clob_freetemporary;
        util_ilog_stop;
      END LOOP;
    END process_queries;

    PROCEDURE finish IS
    BEGIN
      g_queries.DELETE;
      util_ilog_exit;
      IF p_include_runtime_log THEN
        util_g_clob_createtemporary;
        util_g_clob_create_runtime_log;
        util_g_clob_flush_cache;
        util_export_files_append(
          p_export_files   => l_export_files,
          p_name           => 'plex_queries_to_csv_log.md',
          p_contents       => g_clob
        );
        util_g_clob_freetemporary;
      END IF;

    END finish;

  BEGIN
    init;
    process_queries;
    finish;
    RETURN l_export_files;
  END queries_to_csv;

  FUNCTION to_zip (
    p_file_collection IN tab_export_files
  ) RETURN BLOB IS
    l_zip BLOB;
  BEGIN
    dbms_lob.createtemporary(
      l_zip,
      true
    );
    FOR i IN 1..p_file_collection.count LOOP apex_zip.add_file(
      p_zipped_blob   => l_zip,
      p_file_name     => p_file_collection(i).name,
      p_content       => util_clob_to_blob(p_file_collection(i).contents)
    );
    END LOOP;

    apex_zip.finish(l_zip);
    RETURN l_zip;
  END to_zip;

  FUNCTION view_runtime_log RETURN tab_runtime_log
    PIPELINED
  IS
    v_return rec_runtime_log;
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