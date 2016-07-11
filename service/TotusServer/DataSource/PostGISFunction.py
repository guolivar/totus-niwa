"""
    Generic PostGIS datasource that can execute void functions
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

class PostGISFunction (PostGIS):
    def __init__(self, name, **args):
        PostGIS.__init__(self, name, **args)

    def select (self, action):
        cursor = self.db.cursor()

        sql  = "SELECT %s AS id, ST_AsText(%s) as fs_text_geom, %s FROM %s()" % (self.fid_col, self.geom_col, self.attribute_cols, self.table)

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
