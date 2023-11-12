# About the Project
The Transportation Data Equity Initiative project is led by the Taskar Center for Accessible Technology (TCAT) and co-investigated by the Washington State Transportation Center (TRAC) at the University of Washington. This initiative aims to provide detailed, accurate data about pedestrian spaces, effectively bridging the gap between existing data and the real-world needs of those with mobility challenges.

This project recognizes the vital role of detailed and accurate data concerning pedestrian spaces, travel environments, and travel services in trip planning, concierge services, and mobile wayfinding applications. We realize that data on pedestrian spaces must be as descriptive and specific as possible. For instance, instead of labeling a path 'wheelchair accessible,' we need to "store data on its steepness and interpret it based on rules like 'no steepness greater than eight percent'". We will deploy this project in six counties: two each in Maryland, Oregon, and Washington state.

# My Role
As a GIS Analyst at TRAC, my role serves the purpose of automating the process of collecting and intergrating data from publicly available transportation data into OpenStreetMap (OSM) so that we have a more comprehensive sidewalk dataset that is openly available.

# My Conflation Attempts
Here are the conflation attempts that I have been working on:
1. ARNOLD-OSM
    The following process is designed to conflate two networks: OpenStreetMap (OSM) and All Roads Network Of Linear Referenced Data (ARNOLD). These two networks contain sidewalk data (OSM) and street data (ARNOLD). The outcome of the process can be used for multiple purposes, including: 
    * Vetting of data by finding inconsistencies between two datasets 
    * Allowing for transfer from one dataset to another by identifying comparable network segments and nodes 
    * Identifying parallel and associated network segments (e.g. in this case, which roadway segments should be associated with which sidewalk segments and vice versa)
2. SDOT-OSM
    The following process is designed to conflate two networks: OpenStreetMap (OSM) and Seattle Department of Transportation (SDOT). The networks include two alternative sidewalk networks, and one crossing network versus one accessible pedestrian signal network. The outcome of the process can be used for multiple purposes, including: 
    * Vetting of data by finding inconsistencies between two datasets 
    * Allowing for transfer from one dataset to another by identifying comparable network segments and nodes 
    * Identifying parallel and associated network segments (e.g., which sidewalks segments in this network should be associated with which sidewalk segments in another network and vice versa.)  

