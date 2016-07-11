-- -- function that takes a point, number of edges, dispersion function and inclusion distance
-- returns cumulative TIF
SET search_path = exposure, public;

DROP FUNCTION IF EXISTS cumulative_tif (NUMERIC[], NUMERIC[], INTEGER, NUMERIC, INTEGER);
DROP FUNCTION IF EXISTS cumulative_tif (NUMERIC, NUMERIC, INTEGER, NUMERIC, INTEGER);
DROP TYPE IF EXISTS TIF;

CREATE TYPE TIF AS (
  id   INTEGER,
  x    NUMERIC,
  y    NUMERIC,
  tif  NUMERIC,
  geom GEOMETRY 
);

CREATE FUNCTION cumulative_tif (
  x            NUMERIC[],
  y            NUMERIC[],
  roadCount    INTEGER,
  dispFactor   NUMERIC,
  inclDistance INTEGER
)
RETURNS SETOF TIF
AS
$_$
DECLARE
  query     TEXT;
  result    RECORD;
  tif       exposure.TIF;
  degreeM   NUMERIC DEFAULT 111319.9; -- 1 degree in meters (approximate)
  geomJoin  TEXT;
  pointWKT  VARCHAR(255);
  i         INTEGER DEFAULT 0;
BEGIN
  -- check that list of x and y positions match in length
  IF ARRAY_UPPER (x, 1) <> ARRAY_UPPER (y, 1)
  THEN
    RAISE EXCEPTION 'The number of x coordinates: % and y coordinates: % do not match',
                    ARRAY_UPPER (x, 1) + 1, ARRAY_UPPER (y, 1) + 1;
  END IF;

  -- check that list of x is not empty
  IF ARRAY_UPPER (x, 1) < 0
  THEN
    RAISE EXCEPTION 'No coordinates provided';
  END IF;

  -- will have valid list of x and y coordinates
  -- construct geometry values clause
  geomJoin := '(VALUES ';

  FOR i IN SELECT GENERATE_SERIES (1, ARRAY_UPPER (x, 1))
  LOOP
    IF x[i] < -180 OR x[i] > 180
    THEN
      RAISE EXCEPTION 'Invalid longitude: % found at %', x[i], i;
    END IF;

    IF y[i] < -90 OR y[i] > 90
    THEN
      RAISE EXCEPTION 'Invalid latitude: % found at %', y[i], i;
    END IF;

    IF i > 1
    THEN
      geomJoin := geomJoin || ', (' || i || ', ST_GeomFromText (''POINT (' || x[i] || ' ' || y[i] || ')'', 4326))';
    ELSE
      geomJoin := geomJoin || '(' || i || ', ST_GeomFromText (''POINT (' || x[i] || ' ' || y[i] || ')'', 4326))';
    END IF;
  END LOOP;

  geomJoin := geomJoin || ') AS p (id, geom)';
  
  query := 'SELECT id,
                   x,
                   y,
                   SUM (aadt * POW (distance * ' || degreeM || ' * ABS (COS (RADIANS (y))), ' || dispFactor || ')) AS tif, 
                   ST_Multi (ST_Collect (DISTINCT geom)) AS geom
              FROM (
                SELECT p.id,
                       ST_X (p.geom) AS x,
                       ST_Y (p.geom) AS y,
                       en.network_id AS edge_id,
                       aadt_weekdays AS aadt,
                       ST_Distance (p.geom, en.geom) AS distance,
                       RANK () OVER (PARTITION BY p.id ORDER BY ST_Distance (p.geom, en.geom)) AS rank,
                       en.geom
                  FROM trafficmodel.network_edge AS en
                  JOIN ' || geomJoin || '
                       ON ST_IsValid (p.geom) = TRUE AND
                          ST_Expand (p.geom, 0.0201397760129886) && en.geom AND
                          ST_DWithin (p.geom, en.geom, ' || inclDistance || '/ (' || degreeM || ' * ABS (COS (RADIANS (ST_Y(p.geom)))))) = FALSE
              ) AS c 
             WHERE rank < ' || roadCount || '
          GROUP BY id, x, y';

  RAISE NOTICE 'query: %', query;

  FOR result IN EXECUTE query
  LOOP
    tif.id    := result.id;
    tif.x     := result.x;
    tif.y     := result.y;
    tif.tif   := result.tif;
    tif.geom  := result.geom;

    RETURN NEXT tif;
  END LOOP;
  
  RETURN;
END;
$_$
LANGUAGE 'plpgsql' VOLATILE STRICT
;

--
-- wrapper function for submitting single point for calculating TIF
--

CREATE FUNCTION cumulative_tif (
  x            NUMERIC,
  y            NUMERIC,
  roadCount    INTEGER,
  dispFactor   NUMERIC,
  inclDistance INTEGER
)
RETURNS SETOF TIF
AS
$_$
DECLARE
  query  TEXT;
  result RECORD;
  tif    exposure.TIF;
BEGIN
  query := 'SELECT (m).id, (m).x, (m).y, (m).tif, (m).geom
              FROM exposure.cumulative_tif (ARRAY[' || x || ']::NUMERIC[],
                                            ARRAY[' || y || ']::NUMERIC[],
                                            ' || roadCount || ',
                                            ' || dispFactor || ',
                                            ' || inclDistance || ') AS m';

  FOR result IN EXECUTE query
  LOOP
    tif.id   = result.id;
    tif.x    = result.x;
    tif.y    = result.y;
    tif.tif  = result.tif;
    tif.geom = result.geom;

    RETURN NEXT tif;
  END LOOP;

  RETURN;
END;
$_$
LANGUAGE 'plpgsql' VOLATILE STRICT
;


