SET search_path = network, public;

--
-- copy of schema created by osm2pgrouting
--

CREATE TABLE types (
    id   INTEGER NOT NULL,
    name VARCHAR(200)
);

CREATE TABLE classes (
    id      INTEGER NOT NULL,
    type_id INTEGER,
    name    VARCHAR(200),
    cost    NUMERIC
);

CREATE TABLE edges (
    gid          SERIAL,
    osm_id       BIGINT,
    class_id     INTEGER,
    length       NUMERIC,
    name         VARCHAR(200),
    x1           NUMERIC,
    y1           NUMERIC,
    x2           NUMERIC,
    y2           NUMERIC,
    reverse_cost NUMERIC,
    rule         TEXT,
    to_cost      NUMERIC,
    source       INTEGER,
    target       INTEGER,
    the_geom     GEOMETRY (LINESTRING, 4326)
);

--
-- copy of table created by pgrouting assign_vertex_id
-- we use this table to link the edges to nodes (vertices)
--

CREATE TABLE nodes (
    id       SERIAL,
    the_geom GEOMETRY (POINT, 4326)
);

-- TOTUS tables added to facilitate scaling of cost based on route option
-- overwrites the default class costs
CREATE TABLE costing_options (
  id          SERIAL,
  option      VARCHAR(200),
  description TEXT
);

CREATE TABLE class_costs (
  id           SERIAL,
  option_id    INTEGER NOT NULL,
  class_id     INTEGER NOT NULL,
  cost         NUMERIC NOT NULL
);
