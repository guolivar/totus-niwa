-- SQL function to determine closest node to a point alongside line string
SET search_path = network, public;

DROP FUNCTION IF EXISTS closest_edge_node ( NUMERIC (12, 8),  NUMERIC (12, 8), NUMERIC (12, 8) );
DROP TYPE IF EXISTS ROUTE_EDGE;

CREATE TYPE ROUTE_EDGE AS (
  id     INTEGER,
  nodeId INTEGER
);

CREATE FUNCTION closest_edge_node ( x NUMERIC (12, 8), y NUMERIC (12, 8), range NUMERIC (12, 8) )
RETURNS route_edge AS
$_$
DECLARE
  srid   INTEGER       DEFAULT 4326;  -- WGS84
  bbox   VARCHAR(256);
  query  TEXT;
  result network.ROUTE_EDGE;
BEGIN
  bbox := 'BOX3D(' || x - range || ' ' || y - range || ',' || x + range || ' ' || y + range || ')';

  query := 'SELECT gid AS id,
                   CASE WHEN ST_Line_Locate_Point (ST_LineMerge(the_geom), 
                                 ST_GeometryFromText(''POINT(' || x || ' ' || y || ')'', ' || srid || ')
                             ) < 0.5
                        THEN source
                        ELSE target
                   END AS nodeId
             FROM network.edges
             WHERE the_geom && ST_SetSRID (''' || bbox || '''::box3d, ' || srid || ')
          ORDER BY ST_Distance(the_geom, ST_GeometryFromText(''POINT(' || x || ' ' || y || ')'', ' || srid || '))
             LIMIT 1';

  EXECUTE query INTO result;

  RETURN result;
END;
$_$
LANGUAGE 'plpgsql' VOLATILE STRICT; 
