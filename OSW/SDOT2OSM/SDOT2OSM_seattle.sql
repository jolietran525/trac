----------------------------------------------------
/*                 SIDEWALK DATA                  */
----------------------------------------------------

-- osm sidewalk
CREATE TABLE jolie_sdot2osm_seattle.osm_sidewalk AS
	SELECT *, ST_Length(way) AS length
	FROM planet_osm_line pol 
	WHERE   highway='footway' AND tags->'footway'='sidewalk' AND
			way && st_setsrid( st_makebox2d( st_makepoint(-13616673,6039866), st_makepoint(-13613924,6042899)), 3857); --2385

ALTER TABLE jolie_sdot2osm_seattle.osm_sidewalk RENAME COLUMN way TO geom;
CREATE INDEX sw_geom ON jolie_sdot2osm_seattle.osm_sidewalk USING GIST (geom);




-- sdot sidewalk
--DROP TABLE jolie_sdot2osm_seattle.sdot_sidewalk
CREATE TABLE jolie_sdot2osm_seattle.sdot_sidewalk AS
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

			
CREATE INDEX sdot_seattle_geom ON jolie_sdot2osm_seattle.sdot_sidewalk USING GIST (geom);




----------------------------------------------------
/*                   FUNCTION                     */
----------------------------------------------------


-- this function will take an input of computed angle (_rad) between any 2 linestring, and an input of a tolerence angle threshold (_thresh)
-- to calculate whether or not the computed angle between 2 linestrings are within the threshold so we know if these 2 are parallel
CREATE OR REPLACE FUNCTION public.f_within_degrees(_rad DOUBLE PRECISION, _thresh int) RETURNS boolean AS $$
    WITH m AS (SELECT mod(degrees(_rad)::NUMERIC, 180) AS angle)
        ,a AS (SELECT CASE WHEN m.angle > 90 THEN m.angle - 180 ELSE m.angle END AS angle FROM m)
    SELECT abs(a.angle) < _thresh FROM a;
$$ LANGUAGE SQL IMMUTABLE STRICT;




----------------------------------------------------
/*              PREPROCESSED CASES                */
----------------------------------------------------
-- These are cases where the OSM sidewalks are drawn as a closed linestrings
-- so we want to preprocess these OSM sidewalk segments by:
-- 1. Check which OSM sidewalks are closed linestrings, break these OSM at vertices to sub-seg, number them by the order from start to end points
-- 2. Then check if the sub-seg are adjacent and parallel to each other, we run a procedure to line them up 
-- 3. Finally, for those that's not adjacent and parallel to others, we also want to insert them into the adjacent_parallel table


-- 1. Check which OSM sidewalks are closed linestrings, break these OSM at vertices to sub-seg, number them by the order from start to end points

CREATE TABLE jolie_sdot2osm_seattle.polygon_osm_break AS
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
	            jolie_sdot2osm_seattle.osm_sidewalk
	        WHERE ST_IsClosed(geom)
	        ) AS dumps 
	)
	SELECT 
	    *
	FROM 
	    segments
	WHERE 
	    geom IS NOT NULL; -- 46




-- 2. Then check if the sub-seg are adjacent and parallel to each other, we run a procedure to line them up

CREATE TABLE jolie_sdot2osm_seattle.adjacent_lines AS
	SELECT  p1.osm_id AS osm_id
			,p1.segment_number AS seg_a
			,p1.geom AS geom_a
			,p2.segment_number AS seg_b
			,p2.geom AS geom_b
	FROM jolie_sdot2osm_seattle.polygon_osm_break p1
	JOIN jolie_sdot2osm_seattle.polygon_osm_break p2
	ON p1.osm_id = p2.osm_id AND p1.segment_number < p2.segment_number AND ST_Intersects(p1.geom, p2.geom)
	WHERE  public.f_within_degrees(ST_Angle(p1.geom, p2.geom), 15);





CREATE TABLE jolie_sdot2osm_seattle.adjacent_linestrings (
	osm_id int8 NOT NULL
	,start_seg int8 NOT NULL
	,end_seg int8 NOT NULL
	,geom GEOMETRY(linestring, 3857) NOT NULL
);



-- procedure to iterate over results and join adjacent segments
-- NOTE: if doing for other tables, updte to pass input and output tables and use dynamic SQL
CREATE OR REPLACE PROCEDURE jolie_sdot2osm_seattle.stitch_segments()
LANGUAGE plpgsql AS $$
DECLARE 
	_rec record;
	_first record;
	_prev record;
	_osm_id int8;
BEGIN 
	FOR _rec IN
		SELECT  *
		  FROM  jolie_sdot2osm_seattle.adjacent_lines
	 	ORDER BY osm_id ASC, seg_a ASC, seg_b DESC	-- sort seg_b IN descending order so that first/last segment is first on new osm_id
	 LOOP 
		 IF _first IS DISTINCT FROM NULL OR _prev IS DISTINCT FROM NULL THEN	-- prev or _first record exists 
		 	-- check if current record is same osm_id as previous
		 	IF _rec.osm_id = _osm_id THEN	-- working on same osm_id
		 		-- should we stich to the first or previous segment?
		 		IF _first IS DISTINCT FROM NULL AND _rec.seg_a = _first.seg_a THEN
		 			-- update _first record with info from current record
		 		    _first.geom_a := ST_Linemerge(ST_Union(_first.geom_b,_first.geom_a));
		 			_first.geom_b := _rec.geom_b;
		 			_first.seg_a := _rec.seg_b;
		 		ELSIF _prev IS DISTINCT FROM NULL THEN
		 			IF _rec.seg_a = _prev.seg_b THEN 
			 			-- update previous record with info from current record
			 			_prev.geom_a := ST_Linemerge(ST_Union(_prev.geom_a,_prev.geom_b));
			 			_prev.geom_b := _rec.geom_b;
		 				_prev.seg_b := _rec.seg_b;
		 			ELSE
		 				-- segment is not a continuation of previous; write to table
			 			INSERT INTO jolie_sdot2osm_seattle.adjacent_linestrings VALUES (_prev.osm_id, _prev.seg_a, _prev.seg_b, ST_Linemerge(ST_Union(_prev.geom_a, _prev.geom_b)));
			 			-- set _prev record since 'new' line part
			 			_prev := _rec;
			 		END IF;
			 	ELSE
			 		-- set _prev record since 'new' line part
			 		_prev := _rec;
		 		END IF;
		    ELSE	-- NEW osm_id
		    	-- set new osm_id
		    	_osm_id := _rec.osm_id;
		    	-- check for non-NULL first/last record
		    	-- NOTE: can assume existence of prev when appending first because geometry is a polygon that not all parts can be parallel
		    	IF _first IS DISTINCT FROM NULL THEN
		    		IF _first.seg_b = _prev.seg_b THEN
			    		-- merge _first with _prev and inverst min/max to indicate that it 'wrapped' around the end 
			    		_prev.geom_a := ST_Linemerge(ST_Union(_prev.geom_a,_first.geom_a));		-- e.g., 21 -> 24 + 25 -> 2
			    		_prev.geom_b := _first.geom_b;
		    			_prev.seg_b := _first.seg_a;	-- will 'wrap' around END
		    		ELSE
		    			-- insert first record if not appended with previous at end
			    		INSERT INTO jolie_sdot2osm_seattle.adjacent_linestrings VALUES (_first.osm_id, _first.seg_b, _first.seg_a, ST_Linemerge(ST_Union(_first.geom_a, _first.geom_b)));
			    	END IF;
		    	END IF;
		    	-- write final segment from previous osm_id to table
		    	INSERT INTO jolie_sdot2osm_seattle.adjacent_linestrings VALUES (_prev.osm_id, _prev.seg_a, _prev.seg_b, ST_Linemerge(ST_Union(_prev.geom_a, _prev.geom_b)));
		    	-- check if record is "first/last" record where seg_a is 1 and seg_b is not 2
			 	IF _rec.seg_a = 1 AND _rec.seg_b <> 2 THEN 
			    	 -- set as first record and set prev to NULL
		    		 _first := _rec;
		    		_prev := NULL;
		    	ELSE
		    		-- set _first to NULL and set _prev record since 'new' line part
		    		_first := NULL;
		 			_prev := _rec;
		    	END IF;
		 	END IF;
		 ELSE	-- first record, set _prev OR _first
		 	-- set new osm_id
		    _osm_id := _rec.osm_id;
		 	-- check if first/last record
		 	IF _rec.seg_a = 1 AND _rec.seg_b <> 2 THEN 
		    	 -- set as first record and set prev to NULL
		    	 _first := _rec;
		    	 _prev := NULL;
		   	ELSE
			 	-- set _first to NULL and set _prev record since 'new' line part
		    	_first := NULL;
		 		_prev := _rec;	   	
		   	END IF;
		 END IF;
	 END LOOP;
	
	-- check for first/last record; append to prev if matching; then insert final prev record
    IF _first IS DISTINCT FROM NULL THEN
    	IF _first.seg_b = _prev.seg_b THEN
			-- merge _first with _prev and inverst min/max to indicate that it 'wrapped' around the end 
			_prev.geom_a := ST_Linemerge(ST_Union(_prev.geom_a,_first.geom_a));		-- e.g., 21 -> 24 + 25 -> 2
			_prev.geom_b := _first.geom_b;
			_prev.seg_b := _first.seg_a;	-- will 'wrap' around END
		ELSE
			-- insert first record if not appended with previous at end
			INSERT INTO jolie_sdot2osm_seattle.adjacent_linestrings VALUES (_first.osm_id, _first.seg_b, _first.seg_a, ST_Linemerge(ST_Union(_first.geom_a, _first.geom_b)));
		END IF;
	END IF;
	-- write final segment from previous osm_id to table
	INSERT INTO jolie_sdot2osm_seattle.adjacent_linestrings VALUES (_prev.osm_id, _prev.seg_a, _prev.seg_b, ST_Linemerge(ST_Union(_prev.geom_a, _prev.geom_b)));

END
$$;


CALL jolie_sdot2osm_seattle.stitch_segments();




-- 3. Finally, for those that's not adjacent and parallel to others, we also want to insert them into the adjacent_parallel table

INSERT INTO jolie_sdot2osm_seattle.adjacent_linestrings
	SELECT osm_id, segment_number AS start_seg, segment_number AS end_seg, geom
	FROM jolie_sdot2osm_seattle.polygon_osm_break
	WHERE (osm_id, segment_number) NOT IN
		(
			SELECT osm_id, seg_a AS seg
			FROM jolie_sdot2osm_seattle.adjacent_lines
			UNION ALL
			SELECT osm_id, seg_b AS seg
			FROM jolie_sdot2osm_seattle.adjacent_lines
		);




----------------------------------------------------
/*                   CONFLATION                   */
----------------------------------------------------

-- changes:
-- now creat a table where we union all the osm sidewalks together
-- we will have the columns:
		-- osm_id,
		-- start_end_seg: null if the osm is not preprocessed
		-- geom
		-- length
CREATE TABLE jolie_sdot2osm_seattle.osm_sidewalk_preprocessed AS (
	SELECT osm_id, CONCAT(start_seg, '-', end_seg) AS start_end_seg, geom, ST_Length(geom) AS length
	FROM jolie_sdot2osm_seattle.adjacent_linestrings
	
	UNION ALL 
	
	SELECT osm_id, 'null' AS start_end_seg, geom, ST_Length(geom) AS length
	FROM jolie_sdot2osm_seattle.osm_sidewalk
	WHERE NOT ST_IsClosed(geom) ); -- 2399

	
	

-- changes:
	-- change the osm source table, 
	-- add column start_end_seg,
	-- change the (sdot.length > osm.length*0.85) to (sdot.length > osm.length)
	-- get rid of NOT IN osm_polygon part
	-- buffer size: sdot to 5, osm to 3
	
-- conflation
CREATE TABLE jolie_sdot2osm_seattle.sdot2osm_sw_raw AS (
	WITH ranked_roads AS (
		SELECT 
		  osm.osm_id AS osm_id,
		  osm.start_end_seg AS start_end_seg,
		  sdot.objectid AS sdot_objectid,
		  sdot.sw_width,
		  sdot.surftype, 
		  sdot.cross_slope,
		  sdot.sw_category,
		  osm.geom AS osm_geom,
		  sdot.geom AS sdot_geom,
		  CASE
				WHEN (sdot.length > osm.length) THEN NULL
				ELSE ST_LineSubstring( osm.geom, LEAST(ST_LineLocatePoint(osm.geom, ST_ClosestPoint(st_startpoint(sdot.geom), osm.geom)) , ST_LineLocatePoint(osm.geom, ST_ClosestPoint(st_endpoint(sdot.geom), osm.geom))), GREATEST(ST_LineLocatePoint(osm.geom, ST_ClosestPoint(st_startpoint(sdot.geom), osm.geom)) , ST_LineLocatePoint(osm.geom, ST_ClosestPoint(st_endpoint(sdot.geom), osm.geom))) )
		  END AS osm_seg,
		  CASE
				WHEN (sdot.length > osm.length)
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
				  		THEN 
				  			ST_Area(ST_Intersection(
				  				ST_Buffer(ST_LineSubstring( sdot.geom, LEAST(ST_LineLocatePoint(sdot.geom, ST_ClosestPoint(st_startpoint(osm.geom), sdot.geom)) , ST_LineLocatePoint(sdot.geom, ST_ClosestPoint(st_endpoint(osm.geom), sdot.geom))), GREATEST(ST_LineLocatePoint(sdot.geom, ST_ClosestPoint(st_startpoint(osm.geom), sdot.geom)) , ST_LineLocatePoint(sdot.geom, ST_ClosestPoint(st_endpoint(osm.geom), sdot.geom))) ), sdot.sw_width *5, 'endcap=flat join=round'),
				  				ST_Buffer(osm.geom, 3, 'endcap=flat join=round')
				  			)) 
				  	ELSE
				  		ST_Area(ST_Intersection(
				  				ST_Buffer(ST_LineSubstring( osm.geom, LEAST(ST_LineLocatePoint(osm.geom, ST_ClosestPoint(st_startpoint(sdot.geom), osm.geom)) , ST_LineLocatePoint(osm.geom, ST_ClosestPoint(st_endpoint(sdot.geom), osm.geom))), GREATEST(ST_LineLocatePoint(osm.geom, ST_ClosestPoint(st_startpoint(sdot.geom), osm.geom)) , ST_LineLocatePoint(osm.geom, ST_ClosestPoint(st_endpoint(sdot.geom), osm.geom))) ), 3, 'endcap=flat join=round'),
				  				ST_Buffer(sdot.geom, sdot.sw_width * 5, 'endcap=flat join=round')
				  			)) 
				 END DESC
		  	)  AS RANK
		FROM jolie_sdot2osm_seattle.osm_sidewalk_preprocessed osm
		JOIN jolie_sdot2osm_seattle.sdot_sidewalk sdot
		ON ST_Intersects(ST_Buffer(sdot.geom, sdot.sw_width * 5, 'endcap=flat join=round'), ST_Buffer(osm.geom, 3, 'endcap=flat join=round'))
		WHERE  CASE
				  	WHEN (sdot.length > osm.length)
				  		THEN 
							 public.f_within_degrees(ST_Angle(ST_LineSubstring( sdot.geom, LEAST(ST_LineLocatePoint(sdot.geom, ST_ClosestPoint(st_startpoint(osm.geom), sdot.geom)) , ST_LineLocatePoint(sdot.geom, ST_ClosestPoint(st_endpoint(osm.geom), sdot.geom))), GREATEST(ST_LineLocatePoint(sdot.geom, ST_ClosestPoint(st_startpoint(osm.geom), sdot.geom)) , ST_LineLocatePoint(sdot.geom, ST_ClosestPoint(st_endpoint(osm.geom), sdot.geom))) ), osm.geom), 15)
				  	ELSE -- osm.length > sdot.length
						 public.f_within_degrees(ST_Angle(ST_LineSubstring( osm.geom, LEAST(ST_LineLocatePoint(osm.geom, ST_ClosestPoint(st_startpoint(sdot.geom), osm.geom)) , ST_LineLocatePoint(osm.geom, ST_ClosestPoint(st_endpoint(sdot.geom), osm.geom))), GREATEST(ST_LineLocatePoint(osm.geom, ST_ClosestPoint(st_startpoint(sdot.geom), osm.geom)) , ST_LineLocatePoint(osm.geom, ST_ClosestPoint(st_endpoint(sdot.geom), osm.geom))) ), sdot.geom), 15) 
			   END
	    )
	SELECT
		  osm_id,
		  start_end_seg,
		  sdot_objectid,
		  sw_width,
		  surftype,
		  cross_slope,
		  sw_category,
		  CASE
		  	WHEN osm_seg IS NULL
		  		THEN ST_Length(ST_Intersection(sdot_seg, ST_Buffer(osm_geom, sw_width*8,  'endcap=flat join=round')))/GREATEST(ST_Length(sdot_seg), ST_Length(osm_geom))
		  	ELSE 
		  		ST_Length(ST_Intersection(osm_seg, ST_Buffer(sdot_geom, sw_width*8,  'endcap=flat join=round')))/GREATEST(ST_Length(osm_seg), ST_Length(sdot_geom))
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
		  		THEN ST_Length(ST_Intersection(sdot_seg, ST_Buffer(osm_geom, sw_width*8,  'endcap=flat join=round')))/GREATEST(ST_Length(sdot_seg), ST_Length(osm_geom)) > 0.15 -- TODO: need TO give it a PARAMETER later as we wanna change
		  	ELSE
		  		ST_Length(ST_Intersection(osm_seg, ST_Buffer(sdot_geom, sw_width*8,  'endcap=flat join=round')))/GREATEST(ST_Length(osm_seg), ST_Length(sdot_geom)) > 0.15 -- TODO: need TO give it a PARAMETER later as we wanna change
		  END ); -- 1836








-- This step give us the table while filtering out overlapped segments
		 -- If it overlapps, choose the one thats closer
-- change: the metrics of 0.4
CREATE TABLE jolie_sdot2osm_seattle.sdot2osm_sw_prepocessed AS (
	SELECT  *
	FROM 
	    jolie_sdot2osm_seattle.sdot2osm_sw_raw
	WHERE 
	    (CONCAT(osm_id, start_end_seg), sdot_objectid) NOT IN ( 
	    	-- case when the whole sdot already conflated to one osm, but then its subseg also conflated to another osm
			-- if these 2 osm overlap at least 50% of the shorter one between 2 of them, then we filter out the one that's further away from our sdot
	        SELECT 
				    CONCAT(r1.osm_id, r1.start_end_seg),
				    CASE
				        WHEN r1.sdot_seg IS NULL AND r2.sdot_seg IS NOT NULL
						  	THEN
						  		CASE
						  			WHEN ST_Distance(ST_LineInterpolatePoint(r1.osm_geom, 0.5), ST_LineInterpolatePoint(r1.sdot_geom, 0.5)) < ST_Distance(ST_LineInterpolatePoint(r2.osm_geom, 0.5), ST_LineInterpolatePoint(r2.sdot_seg, 0.5))
							            THEN (r2.sdot_objectid)
							        ELSE (r1.sdot_objectid)
						  		END
					  		
					    WHEN r1.sdot_seg IS NOT NULL AND r2.sdot_seg IS NULL
					  		THEN
					  			CASE 
					  				WHEN ST_Distance(ST_LineInterpolatePoint(r1.osm_geom, 0.5), ST_LineInterpolatePoint(r1.sdot_seg, 0.5)) < ST_Distance(ST_LineInterpolatePoint(r2.osm_geom, 0.5), ST_LineInterpolatePoint(r2.sdot_geom, 0.5))
							            THEN (r2.sdot_objectid)
							        ELSE (r1.sdot_objectid)
							  	END
						  		
						WHEN r1.sdot_seg IS NULL AND r2.sdot_seg IS NULL
					  		THEN
					  			CASE 
					  				WHEN ST_Length(r1.osm_seg) > ST_Length(r2.osm_seg) THEN
	 									CASE
	 										WHEN ST_Distance(ST_LineInterpolatePoint(r1.osm_seg, 0.5), ST_LineInterpolatePoint(r1.sdot_geom, 0.5)) < ST_Distance(ST_LineInterpolatePoint(r1.osm_seg, 0.5), ST_LineInterpolatePoint(r2.sdot_geom, 0.5))
												THEN (r2.sdot_objectid)
											ELSE (r1.sdot_objectid)
	 									END
	 								ELSE 
							        	CASE
	 										WHEN ST_Distance(ST_LineInterpolatePoint(r2.osm_seg, 0.5), ST_LineInterpolatePoint(r1.sdot_geom, 0.5)) < ST_Distance(ST_LineInterpolatePoint(r2.osm_seg, 0.5), ST_LineInterpolatePoint(r2.sdot_geom, 0.5))
												THEN (r2.sdot_objectid)
											ELSE (r1.sdot_objectid)
	 									END
							  	END
				    END AS sdot_objectid
			FROM jolie_sdot2osm_seattle.sdot2osm_sw_raw r1
			JOIN (
			    SELECT *
			    FROM jolie_sdot2osm_seattle.sdot2osm_sw_raw
			    WHERE (osm_id, start_end_seg) IN (
			        SELECT osm_id, start_end_seg
			        FROM jolie_sdot2osm_seattle.sdot2osm_sw_raw
			        GROUP BY osm_id, start_end_seg
			        HAVING count(*) > 1 ) ) r2
			ON r1.osm_id = r2.osm_id AND r1.start_end_seg = r2.start_end_seg AND r1.sdot_objectid < r2.sdot_objectid
			WHERE 
				CASE
					WHEN r1.sdot_seg IS NULL AND r2.sdot_seg IS NOT NULL
					THEN
					  	  ST_Length(
						  	ST_Intersection (
						  		ST_LineSubstring( 
						  			r2.osm_geom,
						  			LEAST(ST_LineLocatePoint(r2.osm_geom, ST_ClosestPoint(st_startpoint(r2.sdot_seg), r2.osm_geom)) , ST_LineLocatePoint(r2.osm_geom, ST_ClosestPoint(st_endpoint(r2.sdot_seg), r2.osm_geom))),
						  			GREATEST(ST_LineLocatePoint(r2.osm_geom, ST_ClosestPoint(st_startpoint(r2.sdot_seg), r2.osm_geom)) , ST_LineLocatePoint(r2.osm_geom, ST_ClosestPoint(st_endpoint(r2.sdot_seg), r2.osm_geom))) )
						  		, ST_Buffer(r1.osm_seg, r1.sw_width*5, 'endcap=flat join=round')))
						  / LEAST(
						  		ST_Length(r1.osm_seg),
						  		ST_Length (
						  		 	ST_LineSubstring( 
							  			r2.osm_geom,
							  			LEAST(ST_LineLocatePoint(r2.osm_geom, ST_ClosestPoint(st_startpoint(r2.sdot_seg), r2.osm_geom)) , ST_LineLocatePoint(r2.osm_geom, ST_ClosestPoint(st_endpoint(r2.sdot_seg), r2.osm_geom))),
							  			GREATEST(ST_LineLocatePoint(r2.osm_geom, ST_ClosestPoint(st_startpoint(r2.sdot_seg), r2.osm_geom)) , ST_LineLocatePoint(r2.osm_geom, ST_ClosestPoint(st_endpoint(r2.sdot_seg), r2.osm_geom))) ) )					  		 
						 ) > 0.4 
						 
					 WHEN r1.sdot_seg IS NOT NULL AND r2.sdot_seg IS NULL
				  	 THEN 
				  	 	  ST_Length(
						  	ST_Intersection (
						  		ST_LineSubstring( 
						  			r1.osm_geom,
						  			LEAST(ST_LineLocatePoint(r1.osm_geom, ST_ClosestPoint(st_startpoint(r1.sdot_seg), r1.osm_geom)) , ST_LineLocatePoint(r1.osm_geom, ST_ClosestPoint(st_endpoint(r1.sdot_seg), r1.osm_geom))),
						  			GREATEST(ST_LineLocatePoint(r1.osm_geom, ST_ClosestPoint(st_startpoint(r1.sdot_seg), r1.osm_geom)) , ST_LineLocatePoint(r1.osm_geom, ST_ClosestPoint(st_endpoint(r1.sdot_seg), r1.osm_geom))) )
						  		, ST_Buffer(r2.osm_seg, r2.sw_width*5, 'endcap=flat join=round')))
						  / LEAST(
						  		ST_Length(r2.osm_seg),
						  		ST_Length (
						  		 	ST_LineSubstring( 
							  			r1.osm_geom,
							  			LEAST(ST_LineLocatePoint(r1.osm_geom, ST_ClosestPoint(st_startpoint(r1.sdot_seg), r1.osm_geom)) , ST_LineLocatePoint(r1.osm_geom, ST_ClosestPoint(st_endpoint(r1.sdot_seg), r1.osm_geom))),
							  			GREATEST(ST_LineLocatePoint(r1.osm_geom, ST_ClosestPoint(st_startpoint(r1.sdot_seg), r1.osm_geom)) , ST_LineLocatePoint(r1.osm_geom, ST_ClosestPoint(st_endpoint(r1.sdot_seg), r1.osm_geom))) ) )					  		 
						 ) > 0.4
					  
					 WHEN r1.sdot_seg IS NULL AND r2.sdot_seg IS NULL
				  	 THEN 
				  	 	  ST_Length(
				  	 	  	ST_Intersection(r1.osm_seg, ST_Buffer(r2.osm_seg, r2.sw_width*5, 'endcap=flat join=round') ) )
				  	 	  / LEAST(
				  	 	  	ST_Length(r1.osm_seg),
				  	 	  	ST_Length(r2.osm_seg))
				  	 	  > 0.4	 	
				END

			
			UNION ALL
			
			-- case when the whole osm already conflated to one sdot, but then its subseg also conflated to another sdot
			-- if these 2 sdot overlap at least 40% of the shorter one between 2 of them, then we filter out the one that's further away from our osm
			SELECT 
				    CASE
				        WHEN r1.sdot_seg IS NOT NULL AND r2.sdot_seg IS NULL 
				        	THEN 
				        		CASE
				        			WHEN ST_Distance(ST_LineInterpolatePoint(r1.osm_geom, 0.5), ST_LineInterpolatePoint(r1.sdot_geom, 0.5)) < ST_Distance(ST_LineInterpolatePoint(r2.osm_seg, 0.5), ST_LineInterpolatePoint(r2.sdot_geom, 0.5))
				            			THEN CONCAT(r2.osm_id, r2.start_end_seg)
				        			ELSE CONCAT(r1.osm_id, r1.start_end_seg)
				        		END
				        
				        WHEN r1.sdot_seg IS NULL AND r2.sdot_seg IS NOT NULL 
				        	THEN 
				        		CASE
				        			WHEN ST_Distance(ST_LineInterpolatePoint(r1.osm_seg, 0.5), ST_LineInterpolatePoint(r1.sdot_geom, 0.5)) < ST_Distance(ST_LineInterpolatePoint(r2.osm_geom, 0.5), ST_LineInterpolatePoint(r2.sdot_geom, 0.5))
				            			THEN CONCAT(r2.osm_id, r2.start_end_seg)
				        			ELSE CONCAT(r1.osm_id, r1.start_end_seg)
				        		END
				       
				        WHEN r1.sdot_seg IS NOT NULL AND r2.sdot_seg IS NOT NULL 
				        	THEN
					  			CASE 
					  				WHEN ST_Length(r1.sdot_seg) > ST_Length(r2.sdot_seg) THEN
	 									CASE
	 										WHEN ST_Distance(ST_LineInterpolatePoint(r1.osm_geom, 0.5), ST_LineInterpolatePoint(r1.sdot_seg, 0.5)) < ST_Distance(ST_LineInterpolatePoint(r2.osm_geom, 0.5), ST_LineInterpolatePoint(r1.sdot_seg, 0.5))
												THEN CONCAT(r2.osm_id, r2.start_end_seg)
											ELSE CONCAT(r1.osm_id, r1.start_end_seg)
	 									END
	 								ELSE 
							        	CASE
	 										WHEN ST_Distance(ST_LineInterpolatePoint(r1.osm_geom, 0.5), ST_LineInterpolatePoint(r2.sdot_seg, 0.5)) < ST_Distance(ST_LineInterpolatePoint(r2.osm_geom, 0.5), ST_LineInterpolatePoint(r2.sdot_seg, 0.5))
												THEN CONCAT(r2.osm_id, r2.start_end_seg)
											ELSE CONCAT(r1.osm_id, r1.start_end_seg)
	 									END
							  	END
				       
				    END AS osm_id_seg,
				    r1.sdot_objectid
			FROM jolie_sdot2osm_seattle.sdot2osm_sw_raw r1
			JOIN (
			        SELECT *
			        FROM jolie_sdot2osm_seattle.sdot2osm_sw_raw
			        WHERE sdot_objectid IN (
			            SELECT sdot_objectid
			            FROM jolie_sdot2osm_seattle.sdot2osm_sw_raw
			            GROUP BY sdot_objectid
			            HAVING count(*) > 1 ) ) r2
			ON r1.sdot_objectid = r2.sdot_objectid AND CONCAT(r1.osm_id, r1.start_end_seg) < CONCAT(r2.osm_id, r2.start_end_seg)
			WHERE 	
				CASE
					WHEN r1.sdot_seg IS NOT NULL AND r2.sdot_seg IS NULL
						THEN 
							ST_Length(
						  		ST_Intersection(
						  			ST_LineSubstring(
						  				r2.sdot_geom,
						  				LEAST(ST_LineLocatePoint(r2.sdot_geom, ST_ClosestPoint(st_startpoint(r2.osm_seg), r2.sdot_geom)) , ST_LineLocatePoint(r2.sdot_geom, ST_ClosestPoint(st_endpoint(r2.osm_seg), r2.sdot_geom))),
						  				GREATEST(ST_LineLocatePoint(r2.sdot_geom, ST_ClosestPoint(st_startpoint(r2.osm_seg), r2.sdot_geom)) , ST_LineLocatePoint(r2.sdot_geom, ST_ClosestPoint(st_endpoint(r2.osm_seg), r2.sdot_geom))) )
						  			, ST_Buffer(r1.sdot_seg, r1.sw_width*5, 'endcap=flat join=round')) )
						  	/LEAST(
						  	  	ST_Length(r1.sdot_seg),
						  	  	ST_Length(
						  	  		ST_LineSubstring(
						  	  			r2.sdot_geom,
						  	  			LEAST(ST_LineLocatePoint(r2.sdot_geom, ST_ClosestPoint(st_startpoint(r2.osm_seg), r2.sdot_geom)) , ST_LineLocatePoint(r2.sdot_geom, ST_ClosestPoint(st_endpoint(r2.osm_seg), r2.sdot_geom))),
						  	  			GREATEST(ST_LineLocatePoint(r2.sdot_geom, ST_ClosestPoint(st_startpoint(r2.osm_seg), r2.sdot_geom)) , ST_LineLocatePoint(r2.sdot_geom, ST_ClosestPoint(st_endpoint(r2.osm_seg), r2.sdot_geom))) )))
					  	    > 0.4
					 
					 WHEN r1.sdot_seg IS NULL AND r2.sdot_seg IS NOT NULL
						THEN 
							ST_Length(
						  		ST_Intersection(
						  			ST_LineSubstring(
						  				r1.sdot_geom,
						  				LEAST(ST_LineLocatePoint(r1.sdot_geom, ST_ClosestPoint(st_startpoint(r1.osm_seg), r1.sdot_geom)) , ST_LineLocatePoint(r1.sdot_geom, ST_ClosestPoint(st_endpoint(r1.osm_seg), r1.sdot_geom))),
						  				GREATEST(ST_LineLocatePoint(r1.sdot_geom, ST_ClosestPoint(st_startpoint(r1.osm_seg), r1.sdot_geom)) , ST_LineLocatePoint(r1.sdot_geom, ST_ClosestPoint(st_endpoint(r1.osm_seg), r1.sdot_geom))) )
						  			, ST_Buffer(r2.sdot_seg, r2.sw_width*5, 'endcap=flat join=round')) )
						  	/LEAST(
						  	  	ST_Length(r2.sdot_seg),
						  	  	ST_Length(
						  	  		ST_LineSubstring(
						  				r1.sdot_geom,
						  				LEAST(ST_LineLocatePoint(r1.sdot_geom, ST_ClosestPoint(st_startpoint(r1.osm_seg), r1.sdot_geom)) , ST_LineLocatePoint(r1.sdot_geom, ST_ClosestPoint(st_endpoint(r1.osm_seg), r1.sdot_geom))),
						  				GREATEST(ST_LineLocatePoint(r1.sdot_geom, ST_ClosestPoint(st_startpoint(r1.osm_seg), r1.sdot_geom)) , ST_LineLocatePoint(r1.sdot_geom, ST_ClosestPoint(st_endpoint(r1.osm_seg), r1.sdot_geom))) )))
					  	    > 0.4
					
					  WHEN r1.sdot_seg IS NOT NULL AND r2.sdot_seg IS NOT NULL
						THEN 
							ST_Length(
						  		ST_Intersection(
						  			r1.sdot_seg,
						  			ST_Buffer(r2.sdot_seg, r2.sw_width*5, 'endcap=flat join=round')) )
						  	/LEAST(
						  	  	ST_Length(r1.sdot_seg),
						  	  	ST_Length(r2.sdot_seg) )
					  	    > 0.4
				END 		
	    	)
	   ); -- 1819
    

	  



-- NOT IMPORTANT --
-- create a table with metrics:
	-- GROUP BY sdot_objectid, the SUM the length of the conflated sdot divided by the length of the original sdot:
			 -- This will give us how much of the sdot got conflated
CREATE TABLE jolie_sdot2osm_seattle.sdot2osm_metrics_sdot AS (
	SELECT  sdot.objectid,
			COALESCE(SUM(ST_Length(sdot2osm.conflated_sdot_seg))/ST_Length(sdot.geom), 0) AS percent_conflated,
			sdot.geom, ST_UNION(sdot2osm.conflated_sdot_seg) AS sdot_conflated_subseg 
	FROM jolie_sdot2osm_seattle.sdot_sidewalk sdot
	LEFT JOIN (
				SELECT *,
						CASE 
							WHEN osm_seg IS NOT NULL
								THEN 
								ST_LineSubstring( sdot_geom, LEAST(ST_LineLocatePoint(sdot_geom, ST_ClosestPoint(st_startpoint(osm_seg), sdot_geom)) , ST_LineLocatePoint(sdot_geom, ST_ClosestPoint(st_endpoint(osm_seg), sdot_geom))), GREATEST(ST_LineLocatePoint(sdot_geom, ST_ClosestPoint(st_startpoint(osm_seg), sdot_geom)) , ST_LineLocatePoint(sdot_geom, ST_ClosestPoint(st_endpoint(osm_seg), sdot_geom))) )
							ELSE sdot_seg
						END conflated_sdot_seg
						
				FROM jolie_sdot2osm_seattle.sdot2osm_sw_prepocessed
			) sdot2osm
	ON sdot.objectid = sdot2osm.sdot_objectid
	GROUP BY sdot.objectid, sdot2osm.sdot_objectid, sdot.geom ); --1229



-- NOT IMPORTANT --
-- create a table with metrics:
	-- GROUP BY osm_id, the SUM the length of the conflated osm divided by the length of the original osm:
			 -- This will give us how much of the osm got conflated
CREATE TABLE jolie_sdot2osm_seattle.sdot2osm_metrics_osm AS (
		SELECT  osm.osm_id,
				COALESCE(SUM(ST_Length(sdot2osm.conflated_osm_seg))/ST_Length(osm.geom), 0) AS percent_conflated,
				osm.geom, ST_UNION(sdot2osm.conflated_osm_seg) AS osm_conflated_subseg
		FROM jolie_sdot2osm_seattle.osm_sidewalk osm
		LEFT JOIN (
					SELECT *,
							CASE 
								WHEN sdot_seg IS NOT NULL
									THEN 
									ST_LineSubstring( osm_geom, LEAST(ST_LineLocatePoint(osm_geom, ST_ClosestPoint(st_startpoint(sdot_seg), osm_geom)) , ST_LineLocatePoint(osm_geom, ST_ClosestPoint(st_endpoint(sdot_seg), osm_geom))), GREATEST(ST_LineLocatePoint(osm_geom, ST_ClosestPoint(st_startpoint(sdot_seg), osm_geom)) , ST_LineLocatePoint(osm_geom, ST_ClosestPoint(st_endpoint(sdot_seg), osm_geom))) )
								ELSE osm_seg
							END conflated_osm_seg
					FROM jolie_sdot2osm_seattle.sdot2osm_sw_prepocessed
				) sdot2osm
		ON osm.osm_id = sdot2osm.osm_id
		GROUP BY osm.osm_id, sdot2osm.osm_id, osm.geom ); -- 2385

    



CREATE TABLE jolie_sdot2osm_seattle.sidewalk AS
	SELECT  osm_id,
			start_end_seg,
		    sdot_objectid,
		    sw_width AS width,
		    CASE WHEN surftype ILIKE 'PCC%' THEN 'concrete'
		         WHEN surftype ILIKE 'AC%' THEN 'asphalt'
		         ELSE 'paved'
		    END AS sdot_surface,
		    hstore(CAST('cross_slope' AS TEXT), CAST(cross_slope AS TEXT)) AS cross_slope,
		    sw_category AS sdot_sw_category,
		    conflated_score,
		    CASE
			    WHEN osm_seg IS NOT NULL
			    	THEN 'no'
		    	WHEN osm_seg IS NULL AND
		    		 NOT ST_Equals(
		    			ST_LineSubstring( osm_geom, LEAST(ST_LineLocatePoint(osm_geom, ST_ClosestPoint(st_startpoint(sdot_seg), osm_geom)) , ST_LineLocatePoint(osm_geom, ST_ClosestPoint(st_endpoint(sdot_seg), osm_geom))), GREATEST(ST_LineLocatePoint(osm_geom, ST_ClosestPoint(st_startpoint(sdot_seg), osm_geom)) , ST_LineLocatePoint(osm_geom, ST_ClosestPoint(st_endpoint(sdot_seg), osm_geom))) ),
		    			osm_geom)
		    		THEN 'no'
		    	ELSE 'yes'
		    END AS original_way,
		    CASE
			    WHEN osm_seg IS NOT NULL
			    	THEN osm_seg
		    	ELSE 
					ST_LineSubstring( osm_geom, LEAST(ST_LineLocatePoint(osm_geom, ST_ClosestPoint(st_startpoint(sdot_seg), osm_geom)) , ST_LineLocatePoint(osm_geom, ST_ClosestPoint(st_endpoint(sdot_seg), osm_geom))), GREATEST(ST_LineLocatePoint(osm_geom, ST_ClosestPoint(st_startpoint(sdot_seg), osm_geom)) , ST_LineLocatePoint(osm_geom, ST_ClosestPoint(st_endpoint(sdot_seg), osm_geom))) )
		    END AS way,
		    osm_geom,
		    sdot_geom
	FROM jolie_sdot2osm_seattle.sdot2osm_sw_prepocessed; -- 1819





-- changes: add start_end_seg, transform geom
-- FINAL TABLE that will be exported
CREATE TABLE jolie_sdot2osm_seattle.sidewalk_json AS (
	SELECT  sdot2osm.osm_id,
			sdot2osm.start_end_seg,
			sdot2osm.sdot_objectid,
			osm.highway,
			osm.surface,
			sdot2osm.sdot_surface,
			sdot2osm.width,
			osm.tags||sdot2osm.cross_slope AS tags,
			conflated_score,
			original_way,
			ST_Transform(sdot2osm.way, 4326) AS way 
	FROM jolie_sdot2osm_seattle.sidewalk sdot2osm
	JOIN jolie_sdot2osm_seattle.osm_sidewalk osm
	ON sdot2osm.osm_id = osm.osm_id -- 1819
	
	UNION
	
	SELECT  pre_osm.osm_id,
			pre_osm.start_end_seg,
			NULL AS sdot_objectid,
			osm.highway,
			osm.surface,
			NULL AS sdot_surface,
			NULL AS width,
			osm.tags,
			NULL AS conflated_score,
			CASE
				WHEN start_end_seg != 'null'
					THEN 'no'
				ELSE 'yes'
			END AS original_way,
			ST_Transform(pre_osm.geom, 4326) AS way
	FROM jolie_sdot2osm_seattle.osm_sidewalk osm
	JOIN jolie_sdot2osm_seattle.osm_sidewalk_preprocessed pre_osm
	ON osm.osm_id = pre_osm.osm_id
	WHERE (pre_osm.osm_id, pre_osm.start_end_seg) NOT IN (
			SELECT DISTINCT osm_id, start_end_seg
			FROM jolie_sdot2osm_seattle.sidewalk ) -- 707
	); --2526
	  

	
----------------------------------------------------
/*                 CROSSING DATA                  */
----------------------------------------------------
CREATE TABLE jolie_sdot2osm_seattle.osm_crossing AS
	SELECT *
	FROM planet_osm_line pol 
	WHERE   highway='footway' AND tags->'footway'='crossing' AND
			way && st_setsrid( st_makebox2d( st_makepoint(-13616673,6039866), st_makepoint(-13613924,6042899)), 3857); --1034

ALTER TABLE jolie_sdot2osm_seattle.osm_crossing RENAME COLUMN way TO geom;
CREATE INDEX crossing_geom ON jolie_sdot2osm_seattle.osm_crossing USING GIST (geom);
			
			
			
CREATE TABLE jolie_sdot2osm_seattle.sdot_accpedsig AS
	SELECT *
	FROM sdot.accessible_pedestrian_signals aps
	WHERE  wkb_geometry && st_setsrid( st_makebox2d( st_makepoint(-13616673,6039866), st_makepoint(-13613924,6042899)), 3857); -- 22

ALTER TABLE jolie_sdot2osm_seattle.sdot_accpedsig RENAME COLUMN wkb_geometry TO geom;
	

-- test and see which buffer size works
SELECT osm.geom, sdot.geom, ST_Buffer(osm.geom, 10, 'endcap=flat join=round'), ST_Buffer(sdot.geom, 20)
FROM jolie_sdot2osm_seattle.osm_crossing osm 
JOIN jolie_sdot2osm_seattle.sdot_accpedsig sdot
ON ST_Intersects(ST_Buffer(osm.geom, 10, 'endcap=flat join=round'), ST_Buffer(sdot.geom, 20))


-- FINAL TABLE
-- changes: transform, buffer size
CREATE TABLE jolie_sdot2osm_seattle.crossing_json AS (
	SELECT 
		osm.osm_id, osm.highway,
		(osm.tags ||
		hstore('crossing', 'marked') || 
		hstore('crossing:signals', 'yes') ||
		hstore('crossing:signals:sound', 'yes') ||
		hstore('crossing:signals:button_operated', 'yes') ||
		hstore('crossing:signals:countdown', 'yes')) AS tags,
		ST_Transform(osm.geom, 4326) AS way
	FROM (SELECT osm.osm_id, osm.highway, osm.tags, osm.geom
		FROM jolie_sdot2osm_seattle.osm_crossing osm 
		JOIN jolie_sdot2osm_seattle.sdot_accpedsig sdot
		ON ST_Intersects(ST_Buffer(osm.geom, 10, 'endcap=flat join=round'), ST_Buffer(sdot.geom, 20))
		) osm
	
	UNION
	
	-- IF the crossing did NOT conflate:
	SELECT osm.osm_id, osm.highway, osm.tags, ST_Transform(osm.geom, 4326) AS way
	FROM jolie_sdot2osm_seattle.osm_crossing osm
	WHERE osm.osm_id NOT IN (
		SELECT osm.osm_id
		FROM jolie_sdot2osm_seattle.osm_crossing osm 
		JOIN jolie_sdot2osm_seattle.sdot_accpedsig sdot
		ON ST_Intersects(ST_Buffer(osm.geom, 10, 'endcap=flat join=round'), ST_Buffer(sdot.geom, 20))) ); -- 1034