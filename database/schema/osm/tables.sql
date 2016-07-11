SET search_path = osm, public;

-- Taken from:
-- ../../thirdparty/osmosis/script/pgsql_simple_schema_0.6.sql
-- ../../thirdparty/osmosis/script/pgsql_simple_schema_0.6_action.sql
-- ../../thirdparty/osmosis/script/pgsql_simple_schema_0.6_linestring.sql  
-- ../../thirdparty/osmosis/script/pgsql_simple_schema_0.6_bbox.sql

-- Database creation script for the simple PostgreSQL schema.

-- Create a table which will contain a single row defining the current schema version.
CREATE TABLE schema_info (
    version integer NOT NULL
);


-- Create a table for users.
CREATE TABLE users (
    id int NOT NULL,
    name text NOT NULL
);


-- Create a table for nodes.
CREATE TABLE nodes (
    id bigint NOT NULL,
    version int NOT NULL,
    user_id int NOT NULL,
    tstamp timestamp without time zone NOT NULL,
    changeset_id bigint NOT NULL,
    geom GEOMETRY (POINT, 4326)
);

-- Create a table for node tags.
CREATE TABLE node_tags (
    node_id bigint NOT NULL,
    k text NOT NULL,
    v text NOT NULL
);


-- Create a table for ways.
CREATE TABLE ways (
    id bigint NOT NULL,
    version int NOT NULL,
    user_id int NOT NULL,
    tstamp timestamp without time zone NOT NULL,
    changeset_id bigint NOT NULL,
    bbox GEOMETRY (POLYGON, 4326),
    linestring GEOMETRY (LINESTRING, 4326)
);

-- Create a table for representing way to node relationships.
CREATE TABLE way_nodes (
    way_id bigint NOT NULL,
    node_id bigint NOT NULL,
    sequence_id int NOT NULL
);


-- Create a table for way tags.
CREATE TABLE way_tags (
    way_id bigint NOT NULL,
    k text NOT NULL,
    v text
);


-- Create a table for relations.
CREATE TABLE relations (
    id bigint NOT NULL,
    version int NOT NULL,
    user_id int NOT NULL,
    tstamp timestamp without time zone NOT NULL,
    changeset_id bigint NOT NULL
);


-- Create a table for representing relation member relationships.
CREATE TABLE relation_members (
    relation_id bigint NOT NULL,
    member_id bigint NOT NULL,
    member_type character(1) NOT NULL,
    member_role text NOT NULL,
    sequence_id int NOT NULL
);


-- Create a table for relation tags.
CREATE TABLE relation_tags (
    relation_id bigint NOT NULL,
    k text NOT NULL,
    v text NOT NULL
);


-- Configure the schema version.
INSERT INTO schema_info (version) VALUES (5);

-- Add an action table for the purpose of capturing all actions applied to a database.
-- The table is populated during application of a changeset, then osmosisUpdate is called,
-- then the table is cleared all within a single database transaction.
-- The contents of this table can be used to update derivative tables by customising the
-- osmosisUpdate stored procedure.

-- Create a table for actions.
CREATE TABLE actions (
	data_type character(1) NOT NULL,
	action character(1) NOT NULL,
	id bigint NOT NULL
);
