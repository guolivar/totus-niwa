DROP FUNCTION IF EXISTS closest_edge ( NUMERIC (12, 8),  NUMERIC (12, 8) );
DROP TYPE IF EXISTS edge;

CREATE TYPE edge AS (
  id        INTEGER,
  startnode INTEGER,
  endnode   INTEGER
);

CREATE FUNCTION closest_edge ( x NUMERIC (12, 8), y NUMERIC (12, 8) )
RETURNS edge AS
$_$
DECLARE
  --range NUMERIC (12, 8) DEFAULT 0.002  ; -- ~222 m at equator
  range NUMERIC (12, 8) DEFAULT 0.2; -- ~22.2 km at equator
  srid  INTEGER         DEFAULT 4326;  -- WGS84
  bbox  VARCHAR(256);
  query TEXT;
  result record;
  edge edge;
BEGIN
  bbox := 'BOX3D(' || x - range || ' ' || y - range || ',' || x + range || ' ' || y + range || ')';

  query := 'SELECT gid AS id,
                   source AS startnode,
                   target AS endnode
              FROM network.edges
             WHERE the_geom && ST_SetSRID (''' || bbox || '''::box3d, ' || srid || ')
          ORDER BY ST_Distance(the_geom, ST_GeometryFromText(''POINT(' || x || ' ' || y || ')'', ' || srid || '))
             LIMIT 1';
	FOR result IN EXECUTE query
    LOOP
      edge.id        := result.id;
      edge.startnode := result.startnode;
      edge.endnode   := result.endnode;
      RETURN edge;
    END LOOP;
END;
$_$
LANGUAGE 'plpgsql' VOLATILE STRICT; 
