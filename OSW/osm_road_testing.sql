-- testing on bel1

-- first, get the road data from osm
CREATE TEMPORARY TABLE temp_osm_road AS (
	SELECT osm_id, highway, name, tags, way AS geom
	FROM planet_osm_line
	WHERE	highway IN ('motorway', 'trunk', 'primary', 'secondary', 'tertiary', 'road', 'busway', 'unclassified') AND 
			way && st_setsrid( st_makebox2d( st_makepoint(-13603442,6043723), st_makepoint(-13602226,6044848)), 3857) );
		
-- delete osm_lanes table if exist
DROP TABLE osm_lanes
-- In this table, we want to pull out the number of lanes
CREATE TEMPORARY TABLE osm_lanes AS (
	SELECT osm_id, name, highway, CAST(tags -> 'lanes' AS int) lanes, geom
	FROM temp_osm_road
	WHERE tags ? 'lanes' );
    
    
-- For those that do not have the lanes, if the road seg (with no lanes info) has the end/start point
-- intersecting with another end/start point of the road seg (with lanes info), and they are parallel to each other,
-- inherit the lanes info from the existing osm_lanes table 
INSERT INTO osm_lanes(osm_id, name, highway, lanes, geom)
	WITH ranked_road AS (
		SELECT r2.osm_id, r2.name, r2.highway, r1.lanes, r2.geom,
			   ROW_NUMBER() OVER (
			   		PARTITION BY r2.osm_id
			   		ORDER BY r1.lanes DESC
			   ) AS RANK 
		FROM osm_lanes r1
		JOIN (SELECT osm_id, name, highway, geom
				FROM temp_osm_road
				WHERE tags -> 'lanes' IS NULL) r2
		ON 	ST_Intersects(st_startpoint(r1.geom), st_startpoint(r2.geom))
			OR ST_Intersects(st_startpoint(r1.geom), st_endpoint(r2.geom))
			OR ST_Intersects(st_endpoint(r1.geom), st_startpoint(r2.geom))
			OR ST_Intersects(st_endpoint(r1.geom), st_endpoint(r2.geom))
		WHERE r1.osm_id != r2.osm_id
			  AND ( -- osm road should be PARALLEL TO the roads that ARE IN the 
				       ABS(DEGREES(ST_Angle(r1.geom, r2.geom))) BETWEEN 0 AND 10 -- 0 
				    OR ABS(DEGREES(ST_Angle(r1.geom, r2.geom))) BETWEEN 170 AND 190 -- 180
				    OR ABS(DEGREES(ST_Angle(r1.geom, r2.geom))) BETWEEN 350 AND 360  )  ) -- 360 
	SELECT osm_id, name, highway, lanes, geom
	FROM ranked_road
	WHERE RANK = 1


-- this is the table we are checking if the osm road are the same as the arnold road
	-- check if they are parallel and the arnold intersects the buffer from the osm road (the buffer size depend on the lanes)
CREATE TEMPORARY TABLE arnold_osm_road_unfiltered AS 
	WITH ranked_roads AS (
		SELECT arnold.objectid, arnold.og_objectid, arnold.geom, osm.osm_id, osm.name, osm.highway, osm.geom AS osm_geom,
			ST_LineSubstring( arnold.geom,
		  						LEAST(ST_LineLocatePoint(arnold.geom, ST_ClosestPoint(st_startpoint(osm.geom), arnold.geom)) , ST_LineLocatePoint(arnold.geom, ST_ClosestPoint(st_endpoint(osm.geom), arnold.geom))),
		  						GREATEST(ST_LineLocatePoint(arnold.geom, ST_ClosestPoint(st_startpoint(osm.geom), arnold.geom)) , ST_LineLocatePoint(arnold.geom, ST_ClosestPoint(st_endpoint(osm.geom), arnold.geom))) ) AS seg_geom,
			ROW_NUMBER() OVER (
		  	PARTITION BY osm.geom
		  	ORDER BY ST_distance( 
		  				ST_LineSubstring( arnold.geom,
		  								  LEAST(ST_LineLocatePoint(arnold.geom, ST_ClosestPoint(st_startpoint(osm.geom), arnold.geom)) , ST_LineLocatePoint(arnold.geom, ST_ClosestPoint(st_endpoint(osm.geom), arnold.geom))),
		  								  GREATEST(ST_LineLocatePoint(arnold.geom, ST_ClosestPoint(st_startpoint(osm.geom), arnold.geom)) , ST_LineLocatePoint(arnold.geom, ST_ClosestPoint(st_endpoint(osm.geom), arnold.geom))) ),
		  				osm.geom )
		  	) AS RANK
	FROM osm_lanes osm
	RIGHT JOIN jolie_bel1.arnold_roads arnold
	ON ST_Intersects(ST_buffer(osm.geom, (osm.lanes+1)*4), arnold.geom)
	WHERE (  ABS(DEGREES(ST_Angle(ST_LineSubstring( arnold.geom,
		  						LEAST(ST_LineLocatePoint(arnold.geom, ST_ClosestPoint(st_startpoint(osm.geom), arnold.geom)) , ST_LineLocatePoint(arnold.geom, ST_ClosestPoint(st_endpoint(osm.geom), arnold.geom))),
		  						GREATEST(ST_LineLocatePoint(arnold.geom, ST_ClosestPoint(st_startpoint(osm.geom), arnold.geom)) , ST_LineLocatePoint(arnold.geom, ST_ClosestPoint(st_endpoint(osm.geom), arnold.geom))) ), osm.geom))) BETWEEN 0 AND 15 -- 0 
			 OR ABS(DEGREES(ST_Angle(ST_LineSubstring( arnold.geom,
		  						LEAST(ST_LineLocatePoint(arnold.geom, ST_ClosestPoint(st_startpoint(osm.geom), arnold.geom)) , ST_LineLocatePoint(arnold.geom, ST_ClosestPoint(st_endpoint(osm.geom), arnold.geom))),
		  						GREATEST(ST_LineLocatePoint(arnold.geom, ST_ClosestPoint(st_startpoint(osm.geom), arnold.geom)) , ST_LineLocatePoint(arnold.geom, ST_ClosestPoint(st_endpoint(osm.geom), arnold.geom))) ), osm.geom))) BETWEEN 165 AND 195 -- 180
			 OR ABS(DEGREES(ST_Angle(ST_LineSubstring( arnold.geom,
		  						LEAST(ST_LineLocatePoint(arnold.geom, ST_ClosestPoint(st_startpoint(osm.geom), arnold.geom)) , ST_LineLocatePoint(arnold.geom, ST_ClosestPoint(st_endpoint(osm.geom), arnold.geom))),
		  						GREATEST(ST_LineLocatePoint(arnold.geom, ST_ClosestPoint(st_startpoint(osm.geom), arnold.geom)) , ST_LineLocatePoint(arnold.geom, ST_ClosestPoint(st_endpoint(osm.geom), arnold.geom))) ), osm.geom))) BETWEEN 345 AND 360 ) -- 360
	     )
	SELECT
		  objectid,
		  og_objectid,
		  osm_id,
		  name,
		  highway,
		  osm_geom
	FROM
		  ranked_roads
	WHERE
		  rank = 1;

		 
INSERT INTO arnold_osm_road_unfiltered(objectid, og_objectid, osm_id, name, highway, osm_geom)
	SELECT DISTINCT arnold_osm.objectid, arnold_osm.og_objectid, lanes.osm_id, lanes.name, lanes.highway, lanes.geom
	FROM osm_lanes lanes
	JOIN arnold_osm_road_unfiltered arnold_osm
	ON lanes.name = arnold_osm.name AND 
		(
			ST_Intersects(st_startpoint(lanes.geom), st_startpoint(arnold_osm.osm_geom))
			OR ST_Intersects(st_startpoint(lanes.geom), st_endpoint(arnold_osm.osm_geom))
			OR ST_Intersects(st_endpoint(lanes.geom), st_startpoint(arnold_osm.osm_geom))
			OR ST_Intersects(st_endpoint(lanes.geom), st_endpoint(arnold_osm.osm_geom))
		)
	WHERE lanes.osm_id NOT IN (
			SELECT osm_id
			FROM arnold_osm_road_unfiltered
		)	
	GROUP BY arnold_osm.objectid, arnold_osm.og_objectid, lanes.osm_id, lanes.name, lanes.highway, lanes.geom

	
CREATE TABLE <schema>.arnold_osm_conflated AS
	SELECT objectid, og_objectid, osm_id, osm_geom FROM arnold_osm_road_unfiltered



	