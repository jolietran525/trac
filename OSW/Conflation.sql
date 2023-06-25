--------------------------------------------
/** BOUNDING BOX **/
-------------------------------------
---------- OSM in u-district ------------
CREATE TABLE osm_sidewalk_udistrict AS (-- ONLY footway = sidewalk
	SELECT *
	FROM planet_osm_line
	WHERE 	highway = 'footway' AND 
			tags -> 'footway' = 'sidewalk' AND 
			way && st_setsrid( st_makebox2d( st_makepoint(-13616401,6049782), st_makepoint(-13615688,6050649)), 3857) );

-- SMALLER bbox in u-district for easier testing purpose
CREATE table osm_sidewalk_udistrict1 AS (-- ONLY footway = sidewalk
	SELECT *
	FROM planet_osm_line
	WHERE	highway = 'footway' AND
			tags -> 'footway' = 'sidewalk' AND 
			way && st_setsrid( st_makebox2d( st_makepoint(-13616323, 6049894), st_makepoint(-13615733, 6050671) ), 3857) );

ALTER TABLE osm_sidewalk_udistrict1 RENAME COLUMN way TO geom;



-- points in u-district
CREATE table osm_point_udistrict1 AS (
	SELECT *
	FROM planet_osm_point
	WHERE
			way && st_setsrid( st_makebox2d( st_makepoint(-13616323, 6049894), st_makepoint(-13615733, 6050671) ), 3857) );

ALTER TABLE osm_point_udistrict1 RENAME COLUMN way TO geom;

-- crossing in u-district
CREATE TABLE osm_crossing_udistrict1 AS (
	SELECT *
	FROM planet_osm_line
	WHERE   highway = 'footway' AND 
			tags -> 'footway' = 'crossing' AND 
			way && st_setsrid( st_makebox2d( st_makepoint(-13616323, 6049894), st_makepoint(-13615733, 6050671) ), 3857) );

ALTER TABLE osm_crossing_udistrict1 RENAME COLUMN way TO geom;


-- only highway = footway null
CREATE TABLE osm_footway_null_udistrict1 AS (-- ONLY highway = footway, footway IS NULL
	SELECT *
	FROM planet_osm_line
	WHERE 	highway = 'footway' AND 
			tags -> 'footway' IS NULL AND
			way && st_setsrid( st_makebox2d( st_makepoint(-13616323, 6049894), st_makepoint(-13615733, 6050671) ), 3857)  );
		
ALTER TABLE osm_footway_null_udistrict1 RENAME COLUMN way TO geom;
	

--------- ARNOLD in u-district ----------
CREATE TABLE  arnold.wapr_udistrict AS (
	SELECT  *
	FROM arnold.wapr_linestring 
	WHERE geom && st_setsrid( st_makebox2d( st_makepoint(-13616401,6049782), st_makepoint(-13615688,6050649)), 3857));

-- SMALLER bbox in u-district for easier testing purpose
CREATE TABLE arnold.wapr_udistrict1 AS (
	SELECT *
	FROM arnold.wapr_linestring 
	WHERE geom && st_setsrid( st_makebox2d( st_makepoint(-13616323, 6049894), st_makepoint(-13615733, 6050671)), 3857)
	ORDER BY objectid, routeid);



--------------------------------------------
/* CONFLATION */
--------------------------------------------

--------- STEP 1: break down the main road whenever it intersects with another main road ---------

-- This code creates a new table named segment_test by performing the following steps:
	-- Define intersection_points table which finds distinct intersection points between different geometries in the arnold.wapr_udistrict1 table.
	-- Performs a select query that joins the arnold.wapr_udistrict table (a) with the intersection_points CTE (b) using object IDs and route IDs. It collects all the intersection geometries (ST_collect(b.geom)) for each object ID and route ID.
	-- Finally, it splits the geometries in a.geom using the collected intersection geometries (ST_Split(a.geom, ST_collect(b.geom))). The result is a set of individual linestrings obtained by splitting the original geometries.
	-- The resulting linestrings are grouped by object ID, route ID, and original geometry (a.objectid, a.routeid, a.geom) and inserted into the arnold.segment_test table.
CREATE TABLE arnold.segment_test AS
	WITH intersection_points AS (
	  SELECT DISTINCT m1.objectid oi1, m1.routeid ri1, ST_Intersection(m1.geom, m2.geom) AS geom
	  FROM arnold.wapr_udistrict1 m1
	  JOIN arnold.wapr_udistrict1 m2 ON ST_Intersects(m1.geom, m2.geom) AND m1.objectid <> m2.objectid )
	SELECT
	  a.objectid, a.routeid, ST_collect(b.geom), ST_Split(a.geom, ST_collect(b.geom))
	FROM
	  arnold.wapr_udistrict1 AS a
	JOIN
	  intersection_points AS b ON a.objectid = b.oi1 AND a.routeid = b.ri1
	GROUP BY
	  a.objectid,
	  a.routeid,
	  a.geom;

-- create a table that pull the data from the segment_test table, convert it into linestring instead leaving it as a collection
CREATE TABLE arnold.segment_test_line AS
	SELECT objectid, routeid, (ST_Dump(st_split)).geom::geometry(LineString, 3857) AS geom
	FROM arnold.segment_test;

-- Create a geom index for segment_test_line and osm_sidewalk_udistrict1
CREATE INDEX segment_test_line_geom ON arnold.segment_test_line USING GIST (geom);
CREATE INDEX osm_sidewalk_udistrict1_geom ON osm_sidewalk_udistrict1 USING GIST (geom);

--------- STEP 2: identify matching criteria ---------
-- since the arnold and the OSM datasets don't have any common attributes or identifiers, and their content represents
-- different aspects of the street network (sidewalk vs main roads), we are going to rely on the geomtry properties and
-- spatial relationships to find potential matches. So, we want:
-- 1. buffering
-- 2. intersection with buffer of the road segment
-- 3. parallel

-- check point 2.1: how many sidewalks are there
SELECT sidewalk.*
FROM osm_sidewalk_udistrict1 sidewalk; -- there ARE 107 sidewalks

-- check point 2.2: how many road segments are there
SELECT *
FROM arnold.segment_test_line;

-- In this code, we filter:
-- 1. the road buffer and the sidewalk buffer overlap
-- 2. the road and the sidewalk are parallel to each other (between 0-30 or 165/195 or 330-360 degree)
-- 3. in case where the sidewalk.geom looking at more than 2 road.geom at the same time, we need to choose the one that have the closest distance
--    from the midpoint of the sidewalk to the midpoint of the road
-- 4. Ignore those roads that are smaller than 10 meters
-- This long_parallel table only contain 75 sidewalk segments that are greater 10 meters and parallel to the road. This is pretty solid.
CREATE TABLE conflation.long_parallel AS
	WITH ranked_roads AS (
	  SELECT
	    sidewalk.osm_id AS sidewalk_id,
	    road.objectid AS road_id,
	    road.routeid AS road_routeid,
	  	sidewalk.geom AS sidewalk_geom,
	    road.geom AS road_geom,
	    ABS(DEGREES(ST_Angle(road.geom, sidewalk.geom))) AS angle_degrees,
	    ST_Distance(ST_LineInterpolatePoint(road.geom, 0.5), ST_LineInterpolatePoint(sidewalk.geom, 0.5)) AS midpoints_distance,
	    ST_length(sidewalk.geom) AS sidewalk_length,
	    sidewalk.tags AS tags,
	    -- rank this based on the distance of the midpoint of the sidewalk to the midpoint of the road
	    ROW_NUMBER() OVER (PARTITION BY sidewalk.geom ORDER BY ST_Distance(ST_LineInterpolatePoint(road.geom, 0.5), ST_LineInterpolatePoint(sidewalk.geom, 0.5)) ) AS RANK
	  FROM
	    osm_sidewalk_udistrict1 sidewalk
	  JOIN
	    arnold.segment_test_line road
	  ON
	    ST_Intersects(ST_Buffer(sidewalk.geom, 2), ST_Buffer(road.geom, 15))  -- TODO: need TO MODIFY so so we have better number, what IF there 
	  WHERE (
	    		ABS(DEGREES(ST_Angle(road.geom, sidewalk.geom))) BETWEEN 0 AND 10 -- 0 
		    	OR ABS(DEGREES(ST_Angle(road.geom, sidewalk.geom))) BETWEEN 170 AND 190 -- 180
		    	OR ABS(DEGREES(ST_Angle(road.geom, sidewalk.geom))) BETWEEN 350 AND 360 -- 360
	    	) 
	   		AND (  ST_length(sidewalk.geom) > 10 ) -- IGNORE sidewalk that ARE shorter than 10 meters
	)
	SELECT
	  sidewalk_id,
	  road_id,
	  road_routeid,
	  angle_degrees,
	  midpoints_distance,
	  sidewalk_length,
	  tags,
	  sidewalk_geom,
	  road_geom,
	  'sidewalk' AS label
	FROM
	  ranked_roads
	WHERE
	  rank = 1;


-------------- STEP 3: How to deal with the rest of the sidewalk segments? --------------
-- check point 3.1: how many sidewalk segments left
SELECT *
FROM osm_sidewalk_udistrict1 sidewalk
WHERE sidewalk.geom NOT IN (
	SELECT lp.sidewalk_geom
	FROM conflation.long_parallel lp); --34
	-- TODO: weird case: 490774566
	
---- STEP 3.1: CREATE conflation table
CREATE TABLE conflation.conflation_test1 (
	osm_id INT8,
	label VARCHAR(100),
	tags hstore,
	st1_routeid VARCHAR(75),
	st2_routeid VARCHAR(75),
	st3_routeid VARCHAR(75),
	osm_geom GEOMETRY(LineString, 3857)
)

-- insert long and parallel sidewalk to conflation table
INSERT INTO conflation.conflation_test1 (osm_id, LABEL, tags, st1_routeid, osm_geom)
	SELECT sidewalk_id AS osm_id, LABEL, tags, road_routeid AS st1_routeid, sidewalk_geom AS osm_geom
	FROM conflation.long_parallel

---- STEP 3.2: Handle the segments that are the corner connecting this centerline of the sidewalk to the other centerline of the sidewalk
-- insert corner into the conflation table
INSERT INTO conflation.conflation_test1 (osm_id, LABEL, tags, st1_routeid, st2_routeid, osm_geom)
	SELECT corner.osm_id AS osm_id, 'corner' AS LABEL, corner.tags, centerline1.road_routeid AS st1_routeid, centerline2.road_routeid AS st2_routeid, corner.geom AS osm_geom
	FROM osm_sidewalk_udistrict1 corner
	JOIN conflation.long_parallel centerline1 ON st_intersects(st_startpoint(corner.geom), centerline1.sidewalk_geom)
	JOIN conflation.long_parallel centerline2 ON st_intersects(st_endpoint(corner.geom), centerline2.sidewalk_geom)
	WHERE corner.geom NOT IN (
		SELECT lp.sidewalk_geom
		FROM conflation.long_parallel lp) AND (centerline1.road_routeid <> centerline2.road_routeid)

-- check point 3.2: points that intersect with the sidewalk, but sidewalk not in the conflation table
SELECT point.barrier, point.tags AS point_tag, sw.tags AS sw_tags, point.geom, sw.geom
FROM osm_point_udistrict1 point
JOIN (	
	SELECT *
	FROM osm_sidewalk_udistrict1 sidewalk
	WHERE sidewalk.geom NOT IN (
	SELECT osm_geom
	FROM conflation.conflation_test1 ) ) AS sw
ON ST_intersects(sw.geom, point.geom)

-- check point 3.3: points that intersect with the sidewalk and sidewalk in the conflation table
SELECT point.barrier, point.tags AS point_tag, sw.tags AS sw_tags, point.geom, sw.geom
FROM osm_point_udistrict1 point
JOIN (	
	SELECT *
	FROM osm_sidewalk_udistrict1 sidewalk
	WHERE sidewalk.geom IN (
	SELECT osm_geom
	FROM conflation.conflation_test1 ) ) AS sw
ON ST_intersects(sw.geom, point.geom)


-- check point 3.4: points that intersect with the sidewalk, regardless if sidewalk is in the conflation or not
SELECT point.barrier, point.tags AS point_tag, sw.tags AS sw_tags, point.geom, sw.geom
FROM osm_point_udistrict1 point
JOIN (	
	SELECT *
	FROM osm_sidewalk_udistrict1 sidewalk ) AS sw
ON ST_intersects(sw.geom, point.geom)


---- STEP 3.3: for those points that intersects with the sidewalk segments that not already in the table,
-- we are going to throw it in the conflation table, and it will not associate with any street(?)
-- TODO: confirm, do we need to associate entrance with streets?
INSERT INTO conflation.conflation_test1 (osm_id, LABEL, tags, osm_geom)
	SELECT sw.osm_id, 'entrance' AS LABEL, point.tags AS tags, sw.geom AS osm_geom
	FROM osm_sidewalk_udistrict1 sw
	JOIN (
		SELECT *
		FROM osm_point_udistrict1 
		WHERE tags -> 'entrance' IS NOT NULL 
		OR tags -> 'wheelchair' IS NOT NULL 
		) AS point 
		ON ST_intersects(sw.geom, point.geom)

		
-- check point 3.4: what do we have in conflation table after inputting sidewalk, entrance, corner?
SELECT *
FROM conflation.conflation_test1 ct -- 87 OUT OF 107 sidewalk segments! (81%)

-- check point: how crossing and sidewalk are connected?
SELECT crossing.tags AS crossing, sidewalk.tags AS sidewalk, crossing.geom AS cross_geom, sidewalk.geom AS sidewalk_geom
FROM osm_crossing_udistrict1 crossing
JOIN osm_sidewalk_udistrict1 sidewalk
ON ST_Intersects(sidewalk.geom, crossing.geom);


-- check point: how highway=footway and crossing are connected?
SELECT crossing.tags AS crossing, footway.tags AS footway, crossing.geom AS cross_geom, footway.geom AS footway_geom
FROM osm_footway_null_udistrict1 footway
JOIN osm_crossing_udistrict1 crossing
ON ST_Intersects(footway.geom, crossing.geom);

-- check point: how highway=footway and crossing and sidewalk are connected?
SELECT joined_crossing.crossing_tags AS crossing_tags, joined_crossing.footway_tags AS footway_tags, sidewalk.tags AS sidewalk, joined_crossing.cross_geom AS cross_geom, joined_crossing.footway_geom AS footway_geom,sidewalk.geom AS sidewalk_geom
FROM osm_sidewalk_udistrict1 sidewalk
JOIN (SELECT crossing.tags AS crossing_tags, footway.tags AS footway_tags, crossing.geom AS cross_geom, footway.geom AS footway_geom
		FROM osm_footway_null_udistrict1 footway
		JOIN osm_crossing_udistrict1 crossing
		ON ST_Intersects(footway.geom, crossing.geom)) AS joined_crossing
ON ST_Intersects(sidewalk.geom, joined_crossing.footway_geom) OR ST_Intersects(sidewalk.geom, joined_crossing.cross_geom)

-- check point: what is sidewalk intersecting?
SELECT footway.tags AS footway, sidewalk.geom AS sidewalk_geom, footway.geom AS footway_geom
FROM osm_sidewalk_udistrict1 sidewalk
JOIN (
	SELECT tags, way AS geom
	FROM planet_osm_line
	WHERE 	highway = 'footway' AND 
			(tags -> 'footway' IS NULL OR
			tags -> 'footway' !=  'sidewalk' ) AND
			way && st_setsrid( st_makebox2d( st_makepoint(-13616323, 6049894), st_makepoint(-13615733, 6050671) ), 3857) ) AS footway
ON ST_Intersects(footway.geom, sidewalk.geom);
 


---- STEP 3.4: How to handle the rest of the sidewalk segments
-- Solution: first, conflate the crossing edge.

-- check point: see how many crossing are there 
SELECT DISTINCT crossing.osm_id, crossing.geom
FROM osm_crossing_udistrict1 crossing -- 60

INSERT INTO conflation.conflation_test1 (osm_id, LABEL, tags, st1_routeid, osm_geom)
	SELECT crossing.osm_id AS osm_id, 'crossing' AS LABEL, crossing.tags AS tags, road.routeid AS st1_routeid, crossing.geom AS osm_geom 
	FROM osm_crossing_udistrict1 crossing
	JOIN arnold.segment_test_line road ON ST_Intersects(crossing.geom, road.geom)
-- note, there is one special case that is not joined in this table cuz it is not intersecting with any roads: osm_id 929628172

-- check point: where sidewalk intersects crossing and sidewalk not in conflation table
SELECT crossing.osm_id AS osm_id, crossing.tags AS cross_tags, sw.tags AS sw_tags, sw.geom AS sw_geom, crossing.geom AS cross_geom
	FROM osm_crossing_udistrict1 crossing
	JOIN osm_sidewalk_udistrict1 sw ON ST_Intersects(crossing.geom, sw.geom)
	JOIN conflation.conflation_test1 sw_conf ON ST_Intersects(sw_conf.osm_geom, crossing.geom)
	WHERE sw.geom NOT IN 
	(
	SELECT osm_geom
	FROM conflation.conflation_test1 )


	
	
-- finding links by perform st_intersects between the osm_sidewalk_udistrict1 with the crossing in the conflation table
SELECT DISTINCT sw.osm_id, 'crossing link' AS label, sw.tags, sw.geom, crossing.osm_geom
FROM osm_sidewalk_udistrict1 sw
JOIN conflation.conflation_test1 crossing
ON ST_Intersects(crossing.osm_geom, sw.geom)
WHERE   crossing.LABEL = 'crossing' AND
		sw.geom NOT IN (
						SELECT osm_geom
						FROM conflation.conflation_test1 ) AND
		ST_Length(sw.geom) < 10 -- leaving the two special cases OUT: osm_id = 490774566, 475987407

	
-- next, finding links by perform st_intersects between the osm_footway_null_udistrict1 with the crossing in the conflation table
--check point: see where crossing intersect with footway = null
SELECT footway_null.tags, footway_null.geom, crossing.osm_geom
FROM osm_footway_null_udistrict1 footway_null
JOIN conflation.conflation_test1 crossing
ON ST_Intersects(crossing.osm_geom, footway_null.geom)
WHERE crossing.LABEL = 'crossing'
-- not using this right now
	
	
-- TODO: Confirm, what information do we need in a conflation table
-- TODO: revise the conflation table schema
-- TODO: Design a permanent id to refer

	

-- LIMITATION: defined number and buffer cannot accurately represent all the sidewalk scenarios
	-- TODO: buffer size when we look at how many lanes there are --> better size of buffering

