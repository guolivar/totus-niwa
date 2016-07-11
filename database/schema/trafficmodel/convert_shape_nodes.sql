-- convert a sequence of node with the same traffic flow (same traffic pipe/link) to shape points
-- these have been introduced by Traffic Model or ATM to maintain some form of shape, however it seems to
-- have been done only in areas of interest, eg. Waterview

-- find node that are only a start node of one link and an end node of another
-- filter node whose adjacent link do not have the same traffic data
-- retain only the ones that match for all 3 traffic peaks
-- find redundant node in two passes to ensure we get the link right
-- do the same for reverse, eg. find node that are only the end node of one
-- link and the start of another
-- done seperately to deal with one ways and two ways
DROP TABLE IF EXISTS trafficmodel.shape_node;

CREATE TABLE trafficmodel.shape_node (
  node_id INTEGER
);

INSERT INTO trafficmodel.shape_node (node_id)
SELECT c.id
  FROM (
    SELECT cn.id
      FROM (
        SELECT n.id
          FROM trafficmodel.node AS n
          JOIN trafficmodel.link AS l1
               ON n.id = l1.end_node_id
          JOIN trafficmodel.link AS l2
               ON n.id = l2.start_node_id AND
                  FALSE = ST_Equals (l1.geom, l2.geom)
      GROUP BY n.id
        HAVING COUNT(*) = 1
      ) AS cn
      JOIN trafficmodel.link AS l1
           ON cn.id = l1.end_node_id
      JOIN trafficmodel.link_traffic_data AS ltd1
           ON l1.id = ltd1.link_id
      JOIN trafficmodel.traffic_data AS td1
           ON ltd1.data_id = td1.id
      JOIN trafficmodel.traffic_attribute AS ta1
           ON td1.attribute_id = ta1.id AND
              ta1.attribute = 'LkVehTotal'
      JOIN trafficmodel.link AS l2
           ON cn.id = l2.start_node_id
      JOIN trafficmodel.link_traffic_data AS ltd2
           ON l2.id = ltd2.link_id AND
              ltd1.data_id = ltd2.data_id
    ) AS c
GROUP BY c.id
HAVING COUNT(*) = 3
UNION
SELECT c.id
  FROM (
    SELECT cn.id
      FROM (
        SELECT n.id
          FROM trafficmodel.node AS n
          JOIN trafficmodel.link AS l1
               ON n.id = l1.start_node_id
          JOIN trafficmodel.link AS l2
               ON n.id = l2.end_node_id AND
                  FALSE = ST_Equals (l1.geom, l2.geom)
      GROUP BY n.id
        HAVING COUNT(*) = 1
      ) AS cn
      JOIN trafficmodel.link AS l1
           ON cn.id = l1.start_node_id
      JOIN trafficmodel.link_traffic_data AS ltd1
           ON l1.id = ltd1.link_id
      JOIN trafficmodel.traffic_data AS td1
           ON ltd1.data_id = td1.id
      JOIN trafficmodel.traffic_attribute AS ta1
           ON td1.attribute_id = ta1.id AND
              ta1.attribute = 'LkVehTotal'
      JOIN trafficmodel.link AS l2
           ON cn.id = l2.end_node_id
      JOIN trafficmodel.link_traffic_data AS ltd2
           ON l2.id = ltd2.link_id AND
              ltd1.data_id = ltd2.data_id
    ) AS c
GROUP BY c.id
HAVING COUNT(*) = 3
;

CREATE INDEX shape_node_idx ON trafficmodel.shape_node USING BTREE (node_id);

ANALYZE VERBOSE trafficmodel.shape_node;

-- recursive function to walk route
DROP FUNCTION IF EXISTS trafficmodel.combine_links (INTEGER, INTEGER);

CREATE FUNCTION trafficmodel.combine_links (startLink INTEGER, shapeNode INTEGER)
RETURNS VOID
AS
$_$
DECLARE
  result RECORD;
  query  TEXT;
  done   BOOLEAN DEFAULT TRUE;
  dataId INTEGER; 
  p      INTEGER;
  peaks  CHAR(2)[];
BEGIN
  -- stop when start node of next link is not a shape node
  query := 'SELECT l.id AS link_id,
                   l.end_node_id AS shape_node,
                   l.geom
              FROM trafficmodel.link AS l
              JOIN trafficmodel.shape_node AS sn 
                   ON l.start_node_id = sn.node_id
             WHERE start_node_id = ' || shapeNode;

  -- link time needs be aggregated, need to be done per traffic peak
  EXECUTE 'SELECT trafficmodel.ARRAY_ACCUM (type)
             FROM trafficmodel.traffic_peak'
     INTO peaks;

  FOR p IN SELECT GENERATE_SERIES (1, ARRAY_UPPER (peaks, 1))
  LOOP
    -- fetch next traffic data id for traffic each peak
    EXECUTE 'SELECT NEXTVAL (''trafficmodel.traffic_data_id_seq'')' INTO dataId;

    -- prepare new traffic data record
    -- to be safe we insert a copy of the start link's travel time
    -- we do not care whether or not the existing value is used, if not
    -- it will be removed later
    EXECUTE 'INSERT INTO trafficmodel.traffic_data (id, attribute_id, value)
             SELECT ' || dataId || ',
                    ta.id AS attribute_id,
                    td.value
               FROM trafficmodel.link_traffic_data AS ltd
               JOIN trafficmodel.traffic_data AS td
                    ON ltd.data_id = td.id
               JOIN trafficmodel.traffic_attribute AS ta
                    ON td.attribute_id = ta.id
              WHERE ltd.link_id = ' || startLink || '
                AND ltd.peak = ' || QUOTE_LITERAL(peaks[p]) || '
                AND ta.attribute = ''LkTime''';

    -- update existing traffic link to use copy of orginal link time
    EXECUTE 'UPDATE trafficmodel.link_traffic_data AS ltd
                SET data_id = ' || dataId || '
              WHERE link_id = ' || startLink || '
                AND peak = ' || QUOTE_LITERAL (peaks[p]) || '
                AND data_id IN (
                   SELECT ltd.data_id
                     FROM trafficmodel.link_traffic_data AS ltd
                     JOIN trafficmodel.traffic_data AS td
                          ON ltd.data_id = td.id
                     JOIN trafficmodel.traffic_attribute AS ta
                          ON td.attribute_id = ta.id
                    WHERE ltd.link_id = ' || startLink || '
                      AND ltd.peak = ' || QUOTE_LITERAL (peaks[p]) || '
                      AND ta.attribute = ''LkTime''
                )';
  END LOOP;

  FOR result IN EXECUTE query
  LOOP
    -- append redundant link's geometry to the master link
    EXECUTE 'UPDATE trafficmodel.link AS l
                SET geom  = ST_Multi (ST_Union (l.geom, ''' || result.geom::VARCHAR || '''::GEOMETRY)),
                    end_node_id = ' || result.shape_node || ',
                    traffic_id     = (REGEXP_SPLIT_TO_ARRAY (l.traffic_id, ''-''))[1] || ''-'' || n.traffic_id::VARCHAR
               FROM trafficmodel.node AS n
              WHERE l.id = ' || startLink || '
                AND n.id = ' || result.shape_node;


    EXECUTE 'UPDATE trafficmodel.traffic_data AS td
                SET value = n.value
               FROM (
                 SELECT td1.id,
                        td1.value + td2.value AS value
                   FROM trafficmodel.link_traffic_data AS ltd1
                   JOIN trafficmodel.traffic_data AS td1
                        ON ltd1.data_id = td1.id
                   JOIN trafficmodel.traffic_attribute AS ta1
                         ON ta1.attribute = ''LkTime'' AND
                            td1.attribute_id = ta1.id
                   JOIN trafficmodel.link_traffic_data AS ltd2
                        ON ltd2.link_id = ' || result.link_id || ' AND
                           ltd1.peak = ltd2.peak
                   JOIN trafficmodel.traffic_data AS td2
                        ON ltd2.data_id = td2.id AND
                           td1.attribute_id = td2.attribute_id
                  WHERE ltd1.link_id = ' || startLink || '
               ) AS n
              WHERE td.id = n.id';

    -- remove redundant link's traffic data
    EXECUTE 'DELETE FROM trafficmodel.link_traffic_data
              WHERE link_id = ' || result.link_id;

    -- remove transport route link
    EXECUTE 'DELETE FROM trafficmodel.transport_route_link
              WHERE link_id = ' || result.link_id;

    -- remove links' transport mode
    EXECUTE 'DELETE FROM trafficmodel.link_transport_mode
              WHERE link_id = ' || result.link_id;

    -- remove redundant link
    EXECUTE 'DELETE FROM trafficmodel.link
              WHERE id = ' || result.link_id;

   done = FALSE;
  END LOOP;

  IF (done = TRUE)
  THEN
    RETURN;
  ELSE
    RAISE NOTICE 'Next link after %', result.link_id;

    EXECUTE trafficmodel.combine_links (startLink, result.shape_node);
  END IF;
END;
$_$
LANGUAGE 'plpgsql' VOLATILE STRICT;

-- determine start link, end node is a shape point
-- combine the redundant link in it's path to next intersection to master link
SELECT 'Processing link: ' || l.id,
       trafficmodel.combine_links (l.id, l.end_node_id)
  FROM trafficmodel.link AS l 
  JOIN trafficmodel.shape_node AS sn 
       ON l.end_node_id = sn.node_id
 WHERE NOT EXISTS (
    SELECT DISTINCT ON (nn.node_id) nn.node_id
      FROM trafficmodel.shape_node AS nn
     WHERE nn.node_id = l.start_node_id
  );

-- done
DROP FUNCTION IF EXISTS trafficmodel.combine_links (INTEGER, INTEGER);

-- now remove all Traffic Model shape node no longer needed as real node
DELETE FROM trafficmodel.node_traffic_data WHERE node_id IN (
  SELECT id 
    FROM trafficmodel.node
   WHERE id NOT IN ( 
     SELECT start_node_id
      FROM trafficmodel.link
     UNION
    SELECT end_node_id
      FROM trafficmodel.link
   )
);

DELETE FROM trafficmodel.node WHERE id NOT IN (
  SELECT start_node_id
    FROM trafficmodel.link
   UNION
  SELECT end_node_id
    FROM trafficmodel.link
);

-- remove redundant traffic data
DELETE FROM trafficmodel.traffic_data WHERE id NOT IN (
  SELECT data_id
    FROM trafficmodel.link_traffic_data
  UNION ALL
  SELECT data_id
    FROM trafficmodel.node_traffic_data
);

 
