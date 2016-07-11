-- create OSM schema
CREATE SCHEMA osm AUTHORIZATION totus_admin;
COMMENT ON SCHEMA osm IS 'Open Street Map (OSM) simple schema';
GRANT USAGE ON SCHEMA osm TO totus_ingester;
GRANT USAGE ON SCHEMA osm TO totus;

-- create Network schema used for routing
CREATE SCHEMA network AUTHORIZATION totus_admin;
COMMENT ON SCHEMA network IS 'Routing network schema (derived from OSM)';
GRANT USAGE ON SCHEMA network TO totus_ingester;
GRANT USAGE ON SCHEMA network TO totus;

-- create traffic model schema
CREATE SCHEMA trafficmodel AUTHORIZATION totus_admin;
COMMENT ON SCHEMA trafficmodel IS 'Traffic model schema';
GRANT USAGE ON SCHEMA trafficmodel TO totus_ingester;
GRANT USAGE ON SCHEMA trafficmodel TO totus;

-- create Exposure schema
CREATE SCHEMA exposure AUTHORIZATION totus_admin;
COMMENT ON SCHEMA exposure IS 'Traffic Impact Factor (TIF) and exposure modelling schema';
GRANT USAGE ON SCHEMA exposure TO totus_ingester;
GRANT USAGE ON SCHEMA exposure TO totus;

-- create Census schema
CREATE SCHEMA census AUTHORIZATION totus_admin;
COMMENT ON SCHEMA census IS 'Population census schema';
GRANT USAGE ON SCHEMA census TO totus_ingester;
GRANT USAGE ON SCHEMA census TO totus;

-- create Energy schema
CREATE SCHEMA energy AUTHORIZATION totus_admin;
COMMENT ON SCHEMA energy IS 'Energy intensity modelling schema';
GRANT USAGE ON SCHEMA energy TO totus_ingester;
GRANT USAGE ON SCHEMA energy TO totus;
