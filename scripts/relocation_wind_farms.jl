
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

function add_OFF_DC_buses!(input_data)
    relocation_dict = relocation_wind_farms()
    DC_number = maximum([bus["index"] for (b, bus) in input_data["busdc"]]) + 1
    println(DC_number)

    max_groups_dict = Dict(
        "BE" => 2,
        "DE" => 5,
        "DK1" => 3,
        "DK2" => 3,
        "FR" => 4,
        "NL" => 7,
        "NO1" => 1,
        "UK" => 6)

    new_DC_buses = Dict{String,Any}()
    for zone in keys(relocation_dict)
        println("Clustering zone $zone")
        max_groups = max_groups_dict["$zone"]
        DC_number, DC_bus = group_OFFwindfarms(relocation_dict,zone,max_groups,DC_number)

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
            input_data["branch"]["$ACbranch_number"]["index"] = ACbranch_number
            input_data["branch"]["$ACbranch_number"]["interconnector"] = false
            input_data["branch"]["$ACbranch_number"]["transformer"] = false
            new_branches["$ACbranch_number"] = deepcopy(input_data["branch"]["$ACbranch_number"])
            ACbranch_number +=1

            if !(corr_DC_bus in corr_DC_bus_set)
                old_gen_bus = relocation_dict["$zone"]["$g_id"]["old_gen_bus"] #AC bus
                input_data["branch"]["$ACbranch_number"] = deepcopy(reference_acbranch)
                input_data["branch"]["$ACbranch_number"]["source_id"][2] = ACbranch_number
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