#####################################
# get_value.jl
# Author: Hakan Ergun 24.03.2022
# Functions to extract hourly demand and installed generation capacity
#######################################

# Gets hourly demand data from dataframe demand
# area{String} ... name of zone, e.g. "AL00"
# hour{Int} selected hour {1,2, ...., 8760}
function get_demand_data(demand, area, hour)
    if    sum(names(demand) .== area) !=0
        value = demand[!, area][hour]
    else
        value = 0
    end
       
    return value
end

"""
    get_demand_data_ext(orig_demand, demand, nodes, area, scenario, year, climate_year)

Compute a scaled electricity demand time series (in MWh) for a specific area based on a given scenario, year, and climate year.

- Arguments
    - `orig_demand`: Original hourly electricity demand per area (in MWh), with 8760 rows for each area.
    - `demand`: Scenario-based demand values (in GWh) including country, node type, scenario, year, and climate year.
    - `nodes`: A two-column matrix mapping area codes to country names.
    - `area`: The specific area code for which the demand time series is requested.
    - `scenario`: Scenario short code ("DE", "GA", or "NT"), which will be expanded to the full scenario name.
    - `year`: Target simulation year (e.g., "2030").
    - `climate_year`: Climate reference year (e.g., "2008").

- Output
    - `Vector{Float64}`: A vector of 8760 values representing the scaled electricity demand time series for the specified area.

- Description
    This function:
    1. Translates scenario codes to full scenario names.
    2. Maps area codes to country names, including manual overrides for special cases (e.g., different Denmark codes).
    3. Identifies all area codes belonging to the same country as the given area.
    4. Calculates the total real (historical/original) electricity demand of that country by summing the values of all relevant areas.
    5. Extracts the demand time series for the specified area (if present).
    6. Filters the demand scenario data for the relevant country, scenario, year, and climate year.
    7. Computes the total scenario-based demand for the country and scales the original area's time series accordingly.

    If the original area demand is missing, a zero time series is returned. If the scenario demand is missing, the scaling ratio is zero.
"""

function get_demand_data_ext(orig_demand,demand,nodes,area,scenario,year,climate_year)
    
    # Translate short scenario codes to full names
    if scenario == "DE"
        scenario = "Distributed Energy"
    elseif scenario == "GA"
        scenario = "Global Ambition"
    elseif scenario == "NT"
        scenario = "National Trends"
    end

    # Create a mapping from area/node codes to country names
    country_names =  Dict{String,Any}()
    for i_idx in 1:length(nodes[:,1])
        i = nodes[i_idx,1]
        country_names[i] = nodes[i_idx,2]
    end

    
    # Manually override/add some specific area-to-country mappings because Denmark was written differently in the data
    country_names["DKE1"] = "Denmark"
    country_names["DKW1"] = "Denmark"
    country_names["DKKF"] = "Denmark"
    country_names["DEKF"] = "Denmark"
    country_names["DK00"] = "Denmark"
    country_names["UKNI"] = "United Kingdom"
    country_names["GR03"] = "Greece"
    country_names["FR15"] = "France"
    
    # Get the country for the specified area
    country = country_names[area]
    
    # Construct the climate year string, e.g., "CY2008"
    climate_year = "CY$climate_year"

    # Find all area/node codes that belong to the same country
    multiple_nodes=[]
    for (n,c) in country_names
        if c == country
            push!(multiple_nodes,n)
        end
    end
    
    # Sum up the total electricity demand for all nodes in the country
    Total_country_demand=0
    for area_i in multiple_nodes      
        for hour in 1:8760
            if    sum(names(orig_demand) .== area_i) !=0
                Total_country_demand += orig_demand[!, area_i][hour]
            else
                Total_country_demand += 0
            end
        end
    end

    # Get the demand time series for the specific area
    demand_series =[]
    if    sum(names(orig_demand) .== area) !=0
        for hour in 1:8760
            push!(demand_series,orig_demand[!, area][hour])
        end
    else
        # If area data is missing, use a flat zero series
        demand_series =  zeros(8760)
    end

   # Filter the main demand dataframe to get only rows for the country
    nodal_dem = demand[demand[!, "Country"] .== country, :]

    # Further filter to include only "Market" type nodes
    market_dem = nodal_dem[nodal_dem[!, "Node_Type"] .== "Market", :]

    # Filter by scenario, year, and climate year
    values = market_dem[(market_dem[!, "Scenario"] .== scenario) .&
                            (parse(Int, year) .== market_dem[!,"Year"]) .&
                            (market_dem[!,"Climate_Year"] .== climate_year), :]

    # Sum the relevant values (assumed to be in GWh) and convert to MWh
    if isempty(values[!,"Value"])
        final_value = 0
    else
        final_value = sum(values[!,"Value"])*10^6 #MWh
    end

    # Compute the ratio between market demand value and total country demand
    ratio = final_value/Total_country_demand

    # If demand_series is a zero series, return it directly
    # Otherwise scale the original series by the ratio
    if demand_series == zeros(8760)
        return demand_series
    else
        return demand_series .* ratio
    end
end


# Extract generation capacity for each scenario, generation type, climate year and zone
# Capacity: Input data frame with generation capacity
# scenario{String}, e.g. "NT2025"
# type{String}: Generation type, e.g. "Solar PV"
# climate_year{Int}: {1982, 1984, 2007} 
# node{String}: zone name, e.g. "AL00"
function get_generation_capacity(capacity, scenario, type, climate_year, node)
    if scenario == "DE2040"
        scenario = "DE2040 Update"
    end
    nodal_gen = capacity[capacity[!, "Node_Line"] .== node, :]
    final_value = 0
    
    if type == "Gas CCGT new"
        types = ["Gas CCGT new", "Gas CCGT present 2","Gas CCGT old 2","Gas conventional old 2", "Gas CCGT old 1","Gas CCGT old 2","Gas CCGT present 1", "Gas conventional old 1", "Gas CCGT new CCS", "Gas OCGT new", "Gas OCGT old", "Other non-RES","PS Closed"]
        for i in types
            if i in nodal_gen[!, "Generator_ID"]
                nodal_gen_type = nodal_gen[nodal_gen[!, "Generator_ID"] .== i, :]
                if scenario in nodal_gen_type[!, "Simulation_ID"]
                    values = nodal_gen_type[nodal_gen_type[!, "Simulation_ID"] .== scenario, :]
                    value = values[values[!, "ClimateYear"] .== parse(Int, climate_year), "Value"]
                    final_value += value[1]
                end
            end
        end
    else
        nodal_gen_type = nodal_gen[nodal_gen[!, "Generator_ID"] .== type, :]
        values = nodal_gen_type[nodal_gen_type[!, "Simulation_ID"] .== scenario, :]
        value = values[values[!, "ClimateYear"] .== parse(Int, climate_year), "Value"]
        final_value = value
        
    end

    return final_value
end

"""
    get_generation_ratio_2024(capacity, type, node, nodes)

Compute the share (ratio) of installed generation capacity of a given type at a specific node compared to the total national capacity for that generator type or group.

- Arguments
    - `capacity`: Generation capacity data containing columns `"Node_Line"`, `"Generator_ID"`, and `"Value"` (capacity values).
    - `type`: The specific generator technology (e.g., "Gas CCGT new", "Offshore Wind").
    - `node`: Node (zone) identifier for which the capacity ratio is to be computed.
    - `nodes`: A dataset or matrix mapping node identifiers to country names, with columns `"node_id"` and `"country_text"` (or equivalent).

- Output
    - `Float64`: The share (between 0 and 1) of this node’s capacity of the specified generator type compared to the total national capacity of the same type or group.

- Description
    This function calculates how much of a specific generation technology's national capacity is located at a given node. It includes several steps:

    1. **Offshore Special Case**: If the node is an offshore virtual node (e.g., `"FR00"`, `"NL00"`, etc.) and the generator type is `"Offshore Wind"`, the function returns `1.0` (100%) by definition.
    2. **Country Mapping**: Constructs a mapping of node IDs to countries, with manual adjustments for Danish virtual nodes.
    3. **Node Capacity Extraction**: Extracts capacity value for the given generator type at the specified node.
    4. **Technology Grouping**: Groups certain technologies (e.g., multiple variants of "Gas CCGT") under one umbrella when computing national capacity.
    5. **National Capacity Aggregation**: Sums capacities of the same group/type across all nodes in the same country.
    6. **Ratio Calculation**: Computes the node's share of the total national capacity for the given generator type or group.
    7. **Error Handling**: If the denominator is zero (no national capacity found), the result defaults to `0`.

"""

function get_generation_ratio_2024(capacity,type,node,nodes)
    # To create a ratio of generation capacity for different zones in one country

     # Special case: if it's an offshore virtual node and type is Offshore Wind, assign full (100%) ratio
    if (node == "FR00" || node == "NL00" || node == "DE00" || node == "PL00") && type == "Offshore Wind"
        return 1
    end

    # Build a mapping: node_id → country name
    country_names =  Dict{String,Any}()
    for i_idx in 1:length(nodes[:,1])
        i = nodes[i_idx,1]
        country_names[i] = nodes[i_idx,2]
    end
    # Add custom mappings for Danish offshore/virtual nodes
    country_names["DKE1"] = "Denmark"
    country_names["DKW1"] = "Denmark"
    country_names["DKKF"] = "Denmark"
    country_names["DEK1"] = "Denmark"
    
    # Get the country for the current node
    country = country_names[node]
    # Handle possible space issue in country names (fallback if country doesn't match anything)
    if isempty(nodes[nodes[!,"country_text"] .== "$country", "node_id"])
        country = "$country "
    end
    
    # Extract generation capacity for the given node
    nodal_gen_i = capacity[capacity[!, "Node_Line"] .== node, :]
   
     # Get the generation capacity value for the specific type at this node
    if !isempty(nodal_gen_i[nodal_gen_i[!, "Generator_ID"] .== type, :])
        nodal_gen_type_1 = nodal_gen_i[nodal_gen_i[!, "Generator_ID"] .== type, "Value"][1]
    else
        nodal_gen_type_1 = 0 # No capacity for this type at this node
    end


    # Initialize the total countrywide capacity for this generator group/type
    nodal_gen_general_type = 0
 
    # Loop over all nodes in the same country
    for node in nodes[nodes[!,"country_text"] .== "$country", "node_id"]
           
        # Get generation data for this node
        nodal_gen = capacity[capacity[!, "Node_Line"] .== node, :]

        # Check if the given type belongs to a broader technology group
        if type in ["Gas CCGT new", "Gas CCGT old 1", "Gas CCGT old 2", "Gas CCGT present 1", "Gas CCGT present 2"]
            for i in ["Gas CCGT new", "Gas CCGT old 1", "Gas CCGT old 2", "Gas CCGT present 1", "Gas CCGT present 2"]
                nodal_gen_type =  nodal_gen[nodal_gen[!, "Generator_ID"] .== i, :]
                if isempty(nodal_gen_type[!, "Value"])
                    nodal_gen_general_type += 0.0
                else
                    nodal_gen_general_type +=  nodal_gen_type[!, "Value"][1]
                end
            end
        elseif type in ["Gas Conventional old 1", "Gas Conventional old 2"]
            for i in ["Gas Conventional old 1", "Gas Conventional old 2"]
                nodal_gen_type =  nodal_gen[nodal_gen[!, "Generator_ID"] .== i, :]
                if isempty(nodal_gen_type[!, "Value"])
                    nodal_gen_general_type += 0.0
                else
                    nodal_gen_general_type +=  nodal_gen_type[!, "Value"][1]
                end
            end
        elseif type in ["Gas OCGT new", "Gas OCGT old"]
            for i in ["Gas OCGT new", "Gas OCGT old"]
                nodal_gen_type =  nodal_gen[nodal_gen[!, "Generator_ID"] .== i, :]
                if isempty(nodal_gen_type[!, "Value"])
                    nodal_gen_general_type += 0.0
                else
                    nodal_gen_general_type +=  nodal_gen_type[!, "Value"][1]
                end
            end
        elseif type in ["Hard coal CCS", "Hard coal new", "Hard coal old 1", "Hard coal old 2"]
            for i in ["Hard coal CCS", "Hard coal new", "Hard coal old 1", "Hard coal old 2"]
                nodal_gen_type =  nodal_gen[nodal_gen[!, "Generator_ID"] .== i, :]
                if isempty(nodal_gen_type[!, "Value"])
                    nodal_gen_general_type += 0.0
                else
                    nodal_gen_general_type +=  nodal_gen_type[!, "Value"][1]
                end
            end
        elseif type in ["Heavy oil old 1", "Heavy oil old 2"]
            for i in ["Heavy oil old 1", "Heavy oil old 2"]
                nodal_gen_type =  nodal_gen[nodal_gen[!, "Generator_ID"] .== i, :]
                if isempty(nodal_gen_type[!, "Value"])
                    nodal_gen_general_type += 0.0
                else
                    nodal_gen_general_type +=  nodal_gen_type[!, "Value"][1]
                end
            end
        elseif type in ["Lignite CCS", "Lignite new", "Lignite old 1", "Lignite old 2"]
            for i in ["Lignite CCS", "Lignite new", "Lignite old 1", "Lignite old 2"]
                nodal_gen_type =  nodal_gen[nodal_gen[!, "Generator_ID"] .== i, :]
                if isempty(nodal_gen_type[!, "Value"])
                    nodal_gen_general_type += 0.0
                else
                    nodal_gen_general_type +=  nodal_gen_type[!, "Value"][1]
                end
            end
        elseif type in ["Oil shale new", "Oil shale old"]
            for i in ["Oil shale new", "Oil shale old"]
                nodal_gen_type =  nodal_gen[nodal_gen[!, "Generator_ID"] .== i, :]
                if isempty(nodal_gen_type[!, "Value"])
                    nodal_gen_general_type += 0.0
                else
                    nodal_gen_general_type +=  nodal_gen_type[!, "Value"][1]
                end
            end
        else
            # If the type doesn't belong to a group, use only the value from the original node
            nodal_gen_general_type =  nodal_gen_type_1
        end
    end
    
    # Compute the ratio of the node's capacity to the total national capacity for this type/group
    nodal_gen_ratio = nodal_gen_type_1/nodal_gen_general_type

    # If the result is NaN (e.g. divide by 0), set it to 0
    if isnan(nodal_gen_ratio)
        nodal_gen_ratio = 0
    end
    return nodal_gen_ratio
end

"""
    get_corrected_capacity_2024(year, scenario, g, node_id, climate_year, nodes, data)

Retrieves the corrected installed capacity (in MW) for a specific generation unit `g` in the country of `node_id`, for a given year, scenario, and climate year.

- Arguments
    - `year`: The year for which capacity is requested, as a string (e.g., "2024").
    - `scenario`: The scenario, given as a short code ("DE", "GA", "NT"). This is translated to its full name.
    - `g`: The generator technology/type (e.g., "Gas CCGT new", "Solar PV").
    - `node_id`: The node (zone) for which the country is determined.
    - `climate_year`: The climate year (e.g., 2008), used for filtering the data.
    - `nodes`: Data with nodes and their corresponding countries (columns with node_id and country name).
    - `data`: Dataset containing installed capacities and associated properties (columns include "Property_Name", "Country", "Year", "Climate_Year", "Category_Detail", "Value").

- Output
    - `Float64` or `Nothing`: Corrected installed capacity in MW for the specified type and country. Returns `nothing` if no capacity is found.

- Description
The function works as follows:

1. Translates short scenario codes to full scenario names.
2. Creates a mapping from node_id → country, with manual corrections for certain Danish offshore nodes.
3. Uses a dictionary to find which category(ies) in the data correspond to the given generation type `g`.
4. Filters the data on installed capacity, country, year, and climate year.
5. Sums the capacities that match the relevant categories for `g`.
6. Converts capacity from GW to MW (multiplies by 1000).
7. Returns the sum or `nothing` if no capacity is found.

This provides a “corrected” capacity (specific to scenario and climate year) for a generator in the country of the node.
"""

function get_corrected_capacity_2024(year,scenario,g,node_id,climate_year,nodes,data)
    
    # Translate short scenario codes to full names
    if scenario == "DE"
        scenario = "Distributed Energy"
    elseif scenario == "GA"
        scenario = "Global Ambition"
    elseif scenario == "NT"
        scenario = "National Trends"
    end

    # Construct the climate year label, e.g. "CY2008"
    Climate_year = "CY$climate_year"

    # Create a dictionary that maps node IDs to country names
    country_names =  Dict{String,Any}()
    for i_idx in 1:length(nodes[:,1])
        i = nodes[i_idx,1]
        country_names[i] = nodes[i_idx,2]
    end   

    # Add special offshore Danish nodes manually
    country_names["DKE1"] = "Denmark"
    country_names["DKW1"] = "Denmark"
    country_names["DKKF"] = "Denmark"
    country_names["DEK1"] = "Denmark"

    # Get the country for the given node
    country = country_names[node_id]

    # Define how generator types map to category names in the dataset
    Corresponding_type = Dict{String,Any}(
    "Battery" => [],
    "Solar PV" => ["Solar PV Utility"],
    "Offshore Wind" => ["Wind Offshore"] ,
    "Onshore Wind" => ["Wind Onshore"],
    "Gas Conventional old 1" => ["Gas","Gas conventional"],
    "Gas Conventional old 2" => ["Gas","Gas conventional"],
    "Gas CCGT new"=> ["Gas CCGT"],
    "Gas CCGT old 1"=> ["Gas CCGT"],
    "Gas CCGT old 2"=> ["Gas CCGT"],
    "Gas CCGT present 1"=> ["Gas CCGT"],
    "Gas CCGT present 2" => ["Gas CCGT"],
    "Gas CCGT CCS" => ["Gas CCGT CCS"],
    "Gas OCGT new" =>["Gas OCGT"],
    "Gas OCGT old" =>["Gas OCGT"],
    "Hard coal CCS" => ["Hard coal","Hard coal biofuel"],
    "Hard coal new" => ["Hard coal","Hard coal biofuel"],
    "Hard coal old 1" => ["Hard coal","Hard coal biofuel"],
    "Hard coal old 2" => ["Hard coal","Hard coal biofuel"],
    "Heavy oil old 1" => ["Heavy oil"],
    "Heavy oil old 2" => ["Heavy oil"],
    "Light oil" => ["Light oil"],
    "Lignite CCS" => ["Lignite","Lignite biofuel"],
    "Lignite new" => ["Lignite","Lignite biofuel"],
    "Lignite old 1" => ["Lignite","Lignite biofuel"],
    "Lignite old 2" => ["Lignite","Lignite biofuel"],
    "Nuclear" => ["Nuclear"],
    "Oil shale new" => ["Oil shale biofuel"],
    "Oil shale old" => ["Oil shale biofuel"],
    "Other RES" => ["Other RES","Solar Thermal"],
    "Reservoir" => ["Pondage","Reservoir"],
    "Run-of-River" => ["Run-of-River"],
    "Other non-RES" => ["Hydrogen CCGT","Hydrogen FC"])

    # Get the list of category types that correspond to generator type `g`
    gen_types = Corresponding_type[g]

    # If no category types are found, return nothing
    if isempty(gen_types)
        return nothing
    else
        corrected_capacity = 0          # Initialize total capacity accumulator
        for type in gen_types
            # Filter the dataset for installed capacity entries
            capacity = data[data[!,"Property_Name"] .== "Installed Capacity", :]

            # Further filter by country
            nodal_gen = capacity[capacity[!, "Country"] .== country, :]

            # Filter by year
            nodal_gen_y = nodal_gen[nodal_gen[!, "Year"] .== parse(Int,year), :]

            # Filter by climate year
            nodal_gen_cy = nodal_gen_y[nodal_gen_y[!, "Climate_Year"] .== Climate_year, :]
            
            # Check if the category exists in the filtered set
            if type in nodal_gen_cy[!, "Category_Detail"]
                # Add the capacity (converted from GW to MW with *1000)
                corrected_capacity += nodal_gen_cy[nodal_gen_cy[!, "Category_Detail"] .== type, "Value"][1]*1000  #OMZETTING NAAR MW
            end
        end

        # Return nothing if total capacity is still zero
        if corrected_capacity == 0
            return nothing
        else
            return corrected_capacity  # Return the total corrected capacity in MW
        end
    end
end

function get_generation_capacity_2024(capacity, type, node)
    nodal_gen = capacity[capacity[!, "Node_Line"] .== node, :]
    nodal_gen_type = nodal_gen[nodal_gen[!, "Generator_ID"] .== type, :]
    if isempty(nodal_gen_type[!, "Value"])
        value = 0.0
    else
        value =  nodal_gen_type[!, "Value"][1]
    end
    return value
end

function get_generation_capacity_2024_v2(data, scenario, year, type, climate_year, node)

    # Format climate year as string, e.g. "CY1"
    climate_year = "CY$climate_year"
    
    # Define mapping from general types to detailed categories in data
    type_mapping = Dict(
        "Gas CCGT new" => ["Gas", "Gas conventional", "Gas CCGT", "Gas CCGT CCS", "Gas OCGT", "Hydrogen CCGT", "Hydrogen FC"],
        "Solar PV" => ["Solar PV Utility"],
        "Onshore Wind" => ["Wind Onshore"],
        "Offshore Wind" => ["Wind Offshore"],
        "Lignite old 1" => ["Lignite", "Lignite biofuel"],
        "Run-of-River" => ["Run-of-River"],
        "Hard coal old 2 Bio" => ["Hard coal", "Hard coal biofuel"],
        "Heavy oil old 1 Bio" => ["Heavy oil", "Ligth oil", "Oil shale biofuel"],
        "Other RES" => ["Other RES", "Solar Thermal"],
        "Nuclear" => ["Nuclear"]
    )

    # Filter for the relevant node and installed capacity
    capacity = data[data[!,"Property_Name"] .== "Installed Capacity", :]
    nodal_gen = capacity[capacity[!, "Country"] .== node, :]

    # Get the list of categories corresponding to the input 'type'
    types = get(type_mapping, type, [])

    # Filter data to only include rows with these categories
    nodal_gen_type = nodal_gen[in.(nodal_gen[!, "Category_Detail"], Ref(types)), :]

    # Filter by scenario, year and climate year simultaneously
    values = nodal_gen_type[(nodal_gen_type[!, "Scenario"] .== scenario) .&
                            (parse(Int, year) .== nodal_gen_type[!,"Year"]) .&
                            (nodal_gen_type[!,"Climate_Year"] .== climate_year), :]

    # Sum the capacity values; multiply by 1000 to convert from GW to MW
    if isempty(values[!,"Value"])
        final_value = 0
    else
        final_value = sum(values[!,"Value"])*1000
    end
    
    return final_value
end


# Extract hourly RES capacity factors from RES time series
# source{DataFrame} with time series data for each climate year, zone and hour
# area{String}: zone name, e.g. "AL00"
# climate_year{Int}: {1982, 1984, 2007} 
# hour{Int} selected hour {1,2, ...., 8760}
function get_res_data(source, area, climate_year, hour)
    if sum(source[!, "area"].== area) != 0
        value = source[source[!, "area"] .== area, climate_year][hour]
    else
        value = 0
    end
    
    return value
end