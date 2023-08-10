-- osm sidewalk
CREATE TABLE jolie_sdot2osm_caphill.osm_sidewalk AS
	SELECT *, ST_Length(way) AS length
	FROM planet_osm_line pol 
	WHERE   highway='footway' AND tags->'footway'='sidewalk' AND
			way && st_setsrid( st_makebox2d( st_makepoint(-13616673,6039866), st_makepoint(-13613924,6042899)), 3857); --1589

ALTER TABLE jolie_sdot2osm_caphill.osm_sidewalk RENAME COLUMN way TO geom;
CREATE INDEX sw_geom ON jolie_sdot2osm_caphill.osm_sidewalk USING GIST (geom);

-- osm crossing
CREATE TABLE jolie_sdot2osm_caphill.osm_crossing AS
	SELECT *, ST_Length(way) AS length
	FROM planet_osm_line pol 
	WHERE   highway='footway' AND tags->'footway'='crossing' AND
			way && st_setsrid( st_makebox2d( st_makepoint(-13616673,6039866), st_makepoint(-13613924,6042899)), 3857); --810

ALTER TABLE jolie_sdot2osm_caphill.osm_crossing RENAME COLUMN way TO geom;
CREATE INDEX crossing_geom ON jolie_sdot2osm_caphill.osm_crossing USING GIST (geom);

-- osm connlink
CREATE TABLE jolie_sdot2osm_caphill.osm_connlink AS
	SELECT sw.*
	FROM jolie_sdot2osm_caphill.osm_crossing crossing
	JOIN jolie_sdot2osm_caphill.osm_sidewalk sw
	ON ST_Intersects(sw.geom, crossing.geom)
	WHERE sw.length < 12; -- 922
	
-- sdot sidewalk
CREATE TABLE jolie_sdot2osm_caphill.sdot_sidewalk AS
	SELECT *, ST_Length(geom) AS length
	FROM sdot.sidewalks
	WHERE   st_astext(geom) != 'LINESTRING EMPTY'
			AND surftype != 'UIMPRV'
			AND sw_width != 0
			AND geom && st_setsrid( st_makebox2d( st_makepoint(-13616673,6039866), st_makepoint(-13613924,6042899)), 3857); -- 1229

CREATE INDEX sdot_sidewalk_geom ON jolie_sdot2osm_caphill.sdot_sidewalk USING GIST (geom);

-- conflation
CREATE TABLE jolie_sdot2osm_caphill.sdot2osm_sw AS 
	WITH ranked_roads AS (
		SELECT 
		  osm.osm_id AS osm_id,
		  sdot.objectid AS sdot_objectid,
		  sdot.segkey AS sdot_segkey,
		  sdot.unitid AS sdot_unitid,
		  (sdot.shape_length/3.281) AS sdot_length,
		  sdot.sw_width/3.281 AS sdot_sw_width,
		  osm.geom AS osm_geom,
		  sdot.geom AS sdot_geom,
		  CASE
				  	WHEN (sdot.shape_length/3.281 > osm.length) THEN NULL
				  	ELSE ST_LineSubstring( osm.geom, LEAST(ST_LineLocatePoint(osm.geom, ST_ClosestPoint(st_startpoint(sdot.geom), osm.geom)) , ST_LineLocatePoint(osm.geom, ST_ClosestPoint(st_endpoint(sdot.geom), osm.geom))), GREATEST(ST_LineLocatePoint(osm.geom, ST_ClosestPoint(st_startpoint(sdot.geom), osm.geom)) , ST_LineLocatePoint(osm.geom, ST_ClosestPoint(st_endpoint(sdot.geom), osm.geom))) )
			  	END AS osm_seg,
		  CASE
				  	WHEN (sdot.shape_length/3.281 > osm.length)
				  		THEN ST_LineSubstring( sdot.geom, LEAST(ST_LineLocatePoint(sdot.geom, ST_ClosestPoint(st_startpoint(osm.geom), sdot.geom)) , ST_LineLocatePoint(sdot.geom, ST_ClosestPoint(st_endpoint(osm.geom), sdot.geom))), GREATEST(ST_LineLocatePoint(sdot.geom, ST_ClosestPoint(st_startpoint(osm.geom), sdot.geom)) , ST_LineLocatePoint(sdot.geom, ST_ClosestPoint(st_endpoint(osm.geom), sdot.geom))) )
				  	ELSE NULL
			  	END AS sdot_seg,
		  ROW_NUMBER() OVER (
		  	PARTITION BY (
		  		CASE
				  	WHEN (sdot.length > osm.length) 
				  		THEN  osm.geom
				  	ELSE sdot.geom
			  	END
		  	)
		  	ORDER BY
		  		CASE
				  	WHEN (sdot.length > osm.length)
				  		THEN ST_distance(
				  			ST_LineInterpolatePoint(ST_LineSubstring( sdot.geom, LEAST(ST_LineLocatePoint(sdot.geom, ST_ClosestPoint(st_startpoint(osm.geom), sdot.geom)) , ST_LineLocatePoint(sdot.geom, ST_ClosestPoint(st_endpoint(osm.geom), sdot.geom))), GREATEST(ST_LineLocatePoint(sdot.geom, ST_ClosestPoint(st_startpoint(osm.geom), sdot.geom)) , ST_LineLocatePoint(sdot.geom, ST_ClosestPoint(st_endpoint(osm.geom), sdot.geom))) ), 0.5), ST_LineInterpolatePoint(osm.geom, 0.5) )
				  	ELSE ST_distance(
				  		ST_LineInterpolatePoint(ST_LineSubstring( osm.geom, LEAST(ST_LineLocatePoint(osm.geom, ST_ClosestPoint(st_startpoint(sdot.geom), osm.geom)) , ST_LineLocatePoint(osm.geom, ST_ClosestPoint(st_endpoint(sdot.geom), osm.geom))), GREATEST(ST_LineLocatePoint(osm.geom, ST_ClosestPoint(st_startpoint(sdot.geom), osm.geom)) , ST_LineLocatePoint(osm.geom, ST_ClosestPoint(st_endpoint(sdot.geom), osm.geom)))) , 0.5), ST_LineInterpolatePoint(sdot.geom, 0.5))
			  	END
		  	) AS RANK
		FROM jolie_sdot2osm_caphill.osm_sidewalk osm
		JOIN jolie_sdot2osm_caphill.sdot_sidewalk sdot
		ON ST_Intersects(ST_Buffer(sdot.geom, sdot.sw_width/3.281, 'endcap=flat join=round'), osm.geom)
		WHERE  osm.osm_id NOT IN (SELECT osm_id FROM jolie_sdot2osm_caphill.osm_connlink) AND 
			   CASE
				  	WHEN (sdot.length > osm.length)
				  		THEN (  ABS(DEGREES(ST_Angle(ST_LineSubstring( sdot.geom, LEAST(ST_LineLocatePoint(sdot.geom, ST_ClosestPoint(st_startpoint(osm.geom), sdot.geom)) , ST_LineLocatePoint(sdot.geom, ST_ClosestPoint(st_endpoint(osm.geom), sdot.geom))), GREATEST(ST_LineLocatePoint(sdot.geom, ST_ClosestPoint(st_startpoint(osm.geom), sdot.geom)) , ST_LineLocatePoint(sdot.geom, ST_ClosestPoint(st_endpoint(osm.geom), sdot.geom))) ), osm.geom))) BETWEEN 0 AND 10 -- 0 
							 OR ABS(DEGREES(ST_Angle(ST_LineSubstring( sdot.geom, LEAST(ST_LineLocatePoint(sdot.geom, ST_ClosestPoint(st_startpoint(osm.geom), sdot.geom)) , ST_LineLocatePoint(sdot.geom, ST_ClosestPoint(st_endpoint(osm.geom), sdot.geom))), GREATEST(ST_LineLocatePoint(sdot.geom, ST_ClosestPoint(st_startpoint(osm.geom), sdot.geom)) , ST_LineLocatePoint(sdot.geom, ST_ClosestPoint(st_endpoint(osm.geom), sdot.geom))) ), osm.geom))) BETWEEN 170 AND 190 -- 180
							 OR ABS(DEGREES(ST_Angle(ST_LineSubstring( sdot.geom, LEAST(ST_LineLocatePoint(sdot.geom, ST_ClosestPoint(st_startpoint(osm.geom), sdot.geom)) , ST_LineLocatePoint(sdot.geom, ST_ClosestPoint(st_endpoint(osm.geom), sdot.geom))), GREATEST(ST_LineLocatePoint(sdot.geom, ST_ClosestPoint(st_startpoint(osm.geom), sdot.geom)) , ST_LineLocatePoint(sdot.geom, ST_ClosestPoint(st_endpoint(osm.geom), sdot.geom))) ), osm.geom))) BETWEEN 350 AND 360 ) -- 360
							 AND ST_Length(ST_LineSubstring( sdot.geom, LEAST(ST_LineLocatePoint(sdot.geom, ST_ClosestPoint(st_startpoint(osm.geom), sdot.geom)) , ST_LineLocatePoint(sdot.geom, ST_ClosestPoint(st_endpoint(osm.geom), sdot.geom))), GREATEST(ST_LineLocatePoint(sdot.geom, ST_ClosestPoint(st_startpoint(osm.geom), sdot.geom)) , ST_LineLocatePoint(sdot.geom, ST_ClosestPoint(st_endpoint(osm.geom), sdot.geom))) )) not BETWEEN (osm.length*0.5) AND (osm.length*1.5)
				  	ELSE 
				  		(   ABS(DEGREES(ST_Angle(ST_LineSubstring( osm.geom, LEAST(ST_LineLocatePoint(osm.geom, ST_ClosestPoint(st_startpoint(sdot.geom), osm.geom)) , ST_LineLocatePoint(osm.geom, ST_ClosestPoint(st_endpoint(sdot.geom), osm.geom))), GREATEST(ST_LineLocatePoint(osm.geom, ST_ClosestPoint(st_startpoint(sdot.geom), osm.geom)) , ST_LineLocatePoint(osm.geom, ST_ClosestPoint(st_endpoint(sdot.geom), osm.geom))) ), sdot.geom))) BETWEEN 0 AND 10 -- 0 
						 OR ABS(DEGREES(ST_Angle(ST_LineSubstring( osm.geom, LEAST(ST_LineLocatePoint(osm.geom, ST_ClosestPoint(st_startpoint(sdot.geom), osm.geom)) , ST_LineLocatePoint(osm.geom, ST_ClosestPoint(st_endpoint(sdot.geom), osm.geom))), GREATEST(ST_LineLocatePoint(osm.geom, ST_ClosestPoint(st_startpoint(sdot.geom), osm.geom)) , ST_LineLocatePoint(osm.geom, ST_ClosestPoint(st_endpoint(sdot.geom), osm.geom))) ), sdot.geom))) BETWEEN 170 AND 190 -- 180
						 OR ABS(DEGREES(ST_Angle(ST_LineSubstring( osm.geom, LEAST(ST_LineLocatePoint(osm.geom, ST_ClosestPoint(st_startpoint(sdot.geom), osm.geom)) , ST_LineLocatePoint(osm.geom, ST_ClosestPoint(st_endpoint(sdot.geom), osm.geom))), GREATEST(ST_LineLocatePoint(osm.geom, ST_ClosestPoint(st_startpoint(sdot.geom), osm.geom)) , ST_LineLocatePoint(osm.geom, ST_ClosestPoint(st_endpoint(sdot.geom), osm.geom))) ), sdot.geom))) BETWEEN 350 AND 360 ) -- 360
						  AND ST_Length(ST_LineSubstring( osm.geom, LEAST(ST_LineLocatePoint(osm.geom, ST_ClosestPoint(st_startpoint(sdot.geom), osm.geom)) , ST_LineLocatePoint(osm.geom, ST_ClosestPoint(st_endpoint(sdot.geom), osm.geom))), GREATEST(ST_LineLocatePoint(osm.geom, ST_ClosestPoint(st_startpoint(sdot.geom), osm.geom)) , ST_LineLocatePoint(osm.geom, ST_ClosestPoint(st_endpoint(sdot.geom), osm.geom))) )) NOT BETWEEN ((sdot.length)*0.5) AND ((sdot.length)*1.5)
			   END AND
			   osm.osm_id NOT IN (SELECT distinct osm_id -- polygon
			   					  FROM jolie_sdot2osm_caphill.polygon_osm_break )
	    )
	SELECT
		  osm_id,
		  sdot_objectid,
		  sdot_segkey,
		  sdot_unitid
		  osm_seg,
		  ST_length(osm_seg),
		  osm_geom,
		  sdot_seg,
		  sdot_geom,
		  sdot_length,
		  ST_length(sdot_geom)
	FROM
		  ranked_roads
	WHERE
		  rank = 1;
		 
-- conflate the adjacent_linestring (osm) to sdot_sidewalk
		 
-- check if it conflate right
-- case: osm > sdot
SELECT sdot_objectid, sdot_segkey, sdot_unitid, COUNT(osm_id) AS noseg, SUM(ST_Length(osm_seg))/sdot_length AS cover, st_linemerge(ST_union(osm_seg), TRUE) AS merge_osm_geom, sdot_geom
FROM jolie_sdot2osm_caphill.sdot2osm_caphill
WHERE osm_seg IS NOT NULL
GROUP BY sdot_objectid, sdot_segkey, sdot_unitid, sdot_length, sdot_geom

SELECT osm_id, COUNT(*) AS noseg, SUM(ST_Length(sdot_seg))/ST_Length(osm_geom) AS cover, st_linemerge(ST_union(sdot_seg), TRUE) AS merge_sdot_geom, osm_geom
FROM jolie_sdot2osm_caphill.sdot2osm_caphill
WHERE osm_seg IS NULL
GROUP BY osm_id, osm_geom


SELECT *
FROM jolie_sdot2osm_caphill.sdot2osm_caphill s1
JOIN (SELECT sdot_objectid, sdot_segkey, sdot_unitid, COUNT(osm_id) AS noseg, SUM(ST_Length(osm_seg))/sdot_length AS cover, st_linemerge(ST_union(osm_seg), TRUE) AS merge_osm_geom, sdot_geom
	FROM jolie_sdot2osm_caphill.sdot2osm_caphill
	WHERE osm_seg IS NOT NULL
	GROUP BY sdot_objectid, sdot_segkey, sdot_unitid, sdot_length, sdot_geom) s2
ON s1.sdot_objectid = s2.sdot_objectid AND s1.sdot_segkey = s2.sdot_segkey AND s1.sdot_unitid =  s2.sdot_unitid

SELECT *
FROM jolie_sdot2osm_caphill.sdot2osm_caphill

SELECT *
FROM sdot.sidewalk_caphill
WHERE (geom) NOT IN 
	( SELECT sdot_geom
	  FROM jolie_sdot2osm_caphill.sdot2osm_caphill )


	--- full data
CREATE TABLE jolie_sdot2osm_caphill.osm_sidewalk AS
	SELECT *
	FROM planet_osm_line pol 
	WHERE   highway='footway' AND tags->'footway'='sidewalk' AND
			way && st_setsrid( st_makebox2d( st_makepoint(-13630776,6020942), st_makepoint(-13605961,6062738)), 3857)
			
ALTER TABLE jolie_sdot2osm_caphill.osm_sidewalk RENAME COLUMN way TO geom;
CREATE INDEX sw_geom ON jolie_sdot2osm_caphill.osm_sidewalk USING GIST (geom);

ALTER TABLE sdot.sidewalks RENAME COLUMN wkb_geometry TO geom;
CREATE INDEX sdot_sw_geom ON sdot.sidewalks USING GIST (geom);


SELECT *
FROM sdot.sidewalks sdot
JOIN jolie_sdot2osm_caphill.osm_sidewalk osm
	 ON ST_Intersects(ST_Buffer(sdot.geom, sw_width/3.281), ST_Buffer(osm.geom, 3))
WHERE st_astext(sdot.geom) != 'LINESTRING EMPTY'
	  AND surftype != 'UIMPRV'
	  AND sw_width != 0


SELECT DISTINCT surftype 
FROM sdot.sidewalks sdot
WHERE st_astext(geom) != 'LINESTRING EMPTY'
	  AND surftype != 'UIMPRV'
	  AND sw_width != 0


SELECT surftype, sw_width, count(*)
FROM sdot.sidewalks sdot
WHERE st_astext(geom) != 'LINESTRING EMPTY'
	  AND sw_width = 0	 
GROUP BY surftype, sw_width

	  
SELECT *
FROM sdot.sidewalks
WHERE surftype = 'PVAS'

SELECT DISTINCT surftype
FROM sdot.sidewalks
WHERE st_astext(geom) != 'LINESTRING EMPTY'

