#! /usr/bin/env python

"""
    Service wrapper
"""

import sys

sys.path.append ('./')
sys.path.append ('./TotusServer/DataSource')
sys.path.append ('./thirdparty/featureserver')

from FeatureServer import Server

def handler (request):
    return Server.handler (request)
