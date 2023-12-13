# About the Project: Transportation Data Equity Initiative

In the dynamic realm of accessible technology, the Transportation Data Equity Initiative is a groundbreaking project led by the Taskar Center for Accessible Technology (TCAT) in collaboration with the Washington State Transportation Center (TRAC) at the University of Washington. Our mission is clear: to bridge the gap between existing data and the real-world needs of individuals facing mobility challenges.

## The Challenge: Enhancing Pedestrian Spaces Through Data Precision

Recognizing the pivotal role of accurate data in trip planning, concierge services, and mobile wayfinding applications, our initiative focuses on refining data related to pedestrian spaces. We go beyond mere labels, insisting on granularity, such as storing data on the steepness of paths with rules like 'no steepness greater than eight percent.' This meticulous approach ensures that our data serves the diverse needs of individuals with mobility challenges. Our scope extends across six counties, with targeted deployment in Maryland, Oregon, and Washington state.

## My Role as a GIS Analyst at TRAC:

In my capacity as a GIS Analyst at TRAC, I play a key role in automating the collection and integration of publicly available transportation data into OpenStreetMap (OSM). This initiative aims to create a more comprehensive and openly accessible sidewalk dataset, addressing the specific needs of our community.

## Conflation Attempts: Navigating Complex Networks

I have been actively engaged in three significant conflation attempts, each designed to harmonize diverse datasets and enhance the quality of sidewalk information.

### 1. ARNOLD-OSM Conflation:
   - **Purpose:** The primary goal is to identify the sidewalk segments in OpenStreetMap (OSM) that associate with a single road segment in the All Roads Network Of Linear Referenced Data (ARNOLD). This process allows us to extract traffic volume information from ARNOLD and incorporate it into our OSM sidewalk data as a new tag, utilizing the hstore data type. From the OSM perspective, this results in an additional attribute of traffic volume for sidewalk segments, providing valuable data for assessing safety when a pedestrian crosses the road. Simultaneously, we share the conflation result with ARNOLD stakeholders, enhancing their awareness of sidewalk locations and distribution.
   - **My Contribution:** Design a procedure in PostgreSQL that does the following:
      1. **Initialization:**
         - Set up the databases and necessary software tools.
         - Load the networks (OSM and ARNOLD) into the database.
      2. **Preprocessing:**
         - Subsegment the original network segments for better conflation.
      3. **Spatial Joins:**
         - Perform spatial joins using combined methods to create conflation tables.
      4. **Parallelism Checks:**
         - Check for parallelism between associated geometries to ensure proper conflation.
      5. **Conflation Table Generation:**
         - Generate conflation tables containing the relationships between sidewalk and roadway segments.
      6. **Quality Assurance:**
         - Review and validate the conflation results.
   - **Read more about this conflation attempt:** [ARNOLD2OSM: Conflation Explanaion](ARNOLD2OSM/ConflationExplain.md)


### 2. SDOT-OSM Conflation:
   - **Purpose:** The primary goal is to:
      1. Identify Seattle sidewalks in OpenStreetMap (OSM) corresponding to the Seattle Department of Transportation (SDOT) sidewalk datasets. Attributes like sidewalk width, slope, and surface type from SDOT are integrated into OSM sidewalk data. Additionally, we aim to identify sidewalk segments in SDOT that do not exist in OSM and those that are in OSM but not in SDOT, facilitating data enrichment in both OSM and SDOT.
      2. Pinpoint intersections in Seattle with Accessible Pedestrian Signals (APS) using SDOT's APS dataset. Then, update or add tags to OSM crossings at these intersections to reflect the latest status accurately.
   - **My Contribution:** Developed PostgreSQL procedures for conflation, including:
      1. **Initialization:**
         - Set up PostgreSQL databases and required software tools.
         - Load SDOT and Seattle OSM sidewalk networks into the database.
      2. **Preprocessing OSM Sidewalks:**
         - Address scenarios where sidewalk segments are represented as closed line strings in the OSM dataset.
         - Subsegment original network segments, enhancing conflation accuracy.
      3. **Preprocessing SDOT Sidewalks:**
         - Address the scenarios where the SDOT sidewalks are stored as MultiLinestring instead of Linestring, which would cause errors in performing spatial analysis due to a mismatch of datatype.
         - Use `ST_Dump` to convert the MultiLinestring into Linestring.
      5. **Spatial Joins:**
         - Execute spatial joins incorporating various methods (`ST_Buffer` and `ST_Intersects`) to create an initial link between SDOT and OSM sidewalks datasets based on distance.
      6. **Segmentize and Parallelism Checks:**
         - Take the shorter segment between the two sidewalks (either SDOT or OSM) that is linked from the previous step, and project it onto the longer one based on the start and end point of the shorter segment. That results in a subsegment of a longer segment that is based upon the geometry of the shorter one.
         - Ensure geometrical parallelism by checking if the angle between the sidewalk segment and the subsegment is within a certain threshold to make sure this sidewalk in OSM is the exact sidewalk in SDOT.
      7. **Quality Assurance:**
         - Develop a conflation score system to automatically reject the conflation result that has a low score.
         - Review and validate conflation procedure (keep improving the procedure above) and results (develop a [web map interface](https://jolietran525.github.io/trac-leaflet-map/index.html)), ensuring accuracy in matched sidewalk attributes.
      8. **Conflation Table Generation:**
         - Generate conflation tables containing relationships between OSM and SDOT sidewalk segments.
      9. **Identify APS Locations:**
         - Utilize SDOT's Accessible Pedestrian Signals (APS) dataset to pinpoint intersections in Seattle with APS.
      9 **Update OSM Crossings:**
         - Update or add tags to OSM crossings at identified intersections, reflecting the latest status accurately.
   - **Read more about this conflation attempt:** [SDOT2OSM: Conflation Details](SDOT2OSM/ConflationDetails.md)


### 3. OSM Roads to Sidewalks \[ongoing\]:



## Technical Proficiency:

My work encompasses a range of technical skills, including:
- expertise in GIS tools
- **Logical Reasoning and Problem Solving:** Define a set of rules for data cleaning, data transformation, and data alignment from disparate source, solve the challenges with prom
By leveraging these skills, I contribute to the creation of a robust and reliable sidewalk dataset that serves the diverse needs of our community.

## Results and Future Steps:

The conflation processes I led have yielded tangible outcomes, including enhanced data accuracy and improved accessibility information. As we move forward, I remain committed to refining and expanding our dataset by building up the conflation reviewing tool using Leaflet, ensuring its ongoing relevance and impact.

This portfolio is a testament to my dedication to leveraging technology for social good, and I am excited about the potential for positive change that our work in the Transportation Data Equity Initiative brings to communities facing mobility challenges.
