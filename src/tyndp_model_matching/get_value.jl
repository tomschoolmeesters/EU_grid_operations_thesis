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

function get_generation_ratio_2024(capacity,type,node,nodes)

    if (node == "FR00" || node == "NL00" || node == "DE00" || node == "PL00") && type == "Offshore Wind"
        return 1
    end

    country_names =  Dict{String,Any}()
    for i_idx in 1:length(nodes[:,1])
        i = nodes[i_idx,1]
        country_names[i] = nodes[i_idx,2]
    end
    
    country = country_names[node]
    if isempty(nodes[nodes[!,"country_text"] .== "$country", "node_id"])
        country = "$country "
    end
    
    nodal_gen_i = capacity[capacity[!, "Node_Line"] .== node, :]
   
    if !isempty(nodal_gen_i[nodal_gen_i[!, "Generator_ID"] .== type, :])
        nodal_gen_type_1 = nodal_gen_i[nodal_gen_i[!, "Generator_ID"] .== type, "Value"][1]
    else
        nodal_gen_type_1 = 0
    end

    nodal_gen_general_type = 0
 
    for node in nodes[nodes[!,"country_text"] .== "$country", "node_id"]
           
        nodal_gen = capacity[capacity[!, "Node_Line"] .== node, :]

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
            nodal_gen_general_type =  nodal_gen_type_1
        end
    end
    
    nodal_gen_ratio = nodal_gen_type_1/nodal_gen_general_type
    if isnan(nodal_gen_ratio)
        nodal_gen_ratio = 0
    end
    return nodal_gen_ratio
end

function get_corrected_capacity_2024(year,scenario,g,node_id,climate_year,nodes,data)
    
    #####################
    if scenario == "DE"
        scenario = "Distributed Energy"
    elseif scneario == "GA"
        scenario = "Global Ambition"
    elseif scenario == "NT"
        scenario = "National Trends"
    end
    Climate_year = "CY$climate_year"

    country_names =  Dict{String,Any}()
    for i_idx in 1:length(nodes[:,1])
        i = nodes[i_idx,1]
        country_names[i] = nodes[i_idx,2]
    end    
    country = country_names[node_id]
    #####################
    Corresponding_type = Dict{String,Any}(
    "Battery" => [],
    "Solar PV" => ["DRES Solar PV","Solar PV Rooftop","Solar PV Utility"],
    "Offshore Wind" => ["DRES Wind Off","Wind Offshore"] ,
    "Onshore Wind" => ["DRES Wind On","Wind Onshore"],
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
    gen_types = Corresponding_type[g]

    #############################

    if isempty(gen_types)
        return nothing
    else
        corrected_capacity = 0
        for type in gen_types
            capacity = data[data[!,"Property_Name"] .== "Installed Capacity", :]
            nodal_gen = capacity[capacity[!, "Country"] .== country, :]
            nodal_gen_y = nodal_gen[nodal_gen[!, "Year"] .== parse(Int,year), :]
            nodal_gen_cy = nodal_gen_y[nodal_gen_y[!, "Climate_Year"] .== Climate_year, :]
            
            if type in nodal_gen_cy[!, "Category_Detail"]
                corrected_capacity += nodal_gen_cy[nodal_gen_cy[!, "Category_Detail"] .== type, "Value"][1]
            end
        end
        if corrected_capacity == 0
            return nothing
        else
            return corrected_capacity
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

#=
function get_generation_capacity_2024_v2(data,scenario,year,type,climate_year,node)
    climate_year = "CY$climate_year"
    
    capacity = data[data[!,"Property_Name"] .== "Installed Capacity", :]
    nodal_gen = capacity[capacity[!, "Country"] .== node, :]

    final_value = 0
    if type == "Gas CCGT new"
        types = ["Gas","Gas conventional","Gas CCGT","Gas CCGT CCS","Gas OCGT","Hydrogen CCGT","Hydrogen FC"]
        for i in types
            if i in nodal_gen[!, "Category_Detail"]
                nodal_gen_type = nodal_gen[nodal_gen[!, "Category_Detail"] .== i, :]
                if scenario in nodal_gen_type[!, "Scenario"]
                    values = nodal_gen_type[nodal_gen_type[!, "Scenario"] .== scenario, :]
                    if parse(Int,year) in values[!,"Year"]
                        value = values[values[!, "Year"] .== parse(Int, year), :]
                        value_cy = value[value[!,"Climate_Year"] .== climate_year, "Value"]
                        final_value += value_cy[1]*1000
                    end
                    
                end
            end
        end
    elseif type == "Solar PV"
        types = ["Solar PV Rooftop", "Solar PV Utility","DRES Solar PV"]
        for i in types
            if i in nodal_gen[!, "Category_Detail"]
                nodal_gen_type = nodal_gen[nodal_gen[!, "Category_Detail"] .== i, :]
                if scenario in nodal_gen_type[!, "Scenario"]
                    values = nodal_gen_type[nodal_gen_type[!, "Scenario"] .== scenario, :]
                    if parse(Int,year) in values[!,"Year"]
                        value = values[values[!, "Year"] .== parse(Int, year), :]
                        value_cy = value[value[!,"Climate_Year"] .== climate_year, "Value"]
                        final_value += value_cy[1]*1000
                    end
                end
            end
        end
    elseif type == "Onshore Wind"
        types = ["DRES Wind Off","Wind Offshore"]
        for i in types
            if i in nodal_gen[!, "Category_Detail"]
                nodal_gen_type = nodal_gen[nodal_gen[!, "Category_Detail"] .== i, :]
                if scenario in nodal_gen_type[!, "Scenario"]
                    values = nodal_gen_type[nodal_gen_type[!, "Scenario"] .== scenario, :]
                    if parse(Int,year) in values[!,"Year"]
                        value = values[values[!, "Year"] .== parse(Int, year), :]
                        value_cy = value[value[!,"Climate_Year"] .== climate_year, "Value"]
                        final_value += value_cy[1]*1000
                    end
                end
            end
        end
    elseif type == "Offshore Wind"
        types = ["DRES Wind Off","Wind Offshore"]
        for i in types
            if i in nodal_gen[!, "Category_Detail"]
                nodal_gen_type = nodal_gen[nodal_gen[!, "Category_Detail"] .== i, :]
                if scenario in nodal_gen_type[!, "Scenario"]
                    values = nodal_gen_type[nodal_gen_type[!, "Scenario"] .== scenario, :]
                    if parse(Int,year) in values[!,"Year"]
                        value = values[values[!, "Year"] .== parse(Int, year), :]
                        value_cy = value[value[!,"Climate_Year"] .== climate_year, "Value"]
                        final_value += value_cy[1]*1000
                    end
                end
            end
        end
    elseif type == "Lignite old 1"
        types = ["Lignite","Lignite biofuel"]
        for i in types
            if i in nodal_gen[!, "Category_Detail"]
                nodal_gen_type = nodal_gen[nodal_gen[!, "Category_Detail"] .== i, :]
                if scenario in nodal_gen_type[!, "Scenario"]
                    values = nodal_gen_type[nodal_gen_type[!, "Scenario"] .== scenario, :]
                    if parse(Int,year) in values[!,"Year"]
                        value = values[values[!, "Year"] .== parse(Int, year), :]
                        value_cy = value[value[!,"Climate_Year"] .== climate_year, "Value"]
                        final_value += value_cy[1]*1000
                    end
                end
            end
        end
    elseif type == "Run-of-River"
        types = ["Run-of-River"]
        for i in types
            if i in nodal_gen[!, "Category_Detail"]
                nodal_gen_type = nodal_gen[nodal_gen[!, "Category_Detail"] .== i, :]
                if scenario in nodal_gen_type[!, "Scenario"]
                    values = nodal_gen_type[nodal_gen_type[!, "Scenario"] .== scenario, :]
                    if parse(Int,year) in values[!,"Year"]
                        value = values[values[!, "Year"] .== parse(Int, year), :]
                        value_cy = value[value[!,"Climate_Year"] .== climate_year, "Value"]
                        final_value += value_cy[1]*1000
                    end
                end
            end
        end
    elseif type == "Hard coal old 2 Bio"
        types = ["Hard coal","Hard coal biofuel"]
        for i in types
            if i in nodal_gen[!, "Category_Detail"]
                nodal_gen_type = nodal_gen[nodal_gen[!, "Category_Detail"] .== i, :]
                if scenario in nodal_gen_type[!, "Scenario"]
                    values = nodal_gen_type[nodal_gen_type[!, "Scenario"] .== scenario, :]
                    if parse(Int,year) in values[!,"Year"]
                        value = values[values[!, "Year"] .== parse(Int, year), :]
                        value_cy = value[value[!,"Climate_Year"] .== climate_year, "Value"]
                        final_value += value_cy[1]*1000
                    end
                end
            end
        end
    elseif type == "Heavy oil old 1 Bio"
        types = ["Heavy oil","Ligth oil","Oil shale biofuel"]
        for i in types
            if i in nodal_gen[!, "Category_Detail"]
                nodal_gen_type = nodal_gen[nodal_gen[!, "Category_Detail"] .== i, :]
                if scenario in nodal_gen_type[!, "Scenario"]
                    values = nodal_gen_type[nodal_gen_type[!, "Scenario"] .== scenario, :]
                    if parse(Int,year) in values[!,"Year"]
                        value = values[values[!, "Year"] .== parse(Int, year), :]
                        value_cy = value[value[!,"Climate_Year"] .== climate_year, "Value"]
                        final_value += value_cy[1]*1000
                    end
                end
            end
        end
    elseif type == "Other RES"
        types = ["Other RES","Solar Thermal"]
        for i in types
            if i in nodal_gen[!, "Category_Detail"]
                nodal_gen_type = nodal_gen[nodal_gen[!, "Category_Detail"] .== i, :]
                if scenario in nodal_gen_type[!, "Scenario"]
                    values = nodal_gen_type[nodal_gen_type[!, "Scenario"] .== scenario, :]
                    if parse(Int,year) in values[!,"Year"]
                        value = values[values[!, "Year"] .== parse(Int, year), :]
                        value_cy = value[value[!,"Climate_Year"] .== climate_year, "Value"]
                        final_value += value_cy[1]*1000
                    end
                end
            end
        end
    elseif type == "Nuclear"
        types = ["Nuclear"]
        for i in types
            if i in nodal_gen[!, "Category_Detail"]
                nodal_gen_type = nodal_gen[nodal_gen[!, "Category_Detail"] .== i, :]
                if scenario in nodal_gen_type[!, "Scenario"]
                    values = nodal_gen_type[nodal_gen_type[!, "Scenario"] .== scenario, :]
                    if parse(Int,year) in values[!,"Year"]
                        value = values[values[!, "Year"] .== parse(Int, year), :]
                        value_cy = value[value[!,"Climate_Year"] .== climate_year, "Value"]
                        final_value += value_cy[1]*1000
                    end
                end
            end
        end
    end
    return final_value
end
=#

function get_generation_capacity_2024_v2(data, scenario, year, type, climate_year, node)
    climate_year = "CY$climate_year"
    
    # Define the mapping for types
    type_mapping = Dict(
        "Gas CCGT new" => ["Gas", "Gas conventional", "Gas CCGT", "Gas CCGT CCS", "Gas OCGT", "Hydrogen CCGT", "Hydrogen FC"],
        "Solar PV" => ["Solar PV Rooftop", "Solar PV Utility", "DRES Solar PV"],
        "Onshore Wind" => ["DRES Wind On", "Wind Onshore"],
        "Offshore Wind" => ["DRES Wind Off", "Wind Offshore"],
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

    # Get the categories for the requested type
    types = get(type_mapping, type, [])

    # Filter once for the given types
    nodal_gen_type = nodal_gen[in.(nodal_gen[!, "Category_Detail"], Ref(types)), :]

    # Filter for the scenario and year in one step
    values = nodal_gen_type[(nodal_gen_type[!, "Scenario"] .== scenario) .&
                            (parse(Int, year) .== nodal_gen_type[!,"Year"]) .&
                            (nodal_gen_type[!,"Climate_Year"] .== climate_year), :]

    # Sum the values and convert to MW
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