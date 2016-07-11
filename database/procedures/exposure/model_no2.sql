SET search_path = exposure, public;

DROP FUNCTION IF EXISTS model_no2 (NUMERIC, NUMERIC, INTEGER, INTEGER, NUMERIC, INTEGER, BOOLEAN, NUMERIC);
DROP TYPE IF EXISTS grid_no2 CASCADE;

CREATE TYPE grid_no2 AS (
  id   INTEGER,
  tif  NUMERIC,
  no2  NUMERIC,
  year SMALLINT,
  geom GEOMETRY
);
-- NO2 (ug/m3) = 0.00171 TIF + 11.9
CREATE FUNCTION model_no2 (
  coeff             NUMERIC DEFAULT 0.00171, 
  const             NUMERIC DEFAULT 11.9, 
  cellSize          INTEGER DEFAULT 100, 
  roadCount         INTEGER DEFAULT 10000,
  dispersionFactor  NUMERIC DEFAULT -0.65,
  inclusionDistance INTEGER DEFAULT 10,
  forceTIF          BOOLEAN DEFAULT FALSE,
  dataYear          NUMERIC DEFAULT 2006,
  region            CHAR(2) DEFAULT 'AK'
)
RETURNS SETOF grid_no2
AS
$_$
DECLARE
  minx   NUMERIC;
  miny   NUMERIC;
  maxx   NUMERIC;
  maxy   NUMERIC;
  exists VARCHAR(32);
  result RECORD;
  no2    exposure.grid_no2;
BEGIN
  IF cellSize < 10
  THEN
    RAISE EXCEPTION 'Smallest cell size allowed is 10';
  END IF;

  IF region = 'AK'
  THEN
    -- Auckland
    -- Top Left 174.1437, -35.8754
    -- Bottom Right 175.6234, -37.3059
    minx := 174.1437;
    miny := -37.3059;
    maxx := 175.6234;
    maxy := -35.8754;
  END IF;

  IF region = 'CH'
  THEN
    -- Christchurch:
    -- Top Left 172.18346,-43.23770
    -- Bottom Right 172.91026,-43.79516
    minx := 172.18346;
    miny := -43.79516;
    maxx := 172.91026;
    maxy := -43.23770;
  END IF;
 
  EXECUTE 'SELECT tablename 
             FROM pg_tables
            WHERE schemaname = ''exposure''
              AND tablename = ''grid_' || cellSize::VARCHAR || 'm''' INTO exists;

  IF exists IS NULL
  THEN
    -- no grid create it first
    EXECUTE 'SELECT exposure.create_grid (' || 
               minx || ',' || 
               miny || ',' || 
               maxx || ',' || 
               maxy || ',' || 
               cellSize || ')';
  END IF;

  EXECUTE 'SELECT tablename 
             FROM pg_tables
            WHERE schemaname = ''exposure''
              AND tablename = ''grid_' || cellSize::VARCHAR || 'm_tif_edge''' INTO exists;

  IF forceTIF = TRUE OR exists IS NULL
  THEN
    EXECUTE 'DROP TABLE IF EXISTS exposure.grid_' || cellSize::VARCHAR || 'm_tif_edge';

    EXECUTE 'SELECT exposure.grid_tif_edge (' ||
               cellSize          || ',' ||
               roadCount         || ',' ||  
               inclusionDistance || ',' || 
               dispersionFactor  || ',' ||
               dataYear || ')';
  END IF;

  FOR result IN EXECUTE 'SELECT g.id, 
                                tg.tif,
                                ' || coeff || ' * tg.tif + ' || const || ' AS no2, 
                                tg.year,
                                g.geom
                           FROM exposure.grid_' || cellSize::VARCHAR || 'm AS g
                           JOIN (
                             SELECT grid_id, 
                                    SUM (tif) AS tif,
                                    year
                               FROM exposure.grid_' || cellSize::VARCHAR || 'm_tif_edge
                              WHERE year = ' || dataYear::VARCHAR || '
                           GROUP BY grid_id, year
                           ) AS tg
                             ON g.id = tg.grid_id'
    
  LOOP
    no2.id   := result.id;
    no2.tif  := result.tif;
    no2.no2  := result.no2;
    no2.year := result.year;
    no2.geom := result.geom;

    RETURN NEXT no2;
  END LOOP;
                  
  RETURN;
END;
$_$
LANGUAGE 'plpgsql' VOLATILE STRICT
;
