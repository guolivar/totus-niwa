SET search_path = census, public;

--
--              +------------+     +------------+
--              | admin_type |<----| admin_area |<---------------+
--              +------------+     +------------+                |
--                                                         +-------------+
--                                                         | demographic |
--                                                         +-------------+
--       +-------+     +----------+     +-------+                |
--       | topic |<----| category |<----| class |<---------------+
--       +-------+     +----------+     +-------+
--

-- primary keys
ALTER TABLE admin_type ADD CONSTRAINT admin_type_pk PRIMARY KEY (id);
ALTER TABLE admin_area ADD CONSTRAINT admin_area_pk PRIMARY KEY (id);
ALTER TABLE topic ADD CONSTRAINT topic_pk PRIMARY KEY (id);
ALTER TABLE category ADD CONSTRAINT category_pk PRIMARY KEY (id);
ALTER TABLE class ADD CONSTRAINT class_pk PRIMARY KEY (id);
ALTER TABLE demographic ADD CONSTRAINT demographic_pk PRIMARY KEY (id);

-- foreign keys
ALTER TABLE admin_area ADD CONSTRAINT admin_area_type_fk
  FOREIGN KEY (admin_type_id) REFERENCES admin_type (id);

ALTER TABLE admin_area ADD CONSTRAINT admin_area_parent_fk
  FOREIGN KEY (parent_id) REFERENCES admin_area (id);

ALTER TABLE category ADD CONSTRAINT category_topic_fk
  FOREIGN KEY (topic_id) REFERENCES topic (id);

ALTER TABLE class ADD CONSTRAINT class_category_fk
  FOREIGN KEY (category_id) REFERENCES category (id);

ALTER TABLE demographic ADD CONSTRAINT demographic_admin_area_fk
  FOREIGN KEY (admin_area_id) REFERENCES admin_area (id);

ALTER TABLE demographic ADD CONSTRAINT demographic_class_fk
  FOREIGN KEY (class_id) REFERENCES class (id);

-- unique constraints
ALTER TABLE admin_type ADD CONSTRAINT admin_type_uniq UNIQUE (code);
ALTER TABLE admin_area ADD CONSTRAINT admin_area_uniq UNIQUE (census_identifier, admin_type_id, parent_id);
ALTER TABLE topic ADD CONSTRAINT topic_uniq UNIQUE (code);
ALTER TABLE category ADD CONSTRAINT category_uniq UNIQUE (code);
ALTER TABLE class ADD CONSTRAINT class_uniq UNIQUE (code);
ALTER TABLE demographic ADD CONSTRAINT demographic_uniq UNIQUE (admin_area_id, class_id, year);
