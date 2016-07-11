SET search_path = osm, public;

-- Add indexes to tables.
CREATE INDEX idx_node_tags_node_id ON node_tags USING btree (node_id);
CREATE INDEX idx_nodes_geom ON nodes USING gist (geom);
CREATE INDEX idx_way_tags_way_id ON way_tags USING btree (way_id);
CREATE INDEX idx_way_nodes_node_id ON way_nodes USING btree (node_id);
CREATE INDEX idx_relation_tags_relation_id ON relation_tags USING btree (relation_id);
CREATE INDEX idx_ways_bbox ON ways USING gist (bbox);
CREATE INDEX idx_ways_linestring ON ways USING gist (linestring);

ANALYZE VERBOSE schema_info;
ANALYZE VERBOSE users;
ANALYZE VERBOSE nodes;
ANALYZE VERBOSE node_tags;
ANALYZE VERBOSE ways;
ANALYZE VERBOSE way_nodes;
ANALYZE VERBOSE way_tags;
ANALYZE VERBOSE relations;
ANALYZE VERBOSE relation_members;
ANALYZE VERBOSE relation_tags;
ANALYZE VERBOSE actions;
