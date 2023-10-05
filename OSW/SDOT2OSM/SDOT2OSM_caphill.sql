----------------------------------------------------
/*                 SIDEWALK DATA                  */
----------------------------------------------------

-- osm sidewalk
CREATE TABLE jolie_sdot2osm_caphill.osm_sidewalk AS
	SELECT *, ST_Length(way) AS length
	FROM planet_osm_line pol 
	WHERE   highway='footway' AND tags->'footway'='sidewalk' AND
			way && st_setsrid( st_makebox2d( st_makepoint(-13616673,6039866), st_makepoint(-13613924,6042899)), 3857); --2385

ALTER TABLE jolie_sdot2osm_caphill.osm_sidewalk RENAME COLUMN way TO geom;
CREATE INDEX sw_geom ON jolie_sdot2osm_caphill.osm_sidewalk USING GIST (geom);




-- sdot sidewalk
--DROP TABLE jolie_sdot2osm_caphill.sdot_sidewalk
CREATE TABLE jolie_sdot2osm_caphill.sdot_sidewalk AS
	SELECT  ogc_fid,
			objectid,
			sw_width/39.37 AS sw_width,
			surftype, primarycrossslope AS cross_slope,
			sw_category,
			(ST_Dump(wkb_geometry)).geom AS geom,
			ST_Length(wkb_geometry) AS length
	FROM sdot.sidewalks
	WHERE   st_astext(wkb_geometry) != 'LINESTRING EMPTY'
			AND surftype != 'UIMPRV'
			AND sw_width != 0
			AND wkb_geometry && st_setsrid( st_makebox2d( st_makepoint(-13616673,6039866), st_makepoint(-13613924,6042899)), 3857); -- 1229

			
CREATE INDEX sdot_caphill_geom ON jolie_sdot2osm_caphill.sdot_sidewalk USING GIST (geom);




-- check if the osm_sidewalk table has osm_sidewalk drawn as a polygon
CREATE TABLE jolie_sdot2osm_caphill.polygon_osm_break AS
	WITH segments AS (
	    SELECT 
	        osm_id,
	        row_number() OVER (PARTITION BY osm_id ORDER BY osm_id, (pt).path) - 1 AS segment_number,
	        (ST_MakeLine(lag((pt).geom, 1, NULL) OVER (PARTITION BY osm_id ORDER BY osm_id, (pt).path), (pt).geom)) AS geom
	    FROM (
	        SELECT 
	            osm_id, 
	            ST_DumpPoints(geom) AS pt 
	        FROM 
	            jolie_sdot2osm_caphill.osm_sidewalk
	        WHERE ST_StartPoint(geom) = ST_Endpoint(geom)
	        ) AS dumps 
	)
	SELECT 
	    *
	FROM 
	    segments
	WHERE 
	    geom IS NOT NULL; -- 0

	    


-- FUNCTION
CREATE OR REPLACE FUNCTION public.f_within_degrees(_rad DOUBLE PRECISION, _thresh int) RETURNS boolean AS $$
    WITH m AS (SELECT mod(degrees(_rad)::NUMERIC, 180) AS angle)
        ,a AS (SELECT CASE WHEN m.angle > 90 THEN m.angle - 180 ELSE m.angle END AS angle FROM m)
    SELECT abs(a.angle) < _thresh FROM a;
$$ LANGUAGE SQL IMMUTABLE STRICT;





-- conflation
CREATE TABLE jolie_sdot2osm_caphill.sdot2osm_sw_raw AS 
	WITH ranked_roads AS (
		SELECT 
		  osm.osm_id AS osm_id,
		  sdot.objectid AS sdot_objectid,
		  sdot.sw_width,
		  sdot.surftype, 
		  sdot.cross_slope,
		  sdot.sw_category,
		  osm.geom AS osm_geom,
		  sdot.geom AS sdot_geom,
		  CASE
				WHEN (sdot.length > osm.length*0.85) THEN NULL
				ELSE ST_LineSubstring( osm.geom, LEAST(ST_LineLocatePoint(osm.geom, ST_ClosestPoint(st_startpoint(sdot.geom), osm.geom)) , ST_LineLocatePoint(osm.geom, ST_ClosestPoint(st_endpoint(sdot.geom), osm.geom))), GREATEST(ST_LineLocatePoint(osm.geom, ST_ClosestPoint(st_startpoint(sdot.geom), osm.geom)) , ST_LineLocatePoint(osm.geom, ST_ClosestPoint(st_endpoint(sdot.geom), osm.geom))) )
		  END AS osm_seg,
		  CASE
				WHEN (sdot.length > osm.length*0.85)
					THEN ST_LineSubstring( sdot.geom, LEAST(ST_LineLocatePoint(sdot.geom, ST_ClosestPoint(st_startpoint(osm.geom), sdot.geom)) , ST_LineLocatePoint(sdot.geom, ST_ClosestPoint(st_endpoint(osm.geom), sdot.geom))), GREATEST(ST_LineLocatePoint(sdot.geom, ST_ClosestPoint(st_startpoint(osm.geom), sdot.geom)) , ST_LineLocatePoint(sdot.geom, ST_ClosestPoint(st_endpoint(osm.geom), sdot.geom))) )
				ELSE NULL
		  END AS sdot_seg,
		  ROW_NUMBER() OVER (
		  	PARTITION BY (
		  		CASE
				  	WHEN (sdot.length > osm.length*0.85) 
				  		THEN  osm.geom
				  	ELSE sdot.geom
			  	END
		  	)
		  	ORDER BY
		  		CASE
				  	WHEN (sdot.length > osm.length*0.85)
				  		THEN --ST_distance(
				  			--ST_LineInterpolatePoint(ST_LineSubstring( sdot.geom, LEAST(ST_LineLocatePoint(sdot.geom, ST_ClosestPoint(st_startpoint(osm.geom), sdot.geom)) , ST_LineLocatePoint(sdot.geom, ST_ClosestPoint(st_endpoint(osm.geom), sdot.geom))), GREATEST(ST_LineLocatePoint(sdot.geom, ST_ClosestPoint(st_startpoint(osm.geom), sdot.geom)) , ST_LineLocatePoint(sdot.geom, ST_ClosestPoint(st_endpoint(osm.geom), sdot.geom))) ), 0.5), ST_LineInterpolatePoint(osm.geom, 0.5) )
				  			ST_Area(ST_Intersection(
				  				ST_Buffer(ST_LineSubstring( sdot.geom, LEAST(ST_LineLocatePoint(sdot.geom, ST_ClosestPoint(st_startpoint(osm.geom), sdot.geom)) , ST_LineLocatePoint(sdot.geom, ST_ClosestPoint(st_endpoint(osm.geom), sdot.geom))), GREATEST(ST_LineLocatePoint(sdot.geom, ST_ClosestPoint(st_startpoint(osm.geom), sdot.geom)) , ST_LineLocatePoint(sdot.geom, ST_ClosestPoint(st_endpoint(osm.geom), sdot.geom))) ), sdot.sw_width *4, 'endcap=flat join=round'),
				  				ST_Buffer(osm.geom, 1, 'endcap=flat join=round')
				  			)) 
				  	ELSE --ST_distance(
				  		 --ST_LineInterpolatePoint(ST_LineSubstring( osm.geom, LEAST(ST_LineLocatePoint(osm.geom, ST_ClosestPoint(st_startpoint(sdot.geom), osm.geom)) , ST_LineLocatePoint(osm.geom, ST_ClosestPoint(st_endpoint(sdot.geom), osm.geom))), GREATEST(ST_LineLocatePoint(osm.geom, ST_ClosestPoint(st_startpoint(sdot.geom), osm.geom)) , ST_LineLocatePoint(osm.geom, ST_ClosestPoint(st_endpoint(sdot.geom), osm.geom)))) , 0.5), ST_LineInterpolatePoint(sdot.geom, 0.5))
			  			 ST_Area(ST_Intersection(
				  				ST_Buffer(ST_LineSubstring( osm.geom, LEAST(ST_LineLocatePoint(osm.geom, ST_ClosestPoint(st_startpoint(sdot.geom), osm.geom)) , ST_LineLocatePoint(osm.geom, ST_ClosestPoint(st_endpoint(sdot.geom), osm.geom))), GREATEST(ST_LineLocatePoint(osm.geom, ST_ClosestPoint(st_startpoint(sdot.geom), osm.geom)) , ST_LineLocatePoint(osm.geom, ST_ClosestPoint(st_endpoint(sdot.geom), osm.geom))) ), 1, 'endcap=flat join=round'),
				  				ST_Buffer(sdot.geom, sdot.sw_width * 4, 'endcap=flat join=round')
				  			)) 
				 END DESC
		  	)  AS RANK
		FROM jolie_sdot2osm_caphill.osm_sidewalk osm
		JOIN jolie_sdot2osm_caphill.sdot_sidewalk sdot
		ON ST_Intersects(ST_Buffer(sdot.geom, sdot.sw_width * 4, 'endcap=flat join=round'), ST_Buffer(osm.geom, 1, 'endcap=flat join=round'))
		WHERE  CASE
				  	WHEN (sdot.length > osm.length*0.85)
				  		THEN 
							 public.f_within_degrees(ST_Angle(ST_LineSubstring( sdot.geom, LEAST(ST_LineLocatePoint(sdot.geom, ST_ClosestPoint(st_startpoint(osm.geom), sdot.geom)) , ST_LineLocatePoint(sdot.geom, ST_ClosestPoint(st_endpoint(osm.geom), sdot.geom))), GREATEST(ST_LineLocatePoint(sdot.geom, ST_ClosestPoint(st_startpoint(osm.geom), sdot.geom)) , ST_LineLocatePoint(sdot.geom, ST_ClosestPoint(st_endpoint(osm.geom), sdot.geom))) ), osm.geom), 15)
				  	ELSE -- osm.length > sdot.length
						 public.f_within_degrees(ST_Angle(ST_LineSubstring( osm.geom, LEAST(ST_LineLocatePoint(osm.geom, ST_ClosestPoint(st_startpoint(sdot.geom), osm.geom)) , ST_LineLocatePoint(osm.geom, ST_ClosestPoint(st_endpoint(sdot.geom), osm.geom))), GREATEST(ST_LineLocatePoint(osm.geom, ST_ClosestPoint(st_startpoint(sdot.geom), osm.geom)) , ST_LineLocatePoint(osm.geom, ST_ClosestPoint(st_endpoint(sdot.geom), osm.geom))) ), sdot.geom), 15) 
			   END
			   AND osm.osm_id NOT IN (SELECT distinct osm_id -- polygon
			   					 	  FROM jolie_sdot2osm_caphill.polygon_osm_break )
	    )
	SELECT
		  osm_id,
		  sdot_objectid,
		  sw_width,
		  surftype,
		  cross_slope,
		  sw_category,
		  CASE
		  	WHEN osm_seg IS NULL
		  		THEN ST_Length(ST_Intersection(sdot_seg, ST_Buffer(osm_geom, sw_width*5,  'endcap=flat join=round')))/GREATEST(ST_Length(sdot_seg), ST_Length(osm_geom))
		  	ELSE 
		  		ST_Length(ST_Intersection(osm_seg, ST_Buffer(sdot_geom, sw_width*5,  'endcap=flat join=round')))/GREATEST(ST_Length(osm_seg), ST_Length(sdot_geom))
		  END AS conflated_score,		  
		  osm_seg,
		  osm_geom,
		  sdot_seg,
		  sdot_geom
	FROM
		  ranked_roads
	WHERE
		  rank = 1 AND
		  -- Make sure this only return segments with the intersected segments between the osm and its conflated sdot beyond some threshold
		  -- for example, if the intersection between the (full) sdot and the (sub seg) osm is less than 10% of the length of any 2 of them, it means we did not conflated well, and we want to filter it out
		  CASE
		  	WHEN osm_seg IS NULL
		  		THEN ST_Length(ST_Intersection(sdot_seg, ST_Buffer(osm_geom, sw_width*5,  'endcap=flat join=round')))/GREATEST(ST_Length(sdot_seg), ST_Length(osm_geom)) > 0.1 -- TODO: need TO give it a PARAMETER later as we wanna change
		  	ELSE
		  		ST_Length(ST_Intersection(osm_seg, ST_Buffer(sdot_geom, sw_width*5,  'endcap=flat join=round')))/GREATEST(ST_Length(osm_seg), ST_Length(sdot_geom)) > 0.1 -- TODO: need TO give it a PARAMETER later as we wanna change
		  END; -- 156





		 
-- conflate the adjacent_linestring (osm) to sdot_sidewalk
-- since 0 polygon, so no need to conflate






-- This step give us the table while filtering out overlapped segments
		 -- If it overlapps, choose the one thats closer
DROP TABLE jolie_sdot2osm_caphill.sdot2osm_sw_prepocessed
CREATE TABLE jolie_sdot2osm_caphill.sdot2osm_sw_prepocessed AS
	SELECT  *
	FROM 
	    jolie_sdot2osm_caphill.sdot2osm_sw_raw
	WHERE 
	    (osm_id, sdot_objectid) NOT IN ( 
	    	-- case when the whole sdot already conflated to one osm, but then its subseg also conflated to another osm
			-- if these 2 osm overlap at least 50% of the shorter one between 2 of them, then we filter out the one that's further away from our sdot
	        SELECT 
				    r1.osm_id,
				    CASE
				        WHEN ST_Distance(ST_LineInterpolatePoint(r1.osm_geom, 0.5), ST_LineInterpolatePoint(r1.sdot_geom, 0.5)) < ST_Distance(ST_LineInterpolatePoint(r2.osm_geom, 0.5), ST_LineInterpolatePoint(r2.sdot_seg, 0.5))
				            THEN (r2.sdot_objectid)
				        ELSE (r1.sdot_objectid)
				    END AS sdot_objectid
			FROM jolie_sdot2osm_caphill.sdot2osm_sw_raw r1
			JOIN (
			    SELECT *
			    FROM jolie_sdot2osm_caphill.sdot2osm_sw_raw
			    WHERE osm_id IN (
			        SELECT osm_id
			        FROM jolie_sdot2osm_caphill.sdot2osm_sw_raw
			        GROUP BY osm_id
			        HAVING count(*) > 1 ) ) r2
			ON r1.osm_id = r2.osm_id
			WHERE     r1.osm_seg IS NOT NULL
				  AND r2.osm_seg IS NULL
				  AND ST_Length(ST_Intersection(ST_Buffer(r1.sdot_geom, r1.sw_width*5, 'endcap=flat join=round'), r2.sdot_seg))/LEAST(ST_Length(r1.sdot_geom), ST_Length(r2.sdot_seg)) > 0.4
			
			UNION ALL
			
			-- case when the whole osm already conflated to one sdot, but then its subseg also conflated to another sdot
			-- if these 2 sdot overlap at least 50% of the shorter one between 2 of them, then we filter out the one that's further away from our osm
			SELECT 
				    CASE
				        WHEN ST_Distance(ST_LineInterpolatePoint(r1.osm_geom, 0.5), ST_LineInterpolatePoint(r1.sdot_geom, 0.5)) < ST_Distance(ST_LineInterpolatePoint(r2.osm_seg, 0.5), ST_LineInterpolatePoint(r2.sdot_geom, 0.5))
				            THEN (r2.osm_id)
				        ELSE (r1.osm_id)
				    END AS osm_id,
				    r1.sdot_objectid
			FROM jolie_sdot2osm_caphill.sdot2osm_sw_raw r1
			JOIN (
			        SELECT *
			        FROM jolie_sdot2osm_caphill.sdot2osm_sw_raw
			        WHERE sdot_objectid IN (
			            SELECT sdot_objectid
			            FROM jolie_sdot2osm_caphill.sdot2osm_sw_raw
			            GROUP BY sdot_objectid
			            HAVING count(*) > 1 ) ) r2
			ON r1.sdot_objectid = r2.sdot_objectid
			WHERE 	  r1.sdot_seg IS NOT NULL
				  AND r2.sdot_seg IS NULL
				  AND ST_Length(ST_Intersection(ST_Buffer(r1.osm_geom, r1.sw_width*5, 'endcap=flat join=round'), r2.osm_seg))/LEAST(ST_Length(r1.osm_geom), ST_Length(r2.osm_seg)) > 0.4 -- TODO: need TO give it a PARAMETER later as we wanna change			
	    	); -- 154
    
    
 
-- keep track of what being filtered out from the last step:
	    -- this one suggests that sdot have segments in the network but osm does NOT!
SELECT *
FROM jolie_sdot2osm_caphill.sdot2osm_sw_raw
WHERE (osm_id, sdot_objectid) IN (
		SELECT
			    r1.osm_id,
			    CASE
			        WHEN ST_Distance(ST_LineInterpolatePoint(r1.osm_geom, 0.5), ST_LineInterpolatePoint(r1.sdot_geom, 0.5)) < ST_Distance(ST_LineInterpolatePoint(r2.osm_geom, 0.5), ST_LineInterpolatePoint(r2.sdot_seg, 0.5))
			            THEN (r2.sdot_objectid)
			        ELSE (r1.sdot_objectid)
			    END AS sdot_objectid
		FROM jolie_sdot2osm_caphill.sdot2osm_sw_raw r1
		JOIN (
		    SELECT *
		    FROM jolie_sdot2osm_caphill.sdot2osm_sw_raw
		    WHERE osm_id IN (
		        SELECT osm_id
		        FROM jolie_sdot2osm_caphill.sdot2osm_sw_raw
		        GROUP BY osm_id
		        HAVING count(*) > 1 ) ) r2
		ON r1.osm_id = r2.osm_id
		WHERE     r1.osm_seg IS NOT NULL
			  AND r2.osm_seg IS NULL
			  AND ST_Length(ST_Intersection(ST_Buffer(r1.sdot_geom, r1.sw_width*5, 'endcap=flat join=round'), r2.sdot_seg))/LEAST(ST_Length(r1.sdot_geom), ST_Length(r2.sdot_seg)) > 0.5 );

			  
			  

-- keep track of what being filtered out from the last step:
	    -- this one suggests that osm have segments in the network but sdot does NOT! 
SELECT *
FROM jolie_sdot2osm_caphill.sdot2osm_sw_raw
WHERE (osm_id, sdot_objectid) IN  (
		SELECT 
			    CASE 
			        WHEN ST_Distance(ST_LineInterpolatePoint(r1.osm_geom, 0.5), ST_LineInterpolatePoint(r1.sdot_geom, 0.5)) < ST_Distance(ST_LineInterpolatePoint(r2.osm_seg, 0.5), ST_LineInterpolatePoint(r2.sdot_geom, 0.5))
			            THEN (r2.osm_id)
			        ELSE (r1.osm_id)
			    END AS osm_id,
			    r1.sdot_objectid
		FROM jolie_sdot2osm_caphill.sdot2osm_sw_raw r1
		JOIN (
		        SELECT *
		        FROM jolie_sdot2osm_caphill.sdot2osm_sw_raw
		        WHERE sdot_objectid IN (
		            SELECT sdot_objectid
		            FROM jolie_sdot2osm_caphill.sdot2osm_sw_raw
		            GROUP BY sdot_objectid
		            HAVING count(*) > 1 ) ) r2
		ON r1.sdot_objectid = r2.sdot_objectid
		WHERE 	  r1.sdot_seg IS NOT NULL
			  AND r2.sdot_seg IS NULL
			  AND ST_Length(ST_Intersection(ST_Buffer(r1.osm_geom, r1.sw_width*5, 'endcap=flat join=round'), r2.osm_seg))/LEAST(ST_Length(r1.osm_geom), ST_Length(r2.osm_seg)) > 0.5  );

	  




-- create a table with metrics:
	-- GROUP BY sdot_objectid, the SUM the length of the conflated sdot divided by the length of the original sdot:
			 -- This will give us how much of the sdot got conflated
CREATE TABLE jolie_sdot2osm_caphill.sdot2osm_metrics_sdot AS
	SELECT  sdot.objectid,
			COALESCE(SUM(ST_Length(sdot2osm.conflated_sdot_seg))/ST_Length(sdot.geom), 0) AS percent_conflated,
			sdot.geom, ST_UNION(sdot2osm.conflated_sdot_seg) AS sdot_conflated_subseg 
	FROM jolie_sdot2osm_caphill.sdot_sidewalk sdot
	LEFT JOIN (
				SELECT *,
						CASE 
							WHEN osm_seg IS NOT NULL
								THEN 
								ST_LineSubstring( sdot_geom, LEAST(ST_LineLocatePoint(sdot_geom, ST_ClosestPoint(st_startpoint(osm_seg), sdot_geom)) , ST_LineLocatePoint(sdot_geom, ST_ClosestPoint(st_endpoint(osm_seg), sdot_geom))), GREATEST(ST_LineLocatePoint(sdot_geom, ST_ClosestPoint(st_startpoint(osm_seg), sdot_geom)) , ST_LineLocatePoint(sdot_geom, ST_ClosestPoint(st_endpoint(osm_seg), sdot_geom))) )
							ELSE sdot_seg
						END conflated_sdot_seg
						
				FROM jolie_sdot2osm_caphill.sdot2osm_sw_prepocessed
			) sdot2osm
	ON sdot.objectid = sdot2osm.sdot_objectid
	GROUP BY sdot.objectid, sdot2osm.sdot_objectid, sdot.geom; --124




-- create a table with metrics:
	-- GROUP BY osm_id, the SUM the length of the conflated osm divided by the length of the original osm:
			 -- This will give us how much of the osm got conflated
CREATE TABLE jolie_sdot2osm_caphill.sdot2osm_metrics_osm AS
		SELECT  osm.osm_id,
				COALESCE(SUM(ST_Length(sdot2osm.conflated_osm_seg))/ST_Length(osm.geom), 0) AS percent_conflated,
				osm.geom, ST_UNION(sdot2osm.conflated_osm_seg) AS osm_conflated_subseg
		FROM jolie_sdot2osm_caphill.osm_sidewalk osm
		LEFT JOIN (
					SELECT *,
							CASE 
								WHEN sdot_seg IS NOT NULL
									THEN 
									ST_LineSubstring( osm_geom, LEAST(ST_LineLocatePoint(osm_geom, ST_ClosestPoint(st_startpoint(sdot_seg), osm_geom)) , ST_LineLocatePoint(osm_geom, ST_ClosestPoint(st_endpoint(sdot_seg), osm_geom))), GREATEST(ST_LineLocatePoint(osm_geom, ST_ClosestPoint(st_startpoint(sdot_seg), osm_geom)) , ST_LineLocatePoint(osm_geom, ST_ClosestPoint(st_endpoint(sdot_seg), osm_geom))) )
								ELSE osm_seg
							END conflated_osm_seg
					FROM jolie_sdot2osm_caphill.sdot2osm_sw_prepocessed
				) sdot2osm
		ON osm.osm_id = sdot2osm.osm_id
		GROUP BY osm.osm_id, sdot2osm.osm_id, osm.geom;

    
	  	  



CREATE TABLE jolie_sdot2osm_caphill.sidewalk AS
	SELECT  osm_id,
		    sdot_objectid,
		    sw_width AS width,
		    CASE WHEN surftype ILIKE 'PCC%' THEN 'concrete'
		         WHEN surftype ILIKE 'AC%' THEN 'asphalt'
		         ELSE 'paved'
		    END AS sdot_surface,
		    hstore(CAST('cross_slope' AS TEXT), CAST(cross_slope AS TEXT)) AS cross_slope,
		    conflated_score,
		    CASE
			    WHEN osm_seg IS NOT NULL
			    	THEN 'no'
		    	ELSE 'yes'
		    END AS original_way,
		    CASE
			    WHEN osm_seg IS NOT NULL
			    	THEN osm_seg
		    	ELSE osm_geom
		    END AS way
	FROM jolie_sdot2osm_caphill.sdot2osm_sw_prepocessed;






-- FINAL TABLE that will be exported
CREATE TABLE jolie_sdot2osm_caphill.sidewalk_json AS
	SELECT  sdot2osm.osm_id,
			sdot2osm.sdot_objectid,
			osm.highway,
			osm.surface,
			sdot2osm.sdot_surface,
			CAST(sdot2osm.width AS TEXT),
			osm.tags||sdot2osm.cross_slope AS tags,
			conflated_score,
			original_way,
			sdot2osm.way
	FROM jolie_sdot2osm_caphill.sidewalk sdot2osm
	JOIN jolie_sdot2osm_caphill.osm_sidewalk osm
	ON sdot2osm.osm_id = osm.osm_id
	
	UNION ALL
	
	SELECT  osm_id,
			NULL AS "sdot_objectid",
			highway, surface, 
			NULL AS "sdot_surface", 
			width, tags, 
			NULL AS conflated_score, 
			NULL AS original_way, 
			geom AS "way"
	FROM jolie_sdot2osm_caphill.osm_sidewalk
	WHERE osm_id NOT IN (
			SELECT DISTINCT osm_id
			FROM jolie_sdot2osm_caphill.sidewalk ); --219
	  

----------------------------------------------------
/*                 CROSSING DATA                  */
----------------------------------------------------
CREATE TABLE jolie_sdot2osm_caphill.osm_crossing AS
	SELECT *
	FROM planet_osm_line pol 
	WHERE   highway='footway' AND tags->'footway'='crossing' AND
			way && st_setsrid( st_makebox2d( st_makepoint(-13616596,6053033), st_makepoint(-13615615,6053724)), 3857); --114

			
			
			
CREATE TABLE jolie_sdot2osm_caphill.sdot_accpedsig AS
	SELECT *
	FROM sdot.accessible_pedestrian_signals aps
	WHERE  wkb_geometry && st_setsrid( st_makebox2d( st_makepoint(-13616596,6053033), st_makepoint(-13615615,6053724)), 3857); -- 4

ALTER TABLE jolie_sdot2osm_caphill.sdot_accpedsig RENAME COLUMN wkb_geometry TO geom;
	

-- test and see which buffer size works
SELECT osm.*, sdot.geom
FROM jolie_sdot2osm_caphill.osm_crossing osm 
JOIN jolie_sdot2osm_caphill.sdot_accpedsig sdot
ON ST_Intersects(osm.geom, ST_Buffer(sdot.geom, 20))


-- FINAL TABLE
CREATE TABLE jolie_sdot2osm_caphill.crossing_json AS 
	SELECT 
		osm.osm_id, osm.highway,
		(osm.tags ||
		hstore('crossing', 'marked') || 
		hstore('crossing:signals', 'yes') ||
		hstore('crossing:signals:sound', 'yes') ||
		hstore('crossing:signals:button_operated', 'yes') ||
		hstore('crossing:signals:countdown', 'yes')) AS tags,
		osm.geom AS way
	FROM (SELECT osm.osm_id, osm.highway, osm.tags, osm.geom
		FROM jolie_sdot2osm_caphill.osm_crossing osm 
		JOIN jolie_sdot2osm_caphill.sdot_accpedsig sdot
		ON ST_Intersects(osm.geom, ST_Buffer(sdot.geom, 20))
		) osm
	
	UNION
	
	-- IF the crossing did NOT conflate:
	SELECT osm.osm_id, osm.highway, osm.tags, osm.geom AS way
	FROM jolie_sdot2osm_caphill.osm_crossing osm
	WHERE osm.osm_id NOT IN (
		SELECT osm.osm_id
		FROM jolie_sdot2osm_caphill.osm_crossing osm 
		JOIN jolie_sdot2osm_caphill.sdot_accpedsig sdot
		ON ST_Intersects(osm.geom, ST_Buffer(sdot.geom, 20))); -- 114