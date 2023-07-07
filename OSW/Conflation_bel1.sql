--------------------------------------------
		/** BOUNDING BOX **/
--------------------------------------------

---------- OSM ------------

-- highway = footway, footway = sidewalk
CREATE TABLE jolie_bel1.osm_sw AS (
	SELECT *
	FROM planet_osm_line
	WHERE	highway = 'footway' AND
			tags -> 'footway' = 'sidewalk' AND 
			way && st_setsrid( st_makebox2d( st_makepoint(-13603442,6043723), st_makepoint(-13602226,6044848)), 3857) ); -- 255

ALTER TABLE jolie_bel1.osm_sw RENAME COLUMN way TO geom;



-- points
CREATE table jolie_bel1.osm_point AS (
	SELECT *
	FROM planet_osm_point
	WHERE
			way && st_setsrid( st_makebox2d( st_makepoint(-13603442,6043723), st_makepoint(-13602226,6044848)), 3857) ); -- 719

ALTER TABLE jolie_bel1.osm_point RENAME COLUMN way TO geom;

-- highway = footway, footway = crossing
CREATE TABLE jolie_bel1.osm_crossing AS (
	SELECT *
	FROM planet_osm_line
	WHERE   highway = 'footway' AND 
			tags -> 'footway' = 'crossing' AND 
			way && st_setsrid( st_makebox2d( st_makepoint(-13603442,6043723), st_makepoint(-13602226,6044848)), 3857) ); -- 114

ALTER TABLE jolie_bel1.osm_crossing RENAME COLUMN way TO geom;


-- highway = footway, footway IS NULL OR footway not sidewalk/crossing
CREATE TABLE jolie_bel1.osm_footway_null AS (
	SELECT *
	FROM planet_osm_line
	WHERE 	highway = 'footway' AND 
			(tags -> 'footway' IS NULL OR 
			tags -> 'footway' NOT IN ('sidewalk', 'crossing'))  AND
			way && st_setsrid( st_makebox2d( st_makepoint(-13603442,6043723), st_makepoint(-13602226,6044848)), 3857)  ); -- 270
		
ALTER TABLE jolie_bel1.osm_footway_null RENAME COLUMN way TO geom;


--------- ARNOLD in bellevue ----------
CREATE TABLE jolie_bel1.arnold_roads AS (
	SELECT *
	FROM arnold.wapr_linestring 
	WHERE geom && st_setsrid( st_makebox2d( st_makepoint(-13603442,6043723), st_makepoint(-13602226,6044848)), 3857)
	ORDER BY routeid, beginmeasure, endmeasure); -- 41

-- Create a geom index
CREATE INDEX sw_geom ON jolie_bel1.osm_sw USING GIST (geom);
CREATE INDEX crossing_geom ON jolie_bel1.osm_crossing USING GIST (geom);
CREATE INDEX point_geom ON jolie_bel1.osm_point USING GIST (geom);
CREATE INDEX footway_null_geom ON jolie_bel1.osm_footway_null USING GIST (geom);
CREATE INDEX arnold_roads_geom ON jolie_bel1.arnold_roads USING GIST (geom);


--------------------------------------------
			/* CONFLATION */
--------------------------------------------


---- STEP 1: Dealing with crossing
	-- assumption: all of the crossing are referred to as footway=crossing

-- check point: see how many crossing are there 
SELECT DISTINCT crossing.osm_id, crossing.geom
FROM jolie_bel1.osm_crossing crossing -- 114

CREATE TABLE jolie_conflation_bel1.crossing (osm_id, arnold_objectid, osm_geom) AS
	SELECT crossing.osm_id AS osm_id, road.og_objectid AS arnold_objectid, crossing.geom AS osm_geom
	FROM jolie_bel1.osm_crossing crossing
	JOIN jolie_bel1.arnold_roads road
	ON ST_Intersects(crossing.geom, road.geom) -- 55 crossing have road associated TO it

---- STEP 2: Dealing with entrances
	-- assumption: entrances are small footway=sidewalk segments that intersect with a point that have a tag of entrance=*
	
CREATE TABLE jolie_conflation_bel1.entrances AS
	SELECT entrance.osm_id, entrance.geom AS osm_geom
	FROM jolie_bel1.osm_point point
	JOIN jolie_bel1.osm_sw entrance
	ON ST_intersects(entrance.geom, point.geom)
	WHERE point.tags -> 'entrance' IS NOT NULL 			


	
---- STEP 3: Dealing with connecting link
	-- assumption 1: a link connects the sidewalk to the crossing
	-- note: a link might or might not have a footway='sidewalk' tag

	
CREATE TABLE jolie_conflation_bel1.connlink (
	osm_id INT8,
	road_num INT4,
	arnold_objectid INT8,
	osm_geom GEOMETRY(LineString, 3857)
)


-- STEP 3.1: Deal with links (footway = sidewalk) that are connected to crossing and less than 12 meters

-- check point: segments (footway=sidewalk) intersects crossing (conlfated)
SELECT crossing.osm_id AS cross_id, sw.geom AS link_geom, crossing.osm_geom AS cross_geom, sw.osm_id AS link_id
FROM jolie_conflation_bel1.crossing crossing
JOIN jolie_bel1.osm_sw sw ON ST_Intersects(crossing.osm_geom, sw.geom)
WHERE ST_Length(sw.geom) < 12

INSERT INTO jolie_conflation_bel1.connlink (osm_id, road_num, arnold_objectid, osm_geom)
	SELECT link.osm_id AS osm_id, ROW_NUMBER() OVER (PARTITION BY link.osm_id ORDER BY crossing.arnold_objectid) AS road_num, crossing.arnold_objectid AS arnold_objectid, link.geom AS osm_geom
    FROM jolie_conflation_bel1.crossing crossing
    JOIN jolie_bel1.osm_sw link
    ON ST_Intersects(crossing.osm_geom, st_startpoint(link.geom)) OR ST_Intersects(crossing.osm_geom, st_endpoint(link.geom))
    WHERE ST_length(link.geom) < 12


-- STEP 3.2: deal with link that are not tagged as sidewalk/crossing

-- check point: how highway=footway and footway IS NULL vs crossing (conflated) are connected?
SELECT link.osm_id AS link_id, crossing.osm_id AS cross_id, crossing.arnold_objectid, crossing.osm_geom AS cross_geom, link.geom AS link_geom
FROM jolie_bel1.osm_footway_null link
JOIN jolie_conflation_bel1.crossing crossing
ON ST_Intersects(link.geom, crossing.osm_geom)
WHERE ST_Length(link.geom) < 12


INSERT INTO jolie_conflation_bel1.connlink (osm_id, road_num, arnold_objectid, osm_geom)
	SELECT link.osm_id AS link_id, ROW_NUMBER() OVER (PARTITION BY link.osm_id ORDER BY crossing.arnold_objectid) AS road_num, crossing.arnold_objectid AS arnold_objectid, link.geom AS link_geom
		FROM jolie_bel1.osm_footway_null link
		JOIN jolie_conflation_bel1.crossing crossing
		ON ST_Intersects(link.geom, crossing.osm_geom)  
		WHERE ST_Length(link.geom) < 12
		ORDER BY link.osm_id; -- 86


SELECT DISTINCT osm_id
FROM jolie_conflation_bel1.connlink -- DISTINCT 80


---- STEP 3.3: Give a table that include all connlink regardless of it conflated to the road or not
SELECT link.osm_id AS link_osm_id, ROW_NUMBER() OVER (PARTITION BY link.osm_id ORDER BY crossing.osm_id) AS road_num, crossing.osm_id AS cross_osm_id, link.geom AS link_geom, crossing.geom AS cross_geom
FROM jolie_bel1.osm_crossing crossing
JOIN jolie_bel1.osm_sw link ON ST_Intersects(crossing.geom, link.geom)
WHERE ST_Length(link.geom) < 12
ORDER BY link.osm_id --43

SELECT link.osm_id AS link_osm_id, ROW_NUMBER() OVER (PARTITION BY link.osm_id ORDER BY crossing.osm_id) AS road_num, crossing.osm_id AS cross_osm_id, link.geom AS link_geom, crossing.geom AS cross_geom
FROM jolie_bel1.osm_crossing crossing
JOIN jolie_bel1.osm_footway_null link ON ST_Intersects(crossing.geom, link.geom)
WHERE ST_Length(link.geom) < 12
ORDER BY link.osm_id -- 103

CREATE TABLE jolie_bel1.osm_sw_connlink AS (
	SELECT DISTINCT link.osm_id AS link_osm_id, link.geom AS link_geom
	FROM jolie_bel1.osm_crossing crossing
	JOIN jolie_bel1.osm_sw link ON ST_Intersects(crossing.geom, link.geom)
	WHERE ST_Length(link.geom) < 12 ) -- 41

CREATE TABLE jolie_bel1.osm_footway_null_connlink AS (
	SELECT DISTINCT link.osm_id AS link_osm_id, link.geom AS link_geom
	FROM jolie_bel1.osm_crossing crossing
	JOIN jolie_bel1.osm_footway_null link ON ST_Intersects(crossing.geom, link.geom)
	WHERE ST_Length(link.geom) < 12 ) -- 93


---- STEP 4: deal with general case of sidewalk

-- In this code, we filter:
-- 1. the road buffer and the sidewalk buffer overlap
-- 2. the road and the sidewalk are parallel to each other (between 0-30 or 165/195 or 330-360 degree)
-- 3. in case where the sidewalk.geom looking at more than 2 road.geom at the same time, we need to choose the one that have the closest distance
--    from the midpoint of the sidewalk to the midpoint of the road
-- 4. Ignore those roads that are already entrance, connlink table

CREATE TABLE jolie_conflation_bel1.sidewalk AS
WITH ranked_roads AS (
	SELECT
	  sidewalk.osm_id AS osm_id,
	  big_road.og_objectid AS arnold_objectid,
	  sidewalk.geom AS osm_geom,
	  ST_LineSubstring( big_road.geom, LEAST(ST_LineLocatePoint(big_road.geom, ST_ClosestPoint(st_startpoint(sidewalk.geom), big_road.geom)) , ST_LineLocatePoint(big_road.geom, ST_ClosestPoint(st_endpoint(sidewalk.geom), big_road.geom))), GREATEST(ST_LineLocatePoint(big_road.geom, ST_ClosestPoint(st_startpoint(sidewalk.geom), big_road.geom)) , ST_LineLocatePoint(big_road.geom, ST_ClosestPoint(st_endpoint(sidewalk.geom), big_road.geom))) ) AS seg_geom,
	  -- calculate the coverage of sidewalk within the buffer of the road
	  ST_Length(ST_Intersection(sidewalk.geom, ST_Buffer(ST_LineSubstring( big_road.geom, LEAST(ST_LineLocatePoint(big_road.geom, ST_ClosestPoint(st_endpoint(sidewalk.geom), big_road.geom))), GREATEST(ST_LineLocatePoint(big_road.geom, ST_ClosestPoint(st_endpoint(sidewalk.geom), big_road.geom))) ), 18))) / ST_Length(sidewalk.geom) AS sidewalk_coverage_bigroad,
	  -- rank this based on the distance of the midpoint of the sidewalk to the midpoint of the road
	  ROW_NUMBER() OVER (
	  	PARTITION BY sidewalk.geom
	  	ORDER BY ST_distance( 
	  				ST_LineSubstring( big_road.geom,
	  								  LEAST(ST_LineLocatePoint(big_road.geom, ST_ClosestPoint(st_startpoint(sidewalk.geom), big_road.geom)) , ST_LineLocatePoint(big_road.geom, ST_ClosestPoint(st_endpoint(sidewalk.geom), big_road.geom))),
	  								  GREATEST(ST_LineLocatePoint(big_road.geom, ST_ClosestPoint(st_startpoint(sidewalk.geom), big_road.geom)) , ST_LineLocatePoint(big_road.geom, ST_ClosestPoint(st_endpoint(sidewalk.geom), big_road.geom))) ),
	  				sidewalk.geom )
	  	) AS RANK
	FROM jolie_bel1.osm_sw sidewalk
	JOIN jolie_bel1.arnold_roads big_road ON ST_Intersects(ST_Buffer(sidewalk.geom, 5), ST_Buffer(big_road.geom, 18))
	WHERE 
	  (  ABS(DEGREES(ST_Angle(ST_LineSubstring( big_road.geom, LEAST(ST_LineLocatePoint(big_road.geom, ST_ClosestPoint(st_startpoint(sidewalk.geom), big_road.geom)) , ST_LineLocatePoint(big_road.geom, ST_ClosestPoint(st_endpoint(sidewalk.geom), big_road.geom))), GREATEST(ST_LineLocatePoint(big_road.geom, ST_ClosestPoint(st_startpoint(sidewalk.geom), big_road.geom)) , ST_LineLocatePoint(big_road.geom, ST_ClosestPoint(st_endpoint(sidewalk.geom), big_road.geom))) ), sidewalk.geom))) BETWEEN 0 AND 10 -- 0 
		 OR ABS(DEGREES(ST_Angle(ST_LineSubstring( big_road.geom, LEAST(ST_LineLocatePoint(big_road.geom, ST_ClosestPoint(st_startpoint(sidewalk.geom), big_road.geom)) , ST_LineLocatePoint(big_road.geom, ST_ClosestPoint(st_endpoint(sidewalk.geom), big_road.geom))), GREATEST(ST_LineLocatePoint(big_road.geom, ST_ClosestPoint(st_startpoint(sidewalk.geom), big_road.geom)) , ST_LineLocatePoint(big_road.geom, ST_ClosestPoint(st_endpoint(sidewalk.geom), big_road.geom))) ), sidewalk.geom))) BETWEEN 170 AND 190 -- 180
		 OR ABS(DEGREES(ST_Angle(ST_LineSubstring( big_road.geom, LEAST(ST_LineLocatePoint(big_road.geom, ST_ClosestPoint(st_startpoint(sidewalk.geom), big_road.geom)) , ST_LineLocatePoint(big_road.geom, ST_ClosestPoint(st_endpoint(sidewalk.geom), big_road.geom))), GREATEST(ST_LineLocatePoint(big_road.geom, ST_ClosestPoint(st_startpoint(sidewalk.geom), big_road.geom)) , ST_LineLocatePoint(big_road.geom, ST_ClosestPoint(st_endpoint(sidewalk.geom), big_road.geom))) ), sidewalk.geom))) BETWEEN 350 AND 360 ) -- 360
    )
SELECT
	  osm_id,
	  arnold_objectid,
	  osm_geom,
	  seg_geom AS arnold_geom
FROM
	  ranked_roads
WHERE
	  rank = 1
	  AND ( osm_id NOT IN (
 				SELECT link.osm_id FROM jolie_conflation_bel1.connlink link 
			    UNION ALL
			    SELECT entrance.osm_id FROM jolie_conflation_bel1.entrances entrance)	
 	      ); -- 182
	 

CREATE INDEX sidwalk_sidwalk_geom ON jolie_conflation_bel1.sidewalk USING GIST (osm_geom);
CREATE INDEX sidwalk_arnold_geom ON jolie_conflation_bel1.sidewalk USING GIST (arnold_geom);
	


---- STEP 5: Dealing with edges
	-- assumption: edge will have it start and end point connectected to sidewalk. We will use the sidewalk table to identify our sidewalk edges
CREATE TABLE jolie_conflation_bel1.sw_edges (
	osm_id INT8,
	arnold_objectid1 INT8,
	arnold_objectid2 INT8,
	osm_geom GEOMETRY(LineString, 3857) )


INSERT INTO jolie_conflation_bel1.sw_edges (osm_id, arnold_objectid1, arnold_objectid2, osm_geom)
	SELECT  edge.osm_id AS osm_id,
			centerline1.arnold_objectid AS arnold_objectid1,
			centerline1.arnold_objectid AS arnold_objectid2,
			edge.geom AS osm_geom
	FROM jolie_bel1.osm_sw edge
	JOIN jolie_conflation_bel1.sidewalk centerline1 ON st_intersects(st_startpoint(edge.geom), centerline1.osm_geom)
	JOIN jolie_conflation_bel1.sidewalk centerline2 ON st_intersects(st_endpoint(edge.geom), centerline2.osm_geom)
	WHERE   edge.geom NOT IN (
				SELECT sw.osm_geom FROM jolie_conflation_bel1.sidewalk sw
				UNION ALL 
				SELECT link.osm_geom FROM jolie_conflation_bel1.connlink link
				UNION ALL 
				SELECT entrance.osm_geom FROM jolie_conflation_bel1.entrances entrance)
			AND ST_Equals(centerline1.osm_geom, centerline2.osm_geom) IS FALSE
			AND centerline1.arnold_objectid != centerline2.arnold_objectid -- 19
			
			



 
 
-- checkpoint: see what is there in conflation tables
WITH conf_table AS (
		SELECT CAST(sidewalk.osm_id AS varchar(75)) AS id, sidewalk.osm_geom, 'sidewalk' AS label FROM jolie_conflation_bel1.sidewalk sidewalk
	    UNION ALL
	    SELECT CAST(link.osm_id AS varchar(75)) AS id, link.osm_geom, 'link' AS label FROM jolie_conflation_bel1.connlink link 
	    UNION ALL
	    SELECT CAST(crossing.osm_id AS varchar(75)) AS id, crossing.osm_geom, 'crossing' AS label FROM jolie_conflation_bel1.crossing crossing
	    UNION ALL
	    SELECT CAST(edge.osm_id AS varchar(75)) AS id, edge.osm_geom, 'edge' AS label FROM jolie_conflation_bel1.sw_edges edge
	    UNION ALL
	    SELECT CAST(entrance.osm_id AS varchar(75)) AS id, entrance.osm_geom, 'entrance' AS label FROM jolie_conflation_bel1.entrances entrance
	    )
SELECT CAST(sw.osm_id AS varchar(75)) AS id, sw.geom, 'not conflated' AS label
FROM jolie_bel1.osm_sw sw
LEFT JOIN conf_table ON sw.geom = conf_table.osm_geom
WHERE conf_table.osm_geom IS NULL



----- STEP 4: Handle weird case:

-- create a table of weird cases
CREATE TABLE jolie_bel1.weird_case AS
	WITH conf_table AS (
			SELECT CAST(sidewalk.osm_id AS varchar(75)) AS id, sidewalk.osm_geom, 'sidewalk' AS label FROM jolie_conflation_bel1.sidewalk sidewalk
		    UNION ALL
		    SELECT CAST(link.osm_id AS varchar(75)) AS id, link.osm_geom, 'link' AS label FROM jolie_conflation_bel1.connlink link 
		    UNION ALL
		    SELECT CAST(crossing.osm_id AS varchar(75)) AS id, crossing.osm_geom, 'crossing' AS label FROM jolie_conflation_bel1.crossing crossing
		    UNION ALL
		    SELECT CAST(edge.osm_id AS varchar(75)) AS id, edge.osm_geom, 'edge' AS label FROM jolie_conflation_bel1.sw_edges edge
		    UNION ALL
	    	SELECT CAST(entrance.osm_id AS varchar(75)) AS id, entrance.osm_geom, 'entrance' AS label FROM jolie_conflation_bel1.entrances entrance
		    )
	SELECT sw.osm_id, sw.tags, sw.geom
	FROM jolie_bel1.osm_sw sw
	LEFT JOIN conf_table ON sw.geom = conf_table.osm_geom
	WHERE conf_table.osm_geom IS NULL

-- Split the weird case geom by the vertex
CREATE TABLE jolie_bel1.weird_case_seg AS
	WITH vertices AS (   
	  SELECT osm_id, (ST_DumpPoints(geom)).geom AS geom
	  FROM jolie_bel1.weird_case  )  
	SELECT a.osm_id, a.tags, (ST_Dump(ST_Split(a.geom, ST_Collect(b.geom)))).geom::geometry(LineString, 3857) AS geom
	FROM jolie_bel1.weird_case a
	JOIN vertices b ON a.osm_id = b.osm_id
	GROUP BY a.osm_id, a.tags, a.geom
	ORDER BY a.osm_id, a.geom;


WITH ranked_roads AS (
	SELECT
	  sidewalk.osm_id AS osm_id,
	  big_road.routeid AS arnold_routeid,
	  big_road.beginmeasure AS arnold_beginmeasure,
	  big_road.endmeasure AS arnold_endmeasure,
	  sidewalk.geom AS osm_geom,
	  ST_LineSubstring( big_road.geom, LEAST(ST_LineLocatePoint(big_road.geom, ST_ClosestPoint(st_startpoint(sidewalk.geom), big_road.geom)) , ST_LineLocatePoint(big_road.geom, ST_ClosestPoint(st_endpoint(sidewalk.geom), big_road.geom))), GREATEST(ST_LineLocatePoint(big_road.geom, ST_ClosestPoint(st_startpoint(sidewalk.geom), big_road.geom)) , ST_LineLocatePoint(big_road.geom, ST_ClosestPoint(st_endpoint(sidewalk.geom), big_road.geom))) ) AS seg_geom,
	  -- calculate the coverage of sidewalk within the buffer of the road
	  ST_Length(ST_Intersection(sidewalk.geom, ST_Buffer(ST_LineSubstring( big_road.geom, LEAST(ST_LineLocatePoint(big_road.geom, ST_ClosestPoint(st_endpoint(sidewalk.geom), big_road.geom))), GREATEST(ST_LineLocatePoint(big_road.geom, ST_ClosestPoint(st_endpoint(sidewalk.geom), big_road.geom))) ), 18))) / ST_Length(sidewalk.geom) AS sidewalk_coverage_bigroad,
	  -- rank this based on the distance of the midpoint of the sidewalk to the midpoint of the road
	  ROW_NUMBER() OVER (
	  	PARTITION BY sidewalk.geom
	  	ORDER BY ST_distance( 
	  				ST_LineSubstring( big_road.geom,
	  								  LEAST(ST_LineLocatePoint(big_road.geom, ST_ClosestPoint(st_startpoint(sidewalk.geom), big_road.geom)) , ST_LineLocatePoint(big_road.geom, ST_ClosestPoint(st_endpoint(sidewalk.geom), big_road.geom))),
	  								  GREATEST(ST_LineLocatePoint(big_road.geom, ST_ClosestPoint(st_startpoint(sidewalk.geom), big_road.geom)) , ST_LineLocatePoint(big_road.geom, ST_ClosestPoint(st_endpoint(sidewalk.geom), big_road.geom))) ),
	  				sidewalk.geom )
	  	) AS RANK
	FROM jolie_bel1.weird_case_seg sidewalk
	JOIN jolie_bel1.arnold_roads big_road ON ST_Intersects(ST_Buffer(sidewalk.geom, 5), ST_Buffer(big_road.geom, 18))
	WHERE 
	  (ABS(DEGREES(ST_Angle(ST_LineSubstring( big_road.geom, LEAST(ST_LineLocatePoint(big_road.geom, ST_ClosestPoint(st_startpoint(sidewalk.geom), big_road.geom)) , ST_LineLocatePoint(big_road.geom, ST_ClosestPoint(st_endpoint(sidewalk.geom), big_road.geom))), GREATEST(ST_LineLocatePoint(big_road.geom, ST_ClosestPoint(st_startpoint(sidewalk.geom), big_road.geom)) , ST_LineLocatePoint(big_road.geom, ST_ClosestPoint(st_endpoint(sidewalk.geom), big_road.geom))) ), sidewalk.geom))) BETWEEN 0 AND 10 -- 0 
		 OR ABS(DEGREES(ST_Angle(ST_LineSubstring( big_road.geom, LEAST(ST_LineLocatePoint(big_road.geom, ST_ClosestPoint(st_startpoint(sidewalk.geom), big_road.geom)) , ST_LineLocatePoint(big_road.geom, ST_ClosestPoint(st_endpoint(sidewalk.geom), big_road.geom))), GREATEST(ST_LineLocatePoint(big_road.geom, ST_ClosestPoint(st_startpoint(sidewalk.geom), big_road.geom)) , ST_LineLocatePoint(big_road.geom, ST_ClosestPoint(st_endpoint(sidewalk.geom), big_road.geom))) ), sidewalk.geom))) BETWEEN 170 AND 190 -- 180
		 OR ABS(DEGREES(ST_Angle(ST_LineSubstring( big_road.geom, LEAST(ST_LineLocatePoint(big_road.geom, ST_ClosestPoint(st_startpoint(sidewalk.geom), big_road.geom)) , ST_LineLocatePoint(big_road.geom, ST_ClosestPoint(st_endpoint(sidewalk.geom), big_road.geom))), GREATEST(ST_LineLocatePoint(big_road.geom, ST_ClosestPoint(st_startpoint(sidewalk.geom), big_road.geom)) , ST_LineLocatePoint(big_road.geom, ST_ClosestPoint(st_endpoint(sidewalk.geom), big_road.geom))) ), sidewalk.geom))) BETWEEN 350 AND 360 ) -- 360
 		)
SELECT DISTINCT
	  osm_id,
	  arnold_routeid,
	  arnold_beginmeasure,
	  arnold_endmeasure,
	  osm_geom,
	  seg_geom AS arnold_geom
FROM
	  ranked_roads
WHERE
	  rank = 1;



-- conflate into sidewalk if the segment is parallel tp the sw, and have it end/start point intersect with another end/start point of the sidewalk
-- and also the sum of the segment and the sidewalk should be less than the length of the road that the sidewalk correspond to

INSERT INTO jolie_conflation_bel1.sidewalk(osm_id, arnold_objectid, osm_geom, arnold_geom)
SELECT DISTINCT osm_sw.osm_id, sidewalk.arnold_objectid, osm_sw.geom AS osm_geom, sidewalk.arnold_geom
FROM jolie_bel1.osm_sw
JOIN jolie_conflation_bel1.sidewalk
ON 	ST_Intersects(st_startpoint(sidewalk.osm_geom), st_startpoint(osm_sw.geom))
	OR ST_Intersects(st_startpoint(sidewalk.osm_geom), st_endpoint(osm_sw.geom))
	OR ST_Intersects(st_endpoint(sidewalk.osm_geom), st_startpoint(osm_sw.geom))
	OR ST_Intersects(st_endpoint(sidewalk.osm_geom), st_endpoint(osm_sw.geom))
WHERE osm_sw.geom NOT IN (
		SELECT sidewalk.osm_geom FROM jolie_conflation_bel1.sidewalk sidewalk
	    UNION ALL
	    SELECT link.osm_geom FROM jolie_conflation_bel1.connlink link 
	    UNION ALL
	    SELECT crossing.osm_geom FROM jolie_conflation_bel1.crossing crossing
	    UNION ALL
	    SELECT edge.osm_geom FROM jolie_conflation_bel1.sw_edges edge )
	  AND ( -- specify that the segment should be PARALLEL TO our conflated sidewalk
			ABS(DEGREES(ST_Angle(sidewalk.osm_geom, osm_sw.geom))) BETWEEN 0 AND 10 -- 0 
		    OR ABS(DEGREES(ST_Angle(sidewalk.osm_geom, osm_sw.geom))) BETWEEN 170 AND 190 -- 180
		    OR ABS(DEGREES(ST_Angle(sidewalk.osm_geom, osm_sw.geom))) BETWEEN 350 AND 360  ) -- 360  
	  AND (ST_Length(osm_sw.geom) + ST_Length(sidewalk.osm_geom) ) < ST_Length(sidewalk.arnold_geom)




-- LIMITATION: defined number and buffer cannot accurately represent all the sidewalk scenarios
	-- TODO: buffer size when we look at how many lanes there are --> better size of buffering

