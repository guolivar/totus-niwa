"""
    Add network routing functionality to PostGIS datasource with pgRouting
"""

from FeatureServer.DataSource.PostGIS import PostGIS
from vectorformats.Feature import Feature
from vectorformats.Formats import WKT
from web_request.handlers import ApplicationException
from sys import stderr

try:
    import psycopg2 as psycopg
except:
    import psycopg

import copy
import re
import datetime

try:
    import decimal
except:
    pass

class PGRouting (PostGIS):
    """
       Network route datasource for PostGIS using pgRouting
    """
    
    # supported pgRouting methods
    routing_methods = [ "dijkstra", "astar", "shootingstar" ]

    # routeable parameters
    parameters = [ "routing_method" , "route_start" , "route_end", "costing_option" ]

    # snap threshold in degrees, ~55.5 km at equator
    distance_threshold = 0.5

    def __init__(self, name, **args):
        PostGIS.__init__(self, name, **args)
     
    def select (self, action):
        if not hasattr (action, 'parameters'):
            raise Exception("Server error: action class has no parameters field, it only has: %s" % ", ".join(vars(action)))
        elif not action.parameters.has_key('routing_method'):
            raise ApplicationException("No valid routing options supplied, need: %s" % ", ".join(self.parameters))
        else:
            cursor = self.db.cursor()

            # pgRouting join
            joins  = []

            route = action.parameters
            # route have been requested, verify params
            if not route.has_key('routing_method'):
                # must provide route method
                raise ApplicationException("No valid routing method supplied")

            # validate routing method
            if route["routing_method"] not in self.routing_methods:
                # routing method not supported
                raise ApplicationException("Requested routing method %s not supported, only %s" %
                                (route["routing_method"], ",".join(self.routing_methods)))

            # require both start and end geometry for route
            if not route.has_key('route_start') or not route.has_key('route_end'):
                raise ApplicationException ("Routing method: %s requires start and end position of route" % route["routing_method"])

            if not route.has_key('costing_option'):
                # default to distance based routing
                route["costing_option"] = 'distance'

            # validate start/end geometry in lat/lon
            (MIN_X, MIN_Y, MAX_X, MAX_Y) = ( -180, -90, +180, +90 )
            msg = "start"
            route_nodes = [];
            for geom in [ route["route_start"], route["route_end"] ]:
                if geom.find(" ") == -1:
                    raise ApplicationException ("Invalid %s node coordinate [%s], expecting format [lat lon]" % (msg, geom))

                try:
                    (x, y) = map (float, geom.split(" "))
                except ApplicationException, e:
                    raise ApplicationException ("Invalid %s node coordinate [%s]. Reason: %s" % (msg, geom, e.args))

                if x < MIN_X or x > MAX_X or y < MIN_Y or y > MAX_Y:
                    raise ApplicationException ("Invalid %s node coordinate [%g,%g]. Reason: Coordinate out of bounds"
                                     % (msg, x, y))
                # sub select for start/end edge
                route_nodes.append ( "closest_edge_node (%g, %g, %g)" % (x, y, self.distance_threshold));

                msg = "end"

            joins.append ( """
                JOIN (
                    SELECT route.edge_id,
                           ROW_NUMBER() OVER() AS sequence,
                           type.name AS type,
                           class.name AS class
                      FROM %s AS edge
                      JOIN classes AS class
                           ON edge.class_id = class.id
                      JOIN types AS type
                           ON class.type_id = type.id
                """ % (self.table))

            # construct call to pgRouting
            if route["routing_method"] == "dijkstra":
                joins.append( """
                      JOIN shortest_path(
                           'SELECT e.gid AS id, 
                                   e.source::INT4,
                                   e.target::INT4,
                                   (e.length * c.cost)::FLOAT8 AS cost,
                                   (e.reverse_cost * c.cost)::FLOAT8 AS reverse_cost
                              FROM %s AS e
                              JOIN costing_options AS o
                                   ON o.option = ''%s''
                              JOIN class_costs AS c
                                   ON e.class_id = c.class_id AND
                                      o.id = c.option_id',
                           (SELECT nodeId FROM %s),
                           (SELECT nodeId FROM %s),
                           true,
                           true) AS route
                        ON edge.gid = route.edge_id
                """ % (self.table, route["costing_option"], route_nodes[0], route_nodes[1]))
            elif route["routing_method"] == "astar":
                joins.append( """
                      JOIN shortest_path_astar(
                           'SELECT e.gid AS id, 
                                   e.source::INT4,
                                   e.target::INT4,
                                   (e.length * c.cost)::FLOAT8 AS cost,
                                   (e.reverse_cost * c.cost)::FLOAT8 AS reverse_cost,
                                   e.x1, 
                                   e.y1,
                                   e.x2,
                                   e.y2
                              FROM %s AS e
                              JOIN costing_options AS o
                                   ON o.option = ''%s''
                              JOIN class_costs AS c
                                   ON e.class_id = c.class_id AND
                                      o.id = c.option_id',
                           (SELECT nodeId FROM %s),
                           (SELECT nodeId FROM %s),
                           true,
                           true) AS route
                        ON edge.gid = route.edge_id
                """ % (self.table, route["costing_option"], route_nodes[0], route_nodes[1]))
            elif route["routing_method"] == "shootingstar":
                joins.append( """
                      JOIN shortest_path_shooting_star(
                           'SELECT e.gid AS id, 
                                   e.source::INT4,
                                   e.target::INT4,
                                   (e.length * c.cost)::FLOAT8 AS cost,
                                   (e.reverse_cost * c.cost)::FLOAT8 AS reverse_cost,
                                   e.x1,
                                   e.y1,
                                   e.x2,
                                   e.y2,
                                   e.rule,
                                   e.to_cost
                              FROM %s AS e
                              JOIN costing_options AS o
                                   ON o.option = ''%s''
                              JOIN class_costs AS c
                                   ON e.class_id = c.class_id AND
                                      o.id = c.option_id',
                           (SELECT id FROM %s),
                           (SELECT id FROM %s),
                           true,
                           true) AS route
                        ON edge.gid = route.edge_id
                """ % (self.table, route["costing_option"], route_nodes[0], route_nodes[1]))
            else:
                raise ApplicationException ("No support for route method: %s" % route["routing_method"])

            joins.append ("""
                ) AS m
                  ON %s.gid = m.edge_id
                """ % (self.table))

            sql = "SELECT ST_AsText(%s) as fs_text_geom, \"%s\", %s FROM \"%s\"" % (self.geom_col, self.fid_col, self.attribute_cols, self.table)
            sql += " ".join(joins)

            try:
                cursor.execute(str(sql))
            except Exception, e:
                raise ApplicationException ("<em>Internal error:</em><br><pre>%s</pre>" % (str (e)))
            
            result = cursor.fetchall()

            # column description from cursor
            columns = [desc[0] for desc in cursor.description]
            # output features
            features = []

            for row in result:
                if not row: continue

                # convert results into dictionary with column names as keys
                props = dict(zip(columns, row))

                # skip rows with no geometry
                if not props['fs_text_geom']: continue

                # store feature geometry and id, then remove them from result dict
                geom  = WKT.from_wkt(props['fs_text_geom'])
                id = props[self.fid_col]
                del props[self.fid_col]

                if self.attribute_cols == '*':
                    del props[self.geom_col]
                del props['fs_text_geom']
        
                # loop through remaining attribute items in result dict and apply type conversion
                for key, value in props.items():
                    if isinstance(value, str): 
                        props[key] = unicode(value, self.encoding)
                    elif isinstance(value, datetime.datetime) or isinstance(value, datetime.date):
                        # stringify datetimes 
                        props[key] = str(value)
                        
                    try:
                        if isinstance(value, decimal.Decimal):
                            props[key] = unicode(str(value), self.encoding)
                    except:
                        pass
                        
                # valid feature must have a geometry field, add it to output features
                if (geom):
                    features.append( Feature( id, geom, self.geom_col, self.srid_out, props ) ) 

            return features
