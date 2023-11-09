function score_bin(s) {
    if (s === null) { return '#999'; }
    else if (s > 0.8) { return '#090'; }
    else if (s > 0.5) { return '#c90'; }
    else if (s >= 0) { return '#c00'; }
    else { return '#999'; }
}

// get ISO8601 formatted datetime YYYY-MM-DD HH:MM:SS
function iso8601(date) { return new Date(date).toLocaleString('sv-SV'); }

// get local formatted datetime beginning of month YYYY-MM
function get_mon(date) { return new Date(date).toISOString().substr(0,7); }

// hat-tip to http://lyzidiamond.com/posts/external-geojson-and-leaflet-the-other-way/
function popup_attributes(feature, layer) {
    let html = '<table>';
    for (attrib in feature.properties) {
        html += '<tr><td>' + attrib + '</td><td>' + feature.properties[attrib] + '</td></tr>';
    }
    layer.bindPopup(html + '</table>');
}

let map = L.map('map', {zoomControl: false}).setView([47.60, -122.33], 12);

let tiles = L.tileLayer('https://{s}.basemaps.cartocdn.com/rastertiles/{tileType}/{z}/{x}/{y}{r}.png', {
    attribution: 'Map data &copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors, &copy; <a href="https://cartodb.com/attributions">CARTO</a>',
    subdomains: 'abcd',
    tileType: 'light_all',
    maxZoom: 19
    }
);


tiles.addTo(map);
L.control.zoom({position: 'topright'}).addTo(map);
L.control.scale({maxWidth: 200, position: 'bottomright'}).addTo(map);

// add title
let title = L.control({position: 'topleft'});
title.onAdd = function(mp) {
    let _tdiv = L.DomUtil.create('div', 'title');
    _tdiv.innerHTML = '<h2>GeoJSON Viewer</h2>'
    return _tdiv;
}
title.addTo(map);

let osmLayer;
const t_osm = d3.json("./data/metrics_osm_full.geojson");
t_osm.then(osm => {
    // add features to map
    osmLayer  = L.geoJSON(osm, {
        style: function(e) { return { weight: 5, opacity: 0.8, color:  "#BAD4E4" } },
        // onEachFeature: popup_attributes
    }).addTo(map);

    // zoom to content
    // map.fitBounds(osmLayer.getBounds());
});


let sdotLayer;
const t_sdot = d3.json("./data/metrics_sdot_full.geojson");
t_sdot.then(sdot => {
    // add features to map
    sdotLayer = L.geoJSON(sdot, {
        style: function(e) { return { weight: 5, opacity: 0.5, color:  "#E4C1BA" } },
        // onEachFeature: popup_attributes
    }).addTo(map);

    // zoom to content
    map.fitBounds(sdotLayer.getBounds());
});

let conflationLayer;
// get edges and add to map
const t_conflation = d3.json("./data/sidewalk_full_json.geojson");
t_conflation.then(conflation => {
    // Filter the GeoJSON features based on the 'conflated_score'
    const filteredFeatures = conflation.features.filter(feature => feature.properties.conflated_score < 0.8 && feature.properties.conflated_score != null);

    // Create a new GeoJSON object with the filtered features
    const filteredConflation = {
        type: 'FeatureCollection',
        features: filteredFeatures
    };
    let highlightedFeature = null; 

    // add features to map
    conflationLayer = L.geoJSON(filteredConflation, {
        style: function (e) {
            return { weight: 5, opacity: 0.5, color: score_bin(e.properties.conflated_score) }
        },
    
        onEachFeature: function (feature, layer) {
            // Attach a mouseover event handler
            layer.on('mouseover', function (e) {
                layer.setStyle({
                    weight: 5, opacity: 0.5, color: '#cc41f2'
                });
            });

            // Attach a mouseout event handler to reset the style
            layer.on('mouseout', function (e) {
                if (highlightedFeature !== layer) {
                    layer.setStyle({
                        weight: 5, opacity: 0.5, color: score_bin(layer.feature.properties.conflated_score)
                    });
                }
            });


            layer.on('click', function (e) {
                // Reset the style of the previously highlighted feature
                if (highlightedFeature) {
                    highlightedFeature.setStyle({
                        weight: 5,            // Reset the weight
                        opacity: 0.5,         // Reset the opacity
                        color: score_bin(highlightedFeature.feature.properties.conflated_score) // Reset the color
                    });
                }
    
                // Get the sdot_objectid and osm_id from the clicked feature
                const sdot_objectid = feature.properties.sdot_objectid;
                const osm_id = feature.properties.osm_id;
    
                // Highlight the clicked feature in the conflation layer
                layer.setStyle({
                    weight: 10,           // Adjust the weight to highlight
                    opacity: 0.7,          // Adjust the opacity to highlight
                    color: '#cc41f2'    // Set a different color for highlighting
                });
    
                map.fitBounds(layer.getBounds(), { maxZoom: 17 });

                // Set the currently highlighted feature
                highlightedFeature = layer;
    
                // Highlight the features in the sdot and osm layers with matching IDs
                highlightFeaturesInSDOT(sdot_objectid);
                highlightFeaturesInOSM(osm_id);

                popup_attributes(highlightedFeature.feature, highlightedFeature);
            });
        }
    }).addTo(map);
    

});

// Legend for SDOT Layer
let layerLegend = L.control({ position: 'bottomleft' });
layerLegend.onAdd = function (map) {
    let div = L.DomUtil.create('div', 'legend');
    div.innerHTML += '<h4>SDOT Layer</h4>';
    div.innerHTML += '<span class="legend-color" style="background-color: #E4C1BA"></span><span>Default</span><br>';
    // Add more legend items as needed for different styles/colors
    div.innerHTML += '<h4>Conflation Layer</h4>';
    div.innerHTML += '<span class="legend-color" style="background-color: #090"></span><span>Score > 0.8</span><br>';
    div.innerHTML += '<span class="legend-color" style="background-color: #c90"></span><span>Score > 0.5</span><br>';
    div.innerHTML += '<span class="legend-color" style="background-color: #c00"></span><span>Score >= 0</span><br>';

    div.innerHTML += '<h4>OSM Layer</h4>';
    div.innerHTML += '<span class="legend-color" style="background-color: #BAD4E4"></span><span>Default</span><br>';
    
    return div;
};
layerLegend.addTo(map);

osmLayer.setZIndex(1);  // You can set any integer value based on your requirements

// Set z-index for SDOT Layer
sdotLayer.setZIndex(2);  // You can set any integer value based on your requirements

// Set z-index for Conflation Layer
conflationLayer.setZIndex(4);  // You can set any integer value based on your requirements


// Function to highlight features in the sdot layer with a specific object ID
function highlightFeaturesInSDOT(sdot_objectid) {
    sdotLayer.eachLayer(function (layer) {
        // Check if the feature has a property named 'sdot_objectid' and if it matches the provided objectId
        if (layer.feature.properties.objectid === sdot_objectid) {
            // Apply a highlight style to the matching feature
            layer.setStyle({
                weight: 10,          // Adjust the weight to highlight
                opacity: 1,         // Adjust the opacity to highlight
                color: "#E4C1BA"    // Set a different color for highlighting
            });
        } else {
            layer.setStyle ({
                weight: 5,
                opacity: 0.5,
                color:  "#E4C1BA"
            })
        }
    });
}

// Function to highlight features in the osm layer with a specific osm_id
function highlightFeaturesInOSM(osm_id) {
    osmLayer.eachLayer(function (layer) {
        // Check if the feature has a property named 'osm_id' and if it matches the provided osmId
        if (layer.feature.properties.osm_id === osm_id) {
            // Apply a highlight style to the matching feature
            layer.setStyle({
                weight: 10,          // Adjust the weight to highlight
                opacity: 1,         // Adjust the opacity to highlight
                color: "#BAD4E4"    // Set a different color for highlighting
            });
        } else {
            layer.setStyle({
                weight: 5, opacity: 0.5, color:  "#BAD4E4"
            })
        }
    });
}

// get edges and add to map
// const t_cross = d3.json("./data/crossing_full_json.geojson");
// t_cross.then(cross => {

//   // add features to map
//   let e = L.geoJSON(cross, {
//     style: { weight: 4, opacity: 0.5, color: "#0c9" },
//     onEachFeature: popup_attributes
//   }).addTo(map);

//   // zoom to content
//   //map.fitBounds(e.getBounds());
// });