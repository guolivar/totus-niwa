SET search_path = trafficmodel, public;

--
-- Traffic Model schema definition
--
CREATE TABLE version (
  id              SERIAL,
  traffic_model      VARCHAR(64), 
  transport_model VARCHAR(64),
  data_year       SMALLINT
);

COMMENT ON TABLE  version                 IS 'Holds traffic model, input transport model and data year information';
COMMENT ON COLUMN version.id              IS 'Unique key for Traffic Model version information';
COMMENT ON COLUMN version.traffic_model      IS 'Traffic model model version number';
COMMENT ON COLUMN version.transport_model IS 'Traffic model input transport model version number, eg. ATM2, ATM3, etc.';
COMMENT ON COLUMN version.data_year       IS 'Year of the data for which the traffic model was run';

CREATE TABLE link_type (
  id          INTEGER NOT NULL,
  type        VARCHAR(32),
  description TEXT
);

COMMENT ON TABLE link_type IS 'Traffic model link road class/type information';

CREATE TABLE congestion_function (
  id          INTEGER NOT NULL,
  function    VARCHAR(32),
  description TEXT
);     

COMMENT ON TABLE congestion_function IS 'Traffic model congestion function information, specific for the trip assignment model';

-- transport mode
CREATE TABLE transport_mode (
  id          SERIAL,
  mode        VARCHAR (32),
  description VARCHAR (32)
);

COMMENT ON TABLE transport_mode IS 'Transport mode information';

-- core tables
CREATE TABLE zone (
  id          SERIAL,
  traffic_id     INTEGER      NOT NULL,
  version_id  INTEGER      NOT NULL,
  sector      INTEGER      NOT NULL,
  sector_name VARCHAR(255),
  area_sqm    NUMERIC,
  geom        GEOMETRY (MULTIPOLYGON, 4326)
);

CREATE TABLE link (
  id              SERIAL,
  traffic_id         VARCHAR(16) NOT NULL,
  version_id      INTEGER     NOT NULL,
  start_node_id   INTEGER     NOT NULL,
  end_node_id     INTEGER     NOT NULL,
  length          NUMERIC     NOT NULL,
  type_id         INTEGER     NOT NULL,
  number_of_lanes SMALLINT,
  function_id     INTEGER     NOT NULL,
  geom            GEOMETRY (MULTILINESTRING, 4326)
);

COMMENT ON TABLE link IS 'Traffic model link geometry and core information';

CREATE TABLE link_transport_mode (
  id      SERIAL,
  link_id INTEGER NOT NULL,
  mode_id INTEGER NOT NULL
);  

COMMENT ON TABLE link_transport_mode IS 'Transport modes of Traffic Model links, eg. types of vehicles allowed in';

CREATE TABLE node (
  id         SERIAL,
  traffic_id    INTEGER NOT NULL,
  version_id INTEGER NOT NULL,
  x          NUMERIC NOT NULL,
  y          NUMERIC NOT NULL,
  iszone     BOOLEAN,
  geom       GEOMETRY (POINT, 4326)
);

CREATE TABLE traffic_peak (
  id          SERIAL,
  type        CHAR(2)     NOT NULL,
  description VARCHAR(64) NOT NULL
);

CREATE TABLE traffic_attribute (
  id          SERIAL,
  attribute   VARCHAR(64)  NOT NULL,
  data_type   VARCHAR(64)  NOT NULL,
  description TEXT         NOT NULL,
  version_id  INTEGER      NOT NULL
);

CREATE TABLE traffic_data (
  id           SERIAL,
  attribute_id INTEGER NOT NULL,
  value        NUMERIC NOT NULL
);

CREATE TABLE link_traffic_data (
  link_id    INTEGER  NOT NULL,
  data_id    INTEGER  NOT NULL,
  peak       CHAR(2)  NOT NULL,
  year       SMALLINT NOT NULL
);

CREATE TABLE node_traffic_data (
  node_id    INTEGER  NOT NULL,
  data_id    INTEGER  NOT NULL,
  peak       CHAR(2)  NOT NULL,
  year       SMALLINT NOT NULL
);

CREATE TABLE link_network (
  id               SERIAL,
  traffic_link_id     INTEGER NOT NULL,
  network_edge_id  INTEGER NOT NULL,
  fraction         NUMERIC (9, 8) NOT NULL,
  snapped          BOOLEAN NOT NULL,
  filled           BOOLEAN DEFAULT FALSE,
  geom             GEOMETRY (LINESTRING, 4326)
);

-- 
-- transport route Traffic Model links, eg. public transport, freight, etc.
--
CREATE TABLE route_attribute (
  id          SERIAL,
  attribute   VARCHAR(64)  NOT NULL,
  data_type   VARCHAR(64)  NOT NULL,
  description TEXT         NOT NULL
);

COMMENT ON TABLE route_attribute IS 'Route attribute definition, eg. only less than < x weight';

CREATE TABLE route_data (
  id           SERIAL,
  attribute_id INTEGER NOT NULL,
  value        TEXT
);

COMMENT ON TABLE route_data IS 'A route attribute instance';

CREATE TABLE transport_type (
  id          SERIAL,
  type        VARCHAR(64),
  mode_id     INTEGER NOT NULL,
  vehicle     VARCHAR(64),
  description TEXT
);

COMMENT ON TABLE transport_type IS 'Type of transport, eg. public, with mode of transport, eg. bus';

CREATE TABLE transport_route (
  id                SERIAL,
  route_identifier  VARCHAR(64),
  transport_type_id INTEGER NOT NULL,
  description       TEXT
);

COMMENT ON TABLE transport_route IS 'A Transport route definition';

CREATE TABLE transport_route_data (
  id            SERIAL,
  route_id      INTEGER NOT NULL,
  data_id       INTEGER NOT NULL 
);

COMMENT ON TABLE transport_route_data IS 'The attribute data for transport route';

CREATE TABLE transport_route_link (
  id       SERIAL,
  route_id INTEGER NOT NULL,
  link_id  INTEGER NOT NULL,
  sequence SMALLINT
);

COMMENT ON TABLE transport_route_link IS 'An Traffic Model link for the transport route';
