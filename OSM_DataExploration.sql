----- ABOUT TABLES
-- planet_osm_line: contains all imported ways. It contains details like residential roads, streams and various other features normally rendered only at high zoom.
-- planet_osm_point: contains all imported nodes with tags
-- planet_osm_polygon: contains all imported polygons. Relations seem to be resolved for that.
-- planet_osm_roads: contains a subset of planet_osm_line suitable for rendering at low zoom levels, such as motorsways, rivers, etc.

----- ABOUT SRID
-- SRID from OSM: geom 3857
-- This is the 2 blocks bounded by 9th, 11th, 47th, and 50th Ave
-- Need to use ST_Transform(OSM_geom, 4326) to make spatial join
SELECT *
from planet_osm_line
where ST_within(st_transform(way, 4326), (st_geomfromtext('polygon((-122.3184148188707 47.66495226437948,
-122.31635527220517 47.66495226437948,
-122.31635527220517 47.66311328456703,
-122.3184148188707 47.66311328456703,
-122.3184148188707 47.66495226437948))', 4326)));

--  or st_transform(new_geom, 3857) 
SELECT *
from planet_osm_roads
where ST_within(way, st_transform((st_geomfromtext('polygon((-122.3184148188707 47.66495226437948,
-122.31635527220517 47.66495226437948,
-122.31635527220517 47.66311328456703,
-122.3184148188707 47.66311328456703,
-122.3184148188707 47.66495226437948))', 4326)), 3857));

-- Seattle Bounding box
select *
from planet_osm_line
where 	highway = 'footway' and
		(tags -> 'footway' = 'sidewalk' or tags -> 'footway' = 'crossing') AND
ST_within(way,st_setsrid( st_makebox2d( st_makepoint(-13632151,6020942), st_makepoint(-13605961,6062738)), 3857));


-- Bellevue bounding box

select *
from planet_osm_line
where 	highway = 'footway' and
		(tags -> 'footway' = 'sidewalk' or tags -> 'footway' = 'crossing') AND 
ST_within(way, st_setsrid( st_makebox2d( st_makepoint(-13605781,6029843), st_makepoint(-13590687,6050607)), 3857));


--key: access: Specifies the legal or physical restrictions on accessing a feature.
--key: addr:housename: Indicates the name or lasidbel of a house or building.
--key: addr:housenumber: Specifies the number assigned to a house or building on a street.
--key: addr:interpolation: Used to interpolate addresses between known housenumbers on a street.
--key: admin_level: Indicates the administrative level of a boundary or area.
--key: aerialway: Describes various types of aerial transportation systems, such as cable cars or ski lifts.
--key: aeroway: Represents features related to airports and airfields.
--key: amenity: Identifies various public or private amenities, such as schools, hospitals, or parks.
--key: area: Indicates whether a feature is an area or a linear feature.
--key: barrier: Describes barriers or obstacles, such as fences, walls, or gates.
--key: bicycle: Specifies bicycle-related information, such as designated lanes or parking facilities.
--key: brand: Indicates the brand associated with a specific feature, such as a shop or a restaurant.
--key: bridge: Specifies if a road or pathway is a bridge.
--key: boundary: Represents administrative boundaries, such as country or state borders.
--key: building: Describes buildings and their properties, including their function and architectural style.
--key: construction: Indicates whether a feature is under construction.
--key: covered: Specifies if a feature is covered or sheltered.
--key: culvert: Represents culverts, which are structures that allow water to flow under a road or railway.
--key: cutting: Describes a man-made cutting or trench, usually in the context of railways or roads.
--key: denomination: Specifies the religious denomination of a place of worship.
--key: disused: Indicates if a feature is no longer in use.
--key: embankment: Represents man-made embankments, typically used to raise the level of a road or railway.
--key: foot: Specifies pedestrian-related information, such as accessibility and usability.
--key: generator:source: Indicates the source of the energy generated, such as solar, wind, or hydro.
--key: harbour: Describes harbors, marinas, or other facilities related to water transportation.
--key: highway: Specifies the classification and type of a road or path.
--key: historic: Represents historical features or sites.
--key: horse: Specifies information related to horse riding, such as bridleways or equestrian facilities.
--key: intermittent: Indicates if a water feature has an intermittent flow.
--key: junction: Describes road junctions or interchanges.
--key: landuse: Represents the way land is used, such as residential, commercial, or agricultural.
--key: layer: Specifies the vertical ordering of features in a 3D space.
--key: leisure: Indicates areas or facilities for leisure and recreation, such as parks or sports fields.
--key: lock: Describes locks, which are devices used for raising or lowering boats between different water levels.
--key: man_made: Represents various man-made structures or features.
--key: military: Indicates features related to military installations or areas.
--key: motorcar: Specifies information related to motor vehicles, such as access restrictions or parking facilities.
--key: name: Specifies the name or title of a feature.
--key: natural: Represents natural features or elements, such as rivers, mountains, or forests.
--key: office: Indicates features related to offices or administrative buildings.
--key: oneway: Specifies the direction of traffic flow on a road or path.
--key: operator: Specifies the operator or company responsible for a feature, such as a public transportation network.
--key: place: Represents types of place, such as cities, towns, or villages.
--key: population: Indicates the population count or estimate for a specific area.
--key: power: Describes power-related features, such as power plants or substations.
--key: power_source: Specifies the source of power generation, such as solar, wind, or nuclear.
--key: public_transport: Indicates public transportation-related features or infrastructure.
--key: railway: Represents railway tracks, stations, or other railway-related features.
--key: ref: Specifies reference numbers or codes associated with a feature, such as road numbers.
--key: religion: Indicates the religious affiliation or denomination associated with a place of worship.
--key: route: Represents various types of routes, such as hiking trails, bus routes, or cycle routes.
--key: service: Describes service-related features, such as parking lots or fuel stations.
--key: shop: Indicates commercial establishments or shops.
--key: sport: Specifies sports-related facilities or features, such as stadiums or sports fields.
--key: surface: Describes the surface type or quality of a road or pathway.
--key: toll: Indicates if a feature requires payment of a toll or fee.
--key: tourism: Represents tourism-related features or attractions, such as hotels, museums, or landmarks.
--key: tower:type: Specifies the type or category of a tower structure.
--key: tracktype: Describes the type or condition of a track or pathway.
--key: tunnel: Indicates if a road or pathway is a tunnel.
--key: water: Represents water-related features, such as lakes, rivers, or ponds.
--key: waterway: Describes features related to waterways, such as canals or drains.
--key: wetland: Represents wetland areas or ecosystems.
--key: width: Specifies the width of a feature, such as a road or pathway.
--key: wood: Indicates the type or species of wood used in a feature, such as a forest or wooden structure.
--key: z_order: Specifies the rendering order of features in a map based on their importance.
--key: way_area: Represents the calculated area of a closed way or polygon.
--key: way: Geometry of the object
