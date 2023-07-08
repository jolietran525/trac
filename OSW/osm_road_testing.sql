CREATE TEMPORARY TABLE temp_bel1_osm_road AS (
	SELECT osm_id, highway, name, tags, way
	FROM planet_osm_line
	WHERE	highway IN ('motorway', 'trunk', 'primary', 'secondary', 'tertiary', 'road', 'residential', 'busway', 'escape') AND 
			way && st_setsrid( st_makebox2d( st_makepoint(-13603442,6043723), st_makepoint(-13602226,6044848)), 3857) );

-- pull out the number of lanes
SELECT CAST(tags -> 'lanes' AS int) lanes, osm_id, way
FROM temp_bel1_osm_road
WHERE tags ? 'lanes';

		
	SELECT osm_id, highway, name, tags, way
	FROM planet_osm_line
	WHERE	highway NOT IN ('footway', 'bridleway', 'steps', 'corridor', 'path', 'via_ferrata') AND 
			way && st_setsrid( st_makebox2d( st_makepoint(-13615706,6049150), st_makepoint(-13614794,6050673)), 3857) ;

	SELECT *
	FROM arnold.wapr_linestring 
	WHERE geom && st_setsrid( st_makebox2d( st_makepoint(-13615706,6049150), st_makepoint(-13614794,6050673)), 3857)
	ORDER BY routeid, beginmeasure, endmeasure