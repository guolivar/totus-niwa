SET search_path = network;

-- add
ALTER TABLE ONLY types
    ALTER COLUMN id SET NOT NULL;

ALTER TABLE ONLY types
    ADD CONSTRAINT types_pkey
    PRIMARY KEY (id);

ALTER TABLE ONLY types
    ADD CONSTRAINT types_uniq
    UNIQUE (name);

ALTER TABLE ONLY classes
    ALTER COLUMN id SET NOT NULL;

ALTER TABLE ONLY classes
    ADD CONSTRAINT classes_pkey
    PRIMARY KEY (id);

ALTER TABLE ONLY classes
    ADD CONSTRAINT classes_type_fkey 
    FOREIGN KEY (type_id) REFERENCES types (id);

ALTER TABLE ONLY classes
    ADD CONSTRAINT classes_uniq
    UNIQUE (type_id, name);

ALTER TABLE ONLY nodes
    ADD CONSTRAINT nodes_pkey
    PRIMARY KEY (id);

ALTER TABLE ONLY edges
    ADD CONSTRAINT edges_pk
    PRIMARY KEY (gid);

ALTER TABLE ONLY edges
    ADD CONSTRAINT edges_source_node_fkey 
    FOREIGN KEY (source) REFERENCES nodes (id);

ALTER TABLE ONLY edges
    ADD CONSTRAINT edges_target_node_fkey 
    FOREIGN KEY (target) REFERENCES nodes (id);

ALTER TABLE ONLY edges
    ADD CONSTRAINT edges_class_fkey 
    FOREIGN KEY (class_id) REFERENCES classes (id);

ALTER TABLE ONLY edges
    ADD CONSTRAINT edges_osm_id_fkey
    FOREIGN KEY (osm_id) REFERENCES osm.ways (id);

ALTER TABLE costing_options
    ADD CONSTRAINT costing_options_pkey
    PRIMARY KEY (id);

ALTER TABLE costing_options
    ADD CONSTRAINT costing_options_uniq
    UNIQUE (option);

ALTER TABLE class_costs
    ADD CONSTRAINT class_costs_pkey
    PRIMARY KEY (id);

ALTER TABLE class_costs
    ADD CONSTRAINT class_costs_uniq
    UNIQUE (option_id, class_id);

ALTER TABLE class_costs
    ADD CONSTRAINT class_costs_option_fkey
    FOREIGN KEY (option_id) REFERENCES costing_options (id);

ALTER TABLE class_costs
    ADD CONSTRAINT class_costs_class_fkey
    FOREIGN KEY (class_id) REFERENCES classes (id);
