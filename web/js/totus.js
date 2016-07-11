var selectPoint = OpenLayers.Class.create();

selectPoint.prototype = OpenLayers.Class.inherit(
    OpenLayers.Handler.Point, {
      createFeature: function(evt) {
          this.control.layer.removeFeatures(this.control.layer.features);
          OpenLayers.Handler.Point.prototype.createFeature.apply(this, arguments);
      }
    }
  );

var selectPolygon = OpenLayers.Class.create();

selectPolygon.prototype = OpenLayers.Class.inherit(
    OpenLayers.Handler.Polygon, {
      createFeature: function(evt) {
          this.control.layer.removeFeatures(this.control.layer.features);
          OpenLayers.Handler.Polygon.prototype.createFeature.apply(this, arguments);
      }
    }
  );

var startStyle = OpenLayers.Util.applyDefaults({
  pointRadius: 3,
  strokeWidth: 1,
  strokeColor: "#000000",
  fillColor: "#00FF00",
  fillOpacity: 0.75
}, OpenLayers.Feature.Vector.style['default']);

var endStyle = OpenLayers.Util.applyDefaults({
  pointRadius: 3,
  strokeWidth: 1,
  strokeColor: "#000000",
  fillColor: "#FF0000",
  fillOpacity: 0.75
}, OpenLayers.Feature.Vector.style['default']);

var routeStyle = OpenLayers.Util.applyDefaults({
  strokeWidth: 3,
  strokeColor: "#000000",
  fillOpacity: 1
}, OpenLayers.Feature.Vector.style['default']);

var summaryStyle = OpenLayers.Util.applyDefaults({
  strokeWidth: 2,
  strokeColor: "#00FF00",
  fillOpacity: 1
}, OpenLayers.Feature.Vector.style['default']);

var fluxStyle = OpenLayers.Util.applyDefaults({
  strokeWidth: 2,
  strokeColor: "#0000FF",
  fillOpacity: 1
}, OpenLayers.Feature.Vector.style['default']);

var gridRules = [ 
    new OpenLayers.Rule ({
        filter : new OpenLayers.Filter.Comparison ({
            type     : OpenLayers.Filter.Comparison.LESS_THAN,
            property : "no2",
            value    : "20"
        }),
        symbolizer : { 
            strokeWidth : 0.5,
            strokeColor : "#CACACA",
            fillColor   : "green",
            fillOpacity : 0.15
        }
    }),
    new OpenLayers.Rule ({
        filter : new OpenLayers.Filter.Comparison ({
            type          : OpenLayers.Filter.Comparison.BETWEEN,
            property      : "no2",
            lowerBoundary : "20",
            upperBoundary : "40"
        }),
        symbolizer : { 
            strokeWidth : 0.5,
            strokeColor : "#CACACA",
            fillColor   : "yellow", 
            fillOpacity : 0.15
        }
    }),
    new OpenLayers.Rule ({
        filter : new OpenLayers.Filter.Comparison ({
            type     : OpenLayers.Filter.Comparison.GREATER_THAN,
            property : "no2",
            value    : "40"
        }),
        symbolizer : { 
            strokeWidth : 0.5,
            strokeColor : "#CACACA",
            fillColor   : "red", 
            fillOpacity : 0.15
        }
    })
];

var gridStyle = new OpenLayers.Style (
    OpenLayers.Feature.Vector.style.default,
    {
        rules: gridRules
    }
);

var gridStyleMap = new OpenLayers.StyleMap (
    {
        'default': gridStyle
    }
);

var filterStyle = OpenLayers.Util.applyDefaults({
  strokeWidth: 1,
  strokeColor: "#000000",
  fillColor: "#FFFFFF",
  fillOpacity: 0.75
}, OpenLayers.Feature.Vector.style['default']);

var TIFStyle = OpenLayers.Util.applyDefaults({
  strokeWidth: 3,
  strokeColor: "#00CC00",
  fillOpacity: 1
}, OpenLayers.Feature.Vector.style['default']);

// global variables
var map, WKTParser, routeStart, routeEnd;
var route, trafficSummary, trafficFlux, TIFResults, routeResults;
var controls;
var summaryTable;
var trafficArea;
var NO2Grid;
var TIFArea, TIFSummary;
var TIFPoint, cumulativeTIF;
var trafficRoutes;

// projections
var mapProj  = new OpenLayers.Projection("EPSG:900913");
var dataProj = new OpenLayers.Projection("EPSG:4326");

var AucklandCBD  = new OpenLayers.Bounds(174.7150, -36.86469, 174.80872, -36.83495).transform(dataProj, mapProj);

WKTParser = new OpenLayers.Format.WKT();

function initTotusMap() {
    var options = {
        projection: mapProj,
        displayProjection: dataProj,
        units: "m",
        numZoomLevels: 16,
        maxResolution: 156543.0339,
        maxExtent: new OpenLayers.Bounds(-20037508, -20037508, 20037508, 20037508.34)
    };

    map = new OpenLayers.Map('map', options);

    map.events.register('zoomend', this, function (event) {
        var z = map.getZoom();
                   
        if (z > 15) {
            map.zoomTo(15);
        }
        if (z < 11) {
            map.zoomTo(11);
        }
    });

    // add controls
    map.addControl(new OpenLayers.Control.LayerSwitcher());
    map.addControl(new OpenLayers.Control.MousePosition());

    // create and add layers to the map
    routeStart = new OpenLayers.Layer.Vector("Start of route", { style: startStyle} );
    routeEnd   = new OpenLayers.Layer.Vector("End of route", { style: endStyle });

    // route path result
    route = new OpenLayers.Layer.Vector("Routing route", { style: routeStyle });

    // Traffic traffic path result
    trafficSummary = new OpenLayers.Layer.Vector("Traffic Aggregate Summary", { style: summaryStyle });

    // Traffic flux path result
    trafficFlux = new OpenLayers.Layer.Vector("Traffic Flux Summary", { style: fluxStyle });

    // area filter for Traffic queries
    trafficArea = new OpenLayers.Layer.Vector("Traffic Area Filter", { style: filterStyle });

    // NO2 grid
    NO2Grid = new OpenLayers.Layer.Vector(
                "NO2 Grid", 
                { 
                    displayInLayerSwitcher : true,
                    styleMap               : gridStyleMap
                }
              );

    // area filter for TIF queries
    TIFArea = new OpenLayers.Layer.Vector("TIF Area Filter", { style: filterStyle });

    // point filter for cumulative TIF queries
    TIFPoint = new OpenLayers.Layer.Vector("Cumulative TIF Point", { style: filterStyle });

    // TIF summary
    TIFSummary = new OpenLayers.Layer.Vector("TIF Summary", { style: routeStyle });

    // cumulative TIF
    cumulativeTIF = new OpenLayers.Layer.Vector("Cumulative TIF", { style: TIFStyle });

    // multi Traffic route
    trafficRoutes = new OpenLayers.Layer.Vector("Traffic Routes", { style: routeStyle });

    var osm = new OpenLayers.Layer.TMS(
                "OpenStreetMap",
                "http://tile.openstreetmap.org/",
                { 
                    type                    : 'png', 
                    getURL                  : osmGetTileURL, 
                    displayOutsideMaxExtent : true,
                    attribution             : '<a href="http://www.openstreetmap.org/">OpenStreetMap</a>',
                    wrapDateLine            : false,
                    isBaseLayer             : true
                }
              );

    getNO2Grid ();

    map.addLayers([osm, routeStart, routeEnd, route, trafficSummary, 
                   trafficFlux, trafficArea,
                   NO2Grid, TIFArea, TIFSummary, TIFPoint,
                   cumulativeTIF, trafficRoutes]);

    // set default position
    map.zoomToExtent(AucklandCBD);
    map.zoomTo(11);

    // controls
    controls = {
        routeStart : new OpenLayers.Control.DrawFeature(routeStart, selectPoint),
        routeEnd   : new OpenLayers.Control.DrawFeature(routeEnd, selectPoint),
        trafficArea   : new OpenLayers.Control.DrawFeature(trafficArea, selectPolygon),
        TIFArea    : new OpenLayers.Control.DrawFeature(TIFArea, selectPolygon),
        TIFPoint   : new OpenLayers.Control.DrawFeature(TIFPoint, selectPoint)
    }
    for (var key in controls) {
        map.addControl(controls[key]);
    }

    getSchoolLayer ();
}

// display HTML content on result tab
function displayQueryResults(content) {
    var resultTab = document.getElementById('QueryResults');

    resultTab.innerHTML = content;
}

function displayFormErrors(content) {
    var resultTab = document.getElementById('FormErrors');

    resultTab.innerHTML = '<div class="alert alert-danger" role="alert">' + content + '</div>';
}

function clearFormErrors() {
    document.getElementById('FormErrors').innerHTML = '';
}

function osmGetTileURL(bounds) {
    var res = this.map.getResolution();
    var x = Math.round((bounds.left - this.maxExtent.left) / (res * this.tileSize.w));
    var y = Math.round((this.maxExtent.top - bounds.top) / (res * this.tileSize.h));
    var z = this.map.getZoom();
    var limit = Math.pow(2, z);

    if (y < 0 || y >= limit) {
        return "http://www.maptiler.org/img/none.png";
    } else {
        x = ((x % limit) + limit) % limit;
        return this.url + z + "/" + x + "/" + y + "." + this.type;
    }
}
 
function clearAllControls() {
    for (key in controls) {
        controls[key].deactivate();
    }
}

function toggleControl(element) {
    for (key in controls) {
        if (element.value == key && element.checked) {
            controls[key].activate();
        } else {
            controls[key].deactivate();
        }
    }

    // when toggling TIFFileToggle enable or disable upload field TIFCSVFile
    if (element.id == 'tifFileToggle') {
        document.getElementById ('tifCSVFile').style.visibility = 'visible';
    }
    else {
        document.getElementById ('tifCSVFile').style.visibility = 'hidden';
    }

    // enable TIFPointClear when a point has been chosen
    if (element.value == 'tifPoint' && element.checked) {
        document.getElementById ('tifPointClear').style.visibility      = 'visible';
        document.getElementById ('tifPointClearLabel').style.visibility = 'visible';
    }
    else {
        if (TIFPoint.features.length == 0) {
            document.getElementById ('tifPointClear').style.visibility      = 'hidden';
            document.getElementById ('tifPointClearLabel').style.visibility = 'hidden';
        }
    }
}

function computeRoute() {
    var startPoint = routeStart.features[0];
    var endPoint   = routeEnd.features[0];

    if (startPoint && endPoint) {
        clearFormErrors();

        startPoint.geometry.transform(mapProj, dataProj);
        endPoint.geometry.transform(mapProj, dataProj);

        var params = {
            'routing_method' : OpenLayers.Util.getElement('routingMethod').value,
            'costing_option' : OpenLayers.Util.getElement('costingOption').value,
            'route_start'    : startPoint.geometry.x + ' ' + startPoint.geometry.y,
            'route_end'      : endPoint.geometry.x + ' ' + endPoint.geometry.y,
            'format'         : 'json'
        };
        OpenLayers.loadURL("http://localhost:80/totus-server/routing?" + OpenLayers.Util.getParameterString(params),
                           null,
                           null,
                           displayRoute);

        clearAllControls();
    }
    else {
        displayFormErrors ("No valid start/end coordinates provided for calculating a network route");
    }
}

function displayRoute(response) {
    if (response && response.responseText) {
        // erase the previous routes
        route.removeFeatures(route.features);

        routeResults  = '<h4>Route Results</h4>';
        routeResults += '<p>';
        routeResults += '<table class="table">';

        var GJParser = new OpenLayers.Format.GeoJSON ();

        // parse feature collection
        var features = GJParser.read (response.responseText);

        // write header from first feature's attributes
        if (features.length > 0) {
            routeResults += '<thead><tr>';

            for (var key in features[0].attributes) {
                routeResults += '<th>' + key + '</th>';
            }

            routeResults += '</tr></thead>';
        }

        routeResults += '<tbody>';

        for (var f in features) {
            features[f].geometry.transform (dataProj, mapProj);

            // data row
            routeResults += '<tr>';
            for (var key in features[f].attributes) {
                routeResults += '<td>' + features[f].attributes[key] + '</td>';
            }
            routeResults += '</tr>';
        }
        if (features.length == 0) {
            routeResults += "<tr><td>No Results</td></tr>";
        }
        routeResults += '</tbody></table>';
        routeResults += '</p>';

        if (features.length > 0) {
            route.addFeatures (features);
            map.zoomToExtent(route.getDataExtent());
        }

        displayQueryResults (routeResults);
    }
}

function computeTrafficSummary() {
    // assume user have already captured polygon
    // if not do not submit request and warn user
    if (trafficArea.features.length > 0) {
        clearFormErrors();
       
        trafficArea.features[0].geometry.transform(mapProj, dataProj);

        var params = {
            'area_filter' : trafficArea.features[0].geometry.toString(),
            'format'      : 'json'
        };
        OpenLayers.loadURL("http://localhost:80/totus-server/traffic_summary?" + OpenLayers.Util.getParameterString(params),
                           null,
                           null,
                           displayTrafficSummary);

        clearAllControls();
    }
    else {
        displayFormErrors ("Choose Traffic Area");
    }
}

function displayTrafficSummary(response) {
    if (response && response.responseText) {
        // erase the previous traffic summary
        trafficSummary.removeFeatures(trafficSummary.features);

        trafficTable  = '<h4>Traffic Results</h4>';
        trafficTable += '<h5>Traffic Summary</h5>';
        trafficTable += '<p>';
        trafficTable += '<table class="table">';

        var GJParser = new OpenLayers.Format.GeoJSON ();

        // parse feature collection
        var features = GJParser.read (response.responseText);

        for (var f in features) {
            features[f].geometry.transform (dataProj, mapProj);

            for (var key in features[f].attributes) {
                trafficTable += '<tr><th>' + key + '</th><td>' + features[f].attributes[key] + '</td></tr>';
            }
        }
        if (features.length == 0) {
            trafficTable += "<tr><td>No Results</td></tr>";
        }
        trafficTable += '</table>';
        trafficTable += '</p>';

        if (features.length > 0) {
            trafficSummary.addFeatures(features);
            map.zoomToExtent(trafficSummary.getDataExtent());
        }

        // load and display traffic flux after traffic summary
        var params = {
            'area_filter' : trafficArea.features[0].geometry.toString(),
            'format'      : 'json'
        };

        OpenLayers.loadURL("http://localhost:80/totus-server/traffic_flux?" + OpenLayers.Util.getParameterString(params),
                           null,
                           null,
                           displayTrafficFlux);
    }
    else {
        displayFormErrors ("[Traffic Summary]: No response received from server");
    }
}

function displayTrafficFlux(response) {
    if (response && response.responseText) {
        // erase the previous traffic flux
        trafficFlux.removeFeatures(trafficFlux.features);

        var GJParser = new OpenLayers.Format.GeoJSON ();

        // parse feature collection
        var features = GJParser.read (response.responseText);

        trafficTable += '<h5>Traffic Influx</h5>';
        trafficTable += '<p>';
        trafficTable += '<table class="table">';
        for (var f in features) {
            features[f].geometry.transform (dataProj, mapProj);
        
            for (var key in features[f].attributes) {
                if (key.match(/^\[influx\] /)) {
                    var field = key.substring("[influx] ".length, key.length);
                    trafficTable += '<tr><th>' + field + '</th><td>' + features[f].attributes[key] + '</td></tr>';
                }
            }
        }
        if (features.length == 0) {
            trafficTable += "<tr><td>No Results</td></tr>";
        }
        trafficTable += '</table>';
        trafficTable += '</p>';

        trafficTable += '<h5>Traffic Outflux</h5>';
        trafficTable += '<p>';
        trafficTable += '<table class="table">';
        for (var f in features) {
            for (var key in features[f].attributes) {
                if (key.match(/^\[outflux\] /)) {
                    var field = key.substring("[outflux] ".length, key.length);
                    trafficTable += '<tr><th>' + field + '</th><td>' + features[f].attributes[key] + '</td></tr>';
                }
            }
        }
        if (features.length == 0) {
            trafficTable += "<tr><td>No Results</td></tr>";
        }
        trafficTable += '</table>';
        trafficTable += '</p>';

        if (features.length > 0) {
            trafficFlux.addFeatures(features);
            map.zoomToExtent(trafficFlux.getDataExtent());
        }

        displayQueryResults (trafficTable);
    }
    else {
        displayFormErrors ("[Traffic Flux]: No response received from server");
    }
}

function clearTrafficArea () {
    trafficArea.removeFeatures(trafficArea.features);
}

function getNO2Grid () {
    OpenLayers.loadURL ("http://localhost:80/totus-server/no2_grid?format=json",
                        null,
                        null,
                        displayNO2Grid);
}

function displayNO2Grid (response) {
    if (response && response.responseText) {

        var GJParser = new OpenLayers.Format.GeoJSON ();

        // parse feature collection
        var features = GJParser.read (response.responseText);

        for (var f in features) {
            features[f].geometry.transform (dataProj, mapProj);
        }

        NO2Grid.addFeatures (features)
    }
}

function computeTIFSummary () {
    // check that user has selected area on map
    if (TIFArea.features.length > 0) {
        clearFormErrors();

        TIFArea.features[0].geometry.transform (mapProj, dataProj);

        var params = {
            'area_filter' : TIFArea.features[0].geometry.toString(),
            'format'      : 'json'
        };

        OpenLayers.loadURL ("http://localhost:80/totus-server/tif_summary?" + OpenLayers.Util.getParameterString (params),
                            null,
                            null,
                            displayTIFSummary);

        clearAllControls();
        clearTIFArea ();
    }
    else {
        displayFormErrors ("Choose TIF Area");
    }
}

function displayTIFSummary (response) {
    if (response && response.responseText) {
        TIFSummary.removeFeatures (TIFSummary.features);

        TIFResults  = '<h4>TIF Results</h4>';
        TIFResults += '<p>';
        TIFResults += '<table class="table">';

        var GJParser = new OpenLayers.Format.GeoJSON ();

        // parse feature collection
        var features = GJParser.read (response.responseText);

        for (var f in features) {
            features[f].geometry.transform (dataProj, mapProj);

            for (var key in features[f].attributes) {
                TIFResults += '<tr><th>' + key + '</th><td>' + features[f].attributes[key] + '</td></tr>';
            }
        }
        if (features.length == 0) {
            TIFResults += "<tr><td>No Results</td></tr>";
        }
        TIFResults += '</table>';
        TIFResults += '</p>';

        if (features.length > 0) {
            TIFSummary.addFeatures (features);
            map.zoomToExtent(TIFSummary.getDataExtent());
        }

        displayQueryResults (TIFResults);
    }
    else {
        displayFormErrors ("[TIF Summary]: No response received from server");
    }
}

function clearTIFArea () {
    TIFArea.removeFeatures(TIFArea.features);
}

function computeCumulativeTIF () {
    // check that user has selected area on map
    var coordinates = '';

    if (TIFPoint.features.length > 0) {
        TIFPoint.features[0].geometry.transform (mapProj, dataProj);

        coordinates = TIFPoint.features[0].geometry.x + ' ' + TIFPoint.features[0].geometry.y;

    }
    // user have chosen to upload CSV file
    else if (document.getElementById('tifCSVFile')) {
        coordinates = parseCoordinateFile ('tifCSVFile', 'tifCSVFileContents');
    }

    if (coordinates.length > 0) {
        clearFormErrors();

        var params = {
            'coordinates'        : coordinates,
            'dispersion_factor'  : OpenLayers.Util.getElement('dispersionFactor').value,
            'road_count'         : OpenLayers.Util.getElement('roadCount').value,
            'inclusion_distance' : OpenLayers.Util.getElement('inclusionDistance').value
        };

        // prepare CSV download link
        params['format'] = 'csv';

        var url = "http://localhost:80/totus-server/cumulative_tif";
        var downLoadURL = url + "?" + OpenLayers.Util.getParameterString (params);

        TIFResults  = '<h4>Cumulative TIF Results</h4>';
        TIFResults += '<p>';
        TIFResults += "<a href='" + downLoadURL + "' target=\"_blank\">Download as CSV</a>";

        // feature request in JSON
        params['format'] = 'json';

        OpenLayers.Request.GET({
            url:      url,
            params:   params,
            callback: displayCumulativeTIF
        });

        clearAllControls();
        clearTIFPoint ();
    }
    else {
        displayFormErrors ("No valid coordinate provided for calculating Cumulative TIF");
    }
}

function displayCumulativeTIF (request) {
    if (request.status == 500 || request.status == 413) {
        // error
        displayQueryResults ('<h4>' + request.statusText   + '</h4>' +
                             '<p>'  + request.responseText + '</p>');
    }
    else if (request.status == 414) {
        // exceeded URL parameters size
        displayQueryResults ('<h4>' + request.statusText   + '</h4>' +
                             '<p>Reduce the number of coordinates for TIF calculation</p>');
    } 
    else if (request.status == 200) {
        cumulativeTIF.removeFeatures (cumulativeTIF.features);

        TIFResults += '<table class="table">';

        var GJParser = new OpenLayers.Format.GeoJSON ();

        // parse feature collection
        var features = GJParser.read (request.responseText);

        // write header from first feature's attributes
        if (features.length > 0) {
            TIFResults += '<thead><tr>';

            for (var key in features[0].attributes) {
                TIFResults += '<th>' + key + '</th>';
            }

            TIFResults += '</tr></thead><tbody>';
        }

        for (var f in features) {
            features[f].geometry.transform (dataProj, mapProj);

            // data row
            TIFResults += '<tr>';
            for (var key in features[f].attributes) {
                TIFResults += '<td>' + features[f].attributes[key] + '</td>';
            }
            TIFResults += '</tr>';
        }
        if (features.length == 0) {
            TIFResults += "<tr><td>No Results</td></tr>";
        }
        TIFResults += '</tbody></table>';
        TIFResults += '</p>';

        if (features.length > 0) {
            cumulativeTIF.addFeatures (features);
            map.zoomToExtent(cumulativeTIF.getDataExtent());
        }

        displayQueryResults (TIFResults);
    }
    else {
        displayFormErrors ("[Cumulative TIF]: No response received from server");
    }
}

function clearTIFPoint () {
    TIFPoint.removeFeatures(TIFPoint.features);
}

function parseCoordinateFile (fileElementId, contentsElementId) {
    var coordinates = "";

    if (document.getElementById(fileElementId)) {
        if (document.getElementById(fileElementId).files && document.getElementById(fileElementId).files[0]) {

            // FF only: http://www.w3.org/TR/FileAPI/ 
            var file = document.getElementById(fileElementId).files[0];
            var reader = new FileReader ();

            reader.onload = function (e) {
                var lines = e.target.result.split ('\n');

                document.getElementById(contentsElementId).value = "";

                var i = 0;
                for (var line in lines) {
                    if (lines[line]) {
                        if (i > 0) {
                            document.getElementById(contentsElementId).value += '|';
                        }

                        document.getElementById(contentsElementId).value += lines[line];
                        i++;
                    }
                }

            }

            reader.readAsText (file);

            var result = document.getElementById(contentsElementId).value;
            var contents = result.split('|');

            var i = 0;
            for (var line in contents) {
                if (contents[line]) {
                    if (i > 0) {
                        coordinates += ',';
                    }

                    var xy = contents[line].split (',');
                    coordinates += xy[0] + ' ' + xy[1];
                    i++;
                }
            }

            // done reading files, clear the contents
            document.getElementById(contentsElementId).value = "";

            // reset trick
            document.getElementById(fileElementId).setAttribute('type', 'input');
            document.getElementById(fileElementId).setAttribute('type', 'file');
        } 
        else {
            displayFormErrors ("No file to upload from element: " + fileElementId);
        }
    }
    else {
        displayFormErrors ("Unable to load file from element: " + fileElementId);
    }


    return coordinates;
}

function computeTrafficRoutes () {
    var startCoordinates = parseCoordinateFile ('trafficStartCSVFile', 'trafficStartCSVFileContents');
    var endCoordinates   = parseCoordinateFile ('trafficEndCSVFile', 'trafficEndCSVFileContents');

    if (startCoordinates.length > 0 && endCoordinates.length > 0) {
        var params = {
            'start_coordinates' : startCoordinates,
            'end_coordinates'   : endCoordinates,
            'routing_method'    : OpenLayers.Util.getElement('trafficRoutingMethod').value,
            'costing_option'    : OpenLayers.Util.getElement('trafficCostingOption').value
        };

        // set as CSV download, store the download URL
        params['format'] = 'csv';
        var url = "http://localhost:80/totus-server/traffic_route";
        var downLoadURL = url + "?" + OpenLayers.Util.getParameterString (params);

        routeResults  = '<h4>Traffic Routes</h4>';
        routeResults += '<p>';
        routeResults += "<a href='" + downLoadURL + "' target=\"_blank\">Download as CSV</a>";

         // feature request in JSON
        params['format'] = 'json';

        OpenLayers.Request.GET({
            url:      url,
            params:   params,
            callback: displayTrafficRoutes
        });
    }
    else {
        displayFormErrors ("No valid start/end coordinates provided for calculating traffic routes");
    }
}

function displayTrafficRoutes (request) {
    if (request.status == 500 || request.status == 413) {
        // error
        displayQueryResults ('<h4>' + request.statusText   + '</h4>' +
                             '<p>'  + request.responseText + '</p>');
    }
    else if (request.status == 414) {
        // exceeded URL parameters size
        displayQueryResults ('<h4>' + request.statusText   + '</h4>' +
                             '<p>Reduce the number of start coordinates for traffic routes</p>');
    } 
    else if (request.status == 200) {
        trafficRoutes.removeFeatures (trafficRoutes.features);

        routeResults += '<table class="table">';

        var GJParser = new OpenLayers.Format.GeoJSON ();

        // parse feature collection
        var features = GJParser.read (request.responseText);

        // write header from first feature's attributes
        if (features.length > 0) {
            routeResults += '<thead><tr>';

            for (var key in features[0].attributes) {
                routeResults += '<th>' + key + '</th>';
            }

            routeResults += '</tr></thead><tbody>';
        }

        for (var f in features) {
            features[f].geometry.transform (dataProj, mapProj);

            // data row
            routeResults += '<tr>';
            for (var key in features[f].attributes) {
                routeResults += '<td>' + features[f].attributes[key] + '</td>';
            }
            routeResults += '</tr>';
        }
        if (features.length == 0) {
            routeResults += "<tr><td>No Results</td></tr>";
        }
        routeResults += '</tbody></table>';
        routeResults += '</p>';

        if (features.length > 0) {
            trafficRoutes.addFeatures (features);
            map.zoomToExtent(trafficRoutes.getDataExtent());
        }

        displayQueryResults (routeResults);
    }
}
