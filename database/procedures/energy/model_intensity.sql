--
-- Run a specific energy intensity model, cache and return results
--
SET search_path = energy, public;

DROP FUNCTION IF EXISTS model_intensity (VARCHAR(64), SMALLINT);

CREATE FUNCTION model_intensity (identifier VARCHAR(64), year SMALLINT)
RETURNS SETOF intensity
AS
$_$
DECLARE
  query      TEXT;
  energy     energy.intensity%ROWTYPE;
  result     RECORD;
  equations  TEXT[];
  modelId    INTEGER;
  part       INTEGER;
  alreadyRun BOOLEAN;
BEGIN
  EXECUTE 'SELECT id FROM energy.model_definition WHERE identifier = ' || QUOTE_LITERAL (identifier) INTO modelId;

  IF modelId IS NULL
  THEN
    RAISE EXCEPTION 'Model: % not found in the model definition table', identifier;
  END IF;

  -- check if model has been run already
  EXECUTE 'SELECT DISTINCT ON (id) TRUE 
             FROM energy.intensity
            WHERE model_definition_id = ' || modelId || '
              AND year = ' || year INTO alreadyRun;
  
  IF alreadyRun IS NULL OR alreadyRun <> TRUE
  THEN
    -- cache equations
    EXECUTE 'SELECT trafficmodel.ARRAY_ACCUM (
                      CASE WHEN equation IS NULL OR equation = ''''
                           THEN ''count * coefficient''
                           ELSE equation
                      END)
               FROM (
                 SELECT equation
                   FROM energy.model_definition_part
                  WHERE model_definition_id = ' || modelId || '
               ORDER BY part
               ) AS t' INTO equations;

    query := 'INSERT INTO energy.intensity (census_admin_area_id, model_definition_id, year, value)
              SELECT admin_area_id, 
                     model_definition_id,
                     year,
                     SUM (intensity_part) AS intensity
                FROM (';

    FOR part IN SELECT GENERATE_SERIES (1, ARRAY_UPPER (equations, 1))
    LOOP
      query := query || '
                  SELECT p.model_definition_id,
                         d.admin_area_id,
                         d.year, 
                         ' ||
                         equations[part] || ' AS intensity_part
                    FROM energy.model_definition_part AS p
                    JOIN census.demographic AS d
                         ON p.census_class_id = d.class_id
                   WHERE p.model_definition_id = ' || modelId || '
                     AND p.part = ' || part || '
                     AND d.year = ' || year;

      IF part <> ARRAY_UPPER (equations, 1)
      THEN
        query := query || '
                 UNION ALL';
      END IF;
    END LOOP;
                   
    query := query || '
                ) AS m
            GROUP BY model_definition_id, admin_area_id, year';

    RAISE NOTICE '   %', query;

    EXECUTE query;
  END IF;

  query := 'SELECT id, census_admin_area_id, model_definition_id, year, value
              FROM energy.intensity
             WHERE model_definition_id = ' || modelId || '
               AND year = ' || year;

  FOR result IN EXECUTE query
  LOOP
    energy.id                   := result.id;
    energy.census_admin_area_id := result.census_admin_area_id;
    energy.model_definition_id  := result.model_definition_id;
    energy.year                 := result.year;
    energy.value                := result.value;

    RETURN NEXT energy;
  END LOOP;

  RETURN;
END;
$_$
LANGUAGE 'plpgsql' VOLATILE STRICT
;
 
