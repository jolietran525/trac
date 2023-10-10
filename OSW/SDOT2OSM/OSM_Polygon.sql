CREATE TABLE jolie_sdot2osm_caphill.polygon_osm_break AS
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
	            jolie_sdot2osm_caphill.osm_sidewalk
	        WHERE ST_StartPoint(geom) = ST_Endpoint(geom)
	        ) AS dumps 
	)
	SELECT 
	    *
	FROM 
	    segments
	WHERE 
	    geom IS NOT NULL;
    

	   
	   
-- function to determine if an angle is within limit threshold
CREATE OR REPLACE FUNCTION public.f_within_degrees(_rad DOUBLE PRECISION, _thresh int) RETURNS boolean AS $$
    WITH m AS (SELECT mod(degrees(_rad)::NUMERIC, 180) AS angle)
        ,a AS (SELECT CASE WHEN m.angle > 90 THEN m.angle - 180 ELSE m.angle END AS angle FROM m)
    SELECT abs(a.angle) < _thresh FROM a;
$$ LANGUAGE SQL IMMUTABLE STRICT;




CREATE TABLE jolie_sdot2osm_caphill.adjacent_lines AS
	SELECT  p1.osm_id AS osm_id
			,p1.segment_number AS seg_a
			,p1.geom AS geom_a
			,p2.segment_number AS seg_b
			,p2.geom AS geom_b
	FROM jolie_sdot2osm_caphill.polygon_osm_break p1
	JOIN jolie_sdot2osm_caphill.polygon_osm_break p2
	ON p1.osm_id = p2.osm_id AND p1.segment_number < p2.segment_number AND ST_Intersects(p1.geom, p2.geom)
	WHERE  public.f_within_degrees(ST_Angle(p1.geom, p2.geom), 15);





-- note to self for a minute: when updating _prev, update _first instead if it exists but only when not written
CREATE TABLE jolie_sdot2osm_caphill.adjacent_linestrings (
	osm_id int8 NOT NULL
	,start_seg int8 NOT NULL
	,end_seg int8 NOT NULL
	,geom GEOMETRY(linestring, 3857) NOT NULL
);



-- procedure to iterate over results and join adjacent segments
-- NOTE: if doing for other tables, updte to pass input and output tables and use dynamic SQL
CREATE OR REPLACE PROCEDURE jolie_sdot2osm_caphill.stitch_segments()
LANGUAGE plpgsql AS $$
DECLARE 
	_rec record;
	_first record;
	_prev record;
	_osm_id int8;
BEGIN 
	FOR _rec IN
		SELECT  *
		  FROM  jolie_sdot2osm_caphill.adjacent_lines
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
			 			INSERT INTO jolie_sdot2osm_caphill.adjacent_linestrings VALUES (_prev.osm_id, _prev.seg_a, _prev.seg_b, ST_Linemerge(ST_Union(_prev.geom_a, _prev.geom_b)));
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
			    		INSERT INTO jolie_sdot2osm_caphill.adjacent_linestrings VALUES (_first.osm_id, _first.seg_b, _first.seg_a, ST_Linemerge(ST_Union(_first.geom_a, _first.geom_b)));
			    	END IF;
		    	END IF;
		    	-- write final segment from previous osm_id to table
		    	INSERT INTO jolie_sdot2osm_caphill.adjacent_linestrings VALUES (_prev.osm_id, _prev.seg_a, _prev.seg_b, ST_Linemerge(ST_Union(_prev.geom_a, _prev.geom_b)));
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
			INSERT INTO jolie_sdot2osm_caphill.adjacent_linestrings VALUES (_first.osm_id, _first.seg_b, _first.seg_a, ST_Linemerge(ST_Union(_first.geom_a, _first.geom_b)));
		END IF;
	END IF;
	-- write final segment from previous osm_id to table
	INSERT INTO jolie_sdot2osm_caphill.adjacent_linestrings VALUES (_prev.osm_id, _prev.seg_a, _prev.seg_b, ST_Linemerge(ST_Union(_prev.geom_a, _prev.geom_b)));

END
$$;


CALL jolie_sdot2osm_caphill.stitch_segments();



SELECT * FROM jolie_sdot2osm_caphill.adjacent_linestrings



INSERT INTO jolie_sdot2osm_caphill.adjacent_linestrings
	SELECT osm_id, segment_number AS start_seg, segment_number AS end_seg, geom
	FROM jolie_sdot2osm_caphill.polygon_osm_break
	WHERE (osm_id, segment_number) NOT IN
		(
			SELECT osm_id, seg_a AS seg
			FROM jolie_sdot2osm_caphill.adjacent_lines
			UNION ALL
			SELECT osm_id, seg_b AS seg
			FROM jolie_sdot2osm_caphill.adjacent_lines
		)

		

