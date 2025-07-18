"""
    relocation_wind_farms()

Reads offshore wind farm relocation data from an Excel file and organizes it into a nested dictionary.

    # Output
    - Returns `relocation_dict` with keys:
        - `old_gen_bus`, `old_lat`, `old_lon`: original bus index and coordinates.
        - `gen_bus`, `lat`, `lon`: new bus index and coordinates.
        - `name` (optional): wind farm name if present.

    # Usage
    - Used to relocate wind farms originally located onshore to offshore wind farms.
"""

function relocation_wind_farms()
    file = "./data_sources/Relocation_WindFarms.xlsx"
    xls = XLSX.readtable(file, "Blad1")
    data, headers = xls
    
     # Find column indices for relevant fields
    zone_col = findfirst(==(:zone), headers) 
    g_id_col = findfirst(==(:WindFarm), headers) 
    old_idx_col = findfirst(==(:old_index), headers)
    old_lat_col = findfirst(==(:old_lat), headers)
    old_lon_col = findfirst(==(:old_lon), headers)
    idx_col = findfirst(==(:index), headers)
    lat_col = findfirst(==(:lat), headers)
    lon_col = findfirst(==(:lon), headers)
    name_col = findfirst(==(:name), headers)  
    
    relocation_dict = Dict{String, Dict{String, Dict{String, Any}}}()

    nrows = length(data[1])  # Number of rows in the dataset
    
    for i in 1:nrows
        zone = data[zone_col][i]
        g_id = string(data[g_id_col][i])

        # Initialize nested dict for zone if not present
        if !haskey(relocation_dict, zone)
            relocation_dict[zone] = Dict{String, Dict{String, Any}}()
        end

        # Build dictionary for each wind farm entry
        entry = Dict(
            "old_gen_bus" => data[old_idx_col][i],
            "old_lat"     => data[old_lat_col][i],
            "old_lon"     => data[old_lon_col][i],
            "gen_bus"     => data[idx_col][i],
            "lat"         => data[lat_col][i],
            "lon"         => data[lon_col][i]
        )

        # Add name only if it exists and is not missing
        name_val = data[name_col][i]
        if name_val !== nothing && name_val !== missing
            entry["name"] = name_val
        end

        relocation_dict[zone][g_id] = entry
    end
    return relocation_dict
end

"""
    add_OFF_DC_buses!(input_data)

Clusters relocated offshore wind farms into DC bus groups and creates new DC bus entries for each cluster.

    # Input
    - `input_data::Dict`: Network input data

    # Output
    - Returns a tuple:
        - `new_DC_buses::Dict`: Newly generated DC buses, grouped per zone, containing:
            - `index`: Unique DC bus index.
            - `lat`, `lon`: Coordinates of the grouped offshore location.
            - `zone`: Country/region identifier.
        - `relocation_dict::Dict`: Offshore wind farm relocation data returned by `relocation_wind_farms()`.

    # Dependencies
    - `relocation_wind_farms()`: Loads and structures offshore relocation data from an Excel file.
    - `group_OFFwindfarms(...)`: Clusters offshore wind farms per zone and assigns DC bus coordinates and indices.
        
"""

function add_OFF_DC_buses!(input_data)
    # Load relocation data from Excel
    relocation_dict = relocation_wind_farms()

    # Determine the next available DC bus index
    DC_number = maximum([bus["index"] for (b, bus) in input_data["busdc"]]) + 1
    println("Starting DC index: $DC_number")

    # Maximum allowed DC clusters per zone (can be adjusted if more or less detail is needed)
    max_groups_dict = Dict(
        "BE" => 2,
        "DE" => 5,
        "DK1" => 3,
        "NL" => 7,
        "UK" => 8)

    # Initialize dictionary to store new DC buses
    new_DC_buses = Dict{String,Any}()

    # Process each zone in the relocation dictionary
    for zone in keys(relocation_dict)
        println("Clustering zone $zone")
        max_groups = max_groups_dict["$zone"]

        # Group wind farms into offshore DC buses
        DC_number, DC_bus = group_OFFwindfarms(relocation_dict,zone,max_groups,DC_number)

        # Add each generated DC bus to the result dictionary
        for (i,dc_bus) in DC_bus
            idx = dc_bus["idx"]
            new_DC_buses["$idx"] = Dict{String,Any}()
            new_DC_buses["$idx"]["index"] = idx
            new_DC_buses["$idx"]["lat"] = dc_bus["lat"]
            new_DC_buses["$idx"]["lon"] = dc_bus["lon"]
            new_DC_buses["$idx"]["zone"] = zone
        end
    end

    return new_DC_buses, relocation_dict
end  

"""
    update_input_data(input_data)

Adds and configures new offshore wind buses, converters, and AC branches in the power system `input_data` structure. 
Also relocates offshore wind generators to new offshore buses and connects them appropriately.

    # Arguments
    - `input_data::Dict`: Network input data

    # Output
    - Returns a tuple of three elements:
        - `new_DC_buses::Dict{String, Any}`: Dictionary of newly created offshore DC buses.
        - `relocation_dict::Dict{String, Any}`: Mapping of relocated generators to their new AC bus locations and corresponding DC buses.
        - `new_branches::Dict{String, Any}`: Dictionary of new AC branches created for connecting offshore generators to converter buses and reconnecting old generator buses if needed.

    # Description
    - Randomly selects reference elements (AC bus, DC bus, converter, AC branch) as templates to clone for creating new infrastructure.
    - Iterates over all zones and generators in the `relocation_dict`, and for each:
        - Creates a new offshore AC bus if it doesn't already exist.
        - Updates generator bus assignments.
    - For each new DC bus, creates:
        - A corresponding AC bus.
        - A DC bus based on reference.
        - A `convdc` converter linking the new AC and DC buses.
    - Builds AC branches to:
        - Connect relocated generators to the AC side of their associated DC converter.
        - Optionally reconnect the converter's AC side to the old generator bus if not already connected.

    # Dependencies
    This function relies on the following other functions:
        - `add_OFF_DC_buses!(input_data)`
    
    # Notes
    - This function modifies `input_data` in-place.
"""

function update_input_data(input_data)

    new_DC_buses, relocation_dict = add_OFF_DC_buses!(input_data)
    country_dict = Dict()
    
    # Verzamel landen per zone in country_dict
    for (b_id, bus) in input_data["bus"]
        if !haskey(country_dict, bus["zone"])
            country_dict[bus["zone"]] = bus["country"]
        end   
    end

    # Kies een referentiebus willekeurig
    reference_key_AC = rand(keys(input_data["bus"]))#"3935"#Base kv = 225#rand(keys(input_data["bus"]))
    reference_key_DC = rand(keys(input_data["busdc"]))#"10168"#BAse kv =500, rand(keys(input_data["busdc"]))
    reference_key_conv = rand(keys(input_data["convdc"]))#"32"#rand(keys(input_data["convdc"]))
    reference_key_acbranch = rand(keys(input_data["branch"]))#"4304" #rand(keys(input_data["branch"]))
    println("Reference key for AC: $reference_key_AC")
    println("Reference key for DC: $reference_key_DC")
    println("Reference key for converter: $reference_key_conv")
    println("Reference key for ac branch: $reference_key_acbranch")
    reference_bus_AC = deepcopy(input_data["bus"]["$reference_key_AC"])  
    reference_bus_DC = deepcopy(input_data["busdc"]["$reference_key_DC"])
    reference_conv = deepcopy(input_data["convdc"]["$reference_key_conv"])
    reference_acbranch = deepcopy(input_data["branch"]["$reference_key_acbranch"])

    # Verwerk de relocation_dict per zone
    for zone in keys(relocation_dict)
        for (g_id, gen) in relocation_dict["$zone"]  
            new_gen_bus = relocation_dict["$zone"]["$g_id"]["gen_bus"]
            
            if !haskey(input_data["bus"], new_gen_bus)
                # Verkrijg lat, lon, en naam
                latitude = relocation_dict["$zone"]["$g_id"]["lat"]
                longitude = relocation_dict["$zone"]["$g_id"]["lon"]
                name = relocation_dict["$zone"]["$g_id"]["name"]
                
                # Voeg de nieuwe bus toe aan input_data
                input_data["bus"]["$new_gen_bus"] = deepcopy(reference_bus_AC)
                input_data["bus"]["$new_gen_bus"]["lat"] = latitude
                input_data["bus"]["$new_gen_bus"]["lon"] = longitude
                input_data["bus"]["$new_gen_bus"]["zone"] = zone
                input_data["bus"]["$new_gen_bus"]["bus_i"] = new_gen_bus

                # Als naam beschikbaar is, gebruik deze, anders standaard naam
                if name !== nothing
                    input_data["bus"]["$new_gen_bus"]["name"] = name
                else
                    input_data["bus"]["$new_gen_bus"]["name"] = "$zone_$new_gen_bus"
                end
                
                # Stel het land in voor de bus
                input_data["bus"]["$new_gen_bus"]["country"] = country_dict[zone]

                # Als "source_id" een array is, update het tweede element
                input_data["bus"]["$new_gen_bus"]["source_id"][2] = new_gen_bus
                input_data["bus"]["$new_gen_bus"]["index"] = new_gen_bus
            
                # Update de generator als deze al bestaat
                if haskey(input_data["gen"], g_id)
                    input_data["gen"]["$g_id"]["gen_bus"] = new_gen_bus
                end
            end
        end
    end
    
    #Maak nieuwe AC bussen
    AC_number = maximum([bus["index"] for (b, bus) in input_data["bus"]]) + 1
    Conv_number = maximum([conv["index"] for (c, conv) in input_data["convdc"]]) + 1
    ACbranch_number = maximum([branch["index"] for (b, branch) in input_data["branch"]]) + 1

    for (b_id,bus) in new_DC_buses

        dc_index = bus["index"]
        latitude = bus["lat"]
        longitude = bus["lon"]
        zone = bus["zone"]
        name_AC = "$zone$AC_number"

        input_data["bus"]["$AC_number"] = deepcopy(reference_bus_AC)
        input_data["bus"]["$AC_number"]["lat"] = latitude
        input_data["bus"]["$AC_number"]["lon"] = longitude
        input_data["bus"]["$AC_number"]["zone"] = zone
        input_data["bus"]["$AC_number"]["bus_i"] = AC_number

        # Als naam beschikbaar is, gebruik deze, anders standaard naam
        if name_AC !== nothing
            input_data["bus"]["$AC_number"]["name"] = name_AC
        else
            input_data["bus"]["$AC_number"]["name"] = "$zone$AC_number"
        end
        
        # Stel het land in voor de bus
        input_data["bus"]["$AC_number"]["country"] = country_dict[zone]

        # Als "source_id" een array is, update het tweede element
        input_data["bus"]["$AC_number"]["source_id"][2] = AC_number
        input_data["bus"]["$AC_number"]["index"] = AC_number

        

        name_DC = "$zone$dc_index"
        input_data["busdc"]["$dc_index"] = deepcopy(reference_bus_DC)
        input_data["busdc"]["$dc_index"]["lat"] = latitude
        input_data["busdc"]["$dc_index"]["lon"] = longitude
        input_data["busdc"]["$dc_index"]["name"] = name_DC
        input_data["busdc"]["$dc_index"]["source_id"][2] = dc_index
        input_data["busdc"]["$dc_index"]["busdc_i"] = dc_index
        input_data["busdc"]["$dc_index"]["index"] = dc_index
        input_data["busdc"]["$dc_index"]["zone"] = country_dict[zone]

        input_data["convdc"]["$Conv_number"] = deepcopy(reference_conv)
        input_data["convdc"]["$Conv_number"]["busdc_i"] = dc_index
        input_data["convdc"]["$Conv_number"]["busac_i"] = AC_number
        input_data["convdc"]["$Conv_number"]["index"] = Conv_number 
        input_data["convdc"]["$Conv_number"]["source_id"][2] = Conv_number
        input_data["convdc"]["$Conv_number"]["interconnector"] = false
        #input_data["convdc"]["$Conv_number"]["Pacmax"] = 40
        #input_data["convdc"]["$Conv_number"]["Qacrated"] = 40
        #input_data["convdc"]["$Conv_number"]["Pacrated"] = 40
        #input_data["convdc"]["$Conv_number"]["Qacmax"] = 40
        #input_data["convdc"]["$Conv_number"]["Qacmin"] = -40
        #input_data["convdc"]["$Conv_number"]["Pacmax"] = 40
        #input_data["convdc"]["$Conv_number"]["Pacmin"] = 40
        #input_data["convdc"]["$Conv_number"]["Imax"] = 4000
        #input_data["convdc"]["$Conv_number"]["basekVac"] = 225

        AC_number += 1
        Conv_number += 1



    end

    corr_DC_bus_set = Vector()
    corr_DC_bus = 0
    new_branches = Dict{String,Any}()
    for zone in keys(relocation_dict)
        for (g_id, gen) in relocation_dict["$zone"]
            new_gen_bus = relocation_dict["$zone"]["$g_id"]["gen_bus"]
            push!(corr_DC_bus_set,corr_DC_bus)
            corr_DC_bus = relocation_dict["$zone"]["$g_id"]["corresponding_DCbus"]
            DC_to_ACbus = 0
            for (c,conv) in input_data["convdc"]
                if conv["busdc_i"] == corr_DC_bus
                    DC_to_ACbus = conv["busac_i"]
                end
            end
            
            input_data["branch"]["$ACbranch_number"] = deepcopy(reference_acbranch)
            input_data["branch"]["$ACbranch_number"]["source_id"][2] = ACbranch_number
            input_data["branch"]["$ACbranch_number"]["f_bus"] = new_gen_bus
            input_data["branch"]["$ACbranch_number"]["t_bus"] = DC_to_ACbus
            input_data["branch"]["$ACbranch_number"]["name"] = "WindFarm connector"
            input_data["branch"]["$ACbranch_number"]["rate_a"] = 101
            input_data["branch"]["$ACbranch_number"]["rate_b"] = 101
            input_data["branch"]["$ACbranch_number"]["rate_c"] = 101
            input_data["branch"]["$ACbranch_number"]["br_x"] = 0.01
            input_data["branch"]["$ACbranch_number"]["index"] = ACbranch_number
            input_data["branch"]["$ACbranch_number"]["interconnector"] = false
            input_data["branch"]["$ACbranch_number"]["transformer"] = false
            new_branches["$ACbranch_number"] = deepcopy(input_data["branch"]["$ACbranch_number"])
            ACbranch_number +=1

            if !(corr_DC_bus in corr_DC_bus_set)
                old_gen_bus = relocation_dict["$zone"]["$g_id"]["old_gen_bus"] #AC bus
                input_data["branch"]["$ACbranch_number"] = deepcopy(reference_acbranch)
                input_data["branch"]["$ACbranch_number"]["source_id"][2] = ACbranch_number
                input_data["branch"]["$ACbranch_number"]["name"] = "WindFarm connector"
                input_data["branch"]["$ACbranch_number"]["rate_a"] = 101
                input_data["branch"]["$ACbranch_number"]["rate_b"] = 101
                input_data["branch"]["$ACbranch_number"]["rate_c"] = 101
                input_data["branch"]["$ACbranch_number"]["br_x"] = 0.01
                input_data["branch"]["$ACbranch_number"]["f_bus"] = DC_to_ACbus
                input_data["branch"]["$ACbranch_number"]["t_bus"] = old_gen_bus
                input_data["branch"]["$ACbranch_number"]["index"] = ACbranch_number
                input_data["branch"]["$ACbranch_number"]["interconnector"] = false
                input_data["branch"]["$ACbranch_number"]["transformer"] = false
                new_branches["$ACbranch_number"] = deepcopy(input_data["branch"]["$ACbranch_number"])

                ACbranch_number +=1
            end
            
        end

        
    end    
    println(corr_DC_bus_set)
    return new_DC_buses, relocation_dict, new_branches

end

"""
    relocation_wind_farms_ext()

Reads offshore wind farm relocation and expansion data from an Excel file and organizes it into a nested dictionary.

    # Output
    - Returns `relocation_dict` with keys per wind farm:
        - `gen_bus`: new offshore bus index
        - `index`: wind farm ID
        - `lat`, `lon`: coordinates
        - `year`: planned year
        - `pmax`: power capacity
        - `onshore_bus`: original onshore bus index
        - `name` (optional): wind farm name if present

    # Usage
    - Used to manage relocation and expansion of wind farms planned for 2030, supporting offshore wind development planning.
"""

function relocation_wind_farms_ext()
    file = joinpath(@__DIR__, "..", "data_sources", "Relocation_WindFarms_EXTEND.xlsx")
    xls = XLSX.readtable(file, "Blad1")
    data, headers = xls
    
    # Find column indices for relevant fields
    zone_col = findfirst(==(:zone), headers) 
    g_id_col = findfirst(==(:WindFarm), headers) 
    lat_col = findfirst(==(:lat), headers)
    lon_col = findfirst(==(:lon), headers)
    name_col = findfirst(==(:name), headers)
    p_col = findfirst(==(:power), headers)
    #ext_col = findfirst(==(:Expandable), headers)
    year_col = findfirst(==(:Year), headers)
    onshore_b_col = findfirst(==(:onshore_bus), headers)
    offshore_b_col = findfirst(==(:offshore_bus), headers)

    relocation_dict = Dict{String, Dict{String, Dict{String, Any}}}()
    nrows = length(data[1])  # Number of rows in the dataset
    
    # Iterate over each row in data
    for i in 1:nrows
        zone = data[zone_col][i] 
        g_id = string(data[g_id_col][i])
        
        # Initialiseer land als het nog niet bestaat
        if !haskey(relocation_dict, zone)
            relocation_dict[zone] = Dict()
        end
        
        # Voeg g_id toe aan land
        relocation_dict[zone][g_id] = Dict(
            "gen_bus" => data[offshore_b_col][i],
            "index" => data[g_id_col][i],
            "lat" => data[lat_col][i],
            "lon" => data[lon_col][i],
            "year" => data[year_col][i],
            "pmax" => data[p_col][i],
            "onshore_bus" => data[onshore_b_col][i],
            if data[name_col][i] !== nothing
                "name" => data[name_col][i]
            end
        )
    end
    return relocation_dict
end

"""
    add_OFF_DC_buses_ext!(input_data)

Generates and adds offshore DC bus entries to the input data structure using extended offshore wind farm relocation information for multiple time horizons.

    # Input
    - `input_data::Dict`: Network input data

    # Output
    - Returns a tuple:
        - `new_DC_buses`: Dictionary of newly generated offshore DC buses by zone and year.
        - `relocation_dict`: Offshore wind farm relocation data returned by `relocation_wind_farms_ext()`.

    # Dependencies
    - `relocation_wind_farms_ext()`: Loads and structures offshore relocation data from an Excel file.
    - `group_OFFwindfarms_ext()`: Clusters offshore wind farms per zone and per year (2030 or 2040) and assigns DC bus coordinates and indices.
"""

function add_OFF_DC_buses_ext!(input_data)
    # Load extended wind farm relocation data
    relocation_dict = relocation_wind_farms_ext()

    # Start indexing new DC buses after the highest existing index
    DC_number = maximum([bus["index"] for (b, bus) in input_data["busdc"]]) + 1
    println("Starting DC bus index: $DC_number")

    # Max number of DC bus groups per zone for 2030
    max_groups_dict_30 = Dict(
        "BE" => 1,
        "DE" => 9,
        "DK1" => 3,
        "NL" => 8,
        "UK" => 14)

    # Max number of DC bus groups per zone for 2040
    max_groups_dict_40 = Dict(
        "BE" => 1,
        "DE" => 4,
        "DK1" => 2,
        "NL" => 4,
        "UK" => 9)
    
    # Container to store newly created DC bus entries
    new_DC_buses = Dict{String,Any}()

    # Iterate over each country/zone in the relocation data
    for zone in keys(relocation_dict)
        println("Clustering zone $zone")

        max_groups_30 = max_groups_dict_30["$zone"]
        max_groups_40 = max_groups_dict_40["$zone"]

        # Cluster wind farms for 2030 and 2040 and get new DC bus data
        DC_number, DC_bus_30, DC_bus_40 = group_OFFwindfarms_ext(relocation_dict,zone,max_groups_30,max_groups_40,DC_number)

        # Add 2030 DC bus clusters to the dictionary
        for (_,dc_bus) in DC_bus_30
            idx = dc_bus["idx"]
            new_DC_buses["$idx"] = Dict{String,Any}()
            new_DC_buses["$idx"]["index"] = idx
            new_DC_buses["$idx"]["lat"] = dc_bus["lat"]
            new_DC_buses["$idx"]["lon"] = dc_bus["lon"]
            new_DC_buses["$idx"]["zone"] = zone
            new_DC_buses["$idx"]["year"] = 2030
        end

        # Add 2040 DC bus clusters to the dictionary
        for (_,dc_bus) in DC_bus_40
            idx = dc_bus["idx"]
            new_DC_buses["$idx"] = Dict{String,Any}()
            new_DC_buses["$idx"]["index"] = idx
            new_DC_buses["$idx"]["lat"] = dc_bus["lat"]
            new_DC_buses["$idx"]["lon"] = dc_bus["lon"]
            new_DC_buses["$idx"]["zone"] = zone
            new_DC_buses["$idx"]["year"] = 2040
        end
    end

    # Return both the new bus dictionary and the relocation mapping
    return new_DC_buses, relocation_dict
end  


function get_clustering_rating(DC_bus,relocation_dict_zone)
    p_cluster = 0
    for (g,gen) in relocation_dict_zone
        if gen["corresponding_DCbus"] == DC_bus
            p_cluster += gen["pmax"]
        end
    end
    return p_cluster

end


function update_input_data_ext(input_data, OPF_year;use_1MW_connection = true)

    new_DC_buses, relocation_dict = add_OFF_DC_buses_ext!(input_data)
    country_dict = Dict()
    
    # Verzamel landen per zone in country_dict
    for (b_id, bus) in input_data["bus"]
        if !haskey(country_dict, bus["zone"])
            country_dict[bus["zone"]] = bus["country"]
        end   
    end

    # Kies een referentiebus willekeurig
    reference_key_AC = rand(keys(input_data["bus"]))#"3935"#Base kv = 225#rand(keys(input_data["bus"]))
    reference_key_DC = rand(keys(input_data["busdc"]))#"10168"#BAse kv =500, rand(keys(input_data["busdc"]))
    reference_key_conv = rand(keys(input_data["convdc"]))#"32"#rand(keys(input_data["convdc"]))
    reference_key_acbranch = rand(keys(input_data["branch"]))#"4304" #rand(keys(input_data["branch"]))
    println("Reference key for AC: $reference_key_AC")
    println("Reference key for DC: $reference_key_DC")
    println("Reference key for converter: $reference_key_conv")
    println("Reference key for ac branch: $reference_key_acbranch")
    reference_bus_AC = deepcopy(input_data["bus"]["$reference_key_AC"])  
    reference_bus_DC = deepcopy(input_data["busdc"]["$reference_key_DC"])
    reference_conv = deepcopy(input_data["convdc"]["$reference_key_conv"])
    reference_acbranch = deepcopy(input_data["branch"]["$reference_key_acbranch"])

    # Verwerk de relocation_dict per zone
    for zone in keys(relocation_dict)
        for (g_id, gen) in relocation_dict["$zone"]  
            new_gen_bus = relocation_dict["$zone"]["$g_id"]["gen_bus"]
            
            if !haskey(input_data["bus"], new_gen_bus)
                # Verkrijg lat, lon, en naam
                latitude = relocation_dict["$zone"]["$g_id"]["lat"]
                longitude = relocation_dict["$zone"]["$g_id"]["lon"]
                name = relocation_dict["$zone"]["$g_id"]["name"]
                year = relocation_dict["$zone"]["$g_id"]["year"]
                onshore_bus = relocation_dict["$zone"]["$g_id"]["onshore_bus"]
                
                # Voeg de nieuwe bus toe aan input_data
                input_data["bus"]["$new_gen_bus"] = deepcopy(reference_bus_AC)
                input_data["bus"]["$new_gen_bus"]["lat"] = latitude
                input_data["bus"]["$new_gen_bus"]["lon"] = longitude
                input_data["bus"]["$new_gen_bus"]["zone"] = zone
                input_data["bus"]["$new_gen_bus"]["bus_i"] = new_gen_bus
                input_data["bus"]["$new_gen_bus"]["year"] = year
                input_data["bus"]["$new_gen_bus"]["onshore_bus"] = onshore_bus

                # Als naam beschikbaar is, gebruik deze, anders standaard naam
                if name !== nothing
                    input_data["bus"]["$new_gen_bus"]["name"] = name
                else
                    input_data["bus"]["$new_gen_bus"]["name"] = "$zone_$new_gen_bus"
                end
                
                # Stel het land in voor de bus
                input_data["bus"]["$new_gen_bus"]["country"] = country_dict[zone]

                # Als "source_id" een array is, update het tweede element
                input_data["bus"]["$new_gen_bus"]["source_id"][2] = new_gen_bus
                input_data["bus"]["$new_gen_bus"]["index"] = new_gen_bus
            
                # Update de generator als deze al bestaat
                input_data["gen"]["$g_id"] = Dict{String,Any}()
                input_data["gen"]["$g_id"]["gen_bus"] = new_gen_bus
                input_data["gen"]["$g_id"]["index"] = parse(Int,g_id)
                input_data["gen"]["$g_id"]["year"] = year
                input_data["gen"]["$g_id"]["zone"] = zone
                input_data["gen"]["$g_id"]["type_tyndp"] = "Offshore Wind"
                input_data["gen"]["$g_id"]["model"] = 2
                input_data["gen"]["$g_id"]["pmax"] = relocation_dict["$zone"]["$g_id"]["pmax"]/100
                input_data["gen"]["$g_id"]["pmin"] = 0
                input_data["gen"]["$g_id"]["ncost"] = 2
                if year <= OPF_year 
                    input_data["gen"]["$g_id"]["gen_status"] = 1
                else
                    input_data["gen"]["$g_id"]["gen_status"] = 0 #NOT ACTIVE YET
                end
                input_data["gen"]["$g_id"]["qmin"] = -4.5
                input_data["gen"]["$g_id"]["qmax"] = 4.5
                input_data["gen"]["$g_id"]["vg"] = 1
                input_data["gen"]["$g_id"]["country"] = country_dict[zone]
                input_data["gen"]["$g_id"]["source_id"] = ["gen",new_gen_bus]
                input_data["gen"]["$g_id"]["cost"] = [17,0]
                input_data["gen"]["$g_id"]["type"] = "Offshore"
            end
        end
    end
    
    #Maak nieuwe AC bussen
    AC_number = maximum([bus["index"] for (b, bus) in input_data["bus"]]) + 1
    Conv_number = maximum([conv["index"] for (c, conv) in input_data["convdc"]]) + 1
    ACbranch_number = maximum([branch["index"] for (b, branch) in input_data["branch"]]) + 1

    for (b_id,bus) in new_DC_buses

        dc_index = bus["index"]
        latitude = bus["lat"]
        longitude = bus["lon"]
        zone = bus["zone"]
        name_AC = "$zone$AC_number"

        input_data["bus"]["$AC_number"] = deepcopy(reference_bus_AC)
        input_data["bus"]["$AC_number"]["lat"] = latitude
        input_data["bus"]["$AC_number"]["lon"] = longitude
        input_data["bus"]["$AC_number"]["zone"] = zone
        input_data["bus"]["$AC_number"]["bus_i"] = AC_number

        # Als naam beschikbaar is, gebruik deze, anders standaard naam
        if name_AC !== nothing
            input_data["bus"]["$AC_number"]["name"] = name_AC
        else
            input_data["bus"]["$AC_number"]["name"] = "$zone$AC_number"
        end
        
        # Stel het land in voor de bus
        input_data["bus"]["$AC_number"]["country"] = country_dict[zone]

        # Als "source_id" een array is, update het tweede element
        input_data["bus"]["$AC_number"]["source_id"][2] = AC_number
        input_data["bus"]["$AC_number"]["index"] = AC_number

        

        name_DC = "$zone$dc_index"
        input_data["busdc"]["$dc_index"] = deepcopy(reference_bus_DC)
        input_data["busdc"]["$dc_index"]["lat"] = latitude
        input_data["busdc"]["$dc_index"]["lon"] = longitude
        input_data["busdc"]["$dc_index"]["name"] = name_DC
        input_data["busdc"]["$dc_index"]["source_id"][2] = dc_index
        input_data["busdc"]["$dc_index"]["busdc_i"] = dc_index
        input_data["busdc"]["$dc_index"]["index"] = dc_index
        input_data["busdc"]["$dc_index"]["zone"] = country_dict[zone]

        input_data["convdc"]["$Conv_number"] = deepcopy(reference_conv)
        input_data["convdc"]["$Conv_number"]["busdc_i"] = dc_index
        input_data["convdc"]["$Conv_number"]["busac_i"] = AC_number
        input_data["convdc"]["$Conv_number"]["index"] = Conv_number 
        input_data["convdc"]["$Conv_number"]["source_id"][2] = Conv_number
        input_data["convdc"]["$Conv_number"]["interconnector"] = false
        #input_data["convdc"]["$Conv_number"]["Pacmax"] = 40
        #input_data["convdc"]["$Conv_number"]["Qacrated"] = 40
        #input_data["convdc"]["$Conv_number"]["Pacrated"] = 40
        #input_data["convdc"]["$Conv_number"]["Qacmax"] = 40
        #input_data["convdc"]["$Conv_number"]["Qacmin"] = -40
        #input_data["convdc"]["$Conv_number"]["Pacmax"] = 40
        #input_data["convdc"]["$Conv_number"]["Pacmin"] = 40
        #input_data["convdc"]["$Conv_number"]["Imax"] = 4000
        #input_data["convdc"]["$Conv_number"]["basekVac"] = 225

        AC_number += 1
        Conv_number += 1
    end

    corr_DC_bus_set = Vector()
    corr_DC_bus = 0
    new_branches = Dict{String,Any}()
    for zone in keys(relocation_dict)
        for (g_id, gen) in relocation_dict["$zone"]
            new_gen_bus = relocation_dict["$zone"]["$g_id"]["gen_bus"]
            push!(corr_DC_bus_set,corr_DC_bus)
            corr_DC_bus = relocation_dict["$zone"]["$g_id"]["corresponding_DCbus"] #corresponding_DCbus
            DC_to_ACbus = 0
            for (c,conv) in input_data["convdc"]
                if conv["busdc_i"] == corr_DC_bus
                    DC_to_ACbus = conv["busac_i"]
                end
            end
            
            input_data["gen"]["$g_id"]["AC_cluster"] = DC_to_ACbus
            input_data["gen"]["$g_id"]["corr_DC_bus"] = corr_DC_bus
        
            input_data["branch"]["$ACbranch_number"] = deepcopy(reference_acbranch)
            input_data["branch"]["$ACbranch_number"]["source_id"][2] = ACbranch_number
            input_data["branch"]["$ACbranch_number"]["f_bus"] = new_gen_bus
            input_data["branch"]["$ACbranch_number"]["t_bus"] = DC_to_ACbus
            input_data["branch"]["$ACbranch_number"]["name"] = "WindFarm connector"
            input_data["branch"]["$ACbranch_number"]["rate_a"] = 101
            input_data["branch"]["$ACbranch_number"]["rate_b"] = 101
            input_data["branch"]["$ACbranch_number"]["rate_c"] = 101
            input_data["branch"]["$ACbranch_number"]["br_x"] = 0.01
            input_data["branch"]["$ACbranch_number"]["index"] = ACbranch_number
            input_data["branch"]["$ACbranch_number"]["interconnector"] = false
            input_data["branch"]["$ACbranch_number"]["transformer"] = false
            new_branches["$ACbranch_number"] = deepcopy(input_data["branch"]["$ACbranch_number"])
            ACbranch_number +=1

            if gen["year"] < 2040
                if !(corr_DC_bus in corr_DC_bus_set)
                    rating = get_clustering_rating(corr_DC_bus,relocation_dict["$zone"])/100
                    old_gen_bus = relocation_dict["$zone"]["$g_id"]["onshore_bus"] #AC bus
                    input_data["branch"]["$ACbranch_number"] = deepcopy(reference_acbranch)
                    input_data["branch"]["$ACbranch_number"]["source_id"][2] = ACbranch_number
                    input_data["branch"]["$ACbranch_number"]["name"] = "WindFarm connector"
                    input_data["branch"]["$ACbranch_number"]["rate_a"] = rating
                    input_data["branch"]["$ACbranch_number"]["rate_b"] = rating
                    input_data["branch"]["$ACbranch_number"]["rate_c"] = rating
                    input_data["branch"]["$ACbranch_number"]["br_x"] = 0.01
                    input_data["branch"]["$ACbranch_number"]["f_bus"] = DC_to_ACbus
                    input_data["branch"]["$ACbranch_number"]["t_bus"] = old_gen_bus
                    input_data["branch"]["$ACbranch_number"]["index"] = ACbranch_number
                    input_data["branch"]["$ACbranch_number"]["interconnector"] = false
                    input_data["branch"]["$ACbranch_number"]["transformer"] = false
                    new_branches["$ACbranch_number"] = deepcopy(input_data["branch"]["$ACbranch_number"])

                    ACbranch_number +=1
                end
            elseif gen["year"] >= 2040 && use_1MW_connection
                if !(corr_DC_bus in corr_DC_bus_set)
                    old_gen_bus = relocation_dict["$zone"]["$g_id"]["onshore_bus"] #AC bus
                    input_data["branch"]["$ACbranch_number"] = deepcopy(reference_acbranch)
                    input_data["branch"]["$ACbranch_number"]["source_id"][2] = ACbranch_number
                    input_data["branch"]["$ACbranch_number"]["name"] = "WindFarm connector"
                    input_data["branch"]["$ACbranch_number"]["rate_a"] = 0.01
                    input_data["branch"]["$ACbranch_number"]["rate_b"] = 0.01
                    input_data["branch"]["$ACbranch_number"]["rate_c"] = 0.01
                    input_data["branch"]["$ACbranch_number"]["br_x"] = 0.01
                    input_data["branch"]["$ACbranch_number"]["WF_conn"] = 1
                    input_data["branch"]["$ACbranch_number"]["f_bus"] = DC_to_ACbus
                    input_data["branch"]["$ACbranch_number"]["t_bus"] = old_gen_bus
                    input_data["branch"]["$ACbranch_number"]["index"] = ACbranch_number
                    input_data["branch"]["$ACbranch_number"]["interconnector"] = false
                    input_data["branch"]["$ACbranch_number"]["transformer"] = false
                    new_branches["$ACbranch_number"] = deepcopy(input_data["branch"]["$ACbranch_number"])

                    ACbranch_number +=1
                end
                
            end         
        end        
    end    
   
    return new_DC_buses, relocation_dict, new_branches
end

function check_OFFwind_capacities(EU_grid,zone,tyndp_version,scenario,climate_year)

    Years_dict = Dict{String,Any}()
    Years_dict["2020"] = Dict{String,Any}()
    Years_dict["2020"]["DE"] = ["2030","2040"]
    Years_dict["2020"]["GA"] = ["2030","2040"]
    Years_dict["2020"]["NT"] = ["2025","2030","2040"]
    Years_dict["2024"] = Dict{String,Any}()
    Years_dict["2024"]["DE"] = ["2030","2040","2050"]
    Years_dict["2024"]["GA"] = ["2030","2040","2050"]
    Years_dict["2024"]["NT"] = ["2030","2040","2050"]
    
    OFFwind_capacities = Dict{String,Any}()
    OFFwind_capacities_zone = Dict{String,Any}()
    yearly_input_data = Dict{String,Any}()
    for Year in Years_dict["$tyndp_version"]["$scenario"]
        yearly_input_data["$Year"] = deepcopy(EU_grid)
        input_data = yearly_input_data["$Year"]
        ntcs, zones, arcs, tyndp_capacity, tyndp_demand, gen_types, gen_costs, emission_factor, inertia_constants, start_up_cost, node_positions = _EUGO.get_grid_data(tyndp_version, scenario, Year, climate_year)
        zone_mapping = _EUGO.map_zones()
        scenario_id = "$scenario$Year"
        _EUGO.scale_generation!(tyndp_capacity, input_data, scenario_id, climate_year, zone_mapping)
        
        for (g, gen) in input_data["gen"]
            if gen["type_tyndp"] == "Offshore Wind"
                zone = gen["zone"]
                if !haskey(OFFwind_capacities,"$g")
                    OFFwind_capacities["$g"] = []
                end
                OFFwind_capacities["$g"] = push!(OFFwind_capacities["$g"],gen["pmax"]*100)

                if !haskey(OFFwind_capacities_zone,zone)
                    OFFwind_capacities_zone[zone] = Dict{String,Any}()
                end
                if !haskey(OFFwind_capacities_zone[zone],"$Year")
                    OFFwind_capacities_zone[zone]["$Year"] = 0
                end
                OFFwind_capacities_zone[zone]["$Year"] += (gen["pmax"]*100) #MW
            end
        end
    end
    
    return OFFwind_capacities, OFFwind_capacities_zone
end

function plot_OFFwind_capacities(input_data,zone,tyndp_version,scenario,climate_year)

    OFFwind_capacities, OFFwind_capacities_zone = check_OFFwind_capacities(input_data,zone,tyndp_version,scenario,climate_year)

    years = collect(keys(OFFwind_capacities_zone["$zone"]))
    sort!(years)
    capacities = [get(OFFwind_capacities_zone["$zone"],year,0) for year in years]

    # Plot the capacities
    P1 = Plots.bar()
    Plots.bar!(years,(capacities/1000),title="Offshore Wind Capacities for $zone" , xlabel="Year", ylabel="Capacity (GW)",legend=false,guidefont=12, xtickfont=12, ytickfont=12)

    display(P1)
end

function update_conv_input(nodal_input)
    for (i,conv) in nodal_input["convdc"]
        if conv["Pacrated"] <= 150
            conv["Pacrated"] = 150
            conv["Pacmax"] = 150
            conv["Pacmin"] = -150
        end
        conv["transformer"] = 0
        conv["reactor"] = 0
        conv["filter"] = 0
    end
    return nodal_input
end

function add_VOLL_generation(EU_grid)
    index = 100000
    for (i,load) in EU_grid["load"]
        load_bus = load["load_bus"]
        zone = load["zone"]
        country = load["country"]
        EU_grid["gen"]["$index"] = Dict{String,Any}()
        EU_grid["gen"]["$index"]["zone"] = zone
        EU_grid["gen"]["$index"]["type_tyndp"] = "VOLL"
        EU_grid["gen"]["$index"]["model"] = 2
        EU_grid["gen"]["$index"]["gen_bus"] = load_bus
        EU_grid["gen"]["$index"]["pmax"] = 200
        EU_grid["gen"]["$index"]["country"] = country
        EU_grid["gen"]["$index"]["vg"] = 1.0
        EU_grid["gen"]["$index"]["source_id"] = ["gen", index]
        EU_grid["gen"]["$index"]["index"] = index
        EU_grid["gen"]["$index"]["cost"] = [60, 0]
        EU_grid["gen"]["$index"]["qmax"] = 1.77
        EU_grid["gen"]["$index"]["gen_status"] = 1
        EU_grid["gen"]["$index"]["qmin"] = -1.77
        EU_grid["gen"]["$index"]["type"] = "VOLL"
        EU_grid["gen"]["$index"]["pmin"] = 0
        EU_grid["gen"]["$index"]["ncost"] = 2
    

        index += 1
    end
    return EU_grid
end

function add_offshore_hub(input_data)
    
    country_dict = Dict()
    # Verzamel landen per zone in country_dict
    for (b_id, bus) in input_data["bus"]
        if !haskey(country_dict, bus["zone"])
            country_dict[bus["zone"]] = bus["country"]
        end   
    end

    reference_key_DC = rand(keys(input_data["busdc"]))
    reference_bus_DC = deepcopy(input_data["busdc"]["$reference_key_DC"])
    
    file = "./data_sources/Relocation_WindFarms.xlsx"
    xls = XLSX.readtable(file, "Blad2")
    
    data, headers = xls
    
    # Kolommen indexeren
    name_col = findfirst(==(:Offshore_Hub), headers) 
    idx_col = findfirst(==(:DC_bus), headers)
    lat_col = findfirst(==(:lat), headers)
    lon_col = findfirst(==(:lon), headers)
    zone_col = findfirst(==(:zone), headers)
    
     # Loop door de gegevens
     for i in 1:length(data[1])
        zone = data[zone_col][i]
        name = data[name_col][i]
        latitude = data[lat_col][i]
        longitude = data[lon_col][i]
        dc_index = data[idx_col][i] 
            
        input_data["busdc"]["$dc_index"] = deepcopy(reference_bus_DC)
        input_data["busdc"]["$dc_index"]["lat"] = latitude
        input_data["busdc"]["$dc_index"]["lon"] = longitude
        input_data["busdc"]["$dc_index"]["name"] = name
        input_data["busdc"]["$dc_index"]["source_id"][2] = dc_index
        input_data["busdc"]["$dc_index"]["index"] = dc_index
        input_data["busdc"]["$dc_index"]["zone"] = country_dict[zone]
    end

end