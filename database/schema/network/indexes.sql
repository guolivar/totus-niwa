SET search_path = network;

CREATE INDEX edges_osm_id_idx      ON edges USING BTREE (osm_id);
CREATE INDEX edges_source_node_idx ON edges USING BTREE (source);
CREATE INDEX edges_target_node_idx ON edges USING BTREE (target);
CREATE INDEX edges_class_idx       ON edges USING BTREE (class_id);
CREATE INDEX edges_geom_idx        ON edges USING GiST (the_geom);

CREATE INDEX nodes_geom_idx        ON nodes USING GiST (the_geom);

CREATE INDEX class_costs_option_idx ON class_costs USING BTREE (option_id);
CREATE INDEX class_costs_class_idx  ON class_costs USING BTREE (class_id);

ANALYZE VERBOSE classes;
ANALYZE VERBOSE types;
ANALYZE VERBOSE edges;
ANALYZE VERBOSE nodes;
ANALYZE VERBOSE class_costs;
