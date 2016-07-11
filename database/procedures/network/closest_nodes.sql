SET search_path = network, public;

DROP FUNCTION IF EXISTS closest_nodes ( NUMERIC (12, 8),  NUMERIC (12, 8), NUMERIC (9, 8), SMALLINT );
DROP FUNCTION IF EXISTS closest_nodes ( NUMERIC (12, 8),  NUMERIC (12, 8), NUMERIC (9, 8), VARCHAR (32)[], SMALLINT );
DROP TYPE IF EXISTS node;

CREATE TYPE node AS (
  id    INTEGER,
  x     NUMERIC (12, 8),
  y     NUMERIC (12, 8),
  error NUMERIC (12, 8)
);

-- given a DD position and degree range return number of closest nodes in network.nodes
CREATE FUNCTION closest_nodes ( x NUMERIC (12, 8), y NUMERIC (12, 8), range NUMERIC (9, 8), number SMALLINT )
RETURNS SETOF network.node AS
$_$
DECLARE
  srid   INTEGER       DEFAULT 4326;  -- WGS84
  bbox   VARCHAR(256);
  query  TEXT;
  result record;
  node   network.node;
BEGIN
  bbox := 'BOX3D(' || x - range || ' ' || y - range || ',' || x + range || ' ' || y + range || ')';

  query := 'SELECT DISTINCT
                   n.id,
                   ST_X(n.the_geom) AS x,
                   ST_Y(n.the_geom) AS y,
                   ST_Distance(n.the_geom, ST_GeometryFromText(''POINT(' || x || ' ' || y || ')'', ' || srid || ')) AS error
              FROM network.nodes AS n
              JOIN network.edges AS e
                   ON n.id = e.source OR
                      n.id = e.target
              JOIN network.classes AS c
                   ON e.class_id = c.id
              JOIN network.types AS t
                   ON c.type_id = t.id AND
                      t.name = ''highway''
             WHERE n.the_geom && ST_SetSRID (''' || bbox || '''::box3d, ' || srid || ')
          ORDER BY ST_Distance(n.the_geom, ST_GeometryFromText(''POINT(' || x || ' ' || y || ')'', ' || srid || '))
             LIMIT ' || number;

	FOR result IN EXECUTE query
    LOOP
      node.id    := result.id;
      node.x     := result.x;
      node.y     := result.y;
      node.error := result.error;
      RETURN NEXT node;
    END LOOP;
END;
$_$
LANGUAGE 'plpgsql' VOLATILE STRICT; 

-- given a DD position, degree range and array of road classes to filter on, return number of closest nodes in network.nodes
CREATE FUNCTION closest_nodes (
  x NUMERIC (12, 8),
  y NUMERIC (12, 8),
  range NUMERIC (9, 8),
  roadClassFilters VARCHAR (32)[],
  number SMALLINT
)
RETURNS SETOF network.node AS
$_$
DECLARE
  srid   INTEGER       DEFAULT 4326;  -- WGS84
  bbox   VARCHAR(256);
  query  TEXT;
  result record;
  node   network.node;
BEGIN
  bbox := 'BOX3D(' || x - range || ' ' || y - range || ',' || x + range || ' ' || y + range || ')';

  query := 'SELECT DISTINCT
                   n.id,
                   ST_X(n.the_geom) AS x,
                   ST_Y(n.the_geom) AS y,
                   ST_Distance(n.the_geom, ST_GeometryFromText(''POINT(' || x || ' ' || y || ')'', ' || srid || ')) AS error
              FROM network.nodes AS n
              JOIN network.edges AS e
                   ON n.id = e.source OR
                      n.id = e.target
              JOIN network.classes AS c
                   ON e.class_id = c.id
              JOIN network.types AS t
                   ON c.type_id = t.id
             WHERE n.the_geom && ST_SetSRID (''' || bbox || '''::box3d, ' || srid || ')
               AND t.name = ''highway''
               AND c.name IN (''' || ARRAY_TO_STRING (roadClassFilters, ''',''') || ''')
          ORDER BY ST_Distance(n.the_geom, ST_GeometryFromText(''POINT(' || x || ' ' || y || ')'', ' || srid || '))
             LIMIT ' || number;

	FOR result IN EXECUTE query
    LOOP
      node.id    := result.id;
      node.x     := result.x;
      node.y     := result.y;
      node.error := result.error;
      RETURN NEXT node;
    END LOOP;
END;
$_$
LANGUAGE 'plpgsql' VOLATILE STRICT; 
