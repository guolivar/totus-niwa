SET search_path = trafficmodel;

--
-- Traffic Model schema indexes
--
CREATE INDEX link_start_node_id_idx ON link USING BTREE (start_node_id);
CREATE INDEX link_end_node_id_idx ON link USING BTREE (end_node_id);

CREATE INDEX link_geom_idx ON link USING GiST (geom);
CREATE INDEX node_geom_idx ON node USING GiST (geom);

CREATE INDEX link_traffic_data_idx1 ON link_traffic_data USING BTREE (link_id);
CREATE INDEX link_traffic_data_idx2 ON link_traffic_data USING BTREE (data_id);
CREATE INDEX link_traffic_data_idx3 ON link_traffic_data USING BTREE (peak);
CLUSTER link_traffic_data_idx3 ON link_traffic_data;
CREATE INDEX link_traffic_data_idx4 ON link_traffic_data USING BTREE (year);

CREATE INDEX node_traffic_data_idx1 ON node_traffic_data USING BTREE (node_id);
CREATE INDEX node_traffic_data_idx2 ON node_traffic_data USING BTREE (data_id);
CREATE INDEX node_traffic_data_idx3 ON node_traffic_data USING BTREE (peak);
CLUSTER node_traffic_data_idx3 ON node_traffic_data;
CREATE INDEX node_traffic_data_idx4 ON node_traffic_data USING BTREE (year);

CREATE INDEX link_network_idx1 ON link_network USING BTREE (traffic_link_id);
CREATE INDEX link_network_idx2 ON link_network USING BTREE (network_edge_id);

CREATE INDEX transport_route_link_idx1 ON transport_route_link USING BTREE (route_id);
CREATE INDEX transport_route_link_idx2 ON transport_route_link USING BTREE (link_id);

CREATE INDEX transport_route_data_idx1 ON transport_route_data USING BTREE (route_id);
CREATE INDEX transport_route_data_idx2 ON transport_route_data USING BTREE (data_id);

ANALYZE VERBOSE version;
ANALYZE VERBOSE link;
ANALYZE VERBOSE node;
ANALYZE VERBOSE traffic_peak;
ANALYZE VERBOSE traffic_attribute;
ANALYZE VERBOSE traffic_data;
ANALYZE VERBOSE link_traffic_data;
ANALYZE VERBOSE node_traffic_data;
ANALYZE VERBOSE link_network;
ANALYZE VERBOSE transport_type;
ANALYZE VERBOSE transport_route;
ANALYZE VERBOSE transport_route_link;
ANALYZE VERBOSE route_attribute;
ANALYZE VERBOSE route_data;
ANALYZE VERBOSE transport_route_data;
