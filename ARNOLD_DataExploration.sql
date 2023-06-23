-- axplore the wapr table
select count(distinct routeid)
from arnold.wapr_hpms_submittal

-- since it is in multistringm format, we want to convert to linestring
-- Step 1: Create a new table with the desired geometry type
CREATE TABLE arnold.wapr_linestring (
  objectid SERIAL PRIMARY KEY,
  routeid VARCHAR(75),
  beginmeasure FLOAT8,
  endmeasure FLOAT8,
  shape_length FLOAT8,
  geom geometry(linestring, 3857)
);

-- Step 2: Convert the MultiLineString geometries into LineString geometries
INSERT INTO arnold.wapr_linestring (routeid, beginmeasure, endmeasure, shape_length, geom)
SELECT routeid, beginmeasure, endmeasure, shape_length, ST_Force2D((ST_Dump(shape)).geom)::geometry(linestring, 3857)
FROM arnold.wapr_hpms_submittal;

alter table arnold.wapr_linestring
drop shapelength_line;

alter table arnold.wapr_linestring
add shapelength_line FLOAT8;

INSERT INTO arnold.wapr_linestring (shapelength_line)
select ST_length(geom)
from wapr_linestring;


select count(*)
from arnold.wapr_linestring  -- 159732

select count(distinct routeid)
from arnold.wapr_linestring -- 159207

select count(*)
from arnold.wapr_hpms_submittal -- 159434

select count(distinct routeid )
from arnold.wapr_hpms_submittal -- 159207

select *
from arnold.wapr_hpms_submittal
where st_astext(shape) ilike '%multilinestring%' -- 159434

select count(*) 
from arnold.wapr_hpms_submittal
where st_astext(shape) ilike '%multilinestring%' -- 159434

-- check duplicate
select geom, count(*)
from arnold.wapr_linestring
group by geom, shape_length 
having count(*)>1

SELECT routeid, COUNT(*) AS count
  FROM arnold.wapr_hpms_submittal 
  GROUP BY routeid
  HAVING COUNT(*) > 1



WITH routeid_dup AS (
  SELECT routeid, COUNT(*) AS count
  FROM arnold.wapr_linestring
  GROUP BY routeid
  HAVING COUNT(*) > 1
)
SELECT *
FROM arnold.wapr_linestring wl
JOIN routeid_dup dup ON dup.routeid = wl.routeid
order by wl.routeid;
		
select *
from arnold.wapr_linestring
where geom IN (select geom
				from arnold.wapr_linestring as count_dup
				group by geom, shape_length 
				having count(*)>1)

-- error with converting the length of the line/mul, so let's not involve any length in this
