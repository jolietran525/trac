-- create road table that have sidewalk tags
CREATE TABLE jolie_portland_1.osm_roads_sidewalk AS 
	SELECT osm_id
	FROM planet_osm_line
	WHERE tags -> 'sidewalk' IN ('left', 'right', 'both') AND
		  highway NOT IN ('proposed', 'footway', 'pedestrian') AND
		  way && st_setsrid( st_makebox2d( st_makepoint(-13643161,5704871), st_makepoint(-13642214,5705842)), 3857);
	
 
CREATE TABLE jolie_portland_1.osm_roads AS
	SELECT DISTINCT og.*, 
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
			END AS lanes
		FROM planet_osm_line og
		JOIN jolie_portland_1.osm_roads_lanes_alt road
		ON ST_Intersects(road.way, og.way)
		WHERE og.osm_id NOT IN (SELECT osm_id FROM jolie_portland_1.osm_roads_sidewalk) AND
			  og.highway NOT IN ('proposed', 'footway', 'cycleway', 'bridleway', 'path', 'steps', 'escalator') AND
			  og.way && st_setsrid( st_makebox2d( st_makepoint(-13643161,5704871), st_makepoint(-13642214,5705842)), 3857);


ALTER TABLE jolie_portland_1.osm_roads
ADD norm_lanes INT4; 

-- NORMALIZE the number of lanes
UPDATE jolie_portland_1.osm_roads
SET norm_lanes = subquery.updated_lanes
FROM (
    SELECT l1.name, l1.highway, CEIL(AVG(l1.lanes)) AS updated_lanes
    FROM jolie_portland_1.osm_roads l1
    GROUP BY l1.name, l1.highway
) AS subquery
WHERE jolie_portland_1.osm_roads.name = subquery.name
	  AND jolie_portland_1.osm_roads.highway = subquery.highway
	  
SELECT * FROM jolie_portland_1.osm_roads

SELECT * FROM  jolie_portland_1.sidewalk_raw



-- take out the sub-seg that touch the road
SELECT 
	COALESCE(ST_Difference(sidewalk.geom, ST_Buffer((ST_Union(ST_Intersection(sidewalk.geom, ST_Buffer(road.way, (LEAST(COALESCE(road.lanes, road.norm_lanes))*12+6)/3.5 )))), 1, 'endcap=square join=round')),
			 sidewalk.geom)
FROM jolie_portland_1.sidewalk_raw sidewalk
LEFT JOIN jolie_portland_1.osm_roads road
ON ST_Intersects(sidewalk.geom, ST_Buffer(road.way, 2 ))
GROUP BY sidewalk.geom
HAVING NOT ST_IsEmpty(
    COALESCE(ST_Difference(sidewalk.geom, ST_Buffer((ST_Union(ST_Intersection(sidewalk.geom, ST_Buffer(road.way, (LEAST(COALESCE(road.lanes, road.norm_lanes))*12+6)/3.5 )))), 1, 'endcap=square join=round')),
			 sidewalk.geom));

-- see the sub-seg that are deleted
SELECT 
	ST_Intersection(sidewalk.geom, ST_Buffer((ST_Union(ST_Intersection(sidewalk.geom, ST_Buffer(road.way, (LEAST(COALESCE(road.lanes, road.norm_lanes))*12+6)/3.5 )))), 1, 'endcap=square join=round'))
FROM jolie_portland_1.sidewalk_raw sidewalk
LEFT JOIN jolie_portland_1.osm_roads road
ON ST_Intersects(sidewalk.geom, ST_Buffer(road.way, 2 ))
GROUP BY sidewalk.geom
HAVING NOT ST_IsEmpty(
    ST_Intersection(sidewalk.geom, ST_Buffer((ST_Union(ST_Intersection(sidewalk.geom, ST_Buffer(road.way, (LEAST(COALESCE(road.lanes, road.norm_lanes))*12+6)/3.5 )))), 1, 'endcap=square join=round')));
    
   
   
------ MEDIANs
-- create an alternative table of road
CREATE TABLE jolie_portland_1.osm_roads_lanes_alt AS
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
		   	r1.norm_lanes,
		   	ST_Makeline(ST_Startpoint(r1.way), ST_endpoint(r1.way)) AS way
	FROM jolie_portland_1.osm_roads_lanes r1
	JOIN jolie_portland_1.osm_roads_lanes r2
	ON ST_Intersects(ST_Startpoint(r1.way), ST_endpoint(r2.way)) AND 
		ST_Intersects(ST_endpoint(r1.way), ST_startpoint(r2.way))
	WHERE r1.osm_id < r2.osm_id
	UNION ALL
	SELECT osm_id, highway, name, tags, lanes, norm_lanes, way
	FROM jolie_portland_1.osm_roads_lanes
	WHERE osm_id NOT IN (
		SELECT r1.osm_id
		FROM jolie_portland_1.osm_roads_lanes r1
		JOIN jolie_portland_1.osm_roads_lanes r2
		ON ST_Intersects(ST_Startpoint(r1.way), ST_endpoint(r2.way)) AND 
			ST_Intersects(ST_endpoint(r1.way), ST_startpoint(r2.way))
	)
	

DROP TABLE jolie_portland_1.sidewalk_from_road_alt
CREATE TABLE jolie_portland_1.sidewalk_from_road_alt AS
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
	FROM jolie_portland_1.osm_roads_lanes_alt;

------- CUT THE Sidewalks if it touches the road --------
DROP TABLE jolie_portland_1.sidewalk_raw_alt
CREATE TABLE jolie_portland_1.sidewalk_raw_alt AS 
	SELECT osm_id, left_sidewalk AS geom, tags, way
	FROM jolie_portland_1.sidewalk_from_road_alt
	WHERE left_sidewalk IS NOT NULL
	UNION ALL
	SELECT osm_id, right_sidewalk AS geom, tags, way
	FROM jolie_portland_1.sidewalk_from_road_alt
	WHERE right_sidewalk IS NOT NULL;

-- take out the sub-seg that touch the BIG road
SELECT 
	COALESCE(ST_Difference(sidewalk.geom, ST_Buffer((ST_Union(ST_Intersection(sidewalk.geom, ST_Buffer(road.way, (LEAST(COALESCE(road.lanes, road.norm_lanes))*12+6)/3.5 )))), 1, 'endcap=square join=round')),
			 sidewalk.geom)
FROM jolie_portland_1.sidewalk_raw_alt sidewalk
LEFT JOIN jolie_portland_1.osm_roads_lanes_alt road
ON ST_Intersects(sidewalk.geom, ST_Buffer(road.way, 2 ))
GROUP BY sidewalk.geom
HAVING NOT ST_IsEmpty(
    COALESCE(ST_Difference(sidewalk.geom, ST_Buffer((ST_Union(ST_Intersection(sidewalk.geom, ST_Buffer(road.way, (LEAST(COALESCE(road.lanes, road.norm_lanes))*12+6)/3.5 )))), 1, 'endcap=square join=round')),
			 sidewalk.geom))
UNION ALL
SELECT wkb_geometry 
FROM portland.curb_ramps 
WHERE wkb_geometry && st_setsrid( st_makebox2d( st_makepoint(-13643161,5704871), st_makepoint(-13642214,5705842)), 3857)

