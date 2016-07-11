SET search_path = census, public;

-- join indexes
CREATE INDEX admin_area_type_idx ON admin_area USING BTREE (admin_type_id);
CREATE INDEX admin_area_parent_idx ON admin_area USING BTREE (parent_id);
CREATE INDEX demographic_admin_area_idx ON demographic USING BTREE (admin_area_id);
CREATE INDEX demographic_class_idx ON demographic USING BTREE (class_id);

-- query indexes
CREATE INDEX demographic_year_idx ON demographic USING BTREE (year);

-- cluster demographic on year first (lower cardinality), then class
CREATE INDEX demographic_cluster_idx ON demographic USING BTREE (year, class_id);
CLUSTER demographic USING demographic_cluster_idx;

ANALYZE VERBOSE admin_area;
ANALYZE VERBOSE demographic;
