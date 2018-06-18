# PLEX - PL/SQL Export Utilities

One word regarding the parameters in this package: To be usable in the SQL and PL/SQL context all boolean parameters are coded as varchars. We check only the uppercased first character:

- 1 (one), Y [ES], T [RUE] will be parsed as TRUE
- 0 (zero), N [O], F [ALSE] will be parsed as FALSE
- If we can't find a match the default for the parameter is used
- This means the following keywords are also correct ;-)
  - `yes please`
  - `no thanks`
  - `yeah`
  - `nope`
  - `Yippie Yippie Yeah Yippie Yeah`
  - `time goes by...` - that is true, right?
  - All that fun only because Oracle does not support boolean values in pure SQL context...


## BackApp

Get a zip file for an APEX application (or schema) including:

- The app export SQL file - full and splitted ready to use for version control
- All objects DDL, object grants DDL
- Optional the data in csv files - useful for small applications in cloud environments for a logical backup
- Everything in a (hopefully) nice directory structure 

### Simple Call

```sql
DECLARE
  l_zip blob;
BEGIN

  -- do the backapp
  l_zip := plex.backapp(p_app_id => 100);

  -- do something with the zip file

END;
/
```


### Signature

```sql
FUNCTION backapp
(
  p_app_id                   IN NUMBER DEFAULT NULL,   -- If not provided we simply skip the APEX app export.
  p_app_public_reports       IN VARCHAR2 DEFAULT 'Y',  -- Include public reports in your application export.
  p_app_private_reports      IN VARCHAR2 DEFAULT 'N',  -- Include private reports in your application export.
  p_app_report_subscriptions IN VARCHAR2 DEFAULT 'N',  -- Include IRt or IG subscription settings in your application export.
  p_app_translations         IN VARCHAR2 DEFAULT 'Y',  -- Include translations in your application export.
  p_app_subscriptions        IN VARCHAR2 DEFAULT 'Y',  -- Include component subscriptions.
  p_app_original_ids         IN VARCHAR2 DEFAULT 'N',  -- Include original workspace id, application id and component ids.
  p_app_packaged_app_mapping IN VARCHAR2 DEFAULT 'N',  -- Include mapping between the application and packaged application if it exists.                        
  p_include_object_ddl       IN VARCHAR2 DEFAULT 'Y',  -- Include DDL of current user/schema and its objects.
  p_object_prefix            IN VARCHAR2 DEFAULT NULL, -- Filter the schema objects with the provided object prefix.                        
  p_include_data             IN VARCHAR2 DEFAULT 'N',  -- Include CSV data of each table.
  p_data_max_rows            IN NUMBER DEFAULT 1000,   -- Maximal number of rows per table.                        
  p_debug                    IN VARCHAR2 DEFAULT 'N'   -- Generate plex_backapp_log.md in the root of the zip file.
) RETURN BLOB;
```


## Queries to CSV

Export one or more queries as CSV data within a zip file.


### Simple Call

```sql
DECLARE
  l_zip blob;
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
  l_zip := plex.queries_to_csv;

  -- do something with the zip file...

END;
/
```


### Signature

```sql
FUNCTION queries_to_csv
(
  p_delimiter       IN VARCHAR2 DEFAULT ',',  -- The column delimiter - there is also plex.tab as a helper function.
  p_quote_mark      IN VARCHAR2 DEFAULT '"',  -- Used when the data contains the delimiter character.
  p_line_terminator IN VARCHAR2 DEFAULT lf,   -- Default is line feed (plex.lf) - there are also plex.crlf and plex.cr as helpers.
  p_header_prefix   IN VARCHAR2 DEFAULT NULL, -- Prefix the header line with this text.
  p_debug           IN VARCHAR2 DEFAULT 'N'   -- Generate plex_queries_to_csv_log.md in the root of the zip file.
) RETURN BLOB;
```


