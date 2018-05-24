# plex

Oracle PL/SQL export utilities

# Examples

## Export an APEX App

```sql
BEGIN
  --> set the APEX workspace to be able to send emails from within SQL tool
  apex_util.set_security_group_id(apex_util.find_security_group_id(p_workspace => 'HR'));
  
  --> all active channels will work parallel, see also package spec for possible channels
  plex.g_channel_apex_mail := 'ottmar.gobrecht@gmail.com';

  plex.apex_backapp(p_app_id             => 200,
                    p_object_prefix      => 'CTLG_',
                    p_include_data       => TRUE);
END;
/
```
