SET search_path = trafficmodel, public;

--
-- preconditions:
-- 1. raw interzone Traffic Model links with inode/jnode < 1000 have been filtered DONE BEFORE LOADING
-- 2. shape Traffic Model links have been converted to single multi-shape point Traffic Model link
-- 3. link types < 10 associated with ferry and rails have been filtered
--
ANALYZE VERBOSE trafficmodel.link;
ANALYZE VERBOSE trafficmodel.link_traffic_data;
ANALYZE VERBOSE trafficmodel.node;
ANALYZE VERBOSE trafficmodel.node_traffic_data;

DROP TABLE IF EXISTS link_road_class;

CREATE TABLE link_road_class (
  id           SERIAL,
  link_id      INTEGER NOT NULL,
  road_classes VARCHAR (32)[]
);

-- specific mapping for 2006 Traffic Model data
-- all other data sets consider all road types
INSERT INTO link_road_class (link_id, road_classes)
SELECT DISTINCT ON (l.id)
       l.id AS link_id,
       CASE WHEN ltd.year = 2006
            THEN
              CASE WHEN l.type_id IN (19)
                   THEN ARRAY['motorway', 'motorway_junction']
                   WHEN l.type_id IN (20, 21)
                   THEN ARRAY['motorway_link','trunk_link']
                   WHEN l.type_id IN (11)
                   THEN ARRAY['primary','unclassified']
                   WHEN l.type_id IN (12,13,14,15,16,17,18)
                   THEN ARRAY['trunk','trunk_link','primary','primary_link','secondary','secondary_link','tertiary','tertiary_link','residential','road','unclassified']
                   WHEN l.type_id >= 22
                   THEN ARRAY['trunk','trunk_link','primary','primary_link','secondary','secondary_link','tertiary','tertiary_link','residential','road','unclassified']
              END
            ELSE
              ARRAY['motorway','motorway_link','motorway_junction','trunk','trunk_link','primary','primary_link','secondary','secondary_link','tertiary','tertiary_link','residential','road','unclassified'] 
       END AS road_classes
  FROM link AS l
  JOIN link_traffic_data AS ltd
       ON l.id = ltd.link_id
 WHERE (ltd.year = 2006 AND l.type_id >= 10)
    OR ltd.year <> 2006;

CREATE INDEX link_road_class_idx ON link_road_class USING BTREE (link_id);
ANALYZE VERBOSE link_road_class;

DROP TABLE IF EXISTS link_network_candidate;

-- relate a trafficmodel link with start/end node to network source/target node
CREATE TABLE link_network_candidate (
  id                        SERIAL,
  link_id                   INTEGER,
  network_source_node_id    INTEGER,
  network_source_node_error NUMERIC (12, 8),
  network_target_node_id    INTEGER,
  network_target_node_error NUMERIC (12, 8),
  geom                      GEOMETRY (POLYGON, 4326),
  PRIMARY KEY (id)
);

INSERT INTO link_network_candidate (link_id, network_source_node_id, network_source_node_error,
                                    network_target_node_id, network_target_node_error, geom)
SELECT sn.link_id,
       sn.network_node_id    AS network_source_node_id,
       sn.network_node_error AS network_source_node_error,
       en.network_node_id    AS network_target_node_id,
       en.network_node_error AS network_target_node_error,
       ST_Expand (ST_MakeLine (source.the_geom, target.the_geom), 0.0201397760129886) AS geom
  FROM (
   SELECT DISTINCT ON (link_id, network_node_id)
           link_id,
           network_node_id,
           network_node_error
      FROM (
        SELECT link_id,
               (network_node).id AS network_node_id,
               (network_node).error AS network_node_error
          FROM (
            SELECT l.id AS link_id,
                   network.closest_nodes (ST_X(ST_StartPoint (ST_LineMerge(l.geom)))::NUMERIC(12,8), 
                                          ST_Y(ST_StartPoint (ST_LineMerge(l.geom)))::NUMERIC(12,8),
                                          0.00402795520259772::NUMERIC(12,8),
                                          lrc.road_classes,
                                          3::smallint) AS network_node
              FROM link AS l
              JOIN link_road_class AS lrc
                   ON l.id = lrc.link_id
             UNION
             SELECT l.id AS link_id,
                    network.closest_nodes (ST_X(ST_EndPoint (ST_LineMerge(l.geom)))::NUMERIC(12,8), 
                                           ST_Y(ST_EndPoint (ST_LineMerge(l.geom)))::NUMERIC(12,8),
                                           0.00402795520259772::NUMERIC(12,8),
                                           lrc.road_classes,
                                           3::smallint) AS network_node
              FROM link AS l
              JOIN link_road_class AS lrc
                   ON l.id = lrc.link_id
             ) AS m
          JOIN network.nodes AS n
               ON n.id = (network_node).id
         UNION
        SELECT link_id,
               network_node_id,
               network_node_error
          FROM (
            SELECT DISTINCT
                   l.id AS link_id,
                   n.id AS network_node_id,
                   CASE WHEN ST_Distance (ST_StartPoint (ST_LineMerge(l.geom)), n.the_geom) <= ST_Distance (ST_EndPoint (ST_LineMerge(l.geom)), n.the_geom)
                        THEN ST_Distance (ST_StartPoint (ST_LineMerge(l.geom)), n.the_geom)
                        ELSE ST_Distance (ST_EndPoint (ST_LineMerge(l.geom)), n.the_geom)
                   END AS network_node_error,
                   DENSE_RANK () OVER (PARTITION BY l.id ORDER BY ST_Distance (ST_Centroid (l.geom), n.the_geom)) AS rank
              FROM network.nodes AS n
              JOIN link AS l
                   ON n.the_geom && ST_Expand (l.geom, 0.00402795520259772)
              JOIN link_road_class AS lrc
                   ON l.id = lrc.link_id
              JOIN network.edges AS e
                   ON n.id = e.source OR
                      n.id = e.target
              JOIN network.classes AS c
                   ON e.class_id = c.id
              JOIN network.types AS t
                   ON c.type_id = t.id
             WHERE t.name = 'highway'
               AND c.name = ANY (lrc.road_classes)
             ) AS m
         WHERE rank <= 5
         ) AS mm
     ) AS sn
  JOIN (
   SELECT DISTINCT ON (link_id, network_node_id)
           link_id,
           network_node_id,
           network_node_error
      FROM (
        SELECT link_id,
               (network_node).id AS network_node_id,
               (network_node).error AS network_node_error
          FROM (
            SELECT l.id AS link_id,
                   network.closest_nodes (ST_X(ST_StartPoint (ST_LineMerge(l.geom)))::NUMERIC(12,8), 
                                          ST_Y(ST_StartPoint (ST_LineMerge(l.geom)))::NUMERIC(12,8),
                                          0.00402795520259772::NUMERIC(12,8),
                                          lrc.road_classes,
                                          3::smallint) AS network_node
              FROM link AS l
              JOIN link_road_class AS lrc
                   ON l.id = lrc.link_id
             UNION
             SELECT l.id AS link_id,
                    network.closest_nodes (ST_X(ST_EndPoint (ST_LineMerge(l.geom)))::NUMERIC(12,8), 
                                           ST_Y(ST_EndPoint (ST_LineMerge(l.geom)))::NUMERIC(12,8),
                                           0.00402795520259772::NUMERIC(12,8),
                                           lrc.road_classes,
                                           3::smallint) AS network_node
              FROM link AS l
              JOIN link_road_class AS lrc
                   ON l.id = lrc.link_id
             ) AS m
          JOIN network.nodes AS n
               ON n.id = (network_node).id
         UNION
        SELECT link_id,
               network_node_id,
               network_node_error
          FROM (
            SELECT DISTINCT
                   l.id AS link_id,
                   n.id AS network_node_id,
                   CASE WHEN ST_Distance (ST_StartPoint (ST_LineMerge(l.geom)), n.the_geom) <= ST_Distance (ST_EndPoint (ST_LineMerge(l.geom)), n.the_geom)
                        THEN ST_Distance (ST_StartPoint (ST_LineMerge(l.geom)), n.the_geom)
                        ELSE ST_Distance (ST_EndPoint (ST_LineMerge(l.geom)), n.the_geom)
                   END AS network_node_error,
                   DENSE_RANK () OVER (PARTITION BY l.id ORDER BY ST_Distance (ST_Centroid (l.geom), n.the_geom)) AS rank
              FROM network.nodes AS n
              JOIN link AS l
                   ON n.the_geom && ST_Expand (l.geom, 0.00402795520259772)
              JOIN link_road_class AS lrc
                   ON l.id = lrc.link_id
              JOIN network.edges AS e
                   ON n.id = e.source OR
                      n.id = e.target
              JOIN network.classes AS c
                   ON e.class_id = c.id
              JOIN network.types AS t
                   ON c.type_id = t.id
             WHERE t.name = 'highway'
               AND c.name = ANY (lrc.road_classes)
             ) AS m
         WHERE rank <= 5
         ) AS mm
      ) AS en
       ON sn.link_id = en.link_id AND
          sn.network_node_id <> en.network_node_id
  JOIN network.nodes AS source
       ON sn.network_node_id = source.id
  JOIN network.nodes AS target
       ON en.network_node_id = target.id;

-- index for primary column used in joins
CREATE INDEX link_network_candidate_link_idx   ON link_network_candidate USING BTREE (link_id);
CREATE INDEX link_network_candidate_source_idx ON link_network_candidate USING BTREE (network_source_node_id);
CREATE INDEX link_network_candidate_target_idx ON link_network_candidate USING BTREE (network_target_node_id);
CREATE INDEX link_network_candidate_geom_idx   ON link_network_candidate USING GiST (geom);

ANALYZE VERBOSE link_network_candidate;

DROP TABLE IF EXISTS link_network_candidate_path;

-- link network candidate with network path
CREATE TABLE link_network_candidate_path (
  id                        SERIAL,
  link_network_candidate_id INTEGER,
  network_path_node_id      INTEGER,
  network_path_edge_id      INTEGER,
  network_path_cost         NUMERIC,
  network_path_seq          INTEGER,
  PRIMARY KEY (id)
);

--
-- store the shortest graph path (considering wayness) between source and target network node as candidate path
-- apply spatial filter to search edges by expanding bounding box of line string from source to target node
-- by ~ 2 km
-- insert sequence for all paths
-- partition into paths using the first sequence in the group
--
DROP FUNCTION IF EXISTS link_network_candidate_paths (INTEGER, INTEGER);

CREATE FUNCTION link_network_candidate_paths (lowerLimit INTEGER, upperLimit INTEGER)
RETURNS void
AS
$_$
DECLARE
  query      TEXT;
BEGIN
  query := 'INSERT INTO trafficmodel.link_network_candidate_path (link_network_candidate_id,
                                                          network_path_node_id, 
                                                          network_path_edge_id,
                                                          network_path_cost,
                                                          network_path_seq)
            SELECT lnp.link_network_candidate_id,
                   (lnp.path).vertex_id          AS network_path_node_id,
                   (lnp.path).edge_id            AS network_path_edge_id,
                   (lnp.path).cost               AS network_path_cost,
                   ROW_NUMBER () OVER (PARTITION BY lnp.link_network_candidate_id) AS network_path_seq
              FROM (
                SELECT lnc.id AS link_network_candidate_id,
                       public.shortest_path_astar(
                        ''SELECT e.gid AS id, 
                                 e.source::int4,
                                 e.target::int4,
                                 (e.length * cc.cost)::float8 AS cost,
                                 (e.reverse_cost * cc.cost)::float8 AS reverse_cost,
                                 e.x1, 
                                 e.y1,
                                 e.x2,
                                 e.y2
                            FROM network.edges AS e
                            JOIN network.costing_options AS co
                                 ON co.option = '' || quote_literal(''vehicle'') || ''
                            JOIN network.class_costs AS cc
                                 ON e.class_id = cc.class_id AND
                                    co.id = cc.option_id
                            JOIN network.classes AS c
                                 ON e.class_id = c.id
                            JOIN network.types AS t
                                 ON c.type_id = t.id
                           WHERE t.name = '' || quote_literal (''highway'') || ''
                             AND c.name = ANY (
                                   STRING_TO_ARRAY ('''''' || 
                                     (SELECT ARRAY_TO_STRING (road_classes, '','') FROM link_road_class WHERE link_id = lnc.link_id) ||
                                     '''''', '''','''')
                                 ) 
                             AND e.the_geom && '' || quote_literal (lnc.geom::TEXT) || ''::GEOMETRY'',
                         lnc.network_source_node_id, 
                         lnc.network_target_node_id, 
                         true, 
                         true) AS path
                  FROM trafficmodel.link_network_candidate AS lnc
                 WHERE lnc.link_id BETWEEN ' || lowerLimit || ' AND ' || upperLimit || '
              ) AS lnp';
  RAISE NOTICE 'Calculating candidate paths for Traffic Model link % to %', lowerLimit, upperLimit;
  RAISE NOTICE '%', query;

  EXECUTE query;

  RETURN;
END;
$_$
LANGUAGE 'plpgsql' VOLATILE STRICT;

-- calculate network candidate paths in batches of 50 Traffic Model link
--
-- ideally we batch the calls to the SRF (set returning functions) using a series
-- but the timing of garbage collection for SRFs means that memory is only reclaimed
-- at the end of statement, which results in a session memory leak
--
--SELECT link_network_candidate_paths (i + 1, i + 50)
--  FROM GENERATE_SERIES (
--         0, 
--         (SELECT MAX(id) FROM link), 
--         50
--       ) AS i;
--
-- for above reason we need to call SRFs in a statement per batch with commits to flush memory
SELECT link_network_candidate_paths (1, 50);
SELECT link_network_candidate_paths (51, 100);
SELECT link_network_candidate_paths (101, 150);
SELECT link_network_candidate_paths (151, 200);
SELECT link_network_candidate_paths (201, 250);
SELECT link_network_candidate_paths (251, 300);
SELECT link_network_candidate_paths (301, 350);
SELECT link_network_candidate_paths (351, 400);
SELECT link_network_candidate_paths (401, 450);
SELECT link_network_candidate_paths (451, 500);
SELECT link_network_candidate_paths (501, 550);
SELECT link_network_candidate_paths (551, 600);
SELECT link_network_candidate_paths (601, 650);
SELECT link_network_candidate_paths (651, 700);
SELECT link_network_candidate_paths (701, 750);
SELECT link_network_candidate_paths (751, 800);
SELECT link_network_candidate_paths (801, 850);
SELECT link_network_candidate_paths (851, 900);
SELECT link_network_candidate_paths (901, 950);
SELECT link_network_candidate_paths (951, 1000);
SELECT link_network_candidate_paths (1001, 1050);
SELECT link_network_candidate_paths (1051, 1100);
SELECT link_network_candidate_paths (1101, 1150);
SELECT link_network_candidate_paths (1151, 1200);
SELECT link_network_candidate_paths (1201, 1250);
SELECT link_network_candidate_paths (1251, 1300);
SELECT link_network_candidate_paths (1301, 1350);
SELECT link_network_candidate_paths (1351, 1400);
SELECT link_network_candidate_paths (1401, 1450);
SELECT link_network_candidate_paths (1451, 1500);
SELECT link_network_candidate_paths (1501, 1550);
SELECT link_network_candidate_paths (1551, 1600);
SELECT link_network_candidate_paths (1601, 1650);
SELECT link_network_candidate_paths (1651, 1700);
SELECT link_network_candidate_paths (1701, 1750);
SELECT link_network_candidate_paths (1751, 1800);
SELECT link_network_candidate_paths (1801, 1850);
SELECT link_network_candidate_paths (1851, 1900);
SELECT link_network_candidate_paths (1901, 1950);
SELECT link_network_candidate_paths (1951, 2000);
SELECT link_network_candidate_paths (2001, 2050);
SELECT link_network_candidate_paths (2051, 2100);
SELECT link_network_candidate_paths (2101, 2150);
SELECT link_network_candidate_paths (2151, 2200);
SELECT link_network_candidate_paths (2201, 2250);
SELECT link_network_candidate_paths (2251, 2300);
SELECT link_network_candidate_paths (2301, 2350);
SELECT link_network_candidate_paths (2351, 2400);
SELECT link_network_candidate_paths (2401, 2450);
SELECT link_network_candidate_paths (2451, 2500);
SELECT link_network_candidate_paths (2501, 2550);
SELECT link_network_candidate_paths (2551, 2600);
SELECT link_network_candidate_paths (2601, 2650);
SELECT link_network_candidate_paths (2651, 2700);
SELECT link_network_candidate_paths (2701, 2750);
SELECT link_network_candidate_paths (2751, 2800);
SELECT link_network_candidate_paths (2801, 2850);
SELECT link_network_candidate_paths (2851, 2900);
SELECT link_network_candidate_paths (2901, 2950);
SELECT link_network_candidate_paths (2951, 3000);
SELECT link_network_candidate_paths (3001, 3050);
SELECT link_network_candidate_paths (3051, 3100);
SELECT link_network_candidate_paths (3101, 3150);
SELECT link_network_candidate_paths (3151, 3200);
SELECT link_network_candidate_paths (3201, 3250);
SELECT link_network_candidate_paths (3251, 3300);
SELECT link_network_candidate_paths (3301, 3350);
SELECT link_network_candidate_paths (3351, 3400);
SELECT link_network_candidate_paths (3401, 3450);
SELECT link_network_candidate_paths (3451, 3500);
SELECT link_network_candidate_paths (3501, 3550);
SELECT link_network_candidate_paths (3551, 3600);
SELECT link_network_candidate_paths (3601, 3650);
SELECT link_network_candidate_paths (3651, 3700);
SELECT link_network_candidate_paths (3701, 3750);
SELECT link_network_candidate_paths (3751, 3800);
SELECT link_network_candidate_paths (3801, 3850);
SELECT link_network_candidate_paths (3851, 3900);
SELECT link_network_candidate_paths (3901, 3950);
SELECT link_network_candidate_paths (3951, 4000);
SELECT link_network_candidate_paths (4001, 4050);
SELECT link_network_candidate_paths (4051, 4100);
SELECT link_network_candidate_paths (4101, 4150);
SELECT link_network_candidate_paths (4151, 4200);
SELECT link_network_candidate_paths (4201, 4250);
SELECT link_network_candidate_paths (4251, 4300);
SELECT link_network_candidate_paths (4301, 4350);
SELECT link_network_candidate_paths (4351, 4400);
SELECT link_network_candidate_paths (4401, 4450);
SELECT link_network_candidate_paths (4451, 4500);
SELECT link_network_candidate_paths (4501, 4550);
SELECT link_network_candidate_paths (4551, 4600);
SELECT link_network_candidate_paths (4601, 4650);
SELECT link_network_candidate_paths (4651, 4700);
SELECT link_network_candidate_paths (4701, 4750);
SELECT link_network_candidate_paths (4751, 4800);
SELECT link_network_candidate_paths (4801, 4850);
SELECT link_network_candidate_paths (4851, 4900);
SELECT link_network_candidate_paths (4901, 4950);
SELECT link_network_candidate_paths (4951, 5000);
SELECT link_network_candidate_paths (5001, 5050);
SELECT link_network_candidate_paths (5051, 5100);
SELECT link_network_candidate_paths (5101, 5150);
SELECT link_network_candidate_paths (5151, 5200);
SELECT link_network_candidate_paths (5201, 5250);
SELECT link_network_candidate_paths (5251, 5300);
SELECT link_network_candidate_paths (5301, 5350);
SELECT link_network_candidate_paths (5351, 5400);
SELECT link_network_candidate_paths (5401, 5450);
SELECT link_network_candidate_paths (5451, 5500);
SELECT link_network_candidate_paths (5501, 5550);
SELECT link_network_candidate_paths (5551, 5600);
SELECT link_network_candidate_paths (5601, 5650);
SELECT link_network_candidate_paths (5651, 5700);
SELECT link_network_candidate_paths (5701, 5750);
SELECT link_network_candidate_paths (5751, 5800);
SELECT link_network_candidate_paths (5801, 5850);
SELECT link_network_candidate_paths (5851, 5900);
SELECT link_network_candidate_paths (5901, 5950);
SELECT link_network_candidate_paths (5951, 6000);
SELECT link_network_candidate_paths (6001, 6050);
SELECT link_network_candidate_paths (6051, 6100);
SELECT link_network_candidate_paths (6101, 6150);
SELECT link_network_candidate_paths (6151, 6200);
SELECT link_network_candidate_paths (6201, 6250);
SELECT link_network_candidate_paths (6251, 6300);
SELECT link_network_candidate_paths (6301, 6350);
SELECT link_network_candidate_paths (6351, 6400);
SELECT link_network_candidate_paths (6401, 6450);
SELECT link_network_candidate_paths (6451, 6500);
SELECT link_network_candidate_paths (6501, 6550);
SELECT link_network_candidate_paths (6551, 6600);
SELECT link_network_candidate_paths (6601, 6650);
SELECT link_network_candidate_paths (6651, 6700);
SELECT link_network_candidate_paths (6701, 6750);
SELECT link_network_candidate_paths (6751, 6800);
SELECT link_network_candidate_paths (6801, 6850);
SELECT link_network_candidate_paths (6851, 6900);
SELECT link_network_candidate_paths (6901, 6950);
SELECT link_network_candidate_paths (6951, 7000);
SELECT link_network_candidate_paths (7001, 7050);
SELECT link_network_candidate_paths (7051, 7100);
SELECT link_network_candidate_paths (7101, 7150);
SELECT link_network_candidate_paths (7151, 7200);
SELECT link_network_candidate_paths (7201, 7250);
SELECT link_network_candidate_paths (7251, 7300);
SELECT link_network_candidate_paths (7301, 7350);
SELECT link_network_candidate_paths (7351, 7400);
SELECT link_network_candidate_paths (7401, 7450);
SELECT link_network_candidate_paths (7451, 7500);
SELECT link_network_candidate_paths (7501, 7550);
SELECT link_network_candidate_paths (7551, 7600);
SELECT link_network_candidate_paths (7601, 7650);
SELECT link_network_candidate_paths (7651, 7700);
SELECT link_network_candidate_paths (7701, 7750);
SELECT link_network_candidate_paths (7751, 7800);
SELECT link_network_candidate_paths (7801, 7850);
SELECT link_network_candidate_paths (7851, 7900);
SELECT link_network_candidate_paths (7901, 7950);
SELECT link_network_candidate_paths (7951, 8000);
SELECT link_network_candidate_paths (8001, 8050);
SELECT link_network_candidate_paths (8051, 8100);
SELECT link_network_candidate_paths (8101, 8150);
SELECT link_network_candidate_paths (8151, 8200);
SELECT link_network_candidate_paths (8201, 8250);
SELECT link_network_candidate_paths (8251, 8300);
SELECT link_network_candidate_paths (8301, 8350);
SELECT link_network_candidate_paths (8351, 8400);
SELECT link_network_candidate_paths (8401, 8450);
SELECT link_network_candidate_paths (8451, 8500);
SELECT link_network_candidate_paths (8501, 8550);
SELECT link_network_candidate_paths (8551, 8600);
SELECT link_network_candidate_paths (8601, 8650);
SELECT link_network_candidate_paths (8651, 8700);
SELECT link_network_candidate_paths (8701, 8750);
SELECT link_network_candidate_paths (8751, 8800);
SELECT link_network_candidate_paths (8801, 8850);
SELECT link_network_candidate_paths (8851, 8900);
SELECT link_network_candidate_paths (8901, 8950);
SELECT link_network_candidate_paths (8951, 9000);
SELECT link_network_candidate_paths (9001, 9050);
SELECT link_network_candidate_paths (9051, 9100);
SELECT link_network_candidate_paths (9101, 9150);
SELECT link_network_candidate_paths (9151, 9200);
SELECT link_network_candidate_paths (9201, 9250);
SELECT link_network_candidate_paths (9251, 9300);
SELECT link_network_candidate_paths (9301, 9350);
SELECT link_network_candidate_paths (9351, 9400);
SELECT link_network_candidate_paths (9401, 9450);
SELECT link_network_candidate_paths (9451, 9500);
SELECT link_network_candidate_paths (9501, 9550);
SELECT link_network_candidate_paths (9551, 9600);
SELECT link_network_candidate_paths (9601, 9650);
SELECT link_network_candidate_paths (9651, 9700);
SELECT link_network_candidate_paths (9701, 9750);
SELECT link_network_candidate_paths (9751, 9800);
SELECT link_network_candidate_paths (9801, 9850);
SELECT link_network_candidate_paths (9851, 9900);
SELECT link_network_candidate_paths (9901, 9950);
SELECT link_network_candidate_paths (9951, 10000);
SELECT link_network_candidate_paths (10001, 10050);
SELECT link_network_candidate_paths (10051, 10100);
SELECT link_network_candidate_paths (10101, 10150);
SELECT link_network_candidate_paths (10151, 10200);
SELECT link_network_candidate_paths (10201, 10250);
SELECT link_network_candidate_paths (10251, 10300);
SELECT link_network_candidate_paths (10301, 10350);
SELECT link_network_candidate_paths (10351, 10400);
SELECT link_network_candidate_paths (10401, 10450);
SELECT link_network_candidate_paths (10451, 10500);
SELECT link_network_candidate_paths (10501, 10550);
SELECT link_network_candidate_paths (10551, 10600);
SELECT link_network_candidate_paths (10601, 10650);
SELECT link_network_candidate_paths (10651, 10700);
SELECT link_network_candidate_paths (10701, 10750);
SELECT link_network_candidate_paths (10751, 10800);
SELECT link_network_candidate_paths (10801, 10850);
SELECT link_network_candidate_paths (10851, 10900);
SELECT link_network_candidate_paths (10901, 10950);
SELECT link_network_candidate_paths (10951, 11000);
SELECT link_network_candidate_paths (11001, 11050);
SELECT link_network_candidate_paths (11051, 11100);
SELECT link_network_candidate_paths (11101, 11150);
SELECT link_network_candidate_paths (11151, 11200);
SELECT link_network_candidate_paths (11201, 11250);
SELECT link_network_candidate_paths (11251, 11300);
SELECT link_network_candidate_paths (11301, 11350);
SELECT link_network_candidate_paths (11351, 11400);
SELECT link_network_candidate_paths (11401, 11450);
SELECT link_network_candidate_paths (11451, 11500);
SELECT link_network_candidate_paths (11501, 11550);
SELECT link_network_candidate_paths (11551, 11600);
SELECT link_network_candidate_paths (11601, 11650);
SELECT link_network_candidate_paths (11651, 11700);
SELECT link_network_candidate_paths (11701, 11750);
SELECT link_network_candidate_paths (11751, 11800);
SELECT link_network_candidate_paths (11801, 11850);
SELECT link_network_candidate_paths (11851, 11900);
SELECT link_network_candidate_paths (11901, 11950);
SELECT link_network_candidate_paths (11951, 12000);
SELECT link_network_candidate_paths (12001, 12050);
SELECT link_network_candidate_paths (12051, 12100);
SELECT link_network_candidate_paths (12101, 12150);
SELECT link_network_candidate_paths (12151, 12200);
SELECT link_network_candidate_paths (12201, 12250);
SELECT link_network_candidate_paths (12251, 12300);
SELECT link_network_candidate_paths (12301, 12350);
SELECT link_network_candidate_paths (12351, 12400);
SELECT link_network_candidate_paths (12401, 12450);
SELECT link_network_candidate_paths (12451, 12500);
SELECT link_network_candidate_paths (12501, 12550);
SELECT link_network_candidate_paths (12551, 12600);
SELECT link_network_candidate_paths (12601, 12650);
SELECT link_network_candidate_paths (12651, 12700);
SELECT link_network_candidate_paths (12701, 12750);
SELECT link_network_candidate_paths (12751, 12800);
SELECT link_network_candidate_paths (12801, 12850);
SELECT link_network_candidate_paths (12851, 12900);
SELECT link_network_candidate_paths (12901, 12950);
SELECT link_network_candidate_paths (12951, 13000);
SELECT link_network_candidate_paths (13001, 13050);
SELECT link_network_candidate_paths (13051, 13100);
SELECT link_network_candidate_paths (13101, 13150);
SELECT link_network_candidate_paths (13151, 13200);
SELECT link_network_candidate_paths (13201, 13250);
SELECT link_network_candidate_paths (13251, 13300);
SELECT link_network_candidate_paths (13301, 13350);
SELECT link_network_candidate_paths (13351, 13400);
SELECT link_network_candidate_paths (13401, 13450);
SELECT link_network_candidate_paths (13451, 13500);
SELECT link_network_candidate_paths (13501, 13550);
SELECT link_network_candidate_paths (13551, 13600);
SELECT link_network_candidate_paths (13601, 13650);
SELECT link_network_candidate_paths (13651, 13700);
SELECT link_network_candidate_paths (13701, 13750);
SELECT link_network_candidate_paths (13751, 13800);
SELECT link_network_candidate_paths (13801, 13850);
SELECT link_network_candidate_paths (13851, 13900);
SELECT link_network_candidate_paths (13901, 13950);
SELECT link_network_candidate_paths (13951, 14000);
SELECT link_network_candidate_paths (14001, 14050);
SELECT link_network_candidate_paths (14051, 14100);
SELECT link_network_candidate_paths (14101, 14150);
SELECT link_network_candidate_paths (14151, 14200);
SELECT link_network_candidate_paths (14201, 14250);
SELECT link_network_candidate_paths (14251, 14300);
SELECT link_network_candidate_paths (14301, 14350);
SELECT link_network_candidate_paths (14351, 14400);
SELECT link_network_candidate_paths (14401, 14450);
SELECT link_network_candidate_paths (14451, 14500);
SELECT link_network_candidate_paths (14501, 14550);
SELECT link_network_candidate_paths (14551, 14600);
SELECT link_network_candidate_paths (14601, 14650);
SELECT link_network_candidate_paths (14651, 14700);
SELECT link_network_candidate_paths (14701, 14750);
SELECT link_network_candidate_paths (14751, 14800);
SELECT link_network_candidate_paths (14801, 14850);
SELECT link_network_candidate_paths (14851, 14900);
SELECT link_network_candidate_paths (14901, 14950);
SELECT link_network_candidate_paths (14951, 15000);
SELECT link_network_candidate_paths (15001, 15050);
SELECT link_network_candidate_paths (15051, 15100);
SELECT link_network_candidate_paths (15101, 15150);
SELECT link_network_candidate_paths (15151, 15200);
SELECT link_network_candidate_paths (15201, 15250);
SELECT link_network_candidate_paths (15251, 15300);
SELECT link_network_candidate_paths (15301, 15350);
SELECT link_network_candidate_paths (15351, 15400);
SELECT link_network_candidate_paths (15401, 15450);
SELECT link_network_candidate_paths (15451, 15500);
SELECT link_network_candidate_paths (15501, 15550);
SELECT link_network_candidate_paths (15551, 15600);
SELECT link_network_candidate_paths (15601, 15650);
SELECT link_network_candidate_paths (15651, 15700);
SELECT link_network_candidate_paths (15701, 15750);
SELECT link_network_candidate_paths (15751, 15800);
SELECT link_network_candidate_paths (15801, 15850);
SELECT link_network_candidate_paths (15851, 15900);
SELECT link_network_candidate_paths (15901, 15950);
SELECT link_network_candidate_paths (15951, 16000);
SELECT link_network_candidate_paths (16001, 16050);
SELECT link_network_candidate_paths (16051, 16100);
SELECT link_network_candidate_paths (16101, 16150);
SELECT link_network_candidate_paths (16151, 16200);
SELECT link_network_candidate_paths (16201, 16250);
SELECT link_network_candidate_paths (16251, 16300);
SELECT link_network_candidate_paths (16301, 16350);
SELECT link_network_candidate_paths (16351, 16400);
SELECT link_network_candidate_paths (16401, 16450);
SELECT link_network_candidate_paths (16451, 16500);
SELECT link_network_candidate_paths (16501, 16550);
SELECT link_network_candidate_paths (16551, 16600);
SELECT link_network_candidate_paths (16601, 16650);
SELECT link_network_candidate_paths (16651, 16700);
SELECT link_network_candidate_paths (16701, 16750);
SELECT link_network_candidate_paths (16751, 16800);
SELECT link_network_candidate_paths (16801, 16850);
SELECT link_network_candidate_paths (16851, 16900);
SELECT link_network_candidate_paths (16901, 16950);
SELECT link_network_candidate_paths (16951, 17000);
SELECT link_network_candidate_paths (17001, 17050);
SELECT link_network_candidate_paths (17051, 17100);
SELECT link_network_candidate_paths (17101, 17150);
SELECT link_network_candidate_paths (17151, 17200);
SELECT link_network_candidate_paths (17201, 17250);
SELECT link_network_candidate_paths (17251, 17300);
SELECT link_network_candidate_paths (17301, 17350);
SELECT link_network_candidate_paths (17351, 17400);
SELECT link_network_candidate_paths (17401, 17450);
SELECT link_network_candidate_paths (17451, 17500);
SELECT link_network_candidate_paths (17501, 17550);
SELECT link_network_candidate_paths (17551, 17600);
SELECT link_network_candidate_paths (17601, 17650);
SELECT link_network_candidate_paths (17651, 17700);
SELECT link_network_candidate_paths (17701, 17750);
SELECT link_network_candidate_paths (17751, 17800);
SELECT link_network_candidate_paths (17801, 17850);
SELECT link_network_candidate_paths (17851, 17900);
SELECT link_network_candidate_paths (17901, 17950);
SELECT link_network_candidate_paths (17951, 18000);
SELECT link_network_candidate_paths (18001, 18050);
SELECT link_network_candidate_paths (18051, 18100);
SELECT link_network_candidate_paths (18101, 18150);
SELECT link_network_candidate_paths (18151, 18200);
SELECT link_network_candidate_paths (18201, 18250);
SELECT link_network_candidate_paths (18251, 18300);
SELECT link_network_candidate_paths (18301, 18350);
SELECT link_network_candidate_paths (18351, 18400);
SELECT link_network_candidate_paths (18401, 18450);
SELECT link_network_candidate_paths (18451, 18500);
SELECT link_network_candidate_paths (18501, 18550);
SELECT link_network_candidate_paths (18551, 18600);
SELECT link_network_candidate_paths (18601, 18650);
SELECT link_network_candidate_paths (18651, 18700);
SELECT link_network_candidate_paths (18701, 18750);
SELECT link_network_candidate_paths (18751, 18800);
SELECT link_network_candidate_paths (18801, 18850);
SELECT link_network_candidate_paths (18851, 18900);
SELECT link_network_candidate_paths (18901, 18950);
SELECT link_network_candidate_paths (18951, 19000);
SELECT link_network_candidate_paths (19001, 19050);
SELECT link_network_candidate_paths (19051, 19100);
SELECT link_network_candidate_paths (19101, 19150);
SELECT link_network_candidate_paths (19151, 19200);
SELECT link_network_candidate_paths (19201, 19250);
SELECT link_network_candidate_paths (19251, 19300);
SELECT link_network_candidate_paths (19301, 19350);
SELECT link_network_candidate_paths (19351, 19400);
SELECT link_network_candidate_paths (19401, 19450);
SELECT link_network_candidate_paths (19451, 19500);
SELECT link_network_candidate_paths (19501, 19550);
SELECT link_network_candidate_paths (19551, 19600);
SELECT link_network_candidate_paths (19601, 19650);
SELECT link_network_candidate_paths (19651, 19700);
SELECT link_network_candidate_paths (19701, 19750);
SELECT link_network_candidate_paths (19751, 19800);
SELECT link_network_candidate_paths (19801, 19850);
SELECT link_network_candidate_paths (19851, 19900);
SELECT link_network_candidate_paths (19901, 19950);
SELECT link_network_candidate_paths (19951, 20000);

ANALYZE VERBOSE link_network_candidate_path;

DROP FUNCTION link_network_candidate_paths (INTEGER, INTEGER);

CREATE INDEX link_network_candidate_path_candidate_idx
    ON link_network_candidate_path USING BTREE (link_network_candidate_id);

ANALYZE VERBOSE link_network_candidate_path (link_network_candidate_id);

CREATE INDEX link_network_candidate_path_edge_idx
    ON link_network_candidate_path USING BTREE (network_path_edge_id)
 WHERE network_path_edge_id <> -1;

ANALYZE VERBOSE link_network_candidate_path (link_network_candidate_id);

CREATE INDEX link_network_candidate_path_candidate_edge_idx
  ON link_network_candidate_path USING BTREE (link_network_candidate_id, network_path_edge_id);

ANALYZE VERBOSE link_network_candidate_path (link_network_candidate_id, network_path_edge_id);

DROP TABLE IF EXISTS link_extension;

CREATE TABLE link_extension (
  link_id  INTEGER,
  typ      SMALLINT,
  geom     GEOMETRY (LINESTRING, 4326)
);

INSERT INTO link_extension (link_id, typ, geom)
SELECT link_id,
       typ,
       CASE WHEN typ = 0
            THEN 
            ST_MakeLine (
              ST_Line_Interpolate_Point (geom, distance / ST_Length (geom)),
              ST_StartPoint (geom)
            )
            ELSE
            ST_MakeLine (
              ST_StartPoint (geom),
              ST_Line_Interpolate_Point (geom, distance / ST_Length (geom))
            )
       END AS geom
  FROM (
    SELECT l.id AS link_id, 
           typ,
           CASE WHEN typ = 0
                THEN
                CASE WHEN x1 < x2
                     THEN
                       ST_LineFromText ('LINESTRING (' ||
                                     x1 || ' ' || y1 ||
                                     ',' ||
                                     x1 - distance || ' ' || y1 - (x1 - (x1 - distance)) / (x2 - x1) * (y2 - y1) ||
                                     ')', 4326)
                     ELSE
                       ST_LineFromText ('LINESTRING (' ||
                                     x1 || ' ' || y1 ||
                                     ',' ||
                                     x1 + distance || ' ' || y1 - (x1 - (x1 + distance)) / (x2 - x1) * (y2 - y1) ||
                                     ')', 4326)
                END
                ELSE
                CASE WHEN x1 < x2
                     THEN
                       ST_LineFromText ('LINESTRING (' ||
                                     x2 || ' ' || y2 || ',' ||
                                     x2 + distance || ' ' || y2 + ((x2 + distance) - x2) / (x2 - x1) * (y2 - y1) || ')', 4326)
                     ELSE
                       ST_LineFromText ('LINESTRING (' ||
                                     x2 || ' ' || y2 || ',' ||
                                     x2 - distance || ' ' || y2 + ((x2 - distance) - x2) / (x2 - x1) * (y2 - y1) || ')', 4326)

                END
            END AS geom,
            distance
       FROM (
        SELECT id,
               typ,
               ST_X(ST_StartPoint(geom)) AS x1,
               ST_Y(ST_StartPoint(geom)) AS y1,
               ST_X(ST_EndPoint(geom))   AS x2,
               ST_Y(ST_EndPoint(geom))   AS y2,
               2000.0::NUMERIC / (111319.9 * COS ((RADIANS (ST_Y(ST_StartPoint(geom))) + RADIANS (ST_Y(ST_EndPoint(geom)))) / 2)) AS distance
          FROM (
            SELECT id,
                   0 AS typ,
                   ST_GeometryN (geom, 1) AS geom
              FROM link
         UNION ALL
            SELECT id,
                   1 AS typ,
                   ST_GeometryN (geom, ST_NumGeometries (geom))
              FROM link
          ) AS lg
       ) AS lp
         JOIN link AS l
              ON lp.id = l.id
  ) AS ll
;

CREATE INDEX link_extension_link_idx ON link_extension USING BTREE (link_id);
ANALYZE VERBOSE link_extension (link_id);

CREATE INDEX link_extension_type_idx ON link_extension USING BTREE (typ);
ANALYZE VERBOSE link_extension (typ);

-- extended link geometry
DROP TABLE IF EXISTS link_extended;

CREATE TABLE link_extended (
  link_id  INTEGER,
  geom     GEOMETRY (MULTILINESTRING, 4326)
);

-- extend the link each way by approximately 2000 m
-- any edge points that do not project onto this line are ignored
INSERT INTO link_extended (link_id, geom)
SELECT ll.link_id,
       ST_Multi (ST_Union (ll.geom, le.geom)) AS geom
  FROM (
    SELECT l.id AS link_id,
           ST_Multi (ST_Union (ls.geom, l.geom)) AS geom
      FROM link AS l
      JOIN link_extension AS ls
           ON l.id = ls.link_id
     WHERE ls.typ = 0
     ) AS ll
  JOIN link_extension AS le
       ON ll.link_id = le.link_id
 WHERE le.typ = 1
;

CREATE INDEX link_extended_id_idx ON link_extended USING BTREE (link_id);
ANALYZE VERBOSE link_extended (link_id);

CREATE INDEX link_extended_geom_idx ON link_extended USING GiST (geom);
ANALYZE VERBOSE link_extended (geom);

--
-- for efficient geometry operations store and index all related network paths segmented between shape points
-- and it's corresponding projected version on the trafficmodel link linestring
--

DROP TABLE IF EXISTS link_network_edge_segment;

-- line segments for network and corresponding projected geometry on trafficmodel link
CREATE TABLE link_network_edge_segment (
  link_id                    INTEGER,
  link_network_candidate_id  INTEGER,
  network_edge_id            INTEGER,
  segment                    SMALLINT,
  geom                       GEOMETRY (LINESTRING, 4326),
  proj                       GEOMETRY (LINESTRING, 4326)
);

-- extract segments from network and projected segments from trafficmodel link
-- respect wayness of the links and edges and need to deal with two and one way sub-edge segments
-- we do so by duplicating the segments of two way edges as two one ways for all edges in each route path
-- this logic is meant only for two-way segments, ensure we filter one-ways that do not follow the
-- Traffic Model link
INSERT INTO link_network_edge_segment (link_id, link_network_candidate_id, network_edge_id, segment, geom, proj)
SELECT DISTINCT ON (link_id, link_network_candidate_id, network_edge_id, segment)
       link_id,
       link_network_candidate_id,
       network_edge_id,
       segment,
       geom,
       ST_MakeLine (proj_point1, proj_point2) AS proj
  FROM (
    SELECT lnc.link_id,
           lnc.id      AS link_network_candidate_id,
           e.gid       AS network_edge_id,
           nep.segment AS segment,
           CASE WHEN ST_Line_Locate_Point (l.geom, ST_PointN(nep.geom, segment)) < 
                     ST_Line_Locate_Point (l.geom, ST_PointN(nep.geom, segment + 1))
                THEN
                  ST_LineFromText ('LINESTRING (' || ST_X(ST_PointN(nep.geom, segment)) || ' ' || ST_Y(ST_PointN(nep.geom, segment)) ||
                                           ',' || ST_X(ST_PointN(nep.geom, segment + 1)) || ' ' || ST_Y(ST_PointN(nep.geom, segment + 1)) || ')',
                                4326)
                ELSE
                  ST_LineFromText ('LINESTRING (' || ST_X(ST_PointN(nep.geom, segment + 1)) || ' ' || ST_Y(ST_PointN(nep.geom, segment + 1)) ||
                                           ',' || ST_X(ST_PointN(nep.geom, segment)) || ' ' || ST_Y(ST_PointN(nep.geom, segment)) || ')',
                                4326)
           END AS geom,
           CASE WHEN ST_Line_Locate_Point (l.geom, ST_PointN(nep.geom, segment)) < 
                     ST_Line_Locate_Point (l.geom, ST_PointN(nep.geom, segment + 1))
                THEN ST_PointN(nep.geom, segment)
                ELSE ST_PointN(nep.geom, segment + 1)
           END AS edge_point1,
           CASE WHEN ST_Line_Locate_Point (l.geom, ST_PointN(nep.geom, segment)) < 
                     ST_Line_Locate_Point (l.geom, ST_PointN(nep.geom, segment + 1))
                THEN ST_PointN(nep.geom, segment + 1)
                ELSE ST_PointN(nep.geom, segment)
           END AS edge_point2,
           CASE WHEN ST_Line_Locate_Point (l.geom, ST_PointN(nep.geom, segment)) =
                     ST_Line_Locate_Point (l.geom, ST_PointN(nep.geom, segment + 1))
                THEN CASE WHEN ST_Line_Locate_Point (l.geom, ST_PointN(nep.geom, segment)) = 1
                         THEN ST_Line_Interpolate_Point (
                                  l.geom,
                                  ST_Line_Locate_Point (l.geom, ST_PointN(nep.geom, segment)) - 0.00001
                              )
                         ELSE
                              ST_Line_Interpolate_Point (
                                  l.geom,
                                  ST_Line_Locate_Point (l.geom, ST_PointN(nep.geom, segment))
                              )
                     END
                WHEN ST_Line_Locate_Point (l.geom, ST_PointN(nep.geom, segment)) < 
                     ST_Line_Locate_Point (l.geom, ST_PointN(nep.geom, segment + 1))
                THEN ST_Line_Interpolate_Point (
                         l.geom,
                         ST_Line_Locate_Point (l.geom, ST_PointN(nep.geom, segment))
                     )
                ELSE ST_Line_Interpolate_Point (
                         l.geom,
                         ST_Line_Locate_Point (l.geom, ST_PointN(nep.geom, segment + 1))
                     )
           END AS proj_point1,
           CASE WHEN ST_Line_Locate_Point (l.geom, ST_PointN(nep.geom, segment)) =
                     ST_Line_Locate_Point (l.geom, ST_PointN(nep.geom, segment + 1))
                THEN CASE WHEN ST_Line_Locate_Point (l.geom, ST_PointN(nep.geom, segment)) = 1
                          THEN ST_Line_Interpolate_Point (
                                   l.geom,
                                   ST_Line_Locate_Point (l.geom, ST_PointN(nep.geom, segment))
                               )
                          ELSE ST_Line_Interpolate_Point (
                                   l.geom,
                                   ST_Line_Locate_Point (l.geom, ST_PointN(nep.geom, segment)) + 0.00001
                               )
                     END
                WHEN ST_Line_Locate_Point (l.geom, ST_PointN(nep.geom, segment)) < 
                     ST_Line_Locate_Point (l.geom, ST_PointN(nep.geom, segment + 1))
                THEN ST_Line_Interpolate_Point (
                         l.geom,
                         ST_Line_Locate_Point (l.geom, ST_PointN(nep.geom, segment + 1))
                     )
                ELSE ST_Line_Interpolate_Point (
                         l.geom,
                         ST_Line_Locate_Point (l.geom, ST_PointN(nep.geom, segment))
                     )
           END AS proj_point2
      FROM link_network_candidate AS lnc
      JOIN link_network_candidate_path AS lncp
           ON lnc.id = lncp.link_network_candidate_id
      JOIN network.edges AS e
           ON lncp.network_path_edge_id = e.gid
    LEFT JOIN
           osm.way_tags AS oneway
           ON e.osm_id  = oneway.way_id AND
              oneway.k ILIKE 'oneway' AND
              oneway.v ILIKE 'yes'
      JOIN (
        SELECT gid,
               ST_LineMerge (the_geom) AS geom,
               GENERATE_SERIES(1, ST_NumPoints (ST_LineMerge(the_geom)) - 1) AS segment
          FROM network.edges
         ) AS nep
           ON e.gid = nep.gid
      JOIN (
        SELECT link_id,
               ST_GeometryN(geom, i) AS geom
          FROM (
            SELECT link_id,
                   geom,
                   GENERATE_SERIES (1, ST_NumGeometries(geom)) AS i
              FROM link_extended
             ) AS ll
         ) AS l
           ON lnc.link_id = l.link_id
     WHERE oneway.way_id IS NULL OR
           (oneway.way_id IS NOT NULL AND
            (
             ST_Line_Locate_Point (l.geom, ST_PointN(nep.geom, 1)) <=
             ST_Line_Locate_Point (l.geom, ST_PointN(nep.geom, ST_NumPoints (nep.geom))) AND
             ST_Line_Locate_Point (l.geom, ST_PointN(nep.geom, segment)) <=
             ST_Line_Locate_Point (l.geom, ST_PointN(nep.geom, segment + 1))
            )
           )
      ) AS cand
WHERE (
        ABS(ABS((ST_Azimuth (edge_point1, proj_point1) 
               - ST_Azimuth (proj_point1, proj_point2)) * 180.0 / PI())::INTEGER % 90) <= 1.0 OR
        ABS(ABS((ST_Azimuth (edge_point2, proj_point2)
               - ST_Azimuth (proj_point1, proj_point2)) * 180.0 / PI())::INTEGER % 90) <= 1.0
     )
ORDER BY link_id, link_network_candidate_id, network_edge_id, segment
;

-- index used by point extraction and statistics
CREATE INDEX link_network_edge_segment_seq_idx ON link_network_edge_segment USING BTREE (segment);
ANALYZE VERBOSE link_network_edge_segment (segment);

-- index on primary join columns 
CREATE INDEX link_network_edge_segment_link_idx ON link_network_edge_segment USING BTREE (link_id);
ANALYZE VERBOSE link_network_edge_segment (link_id);

CREATE INDEX link_network_edge_segment_idx
  ON link_network_edge_segment USING BTREE (link_network_candidate_id, network_edge_id);
ANALYZE VERBOSE link_network_edge_segment (link_network_candidate_id, network_edge_id);

-- geometry index for spatial operations
CREATE INDEX link_network_edge_segment_geom_idx ON link_network_edge_segment USING GiST (geom);
ANALYZE VERBOSE link_network_edge_segment (geom);

CREATE INDEX link_network_edge_segment_proj_idx ON link_network_edge_segment USING GiST (proj);
ANALYZE VERBOSE link_network_edge_segment (proj);

-- network candidates that have a complete route path
DROP TABLE IF EXISTS link_network_candidate_complete_path;

CREATE TABLE link_network_candidate_complete_path (
  link_network_candidate_id INTEGER,
  path_cost                 NUMERIC
);
  
-- filter route paths that did not reach destinations, these will produce false statistics
INSERT INTO link_network_candidate_complete_path (link_network_candidate_id, path_cost)
SELECT lnepc.link_network_candidate_id,
       lnepc.path_cost
  FROM (
    SELECT link_network_candidate_id,
           SUM(network_path_cost) AS path_cost,
           COUNT(*) AS edge_count
      FROM link_network_candidate_path
     WHERE network_path_edge_id <> -1
  GROUP BY link_network_candidate_id
     ) AS lnepc
  JOIN (
    SELECT link_network_candidate_id,
           COUNT(*) AS edge_count
      FROM link_network_edge_segment
     WHERE segment = 1
  GROUP BY link_network_candidate_id
      ) AS lnesp
       ON lnepc.link_network_candidate_id = lnesp.link_network_candidate_id AND
          lnepc.edge_count = lnesp.edge_count;

CREATE INDEX link_network_candidate_complete_path_idx
    ON link_network_candidate_complete_path USING BTREE (link_network_candidate_id);

ANALYZE VERBOSE link_network_candidate_complete_path_idx (link_network_candidate_id);

-- calculate route path length for complete candidate network paths only
DROP TABLE IF EXISTS link_network_candidate_path_length;

CREATE TABLE link_network_candidate_path_length (
  link_network_candidate_id INTEGER,
  path_length               NUMERIC
);

INSERT INTO link_network_candidate_path_length (link_network_candidate_id, path_length)
SELECT lncp.link_network_candidate_id,
       SUM (ST_Length(e.the_geom)) AS path_length
  FROM link_network_candidate_path AS lncp
  JOIN link_network_candidate_complete_path AS lnepc
       ON lncp.link_network_candidate_id = lnepc.link_network_candidate_id
  JOIN network.edges AS e
       ON lncp.network_path_edge_id = e.gid
GROUP BY lncp.link_network_candidate_id;
 
CREATE INDEX link_network_candidate_path_length_idx
    ON link_network_candidate_path_length USING BTREE (link_network_candidate_id);

ANALYZE VERBOSE link_network_candidate_path_length_idx (link_network_candidate_id);

DROP TABLE IF EXISTS link_network_candidate_path_error;

CREATE TABLE link_network_candidate_path_error (
  link_id                   INTEGER,
  link_network_candidate_id INTEGER,
  azimuth_rmse              NUMERIC,
  proj_rmse                 NUMERIC,
  distance_rmse             NUMERIC,
  length_error              NUMERIC,
  node_error                NUMERIC,
  path_cost                 NUMERIC,
  mbr_error                 NUMERIC
);

INSERT INTO link_network_candidate_path_error (link_id, link_network_candidate_id, azimuth_rmse, proj_rmse,
                                               distance_rmse, length_error, node_error, path_cost,
                                               mbr_error)
SELECT lnc.link_id,
       lnc.id AS link_network_candidate_id,
       lncpe.azimuth_rmse,
       lncpe.proj_rmse,
       lncpe.distance_rmse,
       ABS ( ST_Length (l.geom) - lncpl.path_length) AS length_error,
       SQRT ( POW (lnc.network_source_node_error, 2) + POW (lnc.network_target_node_error, 2) ) AS node_error,
       lnepc.path_cost,
       lncpe.mbr_error
  FROM link_network_candidate AS lnc
  JOIN link AS l
       ON lnc.link_id = l.id
  JOIN link_network_candidate_complete_path AS lnepc
       ON lnc.id = lnepc.link_network_candidate_id
  JOIN link_network_candidate_path_length AS lncpl
        ON lnc.id = lncpl.link_network_candidate_id
  JOIN (
    SELECT link_network_candidate_id,
           SQRT (SUM (POW (azimuth_error, 2)) / COUNT(*)) AS azimuth_rmse,
           SQRT (SUM (POW (length_error, 2)) / COUNT(*)) AS proj_rmse,
           SQRT ( ((SUM (POW (distance_error1, 2)) / COUNT(*)) + (SUM (POW (distance_error2, 2)) / COUNT(*))) / 2 ) AS distance_rmse,
           ST_Area (
             ST_SymDifference (
               ST_Expand (l.geom, 0.00000000001),  
               ST_SetSRID (
                 ST_MakeBox2D (ST_Point (MIN(minx), MIN(miny)), ST_Point (MAX(maxx), MAX(maxy))),
                 4326
               )
             )
           )
           / (ST_Area (ST_Expand (l.geom, 0.00000000001)) +
              ST_Area (
               ST_SetSRID (
                 ST_MakeBox2D (ST_Point (MIN(minx), MIN(miny)), ST_Point (MAX(maxx), MAX(maxy))),
                 4326
               )
              )) AS mbr_error
      FROM (
        SELECT lnc.link_id,
               lncp.link_network_candidate_id,
               lnes.network_edge_id, 
               lnes.segment,
               ABS (ST_Azimuth (ST_StartPoint(lnes.geom), ST_EndPoint(lnes.geom)) - 
                    ST_Azimuth (ST_StartPoint(lnes.proj), ST_EndPoint(lnes.proj))) AS azimuth_error,
               ABS (ST_length (lnes.geom) - ST_Length(lnes.proj)) AS length_error,
               ABS (COALESCE (ST_Distance (ST_StartPoint(lnes.geom), ST_StartPoint(lnes.proj)), 0.01)) AS distance_error1,
               ABS (COALESCE (ST_Distance (ST_EndPoint(lnes.geom), ST_EndPoint(lnes.proj)), 0.01)) AS distance_error2,
               CASE WHEN ST_X (ST_StartPoint(lnes.geom)) < ST_X (ST_EndPoint(lnes.geom))
                    THEN ST_X (ST_StartPoint(lnes.geom)) 
                    ELSE ST_X (ST_EndPoint(lnes.geom))
               END AS minx,
               CASE WHEN ST_Y (ST_StartPoint(lnes.geom)) < ST_Y (ST_EndPoint(lnes.geom))
                    THEN ST_Y (ST_StartPoint(lnes.geom)) 
                    ELSE ST_Y (ST_EndPoint(lnes.geom))
               END AS miny,
               CASE WHEN ST_X (ST_StartPoint(lnes.geom)) > ST_X (ST_EndPoint(lnes.geom))
                    THEN ST_X (ST_StartPoint(lnes.geom)) 
                    ELSE ST_X (ST_EndPoint(lnes.geom))
               END AS maxx,
               CASE WHEN ST_Y (ST_StartPoint(lnes.geom)) > ST_Y (ST_EndPoint(lnes.geom))
                    THEN ST_Y (ST_StartPoint(lnes.geom)) 
                    ELSE ST_Y (ST_EndPoint(lnes.geom))
               END AS maxy
          FROM link_network_candidate      AS lnc
          JOIN link_network_candidate_path AS lncp
               ON lnc.id = lncp.link_network_candidate_id
          JOIN link_network_edge_segment   AS lnes
               ON lncp.link_network_candidate_id = lnes.link_network_candidate_id AND
                  lncp.network_path_edge_id      = lnes.network_edge_id
         WHERE lncp.network_path_edge_id <> -1
          ) AS prmse
       JOIN trafficmodel.link AS l
            ON prmse.link_id = l.id
  GROUP BY link_network_candidate_id, l.geom
      ) AS lncpe
        ON lnc.id = lncpe.link_network_candidate_id
;
ANALYZE VERBOSE link_network_candidate_path_error;

DROP TABLE IF EXISTS link_network_candidate_path_rank;

CREATE TABLE link_network_candidate_path_rank (
  link_id                   INTEGER,
  link_network_candidate_id INTEGER,
  rank_index                NUMERIC
);

--
-- rank candidate paths according to a measure of shape and distance deviation, displacement and path
-- length and cost error from Traffic Model link
--
-- filter bad matches using the following thresholds:
--
-- 1. path cost of 1000
-- 2. RMSE of projected link to path edge segment distance error of ~200m scaled by cosine of latitude
-- 3. node displacement error of ~200m scaled by cosine of latitude for all non-motorway links
--
-- to prevent bogus matches from contributing, all ones that fail need to fall back to
-- plain closest match and take it as it is
--
INSERT INTO link_network_candidate_path_rank (link_id, link_network_candidate_id, rank_index)
SELECT link_id,
       link_network_candidate_id,
       (
         mbr_error_scaled     *  5.0::NUMERIC +
         node_error_scaled    *  2.0::NUMERIC +
         distance_rmse_scaled *  2.0::NUMERIC +
         length_error_scaled  *  1.0::NUMERIC +
         proj_rmse_scaled     /  2.0::NUMERIC +
         azimuth_rmse_scaled  /  2.0::NUMERIC +
         path_cost_scaled     /  3.0::NUMERIC
       ) / 7.0::NUMERIC AS rank_index
  FROM (
    SELECT lncpr.link_id,
           lncpr.link_network_candidate_id,
           CASE WHEN (azimuth_rmse_max - azimuth_rmse_min) <= 0.00000001
                THEN 0
                ELSE
                  (lncpr.azimuth_rmse - azimuth_rmse_min) / (azimuth_rmse_max - azimuth_rmse_min)
           END AS azimuth_rmse_scaled,
           CASE WHEN (proj_rmse_max - proj_rmse_min) <= 0.00000001
                THEN 0
                ELSE
                  (lncpr.proj_rmse - proj_rmse_min) / (proj_rmse_max - proj_rmse_min)
           END AS proj_rmse_scaled,
           CASE WHEN (distance_rmse_max - distance_rmse_min) <= 0.00000001
                THEN 0
                ELSE
                  (lncpr.distance_rmse - distance_rmse_min) / (distance_rmse_max - distance_rmse_min)
           END AS distance_rmse_scaled,
           CASE WHEN (length_error_max - length_error_min) <= 0.00000001
                THEN 0
                ELSE
                  (lncpr.length_error - length_error_min) / (length_error_max - length_error_min)
           END AS length_error_scaled,
           CASE WHEN (node_error_max - node_error_min) <= 0.00000001
                THEN 0
                ELSE
                  (lncpr.node_error - node_error_min) / (node_error_max - node_error_min)
           END AS node_error_scaled,
           CASE WHEN (path_cost_max - path_cost_min) <= 0.00000001
                THEN 0
                ELSE
                  (lncpr.path_cost - path_cost_min) / (path_cost_max - path_cost_min)
           END AS path_cost_scaled,
           CASE WHEN (mbr_error_max - mbr_error_min) <= 0.00000001
                THEN 0
                ELSE
                  (lncpr.mbr_error - mbr_error_min) / (mbr_error_max - mbr_error_min)
           END AS mbr_error_scaled
       FROM link_network_candidate_path_error AS lncpr
      JOIN (
        SELECT l.id AS link_id, 
               MIN (azimuth_rmse)  AS azimuth_rmse_min,
               MAX (azimuth_rmse)  AS azimuth_rmse_max,
               MIN (proj_rmse)     AS proj_rmse_min,
               MAX (proj_rmse)     AS proj_rmse_max,
               MIN (distance_rmse) AS distance_rmse_min,
               MAX (distance_rmse) AS distance_rmse_max,
               MIN (length_error)  AS length_error_min,
               MAX (length_error)  AS length_error_max,
               MIN (node_error)    AS node_error_min,
               MAX (node_error)    AS node_error_max,
               MIN (path_cost)     AS path_cost_min,
               MAX (path_cost)     AS path_cost_max,
               MIN (mbr_error)     AS mbr_error_min,
               MAX (mbr_error)     AS mbr_error_max
          FROM link_network_candidate_path_error AS lncpe
          JOIN link AS l
               ON lncpe.link_id = l.id
      GROUP BY l.id
         ) AS rrmse
        ON lncpr.link_id = rrmse.link_id
      JOIN link AS l
        ON lncpr.link_id = l.id
     WHERE lncpr.path_cost <= 1000
       AND lncpr.distance_rmse <= COS(RADIANS(ST_Y(ST_Centroid(l.geom)))) * 0.002
       AND (
                l.type_id IN (19, 20, 21) 
                OR
                (
                    l.type_id NOT IN (19, 20, 21) 
                    AND
                    lncpr.node_error <= COS(RADIANS(ST_Y(ST_Centroid(l.geom)))) * 0.002
                )
           )
  ) AS srmse
;

ANALYZE VERBOSE link_network_candidate_path_rank;

CREATE INDEX link_network_candidate_path_rank_idx1 ON link_network_candidate_path_rank USING BTREE (link_id);
CREATE INDEX link_network_candidate_path_rank_idx2 ON link_network_candidate_path_rank USING BTREE (rank_index);
ANALYZE VERBOSE link_network_candidate_path_rank (link_id);
ANALYZE VERBOSE link_network_candidate_path_rank (rank_index);

--
-- link the best network path to the Traffic Model link
--
INSERT INTO link_network (traffic_link_id, network_edge_id, fraction, snapped, geom)
SELECT DISTINCT
       lnc.link_id AS traffic_link_id, 
       ne.gid      AS network_edge_id,
       l.length / nel.length * ne.length / l.length AS fraction,
       FALSE AS snapped,
       ne.the_geom AS geom
  FROM (
    SELECT link_id, MIN(rank_index) AS best_rank_index
      FROM link_network_candidate_path_rank
  GROUP BY link_id
    ) AS lncpb
  JOIN link_network_candidate_path_rank AS lncpr
       ON lncpb.link_id         = lncpr.link_id AND
          lncpb.best_rank_index = lncpr.rank_index
  JOIN link_network_candidate AS lnc
       ON lncpr.link_id                   = lnc.link_id AND
          lncpr.link_network_candidate_id = lnc.id
  JOIN link_network_candidate_path AS lncp
       ON lnc.id = lncp.link_network_candidate_id
  JOIN network.edges AS ne
       ON lncp.network_path_edge_id = ne.gid
  JOIN (
    SELECT c.id, SUM(e.length) AS length
      FROM link_network_candidate AS c
      JOIN link_network_candidate_path AS p
           ON c.id = p.link_network_candidate_id
      JOIN network.edges AS e
           ON p.network_path_edge_id = e.gid
  GROUP BY c.id
    ) AS nel
       ON lnc.id = nel.id
  JOIN link AS l
       ON lnc.link_id = l.id
;

ANALYZE VERBOSE link_network;

-- all link that rejected all their candidate network edge paths now have to resort
-- to primitive snapping to transfer it's Traffic Model attributes to the closest edge
DROP TABLE IF EXISTS link_network_snapped_node;

CREATE TABLE link_network_snapped_node (
  traffic_node_id    INTEGER NOT NULL,
  network_edge_id INTEGER NOT NULL,
  network_node_id INTEGER NOT NULL,
  geom            GEOMETRY (POINT, 4326)
);

-- pick the closer of the two edge node as the equivalent road node
-- use route cost and angular deviation to scale distance
INSERT INTO link_network_snapped_node (traffic_node_id, network_edge_id, network_node_id, geom)
SELECT DISTINCT ON (traffic_node_id)
       traffic_node_id, 
       network_edge_id,
       network_node_id,
       ST_Line_Interpolate_Point (
         edge_geom, 
         ST_Line_Locate_Point (edge_geom, node_geom)
       ) AS geom
  FROM (
    SELECT n.id AS traffic_node_id,
           e.gid AS network_edge_id,
           n.geom AS node_geom,
           ST_LineMerge (e.the_geom) AS edge_geom,
           CASE WHEN ST_GeometryType (ST_LineMerge (l.geom)) ~ 'Multi'
                THEN ABS (
                        ST_Azimuth (
                            ST_StartPoint (e.the_geom),
                            ST_EndPoint (e.the_geom)
                        ) 
                        - 
                        ST_Azimuth (                 
                           ST_StartPoint(ST_GeometryN(l.geom, 1)),
                           ST_EndPoint (ST_GeometryN(l.geom, ST_NumGeometries (l.geom)))
                        )
                    )
                    * c.cost * ST_Distance (n.geom, e.the_geom)
                ELSE ABS (
                        ST_Azimuth (
                            ST_StartPoint (e.the_geom),
                            ST_EndPoint (e.the_geom)
                        ) 
                        - 
                        ST_Azimuth (
                            ST_StartPoint (ST_LineMerge(l.geom)),
                            ST_EndPoint (ST_LineMerge(l.geom))
                        )
                    )
                    * c.cost * ST_Distance (n.geom, e.the_geom)
           END AS distance,
           CASE WHEN ST_Distance (n.geom, ST_StartPoint (e.the_geom)) <=
                     ST_Distance (n.geom, ST_EndPoint (e.the_geom))
                THEN e.source
                ELSE e.target
           END AS network_node_id
      FROM (
        SELECT id AS link_id
          FROM trafficmodel.link
        EXCEPT
        SELECT traffic_link_id AS link_id
          FROM trafficmodel.link_network
         ) AS m
      JOIN trafficmodel.link AS l
           ON m.link_id = l.id
      JOIN trafficmodel.link_road_class AS lrc
           ON l.id = lrc.link_id
      JOIN trafficmodel.node AS n
           ON l.start_node_id = n.id OR
              l.end_node_id = n.id
      JOIN network.edges AS e
           ON n.geom && ST_Expand (e.the_geom, 0.0201397760129886)
      JOIN network.classes AS c
           ON e.class_id = c.id
      JOIN network.types AS t
           ON c.type_id = t.id
    WHERE t.name = 'highway'
      AND c.name = ANY (lrc.road_classes)
  ORDER BY traffic_node_id, distance
    ) AS cd
;

CREATE INDEX link_network_snapped_node_idx      ON link_network_snapped_node USING BTREE (traffic_node_id);
CREATE INDEX link_network_snapped_node_edge_idx ON link_network_snapped_node USING BTREE (network_edge_id);

ANALYZE VERBOSE link_network_snapped_node;

DROP TABLE IF EXISTS link_network_snapped;

CREATE TABLE link_network_snapped (
  id              SERIAL,
  traffic_link_id    INTEGER NOT NULL,
  network_edge_id INTEGER NOT NULL,
  geom            GEOMETRY (LINESTRING, 4326)
);

INSERT INTO link_network_snapped (traffic_link_id, network_edge_id, geom)
SELECT ls.link_id AS traffic_link_id,
       e.gid AS network_edge_id,
       e.the_geom AS geom
  FROM (
    SELECT l.id AS link_id,
           ST_MakeLine (lsn.geom, len.geom) AS geom,
           public.shortest_path_astar(
             'SELECT e.gid AS id, 
                      e.source::int4,
                      e.target::int4,
                      (e.length * cc.cost)::float8 AS cost,
                      (e.reverse_cost * cc.cost)::float8 AS reverse_cost,
                      e.x1, 
                      e.y1,
                      e.x2,
                      e.y2
                 FROM network.edges AS e
                 JOIN network.costing_options AS co
                      ON co.option = ''vehicle''
                 JOIN network.class_costs AS cc
                      ON e.class_id = cc.class_id AND
                         co.id = cc.option_id
                 JOIN network.classes AS c
                      ON e.class_id = c.id
                 JOIN network.types AS t
                      ON c.type_id = t.id
                WHERE t.name = ''highway''',
              lsn.network_node_id, 
              len.network_node_id, 
              TRUE, 
              TRUE) AS path
      FROM trafficmodel.link AS l
      JOIN (
        SELECT id AS link_id
          FROM trafficmodel.link
        EXCEPT
        SELECT traffic_link_id AS link_id
          FROM trafficmodel.link_network
         ) AS m
           ON l.id = m.link_id
      JOIN trafficmodel.link_network_snapped_node AS lsn
           ON l.start_node_id = lsn.traffic_node_id
      JOIN trafficmodel.link_network_snapped_node AS len
           ON l.end_node_id = len.traffic_node_id
    ) AS ls
  JOIN trafficmodel.link AS l
       ON ls.link_id = l.id
  JOIN network.edges AS e
       ON (ls.path).edge_id = e.gid
 WHERE ST_Expand (l.geom, 0.201397760129886) && e.the_geom
UNION ALL
SELECT l.id AS traffic_link_id,
       e.gid AS network_edge_id,
       e.the_geom AS geom
  FROM trafficmodel.link AS l
  JOIN (
    SELECT id AS link_id
      FROM trafficmodel.link
    EXCEPT
    SELECT traffic_link_id AS link_id
      FROM trafficmodel.link_network
     ) AS m
       ON l.id = m.link_id
  JOIN trafficmodel.link_network_snapped_node AS lsn
       ON l.start_node_id = lsn.traffic_node_id
  JOIN trafficmodel.link_network_snapped_node AS len
       ON l.end_node_id       = len.traffic_node_id AND
          lsn.network_node_id = len.network_node_id AND
          lsn.network_edge_id = len.network_edge_id
  JOIN network.edges AS e
       ON lsn.network_edge_id = e.gid
;

CREATE INDEX link_network_snapped_idx ON link_network_snapped USING BTREE (traffic_link_id);

ANALYZE VERBOSE link_network_snapped;

INSERT INTO link_network (traffic_link_id, network_edge_id, fraction, snapped, geom)
SELECT lns.traffic_link_id,
       lns.network_edge_id,
       (ST_Length (l.geom) / lnse.length) * (ST_Length (lns.geom) / ST_Length (l.geom)) AS fraction,
       TRUE AS snapped,
       lns.geom
  FROM trafficmodel.link_network_snapped AS lns
  JOIN (
    SELECT traffic_link_id,
           SUM (ST_Length (geom)) AS length
      FROM trafficmodel.link_network_snapped
  GROUP BY traffic_link_id
  ) AS lnse
       ON lns.traffic_link_id = lnse.traffic_link_id
  JOIN trafficmodel.link AS l
       ON lns.traffic_link_id = l.id;

ANALYZE VERBOSE link_network;

-- find Traffic Model road nodes adjacent to a gap
-- filling in Traffic Model gaps
--
-- find gap nodes as nodes that have only one connected Traffic Model edge per road class
-- find neighboring edges of same road class as edge connected to gap node inside gap
-- iterate through neighbors of the gap node neighboring edge following topology in the correct direction
-- iteration halts when next Traffic Model road node is found or when candidates are too far away
-- some paths may loop back unto themselves, these are truncated at loop node
-- when two candidate edges are available to fill an Traffic Model gap the closest one is chosen
-- add these gap edges to link_network and update all portions for the edges snapped for a Traffic Model link
--
SET search_path = trafficmodel, public;

DROP TABLE IF EXISTS gap_node;

CREATE TABLE gap_node (
  node_id INTEGER NOT NULL,
  class_id INTEGER NOT NULL
);

INSERT INTO gap_node (node_id, class_id)
SELECT nn.id AS node_id,
       c.id AS class_id
  FROM trafficmodel.link_network AS ln
  JOIN network.edges AS ne
       ON ln.network_edge_id = ne.gid
  JOIN network.nodes AS nn
       ON ne.source = nn.id OR
          ne.target = nn.id
  JOIN trafficmodel.link_road_class AS lrc
       ON ln.traffic_link_id = lrc.link_id
  JOIN network.classes AS c
       ON ne.class_id = c.id AND
          c.name = ANY (lrc.road_classes)
  JOIN network.types AS t
       ON c.type_id = t.id AND
          t.name = 'highway'
  JOIN trafficmodel.link AS l
       ON ln.traffic_link_id = l.id
LEFT JOIN (
    SELECT node_id
      FROM (
        SELECT start_node_id AS node_id
          FROM trafficmodel.link
     UNION ALL
        SELECT end_node_id AS node_id
          FROM trafficmodel.link
      ) AS ln
  GROUP BY node_id
    HAVING COUNT (*) = 1
     ) AS vn
       ON l.start_node_id = vn.node_id OR
          l.end_node_id = vn.node_id
 WHERE vn.node_id IS NULL
   AND c.id < (SELECT id FROM network.classes WHERE name = 'residential')
 GROUP BY nn.id, c.id
HAVING COUNT(*) = 1;

CREATE INDEX gap_node_idx ON gap_node USING BTREE (node_id);
ANALYZE VERBOSE gap_node;

DROP TABLE IF EXISTS gap_candidate_edge;

CREATE TABLE gap_candidate_edge (
  edge_id      INTEGER  NOT NULL,
  class_id     INTEGER  NOT NULL,
  link_id      INTEGER  NOT NULL,
  traverse_end BOOLEAN  NOT NULL,
  sequence     SMALLINT NOT NULL
);

--
-- try to fill in simple traffic gaps, search up to ~ 1km
-- 
INSERT INTO gap_candidate_edge (edge_id, class_id, link_id, traverse_end, sequence)
  WITH RECURSIVE gap_intermediate_edge AS (
    SELECT edge_id,
           class_id,
           link_id,
           traverse_end,
           sequence
      FROM (
        SELECT me.gid AS edge_id,
               me.class_id,
               sln.traffic_link_id AS link_id,
               CASE WHEN gn.node_id = se.target
                    THEN TRUE
                    ELSE FALSE
               END AS traverse_end,
               1 AS sequence,
               RANK () OVER(
                 PARTITION BY sln.traffic_link_id
                     ORDER BY CASE WHEN gn.node_id = se.target
                                   THEN
                                        ST_Azimuth (ST_PointN (se.the_geom, ST_NumPoints (se.the_geom) - 1),
                                                    ST_PointN (se.the_geom, ST_NumPoints (se.the_geom)))
                                        -
                                        ST_Azimuth (ST_PointN (me.the_geom, 1),
                                                    ST_PointN (me.the_geom, 2))
                                   ELSE
                                        ST_Azimuth (ST_PointN (se.the_geom, 1), 
                                                    ST_PointN (se.the_geom, 2))
                                        -
                                        ST_Azimuth (ST_PointN (me.the_geom, ST_NumPoints (me.the_geom) - 1),
                                                    ST_PointN (me.the_geom, ST_NumPoints (me.the_geom)))
                              END
                     DESC
               ) AS rank
          FROM trafficmodel.gap_node AS gn
          JOIN network.edges AS se
               ON (gn.node_id = se.source OR
                   gn.node_id = se.target) AND
                   gn.class_id <= se.class_id 
          JOIN trafficmodel.link_network AS sln
               ON se.gid = sln.network_edge_id
          JOIN trafficmodel.link AS l
               ON sln.traffic_link_id = l.id
          JOIN network.edges AS me
               ON (gn.node_id = se.target AND gn.node_id = me.source) OR
                  (gn.node_id = se.source AND gn.node_id = me.target)
          JOIN trafficmodel.link_road_class AS lrc
               ON sln.traffic_link_id = lrc.link_id
          JOIN network.classes AS c
               ON me.class_id = c.id AND
                  c.name = ANY (lrc.road_classes)
          JOIN network.types AS t
               ON c.type_id = t.id AND
                  t.name = 'highway'
     LEFT JOIN trafficmodel.link_network AS mln
               ON me.gid = mln.network_edge_id
         WHERE mln.id IS NULL
           AND se.the_geom && ST_Expand (l.geom, 0.00799985392679277)
           AND ST_Distance (ST_Centroid (se.the_geom), ST_Centroid (l.geom)) < 0.00799985392679277
      ) AS m
     WHERE rank = 1
     UNION
    SELECT gae.gid AS edge_id,
           gae.class_id,
           gie.link_id,
           gie.traverse_end,
           gie.sequence + 1
      FROM gap_intermediate_edge AS gie
      JOIN network.edges AS ge
           ON gie.edge_id = ge.gid
      JOIN network.edges AS gae
           ON ge.gid <> gae.gid AND
              ((gie.traverse_end = FALSE AND ge.source = gae.target) OR
               (gie.traverse_end = TRUE AND ge.target = gae.source))
      JOIN trafficmodel.link_road_class AS lrc
           ON gie.link_id = lrc.link_id
      JOIN network.classes AS c
           ON gae.class_id = c.id AND
              c.name = ANY (lrc.road_classes)
      JOIN network.types AS t
           ON c.type_id = t.id AND
              t.name = 'highway'
      JOIN trafficmodel.link AS gl
           ON gie.link_id = gl.id
 LEFT JOIN trafficmodel.link_network AS mln
           ON gae.gid = mln.network_edge_id
 LEFT JOIN trafficmodel.link AS ml
           ON mln.traffic_link_id = ml.id AND
              (gl.start_node_id = ml.end_node_id OR
               gl.end_node_id = ml.start_node_id)
 LEFT JOIN trafficmodel.gap_node AS gn
           ON ((gie.traverse_end = FALSE AND gae.target = gn.node_id) OR
               (gie.traverse_end = TRUE AND gae.source = gn.node_id)) AND
               ge.class_id <= gn.class_id
     WHERE mln.id IS NULL
       AND ml.id IS NULL
       AND gn.node_id IS NULL
       AND c.id < (SELECT id FROM network.classes WHERE name = 'residential')
       AND gae.the_geom && ST_Expand (gl.geom, 0.00799985392679277)
       AND ST_Distance (gae.the_geom, gl.geom) < 0.00799985392679277
)
SELECT * FROM gap_intermediate_edge;

CREATE INDEX gap_edge_idx ON gap_candidate_edge USING BTREE(edge_id);

ANALYZE VERBOSE gap_candidate_edge;

-- duplicates
-- remove the gap's candidate edge with the closest node to it's Traffic Model link - one ways considered only
DELETE FROM gap_candidate_edge
 WHERE (link_id, edge_id) IN (
    SELECT link_id,
           edge_id
      FROM (
        SELECT dge.link_id,
               dge.edge_id,
               RANK () OVER (
                 PARTITION BY dge.edge_id
                     ORDER BY CASE WHEN dge.traverse_end = TRUE
                                   THEN ST_Distance (ST_EndPoint (ne.the_geom), ST_StartPoint (ST_LineMerge(l.geom)))
                                   ELSE ST_Distance (ST_Startpoint (ne.the_geom), ST_StartPoint (ST_LineMerge(l.geom)))
                              END DESC
               ) AS rank
          FROM (
            SELECT edge_id
              FROM gap_candidate_edge 
            GROUP BY edge_id 
            HAVING COUNT(*) > 1
          ) AS dups
          JOIN trafficmodel.gap_candidate_edge AS dge
               ON dups.edge_id = dge.edge_id
          JOIN network.edges AS ne
               ON dups.edge_id = ne.gid
          JOIN trafficmodel.link AS l
               ON dge.link_id = l.id
      ) AS m
     WHERE rank > 1);

-- truncate paths where it's reached a no-exit and is recursively branching and returning to each node
-- creating an artificial branch of traffic
DELETE FROM gap_candidate_edge
 WHERE (link_id, sequence) IN (
    SELECT gae.link_id, 
           GENERATE_SERIES (MIN(gae.sequence)::INTEGER, m.max_sequence::INTEGER) AS sequence
      FROM gap_candidate_edge AS gae 
      JOIN (
         SELECT link_id,
                edge_id
           FROM gap_candidate_edge
       GROUP BY edge_id,
                link_id
         HAVING COUNT(*) > 1
         ) AS dups
           ON gae.link_id = dups.link_id AND
              gae.edge_id = dups.edge_id
      JOIN (
         SELECT link_id,
                MAX (sequence) AS max_sequence
           FROM gap_candidate_edge
       GROUP BY link_id
         ) AS m
           ON dups.link_id = m.link_id
     GROUP BY gae.link_id, m.max_sequence
  );

ANALYZE VERBOSE gap_candidate_edge;

INSERT INTO link_network (traffic_link_id, network_edge_id, fraction, snapped, filled, geom)
SELECT DISTINCT
       ge.link_id AS traffic_link_id,
       ge.edge_id AS network_edge_id,
       0.0 AS fraction,
       lns.snapped,
       TRUE AS filled,
       e.the_geom AS geom
  FROM gap_candidate_edge AS ge
  JOIN network.edges AS e
       ON ge.edge_id = e.gid
  JOIN (
      SELECT traffic_link_id,
             snapped
        FROM link_network
    GROUP BY traffic_link_id, snapped
     ) AS lns
       ON ge.link_id = lns.traffic_link_id;

ANALYZE VERBOSE gap_candidate_edge;

UPDATE link_network AS ln SET fraction = nn.fraction
  FROM (
    SELECT lne.traffic_link_id,
           lne.network_edge_id,
           l.length / nf.pathLength * ST_Length (lne.geom) / l.length AS fraction
      FROM (
        SELECT aln.traffic_link_id,
               SUM (ST_Length(geom)) AS pathLength
          FROM link_network AS aln
          JOIN (
            SELECT DISTINCT
                   traffic_link_id
              FROM link_network
             WHERE filled = TRUE
          ) AS ol
               ON aln.traffic_link_id = ol.traffic_link_id
      GROUP BY aln.traffic_link_id
      ) AS nf
      JOIN link AS l
           ON nf.traffic_link_id = l.id
      JOIN link_network AS lne
           ON nf.traffic_link_id = lne.traffic_link_id
  ) AS nn
 WHERE ln.traffic_link_id = nn.traffic_link_id AND
       ln.network_edge_id = nn.network_edge_id;

ANALYZE VERBOSE link_network;

SELECT 'ERROR: Unable to snap link: ' || id AS error
  FROM (
    SELECT id
      FROM trafficmodel.link
    EXCEPT
    SELECT traffic_link_id
      FROM trafficmodel.link_network
  ) AS m;

 
DO
$DROP_WORK_TABLES$
BEGIN
     IF (SELECT current_database()) !~ '(autotest|dev|test)'
     THEN
        -- remove temporary work tables when in not in development or test mode
        DROP TABLE link_road_class;
        DROP TABLE link_network_candidate_path;
        DROP TABLE link_network_candidate_path_error;
        DROP TABLE link_network_candidate_path_rank;
        DROP TABLE link_network_candidate_complete_path;
        DROP TABLE link_network_candidate_path_length;
        DROP TABLE gap_node;
        DROP TABLE gap_candidate_edge;
        DROP TABLE link_network_candidate;
        DROP TABLE link_extension;
        DROP TABLE link_extended;
        DROP TABLE link_network_edge_segment;
        DROP TABLE link_network_snapped_node;
        DROP TABLE link_network_snapped;
        DROP TABLE shape_node;
    END IF;
END
$DROP_WORK_TABLES$;
