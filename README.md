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
      - Perform spatial joins using the methods described earlier to create conflation tables.
   4. **Parallelism Checks:**
      - Check for parallelism between associated geometries to ensure proper conflation.
   5. **Conflation Table Generation:**
      - Generate conflation tables containing the relationships between sidewalk and roadway segments.
   6. **Quality Assurance:**
      - Review and validate the conflation results.
   7. **Export Data:**
      - Export the conflation results in database or GeoJSON formats.
   **Read more about this attemp:** [ARNOLD2OSM: Conflaion Explanaion](ARNOLD2OSM/ConflationExplain.md)


### 2. SDOT-OSM Conflation:
   - **Purpose:** Identify inconsistencies, facilitate data transfer, and pinpoint associated network segments.
   - **My Contribution:** Through a meticulous process, I navigated the conflation of OpenStreetMap (OSM) with the Seattle Department of Transportation (SDOT) data. This resulted in an enriched dataset, facilitating improved accessibility information and contributing to the overall success of our initiative.

## Technical Proficiency:

My work encompasses a range of technical skills, including expertise in GIS tools, data integration, and conflation techniques. By leveraging these skills, I contribute to the creation of a robust and reliable sidewalk dataset that serves the diverse needs of our community.

## Results and Future Steps:

The conflation processes I led have yielded tangible outcomes, including enhanced data accuracy and improved accessibility information. As we move forward, I remain committed to refining and expanding our dataset, ensuring its ongoing relevance and impact.

This portfolio is a testament to my dedication to leveraging technology for social good, and I am excited about the potential for positive change that our work in the Transportation Data Equity Initiative brings to communities facing mobility challenges.
