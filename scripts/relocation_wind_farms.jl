function relocation_wind_farms()

    file = "./data_sources/Relocation_WindFarms.xlsx"
    xls = XLSX.readtable(file, "Blad1")
    
    data, headers = xls
    
    # Kolommen indexeren
    zone_col = findfirst(==(:zone), headers) 
    g_id_col = findfirst(==(:WindFarm), headers) 
    old_idx_col = findfirst(==(:old_index), headers)
    old_lat_col = findfirst(==(:old_lat), headers)
    old_lon_col = findfirst(==(:old_lon), headers)
    idx_col = findfirst(==(:index), headers)
    lat_col = findfirst(==(:lat), headers)
    lon_col = findfirst(==(:lon), headers)
    name_col = findfirst(==(:name), headers)  
    
    # Dictionary maken
    relocation_dict = Dict()
    
    # Loop door de gegevens
    for i in 1:length(data[1])
        zone = data[zone_col][i] 
        g_id = string(data[g_id_col][i])
        
        # Initialiseer land als het nog niet bestaat
        if !haskey(relocation_dict, zone)
            relocation_dict[zone] = Dict()
        end
        
        # Voeg g_id toe aan land
        relocation_dict[zone][g_id] = Dict(
            "old_gen_bus" => data[old_idx_col][i],
            "old_lat" => data[old_lat_col][i],
            "old_lon" => data[old_lon_col][i],
            "gen_bus" => data[idx_col][i],
            "lat" => data[lat_col][i],
            "lon" => data[lon_col][i],
            if data[name_col][i] !== nothing
                "name" => data[name_col][i]
            end
        )
    end
    return relocation_dict
end

function update_input_data(input_data)
    relocation_dict = relocation_wind_farms()
    country_dict = Dict()
    
    for (b_id,bus) in input_data["bus"]
        if !haskey(country_dict, bus["zone"])
            country_dict[bus["zone"]] = bus["country"]
        end   
    end

    rerference_key = rand(keys(input_data["bus"]))
    reference_bus = deepcopy(input_data["bus"]["$rerference_key"])

    for zone in keys(relocation_dict)
        for (g_id,gen) in relocation_dict["$zone"]
            new_gen_bus = relocation_dict["$zone"]["$g_id"]["gen_bus"]
            if !haskey(input_data["bus"], new_gen_bus)

                lat = relocation_dict["$zone"]["$g_id"]["lat"] 
                lon = relocation_dict["$zone"]["$g_id"]["lon"]
                name = relocation_dict["$zone"]["$g_id"]["name"]
                
                input_data["bus"]["$new_gen_bus"] = reference_bus
                input_data["bus"]["$new_gen_bus"]["lat"] = lat
                input_data["bus"]["$new_gen_bus"]["lon"] = lon
                input_data["bus"]["$new_gen_bus"]["zone"] = zone
                input_data["bus"]["$new_gen_bus"]["bus_i"] = new_gen_bus
                if name !== nothing
                    input_data["bus"]["$new_gen_bus"]["name"] =  name
                else
                    input_data["bus"]["$new_gen_bus"]["name"] = "$zone_$new_gen_bus"
                end
                input_data["bus"]["$new_gen_bus"]["country"] = country_dict["$zone"]
                input_data["bus"]["$new_gen_bus"]["source_id"][2] = new_gen_bus
                input_data["bus"]["$new_gen_bus"]["index"] = new_gen_bus
            
                if haskey(input_data["gen"], g_id)
                    input_data["gen"]["$g_id"]["gen_bus"] = new_gen_bus
                end

            end
        end
    end

end

function check_OFFwind_capacities(input_data,zone,tyndp_version,scenario,climate_year)

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
    for Year in Years_dict["$tyndp_version"]["$scenario"]
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

    # Plot the capacities
    P1 = Plots.bar()
    for (z_id,zone) in OFFwind_capacities_zone
        Years = collect(keys(zone))
        Capacities = collect(values(zone))
        Plots.bar!(Years,Capacities,title="Offshore Wind Capacities for $z_id" , xlabel="Year", ylabel="Capacity (MW)")
    end
    display(P1)
end