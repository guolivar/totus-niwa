"""
    Emme Route Traffic information

    Provided with a set of source and target coordinates, a routing method and costing option
    will perform a network route between each source and target set and return the Traffic Model route
    information
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

import datetime

try:
    import decimal
except:
    pass

class EmmeRoute (PostGIS):
    """
        The Traffic Model Route Datasource
    """

    # data source parameters, these are trusted by service and injected into action object
    parameters = [ "start_coordinates", "end_coordinates", "routing_method", "costing_option" ]

    def __init__(self, name, **args):
        PostGIS.__init__(self, name, **args)

    def checkParams (self, action):
        if not hasattr (action, 'parameters'):
            raise ApplicationException ("Invalid empty request for Traffic Model route, require: %s" % join (",", self.parameters))

        for parameter in self.parameters:
            if not action.parameters.has_key (parameter):
                raise ApplicationException ("Missing [%s] parameter from Traffic Model route query" % parameter)

    def getXCoordinates (self, coordinates):
        x = list()
        
        for coordinate in coordinates:
            point = coordinate.split(' ')

            if len (point) != 2:
                raise ApplicationException ("Invalid coordinate: %s in %s" % (coordinate, coordinates))

            x.append (point[0])

        return x

    def getYCoordinates (self, coordinates):
        y = list()
        
        for coordinate in coordinates:
            point = coordinate.split(' ')

            if len (point) != 2:
                raise ApplicationException ("Invalid coordinate: %s in %s" % (coordinate, coordinates))

            y.append (point[1])

        return y

    def select (self, action):
        self.checkParams (action)

        # split coordinate pairs of longitude and latitue to seperate lists
        startCoordinates = action.parameters['start_coordinates'].split(',')
        startx = self.getXCoordinates (startCoordinates)
        starty = self.getYCoordinates (startCoordinates)

        endCoordinates = action.parameters['end_coordinates'].split(',')
        endx = self.getXCoordinates (endCoordinates)
        endy = self.getYCoordinates (endCoordinates)

        # prepare cursor for extracting features
        cursor = self.db.cursor()

        sql  = "SELECT %s AS id, ST_AsText(%s) as fs_text_geom, %s FROM \"%s\"" % (self.fid_col, self.geom_col, self.attribute_cols, self.table)
        sql += "(ARRAY[%s], ARRAY[%s], ARRAY[%s], ARRAY[%s], '%s'::VARCHAR, '%s'::VARCHAR)" % ( \
                    ','.join (startx), \
                    ','.join (starty), \
                    ','.join (endx),   \
                    ','.join (endy),   \
                    action.parameters['routing_method'], \
                    action.parameters['costing_option']  \
                )

        try:
            cursor.execute(str(sql))
        except Exception, e:
            raise ApplicationException ("<em>Internal error:</em><br><pre>%s</pre>" % (str (e)))

        result = cursor.fetchall()

        # column names from cursor
        columns = [desc[0] for desc in cursor.description]

        # output features to return
        features = []

        for row in result:
            if not row: continue

            # convert result set row record into dictionary
            props = dict(zip(columns, row))

            # skip records with no geometry
            if not props['fs_text_geom']: continue

            geom = WKT.from_wkt(props['fs_text_geom'])

            # add feature id column and remove it from result set dictionary
            id = props[self.fid_col]
            del props[self.fid_col]

            # all attribute columns, including geometry have been selected, remove the duplicate
            if self.attribute_cols == '*':
                del props[self.geom_col]

            # no need for it anymore, geom is already been set
            del props['fs_text_geom']

            # attribute data for feature
            data = {}

            for key, value in props.items():
                data[key] = value     

            props.clear()

            # go through data fields and format according to type
            for key, value in data.items():
                if isinstance(value, str): 
                    data[key] = unicode(value, self.encoding)
                elif isinstance(value, datetime.datetime) or isinstance(value, datetime.date):
                    # stringify datetimes 
                    data[key] = str(value)
                    
                try:
                    if isinstance(value, decimal.Decimal):
                        data[key] = unicode(str(value), self.encoding)
                except:
                    pass

            if (geom):
                features.append( Feature( id, geom, self.geom_col, self.srid_out, data ) ) 

        return features
