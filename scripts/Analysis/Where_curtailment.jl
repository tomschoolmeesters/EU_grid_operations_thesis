function where_curtailment()
    start_hour = 1;
    where_curtailment = Dict()
    gen_types = Dict("Solar PV" => "solar_pv", 
                     "Onshore Wind" => "wind_onshore", 
                     "Offshore Wind" => "wind_offshore")

    for g in keys(nodal_result["1"]["solution"]["gen"])
        gen_info = nodal_input["gen"]["$g"]
        gen_type_tyndp = get(gen_info, "type_tyndp", nothing)
        
        # Check if the generator type is in the defined types
        if haskey(gen_types, gen_type_tyndp)
            gen_type = gen_types[gen_type_tyndp]
            Curtailment, _ = RES_curtailment_WO(g, gen_type, nodal_result, nodal_input, timeseries_data, start_hour)
            
            # Only store curtailment data if the condition is met
            if mean(Curtailment .> 0.3 )> 0.3
                where_curtailment[g] = Curtailment
            end
        end
    end

    for key in keys(where_curtailment)
        type = nodal_input["gen"]["$key"]["type_tyndp"]
        zone = nodal_input["gen"]["$key"]["zone"]
        bus = nodal_input["gen"]["$key"]["gen_bus"]
        println("Generator: $key")
        println("   Type: $type --- Zone: $zone --- Bus: $bus\n")
    end
    if length(where_curtailment) == 0
        println("No curtailment")
    end
    
end

using Plots
function scatter_curtailment()
    start_hour = 1;
    Curt = Dict()
    gen_types = Dict("Solar PV" => "solar_pv", 
                     "Onshore Wind" => "wind_onshore", 
                     "Offshore Wind" => "wind_offshore")

    for g in keys(nodal_result["1"]["solution"]["gen"])
        gen_info = nodal_input["gen"]["$g"]
        gen_type_tyndp = get(gen_info, "type_tyndp", nothing)
        
        # Check if the generator type is in the defined types
        if haskey(gen_types, gen_type_tyndp)
            gen_type = gen_types[gen_type_tyndp]
            Curtailment, _ = RES_curtailment_WO(g, gen_type, nodal_result, nodal_input, timeseries_data, start_hour)
            Curt[g] = Curtailment
        end
    end
    
    gen = collect(keys(Curt))
    x_indices = Int[]
    y_values_curt = Float64[]

    for (i,key) in enumerate(gen)
        append!(x_indices,fill(i,length(Curt[key])))
        append!(y_values_curt,Curt[key])
    end
    P = Plots.scatter(x_indices, y_values_curt,
            xlabel = "Generators",
            ylabel = "Curtailment",
            title = "Curtailment per Generator",
            legend = false,
            xticks = (1:length(gen), gen),
            size=(3000, 1000))
        
    Plots.savefig("Curtailment_per_generator")

    ### Tweede scatter plot ###
    x_values_time = []  # Tijdsmomenten
    y_values_curt = []  # Curtailmentwaarden

    # Genereer data voor scatter plot
    for t in 1:number_of_hours
        for (gen, values) in Curt
            push!(x_values_time, t)    # Tijdsmoment toevoegen aan x
            push!(y_values_curt, values[t])  # Curtailmentwaarde op dat moment aan y
        end
    end

    P2 = Plots.scatter(x_values_time, y_values_curt,
            xlabel = "Time Moment",
            ylabel = "Curtailment",
            title = "Curtailment per Time Moment",
            legend = false,
            xticks = ([], []),
            size = (2000, 1000))

    Plots.savefig("Curtailment_per_time")
end