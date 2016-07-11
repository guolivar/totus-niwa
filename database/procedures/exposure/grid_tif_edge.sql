SET search_path = exposure, public;

DROP FUNCTION IF EXISTS grid_tif_edge (INTEGER, INTEGER, INTEGER, NUMERIC, NUMERIC);

CREATE FUNCTION grid_tif_edge (
  cellSize          INTEGER,
  roadCount         INTEGER,
  inclusionDistance INTEGER,
  dispersionFactor  NUMERIC,
  dataYear          NUMERIC
)
RETURNS VOID
AS
$_$
DECLARE
  tableName    VARCHAR(32);
  degreeM  NUMERIC;
  query    TEXT;
  centerY  NUMERIC; 
  distance NUMERIC;
BEGIN
  -- 1 degree in meters (approximate) at equator, scale it by cosine 
  -- with increasing latitude
  degreeM := 111319.9; 

  tableName := 'grid_' || cellSize::VARCHAR || 'm_tif_edge';

  query := 'SELECT MIN (ST_Y(ST_Centroid(geom))) + MAX (ST_Y(ST_Centroid(geom))) / 2 
              FROM exposure.grid_' || cellSize::VARCHAR || 'm';

  EXECUTE query INTO centerY;

  IF centerY IS NULL
  THEN
    RAISE EXCEPTION 'Unable to calculate center Y from grid geometry, please check exposure.grid_%m', cellSize::VARCHAR;
  END IF;

  -- convert edge inclusion distance to approximate degrees
  distance := inclusionDistance / (degreeM * COS (RADIANS (centerY)));

  EXECUTE 'DROP TABLE IF EXISTS exposure.' || tableName;

  EXECUTE 'CREATE TABLE exposure.' || tableName || ' (
             grid_id INTEGER NOT NULL,
             edge_id INTEGER NOT NULL,
             tif     NUMERIC NOT NULL,
             rank    INTEGER NOT NULL,
             year    SMALLINT NOT NULL
           )';

  EXECUTE 'INSERT INTO exposure.' || tableName || ' (grid_id, edge_id, tif, rank, year)
           SELECT grid_id,
                  edge_id,
                  volume * length * POW (distance * ' || degreeM || ' * ' || COS (RADIANS (centerY)) || ', ' || dispersionFactor || ') AS tif, 
                  rank,
                  year
             FROM (
               SELECT g.id AS grid_id,
                      en.network_id AS edge_id,
                      en.am_vol + en.ip_vol + en.pm_vol AS volume,
                      ST_Length2D_spheroid(en.geom,''SPHEROID["WGS_1984",6378137,298.257223563]'')/1000 as length,
                      ST_Distance (ST_Centroid (g.geom), en.geom) AS distance,
                      RANK () OVER (PARTITION BY g.id ORDER BY ST_Distance (ST_Centroid (g.geom), en.geom)) AS rank,
                      ' || dataYear::VARCHAR || ' AS year
                 FROM exposure.grid_' || cellSize::VARCHAR || 'm AS g
                 JOIN trafficmodel.network_edge AS en
                      ON ST_Expand (g.geom, 0.0201397760129886) && en.geom AND
                         ST_DWithin (ST_Centroid (g.geom), en.geom, ' || distance || ') = FALSE
               WHERE en.year = ' || dataYear::VARCHAR || '
             ) AS c 
            WHERE rank < ' || roadCount;

  EXECUTE 'ALTER TABLE exposure.' || tableName || ' ADD CONSTRAINT ' || tableName || '_fk
             FOREIGN KEY (grid_id) REFERENCES exposure.grid_' || cellSize::VARCHAR || 'm(id)';

  EXECUTE 'CREATE INDEX ' || tableName || '_idx ON exposure.' || tableName || ' USING BTREE (grid_id)';

  EXECUTE 'ANALYZE VERBOSE exposure.' || tableName;

  PERFORM 'GRANT SELECT ON exposure.' || tableName || ' TO totus';
  PERFORM 'GRANT SELECT ON exposure.' || tableName || ' TO totus_ingester';
  PERFORM 'GRANT SELECT ON exposure.' || tableName || '_id_seq TO totus';
  PERFORM 'GRANT SELECT ON exposure.' || tableName || '_id_seq TO totus_ingester';

  RETURN;
END;
$_$
LANGUAGE 'plpgsql' VOLATILE STRICT;
