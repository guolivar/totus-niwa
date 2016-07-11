SET search_path = osm;

-- Add primary keys to tables.
ALTER TABLE ONLY schema_info
    ADD CONSTRAINT pk_schema_info PRIMARY KEY (version);

ALTER TABLE ONLY users
    ADD CONSTRAINT pk_users PRIMARY KEY (id);

ALTER TABLE ONLY nodes
    ADD CONSTRAINT pk_nodes PRIMARY KEY (id);

ALTER TABLE ONLY ways
    ADD CONSTRAINT pk_ways PRIMARY KEY (id);

ALTER TABLE ONLY way_nodes
    ADD CONSTRAINT pk_way_nodes PRIMARY KEY (way_id, sequence_id);

ALTER TABLE ONLY relations
    ADD CONSTRAINT pk_relations PRIMARY KEY (id);

ALTER TABLE ONLY relation_members
    ADD CONSTRAINT pk_relation_members PRIMARY KEY (relation_id, sequence_id);

ALTER TABLE ONLY actions
    ADD CONSTRAINT pk_actions PRIMARY KEY (data_type, id);

ALTER TABLE ONLY ways
    ADD CONSTRAINT ways_user_fkey FOREIGN KEY (user_id) REFERENCES users(id);

ALTER TABLE ONLY nodes
    ADD CONSTRAINT nodes_user_fkey FOREIGN KEY (user_id) REFERENCES users(id);

ALTER TABLE ONLY node_tags
    ADD CONSTRAINT node_tags_id_fkey FOREIGN KEY (node_id) REFERENCES nodes(id);

ALTER TABLE ONLY relation_members
    ADD CONSTRAINT relation_members_id_fkey FOREIGN KEY (relation_id) REFERENCES relations(id);

ALTER TABLE ONLY relation_tags
    ADD CONSTRAINT relation_tags_id_fkey FOREIGN KEY (relation_id) REFERENCES relations(id);

ALTER TABLE ONLY way_nodes
    ADD CONSTRAINT way_nodes_id_fkey FOREIGN KEY (way_id) REFERENCES ways(id);

ALTER TABLE ONLY way_nodes
    ADD CONSTRAINT way_nodes_node_id_fkey FOREIGN KEY (node_id) REFERENCES nodes(id);

ALTER TABLE ONLY way_tags
    ADD CONSTRAINT way_tags_id_fkey FOREIGN KEY (way_id) REFERENCES ways(id);
