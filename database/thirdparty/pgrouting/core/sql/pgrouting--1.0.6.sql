--
-- Copyright (c) 2005 Sylvain Pasche,
--               2006-2007 Anton A. Patrushev, Orkney, Inc.
--
-- This program is free software; you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation; either version 2 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program; if not, write to the Free Software
-- Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
--


CREATE TYPE path_result AS (vertex_id integer, edge_id integer, cost float8);
CREATE TYPE vertex_result AS (x float8, y float8);

-----------------------------------------------------------------------
-- Core function for shortest_path computation
-- See README for description
-----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION shortest_path(sql text, source_id integer, 
        target_id integer, directed boolean, has_reverse_cost boolean)
        RETURNS SETOF path_result
        AS '$libdir/librouting'
        LANGUAGE C IMMUTABLE STRICT;

-----------------------------------------------------------------------
-- Core function for shortest_path_astar computation
-- Simillar to shortest_path in usage but uses the A* algorithm
-- instead of Dijkstra's.
-----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION shortest_path_astar(sql text, source_id integer, 
        target_id integer,directed boolean, has_reverse_cost boolean)
         RETURNS SETOF path_result
         AS '$libdir/librouting'
         LANGUAGE C IMMUTABLE STRICT; 

-----------------------------------------------------------------------
-- Core function for shortest_path_astar computation
-- Simillar to shortest_path in usage but uses the Shooting* algorithm
-----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION shortest_path_shooting_star(sql text, source_id integer, 
        target_id integer,directed boolean, has_reverse_cost boolean)
         RETURNS SETOF path_result
         AS '$libdir/librouting'
         LANGUAGE C IMMUTABLE STRICT; 

-----------------------------------------------------------------------
-- This function should not be used directly. Use create_graph_tables instead
--
-- Insert a vertex into the vertices table if not already there, and
--  return the id of the newly inserted or already existing element
-----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION insert_vertex(vertices_table varchar, 
       geom_id anyelement) 
       RETURNS int AS
$$
DECLARE
        vertex_id int;
        myrec record;
BEGIN
        LOOP
          FOR myrec IN EXECUTE 'SELECT id FROM ' || 
                     quote_ident(vertices_table) || 
                     ' WHERE geom_id = ' || quote_literal(geom_id)  LOOP

                        IF myrec.id IS NOT NULL THEN
                                RETURN myrec.id;
                        END IF;
          END LOOP; 
          EXECUTE 'INSERT INTO ' || quote_ident(vertices_table) || 
                  ' (geom_id) VALUES (' || quote_literal(geom_id) || ')';
        END LOOP;
END;
$$
LANGUAGE 'plpgsql' VOLATILE STRICT; 
--
-- Copyright (c) 2005 Sylvain Pasche,
--               2006-2007 Anton A. Patrushev, Orkney, Inc.
--
-- This program is free software; you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation; either version 2 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program; if not, write to the Free Software
-- Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.


-- BEGIN;

CREATE OR REPLACE FUNCTION text(boolean)
       RETURNS text AS
$$
SELECT CASE WHEN $1 THEN 'true' ELSE 'false' END
$$
LANGUAGE 'sql';

-----------------------------------------------------------------------
-- For each vertex in the vertices table, set a point geometry which is
--  the corresponding line start or line end point
--
-- Last changes: 14.02.2008
-----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION add_vertices_geometrST_Y(geom_table varchar) 
       RETURNS VOID AS
$$
DECLARE
	vertices_table varchar := quote_ident(geom_table) || '_vertices';
BEGIN
	
	BEGIN
		EXECUTE 'SELECT addGeometryColumn(''' || 
                        quote_ident(vertices_table)  || 
                        ''', ''the_geom'', -1, ''POINT'', 2)';
	EXCEPTION 
		WHEN DUPLICATE_COLUMN THEN
	END;

	EXECUTE 'UPDATE ' || quote_ident(vertices_table) || 
                ' SET the_geom = NULL';

	EXECUTE 'UPDATE ' || quote_ident(vertices_table) || 
                ' SET the_geom = startPoint(geometryn(m.the_geom, 1)) FROM ' ||
                 quote_ident(geom_table) || 
                ' m where geom_id = m.source';

	EXECUTE 'UPDATE ' || quote_ident(vertices_table) || 
                ' set the_geom = endPoint(geometryn(m.the_geom, 1)) FROM ' || 
                quote_ident(geom_table) || 
                ' m where geom_id = m.target_id AND ' || 
                quote_ident(vertices_table) || 
                '.the_geom IS NULL';

	RETURN;
END;
$$
LANGUAGE 'plpgsql' VOLATILE STRICT; 

-----------------------------------------------------------------------
-- Update the cost column from the edges table, from the length of
--  all lines which belong to an edge.
--
-- Last changes: 14.02.2008
-----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION update_cost_from_distance(geom_table varchar) 
       RETURNS VOID AS
$$
DECLARE 
BEGIN
	BEGIN
	  EXECUTE 'CREATE INDEX ' || quote_ident(geom_table) || 
                  '_edge_id_idx ON ' || quote_ident(geom_table) || 
                  ' (edge_id)';
	EXCEPTION 
		WHEN DUPLICATE_TABLE THEN
		RAISE NOTICE 'Not creating index, already there';
	END;

	EXECUTE 'UPDATE ' || quote_ident(geom_table) || 
              '_edges SET cost = (SELECT sum( length( g.the_geom ) ) FROM ' || 
              quote_ident(geom_table) || 
              ' g WHERE g.edge_id = id GROUP BY id)';

	RETURN;
END;
$$
LANGUAGE 'plpgsql' VOLATILE STRICT; 


CREATE TYPE geoms AS
(
  id integer,
  gid integer,
  the_geom geometry
);

-----------------------------------------------------------------------
-- Dijkstra function for undirected graphs.
-- Compute the shortest path using edges table, and return
--  the result as a set of (gid integer, the_geom geometry) records.
--
-- Last changes: 14.02.2008
-----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION dijkstra_sp(
       geom_table varchar, source int4, target int4) 
       RETURNS SETOF GEOMS AS
$$
DECLARE 
	r record;
	path_result record;
	v_id integer;
	e_id integer;
	geom geoms;
	id integer;
BEGIN
	
	id :=0;
	
	FOR path_result IN EXECUTE 'SELECT gid,the_geom FROM ' ||
          'shortest_path(''SELECT gid as id, source::integer, target::integer, ' || 
          'length::double precision as cost FROM ' ||
	  quote_ident(geom_table) || ''', ' || quote_literal(source) || 
          ' , ' || quote_literal(target) || ' , false, false), ' || 
          quote_ident(geom_table) || ' where edge_id = gid ' 
        LOOP

                 geom.gid      := path_result.gid;
                 geom.the_geom := path_result.the_geom;
		 id := id+1;
		 geom.id       := id;
                 
                 RETURN NEXT geom;

	END LOOP;
	RETURN;
END;
$$
LANGUAGE 'plpgsql' VOLATILE STRICT; 

-----------------------------------------------------------------------
-- Dijkstra wrapper function for directed graphs.
-- Compute the shortest path using edges table, and return
--  the result as a set of (gid integer, the_geom geometry) records.
--
-- Last changes: 14.02.2008
-----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION dijkstra_sp_directed(
       geom_table varchar, source int4, target int4, dir boolean, rc boolean) 
       RETURNS SETOF GEOMS AS
$$
DECLARE 
	r record;
	path_result record;
	v_id integer;
	e_id integer;
	geom geoms;
	query text;
	id integer;
BEGIN
	
	id :=0;
	
	query := 'SELECT gid,the_geom FROM ' ||
          'shortest_path(''SELECT gid as id, source::integer, target::integer, ' || 
          'length::double precision as cost ';
	  
	IF rc THEN query := query || ', reverse_cost ';  
	END IF;
	
	query := query || 'FROM ' ||  quote_ident(geom_table) || ''', ' || quote_literal(source) || 
          ' , ' || quote_literal(target) || ' , '''||text(dir)||''', '''||text(rc)||'''), ' || 
          quote_ident(geom_table) || ' where edge_id = gid ';

	FOR path_result IN EXECUTE query
        LOOP

                 geom.gid      := path_result.gid;
                 geom.the_geom := path_result.the_geom;
		 id := id+1;
		 geom.id       := id;
                 
                 RETURN NEXT geom;

	END LOOP;
	RETURN;
END;
$$
LANGUAGE 'plpgsql' VOLATILE STRICT; 

-----------------------------------------------------------------------
-- A* function for undirected graphs.
-- Compute the shortest path using edges table, and return
--  the result as a set of (gid integer, the_geom geometry) records.
-- Also data clipping added to improve function performance.
--
-- Last changes: 14.02.2008
-----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION astar_sp_delta(
       varchar,int4, int4, float8) 
       RETURNS SETOF GEOMS AS
$$
DECLARE 
        geom_table ALIAS FOR $1;
	sourceid ALIAS FOR $2;
	targetid ALIAS FOR $3;
	delta ALIAS FOR $4;

	rec record;
	r record;
        path_result record;
        v_id integer;
        e_id integer;
        geom geoms;
	
	id integer;
BEGIN
	
	id :=0;

	FOR path_result IN EXECUTE 'SELECT gid,the_geom FROM ' || 
           'astar_sp_delta_directed(''' || 
           quote_ident(geom_table) || ''', ' || quote_literal(sourceid) || ', ' || 
	   quote_literal(targetid) || ', ' || delta || ', false, false)'
        LOOP

                 geom.gid      := path_result.gid;
                 geom.the_geom := path_result.the_geom;
		 id := id+1;
		 geom.id       := id;
                 
                 RETURN NEXT geom;

        END LOOP;
        RETURN;
END;
$$
LANGUAGE 'plpgsql' VOLATILE STRICT; 

-----------------------------------------------------------------------
-- A* function for directed graphs.
-- Compute the shortest path using edges table, and return
--  the result as a set of (gid integer, the_geom geometry) records.
-- Also data clipping added to improve function performance.
--
-- Last changes: 14.02.2008
-----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION astar_sp_delta_directed(
       varchar,int4, int4, float8, boolean, boolean) 
       RETURNS SETOF GEOMS AS
$$
DECLARE 
        geom_table ALIAS FOR $1;
	sourceid ALIAS FOR $2;
	targetid ALIAS FOR $3;
	delta ALIAS FOR $4;
	dir ALIAS FOR $5;
	rc ALIAS FOR $6;

	rec record;
	r record;
        path_result record;
        v_id integer;
        e_id integer;
        geom geoms;
	
	srid integer;

	source_x float8;
	source_y float8;
	target_x float8;
	target_y float8;
	
	ll_x float8;
	ll_y float8;
	ur_x float8;
	ur_y float8;
	
	query text;

	id integer;
BEGIN
	
	id :=0;
	FOR rec IN EXECUTE
	    'select ST_SRID(the_geom) from ' ||
	    quote_ident(geom_table) || ' limit 1'
	LOOP
	END LOOP;
	srid := rec.srid;
	
	FOR rec IN EXECUTE 
            'select ST_X(ST_StartPoint(the_geom)) as source_x from ' || 
            quote_ident(geom_table) || ' where source = ' || 
            sourceid ||  ' or target='||sourceid||' limit 1'
        LOOP
	END LOOP;
	source_x := rec.source_x;
	
	FOR rec IN EXECUTE 
            'select ST_Y(ST_StartPoint(the_geom)) as source_y from ' || 
            quote_ident(geom_table) || ' where source = ' || 
            sourceid ||  ' or target='||sourceid||' limit 1'
        LOOP
	END LOOP;

	source_y := rec.source_y;

	FOR rec IN EXECUTE 
            'select ST_X(ST_StartPoint(the_geom)) as target_x from ' ||
            quote_ident(geom_table) || ' where source = ' || 
            targetid ||  ' or target='||targetid||' limit 1'
        LOOP
	END LOOP;

	target_x := rec.target_x;
	
	FOR rec IN EXECUTE 
            'select ST_Y(ST_StartPoint(the_geom)) as target_y from ' || 
            quote_ident(geom_table) || ' where source = ' || 
            targetid ||  ' or target='||targetid||' limit 1'
        LOOP
	END LOOP;
	target_y := rec.target_y;

	FOR rec IN EXECUTE 'SELECT CASE WHEN '||source_x||'<'||target_x||
           ' THEN '||source_x||' ELSE '||target_x||
           ' END as ll_x, CASE WHEN '||source_x||'>'||target_x||
           ' THEN '||source_x||' ELSE '||target_x||' END as ur_x'
        LOOP
	END LOOP;

	ll_x := rec.ll_x;
	ur_x := rec.ur_x;

	FOR rec IN EXECUTE 'SELECT CASE WHEN '||source_y||'<'||
            target_y||' THEN '||source_y||' ELSE '||
            target_y||' END as ll_y, CASE WHEN '||
            source_y||'>'||target_y||' THEN '||
            source_y||' ELSE '||target_y||' END as ur_y'
        LOOP
	END LOOP;

	ll_y := rec.ll_y;
	ur_y := rec.ur_y;

	query := 'SELECT gid,the_geom FROM ' || 
          'shortest_path_astar(''SELECT gid as id, source::integer, ' || 
          'target::integer, length::double precision as cost, ' || 
          'x1::double precision, y1::double precision, x2::double ' ||
          'precision, y2::double precision ';
	  
	IF rc THEN query := query || ' , reverse_cost ';  
	END IF;
	  
	query := query || 'FROM ' || quote_ident(geom_table) || ' where setSRID(''''BOX3D('||
          ll_x-delta||' '||ll_y-delta||','||ur_x+delta||' '||
          ur_y+delta||')''''::BOX3D, ' || srid || ') && the_geom'', ' || 
          quote_literal(sourceid) || ' , ' || 
          quote_literal(targetid) || ' , '''||text(dir)||''', '''||text(rc)||''' ),' || 
          quote_ident(geom_table) || ' where edge_id = gid ';
	  
	FOR path_result IN EXECUTE query
        LOOP
                 geom.gid      := path_result.gid;
                 geom.the_geom := path_result.the_geom;
		 id := id+1;
		 geom.id       := id;
                 
                 RETURN NEXT geom;
--
--                v_id = path_result.vertex_id;
--                e_id = path_result.edge_id;

--                FOR r IN EXECUTE 'SELECT gid, the_geom FROM ' || 
--                      quote_ident(geom_table) || '  WHERE gid = ' || 
--                      quote_literal(e_id) LOOP
--                        geom.gid := r.gid;
--                        geom.the_geom := r.the_geom;
--                        RETURN NEXT geom;
--                END LOOP;

        END LOOP;
        RETURN;
END;
$$
LANGUAGE 'plpgsql' VOLATILE STRICT; 


-----------------------------------------------------------------------
-- A* function for undirected graphs.
-- Compute the shortest path using edges table, and return
--  the result as a set of (gid integer, the_geom geometry) records.
-- Also data clipping added to improve function performance.
-- Cost column name can be specified (last parameter)
--
-- Last changes: 14.02.2008
-----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION astar_sp_delta_cc(
       varchar,int4, int4, float8, varchar) 
       RETURNS SETOF GEOMS AS
$$
DECLARE 
        geom_table ALIAS FOR $1;
	sourceid ALIAS FOR $2;
	targetid ALIAS FOR $3;
	delta ALIAS FOR $4;
	cost_column ALIAS FOR $5;

	rec record;
	r record;
        path_result record;
        v_id integer;
        e_id integer;
        geom geoms;
	
	id integer;
BEGIN
	
	id :=0;
	FOR path_result IN EXECUTE 'SELECT gid,the_geom FROM ' || 
           'astar_sp_delta_cc_directed(''' || 
           quote_ident(geom_table) || ''', ' || quote_literal(sourceid) || ', ' || 
	   quote_literal(targetid) || ', ' || delta || ',' || 
	   quote_literal(cost_column) || ', false, false)'
        LOOP

                 geom.gid      := path_result.gid;
                 geom.the_geom := path_result.the_geom;
		 id := id+1;
		 geom.id       := id;
                 
                 RETURN NEXT geom;

        END LOOP;
        RETURN;
END;
$$
LANGUAGE 'plpgsql' VOLATILE STRICT; 

-----------------------------------------------------------------------
-- A* function for directed graphs.
-- Compute the shortest path using edges table, and return
--  the result as a set of (gid integer, the_geom geometry) records.
-- Also data clipping added to improve function performance.
-- Cost column name can be specified (last parameter)
--
-- Last changes: 14.02.2008
-----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION astar_sp_delta_cc_directed(
       varchar,int4, int4, float8, varchar, boolean, boolean) 
       RETURNS SETOF GEOMS AS
$$
DECLARE 
        geom_table ALIAS FOR $1;
	sourceid ALIAS FOR $2;
	targetid ALIAS FOR $3;
	delta ALIAS FOR $4;
	cost_column ALIAS FOR $5;
	dir ALIAS FOR $6;
	rc ALIAS FOR $7;

	rec record;
	r record;
        path_result record;
        v_id integer;
        e_id integer;
        geom geoms;
	
	srid integer;

	source_x float8;
	source_y float8;
	target_x float8;
	target_y float8;
	
	ll_x float8;
	ll_y float8;
	ur_x float8;
	ur_y float8;
	
	query text;

	id integer;
BEGIN
	
	id :=0;
	FOR rec IN EXECUTE
	    'select ST_SRID(the_geom) from ' ||
	    quote_ident(geom_table) || ' limit 1'
	LOOP
	END LOOP;
	srid := rec.srid;
	
	FOR rec IN EXECUTE 
            'select ST_X(ST_StartPoint(the_geom)) as source_x from ' || 
            quote_ident(geom_table) || ' where source = ' || 
            sourceid || ' or target='||sourceid||' limit 1'
        LOOP
	END LOOP;
	source_x := rec.source_x;
	
	FOR rec IN EXECUTE 
            'select ST_Y(ST_StartPoint(the_geom)) as source_y from ' || 
            quote_ident(geom_table) || ' where source = ' || 
            sourceid ||  ' or target='||sourceid||' limit 1'
        LOOP
	END LOOP;

	source_y := rec.source_y;

	FOR rec IN EXECUTE 
            'select ST_X(ST_StartPoint(the_geom)) as target_x from ' ||
            quote_ident(geom_table) || ' where source = ' || 
            targetid ||  ' or target='||targetid||' limit 1'
        LOOP
	END LOOP;

	target_x := rec.target_x;
	
	FOR rec IN EXECUTE 
            'select ST_Y(ST_StartPoint(the_geom)) as target_y from ' || 
            quote_ident(geom_table) || ' where source = ' || 
            targetid ||  ' or target='||targetid||' limit 1'
        LOOP
	END LOOP;
	target_y := rec.target_y;


	FOR rec IN EXECUTE 'SELECT CASE WHEN '||source_x||'<'||target_x||
           ' THEN '||source_x||' ELSE '||target_x||
           ' END as ll_x, CASE WHEN '||source_x||'>'||target_x||
           ' THEN '||source_x||' ELSE '||target_x||' END as ur_x'
        LOOP
	END LOOP;

	ll_x := rec.ll_x;
	ur_x := rec.ur_x;

	FOR rec IN EXECUTE 'SELECT CASE WHEN '||source_y||'<'||
            target_y||' THEN '||source_y||' ELSE '||
            target_y||' END as ll_y, CASE WHEN '||
            source_y||'>'||target_y||' THEN '||
            source_y||' ELSE '||target_y||' END as ur_y'
        LOOP
	END LOOP;

	ll_y := rec.ll_y;
	ur_y := rec.ur_y;

	query := 'SELECT gid,the_geom FROM ' || 
          'shortest_path_astar(''SELECT gid as id, source::integer, ' || 
          'target::integer, '||cost_column||'::double precision as cost, ' || 
          'x1::double precision, y1::double precision, x2::double ' ||
          'precision, y2::double precision ';
	
	IF rc THEN query := query || ' , reverse_cost ';
	END IF;
	  
	query := query || 'FROM ' || quote_ident(geom_table) || ' where setSRID(''''BOX3D('||
          ll_x-delta||' '||ll_y-delta||','||ur_x+delta||' '||
          ur_y+delta||')''''::BOX3D, ' || srid || ') && the_geom'', ' || 
          quote_literal(sourceid) || ' , ' || 
          quote_literal(targetid) || ' , '''||text(dir)||''', '''||text(rc)||''' ),' || 
          quote_ident(geom_table) || ' where edge_id = gid ';
	
	FOR path_result IN EXECUTE query
        LOOP

                 geom.gid      := path_result.gid;
                 geom.the_geom := path_result.the_geom;
		 id := id+1;
		 geom.id       := id;
                 
                 RETURN NEXT geom;

        END LOOP;
        RETURN;
END;
$$
LANGUAGE 'plpgsql' VOLATILE STRICT; 


-----------------------------------------------------------------------
-- Dijkstra function for undirected graphs.
-- Compute the shortest path using edges table, and return
--  the result as a set of (gid integer, the_geom geometry) records.
-- Also data clipping added to improve function performance.
--
-- Last changes: 14.02.2008
-----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION dijkstra_sp_delta(
       varchar,int4, int4, float8) 
       RETURNS SETOF GEOMS AS
$$
DECLARE 
        geom_table ALIAS FOR $1;
	sourceid ALIAS FOR $2;
	targetid ALIAS FOR $3;
	delta ALIAS FOR $4;

	rec record;
	r record;
        path_result record;
        v_id integer;
        e_id integer;
        geom geoms;
	
	id integer;
BEGIN
	
	id :=0;
	FOR path_result IN EXECUTE 'SELECT gid,the_geom FROM ' || 
           'dijkstra_sp_delta_directed(''' || 
           quote_ident(geom_table) || ''', ' || quote_literal(sourceid) || ', ' || 
	   quote_literal(targetid) || ', ' || delta || ', false, false)'
        LOOP
                 geom.gid      := path_result.gid;
                 geom.the_geom := path_result.the_geom;
		 id := id+1;
		 geom.id       := id;
                 
                 RETURN NEXT geom;

        END LOOP;
        RETURN;
END;
$$
LANGUAGE 'plpgsql' VOLATILE STRICT; 

-----------------------------------------------------------------------
-- Dijkstra function for directed graphs.
-- Compute the shortest path using edges table, and return
--  the result as a set of (gid integer, the_geom geometry) records.
-- Also data clipping added to improve function performance.
--
-- Last changes: 14.02.2008
-----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION dijkstra_sp_delta_directed(
       varchar,int4, int4, float8, boolean, boolean) 
       RETURNS SETOF GEOMS AS
$$
DECLARE 
        geom_table ALIAS FOR $1;
	sourceid ALIAS FOR $2;
	targetid ALIAS FOR $3;
	delta ALIAS FOR $4;
	dir ALIAS FOR $5;
	rc ALIAS FOR $6;

	rec record;
	r record;
        path_result record;
        v_id integer;
        e_id integer;
        geom geoms;
	
	srid integer;

	source_x float8;
	source_y float8;
	target_x float8;
	target_y float8;
	
	ll_x float8;
	ll_y float8;
	ur_x float8;
	ur_y float8;
	
	query text;
	id integer;
BEGIN
	
	id :=0;
	FOR rec IN EXECUTE
	    'select ST_SRID(the_geom) from ' ||
	    quote_ident(geom_table) || ' limit 1'
	LOOP
	END LOOP;
	srid := rec.srid;

	FOR rec IN EXECUTE 
            'select ST_X(ST_StartPoint(the_geom)) as source_x from ' || 
            quote_ident(geom_table) || ' where source = ' || 
            sourceid ||  ' or target='||sourceid||' limit 1'
        LOOP
	END LOOP;
	source_x := rec.source_x;
	
	FOR rec IN EXECUTE 
            'select ST_Y(ST_StartPoint(the_geom)) as source_y from ' || 
            quote_ident(geom_table) || ' where source = ' || 
            sourceid ||  ' or target='||sourceid||' limit 1'
        LOOP
	END LOOP;

	source_y := rec.source_y;

	FOR rec IN EXECUTE 
            'select ST_X(ST_StartPoint(the_geom)) as target_x from ' ||
            quote_ident(geom_table) || ' where source = ' || 
            targetid ||  ' or target='||targetid||' limit 1'
        LOOP
	END LOOP;

	target_x := rec.target_x;
	
	FOR rec IN EXECUTE 
            'select ST_Y(ST_StartPoint(the_geom)) as target_y from ' || 
            quote_ident(geom_table) || ' where source = ' || 
            targetid ||  ' or target='||targetid||' limit 1'
        LOOP
	END LOOP;
	target_y := rec.target_y;


	FOR rec IN EXECUTE 'SELECT CASE WHEN '||source_x||'<'||target_x||
           ' THEN '||source_x||' ELSE '||target_x||
           ' END as ll_x, CASE WHEN '||source_x||'>'||target_x||
           ' THEN '||source_x||' ELSE '||target_x||' END as ur_x'
        LOOP
	END LOOP;

	ll_x := rec.ll_x;
	ur_x := rec.ur_x;

	FOR rec IN EXECUTE 'SELECT CASE WHEN '||source_y||'<'||
            target_y||' THEN '||source_y||' ELSE '||
            target_y||' END as ll_y, CASE WHEN '||
            source_y||'>'||target_y||' THEN '||
            source_y||' ELSE '||target_y||' END as ur_y'
        LOOP
	END LOOP;

	ll_y := rec.ll_y;
	ur_y := rec.ur_y;

	query := 'SELECT gid,the_geom FROM ' || 
          'shortest_path(''SELECT gid as id, source::integer, target::integer, ' || 
          'length::double precision as cost ';
	  
	IF rc THEN query := query || ' , reverse_cost ';
	END IF;

	query := query || ' FROM ' || quote_ident(geom_table) || ' where setSRID(''''BOX3D('||
          ll_x-delta||' '||ll_y-delta||','||ur_x+delta||' '||
          ur_y+delta||')''''::BOX3D, ' || srid || ') && the_geom'', ' || 
          quote_literal(sourceid) || ' , ' || 
          quote_literal(targetid) || ' , '''||text(dir)||''', '''||text(rc)||''' ), ' ||
          quote_ident(geom_table) || ' where edge_id = gid ';
	  
	FOR path_result IN EXECUTE query
        LOOP
                 geom.gid      := path_result.gid;
                 geom.the_geom := path_result.the_geom;
		 id := id+1;
		 geom.id       := id;
                 
                 RETURN NEXT geom;

        END LOOP;
        RETURN;
END;
$$
LANGUAGE 'plpgsql' VOLATILE STRICT; 


-----------------------------------------------------------------------
-- A* function for undirected graphs.
-- Compute the shortest path using edges table, and return
--  the result as a set of (gid integer, the_geom geometry) records.
-- Also data clipping added to improve function performance
--  (specified by lower left and upper right box corners).
--
-- Last changes: 14.02.2008
-----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION astar_sp_bboST_X(
       varchar,int4, int4, float8, float8, float8, float8) 
       RETURNS SETOF GEOMS AS
$$
DECLARE 
        geom_table ALIAS FOR $1;
	sourceid ALIAS FOR $2;
	targetid ALIAS FOR $3;
	ll_x ALIAS FOR $4;
	ll_y ALIAS FOR $5;
	ur_x ALIAS FOR $6;
	ur_y ALIAS FOR $7;

	rec record;
	r record;
        path_result record;
        v_id integer;
        e_id integer;
        geom geoms;
	
	srid integer;

	id integer;
BEGIN
	
	id :=0;
	FOR path_result IN EXECUTE 'SELECT gid,the_geom FROM ' || 
           'astar_sp_bbox_directed(''' || 
           quote_ident(geom_table) || ''', ' || quote_literal(sourceid) || ', ' || 
	   quote_literal(targetid) || ', ' || ll_x || ', ' || ll_y || ', ' ||
	   ur_x || ', ' || ur_y || ', false, false)'
        LOOP

               geom.gid      := path_result.gid;
               geom.the_geom := path_result.the_geom;
               id := id+1;
	       geom.id       := id;
                 
               RETURN NEXT geom;

        END LOOP;
        RETURN;
END;
$$
LANGUAGE 'plpgsql' VOLATILE STRICT; 

-----------------------------------------------------------------------
-- A* function for directed graphs.
-- Compute the shortest path using edges table, and return
--  the result as a set of (gid integer, the_geom geometry) records.
-- Also data clipping added to improve function performance
--  (specified by lower left and upper right box corners).
--
-- Last changes: 14.02.2008
-----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION astar_sp_bbox_directed(
       varchar,int4, int4, float8, float8, float8, float8, boolean, boolean) 
       RETURNS SETOF GEOMS AS
$$
DECLARE 
        geom_table ALIAS FOR $1;
	sourceid ALIAS FOR $2;
	targetid ALIAS FOR $3;
	ll_x ALIAS FOR $4;
	ll_y ALIAS FOR $5;
	ur_x ALIAS FOR $6;
	ur_y ALIAS FOR $7;
	dir ALIAS FOR $8;
	rc ALIAS FOR $9;

	rec record;
	r record;
        path_result record;
        v_id integer;
        e_id integer;
        geom geoms;
	
	srid integer;
	
	query text;

	id integer;
BEGIN
	
	id :=0;
	FOR rec IN EXECUTE
	    'select ST_SRID(the_geom) from ' ||
	    quote_ident(geom_table) || ' limit 1'
	LOOP
	END LOOP;
	srid := rec.srid;
	
	query := 'SELECT gid,the_geom FROM ' || 
           'shortest_path_astar(''SELECT gid as id, source::integer, ' || 
           'target::integer, length::double precision as cost, ' || 
           'x1::double precision, y1::double precision, ' || 
           'x2::double precision, y2::double precision ';
	   
	IF rc THEN query := query || ' , reverse_cost ';
	END IF;
	   
	query := query || 'FROM ' || 
           quote_ident(geom_table) || ' where setSRID(''''BOX3D('||ll_x||' '||
           ll_y||','||ur_x||' '||ur_y||')''''::BOX3D, ' || srid || 
	   ') && the_geom'', ' || quote_literal(sourceid) || ' , ' || 
           quote_literal(targetid) || ' , '''||text(dir)||''', '''||text(rc)||''' ),'  ||
           quote_ident(geom_table) || ' where edge_id = gid ';
	
	FOR path_result IN EXECUTE query
        LOOP
               geom.gid      := path_result.gid;
               geom.the_geom := path_result.the_geom;
               id := id+1;
	       geom.id       := id;
                 
               RETURN NEXT geom;

        END LOOP;
        RETURN;
END;
$$
LANGUAGE 'plpgsql' VOLATILE STRICT; 


CREATE OR REPLACE FUNCTION astar_sp(
       geom_table varchar, source int4, target int4) 
       RETURNS SETOF GEOMS AS
$$
DECLARE 
        r record;
        path_result record;
        v_id integer;
        e_id integer;
        geom geoms;

	id integer;
BEGIN
	
	id :=0;
	FOR path_result IN EXECUTE 'SELECT gid,the_geom FROM ' || 
           'astar_sp_directed(''' || 
           quote_ident(geom_table) || ''', ' || quote_literal(source) || ', ' || 
	   quote_literal(target) || ', false, false)'
        LOOP

              geom.gid      := path_result.gid;
              geom.the_geom := path_result.the_geom;
              id := id+1;
	      geom.id       := id;
                 
              RETURN NEXT geom;

        END LOOP;
        RETURN;
END;
$$
LANGUAGE 'plpgsql' VOLATILE STRICT; 

-----------------------------------------------------------------------
-- A* function for directed graphs.
-- Compute the shortest path using edges table, and return
--  the result as a set of (gid integer, the_geom geometry) records.
-- Also data clipping added to improve function performance.
--
-- Last changes: 14.02.2008
-----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION astar_sp_directed(
       geom_table varchar, source int4, target int4, dir boolean, rc boolean) 
       RETURNS SETOF GEOMS AS
$$
DECLARE 
        r record;
        path_result record;
        v_id integer;
        e_id integer;
        geom geoms;
	
	query text;

	id integer;
BEGIN
	
	id :=0;
	query := 'SELECT gid,the_geom FROM ' || 
           'shortest_path_astar(''SELECT gid as id, source::integer, ' || 
           'target::integer, length::double precision as cost, ' || 
           'x1::double precision, y1::double precision, ' || 
           'x2::double precision, y2::double precision ';
	   
	IF rc THEN query := query || ' , reverse_cost ';
	END IF;

	query := query || 'FROM ' || quote_ident(geom_table) || ' '', ' || 
           quote_literal(source) || ' , ' || 
           quote_literal(target) || ' , '''||text(dir)||''', '''||text(rc)||'''), ' ||
           quote_ident(geom_table) || ' where edge_id = gid ';
	   
	FOR path_result IN EXECUTE query
        LOOP

              geom.gid      := path_result.gid;
              geom.the_geom := path_result.the_geom;
              id := id+1;
	      geom.id       := id;
                 
              RETURN NEXT geom;

        END LOOP;
        RETURN;
END;
$$
LANGUAGE 'plpgsql' VOLATILE STRICT; 

-----------------------------------------------------------------------
-- Shooting* function for directed graphs.
-- Compute the shortest path using edges table, and return
--  the result as a set of (gid integer, the_geom geometry) records.
--
-- Last changes: 14.02.2008
-----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION shootingstar_sp(
       varchar,int4, int4, float8, varchar, boolean, boolean) 
       RETURNS SETOF GEOMS AS
$$
DECLARE 
        geom_table ALIAS FOR $1;
	sourceid ALIAS FOR $2;
	targetid ALIAS FOR $3;
	delta ALIAS FOR $4;
        cost_column ALIAS FOR $5;
	dir ALIAS FOR $6;
	rc ALIAS FOR $7;

	rec record;
	r record;
        path_result record;
        v_id integer;
        e_id integer;
        geom geoms;
	
	srid integer;

	source_x float8;
	source_y float8;
	target_x float8;
	target_y float8;
	
	ll_x float8;
	ll_y float8;
	ur_x float8;
	ur_y float8;
	
	query text;

	id integer;
BEGIN
	
	id :=0;
	FOR rec IN EXECUTE
	    'select ST_SRID(the_geom) from ' ||
	    quote_ident(geom_table) || ' limit 1'
	LOOP
	END LOOP;
	srid := rec.srid;
	
	FOR rec IN EXECUTE 
            'select ST_X(ST_StartPoint(the_geom)) as source_x from ' || 
            quote_ident(geom_table) || ' where gid = '||sourceid
        LOOP
	END LOOP;
	source_x := rec.source_x;
	
	FOR rec IN EXECUTE 
            'select ST_Y(ST_StartPoint(the_geom)) as source_y from ' || 
            quote_ident(geom_table) || ' where gid = ' ||sourceid
        LOOP
	END LOOP;

	source_y := rec.source_y;

	FOR rec IN EXECUTE 
            'select ST_X(ST_StartPoint(the_geom)) as target_x from ' ||
            quote_ident(geom_table) || ' where gid = ' ||targetid
        LOOP
	END LOOP;

	target_x := rec.target_x;
	
	FOR rec IN EXECUTE 
            'select ST_Y(ST_StartPoint(the_geom)) as target_y from ' || 
            quote_ident(geom_table) || ' where gid = ' ||targetid
        LOOP
	END LOOP;
	target_y := rec.target_y;

	FOR rec IN EXECUTE 'SELECT CASE WHEN '||source_x||'<'||target_x||
           ' THEN '||source_x||' ELSE '||target_x||
           ' END as ll_x, CASE WHEN '||source_x||'>'||target_x||
           ' THEN '||source_x||' ELSE '||target_x||' END as ur_x'
        LOOP
	END LOOP;

	ll_x := rec.ll_x;
	ur_x := rec.ur_x;

	FOR rec IN EXECUTE 'SELECT CASE WHEN '||source_y||'<'||
            target_y||' THEN '||source_y||' ELSE '||
            target_y||' END as ll_y, CASE WHEN '||
            source_y||'>'||target_y||' THEN '||
            source_y||' ELSE '||target_y||' END as ur_y'
        LOOP
	END LOOP;

	ll_y := rec.ll_y;
	ur_y := rec.ur_y;

	query := 'SELECT gid,the_geom FROM ' || 
          'shortest_path_shooting_star(''SELECT gid as id, source::integer, ' || 
          'target::integer, '||cost_column||'::double precision as cost, ' || 
          'x1::double precision, y1::double precision, x2::double ' ||
          'precision, y2::double precision, rule::varchar, ' ||
	  'to_cost::double precision ';
	  
	IF rc THEN query := query || ' , reverse_cost ';  
	END IF;
	  
	query := query || 'FROM ' || quote_ident(geom_table) || ' where setSRID(''''BOX3D('||
          ll_x-delta||' '||ll_y-delta||','||ur_x+delta||' '||
          ur_y+delta||')''''::BOX3D, ' || srid || ') && the_geom'', ' || 
          quote_literal(sourceid) || ' , ' || 
          quote_literal(targetid) || ' , '''||text(dir)||''', '''||text(rc)||''' ),' || 
          quote_ident(geom_table) || ' where edge_id = gid ';
	  
	FOR path_result IN EXECUTE query
        LOOP
                 geom.gid      := path_result.gid;
                 geom.the_geom := path_result.the_geom;
		 id := id+1;
		 geom.id       := id;
                 
                 RETURN NEXT geom;

        END LOOP;
        RETURN;
END;
$$
LANGUAGE 'plpgsql' VOLATILE STRICT; 

-- COMMIT;
-----------------------------------------------------------------------
-- This function should not be used directly. Use assign_vertex_id instead
-- 
-- Inserts a point into a temporary vertices table, and return an id
--  of a new point or an existing point. Tolerance is the minimal distance
--  between existing points and the new point to create a new point.
--
-- Last changes: 16.04.2008
-- Author: Christian Gonzalez
-----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION point_to_id(p geometry, tolerance double precision)
RETURNS BIGINT 
AS 
$$ 

DECLARE
    _r record; 
    _id bigint;
BEGIN

    SELECT

        ST_Distance(the_geom, p) AS d, id, the_geom

    INTO _r FROM nodes WHERE

        ST_DWithin(the_geom, p, tolerance)

    ORDER BY d LIMIT 1; IF FOUND THEN

        _id:= _r.id;

    ELSE

        INSERT INTO nodes(the_geom) VALUES (p); _id:=lastval();

    END IF;

    RETURN _id;

END; $$ LANGUAGE 'plpgsql' VOLATILE STRICT; 


-----------------------------------------------------------------------
-- Fill the source and target_id column for all lines. All line ends
--  with a distance less than tolerance, are assigned the same id
--
-- Last changes: 16.04.2008
-- Author: Christian Gonzalez
-----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION assign_vertex_id(schema_name varchar, geom_table varchar,
    tolerance double precision, geo_cname varchar, gid_cname varchar)
RETURNS VARCHAR AS
$$
DECLARE
    _r record;
    source_id int;
    target_id int;
    srid integer;
BEGIN

    RAISE NOTICE 'Creating nodes from edges';

    FOR _r IN EXECUTE 'SELECT ' || quote_ident(gid_cname) || ' AS id,'
      || ' ST_StartPoint('|| quote_ident(geo_cname) ||') AS source,'
            || ' ST_EndPoint('|| quote_ident(geo_cname) ||') as target'
	    || ' FROM ' || quote_ident(schema_name) || '.' || quote_ident(geom_table)
        || ' WHERE ' || quote_ident(geo_cname) || ' IS NOT NULL '
    LOOP
      source_id := point_to_id(_r.source, tolerance);
      target_id := point_to_id(_r.target, tolerance);
								
	  EXECUTE 'update ' || quote_ident(schema_name) || '.' || quote_ident(geom_table) || 
        ' SET source = ' || source_id || 
        ', target = ' || target_id || 
        ' WHERE ' || quote_ident(gid_cname) || ' =  ' || _r.id;
    END LOOP;

    RAISE NOTICE 'Done';

    RETURN 'OK';
END;
$$
LANGUAGE 'plpgsql' VOLATILE STRICT; 
                                    
CREATE TYPE link_point AS (id integer, name varchar);

-------------------------------------------------------------------
-- This function finds nearest link to a given node
-- point - text representation of point
-- distance - function will search for a link within this distance
-- tbl - table name
-------------------------------------------------------------------
CREATE OR REPLACE FUNCTION find_nearest_link_within_distance(point varchar, 
	distance double precision, tbl varchar)
	RETURNS INT AS
$$
DECLARE
    row record;
    x float8;
    y float8;
    
    srid integer;
    
BEGIN

    FOR row IN EXECUTE 'select ST_SRID(the_geom) as srid from '||tbl||' where gid = (select min(gid) from '||tbl||')' LOOP
    END LOOP;
	srid:= row.srid;
    
    -- Getting x and y of the point
    
    FOR row in EXECUTE 'select ST_X(ST_GeometryFromText('''||point||''', '||srid||')) as x' LOOP
    END LOOP;
	x:=row.x;

    FOR row in EXECUTE 'select ST_Y(ST_GeometryFromText('''||point||''', '||srid||')) as y' LOOP
    END LOOP;
	y:=row.y;

    -- Searching for a link within the distance

    FOR row in EXECUTE 'select gid, ST_Distance(the_geom, ST_GeometryFromText('''||point||''', '||srid||')) as dist from '||tbl||
			    ' where ST_SetSRID(''BOX3D('||x-distance||' '||y-distance||', '||x+distance||' '||y+distance||')''::BOX3D, '||srid||')&&the_geom order by dist asc limit 1'
    LOOP
    END LOOP;

    IF row.gid IS NULL THEN
	    --RAISE EXCEPTION 'Data cannot be matched';
	    RETURN NULL;
    END IF;

    RETURN row.gid;

END;
$$
LANGUAGE 'plpgsql' VOLATILE STRICT;

-------------------------------------------------------------------
-- This function finds nearest node to a given node
-- point - text representation of point
-- distance - function will search for a link within this distance
-- tbl - table name
-------------------------------------------------------------------

CREATE OR REPLACE FUNCTION find_nearest_node_within_distance(point varchar, 
	distance double precision, tbl varchar)
	RETURNS INT AS
$$
DECLARE
    row record;
    x float8;
    y float8;
    d1 double precision;
    d2 double precision;
    d  double precision;
    field varchar;

    node integer;
    source integer;
    target integer;
    
    srid integer;
    
BEGIN

    FOR row IN EXECUTE 'select ST_SRID(the_geom) as srid from '||tbl||' where gid = (select min(gid) from '||tbl||')' LOOP
    END LOOP;
	srid:= row.srid;

    -- Getting x and y of the point

    FOR row in EXECUTE 'select ST_X(ST_GeometryFromText('''||point||''', '||srid||')) as x' LOOP
    END LOOP;
	x:=row.x;

    FOR row in EXECUTE 'select ST_Y(ST_GeometryFromText('''||point||''', '||srid||')) as y' LOOP
    END LOOP;
	y:=row.y;

    -- Getting nearest source

    FOR row in EXECUTE 'select source, ST_Distance(ST_StartPoint(the_geom), ST_GeometryFromText('''||point||''', '||srid||')) as dist from '||tbl||
			    ' where ST_SetSRID(''BOX3D('||x-distance||' '||y-distance||', '||x+distance||' '||y+distance||')''::BOX3D, '||srid||')&&the_geom order by dist asc limit 1'
    LOOP
    END LOOP;
    
    d1:=row.dist;
    source:=row.source;

    -- Getting nearest target

    FOR row in EXECUTE 'select target, ST_Distance(ST_EndPoint(the_geom), ST_GeometryFromText('''||point||''', '||srid||')) as dist from '||tbl||
			    ' where ST_SetSRID(''BOX3D('||x-distance||' '||y-distance||', '||x+distance||' '||y+distance||')''::BOX3D, '||srid||')&&the_geom order by dist asc limit 1'
    LOOP
    END LOOP;

    -- Checking what is nearer - source or target
    
    d2:=row.dist;
    target:=row.target;
    IF d1<d2 THEN
	node:=source;
        d:=d1;
    ELSE
	node:=target;
        d:=d2;
    END IF;

    IF d=NULL OR d>distance THEN
        node:=NULL;
    END IF;

    RETURN node;

END;
$$
LANGUAGE 'plpgsql' VOLATILE STRICT;

-------------------------------------------------------------------
-- This function finds nearest node as a source or target of the
-- nearest link
-- point - text representation of point
-- distance - function will search for a link within this distance
-- tbl - table name
-------------------------------------------------------------------

CREATE OR REPLACE FUNCTION find_node_by_nearest_link_within_distance(point varchar, 
	distance double precision, tbl varchar)
	RETURNS link_point AS
$$
DECLARE
    row record;
    link integer;
    d1 double precision;
    d2 double precision;
    field varchar;
    res link_point;
    
    srid integer;
BEGIN

    FOR row IN EXECUTE 'select ST_SRID(the_geom) as srid from '||tbl||' where gid = (select min(gid) from '||tbl||')' LOOP
    END LOOP;
	srid:= row.srid;


    -- Searching for a nearest link
    
    FOR row in EXECUTE 'select id from find_nearest_link_within_distance('''||point||''', '||distance||', '''||tbl||''') as id'
    LOOP
    END LOOP;
    IF row.id is null THEN
        res.id = -1;
        RETURN res;
    END IF;
    link:=row.id;

    -- Check what is nearer - source or target
    
    FOR row in EXECUTE 'select ST_Distance((select ST_StartPoint(the_geom) from '||tbl||' where gid='||link||'), ST_GeometryFromText('''||point||''', '||srid||')) as dist'
    LOOP
    END LOOP;
    d1:=row.dist;

    FOR row in EXECUTE 'select ST_Distance((select ST_EndPoint(the_geom) from '||tbl||' where gid='||link||'), ST_GeometryFromText('''||point||''', '||srid||')) as dist'
    LOOP
    END LOOP;
    d2:=row.dist;

    IF d1<d2 THEN
	field:='source';
    ELSE
	field:='target';
    END IF;
    
    FOR row in EXECUTE 'select '||field||' as id, '''||field||''' as f from '||tbl||' where gid='||link
    LOOP
    END LOOP;
        
    res.id:=row.id;
    res.name:=row.f;
    
    RETURN res;


END;
$$
LANGUAGE 'plpgsql' VOLATILE STRICT;

-------------------------------------------------------------------
-- This function matches given line to the existing network.
-- Returns set of edges as geometry.
-- tbl - table name
-- line - line to match
-- distance - distance for nearest node search
-- distance2 - distance for shortest path search
-- dir - true if your network graph is directed
-- rc - true if you have a reverse_cost column
-------------------------------------------------------------------

CREATE OR REPLACE FUNCTION match_line_as_geometry(tbl varchar, line geometry, distance double precision, 
						distance2 double precision, dir boolean, rc boolean)
	RETURNS SETOF GEOMS AS
$$
DECLARE
    row record;
    num integer;
    i integer;
    geom geoms;
    points integer[];
    
    srid integer;
    
    query text;
    
BEGIN

    FOR row IN EXECUTE 'select ST_SRID(the_geom) as srid from '||tbl||' where gid = (select min(gid) from '||tbl||')' LOOP
    END LOOP;
	srid:= row.srid;


    FOR row IN EXECUTE 'select ST_GeometryType(ST_GeometryFromText('''||astext(line)||''', '||srid||')) as type' LOOP
    END LOOP;
    
    IF row.type <> 'LINESTRING' THEN
	RAISE EXCEPTION 'Geometry should be a linestring.';
    END IF;
    
    -- Searching through all points in given line
    
    num:=NumPoints(line);
    i:= 0;
    
    LOOP
	i:=i+1;

        -- Getting nearest node to the current point
	
	FOR row in EXECUTE 'select * from find_nearest_node_within_distance(''POINT('
			    ||ST_X(ST_PointN(line, i))||' '||ST_Y(PointN(line, i))||')'','||distance||', '''||tbl||''') as id'
	LOOP
	END LOOP;
	
	IF row.id IS NOT NULL THEN
	    points[i-1]:=row.id;

        ELSE 
	
	    -- If there is no nearest node within given distance, let's try another algorithm
	
            FOR row in EXECUTE 'select * from find_node_by_nearest_link_within_distance(''POINT('
	    		        ||ST_X(ST_PointN(line, i))||' '||ST_Y(PointN(line, i))||')'','||distance2||', '''||tbl||''') as id'
	    LOOP
	    END LOOP;

	    points[i-1]:=row.id;

        END IF;

	IF i>1 AND points[i-2] <> points[i-1] THEN
	
	    -- We could find existing edge, so let's construct the main query now
	
	    query := 'select gid, the_geom FROM shortest_path( ''select gid as id, source::integer,'||
				' target::integer, length::double precision as cost,x1,x2,y1,y2';
				
	    IF rc THEN query := query || ', reverse_cost'; 
	    END IF;				
				
	    query := query || ' from '||quote_ident(tbl)||' where ST_SetSRID(''''BOX3D('||ST_X(ST_PointN(line, i-1))-distance2*2||' '
				||ST_Y(ST_PointN(line, i-1))-distance2*2||', '||ST_X(ST_PointN(line, i))+distance2*2||' '
				||ST_Y(ST_PointN(line, i))+distance2*2||')''''::BOX3D, '||srid||')&&the_geom'', '
				|| points[i-1] ||', '||	points[i-2] ||', '''||dir||''', '''||rc||'''), '
				||quote_ident(tbl)||' where edge_id=gid';
	    FOR row IN EXECUTE query
	    LOOP

		geom.gid := row.gid;
		geom.the_geom := row.the_geom;
		
		RETURN NEXT geom;
		
	    END LOOP;

	END IF;															


	EXIT WHEN i=num;
	
	
    END LOOP;    
    
    RETURN;

END;
$$

LANGUAGE 'plpgsql' VOLATILE STRICT;

-------------------------------------------------------------------
-- This function matches given line to the existing network.
-- Returns set of edges.
-- tbl - table name
-- line - line to match
-- distance - distance for nearest node search
-- distance2 - distance for shortest path search
-- dir - true if your network graph is directed
-- rc - true if you have a reverse_cost column
-------------------------------------------------------------------

CREATE OR REPLACE FUNCTION match_line(tbl varchar, line geometry, distance double precision, 
						distance2 double precision, dir boolean, rc boolean)
	RETURNS SETOF PATH_RESULT AS
$$
DECLARE
    row record;
    num integer;
    
    i integer;
    z integer;
    t integer;
    
    prev integer;
    
    query text;
    
    path path_result;
    
    edges integer[];
    vertices integer[];
    costs double precision[];
    
    srid integer;
    
    points integer[];

BEGIN

    FOR row IN EXECUTE 'select ST_SRID(the_geom) as srid from '||tbl||' where gid = (select min(gid) from '||tbl||')' LOOP
    END LOOP;
	srid:= row.srid;

    FOR row IN EXECUTE 'select ST_GeometryType(ST_GeometryFromText('''||astext(line)||''', '||srid||')) as type' LOOP
    END LOOP;
    
    IF row.type <> 'LINESTRING' THEN
	RAISE EXCEPTION 'Geometry should be a linestring.';
    END IF;

    num:=ST_NumPoints(line);
    i:= 0;
    z:= 0;
    prev := -1;
        
    -- Searching through all points in given line

    LOOP
	i:=i+1;

        -- Getting nearest node to the current point

        FOR row in EXECUTE 'select * from find_nearest_node_within_distance(''POINT('
			    ||ST_X(ST_PointN(line, i))||' '||ST_Y(ST_PointN(line, i))||')'','||distance||', '''||tbl||''') as id'
	LOOP
	END LOOP;
	

	IF row.id IS NOT NULL THEN
	    points[i-1]:=row.id;

        ELSE 

	    -- If there is no nearest node within given distance, let's try another algorithm

            FOR row in EXECUTE 'select * from find_node_by_nearest_link_within_distance(''POINT('
	    		        ||ST_X(ST_PointN(line, i))||' '||ST_Y(ST_PointN(line, i))||')'','||distance2||', '''||tbl||''') as id'
	    LOOP
	    END LOOP;

	    points[i-1]:=row.id;
            IF row.id = -1 THEN
                return;
            END IF;

        END IF;

	IF i>1 AND points[i-2] <> points[i-1] THEN
	
	    -- We could find existing edge, so let's construct the main query now

	    query := 'select edge_id, vertex_id, cost FROM shortest_path( ''select gid as id, source::integer,'||
				' target::integer, length::double precision as cost,x1,x2,y1,y2 ';
				
	    IF rc THEN query := query || ', reverse_cost'; 
	    END IF;
	    
	    query := query || ' from '||quote_ident(tbl)||' where ST_SetSRID(''''BOX3D('||ST_X(ST_PointN(line, i-1))-distance2*2||' '
				||ST_Y(ST_PointN(line, i-1))-distance2*2||', '||ST_X(ST_PointN(line, i))+distance2*2||' '
				||ST_Y(ST_PointN(line, i))+distance2*2||')''''::BOX3D, '||srid||')&&the_geom'', '
				|| points[i-1] ||', '||	points[i-2] ||', '''||dir||''', '''||rc||''')';

	    
	    BEGIN
	    
	    FOR row IN EXECUTE query
	    LOOP
	    
	    
		IF row IS NULL THEN
		    RAISE NOTICE 'Cannot find a path between % and %', points[i-1], points[i-2];
	    	    RETURN;
		END IF;

		edges[z] := row.edge_id;
		vertices[z] := row.vertex_id;
		costs[z] := row.cost;
		
		IF edges[z] = -1 THEN
		
		    t := 0;
		    
		    -- Ordering edges
		    
		    FOR t IN (prev+1)..z-1 LOOP
		    
			path.edge_id := edges[t];
			path.vertex_id := vertices[t];
			path.cost = costs[t];
			
			edges[t] := edges[z-t+prev+1];
			vertices[t] := vertices[z-t+prev+1];
			costs[t] := costs[z-t+prev+1];

			edges[z-t+prev+1] := path.edge_id;
			vertices[z-t+prev+1] := path.vertex_id;
			costs[z-t+prev+1] := path.cost;
			
					    
		    END LOOP;
		    
		    prev := z;

		END IF;	
		
		z := z+1;
		
	    END LOOP;
	    
	    EXCEPTION
		WHEN containing_sql_not_permitted THEN RETURN;
	    
	    END;

	END IF;															

	EXIT WHEN i=num;
	
    END LOOP;    

    FOR t IN 0..array_upper(edges, 1) LOOP
    
	IF edges[array_upper(edges, 1)-t] > 0 OR (edges[array_upper(edges, 1)-t] < 0 AND t = array_upper(edges, 1)) THEN
	path.edge_id := edges[array_upper(edges, 1)-t];
	path.vertex_id := vertices[array_upper(edges, 1)-t];
	path.cost = costs[array_upper(edges, 1)-t];
	RETURN NEXT path;	
	END IF;
    END LOOP;
    
    RETURN;

END;
$$

LANGUAGE 'plpgsql' VOLATILE STRICT;

-------------------------------------------------------------------
-- This function matches given line to the existing network.
-- Returns single (multi)linestring.
-- tbl - table name
-- line - line to match
-- distance - distance for nearest node search
-- distance2 - distance for shortest path search
-- dir - true if your network graph is directed
-- rc - true if you have a reverse_cost column
-------------------------------------------------------------------

CREATE OR REPLACE FUNCTION match_line_as_linestring(tbl varchar, line geometry, distance double precision, 
						distance2 double precision, dir boolean, rc boolean)
	RETURNS GEOMETRY AS
$$
DECLARE
    row record;
    
    i integer;
    
    edges integer[];
    
    srid integer;
    
BEGIN

    FOR row IN EXECUTE 'select ST_SRID(the_geom) as srid from '||tbl||' where gid = (select min(gid) from '||tbl||')' LOOP
    END LOOP;
	srid:= row.srid;

    FOR row IN EXECUTE 'select ST_GeometryType(ST_GeometryFromText('''||astext(line)||''', '||srid||')) as type' LOOP
    END LOOP;
    
    IF row.type <> 'LINESTRING' THEN
	RAISE EXCEPTION 'Geometry should be a linestring.';
    END IF;

    i := 0;
    
    FOR row IN EXECUTE 'select * from match_line('''||quote_ident(tbl)||''', ST_GeometryFromText('''||astext(line)||''', '||srid||'), '
			    ||distance||', '||distance2||', '''||dir||''', '''||rc||''')' LOOP
	edges[i] := row.edge_id;
	i := i + 1;
    END LOOP;
    IF i = 0 THEN
        return NULL;
    END IF;

    -- Attempt to create a single linestring. It may return multilinestring as well.

    FOR row IN EXECUTE 'select ST_LineMerge(ST_Union(ST_Multi(the_geom))) as the_geom from '||tbl||' where gid in ('||array_to_string(edges, ', ')||') and gid > 0' LOOP
    END LOOP;
    
    IF isvalid(row.the_geom) THEN
        RETURN row.the_geom;
    ELSE
	RAISE EXCEPTION 'The result is not a valid geometry.';
    END IF;

END;
$$

LANGUAGE 'plpgsql' VOLATILE STRICT;
