-- add referential constraints on Traffic Model schema
--
SET search_path = trafficmodel;

--
-- Traffic Model schema constraints
--
ALTER TABLE version
  ADD CONSTRAINT version_pk PRIMARY KEY (id);

ALTER TABLE version
  ADD CONSTRAINT version_uniq UNIQUE (traffic_model, transport_model, data_year);

ALTER TABLE link_type 
  ADD CONSTRAINT link_type_pk PRIMARY KEY (id);

ALTER TABLE link_type
  ADD CONSTRAINT link_type_uniq UNIQUE (type);

ALTER TABLE congestion_function
  ADD CONSTRAINT congestion_function_pk PRIMARY KEY (id);

ALTER TABLE congestion_function
  ADD CONSTRAINT congestion_function_uniq UNIQUE (function);

ALTER TABLE transport_mode
  ADD CONSTRAINT transport_mode_pk PRIMARY KEY (id);

ALTER TABLE transport_mode
  ADD CONSTRAINT transport_mode_uniq UNIQUE (mode);

ALTER TABLE traffic_peak
  ADD CONSTRAINT traffic_peak_pk PRIMARY KEY (id);

ALTER TABLE traffic_peak
  ADD CONSTRAINT traffic_peak_uniq UNIQUE (type);

ALTER TABLE traffic_attribute
  ADD CONSTRAINT traffic_attribute_pk PRIMARY KEY (id);

ALTER TABLE traffic_attribute
  ADD CONSTRAINT traffic_attribute_uniq UNIQUE (attribute, version_id);

ALTER TABLE traffic_attribute
  ADD CONSTRAINT traffic_attribute_version_fk FOREIGN KEY (version_id) REFERENCES version (id);

ALTER TABLE traffic_data
  ADD CONSTRAINT traffic_data_pk PRIMARY KEY (id);

ALTER TABLE traffic_data
  ADD CONSTRAINT traffic_data_fk FOREIGN KEY (attribute_id) REFERENCES traffic_attribute (id);

ALTER TABLE zone
  ADD CONSTRAINT zone_pk PRIMARY KEY (id);

ALTER TABLE zone
  ADD CONSTRAINT zone_fk FOREIGN KEY (version_id) REFERENCES version (id);

ALTER TABLE zone
  ADD CONSTRAINT zone_uniq UNIQUE (traffic_id, version_id);

ALTER TABLE node
  ADD CONSTRAINT node_pk PRIMARY KEY (id);

ALTER TABLE node
  ADD CONSTRAINT node_version_fk FOREIGN KEY (version_id) REFERENCES version (id);

ALTER TABLE node
  ADD CONSTRAINT node_uniq UNIQUE (traffic_id, version_id);

ALTER TABLE link
  ADD CONSTRAINT link_pk PRIMARY KEY (id);

ALTER TABLE ONLY link
  ADD CONSTRAINT link_start_node_fk FOREIGN KEY (start_node_id) REFERENCES node(id);

ALTER TABLE link
  ADD CONSTRAINT link_end_node_fk FOREIGN KEY (end_node_id) REFERENCES node(id);

ALTER TABLE link
  ADD CONSTRAINT link_type_fk FOREIGN KEY (type_id) REFERENCES link_type (id);

ALTER TABLE link
  ADD CONSTRAINT link_function_fk FOREIGN KEY (function_id) REFERENCES congestion_function (id);

ALTER TABLE link
  ADD CONSTRAINT link_version_fk FOREIGN KEY (version_id) REFERENCES version (id);

ALTER TABLE link
  ADD CONSTRAINT link_uniq UNIQUE (traffic_id, version_id);

ALTER TABLE link_transport_mode
  ADD CONSTRAINT link_transport_mode_pk PRIMARY KEY (id);

ALTER TABLE link_transport_mode
  ADD CONSTRAINT link_transport_mode_fk1 FOREIGN KEY (link_id) REFERENCES link (id);

ALTER TABLE link_transport_mode
  ADD CONSTRAINT link_transport_mode_fk2 FOREIGN KEY (mode_id) REFERENCES transport_mode (id);

ALTER TABLE link_transport_mode
  ADD CONSTRAINT link_transport_mode_uniq UNIQUE (link_id, mode_id);

ALTER TABLE link_traffic_data
  ADD CONSTRAINT link_traffic_data_fk1 FOREIGN KEY (link_id) REFERENCES link (id);

ALTER TABLE link_traffic_data
  ADD CONSTRAINT link_traffic_data_fk2 FOREIGN KEY (data_id) REFERENCES traffic_data (id);

ALTER TABLE link_traffic_data
  ADD CONSTRAINT link_traffic_data_fk3 FOREIGN KEY (peak) REFERENCES traffic_peak (type);

ALTER TABLE node_traffic_data
  ADD CONSTRAINT node_traffic_data_fk1 FOREIGN KEY (node_id) REFERENCES node (id);

ALTER TABLE node_traffic_data
  ADD CONSTRAINT node_traffic_data_fk2 FOREIGN KEY (data_id) REFERENCES traffic_data (id);

ALTER TABLE node_traffic_data
  ADD CONSTRAINT node_traffic_data_fk3 FOREIGN KEY (peak) REFERENCES traffic_peak (type);

ALTER TABLE link_network
  ADD CONSTRAINT link_network_pk PRIMARY KEY (id);

ALTER TABLE link_network
  ADD CONSTRAINT link_network_traffic_fk FOREIGN KEY (traffic_link_id) REFERENCES link (id);

ALTER TABLE link_network
  ADD CONSTRAINT link_network_edge_fk FOREIGN KEY (network_edge_id) REFERENCES network.edges (gid);

ALTER TABLE link_network
  ADD CONSTRAINT link_network_fraction_check CHECK (fraction BETWEEN 0.0 AND 1.0);

ALTER TABLE link_network
  ADD CONSTRAINT link_network_uniq UNIQUE (traffic_link_id, network_edge_id);

ALTER TABLE transport_type
  ADD CONSTRAINT transport_type_pk PRIMARY KEY (id);

ALTER TABLE transport_type
  ADD CONSTRAINT transport_type_fk FOREIGN KEY (mode_id) REFERENCES transport_mode (id);

ALTER TABLE transport_route
  ADD CONSTRAINT transport_route_pk PRIMARY KEY(id);

ALTER TABLE transport_route
  ADD CONSTRAINT transport_route_fk 
  FOREIGN KEY (transport_type_id) REFERENCES transport_type (id);

ALTER TABLE transport_route
  ADD CONSTRAINT transport_route_uniq UNIQUE (route_identifier);

ALTER TABLE transport_route_link
  ADD CONSTRAINT transport_route_link_pk PRIMARY KEY (id);

ALTER TABLE transport_route_link
  ADD CONSTRAINT transport_route_link_parent_fk FOREIGN KEY (route_id) REFERENCES transport_route (id);

ALTER TABLE transport_route_link
  ADD CONSTRAINT transport_route_link_traffic_fk FOREIGN KEY (link_id) REFERENCES link (id);

ALTER TABLE transport_route_link
  ADD CONSTRAINT transport_route_link_uniq UNIQUE (route_id, link_id, sequence);

ALTER TABLE route_attribute
  ADD CONSTRAINT route_attribute_pk PRIMARY KEY (id);

ALTER TABLE route_data
  ADD CONSTRAINT route_data_pk PRIMARY KEY (id);

ALTER TABLE route_data
  ADD CONSTRAINT route_data_fk FOREIGN KEY (attribute_id) REFERENCES route_attribute (id);

ALTER TABLE route_data
  ADD CONSTRAINT route_data_uniq UNIQUE (attribute_id, value);

ALTER TABLE transport_route_data
  ADD CONSTRAINT transport_route_data_pk PRIMARY KEY (id);

ALTER TABLE transport_route_data
  ADD CONSTRAINT transport_route_data_fk1 FOREIGN KEY (route_id) REFERENCES transport_route (id);

ALTER TABLE transport_route_data
  ADD CONSTRAINT transport_route_data_fk2 FOREIGN KEY (data_id) REFERENCES route_data (id);

ALTER TABLE transport_route_data
  ADD CONSTRAINT transport_route_data_uniq UNIQUE (route_id, data_id);
