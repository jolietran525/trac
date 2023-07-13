-- osm roads with lane information -- temp table only
CREATE TEMPORARY TABLE temp_osm_road AS (
	SELECT osm_id, highway, name, tags, way AS geom
	FROM planet_osm_line
	WHERE	highway IN ('motorway', 'trunk', 'primary', 'secondary', 'tertiary', 'road', 'busway')  ); -- 71930
		
	
DROP TABLE osm_lanes
-- pull out the number of lanes
CREATE TEMPORARY TABLE osm_lanes AS (
	SELECT osm_id, name, highway, 
	    (
	        SELECT SUM(CAST(trim(value) AS INTEGER))
	        FROM unnest(string_to_array(regexp_replace(tags -> 'lanes', '[^\d]', ' ', 'g'), ' ')) AS value
	        WHERE trim(value) <> ''
	    ) AS lanes,
	    geom
	FROM temp_osm_road
	WHERE tags ? 'lanes'); --43540

CREATE INDEX osm_lanes_geom ON osm_lanes USING GIST (geom);
	

CREATE TEMPORARY TABLE osm_lanes_null AS (
	SELECT osm_id, name, highway, geom
	FROM temp_osm_road
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
-- first round:	    3226
-- second round:    1176
-- third round:	     600
-- fourth round:     363
-- fifth round:      241
-- sixth round:	     157
-- seventh round:    122
-- eighth round:      93
-- ninth round:      
-- tenth round:      
-- eleventh round:   
-- twelfth round:    

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
	
CREATE TEMPORARY TABLE arnold_osm_road AS 
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


INSERT INTO arnold_osm_road(objectid, og_objectid, osm_id, name, highway, osm_geom)
	SELECT DISTINCT arnold_osm.objectid, arnold_osm.og_objectid, lanes.osm_id, lanes.name, lanes.highway, lanes.geom
	FROM osm_lanes lanes
	JOIN arnold_osm_road arnold_osm ON lanes.name = arnold_osm.name AND lanes.highway = arnold_osm.highway
	WHERE lanes.osm_id NOT IN (
			SELECT osm_id
			FROM arnold_osm_road
		)
	GROUP BY arnold_osm.objectid, arnold_osm.og_objectid, lanes.osm_id, lanes.name, lanes.highway, lanes.geom
	
	
CREATE TABLE jolie_bel1.arnold_osm_conflated AS
	SELECT objectid, og_objectid, osm_id, osm_geom FROM arnold_osm_road