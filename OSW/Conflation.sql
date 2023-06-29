--------------------------------------------
		/** BOUNDING BOX **/
--------------------------------------------

---------- OSM in u-district ------------

-- highway = footway, footway = sidewalk
CREATE table jolie_ud1.osm_sw AS (
	SELECT *
	FROM planet_osm_line
	WHERE	highway = 'footway' AND
			tags -> 'footway' = 'sidewalk' AND 
			way && st_setsrid( st_makebox2d( st_makepoint(-13616323, 6049894), st_makepoint(-13615733, 6050671) ), 3857) );

ALTER TABLE jolie_ud1.osm_sw RENAME COLUMN way TO geom;


-- points
CREATE table jolie_ud1.osm_point AS (
	SELECT *
	FROM planet_osm_point
	WHERE
			way && st_setsrid( st_makebox2d( st_makepoint(-13616323, 6049894), st_makepoint(-13615733, 6050671) ), 3857) );

ALTER TABLE jolie_ud1.osm_point RENAME COLUMN way TO geom;

-- highway = footway, footway = crossing
CREATE TABLE jolie_ud1.osm_crossing AS (
	SELECT *
	FROM planet_osm_line
	WHERE   highway = 'footway' AND 
			tags -> 'footway' = 'crossing' AND 
			way && st_setsrid( st_makebox2d( st_makepoint(-13616323, 6049894), st_makepoint(-13615733, 6050671) ), 3857) );

ALTER TABLE jolie_ud1.osm_crossing RENAME COLUMN way TO geom;


-- highway = footway, footway IS NULL OR footway not sidewalk/crossing
CREATE TABLE jolie_ud1.osm_footway_null AS (
	SELECT *
	FROM planet_osm_line
	WHERE 	highway = 'footway' AND 
			(tags -> 'footway' IS NULL OR 
			tags -> 'footway' NOT IN ('sidewalk', 'crossing'))  AND
			way && st_setsrid( st_makebox2d( st_makepoint(-13616323, 6049894), st_makepoint(-13615733, 6050671) ), 3857)  );
		
ALTER TABLE jolie_ud1.osm_footway_null RENAME COLUMN way TO geom;

CREATE TABLE jolie_ud1.osm_footway AS (
	SELECT *
	FROM planet_osm_line
	WHERE 	highway = 'footway' AND
			way && st_setsrid( st_makebox2d( st_makepoint(-13616323, 6049894), st_makepoint(-13615733, 6050671) ), 3857)  );

ALTER TABLE jolie_ud1.osm_footway RENAME COLUMN way TO geom;


--------- ARNOLD in u-district ----------
CREATE TABLE jolie_ud1.arnold_roads AS (
	SELECT *
	FROM arnold.wapr_linestring 
	WHERE geom && st_setsrid( st_makebox2d( st_makepoint(-13616323, 6049894), st_makepoint(-13615733, 6050671)), 3857)
	ORDER BY routeid, beginmeasure, endmeasure);


--------------------------------------------
			/* CONFLATION */
--------------------------------------------

--------- STEP 1: break down the main road whenever it intersects with another main road ---------

-- This code creates a new table named segment_test by performing the following steps:
	-- Define intersection_points table which finds distinct intersection points between different geometries in the jolie_ud1.arnold_roads table.
	-- Performs a select query that joins the arnold.wapr_udistrict table (a) with the intersection_points CTE (b) using object IDs and route IDs. It collects all the intersection geometries (ST_collect(b.geom)) for each object ID and route ID.
	-- Finally, it splits the geometries in a.geom using the collected intersection geometries (ST_Split(a.geom, ST_collect(b.geom))). The result is a set of individual linestrings obtained by splitting the original geometries.
	-- The resulting linestrings are grouped by object ID, route ID, and original geometry (a.objectid, a.routeid, a.geom) and inserted into the jolie_ud1.arnold_segments_collection table.
CREATE TABLE jolie_ud1.arnold_segments_collection AS
	WITH intersection_points AS (
	  SELECT DISTINCT m1.objectid objectid, m1.og_objectid og_objectid, m1.routeid routeid, m1.beginmeasure beginmeasure, m1.endmeasure endmeasure, ST_Intersection(m1.geom, m2.geom) AS geom
	  FROM jolie_ud1.arnold_roads m1
	  JOIN jolie_ud1.arnold_roads m2 ON ST_Intersects(m1.geom, m2.geom) AND m1.objectid <> m2.objectid )
	SELECT
	  a.objectid, a.og_objectid, a.routeid, a.beginmeasure, a.endmeasure, ST_collect(b.geom), ST_Split(a.geom, ST_collect(b.geom))
	FROM
	  jolie_ud1.arnold_roads AS a
	JOIN
	  intersection_points AS b ON a.objectid = b.objectid AND a.routeid = b.routeid
	GROUP BY
	  a.objectid,
	  a.og_objectid,
	  a.routeid,
	  a.beginmeasure,
	  a.endmeasure,
	  a.geom;

-- create a table that pull the data from the segment_test table, convert it into linestring instead leaving it as a collection
CREATE TABLE jolie_ud1.arnold_segments_line AS
	SELECT objectid, og_objectid, routeid, beginmeasure, endmeasure, (ST_Dump(st_split)).geom::geometry(LineString, 3857) AS geom
	FROM jolie_ud1.arnold_segments_collection
	ORDER BY routeid, beginmeasure, endmeasure;

-- Create a geom index
CREATE INDEX segments_line_geom ON jolie_ud1.arnold_segments_line USING GIST (geom);
CREATE INDEX sw_geom ON jolie_ud1.osm_sw USING GIST (geom);
CREATE INDEX crossing_geom ON jolie_ud1.osm_crossing USING GIST (geom);
CREATE INDEX point_geom ON jolie_ud1.osm_point USING GIST (geom);
CREATE INDEX footway_null_geom ON jolie_ud1.osm_footway_null USING GIST (geom);

--------- STEP 2: identify matching criteria between sidewalk and arnold ---------
-- since the arnold and the OSM datasets don't have any common attributes or identifiers, and their content represents
-- different aspects of the street network (sidewalk vs main roads), we are going to rely on the geomtry properties and
-- spatial relationships to find potential matches. So, we want:
-- 1. buffering
-- 2. intersection with buffer of the road segment
-- 3. parallel

-- check point 2.1: how many sidewalks are there
SELECT sidewalk.*
FROM jolie_ud1.osm_sw sidewalk; -- there ARE 107 sidewalks

-- check point 2.2: how many road segments are there
SELECT *
FROM jolie_ud1.arnold_segments_line; -- there ARE 84 segments

-- In this code, we filter:
-- 1. the road buffer and the sidewalk buffer overlap
-- 2. the road and the sidewalk are parallel to each other (between 0-30 or 165/195 or 330-360 degree)
-- 3. in case where the sidewalk.geom looking at more than 2 road.geom at the same time, we need to choose the one that have the closest distance
--    from the midpoint of the sidewalk to the midpoint of the road
-- 4. Ignore those roads that are smaller than 10 meters
-- Create a big_sw table which contains 73 sidewalk segments that are greater 10 meters and parallel to the road. This is pretty solid.
CREATE TABLE jolie_conflation.big_sw AS
	WITH ranked_roads AS (
	  SELECT
	    sidewalk.osm_id AS osm_id,
	    road.routeid AS arnold_routeid,
	    road.beginmeasure AS arnold_beginmeasure,
	    road.endmeasure AS arnold_endmeasure,
	  	sidewalk.geom AS osm_geom,
	    road.geom AS arnold_geom,
	    ABS(DEGREES(ST_Angle(road.geom, sidewalk.geom))) AS angle_degrees,
	    ST_Distance(ST_LineInterpolatePoint(road.geom, 0.5), ST_LineInterpolatePoint(sidewalk.geom, 0.5)) AS midpoints_distance,
	    sidewalk.tags AS tags,
	    -- rank this based on the distance of the midpoint of the sidewalk to the midpoint of the road
	    ROW_NUMBER() OVER (PARTITION BY sidewalk.geom ORDER BY ST_Distance(ST_LineInterpolatePoint(road.geom, 0.5), ST_LineInterpolatePoint(sidewalk.geom, 0.5)) ) AS RANK
	  FROM
	    jolie_ud1.osm_sw sidewalk
	  JOIN
	    jolie_ud1.arnold_segments_line road
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
	  osm_id,
	  arnold_routeid,
	  arnold_beginmeasure,
	  arnold_endmeasure,
	  osm_geom,
	  arnold_geom
	FROM
	  ranked_roads
	WHERE
	  rank = 1;
	 
	 
-- dealing with the sidewalk segment that are 
SELECT DISTINCT osm_sw.geom, big_sw.arnold_routeid, big_sw.arnold_beginmeasure, big_sw.arnold_endmeasure, big_sw.arnold_geom
FROM jolie_ud1.osm_sw
LEFT JOIN jolie_conflation.big_sw
ON ST_Intersects(big_sw.osm_geom, st_startpoint(osm_sw.geom)) OR ST_Intersects(big_sw.osm_geom, st_endpoint(osm_sw.geom))
WHERE osm_sw.geom NOT IN (
		SELECT big_sw.osm_geom FROM jolie_conflation.big_sw big_sw
	    UNION ALL
	    SELECT link.osm_geom FROM jolie_conflation.connlink link 
	    UNION ALL
	    SELECT crossing.osm_geom FROM jolie_conflation.crossing crossing
	    UNION ALL
	    SELECT edge.osm_geom FROM jolie_conflation.sw_edges edge
	    UNION ALL
	    SELECT entrance.osm_geom FROM jolie_conflation.entrances entrance)
	  AND (
			ABS(DEGREES(ST_Angle(big_sw.osm_geom, osm_sw.geom))) BETWEEN 0 AND 10 -- 0 
		    OR ABS(DEGREES(ST_Angle(big_sw.osm_geom, osm_sw.geom))) BETWEEN 170 AND 190 -- 180
		    OR ABS(DEGREES(ST_Angle(big_sw.osm_geom, osm_sw.geom))) BETWEEN 350 AND 360  ) -- 360  
	  AND (ST_Length(osm_sw.geom) + ST_Length(big_sw.osm_geom) ) < ST_Length(big_sw.arnold_geom)

CREATE INDEX big_sw_sidwalk_geom ON jolie_conflation.big_sw USING GIST (osm_geom);
CREATE INDEX big_sw_arnold_geom ON jolie_conflation.big_sw USING GIST (arnold_geom);


-------------- STEP 3: How to deal with the rest of the footway = sidewalk segments? Possibilities are: edges, connecting link --------------
-- check point 3.1: how many sidewalk segments left, there are edges and link 
SELECT *
FROM jolie_ud1.osm_sw sidewalk
WHERE sidewalk.geom NOT IN (
	SELECT big_sw.osm_geom
	FROM jolie_conflation.big_sw big_sw); --34
	-- TODO: weird case: 490774566
	

---- STEP 3.1: Dealing with edges
	-- assumption: edge will have it start and end point connectected to sidewalk. We will use the big_sw table to identify our sidewalk edges
CREATE TABLE jolie_conflation.sw_edges (
	osm_id INT8,
	arnold_routeid1 VARCHAR(75),
	arnold_beginmeasure1 FLOAT8,
	arnold_endmeasure1 FLOAT8,
	arnold_routeid2 VARCHAR(75),
	arnold_beginmeasure2 FLOAT8,
	arnold_endmeasure2 FLOAT8,
	osm_geom GEOMETRY(LineString, 3857)
)


INSERT INTO jolie_conflation.sw_edges (osm_id, arnold_routeid1, arnold_beginmeasure1, arnold_endmeasure1, arnold_routeid2, arnold_beginmeasure2, arnold_endmeasure2, osm_geom)
	SELECT  edge.osm_id AS osm_id,
			centerline1.arnold_routeid AS arnold_routeid1,
			centerline1.arnold_beginmeasure AS arnold_beginmeasure1,
			centerline1.arnold_endmeasure AS arnold_endmeasure1,
			centerline2.arnold_routeid AS arnold_routeid2,
			centerline2.arnold_beginmeasure AS arnold_beginmeasure2,
			centerline2.arnold_endmeasure AS arnold_endmeasure2,
			edge.geom AS osm_geom
	FROM jolie_ud1.osm_sw edge
	JOIN jolie_conflation.big_sw centerline1 ON st_intersects(st_startpoint(edge.geom), centerline1.osm_geom)
	JOIN jolie_conflation.big_sw centerline2 ON st_intersects(st_endpoint(edge.geom), centerline2.osm_geom)
	WHERE   edge.geom NOT IN (
				SELECT sw.osm_geom
				FROM jolie_conflation.big_sw sw)
			AND ST_Equals(centerline1.osm_geom, centerline2.osm_geom) IS FALSE


---- STEP 3.2: Dealing with entrances
	-- assumption: entrances are small segments that intersect with the sidewalk on one end and intersect with a point that have a tag of entrance=* or wheelchair=*
	
-- create an entrance table
CREATE TABLE jolie_conflation.entrances AS
	SELECT entrance.osm_id, sidewalk.osm_id AS sidewalk_id, entrance.geom AS osm_geom
	FROM jolie_ud1.osm_point point
	JOIN (	SELECT *
			FROM jolie_ud1.osm_sw sidewalk
			WHERE sidewalk.geom NOT IN (
					SELECT osm_geom
					FROM jolie_conflation.big_sw ) AND 
				  sidewalk.geom NOT IN (
					SELECT osm_geom
					FROM jolie_conflation.sw_edges )  ) AS entrance
	ON ST_intersects(entrance.geom, point.geom)
	JOIN jolie_conflation.big_sw sidewalk ON ST_Intersects(entrance.geom, sidewalk.osm_geom)
	WHERE point.tags -> 'entrance' IS NOT NULL 
			OR point.tags -> 'wheelchair' IS NOT NULL
			

---- STEP 3.3: Dealing with crossing
	-- assumption: all of the crossing are referred to as footway=crossing

-- check point: see how many crossing are there 
SELECT DISTINCT crossing.osm_id, crossing.geom
FROM jolie_ud1.osm_crossing crossing -- 60

CREATE TABLE jolie_conflation.crossing (osm_id, arnold_routeid, arnold_beginmeasure, arnold_endmeasure, osm_geom)
	SELECT crossing.osm_id AS osm_id, road.routeid AS arnold_routeid, road.beginmeasure AS arnold_beginmeasure, road.endmeasure arnold_endmeasure, crossing.geom AS osm_geom 
	FROM jolie_ud1.osm_crossing crossing
	JOIN jolie_ud1.arnold_segments_line road ON ST_Intersects(crossing.geom, road.geom)
-- note, there is one special case that is not joined in this table cuz it is not intersecting with any roads: osm_id 929628172. This crossing segment has the access=no

	
---- STEP 3.4: Dealing with connecting link
	-- assumption 1: a link connects the sidewalk to the crossing
	-- assumption 2: OR a link connects the sidewalk esge to the crossing
	-- note: a link might or might not have a footway='sidewalk' tag

-- check point: segments (footway=sidewalk) intersects crossing and not yet in conflation table --> link
SELECT crossing.osm_id AS cross_id, sw.geom AS link_geom, crossing.osm_geom AS cross_geom, sw.osm_id AS link_id
FROM jolie_conflation.crossing crossing
JOIN jolie_ud1.osm_sw sw ON ST_Intersects(crossing.osm_geom, sw.geom)
WHERE sw.geom NOT IN (
		SELECT osm_geom
		FROM jolie_conflation.big_sw ) AND
	  sw.geom NOT IN (
		SELECT osm_geom
		FROM jolie_conflation.sw_edges ) AND
	  ST_Length(sw.geom) < 10 -- leaving the two special cases OUT: osm_id = 490774566, 475987407
ORDER BY link_id

CREATE TABLE jolie_conflation.connlink (
	osm_id INT8,
	arnold_routeid1 VARCHAR(75), 
	arnold_beginmeasure1 FLOAT8,
	arnold_endmeasure1 FLOAT8,
	arnold_routeid2 VARCHAR(75),
	arnold_beginmeasure2 FLOAT8,
	arnold_endmeasure2 FLOAT8,
	osm_geom GEOMETRY(LineString, 3857)
)

-- first, deal with links (footway = sidewalk) that are connected to crossing and not yet in the big_sw table
INSERT INTO jolie_conflation.connlink (osm_id, arnold_routeid1, arnold_beginmeasure1, arnold_endmeasure1, arnold_routeid2, arnold_beginmeasure2, arnold_endmeasure2, osm_geom)
WITH link_not_distinct AS (
    SELECT link_id, arnold_routeid, arnold_beginmeasure, arnold_endmeasure, cross_id, link_geom, ROW_NUMBER() OVER (PARTITION BY link_id ORDER BY cross_id) AS rn
    FROM
        (
            SELECT
                crossing.osm_id AS cross_id, crossing.arnold_routeid, crossing.arnold_beginmeasure, crossing.arnold_endmeasure, sw.geom AS link_geom, crossing.osm_geom AS cross_geom, sw.osm_id AS link_id
            FROM
                jolie_conflation.crossing crossing
            JOIN
                jolie_ud1.osm_sw sw ON ST_Intersects(crossing.osm_geom, sw.geom)
            WHERE
                sw.geom NOT IN (
                    SELECT osm_geom
                    FROM jolie_conflation.big_sw )
                AND sw.geom NOT IN (
					SELECT osm_geom
					FROM jolie_conflation.sw_edges )
                AND ST_Length(sw.geom) < 10
                AND crossing.osm_id NOT IN (490774566, 475987407) -- IGNORE 2 weird cases
            ORDER BY
                link_id
        ) subquery
)
SELECT
    link_id AS osm_id,
    MAX(CASE WHEN rn = 1 THEN arnold_routeid END) AS arnold_routeid1,
    MAX(CASE WHEN rn = 1 THEN arnold_beginmeasure END) AS arnold_beginmeasure1,
    MAX(CASE WHEN rn = 1 THEN arnold_endmeasure END) AS arnold_endmeasure1,
    MAX(CASE WHEN rn = 2 THEN arnold_routeid END) AS arnold_routeid2,
    MAX(CASE WHEN rn = 2 THEN arnold_beginmeasure END) AS arnold_beginmeasure2,
    MAX(CASE WHEN rn = 2 THEN arnold_endmeasure END) AS arnold_endmeasure2,
    link_geom AS osm_geom
FROM
    link_not_distinct
GROUP BY
    link_id, link_geom ;



-- check point: how highway=footway and crossing (conflated) and sidewalk are connected?
SELECT link_crossing.link_id, link_crossing.cross_id, link_crossing.arnold_routeid, link_crossing.arnold_beginmeasure, link_crossing.arnold_endmeasure, link_crossing.link_geom AS link_geom, ROW_NUMBER() OVER (PARTITION BY link_crossing.link_id ORDER BY link_crossing.cross_id) AS rn
FROM jolie_ud1.osm_sw sidewalk
JOIN (  SELECT link.osm_id AS link_id, crossing.osm_id AS cross_id, crossing.arnold_routeid, crossing.arnold_beginmeasure, crossing.arnold_endmeasure, crossing.osm_geom AS cross_geom, link.geom AS link_geom
		FROM jolie_ud1.osm_footway_null link
		JOIN jolie_conflation.crossing crossing
		ON ST_Intersects(link.geom, crossing.osm_geom)) AS link_crossing
ON ST_Intersects(sidewalk.geom, link_crossing.link_geom)



-- then, deal with link that are not tagged as sidewalk/crossing
INSERT INTO jolie_conflation.connlink (osm_id, arnold_routeid1, arnold_beginmeasure1, arnold_endmeasure1, arnold_routeid2, arnold_beginmeasure2, arnold_endmeasure2, osm_geom)
WITH link_not_distinct AS (
SELECT link_crossing.link_id, link_crossing.cross_id, link_crossing.arnold_routeid, link_crossing.arnold_beginmeasure, link_crossing.arnold_endmeasure, link_crossing.link_geom AS link_geom, ROW_NUMBER() OVER (PARTITION BY link_crossing.link_id ORDER BY link_crossing.cross_id) AS rn
FROM jolie_ud1.osm_sw sidewalk
JOIN (  SELECT link.osm_id AS link_id, crossing.osm_id AS cross_id, crossing.arnold_routeid, crossing.arnold_beginmeasure, crossing.arnold_endmeasure, crossing.osm_geom AS cross_geom, link.geom AS link_geom
		FROM jolie_ud1.osm_footway_null link
		JOIN jolie_conflation.crossing crossing
		ON ST_Intersects(link.geom, crossing.osm_geom)
		WHERE link.osm_id NOT IN (475992192) -- IGNORE weird case
	 ) AS link_crossing
ON ST_Intersects(sidewalk.geom, link_crossing.link_geom)
)
SELECT
    link_id AS osm_id,
    MAX(CASE WHEN rn = 1 THEN arnold_routeid END) AS arnold_routeid1,
    MAX(CASE WHEN rn = 1 THEN arnold_beginmeasure END) AS arnold_beginmeasure1,
    MAX(CASE WHEN rn = 1 THEN arnold_endmeasure END) AS arnold_endmeasure1,
    MAX(CASE WHEN rn = 2 THEN arnold_routeid END) AS arnold_routeid2,
    MAX(CASE WHEN rn = 2 THEN arnold_beginmeasure END) AS arnold_beginmeasure2,
    MAX(CASE WHEN rn = 2 THEN arnold_endmeasure END) AS arnold_endmeasure2,
    link_geom AS osm_geom
FROM
    link_not_distinct
GROUP BY
    link_id, link_geom ;

 
 
-- checkpoint: see what is there in conflation tables
WITH conf_table AS (
		SELECT big_sw.osm_geom, 'sidewalk' AS label FROM jolie_conflation.big_sw big_sw
	    UNION ALL
	    SELECT link.osm_geom, 'link' AS label FROM jolie_conflation.connlink link 
	    UNION ALL
	    SELECT crossing.osm_geom, 'crossing' AS label FROM jolie_conflation.crossing crossing
	    UNION ALL
	    SELECT edge.osm_geom, 'edge' AS label FROM jolie_conflation.sw_edges edge
	    UNION ALL
	    SELECT entrance.osm_geom, 'entrance' AS label FROM jolie_conflation.entrances entrance )
SELECT sw.*
FROM jolie_ud1.osm_sw sw
LEFT JOIN conf_table ON sw.geom = conf_table.osm_geom
WHERE conf_table.osm_geom IS NULL;

SELECT count(*) FROM jolie_conflation.big_sw -- 73
SELECT count(*) FROM jolie_conflation.sw_edges -- 5
SELECT count(*) FROM jolie_conflation.entrances --9
SELECT count(*) FROM jolie_conflation.connlink --76

-- LIMITATION: defined number and buffer cannot accurately represent all the sidewalk scenarios
	-- TODO: buffer size when we look at how many lanes there are --> better size of buffering

