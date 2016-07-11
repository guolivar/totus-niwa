-- SQL functions to return Traffic Model area summary which includes:
-- area_aggregate: all edges with Traffic Model trip information assigned (geometry)
--                 area Traffic Model attributes aggregated
-- area_flux:      in/out area Traffic Model attribute flux

-- TODO:
-- two versions: one polygon, one ATM2 zone number (add ATM2 as WFS feed or WMS feed)
--

-- pass in polygon as spatial filter
--
SET search_path = trafficmodel, public;

DROP FUNCTION IF EXISTS area_aggregate (TEXT);
DROP TYPE IF EXISTS AREA_AGGREGATE;

CREATE TYPE AREA_AGGREGATE AS (
  geom       GEOMETRY,
  attributes VARCHAR(64)[],
  aggregates VARCHAR(256)[]
);

CREATE FUNCTION area_aggregate (TEXT)
RETURNS AREA_AGGREGATE
AS
$_$
DECLARE
  spatial_filter ALIAS FOR $1;
  query          TEXT;
  result         RECORD;
  attrs          VARCHAR(64)[];
  aggrs          VARCHAR(256)[];
  summary        TRAFFICMODEL.AREA_AGGREGATE;
  geomText       TEXT[];
  prevId         INTEGER;
  l              INTEGER;
  i              INTEGER;
BEGIN
  -- sanity check on spatial filter supplied
  IF spatial_filter !~ '^(MULTIP|P)OLYGON' OR spatial_filter ~ '(SELECT|;|DROP|UPDATE)'
  THEN
    RAISE EXCEPTION 'Invalid spatial filter supplied: %', spatial_filter;
  END IF;

  -- query all trafficmodel network (edge) links inside spatial area
  -- and extract it's trafficmodel link traffic attributes and scaling
  -- factor
  query := 'SELECT ta.id,
                   ta.description AS attribute,
                   td.value,
                   ST_AsText (ne.the_geom) AS geom,
                   ln.fraction 
              FROM trafficmodel.link_network AS ln
              JOIN trafficmodel.link_traffic_data AS ltd
                   ON ln.traffic_link_id = ltd.link_id
              JOIN trafficmodel.traffic_data AS td
                   ON ltd.data_id = td.id
              JOIN trafficmodel.traffic_attribute AS ta
                   ON td.attribute_id = ta.id
              JOIN network.edges AS ne
                   ON ln.network_edge_id = ne.gid,
                   ST_GeomFromText (' || quote_literal (spatial_filter) || ', 4326) AS filter (geom)
             WHERE ne.the_geom && filter.geom AND
                   ST_Within (ne.the_geom, filter.geom) AND
                   ST_IsValid (filter.geom) AND
                   ta.attribute <> ' || quote_literal ('lanes') || '
          ORDER BY ta.id';

  prevId := -9999;
  l      := 0;
  i      := 0;

  attrs[l] := '';
  aggrs[l] := '0';

  FOR result IN EXECUTE query
  LOOP
    IF prevId <> -9999 AND prevId <> result.id
    THEN
      -- result set is ordered by attribute type, when attribute type id changes advance to next attribute
      l := l + 1;

      -- init to zero
      aggrs[l] := '0';
    END IF;

    -- attribute name
    attrs[l]    := result.attribute;
    -- accumulate scaled value
    aggrs[l]    := ROUND(aggrs[l]::NUMERIC + (result.value::NUMERIC * result.fraction)::NUMERIC, 2)::VARCHAR(256);
    -- capture coordinate list in line string
    geomText[i] := REGEXP_REPLACE (result.geom, E'LINESTRING\((\.*)\)', E'\\1', '');

    prevId := result.id;
    i := i + 1;
  END LOOP;


  summary.geom       := ST_MLineFromText (E'MULTILINESTRING (' || ARRAY_TO_STRING (geomText, ', ') || E')', 4326);
  summary.attributes := attrs;
  summary.aggregates := aggrs;

  RETURN summary;
END;
$_$
LANGUAGE 'plpgsql' VOLATILE STRICT
;

DROP FUNCTION IF EXISTS area_flux (TEXT);
DROP TYPE IF EXISTS AREA_FLUX;

CREATE TYPE AREA_FLUX AS (
  geom        GEOMETRY,
  attributes  VARCHAR(64)[],
  influx      VARCHAR(256)[],
  outflux     VARCHAR(256)[]
);

CREATE FUNCTION area_flux (TEXT)
RETURNS AREA_FLUX
AS
$_$
DECLARE
  spatial_filter ALIAS FOR $1;
  query          TEXT;
  result         RECORD;
  attrs          VARCHAR(64)[];
  influx         VARCHAR(256)[];
  outflux        VARCHAR(256)[];
  flux           TRAFFICMODEL.AREA_FLUX;
  geomText       TEXT[];
  prevId         INTEGER;
  l              INTEGER;
  i              INTEGER;
BEGIN
  -- sanity check on spatial filter supplied
  IF spatial_filter !~ '^(MULTIP|P)OLYGON' OR spatial_filter ~ '(SELECT|;|DROP|UPDATE)'
  THEN
    RAISE EXCEPTION 'Invalid spatial filter supplied: %', spatial_filter;
  END IF;

  -- query all trafficmodel network (edge) links inside spatial area
  -- and extract it's trafficmodel link traffic attributes and scaling
  -- factor
  query := 'SELECT ta.id,
                   ta.description AS attribute,
                   td.value,
                   ST_AsText (ne.the_geom) AS geom,
                   ln.fraction,
                   CASE WHEN ST_Within (ST_SetSrid (ST_MakePoint (x1, y1), 4326), filter.geom)
                        THEN ' || quote_literal ('outflux') || '
                        ELSE ' || quote_literal ('influx')  || '
                   END AS flux_type
              FROM trafficmodel.link_network AS ln
              JOIN trafficmodel.link_traffic_data AS ltd
                   ON ln.traffic_link_id = ltd.link_id
              JOIN trafficmodel.traffic_data AS td
                   ON ltd.data_id = td.id
              JOIN trafficmodel.traffic_attribute AS ta
                   ON td.attribute_id = ta.id
              JOIN network.edges AS ne
                   ON ln.network_edge_id = ne.gid,
                   ST_GeomFromText (' || quote_literal (spatial_filter) || ', 4326) AS filter (geom)
             WHERE ne.the_geom && filter.geom AND
                   ST_Crosses (ne.the_geom, filter.geom) AND
                   ST_IsValid (filter.geom) AND
                   ta.attribute <> ' || quote_literal ('lanes') || '
          ORDER BY ta.id';

  prevId := -9999;
  l      := 0;
  i      := 0;

  attrs[l]   := '';
  influx[l]  := '0';
  outflux[l] := '0';

  FOR result IN EXECUTE query
  LOOP
    IF prevId <> -9999 AND prevId <> result.id
    THEN
      -- result set is ordered by attribute type, when attribute type id changes advance to next attribute
      l := l + 1;

      -- init to zero
      influx[l]  := '0';
      outflux[l] := '0';
    END IF;

    -- attribute name
    attrs[l] := result.attribute;

    -- accumulate scaled value for either in-flux or out-flux
    IF result.flux_type = 'influx'
    THEN
      influx[l] := ROUND(influx[l]::NUMERIC + (result.value::NUMERIC * result.fraction)::NUMERIC, 2)::VARCHAR(256);
    ELSE
      outflux[l] := ROUND(outflux[l]::NUMERIC + (result.value::NUMERIC * result.fraction)::NUMERIC, 2)::VARCHAR(256);
    END IF;

    -- capture coordinate list in line string
    geomText[i] := REGEXP_REPLACE (result.geom, E'LINESTRING\((\.*)\)', E'\\1', '');

    prevId := result.id;
    i := i + 1;
  END LOOP;

  flux.geom       := ST_MLineFromText (E'MULTILINESTRING (' || ARRAY_TO_STRING (geomText, ', ') || E')', 4326);
  flux.attributes := attrs;
  flux.influx     := influx;
  flux.outflux    := outflux;

  RETURN flux;
END;
$_$
LANGUAGE 'plpgsql' VOLATILE STRICT
;
