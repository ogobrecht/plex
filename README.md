# PLEX - PL/SQL export utilities


## BackApp

Get a zip file for an APEX application (or schema) including:

- The app export SQL file - full and splitted ready to use for version control
- All objects DDL, object grants DDL
- Optional the data in csv files - useful for small applications in cloud environments for a logical backup
- Everything in a (hopefully) nice directory structure 

### Simple Call

```sql
DECLARE
  l_zip_file blob;
BEGIN

  -- do the backapp
  l_zip_file := plex.backapp(p_app_id => 100);

  -- do something with the zip file

END;
/
```


### Signature

```sql
FUNCTION backapp
(
  p_app_id                   IN NUMBER DEFAULT NULL,   -- If not provided we simply skip the APEX app export.
  p_app_public_reports       IN BOOLEAN DEFAULT TRUE,  -- Include public reports in your application export.
  p_app_private_reports      IN BOOLEAN DEFAULT FALSE, -- Include private reports in your application export.
  p_app_report_subscriptions IN BOOLEAN DEFAULT FALSE, -- Include IRt or IG subscription settings in your application export.
  p_app_translations         IN BOOLEAN DEFAULT TRUE,  -- Include translations in your application export.
  p_app_subscriptions        IN BOOLEAN DEFAULT TRUE,  -- Include component subscriptions.
  p_app_original_ids         IN BOOLEAN DEFAULT FALSE, -- Include original workspace id, application id and component ids.
  p_app_packaged_app_mapping IN BOOLEAN DEFAULT FALSE, -- Include mapping between the application and packaged application if it exists.

  p_include_object_ddl       IN BOOLEAN DEFAULT TRUE,  -- Include DDL of current user/schema and its objects.
  p_object_prefix            IN VARCHAR2 DEFAULT NULL, -- Filter the schema objects with the provided object prefix.

  p_include_data             IN BOOLEAN DEFAULT FALSE, -- Include CSV data of each table.
  p_data_max_rows            IN NUMBER DEFAULT 1000,   -- Maximal number of rows per table.

  p_debug                    IN BOOLEAN DEFAULT FALSE  -- Generate plex_backapp_log.md in the root of the zip file.
) RETURN BLOB;
```


## Queries to CSV

Export one or more queries as CSV data within a zip file.


### Simple Call

```sql
DECLARE
  l_zip_file blob;
BEGIN

  --fill the queries array
  plex.add_query(
    p_query       => 'select * from user_tables',
    p_file_name   => 'user_tables'
  );
  plex.add_query(
    p_query       => 'select * from user_tab_columns',
    p_file_name   => 'user_tab_columns',
    p_max_rows    => 10000
  );

  -- process the queries
  l_zip_file := plex.queries_to_csv;

  -- do something with the file...

END;
/
```


### Signature

```sql
FUNCTION queries_to_csv
(
  p_delimiter       IN VARCHAR2 DEFAULT ',',
  p_quote_mark      IN VARCHAR2 DEFAULT '"',
  p_line_terminator IN VARCHAR2 DEFAULT chr(10),
  p_header_prefix   IN VARCHAR2 DEFAULT NULL,
  p_debug           BOOLEAN DEFAULT FALSE -- Generate debug_log.md in the root of the zip file.
) RETURN BLOB;
```


