"""
Overview of functions in `Analyse_generation.jl`:

1. Analyse_generation_types(hour_range, start_hour, nodal_input, nodal_result)
    - Analyzes electricity generation over a selected range of hours.
    - Computes total generation by generator type and storage.
    - Displays a pie chart summarizing the generation mix.
    - Prompts user to select generator types to plot.
    - Plots time series of generation and compares it to total load.
    - Output: Displays summary statistics and interactive plots.

2. Capacity_installed(nodal_input)
    - Calculates the total installed generation capacity per generator type.
    - Extracts generator type from the `type_tyndp` field in the input.
    - Sums `pmax` values for all generators of each type (converted to MW).
    - Output: Returns a dictionary with total installed capacity (MW) by type.
"""

"""
    Analyse_generation_types(hour_range,start_hour,nodal_input,nodal_result)

Analyse and visualize electricity generation by generator type and storage over a specified range of hours.

    # Arguments
    - `hour_range`: Range of hours to analyze (e.g., `1:24`).
    - `start_hour`: The first hour in the full simulation (used to adjust indices).
    - `nodal_input`: Dictionary containing input data for the nodal model.
    - `nodal_result`: Dictionary containing simulation results for the nodal model.

    # Description
    This function performs the following:
    1. Aggregates total generation by generator type and storage.
    2. Generates a pie chart showing the contribution of each type.
    3. Builds a time series of generation and load for the selected types.
    4. Asks the user which types they wish to plot.
    5. Plots generation vs. load over time for the selected types.

    # Note
    - Be careful when using a result based on the reduced timeseries. If you use a reduced timeseries and want to plot the 
    pie diagram for a full year, you need to adjust the values using the corresponding factor. (not implemented here yet)

"""

function Analyse_generation_types(hour_range,start_hour,nodal_input,nodal_result,output_dir_fig)
    # Collect unique generator types from nodal input
    types = []
    for (g_id, g) in nodal_input["gen"]
        push!(types, g["type"])
    end
    unique_types = unique(types)

    # Initialize dictionary to store total generation per type (in GWh)
    total_generation = Dict{String, Float64}()
    for i in unique_types
        total_generation["$i"] = 0.0
    end
    total_generation["Storage"] = 0.0  # Add storage as a generation type

    # Loop over all hours and sum up generation per generator and storage
    for h in hour_range
        for (g_id, g) in nodal_input["gen"]
            type_tyndp = g["type"]
            if haskey(nodal_result["$h"]["solution"]["gen"], g_id)
                # Convert MW to GWh (100 MW * 1 hour / 1000)
                total_generation[type_tyndp] += nodal_result["$h"]["solution"]["gen"][g_id]["pg"] * 100 / 1000
            end
        end
        for (s_id, storage) in nodal_input["storage"]
            if haskey(nodal_result["$h"]["solution"]["storage"], s_id)
                total_generation["Storage"] += -nodal_result["$h"]["solution"]["storage"][s_id]["ps"] * 100 / 1000
            end
        end
    end

    # Prepare pie chart data by filtering only positive values
    labels = collect(keys(total_generation))
    valuez = collect(values(total_generation))
    positive_indices = valuez .>= 0
    filtered_labels = labels[positive_indices] #energy sources with a positive (or zero) net injection during the selected period.
    println("Filtered labels: ", filtered_labels)
    filtered_values = valuez[positive_indices]

    # Display pie chart of energy generation distribution
    P1 = Plots.pie(filtered_labels, filtered_values)
    Plots.title!("Energy Generation Distribution (Hours $(minimum(hour_range)) to $(maximum(hour_range)))")
    Plots.display(P1)

    plot_filename = joinpath(output_dir_fig, join(["Pie_diagram_generation.svg"]))
    Plots.savefig(P1, plot_filename)

    # Print summary of total generation by type (including negative if any)
    println("Energy Generation Summary (Hours $(minimum(hour_range)) to $(maximum(hour_range)))")
    total_sum = 0.0
    for (label, value) in zip(labels, valuez)
        println("Generator Type: $label - Total Generation (GWh): $value")
        total_sum += value * 100 / 1000  # Convert GWh to TWh
    end
    println("\nTotal Generation (TWh) over all types: $total_sum")


    # Calculate generation per hour per generator type
    Generation_per_hour = Dict{String, Any}()
    for type in unique_types
        generation_per_type = Vector{Float64}()
        for hour in hour_range
            hourly_generation = 0.0
            for (g_idx, gen) in nodal_result["1"]["solution"]["gen"]
                if nodal_input["gen"]["$g_idx"]["type"] == type
                    hourly_generation += nodal_result["$hour"]["solution"]["gen"][g_idx]["pg"] * 100 #in MWh
                end
            end
            push!(generation_per_type, hourly_generation)
        end
        Generation_per_hour[type] = generation_per_type
    end

    # Storage generation per hour (as negative dispatch)
    storage_generation = Vector{Float64}()
    for hour in hour_range
        hourly_generation = 0.0
        for (s_idx, storage) in nodal_input["storage"]
            if haskey(nodal_result["$hour"]["solution"]["storage"], s_idx)
                hourly_generation += -nodal_result["$hour"]["solution"]["storage"][s_idx]["ps"] * 100 #in MWh
            end
        end
        push!(storage_generation, hourly_generation)
    end
    Generation_per_hour["Storage"] = storage_generation

     # Compute total generation per hour (all types)
    total_generation = Vector{Float64}()
    for hour in hour_range
        hour_idx = hour - start_hour + 1
        hourly_generation = 0.0
        for (type, data) in Generation_per_hour
            hourly_generation += data[hour_idx]
        end
        push!(total_generation, hourly_generation)
    end
    Generation_per_hour["Total"] = total_generation

    # Compute total load per hour
    Load_per_hour = Vector{Float64}()
    for hour in hour_range
        hourly_load = 0.0
        for (l_idx, load) in nodal_input["load"]
            hourly_load += nodal_result["$hour"]["solution"]["load"][l_idx]["pflex"] * 100 #in MWh
        end
        push!(Load_per_hour, hourly_load)
    end


    # Prompt user for types to plot
    available_types = ["Solar PV", "Offshore", "Onshore", "Hard Coal", "Oil", "Hydro Run-of-River",
                       "Gas", "XB_dummy", "Biomass", "Nuclear", "Lignite", "Storage", "VOLL"]
    println("Available generation types: ", join(available_types, ", "))
    println("Enter the types you want to plot, separated by commas (e.g. Solar PV, Gas, Nuclear): ")
    input = readline()
    selected_types = split(input, ",") .|> strip
    selected_types = intersect(selected_types, available_types)

    if isempty(selected_types)
        println("No valid types selected. Nothing will be plotted.")
    else
        # Create generation vs load time series plot
        P3 = Plots.plot()
        time = 1:length(first(values(Generation_per_hour)))

        for i in selected_types
            # Custom plotting for selected types
            Plots.plot!(time, Generation_per_hour["$i"] ./ 1000, label="$i", linewidth=2, grid=false)
        end

        # Plot total load
        Plots.plot!(time, Load_per_hour ./ 1000, label="Load", linewidth=2, linestyle=:dash, size=(800, 600))

        # Axis settings
        Plots.xlims!(0.8, 15.2)
        Plots.xticks!(1:1:15)
        Plots.ylims!(-50, 250)

        Plots.xlabel!("Scenario")
        Plots.ylabel!("Power (GW)")
        Plots.title!("Electricity Generation and Load")

        display(P3)

        plot_filename = joinpath(output_dir_fig, join(["Selected_gen_and_load.svg"]))
        Plots.savefig(P3, plot_filename)
    end    
    # Create generation vs load time series plot
    P2 = Plots.plot()
    time = 1:length(first(values(Generation_per_hour)))

    # Custom plotting for selected types
    Plots.plot!(time, Generation_per_hour["Solar PV"] ./ 1000, label="Solar PV", linewidth=2, grid=false)
    Plots.plot!(time, Generation_per_hour["Offshore"] ./ 1000, label="Offshore Wind", linewidth=2)
    Plots.plot!(time, Generation_per_hour["Onshore"] ./ 1000, label="Onshore Wind", linewidth=2)
    Plots.plot!(time, Generation_per_hour["VOLL"] ./ 1000, label="Load shedding", linewidth=2)
    Plots.plot!(time, Generation_per_hour["XB_dummy"] ./ 1000, label="Cross Border", linewidth=2, linestyle=:dash)

    # Combine non-RES generation for a single line
    non_res_data = Generation_per_hour["Hard Coal"] .+ Generation_per_hour["Oil"] .+
                Generation_per_hour["Gas"] .+ Generation_per_hour["Biomass"] .+
                Generation_per_hour["Nuclear"] .+ Generation_per_hour["Lignite"] .+
                Generation_per_hour["Hydro Run-of-River"] .+ Generation_per_hour["Storage"]
    Plots.plot!(time, non_res_data ./ 1000, label="Non-Res", linewidth=2)

    # Plot total load
    Plots.plot!(time, Load_per_hour ./ 1000, label="Load", linewidth=2, linestyle=:dash, size=(800, 600))

    # Axis settings
    Plots.xlims!(0.8, 15.2)
    Plots.xticks!(1:1:15)
    Plots.ylims!(-50, 250)

    Total_load = sum(Load_per_hour)
    println("Total Load (GW): ", Total_load)

    Plots.xlabel!("Scenario")
    Plots.ylabel!("Power (GW)")
    Plots.title!("Electricity Generation and Load")

    display(P2)

    plot_filename = joinpath(output_dir_fig, join(["Electricity_gen_and_load.svg"]))
    Plots.savefig(P2, plot_filename)
end

"""
    Capacity_installed(nodal_input)

Compute the total installed generation capacity per generator type.

    # Arguments
    - `nodal_input`: Dictionary containing input data for the nodal model.

    # Output
    - A dictionary where each key is a generator type (`type_tyndp`) and the value is the total installed capacity in MW.

    # Description
    This function loops through the `nodal_input["gen"]` structure to:
    1. Identify all unique generator types based on `type_tyndp`.
    2. Sum the maximum generation capacity (`pmax`) for each type.
"""

function Capacity_installed(nodal_input)
    println("Installed capacity by technology (in MW):\n")

    # Gather all generator types from the input data
    types = []
    for (g_id, g) in nodal_input["gen"]
        push!(types, g["type_tyndp"])
    end
    unique_types = unique(types)

    # Initialize a dictionary to store total installed capacity per type
    total_capacity = Dict{String, Float64}()
    for i in unique_types
        total_capacity["$i"] = 0.0
    end

    # Sum installed capacity for each type
    for (g_id, g) in nodal_input["gen"]
        type = g["type_tyndp"]
        total_capacity[type] += g["pmax"] * 100  # Convert from GW to MW if needed
    end

    # Print nicely formatted output
    for (type, cap) in sort(collect(total_capacity); by=x->x[1])  # Sort by type name
        println(" - $(rpad(type, 20)) : $(round(cap, digits=2)) MW")
    end
end