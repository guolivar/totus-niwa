SET search_path = osm, public;

-- drop indexes if exists, too slow to rebuild indexes
DROP INDEX IF EXISTS idx_ways_bbox;
DROP INDEX IF EXISTS idx_ways_linestring;

-- Update the bbox column of the way table.
UPDATE ways SET bbox = (
  SELECT ST_Expand (ST_Envelope(ST_Collect(geom)), 0.000001)
    FROM nodes 
    JOIN way_nodes 
         ON way_nodes.node_id = nodes.id
   WHERE way_nodes.way_id = ways.id
);

-- Update the linestring column of the way table.
UPDATE ways w SET linestring = (
  SELECT ST_MakeLine(c.geom) AS way_line 
    FROM (
      SELECT n.geom AS geom
        FROM nodes n 
        JOIN way_nodes wn 
             ON n.id = wn.node_id
       WHERE (wn.way_id = w.id) 
    ORDER BY wn.sequence_id
  ) c
);

CREATE INDEX idx_ways_bbox ON ways USING gist (bbox);
CREATE INDEX idx_ways_linestring ON ways USING gist (linestring);
