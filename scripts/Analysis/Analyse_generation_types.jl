function Analyse_generation_types(hour_range)
    # Maak een lijst van unieke generator types
    types = []
    for (g_id, g) in nodal_input["gen"]
        push!(types, g["type"])
    end
    unique_types = unique(types)

    # Initialiseer een dictionary voor het opslaan van totale generatie per type
    total_generation = Dict{String, Float64}()
    for i in unique_types
        total_generation["$i"] = 0.0
        total_generation["Storage"] = 0.0
    end

    # Loop over alle uren in de gegeven range
    for h in hour_range
        for (g_id, g) in nodal_input["gen"]
            type_tyndp = g["type"]
            if haskey(nodal_result["$h"]["solution"]["gen"], g_id)
                total_generation[type_tyndp] += nodal_result["$h"]["solution"]["gen"][g_id]["pg"]*100/1000 #GWh
            end
        end
        for (s_id, storage) in nodal_input["storage"]
            if haskey(nodal_result["$h"]["solution"]["storage"], s_id)
                total_generation["Storage"] += -nodal_result["$h"]["solution"]["storage"][s_id]["ps"]*100/1000 #GWh
            end
        end
    end

    # Pie-diagram
    labels = collect(keys(total_generation))       # Extract labels
    waarden = collect(values(total_generation))    # Extract values
    positive_indices = waarden .> 0                # Filter out non-positive values
    #println("Positive indices: ", positive_indices)
    # Filter data for the pie chart (ignoring negative values)
    filtered_labels = labels[positive_indices]
    println("Filtered labels: ", filtered_labels)
    filtered_values = waarden[positive_indices]
    #println("Filtered values: ", filtered_values)

    # Generate the pie chart
    P1 = Plots.pie(filtered_labels, filtered_values)
    title!("Energy Generation Distribution (Hours $(minimum(hour_range)) to $(maximum(hour_range)))")
    display(P1)

    # Print de labels en waarden (alleen de niet-gefilterde)
    println("Energy Generation Summary (Hours $(minimum(hour_range)) to $(maximum(hour_range)))")
    total_sum = 0.0
    for (label, value) in zip(labels, waarden)
        println("Generator Type: $label - Total Generation (GWh): $value")
        total_sum += value*100/1000 #GWh
    end

    # Print de totale som van alle waarden
    println("\nTotal Generation (GWh) over all types: $total_sum")


    # Loop over alle unieke types en bereken de totale generatie per type per uur
    Generation_per_hour = Dict{String,Any}()
    for type in unique_types
        #if type != "XB_dummy"
            generation_per_type = Vector{Float64}()
            for hour in hour_range
                hourly_generation = 0
                for (g_idx,gen) in nodal_input["gen"]
                    if gen["type"] == type
                        hourly_generation += nodal_result["$hour"]["solution"]["gen"][g_idx]["pg"]*100
                    end
                end
                push!(generation_per_type, hourly_generation)
            end
            Generation_per_hour[type] = generation_per_type
        #end 
    end
    generation_per_type = Vector{Float64}()
    for hour in hour_range
        hourly_generation = 0
        for (s_idx,storage) in nodal_input["storage"]
            if haskey(nodal_result["$hour"]["solution"]["storage"], s_idx)
                hourly_generation += -nodal_result["$hour"]["solution"]["storage"][s_idx]["ps"]*100
            end
        end
        push!(generation_per_type, hourly_generation)
    end
    Generation_per_hour["Storage"] = generation_per_type


    total_generation = Vector{Float64}()
    for hour in hour_range
        hourly_generation = 0
        for (type,data) in Generation_per_hour
            hourly_generation += data[hour]
        end
        push!(total_generation, hourly_generation)
    end
    Generation_per_hour["Total"] = total_generation


    Load_per_hour = Vector{Float64}()
    for hour in hour_range
        hourly_load = 0
        for (l_idx,load) in nodal_input["load"]
            hourly_load += (nodal_result["$hour"]["solution"]["load"][l_idx]["pflex"])*100
        end
        push!(Load_per_hour, hourly_load)
    end


    # Beschikbare generatie types
    available_types = ["Solar PV", "Offshore", "Onshore", "Hard Coal", "Oil", "Hydro Run-of-River",
    "Gas", "XB_dummy", "Biomass", "Nuclear", "Lignite", "Storage"]

    # Vraag de gebruiker welke types te plotten
    println("Beschikbare generatie types: ", join(available_types, ", "))
    println("Geef de types in die je wilt plotten, gescheiden door komma’s (bijv. Solar PV, Gas, Nuclear): ")
    input = readline()

    # Converteer de invoer naar een lijst van geselecteerde types
    selected_types = split(input, ",") .|> strip  # Verwijdert spaties rondom de invoer

    # Filter de selectie op geldige types
    selected_types = intersect(selected_types, available_types)

    if isempty(selected_types)
        println("Geen geldige types geselecteerd. Er wordt niets geplot.")
    else
    # Plot met generatie en load per uur
    P2 = Plots.plot()
    time = 1:length(first(values(Generation_per_hour)))

    for (type, data) in Generation_per_hour
        if type in selected_types
            Plots.plot!(time, data ./ 1000, label=type, linewidth=2)
        end
    end

    Plots.plot!(time, Load_per_hour ./ 1000, label="Load", linewidth=2, linestyle=:dash)

    # Labels en titel toevoegen
    xlabel!("Time")
    ylabel!("Power (GW)")
    title!("Electricity Generation and Load")

    display(P2)
    end

end

function Capacity_installed()
    types = []
    for (g_id, g) in nodal_input["gen"]
        push!(types, g["type_tyndp"])
    end
    unique_types = unique(types)
    
    total_capacity = Dict{String, Float64}()
    for i in unique_types
        total_capacity["$i"] = 0.0
    end

    for (g_id,g) in nodal_input["gen"]
        type = g["type_tyndp"]
        total_capacity["$type"] += g["pmax"]*100
    end
    return total_capacity
end