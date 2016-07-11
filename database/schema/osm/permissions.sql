-- use grant_schema_permissions procedure to grant read-only permissions on tables and
-- sequences and execute permissions on all other schema function procedures to totus
SELECT * FROM public.grant_schema_permissions ('osm', ARRAY['SELECT'], 'totus');

-- use grant_schema_permissions procedure to grant insert permissions on tables and
-- sequences and execute permissions on all other schema function procedures to totus_admin
SELECT * FROM public.grant_schema_permissions ('osm', ARRAY['SELECT', 'INSERT'], 'totus_ingester');
