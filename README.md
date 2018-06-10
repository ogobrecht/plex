# PLEX

Oracle PL/SQL export utilities

# Examples

## Backup of an APEX application

```sql
DECLARE
  l_file      plex.file;
  l_mail_to   VARCHAR2(100 CHAR) := 'email@example.com';
  l_mail_id   NUMBER;
BEGIN

  -- get the zip file
  plex.apex_backapp(
    p_app_id          => 2600,
    p_file            => l_file
  );

  -- send it via APEX mail or do whatever with it
  apex_util.set_security_group_id(apex_util.find_security_group_id('YOUR_WORKSPACE_NAME') );
  l_mail_id   := apex_mail.send(
    p_to     => l_mail_to,
    p_from   => l_mail_to,
    p_subj   => l_file.file_name,
    p_body   => l_file.file_name
  );
  apex_mail.add_attachment(
    p_mail_id      => l_mail_id,
    p_attachment   => l_file.blob_content,
    p_filename     => l_file.file_name,
    p_mime_type    => l_file.mime_type
  );
  apex_mail.push_queue;

  -- free the temp space, which was created by plex for the blob_content column
  dbms_lob.freetemporary(l_file.blob_content);

END;
/
```

## Export one or more queries as csv data within a zip file:

```sql
DECLARE
  l_file plex.file;
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

  -- get the zip file
  l_file.file_name := 'user-tables';
  plex.queries_to_csv(p_file => l_file);

  -- do something with the file...

  -- free the temp space, which was created by plex for the blob_content column
  dbms_lob.freetemporary(l_file.blob_content);

END;
/
```
