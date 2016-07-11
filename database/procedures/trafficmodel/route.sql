SET search_path = trafficmodel, network, public;

--
-- SQL function to produce Traffic Model routes from multiple source to multiple target destinations.
-- It returns raw network edges with or without Traffic Model traffic assigned. No aggregation is
-- applied
--
DROP FUNCTION IF EXISTS get_attribute_value (VARCHAR(64), VARCHAR(64)[], NUMERIC[]);

-- binary search, attribute/value pairs must be sorted on attribute
CREATE FUNCTION get_attribute_value (attribute VARCHAR(64), attributes VARCHAR(64)[], "values" NUMERIC[])
RETURNS NUMERIC
AS
$_$
DECLARE
  i     INTEGER;
  mid   INTEGER;
  lower INTEGER; 
  upper INTEGER;
BEGIN
  lower := 1;
  upper := ARRAY_UPPER (attributes, 1);
  mid   := (lower + upper ) / 2;

  WHILE upper >= lower
  LOOP
    IF (attributes[mid] < attribute)
    THEN
      lower := mid + 1;
    ELSIF (attributes[mid] > attribute)
    THEN
      upper := mid - 1;
    ELSE
      RETURN values[mid];
    END IF;

    mid := (lower + upper ) / 2;
  END LOOP;

  RETURN NULL;
END;
$_$
LANGUAGE 'plpgsql' VOLATILE STRICT
;

DROP FUNCTION IF EXISTS route (NUMERIC [], NUMERIC [], NUMERIC [], NUMERIC [], VARCHAR(64), VARCHAR(64));
DROP FUNCTION IF EXISTS route (GEOMETRY [], GEOMETRY [], VARCHAR(64), VARCHAR(64));
DROP TYPE IF EXISTS TRAFFIC_EDGE;

CREATE TYPE TRAFFIC_EDGE AS (
  id               INTEGER,
  route_id         INTEGER,
  edge_id          INTEGER,
  sequence         INTEGER,
  road_name        VARCHAR(64),
  geom             GEOMETRY,
  AM_LkTime        NUMERIC,
  AM_LkVehHCV_ALL  NUMERIC,
  AM_LkVehHCV_COLD NUMERIC,
  AM_LkVehLV_ALL   NUMERIC,
  AM_LkVehLV_COLD  NUMERIC,
  AM_LkVehTotal    NUMERIC,
  IP_LkTime        NUMERIC,
  IP_LkVehHCV_ALL  NUMERIC,
  IP_LkVehHCV_COLD NUMERIC,
  IP_LkVehLV_ALL   NUMERIC,
  IP_LkVehLV_COLD  NUMERIC,
  IP_LkVehTotal    NUMERIC,
  PM_LkTime        NUMERIC,
  PM_LkVehHCV_ALL  NUMERIC,
  PM_LkVehHCV_COLD NUMERIC,
  PM_LkVehLV_ALL   NUMERIC,
  PM_LkVehLV_COLD  NUMERIC,
  PM_LkVehTotal    NUMERIC
);

CREATE FUNCTION route (startGeoms GEOMETRY[], endGeoms GEOMETRY[], routingMethod VARCHAR(64), costingOption VARCHAR(64))
RETURNS SETOF TRAFFIC_EDGE
AS
$_$
DECLARE
  query        TEXT;
  result       RECORD;
  trafficEdge     trafficmodel.TRAFFIC_EDGE;
  emptyEdge    trafficmodel.TRAFFIC_EDGE;
  searchExpand NUMERIC DEFAULT 0.09;
  id           INTEGER DEFAULT 1;
BEGIN
  query := '
      SELECT rp.route_id,
             rp.edge_id,
             rp.sequence,
             rp.road_name,
             rp.geom,
             ea.peak,
             ea.attributes,
             ea.values
        FROM (
          SELECT r.id AS route_id,
                 ne.gid AS edge_id,
                 ROW_NUMBER () OVER (PARTITION BY r.id) AS sequence,
                 ne.name AS road_name,
                 ne.the_geom AS geom
            FROM (
              SELECT ROW_NUMBER () OVER() AS id,
                     network.route (c.source, c.target, ' ||
                     quote_literal (routingMethod) || ', ' ||
                     quote_literal (costingOption) || ', ' ||
                     searchExpand || '::NUMERIC) AS path_result
                FROM (
                  SELECT network.closest_edge_node (ST_X(s.geom)::NUMERIC(12,8),
                                                    ST_Y(s.geom)::NUMERIC(12,8), ' ||
                                                    searchExpand || '::NUMERIC) AS source,
                         network.closest_edge_node (ST_X(e.geom)::NUMERIC(12,8),
                                                    ST_Y(e.geom)::NUMERIC(12,8), ' ||
                                                    searchExpand || '::NUMERIC) AS target
                    FROM (VALUES (''' || ARRAY_TO_STRING (startGeoms, '''::GEOMETRY),(''') || '''::GEOMETRY)) AS s (geom),
                         (VALUES (''' || ARRAY_TO_STRING (endGeoms, '''::GEOMETRY),(''') || '''::GEOMETRY)) AS e (geom)
                   ) AS c
               ) AS r
            JOIN network.edges AS ne
                 ON (r.path_result).edge_id = ne.gid
           WHERE (r.path_result).edge_id <> -1
           ) AS rp
   LEFT JOIN (
          SELECT edge_id,
                 peak,
                 trafficmodel.ARRAY_ACCUM (attribute) AS attributes,
                 trafficmodel.ARRAY_ACCUM (value) AS values
            FROM (             
              SELECT ln.network_edge_id AS edge_id,
                     ltd.peak,
                     ta.attribute,
                     SUM(CASE WHEN (td.value IS NULL) THEN 0 ELSE ln.fraction * td.value::NUMERIC END) AS value
                FROM trafficmodel.link_network AS ln
                JOIN trafficmodel.link_traffic_data AS ltd
                     ON ln.traffic_link_id = ltd.link_id
                JOIN trafficmodel.traffic_data AS td
                     ON ltd.data_id = td.id
                JOIN trafficmodel.traffic_attribute AS ta
                     ON td.attribute_id = ta.id
               WHERE ta.attribute IN (''LkTime'', ''LkVehHCV_ALL'', ''LkVehHCV_COLD'', ''LkVehLV_ALL'', ''LkVehLV_COLD'', ''LkVehTotal'')
            GROUP BY ln.network_edge_id, ltd.peak, ta.attribute
            ORDER BY ln.network_edge_id, ltd.peak, ta.attribute
               ) AS a
        GROUP BY edge_id, peak
           ) AS ea
             ON rp.edge_id = ea.edge_id
    ORDER BY route_id, sequence, peak';

  RAISE NOTICE 'query: %', query;

  -- initialise empty Traffic Model edge
  emptyEdge.id               = NULL;
  emptyEdge.route_id         = NULL;
  emptyEdge.edge_id          = NULL;
  emptyEdge.sequence         = NULL;
  emptyEdge.road_name        = NULL;
  emptyEdge.geom             = NULL; 
  emptyEdge.AM_LkTime        = NULL; 
  emptyEdge.AM_LkVehHCV_ALL  = NULL; 
  emptyEdge.AM_LkVehHCV_COLD = NULL; 
  emptyEdge.AM_LkVehLV_ALL   = NULL; 
  emptyEdge.AM_LkVehLV_COLD  = NULL; 
  emptyEdge.AM_LkVehTotal    = NULL; 
  emptyEdge.IP_LkTime        = NULL; 
  emptyEdge.IP_LkVehHCV_ALL  = NULL; 
  emptyEdge.IP_LkVehHCV_COLD = NULL; 
  emptyEdge.IP_LkVehLV_ALL   = NULL; 
  emptyEdge.IP_LkVehLV_COLD  = NULL; 
  emptyEdge.IP_LkVehTotal    = NULL; 
  emptyEdge.PM_LkTime        = NULL; 
  emptyEdge.PM_LkVehHCV_ALL  = NULL; 
  emptyEdge.PM_LkVehHCV_COLD = NULL; 
  emptyEdge.PM_LkVehLV_ALL   = NULL; 
  emptyEdge.PM_LkVehLV_COLD  = NULL; 
  emptyEdge.PM_LkVehTotal    = NULL; 

  FOR result IN EXECUTE query
  LOOP
    -- we're still on a previous Traffic Model route path edge, re-initialise
    IF (trafficEdge.route_id IS NULL AND trafficEdge.sequence IS NULL) OR 
       trafficEdge.route_id <> result.route_id OR
       (trafficEdge.route_id = result.route_id AND trafficEdge.sequence <> result.sequence)
    THEN
      trafficEdge := emptyEdge;
      
      trafficEdge.id        := id;
      trafficEdge.route_id  := result.route_id;
      trafficEdge.edge_id   := result.edge_id;
      trafficEdge.sequence  := result.sequence;
      trafficEdge.road_name := result.road_name;
      trafficEdge.geom      := result.geom;

      id := id + 1;
    END IF;

     -- first AM, then IP and lastly PM
    IF result.peak = 'AM'
    THEN
      trafficEdge.AM_LkTime        := trafficmodel.get_attribute_value ('LkTime', result.attributes, result.values);
      trafficEdge.AM_LkVehHCV_ALL  := trafficmodel.get_attribute_value ('LkVehHCV_ALL', result.attributes, result.values);
      trafficEdge.AM_LkVehHCV_COLD := trafficmodel.get_attribute_value ('LkVehHCV_COLD', result.attributes, result.values);
      trafficEdge.AM_LkVehLV_ALL   := trafficmodel.get_attribute_value ('LkVehLV_ALL', result.attributes, result.values);
      trafficEdge.AM_LkVehLV_COLD  := trafficmodel.get_attribute_value ('LkVehLV_COLD', result.attributes, result.values);
      trafficEdge.AM_LkVehTotal    := trafficmodel.get_attribute_value ('LkVehTotal', result.attributes, result.values);
    ELSIF result.peak = 'IP'
    THEN
      trafficEdge.IP_LkTime        := trafficmodel.get_attribute_value ('LkTime', result.attributes, result.values);
      trafficEdge.IP_LkVehHCV_ALL  := trafficmodel.get_attribute_value ('LkVehHCV_ALL', result.attributes, result.values);
      trafficEdge.IP_LkVehHCV_COLD := trafficmodel.get_attribute_value ('LkVehHCV_COLD', result.attributes, result.values);
      trafficEdge.IP_LkVehLV_ALL   := trafficmodel.get_attribute_value ('LkVehLV_ALL', result.attributes, result.values);
      trafficEdge.IP_LkVehLV_COLD  := trafficmodel.get_attribute_value ('LkVehLV_COLD', result.attributes, result.values);
      trafficEdge.IP_LkVehTotal    := trafficmodel.get_attribute_value ('LkVehTotal', result.attributes, result.values);
    ELSIF result.peak = 'PM'
    THEN
      trafficEdge.PM_LkTime        := trafficmodel.get_attribute_value ('LkTime', result.attributes, result.values);
      trafficEdge.PM_LkVehHCV_ALL  := trafficmodel.get_attribute_value ('LkVehHCV_ALL', result.attributes, result.values);
      trafficEdge.PM_LkVehHCV_COLD := trafficmodel.get_attribute_value ('LkVehHCV_COLD', result.attributes, result.values);
      trafficEdge.PM_LkVehLV_ALL   := trafficmodel.get_attribute_value ('LkVehLV_ALL', result.attributes, result.values);
      trafficEdge.PM_LkVehLV_COLD  := trafficmodel.get_attribute_value ('LkVehLV_COLD', result.attributes, result.values);
      trafficEdge.PM_LkVehTotal    := trafficmodel.get_attribute_value ('LkVehTotal', result.attributes, result.values);

      -- done with this Traffic Model edge
      RETURN NEXT trafficEdge;
    ELSIF result.peak IS NULL
    THEN
      -- return edge with no Traffic Model data assigned
      RETURN NEXT trafficEdge;
    END IF;
  END LOOP;

  RETURN;
END;
$_$
LANGUAGE 'plpgsql' VOLATILE STRICT
;

-- wrapper that constructs the source and target geometries and call above function
CREATE FUNCTION route (startx NUMERIC[], starty NUMERIC[], endx NUMERIC[], endy NUMERIC[], routingMethod VARCHAR(64), costingOption VARCHAR(64))
RETURNS SETOF TRAFFIC_EDGE
AS
$_$
DECLARE
  startGeoms GEOMETRY[];
  endGeoms   GEOMETRY[];
  i          INTEGER DEFAULT 0;
  query      TEXT;
  trafficEdge   TRAFFIC_EDGE;
  result     RECORD;
BEGIN
  -- check that list of start x and y positions match in length
  IF ARRAY_UPPER (startx, 1) <> ARRAY_UPPER (starty, 1)
  THEN
    RAISE EXCEPTION 'The number of start X coordinates: % and start Y coordinates: % do not match',
                    ARRAY_UPPER (startx, 1) + 1, ARRAY_UPPER (starty, 1) + 1;
  END IF;

  -- check that list of start x is not empty
  IF ARRAY_UPPER (startx, 1) < 0
  THEN
    RAISE EXCEPTION 'No start coordinates provided';
  END IF;

  -- check that list of end x and y positions match in length
  IF ARRAY_UPPER (endx, 1) <> ARRAY_UPPER (endy, 1)
  THEN
    RAISE EXCEPTION 'The number of end X coordinates: % and end Y coordinates: % do not match',
                    ARRAY_UPPER (endx, 1) + 1, ARRAY_UPPER (endy, 1) + 1;
  END IF;

  -- check that list of end x is not emptendy
  IF ARRAY_UPPER (endx, 1) < 0
  THEN
    RAISE EXCEPTION 'No end coordinates provided';
  END IF;

  -- will have valid list of start x and y coordinates
  -- construct list of start geometry
  FOR i IN SELECT GENERATE_SERIES (1, ARRAY_UPPER (startx, 1))
  LOOP
    IF startx[i] < -180 OR startx[i] > 180
    THEN
      RAISE EXCEPTION 'Invalid start longitude: % found at %', startx[i], i;
    END IF;

    IF starty[i] < -90 OR starty[i] > 90
    THEN
      RAISE EXCEPTION 'Invalid start latitude: % found at %', starty[i], i;
    END IF;

    startGeoms[i] := ST_GeomFromText ('POINT (' || startx[i] || ' ' || starty[i] || ')', 4326);
  END LOOP;
 
  -- construct list of end geometry
  FOR i IN SELECT GENERATE_SERIES (1, ARRAY_UPPER (endx, 1))
  LOOP
    IF endx[i] < -180 OR endx[i] > 180
    THEN
      RAISE EXCEPTION 'Invalid end longitude: % found at %', endx[i], i;
    END IF;

    IF endy[i] < -90 OR endy[i] > 90
    THEN
      RAISE EXCEPTION 'Invalid end latitude: % found at %', endy[i], i;
    END IF;

    endGeoms[i] := ST_GeomFromText ('POINT (' || endx[i] || ' ' || endy[i] || ')', 4326);
  END LOOP;

  FOR result IN 
    SELECT (m).id,
           (m).route_id,
           (m).edge_id,
           (m).sequence,
           (m).road_name,
           (m).geom,
           (m).AM_LkTime,
           (m).AM_LkVehHCV_ALL,
           (m).AM_LkVehHCV_COLD,
           (m).AM_LkVehLV_ALL,
           (m).AM_LkVehLV_COLD,
           (m).AM_LkVehTotal,
           (m).IP_LkTime,
           (m).IP_LkVehHCV_ALL,
           (m).IP_LkVehHCV_COLD,
           (m).IP_LkVehLV_ALL,
           (m).IP_LkVehLV_COLD,
           (m).IP_LkVehTotal,
           (m).PM_LkTime,
           (m).PM_LkVehHCV_ALL,
           (m).PM_LkVehHCV_COLD,
           (m).PM_LkVehLV_ALL,
           (m).PM_LkVehLV_COLD,
           (m).PM_LkVehTotal
      FROM trafficmodel.route (startGeoms, endGeoms, routingMethod, costingOption) AS m
  LOOP
    trafficEdge.id = result.id;
    trafficEdge.route_id = result.route_id;
    trafficEdge.edge_id = result.edge_id;
    trafficEdge.sequence = result.sequence;
    trafficEdge.road_name = result.road_name;
    trafficEdge.geom = result.geom;
    trafficEdge.AM_LkTime = result.AM_LkTime;
    trafficEdge.AM_LkVehHCV_ALL = result.AM_LkVehHCV_ALL;
    trafficEdge.AM_LkVehHCV_COLD = result.AM_LkVehHCV_COLD;
    trafficEdge.AM_LkVehLV_ALL = result.AM_LkVehLV_ALL;
    trafficEdge.AM_LkVehLV_COLD = result.AM_LkVehLV_COLD;
    trafficEdge.AM_LkVehTotal = result.AM_LkVehTotal;
    trafficEdge.IP_LkTime = result.IP_LkTime;
    trafficEdge.IP_LkVehHCV_ALL = result.IP_LkVehHCV_ALL;
    trafficEdge.IP_LkVehHCV_COLD = result.IP_LkVehHCV_COLD;
    trafficEdge.IP_LkVehLV_ALL = result.IP_LkVehLV_ALL;
    trafficEdge.IP_LkVehLV_COLD = result.IP_LkVehLV_COLD;
    trafficEdge.IP_LkVehTotal = result.IP_LkVehTotal;
    trafficEdge.PM_LkTime = result.PM_LkTime;
    trafficEdge.PM_LkVehHCV_ALL = result.PM_LkVehHCV_ALL;
    trafficEdge.PM_LkVehHCV_COLD = result.PM_LkVehHCV_COLD;
    trafficEdge.PM_LkVehLV_ALL = result.PM_LkVehLV_ALL;
    trafficEdge.PM_LkVehLV_COLD = result.PM_LkVehLV_COLD;
    trafficEdge.PM_LkVehTotal = result.PM_LkVehTotal;

    RETURN NEXT trafficEdge;
  END LOOP;

  RETURN;
END;
$_$
LANGUAGE 'plpgsql' VOLATILE STRICT
;
