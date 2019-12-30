-- Inline function because of boolean parameters (needs Oracle 12c or higher).
-- Alternative create a helper function and call that in a SQL context.
WITH
  FUNCTION backapp RETURN BLOB IS
  BEGIN
    RETURN plex.to_zip(plex.backapp(
      p_app_id               => 100,
      p_include_object_ddl   => true,
      p_include_ords_modules => true,
      p_include_data         => true,
      p_include_templates    => true));
  END backapp;
SELECT backapp FROM dual;
/

select * from table(plex.view_runtime_log);


