SET search_path = public;

DROP AGGREGATE IF EXISTS ARRAY_ACCUM (ANYELEMENT);

CREATE AGGREGATE ARRAY_ACCUM (ANYELEMENT) (
  sfunc = array_append,
  stype = anyarray,
  initcond = '{}'
);

DROP FUNCTION IF EXISTS grant_schema_permissions (VARCHAR, VARCHAR[], VARCHAR);

CREATE FUNCTION grant_schema_permissions (
  schema   VARCHAR(32),
  grants   VARCHAR(32)[],
  roleName VARCHAR(32)
)
RETURNS VOID
AS
$_$
DECLARE
  i          INTEGER;
  j          INTEGER;
  tables     VARCHAR(255)[];
  sequences  VARCHAR(255)[];
  functions  VARCHAR(255)[];
  doGrant      BOOLEAN;
  seqGrant   VARCHAR(32);
BEGIN
  -- grant usage on schema
  EXECUTE 'GRANT USAGE ON SCHEMA ' || schema || ' TO ' || roleName;

  -- find all schema tables
  EXECUTE 'SELECT public.ARRAY_ACCUM (table_name::VARCHAR(255)) 
             FROM information_schema.tables
            WHERE table_schema = ' || quote_literal (schema)
    INTO tables;

  -- add all requested permissions to all of the schema tables
  FOR i IN SELECT GENERATE_SERIES (1, ARRAY_UPPER (grants, 1))
  LOOP
    FOR j IN SELECT GENERATE_SERIES (1, ARRAY_UPPER (tables, 1))
    LOOP
      EXECUTE '
        SELECT true
          FROM information_schema.role_table_grants
         WHERE grantee        = ' || quote_literal (roleName) || ' AND
               table_schema   = ' || quote_literal (schema) || ' AND
               table_name     = ' || quote_literal (tables[j]) || ' AND
               privilege_type = ' || quote_literal (grants[i])
        INTO doGrant;

      IF doGrant IS NULL
      THEN
        RAISE NOTICE 'Granting % permission on table: % to role: %', grants[i], tables[j], roleName;

        EXECUTE 'GRANT ' || grants[i] || ' ON TABLE ' || schema || '.' || tables[j] || ' TO ' || roleName;
      END IF;
    END LOOP;
  END LOOP;

  -- grant access to sequences
  EXECUTE 'SELECT public.ARRAY_ACCUM (sequence_name::VARCHAR(255))
             FROM information_schema.sequences
            WHERE sequence_schema = ' || quote_literal (schema)
     INTO sequences;

  -- add all requested permissions to all of the schema sequences
  FOR i IN SELECT GENERATE_SERIES (1, ARRAY_UPPER (grants, 1))
  LOOP
    IF grants[i] = 'INSERT'
    THEN
      seqGrant := 'UPDATE';
    ELSE
      seqGrant := grants[i];
    END IF;
   
    -- cannot grant DELETE on sequence
    IF seqGrant <> 'DELETE'
    THEN
      FOR j IN SELECT GENERATE_SERIES (1, ARRAY_UPPER (sequences, 1))
      LOOP
        EXECUTE 'GRANT ' || seqGrant || ' ON SEQUENCE ' || schema || '.' || sequences[j] || ' TO ' || roleName;
      END LOOP;
    END IF;
  END LOOP;

  -- grant execute rights to all schema functions
  EXECUTE 'SELECT public.ARRAY_ACCUM (f.oid::regprocedure)
             FROM pg_proc AS f 
             JOIN pg_namespace AS s 
                  ON f.pronamespace = s.oid
            WHERE s.nspname = ' || quote_literal (schema)
    INTO functions;

  -- grant execute permissions on functions
  FOR j IN SELECT GENERATE_SERIES (1, ARRAY_UPPER (functions, 1))
  LOOP
    EXECUTE '
      SELECT true
        FROM information_schema.routine_privileges
       WHERE grantee        = ' || quote_literal (roleName) || ' AND
             routine_schema = ' || quote_literal (schema) || ' AND
             routine_name   = ' || quote_literal (functions[j]) || ' AND
             privilege_type = ''EXECUTE'''
      INTO doGrant;

      IF doGrant IS NULL
      THEN
        RAISE NOTICE 'Granting EXECUTE permission on function: % to role: %', functions[j], roleName;

        EXECUTE 'GRANT EXECUTE ON FUNCTION ' || functions[j] || ' TO ' || roleName;
      END IF;
  END LOOP;
 
END;
$_$
LANGUAGE 'plpgsql' VOLATILE STRICT;
