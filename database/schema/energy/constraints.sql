SET search_path = energy, public;

-- energy producing activity
ALTER TABLE activity ADD CONSTRAINT activity_pk PRIMARY KEY(id);

ALTER TABLE activity ADD CONSTRAINT activity_uniq UNIQUE (code);

-- scenario
ALTER TABLE scenario ADD CONSTRAINT scenario_pk PRIMARY KEY(id);

ALTER TABLE scenario ADD CONSTRAINT scenario_uniq UNIQUE (code);

-- energy model definition
ALTER TABLE model_definition ADD CONSTRAINT model_definition_pk PRIMARY KEY(id);

ALTER TABLE model_definition ADD CONSTRAINT model_definition_activity_fk
  FOREIGN KEY (activity_id) REFERENCES activity (id);

ALTER TABLE model_definition ADD CONSTRAINT model_definition_scenario_fk
  FOREIGN KEY (scenario_id) REFERENCES scenario (id);

ALTER TABLE model_definition ADD CONSTRAINT model_definition_uniq UNIQUE (identifier);

-- energy model parameter
ALTER TABLE model_definition_part ADD CONSTRAINT model_definition_part_pk PRIMARY KEY(id);

ALTER TABLE model_definition_part ADD CONSTRAINT model_definition_part_parent_fk
  FOREIGN KEY (model_definition_id) REFERENCES model_definition (id);

ALTER TABLE model_definition_part ADD CONSTRAINT model_definition_part_census_class_fk
  FOREIGN KEY (census_class_id) REFERENCES census.class (id);

ALTER TABLE model_definition_part ADD CONSTRAINT model_definition_part_uniq
  UNIQUE (model_definition_id, census_class_id);

-- energy intensity
ALTER TABLE intensity ADD CONSTRAINT intensity_pk PRIMARY KEY(id);

ALTER TABLE intensity ADD CONSTRAINT intensity_model_definition_fk
  FOREIGN KEY (model_definition_id) REFERENCES model_definition (id);

ALTER TABLE intensity ADD CONSTRAINT intensity_census_area_fk
  FOREIGN KEY (census_admin_area_id) REFERENCES census.admin_area (id);

ALTER TABLE intensity ADD CONSTRAINT intensity_uniq
  UNIQUE (model_definition_id, census_admin_area_id, year);
