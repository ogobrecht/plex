timing start test_export
set verify off feedback off heading off
set trimout on trimspool on pagesize 0 linesize 5000 long 100000000 longchunksize 32767
whenever sqlerror exit sql.sqlcode rollback
whenever oserror continue
variable zip clob

prompt
prompt PLEX Test Export Format INSERT With Multiple Data Types (create data)
prompt =====================================================================

prompt Insert 1000 rows into plex_test_multiple_datatypes
declare
  l_rows_tab       plex_test_multiple_datatypes_api.t_rows_tab;
  l_number_records pls_integer := 1000;
begin
  l_rows_tab := plex_test_multiple_datatypes_api.t_rows_tab();
  l_rows_tab.extend(l_number_records);
  for i in 1 .. l_number_records loop
    l_rows_tab(i) := plex_test_multiple_datatypes_api.get_a_row;
  end loop;
  plex_test_multiple_datatypes_api.create_rows(l_rows_tab);
  commit;
end;
/

timing stop
prompt =======================================================
prompt Done :-)
prompt also see this: https://connor-mcdonald.com/2019/05/17/hacking-together-faster-inserts/
prompt and this:      https://www.youtube.com/watch?v=LdGtl09C6DM
prompt alter session set cursor_sharing = force;
prompt insert all
prompt    into ...
prompt    into ...
prompt    into ...
prompt    into ...
prompt    into ...
prompt alter session set cursor_sharing = exact;

/*

numlist, vc2list (as synonyms):
- https://sqlpatterns.wordpress.com/tag/sys-odcivarchar2list/
- https://laurentschneider.com/wordpress/2007/12/predefined-collections.html


create or replace function as_insert(p_query varchar2, p_batch int default 10) return sys.odcivarchar2list pipelined as
    l_theCursor     integer default dbms_sql.open_cursor;
    l_columnValue   varchar2(4000);
    l_status        integer;
    l_descTbl       dbms_sql.desc_tab;
    l_colCnt        number;
    n number := 0;

    l_tname varchar2(200) := substr(p_query,instr(p_query,' ',-1,1)+1);
    l_collist varchar2(32000);
    l_colval varchar2(32000);
    l_dml varchar2(32000);

    l_nls sys.odcivarchar2list := sys.odcivarchar2list();

begin
   if l_tname is null then l_tname := '@@TABLE@@'; end if;

   select value
   bulk collect into l_nls
   from v$nls_parameters
   where parameter in (
      'NLS_DATE_FORMAT',
      'NLS_TIMESTAMP_FORMAT',
      'NLS_TIMESTAMP_TZ_FORMAT')
   order by parameter;

    execute immediate 'alter session set nls_date_format=''yyyy-mm-dd hh24:mi:ss'' ';
    execute immediate 'alter session set nls_timestamp_format=''yyyy-mm-dd hh24:mi:ssff'' ';
    execute immediate 'alter session set nls_timestamp_tz_format=''yyyy-mm-dd hh24:mi:ssff tzr'' ';

    dbms_sql.parse(  l_theCursor,  p_query, dbms_sql.native );
    dbms_sql.describe_columns( l_theCursor, l_colCnt, l_descTbl );

    for i in 1 .. l_colCnt loop
        dbms_sql.define_column(l_theCursor, i, l_columnValue, 4000);
        l_collist := l_collist || l_descTbl(i).col_name||',';
    end loop;
    l_collist := 'into '||l_tname||'('||rtrim(l_collist,',')||')';

    l_status := dbms_sql.execute(l_theCursor);

    pipe row('alter session set cursor_sharing = force;');
    while ( dbms_sql.fetch_rows(l_theCursor) > 0 ) loop
       n := n + 1;

       if mod(n,p_batch) = 1 then
          pipe row('insert all ');
       end if;

        for i in 1 .. l_colCnt loop
            dbms_sql.column_value( l_theCursor, i, l_columnValue );
            if l_columnValue is null then
              l_colval := l_colval || 'null,';
            elsif l_descTbl(i).col_type in (1,8,9,96,112) then
              l_colval := l_colval || 'q''{'||l_columnValue ||'}''' || ',';
            elsif l_descTbl(i).col_type in (2,100,101) then
              l_colval := l_colval || l_columnValue || ',';
            elsif l_descTbl(i).col_type in (12) then
              l_colval := l_colval || 'to_date('''||l_columnValue||''',''yyyy-mm-dd hh24:mi:ss'')' || ',';
            elsif l_descTbl(i).col_type in (180) then
              l_colval := l_colval || 'to_timestamp('''||l_columnValue||''',''yyyy-mm-dd hh24:mi:ssff'')' || ',';
            elsif l_descTbl(i).col_type in (181) then
              l_colval := l_colval ||'to_timestamp_tz('''||l_columnValue||''',''yyyy-mm-dd hh24:mi:ssff tzr'')' || ',';
            elsif l_descTbl(i).col_type in (231) then
              l_colval := l_colval || 'to_timestamp('''||l_columnValue||''',''yyyy-mm-dd hh24:mi:ssff'')' || ',';
            elsif l_descTbl(i).col_type in (182) then
              l_colval := l_colval || 'to_yminterval('''||l_columnValue||''')' || ',';
            elsif l_descTbl(i).col_type in (183) then
              l_colval := l_colval ||'to_dsinterval('''||l_columnValue||''')'  || ',';
            end if;
        end loop;
        l_colval := rtrim(l_colval,',')||')';
        pipe row( l_collist  );
        pipe row( '  values ('||l_colval );
        if mod(n,p_batch) = 0 then
          pipe row('select * from dual;');
        end if;
        l_colval := null;
    end loop;
    if n = 0 then
      pipe row( 'No data found ');
    elsif mod(n,p_batch) != 0 then
      pipe row('select * from dual;');
    end if;
    pipe row('alter session set cursor_sharing = exact;');

    execute immediate 'alter session set nls_date_format='''||l_nls(1)||''' ';
    execute immediate 'alter session set nls_timestamp_format='''||l_nls(2)||''' ';
    execute immediate 'alter session set nls_timestamp_tz_format='''||l_nls(3)||''' ';
    return;
end;
/

*/
