# Introduction

The following process is designed to conflate two networks: OpenStreetMap (OSM) and All Roads Network Of Linear Referenced Data (ARNOLD). These two networks contain sidewalk data (OSM) and street data (ARNOLD). The outcome of the process can be used for multiple purposes, including:

- Vetting of data by finding inconsistencies between two datasets
- Allowing for transfer from one dataset to another by identifying comparable network segments and nodes
- Identifying parallel and associated network segments (e.g. which roadway segments should be associated with which sidewalk segments and vice versa)

The initial outcome is a “conflation table” (or set of tables) that describe the relationship between two different network databases that serve as primary keys into those databases.

The process of associating sidewalk segments with their corresponding roadway segments from two distinct networks is complicated by several facets of network design.

For both networks, roadways are not always segmented conveniently for a straightforward conflation process. In this specific case, for example, OSM segmentation does not always break at intersections. This leads to many-to-many relationships between segments in the networks being conflated.

This requires sub-segmentation of the original network segments and tracking the parent/child relationships between these segments. The OpenSidewalks (OSW) network design contains a variety of specific link (edge/way) coding designs that complicate the conflation process.

For example, there is a “connecting link” which connects the node at the end of a sidewalk centerline to the roadway right-of-way when a crossing of a street is being coded between sidewalks on either side of a street.

There are OSM sidewalk segments we have termed “stubs” or “entrances” which represent the path to be taken into land parcels from sidewalk centerlines. These sidewalk segments have been identified and are tracked but are not conflated at this time.

Additional tables and data fields are needed to store data contained in those asset management systems due to the convoluted process of connecting OSW and OSM networks and then further connecting those networks to city/county asset management systems.

Once conflated and transferred between datasets, these data can then be exported out in either database or GeoJSON formats as desired.

## Process Terminologies

**Spatial join by intersection of buffers:**
This method is used to join two networks by their geometries and based on how their geometries interact. Specifically, we narrow our association to the geometries that indicate any interaction between each other once buffered.

For example, given 2 geometries from each network (OSM and ARNOLD), we check to see if a certain ARNOLD road is associated with an OSM sidewalk. However, these 2 geometries do not intersect directly with each other as their raw geometries, rightfully so as we would expect roads to not intersect with sidewalks. However, we can assume that the sidewalk associated with a road and vice versa would be within a certain vicinity of each other. Therefore we buffer the road and the sidewalk, and see if these buffers intersect. This narrows the possibilities of what constitutes a more accurate conflation between the sidewalk and road data.

*Figure 1: ARNOLD road sub-segment (red) and OSM sidewalk (blue)*

![Figure 1](URL to Figure 1 image)

*Figure 2: Buffer of the same ARNOLD road sub-segment (dark-red polygon) intersecting with buffer of the same OSM sidewalk (orange polygon)*

![Figure 2](URL to Figure 2 image)

**Spatial join by intersection of two geometries:**
This method is used to join two networks by their geometries and based on how their geometries interact. In this case, we do focus on the raw geometries given to us from each database and see if there is a direct interaction, or intersection. This method is used in associating crossings, for example, to ARNOLD roads as shown below because unlike sidewalks, crossings are footways that do/should intersect with road data.

*Figure 3: OSM crossing (blue) intersecting ARNOLD road (red)*

![Figure 3](URL to Figure 3 image)

**Checking for Parallel (Angle Similarity):**
This method is used to join two networks by their geometries and based on how similar their geometries are to one another. In this case, we narrow down our association by checking the angle between the two geometries to make sure they are parallel, or near parallel with a defined leniency value, to each other. This would mean they have an angle around 0, 180, or 360 degrees between each other.

It is important to note that two networks (e.g., OSM and ARNOLD) are quite different in segment length and shape, i.e., ARNOLD’s road geometry can be very long compared to a sidewalk or a road segment in OSM as it represents a continuation of one big road, especially if it is an interstate highway.

*Figure 7: ARNOLD road (red) with long geometry covering different blocks and an OSM sidewalk segment (blue)*

![Figure 7](URL to Figure 7 image)

Therefore, if we check to see if 2 Linestring geometries from both databases are parallel to each other without some leniency, it would be highly unlikely that these geometries would ever meet the criterion and be matched.

We try to account for this by developing a method to check if two geometries are similar or parallel to each other by checking the angle between the two segments.

*Figure 8: ARNOLD road (red) and OSM sidewalk segment (blue) having an angle between them that falls within the acceptable leniency range*

![Figure 8](URL to Figure 8 image)

# Conflation Flow

The general flow of the conflation process is as follows:

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

# Conflation of General Cases

The conflation of general cases involves the steps outlined in the general conflation flow. This includes the initialization, preprocessing, spatial joins, parallelism checks, conflation table generation, quality assurance, and data export.

# Conflation of Weird Cases

The conflation of weird cases involves additional steps and considerations due to specific network designs or anomalies. These cases may require special attention and manual intervention to ensure accurate conflation results.

1. **Identify Weird Cases:**
   - Recognize network segments that deviate from the general conflation process.

2. **Custom Processing:**
   - Implement custom processing steps to address the peculiarities of weird cases.

3. **Manual Intervention:**
   - Manually review and intervene in the conflation process for weird cases.

4. **Verification:**
   - Verify the conflation results for weird cases to ensure accuracy.

# Conclusion

The conflation process between OSM and ARNOLD networks involves a systematic approach to associate sidewalk and roadway segments. By leveraging spatial joins, parallelism checks, and conflation tables, the process aims to create a reliable relationship between the two networks for various use cases. The conflation flow, including general cases and weird cases, provides a comprehensive guide to handling different scenarios in the conflation process.