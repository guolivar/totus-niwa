--
-- SQL stored procedure for configuring a Energy intensity model
--
SET search_path = energy, public;

DROP FUNCTION IF EXISTS configure_model_run (VARCHAR(64), TEXT, VARCHAR(32), VARCHAR(32), definition_part[]);
DROP TYPE IF EXISTS definition_part;

CREATE TYPE definition_part AS (
  census_class        VARCHAR(32),
  equation            TEXT,
  coefficient         NUMERIC
);
 
CREATE FUNCTION configure_model_run (
  identifier       VARCHAR(64),
  description      TEXT,
  activity         VARCHAR(32),
  scenario         VARCHAR(32),
  definition_parts definition_part[]
)
RETURNS TEXT
AS
$_$
DECLARE
  activityId INTEGER;
  scenarioId INTEGER;
  modelId    INTEGER;
  classId    INTEGER;
  i          INTEGER;
BEGIN
   
  -- find activity
  EXECUTE 'SELECT id FROM energy.activity WHERE code = ' || QUOTE_LITERAL (activity) INTO activityId;

  IF activityId IS NULL
  THEN
    RAISE EXCEPTION 'Activity: % not found in activity table', activity;
  END IF;

  -- find scenario
  EXECUTE 'SELECT id FROM energy.scenario WHERE code = ' || QUOTE_LITERAL (scenario) INTO scenarioId;

  IF scenarioId IS NULL
  THEN
    RAISE EXCEPTION 'Scenario: % not found in scenario table', scenario;
  END IF;

  -- create parent model definition record
  EXECUTE 'INSERT INTO energy.model_definition (identifier, description, activity_id, scenario_id, number_parts) 
           VALUES (' || QUOTE_LITERAL (identifier)  || ',' 
                     || QUOTE_LITERAL (description) || ',' 
                     || activityId  || ',' 
                     || scenarioId  || ',' 
                     || ARRAY_LENGTH (definition_parts, 1) || ')';

  -- find the model definition just inserted
  EXECUTE 'SELECT id FROM energy.model_definition WHERE identifier = ' || QUOTE_LITERAL (identifier) INTO modelId;

  -- loop through each model definition part provided and create part records
  FOR i IN SELECT GENERATE_SERIES (1, ARRAY_UPPER (definition_parts, 1))
  LOOP
    -- find census class
    EXECUTE 'SELECT id FROM census.class WHERE code = ' || QUOTE_LITERAL ((definition_parts[i]).census_class) INTO classId;

    IF classId IS NULL
    THEN
      RAISE EXCEPTION 'Census class: % not found in census class table', (definition_parts[i]).census_class;
    END IF;

    -- create child model definition part record
    EXECUTE 'INSERT INTO energy.model_definition_part (model_definition_id, census_class_id, equation, coefficient, part)
             VALUES (' || modelId || ','
                       || classId || ','
                       || QUOTE_LITERAL ((definition_parts[i]).equation) || ','
                       || (definition_parts[i]).coefficient || ','
                       || i || ')';
  END LOOP;

  RETURN 'Energy intensity model: ' || identifier || ' ready';
END;
$_$
LANGUAGE 'plpgsql' VOLATILE STRICT
;
  
