SET search_path = trafficmodel, public;

CREATE OR REPLACE VIEW trafficmodel.network_node (
    id,
    edge_count,
    geom
) AS
SELECT DISTINCT
       n.id, c.count, n.the_geom
  FROM network.nodes AS n
  JOIN network.edges AS e
    ON n.id = e.source OR
       n.id = e.target
  JOIN trafficmodel.link_network AS ln
    ON e.gid = ln.network_edge_id
  JOIN trafficmodel.link_traffic_data AS ltd
    ON ln.traffic_link_id = ltd.link_id
  JOIN (
    SELECT n.id, COUNT(*) AS count
      FROM network.nodes AS n
      JOIN network.edges AS e
        ON n.id = e.source OR
           n.id = e.target
  GROUP BY n.id
  ) AS c
    ON n.id = c.id;

CREATE OR REPLACE VIEW trafficmodel.network_edge (
    network_id,
    start_node_id,
    end_node_id,
    type, 
    class, 
    name, 
    osm_id,
    am_phcv,
    am_vol,
    ip_phcv,
    ip_vol,
    pm_phcv,
    pm_vol,
    aadt_weekdays,
    aadt_weekends,
    year,
    geom
) AS
SELECT network_id, start_node_id, end_node_id,
       type, class, name, osm_id,
       AVG (am_phcv) AS am_phcv, AVG (am_vol) AS am_vol,
       AVG (ip_phcv) AS ip_phcv, AVG (ip_vol) AS ip_vol,
       AVG (pm_phcv) AS pm_phcv, AVG (pm_vol) AS pm_vol,
       -- 28 June 2012. Added AADT calculation according to traffic weights taken from WRR traffic modelling
       AVG (am_vol+pm_vol+10.059*ip_vol) AS aadt_weekdays,
       AVG (13.244*ip_vol) AS aadt_weekends,
       year,
       geom
  FROM (
    SELECT e.gid AS network_id,
           e.source AS start_node_id,
           e.target AS end_node_id,
           t.name AS type, c.name AS class, e.name, e.osm_id,
           -- Do not consider the link "fraction" because the traffic is a flow that is
           -- conserved through a link, i.e., if a link maps to 2 roads, the traffic flow
           -- on the link goes through both roads.
           am_phcv.value::NUMERIC AS am_phcv, am_vol.value::NUMERIC AS am_vol,
           ip_phcv.value::NUMERIC AS ip_phcv, ip_vol.value::NUMERIC AS ip_vol,
           pm_phcv.value::NUMERIC AS pm_phcv, pm_vol.value::NUMERIC AS pm_vol,
           am1.year,
           ST_LineMerge (e.the_geom) AS geom
      FROM trafficmodel.link_network AS ln
      JOIN network.edges AS e
           ON ln.network_edge_id = e.gid
      JOIN network.classes AS c
           ON e.class_id = c.id
      JOIN network.types AS t
           ON c.type_id = t.id
      JOIN trafficmodel.link_traffic_data AS am1
           ON ln.traffic_link_id = am1.link_id AND
              am1.peak = 'AM'
      JOIN trafficmodel.traffic_data AS am_phcv
           ON am1.data_id = am_phcv.id
      JOIN trafficmodel.traffic_attribute AS am_phcva
           ON am_phcv.attribute_id = am_phcva.id AND
              am_phcva.attribute = 'LkVehHCV_ALL'
      JOIN trafficmodel.link_traffic_data AS am2
           ON ln.traffic_link_id = am2.link_id AND
              am2.peak = 'AM' AND
              am2.year = am1.year
      JOIN trafficmodel.traffic_data AS am_vol
           ON am2.data_id = am_vol.id
      JOIN trafficmodel.traffic_attribute AS am_vola
           ON am_vol.attribute_id = am_vola.id AND
              am_vola.attribute = 'LkVehTotal'
      JOIN trafficmodel.link_traffic_data AS ip1
           ON ln.traffic_link_id = ip1.link_id AND
              ip1.peak = 'IP' AND
              ip1.year = am1.year
      JOIN trafficmodel.traffic_data AS ip_phcv
           ON ip1.data_id = ip_phcv.id
      JOIN trafficmodel.traffic_attribute AS ip_phcva
           ON ip_phcv.attribute_id = ip_phcva.id AND
              ip_phcva.attribute = 'LkVehHCV_ALL'
      JOIN trafficmodel.link_traffic_data AS ip2
           ON ln.traffic_link_id = ip2.link_id AND
              ip2.peak = 'IP' AND
              ip2.year = ip1.year
      JOIN trafficmodel.traffic_data AS ip_vol
           ON ip2.data_id = ip_vol.id
      JOIN trafficmodel.traffic_attribute AS ip_vola
           ON ip_vol.attribute_id = ip_vola.id AND
              ip_vola.attribute = 'LkVehTotal'
      JOIN trafficmodel.link_traffic_data AS pm1
           ON ln.traffic_link_id = pm1.link_id AND
              pm1.peak = 'PM' AND
              pm1.year = am1.year
      JOIN trafficmodel.traffic_data AS pm_phcv
           ON pm1.data_id = pm_phcv.id
      JOIN trafficmodel.traffic_attribute AS pm_phcva
           ON pm_phcv.attribute_id = pm_phcva.id AND
              pm_phcva.attribute = 'LkVehHCV_ALL'
      JOIN trafficmodel.link_traffic_data AS pm2
           ON ln.traffic_link_id = pm2.link_id AND
              pm2.peak = 'PM' AND
              pm2.year = pm1.year
      JOIN trafficmodel.traffic_data AS pm_vol
           ON pm2.data_id = pm_vol.id
      JOIN trafficmodel.traffic_attribute AS pm_vola
           ON pm_vol.attribute_id = pm_vola.id AND
              pm_vola.attribute = 'LkVehTotal'
  ) AS m
  GROUP BY network_id, start_node_id, end_node_id, 
           type, class, name, osm_id, year, geom;

GRANT SELECT ON trafficmodel.network_node TO TOTUS;
GRANT SELECT ON trafficmodel.network_edge TO TOTUS;
