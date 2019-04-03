prompt Installing PL/SQL Export Utilities
SET DEFINE OFF

BEGIN
  EXECUTE IMMEDIATE q'[ alter session set plsql_ccflags='apex_exists:false' ]';
END;
/

@plex.pks

@plex.pkb