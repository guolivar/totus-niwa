SET search_path = exposure, public;

DROP TABLE IF EXISTS grid_tif_edge;
DROP TABLE IF EXISTS grid;
DROP TABLE IF EXISTS no2_grid;

CREATE TABLE no2_grid (
  id   INTEGER NOT NULL,
  tif  NUMERIC NOT NULL,
  no2  NUMERIC NOT NULL,
  year SMALLINT NOT NULL,
  geom GEOMETRY (POLYGON, 4326)
);

CREATE TABLE grid (
  id   SERIAL,
  geom GEOMETRY (POLYGON, 4326)
);

CREATE TABLE grid_tif_edge (
  grid_id INTEGER NOT NULL,
  edge_id INTEGER NOT NULL,
  tif     NUMERIC NOT NULL,
  rank    INTEGER NOT NULL,
  year    SMALLINT NOT NULL
);
