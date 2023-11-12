-- osm roads with lane information -- temp table only
CREATE TABLE osm_road AS (
	SELECT osm_id, highway, name, tags, way AS geom
	FROM planet_osm_line
	WHERE	highway IN ('motorway', 'trunk', 'primary', 'secondary', 'tertiary', 'road', 'busway')  ); -- 71930
		
	
-- pull out the number of lanes
CREATE TABLE osm_lanes AS (
	SELECT osm_id, name, highway, 
	    (
	        SELECT SUM(CAST(trim(value) AS INTEGER))
	        FROM unnest(string_to_array(regexp_replace(tags -> 'lanes', '[^\d]', ' ', 'g'), ' ')) AS value
	        WHERE trim(value) <> ''
	    ) AS lanes,
	    geom
	FROM osm_road
	WHERE tags ? 'lanes'); --43540

CREATE INDEX osm_lanes_geom ON osm_lanes USING GIST (geom);
	

CREATE TABLE osm_lanes_null AS (
	SELECT osm_id, name, highway, geom
	FROM osm_road
	WHERE tags -> 'lanes' IS NULL ) ;   -- 28390

CREATE INDEX osm_lanes_null_geom ON osm_lanes_null USING GIST (geom);


-- for those that does not have the lanes, inherit the lanes when the end/start point intersect with another end/start point of the osm road
-- TODO: make a while loop
INSERT INTO osm_lanes(osm_id, name, highway, lanes, geom)
	WITH ranked_road AS (
		SELECT r2.osm_id, r2.name, r2.highway, r1.lanes, r2.geom,
			   ROW_NUMBER() OVER (
			   		PARTITION BY r2.osm_id
			   		ORDER BY r1.lanes DESC
			   ) AS RANK 
		FROM osm_lanes r1
		JOIN osm_lanes_null r2
		ON 	ST_Intersects(st_startpoint(r1.geom), st_startpoint(r2.geom))
			OR ST_Intersects(st_startpoint(r1.geom), st_endpoint(r2.geom))
			OR ST_Intersects(st_endpoint(r1.geom), st_startpoint(r2.geom))
			OR ST_Intersects(st_endpoint(r1.geom), st_endpoint(r2.geom))
		WHERE r1.osm_id != r2.osm_id
			  AND ( -- osm road should be PARALLEL TO the roads that ARE IN the 
					   ABS(DEGREES(ST_Angle(r1.geom, r2.geom))) BETWEEN 0 AND 10 -- 0 
				    OR ABS(DEGREES(ST_Angle(r1.geom, r2.geom))) BETWEEN 170 AND 190 -- 180
				    OR ABS(DEGREES(ST_Angle(r1.geom, r2.geom))) BETWEEN 350 AND 360  )   -- 360 
			 AND r2.osm_id NOT IN (SELECT osm_id FROM osm_lanes)
		     )
	SELECT osm_id, name, highway, lanes, geom
	FROM ranked_road
	WHERE RANK = 1;


-- procedure attempt
CREATE OR REPLACE PROCEDURE insert_osm_lanes()
LANGUAGE plpgsql AS $$
DECLARE 
	_itr_cnt int := 0;
	_res_cnt int;
BEGIN 

	LOOP
		-- increment counter
		_itr_cnt := _itr_cnt + 1;
	
		WITH ranked_road AS (
			SELECT r2.osm_id, r2.name, r2.highway, r1.lanes, r2.geom,
				   ROW_NUMBER() OVER (
				   		PARTITION BY r2.osm_id
				   		ORDER BY r1.lanes DESC
				   ) AS RANK 
			FROM osm_lanes r1
			JOIN osm_lanes_null r2
			ON 	ST_Intersects(st_startpoint(r1.geom), st_startpoint(r2.geom))
				OR ST_Intersects(st_startpoint(r1.geom), st_endpoint(r2.geom))
				OR ST_Intersects(st_endpoint(r1.geom), st_startpoint(r2.geom))
				OR ST_Intersects(st_endpoint(r1.geom), st_endpoint(r2.geom))
			WHERE r1.osm_id != r2.osm_id
				  AND ( -- osm road should be PARALLEL TO the roads that ARE IN the 
						   ABS(DEGREES(ST_Angle(r1.geom, r2.geom))) BETWEEN 0 AND 10 -- 0 
					    OR ABS(DEGREES(ST_Angle(r1.geom, r2.geom))) BETWEEN 170 AND 190 -- 180
					    OR ABS(DEGREES(ST_Angle(r1.geom, r2.geom))) BETWEEN 350 AND 360  )   -- 360 
				 AND r2.osm_id NOT IN (SELECT osm_id FROM osm_lanes)
		), ins AS (
			INSERT INTO osm_lanes(osm_id, name, highway, lanes, geom)
			SELECT osm_id, name, highway, lanes, geom
			FROM ranked_road
			WHERE RANK = 1
			RETURNING 1
		)
		SELECT  count(*)
		  INTO  _res_cnt
	      FROM  ins;

		RAISE NOTICE 'Iteration %: inserted % rows', _itr_cnt, _res_cnt;
	     
		IF (_res_cnt = 0) THEN
			EXIT;
		END IF;
	END LOOP;
    
END $$;

CALL insert_osm_lanes();



-- update the number of lanes
UPDATE osm_lanes
SET lanes = subquery.updated_lanes
FROM (
    SELECT l1.osm_id, l1.name, l1.highway, l1.geom, SUM(l2.lanes) AS updated_lanes
    FROM osm_lanes l1
    JOIN osm_lanes l2 ON ST_Intersects(ST_StartPoint(l1.geom), l2.geom) AND ST_Equals(l1.geom, l2.geom) IS FALSE
    WHERE l1.lanes > 12
    GROUP BY l2.name, l2.highway, l1.osm_id, l1.name, l1.highway, l1.geom
) AS subquery
WHERE osm_lanes.osm_id = subquery.osm_id;



INSERT INTO osm_lanes(osm_id, name, highway, lanes, geom)
	SELECT null_lane.osm_id, null_lane.name, null_lane.highway, lanes.max_lane, null_lane.geom
	FROM osm_lanes_null null_lane
	JOIN (
		SELECT name, highway, max(lanes) AS max_lane
		FROM osm_lanes
		GROUP BY name, highway
		) lanes
	ON null_lane.name = lanes.name AND null_lane.highway = lanes.highway
	WHERE null_lane.osm_id NOT IN (SELECT osm_id FROM osm_lanes)
	

INSERT INTO osm_lanes(osm_id, name, highway, lanes, geom)
	SELECT lane_null.osm_id, lane_null.name, lane_null.highway, MAX(lane.lanes) , lane_null.geom
	FROM osm_lanes_null lane_null
	JOIN osm_lanes lane
	ON (ST_Intersects(ST_Startpoint(lane_null.geom), lane.geom) OR ST_Intersects(ST_Endpoint(lane_null.geom), lane.geom))
		AND lane_null.name = lane.name
	WHERE lane_null.osm_id NOT IN (SELECT osm_id FROM osm_lanes)
	GROUP BY lane.name, lane_null.osm_id, lane_null.name, lane_null.highway, lane_null.geom

	
	
INSERT INTO osm_lanes(osm_id, name, highway, lanes, geom)
	SELECT lane_null.osm_id, lane_null.name, lane_null.highway, MAX(lane.lanes) , lane_null.geom
	FROM osm_lanes_null lane_null
	JOIN osm_lanes lane
	ON (ST_Intersects(ST_Startpoint(lane_null.geom), lane.geom) OR ST_Intersects(ST_Endpoint(lane_null.geom), lane.geom))
	WHERE lane_null.osm_id NOT IN (SELECT osm_id FROM osm_lanes)
	GROUP BY lane.name, lane_null.osm_id, lane_null.name, lane_null.highway, lane_null.geom



INSERT INTO osm_lanes(osm_id, name, highway, lanes, geom)
	SELECT null_lane.osm_id, null_lane.name, null_lane.highway, lane.lanes, null_lane.geom
	FROM osm_lanes_null null_lane
	JOIN (
		SELECT highway, CEIL(avg(lanes)) AS lanes
		FROM osm_lanes
		GROUP BY highway
		) lane
	ON null_lane.highway = lane.highway
	WHERE osm_id NOT IN (SELECT osm_id FROM osm_lanes)



CREATE TABLE osm2arnold_road AS 
	WITH ranked_roads AS (
		SELECT arnold.objectid, arnold.og_objectid, arnold.routeid, arnold.beginmeasure, arnold.endmeasure, arnold.geom, osm.osm_id, osm.name, osm.highway, osm.geom AS osm_geom,
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
	RIGHT JOIN arnold.wapr_linestring arnold
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
		  routeid,
		  beginmeasure,
		  endmeasure,
		  osm_id,
		  name,
		  highway,
		  osm_geom
	FROM
		  ranked_roads
	WHERE
		  rank = 1;


INSERT INTO osm2arnold_road(objectid, og_objectid,  routeid, beginmeasure, endmeasure, osm_id, name, highway, osm_geom)
	SELECT DISTINCT arnold_osm.objectid, arnold_osm.og_objectid, lanes.osm_id, lanes.name, lanes.highway, lanes.geom
	FROM osm_lanes lanes
	JOIN osm2arnold_road arnold_osm ON lanes.name = arnold_osm.name AND lanes.highway = arnold_osm.highway
	WHERE lanes.osm_id NOT IN (
			SELECT osm_id
			FROM osm2arnold_road
		)
	GROUP BY arnold_osm.objectid, arnold_osm.og_objectid, lanes.osm_id, lanes.name, lanes.highway, lanes.geom