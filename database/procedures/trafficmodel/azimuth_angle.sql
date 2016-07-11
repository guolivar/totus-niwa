SET search_path = trafficmodel, public;

DROP FUNCTION IF EXISTS azimuth_angle (GEOMETRY, GEOMETRY);

CREATE FUNCTION azimuth_angle (point1 GEOMETRY, point2 GEOMETRY)
RETURNS NUMERIC
AS
$_$
DECLARE
  azimuth NUMERIC;
BEGIN
  azimuth := ST_Azimuth (point1, point2)::NUMERIC;

  IF azimuth > pi()
  THEN
    RETURN azimuth - (2 * pi());
  ELSE
    RETURN azimuth;
  END IF;
END;
$_$
LANGUAGE 'plpgsql' STABLE STRICT;
