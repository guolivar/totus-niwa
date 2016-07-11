-- function that extracts TIF summary statistics from 100m grid TIF Traffic Model edges
-- inside a given polygon area
SET search_path = exposure, public;

DROP FUNCTION IF EXISTS tif_summary (TEXT);
DROP TYPE IF EXISTS TIF_SUMMARY;

CREATE TYPE TIF_SUMMARY AS (
  id    INTEGER,
  sum   NUMERIC,
  min   NUMERIC,
  max   NUMERIC,
  ave   NUMERIC,
  count INTEGER,
  geom  GEOMETRY
);

CREATE FUNCTION tif_summary (spatialFilter TEXT)
RETURNS SETOF TIF_SUMMARY
AS
$_$
DECLARE
  query  TEXT;
  result RECORD;
  tif    exposure.TIF_SUMMARY;  
BEGIN
  IF spatialFilter !~ '^(MULTIP|P)OLYGON' OR spatialFilter ~ '(SELECT|;|DROP|UPDATE)'
  THEN
    RAISE EXCEPTION 'Invalid spatial filter supplied: %', spatialFilter;
  END IF;

  query := 'SELECT 1 AS id,
                   SUM (gte.tif) AS sum,
                   MIN (gte.tif) AS min,
                   MAX (gte.tif) AS max,
                   AVG (gte.tif) AS ave,
                   COUNT (gte.tif) AS count,
                   ST_Multi (ST_Collect (DISTINCT e.the_geom)) AS geom
              FROM exposure.grid AS g
              JOIN exposure.grid_tif_edge AS gte
                   ON g.id = gte.grid_id
              JOIN network.edges AS e
                   ON gte.edge_id = e.gid
              JOIN ST_GeomFromText (' || quote_literal (spatialFilter) || ', 4326) AS f (geom)
                   ON ST_IsValid (f.geom) = TRUE AND
                      g.geom && f.geom AND
                      ST_Within (e.the_geom, f.geom)';

  FOR result IN EXECUTE query
  LOOP
    tif.id    := result.id;
    tif.sum   := result.sum;
    tif.min   := result.min;
    tif.max   := result.max;
    tif.ave   := result.ave;
    tif.count := result.count;
    tif.geom  := result.geom;

    RETURN NEXT tif;
  END LOOP;
  
  RETURN;
END;
$_$
LANGUAGE 'plpgsql' VOLATILE STRICT
;
