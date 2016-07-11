SET search_path = exposure, public;

ALTER TABLE grid ADD CONSTRAINT grid_pk PRIMARY KEY (id);

ALTER TABLE grid_tif_edge ADD CONSTRAINT grid_tif_edge_fk1 FOREIGN KEY (grid_id)
  REFERENCES grid (id);

ALTER TABLE grid_tif_edge ADD CONSTRAINT grid_tif_edge_fk2 FOREIGN KEY (edge_id)
  REFERENCES network.edges (gid);

ALTER TABLE no2_grid ADD CONSTRAINT no2_grid_pk PRIMARY KEY (id);

ALTER TABLE no2_grid ADD CONSTRAINT no2_grid_fk FOREIGN KEY (id)
  REFERENCES grid (id);
