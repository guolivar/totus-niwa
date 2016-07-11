SET search_path = exposure, public;

CREATE INDEX no2_grid_geom_idx ON no2_grid USING GiST (geom);

CREATE INDEX grid_geom_idx ON grid USING GiST (geom);

CREATE INDEX grid_tif_edge_idx1 ON grid_tif_edge USING BTREE (grid_id);
CREATE INDEX grid_tif_edge_idx2 ON grid_tif_edge USING BTREE (edge_id);

ANALYZE VERBOSE no2_grid;
ANALYZE VERBOSE grid;
ANALYZE VERBOSE grid_tif_edge;
