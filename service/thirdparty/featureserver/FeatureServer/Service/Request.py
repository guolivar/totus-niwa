
import FeatureServer
from FeatureServer.Service.Action import Action
from FeatureServer.WebFeatureService.WFSRequest import WFSRequest
from web_request.handlers import ApplicationException
from FeatureServer.Exceptions.LayerNotFoundException import LayerNotFoundException
from FeatureServer.Exceptions.NoLayerException import NoLayerException

class Request (object):
    
    query_action_types = []
    
    def __init__ (self, service):
        self.service     = service
        self.datasources = []
        self.actions     = []
        self.host        = None
    
    def encode_metadata(self, action):
        """Accepts an action, which is of method 'metadata' and
            may have one attribute, 'metadata', which includes
            information parsed by the service parse method. This
            should return a content-type, string tuple to be delivered
            as metadata to the Server for delivery to the client."""
        data = []
        if action.metadata:
            data.append(action.metadata)
        else:
            data.append("<h4>The following layers are available</h4>")
            data.append ("<ul>");
            for layer in self.service.datasources:
                data.append(" <li><a href=%s/%s>%s</a></li>" % (self.host, layer, layer))
            data.append ("</ul>");
        return ("text/html", "\n".join(data))

    def parse(self, params, path_info, host, post_data, request_method, format_obj = None):
        """Used by most of the subclasses without changes. Does general
            processing of request information using request method and
            path/parameter information, to build up a list of actions.
            Returns a list of Actions. If the first action in the list is
            of method 'metadata', encode_metadata is called (no datasource
            is touched), and encode_metadata is called. Otherwise, the actions
            are passed onto DataSources to create lists of Features."""
        self.host = host
        
        try:
            self.get_layer(path_info, params)
        except NoLayerException as e:
            a = Action()
            
            if params.has_key('service') and params['service'].lower() == 'wfs':
                # FIXME: not sure about this - need to add layer name, not object reference to datasource
                for layer in self.service.datasources:
                    self.datasources.append(layer['name'])
                if params.has_key('request'):
                    a.request = params['request']
                else:
                    a.request = "GetCapabilities"
            else:
                a.method = "metadata"
            
            self.actions.append(a)
            return

        for datasource in self.datasources:
            if not self.service.datasources.has_key(datasource):
                raise LayerNotFoundException("Request", datasource, self.service.datasources.keys())

        action = Action()

        if request_method == "GET" or (request_method == "OPTIONS" and (post_data is None or len(post_data) <= 0)):
            action = self.get_select_action(path_info, params)

        elif request_method == "POST" or request_method == "PUT" or (request_method == "OPTIONS" and len(post_data) > 0):
            actions = self.handle_post(params, path_info, host, post_data, request_method, format_obj = format_obj)
            for action in actions:
                self.actions.append(action)
            
            return

        elif request_method == "DELETE":
            id = self.get_id_from_path_info(path_info)
            if id is not False:
                action.id = id
                action.method = "delete"

        self.actions.append(action)

    def get_id_from_path_info(self, path_info):
        """Pull Feature ID from path_info and return it."""
        try:
            path = path_info.split("/")
            path_pieces = path[-1].split(".")
            if len(path_pieces) > 1:
                return int(path_pieces[0])
            if path_pieces[0].isdigit():
                return int(path_pieces[0])
        except:
            return False
        return False

    def get_select_action(self, path_info, params):
        """Generate a select action from a URL. Used unmodified by most
            subclasses. Handles attribute query by following the rules passed in
            the DS or in the request, bbox, maxfeatures, and startfeature by
            looking for the parameters in the params. """
        action = Action()
        action.method = "select"
        
        id = self.get_id_from_path_info(path_info)
        
        if id is not False:
            action.id = id
        
        else:
            import sys
            for ds in self.datasources:
                queryable = []
                # special GET parameters
                parameters = None

                # lookup datasource by data source name
                datasource = self.service.datasources[ds];
                
                if hasattr(datasource, 'queryable'):
                    queryable = datasource.queryable.split(",")
                elif params.has_key("queryable"):
                    queryable = params['queryable'].split(",")
                elif hasattr(datasource, 'parameters'):
                    # use data source's parameter list
                    parameters = datasource.parameters

                # empty parameter list
                if parameters is None:
                    parameters = []

                for key, value in params.items():
                    qtype = None
                    if "__" in key:
                        key, qtype = key.split("__")

                    if key == 'bbox':
                        action.bbox = map(float, value.split(","))
                    elif key == "maxfeatures":
                        action.maxfeatures = int(value)
                    elif key == "startfeature":
                        action.startfeature = int(value)
                    elif key == "request":
                        action.request = value
                    elif key == "version":
                        action.version = value
                    elif key == "filter":
                        action.wfsrequest = WFSRequest()
                        try:
                            action.wfsrequest.parse(value)
                        except Exception, E:
                            ''' '''
                    elif key in queryable or key.upper() in queryable and hasattr(datasource, 'query_action_types'):
                        if qtype:
                            if qtype in datasource.query_action_types:
                                action.attributes[key+'__'+qtype] = {'column': key, 'type': qtype, 'value':value}
                            else:
                                raise ApplicationException("%s, %s, %s\nYou can't use %s on this layer. Available query action types are: \n%s" % (self, self.query_action_types, qtype,
                                                                                                                                                   qtype, ",".join(datasource.query_action_types) or "None"))
                        else:
                            action.attributes[key+'__eq'] = {'column': key, 'type': 'eq', 'value':value}
                    elif key in parameters or key.upper() in parameters:
                        # we trust our internal data sources, read their parameters
                        # TODO: fixme
                        #action.parameters[eval ("'%s'" % key)] = value
                        action.parameters[key] = value
        
        return action
    
    def get_layer(self, path_info, params = {}):
        """Return layer based on path, or raise a NoLayerException."""
        if params.has_key("typename"):
            self.datasources = params["typename"].split(",")
            return
        
        path = path_info.split("/")
        if len(path) > 1 and path_info != '/':
            self.datasources.append(path[1])
        if params.has_key("layer"):
            self.datasources.append(params['layer'])
        
        if len(self.datasources) == 0:
            raise NoLayerException("Request", message="Could not obtain data source from layer parameter or path info.")

    def handle_post(self, params, path_info, host, post_data, request_method, format_obj = None):
        """Read data from the request and turn it into an UPDATE/DELETE action."""
        
        if format_obj:
            actions = []
            
            id = self.get_id_from_path_info(path_info)
            if id is not False:
                action = Action()
                action.method = "update"
                action.id = id
                
                features = format_obj.decode(post_data)
                
                action.feature = features[0]
                actions.append(action)
            
            else:
                if hasattr(format_obj, 'decode'):
                    features = format_obj.decode(post_data)
                    
                    for feature in features:
                        action = Action()
                        action.method = "insert"
                        action.feature = feature
                        actions.append(action)
            
                elif hasattr(format_obj, 'parse'):
                    format_obj.parse(post_data)
                    
                    transactions = format_obj.getActions()
                    if transactions is not None:
                        for transaction in transactions:
                            action = Action()
                            action.method = transaction.__class__.__name__.lower()
                            action.wfsrequest = transaction
                            actions.append(action)
            
            return actions
        else:
            raise Exception("Service type does not support adding features.")

    def encode(self, result):
        """Accepts a list of lists of features. Each list is generated by one datasource
            method call. Must return a (content-type, string) tuple."""
        results = ["Service type doesn't support displaying data, using naive display."""]
        for action in result:
            for i in action:
                data = i.to_dict()
                for key,value in data['properties'].items():
                    if value and isinstance(value, str):
                        data['properties'][key] = unicode(value,"utf-8")
                results.append(" * %s" % data)
        
        return ("text/plain", "\n".join(results), None)
    
    def getcapabilities(self, version): pass
    def describefeaturetype(self, version): pass


