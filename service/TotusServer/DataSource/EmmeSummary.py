"""
   Traffic Model Summary Datasource

   Provided with a Well Known Text representation of a spatial polygon area filter
   queries the Totus database for all Traffic Model edges wholly contained by area and
   returns all their traffic data aggregated.
   
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

class EmmeSummary (PostGIS):
    """
       Traffic Model Summary Datasource 
       
       This treats Traffic Model as a generic data source, provided with a table (in this case an aggregate function), a
       set of attribute columns, a geometry and key column it reads all the data from the data source and
       return it to caller as a set of 'Feature' objects. At run time these get served to user by the requested
       service, eg. WKT (no attributes), WFS (with attributes), GeoJSON, etc.

    """
    # data source parameters, these are trusted by service and injected into action object
    parameters = [ "area_filter" ]

    def __init__(self, name, **args):
        PostGIS.__init__(self, name, **args)

    def select (self, action):
        if not hasattr (action, 'parameters') or not action.parameters.has_key('area_filter'):
            raise ApplicationException("Missing spatial area filter, supply a Well Known Text geometry for 'area_filter'")
        else:
            cursor = self.db.cursor()

            # validate input WKT string (TODO: implement as proper regexp)
            if not action.parameters['area_filter'].find ('POLYGON ('):
                raise ApplicationException ("Invalid spatial filter, should be Well Known Text respresentation of a Polygon") 

            sql  = "SELECT ST_AsText(%s) as fs_text_geom, 1 AS \"%s\", %s FROM \"%s\"" % (self.geom_col, self.fid_col, self.attribute_cols, self.table)
            sql += "('%s')" % action.parameters['area_filter']

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
                geom  = WKT.from_wkt(props['fs_text_geom'])

                # add feature id column and remove it from result set dictionary
                id = props[self.fid_col]
                del props[self.fid_col]

                # all attribute columns, including geometry have been selected, remove the duplicate
                if self.attribute_cols == '*':
                    del props[self.geom_col]

                # no need for it anymore, geom is already been set
                del props['fs_text_geom']

                # the remainder of the items in the result set dictionary are only the attributes
                # we need to convert to attributes, for Traffic Model these are embedded as arrays
                data = {}
                attributes = []
                values = []

                # expand arrays in result set to proper attributes
                for key, value in props.items():
                    if key == "attributes":
                        # attributes is an array of attribute type (must be first)
                        attributes = value
                    else:
                        if key == "aggregates":
                            # no prefix needed for aggregate values
                            prefix = ""
                        else:
                            prefix = "[%s] " % key

                        values = value
                        # go through attributes and add values for each
                        for index, type in enumerate(attributes):
                            # prepend prefix to differentiate different types of aggregates
                            field = "%s%s" % (prefix, type)
                            data[field] = values[index]

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
