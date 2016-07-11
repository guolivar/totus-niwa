SET search_path = exposure, public;

DROP FUNCTION IF EXISTS create_grid (NUMERIC, NUMERIC, NUMERIC, NUMERIC, INTEGER, BOOLEAN);

CREATE FUNCTION create_grid (
  minx        NUMERIC, 
  miny        NUMERIC, 
  maxx        NUMERIC, 
  maxy        NUMERIC, 
  cellSize    INTEGER, 
  forceGrid   BOOLEAN DEFAULT FALSE
)
RETURNS VOID
AS
$_$
DECLARE
  nuX       INTEGER;
  nuY       INTEGER;
  sz        NUMERIC;
  i         INTEGER;
  j         INTEGER; 
  sx        NUMERIC;
  sy        NUMERIC;
  tableName VARCHAR(32);
  exists    VARCHAR(32);
  c         INTEGER;
  batch     INTEGER;
  query     TEXT;
  comma     CHAR(1);
  degreeM   NUMERIC; 
BEGIN
  -- batch size of 10 or 100 performs best, when bigger than 1000 it becomes slower
  batch := 100;

  -- 1 degree in meters (approximate) at equator, scale it by cosine 
  -- with increasing latitude
  degreeM := 111319.9; 

  sz  := cellSize / (degreeM * COS (RADIANS ((miny + maxy) / 2)));
  nuX := ((maxx - minx) / sz)::INTEGER;
  nuY := ((maxy - miny) / sz)::INTEGER;

  -- cache grid
  tableName := 'grid_' || cellSize::VARCHAR || 'm';

  -- recreate grid only when forced
  IF forceGrid = TRUE
  THEN
    EXECUTE 'DROP TABLE IF EXISTS exposure.' || tableName;
  END IF;

  EXECUTE 'SELECT tablename 
             FROM pg_tables
            WHERE schemaname = ''exposure''
              AND tablename = ''grid_' || cellSize::VARCHAR || 'm''' INTO exists;

  -- only create the grid if it does not already exist
  IF exists IS NULL
  THEN
    EXECUTE 'SELECT tablename 
               FROM pg_tables
              WHERE schemaname = ''exposure''
                AND tablename = ''grid_mask''' INTO exists;

    IF exists IS NULL
    THEN
      RAISE NOTICE 'Creating grid mask from ATM zones and bridges';

      -- create mask table to hold ATM zones and bridges
      EXECUTE 'CREATE TABLE exposure.grid_mask (
                 id SERIAL
              )';

      EXECUTE 'SELECT AddGeometryColumn (''exposure'', ''grid_mask'', ''geom'', 4326, ''MULTIPOLYGON'', 2)';

      -- insert ATM2 zones merged to produce one mask
      EXECUTE 'INSERT INTO exposure.grid_mask (geom)
               SELECT ST_Simplify (geom, 0.001) AS geom
                 FROM trafficmodel.zone';

      EXECUTE 'CREATE INDEX grid_mask_geom_idx ON exposure.grid_mask USING GiST (geom)';

      EXECUTE 'ANALYZE VERBOSE exposure.grid_mask';

      PERFORM 'GRANT SELECT ON exposure.grid_mask TO totus';
      PERFORM 'GRANT SELECT ON exposure.grid_mask TO totus_ingester';
    END IF;

    RAISE NOTICE 'Creating grid of size: % x %', nuY, nuY ;

    -- create grid table
    EXECUTE 'CREATE TABLE exposure.' || tableName || '(
               id SERIAL
             )';

    EXECUTE 'SELECT AddGeometryColumn (''exposure'', ''' || tableName || ''', ''geom'', 4326, ''POLYGON'', 2)';
             
    c := 0;

    query := 'INSERT INTO exposure.' || tableName || '(geom)
              SELECT DISTINCT ON (m.geom)
                     m.geom
                FROM (
                  VALUES ';

    FOR j IN SELECT GENERATE_SERIES (0, nuY)
    LOOP
      FOR i IN SELECT GENERATE_SERIES (0, nuX)
      LOOP
        -- calculate cell start xy
        sx := minx + (i * sz);
        sy := miny + (j * sz);

        IF (c > 0) 
        THEN
          comma := ',';
        ELSE
          comma := '';
        END IF;

        -- create cell if it overlaps with ATM2 zone
        IF c < batch
        THEN
          query := query || 
                   comma ||
                   '(ST_SetSRID (ST_MakePolygon (ST_GeomFromText (''LINESTRING (' ||
                       sx      || ' ' || sy      || ',' ||
                       sx + sz || ' ' || sy      || ',' ||
                       sx + sz || ' ' || sy + sz || ',' || 
                       sx      || ' ' || sy + sz || ',' ||
                       sx      || ' ' || sy      || ')'')), 4326))';
          c := c + 1;
        END IF;

        IF batch = 1 OR c = batch
        THEN
          query := query ||
                   ') AS m (geom)
                    JOIN exposure.grid_mask AS z
                      ON m.geom && z.geom AND
                         ST_DWithin (z.geom, ST_Centroid (m.geom), ' || (sz / 2) || ')';

          EXECUTE query;
          
          c := 0;
          query := 'INSERT INTO exposure.' || tableName || '(geom)
                    SELECT DISTINCT ON (m.geom)
                           m.geom
                      FROM (
                        VALUES ';

        END IF;
      END LOOP;
    END LOOP;

    -- do last batch
    IF c > 0 AND batch != 1
    THEN
      query := query ||
               ') AS m (geom)
                JOIN exposure.grid_mask AS z
                  ON m.geom && z.geom AND
                     ST_DWithin (z.geom, ST_Centroid (m.geom), ' || (sz / 2) || ')';

      EXECUTE query;
    END IF;

    RAISE NOTICE 'Done creating grid';

    -- add primary key
    EXECUTE 'ALTER TABLE exposure.' || tableName || ' ADD CONSTRAINT ' || tableName || '_pk PRIMARY KEY (id)';

    -- add index
    EXECUTE 'CREATE INDEX ' || tableName || '_geom_idx ON exposure.' || tableName || ' USING GiST (geom)';

    -- collect statistics
    EXECUTE 'ANALYZE VERBOSE exposure.' || tableName;

    PERFORM 'GRANT SELECT ON exposure.' || tableName || ' TO totus';
    PERFORM 'GRANT SELECT ON exposure.' || tableName || ' TO totus_ingester';
    PERFORM 'GRANT SELECT ON exposure.' || tableName || '_id_seq TO totus';
    PERFORM 'GRANT SELECT ON exposure.' || tableName || '_id_seq TO totus_ingester';
  ELSE
    RAISE NOTICE '%m grid table: % already exist', cellSize, tableName;
  END IF;

  RETURN;
END;
$_$
LANGUAGE 'plpgsql' VOLATILE STRICT
;
