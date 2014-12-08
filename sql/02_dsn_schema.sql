--
-- PostgreSQL database dump
--

SET statement_timeout = 0;
SET lock_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;

--
-- Name: plpgsql; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;


--
-- Name: EXTENSION plpgsql; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION plpgsql IS 'PL/pgSQL procedural language';


--
-- Name: intarray; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS intarray WITH SCHEMA public;


--
-- Name: EXTENSION intarray; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION intarray IS 'functions, operators, and index support for 1-D arrays of integers';


--
-- Name: pg_buffercache; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS pg_buffercache WITH SCHEMA public;


--
-- Name: EXTENSION pg_buffercache; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION pg_buffercache IS 'examine the shared buffer cache';


--
-- Name: pg_trgm; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA public;


--
-- Name: EXTENSION pg_trgm; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION pg_trgm IS 'text similarity measurement and index searching based on trigrams';


--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


SET search_path = public, pg_catalog;

--
-- Name: c_fti(); Type: FUNCTION; Schema: public; Owner: webadmin
--

CREATE FUNCTION c_fti() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
declare
  fullstr text;
  s text;
  i integer;
begin
if TG_OP = 'INSERT' then
	if new.usernum > 0 then
		update users set posts = posts + 1, posttime = new.cdate where num = new.usernum;
		fullstr := new.name || ' ' || new.uid || ' ' || new.content;
	else
		fullstr := new.name || ' ' || new.content;
	end if;
	s := 'update ' || new.ptable || ' set comments = comments + 1, commdate = ' || new.cdate || ' where id = ' || new.pid;
	execute(s);
	i := fti_insert(new.ptable || '_fti', new.pid, new.cid, fullstr);
	return new;
elsif TG_OP = 'DELETE' then
	if old.usernum > 0 then
		update users set posts = posts - 1, posttime = abstime(now())::int where num = old.usernum;
	end if;
	s := 'update ' || old.ptable || ' set comments = comments - 1, commdate = abstime(now())::int where id = ' || old.pid;
        execute(s);
	i := fti_delete(old.ptable || '_fti', old.pid, old.cid);
	return old;
elsif TG_OP = 'UPDATE' then
	if (old.uid || ' ' || old.name || ' ' || old.content) <> (new.uid || ' ' || new.name || ' ' || new.content) then
		i := fti_delete(old.ptable || '_fti', old.pid, old.cid);
		if new.usernum > 0 then
			fullstr := new.name || ' ' || new.uid || ' ' || new.content;
		else
			fullstr := new.name || ' ' || new.content;
		end if;
		i := fti_insert(new.ptable || '_fti', new.pid, new.cid, fullstr);
	end if;
	return new;
else
	return null;
end if;
end;
$$;


ALTER FUNCTION public.c_fti() OWNER TO webadmin;

--
-- Name: fti_delete(text, integer, integer); Type: FUNCTION; Schema: public; Owner: webadmin
--

CREATE FUNCTION fti_delete(ftitable text, k integer, c integer) RETURNS integer
    LANGUAGE plpgsql
    AS $$
begin
if k is null then
	return 0;
end if;
if c is null then
	execute('delete from ' || ftitable || ' where k = ' || k || ' and c is null');
else
	execute('delete from ' || ftitable || ' where k = ' || k || ' and c = ' || c);
end if;
return 0;
end;
$$;


ALTER FUNCTION public.fti_delete(ftitable text, k integer, c integer) OWNER TO webadmin;

--
-- Name: fti_insert(text, integer, integer, text); Type: FUNCTION; Schema: public; Owner: webadmin
--

CREATE FUNCTION fti_insert(p_ftitable text, p_k integer, p_c integer, p_fullstr text) RETURNS integer
    LANGUAGE plpgsql
    AS $_$
declare
fullstr text;
row record;
v_c text;

begin
if p_k is null or p_fullstr is null then
        return 0;
end if;
-- strip html tags
fullstr := regexp_replace(p_fullstr, '<[^<>]+>','','g');
-- lower contents
fullstr := lower(regexp_replace(fullstr, '&lt;|&gt;|&quot;|&nbsp;|&amp;|&copy;|<|>|''|"|%|&|©|,|/|~|`|!|#|=|:|;', ' ', 'g'));

if p_c is null then
        v_c := 'null';
else
        v_c := p_c;
end if;
-- one dynamic query!
execute('insert into ' || p_ftitable || 
        ' select ' || p_k || ', ' || v_c || ', 
            substr(a, 1,50) from regexp_split_to_table(' || quote_literal(fullstr) || ',''['' || 
            E''' || E'\\\\\\\\' || ''' || 
            E''' || E'\\\\' || ''' || ''s'' || 
            E''' || E'\\\\' || ''' || ''$'' || 
            E''' || E'\\\\' || ''' || ''^'' || 
            E''' || E'\\\\' || ''' || ''*'' || 
            E''' || E'\\\\' || ''' || ''('' || 
            E''' || E'\\\\' || ''' || '')'' || 
            E''' || E'\\\\' || ''' || ''+'' || 
            E''' || E'\\\\' || ''' || ''|'' || 
            E''' || E'\\\\' || ''' || ''['' || 
            E''' || E'\\\\' || ''' || '']'' || 
            E''' || E'\\\\' || ''' || ''{'' || 
            E''' || E'\\\\' || ''' ||''}?]'') as t (a) group by a having length(a) > 1');
return 1;
end;
$_$;


ALTER FUNCTION public.fti_insert(p_ftitable text, p_k integer, p_c integer, p_fullstr text) OWNER TO webadmin;

--
-- Name: g_int_consistent(internal, integer[], integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION g_int_consistent(internal, integer[], integer) RETURNS boolean
    LANGUAGE c
    AS '$libdir/_int', 'g_int_consistent';


ALTER FUNCTION public.g_int_consistent(internal, integer[], integer) OWNER TO postgres;

--
-- Name: g_int_union(bytea, internal); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION g_int_union(bytea, internal) RETURNS integer[]
    LANGUAGE c
    AS '$libdir/_int', 'g_int_union';


ALTER FUNCTION public.g_int_union(bytea, internal) OWNER TO postgres;

--
-- Name: g_intbig_consistent(internal, integer[], integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION g_intbig_consistent(internal, integer[], integer) RETURNS boolean
    LANGUAGE c
    AS '$libdir/_int', 'g_intbig_consistent';


ALTER FUNCTION public.g_intbig_consistent(internal, integer[], integer) OWNER TO postgres;

--
-- Name: g_intbig_consistent(internal, internal, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION g_intbig_consistent(internal, internal, integer) RETURNS boolean
    LANGUAGE c
    AS '$libdir/_int', 'g_intbig_consistent';


ALTER FUNCTION public.g_intbig_consistent(internal, internal, integer) OWNER TO postgres;

--
-- Name: g_intbig_same(integer[], integer[], internal); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION g_intbig_same(integer[], integer[], internal) RETURNS internal
    LANGUAGE c
    AS '$libdir/_int', 'g_intbig_same';


ALTER FUNCTION public.g_intbig_same(integer[], integer[], internal) OWNER TO postgres;

--
-- Name: g_intbig_union(bytea, internal); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION g_intbig_union(bytea, internal) RETURNS integer[]
    LANGUAGE c
    AS '$libdir/_int', 'g_intbig_union';


ALTER FUNCTION public.g_intbig_union(bytea, internal) OWNER TO postgres;

--
-- Name: getthread(name, integer, integer); Type: FUNCTION; Schema: public; Owner: webadmin
--

CREATE FUNCTION getthread(name, integer, integer) RETURNS SETOF record
    LANGUAGE plpgsql
    AS $_$
	declare
		node1 record;
		subnode record;
		nextdepth int;
	begin
		nextdepth := $3 + 1;
		FOR node1 IN execute 'SELECT ' || $3 || ' as depth, id, subject, name, cdate, reads, comments, commdate, deleted, crows FROM ' || $1 || ' WHERE pid = ' || $2 || ' order by id' LOOP
			return next node1;
			if node1.crows > 0 then
				for subnode IN SELECT * FROM getthread($1, node1.id, nextdepth) as t(depth int,id int,subject text, name text, cdate int, reads int, comments int, commdate int, deleted int, crows int) LOOP
					return next subnode;
				end loop;
			end if;
		end loop;
		return;
	end;
$_$;


ALTER FUNCTION public.getthread(name, integer, integer) OWNER TO webadmin;

--
-- Name: lower(text); Type: FUNCTION; Schema: public; Owner: webadmin
--

CREATE FUNCTION lower(text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $_$
select translate($1,'ABCDEFGHIJKLMNOPQRSTUVWXYZ','abcdefghijklmnopqrstuvwxyz');
$_$;


ALTER FUNCTION public.lower(text) OWNER TO webadmin;

--
-- Name: password(text); Type: FUNCTION; Schema: public; Owner: webadmin
--

CREATE FUNCTION password(text) RETURNS text
    LANGUAGE plpgsql
    AS $_$
declare
        newpass text;
begin
        select into newpass encode(digest($1,'md5'),'hex');
        return newpass;
end;
$_$;


ALTER FUNCTION public.password(text) OWNER TO webadmin;

--
-- Name: plpgsql_call_handler(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION plpgsql_call_handler() RETURNS language_handler
    LANGUAGE c
    AS '$libdir/plpgsql', 'plpgsql_call_handler';


ALTER FUNCTION public.plpgsql_call_handler() OWNER TO postgres;

--
-- Name: t_fti(); Type: FUNCTION; Schema: public; Owner: webadmin
--

CREATE FUNCTION t_fti() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
declare
	fullstr text;
	s text;
	i integer;
	ftitable text;
	upmenuid text;
	v_criteria text;
	v_subcritid integer;
	oldlastid integer;
	oldexist integer;
begin
ftitable := TG_ARGV[0];
upmenuid := split_part(ftitable,'_',2);
-- 게시물이 작성될 때 할일 
-- 해당 사용자 posts 갯수 증가
-- 해당 메뉴 total 증가
-- 해당 메뉴 maxpage 증가
-- 해당 게시물의 pid crows 증가
-- full text index 삽입
if TG_OP = 'INSERT' then
	select criteria into v_criteria from menus where menuid = upmenuid::integer;
	select menuid into v_subcritid from menus where criteria = v_criteria and subcrit = new.topic;

	if new.usernum > 0 then
		update users set posts = posts + 1, posttime = new.cdate where num = new.usernum;
		fullstr := new.name || ' ' || new.uid || ' ' || new.subject || ' ' || new.content;
	else
		fullstr := new.name || ' ' || new.subject || ' ' || new.content;
	end if;

	-- 갯수 및 lastid 갱신
	if new.pid = 0 then
		update menus set total = total + 1, lastid = new.id, maxpage = maxpage + 1 where menuid = upmenuid::integer;
	else
		s := 'update bd_' || upmenuid || ' set crows = crows + 1 where id = ' || new.pid;
		execute(s);
		update menus set total = total + 1, lastid = new.id where menuid =  upmenuid::integer;
	end if;

	if upmenuid <> v_subcritid::text then
		if new.pid = 0 then
			update menus set total = total + 1, lastid = new.id, maxpage = maxpage + 1 where menuid = v_subcritid;
		else
			update menus set total = total + 1, lastid = new.id where menuid = v_subcritid;
		end if;
	end if;

	i := fti_insert(ftitable, new.id, null, fullstr);
	return new;
elsif TG_OP = 'DELETE' then
	select criteria into v_criteria from menus where menuid = upmenuid::integer;
	select menuid into v_subcritid from menus where criteria = v_criteria and subcrit = old.topic;

	if old.usernum > 0 then
		update users set posts = posts - 1, posttime = abstime(now())::int where num = old.usernum;
	end if;

	if old.pid = 0 then
		-- lastid 를 구해서 그놈이 마지막 id 였다면, 새 마지막 id를 지정한다.
		select lastid into oldlastid from menus where menuid = v_subcritid;
		if oldlastid >= old.id then
			execute 'select id from bd_' || upmenuid || ' where id <= ' || oldlastid || ' and topic = ''' || old.topic  || ''' and pid = 0 order by id desc limit 1' into oldexist;
			if oldexist > 0 then
				update menus set total = total - 1, maxpage = maxpage - 1, lastid = oldexist where menuid = v_subcritid;
			else
				update menus set total = total - 1, maxpage = maxpage - 1, lastid = null where menuid = v_subcritid;
			end if;
		else
			update menus set total = total - 1, maxpage = maxpage - 1 where menuid = v_subcritid;
		end if;
	else
		-- pid 의 crow -1 
		execute 'update bd_' || upmenuid || ' set crows = crows - 1 where id = ' || old.pid;
		update menus set total = total - 1 where menuid = v_subcritid;
	end if;

	if upmenuid <> v_subcritid::text then
		-- upmenu 도 update
		if old.pid = 0 then
			update menus set total = total - 1, maxpage = maxpage - 1 where menuid = upmenuid::integer;
		else
			update menus set total = total - 1 where menuid = upmenuid::integer;
		end if;
	end if;

	i := fti_delete(ftitable, old.id, null);
	return old;
elsif TG_OP = 'UPDATE' then
	if old.id <> new.id then
		raise EXCEPTION 'Do not allow to change board number(Primary key)';
		return null;
	end if;
	if (old.uid || ' ' || old.name || ' ' || old.subject || ' ' || old.content) <> (new.uid || ' ' || new.name || ' ' || new.subject || ' ' || new.content) then
		i := fti_delete(ftitable, old.id, null);
		if new.usernum > 0 then
			fullstr := new.name || ' ' || new.uid || ' ' || new.subject || ' ' || new.content;
		else
			fullstr := new.name || ' ' || new.subject || ' ' || new.content;
		end if;
		i := fti_insert(ftitable, new.id, null, fullstr);
	end if;
	return new;
else
	return null;
end if;
end;
$$;


ALTER FUNCTION public.t_fti() OWNER TO webadmin;

--
-- Name: upper(text); Type: FUNCTION; Schema: public; Owner: webadmin
--

CREATE FUNCTION upper(text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $_$
select translate($1,'abcdefghijklmnopqrstuvwxyz', 'ABCDEFGHIJKLMNOPQRSTUVWXYZ');
$_$;


ALTER FUNCTION public.upper(text) OWNER TO webadmin;

--
-- Name: viewcate(text); Type: FUNCTION; Schema: public; Owner: webadmin
--

CREATE FUNCTION viewcate(text) RETURNS SETOF record
    LANGUAGE plpgsql
    AS $_$
DECLARE
	curnode RECORD;
	ppid text;
BEGIN
	ppid := trim($1);
	loop
		if (ppid = '') or (ppid is null) then
			exit;
		end if;
		select into curnode pid,title from category where id = ppid;
		ppid := trim(curnode.pid);
		return next curnode;
	end loop;
	RETURN; 
END; 
$_$;


ALTER FUNCTION public.viewcate(text) OWNER TO webadmin;

--
-- Name: viewcate2(text, text, text); Type: FUNCTION; Schema: public; Owner: webadmin
--

CREATE FUNCTION viewcate2(qcriteria text, curpid text, curtitle text) RETURNS SETOF record
    LANGUAGE plpgsql
    AS $$
declare
        curnode record;
        childnode record;
        nexttitle text;
begin
        nexttitle := '';
        if curtitle <> '' then
                nexttitle := curtitle || '/';
        end if;
        for curnode in select id::text, pid::text, nexttitle || title::text as title from category where criteria = qcriteria and pid = curpid order by title loop
                return next curnode;
                for childnode in select * from viewcate2(qcriteria, curnode.id, nexttitle || curnode.title) as t (id text, pid text, title text) loop
                        return next childnode;
                end loop;
        end loop;
        return;
end;
$$;


ALTER FUNCTION public.viewcate2(qcriteria text, curpid text, curtitle text) OWNER TO webadmin;

--
-- Name: viewmenus(integer, integer); Type: FUNCTION; Schema: public; Owner: webadmin
--

CREATE FUNCTION viewmenus(integer, integer) RETURNS SETOF record
    LANGUAGE plpgsql
    AS $_$
DECLARE
	curnode RECORD;
	childnode RECORD;
	iCurupper ALIAS FOR $1;
	iCurdepth ALIAS FOR $2;
BEGIN
	FOR curnode IN SELECT iCurdepth AS depth, menuid, criteria, subcrit, name, menutype, xgroups, lgroups, tname,upper from menus where upper = iCurupper and menuid <> 1 order by sortnum LOOP
		RETURN NEXT curnode;
		FOR childnode IN SELECT * from viewmenus(curnode.menuid, iCurdepth + 1) AS t(depth int, menuid int, criteria text, subcrit text, name text, menutype int, xgroups int[], lgroups int[], tname text, upper int) LOOP
			RETURN NEXT childnode;
		END LOOP;
	END LOOP;
	RETURN; 
END; 
$_$;


ALTER FUNCTION public.viewmenus(integer, integer) OWNER TO webadmin;

--
-- Name: bit_or(bit); Type: AGGREGATE; Schema: public; Owner: webadmin
--

CREATE AGGREGATE bit_or(bit) (
    SFUNC = bitor,
    STYPE = bit
);


ALTER AGGREGATE public.bit_or(bit) OWNER TO webadmin;

SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: board; Type: TABLE; Schema: public; Owner: webadmin; Tablespace: 
--

CREATE TABLE board (
    id integer NOT NULL,
    topic character varying(10) NOT NULL,
    cdate integer DEFAULT (abstime(now()))::integer NOT NULL,
    mdate integer DEFAULT 0 NOT NULL,
    subject text NOT NULL,
    content text,
    reads integer DEFAULT 0,
    deleted integer DEFAULT 0,
    usernum integer NOT NULL,
    uid text,
    name text,
    email text,
    rip text,
    passwd text DEFAULT ''::text,
    gid integer NOT NULL,
    pid integer DEFAULT 0 NOT NULL,
    crows integer DEFAULT 0 NOT NULL,
    comments integer DEFAULT 0 NOT NULL,
    commdate integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.board OWNER TO webadmin;

--
-- Name: TABLE board; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON TABLE board IS '게시판';


--
-- Name: COLUMN board.id; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN board.id IS '게시물번호';


--
-- Name: COLUMN board.topic; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN board.topic IS '하위분류, =menus.subcrit';


--
-- Name: COLUMN board.cdate; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN board.cdate IS '작성일';


--
-- Name: COLUMN board.mdate; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN board.mdate IS '마지막 수정일';


--
-- Name: COLUMN board.subject; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN board.subject IS '제목';


--
-- Name: COLUMN board.content; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN board.content IS '내용';


--
-- Name: COLUMN board.reads; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN board.reads IS '조회수';


--
-- Name: COLUMN board.deleted; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN board.deleted IS '삭제되었는지';


--
-- Name: COLUMN board.usernum; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN board.usernum IS '사용자번호, =users.num';


--
-- Name: COLUMN board.uid; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN board.uid IS '사용자id, =users.uid';


--
-- Name: COLUMN board.name; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN board.name IS '사용자이름, =users.name';


--
-- Name: COLUMN board.email; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN board.email IS '사용자email, =users.email';


--
-- Name: COLUMN board.rip; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN board.rip IS '사용자IP';


--
-- Name: COLUMN board.passwd; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN board.passwd IS '비밀번호';


--
-- Name: COLUMN board.gid; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN board.gid IS '최상위관련글';


--
-- Name: COLUMN board.pid; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN board.pid IS '상위관련글';


--
-- Name: COLUMN board.crows; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN board.crows IS '관련글개수';


--
-- Name: COLUMN board.comments; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN board.comments IS '댓글개수';


--
-- Name: COLUMN board.commdate; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN board.commdate IS '마지막댓글작성일';


SET default_tablespace = tbs_bd_103;

--
-- Name: bd_103; Type: TABLE; Schema: public; Owner: webadmin; Tablespace: tbs_bd_103
--

CREATE TABLE bd_103 (
    id integer DEFAULT nextval(('public.bd_103_id_seq'::text)::regclass)
)
INHERITS (board);


ALTER TABLE public.bd_103 OWNER TO webadmin;

SET default_tablespace = '';

--
-- Name: fti; Type: TABLE; Schema: public; Owner: webadmin; Tablespace: 
--

CREATE TABLE fti (
    k integer,
    c integer,
    v character varying(50)
);


ALTER TABLE public.fti OWNER TO webadmin;

--
-- Name: TABLE fti; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON TABLE fti IS '검색자료';


--
-- Name: COLUMN fti.k; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN fti.k IS '게시물번호, =board.id';


--
-- Name: COLUMN fti.c; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN fti.c IS '댓글번호, =comments.cid';


--
-- Name: COLUMN fti.v; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN fti.v IS '검색어';


SET default_tablespace = tbs_bd_103;

--
-- Name: bd_103_fti; Type: TABLE; Schema: public; Owner: webadmin; Tablespace: tbs_bd_103
--

CREATE TABLE bd_103_fti (
)
INHERITS (fti);


ALTER TABLE public.bd_103_fti OWNER TO webadmin;

--
-- Name: bd_103_id_seq; Type: SEQUENCE; Schema: public; Owner: webadmin
--

CREATE SEQUENCE bd_103_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.bd_103_id_seq OWNER TO webadmin;

SET default_tablespace = tbs_bd_111;

--
-- Name: bd_111; Type: TABLE; Schema: public; Owner: webadmin; Tablespace: tbs_bd_111
--

CREATE TABLE bd_111 (
    id integer DEFAULT nextval(('public.bd_111_id_seq'::text)::regclass)
)
INHERITS (board);


ALTER TABLE public.bd_111 OWNER TO webadmin;

--
-- Name: bd_111_fti; Type: TABLE; Schema: public; Owner: webadmin; Tablespace: tbs_bd_111
--

CREATE TABLE bd_111_fti (
)
INHERITS (fti);


ALTER TABLE public.bd_111_fti OWNER TO webadmin;

--
-- Name: bd_111_id_seq; Type: SEQUENCE; Schema: public; Owner: webadmin
--

CREATE SEQUENCE bd_111_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.bd_111_id_seq OWNER TO webadmin;

SET default_tablespace = tbs_bd_112;

--
-- Name: bd_112; Type: TABLE; Schema: public; Owner: webadmin; Tablespace: tbs_bd_112
--

CREATE TABLE bd_112 (
    id integer DEFAULT nextval(('public.bd_112_id_seq'::text)::regclass)
)
INHERITS (board);


ALTER TABLE public.bd_112 OWNER TO webadmin;

--
-- Name: bd_112_fti; Type: TABLE; Schema: public; Owner: webadmin; Tablespace: tbs_bd_112
--

CREATE TABLE bd_112_fti (
)
INHERITS (fti);


ALTER TABLE public.bd_112_fti OWNER TO webadmin;

--
-- Name: bd_112_id_seq; Type: SEQUENCE; Schema: public; Owner: webadmin
--

CREATE SEQUENCE bd_112_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.bd_112_id_seq OWNER TO webadmin;

SET default_tablespace = tbs_bd_117;

--
-- Name: bd_117; Type: TABLE; Schema: public; Owner: webadmin; Tablespace: tbs_bd_117
--

CREATE TABLE bd_117 (
    id integer DEFAULT nextval(('public.bd_117_id_seq'::text)::regclass)
)
INHERITS (board);


ALTER TABLE public.bd_117 OWNER TO webadmin;

--
-- Name: bd_117_fti; Type: TABLE; Schema: public; Owner: webadmin; Tablespace: tbs_bd_117
--

CREATE TABLE bd_117_fti (
)
INHERITS (fti);


ALTER TABLE public.bd_117_fti OWNER TO webadmin;

--
-- Name: bd_117_id_seq; Type: SEQUENCE; Schema: public; Owner: webadmin
--

CREATE SEQUENCE bd_117_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.bd_117_id_seq OWNER TO webadmin;

SET default_tablespace = tbs_bd_125;

--
-- Name: bd_125; Type: TABLE; Schema: public; Owner: webadmin; Tablespace: tbs_bd_125
--

CREATE TABLE bd_125 (
    id integer DEFAULT nextval(('public.bd_125_id_seq'::text)::regclass)
)
INHERITS (board);


ALTER TABLE public.bd_125 OWNER TO webadmin;

--
-- Name: bd_125_fti; Type: TABLE; Schema: public; Owner: webadmin; Tablespace: tbs_bd_125
--

CREATE TABLE bd_125_fti (
)
INHERITS (fti);


ALTER TABLE public.bd_125_fti OWNER TO webadmin;

--
-- Name: bd_125_id_seq; Type: SEQUENCE; Schema: public; Owner: webadmin
--

CREATE SEQUENCE bd_125_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.bd_125_id_seq OWNER TO webadmin;

SET default_tablespace = tbs_bd_13;

--
-- Name: bd_13; Type: TABLE; Schema: public; Owner: webadmin; Tablespace: tbs_bd_13
--

CREATE TABLE bd_13 (
    id integer DEFAULT nextval(('public.bd_13_id_seq'::text)::regclass)
)
INHERITS (board);


ALTER TABLE public.bd_13 OWNER TO webadmin;

SET default_tablespace = tbs_bd_137;

--
-- Name: bd_137; Type: TABLE; Schema: public; Owner: webadmin; Tablespace: tbs_bd_137
--

CREATE TABLE bd_137 (
    id integer
)
INHERITS (board);


ALTER TABLE public.bd_137 OWNER TO webadmin;

--
-- Name: bd_137_fti; Type: TABLE; Schema: public; Owner: webadmin; Tablespace: tbs_bd_137
--

CREATE TABLE bd_137_fti (
)
INHERITS (fti);


ALTER TABLE public.bd_137_fti OWNER TO webadmin;

--
-- Name: bd_137_id_seq; Type: SEQUENCE; Schema: public; Owner: webadmin
--

CREATE SEQUENCE bd_137_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.bd_137_id_seq OWNER TO webadmin;

--
-- Name: bd_137_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: webadmin
--

ALTER SEQUENCE bd_137_id_seq OWNED BY bd_137.id;


SET default_tablespace = tbs_bd_13;

--
-- Name: bd_13_fti; Type: TABLE; Schema: public; Owner: webadmin; Tablespace: tbs_bd_13
--

CREATE TABLE bd_13_fti (
)
INHERITS (fti);


ALTER TABLE public.bd_13_fti OWNER TO webadmin;

--
-- Name: bd_13_id_seq; Type: SEQUENCE; Schema: public; Owner: webadmin
--

CREATE SEQUENCE bd_13_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.bd_13_id_seq OWNER TO webadmin;

SET default_tablespace = tbs_bd_21;

--
-- Name: bd_21; Type: TABLE; Schema: public; Owner: webadmin; Tablespace: tbs_bd_21
--

CREATE TABLE bd_21 (
    id integer DEFAULT nextval(('public.bd_21_id_seq'::text)::regclass)
)
INHERITS (board);


ALTER TABLE public.bd_21 OWNER TO webadmin;

--
-- Name: bd_21_fti; Type: TABLE; Schema: public; Owner: webadmin; Tablespace: tbs_bd_21
--

CREATE TABLE bd_21_fti (
)
INHERITS (fti);


ALTER TABLE public.bd_21_fti OWNER TO webadmin;

--
-- Name: bd_21_id_seq; Type: SEQUENCE; Schema: public; Owner: webadmin
--

CREATE SEQUENCE bd_21_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.bd_21_id_seq OWNER TO webadmin;

SET default_tablespace = tbs_bd_22;

--
-- Name: bd_22; Type: TABLE; Schema: public; Owner: webadmin; Tablespace: tbs_bd_22
--

CREATE TABLE bd_22 (
    id integer DEFAULT nextval(('public.bd_22_id_seq'::text)::regclass)
)
INHERITS (board);


ALTER TABLE public.bd_22 OWNER TO webadmin;

--
-- Name: bd_22_fti; Type: TABLE; Schema: public; Owner: webadmin; Tablespace: tbs_bd_22
--

CREATE TABLE bd_22_fti (
)
INHERITS (fti);


ALTER TABLE public.bd_22_fti OWNER TO webadmin;

--
-- Name: bd_22_id_seq; Type: SEQUENCE; Schema: public; Owner: webadmin
--

CREATE SEQUENCE bd_22_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.bd_22_id_seq OWNER TO webadmin;

SET default_tablespace = tbs_bd_23;

--
-- Name: bd_23; Type: TABLE; Schema: public; Owner: webadmin; Tablespace: tbs_bd_23
--

CREATE TABLE bd_23 (
    id integer DEFAULT nextval(('public.bd_23_id_seq'::text)::regclass)
)
INHERITS (board);


ALTER TABLE public.bd_23 OWNER TO webadmin;

--
-- Name: bd_23_fti; Type: TABLE; Schema: public; Owner: webadmin; Tablespace: tbs_bd_23
--

CREATE TABLE bd_23_fti (
)
INHERITS (fti);


ALTER TABLE public.bd_23_fti OWNER TO webadmin;

--
-- Name: bd_23_id_seq; Type: SEQUENCE; Schema: public; Owner: webadmin
--

CREATE SEQUENCE bd_23_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.bd_23_id_seq OWNER TO webadmin;

SET default_tablespace = '';

--
-- Name: bd_31; Type: TABLE; Schema: public; Owner: webadmin; Tablespace: 
--

CREATE TABLE bd_31 (
    id integer DEFAULT nextval(('public.bd_31_id_seq'::text)::regclass)
)
INHERITS (board);


ALTER TABLE public.bd_31 OWNER TO webadmin;

--
-- Name: bd_31_fti; Type: TABLE; Schema: public; Owner: webadmin; Tablespace: 
--

CREATE TABLE bd_31_fti (
)
INHERITS (fti);


ALTER TABLE public.bd_31_fti OWNER TO webadmin;

--
-- Name: bd_31_id_seq; Type: SEQUENCE; Schema: public; Owner: webadmin
--

CREATE SEQUENCE bd_31_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.bd_31_id_seq OWNER TO webadmin;

--
-- Name: bd_39; Type: TABLE; Schema: public; Owner: webadmin; Tablespace: 
--

CREATE TABLE bd_39 (
    id integer DEFAULT nextval(('public.bd_39_id_seq'::text)::regclass)
)
INHERITS (board);


ALTER TABLE public.bd_39 OWNER TO webadmin;

--
-- Name: bd_39_fti; Type: TABLE; Schema: public; Owner: webadmin; Tablespace: 
--

CREATE TABLE bd_39_fti (
)
INHERITS (fti);


ALTER TABLE public.bd_39_fti OWNER TO webadmin;

--
-- Name: bd_39_id_seq; Type: SEQUENCE; Schema: public; Owner: webadmin
--

CREATE SEQUENCE bd_39_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.bd_39_id_seq OWNER TO webadmin;

SET default_tablespace = tbs_bd_47;

--
-- Name: bd_47; Type: TABLE; Schema: public; Owner: webadmin; Tablespace: tbs_bd_47
--

CREATE TABLE bd_47 (
    id integer DEFAULT nextval(('public.bd_47_id_seq'::text)::regclass)
)
INHERITS (board);


ALTER TABLE public.bd_47 OWNER TO webadmin;

--
-- Name: bd_47_fti; Type: TABLE; Schema: public; Owner: webadmin; Tablespace: tbs_bd_47
--

CREATE TABLE bd_47_fti (
)
INHERITS (fti);


ALTER TABLE public.bd_47_fti OWNER TO webadmin;

--
-- Name: bd_47_id_seq; Type: SEQUENCE; Schema: public; Owner: webadmin
--

CREATE SEQUENCE bd_47_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.bd_47_id_seq OWNER TO webadmin;

SET default_tablespace = tbs_bd_5;

--
-- Name: bd_5; Type: TABLE; Schema: public; Owner: webadmin; Tablespace: tbs_bd_5
--

CREATE TABLE bd_5 (
    id integer DEFAULT nextval(('public.bd_5_id_seq'::text)::regclass)
)
INHERITS (board);


ALTER TABLE public.bd_5 OWNER TO webadmin;

SET default_tablespace = tbs_bd_55;

--
-- Name: bd_55; Type: TABLE; Schema: public; Owner: webadmin; Tablespace: tbs_bd_55
--

CREATE TABLE bd_55 (
    id integer DEFAULT nextval(('public.bd_55_id_seq'::text)::regclass)
)
INHERITS (board);


ALTER TABLE public.bd_55 OWNER TO webadmin;

--
-- Name: bd_55_fti; Type: TABLE; Schema: public; Owner: webadmin; Tablespace: tbs_bd_55
--

CREATE TABLE bd_55_fti (
)
INHERITS (fti);


ALTER TABLE public.bd_55_fti OWNER TO webadmin;

--
-- Name: bd_55_id_seq; Type: SEQUENCE; Schema: public; Owner: webadmin
--

CREATE SEQUENCE bd_55_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.bd_55_id_seq OWNER TO webadmin;

SET default_tablespace = tbs_bd_5;

--
-- Name: bd_5_fti; Type: TABLE; Schema: public; Owner: webadmin; Tablespace: tbs_bd_5
--

CREATE TABLE bd_5_fti (
)
INHERITS (fti);


ALTER TABLE public.bd_5_fti OWNER TO webadmin;

--
-- Name: bd_5_id_seq; Type: SEQUENCE; Schema: public; Owner: webadmin
--

CREATE SEQUENCE bd_5_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.bd_5_id_seq OWNER TO webadmin;

SET default_tablespace = tbs_bd_63;

--
-- Name: bd_63; Type: TABLE; Schema: public; Owner: webadmin; Tablespace: tbs_bd_63
--

CREATE TABLE bd_63 (
    id integer DEFAULT nextval(('public.bd_63_id_seq'::text)::regclass)
)
INHERITS (board);


ALTER TABLE public.bd_63 OWNER TO webadmin;

--
-- Name: bd_63_fti; Type: TABLE; Schema: public; Owner: webadmin; Tablespace: tbs_bd_63
--

CREATE TABLE bd_63_fti (
)
INHERITS (fti);


ALTER TABLE public.bd_63_fti OWNER TO webadmin;

--
-- Name: bd_63_id_seq; Type: SEQUENCE; Schema: public; Owner: webadmin
--

CREATE SEQUENCE bd_63_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.bd_63_id_seq OWNER TO webadmin;

SET default_tablespace = tbs_bd_71;

--
-- Name: bd_71; Type: TABLE; Schema: public; Owner: webadmin; Tablespace: tbs_bd_71
--

CREATE TABLE bd_71 (
    id integer DEFAULT nextval(('public.bd_71_id_seq'::text)::regclass)
)
INHERITS (board);


ALTER TABLE public.bd_71 OWNER TO webadmin;

--
-- Name: bd_71_fti; Type: TABLE; Schema: public; Owner: webadmin; Tablespace: tbs_bd_71
--

CREATE TABLE bd_71_fti (
)
INHERITS (fti);


ALTER TABLE public.bd_71_fti OWNER TO webadmin;

--
-- Name: bd_71_id_seq; Type: SEQUENCE; Schema: public; Owner: webadmin
--

CREATE SEQUENCE bd_71_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.bd_71_id_seq OWNER TO webadmin;

SET default_tablespace = tbs_bd_79;

--
-- Name: bd_79; Type: TABLE; Schema: public; Owner: webadmin; Tablespace: tbs_bd_79
--

CREATE TABLE bd_79 (
    id integer DEFAULT nextval(('public.bd_79_id_seq'::text)::regclass)
)
INHERITS (board);


ALTER TABLE public.bd_79 OWNER TO webadmin;

--
-- Name: bd_79_fti; Type: TABLE; Schema: public; Owner: webadmin; Tablespace: tbs_bd_79
--

CREATE TABLE bd_79_fti (
)
INHERITS (fti);


ALTER TABLE public.bd_79_fti OWNER TO webadmin;

--
-- Name: bd_79_id_seq; Type: SEQUENCE; Schema: public; Owner: webadmin
--

CREATE SEQUENCE bd_79_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.bd_79_id_seq OWNER TO webadmin;

SET default_tablespace = tbs_bd_87;

--
-- Name: bd_87; Type: TABLE; Schema: public; Owner: webadmin; Tablespace: tbs_bd_87
--

CREATE TABLE bd_87 (
    id integer DEFAULT nextval(('public.bd_87_id_seq'::text)::regclass)
)
INHERITS (board);


ALTER TABLE public.bd_87 OWNER TO webadmin;

--
-- Name: bd_87_fti; Type: TABLE; Schema: public; Owner: webadmin; Tablespace: tbs_bd_87
--

CREATE TABLE bd_87_fti (
)
INHERITS (fti);


ALTER TABLE public.bd_87_fti OWNER TO webadmin;

--
-- Name: bd_87_id_seq; Type: SEQUENCE; Schema: public; Owner: webadmin
--

CREATE SEQUENCE bd_87_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.bd_87_id_seq OWNER TO webadmin;

SET default_tablespace = tbs_bd_95;

--
-- Name: bd_95; Type: TABLE; Schema: public; Owner: webadmin; Tablespace: tbs_bd_95
--

CREATE TABLE bd_95 (
    id integer DEFAULT nextval(('public.bd_95_id_seq'::text)::regclass)
)
INHERITS (board);


ALTER TABLE public.bd_95 OWNER TO webadmin;

--
-- Name: bd_95_fti; Type: TABLE; Schema: public; Owner: webadmin; Tablespace: tbs_bd_95
--

CREATE TABLE bd_95_fti (
)
INHERITS (fti);


ALTER TABLE public.bd_95_fti OWNER TO webadmin;

--
-- Name: bd_95_id_seq; Type: SEQUENCE; Schema: public; Owner: webadmin
--

CREATE SEQUENCE bd_95_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.bd_95_id_seq OWNER TO webadmin;

SET default_tablespace = '';

--
-- Name: category; Type: TABLE; Schema: public; Owner: webadmin; Tablespace: 
--

CREATE TABLE category (
    id character(32) NOT NULL,
    pid character(32) NOT NULL,
    criteria text NOT NULL,
    path text NOT NULL,
    title text,
    links integer DEFAULT 0,
    haschild integer DEFAULT 0,
    cdate integer DEFAULT (abstime(now()))::integer,
    poster text NOT NULL,
    auth integer DEFAULT 7
);


ALTER TABLE public.category OWNER TO webadmin;

--
-- Name: TABLE category; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON TABLE category IS '링크 분류';


--
-- Name: COLUMN category.id; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN category.id IS '링크ID';


--
-- Name: COLUMN category.pid; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN category.pid IS '상위링크ID';


--
-- Name: COLUMN category.criteria; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN category.criteria IS '메뉴상위분류, =menus.criteria';


--
-- Name: COLUMN category.path; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN category.path IS '위치';


--
-- Name: COLUMN category.title; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN category.title IS '분류이름';


--
-- Name: COLUMN category.links; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN category.links IS '링크 개수';


--
-- Name: COLUMN category.haschild; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN category.haschild IS '하위분류가 있는지';


--
-- Name: COLUMN category.cdate; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN category.cdate IS '만든 날짜';


--
-- Name: COLUMN category.poster; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN category.poster IS '만든이';


--
-- Name: COLUMN category.auth; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN category.auth IS '접근권한, 현재 사용안함';


--
-- Name: comments; Type: TABLE; Schema: public; Owner: webadmin; Tablespace: 
--

CREATE TABLE comments (
    cid integer NOT NULL,
    ptable text NOT NULL,
    pid integer NOT NULL,
    content text NOT NULL,
    usernum integer NOT NULL,
    uid text NOT NULL,
    name text NOT NULL,
    email text,
    passwd text,
    cdate integer DEFAULT (abstime(now()))::integer,
    mdate integer,
    rip text
);


ALTER TABLE public.comments OWNER TO webadmin;

--
-- Name: TABLE comments; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON TABLE comments IS '댓글들';


--
-- Name: COLUMN comments.cid; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN comments.cid IS '일련번호';


--
-- Name: COLUMN comments.ptable; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN comments.ptable IS '메뉴id, =menus.menuid';


--
-- Name: COLUMN comments.pid; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN comments.pid IS '게시물번호, =board.id';


--
-- Name: COLUMN comments.content; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN comments.content IS '내용';


--
-- Name: COLUMN comments.usernum; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN comments.usernum IS '작성자번호, =users.num';


--
-- Name: COLUMN comments.uid; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN comments.uid IS '작성자id, =users.uid';


--
-- Name: COLUMN comments.name; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN comments.name IS '작성자이름, =users.name';


--
-- Name: COLUMN comments.email; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN comments.email IS '작성자email, =users.email';


--
-- Name: COLUMN comments.passwd; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN comments.passwd IS '비밀번호';


--
-- Name: COLUMN comments.cdate; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN comments.cdate IS '작성일';


--
-- Name: COLUMN comments.mdate; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN comments.mdate IS '마지막수정일';


--
-- Name: COLUMN comments.rip; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN comments.rip IS '작성자IP';


--
-- Name: comments_cid_seq; Type: SEQUENCE; Schema: public; Owner: webadmin
--

CREATE SEQUENCE comments_cid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.comments_cid_seq OWNER TO webadmin;

--
-- Name: comments_cid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: webadmin
--

ALTER SEQUENCE comments_cid_seq OWNED BY comments.cid;


--
-- Name: g2_sequenceeventlog; Type: SEQUENCE; Schema: public; Owner: webadmin
--

CREATE SEQUENCE g2_sequenceeventlog
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.g2_sequenceeventlog OWNER TO webadmin;

--
-- Name: g2_sequenceid; Type: SEQUENCE; Schema: public; Owner: webadmin
--

CREATE SEQUENCE g2_sequenceid
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.g2_sequenceid OWNER TO webadmin;

--
-- Name: g2_sequencelock; Type: SEQUENCE; Schema: public; Owner: webadmin
--

CREATE SEQUENCE g2_sequencelock
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.g2_sequencelock OWNER TO webadmin;

--
-- Name: groups; Type: TABLE; Schema: public; Owner: webadmin; Tablespace: 
--

CREATE TABLE groups (
    gid integer NOT NULL,
    name text NOT NULL
);


ALTER TABLE public.groups OWNER TO webadmin;

--
-- Name: TABLE groups; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON TABLE groups IS '그룹';


--
-- Name: COLUMN groups.gid; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN groups.gid IS '그룹번호';


--
-- Name: COLUMN groups.name; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN groups.name IS '그룹이름';


--
-- Name: groups_gid_seq; Type: SEQUENCE; Schema: public; Owner: webadmin
--

CREATE SEQUENCE groups_gid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.groups_gid_seq OWNER TO webadmin;

--
-- Name: groups_gid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: webadmin
--

ALTER SEQUENCE groups_gid_seq OWNED BY groups.gid;


--
-- Name: imagefiles; Type: TABLE; Schema: public; Owner: webadmin; Tablespace: 
--

CREATE TABLE imagefiles (
    imgname text NOT NULL,
    menuid integer,
    pid integer,
    fsize integer,
    fmime text,
    sessionid text
);


ALTER TABLE public.imagefiles OWNER TO webadmin;

--
-- Name: TABLE imagefiles; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON TABLE imagefiles IS '업로드된 그림들';


--
-- Name: COLUMN imagefiles.imgname; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN imagefiles.imgname IS '파일이름';


--
-- Name: COLUMN imagefiles.menuid; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN imagefiles.menuid IS '게시판 번호, =menus.menuid';


--
-- Name: COLUMN imagefiles.pid; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN imagefiles.pid IS '게시물번호, =board.id';


--
-- Name: COLUMN imagefiles.fsize; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN imagefiles.fsize IS '파일크기';


--
-- Name: COLUMN imagefiles.fmime; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN imagefiles.fmime IS '이미지 종류';


--
-- Name: COLUMN imagefiles.sessionid; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN imagefiles.sessionid IS '세션id';


--
-- Name: keywords; Type: TABLE; Schema: public; Owner: webadmin; Tablespace: 
--

CREATE TABLE keywords (
    num integer NOT NULL,
    criteria text,
    keyword text,
    ctime timestamp without time zone,
    rtime double precision
);


ALTER TABLE public.keywords OWNER TO webadmin;

--
-- Name: TABLE keywords; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON TABLE keywords IS '검색결과통계용';


--
-- Name: COLUMN keywords.num; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN keywords.num IS '일련번호';


--
-- Name: COLUMN keywords.criteria; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN keywords.criteria IS '게시판 상위분류, =menus.criteria';


--
-- Name: COLUMN keywords.keyword; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN keywords.keyword IS '검색어';


--
-- Name: COLUMN keywords.ctime; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN keywords.ctime IS '만든 시간';


--
-- Name: COLUMN keywords.rtime; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN keywords.rtime IS '검색 소요시간';


--
-- Name: keywords_num_seq; Type: SEQUENCE; Schema: public; Owner: webadmin
--

CREATE SEQUENCE keywords_num_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.keywords_num_seq OWNER TO webadmin;

--
-- Name: keywords_num_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: webadmin
--

ALTER SEQUENCE keywords_num_seq OWNED BY keywords.num;


--
-- Name: links; Type: TABLE; Schema: public; Owner: webadmin; Tablespace: 
--

CREATE TABLE links (
    id character(32) NOT NULL,
    category character(32) NOT NULL,
    criteria text NOT NULL,
    title text NOT NULL,
    url text NOT NULL,
    alternative text NOT NULL,
    description text,
    lang integer,
    sitetype integer,
    poster text NOT NULL,
    visits integer,
    score integer,
    deleted integer DEFAULT 0,
    cdate integer DEFAULT (abstime(now()))::integer
);


ALTER TABLE public.links OWNER TO webadmin;

--
-- Name: COLUMN links.id; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN links.id IS '링크 고유id';


--
-- Name: COLUMN links.category; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN links.category IS '분류id, =category.id';


--
-- Name: COLUMN links.criteria; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN links.criteria IS '게시판id, =menus.criteria';


--
-- Name: COLUMN links.title; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN links.title IS '링크 제목';


--
-- Name: COLUMN links.url; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN links.url IS '주소';


--
-- Name: COLUMN links.alternative; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN links.alternative IS '대체주소';


--
-- Name: COLUMN links.description; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN links.description IS '링크 설명';


--
-- Name: COLUMN links.lang; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN links.lang IS '사용언어';


--
-- Name: COLUMN links.sitetype; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN links.sitetype IS '사이트형태';


--
-- Name: COLUMN links.poster; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN links.poster IS '작성자';


--
-- Name: COLUMN links.visits; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN links.visits IS '방문횟수';


--
-- Name: COLUMN links.score; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN links.score IS '링크점수';


--
-- Name: COLUMN links.deleted; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN links.deleted IS '삭제되었는지';


--
-- Name: COLUMN links.cdate; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN links.cdate IS '생성날짜';


--
-- Name: menus; Type: TABLE; Schema: public; Owner: webadmin; Tablespace: 
--

CREATE TABLE menus (
    menuid integer NOT NULL,
    criteria text NOT NULL,
    subcrit text NOT NULL,
    sortnum integer NOT NULL,
    name text NOT NULL,
    menutype integer NOT NULL,
    today integer DEFAULT 0 NOT NULL,
    total integer DEFAULT 0 NOT NULL,
    xgroups integer[],
    lgroups integer[],
    vgroups integer[],
    wgroups integer[],
    rgroups integer[],
    lastid integer,
    upper integer NOT NULL,
    maxpage integer DEFAULT 0,
    tname text,
    allowupload boolean DEFAULT false
);


ALTER TABLE public.menus OWNER TO webadmin;

--
-- Name: TABLE menus; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON TABLE menus IS '메뉴정보';


--
-- Name: COLUMN menus.menuid; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN menus.menuid IS '일련번호';


--
-- Name: COLUMN menus.criteria; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN menus.criteria IS '상위메뉴명';


--
-- Name: COLUMN menus.subcrit; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN menus.subcrit IS '하위메뉴명';


--
-- Name: COLUMN menus.sortnum; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN menus.sortnum IS '정렬번호';


--
-- Name: COLUMN menus.name; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN menus.name IS '메뉴명';


--
-- Name: COLUMN menus.menutype; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN menus.menutype IS '메뉴종류, 1=분류,2=게시판,3=link,4=doc';


--
-- Name: COLUMN menus.today; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN menus.today IS '오늘등록된 게시물 개수';


--
-- Name: COLUMN menus.total; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN menus.total IS '전체 게시물 개수';


--
-- Name: COLUMN menus.xgroups; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN menus.xgroups IS '접근 그룹들';


--
-- Name: COLUMN menus.lgroups; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN menus.lgroups IS '리스팅 그룹들';


--
-- Name: COLUMN menus.vgroups; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN menus.vgroups IS '읽기 그룹들';


--
-- Name: COLUMN menus.wgroups; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN menus.wgroups IS '쓰기 그룹들';


--
-- Name: COLUMN menus.rgroups; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN menus.rgroups IS '댓글 그룹들';


--
-- Name: COLUMN menus.lastid; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN menus.lastid IS '마지막 글번호, list 시작번호가 됨';


--
-- Name: COLUMN menus.upper; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN menus.upper IS '상위 메뉴, =menus.menuid';


--
-- Name: COLUMN menus.maxpage; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN menus.maxpage IS 'board.pid = 0 인것들, 페이징 처리용';


--
-- Name: COLUMN menus.tname; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN menus.tname IS '해당 테이블 이름|외부URL 주소';


--
-- Name: COLUMN menus.allowupload; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN menus.allowupload IS '파일업로드허용여부';


--
-- Name: menus_menuid_seq; Type: SEQUENCE; Schema: public; Owner: webadmin
--

CREATE SEQUENCE menus_menuid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.menus_menuid_seq OWNER TO webadmin;

--
-- Name: menus_menuid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: webadmin
--

ALTER SEQUENCE menus_menuid_seq OWNED BY menus.menuid;


--
-- Name: token_table_name; Type: TABLE; Schema: public; Owner: webadmin; Tablespace: 
--

CREATE TABLE token_table_name (
    id integer NOT NULL,
    sid character varying(32) NOT NULL,
    mykey character(32) NOT NULL,
    stamp integer DEFAULT 0 NOT NULL,
    action character varying(64)
);


ALTER TABLE public.token_table_name OWNER TO webadmin;

--
-- Name: token_table_name_id_seq; Type: SEQUENCE; Schema: public; Owner: webadmin
--

CREATE SEQUENCE token_table_name_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.token_table_name_id_seq OWNER TO webadmin;

--
-- Name: token_table_name_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: webadmin
--

ALTER SEQUENCE token_table_name_id_seq OWNED BY token_table_name.id;


SET default_with_oids = true;

--
-- Name: uploadfiles; Type: TABLE; Schema: public; Owner: webadmin; Tablespace: 
--

CREATE TABLE uploadfiles (
    num integer NOT NULL,
    menuid integer,
    pid integer,
    fname text,
    fsize integer,
    fmime text,
    fwidth integer,
    fheight integer,
    ftime integer,
    ftype integer,
    sessionid text
);


ALTER TABLE public.uploadfiles OWNER TO webadmin;

--
-- Name: TABLE uploadfiles; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON TABLE uploadfiles IS '첨부파일들';


--
-- Name: COLUMN uploadfiles.num; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN uploadfiles.num IS '일련번호';


--
-- Name: COLUMN uploadfiles.menuid; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN uploadfiles.menuid IS '게시판 번호, =menus.menuid';


--
-- Name: COLUMN uploadfiles.pid; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN uploadfiles.pid IS '게시물 번호, =board.id';


--
-- Name: COLUMN uploadfiles.fname; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN uploadfiles.fname IS '파일이름';


--
-- Name: COLUMN uploadfiles.fsize; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN uploadfiles.fsize IS '파일크기';


--
-- Name: COLUMN uploadfiles.fmime; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN uploadfiles.fmime IS '파일종류';


--
-- Name: COLUMN uploadfiles.fwidth; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN uploadfiles.fwidth IS '이미지가로크기';


--
-- Name: COLUMN uploadfiles.fheight; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN uploadfiles.fheight IS '이미지세로크기';


--
-- Name: COLUMN uploadfiles.ftime; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN uploadfiles.ftime IS '소리,영상 연주시간';


--
-- Name: COLUMN uploadfiles.ftype; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN uploadfiles.ftype IS '문서=1,이미지=2,오디오=3,비디오=4,기타=5';


--
-- Name: COLUMN uploadfiles.sessionid; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN uploadfiles.sessionid IS '세션id';


--
-- Name: uploadfiles_num_seq; Type: SEQUENCE; Schema: public; Owner: webadmin
--

CREATE SEQUENCE uploadfiles_num_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.uploadfiles_num_seq OWNER TO webadmin;

--
-- Name: uploadfiles_num_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: webadmin
--

ALTER SEQUENCE uploadfiles_num_seq OWNED BY uploadfiles.num;


--
-- Name: user_proc; Type: VIEW; Schema: public; Owner: webadmin
--

CREATE VIEW user_proc AS
 SELECT a.proname,
    format_type(a.prorettype, NULL::integer) AS returns,
    oidvectortypes(a.proargtypes) AS args
   FROM pg_proc a
  WHERE (a.proowner = ( SELECT pg_user.usesysid
           FROM pg_user
          WHERE (pg_user.usename = "current_user"())));


ALTER TABLE public.user_proc OWNER TO webadmin;

SET default_with_oids = false;

--
-- Name: users; Type: TABLE; Schema: public; Owner: webadmin; Tablespace: 
--

CREATE TABLE users (
    num integer NOT NULL,
    uid text NOT NULL,
    passwd text NOT NULL,
    realname text,
    email text,
    homepage text,
    gids integer[] DEFAULT '{2}'::integer[],
    lastlogin integer DEFAULT (abstime(now()))::integer,
    posts integer DEFAULT 0,
    posttime integer DEFAULT (abstime(now()))::integer,
    description text,
    cdate integer NOT NULL,
    authkey text,
    openid text,
    CONSTRAINT users_uid CHECK ((uid ~ '^[A-Za-z0-9가-힝_]+$'::text))
);


ALTER TABLE public.users OWNER TO webadmin;

--
-- Name: TABLE users; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON TABLE users IS '사용자들';


--
-- Name: COLUMN users.num; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN users.num IS '회원번호';


--
-- Name: COLUMN users.uid; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN users.uid IS '사용자ID';


--
-- Name: COLUMN users.passwd; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN users.passwd IS 'MD5 인코딩 비밀번호';


--
-- Name: COLUMN users.realname; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN users.realname IS '사용자 실명';


--
-- Name: COLUMN users.email; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN users.email IS 'Email';


--
-- Name: COLUMN users.homepage; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN users.homepage IS 'Homepage URL';


--
-- Name: COLUMN users.gids; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN users.gids IS 'groups.gid의 부분집합';


--
-- Name: COLUMN users.lastlogin; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN users.lastlogin IS '마지막 접속 unix timestamp';


--
-- Name: COLUMN users.posts; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN users.posts IS '포스팅 갯수';


--
-- Name: COLUMN users.posttime; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN users.posttime IS '마지막 포스팅 unix timestamp';


--
-- Name: COLUMN users.description; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN users.description IS '자기소개, 현재 비워둠';


--
-- Name: COLUMN users.cdate; Type: COMMENT; Schema: public; Owner: webadmin
--

COMMENT ON COLUMN users.cdate IS '가입 unix timestamp';


--
-- Name: users_num_seq; Type: SEQUENCE; Schema: public; Owner: webadmin
--

CREATE SEQUENCE users_num_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.users_num_seq OWNER TO webadmin;

--
-- Name: users_num_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: webadmin
--

ALTER SEQUENCE users_num_seq OWNED BY users.num;


--
-- Name: viewmenus; Type: VIEW; Schema: public; Owner: webadmin
--

CREATE VIEW viewmenus AS
 SELECT t.depth,
    t.menuid,
    t.criteria,
    t.subcrit,
    t.name,
    t.menutype,
    t.xgroups,
    t.lgroups,
    t.tname,
    t.upper
   FROM viewmenus(1, 0) t(depth integer, menuid integer, criteria text, subcrit text, name text, menutype integer, xgroups integer[], lgroups integer[], tname text, upper integer);


ALTER TABLE public.viewmenus OWNER TO webadmin;

--
-- Name: vrelsize; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW vrelsize AS
 SELECT ss.relname,
    ss.tablesize,
    ss.indexsize,
    ss.toastsize,
    ss.toastindexsize,
    (((ss.tablesize + ss.indexsize) + ss.toastsize) + ss.toastindexsize) AS totalsize
   FROM ( SELECT cl.relname,
            pg_relation_size((cl.oid)::regclass) AS tablesize,
            COALESCE(( SELECT (sum(pg_relation_size((pg_index.indexrelid)::regclass)))::bigint AS sum
                   FROM pg_index
                  WHERE (cl.oid = pg_index.indrelid)), (0)::bigint) AS indexsize,
                CASE
                    WHEN (cl.reltoastrelid = (0)::oid) THEN (0)::bigint
                    ELSE pg_relation_size((cl.reltoastrelid)::regclass)
                END AS toastsize,
                CASE
                    WHEN (cl.reltoastrelid = (0)::oid) THEN (0)::bigint
                    ELSE pg_relation_size((( SELECT ct.reltoastidxid
                       FROM pg_class ct
                      WHERE (ct.oid = cl.reltoastrelid)))::regclass)
                END AS toastindexsize
           FROM pg_class cl
          WHERE ((cl.relowner = ( SELECT pg_user.usesysid
                   FROM pg_user
                  WHERE (pg_user.usename = "current_user"()))) AND (cl.relkind = 'r'::"char"))) ss;


ALTER TABLE public.vrelsize OWNER TO postgres;

--
-- Name: cdate; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_103 ALTER COLUMN cdate SET DEFAULT (abstime(now()))::integer;


--
-- Name: mdate; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_103 ALTER COLUMN mdate SET DEFAULT 0;


--
-- Name: reads; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_103 ALTER COLUMN reads SET DEFAULT 0;


--
-- Name: deleted; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_103 ALTER COLUMN deleted SET DEFAULT 0;


--
-- Name: passwd; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_103 ALTER COLUMN passwd SET DEFAULT ''::text;


--
-- Name: pid; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_103 ALTER COLUMN pid SET DEFAULT 0;


--
-- Name: crows; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_103 ALTER COLUMN crows SET DEFAULT 0;


--
-- Name: comments; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_103 ALTER COLUMN comments SET DEFAULT 0;


--
-- Name: commdate; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_103 ALTER COLUMN commdate SET DEFAULT 0;


--
-- Name: cdate; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_111 ALTER COLUMN cdate SET DEFAULT (abstime(now()))::integer;


--
-- Name: mdate; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_111 ALTER COLUMN mdate SET DEFAULT 0;


--
-- Name: reads; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_111 ALTER COLUMN reads SET DEFAULT 0;


--
-- Name: deleted; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_111 ALTER COLUMN deleted SET DEFAULT 0;


--
-- Name: passwd; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_111 ALTER COLUMN passwd SET DEFAULT ''::text;


--
-- Name: pid; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_111 ALTER COLUMN pid SET DEFAULT 0;


--
-- Name: crows; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_111 ALTER COLUMN crows SET DEFAULT 0;


--
-- Name: comments; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_111 ALTER COLUMN comments SET DEFAULT 0;


--
-- Name: commdate; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_111 ALTER COLUMN commdate SET DEFAULT 0;


--
-- Name: cdate; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_112 ALTER COLUMN cdate SET DEFAULT (abstime(now()))::integer;


--
-- Name: mdate; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_112 ALTER COLUMN mdate SET DEFAULT 0;


--
-- Name: reads; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_112 ALTER COLUMN reads SET DEFAULT 0;


--
-- Name: deleted; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_112 ALTER COLUMN deleted SET DEFAULT 0;


--
-- Name: passwd; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_112 ALTER COLUMN passwd SET DEFAULT ''::text;


--
-- Name: pid; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_112 ALTER COLUMN pid SET DEFAULT 0;


--
-- Name: crows; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_112 ALTER COLUMN crows SET DEFAULT 0;


--
-- Name: comments; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_112 ALTER COLUMN comments SET DEFAULT 0;


--
-- Name: commdate; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_112 ALTER COLUMN commdate SET DEFAULT 0;


--
-- Name: cdate; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_117 ALTER COLUMN cdate SET DEFAULT (abstime(now()))::integer;


--
-- Name: mdate; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_117 ALTER COLUMN mdate SET DEFAULT 0;


--
-- Name: reads; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_117 ALTER COLUMN reads SET DEFAULT 0;


--
-- Name: deleted; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_117 ALTER COLUMN deleted SET DEFAULT 0;


--
-- Name: passwd; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_117 ALTER COLUMN passwd SET DEFAULT ''::text;


--
-- Name: pid; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_117 ALTER COLUMN pid SET DEFAULT 0;


--
-- Name: crows; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_117 ALTER COLUMN crows SET DEFAULT 0;


--
-- Name: comments; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_117 ALTER COLUMN comments SET DEFAULT 0;


--
-- Name: commdate; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_117 ALTER COLUMN commdate SET DEFAULT 0;


--
-- Name: cdate; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_125 ALTER COLUMN cdate SET DEFAULT (abstime(now()))::integer;


--
-- Name: mdate; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_125 ALTER COLUMN mdate SET DEFAULT 0;


--
-- Name: reads; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_125 ALTER COLUMN reads SET DEFAULT 0;


--
-- Name: deleted; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_125 ALTER COLUMN deleted SET DEFAULT 0;


--
-- Name: passwd; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_125 ALTER COLUMN passwd SET DEFAULT ''::text;


--
-- Name: pid; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_125 ALTER COLUMN pid SET DEFAULT 0;


--
-- Name: crows; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_125 ALTER COLUMN crows SET DEFAULT 0;


--
-- Name: comments; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_125 ALTER COLUMN comments SET DEFAULT 0;


--
-- Name: commdate; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_125 ALTER COLUMN commdate SET DEFAULT 0;


--
-- Name: cdate; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_13 ALTER COLUMN cdate SET DEFAULT (abstime(now()))::integer;


--
-- Name: mdate; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_13 ALTER COLUMN mdate SET DEFAULT 0;


--
-- Name: reads; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_13 ALTER COLUMN reads SET DEFAULT 0;


--
-- Name: deleted; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_13 ALTER COLUMN deleted SET DEFAULT 0;


--
-- Name: passwd; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_13 ALTER COLUMN passwd SET DEFAULT ''::text;


--
-- Name: pid; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_13 ALTER COLUMN pid SET DEFAULT 0;


--
-- Name: crows; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_13 ALTER COLUMN crows SET DEFAULT 0;


--
-- Name: comments; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_13 ALTER COLUMN comments SET DEFAULT 0;


--
-- Name: commdate; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_13 ALTER COLUMN commdate SET DEFAULT 0;


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_137 ALTER COLUMN id SET DEFAULT nextval('bd_137_id_seq'::regclass);


--
-- Name: cdate; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_137 ALTER COLUMN cdate SET DEFAULT (abstime(now()))::integer;


--
-- Name: mdate; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_137 ALTER COLUMN mdate SET DEFAULT 0;


--
-- Name: reads; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_137 ALTER COLUMN reads SET DEFAULT 0;


--
-- Name: deleted; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_137 ALTER COLUMN deleted SET DEFAULT 0;


--
-- Name: passwd; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_137 ALTER COLUMN passwd SET DEFAULT ''::text;


--
-- Name: pid; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_137 ALTER COLUMN pid SET DEFAULT 0;


--
-- Name: crows; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_137 ALTER COLUMN crows SET DEFAULT 0;


--
-- Name: comments; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_137 ALTER COLUMN comments SET DEFAULT 0;


--
-- Name: commdate; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_137 ALTER COLUMN commdate SET DEFAULT 0;


--
-- Name: cdate; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_21 ALTER COLUMN cdate SET DEFAULT (abstime(now()))::integer;


--
-- Name: mdate; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_21 ALTER COLUMN mdate SET DEFAULT 0;


--
-- Name: reads; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_21 ALTER COLUMN reads SET DEFAULT 0;


--
-- Name: deleted; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_21 ALTER COLUMN deleted SET DEFAULT 0;


--
-- Name: passwd; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_21 ALTER COLUMN passwd SET DEFAULT ''::text;


--
-- Name: pid; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_21 ALTER COLUMN pid SET DEFAULT 0;


--
-- Name: crows; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_21 ALTER COLUMN crows SET DEFAULT 0;


--
-- Name: comments; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_21 ALTER COLUMN comments SET DEFAULT 0;


--
-- Name: commdate; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_21 ALTER COLUMN commdate SET DEFAULT 0;


--
-- Name: cdate; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_22 ALTER COLUMN cdate SET DEFAULT (abstime(now()))::integer;


--
-- Name: mdate; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_22 ALTER COLUMN mdate SET DEFAULT 0;


--
-- Name: reads; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_22 ALTER COLUMN reads SET DEFAULT 0;


--
-- Name: deleted; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_22 ALTER COLUMN deleted SET DEFAULT 0;


--
-- Name: passwd; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_22 ALTER COLUMN passwd SET DEFAULT ''::text;


--
-- Name: pid; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_22 ALTER COLUMN pid SET DEFAULT 0;


--
-- Name: crows; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_22 ALTER COLUMN crows SET DEFAULT 0;


--
-- Name: comments; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_22 ALTER COLUMN comments SET DEFAULT 0;


--
-- Name: commdate; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_22 ALTER COLUMN commdate SET DEFAULT 0;


--
-- Name: cdate; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_23 ALTER COLUMN cdate SET DEFAULT (abstime(now()))::integer;


--
-- Name: mdate; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_23 ALTER COLUMN mdate SET DEFAULT 0;


--
-- Name: reads; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_23 ALTER COLUMN reads SET DEFAULT 0;


--
-- Name: deleted; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_23 ALTER COLUMN deleted SET DEFAULT 0;


--
-- Name: passwd; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_23 ALTER COLUMN passwd SET DEFAULT ''::text;


--
-- Name: pid; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_23 ALTER COLUMN pid SET DEFAULT 0;


--
-- Name: crows; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_23 ALTER COLUMN crows SET DEFAULT 0;


--
-- Name: comments; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_23 ALTER COLUMN comments SET DEFAULT 0;


--
-- Name: commdate; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_23 ALTER COLUMN commdate SET DEFAULT 0;


--
-- Name: cdate; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_31 ALTER COLUMN cdate SET DEFAULT (abstime(now()))::integer;


--
-- Name: mdate; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_31 ALTER COLUMN mdate SET DEFAULT 0;


--
-- Name: reads; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_31 ALTER COLUMN reads SET DEFAULT 0;


--
-- Name: deleted; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_31 ALTER COLUMN deleted SET DEFAULT 0;


--
-- Name: passwd; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_31 ALTER COLUMN passwd SET DEFAULT ''::text;


--
-- Name: pid; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_31 ALTER COLUMN pid SET DEFAULT 0;


--
-- Name: crows; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_31 ALTER COLUMN crows SET DEFAULT 0;


--
-- Name: comments; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_31 ALTER COLUMN comments SET DEFAULT 0;


--
-- Name: commdate; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_31 ALTER COLUMN commdate SET DEFAULT 0;


--
-- Name: cdate; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_39 ALTER COLUMN cdate SET DEFAULT (abstime(now()))::integer;


--
-- Name: mdate; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_39 ALTER COLUMN mdate SET DEFAULT 0;


--
-- Name: reads; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_39 ALTER COLUMN reads SET DEFAULT 0;


--
-- Name: deleted; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_39 ALTER COLUMN deleted SET DEFAULT 0;


--
-- Name: passwd; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_39 ALTER COLUMN passwd SET DEFAULT ''::text;


--
-- Name: pid; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_39 ALTER COLUMN pid SET DEFAULT 0;


--
-- Name: crows; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_39 ALTER COLUMN crows SET DEFAULT 0;


--
-- Name: comments; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_39 ALTER COLUMN comments SET DEFAULT 0;


--
-- Name: commdate; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_39 ALTER COLUMN commdate SET DEFAULT 0;


--
-- Name: cdate; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_47 ALTER COLUMN cdate SET DEFAULT (abstime(now()))::integer;


--
-- Name: mdate; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_47 ALTER COLUMN mdate SET DEFAULT 0;


--
-- Name: reads; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_47 ALTER COLUMN reads SET DEFAULT 0;


--
-- Name: deleted; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_47 ALTER COLUMN deleted SET DEFAULT 0;


--
-- Name: passwd; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_47 ALTER COLUMN passwd SET DEFAULT ''::text;


--
-- Name: pid; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_47 ALTER COLUMN pid SET DEFAULT 0;


--
-- Name: crows; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_47 ALTER COLUMN crows SET DEFAULT 0;


--
-- Name: comments; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_47 ALTER COLUMN comments SET DEFAULT 0;


--
-- Name: commdate; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_47 ALTER COLUMN commdate SET DEFAULT 0;


--
-- Name: cdate; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_5 ALTER COLUMN cdate SET DEFAULT (abstime(now()))::integer;


--
-- Name: mdate; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_5 ALTER COLUMN mdate SET DEFAULT 0;


--
-- Name: reads; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_5 ALTER COLUMN reads SET DEFAULT 0;


--
-- Name: deleted; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_5 ALTER COLUMN deleted SET DEFAULT 0;


--
-- Name: passwd; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_5 ALTER COLUMN passwd SET DEFAULT ''::text;


--
-- Name: pid; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_5 ALTER COLUMN pid SET DEFAULT 0;


--
-- Name: crows; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_5 ALTER COLUMN crows SET DEFAULT 0;


--
-- Name: comments; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_5 ALTER COLUMN comments SET DEFAULT 0;


--
-- Name: commdate; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_5 ALTER COLUMN commdate SET DEFAULT 0;


--
-- Name: cdate; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_55 ALTER COLUMN cdate SET DEFAULT (abstime(now()))::integer;


--
-- Name: mdate; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_55 ALTER COLUMN mdate SET DEFAULT 0;


--
-- Name: reads; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_55 ALTER COLUMN reads SET DEFAULT 0;


--
-- Name: deleted; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_55 ALTER COLUMN deleted SET DEFAULT 0;


--
-- Name: passwd; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_55 ALTER COLUMN passwd SET DEFAULT ''::text;


--
-- Name: pid; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_55 ALTER COLUMN pid SET DEFAULT 0;


--
-- Name: crows; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_55 ALTER COLUMN crows SET DEFAULT 0;


--
-- Name: comments; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_55 ALTER COLUMN comments SET DEFAULT 0;


--
-- Name: commdate; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_55 ALTER COLUMN commdate SET DEFAULT 0;


--
-- Name: cdate; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_63 ALTER COLUMN cdate SET DEFAULT (abstime(now()))::integer;


--
-- Name: mdate; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_63 ALTER COLUMN mdate SET DEFAULT 0;


--
-- Name: reads; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_63 ALTER COLUMN reads SET DEFAULT 0;


--
-- Name: deleted; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_63 ALTER COLUMN deleted SET DEFAULT 0;


--
-- Name: passwd; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_63 ALTER COLUMN passwd SET DEFAULT ''::text;


--
-- Name: pid; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_63 ALTER COLUMN pid SET DEFAULT 0;


--
-- Name: crows; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_63 ALTER COLUMN crows SET DEFAULT 0;


--
-- Name: comments; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_63 ALTER COLUMN comments SET DEFAULT 0;


--
-- Name: commdate; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_63 ALTER COLUMN commdate SET DEFAULT 0;


--
-- Name: cdate; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_71 ALTER COLUMN cdate SET DEFAULT (abstime(now()))::integer;


--
-- Name: mdate; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_71 ALTER COLUMN mdate SET DEFAULT 0;


--
-- Name: reads; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_71 ALTER COLUMN reads SET DEFAULT 0;


--
-- Name: deleted; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_71 ALTER COLUMN deleted SET DEFAULT 0;


--
-- Name: passwd; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_71 ALTER COLUMN passwd SET DEFAULT ''::text;


--
-- Name: pid; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_71 ALTER COLUMN pid SET DEFAULT 0;


--
-- Name: crows; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_71 ALTER COLUMN crows SET DEFAULT 0;


--
-- Name: comments; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_71 ALTER COLUMN comments SET DEFAULT 0;


--
-- Name: commdate; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_71 ALTER COLUMN commdate SET DEFAULT 0;


--
-- Name: cdate; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_79 ALTER COLUMN cdate SET DEFAULT (abstime(now()))::integer;


--
-- Name: mdate; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_79 ALTER COLUMN mdate SET DEFAULT 0;


--
-- Name: reads; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_79 ALTER COLUMN reads SET DEFAULT 0;


--
-- Name: deleted; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_79 ALTER COLUMN deleted SET DEFAULT 0;


--
-- Name: passwd; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_79 ALTER COLUMN passwd SET DEFAULT ''::text;


--
-- Name: pid; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_79 ALTER COLUMN pid SET DEFAULT 0;


--
-- Name: crows; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_79 ALTER COLUMN crows SET DEFAULT 0;


--
-- Name: comments; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_79 ALTER COLUMN comments SET DEFAULT 0;


--
-- Name: commdate; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_79 ALTER COLUMN commdate SET DEFAULT 0;


--
-- Name: cdate; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_87 ALTER COLUMN cdate SET DEFAULT (abstime(now()))::integer;


--
-- Name: mdate; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_87 ALTER COLUMN mdate SET DEFAULT 0;


--
-- Name: reads; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_87 ALTER COLUMN reads SET DEFAULT 0;


--
-- Name: deleted; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_87 ALTER COLUMN deleted SET DEFAULT 0;


--
-- Name: passwd; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_87 ALTER COLUMN passwd SET DEFAULT ''::text;


--
-- Name: pid; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_87 ALTER COLUMN pid SET DEFAULT 0;


--
-- Name: crows; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_87 ALTER COLUMN crows SET DEFAULT 0;


--
-- Name: comments; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_87 ALTER COLUMN comments SET DEFAULT 0;


--
-- Name: commdate; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_87 ALTER COLUMN commdate SET DEFAULT 0;


--
-- Name: cdate; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_95 ALTER COLUMN cdate SET DEFAULT (abstime(now()))::integer;


--
-- Name: mdate; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_95 ALTER COLUMN mdate SET DEFAULT 0;


--
-- Name: reads; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_95 ALTER COLUMN reads SET DEFAULT 0;


--
-- Name: deleted; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_95 ALTER COLUMN deleted SET DEFAULT 0;


--
-- Name: passwd; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_95 ALTER COLUMN passwd SET DEFAULT ''::text;


--
-- Name: pid; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_95 ALTER COLUMN pid SET DEFAULT 0;


--
-- Name: crows; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_95 ALTER COLUMN crows SET DEFAULT 0;


--
-- Name: comments; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_95 ALTER COLUMN comments SET DEFAULT 0;


--
-- Name: commdate; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY bd_95 ALTER COLUMN commdate SET DEFAULT 0;


--
-- Name: cid; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY comments ALTER COLUMN cid SET DEFAULT nextval('comments_cid_seq'::regclass);


--
-- Name: gid; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY groups ALTER COLUMN gid SET DEFAULT nextval('groups_gid_seq'::regclass);


--
-- Name: num; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY keywords ALTER COLUMN num SET DEFAULT nextval('keywords_num_seq'::regclass);


--
-- Name: menuid; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY menus ALTER COLUMN menuid SET DEFAULT nextval('menus_menuid_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY token_table_name ALTER COLUMN id SET DEFAULT nextval('token_table_name_id_seq'::regclass);


--
-- Name: num; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY uploadfiles ALTER COLUMN num SET DEFAULT nextval('uploadfiles_num_seq'::regclass);


--
-- Name: num; Type: DEFAULT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY users ALTER COLUMN num SET DEFAULT nextval('users_num_seq'::regclass);


SET default_tablespace = tbs_bd_103;

--
-- Name: bd_103_pkey; Type: CONSTRAINT; Schema: public; Owner: webadmin; Tablespace: tbs_bd_103
--

ALTER TABLE ONLY bd_103
    ADD CONSTRAINT bd_103_pkey PRIMARY KEY (id);


SET default_tablespace = tbs_bd_111;

--
-- Name: bd_111_pkey; Type: CONSTRAINT; Schema: public; Owner: webadmin; Tablespace: tbs_bd_111
--

ALTER TABLE ONLY bd_111
    ADD CONSTRAINT bd_111_pkey PRIMARY KEY (id);


SET default_tablespace = tbs_bd_112;

--
-- Name: bd_112_pkey; Type: CONSTRAINT; Schema: public; Owner: webadmin; Tablespace: tbs_bd_112
--

ALTER TABLE ONLY bd_112
    ADD CONSTRAINT bd_112_pkey PRIMARY KEY (id);


SET default_tablespace = tbs_bd_117;

--
-- Name: bd_117_pkey; Type: CONSTRAINT; Schema: public; Owner: webadmin; Tablespace: tbs_bd_117
--

ALTER TABLE ONLY bd_117
    ADD CONSTRAINT bd_117_pkey PRIMARY KEY (id);


SET default_tablespace = tbs_bd_125;

--
-- Name: bd_125_pkey; Type: CONSTRAINT; Schema: public; Owner: webadmin; Tablespace: tbs_bd_125
--

ALTER TABLE ONLY bd_125
    ADD CONSTRAINT bd_125_pkey PRIMARY KEY (id);


SET default_tablespace = tbs_bd_137;

--
-- Name: bd_137_pkey; Type: CONSTRAINT; Schema: public; Owner: webadmin; Tablespace: tbs_bd_137
--

ALTER TABLE ONLY bd_137
    ADD CONSTRAINT bd_137_pkey PRIMARY KEY (id);


SET default_tablespace = tbs_bd_13;

--
-- Name: bd_13_pkey; Type: CONSTRAINT; Schema: public; Owner: webadmin; Tablespace: tbs_bd_13
--

ALTER TABLE ONLY bd_13
    ADD CONSTRAINT bd_13_pkey PRIMARY KEY (id);


SET default_tablespace = tbs_bd_21;

--
-- Name: bd_21_pkey; Type: CONSTRAINT; Schema: public; Owner: webadmin; Tablespace: tbs_bd_21
--

ALTER TABLE ONLY bd_21
    ADD CONSTRAINT bd_21_pkey PRIMARY KEY (id);


SET default_tablespace = tbs_bd_22;

--
-- Name: bd_22_pkey; Type: CONSTRAINT; Schema: public; Owner: webadmin; Tablespace: tbs_bd_22
--

ALTER TABLE ONLY bd_22
    ADD CONSTRAINT bd_22_pkey PRIMARY KEY (id);


SET default_tablespace = tbs_bd_23;

--
-- Name: bd_23_pkey; Type: CONSTRAINT; Schema: public; Owner: webadmin; Tablespace: tbs_bd_23
--

ALTER TABLE ONLY bd_23
    ADD CONSTRAINT bd_23_pkey PRIMARY KEY (id);


SET default_tablespace = '';

--
-- Name: bd_31_pkey; Type: CONSTRAINT; Schema: public; Owner: webadmin; Tablespace: 
--

ALTER TABLE ONLY bd_31
    ADD CONSTRAINT bd_31_pkey PRIMARY KEY (id);


--
-- Name: bd_39_pkey; Type: CONSTRAINT; Schema: public; Owner: webadmin; Tablespace: 
--

ALTER TABLE ONLY bd_39
    ADD CONSTRAINT bd_39_pkey PRIMARY KEY (id);


SET default_tablespace = tbs_bd_47;

--
-- Name: bd_47_pkey; Type: CONSTRAINT; Schema: public; Owner: webadmin; Tablespace: tbs_bd_47
--

ALTER TABLE ONLY bd_47
    ADD CONSTRAINT bd_47_pkey PRIMARY KEY (id);


SET default_tablespace = tbs_bd_55;

--
-- Name: bd_55_pkey; Type: CONSTRAINT; Schema: public; Owner: webadmin; Tablespace: tbs_bd_55
--

ALTER TABLE ONLY bd_55
    ADD CONSTRAINT bd_55_pkey PRIMARY KEY (id);


SET default_tablespace = tbs_bd_5;

--
-- Name: bd_5_pkey; Type: CONSTRAINT; Schema: public; Owner: webadmin; Tablespace: tbs_bd_5
--

ALTER TABLE ONLY bd_5
    ADD CONSTRAINT bd_5_pkey PRIMARY KEY (id);


SET default_tablespace = tbs_bd_63;

--
-- Name: bd_63_pkey; Type: CONSTRAINT; Schema: public; Owner: webadmin; Tablespace: tbs_bd_63
--

ALTER TABLE ONLY bd_63
    ADD CONSTRAINT bd_63_pkey PRIMARY KEY (id);


SET default_tablespace = tbs_bd_71;

--
-- Name: bd_71_pkey; Type: CONSTRAINT; Schema: public; Owner: webadmin; Tablespace: tbs_bd_71
--

ALTER TABLE ONLY bd_71
    ADD CONSTRAINT bd_71_pkey PRIMARY KEY (id);


SET default_tablespace = tbs_bd_79;

--
-- Name: bd_79_pkey; Type: CONSTRAINT; Schema: public; Owner: webadmin; Tablespace: tbs_bd_79
--

ALTER TABLE ONLY bd_79
    ADD CONSTRAINT bd_79_pkey PRIMARY KEY (id);


SET default_tablespace = tbs_bd_87;

--
-- Name: bd_87_pkey; Type: CONSTRAINT; Schema: public; Owner: webadmin; Tablespace: tbs_bd_87
--

ALTER TABLE ONLY bd_87
    ADD CONSTRAINT bd_87_pkey PRIMARY KEY (id);


SET default_tablespace = tbs_bd_95;

--
-- Name: bd_95_pkey; Type: CONSTRAINT; Schema: public; Owner: webadmin; Tablespace: tbs_bd_95
--

ALTER TABLE ONLY bd_95
    ADD CONSTRAINT bd_95_pkey PRIMARY KEY (id);


SET default_tablespace = '';

--
-- Name: category_pkey; Type: CONSTRAINT; Schema: public; Owner: webadmin; Tablespace: 
--

ALTER TABLE ONLY category
    ADD CONSTRAINT category_pkey PRIMARY KEY (id);


--
-- Name: comments_pkey; Type: CONSTRAINT; Schema: public; Owner: webadmin; Tablespace: 
--

ALTER TABLE ONLY comments
    ADD CONSTRAINT comments_pkey PRIMARY KEY (cid);


--
-- Name: groups_pkey; Type: CONSTRAINT; Schema: public; Owner: webadmin; Tablespace: 
--

ALTER TABLE ONLY groups
    ADD CONSTRAINT groups_pkey PRIMARY KEY (gid);


--
-- Name: imagefiles_pkey; Type: CONSTRAINT; Schema: public; Owner: webadmin; Tablespace: 
--

ALTER TABLE ONLY imagefiles
    ADD CONSTRAINT imagefiles_pkey PRIMARY KEY (imgname);


--
-- Name: keywords_pkey; Type: CONSTRAINT; Schema: public; Owner: webadmin; Tablespace: 
--

ALTER TABLE ONLY keywords
    ADD CONSTRAINT keywords_pkey PRIMARY KEY (num);


--
-- Name: links_pkey; Type: CONSTRAINT; Schema: public; Owner: webadmin; Tablespace: 
--

ALTER TABLE ONLY links
    ADD CONSTRAINT links_pkey PRIMARY KEY (id);


--
-- Name: menus_pkey; Type: CONSTRAINT; Schema: public; Owner: webadmin; Tablespace: 
--

ALTER TABLE ONLY menus
    ADD CONSTRAINT menus_pkey PRIMARY KEY (menuid);


--
-- Name: token_table_name_pkey; Type: CONSTRAINT; Schema: public; Owner: webadmin; Tablespace: 
--

ALTER TABLE ONLY token_table_name
    ADD CONSTRAINT token_table_name_pkey PRIMARY KEY (id);


--
-- Name: uploadfiles_pkey; Type: CONSTRAINT; Schema: public; Owner: webadmin; Tablespace: 
--

ALTER TABLE ONLY uploadfiles
    ADD CONSTRAINT uploadfiles_pkey PRIMARY KEY (num);


--
-- Name: users_pkey; Type: CONSTRAINT; Schema: public; Owner: webadmin; Tablespace: 
--

ALTER TABLE ONLY users
    ADD CONSTRAINT users_pkey PRIMARY KEY (num);


SET default_tablespace = tbs_bd_103;

--
-- Name: bd_103_cdate_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_103
--

CREATE INDEX bd_103_cdate_i ON bd_103 USING btree (cdate);


--
-- Name: bd_103_fti_kc_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_103
--

CREATE INDEX bd_103_fti_kc_i ON bd_103_fti USING btree (k, c);


--
-- Name: bd_103_fti_v_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_103
--

CREATE INDEX bd_103_fti_v_i ON bd_103_fti USING btree (v);


--
-- Name: bd_103_gid; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_103
--

CREATE INDEX bd_103_gid ON bd_103 USING btree (gid);


--
-- Name: bd_103_id_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_103
--

CREATE INDEX bd_103_id_i ON bd_103 USING btree (id, topic) WHERE (pid = 0);


--
-- Name: bd_103_pid; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_103
--

CREATE INDEX bd_103_pid ON bd_103 USING btree (pid);


--
-- Name: bd_103_usernum_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_103
--

CREATE INDEX bd_103_usernum_i ON bd_103 USING btree (usernum);


SET default_tablespace = tbs_bd_111;

--
-- Name: bd_111_cdate_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_111
--

CREATE INDEX bd_111_cdate_i ON bd_111 USING btree (cdate);


--
-- Name: bd_111_fti_kc_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_111
--

CREATE INDEX bd_111_fti_kc_i ON bd_111_fti USING btree (k, c);


--
-- Name: bd_111_fti_v_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_111
--

CREATE INDEX bd_111_fti_v_i ON bd_111_fti USING btree (v);


--
-- Name: bd_111_gid; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_111
--

CREATE INDEX bd_111_gid ON bd_111 USING btree (gid);


--
-- Name: bd_111_id_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_111
--

CREATE INDEX bd_111_id_i ON bd_111 USING btree (id, topic) WHERE (pid = 0);


--
-- Name: bd_111_pid; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_111
--

CREATE INDEX bd_111_pid ON bd_111 USING btree (pid);


--
-- Name: bd_111_usernum_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_111
--

CREATE INDEX bd_111_usernum_i ON bd_111 USING btree (usernum);


SET default_tablespace = tbs_bd_112;

--
-- Name: bd_112_cdate_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_112
--

CREATE INDEX bd_112_cdate_i ON bd_112 USING btree (cdate);


--
-- Name: bd_112_fti_kc_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_112
--

CREATE INDEX bd_112_fti_kc_i ON bd_112_fti USING btree (k, c);


--
-- Name: bd_112_fti_v_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_112
--

CREATE INDEX bd_112_fti_v_i ON bd_112_fti USING btree (v);


--
-- Name: bd_112_gid; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_112
--

CREATE INDEX bd_112_gid ON bd_112 USING btree (gid);


--
-- Name: bd_112_id_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_112
--

CREATE INDEX bd_112_id_i ON bd_112 USING btree (id, topic) WHERE (pid = 0);


--
-- Name: bd_112_pid; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_112
--

CREATE INDEX bd_112_pid ON bd_112 USING btree (pid);


--
-- Name: bd_112_usernum_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_112
--

CREATE INDEX bd_112_usernum_i ON bd_112 USING btree (usernum);


SET default_tablespace = tbs_bd_117;

--
-- Name: bd_117_cdate_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_117
--

CREATE INDEX bd_117_cdate_i ON bd_117 USING btree (cdate);


--
-- Name: bd_117_fti_kc_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_117
--

CREATE INDEX bd_117_fti_kc_i ON bd_117_fti USING btree (k, c);


--
-- Name: bd_117_fti_v_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_117
--

CREATE INDEX bd_117_fti_v_i ON bd_117_fti USING btree (v);


--
-- Name: bd_117_id_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_117
--

CREATE INDEX bd_117_id_i ON bd_117 USING btree (id, topic);


SET default_tablespace = '';

--
-- Name: bd_117_pid_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: 
--

CREATE INDEX bd_117_pid_i ON bd_117 USING btree (pid);


SET default_tablespace = tbs_bd_117;

--
-- Name: bd_117_usernum_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_117
--

CREATE INDEX bd_117_usernum_i ON bd_117 USING btree (usernum);


SET default_tablespace = tbs_bd_125;

--
-- Name: bd_125_cdate_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_125
--

CREATE INDEX bd_125_cdate_i ON bd_125 USING btree (cdate);


--
-- Name: bd_125_fti_kc_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_125
--

CREATE INDEX bd_125_fti_kc_i ON bd_125_fti USING btree (k, c);


--
-- Name: bd_125_fti_v_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_125
--

CREATE INDEX bd_125_fti_v_i ON bd_125_fti USING btree (v);


SET default_tablespace = '';

--
-- Name: bd_125_gid_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: 
--

CREATE INDEX bd_125_gid_i ON bd_125 USING btree (gid);


SET default_tablespace = tbs_bd_125;

--
-- Name: bd_125_id_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_125
--

CREATE INDEX bd_125_id_i ON bd_125 USING btree (id, topic);


SET default_tablespace = '';

--
-- Name: bd_125_pid_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: 
--

CREATE INDEX bd_125_pid_i ON bd_125 USING btree (pid);


SET default_tablespace = tbs_bd_125;

--
-- Name: bd_125_usernum_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_125
--

CREATE INDEX bd_125_usernum_i ON bd_125 USING btree (usernum);


SET default_tablespace = tbs_bd_137;

--
-- Name: bd_137_cdate_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_137
--

CREATE INDEX bd_137_cdate_i ON bd_137 USING btree (cdate);


--
-- Name: bd_137_fti_kc_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_137
--

CREATE INDEX bd_137_fti_kc_i ON bd_137_fti USING btree (k, c);


--
-- Name: bd_137_fti_v_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_137
--

CREATE INDEX bd_137_fti_v_i ON bd_137_fti USING btree (v);


--
-- Name: bd_137_gid; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_137
--

CREATE INDEX bd_137_gid ON bd_137 USING btree (gid);


SET default_tablespace = '';

--
-- Name: bd_137_id_id; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: 
--

CREATE INDEX bd_137_id_id ON bd_137 USING btree (id, topic) WHERE (pid = 0);


SET default_tablespace = tbs_bd_137;

--
-- Name: bd_137_pid; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_137
--

CREATE INDEX bd_137_pid ON bd_137 USING btree (pid);


--
-- Name: bd_137_usernum_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_137
--

CREATE INDEX bd_137_usernum_i ON bd_137 USING btree (usernum);


SET default_tablespace = tbs_bd_13;

--
-- Name: bd_13_cdate_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_13
--

CREATE INDEX bd_13_cdate_i ON bd_13 USING btree (cdate);


--
-- Name: bd_13_fti_kc_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_13
--

CREATE INDEX bd_13_fti_kc_i ON bd_13_fti USING btree (k, c);


--
-- Name: bd_13_fti_v_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_13
--

CREATE INDEX bd_13_fti_v_i ON bd_13_fti USING btree (v);


--
-- Name: bd_13_gid; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_13
--

CREATE INDEX bd_13_gid ON bd_13 USING btree (gid);


--
-- Name: bd_13_id_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_13
--

CREATE INDEX bd_13_id_i ON bd_13 USING btree (id, topic) WHERE (pid = 0);


--
-- Name: bd_13_pid; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_13
--

CREATE INDEX bd_13_pid ON bd_13 USING btree (pid);


--
-- Name: bd_13_usernum_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_13
--

CREATE INDEX bd_13_usernum_i ON bd_13 USING btree (usernum);


SET default_tablespace = tbs_bd_21;

--
-- Name: bd_21_cdate_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_21
--

CREATE INDEX bd_21_cdate_i ON bd_21 USING btree (cdate);


--
-- Name: bd_21_fti_kc_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_21
--

CREATE INDEX bd_21_fti_kc_i ON bd_21_fti USING btree (k, c);


--
-- Name: bd_21_fti_v_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_21
--

CREATE INDEX bd_21_fti_v_i ON bd_21_fti USING btree (v);


--
-- Name: bd_21_gid; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_21
--

CREATE INDEX bd_21_gid ON bd_21 USING btree (gid);


--
-- Name: bd_21_id_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_21
--

CREATE INDEX bd_21_id_i ON bd_21 USING btree (id, topic) WHERE (pid = 0);


--
-- Name: bd_21_pid; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_21
--

CREATE INDEX bd_21_pid ON bd_21 USING btree (pid);


--
-- Name: bd_21_usernum_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_21
--

CREATE INDEX bd_21_usernum_i ON bd_21 USING btree (usernum);


SET default_tablespace = tbs_bd_22;

--
-- Name: bd_22_cdate_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_22
--

CREATE INDEX bd_22_cdate_i ON bd_22 USING btree (cdate);


--
-- Name: bd_22_fti_kc_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_22
--

CREATE INDEX bd_22_fti_kc_i ON bd_22_fti USING btree (k, c);


--
-- Name: bd_22_fti_v_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_22
--

CREATE INDEX bd_22_fti_v_i ON bd_22_fti USING btree (v);


--
-- Name: bd_22_gid; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_22
--

CREATE INDEX bd_22_gid ON bd_22 USING btree (gid);


--
-- Name: bd_22_id_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_22
--

CREATE INDEX bd_22_id_i ON bd_22 USING btree (id, topic) WHERE (pid = 0);


--
-- Name: bd_22_pid; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_22
--

CREATE INDEX bd_22_pid ON bd_22 USING btree (pid);


--
-- Name: bd_22_usernum_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_22
--

CREATE INDEX bd_22_usernum_i ON bd_22 USING btree (usernum);


SET default_tablespace = tbs_bd_23;

--
-- Name: bd_23_cdate_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_23
--

CREATE INDEX bd_23_cdate_i ON bd_23 USING btree (cdate);


--
-- Name: bd_23_fti_kc_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_23
--

CREATE INDEX bd_23_fti_kc_i ON bd_23_fti USING btree (k, c);


--
-- Name: bd_23_fti_v_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_23
--

CREATE INDEX bd_23_fti_v_i ON bd_23_fti USING btree (v);


--
-- Name: bd_23_gid; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_23
--

CREATE INDEX bd_23_gid ON bd_23 USING btree (gid);


--
-- Name: bd_23_id_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_23
--

CREATE INDEX bd_23_id_i ON bd_23 USING btree (id, topic) WHERE (pid = 0);


--
-- Name: bd_23_pid; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_23
--

CREATE INDEX bd_23_pid ON bd_23 USING btree (pid);


--
-- Name: bd_23_usernum_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_23
--

CREATE INDEX bd_23_usernum_i ON bd_23 USING btree (usernum);


SET default_tablespace = '';

--
-- Name: bd_31_cdate_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: 
--

CREATE INDEX bd_31_cdate_i ON bd_31 USING btree (cdate);


--
-- Name: bd_31_fti_kc_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: 
--

CREATE INDEX bd_31_fti_kc_i ON bd_31_fti USING btree (k, c);


--
-- Name: bd_31_fti_v_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: 
--

CREATE INDEX bd_31_fti_v_i ON bd_31_fti USING btree (v);


--
-- Name: bd_31_gid; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: 
--

CREATE INDEX bd_31_gid ON bd_31 USING btree (gid);


--
-- Name: bd_31_id_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: 
--

CREATE INDEX bd_31_id_i ON bd_31 USING btree (id, topic) WHERE (pid = 0);


--
-- Name: bd_31_pid; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: 
--

CREATE INDEX bd_31_pid ON bd_31 USING btree (pid);


--
-- Name: bd_31_usernum_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: 
--

CREATE INDEX bd_31_usernum_i ON bd_31 USING btree (usernum);


--
-- Name: bd_39_cdate_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: 
--

CREATE INDEX bd_39_cdate_i ON bd_39 USING btree (cdate);


--
-- Name: bd_39_fti_kc_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: 
--

CREATE INDEX bd_39_fti_kc_i ON bd_39_fti USING btree (k, c);


--
-- Name: bd_39_fti_v_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: 
--

CREATE INDEX bd_39_fti_v_i ON bd_39_fti USING btree (v);


--
-- Name: bd_39_gid; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: 
--

CREATE INDEX bd_39_gid ON bd_39 USING btree (gid);


--
-- Name: bd_39_id_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: 
--

CREATE INDEX bd_39_id_i ON bd_39 USING btree (id, topic) WHERE (pid = 0);


--
-- Name: bd_39_pid; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: 
--

CREATE INDEX bd_39_pid ON bd_39 USING btree (pid);


--
-- Name: bd_39_usernum_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: 
--

CREATE INDEX bd_39_usernum_i ON bd_39 USING btree (usernum);


SET default_tablespace = tbs_bd_47;

--
-- Name: bd_47_cdate_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_47
--

CREATE INDEX bd_47_cdate_i ON bd_47 USING btree (cdate);


--
-- Name: bd_47_fti_kc_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_47
--

CREATE INDEX bd_47_fti_kc_i ON bd_47_fti USING btree (k, c);


--
-- Name: bd_47_fti_v_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_47
--

CREATE INDEX bd_47_fti_v_i ON bd_47_fti USING btree (v);


--
-- Name: bd_47_gid; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_47
--

CREATE INDEX bd_47_gid ON bd_47 USING btree (gid);


--
-- Name: bd_47_id_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_47
--

CREATE INDEX bd_47_id_i ON bd_47 USING btree (id, topic) WHERE (pid = 0);


--
-- Name: bd_47_pid; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_47
--

CREATE INDEX bd_47_pid ON bd_47 USING btree (pid);


--
-- Name: bd_47_usernum_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_47
--

CREATE INDEX bd_47_usernum_i ON bd_47 USING btree (usernum);


SET default_tablespace = tbs_bd_55;

--
-- Name: bd_55_cdate_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_55
--

CREATE INDEX bd_55_cdate_i ON bd_55 USING btree (cdate);


--
-- Name: bd_55_fti_kc_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_55
--

CREATE INDEX bd_55_fti_kc_i ON bd_55_fti USING btree (k, c);


--
-- Name: bd_55_fti_v_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_55
--

CREATE INDEX bd_55_fti_v_i ON bd_55_fti USING btree (v);


--
-- Name: bd_55_gid; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_55
--

CREATE INDEX bd_55_gid ON bd_55 USING btree (gid);


--
-- Name: bd_55_id_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_55
--

CREATE INDEX bd_55_id_i ON bd_55 USING btree (id, topic) WHERE (pid = 0);


--
-- Name: bd_55_pid; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_55
--

CREATE INDEX bd_55_pid ON bd_55 USING btree (pid);


--
-- Name: bd_55_usernum_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_55
--

CREATE INDEX bd_55_usernum_i ON bd_55 USING btree (usernum);


SET default_tablespace = tbs_bd_5;

--
-- Name: bd_5_cdate_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_5
--

CREATE INDEX bd_5_cdate_i ON bd_5 USING btree (cdate);


--
-- Name: bd_5_fti_kc_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_5
--

CREATE INDEX bd_5_fti_kc_i ON bd_5_fti USING btree (k, c);


--
-- Name: bd_5_fti_v_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_5
--

CREATE INDEX bd_5_fti_v_i ON bd_5_fti USING btree (v);


--
-- Name: bd_5_gid; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_5
--

CREATE INDEX bd_5_gid ON bd_5 USING btree (gid);


--
-- Name: bd_5_id_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_5
--

CREATE INDEX bd_5_id_i ON bd_5 USING btree (id, topic) WHERE (pid = 0);


--
-- Name: bd_5_pid; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_5
--

CREATE INDEX bd_5_pid ON bd_5 USING btree (pid);


--
-- Name: bd_5_usernum_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_5
--

CREATE INDEX bd_5_usernum_i ON bd_5 USING btree (usernum);


SET default_tablespace = tbs_bd_63;

--
-- Name: bd_63_cdate_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_63
--

CREATE INDEX bd_63_cdate_i ON bd_63 USING btree (cdate);


--
-- Name: bd_63_fti_kc_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_63
--

CREATE INDEX bd_63_fti_kc_i ON bd_63_fti USING btree (k, c);


--
-- Name: bd_63_fti_v_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_63
--

CREATE INDEX bd_63_fti_v_i ON bd_63_fti USING btree (v);


--
-- Name: bd_63_gid; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_63
--

CREATE INDEX bd_63_gid ON bd_63 USING btree (gid);


--
-- Name: bd_63_id_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_63
--

CREATE INDEX bd_63_id_i ON bd_63 USING btree (id, topic) WHERE (pid = 0);


--
-- Name: bd_63_pid; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_63
--

CREATE INDEX bd_63_pid ON bd_63 USING btree (pid);


--
-- Name: bd_63_usernum_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_63
--

CREATE INDEX bd_63_usernum_i ON bd_63 USING btree (usernum);


SET default_tablespace = tbs_bd_71;

--
-- Name: bd_71_cdate_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_71
--

CREATE INDEX bd_71_cdate_i ON bd_71 USING btree (cdate);


--
-- Name: bd_71_fti_kc_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_71
--

CREATE INDEX bd_71_fti_kc_i ON bd_71_fti USING btree (k, c);


--
-- Name: bd_71_fti_v_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_71
--

CREATE INDEX bd_71_fti_v_i ON bd_71_fti USING btree (v);


--
-- Name: bd_71_gid; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_71
--

CREATE INDEX bd_71_gid ON bd_71 USING btree (gid);


--
-- Name: bd_71_id_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_71
--

CREATE INDEX bd_71_id_i ON bd_71 USING btree (id, topic) WHERE (pid = 0);


--
-- Name: bd_71_pid; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_71
--

CREATE INDEX bd_71_pid ON bd_71 USING btree (pid);


--
-- Name: bd_71_usernum_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_71
--

CREATE INDEX bd_71_usernum_i ON bd_71 USING btree (usernum);


SET default_tablespace = tbs_bd_79;

--
-- Name: bd_79_cdate_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_79
--

CREATE INDEX bd_79_cdate_i ON bd_79 USING btree (cdate);


--
-- Name: bd_79_fti_kc_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_79
--

CREATE INDEX bd_79_fti_kc_i ON bd_79_fti USING btree (k, c);


--
-- Name: bd_79_fti_v_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_79
--

CREATE INDEX bd_79_fti_v_i ON bd_79_fti USING btree (v);


--
-- Name: bd_79_gid; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_79
--

CREATE INDEX bd_79_gid ON bd_79 USING btree (gid);


--
-- Name: bd_79_id_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_79
--

CREATE INDEX bd_79_id_i ON bd_79 USING btree (id, topic) WHERE (pid = 0);


--
-- Name: bd_79_pid; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_79
--

CREATE INDEX bd_79_pid ON bd_79 USING btree (pid);


--
-- Name: bd_79_usernum_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_79
--

CREATE INDEX bd_79_usernum_i ON bd_79 USING btree (usernum);


SET default_tablespace = tbs_bd_87;

--
-- Name: bd_87_cdate_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_87
--

CREATE INDEX bd_87_cdate_i ON bd_87 USING btree (cdate);


--
-- Name: bd_87_fti_kc_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_87
--

CREATE INDEX bd_87_fti_kc_i ON bd_87_fti USING btree (k, c);


--
-- Name: bd_87_fti_v_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_87
--

CREATE INDEX bd_87_fti_v_i ON bd_87_fti USING btree (v);


--
-- Name: bd_87_gid; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_87
--

CREATE INDEX bd_87_gid ON bd_87 USING btree (gid);


--
-- Name: bd_87_id_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_87
--

CREATE INDEX bd_87_id_i ON bd_87 USING btree (id, topic) WHERE (pid = 0);


--
-- Name: bd_87_pid; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_87
--

CREATE INDEX bd_87_pid ON bd_87 USING btree (pid);


--
-- Name: bd_87_usernum_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_87
--

CREATE INDEX bd_87_usernum_i ON bd_87 USING btree (usernum);


SET default_tablespace = tbs_bd_95;

--
-- Name: bd_95_cdate_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_95
--

CREATE INDEX bd_95_cdate_i ON bd_95 USING btree (cdate);


--
-- Name: bd_95_fti_kc_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_95
--

CREATE INDEX bd_95_fti_kc_i ON bd_95_fti USING btree (k, c);


--
-- Name: bd_95_fti_v_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_95
--

CREATE INDEX bd_95_fti_v_i ON bd_95_fti USING btree (v);


--
-- Name: bd_95_gid; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_95
--

CREATE INDEX bd_95_gid ON bd_95 USING btree (gid);


--
-- Name: bd_95_id_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_95
--

CREATE INDEX bd_95_id_i ON bd_95 USING btree (id, topic) WHERE (pid = 0);


--
-- Name: bd_95_pid; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_95
--

CREATE INDEX bd_95_pid ON bd_95 USING btree (pid);


--
-- Name: bd_95_usernum_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: tbs_bd_95
--

CREATE INDEX bd_95_usernum_i ON bd_95 USING btree (usernum);


SET default_tablespace = '';

--
-- Name: bd_gid_cdate_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: 
--

CREATE INDEX bd_gid_cdate_i ON bd_117 USING btree (gid);


--
-- Name: cat_crit; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: 
--

CREATE INDEX cat_crit ON category USING btree (criteria);


--
-- Name: cat_path; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: 
--

CREATE INDEX cat_path ON category USING btree (path);


--
-- Name: cat_pid; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: 
--

CREATE INDEX cat_pid ON category USING btree (pid);


--
-- Name: cat_pid_crit; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: 
--

CREATE INDEX cat_pid_crit ON category USING btree (pid, criteria);


--
-- Name: comments_cdate_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: 
--

CREATE INDEX comments_cdate_i ON comments USING btree (cdate);


--
-- Name: comments_pid_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: 
--

CREATE INDEX comments_pid_i ON comments USING btree (ptable, pid);


--
-- Name: imagefiles_pid_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: 
--

CREATE INDEX imagefiles_pid_i ON imagefiles USING btree (menuid, pid);


--
-- Name: imagefiles_sid_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: 
--

CREATE INDEX imagefiles_sid_i ON imagefiles USING btree (sessionid) WHERE (pid IS NULL);


--
-- Name: keywords_ctime_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: 
--

CREATE INDEX keywords_ctime_i ON keywords USING btree (ctime);


--
-- Name: link_cat; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: 
--

CREATE INDEX link_cat ON links USING btree (category);


--
-- Name: link_cat_crit_del; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: 
--

CREATE INDEX link_cat_crit_del ON links USING btree (category, criteria, deleted);


--
-- Name: link_crit; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: 
--

CREATE INDEX link_crit ON links USING btree (criteria);


--
-- Name: link_del; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: 
--

CREATE INDEX link_del ON links USING btree (deleted);


--
-- Name: menus_crit_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: 
--

CREATE UNIQUE INDEX menus_crit_i ON menus USING btree (criteria, subcrit);


--
-- Name: menus_tname_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: 
--

CREATE INDEX menus_tname_i ON menus USING btree (tname);


--
-- Name: menus_upper_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: 
--

CREATE INDEX menus_upper_i ON menus USING btree (upper, sortnum) WHERE (menuid <> 1);


--
-- Name: uploadfiles_pid_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: 
--

CREATE INDEX uploadfiles_pid_i ON uploadfiles USING btree (menuid, pid);


--
-- Name: uploadfiles_sid_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: 
--

CREATE INDEX uploadfiles_sid_i ON uploadfiles USING btree (sessionid) WHERE (pid IS NULL);


--
-- Name: users_email_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: 
--

CREATE UNIQUE INDEX users_email_i ON users USING btree (email);


--
-- Name: users_openid_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: 
--

CREATE UNIQUE INDEX users_openid_i ON users USING btree (openid) WHERE (openid IS NOT NULL);


--
-- Name: users_uid_i; Type: INDEX; Schema: public; Owner: webadmin; Tablespace: 
--

CREATE UNIQUE INDEX users_uid_i ON users USING btree (lower(uid));


--
-- Name: trbd_103; Type: TRIGGER; Schema: public; Owner: webadmin
--

CREATE TRIGGER trbd_103 AFTER INSERT OR DELETE OR UPDATE ON bd_103 FOR EACH ROW EXECUTE PROCEDURE t_fti('bd_103_fti');


--
-- Name: trbd_111; Type: TRIGGER; Schema: public; Owner: webadmin
--

CREATE TRIGGER trbd_111 AFTER INSERT OR DELETE OR UPDATE ON bd_111 FOR EACH ROW EXECUTE PROCEDURE t_fti('bd_111_fti');


--
-- Name: trbd_112; Type: TRIGGER; Schema: public; Owner: webadmin
--

CREATE TRIGGER trbd_112 AFTER INSERT OR DELETE OR UPDATE ON bd_112 FOR EACH ROW EXECUTE PROCEDURE t_fti('bd_112_fti');


--
-- Name: trbd_117; Type: TRIGGER; Schema: public; Owner: webadmin
--

CREATE TRIGGER trbd_117 AFTER INSERT OR DELETE OR UPDATE ON bd_117 FOR EACH ROW EXECUTE PROCEDURE t_fti('bd_117_fti');


--
-- Name: trbd_125; Type: TRIGGER; Schema: public; Owner: webadmin
--

CREATE TRIGGER trbd_125 AFTER INSERT OR DELETE OR UPDATE ON bd_125 FOR EACH ROW EXECUTE PROCEDURE t_fti('bd_125_fti');


--
-- Name: trbd_13; Type: TRIGGER; Schema: public; Owner: webadmin
--

CREATE TRIGGER trbd_13 AFTER INSERT OR DELETE OR UPDATE ON bd_13 FOR EACH ROW EXECUTE PROCEDURE t_fti('bd_13_fti');


--
-- Name: trbd_137; Type: TRIGGER; Schema: public; Owner: webadmin
--

CREATE TRIGGER trbd_137 AFTER INSERT OR DELETE OR UPDATE ON bd_137 FOR EACH ROW EXECUTE PROCEDURE t_fti('bd_137_fti');


--
-- Name: trbd_21; Type: TRIGGER; Schema: public; Owner: webadmin
--

CREATE TRIGGER trbd_21 AFTER INSERT OR DELETE OR UPDATE ON bd_21 FOR EACH ROW EXECUTE PROCEDURE t_fti('bd_21_fti');


--
-- Name: trbd_22; Type: TRIGGER; Schema: public; Owner: webadmin
--

CREATE TRIGGER trbd_22 AFTER INSERT OR DELETE OR UPDATE ON bd_22 FOR EACH ROW EXECUTE PROCEDURE t_fti('bd_22_fti');


--
-- Name: trbd_23; Type: TRIGGER; Schema: public; Owner: webadmin
--

CREATE TRIGGER trbd_23 AFTER INSERT OR DELETE OR UPDATE ON bd_23 FOR EACH ROW EXECUTE PROCEDURE t_fti('bd_23_fti');


--
-- Name: trbd_31; Type: TRIGGER; Schema: public; Owner: webadmin
--

CREATE TRIGGER trbd_31 AFTER INSERT OR DELETE OR UPDATE ON bd_31 FOR EACH ROW EXECUTE PROCEDURE t_fti('bd_31_fti');


--
-- Name: trbd_39; Type: TRIGGER; Schema: public; Owner: webadmin
--

CREATE TRIGGER trbd_39 AFTER INSERT OR DELETE OR UPDATE ON bd_39 FOR EACH ROW EXECUTE PROCEDURE t_fti('bd_39_fti');


--
-- Name: trbd_47; Type: TRIGGER; Schema: public; Owner: webadmin
--

CREATE TRIGGER trbd_47 AFTER INSERT OR DELETE OR UPDATE ON bd_47 FOR EACH ROW EXECUTE PROCEDURE t_fti('bd_47_fti');


--
-- Name: trbd_5; Type: TRIGGER; Schema: public; Owner: webadmin
--

CREATE TRIGGER trbd_5 AFTER INSERT OR DELETE OR UPDATE ON bd_5 FOR EACH ROW EXECUTE PROCEDURE t_fti('bd_5_fti');


--
-- Name: trbd_55; Type: TRIGGER; Schema: public; Owner: webadmin
--

CREATE TRIGGER trbd_55 AFTER INSERT OR DELETE OR UPDATE ON bd_55 FOR EACH ROW EXECUTE PROCEDURE t_fti('bd_55_fti');


--
-- Name: trbd_63; Type: TRIGGER; Schema: public; Owner: webadmin
--

CREATE TRIGGER trbd_63 AFTER INSERT OR DELETE OR UPDATE ON bd_63 FOR EACH ROW EXECUTE PROCEDURE t_fti('bd_63_fti');


--
-- Name: trbd_71; Type: TRIGGER; Schema: public; Owner: webadmin
--

CREATE TRIGGER trbd_71 AFTER INSERT OR DELETE OR UPDATE ON bd_71 FOR EACH ROW EXECUTE PROCEDURE t_fti('bd_71_fti');


--
-- Name: trbd_79; Type: TRIGGER; Schema: public; Owner: webadmin
--

CREATE TRIGGER trbd_79 AFTER INSERT OR DELETE OR UPDATE ON bd_79 FOR EACH ROW EXECUTE PROCEDURE t_fti('bd_79_fti');


--
-- Name: trbd_87; Type: TRIGGER; Schema: public; Owner: webadmin
--

CREATE TRIGGER trbd_87 AFTER INSERT OR DELETE OR UPDATE ON bd_87 FOR EACH ROW EXECUTE PROCEDURE t_fti('bd_87_fti');


--
-- Name: trbd_95; Type: TRIGGER; Schema: public; Owner: webadmin
--

CREATE TRIGGER trbd_95 AFTER INSERT OR DELETE OR UPDATE ON bd_95 FOR EACH ROW EXECUTE PROCEDURE t_fti('bd_95_fti');


--
-- Name: trcomments; Type: TRIGGER; Schema: public; Owner: webadmin
--

CREATE TRIGGER trcomments AFTER INSERT OR DELETE OR UPDATE ON comments FOR EACH ROW EXECUTE PROCEDURE c_fti();


--
-- Name: mens_upper_fkey; Type: FK CONSTRAINT; Schema: public; Owner: webadmin
--

ALTER TABLE ONLY menus
    ADD CONSTRAINT mens_upper_fkey FOREIGN KEY (upper) REFERENCES menus(menuid) ON UPDATE CASCADE;


--
-- Name: public; Type: ACL; Schema: -; Owner: postgres
--

REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON SCHEMA public FROM postgres;
GRANT ALL ON SCHEMA public TO PUBLIC;


--
-- Name: vrelsize; Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON TABLE vrelsize FROM PUBLIC;
REVOKE ALL ON TABLE vrelsize FROM postgres;
GRANT ALL ON TABLE vrelsize TO postgres;
GRANT SELECT ON TABLE vrelsize TO PUBLIC;


--
-- PostgreSQL database dump complete
--

