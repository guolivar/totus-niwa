__author__  = "MetaCarta"
__copyright__ = "Copyright (c) 2006-2008 MetaCarta"
__license__ = "Clear BSD" 
__version__ = "$Id: WKT.py 485 2008-05-18 10:51:09Z crschmidt $"

from FeatureServer.Service.Request import Request
import vectorformats.Formats.WKT  

class WKT(Request):
    def encode(self, results):
        wkt = vectorformats.Formats.WKT.WKT(layername=self.datasources[0])
        output = wkt.encode(results)
        return ("text/plain", output, None, 'utf-8')        
