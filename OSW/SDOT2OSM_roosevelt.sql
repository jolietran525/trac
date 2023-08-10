----------------------------------------------------
/*                 SIDEWALK DATA                  */
----------------------------------------------------

-- osm sidewalk
CREATE TABLE jolie_sdot2osm_roosevelt.osm_sidewalk AS
	SELECT *, ST_Length(way) AS length
	FROM planet_osm_line pol 
	WHERE   highway='footway' AND tags->'footway'='sidewalk' AND
			way && st_setsrid( st_makebox2d( st_makepoint(-13616596,6053033), st_makepoint(-13615615,6053724)), 3857); --207

ALTER TABLE jolie_sdot2osm_roosevelt.osm_sidewalk RENAME COLUMN way TO geom;
CREATE INDEX sw_roosevelt_geom ON jolie_sdot2osm_roosevelt.osm_sidewalk USING GIST (geom);

-- osm crossing
CREATE TABLE jolie_sdot2osm_roosevelt.osm_crossing AS
	SELECT *
	FROM planet_osm_line pol 
	WHERE   highway='footway' AND tags->'footway'='crossing' AND
			way && st_setsrid( st_makebox2d( st_makepoint(-13616596,6053033), st_makepoint(-13615615,6053724)), 3857); --810

ALTER TABLE jolie_sdot2osm_roosevelt.osm_crossing RENAME COLUMN way TO geom;
CREATE INDEX crossing_roosevelt_geom ON jolie_sdot2osm_roosevelt.osm_crossing USING GIST (geom);

-- osm connlink
CREATE TABLE jolie_sdot2osm_roosevelt.osm_connlink AS
	SELECT sw.*
	FROM jolie_sdot2osm_roosevelt.osm_crossing crossing
	JOIN jolie_sdot2osm_roosevelt.osm_sidewalk sw
	ON ST_Intersects(sw.geom, crossing.geom)
	WHERE sw.length < 15; -- 97
	

	
-- sdot sidewalk
CREATE TABLE jolie_sdot2osm_roosevelt.sdot_sidewalk AS
	SELECT *, ST_Length(geom) AS length
	FROM sdot.sidewalks
	WHERE   st_astext(geom) != 'LINESTRING EMPTY'
			AND surftype != 'UIMPRV'
			AND sw_width != 0
			AND geom && st_setsrid( st_makebox2d( st_makepoint(-13616596,6053033), st_makepoint(-13615615,6053724)), 3857); -- 124

CREATE INDEX sdot_roosevelt_geom ON jolie_sdot2osm_roosevelt.sdot_sidewalk USING GIST (geom);


-- check if the osm_sidewalk table has osm_sidewalk drawn as a polygon
CREATE TABLE jolie_sdot2osm_roosevelt.polygon_osm_break AS
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
	            jolie_sdot2osm_roosevelt.osm_sidewalk
	        WHERE ST_StartPoint(geom) = ST_Endpoint(geom)
	        ) AS dumps 
	)
	SELECT 
	    *
	FROM 
	    segments
	WHERE 
	    geom IS NOT NULL; -- 0


-- conflation
DROP TABLE jolie_sdot2osm_roosevelt.sdot2osm_sw_raw
CREATE TABLE jolie_sdot2osm_roosevelt.sdot2osm_sw_raw AS 
	WITH ranked_roads AS (
		SELECT 
		  osm.osm_id AS osm_id,
		  sdot.objectid AS sdot_objectid,
		  sdot.sw_width/39.37 AS sw_width,
		  sdot.surftype AS surftype, 
		  sdot.primarycrossslope AS cross_slope,
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
				  		THEN ST_distance(
				  			ST_LineInterpolatePoint(ST_LineSubstring( sdot.geom, LEAST(ST_LineLocatePoint(sdot.geom, ST_ClosestPoint(st_startpoint(osm.geom), sdot.geom)) , ST_LineLocatePoint(sdot.geom, ST_ClosestPoint(st_endpoint(osm.geom), sdot.geom))), GREATEST(ST_LineLocatePoint(sdot.geom, ST_ClosestPoint(st_startpoint(osm.geom), sdot.geom)) , ST_LineLocatePoint(sdot.geom, ST_ClosestPoint(st_endpoint(osm.geom), sdot.geom))) ), 0.5), ST_LineInterpolatePoint(osm.geom, 0.5) )
				  	ELSE ST_distance(
				  		ST_LineInterpolatePoint(ST_LineSubstring( osm.geom, LEAST(ST_LineLocatePoint(osm.geom, ST_ClosestPoint(st_startpoint(sdot.geom), osm.geom)) , ST_LineLocatePoint(osm.geom, ST_ClosestPoint(st_endpoint(sdot.geom), osm.geom))), GREATEST(ST_LineLocatePoint(osm.geom, ST_ClosestPoint(st_startpoint(sdot.geom), osm.geom)) , ST_LineLocatePoint(osm.geom, ST_ClosestPoint(st_endpoint(sdot.geom), osm.geom)))) , 0.5), ST_LineInterpolatePoint(sdot.geom, 0.5))
			  	END
		  	) AS RANK
		FROM jolie_sdot2osm_roosevelt.osm_sidewalk osm
		JOIN jolie_sdot2osm_roosevelt.sdot_sidewalk sdot
		ON ST_Intersects(ST_Buffer(sdot.geom, sdot.sw_width/39.37 + 5, 'endcap=flat join=round'), osm.geom)
		WHERE  osm.osm_id NOT IN (SELECT osm_id FROM jolie_sdot2osm_roosevelt.osm_connlink) AND 
			   CASE
				  	WHEN (sdot.length > osm.length*0.85)
				  		THEN (  ABS(DEGREES(ST_Angle(ST_LineSubstring( sdot.geom, LEAST(ST_LineLocatePoint(sdot.geom, ST_ClosestPoint(st_startpoint(osm.geom), sdot.geom)) , ST_LineLocatePoint(sdot.geom, ST_ClosestPoint(st_endpoint(osm.geom), sdot.geom))), GREATEST(ST_LineLocatePoint(sdot.geom, ST_ClosestPoint(st_startpoint(osm.geom), sdot.geom)) , ST_LineLocatePoint(sdot.geom, ST_ClosestPoint(st_endpoint(osm.geom), sdot.geom))) ), osm.geom))) BETWEEN 0 AND 10 -- 0 
							 OR ABS(DEGREES(ST_Angle(ST_LineSubstring( sdot.geom, LEAST(ST_LineLocatePoint(sdot.geom, ST_ClosestPoint(st_startpoint(osm.geom), sdot.geom)) , ST_LineLocatePoint(sdot.geom, ST_ClosestPoint(st_endpoint(osm.geom), sdot.geom))), GREATEST(ST_LineLocatePoint(sdot.geom, ST_ClosestPoint(st_startpoint(osm.geom), sdot.geom)) , ST_LineLocatePoint(sdot.geom, ST_ClosestPoint(st_endpoint(osm.geom), sdot.geom))) ), osm.geom))) BETWEEN 170 AND 190 -- 180
							 OR ABS(DEGREES(ST_Angle(ST_LineSubstring( sdot.geom, LEAST(ST_LineLocatePoint(sdot.geom, ST_ClosestPoint(st_startpoint(osm.geom), sdot.geom)) , ST_LineLocatePoint(sdot.geom, ST_ClosestPoint(st_endpoint(osm.geom), sdot.geom))), GREATEST(ST_LineLocatePoint(sdot.geom, ST_ClosestPoint(st_startpoint(osm.geom), sdot.geom)) , ST_LineLocatePoint(sdot.geom, ST_ClosestPoint(st_endpoint(osm.geom), sdot.geom))) ), osm.geom))) BETWEEN 350 AND 360 ) -- 360
							 AND ST_Length(ST_LineSubstring( sdot.geom, LEAST(ST_LineLocatePoint(sdot.geom, ST_ClosestPoint(st_startpoint(osm.geom), sdot.geom)) , ST_LineLocatePoint(sdot.geom, ST_ClosestPoint(st_endpoint(osm.geom), sdot.geom))), GREATEST(ST_LineLocatePoint(sdot.geom, ST_ClosestPoint(st_startpoint(osm.geom), sdot.geom)) , ST_LineLocatePoint(sdot.geom, ST_ClosestPoint(st_endpoint(osm.geom), sdot.geom))) )) BETWEEN (osm.length*0.75) AND (osm.length*1.25)
				  	ELSE -- osm.length > sdot.length
				  		(   ABS(DEGREES(ST_Angle(ST_LineSubstring( osm.geom, LEAST(ST_LineLocatePoint(osm.geom, ST_ClosestPoint(st_startpoint(sdot.geom), osm.geom)) , ST_LineLocatePoint(osm.geom, ST_ClosestPoint(st_endpoint(sdot.geom), osm.geom))), GREATEST(ST_LineLocatePoint(osm.geom, ST_ClosestPoint(st_startpoint(sdot.geom), osm.geom)) , ST_LineLocatePoint(osm.geom, ST_ClosestPoint(st_endpoint(sdot.geom), osm.geom))) ), sdot.geom))) BETWEEN 0 AND 10 -- 0 
						 OR ABS(DEGREES(ST_Angle(ST_LineSubstring( osm.geom, LEAST(ST_LineLocatePoint(osm.geom, ST_ClosestPoint(st_startpoint(sdot.geom), osm.geom)) , ST_LineLocatePoint(osm.geom, ST_ClosestPoint(st_endpoint(sdot.geom), osm.geom))), GREATEST(ST_LineLocatePoint(osm.geom, ST_ClosestPoint(st_startpoint(sdot.geom), osm.geom)) , ST_LineLocatePoint(osm.geom, ST_ClosestPoint(st_endpoint(sdot.geom), osm.geom))) ), sdot.geom))) BETWEEN 170 AND 190 -- 180
						 OR ABS(DEGREES(ST_Angle(ST_LineSubstring( osm.geom, LEAST(ST_LineLocatePoint(osm.geom, ST_ClosestPoint(st_startpoint(sdot.geom), osm.geom)) , ST_LineLocatePoint(osm.geom, ST_ClosestPoint(st_endpoint(sdot.geom), osm.geom))), GREATEST(ST_LineLocatePoint(osm.geom, ST_ClosestPoint(st_startpoint(sdot.geom), osm.geom)) , ST_LineLocatePoint(osm.geom, ST_ClosestPoint(st_endpoint(sdot.geom), osm.geom))) ), sdot.geom))) BETWEEN 350 AND 360 ) -- 360
						  AND ST_Length(ST_LineSubstring( osm.geom, LEAST(ST_LineLocatePoint(osm.geom, ST_ClosestPoint(st_startpoint(sdot.geom), osm.geom)) , ST_LineLocatePoint(osm.geom, ST_ClosestPoint(st_endpoint(sdot.geom), osm.geom))), GREATEST(ST_LineLocatePoint(osm.geom, ST_ClosestPoint(st_startpoint(sdot.geom), osm.geom)) , ST_LineLocatePoint(osm.geom, ST_ClosestPoint(st_endpoint(sdot.geom), osm.geom))) )) BETWEEN ((sdot.length)*0.75) AND ((sdot.length)*1.25)
			   END AND
			   osm.osm_id NOT IN (SELECT distinct osm_id -- polygon
			   					  FROM jolie_sdot2osm_roosevelt.polygon_osm_break )
	    )
	SELECT
		  osm_id,
		  sdot_objectid,
		  sw_width,
		  surftype,
		  cross_slope,
		  osm_seg,
		  osm_geom,
		  sdot_seg,
		  sdot_geom
	FROM
		  ranked_roads
	WHERE
		  rank = 1;

	   
-- conflate the adjacent_linestring (osm) to sdot_sidewalk
-- since 0 polygon, so no need to conflate
		 
-- case: osm > sdot:
		 -- if there are 2 sdot looking at same osm_seg (more than 80% coverage)
		 -- chose the sdot that is closer to the osm_seg
DROP TABLE jolie_sdot2osm_roosevelt.sidewalk
CREATE TABLE jolie_sdot2osm_roosevelt.sidewalk AS
	SELECT  
	    osm_id,
	    CAST(CONCAT(osm_id,'.',
	    CASE WHEN osm_seg IS NOT NULL THEN 
	        ROW_NUMBER() OVER (PARTITION BY osm_id ORDER BY ST_Distance(ST_Startpoint(osm_geom), ST_StartPoint(osm_seg))) 
	    ELSE 
	        0 
	    END) AS TEXT) AS sdot_osm_id,
	    sw_width AS width,
	    CASE WHEN surftype ILIKE 'PCC%' THEN 'concrete'
	         WHEN surftype ILIKE 'AC%' THEN 'asphalt'
	         ELSE 'paved'
	    END AS sdot_surface,
	    hstore(CAST('cross_slope' AS TEXT), CAST(cross_slope AS TEXT)),
	    CASE WHEN osm_seg IS NOT NULL THEN osm_seg
	    ELSE osm_geom
	    END AS way    
	FROM 
	    jolie_sdot2osm_roosevelt.sdot2osm_sw_raw
	WHERE 
	    (osm_id, sdot_objectid) NOT IN ( 
	        SELECT r1.osm_id,
	        CASE
	            WHEN ST_Distance(ST_LineInterpolatePoint(r1.osm_seg, 0.5), ST_LineInterpolatePoint(r1.sdot_geom, 0.5)) < ST_Distance(ST_LineInterpolatePoint(r2.osm_seg, 0.5), ST_LineInterpolatePoint(r2.sdot_geom, 0.5))
	                THEN (r2.sdot_objectid)
	            ELSE (r1.sdot_objectid)
	        END AS sdot_objectid
	        FROM jolie_sdot2osm_roosevelt.sdot2osm_sw_raw r1
	        JOIN (
	            SELECT *
	            FROM jolie_sdot2osm_roosevelt.sdot2osm_sw_raw
	            WHERE osm_id IN (
	                SELECT osm_id
	                FROM jolie_sdot2osm_roosevelt.sdot2osm_sw_raw
	                WHERE osm_seg IS NOT NULL
	                GROUP BY osm_id
	                HAVING count(*) > 1 ) ) r2
	        ON r1.osm_id = r2.osm_id AND r1.sdot_objectid < r2.sdot_objectid
	        WHERE ST_Length(ST_Intersection(ST_Buffer(r1.osm_seg, 1, 'endcap=flat join=round'), r2.osm_seg))/ST_Length(r1.osm_seg) > 0.8 OR
	              ST_Length(ST_Intersection(ST_Buffer(r1.osm_seg, 1, 'endcap=flat join=round'), r2.osm_seg))/ST_Length(r2.osm_seg) > 0.8
	        UNION ALL
	        SELECT 
	        CASE
	            WHEN ST_Distance(ST_LineInterpolatePoint(r1.osm_geom, 0.5), ST_LineInterpolatePoint(r1.sdot_seg, 0.5)) < ST_Distance(ST_LineInterpolatePoint(r2.osm_geom, 0.5), ST_LineInterpolatePoint(r2.sdot_seg, 0.5))
	                THEN (r2.osm_id)
	            ELSE (r1.osm_id)
	        END AS osm_id,
	        r1.sdot_objectid
	        FROM jolie_sdot2osm_roosevelt.sdot2osm_sw_raw r1
	        JOIN (
	            SELECT *
	            FROM jolie_sdot2osm_roosevelt.sdot2osm_sw_raw
	            WHERE sdot_objectid IN (
	                SELECT sdot_objectid
	                FROM jolie_sdot2osm_roosevelt.sdot2osm_sw_raw
	                WHERE sdot_seg IS NOT NULL
	                GROUP BY sdot_objectid
	                HAVING count(*) > 1 ) ) r2
	        ON r1.sdot_objectid = r2.sdot_objectid AND r1.osm_id < r2.osm_id
	        WHERE ST_Length(ST_Intersection(ST_Buffer(r1.sdot_seg, 1, 'endcap=flat join=round'), r2.sdot_seg))/ST_Length(r1.sdot_seg) > 0.8 OR
	              ST_Length(ST_Intersection(ST_Buffer(r1.sdot_seg, 1, 'endcap=flat join=round'), r2.sdot_seg))/ST_Length(r2.sdot_seg) > 0.8
	        UNION ALL 
	        SELECT osm_id, sdot_objectid 
			FROM jolie_sdot2osm_roosevelt.sdot2osm_sw_raw
			WHERE osm_id IN (
				SELECT r1.osm_id
				FROM jolie_sdot2osm_roosevelt.sdot2osm_sw_raw r1
				JOIN (
					SELECT osm_id
				 	FROM jolie_sdot2osm_roosevelt.sdot2osm_sw_raw
				 	GROUP BY osm_id
					HAVING COUNT(*) > 1) r2
			 	ON r1.osm_id = r2.osm_id
				WHERE r1.osm_seg IS NULL )
			    AND osm_seg IS NOT NULL 
	    );


-- case when the whole osm_geom already conflated, but the there is its sub-seg conflating to another sdot, and it looks weird
SELECT osm_id, sdot_objectid 
FROM jolie_sdot2osm_roosevelt.sdot2osm_sw_raw
WHERE osm_id IN (
	SELECT r1.osm_id
	FROM jolie_sdot2osm_roosevelt.sdot2osm_sw_raw r1
	JOIN (
		SELECT osm_id
	 	FROM jolie_sdot2osm_roosevelt.sdot2osm_sw_raw
	 	GROUP BY osm_id
		HAVING COUNT(*) > 1) r2
 	ON r1.osm_id = r2.osm_id
	WHERE r1.osm_seg IS NULL )
    AND osm_seg IS NOT NULL 


-- case: sdot > osm
SELECT *
FROM jolie_sdot2osm_roosevelt.sdot2osm_sw_raw
WHERE sdot_seg IS NOT NULL
	  AND (osm_id, sdot_objectid) NOT IN ( 
	  		SELECT 
			CASE
				WHEN ST_Distance(ST_LineInterpolatePoint(r1.osm_geom, 0.5), ST_LineInterpolatePoint(r1.sdot_seg, 0.5)) < ST_Distance(ST_LineInterpolatePoint(r2.osm_geom, 0.5), ST_LineInterpolatePoint(r2.sdot_seg, 0.5))
					THEN (r2.osm_id)
				ELSE (r1.osm_id)
			END AS osm_id,
			r1.sdot_objectid
			FROM jolie_sdot2osm_roosevelt.sdot2osm_sw_raw r1
			JOIN (
				SELECT *
				FROM jolie_sdot2osm_roosevelt.sdot2osm_sw_raw
				WHERE sdot_objectid IN (
					SELECT sdot_objectid
					FROM jolie_sdot2osm_roosevelt.sdot2osm_sw_raw
					WHERE sdot_seg IS NOT NULL
					GROUP BY sdot_objectid
					HAVING count(*) > 1 ) ) r2
			ON r1.sdot_objectid = r2.sdot_objectid AND r1.osm_id < r2.osm_id
			WHERE ST_Length(ST_Intersection(ST_Buffer(r1.sdot_seg, 1, 'endcap=flat join=round'), r2.sdot_seg))/ST_Length(r1.sdot_seg) > 0.8 OR
				  ST_Length(ST_Intersection(ST_Buffer(r1.sdot_seg, 1, 'endcap=flat join=round'), r2.sdot_seg))/ST_Length(r2.sdot_seg) > 0.8
	  )
	  	  

-- FINAL TABLE that will be exported
CREATE TABLE jolie_sdot2osm_roosevelt.sidewalk_json AS
	SELECT sdot2osm.osm_id, sdot2osm.sdot_osm_id, osm.highway, osm.surface, sdot2osm.sdot_surface, CAST(sdot2osm.width AS TEXT), osm.tags||sdot2osm.hstore AS tags, sdot2osm.way, osm.geom AS parent_way
	FROM jolie_sdot2osm_roosevelt.sidewalk sdot2osm
	JOIN jolie_sdot2osm_roosevelt.osm_sidewalk osm
	ON sdot2osm.osm_id = osm.osm_id
	UNION  
	SELECT osm_id, NULL AS "sdot_osm_id", highway, surface, NULL AS "sdot_surface", width, tags, geom AS "way", geom AS parent_way
	FROM jolie_sdot2osm_roosevelt.osm_sidewalk
	WHERE osm_id NOT IN (
			SELECT DISTINCT osm_id
			FROM jolie_sdot2osm_roosevelt.sidewalk
		)
	  

----------------------------------------------------
/*                 CROSSING DATA                  */
----------------------------------------------------

SELECT * FROM jolie_sdot2osm_roosevelt.osm_crossing

CREATE TABLE jolie_sdot2osm_roosevelt.sdot_accpedsig AS
	SELECT *
	FROM sdot.accessible_pedestrian_signals aps
	WHERE  wkb_geometry && st_setsrid( st_makebox2d( st_makepoint(-13616596,6053033), st_makepoint(-13615615,6053724)), 3857); -- 4

ALTER TABLE jolie_sdot2osm_roosevelt.sdot_accpedsig RENAME COLUMN wkb_geometry TO geom;
	

-- test and see which buffer size works
SELECT osm.*, sdot.geom
FROM jolie_sdot2osm_roosevelt.osm_crossing osm 
JOIN jolie_sdot2osm_roosevelt.sdot_accpedsig sdot
ON ST_Intersects(osm.geom, ST_Buffer(sdot.geom, 20))


-- FINAL TABLE
CREATE TABLE jolie_sdot2osm_roosevelt.crossing_json AS 
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
		FROM jolie_sdot2osm_roosevelt.osm_crossing osm 
		JOIN jolie_sdot2osm_roosevelt.sdot_accpedsig sdot
		ON ST_Intersects(osm.geom, ST_Buffer(sdot.geom, 20))
		) osm
	UNION
	SELECT osm.osm_id, osm.highway, osm.tags, osm.geom AS way
	FROM jolie_sdot2osm_roosevelt.osm_crossing osm
	WHERE osm.osm_id NOT IN (
		SELECT osm.osm_id
		FROM jolie_sdot2osm_roosevelt.osm_crossing osm 
		JOIN jolie_sdot2osm_roosevelt.sdot_accpedsig sdot
		ON ST_Intersects(osm.geom, ST_Buffer(sdot.geom, 20)))