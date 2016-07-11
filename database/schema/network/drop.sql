SET search_path = network;

-- drop
DROP SEQUENCE IF EXISTS edges_gid_seq;

ALTER TABLE ONLY edges
    DROP CONSTRAINT edges_osm_id_fkey;

ALTER TABLE ONLY edges
    DROP CONSTRAINT edges_source_node_fkey;

ALTER TABLE ONLY edges
    DROP CONSTRAINT edges_target_node_fkey;

ALTER TABLE ONLY edges
    DROP CONSTRAINT edges_class_fkey;

ALTER TABLE ONLY classes
    DROP CONSTRAINT classes_pkey;

ALTER TABLE ONLY classes
    DROP CONSTRAINT classes_type_fkey;

ALTER TABLE ONLY types
    DROP CONSTRAINT types_pkey;

ALTER TABLE ONLY nodes
    DROP CONSTRAINT nodes_pkey;

DROP INDEX edges_osm_id_idx;
