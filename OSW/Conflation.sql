----------------- BOUNDING BOX -------------------
-- osm in u-district
create table osm_sidewalk_udistrict as
(select *
from planet_osm_line
where 	highway = 'footway' and
		tags -> 'footway' = 'sidewalk' AND 
way && st_setsrid( st_makebox2d( st_makepoint(-13616401,6049782), st_makepoint(-13615688,6050649)), 3857))

select *
from planet_osm_line
where 	highway = 'footway' and
		(tags -> 'footway' = 'sidewalk' or tags -> 'footway' = 'crossing' or tags -> 'footway' = 'link') AND 
way && st_setsrid( st_makebox2d( st_makepoint(-13616401,6049782), st_makepoint(-13615688,6050649)), 3857);



-- arnold in u-district
create table arnold.wapr_udistrict as
(select *
from arnold.wapr_linestring 
where geom && st_setsrid( st_makebox2d( st_makepoint(-13616401,6049782), st_makepoint(-13615688,6050649)), 3857));



select routeid, shape_length, ST_length(shape), shape 
from arnold.wapr_hpms_submittal 
where shape && st_setsrid( st_makebox2d( st_makepoint(-13616401,6049782), st_makepoint(-13615688,6050649)), 3857);

-- smaller bbox
create table arnold.wapr_udistrict1 as
(select *
from arnold.wapr_linestring 
where geom && st_setsrid( st_makebox2d( st_makepoint(-13616323, 6049894), st_makepoint(-13615733, 6050671)), 3857)
ORDER BY objectid, routeid);


-------- CONFLATION -------------------
-- STEP 0: break down the main road whenever it intersects with another main road
-- This code creates a new table named segment_test by performing the following steps:
	-- Define intersection_points table which finds distinct intersection points between different geometries in the arnold.wapr_udistrict1 table.
	-- Performs a select query that joins the arnold.wapr_udistrict table (a) with the intersection_points CTE (b) using object IDs and route IDs. It collects all the intersection geometries (ST_collect(b.geom)) for each object ID and route ID.
	-- Finally, it splits the geometries in a.geom using the collected intersection geometries (ST_Split(a.geom, ST_collect(b.geom))). The result is a set of individual linestrings obtained by splitting the original geometries.
	-- The resulting linestrings are grouped by object ID, route ID, and original geometry (a.objectid, a.routeid, a.geom) and inserted into the arnold.segment_test table.


CREATE TABLE arnold.segment_test AS
WITH intersection_points AS (
  SELECT DISTINCT m1.objectid oi1, m1.routeid ri1, ST_Intersection(m1.geom, m2.geom) AS geom
  FROM arnold.wapr_udistrict1 m1
  JOIN arnold.wapr_udistrict1 m2 ON ST_Intersects(m1.geom, m2.geom) AND m1.objectid <> m2.objectid
)
SELECT
  a.objectid, a.routeid, ST_collect(b.geom), ST_Split(a.geom, ST_collect(b.geom))
FROM
  arnold.wapr_udistrict AS a
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

	-- create a geom index
CREATE INDEX segment_test_line_geom ON arnold.segment_test_line USING GIST (geom)

-- Step 2: identify matching criteria
-- since the arnold and the OSM datasets don't have any common attributes or identifiers, and their content represents
-- different aspects of the street network (sidewalk vs main roads), we are going to rely on the geomtry properties and
-- spatial relationships to find potential matches. So, we want:
-- 1. buffering
-- 2. intersection
-- 3. parallel

select distinct sidewalk.*
from osm_sidewalk_udistrict sidewalk

select ST_Buffer(geom, 15) as main_road_buffer
from wapr_line_udistrict

SELECT DISTINCT sidewalk.way, road.geom
FROM osm_sidewalk_udistrict sidewalk
JOIN wapr_line_udistrict road
on ST_Intersects(sidewalk.way, ST_Buffer(road.geom, 40));

select DISTINCT sidewalk.way
from osm_sidewalk_udistrict sidewalk
JOIN wapr_line_udistrict road
on ST_Intersects(sidewalk.way, ST_Buffer(road.geom, 30))
WHERE ST_Within(sidewalk.way, ST_Buffer(road.geom, 30));

