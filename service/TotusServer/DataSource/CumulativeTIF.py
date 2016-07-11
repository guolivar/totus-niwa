"""
    Cumulative TIF Datasource

    Provided with a list of coordinates, the number of Traffic Model roads to include, traffic
    impact dispersion factor and distance to which include roads calculates the cumulative
    TIF for given coordinates
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

class CumulativeTIF (PostGIS):
    """
        Cumulative TIF Datasource
    """

    # data source parameters, these are trusted by service and injected into action object
    parameters = [ "coordinates", "road_count", "dispersion_factor", "inclusion_distance" ]

    def __init__(self, name, **args):
        PostGIS.__init__(self, name, **args)

    def checkParams (self, action):
        if not hasattr (action, 'parameters'):
            raise ApplicationException ("Invalid empty request for cumulative TIF, require: %s" % join (",", self.parameters))

        for parameter in self.parameters:
            if not action.parameters.has_key (parameter):
                raise ApplicationException ("Missing [%s] parameter from cumulative TIF query" % parameter)

    def select (self, action):
        self.checkParams (action)

        # split coordinate pairs of longitude and latitue to seperate lists
        coordinates = action.parameters['coordinates'].split(',')
        x = list()
        y = list()

        for coordinate in coordinates:
            point = coordinate.split(' ');
            x.append (point[0]);
            y.append (point[1]);

        # prepare cursor for extracting features
        cursor = self.db.cursor()

        sql  = "SELECT %s AS id, ST_AsText(%s) as fs_text_geom, %s FROM \"%s\"" % (self.fid_col, self.geom_col, self.attribute_cols, self.table)
        sql += "(ARRAY[%s], ARRAY[%s], %s, %s, %s)" % (','.join (x), \
                                                       ','.join (y), \
                                                       action.parameters['road_count'], \
                                                       action.parameters['dispersion_factor'], \
                                                       action.parameters['inclusion_distance'])

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
