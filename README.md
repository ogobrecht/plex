
- [Package PLEX](#plex)
- [Function backapp](#backapp)
- [Procedure add_query](#add_query)
- [Function queries_to_csv](#queries_to_csv)
- [Function to_zip](#to_zip)
- [Function view_runtime_log](#view_runtime_log)


<h1><a id="plex"></a>Package PLEX</h1>
<!--===============================-->

PL/SQL Export Utilities

PLEX was created to be able to quickstart version control for existing (APEX) apps and has currently two main functions called __BackApp__ and __Queries_to_CSV__. Queries_to_CSV is used by BackApp as a helper function, but its functionality is also useful standalone. 

See also this resources for more information:

- PLEX project page on [GitHub](https://github.com/ogobrecht/plex)
- Blog post on how to [getting started](FIXME: providelink)

[Feedback is welcome](https://github.com/ogobrecht/plex/issues/new).


STANDARDS

- All main functions returning a file collection of type apex_t_export_files
- All main functions setting the session module and action infos while procssing their work


DEPENDENCIES

- APEX 5.1.4 because we use the packages APEX_EXPORT and APEX_ZIP

SIGNATURE

```sql
PACKAGE PLEX AUTHID current_user IS
c_plex_name        CONSTANT VARCHAR2(30 CHAR) := 'PLEX - PL/SQL Export Utilities';
c_plex_version     CONSTANT VARCHAR2(10 CHAR) := '0.15.0';
c_plex_url         CONSTANT VARCHAR2(40 CHAR) := 'https://github.com/ogobrecht/plex';
c_plex_license     CONSTANT VARCHAR2(10 CHAR) := 'MIT';
c_plex_license_url CONSTANT VARCHAR2(60 CHAR) := 'https://github.com/ogobrecht/plex/blob/master/LICENSE.txt';
c_plex_author      CONSTANT VARCHAR2(20 CHAR) := 'Ottmar Gobrecht';
```


<h2><a id="backapp"></a>Function backapp</h2>
<!------------------------------------------>

Get a file collection of an APEX application (or the current user/schema only) including:

- The app export SQL files splitted ready to use for version control and deployment
- Optional the DDL scripts for all objects and grants
- Optional the data in csv files - useful for small applications in cloud environments for a logical backup
- Everything in a (hopefully) nice directory structure

EXAMPLE

```sql
DECLARE
  l_file_collection apex_t_export_files;
BEGIN
  l_file_collection := plex.backapp(
    p_app_id             => 100,
    p_include_object_ddl => false,
    p_include_data       => false
  );

  -- do something with the file collection
  FOR i IN 1..l_file_collection.count LOOP
    dbms_output.put_line(
         i 
      || ' | ' 
      || lpad(round(length(l_file_collection(i).contents) / 1024), 3) || ' kB' 
      || ' | '
      || l_file_collection(i).name 
      );
  END LOOP;
END;
```

SIGNATURE

```sql
FUNCTION backapp (
  p_app_id                    IN NUMBER   DEFAULT null,  -- If null, we simply skip the APEX app export.
  p_app_date                  IN BOOLEAN  DEFAULT true,  -- If true, include export date and time in the result.
  p_app_public_reports        IN BOOLEAN  DEFAULT true,  -- If true, include public reports that a user saved.
  p_app_private_reports       IN BOOLEAN  DEFAULT false, -- If true, include private reports that a user saved.
  p_app_notifications         IN BOOLEAN  DEFAULT false, -- If true, include report notifications.
  p_app_translations          IN BOOLEAN  DEFAULT true,  -- If true, include application translation mappings and all text from the translation repository.
  p_app_pkg_app_mapping       IN BOOLEAN  DEFAULT false, -- If true, export installed packaged applications with references to the packaged application definition. If FALSE, export them as normal applications.
  p_app_original_ids          IN BOOLEAN  DEFAULT true,  -- If true, export with the IDs as they were when the application was imported.
  p_app_subscriptions         IN BOOLEAN  DEFAULT true,  -- If true, components contain subscription references.
  p_app_comments              IN BOOLEAN  DEFAULT true,  -- If true, include developer comments.
  p_app_supporting_objects    IN VARCHAR2 DEFAULT null,  -- If 'Y', export supporting objects. If 'I', automatically install on import. If 'N', do not export supporting objects. If null, the application's include in export deployment value is used.
  p_app_include_single_file   IN BOOLEAN  DEFAULT false, -- If true, the single sql install file is also included beside the splitted files.
  p_app_build_status_run_only IN BOOLEAN  DEFAULT false, -- If true, the build status of the app will be overwritten to RUN_ONLY.

  p_include_object_ddl        IN BOOLEAN  DEFAULT false, -- If true, include DDL of current user/schema and all its objects.
  p_object_filter_regex       IN VARCHAR2 DEFAULT null,  -- Filter the schema objects with the provided object prefix.

  p_include_data              IN BOOLEAN  DEFAULT false, -- If true, include CSV data of each table.
  p_data_as_of_minutes_ago    IN NUMBER   DEFAULT 0,     -- Read consistent data with the resulting timestamp(SCN).
  p_data_max_rows             IN NUMBER   DEFAULT 1000,  -- Maximum number of rows per table.
  p_data_table_filter_regex   IN VARCHAR2 DEFAULT null,  -- Filter user_tables with the given regular expression.

  p_include_templates         IN BOOLEAN  DEFAULT true,  -- If true, include templates for README.md, export and install scripts.
  p_include_runtime_log       IN BOOLEAN  DEFAULT true   -- If true, generate file plex_backapp_log.md with runtime statistics.
) RETURN apex_t_export_files;
```


<h2><a id="add_query"></a>Procedure add_query</h2>
<!----------------------------------------------->

Add a query to be processed by the method queries_to_csv. You can add as many queries as you like.

EXAMPLE

```sql
BEGIN
  plex.add_query(
    p_query     => 'select * from user_tables',
    p_file_name => 'user_tables'
  );
END;
```

SIGNATURE

```sql
PROCEDURE add_query (
  p_query     IN VARCHAR2,             -- The query itself
  p_file_name IN VARCHAR2,             -- File name like 'Path/to/your/file-name-without-extension'.
  p_max_rows  IN NUMBER   DEFAULT 1000 -- The maximum number of rows to be included in your file.
);
```


<h2><a id="queries_to_csv"></a>Function queries_to_csv</h2>
<!-------------------------------------------------------->

Export one or more queries as CSV data within a file collection.

EXAMPLE

```sql
DECLARE
  l_file_collection apex_t_export_files;
BEGIN

  --fill the queries array
  plex.add_query(
    p_query     => 'select * from user_tables',
    p_file_name => 'user_tables'
  );
  plex.add_query(
    p_query     => 'select * from user_tab_columns',
    p_file_name => 'user_tab_columns',
    p_max_rows  => 10000
  );

  -- process the queries
  l_file_collection := plex.queries_to_csv;

  -- do something with the file collection
  FOR i IN 1..l_file_collection.count LOOP
    dbms_output.put_line(
         i 
      || ' | ' 
      || lpad(round(length(l_file_collection(i).contents) / 1024), 3) || ' kB' 
      || ' | '
      || l_file_collection(i).name 
      );
  END LOOP;
END;
```

SIGNATURE

```sql
FUNCTION queries_to_csv (
  p_delimiter                 IN VARCHAR2 DEFAULT ',',   -- The column delimiter - there is also plex.tab as a helper function.
  p_quote_mark                IN VARCHAR2 DEFAULT '"',   -- Used when the data contains the delimiter character.
  p_header_prefix             IN VARCHAR2 DEFAULT NULL,  -- Prefix the header line with this text.
  p_include_runtime_log       IN BOOLEAN  DEFAULT true   -- If true, generate file plex_queries_to_csv_log.md with runtime statistics.
) RETURN apex_t_export_files;
```


<h2><a id="to_zip"></a>Function to_zip</h2>
<!---------------------------------------->

Convert a file collection to a zip file.

EXAMPLE

```sql
DECLARE
  l_zip BLOB;
BEGIN
    l_zip := plex.to_zip(plex.backapp(
      p_app_id             => 100,
      p_include_object_ddl => true
    ));

  -- do something with the zip file...
END;
```

SIGNATURE

```sql
FUNCTION to_zip (
  p_file_collection IN apex_t_export_files -- The file collection to process with APEX_ZIP.
) RETURN BLOB;
```


<h2><a id="view_runtime_log"></a>Function view_runtime_log</h2>
<!------------------------------------------------------------>

View the log from the last plex run. The internal array for the runtime logis cleared after each call of  BackApp or Queries_to_CSV.

EXAMPLE

```sql
SELECT * FROM TABLE(plex.view_runtime_log);
```

SIGNATURE

```sql
FUNCTION view_runtime_log RETURN tab_runtime_log PIPELINED;
```


