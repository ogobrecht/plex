CREATE OR REPLACE PACKAGE BODY plex IS

--------------------------------------------------------------------------------------------------------------------------------
-- CONSTANTS, TYPES
--------------------------------------------------------------------------------------------------------------------------------

c_tab                          CONSTANT VARCHAR2(1) := chr(9);
c_cr                           CONSTANT VARCHAR2(1) := chr(13);
c_lf                           CONSTANT VARCHAR2(1) := chr(10);
c_crlf                         CONSTANT VARCHAR2(2) := chr(13) || chr(10);
c_at                           CONSTANT VARCHAR2(1) := '@';
c_hash                         CONSTANT VARCHAR2(1) := '#';
c_slash                        CONSTANT VARCHAR2(1) := '/';
c_vc2_max_size                 CONSTANT PLS_INTEGER := 32767;
c_zip_local_file_header        CONSTANT RAW(4) := hextoraw('504B0304');
c_zip_end_of_central_directory CONSTANT RAW(4) := hextoraw('504B0506');

TYPE tab_errlog IS TABLE OF rec_error_log INDEX BY BINARY_INTEGER;

TYPE rec_runlog_step IS RECORD (
  action     app_info_text,
  start_time TIMESTAMP(6),
  stop_time  TIMESTAMP(6),
  elapsed    NUMBER,
  execution  NUMBER);
TYPE tab_runlog_step IS TABLE OF rec_runlog_step INDEX BY BINARY_INTEGER;

TYPE rec_runlog IS RECORD (
  module          app_info_text,
  start_time      TIMESTAMP(6),
  stop_time       TIMESTAMP(6),
  run_time        NUMBER,
  measured_time   NUMBER,
  unmeasured_time NUMBER,
  data            tab_runlog_step);
TYPE rec_queries IS RECORD (--
  query       VARCHAR2(32767 CHAR),
  file_name   VARCHAR2(256 CHAR),
  max_rows    NUMBER DEFAULT 100000);
TYPE tab_queries IS TABLE OF rec_queries INDEX BY BINARY_INTEGER;

TYPE tab_file_list_lookup IS TABLE OF PLS_INTEGER INDEX BY VARCHAR2(256);

TYPE rec_ddl_files IS RECORD (
  ords_modules_    tab_vc1k,
  sequences_       tab_vc1k,
  tables_          tab_vc1k,
  ref_constraints_ tab_vc1k,
  indices_         tab_vc1k,
  views_           tab_vc1k,
  types_           tab_vc1k,
  type_bodies_     tab_vc1k,
  triggers_        tab_vc1k,
  functions_       tab_vc1k,
  procedures_      tab_vc1k,
  packages_        tab_vc1k,
  package_bodies_  tab_vc1k,
  grants_          tab_vc1k,
  other_objects_   tab_vc1k);


-- GLOBAL VARIABLES
g_clob          CLOB;
g_clob_vc_cache VARCHAR2(32767char);
g_errlog        tab_errlog;
g_runlog        rec_runlog;
g_queries       tab_queries;



--------------------------------------------------------------------------------------------------------------------------------
-- UTILITIES (forward declarations, only compiled when not public)
--------------------------------------------------------------------------------------------------------------------------------

$if not $$utils_public $then
FUNCTION util_bool_to_string (p_bool IN BOOLEAN) RETURN VARCHAR2;

FUNCTION util_string_to_bool (
  p_bool_string IN VARCHAR2,
  p_default     IN BOOLEAN)
RETURN BOOLEAN;

FUNCTION util_split (
  p_string    IN VARCHAR2,
  p_delimiter IN VARCHAR2 DEFAULT ',')
RETURN tab_vc32k;

FUNCTION util_join (
  p_array     IN tab_vc32k,
  p_delimiter IN VARCHAR2 DEFAULT ',')
RETURN VARCHAR2;

FUNCTION util_clob_to_blob (p_clob CLOB) RETURN BLOB;

/*
ZIP UTILS
- The following four zip utilities are copied from this article:
    - Blog: https://technology.amis.nl/2010/03/13/utl_compress-gzip-and-zlib/
    - Source: https://technology.amis.nl/wp-content/uploads/2010/06/as_zip10.txt
- Copyright (c) 2010, 2011 by Anton Scheffer (MIT license)
- Thank you for sharing this Anton :-)
*/
FUNCTION util_zip_blob_to_num (
  p_blob IN BLOB,
  p_len  IN INTEGER,
  p_pos  IN INTEGER)
RETURN NUMBER;

FUNCTION util_zip_little_endian (
  p_big   IN NUMBER,
  p_bytes IN PLS_INTEGER := 4)
RETURN RAW;

PROCEDURE util_zip_add_file (
  p_zipped_blob IN OUT BLOB,
  p_name        IN     VARCHAR2,
  p_content     IN     BLOB);

PROCEDURE util_zip_finish (p_zipped_blob IN OUT BLOB);

FUNCTION util_multi_replace (
  p_source_string VARCHAR2,
  p_01_find VARCHAR2 DEFAULT NULL, p_01_replace VARCHAR2 DEFAULT NULL,
  p_02_find VARCHAR2 DEFAULT NULL, p_02_replace VARCHAR2 DEFAULT NULL,
  p_03_find VARCHAR2 DEFAULT NULL, p_03_replace VARCHAR2 DEFAULT NULL,
  p_04_find VARCHAR2 DEFAULT NULL, p_04_replace VARCHAR2 DEFAULT NULL,
  p_05_find VARCHAR2 DEFAULT NULL, p_05_replace VARCHAR2 DEFAULT NULL,
  p_06_find VARCHAR2 DEFAULT NULL, p_06_replace VARCHAR2 DEFAULT NULL,
  p_07_find VARCHAR2 DEFAULT NULL, p_07_replace VARCHAR2 DEFAULT NULL,
  p_08_find VARCHAR2 DEFAULT NULL, p_08_replace VARCHAR2 DEFAULT NULL,
  p_09_find VARCHAR2 DEFAULT NULL, p_09_replace VARCHAR2 DEFAULT NULL,
  p_10_find VARCHAR2 DEFAULT NULL, p_10_replace VARCHAR2 DEFAULT NULL,
  p_11_find VARCHAR2 DEFAULT NULL, p_11_replace VARCHAR2 DEFAULT NULL,
  p_12_find VARCHAR2 DEFAULT NULL, p_12_replace VARCHAR2 DEFAULT NULL)
RETURN VARCHAR2;

FUNCTION util_set_build_status_run_only (p_app_export_sql IN CLOB) RETURN CLOB;

FUNCTION util_calc_data_timestamp (p_as_of_minutes_ago IN NUMBER) RETURN TIMESTAMP;

PROCEDURE util_setup_dbms_metadata (
  p_pretty               IN BOOLEAN DEFAULT true,
  p_constraints          IN BOOLEAN DEFAULT true,
  p_ref_constraints      IN BOOLEAN DEFAULT false,
  p_partitioning         IN BOOLEAN DEFAULT true,
  p_tablespace           IN BOOLEAN DEFAULT false,
  p_storage              IN BOOLEAN DEFAULT false,
  p_segment_attributes   IN BOOLEAN DEFAULT false,
  p_sqlterminator        IN BOOLEAN DEFAULT true,
  p_constraints_as_alter IN BOOLEAN DEFAULT false,
  p_emit_schema          IN BOOLEAN DEFAULT false);

--------------------------------------------------------------------------------------------------------------------------------
-- The following tools are working on the global private package variables g_clob, g_clob_varchar_cache, g_runlog and g_queries
--------------------------------------------------------------------------------------------------------------------------------

PROCEDURE util_clob_append (p_content IN VARCHAR2);

PROCEDURE util_clob_append (p_content IN CLOB);

PROCEDURE util_clob_flush_cache;

PROCEDURE util_clob_add_to_export_files (
  p_export_files IN OUT NOCOPY tab_export_files,
  p_name IN VARCHAR2);

PROCEDURE util_clob_query_to_csv (
  p_query         IN VARCHAR2,
  p_max_rows      IN NUMBER DEFAULT 1000,
  p_delimiter     IN VARCHAR2 DEFAULT ',',
  p_quote_mark    IN VARCHAR2 DEFAULT '"',
  p_header_prefix IN VARCHAR2 DEFAULT NULL);

PROCEDURE util_clob_create_runtime_log (p_export_files IN OUT NOCOPY tab_export_files);

PROCEDURE util_clob_create_error_log (p_export_files IN OUT NOCOPY tab_export_files);

PROCEDURE util_ensure_unique_file_names (p_export_files IN OUT tab_export_files);

PROCEDURE util_log_init (p_module IN VARCHAR2);

PROCEDURE util_log_start (p_action IN VARCHAR2);

PROCEDURE util_log_error (p_name VARCHAR2);

PROCEDURE util_log_stop;

FUNCTION util_log_get_runtime (
  p_start IN TIMESTAMP,
  p_stop  IN TIMESTAMP)
RETURN NUMBER;

PROCEDURE util_log_calc_runtimes;

$end



--------------------------------------------------------------------------------------------------------------------------------
-- UTILITIES MAIN CODE
--------------------------------------------------------------------------------------------------------------------------------

FUNCTION util_bool_to_string (p_bool IN BOOLEAN) RETURN VARCHAR2 IS
BEGIN
  RETURN CASE WHEN p_bool THEN 'TRUE' ELSE 'FALSE' END;
END util_bool_to_string;

--------------------------------------------------------------------------------------------------------------------------------

FUNCTION util_string_to_bool (
  p_bool_string IN VARCHAR2,
  p_default     IN BOOLEAN)
RETURN BOOLEAN IS
  v_bool_string VARCHAR2(1 CHAR);
  v_return      BOOLEAN;
BEGIN
  v_bool_string := upper(substr(p_bool_string, 1, 1));
  v_return :=
    CASE
      WHEN v_bool_string IN ('1', 'Y', 'T') THEN
        true
      WHEN v_bool_string IN ('0', 'N', 'F') THEN
        false
      ELSE p_default
    END;
  RETURN v_return;
END util_string_to_bool;

--------------------------------------------------------------------------------------------------------------------------------

FUNCTION util_split (
  p_string    IN VARCHAR2,
  p_delimiter IN VARCHAR2 DEFAULT ',')
RETURN tab_vc32k IS
  v_return           tab_vc32k            := tab_vc32k();
  v_offset           PLS_INTEGER          := 1;
  v_index            PLS_INTEGER          := instr(p_string, p_delimiter, v_offset);
  v_delimiter_length PLS_INTEGER          := length(p_delimiter);
  v_string_length    CONSTANT PLS_INTEGER := length(p_string);
  v_count            PLS_INTEGER          := 1;

  PROCEDURE add_value (p_value VARCHAR2) IS
  BEGIN
    v_return.extend;
    v_return(v_count) := p_value;
    v_count           := v_count + 1;
  END add_value;

BEGIN
  WHILE v_index > 0 LOOP
    add_value(trim(substr(p_string, v_offset, v_index - v_offset)));
    v_offset := v_index + v_delimiter_length;
    v_index  := instr(p_string, p_delimiter, v_offset);
  END LOOP;
  IF v_string_length - v_offset + 1 > 0 THEN
    add_value(trim(substr(p_string, v_offset, v_string_length - v_offset + 1)));
  END IF;
  RETURN v_return;
END util_split;

--------------------------------------------------------------------------------------------------------------------------------

FUNCTION util_join (
  p_array     IN tab_vc32k,
  p_delimiter IN VARCHAR2 DEFAULT ',')
RETURN VARCHAR2 IS
  v_return VARCHAR2(32767);
BEGIN
  IF p_array IS NOT NULL AND p_array.count > 0 THEN
    v_return := p_array(1);
    FOR i IN 2 ..p_array.count LOOP
      v_return := v_return || p_delimiter || p_array(i);
    END LOOP;
  END IF;
  RETURN v_return;
EXCEPTION
  WHEN value_error THEN
    RETURN v_return;
END util_join;

--------------------------------------------------------------------------------------------------------------------------------

FUNCTION util_clob_to_blob (p_clob CLOB) RETURN BLOB IS
  v_blob         BLOB;
  v_lang_context INTEGER := dbms_lob.default_lang_ctx;
  v_warning      INTEGER := dbms_lob.warn_inconvertible_char;
  v_dest_offset  INTEGER := 1;
  v_src_offset   INTEGER := 1;
BEGIN
  IF p_clob IS NOT NULL THEN
    dbms_lob.createtemporary(v_blob, true);
    dbms_lob.converttoblob(
      dest_lob     => v_blob,
      src_clob     => p_clob,
      amount       => dbms_lob.lobmaxsize,
      dest_offset  => v_dest_offset,
      src_offset   => v_src_offset,
      blob_csid    => nls_charset_id('AL32UTF8'),
      lang_context => v_lang_context,
      warning      => v_warning);
  END IF;
  RETURN v_blob;
END util_clob_to_blob;

--------------------------------------------------------------------------------------------------------------------------------

-- copyright by Anton Scheffer (MIT license, see https://technology.amis.nl/2010/03/13/utl_compress-gzip-and-zlib/)
FUNCTION util_zip_blob_to_num (
  p_blob IN BLOB,
  p_len  IN INTEGER,
  p_pos  IN INTEGER)
RETURN NUMBER IS
  rv NUMBER;
BEGIN
  rv := utl_raw.cast_to_binary_integer(
    dbms_lob.substr(p_blob, p_len, p_pos),
    utl_raw.little_endian);
  IF rv < 0 THEN
    rv := rv + 4294967296;
  END IF;
  RETURN rv;
END util_zip_blob_to_num;

--------------------------------------------------------------------------------------------------------------------------------

-- copyright by Anton Scheffer (MIT license, see https://technology.amis.nl/2010/03/13/utl_compress-gzip-and-zlib/)
FUNCTION util_zip_little_endian (
  p_big   IN NUMBER,
  p_bytes IN PLS_INTEGER := 4)
RETURN RAW IS
  t_big NUMBER := p_big;
BEGIN
  IF t_big > 2147483647 THEN
    t_big := t_big - 4294967296;
  END IF;
  RETURN utl_raw.substr(utl_raw.cast_from_binary_integer(t_big, utl_raw.little_endian), 1, p_bytes);
END util_zip_little_endian;

--------------------------------------------------------------------------------------------------------------------------------

-- copyright by Anton Scheffer (MIT license, see https://technology.amis.nl/2010/03/13/utl_compress-gzip-and-zlib/)
PROCEDURE util_zip_add_file (
  p_zipped_blob IN OUT BLOB,
  p_name        IN     VARCHAR2,
  p_content     IN     BLOB)
IS
  t_now        DATE;
  t_blob       BLOB;
  t_len        INTEGER;
  t_clen       INTEGER;
  t_crc32      RAW(4) := hextoraw('00000000');
  t_compressed BOOLEAN := false;
  t_name       RAW(32767);
BEGIN
  t_now := SYSDATE;
  t_len := nvl(dbms_lob.getlength(p_content), 0);
  IF t_len > 0 THEN
    t_blob       := utl_compress.lz_compress(p_content);
    t_clen       := dbms_lob.getlength(t_blob) - 18;
    t_compressed := t_clen < t_len;
    t_crc32      := dbms_lob.substr(t_blob, 4, t_clen + 11);
  END IF;
  IF NOT t_compressed THEN
    t_clen := t_len;
    t_blob := p_content;
  END IF;
  t_name := utl_i18n.string_to_raw(p_name, 'AL32UTF8');
  dbms_lob.append(
    p_zipped_blob,
    utl_raw.concat(
      c_zip_local_file_header, -- local file header signature
      hextoraw('1400'), -- version 2.0
      CASE WHEN t_name = utl_i18n.string_to_raw(p_name, 'US8PC437')
        THEN hextoraw('0000') -- no General purpose bits
        ELSE hextoraw('0008') -- set Language encoding flag (EFS)
      END,
      CASE WHEN t_compressed
        THEN hextoraw('0800') -- deflate
        ELSE hextoraw('0000') -- stored
      END,
      util_zip_little_endian(
          to_number(TO_CHAR(t_now, 'ss')) / 2
        + to_number(TO_CHAR(t_now, 'mi')) * 32
        + to_number(TO_CHAR(t_now, 'hh24')) * 2048,
        2), -- file last modification time
      util_zip_little_endian(
          to_number(TO_CHAR(t_now, 'dd'))
        + to_number(TO_CHAR(t_now, 'mm')) * 32
        + (to_number(TO_CHAR(t_now, 'yyyy')) - 1980) * 512,
        2), -- file last modification date
      t_crc32, -- CRC-32
      util_zip_little_endian(t_clen), -- compressed size
      util_zip_little_endian(t_len), -- uncompressed size
      util_zip_little_endian(utl_raw.length(t_name), 2), -- file name length
      hextoraw('0000'), -- extra field length
      t_name)); -- file name
  IF t_compressed THEN
    dbms_lob.copy(p_zipped_blob, t_blob, t_clen, dbms_lob.getlength(p_zipped_blob) + 1, 11); -- compressed content
  ELSIF t_clen > 0 THEN
    dbms_lob.copy(p_zipped_blob, t_blob, t_clen, dbms_lob.getlength(p_zipped_blob) + 1, 1); -- content
  END IF;
  IF dbms_lob.istemporary(t_blob) = 1 THEN
    dbms_lob.freetemporary(t_blob);
  END IF;
END util_zip_add_file;

--------------------------------------------------------------------------------------------------------------------------------

-- copyright by Anton Scheffer (MIT license, see https://technology.amis.nl/2010/03/13/utl_compress-gzip-and-zlib/)
PROCEDURE util_zip_finish (p_zipped_blob IN OUT BLOB) IS
  t_cnt             PLS_INTEGER := 0;
  t_offs            INTEGER;
  t_offs_dir_header INTEGER;
  t_offs_end_header INTEGER;
  t_comment         RAW(32767) := utl_raw.cast_to_raw('Implementation by Anton Scheffer');
BEGIN
  t_offs_dir_header := dbms_lob.getlength(p_zipped_blob);
  t_offs            := 1;
  WHILE dbms_lob.substr(p_zipped_blob, utl_raw.length(c_zip_local_file_header), t_offs) = c_zip_local_file_header
  LOOP
    t_cnt := t_cnt + 1;
    dbms_lob.append(
      p_zipped_blob,
      utl_raw.concat(
        hextoraw('504B0102'), -- central directory file header signature
        hextoraw('1400'), -- version 2.0
        dbms_lob.substr(p_zipped_blob, 26, t_offs + 4),
        hextoraw('0000'), -- file comment length
        hextoraw('0000'), -- disk number where file starts
        hextoraw('0000'), -- internal file attributes: 0000 = binary file, 0100 = (ascii)text file
        CASE
          WHEN dbms_lob.substr(
            p_zipped_blob,
            1,
            t_offs + 30 + util_zip_blob_to_num(p_zipped_blob, 2, t_offs + 26) - 1)
            IN (hextoraw('2F')/*slash*/, hextoraw('5C')/*backslash*/)
          THEN hextoraw('10000000') -- a directory/folder
          ELSE hextoraw('2000B681') -- a file
        END, -- external file attributes
        util_zip_little_endian(t_offs - 1), -- relative offset of local file header
        dbms_lob.substr(
          p_zipped_blob,
          util_zip_blob_to_num(p_zipped_blob, 2, t_offs + 26),
          t_offs + 30))); -- File name
    t_offs := t_offs + 30
      + util_zip_blob_to_num(p_zipped_blob, 4, t_offs + 18) -- compressed size
      + util_zip_blob_to_num(p_zipped_blob, 2, t_offs + 26) -- file name length
      + util_zip_blob_to_num(p_zipped_blob, 2, t_offs + 28); -- extra field length
  END LOOP;
  t_offs_end_header := dbms_lob.getlength(p_zipped_blob);
  dbms_lob.append(
    p_zipped_blob,
    utl_raw.concat(
      c_zip_end_of_central_directory, -- end of central directory signature
      hextoraw('0000'), -- number of this disk
      hextoraw('0000'), -- disk where central directory starts
      util_zip_little_endian(t_cnt, 2), -- number of central directory records on this disk
      util_zip_little_endian(t_cnt, 2), -- total number of central directory records
      util_zip_little_endian(t_offs_end_header - t_offs_dir_header), -- size of central directory
      util_zip_little_endian(t_offs_dir_header), -- offset of start of central directory, relative to start of archive
      util_zip_little_endian(nvl(utl_raw.length(t_comment), 0), 2), -- ZIP file comment length
      t_comment));
END util_zip_finish;

--------------------------------------------------------------------------------------------------------------------------------

FUNCTION util_multi_replace (
  p_source_string VARCHAR2,
  p_01_find VARCHAR2 DEFAULT NULL, p_01_replace VARCHAR2 DEFAULT NULL,
  p_02_find VARCHAR2 DEFAULT NULL, p_02_replace VARCHAR2 DEFAULT NULL,
  p_03_find VARCHAR2 DEFAULT NULL, p_03_replace VARCHAR2 DEFAULT NULL,
  p_04_find VARCHAR2 DEFAULT NULL, p_04_replace VARCHAR2 DEFAULT NULL,
  p_05_find VARCHAR2 DEFAULT NULL, p_05_replace VARCHAR2 DEFAULT NULL,
  p_06_find VARCHAR2 DEFAULT NULL, p_06_replace VARCHAR2 DEFAULT NULL,
  p_07_find VARCHAR2 DEFAULT NULL, p_07_replace VARCHAR2 DEFAULT NULL,
  p_08_find VARCHAR2 DEFAULT NULL, p_08_replace VARCHAR2 DEFAULT NULL,
  p_09_find VARCHAR2 DEFAULT NULL, p_09_replace VARCHAR2 DEFAULT NULL,
  p_10_find VARCHAR2 DEFAULT NULL, p_10_replace VARCHAR2 DEFAULT NULL,
  p_11_find VARCHAR2 DEFAULT NULL, p_11_replace VARCHAR2 DEFAULT NULL,
  p_12_find VARCHAR2 DEFAULT NULL, p_12_replace VARCHAR2 DEFAULT NULL)
RETURN VARCHAR2 IS
  v_return VARCHAR2(32767);
BEGIN
  v_return := p_source_string;
  IF p_01_find IS NOT NULL THEN v_return := replace(v_return, p_01_find, p_01_replace); END IF;
  IF p_02_find IS NOT NULL THEN v_return := replace(v_return, p_02_find, p_02_replace); END IF;
  IF p_03_find IS NOT NULL THEN v_return := replace(v_return, p_03_find, p_03_replace); END IF;
  IF p_04_find IS NOT NULL THEN v_return := replace(v_return, p_04_find, p_04_replace); END IF;
  IF p_05_find IS NOT NULL THEN v_return := replace(v_return, p_05_find, p_05_replace); END IF;
  IF p_06_find IS NOT NULL THEN v_return := replace(v_return, p_06_find, p_06_replace); END IF;
  IF p_07_find IS NOT NULL THEN v_return := replace(v_return, p_07_find, p_07_replace); END IF;
  IF p_08_find IS NOT NULL THEN v_return := replace(v_return, p_08_find, p_08_replace); END IF;
  IF p_09_find IS NOT NULL THEN v_return := replace(v_return, p_09_find, p_09_replace); END IF;
  IF p_10_find IS NOT NULL THEN v_return := replace(v_return, p_10_find, p_10_replace); END IF;
  IF p_11_find IS NOT NULL THEN v_return := replace(v_return, p_11_find, p_11_replace); END IF;
  IF p_12_find IS NOT NULL THEN v_return := replace(v_return, p_12_find, p_12_replace); END IF;
  RETURN v_return;
END util_multi_replace;

--------------------------------------------------------------------------------------------------------------------------------

FUNCTION util_set_build_status_run_only (p_app_export_sql CLOB) RETURN CLOB IS
  v_position PLS_INTEGER;
BEGIN
  v_position := instr(p_app_export_sql, ',p_exact_substitutions_only');
  RETURN substr(p_app_export_sql, 1, v_position - 1)
    || ',p_build_status=>''RUN_ONLY'''
    || c_lf
    || substr(p_app_export_sql, v_position);
END util_set_build_status_run_only;

--------------------------------------------------------------------------------------------------------------------------------

FUNCTION util_calc_data_timestamp (p_as_of_minutes_ago IN NUMBER) RETURN TIMESTAMP IS
  v_return TIMESTAMP;
BEGIN
  EXECUTE IMMEDIATE
    replace(
      q'[SELECT systimestamp - INTERVAL '{{MINUTES}}' MINUTE FROM dual]',
      '{{MINUTES}}',
      TO_CHAR(p_as_of_minutes_ago))
    INTO v_return;
  RETURN v_return;
END util_calc_data_timestamp;

--------------------------------------------------------------------------------------------------------------------------------

PROCEDURE util_setup_dbms_metadata (
  p_pretty               IN BOOLEAN DEFAULT true,
  p_constraints          IN BOOLEAN DEFAULT true,
  p_ref_constraints      IN BOOLEAN DEFAULT false,
  p_partitioning         IN BOOLEAN DEFAULT true,
  p_tablespace           IN BOOLEAN DEFAULT false,
  p_storage              IN BOOLEAN DEFAULT false,
  p_segment_attributes   IN BOOLEAN DEFAULT false,
  p_sqlterminator        IN BOOLEAN DEFAULT true,
  p_constraints_as_alter IN BOOLEAN DEFAULT false,
  p_emit_schema          IN BOOLEAN DEFAULT false)
IS
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

--------------------------------------------------------------------------------------------------------------------------------

PROCEDURE util_ensure_unique_file_names (p_export_files IN OUT tab_export_files) IS
  v_file_list_lookup     tab_file_list_lookup;
  v_apex_install_file_id PLS_INTEGER;
  v_file_name            VARCHAR2(256);
  v_extension            VARCHAR2(256);
  v_base_name            VARCHAR2(256);
  v_count                PLS_INTEGER;
BEGIN
  util_log_start('ensure unique file names in collection');
  $if $$apex_installed $then
  -- find apex install file
  FOR i IN 1..p_export_files.count LOOP
    IF p_export_files(i).name = 'scripts/install_frontend_generated_by_apex.sql' THEN
      v_apex_install_file_id := i;
    END IF;
  END LOOP;
  $end
  FOR i IN 1..p_export_files.count LOOP
    v_file_name := p_export_files(i).name;
    v_count := 1;
    IF instr(v_file_name, '.') > 0 THEN
      v_base_name := substr(v_file_name, 1, instr(v_file_name, '.', -1) - 1);
      v_extension := substr(v_file_name, instr(v_file_name, '.', -1));
    ELSE
      v_base_name := v_file_name;
      v_extension := NULL;
    END IF;
    WHILE v_file_list_lookup.EXISTS(v_file_name) LOOP
      v_count     := v_count + 1;
      v_file_name := v_base_name || '_' || v_count || v_extension;
    END LOOP;
    v_file_list_lookup(v_file_name) := i;
    -- correct data if needed
    IF p_export_files(i).name != v_file_name THEN
      -- correct the prompt statement
      p_export_files(i).contents := replace(
        p_export_files(i).contents,
        v_base_name,
        v_base_name || '_' || v_count);
      -- correct the apex install file
      IF v_apex_install_file_id IS NOT NULL THEN
        p_export_files(v_apex_install_file_id).contents := regexp_replace(
          p_export_files(v_apex_install_file_id).contents,
          p_export_files(i).name || '$',
          v_file_name,
          1, 2, 'm');
      END IF;
      -- correct the file name itself
      p_export_files(i).name := v_file_name;
    END IF;
  END LOOP;
  util_log_stop;
END util_ensure_unique_file_names;

--------------------------------------------------------------------------------------------------------------------------------

PROCEDURE util_log_init (p_module IN VARCHAR2) IS
BEGIN
  g_runlog.module := substr(p_module, 1, c_app_info_length);
  g_runlog.start_time      := systimestamp;
  g_runlog.stop_time       := NULL;
  g_runlog.run_time        := 0;
  g_runlog.measured_time   := 0;
  g_runlog.unmeasured_time := 0;
  g_runlog.data.DELETE;
  g_errlog.DELETE;
END util_log_init;

--------------------------------------------------------------------------------------------------------------------------------

PROCEDURE util_log_start (p_action IN VARCHAR2) IS
  v_index PLS_INTEGER;
BEGIN
  dbms_application_info.set_module(
    module_name => g_runlog.module,
    action_name => p_action);
  v_index := g_runlog.data.count + 1;
  g_runlog.data(v_index).action     := substr(p_action, 1, plex.c_app_info_length);
  g_runlog.data(v_index).start_time := systimestamp;
END util_log_start;

--------------------------------------------------------------------------------------------------------------------------------

PROCEDURE util_log_error (p_name VARCHAR2) IS
  v_index PLS_INTEGER;
  PROCEDURE add_error_to_action IS
    v_index PLS_INTEGER;
  BEGIN
    v_index := g_runlog.data.count;
    g_runlog.data(v_index).action := substr('ERROR: ' || g_runlog.data(v_index).action, 1, plex.c_app_info_length);
  END add_error_to_action;
BEGIN
  v_index := g_errlog.count + 1;
  g_errlog(v_index).time_stamp := systimestamp;
  g_errlog(v_index).file_name  := substr(p_name, 1, 255);
  g_errlog(v_index).error_text := substr(sqlerrm, 1, 200);
  g_errlog(v_index).call_stack := substr(dbms_utility.format_error_backtrace, 1, 500);
  add_error_to_action;
  util_log_stop;
  g_clob := null;
END util_log_error;

--------------------------------------------------------------------------------------------------------------------------------

PROCEDURE util_log_stop IS
  v_index PLS_INTEGER;
BEGIN
  v_index := g_runlog.data.count;
  dbms_application_info.set_module(
    module_name => NULL,
    action_name => NULL);
  g_runlog.data(v_index).stop_time := systimestamp;
  g_runlog.data(v_index).elapsed   := util_log_get_runtime(g_runlog.start_time, g_runlog.data(v_index).stop_time);
  g_runlog.data(v_index).execution := util_log_get_runtime(g_runlog.data(v_index).start_time, g_runlog.data(v_index).stop_time);
  g_runlog.measured_time           := g_runlog.measured_time + g_runlog.data(v_index).execution;
END util_log_stop;

--------------------------------------------------------------------------------------------------------------------------------

FUNCTION util_log_get_runtime (
  p_start IN TIMESTAMP,
  p_stop  IN TIMESTAMP)
RETURN NUMBER IS
BEGIN
  RETURN SYSDATE + ((p_stop - p_start) * 86400) - SYSDATE;
  --sysdate + (interval_difference * 86400) - sysdate
  --https://stackoverflow.com/questions/10092032/extracting-the-total-number-of-seconds-from-an-interval-data-type
END util_log_get_runtime;

--------------------------------------------------------------------------------------------------------------------------------

PROCEDURE util_log_calc_runtimes IS
BEGIN
  g_runlog.stop_time       := systimestamp;
  g_runlog.run_time        := util_log_get_runtime(g_runlog.start_time, g_runlog.stop_time);
  g_runlog.unmeasured_time := g_runlog.run_time - g_runlog.measured_time;
END util_log_calc_runtimes;

--------------------------------------------------------------------------------------------------------------------------------

PROCEDURE util_clob_append (p_content IN VARCHAR2) IS
BEGIN
  g_clob_vc_cache := g_clob_vc_cache || p_content;
EXCEPTION
  WHEN value_error THEN
    IF g_clob IS NULL THEN
      g_clob := g_clob_vc_cache;
    ELSE
      dbms_lob.writeappend(g_clob, length(g_clob_vc_cache), g_clob_vc_cache);
    END IF;
    g_clob_vc_cache := p_content;
END util_clob_append;

--------------------------------------------------------------------------------------------------------------------------------

PROCEDURE util_clob_append (p_content IN CLOB) IS
BEGIN
  IF p_content IS NOT NULL THEN
    util_clob_flush_cache;
    IF g_clob IS NULL THEN
      g_clob := p_content;
    ELSE
      dbms_lob.writeappend(g_clob, length(p_content), p_content);
    END IF;
  END IF;
END util_clob_append;

--------------------------------------------------------------------------------------------------------------------------------

PROCEDURE util_clob_flush_cache IS
BEGIN
  IF g_clob_vc_cache IS NOT NULL THEN
    IF g_clob IS NULL THEN
      g_clob := g_clob_vc_cache;
    ELSE
      dbms_lob.writeappend(g_clob, length(g_clob_vc_cache), g_clob_vc_cache);
    END IF;
    g_clob_vc_cache := NULL;
  END IF;
END util_clob_flush_cache;

--------------------------------------------------------------------------------------------------------------------------------

PROCEDURE util_clob_add_to_export_files (
  p_export_files IN OUT NOCOPY tab_export_files,
  p_name         IN            VARCHAR2)
IS
  v_index PLS_INTEGER;
BEGIN
  util_clob_flush_cache;
  v_index := p_export_files.count + 1;
  p_export_files.extend;
  p_export_files(v_index).name := p_name;
  p_export_files(v_index).contents := g_clob;
  g_clob := null;
END util_clob_add_to_export_files;

--------------------------------------------------------------------------------------------------------------------------------

PROCEDURE util_clob_query_to_csv (
  p_query         IN VARCHAR2,
  p_max_rows      IN NUMBER DEFAULT 1000,
  p_delimiter     IN VARCHAR2 DEFAULT ',',
  p_quote_mark    IN VARCHAR2 DEFAULT '"',
  p_header_prefix IN VARCHAR2 DEFAULT NULL)
IS
  -- inspired by Tim Hall: https://oracle-base.com/dba/script?category=miscellaneous&file=csv.sql
  v_line_terminator          VARCHAR2(2) := c_crlf; -- to be compatible with Excel we need to use crlf here (multiline text uses lf and is wrapped in quotes)
  v_cursor                   PLS_INTEGER;
  v_ignore_me                   PLS_INTEGER;
  v_data_count               PLS_INTEGER := 0;
  v_col_cnt                  PLS_INTEGER;
  v_desc_tab                 dbms_sql.desc_tab3;
  v_buffer_varchar2          VARCHAR2(32767 CHAR);
  v_buffer_clob              CLOB;
  v_buffer_xmltype           XMLTYPE;
  v_buffer_long              LONG;
  v_buffer_long_length       PLS_INTEGER;
  -- numeric type identfiers
  c_number                   CONSTANT PLS_INTEGER := 2; -- FLOAT
  c_binary_float             CONSTANT PLS_INTEGER := 100;
  c_binary_double            CONSTANT PLS_INTEGER := 101;
  -- string type identfiers
  c_char                     CONSTANT PLS_INTEGER := 96; -- NCHAR
  c_varchar2                 CONSTANT PLS_INTEGER := 1; -- NVARCHAR2
  c_long                     CONSTANT PLS_INTEGER := 8;
  c_clob                     CONSTANT PLS_INTEGER := 112; -- NCLOB
  c_xmltype                  CONSTANT PLS_INTEGER := 109; -- ANYDATA, ANYDATASET, ANYTYPE, Object type, VARRAY, Nested table
  c_rowid                    CONSTANT PLS_INTEGER := 11;
  c_urowid                   CONSTANT PLS_INTEGER := 208;
  -- binary type identfiers
  c_raw                      CONSTANT PLS_INTEGER := 23;
  c_long_raw                 CONSTANT PLS_INTEGER := 24;
  c_blob                     CONSTANT PLS_INTEGER := 113;
  c_bfile                    CONSTANT PLS_INTEGER := 114;
  -- date type identfiers
  c_date                     CONSTANT PLS_INTEGER := 12;
  c_timestamp                CONSTANT PLS_INTEGER := 180;
  c_timestamp_with_time_zone CONSTANT PLS_INTEGER := 181;
  c_timestamp_with_local_tz  CONSTANT PLS_INTEGER := 231;
  -- interval type identfiers
  c_interval_year_to_month   CONSTANT PLS_INTEGER := 182;
  c_interval_day_to_second   CONSTANT PLS_INTEGER := 183;
  -- cursor type identfiers
  c_ref                      CONSTANT PLS_INTEGER := 111;
  c_ref_cursor               CONSTANT PLS_INTEGER := 102; -- same identfiers for strong and weak ref cursor

  PROCEDURE escape_varchar2_buffer_for_csv IS
  BEGIN
    IF v_buffer_varchar2 IS NOT NULL THEN
      -- normalize line feeds for Excel
      v_buffer_varchar2 := replace(
        replace(v_buffer_varchar2, c_crlf, c_lf),
        c_cr,
        c_lf);
      -- if we have the parameter p_force_quotes set to true or the delimiter character or
      -- line feeds in the string then we have to wrap the text in quotes marks and escape
      -- the quote marks inside the text by double them
      IF instr(v_buffer_varchar2, p_delimiter) > 0 OR instr(v_buffer_varchar2, c_lf) > 0 THEN
        v_buffer_varchar2 := p_quote_mark
          || replace(v_buffer_varchar2, p_quote_mark, p_quote_mark || p_quote_mark)
          || p_quote_mark;
      END IF;
    END IF;
  EXCEPTION
    WHEN value_error THEN
      v_buffer_varchar2 := 'Value skipped - escaped text larger then ' || c_vc2_max_size || ' characters';
  END escape_varchar2_buffer_for_csv;

BEGIN
  IF p_query IS NOT NULL THEN
    v_cursor := dbms_sql.open_cursor;
    dbms_sql.parse(
      v_cursor,
      regexp_replace(p_query, ';\s*$', NULL),
      dbms_sql.native);
    -- https://support.esri.com/en/technical-article/000010110
    -- http://bluefrog-oracle.blogspot.com/2011/11/describing-ref-cursor-using-dbmssql-api.html
    dbms_sql.describe_columns3(v_cursor, v_col_cnt, v_desc_tab);
    FOR i IN 1..v_col_cnt LOOP
      IF v_desc_tab(i).col_type = c_clob THEN
        dbms_sql.define_column(v_cursor, i, v_buffer_clob);
      ELSIF v_desc_tab(i).col_type = c_xmltype THEN
        dbms_sql.define_column(v_cursor, i, v_buffer_xmltype);
      ELSIF v_desc_tab(i).col_type = c_long THEN
        dbms_sql.define_column_long(v_cursor, i);
      ELSIF v_desc_tab(i).col_type IN (c_raw, c_long_raw, c_blob, c_bfile) THEN
        NULL; --> we ignore binary data types
      ELSE
        dbms_sql.define_column(v_cursor, i, v_buffer_varchar2, c_vc2_max_size);
      END IF;
    END LOOP;
    v_ignore_me := dbms_sql.execute(v_cursor);
    util_clob_append(p_header_prefix);
    FOR i IN 1..v_col_cnt LOOP
      IF i > 1 THEN
        util_clob_append(p_delimiter);
      END IF;
      v_buffer_varchar2 := v_desc_tab(i).col_name;
      escape_varchar2_buffer_for_csv;
      util_clob_append(v_buffer_varchar2);
    END LOOP;
    util_clob_append(v_line_terminator);
    -- create data
    LOOP
      EXIT WHEN dbms_sql.fetch_rows(v_cursor) = 0 OR v_data_count = p_max_rows;
      FOR i IN 1..v_col_cnt LOOP
        IF i > 1 THEN
          util_clob_append(p_delimiter);
        END IF;
        IF v_desc_tab(i).col_type = c_clob THEN
          dbms_sql.column_value(v_cursor, i, v_buffer_clob);
          IF length(v_buffer_clob) <= c_vc2_max_size THEN
            v_buffer_varchar2 := substr(v_buffer_clob, 1, c_vc2_max_size);
            escape_varchar2_buffer_for_csv;
            util_clob_append(v_buffer_varchar2);
          ELSE
            v_buffer_varchar2 := 'CLOB value skipped - larger then ' || c_vc2_max_size || ' characters';
            util_clob_append(v_buffer_varchar2);
          END IF;
        ELSIF v_desc_tab(i).col_type = c_xmltype THEN
          dbms_sql.column_value(v_cursor, i, v_buffer_xmltype);
          v_buffer_clob := v_buffer_xmltype.getclobval();
          IF length(v_buffer_clob) <= c_vc2_max_size THEN
            v_buffer_varchar2 := substr(v_buffer_clob, 1, c_vc2_max_size);
            escape_varchar2_buffer_for_csv;
            util_clob_append(v_buffer_varchar2);
          ELSE
            v_buffer_varchar2 := 'XML value skipped - larger then ' || c_vc2_max_size || ' characters';
            util_clob_append(v_buffer_varchar2);
          END IF;
        ELSIF v_desc_tab(i).col_type = c_long THEN
          dbms_sql.column_value_long(v_cursor, i, c_vc2_max_size, 0, v_buffer_varchar2, v_buffer_long_length);
          IF v_buffer_long_length <= c_vc2_max_size THEN
            escape_varchar2_buffer_for_csv;
            util_clob_append(v_buffer_varchar2);
          ELSE
            util_clob_append('LONG value skipped - larger then ' || c_vc2_max_size || ' characters');
          END IF;
        ELSIF v_desc_tab(i).col_type IN (c_raw, c_long_raw, c_blob, c_bfile) THEN
          util_clob_append('Binary data type skipped - not supported for CSV');
        ELSE
          dbms_sql.column_value(v_cursor, i, v_buffer_varchar2);
          escape_varchar2_buffer_for_csv;
          util_clob_append(v_buffer_varchar2);
        END IF;
      END LOOP;
      util_clob_append(v_line_terminator);
      v_data_count := v_data_count + 1;
    END LOOP;
    dbms_sql.close_cursor(v_cursor);
  END IF;
END util_clob_query_to_csv;

--------------------------------------------------------------------------------------------------------------------------------

PROCEDURE util_clob_create_error_log (p_export_files IN OUT NOCOPY tab_export_files) IS
BEGIN
  IF g_errlog.count > 0 THEN
    util_log_start(g_errlog.count || ' error' || CASE WHEN g_errlog.count != 1 THEN 's' END || ' occurred: create error log');
    util_clob_append(
      replace('# {{MAIN_FUNCTION}} - Error Log', '{{MAIN_FUNCTION}}', upper(g_runlog.module))
      || c_crlf || c_crlf || c_crlf);
    FOR i IN 1..g_errlog.count LOOP
      util_clob_append('## ' || g_errlog(i).file_name || c_crlf || c_crlf);
      util_clob_append(to_char(g_errlog(i).time_stamp, 'yyyy-mm-dd hh24:mi:ss.ffffff') || ': ' || g_errlog(i).error_text || c_crlf || c_crlf);
      util_clob_append('```sql' || c_crlf || g_errlog(i).call_stack || '```' || c_crlf || c_crlf || c_crlf);
    END LOOP;
    util_clob_add_to_export_files(
      p_export_files => p_export_files,
      p_name         => 'plex_error_log.md');
    util_log_stop;
  END IF;
END util_clob_create_error_log;

--------------------------------------------------------------------------------------------------------------------------------

PROCEDURE util_clob_create_runtime_log (p_export_files IN OUT NOCOPY tab_export_files) IS
BEGIN
  util_log_calc_runtimes;
  util_clob_append(util_multi_replace('# {{MAIN_FUNCTION}} - Runtime Log

- Export started at {{START_TIME}} and took {{RUN_TIME}} seconds to finish with {{ERRORS}}
- Unmeasured execution time because of system waits, missing log calls or log overhead was {{UNMEASURED_TIME}} seconds
- The used PLEX version was {{PLEX_VERSION}}
- More infos here: [PLEX on GitHub]({{PLEX_URL}})

'   ,
    '{{MAIN_FUNCTION}}',   upper(g_runlog.module),
    '{{START_TIME}}',      TO_CHAR(g_runlog.start_time, 'yyyy-mm-dd hh24:mi:ss'),
    '{{RUN_TIME}}',        trim(TO_CHAR(g_runlog.run_time, '999G990D000')),
    '{{UNMEASURED_TIME}}', trim(TO_CHAR(g_runlog.unmeasured_time, '999G990D000')),
    '{{PLEX_VERSION}}',    c_plex_version,
    '{{PLEX_URL}}',        c_plex_url,
    '{{ERRORS}}',          g_errlog.count || ' error' || CASE WHEN g_errlog.count != 1 THEN 's' END));
  util_clob_append('
|  Step |   Elapsed |   Execution | Action                                                           |
|------:|----------:|------------:|:-----------------------------------------------------------------|
' );
  FOR i IN 1..g_runlog.data.count LOOP
    util_clob_append(util_multi_replace(
      '| {{STEP}} | {{ELAPSED}} | {{EXECUTION}} | {{ACTION}} |' || c_lf,
      '{{STEP}}',      lpad(TO_CHAR(i), 5),
      '{{ELAPSED}}',   lpad(trim(TO_CHAR(g_runlog.data(i).elapsed, '99990D000')), 9),
      '{{EXECUTION}}', lpad(trim(TO_CHAR(g_runlog.data(i).execution, '9990D000000')), 11),
      '{{ACTION}}',    rpad(g_runlog.data(i).action, 64)));
  END LOOP;
  util_clob_add_to_export_files(
    p_export_files => p_export_files,
    p_name         => 'plex_runtime_log.md');
END util_clob_create_runtime_log;



------------------------------------------------------------------------------------------------------------------------------
-- MAIN CODE
------------------------------------------------------------------------------------------------------------------------------

FUNCTION backapp (
  $if $$apex_installed $then
  p_app_id                    IN NUMBER   DEFAULT NULL,
  p_app_date                  IN BOOLEAN  DEFAULT true,
  p_app_public_reports        IN BOOLEAN  DEFAULT true,
  p_app_private_reports       IN BOOLEAN  DEFAULT false,
  p_app_notifications         IN BOOLEAN  DEFAULT false,
  p_app_translations          IN BOOLEAN  DEFAULT true,
  p_app_pkg_app_mapping       IN BOOLEAN  DEFAULT false,
  p_app_original_ids          IN BOOLEAN  DEFAULT false,
  p_app_subscriptions         IN BOOLEAN  DEFAULT true,
  p_app_comments              IN BOOLEAN  DEFAULT true,
  p_app_supporting_objects    IN VARCHAR2 DEFAULT NULL,
  p_app_include_single_file   IN BOOLEAN  DEFAULT false,
  p_app_build_status_run_only IN BOOLEAN  DEFAULT false,
  $end
  $if $$ords_installed $then
  p_include_ords_modules      IN BOOLEAN  DEFAULT false,
  $end
  p_include_object_ddl        IN BOOLEAN  DEFAULT false,
  p_object_type_like          IN VARCHAR2 DEFAULT NULL,
  p_object_type_not_like      IN VARCHAR2 DEFAULT NULL,
  p_object_name_like          IN VARCHAR2 DEFAULT NULL,
  p_object_name_not_like      IN VARCHAR2 DEFAULT NULL,
  p_include_data              IN BOOLEAN  DEFAULT false,
  p_data_as_of_minutes_ago    IN NUMBER   DEFAULT 0,
  p_data_max_rows             IN NUMBER   DEFAULT 1000,
  p_data_table_name_like      IN VARCHAR2 DEFAULT NULL,
  p_data_table_name_not_like  IN VARCHAR2 DEFAULT NULL,
  p_include_templates         IN BOOLEAN  DEFAULT true,
  p_include_runtime_log       IN BOOLEAN  DEFAULT true,
  p_include_error_log         IN BOOLEAN  DEFAULT true,
  p_base_path_backend         IN VARCHAR2 DEFAULT 'app_backend',
  p_base_path_frontend        IN VARCHAR2 DEFAULT 'app_frontend',
  p_base_path_web_services    IN VARCHAR2 DEFAULT 'app_web_services',
  p_base_path_data            IN VARCHAR2 DEFAULT 'app_data')
RETURN tab_export_files IS
  v_apex_version     NUMBER;
  v_data_timestamp   TIMESTAMP;
  v_data_scn         NUMBER;
  v_file_path        VARCHAR2(255);
  v_current_user     user_objects.object_name%TYPE;
  v_app_workspace    user_objects.object_name%TYPE;
  v_app_owner        user_objects.object_name%TYPE;
  v_app_alias        user_objects.object_name%TYPE;
  v_ddl_files        rec_ddl_files;
  v_contents         CLOB;
  v_export_files     tab_export_files;
  v_file_list_lookup tab_file_list_lookup;
  TYPE obj_cur_typ   IS REF CURSOR;
  v_cur              obj_cur_typ;
  v_query            VARCHAR2(32767);

  FUNCTION util_get_script_line (p_file_path VARCHAR2) RETURN VARCHAR2 IS
  BEGIN
    RETURN 'prompt --' || replace(p_file_path, '.sql', NULL)
      || c_lf || '@' || '../' || p_file_path || c_lf || c_lf;
  END util_get_script_line; 

  PROCEDURE init IS
  BEGIN
    util_log_init(
      p_module => 'plex.backapp'
      $if $$apex_installed $then
      || CASE WHEN p_app_id IS NOT NULL THEN '(' || TO_CHAR(p_app_id) || ')' END
      $end);
    util_log_start('init');
    v_export_files := NEW tab_export_files();
    v_current_user := sys_context('USERENV', 'CURRENT_USER');
    util_log_stop;
  END init;

  $if $$apex_installed $then
  PROCEDURE check_owner IS
    CURSOR cur_owner IS
      SELECT workspace,
             owner,
             alias
        FROM apex_applications t
       WHERE t.application_id = p_app_id;
  BEGIN
    util_log_start('check_owner');
    IF p_app_id IS NOT NULL THEN
      OPEN cur_owner;
      FETCH cur_owner INTO
        v_app_workspace,
        v_app_owner,
        v_app_alias;
      CLOSE cur_owner;
    END IF;
    IF p_app_id IS NOT NULL AND v_app_owner IS NULL THEN
      raise_application_error(
        -20101,
        'Could not find owner for application - are you sure you provided the right app_id?');
    ELSIF p_app_id IS NOT NULL AND v_app_owner != v_current_user THEN
      raise_application_error(
        -20102,
        'You are not the owner of the app - please login as the owner.');
    END IF;
    util_log_stop;
  END check_owner;
  $end

  $if $$apex_installed $then
  PROCEDURE process_apex_app IS
    v_apex_files apex_t_export_files;
  BEGIN
    -- save as individual files
    util_log_start(p_base_path_frontend || '/APEX_EXPORT:individual_files');
    v_apex_files := apex_export.get_application(
      p_application_id          => p_app_id,
      p_split                   => true,
      p_with_date               => p_app_date,
      p_with_ir_public_reports  => p_app_public_reports,
      p_with_ir_private_reports => p_app_private_reports,
      p_with_ir_notifications   => p_app_notifications,
      p_with_translations       => p_app_translations,
      p_with_pkg_app_mapping    => p_app_pkg_app_mapping,
      p_with_original_ids       => p_app_original_ids,
      p_with_no_subscriptions   => CASE WHEN p_app_subscriptions THEN false ELSE true END,
      p_with_comments           => p_app_comments,
      p_with_supporting_objects => p_app_supporting_objects);
    FOR i IN 1..v_apex_files.count LOOP
      v_export_files.extend;
      -- relocate files to own project structure
      v_export_files(i).name := replace(
        v_apex_files(i).name,
        'f' || p_app_id || '/application/',
        p_base_path_frontend || '/');
      -- correct prompts for relocation
      v_export_files(i).contents := replace(
        v_apex_files(i).contents,
        'prompt --application/',
        'prompt --' || p_base_path_frontend || '/');
      -- special handling for install file
      IF v_export_files(i).name = 'f' || p_app_id || '/install.sql' THEN
        v_export_files(i).name     := 'scripts/install_frontend_generated_by_apex.sql';
        v_export_files(i).contents := '-- DO NOT TOUCH THIS FILE - IT WILL BE OVERWRITTEN ON NEXT PLEX BACKAPP CALL'
          || c_lf || c_lf
          || replace(replace(v_export_files(i).contents,
              '@application/', '@../' || p_base_path_frontend || '/'),
              'prompt --install', 'prompt --install_frontend_generated_by_apex');
      END IF;
      -- handle build status RUN_ONLY
      IF v_export_files(i).name = p_base_path_frontend || '/create_application.sql' AND p_app_build_status_run_only THEN
        v_export_files(i).contents := util_set_build_status_run_only(v_export_files(i).contents);
      END IF;
      v_apex_files.DELETE(i);
    END LOOP;
    util_log_stop;
    --
    IF p_app_include_single_file THEN
      -- save as single file
      v_apex_files.DELETE;
      util_log_start(p_base_path_frontend || '/APEX_EXPORT:single_file');
      v_apex_files := apex_export.get_application(
        p_application_id          => p_app_id,
        p_split                   => false,
        p_with_date               => p_app_date,
        p_with_ir_public_reports  => p_app_public_reports,
        p_with_ir_private_reports => p_app_private_reports,
        p_with_ir_notifications   => p_app_notifications,
        p_with_translations       => p_app_translations,
        p_with_pkg_app_mapping    => p_app_pkg_app_mapping,
        p_with_original_ids       => p_app_original_ids,
        p_with_no_subscriptions   => CASE WHEN p_app_subscriptions THEN false ELSE true END,
        p_with_comments           => p_app_comments,
        p_with_supporting_objects => p_app_supporting_objects);
      IF p_app_build_status_run_only THEN
        v_apex_files(1).contents := util_set_build_status_run_only(v_apex_files(1).contents);
      END IF;
      util_clob_append(v_apex_files(1).contents);
      util_clob_add_to_export_files(
        p_export_files => v_export_files,
        p_name         => p_base_path_frontend || '/' || v_apex_files(1).name);
      v_apex_files.DELETE;
      util_log_stop;
    END IF;
  END process_apex_app;
  $end

  PROCEDURE replace_query_like_expressions (
    p_like_list          VARCHAR2,
    p_not_like_list      VARCHAR2,
    p_placeholder_prefix VARCHAR2,
    p_column_name        VARCHAR2)
  IS
    v_expression_table tab_vc32k;
  BEGIN
    -- process filter "like"
    v_expression_table := util_split(p_like_list, ',');
    FOR i IN 1..v_expression_table.count LOOP
      v_expression_table(i) := p_column_name
        || ' like '''
        || trim(v_expression_table(i))
        || ''' escape ''\''';
    END LOOP;
    v_query := replace(
      v_query,
      '#' || p_placeholder_prefix || '_LIKE_EXPRESSIONS#',
      nvl(util_join(v_expression_table, ' or '), '1 = 1'));
    -- process filter "not like"
    v_expression_table := util_split(p_not_like_list, ',');
    FOR i IN 1..v_expression_table.count LOOP
      v_expression_table(i) := p_column_name
        || ' not like '''
        || trim(v_expression_table (i))
        || ''' escape ''\''';
    END LOOP;
    v_query := replace(
      v_query,
      '#' || p_placeholder_prefix || '_NOT_LIKE_EXPRESSIONS#',
      nvl(util_join(v_expression_table, ' and '), '1 = 1'));
    $if $$debug_on $then
    dbms_output.put_line(v_query);
    $end
  END replace_query_like_expressions;

  PROCEDURE process_user_ddl IS

    PROCEDURE process_user IS
    BEGIN
      v_file_path := p_base_path_backend || '/_user/' || v_current_user || '.sql';
      util_log_start(v_file_path);
      util_setup_dbms_metadata(p_sqlterminator => false);
      util_clob_append(util_multi_replace(q'^
BEGIN
  FOR i IN (SELECT '{{CURRENT_USER}}' AS username FROM dual
             MINUS
            SELECT username FROM dba_users) LOOP
    EXECUTE IMMEDIATE q'[
--------------------------------------------------------------------------------
{{DDL}}
--------------------------------------------------------------------------------
    ]'
  END LOOP;
END;
{{/}}
^'      ,
        '{{CURRENT_USER}}', v_current_user,
        '{{DDL}}',          dbms_metadata.get_ddl('USER', v_current_user),
        '{{/}}',            c_slash));
      util_clob_add_to_export_files(
        p_export_files => v_export_files,
        p_name         => v_file_path);
      util_setup_dbms_metadata;
      util_log_stop;
    EXCEPTION
      WHEN OTHERS THEN
        util_setup_dbms_metadata;
        util_log_error(v_file_path);
    END process_user;

    PROCEDURE process_roles IS
    BEGIN
      v_file_path := p_base_path_backend || '/_user/' || v_current_user || '_roles.sql';
      util_log_start(v_file_path);
      FOR i IN (SELECT DISTINCT username FROM user_role_privs) LOOP
        util_clob_append(dbms_metadata.get_granted_ddl('ROLE_GRANT', v_current_user));
      END LOOP;
      util_clob_add_to_export_files(
        p_export_files => v_export_files,
        p_name         => v_file_path);
      util_log_stop;
    EXCEPTION
      WHEN OTHERS THEN
        util_log_error(v_file_path);
    END process_roles;

    PROCEDURE process_system_privileges IS
    BEGIN
      v_file_path := p_base_path_backend || '/_user/' || v_current_user || '_system_privileges.sql';
      util_log_start(v_file_path);
      FOR i IN (SELECT DISTINCT username FROM user_sys_privs) LOOP
        util_clob_append(dbms_metadata.get_granted_ddl('SYSTEM_GRANT', v_current_user));
      END LOOP;
      util_clob_add_to_export_files(
        p_export_files => v_export_files,
        p_name         => v_file_path);
      util_log_stop;
    EXCEPTION
      WHEN OTHERS THEN
        util_log_error(v_file_path);
    END process_system_privileges;

    PROCEDURE process_object_privileges IS
    BEGIN
      v_file_path := p_base_path_backend || '/_user/' || v_current_user || '_object_privileges.sql';
      util_log_start(v_file_path);
      FOR i IN (SELECT DISTINCT grantee FROM user_tab_privs WHERE grantee = v_current_user) LOOP
        util_clob_append(dbms_metadata.get_granted_ddl('OBJECT_GRANT', v_current_user));
      END LOOP;
      util_clob_add_to_export_files(
        p_export_files => v_export_files,
        p_name         => v_file_path);
      util_log_stop;
    EXCEPTION
      WHEN OTHERS THEN
        util_log_error(v_file_path);
    END process_object_privileges;

  BEGIN
    process_user;
    process_roles;
    process_system_privileges;
    process_object_privileges;
  END process_user_ddl;

  PROCEDURE process_object_ddl IS
    TYPE obj_rec_typ IS RECORD (
      object_type   VARCHAR2(128),
      object_name   VARCHAR2(256),
      file_path     VARCHAR2(512));
    v_rec obj_rec_typ;
  BEGIN
    util_log_start(p_base_path_backend || '/open_objects_cursor');
    v_query   := q'^
--https://stackoverflow.com/questions/10886450/how-to-generate-entire-ddl-of-an-oracle-schema-scriptable
--https://stackoverflow.com/questions/3235300/oracles-dbms-metadata-get-ddl-for-object-type-job
WITH t AS (
  SELECT CASE object_type
           --http://psoug.org/reference/dbms_metadata.html
           WHEN 'UNIFIED AUDIT POLICY' THEN 'AUDIT_OBJ'
           WHEN 'CONSUMER GROUP'       THEN 'RMGR_CONSUMER_GROUP'
           WHEN 'DATABASE LINK'        THEN 'DB_LINK'
           WHEN 'EVALUATION CONTEXT'   THEN 'PROCOBJ'
           WHEN 'JAVA CLASS'           THEN 'JAVA_CLASS'
           WHEN 'JAVA RESOURCE'        THEN 'JAVA_RESOURCE'
           WHEN 'JAVA SOURCE'          THEN 'JAVA_SOURCE'
           WHEN 'JAVA TYPE'            THEN 'JAVA_TYPE'
           WHEN 'JOB'                  THEN 'PROCOBJ'
           WHEN 'JOB CLASS'            THEN 'PROCOBJ'
           WHEN 'MATERIALIZED VIEW'    THEN 'MATERIALIZED_VIEW'
           WHEN 'PACKAGE BODY'         THEN 'PACKAGE_BODY'
           WHEN 'PACKAGE'              THEN 'PACKAGE_SPEC'
           WHEN 'PROGRAM'              THEN 'PROCOBJ'
           WHEN 'QUEUE'                THEN 'AQ_QUEUE'
           WHEN 'RESOURCE PLAN'        THEN 'RMGR_PLAN'
           WHEN 'RULE SET'             THEN 'PROCOBJ'
           WHEN 'RULE'                 THEN 'PROCOBJ'
           WHEN 'SCHEDULE'             THEN 'PROCOBJ'
           WHEN 'SCHEDULER GROUP'      THEN 'PROCOBJ'
           WHEN 'TYPE BODY'            THEN 'TYPE_BODY'
           WHEN 'TYPE'                 THEN 'TYPE_SPEC'
           ELSE object_type
         END AS object_type,
         CASE 
           WHEN object_type like 'JAVA%' AND substr(object_name, 1, 1) = '/' THEN
             dbms_java.longname(object_name)
           ELSE
             object_name
         END as object_name
    FROM ^'
$if NOT $$debug_on
$then || 'user_objects'
$else || '(SELECT MIN(object_name) AS object_name, object_type FROM user_objects GROUP BY object_type)'
$end || q'^
   WHERE -- ignore invalid object types
         object_type NOT IN ('UNDEFINED','DESTINATION','EDITION','JAVA DATA','WINDOW')
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
     AND (#TYPE_LIKE_EXPRESSIONS#)
     AND (#TYPE_NOT_LIKE_EXPRESSIONS#)
     AND (#NAME_LIKE_EXPRESSIONS#)
     AND (#NAME_NOT_LIKE_EXPRESSIONS#)
   ORDER BY
         object_type,
         object_name
)
SELECT object_type,
       object_name,
       '{{BASE_PATH_APP_BACKEND}}/'
       || replace(lower(
          CASE
            WHEN object_type LIKE '%S'  THEN object_type || 'ES'
            WHEN object_type LIKE '%EX' THEN regexp_replace(object_type, 'EX$', 'ICES', 1, 0, 'i')
            WHEN object_type LIKE '%Y'  THEN regexp_replace(object_type, 'Y$', 'IES', 1, 0, 'i')
            ELSE object_type || 'S'
          END), ' ', '_')
       || '/' || object_name
       || CASE object_type
             WHEN 'FUNCTION'     THEN '.fnc'
             WHEN 'PACKAGE BODY' THEN '.pkb'
             WHEN 'PACKAGE'      THEN '.pks'
             WHEN 'PROCEDURE'    THEN '.prc'
             WHEN 'TRIGGER'      THEN '.trg'
             WHEN 'TYPE BODY'    THEN '.tpb'
             WHEN 'TYPE'         THEN '.tps'
             ELSE                     '.sql'
           END AS file_path
  FROM t
^'  ;
    v_query := replace(
      v_query,
      '{{BASE_PATH_APP_BACKEND}}',
      p_base_path_backend);
    replace_query_like_expressions(
      p_like_list          => p_object_type_like,
      p_not_like_list      => p_object_type_not_like,
      p_placeholder_prefix => 'TYPE',
      p_column_name        => 'object_type');
    replace_query_like_expressions(
      p_like_list          => p_object_name_like,
      p_not_like_list      => p_object_name_not_like,
      p_placeholder_prefix => 'NAME',
      p_column_name        => 'object_name');
    util_setup_dbms_metadata;
    OPEN v_cur FOR v_query;
    util_log_stop;
    LOOP
      FETCH v_cur INTO v_rec;
      EXIT WHEN v_cur%notfound;
      BEGIN
        util_log_start(v_rec.file_path);
        CASE v_rec.object_type
          WHEN 'SEQUENCE' THEN
            v_ddl_files.sequences_(v_ddl_files.sequences_.count + 1) := v_rec.file_path;
          WHEN 'TABLE' THEN
            v_ddl_files.tables_(v_ddl_files.tables_.count + 1) := v_rec.file_path;
          WHEN 'INDEX' THEN
            v_ddl_files.indices_(v_ddl_files.indices_.count + 1) := v_rec.file_path;
          WHEN 'VIEW' THEN
            v_ddl_files.views_(v_ddl_files.views_.count + 1) := v_rec.file_path;
          WHEN 'TYPE_SPEC' THEN
            v_ddl_files.types_(v_ddl_files.types_.count + 1) := v_rec.file_path;
          WHEN 'TYPE_BODY' THEN
            v_ddl_files.type_bodies_(v_ddl_files.type_bodies_.count + 1) := v_rec.file_path;
          WHEN 'TRIGGER' THEN
            v_ddl_files.triggers_(v_ddl_files.triggers_.count + 1) := v_rec.file_path;
          WHEN 'FUNCTION' THEN
            v_ddl_files.functions_(v_ddl_files.functions_.count + 1) := v_rec.file_path;
          WHEN 'PROCEDURE' THEN
            v_ddl_files.procedures_(v_ddl_files.procedures_.count + 1) := v_rec.file_path;
          WHEN 'PACKAGE_SPEC' THEN
            v_ddl_files.packages_(v_ddl_files.packages_.count + 1) := v_rec.file_path;
          WHEN 'PACKAGE_BODY' THEN
            v_ddl_files.package_bodies_(v_ddl_files.package_bodies_.count + 1) := v_rec.file_path;
          ELSE
            v_ddl_files.other_objects_(v_ddl_files.other_objects_.count + 1) := v_rec.file_path;
        END CASE;
        CASE
          WHEN v_rec.object_type = 'VIEW' THEN
            util_clob_append(ltrim(regexp_replace(regexp_replace(
              -- source string
              dbms_metadata.get_ddl(v_rec.object_type, v_rec.object_name, v_current_user),
              -- regex replace: remove additional column list from the compiler
              '\(.*\) ', NULL, 1, 1),
              -- regex replace: remove additional whitespace from the compiler
              '^\s*SELECT', 'SELECT', 1, 1, 'im'),
              -- ltrim: remove leading whitspace
              ' ' || c_lf));
            util_clob_add_to_export_files(
              p_export_files => v_export_files,
              p_name         => v_rec.file_path);
          WHEN v_rec.object_type IN ('TABLE', 'INDEX', 'SEQUENCE') THEN
            util_setup_dbms_metadata(p_sqlterminator => false);
            util_clob_append(replace(q'^
BEGIN
  FOR i IN (SELECT '{{OBJECT_NAME}}' AS object_name FROM dual
             MINUS
            SELECT object_name FROM user_objects) LOOP
    EXECUTE IMMEDIATE q'[
--------------------------------------------------------------------------------
^'            ,
              '{{OBJECT_NAME}}',
              v_rec.object_name)
              || dbms_metadata.get_ddl(v_rec.object_type, v_rec.object_name, v_current_user)
              || replace(q'^
--------------------------------------------------------------------------------
    ]';
  END LOOP;
END;
{{/}}

-- Put your ALTER statements below in the same style as before to ensure that
-- the script is restartable.
^'            ,
              '{{/}}',
              c_slash));
            util_setup_dbms_metadata;
          ELSE
            util_clob_append(dbms_metadata.get_ddl(v_rec.object_type, v_rec.object_name, v_current_user));
        END CASE;
        util_clob_add_to_export_files(
          p_export_files => v_export_files,
          p_name         => v_rec.file_path);
        util_log_stop;
      EXCEPTION
        WHEN OTHERS THEN
          util_setup_dbms_metadata;
          util_log_error(v_rec.file_path);
      END;
    END LOOP;
    CLOSE v_cur;
  END process_object_ddl;

  PROCEDURE process_object_grants IS
    TYPE obj_rec_typ IS RECORD (
      grantor     VARCHAR2(128),
      privilege   VARCHAR2(128),
      object_name VARCHAR2(256),
      file_path   VARCHAR2(512));
    v_rec obj_rec_typ;
  BEGIN
    util_log_start(p_base_path_backend || '/grants:open_cursor');
    v_query   := q'^
SELECT DISTINCT
      p.grantor,
      p.privilege,
      p.table_name as object_name,
      '{{BASE_PATH_APP_BACKEND}}/grants/' || p.privilege || '_on_' || p.table_name || '.sql' AS file_path
FROM user_tab_privs p
JOIN user_objects o ON p.table_name = o.object_name
WHERE (#NAME_LIKE_EXPRESSIONS#)
  AND (#NAME_NOT_LIKE_EXPRESSIONS#)
ORDER BY
      privilege,
      object_name
^'  ;
    v_query := replace(
      v_query,
      '{{BASE_PATH_APP_BACKEND}}',
      p_base_path_backend);
    replace_query_like_expressions(
      p_like_list          => p_object_name_like,
      p_not_like_list      => p_object_name_not_like,
      p_placeholder_prefix => 'NAME',
      p_column_name        => 'o.object_name');
    OPEN v_cur FOR v_query;
    util_log_stop;
    LOOP
      FETCH v_cur INTO v_rec;
      EXIT WHEN v_cur%notfound;
      BEGIN
        util_log_start(v_rec.file_path);
        util_clob_append(dbms_metadata.get_dependent_ddl('OBJECT_GRANT', v_rec.object_name, v_rec.grantor));
        v_ddl_files.grants_(v_ddl_files.grants_.count + 1) := v_rec.file_path;
        util_clob_add_to_export_files(
          p_export_files => v_export_files,
          p_name         => v_rec.file_path);
        util_log_stop;
      EXCEPTION
        WHEN OTHERS THEN
          util_log_error(v_rec.file_path);
      END;
    END LOOP;
    CLOSE v_cur;
  END process_object_grants;

  PROCEDURE process_ref_constraints IS
    TYPE obj_rec_typ IS RECORD (
      table_name        VARCHAR2(256),
      constraint_name   VARCHAR2(256),
      file_path         VARCHAR2(512));
    v_rec obj_rec_typ;
  BEGIN
    util_log_start(p_base_path_backend || '/ref_constraints:open_cursor');
    v_query   := q'^
SELECT table_name,
      constraint_name,
      '{{BASE_PATH_APP_BACKEND}}/ref_constraints/' || constraint_name || '.sql' AS file_path
FROM user_constraints
WHERE constraint_type = 'R'
  AND (#NAME_LIKE_EXPRESSIONS#)
  AND (#NAME_NOT_LIKE_EXPRESSIONS#)
ORDER BY
      table_name,
      constraint_name
^'  ;
    v_query := replace(
      v_query,
      '{{BASE_PATH_APP_BACKEND}}',
      p_base_path_backend);
    replace_query_like_expressions(
      p_like_list          => p_object_name_like,
      p_not_like_list      => p_object_name_not_like,
      p_placeholder_prefix => 'NAME',
      p_column_name        => 'table_name');
    OPEN v_cur FOR v_query;
    util_log_stop;
    LOOP
      FETCH v_cur INTO v_rec;
      EXIT WHEN v_cur%notfound;
      BEGIN
        util_log_start(v_rec.file_path);
        util_setup_dbms_metadata(p_sqlterminator => false);
        util_clob_append(replace(q'^
BEGIN
FOR i IN (SELECT '{{CONSTRAINT_NAME}}' AS constraint_name FROM dual
          MINUS
          SELECT constraint_name FROM user_constraints) LOOP
  EXECUTE IMMEDIATE q'[
--------------------------------------------------------------------------------
^'        ,
          '{{CONSTRAINT_NAME}}',
          v_rec.constraint_name)
          || dbms_metadata.get_ddl('REF_CONSTRAINT', v_rec.constraint_name, v_current_user)
          || replace(q'^
--------------------------------------------------------------------------------
  ]';
END LOOP;
END;
{{/}}
^'        ,
          '{{/}}',
          c_slash));
        util_setup_dbms_metadata;
        v_ddl_files.ref_constraints_(v_ddl_files.ref_constraints_.count + 1) := v_rec.file_path;
        util_clob_add_to_export_files(
          p_export_files => v_export_files,
          p_name         => v_rec.file_path);
        util_log_stop;
      EXCEPTION
        WHEN OTHERS THEN
          util_setup_dbms_metadata;
          util_log_error(v_rec.file_path);
      END;
    END LOOP;
    CLOSE v_cur;
  END process_ref_constraints;

  PROCEDURE create_backend_install_file IS
  BEGIN
    v_file_path := 'scripts/install_backend_generated_by_plex.sql';
    util_log_start(v_file_path);
    util_clob_append('/* A T T E N T I O N
DO NOT TOUCH THIS FILE or set the PLEX.BackApp parameter p_include_object_ddl
to false - otherwise your changes would be overwritten on next PLEX.BackApp
call. It is recommended to export your object ddl only ones on initial
repository creation and then start to use the "files first approach".
*/

set define off verify off feedback off
whenever sqlerror exit sql.sqlcode rollback

prompt --install_backend_generated_by_plex

'   );
    FOR i IN 1..v_ddl_files.sequences_.count LOOP
      util_clob_append(util_get_script_line(v_ddl_files.sequences_(i)));
    END LOOP;
    FOR i IN 1..v_ddl_files.tables_.count LOOP
      util_clob_append(util_get_script_line(v_ddl_files.tables_(i)));
    END LOOP;
    FOR i IN 1..v_ddl_files.ref_constraints_.count LOOP
      util_clob_append(util_get_script_line(v_ddl_files.ref_constraints_(i)));
    END LOOP;
    FOR i IN 1..v_ddl_files.indices_.count LOOP
      util_clob_append(util_get_script_line(v_ddl_files.indices_(i)));
    END LOOP;
    FOR i IN 1..v_ddl_files.views_.count LOOP
      util_clob_append(util_get_script_line(v_ddl_files.views_(i)));
    END LOOP;
    FOR i IN 1..v_ddl_files.types_.count LOOP
      util_clob_append(util_get_script_line(v_ddl_files.types_(i)));
    END LOOP;
    FOR i IN 1..v_ddl_files.type_bodies_.count LOOP
      util_clob_append(util_get_script_line(v_ddl_files.type_bodies_(i)));
    END LOOP;
    FOR i IN 1..v_ddl_files.triggers_.count LOOP
      util_clob_append(util_get_script_line(v_ddl_files.triggers_(i)));
    END LOOP;
    FOR i IN 1..v_ddl_files.functions_.count LOOP
      util_clob_append(util_get_script_line(v_ddl_files.functions_(i)));
    END LOOP;
    FOR i IN 1..v_ddl_files.procedures_.count LOOP
      util_clob_append(util_get_script_line(v_ddl_files.procedures_(i)));
    END LOOP;
    FOR i IN 1..v_ddl_files.packages_.count LOOP
      util_clob_append(util_get_script_line(v_ddl_files.packages_(i)));
    END LOOP;
    FOR i IN 1..v_ddl_files.package_bodies_.count LOOP
      util_clob_append(util_get_script_line(v_ddl_files.package_bodies_(i)));
    END LOOP;
    FOR i IN 1..v_ddl_files.grants_.count LOOP
      util_clob_append(util_get_script_line(v_ddl_files.grants_(i)));
    END LOOP;
    FOR i IN 1..v_ddl_files.other_objects_.count LOOP
      util_clob_append(util_get_script_line(v_ddl_files.other_objects_(i)));
    END LOOP;
    util_clob_add_to_export_files(
      p_export_files => v_export_files,
      p_name         => v_file_path);
    util_log_stop;
  END create_backend_install_file;

  $if $$ords_installed $then
  PROCEDURE process_ords_modules IS
    v_module_name user_ords_modules.name%type;
    --
    PROCEDURE export_ords_modules IS
    BEGIN
      util_log_start(p_base_path_web_services || '/open_modules_cursor');
      OPEN v_cur FOR 'select name from user_ords_modules';
      util_log_stop;
      --
      LOOP
        FETCH v_cur INTO v_module_name;
        EXIT WHEN v_cur%notfound;
        BEGIN
          v_file_path := p_base_path_web_services || '/' || v_module_name || '.sql';
          util_log_start(v_file_path);
          util_clob_append(ords_export.export_module(p_module_name => v_module_name) || chr(10) || '/');
          util_clob_add_to_export_files(
            p_export_files => v_export_files,
            p_name         => v_file_path);
          v_ddl_files.ords_modules_(v_ddl_files.ords_modules_.count + 1) := v_file_path;
          util_log_stop;
        EXCEPTION
          WHEN OTHERS THEN
            util_log_error(v_file_path);
        END;
      END LOOP;
      CLOSE v_cur;
    END export_ords_modules;
    --
    PROCEDURE create_ords_install_file IS
    BEGIN
      v_file_path := 'scripts/install_web_services_generated_by_ords.sql';
      util_log_start(v_file_path);
      util_clob_append('/* A T T E N T I O N
DO NOT TOUCH THIS FILE or set the PLEX.BackApp parameter p_include_ords_modules
to false - otherwise your changes would be overwritten on next PLEX.BackApp
call.
*/

set define off verify off feedback off
whenever sqlerror exit sql.sqlcode rollback

prompt --install_web_services_generated_by_ords

'   );
      FOR i IN 1..v_ddl_files.ords_modules_.count LOOP
        util_clob_append(util_get_script_line(v_ddl_files.ords_modules_(i)));
      END LOOP;
      util_clob_add_to_export_files(
        p_export_files => v_export_files,
        p_name         => v_file_path);
      util_log_stop;
    END create_ords_install_file;

  BEGIN
    export_ords_modules;
    create_ords_install_file;
  END process_ords_modules;
  $end

  PROCEDURE process_data IS
    TYPE obj_rec_typ IS RECORD (
      table_name   VARCHAR2(256),
      pk_columns   VARCHAR2(4000));
    v_rec obj_rec_typ;
  BEGIN
    util_log_start(p_base_path_data || '/open_tables_cursor');
    v_query            := q'^
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
   AND (#NAME_LIKE_EXPRESSIONS#)
   AND (#NAME_NOT_LIKE_EXPRESSIONS#)
 ORDER BY
       table_name
^'  ;
    replace_query_like_expressions(
      p_like_list          => p_data_table_name_like,
      p_not_like_list      => p_data_table_name_not_like,
      p_placeholder_prefix => 'NAME',
      p_column_name        => 'table_name');
    OPEN v_cur FOR v_query;
    util_log_stop;
    --
    util_log_start(p_base_path_data || '/get_scn');
    v_data_timestamp := util_calc_data_timestamp(nvl(p_data_as_of_minutes_ago, 0));
    v_data_scn       := timestamp_to_scn(v_data_timestamp);
    util_log_stop;
    LOOP
      FETCH v_cur INTO v_rec;
      EXIT WHEN v_cur%notfound;
      BEGIN
        v_file_path := p_base_path_data || '/' || v_rec.table_name || '.csv';
        util_log_start(v_file_path);
        util_clob_query_to_csv(
          p_query    => 'SELECT * FROM ' || v_rec.table_name || ' AS OF SCN ' || v_data_scn ||
                        CASE
                          WHEN v_rec.pk_columns IS NOT NULL
                          THEN ' ORDER BY ' || v_rec.pk_columns
                          ELSE NULL
                        END,
          p_max_rows => p_data_max_rows);
        util_clob_add_to_export_files(
          p_export_files => v_export_files,
          p_name         => v_file_path);
        util_log_stop;
      EXCEPTION
        WHEN OTHERS THEN
          util_log_error(v_file_path);
      END;
    END LOOP;
    CLOSE v_cur;
  END process_data;

  PROCEDURE create_template_files IS
    v_file_template VARCHAR2(32767 CHAR);
  BEGIN
    -- the readme template
    v_file_template := q'^Your Global README File
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
- scripts/install_web_services_generated_by_ords.sql

Do not touch these generated install files. They will be overwritten on each
plex call. Depending on your call parameters it would be ok to modify the file
install_backend_generated_by_plex - especially when you follow the files first
approach and export your schema DDL only ones to have a starting point for you
repository.

If you need to do modifications for the install process then have a look at the
following templates - they call the generated files and you can do your own
stuff before or after the calls.

- scripts/templates/1_export_app_from_DEV.bat
- scripts/templates/2_install_app_into_INT.bat
- scripts/templates/3_install_app_into_PROD.bat
- scripts/templates/export_app_custom_code.sql
- scripts/templates/install_app_custom_code.sql

If you want to use these files please make a copy into the scripts directory
and modify it to your needs. Doing it this way your changes are overwrite save.

[Feedback is welcome]({{PLEX_URL}}/issues/new)
^'  ;
    v_file_path := 'plex_README.md';
    util_log_start(v_file_path);
    util_clob_append(replace(
      v_file_template,
      '{{PLEX_URL}}',
      c_plex_url));
    util_clob_add_to_export_files(
      p_export_files => v_export_files,
      p_name         => v_file_path);
    util_log_stop;

    -- export and import template - used by three files
    v_file_template := q'^rem Template generated by PLEX version {{PLEX_VERSION}}
rem More infos here: {{PLEX_URL}}

{{@}}echo off
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
{{@}}%scriptfile% ^
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
^'  ;
    v_file_path := 'scripts/templates/1_export_app_from_DEV.bat';
    util_log_start(v_file_path);
    util_clob_append(util_multi_replace(
      v_file_template,
      '{{PLEX_VERSION}}',  c_plex_version,
      '{{PLEX_URL}}',      c_plex_url,
      '{{SYSTEMROLE}}',    'DEV',
      $if $$apex_installed $then
      '{{APP_ID}}',        p_app_id,
      '{{APP_ALIAS}}',     v_app_alias,
      '{{APP_OWNER}}',     v_app_owner,
      '{{APP_WORKSPACE}}', v_app_workspace,
      $end
      '{{SCRIPTFILE}}',    'export_app_custom_code.sql',
      '{{LOGFILE}}',       'logs/export_app_%app_id%_from_%app_schema%_at_%systemrole%_%mydate%_%mytime%.log',
      '{{@}}',             c_at));
    util_clob_add_to_export_files(
      p_export_files => v_export_files,
      p_name         => v_file_path);
    util_log_stop;

    v_file_path := 'scripts/templates/2_install_app_into_INT.bat';
    util_log_start(v_file_path);
    util_clob_append(util_multi_replace(
      v_file_template,
      '{{PLEX_VERSION}}',  c_plex_version,
      '{{PLEX_URL}}',      c_plex_url,
      '{{SYSTEMROLE}}',    'INT',
      $if $$apex_installed $then
      '{{APP_ID}}',        p_app_id,
      '{{APP_ALIAS}}',     v_app_alias,
      '{{APP_OWNER}}',     v_app_owner,
      '{{APP_WORKSPACE}}', v_app_workspace,
      $end
      '{{SCRIPTFILE}}',    'install_app_custom_code.sql',
      '{{LOGFILE}}',       'logs/install_app_%app_id%_into_%app_schema%_at_%systemrole%_%mydate%_%mytime%.log',
      '{{@}}',             c_at));
    util_clob_add_to_export_files(
      p_export_files => v_export_files,
      p_name         => v_file_path);
    util_log_stop;

    v_file_path := 'scripts/templates/3_install_app_into_PROD.bat';
    util_log_start(v_file_path);
    util_clob_append(util_multi_replace(
      v_file_template,
      '{{PLEX_VERSION}}',  c_plex_version,
      '{{PLEX_URL}}',      c_plex_url,
      '{{SYSTEMROLE}}',    'PROD',
      $if $$apex_installed $then
      '{{APP_ID}}',        p_app_id,
      '{{APP_ALIAS}}',     v_app_alias,
      '{{APP_OWNER}}',     v_app_owner,
      '{{APP_WORKSPACE}}', v_app_workspace,
      $end
      '{{SCRIPTFILE}}',    'install_app_custom_code.sql',
      '{{LOGFILE}}',       'logs/install_app_%app_id%_into_%app_schema%_at_%systemrole%_%mydate%_%mytime%.log',
      '{{@}}',             c_at));
    util_clob_add_to_export_files(
      p_export_files => v_export_files,
      p_name         => v_file_path);
    util_log_stop;

    -- export app custom code template
    v_file_template := q'^-- Template generated by PLEX version {{PLEX_VERSION}}
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
BEGIN
  :app_id        := &2;
  :app_alias     := '&3';
  :app_schema    := '&4';
  :app_workspace := '&5';
END;
{{/}}


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
  name     VARCHAR2(255),
  contents CLOB)
ON COMMIT DELETE ROWS
--------------------------------------------------------------------------------
    ';
  END LOOP;
END;
{{/}}


prompt Do the app export, relocate files and save to temporary table
prompt ATTENTION: Depending on your options this could take some time ...
DECLARE
  v_files plex.tab_export_files;
BEGIN
  v_files := plex.backapp(
    -- These are the defaults - align it to your needs:^';
      $if $$apex_installed $then
      v_file_template := v_file_template || q'^
    p_app_id                    => :app_id,
    p_app_date                  => true,
    p_app_public_reports        => true,
    p_app_private_reports       => false,
    p_app_notifications         => false,
    p_app_translations          => true,
    p_app_pkg_app_mapping       => false,
    p_app_original_ids          => false,
    p_app_subscriptions         => true,
    p_app_comments              => true,
    p_app_supporting_objects    => null,
    p_app_include_single_file   => false,
    p_app_build_status_run_only => false,^';
      $end
      v_file_template := v_file_template || q'^
    p_include_object_ddl        => true,
    p_object_type_like          => null,
    p_object_type_not_like      => null,
    p_object_name_like          => null,
    p_object_name_not_like      => null,

    p_include_data              => false,
    p_data_as_of_minutes_ago    => 0,
    p_data_max_rows             => 1000,
    p_data_table_name_like      => null,
    p_data_table_name_not_like  => null,

    p_include_templates         => true,
    p_include_runtime_log       => true,
    p_include_error_log         => true,
    p_base_path_backend         => 'app_backend',
    p_base_path_frontend        => 'app_frontend',
    p_base_path_data            => 'app_data');

  -- relocate files to own project structure, we are inside the scripts folder
  FOR i IN 1..v_files.count LOOP
    v_files(i).name := '../' || v_files(i).name;
  END LOOP;

  FORALL i IN 1..v_files.count
    INSERT INTO temp_export_files VALUES (
      v_files(i).name,
      v_files(i).contents);
END;
{{/}}


prompt Create intermediate script file to unload the table contents into files
spool off
set termout off serveroutput on
spool "logs/temp_export_files.sql"
BEGIN
  -- create host commands for the needed directories (spool does not create missing directories)
  FOR i IN (WITH t AS (SELECT regexp_substr(
                                name,
                                '^((\w|\.)+\/)+' /*path without file name*/) AS dir
                         FROM temp_export_files)
            SELECT DISTINCT
                   dir,
                   -- This is for Windows to create a directory and suppress warning if it exist.
                   -- Align the command to your operating system:
                   'host mkdir "' || replace(dir,'/','\') || '" 2>NUL' AS mkdir
              FROM t
             WHERE dir IS NOT NULL) LOOP
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
{{/}}
spool off
set termout on serveroutput off
spool "&logfile." append


prompt Call the intermediate script file to save the files
spool off
{{@}}logs/temp_export_files.sql
set termout on serveroutput off
spool "&logfile." append


prompt Delete files from the global temporary table
COMMIT;


prompt =========================================================================
prompt Export DONE :-)
prompt
^'  ;
    v_file_path := 'scripts/templates/export_app_custom_code.sql';
    util_log_start(v_file_path);
    util_clob_append(util_multi_replace(
      v_file_template,
      '{{PLEX_VERSION}}', c_plex_version,
      '{{PLEX_URL}}',     c_plex_url,
      '{{/}}',            c_slash,
      '{{@}}',            c_at));
    util_clob_add_to_export_files(
      p_export_files => v_export_files,
      p_name         => v_file_path);
    util_log_stop;
    -- install app custom code template
    v_file_template := q'^-- Template generated by PLEX version {{PLEX_VERSION}}
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
BEGIN
  :app_id        := &2;
  :app_alias     := '&3';
  :app_schema    := '&4';
  :app_workspace := '&5';
END;
{{/}}
set define off


prompt
prompt Start Installation
prompt =========================================================================

prompt Install Backend
{{@}}install_backend_generated_by_plex.sql

prompt Compile Invalid Objects
BEGIN
  dbms_utility.compile_schema(
    schema         => user,
    compile_all    => false,
    reuse_settings => true);
END;
{{/}}

prompt Check Invalid Objects
DECLARE
  v_count   PLS_INTEGER;
  v_objects VARCHAR2(4000);
BEGIN
  SELECT COUNT(*), chr(10) ||
         listagg('- ' || object_name || ' (' || object_type || ')', chr(10)) within GROUP(ORDER BY object_name)
    INTO v_count, v_objects
    FROM user_objects
   WHERE status = 'INVALID';
  IF v_count > 0 THEN
    raise_application_error(-20000, chr(10) || chr(10) ||
                            'Found ' || v_count || ' invalid object' || CASE WHEN v_count > 1 THEN 's' END ||
                            ' :-( ' || chr(10) || '=============================' ||  v_objects || chr(10) || chr(10) );
  END IF;
END;
{{/}}

prompt Install Web Services
{{@}}install_web_services_generated_by_ords.sql

prompt Install Frontend
BEGIN
  apex_application_install.set_workspace_id(APEX_UTIL.find_security_group_id(:app_workspace));
  apex_application_install.set_application_alias(:app_alias);
  apex_application_install.set_application_id(:app_id);
  apex_application_install.set_schema(:app_schema);
  apex_application_install.generate_offset;
END;
{{/}}
{{@}}install_frontend_generated_by_apex.sql

prompt =========================================================================
prompt Installation DONE :-)
prompt
^'  ;
    v_file_path := 'scripts/templates/install_app_custom_code.sql';
    util_log_start(v_file_path);
    util_clob_append(util_multi_replace(
      v_file_template,
      '{{PLEX_VERSION}}', c_plex_version,
      '{{PLEX_URL}}',     c_plex_url,
      '{{/}}',            c_slash,
      '{{@}}',            c_at));
    util_clob_add_to_export_files(
      p_export_files => v_export_files,
      p_name         => v_file_path);
    util_log_stop;
  END create_template_files;

  PROCEDURE create_directory_keepers IS
    v_the_point VARCHAR2(30) := '. < this is the point ;-)';
  BEGIN
    v_file_path := 'docs/_save_your_docs_here.txt';
    util_log_start(v_file_path);
    util_clob_append(v_the_point);
    util_clob_add_to_export_files(
      p_export_files => v_export_files,
      p_name         => v_file_path);
    util_log_stop;
    --
    v_file_path   := 'scripts/logs/_spool_your_script_logs_here.txt';
    util_log_start(v_file_path);
    util_clob_append(v_the_point);
    util_clob_add_to_export_files(
      p_export_files => v_export_files,
      p_name         => v_file_path);
    util_log_stop;
    --
    v_file_path   := 'tests/_save_your_tests_here.txt';
    util_log_start(v_file_path);
    util_clob_append(v_the_point);
    util_clob_add_to_export_files(
      p_export_files => v_export_files,
      p_name         => v_file_path);
    util_log_stop;
  END create_directory_keepers;

  PROCEDURE finish IS
  BEGIN
    util_ensure_unique_file_names(v_export_files);
    IF p_include_error_log THEN
      util_clob_create_error_log(v_export_files);
    END IF;
    IF p_include_runtime_log THEN
      util_clob_create_runtime_log(v_export_files);
    END IF;
  END finish;

BEGIN
  init;
  $if $$apex_installed $then
  check_owner;
  IF p_app_id IS NOT NULL THEN
    process_apex_app;
  END IF;
  $end
  IF p_include_object_ddl THEN
    process_user_ddl;
    process_object_ddl;
    $if NOT $$debug_on $then
    -- excluded in debug mode (potential long running object types)
    process_object_grants;
    process_ref_constraints;
    $end
    create_backend_install_file;
  END IF;
  $if $$ords_installed $then
  IF p_include_ords_modules THEN
    process_ords_modules;
  END IF;
  $end
  IF p_include_data THEN
    process_data;
  END IF;
  IF p_include_templates THEN
    create_template_files;
    create_directory_keepers;
  END IF;
  finish;
  RETURN v_export_files;
END backapp;

--------------------------------------------------------------------------------------------------------------------------------

PROCEDURE add_query (
  p_query     VARCHAR2,
  p_file_name VARCHAR2,
  p_max_rows  NUMBER DEFAULT 1000)
IS
  v_index PLS_INTEGER;
BEGIN
  v_index                      := g_queries.count + 1;
  g_queries(v_index).query     := p_query;
  g_queries(v_index).file_name := p_file_name;
  g_queries(v_index).max_rows  := p_max_rows;
END add_query;

--------------------------------------------------------------------------------------------------------------------------------

FUNCTION queries_to_csv (
  p_delimiter             IN VARCHAR2 DEFAULT ',',
  p_quote_mark            IN VARCHAR2 DEFAULT '"',
  p_header_prefix         IN VARCHAR2 DEFAULT NULL,
  p_include_runtime_log   IN BOOLEAN DEFAULT true,
  p_include_error_log     IN BOOLEAN DEFAULT true)
RETURN tab_export_files IS
  v_export_files tab_export_files;

  PROCEDURE init IS
  BEGIN
    IF g_queries.count = 0 THEN
      raise_application_error(
        -20201,
        'You need first to add queries by using plex.add_query. Calling plex.queries_to_csv clears the global queries array for subsequent processing.');
    END IF;
    util_log_init(p_module => 'plex.queries_to_csv');
    util_log_start('init');
    v_export_files := NEW tab_export_files();
    util_log_stop;
  END init;

  PROCEDURE process_queries IS
  BEGIN
    FOR i IN g_queries.first..g_queries.last LOOP
      BEGIN
        util_log_start('process_query ' || TO_CHAR(i) || ': ' || g_queries(i).file_name);
        util_clob_query_to_csv(
          p_query         => g_queries(i).query,
          p_max_rows      => g_queries(i).max_rows,
          p_delimiter     => p_delimiter,
          p_quote_mark    => p_quote_mark,
          p_header_prefix => p_header_prefix);
        util_clob_add_to_export_files(
          p_export_files => v_export_files,
          p_name         => g_queries(i).file_name || '.csv');
        util_log_stop;
      EXCEPTION
        WHEN OTHERS THEN
          util_log_error(g_queries(i).file_name);
      END;
    END LOOP;
  END process_queries;

  PROCEDURE finish IS
  BEGIN
    g_queries.DELETE;
    util_ensure_unique_file_names(v_export_files);
    IF p_include_error_log THEN
      util_clob_create_error_log(v_export_files);
    END IF;
    IF p_include_runtime_log THEN
      util_clob_create_runtime_log(v_export_files);
    END IF;
  END finish;

BEGIN
  init;
  process_queries;
  finish;
  RETURN v_export_files;
EXCEPTION
  WHEN others THEN
    g_queries.DELETE;
END queries_to_csv;

--------------------------------------------------------------------------------------------------------------------------------

FUNCTION to_zip (p_file_collection IN tab_export_files) RETURN BLOB IS
  v_zip BLOB;
BEGIN
  dbms_lob.createtemporary(v_zip, true);
  util_log_start('post processing with to_zip: ' || p_file_collection.count || ' files');
  FOR i IN 1..p_file_collection.count LOOP
    util_zip_add_file(
      p_zipped_blob => v_zip,
      p_name    => p_file_collection(i).name,
      p_content => util_clob_to_blob(p_file_collection(i).contents));
  END LOOP;
  util_zip_finish(v_zip);
  util_log_stop;
  util_log_calc_runtimes;
  RETURN v_zip;
END to_zip;

--------------------------------------------------------------------------------------------------------------------------------

FUNCTION view_error_log RETURN tab_error_log PIPELINED IS
BEGIN
  FOR i IN 1..g_errlog.count LOOP
    PIPE ROW (g_errlog(i));
  END LOOP;
END view_error_log;

--------------------------------------------------------------------------------------------------------------------------------

FUNCTION view_runtime_log RETURN tab_runtime_log PIPELINED IS
  v_return rec_runtime_log;
BEGIN
  v_return.overall_start_time := g_runlog.start_time;
  v_return.overall_run_time   := round(g_runlog.run_time, 3);
  FOR i IN 1..g_runlog.data.count LOOP
    v_return.step      := i;
    v_return.elapsed   := round(g_runlog.data(i).elapsed, 3);
    v_return.execution := round(g_runlog.data(i).execution, 6);
    v_return.module    := g_runlog.module;
    v_return.action    := g_runlog.data(i).action;
    PIPE ROW (v_return);
  END LOOP;
END view_runtime_log;

--------------------------------------------------------------------------------------------------------------------------------

BEGIN
  IF dbms_lob.istemporary(g_clob) = 0 THEN
    dbms_lob.createtemporary(g_clob, true);
  END IF;
END plex;
/