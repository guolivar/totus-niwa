SET search_path = exposure, public;

-- function to produce base map no2
DROP FUNCTION IF EXISTS base_no2 ();

CREATE FUNCTION base_no2 ()
RETURNS SETOF GRID_NO2
AS
$_$
DECLARE
  query TEXT;
  result RECORD;
  no2 exposure.GRID_NO2;
  gridSize INTEGER DEFAULT 1000;
BEGIN
  -- NO2 (ug/m3) = 0.00171 TIF + 11.9
  -- on 1000 m grid
  query := 'SELECT (n).id, (n).tif, (n).no2, (n).year, (n).geom
              FROM (
                SELECT exposure.model_no2 (0.00171, 11.9, ' || gridSize || ', 10000, -0.65, 10, FALSE, t.year) AS n
                 FROM (
                    SELECT DISTINCT year AS year
                      FROM trafficmodel.link_traffic_data
                 ) AS t
            ) AS tmp';

  FOR result IN EXECUTE query
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
