-- axplore the wapr table
select count(distinct routeid)
from arnold.wapr_hpms_submittal

-- since it is in multistringm format, we want to convert to linestring
CREATE TABLE arnold.wapr_linestring (
  objectid SERIAL PRIMARY KEY,
  og_objectid INT8,
  routeid VARCHAR(75),
  beginmeasure FLOAT8,
  endmeasure FLOAT8,
  shape_length FLOAT8,
  geom geometry(linestring, 3857)
);

-- Step 2: Convert the MultiLineString geometries into LineString geometries
INSERT INTO arnold.wapr_linestring (og_objectid, routeid, beginmeasure, endmeasure, shape_length, geom)
SELECT objectid, routeid, beginmeasure, endmeasure, shape_length, ST_Force2D((ST_Dump(shape)).geom)::geometry(linestring, 3857)
FROM arnold.wapr_hpms_submittal;

select count(*)
from arnold.wapr_linestring  -- 159732

select count(distinct routeid)
from arnold.wapr_linestring -- 159207

select count(*)
from arnold.wapr_hpms_submittal -- 159434


select count(distinct routeid )
from arnold.wapr_hpms_submittal -- 159207

-- error with converting the length of the line/mul, so let's not involve any length in this
