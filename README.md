# PLEX

Oracle PL/SQL export utilities

# Examples

## Backup of an APEX application

```sql
BEGIN
  plex.set_channels(
    p_apex_mail             => 'email@example.com',
    p_apex_mail_workspace   => 'YOUR_WORKSPACE_NAME' --> only needed for mail channel when running outside of an APEX session
  );
  plex.apex_backapp(p_app_id   => your_app_id);
END;
/
```

## Export one or more queries as csv data within a zip file:

```sql
BEGIN
  plex.set_channels(
    p_apex_mail             => 'email@example.com',
    p_apex_mail_workspace   => 'YOUR_WORKSPACE_NAME' --> only needed for mail channel when running outside of an APEX session
  );
  plex.add_query(
    p_query       => 'select * from user_tables',
    p_file_name   => 'user_tables'
  );
  plex.add_query(
    p_query       => 'select * from user_tab_columns',
    p_file_name   => 'user_tab_columns',
    p_max_rows    => 10000
  );
  plex.queries_to_csv(p_zip_file_name   => 'user-tables');
END;
/
```
