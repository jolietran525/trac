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




-- Create OSM roads (only those that intersects with the roads with tags sidewalk = left|right|both)
-- And roads that NOT highway = ('proposed', 'footway', 'cycleway', 'bridleway', 'path', 'steps', 'escalator', 'service', 'track')
-- if highway = 'service', it should intersects with the road (sidewalk = left|right|both) by the points in between, not by endpoints
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
	JOIN jolie_portland_1.osm_roads_sidewalk_alt road_alt
	    ON ST_Intersects(og.way, road_alt.way)
	WHERE og.osm_id NOT IN (SELECT osm_id FROM jolie_portland_1.osm_roads_sidewalk) AND
	      ((og.highway = 'service' AND
	      	road_alt.way IS NOT NULL AND
	      	ST_Intersects(st_startpoint(og.way), road_alt.way) IS FALSE AND
	      	ST_Intersects(st_endpoint(og.way), road_alt.way) IS FALSE) OR
	       (og.highway NOT IN ('proposed', 'footway', 'cycleway', 'bridleway', 'path', 'steps', 'escalator', 'service', 'track'))) AND
	        ST_IsClosed(og.way) IS FALSE AND -- IGNORE IF the road segment IS a roundabout
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
		 


-- update the number of lanes in the osm_roads_sidewalk_alt
UPDATE jolie_portland_1.osm_roads_sidewalk_alt
	SET norm_lanes = subquery.updated_lanes
	FROM (
	    SELECT l1.name, l1.highway, FLOOR(AVG(l1.lanes)) AS updated_lanes
	    FROM jolie_portland_1.osm_roads l1
	    GROUP BY l1.name, l1.highway
	) AS subquery
	WHERE (jolie_portland_1.osm_roads_sidewalk_alt.name = subquery.name OR jolie_portland_1.osm_roads_sidewalk_alt.name IS NULL) AND
		  jolie_portland_1.osm_roads_sidewalk_alt.highway = subquery.highway;


SELECT * FROM jolie_portland_1.osm_roads_sidewalk_alt;



/* ---------------- SIDEWALKS ------------------- */
-- DRAW sidewalks
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


-- Union the left and right sidewalks as individual records
CREATE TABLE jolie_portland_1.sidewalk_raw AS 
	WITH raw_sw AS (
		SELECT osm_id, left_sidewalk AS geom, tags, way
		FROM jolie_portland_1.sidewalk_from_road
		WHERE left_sidewalk IS NOT NULL
		UNION ALL
		SELECT osm_id, right_sidewalk AS geom, tags, way
		FROM jolie_portland_1.sidewalk_from_road
		WHERE right_sidewalk IS NOT NULL )
	SELECT osm_id, CAST(CONCAT( osm_id, '.', ROW_NUMBER () OVER ( PARTITION BY osm_id )) AS FLOAT8) AS sw_id, geom, tags, way
	FROM raw_sw;



-- Update the sidewalk geom, case when the sidewalks endpoints not connected to each other when it supposed to connects
-- TO DO: write a procedure -> stop when the updated rows is 0
UPDATE jolie_portland_1.sidewalk_raw
	SET geom = subquery.updated_geom
		FROM (
		    SELECT sw2.sw_id, sw1.geom, sw2.geom AS sw2_geom, ST_linemerge(ST_Collect(sw2.geom, ST_ShortestLine(sw1.geom, sw2.geom))) AS updated_geom
			FROM jolie_portland_1.sidewalk_raw sw1
			JOIN jolie_portland_1.sidewalk_raw sw2
			ON ST_Intersects(sw1.way, sw2.way) AND sw1.osm_id < sw2.osm_id AND ST_Intersects(sw1.geom, sw2.geom) IS FALSE
			WHERE  (ST_Distance(st_endpoint(sw1.geom), st_endpoint(sw2.geom)) > 0 AND ST_Distance(st_endpoint(sw1.geom), st_endpoint(sw2.geom)) < 5 OR
			        ST_Distance(st_startpoint(sw1.geom), st_startpoint(sw2.geom)) > 0 AND ST_Distance(st_startpoint(sw1.geom), st_startpoint(sw2.geom)) < 5 OR
			        ST_Distance(st_startpoint(sw1.geom), st_endpoint(sw2.geom)) > 0 AND ST_Distance(st_startpoint(sw1.geom), st_endpoint(sw2.geom)) < 5 OR 
			        ST_Distance(st_endpoint(sw1.geom), st_startpoint(sw2.geom)) > 0 AND ST_Distance(st_endpoint(sw1.geom), st_startpoint(sw2.geom)) < 5 )
		) AS subquery
		WHERE jolie_portland_1.sidewalk_raw.sw_id = subquery.sw_id;

        
 
-- take out the sub-seg that touch the road
DROP TABLE jolie_portland_1.sidewalk_subseg
CREATE TABLE jolie_portland_1.sidewalk_subseg AS 
	WITH seg_raw AS (
		SELECT sidewalk.sw_id,
			   (ST_Dump(COALESCE(ST_Difference(sidewalk.geom, ST_Buffer((ST_Union(ST_Intersection(sidewalk.geom, ST_Buffer(road.way, ((LEAST(road.lanes,road.norm_lanes)*12)+8)/3.281 )))), 1, 'endcap=square join=round')),
					    sidewalk.geom))).geom AS geom
		FROM jolie_portland_1.sidewalk_raw sidewalk
		LEFT JOIN jolie_portland_1.osm_roads road
		ON ST_Intersects(sidewalk.geom, ST_Buffer(road.way, 2 ))
		GROUP BY sidewalk.sw_id, sidewalk.geom
		HAVING NOT ST_IsEmpty(
					    COALESCE(ST_Difference(sidewalk.geom, ST_Buffer((ST_Union(ST_Intersection(sidewalk.geom, ST_Buffer(road.way, ((LEAST(road.lanes,road.norm_lanes)*12)+8)/3.281 )))), 1, 'endcap=square join=round')),
								 sidewalk.geom)))
	SELECT sw_id, CAST(CONCAT( sw_id, ROW_NUMBER () OVER (PARTITION BY sw_id)) AS FLOAT8) AS seg_id, geom
	FROM seg_raw





							

-- DEFINE the intersection as the point where there are at least 3 road sub-seg
-- break the roads to smaller segments at every intersections
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



-- Intersection points
CREATE TABLE jolie_portland_1.osm_intersection AS
	SELECT DISTINCT (ST_Intersection(m1.way, m2.way)) AS point
	FROM jolie_portland_1.osm_roads m1
	JOIN jolie_portland_1.osm_roads m2 ON ST_Intersects(m1.way, m2.way) AND m1.osm_id <> m2.osm_id;



-- Show all intersection points with at least 3 road sub-seg
SELECT point AS point, ST_UNION(subseg.way) AS road
FROM jolie_portland_1.osm_intersection point
JOIN jolie_portland_1.osm_roads_subseg subseg
ON ST_Intersects(subseg.way, point.point)
GROUP BY point.point
HAVING COUNT(subseg.osm_id) >= 3


-- show all the intersections and the sidewalks
SELECT NULL::geometry AS sidewalk, point AS point, ST_UNION(subseg.way) AS road
FROM jolie_portland_1.osm_intersection point
JOIN jolie_portland_1.osm_roads_subseg subseg
ON ST_Intersects(subseg.way, point.point)
GROUP BY point.point
HAVING COUNT(subseg.osm_id) >= 3
UNION ALL  
SELECT 
	COALESCE(ST_Difference(sidewalk.geom, ST_Buffer((ST_Union(ST_Intersection(sidewalk.geom, ST_Buffer(road.way, ((LEAST(road.lanes,road.norm_lanes)*12)+8)/3.281 )))), 1, 'endcap=square join=round')),
			 sidewalk.geom) AS sidewalk, NULL::geometry AS point, NULL::geometry AS road
FROM jolie_portland_1.sidewalk_raw sidewalk
LEFT JOIN jolie_portland_1.osm_roads road
ON ST_Intersects(sidewalk.geom, ST_Buffer(road.way, 2 ))
GROUP BY sidewalk.geom
HAVING NOT ST_IsEmpty(
    COALESCE(ST_Difference(sidewalk.geom, ST_Buffer((ST_Union(ST_Intersection(sidewalk.geom, ST_Buffer(road.way, ((LEAST(road.lanes,road.norm_lanes)*12)+8)/3.281 )))), 1, 'endcap=square join=round')),
			 sidewalk.geom))
UNION ALL 
SELECT NULL::geometry AS sidewalk, wkb_geometry AS point, NULL::geometry AS road
FROM portland.curb_ramps
WHERE wkb_geometry && st_setsrid( st_makebox2d( st_makepoint(-13643161,5704871), st_makepoint(-13642214,5705842)), 3857);




-- next step: how to draw crossings?

-- attempt to merge the subseg if it's too short: merge the subseg that's shorter than 5 meters to the longer seg that's connected to it
CREATE TABLE jolie_portland_1.sidewalk_subseg_merged AS
	SELECT large_seg.sw_id, large_seg.seg_id, 
		   CASE
		   		WHEN ST_Distance(ST_EndPoint(small_seg.geom), ST_LineInterpolatePoint(large_seg.geom, 0.5)) > ST_Distance(st_startPoint(small_seg.geom), ST_LineInterpolatePoint(large_seg.geom, 0.5)) AND
		   			 ST_Distance(ST_EndPoint(large_seg.geom), ST_LineInterpolatePoint(small_seg.geom, 0.5)) > ST_Distance(st_startPoint(large_seg.geom), ST_LineInterpolatePoint(small_seg.geom, 0.5))
		   		THEN 
		   			st_linemerge(ST_Collect(ST_LineSubstring(large_seg.geom, LEAST(ST_LineLocatePoint(large_seg.geom, ST_EndPoint(large_seg.geom)), ST_LineLocatePoint(large_seg.geom, ST_Intersection(small_seg.geom, large_seg.geom))), GREATEST(ST_LineLocatePoint(large_seg.geom, ST_EndPoint(large_seg.geom)), ST_LineLocatePoint(large_seg.geom, ST_Intersection(small_seg.geom, large_seg.geom))))
		   			, st_makeline(st_endpoint(small_seg.geom), ST_Intersection(small_seg.geom, large_seg.geom))), FALSE)
		   		
		   		WHEN ST_Distance(ST_EndPoint(small_seg.geom), ST_LineInterpolatePoint(large_seg.geom, 0.5)) > ST_Distance(st_startPoint(small_seg.geom), ST_LineInterpolatePoint(large_seg.geom, 0.5)) AND
		   			 ST_Distance(ST_EndPoint(large_seg.geom), ST_LineInterpolatePoint(small_seg.geom, 0.5)) < ST_Distance(st_startPoint(large_seg.geom), ST_LineInterpolatePoint(small_seg.geom, 0.5)) 
		   		THEN st_linemerge(ST_Collect(ST_LineSubstring(large_seg.geom, LEAST(ST_LineLocatePoint(large_seg.geom, ST_StartPoint(large_seg.geom)), ST_LineLocatePoint(large_seg.geom, ST_Intersection(small_seg.geom, large_seg.geom))), GREATEST(ST_LineLocatePoint(large_seg.geom, ST_StartPoint(large_seg.geom)), ST_LineLocatePoint(large_seg.geom, ST_Intersection(small_seg.geom, large_seg.geom))))
		   			 , st_makeline(st_endpoint(small_seg.geom), ST_Intersection(small_seg.geom, large_seg.geom))), FALSE)
		   			 
		   		WHEN ST_Distance(ST_EndPoint(small_seg.geom), ST_LineInterpolatePoint(large_seg.geom, 0.5)) < ST_Distance(st_startPoint(small_seg.geom), ST_LineInterpolatePoint(large_seg.geom, 0.5)) AND
		   			 ST_Distance(ST_EndPoint(large_seg.geom), ST_LineInterpolatePoint(small_seg.geom, 0.5)) < ST_Distance(st_startPoint(large_seg.geom), ST_LineInterpolatePoint(small_seg.geom, 0.5)) 
		   		THEN st_linemerge(ST_Collect(ST_LineSubstring(large_seg.geom, LEAST(ST_LineLocatePoint(large_seg.geom, ST_StartPoint(large_seg.geom)), ST_LineLocatePoint(large_seg.geom, ST_Intersection(small_seg.geom, large_seg.geom))), GREATEST(ST_LineLocatePoint(large_seg.geom, ST_StartPoint(large_seg.geom)), ST_LineLocatePoint(large_seg.geom, ST_Intersection(small_seg.geom, large_seg.geom))))
		   			 , st_makeline(st_startpoint(small_seg.geom), ST_Intersection(small_seg.geom, large_seg.geom))), FALSE)
		   			 
		   		WHEN ST_Distance(ST_EndPoint(small_seg.geom), ST_LineInterpolatePoint(large_seg.geom, 0.5)) < ST_Distance(st_startPoint(small_seg.geom), ST_LineInterpolatePoint(large_seg.geom, 0.5)) AND
		   			 ST_Distance(ST_EndPoint(large_seg.geom), ST_LineInterpolatePoint(small_seg.geom, 0.5)) > ST_Distance(st_startPoint(large_seg.geom), ST_LineInterpolatePoint(small_seg.geom, 0.5)) 
		   		THEN st_linemerge(ST_Collect(ST_LineSubstring(large_seg.geom, LEAST(ST_LineLocatePoint(large_seg.geom, ST_EndPoint(large_seg.geom)), ST_LineLocatePoint(large_seg.geom, ST_Intersection(small_seg.geom, large_seg.geom))), GREATEST(ST_LineLocatePoint(large_seg.geom, ST_EndPoint(large_seg.geom)), ST_LineLocatePoint(large_seg.geom, ST_Intersection(small_seg.geom, large_seg.geom))))
		   			 , st_makeline(st_startpoint(small_seg.geom), ST_Intersection(small_seg.geom, large_seg.geom))), FALSE)
		   END AS geom
	FROM jolie_portland_1.sidewalk_subseg large_seg
	JOIN jolie_portland_1.sidewalk_subseg small_seg
	ON ST_intersects(large_seg.geom, small_seg.geom) 
	WHERE ST_Length(large_seg.geom)>5 AND ST_Length(small_seg.geom)<5 
	
	UNION ALL
	
	SELECT *
	FROM jolie_portland_1.sidewalk_subseg
	WHERE seg_id NOT IN (
			SELECT seg_id
			FROM jolie_portland_1.sidewalk_subseg
			WHERE ST_Length(geom)<5 
			
			UNION ALL
			
			SELECT large_seg.seg_id
			FROM jolie_portland_1.sidewalk_subseg large_seg
			JOIN jolie_portland_1.sidewalk_subseg small_seg
			ON ST_intersects(large_seg.geom, small_seg.geom) 
			WHERE ST_Length(large_seg.geom)>5 AND ST_Length(small_seg.geom)<5 );



		
		

-- return endpoints of each sidewalks
DROP TABLE jolie_portland_1.sidewalk_subseg_merged_endpoints
CREATE TABLE jolie_portland_1.sidewalk_subseg_merged_endpoints AS
	SELECT seg_id, 'sp' AS pt_type, st_startpoint(geom) AS point, geom
	FROM jolie_portland_1.sidewalk_subseg_merged
	UNION ALL
	SELECT seg_id, 'ep' AS pt_type, st_endpoint(geom) AS point, geom
	FROM jolie_portland_1.sidewalk_subseg_merged;





-- select all endpoints that overlaps over another endpoint of anther sidewalk sub-seg
SELECT DISTINCT p1.seg_id, p1.pt_type, p1.point
FROM jolie_portland_1.sidewalk_subseg_merged_endpoints p1
JOIN jolie_portland_1.sidewalk_subseg_merged_endpoints p2
ON ST_Intersects(ST_Buffer(p1.point, 0.5), p2.point) AND ST_Equals(p1.geom, p2.geom) IS FALSE




-- function finding the angle between 2 segments, if this function return 0, then its parallel,
-- the higher result it return, the less parallel it is
CREATE OR REPLACE FUNCTION jolie_portland_1.f_degrees(_rad DOUBLE PRECISION) RETURNS DOUBLE PRECISION AS $$
    WITH m AS (SELECT mod(degrees(_rad)::NUMERIC, 180) AS angle)
        ,a AS (SELECT CASE WHEN m.angle > 90 THEN m.angle - 180 ELSE m.angle END AS angle FROM m)
    SELECT abs(a.angle) FROM a;
$$ LANGUAGE SQL IMMUTABLE STRICT;


-- see which endpoint of the sidewalk has curb ramps
-- in this query:
	-- first, find the the curb ramps that are within 10 meters of our endpoints (the endpoints must not be those that are the connecting point of another sidewalk segment)
	-- then, we know that for every endpoint, it should only be correspond to only 1 curb 
	-- do this by grouping the endpoints, then only choose the curb ramp that when we draw a line between the enpoint and the curb,
	-- and that line with the subseg of the same distance with one endpoint being the endpoint that we are looking at
	-- must be // to each other (the idea of ordering by distance failed so we use this)
CREATE TABLE jolie_portland_1.endpoint_curb AS 
	WITH rank_curb AS (
		SELECT sw.seg_id, sw.pt_type, sw.point AS end_point, cr.objectid AS cr_id, cr.wkb_geometry AS curb_ramp,  geom AS sidewalk,
			   jolie_portland_1.f_degrees(ST_Angle(st_makeline(sw.point, cr.wkb_geometry), ST_Intersection(geom, ST_Buffer(sw.point, ST_Distance(sw.point, cr.wkb_geometry))))),
			   ROW_NUMBER () OVER (
						  	PARTITION BY point
						  	ORDER BY jolie_portland_1.f_degrees(ST_Angle(st_makeline(sw.point, cr.wkb_geometry), ST_Intersection(geom, ST_Buffer(sw.point, ST_Distance(sw.point, cr.wkb_geometry)))))
						  	) AS RANK
		FROM jolie_portland_1.sidewalk_subseg_merged_endpoints sw
		JOIN portland.curb_ramps cr
		ON ST_Intersects(ST_Buffer(cr.wkb_geometry, 10), sw.point)
		WHERE   (sw.seg_id, sw.pt_type) NOT IN (SELECT DISTINCT p1.seg_id, p1.pt_type
					FROM jolie_portland_1.sidewalk_subseg_merged_endpoints p1
					JOIN jolie_portland_1.sidewalk_subseg_merged_endpoints p2
					ON ST_Intersects(ST_Buffer(p1.point, 0.5), p2.point) AND ST_Equals(p1.geom, p2.geom) IS FALSE) AND
				cr.wkb_geometry && st_setsrid( st_makebox2d( st_makepoint(-13643161,5704871), st_makepoint(-13642214,5705842)), 3857) )
	SELECT seg_id, pt_type, end_point, cr_id, curb_ramp, sidewalk
	FROM rank_curb
	WHERE RANK = 1;




--- create a table that record where all the curb ramps that got attatched to the body of the sidewalk
CREATE TABLE jolie_portland_1.body_curb AS 
	SELECT sw.seg_id, sw.geom AS sidewalk, cr.objectid, ST_ClosestPoint(sw.geom, cr.wkb_geometry) AS curb_ramp
	FROM jolie_portland_1.sidewalk_subseg_merged sw
	JOIN (
		SELECT *
		FROM portland.curb_ramps cr
		WHERE cr.objectid NOT IN (SELECT cr_id
									FROM jolie_portland_1.endpoint_curb) AND
			  cr.wkb_geometry && st_setsrid( st_makebox2d( st_makepoint(-13643161,5704871), st_makepoint(-13642214,5705842)), 3857)		
		) cr
	ON ST_Intersects(ST_Buffer(cr.wkb_geometry, 5), sw.geom)






-- drawing corners
CREATE TABLE jolie_portland_1.sidewalk_corners AS
	SELECT p1.seg_id AS seg_id1, p1.pt_type AS pt_type1, p2.seg_id AS seg_id2, p2.pt_type AS pt_type2, ST_Makeline(p1.point, p2.point) AS corner
	FROM jolie_portland_1.sidewalk_subseg_merged_endpoints p1
	JOIN jolie_portland_1.sidewalk_subseg_merged_endpoints p2
	ON ST_DWithin(p1.point, p2.point, 5) AND ST_Equals(p1.point, p2.point) IS FALSE
	WHERE p1.seg_id < p2.seg_id 
		 AND (p1.seg_id, p1.pt_type) NOT IN (SELECT DISTINCT p1.seg_id, p1.pt_type
						FROM jolie_portland_1.sidewalk_subseg_merged_endpoints p1
						JOIN jolie_portland_1.sidewalk_subseg_merged_endpoints p2
						ON ST_Intersects(ST_Buffer(p1.point, 0.5), p2.point) AND ST_Equals(p1.geom, p2.geom) IS FALSE)
		 AND (p2.seg_id, p2.pt_type) NOT IN (SELECT DISTINCT p1.seg_id, p1.pt_type
						FROM jolie_portland_1.sidewalk_subseg_merged_endpoints p1
						JOIN jolie_portland_1.sidewalk_subseg_merged_endpoints p2
						ON ST_Intersects(ST_Buffer(p1.point, 0.5), p2.point) AND ST_Equals(p1.geom, p2.geom) IS FALSE);
 




-- endpoints (at intersections) that don't get associated to any curb ramps:
SELECT *
FROM jolie_portland_1.sidewalk_subseg_merged_endpoints
WHERE (seg_id, pt_type) NOT IN (
				SELECT DISTINCT p1.seg_id, p1.pt_type
				FROM jolie_portland_1.sidewalk_subseg_merged_endpoints p1
				JOIN jolie_portland_1.sidewalk_subseg_merged_endpoints p2
				ON ST_Intersects(ST_Buffer(p1.point, 0.5), p2.point) AND ST_Equals(p1.geom, p2.geom) IS FALSE
				UNION ALL 
				SELECT DISTINCT seg_id, pt_type
				FROM jolie_portland_1.endpoint_curb)


				
				
--- DRAWING NOW
				
				
CREATE TABLE jolie_portland_1.connlink_raw AS (
				
	---- PART 1: draw connlink from curb ramps that we identify on the body of the sidewalk
	SELECT bc.seg_id, 'bp' AS pt_type, 'yes' AS curb, ST_Intersection(ST_Buffer(bc.curb_ramp, 4), ST_ShortestLine(bc.curb_ramp, road.way)) AS conn_link
	FROM jolie_portland_1.body_curb bc
	JOIN jolie_portland_1.osm_roads_sidewalk_alt road
	ON floor(bc.seg_id) = road.osm_id 
	
	
	UNION ALL
	---- PART 2: draw connlink from endpoints that we CANNOT associate with any curb ramps
	-- a) At intersections with no curbs AND we can draw corner between 2 sidewalk, extend the sidewalk segments
	SELECT 
			CASE
				WHEN oldseg = seg_id1
					THEN  seg_id2
				WHEN oldseg = seg_id2
					THEN seg_id1
			END AS seg_id,
			CASE
				WHEN oldseg = seg_id1
					THEN pt_type2
				WHEN oldseg = seg_id2
					THEN pt_type1
			END AS pt_type, 
			'no' AS curb,
			st_translate(conn_link, del_x, del_y) AS conn_link 
	FROM	(SELECT DISTINCT sc.*, epc.seg_id oldseg, epc.pt_type oldpt, epc.point pt, epc.geom,
						CASE
							WHEN ST_Startpoint(sc.corner) = epc.point
								THEN ST_X(ST_Endpoint(sc.corner)) - ST_X(ST_Startpoint(sc.corner))
							WHEN ST_Endpoint(sc.corner) = epc.point
								THEN ST_X(ST_Startpoint(sc.corner)) - ST_X(ST_Endpoint(sc.corner))
						END AS del_x,
						CASE
							WHEN ST_Startpoint(sc.corner) = epc.point
								THEN ST_Y(ST_Endpoint(sc.corner)) - ST_Y(ST_Startpoint(sc.corner))
							WHEN ST_Endpoint(sc.corner) = epc.point
								THEN ST_Y(ST_Startpoint(sc.corner)) - ST_Y(ST_Endpoint(sc.corner))
						END AS del_y,
					   ST_makeline(epc.point, ST_Startpoint(ST_LongestLine(ST_Buffer(epc.point, 4), ST_Intersection(ST_ExteriorRing(ST_Buffer(epc.point, 4)), epc.geom)))) AS conn_link
		FROM jolie_portland_1.sidewalk_subseg_merged_endpoints epc
		JOIN (	SELECT point
				FROM jolie_portland_1.osm_intersection point
				JOIN jolie_portland_1.osm_roads_subseg subseg
				ON ST_Intersects(subseg.way, point.point)
				GROUP BY point.point
				HAVING COUNT(subseg.osm_id) >= 3 ) int_pt
		ON ST_Intersects(ST_Buffer(int_pt.point, 25), epc.point)
		JOIN jolie_portland_1.sidewalk_corners sc
		ON (sc.seg_id1 = epc.seg_id AND sc.pt_type1 = epc.pt_type) OR (sc.seg_id2 = epc.seg_id AND sc.pt_type2 = epc.pt_type)
		WHERE (seg_id, pt_type) NOT IN (
						SELECT DISTINCT p1.seg_id, p1.pt_type
						FROM jolie_portland_1.sidewalk_subseg_merged_endpoints p1
						JOIN jolie_portland_1.sidewalk_subseg_merged_endpoints p2
						ON ST_Intersects(ST_Buffer(p1.point, 0.5), p2.point) AND ST_Equals(p1.geom, p2.geom) IS FALSE
						UNION ALL 
						SELECT DISTINCT seg_id, pt_type
						FROM jolie_portland_1.endpoint_curb)) pretrans
	UNION ALL
	
	
	-- b)1. At intersections with no curbs AND we cannot draw corner between 2 sidewalk, extend the sidewalk segment and draw a perpendicular
	SELECT DISTINCT epc.seg_id, epc.pt_type, 'no' AS curb,
			   ST_makeline(epc.point, ST_Startpoint(ST_LongestLine(ST_Buffer(epc.point, 4), ST_Intersection(ST_ExteriorRing(ST_Buffer(epc.point, 4)), epc.geom)))) AS conn_link
	FROM jolie_portland_1.sidewalk_subseg_merged_endpoints epc
	JOIN (	SELECT point
			FROM jolie_portland_1.osm_intersection point
			JOIN jolie_portland_1.osm_roads_subseg subseg
			ON ST_Intersects(subseg.way, point.point)
			GROUP BY point.point
			HAVING COUNT(subseg.osm_id) >= 3 ) int_pt
	ON ST_Intersects(ST_Buffer(int_pt.point, 25), epc.point)
	LEFT JOIN jolie_portland_1.sidewalk_corners sc
	ON (sc.seg_id1 = epc.seg_id AND sc.pt_type1 = epc.pt_type) OR (sc.seg_id2 = epc.seg_id AND sc.pt_type2 = epc.pt_type)
	WHERE (seg_id, pt_type) NOT IN (
					SELECT DISTINCT p1.seg_id, p1.pt_type
					FROM jolie_portland_1.sidewalk_subseg_merged_endpoints p1
					JOIN jolie_portland_1.sidewalk_subseg_merged_endpoints p2
					ON ST_Intersects(ST_Buffer(p1.point, 0.5), p2.point) AND ST_Equals(p1.geom, p2.geom) IS FALSE
					UNION ALL 
					SELECT DISTINCT seg_id, pt_type
					FROM jolie_portland_1.endpoint_curb) AND 
			sc.seg_id1 IS NULL
	
			
	UNION ALL
	--- b)2. for the same endpoints as the previous ones (b), draw another connlink that is perpendicular
	SELECT DISTINCT epc.seg_id, epc.pt_type, 'no' AS curb,
					ST_Intersection(ST_Buffer(epc.point, 4), ST_ShortestLine(epc.point, road.way)) AS conn_link
	FROM jolie_portland_1.sidewalk_subseg_merged_endpoints epc
	JOIN (	SELECT point
			FROM jolie_portland_1.osm_intersection point
			JOIN jolie_portland_1.osm_roads_subseg subseg
			ON ST_Intersects(subseg.way, point.point)
			GROUP BY point.point
			HAVING COUNT(subseg.osm_id) >= 3 ) int_pt
	ON ST_Intersects(ST_Buffer(int_pt.point, 25), epc.point)
	JOIN jolie_portland_1.osm_roads_sidewalk_alt road
	ON floor(epc.seg_id) = road.osm_id
	LEFT JOIN jolie_portland_1.sidewalk_corners sc
	ON (sc.seg_id1 = epc.seg_id AND sc.pt_type1 = epc.pt_type) OR (sc.seg_id2 = epc.seg_id AND sc.pt_type2 = epc.pt_type)
	WHERE (seg_id, pt_type) NOT IN (
					SELECT DISTINCT p1.seg_id, p1.pt_type
					FROM jolie_portland_1.sidewalk_subseg_merged_endpoints p1
					JOIN jolie_portland_1.sidewalk_subseg_merged_endpoints p2
					ON ST_Intersects(ST_Buffer(p1.point, 0.5), p2.point) AND ST_Equals(p1.geom, p2.geom) IS FALSE
					UNION ALL 
					SELECT DISTINCT seg_id, pt_type
					FROM jolie_portland_1.endpoint_curb) AND 
			sc.seg_id1 IS NULL
				
			
	---- PART 3: Draw connlink where curb ramps ARE identified at the endpoint of the sidewalks
	
	UNION ALL
	-- a) draw connlink where one curb has 2 endpoints: these need to be 45 degrees 
	SELECT epc.seg_id, epc.pt_type, 'yes' AS curb,
		   ST_ShortestLine(ST_LineInterpolatePoint(sc.corner, 0.5), ST_Buffer(int_pt.point, ST_Distance(ST_LineInterpolatePoint(sc.corner, 0.5), int_pt.point)-4))  AS conn_link
	FROM jolie_portland_1.endpoint_curb epc
	JOIN (	SELECT point
			FROM jolie_portland_1.osm_intersection point
			JOIN jolie_portland_1.osm_roads_subseg subseg
			ON ST_Intersects(subseg.way, point.point)
			GROUP BY point.point
			HAVING COUNT(subseg.osm_id) >= 3 ) int_pt
	ON ST_Intersects(ST_Buffer(point, 25), end_point)
	JOIN jolie_portland_1.sidewalk_corners sc
	ON (sc.seg_id1 = epc.seg_id AND sc.pt_type1 = epc.pt_type) OR (sc.seg_id2 = epc.seg_id AND sc.pt_type2 = epc.pt_type)
	WHERE (epc.cr_id, epc.curb_ramp) IN (
			SELECT cr_id, curb_ramp 
			FROM jolie_portland_1.endpoint_curb
			GROUP BY cr_id, curb_ramp
			HAVING COUNT(end_point) = 2
		) 
	
	
	
	UNION ALL
	--- b) For endpoints that have one curb, and there is another endpoint within 10m
	-- draw this using corners, cuz a corner must have 2 endpoints
	SELECT  
--		    CASE
--				WHEN oldseg = seg_id1
--					THEN  seg_id2
--				WHEN oldseg = seg_id2
--					THEN seg_id1
--			END AS seg_id,
--			CASE
--				WHEN oldseg = seg_id1
--					THEN pt_type2
--				WHEN oldseg = seg_id2
--					THEN pt_type1
--			END AS pt_type,
			oldseg AS seg_id,
			oldpt AS pt_type,
			'yes' AS curb,
			st_translate(conn_link, del_x, del_y) AS conn_link 
	FROM (
			SELECT DISTINCT sc.*, epc.seg_id oldseg, epc.pt_type oldpt, epc.end_point pt, epc.sidewalk,
					CASE
						WHEN ST_Startpoint(sc.corner) = epc.end_point
							THEN CAST(ST_X(ST_Endpoint(sc.corner)) - ST_X(ST_Startpoint(sc.corner)) AS DOUBLE PRECISION)
						WHEN ST_Endpoint(sc.corner) = epc.end_point
							THEN CAST(ST_X(ST_Startpoint(sc.corner)) - ST_X(ST_Endpoint(sc.corner)) AS DOUBLE PRECISION)
					END AS del_x,
					CASE
						WHEN ST_Startpoint(sc.corner) = epc.end_point
							THEN CAST(ST_Y(ST_Endpoint(sc.corner)) - ST_Y(ST_Startpoint(sc.corner)) AS DOUBLE PRECISION)
						WHEN ST_Endpoint(sc.corner) = epc.end_point
							THEN CAST(ST_Y(ST_Startpoint(sc.corner)) - ST_Y(ST_Endpoint(sc.corner)) AS DOUBLE PRECISION)
					END AS del_y, 
					CASE
						WHEN ST_Startpoint(sc.corner) = epc.end_point
							THEN CAST(ST_X(ST_Endpoint(sc.corner)) - ST_X(ST_Startpoint(sc.corner)) AS DOUBLE PRECISION)
						WHEN ST_Endpoint(sc.corner) = epc.end_point
							THEN CAST(ST_X(ST_Startpoint(sc.corner)) - ST_X(ST_Endpoint(sc.corner)) AS DOUBLE PRECISION)
					END AS del_x,
					CASE
						WHEN ST_Startpoint(sc.corner) = epc.end_point
							THEN CAST(ST_Y(ST_Endpoint(sc.corner)) - ST_Y(ST_Startpoint(sc.corner)) AS DOUBLE PRECISION)
						WHEN ST_Endpoint(sc.corner) = epc.end_point
							THEN CAST(ST_Y(ST_Startpoint(sc.corner)) - ST_Y(ST_Endpoint(sc.corner)) AS DOUBLE PRECISION)
					END AS del_y,
				   ST_makeline(epc.end_point, ST_Startpoint(ST_LongestLine(ST_Buffer(epc.end_point, 4), ST_Intersection(ST_ExteriorRing(ST_Buffer(epc.end_point, 4)), epc.sidewalk)))) AS conn_link
			FROM jolie_portland_1.endpoint_curb epc
			JOIN (	SELECT point
					FROM jolie_portland_1.osm_intersection point
					JOIN jolie_portland_1.osm_roads_subseg subseg
					ON ST_Intersects(subseg.way, point.point)
					GROUP BY point.point
					HAVING COUNT(subseg.osm_id) >= 3 ) int_pt
			ON ST_Intersects(ST_Buffer(point, 25), end_point)
			JOIN jolie_portland_1.sidewalk_corners sc
			ON (sc.seg_id1 = epc.seg_id AND sc.pt_type1 = epc.pt_type) OR (sc.seg_id2 = epc.seg_id AND sc.pt_type2 = epc.pt_type)
			WHERE (epc.cr_id, epc.curb_ramp) IN (
					SELECT cr_id, curb_ramp 
					FROM jolie_portland_1.endpoint_curb
					GROUP BY cr_id, curb_ramp
					HAVING COUNT(end_point) = 1 )
		)pretrans
	
	
	UNION ALL	
	-- c)1. For endpoints that have one curb, and there is no other endpoint within 10m
	-- extend it
	SELECT DISTINCT epc.seg_id, epc.pt_type, 'yes' AS curb,
			   ST_makeline(epc.end_point, ST_Startpoint(ST_LongestLine(ST_Buffer(epc.end_point, 4), ST_Intersection(ST_ExteriorRing(ST_Buffer(epc.end_point, 4)), epc.sidewalk)))) AS conn_link
	FROM jolie_portland_1.endpoint_curb epc
	JOIN (	SELECT point
			FROM jolie_portland_1.osm_intersection point
			JOIN jolie_portland_1.osm_roads_subseg subseg
			ON ST_Intersects(subseg.way, point.point)
			GROUP BY point.point
			HAVING COUNT(subseg.osm_id) >= 3 ) int_pt
	ON ST_Intersects(ST_Buffer(int_pt.point, 25), epc.end_point)
	LEFT JOIN jolie_portland_1.sidewalk_corners sc
	ON (sc.seg_id1 = epc.seg_id AND sc.pt_type1 = epc.pt_type) OR (sc.seg_id2 = epc.seg_id AND sc.pt_type2 = epc.pt_type)
	WHERE (epc.cr_id, epc.curb_ramp) IN (
					SELECT cr_id, curb_ramp 
					FROM jolie_portland_1.endpoint_curb
					GROUP BY cr_id, curb_ramp
					HAVING COUNT(end_point) = 1) AND 
			sc.seg_id1 IS NULL
	

	UNION ALL
	-- c)2. For endpoints that have one curb, and there is no other endpoint within 10m
	-- draw a perpendicular connlink
	SELECT DISTINCT epc.seg_id, epc.pt_type, 'yes' AS curb,
					ST_Intersection(ST_Buffer(epc.end_point, 4), ST_ShortestLine(epc.end_point, road.way)) AS conn_link
	FROM jolie_portland_1.endpoint_curb epc
	JOIN (	SELECT point
			FROM jolie_portland_1.osm_intersection point
			JOIN jolie_portland_1.osm_roads_subseg subseg
			ON ST_Intersects(subseg.way, point.point)
			GROUP BY point.point
			HAVING COUNT(subseg.osm_id) >= 3 ) int_pt
	ON ST_Intersects(ST_Buffer(int_pt.point, 25), epc.end_point)
	JOIN jolie_portland_1.osm_roads_sidewalk_alt road
	ON floor(epc.seg_id) = road.osm_id
	LEFT JOIN jolie_portland_1.sidewalk_corners sc
	ON (sc.seg_id1 = epc.seg_id AND sc.pt_type1 = epc.pt_type) OR (sc.seg_id2 = epc.seg_id AND sc.pt_type2 = epc.pt_type)
	WHERE (epc.cr_id, epc.curb_ramp) IN (
					SELECT cr_id, curb_ramp 
					FROM jolie_portland_1.endpoint_curb
					GROUP BY cr_id, curb_ramp
					HAVING COUNT(end_point) = 1) AND 
			sc.seg_id1 IS NULL
)





SELECT *
FROM jolie_portland_1.connlink_raw  





-- group by intersection point
WITH connlink1 AS (
	SELECT *
	FROM jolie_portland_1.connlink_raw  connlink
	JOIN (	    SELECT point
				FROM jolie_portland_1.osm_intersection point
				JOIN jolie_portland_1.osm_roads_subseg subseg
				ON ST_Intersects(subseg.way, point.point)
				GROUP BY point.point
				HAVING COUNT(subseg.osm_id) >= 3    ) int_pt
	ON ST_Intersects(ST_Buffer(int_pt.point, 25), st_endpoint(connlink.conn_link)) )
	, connlink2 AS (
	SELECT *
	FROM jolie_portland_1.connlink_raw  connlink
	JOIN (	    SELECT point
				FROM jolie_portland_1.osm_intersection point
				JOIN jolie_portland_1.osm_roads_subseg subseg
				ON ST_Intersects(subseg.way, point.point)
				GROUP BY point.point
				HAVING COUNT(subseg.osm_id) >= 3    ) int_pt
	ON ST_Intersects(ST_Buffer(int_pt.point, 25), st_endpoint(connlink.conn_link)) )
SELECT ST_MAKELINE(ST_ENDPOINT(connlink1.conn_link), ST_ENDPOINT(connlink2.conn_link)), connlink1.point, connlink1.conn_link, connlink2.conn_link
FROM connlink1
JOIN connlink2
ON  ST_Equals(connlink1.point, connlink2.point) AND
	CONCAT(connlink1.seg_id, connlink1.pt_type)!=(CONCAT(connlink2.seg_id, connlink2.pt_type)) AND 
	FLOOR(connlink1.seg_id) = FLOOR(connlink2.seg_id)
JOIN jolie_portland_1.osm_roads_sidewalk_alt road_lane
ON road_lane.osm_id = FLOOR(connlink1.seg_id)
WHERE ST_DWithin(ST_ENDPOINT(connlink1.conn_link), ST_ENDPOINT(connlink2.conn_link), ((LEAST(road_lane.lanes,road_lane.norm_lanes)*12)+6)/3.281*2)







SELECT *
FROM portland.curb_ramps
WHERE wkb_geometry && st_setsrid(st_makebox2d(st_makepoint(-13643161,5704871), st_makepoint(-13642214,5705842)), 3857)

	  
------- CROSSINGS ---------

