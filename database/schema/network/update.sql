-- post load updates
SET search_path = network;

SELECT pg_catalog.setval('edges_gid_seq',
                         (SELECT MAX(gid) FROM edges),
                         true);

SELECT pg_catalog.setval('nodes_id_seq',
                         (SELECT MAX(id) FROM nodes),
                         true);
