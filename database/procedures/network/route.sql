-- route: SQL wrapper function to PGRouting function
-- pass in non-zero filterExpand to filter input edges considered for routing
-- by expanding bounds of the source and target exploration nodes on network

SET search_path = network, public;

DROP FUNCTION IF EXISTS route (ROUTE_EDGE, ROUTE_EDGE, VARCHAR(64), VARCHAR(32), NUMERIC(9,8));

CREATE FUNCTION route (
  source       ROUTE_EDGE,
  target       ROUTE_EDGE,
  routeMethod  VARCHAR(64),
  costOption   VARCHAR(32),
  filterExpand NUMERIC(9,8)
)
RETURNS SETOF path_result
AS
$_$
DECLARE
  query    TEXT;
  filter   TEXT DEFAULT '';
  result   RECORD;
  output   path_result;
BEGIN
  IF routeMethod NOT IN ('dijkstra', 'astar', 'shootingstar')
  THEN
    RAISE EXCEPTION 'Invalid routing method supplied: %, not ''dijkstra'', ''astar'' or ''shootingstar''', routeMethod;
  END IF;

  IF source IS NULL
  THEN
    RAISE EXCEPTION 'Invalid null source ROUTE_EDGE provided';
  END IF;

  IF target IS NULL
  THEN
    RAISE EXCEPTION 'Invalid null target ROUTE_EDGE provided';
  END IF;

  -- check that a valid cost option was provided
  IF (SELECT id FROM network.costing_options WHERE option ILIKE costOption) IS NULL
  THEN
    RAISE Exception 'Invalid costing option % provided', costOption;
  END IF;

  IF filterExpand IS NOT NULL AND filterExpand > 0
  THEN
  	filter := ' JOIN (
                  SELECT ST_Expand (ST_MakeLine (source.the_geom, target.the_geom), ' || filterExpand || ') AS geom
                    FROM network.nodes AS source, network.nodes AS target
                   WHERE source.id = ' || source.nodeId || '
                     AND target.id = ' || target.nodeId || '
                ) AS filter
                     ON e.the_geom && filter.geom ';
  END IF;

  query := '
     SELECT (path.result).vertex_id, (path.result).edge_id, (path.result).cost
       FROM (';
 
  IF routeMethod = 'dijkstra'
  THEN
    query := query || '
              SELECT shortest_path (
                  ''SELECT e.gid AS id, 
                           e.source::int4,
                           e.target::int4,
                           (e.length * c.cost)::float8 AS cost,
                           (e.reverse_cost * c.cost)::float8 AS reverse_cost
                      FROM network.edges AS e
                      JOIN network.costing_options AS o
                           ON o.option ILIKE ''' || quote_literal (costOption) || '''
                      JOIN network.class_costs AS c
                           ON e.class_id = c.class_id AND
                              o.id = c.option_id' || filter || ''',
                    ' || source.nodeId || ',
                    ' || target.nodeId || ', 
                    true, 
                    true)::path_result AS result';
  ELSIF routeMethod = 'astar'
  THEN
    query := query || '
              SELECT shortest_path_astar(
                  ''SELECT e.gid AS id,
                           e.source::int4,
                           e.target::int4,
                           (e.length * c.cost)::float8 AS cost,
                           (e.reverse_cost * c.cost)::float8 AS reverse_cost,
                           e.x1,
                           e.y1,
                           e.x2,
                           e.y2 
                      FROM network.edges AS e
                      JOIN network.costing_options AS o
                           ON o.option = ''' || quote_literal (costOption) || '''
                      JOIN network.class_costs AS c
                           ON e.class_id = c.class_id AND
                              o.id = c.option_id' || filter || ''',
                    ' || source.nodeId || ',
                    ' || target.nodeId || ', 
                    true, 
                    true)::path_result AS result';

  ELSIF routeMethod = 'shootingstar'
  THEN
    query := query || '
              SELECT shortest_path_shooting_star(
                  ''SELECT e.gid AS id,
                           e.source::int4,
                           e.target::int4,
                           (e.length * c.cost)::float8 AS cost,
                           (e.reverse_cost * c.cost)::float8 AS reverse_cost,
                           e.x1,
                           e.y1,
                           e.x2,
                           e.y2,
                           e.rule,
                           e.to_cost
                      FROM network.edges AS e
                      JOIN network.costing_options AS o
                           ON o.option ILIKE ''' || quote_literal (costOption) || '''
                      JOIN network.class_costs AS c
                           ON e.class_id = c.class_id AND
                              o.id = c.option_id' || filter || ''',
                    ' || source.id || ',
                    ' || target.id || ', 
                    true, 
                    true)::path_result AS result';
  END IF;

  query := query || ') AS path';

  FOR result IN EXECUTE query
  LOOP
    output.vertex_id := result.vertex_id;
    output.edge_id   := result.edge_id;
    output.cost      := result.cost;

    RETURN NEXT output;
  END LOOP;

  RETURN;
END;
$_$
LANGUAGE 'plpgsql' VOLATILE STRICT
;

DROP FUNCTION IF EXISTS route (ROUTE_EDGE, ROUTE_EDGE, VARCHAR(64), VARCHAR(32));

CREATE FUNCTION route (source ROUTE_EDGE, target ROUTE_EDGE, routeMethod VARCHAR(64), costOption VARCHAR(32))
RETURNS SETOF path_result
AS
$_$
DECLARE
  query  TEXT;
  result RECORD;
  path   PATH_RESULT;
BEGIN
  query := 'SELECT (r).vertex_id, (r).edge_id, (r).cost
              FROM (network.route (' || source || ',' || target || ',' || routeMethod || ',' || costOption || ', NULL)';

  FOR result IN EXECUTE query
  LOOP
    path.vertex_id = result.vertex_id;
    path.edge_id   = result.edge_id;
    path.cost      = result.cost;

    RETURN NEXT path;
  END LOOP;

  RETURN;
END;
$_$
LANGUAGE 'plpgsql' VOLATILE STRICT
;
