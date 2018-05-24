BEGIN
  apex_util.set_security_group_id(apex_util.find_security_group_id(p_workspace => 'FARC'));
  plex.g_channel_apex_mail := 'ottmar.gobrecht@linde.com';
  plex.apex_backapp(p_app_id             => 200,
                    p_object_prefix      => 'CTLG_',
                    p_include_data       => TRUE);
END;
/

--SELECT INSTR(nvl(null, ' '),',') FROM dual;
--SELECT POWER(2, 16) FROM dual;
