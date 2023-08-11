-- create road table that have sidewalk tags
CREATE TABLE jolie_portland_1.osm_roads_sidewalk  AS 
	SELECT *,
		   CASE
			WHEN tags ? 'lanes'
				THEN CAST(tags -> 'lanes' AS int)
			WHEN tags ? 'lanes' = FALSE AND 
			    (tags ? 'lanes:forward' OR
				 tags ? 'lanes:backward' OR
				 tags ? 'lanes:both_ways')
				THEN COALESCE(CAST(tags -> 'lanes:forward' AS int), 0) + COALESCE(CAST(tags -> 'lanes:backward' AS int), 0) + COALESCE(CAST(tags -> 'lanes:both_ways' AS int), 0) 
			END AS lanes
	FROM planet_osm_line
	WHERE tags -> 'sidewalk' IN ('left', 'right', 'both') AND
		  highway NOT IN ('proposed', 'footway', 'pedestrian') AND
		  way && st_setsrid( st_makebox2d( st_makepoint(-13643161,5704871), st_makepoint(-13642214,5705842)), 3857);


------ MEDIANs
-- create an alternative table of road
CREATE TABLE jolie_portland_1.osm_roads_sidewalk_alt AS
	SELECT r1.osm_id,
		   r1.highway,
		   r1.name,
		   CASE WHEN
		   		r1.tags->'sidewalk'=r2.tags->'sidewalk'
		   		THEN r1.tags ||
		   			 hstore('sidewalk', 'both') ||
		   			 hstore('lanes', CAST(r1.lanes + r2.lanes AS TEXT))
		   	END AS tags,
		   	r1.lanes + r2.lanes AS lanes,
		   	ST_Makeline(ST_Startpoint(r1.way), ST_endpoint(r1.way)) AS way
	FROM jolie_portland_1.osm_roads_sidewalk r1
	JOIN jolie_portland_1.osm_roads_sidewalk r2
	ON ST_Intersects(ST_Startpoint(r1.way), ST_endpoint(r2.way)) AND 
		ST_Intersects(ST_endpoint(r1.way), ST_startpoint(r2.way))
	WHERE r1.osm_id < r2.osm_id
	UNION ALL
	SELECT osm_id, highway, name, tags, lanes, way
	FROM jolie_portland_1.osm_roads_sidewalk
	WHERE osm_id NOT IN (
		SELECT r1.osm_id
		FROM jolie_portland_1.osm_roads_sidewalk r1
		JOIN jolie_portland_1.osm_roads_sidewalk r2
		ON ST_Intersects(ST_Startpoint(r1.way), ST_endpoint(r2.way)) AND 
			ST_Intersects(ST_endpoint(r1.way), ST_startpoint(r2.way))
	);


CREATE TABLE jolie_portland_1.osm_roads AS
	SELECT DISTINCT og.osm_id, og.highway, og.name, og.tags,
	    CASE
	        WHEN og.tags ? 'lanes'
	            THEN CAST(og.tags -> 'lanes' AS int)
	        WHEN og.tags ? 'lanes' = FALSE AND 
	            (og.tags ? 'lanes:forward' OR
	             og.tags ? 'lanes:backward' OR
	             og.tags ? 'lanes:both_ways')
	            THEN COALESCE(CAST(og.tags -> 'lanes:forward' AS int), 0) + COALESCE(CAST(og.tags -> 'lanes:backward' AS int), 0) + COALESCE(CAST(og.tags -> 'lanes:both_ways' AS int), 0)
	        WHEN og.tags ? 'lanes' = FALSE AND 
	            (og.tags ? 'lanes:forward' = FALSE AND
	             og.tags ? 'lanes:backward' = FALSE AND
	             og.tags ? 'lanes:both_ways' = FALSE)
	            THEN 2
	    END AS lanes,
	    og.way,
	    NULL::bigint AS norm_lanes
	FROM planet_osm_line og
	LEFT JOIN jolie_portland_1.osm_roads_sidewalk_alt road_alt
	    ON ST_Intersects(og.way, road_alt.way) AND
	       (ST_Intersects(st_startpoint(og.way), road_alt.way) IS FALSE AND ST_Intersects(st_endpoint(og.way), road_alt.way) IS FALSE)
	LEFT JOIN jolie_portland_1.osm_roads_sidewalk road
	    ON og.osm_id = road.osm_id
	WHERE og.osm_id NOT IN (SELECT osm_id FROM jolie_portland_1.osm_roads_sidewalk) AND
	      ((og.highway = 'service' AND road_alt.way IS NOT NULL) OR
	      (og.highway NOT IN ('proposed', 'footway', 'cycleway', 'bridleway', 'path', 'steps', 'escalator', 'service', 'track'))) AND
	      og.way && st_setsrid(st_makebox2d(st_makepoint(-13643161,5704871), st_makepoint(-13642214,5705842)), 3857)
	UNION ALL
	SELECT *, NULL::bigint AS norm_lanes
	FROM jolie_portland_1.osm_roads_sidewalk_alt;


 
-- update norm_lanes of osm_roads
UPDATE jolie_portland_1.osm_roads
	SET norm_lanes = subquery.updated_lanes
	FROM (
	    SELECT l1.name, l1.highway, FLOOR(AVG(l1.lanes)) AS updated_lanes
	    FROM jolie_portland_1.osm_roads l1
	    GROUP BY l1.name, l1.highway
	) AS subquery
	WHERE (jolie_portland_1.osm_roads.name = subquery.name OR jolie_portland_1.osm_roads.name IS NULL)
		  AND jolie_portland_1.osm_roads.highway = subquery.highway;



-- NORMALIZE the number of lanes in the osm_roads_sidewalk_alt
ALTER TABLE jolie_portland_1.osm_roads_sidewalk_alt
ADD norm_lanes INT4; 
		 

UPDATE jolie_portland_1.osm_roads_sidewalk_alt
	SET norm_lanes = subquery.updated_lanes
	FROM (
	    SELECT l1.name, l1.highway, FLOOR(AVG(l1.lanes)) AS updated_lanes
	    FROM jolie_portland_1.osm_roads l1
	    GROUP BY l1.name, l1.highway
	) AS subquery
	WHERE (jolie_portland_1.osm_roads_sidewalk_alt.name = subquery.name OR jolie_portland_1.osm_roads_sidewalk_alt.name IS NULL) AND
		  jolie_portland_1.osm_roads_sidewalk_alt.highway = subquery.highway;

SELECT * FROM jolie_portland_1.osm_roads_sidewalk_alt

-- Draw sidewalks given in tags in the roads
CREATE TABLE jolie_portland_1.sidewalk_from_road AS
	SELECT  osm_id,
			CASE 
				WHEN tags->'sidewalk' IN ('left','both')
					THEN ST_OffsetCurve(way, ((LEAST(lanes,norm_lanes)*12)+6)/3.281, 'quad_segs=4 join=mitre mitre_limit=2.2')
			END AS left_sidewalk,
			CASE 
				WHEN tags->'sidewalk' IN ('right','both')
					THEN ST_OffsetCurve(way, -((LEAST(lanes,norm_lanes)*12)+6)/3.281, 'quad_segs=4 join=mitre mitre_limit=2.2')
			END AS right_sidewalk,
			tags,
	        way
	FROM jolie_portland_1.osm_roads_sidewalk_alt;

------- CUT THE Sidewalks if it touches the road --------
CREATE TABLE jolie_portland_1.sidewalk_raw AS 
	SELECT osm_id, left_sidewalk AS geom, tags, way
	FROM jolie_portland_1.sidewalk_from_road
	WHERE left_sidewalk IS NOT NULL
	UNION ALL
	SELECT osm_id, right_sidewalk AS geom, tags, way
	FROM jolie_portland_1.sidewalk_from_road
	WHERE right_sidewalk IS NOT NULL;


-- take out the sub-seg that touch the BIG road
SELECT 
	COALESCE(ST_Difference(sidewalk.geom, ST_Buffer((ST_Union(ST_Intersection(sidewalk.geom, ST_Buffer(road.way, ((LEAST(road.lanes,road.norm_lanes)*12)+6)/3.281 )))), 1, 'endcap=square join=round')),
			 sidewalk.geom)
FROM jolie_portland_1.sidewalk_raw sidewalk
LEFT JOIN jolie_portland_1.osm_roads_sidewalk_alt road
ON ST_Intersects(sidewalk.geom, ST_Buffer(road.way, 2 ))
GROUP BY sidewalk.geom
HAVING NOT ST_IsEmpty(
    COALESCE(ST_Difference(sidewalk.geom, ST_Buffer((ST_Union(ST_Intersection(sidewalk.geom, ST_Buffer(road.way, ((LEAST(road.lanes,road.norm_lanes)*12)+6)/3.281 )))), 1, 'endcap=square join=round')),
			 sidewalk.geom))
UNION ALL
SELECT wkb_geometry --- These ARE the curb ramps
FROM portland.curb_ramps 
WHERE wkb_geometry && st_setsrid( st_makebox2d( st_makepoint(-13643161,5704871), st_makepoint(-13642214,5705842)), 3857)


-- DEFINE the intersection as the point where there are at least 3 road sub-seg
-- First, break the road to smaller segments at every intersections

CREATE TABLE jolie_portland_1.osm_roads_subseg AS
	WITH intersection_points AS (
	  SELECT DISTINCT m1.osm_id, (ST_Intersection(m1.way, m2.way)) AS geom
	  FROM jolie_portland_1.osm_roads m1
	  JOIN jolie_portland_1.osm_roads m2 ON ST_Intersects(m1.way, m2.way) AND m1.osm_id <> m2.osm_id )
	SELECT
	  a.osm_id, (ST_Dump(ST_Split(a.way, ST_Union(b.geom)))).geom AS way
	FROM
	  jolie_portland_1.osm_roads AS a
	JOIN
	  intersection_points AS b ON a.osm_id = b.osm_id
	GROUP BY
	  a.osm_id,
	  a.way;


CREATE TABLE jolie_portland_1.osm_intersection AS
	SELECT DISTINCT (ST_Intersection(m1.way, m2.way)) AS point
	FROM jolie_portland_1.osm_roads m1
	JOIN jolie_portland_1.osm_roads m2 ON ST_Intersects(m1.way, m2.way) AND m1.osm_id <> m2.osm_id;


SELECT point, ST_UNION(subseg.way)
FROM jolie_portland_1.osm_intersection point
JOIN jolie_portland_1.osm_roads_subseg subseg
ON ST_Intersects(subseg.way, point.point)
GROUP BY point.point
HAVING COUNT(subseg.osm_id) >= 3;


SELECT wkb_geometry 
FROM portland.curb_ramps
WHERE wkb_geometry && st_setsrid( st_makebox2d( st_makepoint(-13643161,5704871), st_makepoint(-13642214,5705842)), 3857);