SET search_path = trafficmodel, network, public;

--
-- SQL function to aggregate Traffic Model results for a set of routes for a specific traffic peak
-- Basic version, aggregates all attributes, no partial, no route geometry
--
DROP FUNCTION IF EXISTS trafficmodel.route_aggregator_basic (GEOMETRY [], GEOMETRY [], CHAR(2), VARCHAR(64));
DROP FUNCTION IF EXISTS trafficmodel.route_aggregator (GEOMETRY [], GEOMETRY [], CHAR(2), VARCHAR(64));
DROP TYPE IF EXISTS trafficmodel.PEAK_TRAFFIC_AGGR;
DROP AGGREGATE IF EXISTS trafficmodel.array_accum (anyelement);

CREATE TYPE PEAK_TRAFFIC_AGGR AS (
  peak       CHAR(2),
  attributes VARCHAR(64)[],
  aggregates VARCHAR(256)[],
  trafficGeom    GEOMETRY,
  routeGeom   GEOMETRY
);

CREATE AGGREGATE array_accum (
  sfunc = array_append,
  basetype = anyelement,
  stype = anyarray,
  initcond = '{}'
);

CREATE FUNCTION route_aggregator_basic (startGeoms GEOMETRY [], endGeoms GEOMETRY [], trafficPeak CHAR(2), routeMethod VARCHAR(64))
RETURNS PEAK_TRAFFIC_AGGR
AS
$_$
DECLARE
  query    TEXT;
  result   RECORD;
  aggr trafficmodel.PEAK_TRAFFIC_AGGR;
  i        INTEGER;
  l        INTEGER;
  k        INTEGER;
  m        INTEGER;
  geomText TEXT[];
BEGIN
  -- validate that geometries are POINTs

  -- closest_node for each start geomtry
  -- closest_node for each end geometry
  -- route from each start node to each end node
  -- aggregate results
  -- return geometry collection of all edges routed

  IF routeMethod NOT IN ('dijkstra', 'astar', 'shootingstar')
  THEN
    RAISE EXCEPTION 'Invalid routing method supplied: %, not ''dijkstra'', ''astar'' or ''shootingstar''', routeMethod;
  END IF;

  query := 'SELECT ltd.peak, ta.attribute AS type,
                   SUM(ln.fraction * td.value::NUMERIC) AS value,
                   trafficmodel.ARRAY_ACCUM (ST_AsText (ne.the_geom)) AS geoms
              FROM (
                SELECT network.route (c.source, c.target, ' ||
                       quote_literal (routeMethod) || ', ''distance'', 0.09) AS path_result
                  FROM (
                   SELECT network.closest_edge_node (ST_X(s.geom)::NUMERIC(12,8),
                                                     ST_Y(s.geom)::NUMERIC(12,8),
                                                     0.09::NUMERIC(12,8)) AS source,
                          network.closest_edge_node (ST_X(e.geom)::NUMERIC(12,8),
                                                     ST_Y(e.geom)::NUMERIC(12,8),
                                                     0.09::NUMERIC(12,8)) AS target
                     FROM (VALUES (''' || ARRAY_TO_STRING (startGeoms, '''::GEOMETRY),(''') || '''::GEOMETRY)) AS s (geom),
                          (VALUES (''' || ARRAY_TO_STRING (endGeoms, '''::GEOMETRY),(''') || '''::GEOMETRY)) AS e (geom)
                 ) AS c
              ) AS r
              JOIN network.edges AS ne
                   ON (r.path_result).edge_id = ne.gid
              JOIN trafficmodel.link_network AS ln
                   ON (r.path_result).edge_id = ln.network_edge_id
              JOIN trafficmodel.link_traffic_data AS ltd
                   ON ln.traffic_link_id = ltd.link_id
              JOIN trafficmodel.traffic_data AS td
                   ON ltd.data_id = td.id
              JOIN trafficmodel.traffic_attribute AS ta
                   ON td.attribute_id = ta.id
             WHERE (r.path_result).edge_id <> -1
               AND ta.attribute            <> ''lanes'' 
               AND ltd.peak                = ' || quote_literal (trafficPeak) || '
          GROUP BY ltd.peak, ta.attribute
          ORDER BY ltd.peak, ta.attribute';
 
  l := 0;

  FOR result IN EXECUTE query
  LOOP
    aggr.peak          := result.peak;
    aggr.attributes[l] := result.type;
    aggr.aggregates[l] := result.value;

    IF l = 0
    THEN
      -- assign geometry only once
      geomText := result.geoms;
    END IF;

    l := l + 1;
  END LOOP;

  -- assign trafficmodel geom
  FOR k IN SELECT GENERATE_SERIES (0, ARRAY_UPPER (geomText, 1))
  LOOP
    geomText[k] := REGEXP_REPLACE (geomText[k], E'LINESTRING\((\.*)\)', E'\\1', '');
  END LOOP;

  aggr.trafficgeom := ST_MLineFromText (E'MULTILINESTRING (' || ARRAY_TO_STRING (geomText, ', ') || E')', 4326);
  RETURN aggr;
END;
$_$
LANGUAGE 'plpgsql' VOLATILE STRICT
;

--
-- SQL function to aggregate Traffic Model results for a set of same routes for AM, IM and PM traffic peak
-- Basic version, aggregates all AM, IM, PM peaks for all attributes, no partial, no route geometry
--
DROP FUNCTION IF EXISTS route_aggregator_basic (GEOMETRY [], GEOMETRY [], VARCHAR(64));
DROP FUNCTION IF EXISTS route_aggregator (GEOMETRY [], GEOMETRY [], VARCHAR(64));
DROP TYPE IF EXISTS ROUTE_AGGR;
DROP TYPE IF EXISTS TRAFFIC_AGGR;

CREATE TYPE TRAFFIC_AGGR AS (
  peak       CHAR(2),
  attributes VARCHAR(64)[],
  aggregates VARCHAR(256)[]
);

CREATE TYPE ROUTE_AGGR AS (
  trafficResults TRAFFIC_AGGR[4],
  trafficGeom    GEOMETRY,
  routeGeom   GEOMETRY
);

CREATE FUNCTION route_aggregator_basic (startGeoms GEOMETRY [], endGeoms GEOMETRY [], routeMethod VARCHAR(64))
RETURNS ROUTE_AGGR
AS
$_$
DECLARE
  query    TEXT;
  result   RECORD;
  aggr     trafficmodel.ROUTE_AGGR;
  trafficAggr trafficmodel.TRAFFIC_AGGR;
  i        INTEGER;
  l        INTEGER;
  k        INTEGER;
  m        INTEGER;
  prevPeak CHAR(2);
  geomText VARCHAR(256)[];
BEGIN
  -- validate that geometries are POINTs

  -- closest_node for each start geomtry
  -- closest_node for each end geometry
  -- route from each start node to each end node
  -- aggregate results
  -- return geometry collection of all edges routed

  IF routeMethod NOT IN ('dijkstra', 'astar', 'shootingstar')
  THEN
    RAISE EXCEPTION 'Invalid routing method supplied: %, not ''dijkstra'', ''astar'' or ''shootingstar''', routeMethod;
  END IF;

  query := 'SELECT ltd.peak, ta.attribute AS type,
                   SUM(ln.fraction * td.value::NUMERIC) AS value,
                   trafficmodel.ARRAY_ACCUM (ST_AsText (ne.the_geom)) AS geoms
              FROM (
                SELECT network.route (c.source, c.target, ' ||
                       quote_literal (routeMethod) || ', ''distance'', 0.09) AS path_result
                  FROM (
                   SELECT network.closest_edge_node (ST_X(s.geom)::NUMERIC(12,8),
                                                     ST_Y(s.geom)::NUMERIC(12,8),
                                                     0.09::NUMERIC(12,8)) AS source,
                          network.closest_edge_node (ST_X(e.geom)::NUMERIC(12,8),
                                                     ST_Y(e.geom)::NUMERIC(12,8),
                                                     0.09::NUMERIC(12,8)) AS target
                     FROM (VALUES (''' || ARRAY_TO_STRING (startGeoms, '''::GEOMETRY),(''') || '''::GEOMETRY)) AS s (geom),
                          (VALUES (''' || ARRAY_TO_STRING (endGeoms, '''::GEOMETRY),(''') || '''::GEOMETRY)) AS e (geom)
                 ) AS c
              ) AS r
              JOIN network.edges AS ne
                   ON (r.path_result).edge_id = ne.gid
              JOIN trafficmodel.link_network AS ln
                   ON (r.path_result).edge_id = ln.network_edge_id
              JOIN trafficmodel.link_traffic_data AS ltd
                   ON ln.traffic_link_id = ltd.link_id
              JOIN trafficmodel.traffic_data AS td
                   ON ltd.data_id = td.id
              JOIN trafficmodel.traffic_attribute AS ta
                   ON td.attribute_id = ta.id
             WHERE (r.path_result).edge_id <> -1 AND
                   ta.attribute            <> ''lanes''
          GROUP BY ltd.peak, ta.attribute
          ORDER BY ltd.peak, ta.attribute';
 
  i := 0;
  l := 0;
  k := 0;
  prevPeak := '';

  FOR result IN EXECUTE query
  LOOP
    IF prevPeak <> '' AND prevPeak <> result.peak
    THEN
      l := 0;
      -- assign peak data
      aggr.trafficResults[i] = trafficAggr;
      -- next peak
      i := i + 1;
    END IF;
    
    trafficAggr.peak          := result.peak;
    trafficAggr.attributes[l] := result.type;
    trafficAggr.aggregates[l] := result.value;

    IF i = 0 AND l = 0
    THEN
      -- assign geometry only once
      geomText := result.geoms;
    END IF;

    l := l + 1;
    prevPeak := result.peak;
  END LOOP;

  -- assign trafficmodel geom
  FOR k IN SELECT GENERATE_SERIES (0, ARRAY_UPPER (geomText, 1))
  LOOP
    geomText[k] := REGEXP_REPLACE (geomText[k], E'LINESTRING\((\.*)\)', E'\\1', '');
  END LOOP;

  aggr.trafficgeom := ST_MLineFromText (E'MULTILINESTRING (' || ARRAY_TO_STRING (geomText, ', ') || E')', 4326);
  RETURN aggr;
END;
$_$
LANGUAGE 'plpgsql' VOLATILE STRICT
;

-- SQL function to aggregate Traffic Model results for a set of routes
--
CREATE FUNCTION route_aggregator (startGeoms GEOMETRY [], endGeoms GEOMETRY [], routeMethod VARCHAR(64))
RETURNS ROUTE_AGGR
AS
$_$
DECLARE
  pathQuery    TEXT;
  trafficQuery    TEXT;
  query        TEXT;
  pathResult   RECORD;
  trafficResult   RECORD;
  edgePath     INTEGER[];
  nodePath     INTEGER[];
  i            INTEGER;
  j            INTEGER;
  l            INTEGER;
  k            INTEGER;
  m            INTEGER;
  prevPeak     CHAR(2);
  prevType     VARCHAR(64);
  aggr         trafficmodel.ROUTE_AGGR;
  trafficAggr     trafficmodel.TRAFFIC_AGGR;
  totalEmme    trafficmodel.TRAFFIC_AGGR;
  prevEmme     trafficmodel.TRAFFIC_AGGR;
  adjustStart  BOOLEAN DEFAULT false;
  adjustEnd    BOOLEAN DEFAULT false; 
BEGIN
  -- validate that geometries are POINTs

  -- closest_node for each start geomtry
  -- closest_node for each end geometry
  -- route from each start node to each end node

  -- aggregate results
  -- return geometry collection of all edges routed
  -- and one for trafficmodel edges

  -- TODO: scale start/end edge's Traffic Model scaling fraction to account for house half way
  --       down road, trafficmodel cost will differ
  --       add these if they have been missed on route

  IF routeMethod NOT IN ('dijkstra', 'astar', 'shootingstar')
  THEN
    RAISE EXCEPTION 'Invalid routing method supplied: %, not ''dijkstra'', ''astar'' or ''shootingstar''', routeMethod;
  END IF;

  IF ARRAY_UPPER (startGeoms, 1) IS NULL
  THEN
    RAISE EXCEPTION 'No start geometries provided to route from';
  END IF;

  IF ARRAY_UPPER (endGeoms, 1) IS NULL
  THEN
    RAISE EXCEPTION 'No end geometries provided to route to';
  END IF;

  -- FIXME:
  -- get paths first
  -- loop through them
  -- query their traffic attributes
  -- aggregate these
  -- compensate for start/end partials

  -- TODO:
  -- add geometry

  pathQuery := 'SELECT r.sourceNodeId,
                       r.targetNodeId,
                       (r.path_result).vertex_id AS nodeId,
                       (r.path_result).edge_id   AS edgeId,
                       r.sourceGeom,
                       r.targetGeom,
                       e.the_geom 
                  FROM (
                    SELECT (c.source).nodeId AS sourceNodeId,
                           (c.target).nodeId AS targetNodeId,
                           c.sourceGeom,
                           c.targetGeom,
                           network.route (c.source, c.target, ' ||
                             quote_literal (routeMethod) || ', ''distance'', 0.09) AS path_result

                    FROM (
                       SELECT network.closest_edge_node (ST_X(s.geom)::NUMERIC(12,8),
                                                         ST_Y(s.geom)::NUMERIC(12,8),
                                                         0.09::NUMERIC(12,8)) AS source,
                              network.closest_edge_node (ST_X(t.geom)::NUMERIC(12,8),
                                                         ST_Y(t.geom)::NUMERIC(12,8),
                                                         0.09::NUMERIC(12,8)) AS target,
                              s.geom AS sourceGeom,
                              t.geom AS targetGeom
                         FROM (VALUES (''' || ARRAY_TO_STRING (startGeoms, '''::GEOMETRY),(''') || '''::GEOMETRY)) AS s (geom),
                              (VALUES (''' || ARRAY_TO_STRING (endGeoms, '''::GEOMETRY),(''') || '''::GEOMETRY)) AS t (geom)
                     ) AS c
                  ) AS r
             LEFT JOIN network.edges AS e
                       ON (r.path_result).edge_id = e.gid';
     
  trafficQuery := 'SELECT ltd.peak, ta.attribute AS type, (ln.fraction * td.value::NUMERIC) AS value,
                       ln.network_edge_id AS trafficEdgeId
                  FROM trafficmodel.link_network AS ln
                  JOIN trafficmodel.link_traffic_data AS ltd
                       ON ln.traffic_link_id = ltd.link_id
                  JOIN trafficmodel.traffic_data AS td
                       ON ltd.data_id = td.id
                  JOIN trafficmodel.traffic_attribute AS ta
                       ON td.attribute_id = ta.id AND
                       ta.attribute  <> ''lanes''';
  
  -- init first AM value
  trafficAggr.aggregates[0] := '0';

  FOR pathResult IN EXECUTE pathQuery
  LOOP
    i := 0;
    j := 0;
    l := 0;

    -- end of path is signaled by edge id of -1
    IF pathResult.edgeId = -1
    THEN
      -- end of current path
           
      -- check that we did have a path
      IF ARRAY_LENGTH (edgePath, 1) <> -1
      THEN
        -- fetch all of the paths traffic attributes sorted by peak and type aggregated as array of arrays
        query := trafficQuery || '
                 JOIN (
                  VALUES (' || ARRAY_TO_STRING (edgePath, '),(') || ')) AS ep (edgeId) 
                        ON ln.network_edge_id = ep.edgeId
                ORDER BY ltd.peak, ta.attribute';

        prevPeak := '';
        prevType := '';

        -- execute
        FOR trafficResult IN EXECUTE query
        LOOP
          -- aggregate result
          IF prevPeak <> '' AND prevPeak <> trafficResult.peak
          THEN
            -- init total Traffic Model the first time
            IF totalEmme IS NULL
            THEN
              FOR k IN SELECT GENERATE_SERIES (0, ARRAY_UPPER(trafficAggr.attributes, 1))
              LOOP  
                totalEmme.peak          := 'AD';
                totalEmme.attributes[k] := trafficAggr.attributes[k];
                totalEmme.aggregates[k] := '0.0';
              END LOOP;
            END IF;

            -- init previous Emme
            IF prevEmme IS NULL
            THEN
              FOR k IN SELECT GENERATE_SERIES (0, ARRAY_UPPER(trafficAggr.attributes, 1))
              LOOP
                prevEmme.attributes[k] := trafficAggr.attributes[k];
                prevEmme.aggregates[k] := '0.0';
              END LOOP;

              FOR m IN SELECT GENERATE_SERIES (0, 3)
              LOOP
                aggr.trafficResults[m] = prevEmme;
              END LOOP;
            END IF;
 
            prevEmme = aggr.trafficResults[j];

            -- sanity check to assert sort order of traffic peaks
            IF prevEmme.peak <> trafficAggr.peak
            THEN
              RAISE EXCEPTION 'Cannot aggregate with different peaks: % <> %', prevEmme.peak, trafficAggr.peak;
            END IF;

            FOR k IN SELECT GENERATE_SERIES (0, ARRAY_UPPER(trafficAggr.attributes, 1))
            LOOP
              -- sanity check to assert sort order of traffic attributes
              IF prevEmme.attributes[k] <> trafficAggr.attributes[k]
              THEN
                RAISE EXCEPTION 'Cannot aggregate with different attributes % <> %', 
                                prevEmme.attributes[k], trafficAggr.attributes[k];
              END IF;

              -- trafficmodel total
              totalEmme.aggregates[k] := (totalEmme.aggregates[k]::NUMERIC + trafficAggr.aggregates[k]::NUMERIC)::VARCHAR(255);

              -- add previous trafficmodel results
              trafficAggr.aggregates[k] := (prevEmme.aggregates[k]::NUMERIC + trafficAggr.aggregates[k]::NUMERIC)::VARCHAR(255);
            END LOOP;

            aggr.trafficResults[j] := trafficAggr;
            trafficAggr            := NULL;

            -- init first value
            trafficAggr.aggregates[0] := '0';

            -- advance to next peak
            j := j + 1;

            IF j > 3
            THEN
              RAISE EXCEPTION 'Cannot have more than 3 traffic peaks';
            END IF;

            -- reset attributes
            l := 0;

            -- init value aggregate
            trafficAggr.aggregates[l] := '0';
          END IF;

          IF prevPeak = trafficResult.peak AND prevType <> '' AND prevType <> trafficResult.type
          THEN
            -- advance no next attribute for peak
            l := l + 1;

            -- init value aggregate 
            trafficAggr.aggregates[l] = 0;
          END IF;

          -- accumulate trafficmodel cost for edges in path
          trafficAggr.peak          := trafficResult.peak;
          trafficAggr.attributes[l] := trafficResult.type;
          trafficAggr.aggregates[l] := (trafficAggr.aggregates[l]::NUMERIC + trafficResult.value)::VARCHAR(256);

          prevPeak := trafficResult.peak;
          prevType := trafficResult.type;

          -- check first and last trafficEdgeId
          IF trafficResult.trafficEdgeId = edgePath[0]
          THEN
            adjustStart = true; 
          END IF;

          IF trafficResult.trafficEdgeId = edgePath[ARRAY_UPPER(edgePath, 1)]
          THEN
            adjustEnd = true;
          END IF;
        END LOOP;

        -- TODO: adjust start/end costs

        -- assign last trafficmodel 
        prevEmme = aggr.trafficResults[j];

        -- sanity check to assert sort order of traffic peaks
        IF prevEmme.peak <> trafficAggr.peak
        THEN
          RAISE EXCEPTION 'Cannot aggregate with different peaks: % <> %', prevEmme.peak, trafficAggr.peak;
        END IF;

        FOR k IN SELECT GENERATE_SERIES (0, ARRAY_UPPER(trafficAggr.attributes, 1))
        LOOP
          -- sanity check to assert sort order of traffic attributes
          IF prevEmme.attributes[k] <> trafficAggr.attributes[k]
          THEN
            RAISE EXCEPTION 'Cannot aggregate with different attributesL % <> %', 
                            prevEmme.attributes[k], trafficAggr.attributes[k];
          END IF;

          -- trafficmodel total
          totalEmme.aggregates[k] := (totalEmme.aggregates[k]::NUMERIC + trafficAggr.aggregates[k]::NUMERIC)::VARCHAR(255);

          -- add previous trafficmodel results
          trafficAggr.aggregates[k] := (prevEmme.aggregates[k]::NUMERIC + trafficAggr.aggregates[k]::NUMERIC)::VARCHAR(255);
        END LOOP;

        aggr.trafficResults[j] := trafficAggr;
        trafficAggr            := NULL;

        -- init first value
        trafficAggr.aggregates[0] := '0';

        -- assign total trafficmodel result
        j := j + 1;       

        aggr.trafficResults[j] := totalEmme;

        -- check if source and target edges were inserted, if not could be that start or end node was used
        -- but route start was along side edge, fetch this edges traffic information, but scale it by
        -- proportion of point along side edge and create partial geometry

        -- if these edges were wholly inserted and needed not be, remove it's trafficmodel cost and apply
        -- it as a fraction

        -- clear out path
        edgePath := NULL;

        i := 0;
      END IF;
    ELSE
      edgePath[i] := pathResult.edgeId;
      nodePath[i] := pathResult.nodeId;

      i := i + 1;
    END IF;
  END LOOP;

  RETURN aggr;
END;
$_$
LANGUAGE 'plpgsql' VOLATILE STRICT
;
