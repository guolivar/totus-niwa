SET search_path = osm;

ALTER TABLE ONLY ways
    DROP CONSTRAINT ways_user_fkey;

ALTER TABLE ONLY nodes
    DROP CONSTRAINT nodes_user_fkey;

ALTER TABLE ONLY node_tags
    DROP CONSTRAINT node_tags_id_fkey;

ALTER TABLE ONLY relation_members
    DROP CONSTRAINT relation_members_id_fkey;

ALTER TABLE ONLY relation_tags
    DROP CONSTRAINT relation_tags_id_fkey;

ALTER TABLE ONLY way_nodes
    DROP CONSTRAINT way_nodes_id_fkey;

ALTER TABLE ONLY way_nodes
    DROP CONSTRAINT way_nodes_node_id_fkey;

ALTER TABLE ONLY way_tags
    DROP CONSTRAINT way_tags_id_fkey;
