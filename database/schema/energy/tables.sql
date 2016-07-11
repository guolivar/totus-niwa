SET search_path = energy, public;

-- Energy intensity modelling schema
CREATE TABLE activity (
  id          SERIAL,
  code        VARCHAR(32) NOT NULL,
  description TEXT
);

COMMENT ON TABLE activity IS 'Energy intensity activity, eg. household heating by coal burning';

CREATE TABLE scenario (
  id          SERIAL,
  code        VARCHAR(32) NOT NULL,
  description TEXT
);

COMMENT ON TABLE scenario IS 'Energy intensity scenario, eg. continuity, emmissions concious';

CREATE TABLE model_definition (
  id           SERIAL,
  identifier   VARCHAR(64) NOT NULL,
  description  TEXT,
  activity_id  INTEGER     NOT NULL,
  scenario_id  INTEGER     NOT NULL,
  number_parts INTEGER     NOT NULL
);

COMMENT ON TABLE model_definition IS 'Model definition for producing energy intensity for an activity applied for a scenario';

CREATE TABLE model_definition_part (
  id                  SERIAL,
  model_definition_id INTEGER NOT NULL,
  census_class_id     INTEGER NOT NULL,
  equation            TEXT,
  coefficient         NUMERIC NOT NULL,
  part                INTEGER NOT NULL
);

COMMENT ON TABLE model_definition_part IS 'Define how to transform a census class value to a energy model equation part';

CREATE TABLE intensity (
  id                   SERIAL,
  census_admin_area_id INTEGER  NOT NULL,
  model_definition_id  INTEGER  NOT NULL,
  year                 SMALLINT NOT NULL,
  value                NUMERIC  NOT NULL
);

COMMENT ON TABLE intensity IS 'Energy intensity value for a specific model run';

CREATE TYPE definition_part AS (
  census_class        VARCHAR(32),
  equation            TEXT,
  coefficient         NUMERIC
);
