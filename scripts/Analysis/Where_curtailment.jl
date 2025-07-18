"""
Overview of functions in Where_curtailment.jl:

1. where_curtailment(nodal_input, nodal_result, timeseries_data; start_hour=1)
   - Identifies renewable generators (Solar PV, Onshore Wind, Offshore Wind) with significant curtailment.
   - Flags generators where curtailment exceeds 80% for more than 50% of the simulation hours.
   - Prints details for each curtailed generator, with emphasis on Offshore Wind.


2. scatter_curtailment(nodal_input, nodal_result, timeseries_data, number_of_hours; start_hour=1)
   - Generates two scatter plots of renewable energy curtailment:
     1. Curtailment per generator over all time steps.
     2. Curtailment per time moment across all generators.

"""

"""
    where_curtailment(nodal_input, nodal_result)

Identifies which renewable generators (Solar PV, Onshore Wind, Offshore Wind) experienced significant curtailment
based on a predefined condition. Specifically, it flags generators where the curtailment exceeds 80% for more than 50% of the time.

    # Arguments
    - `nodal_input::Dict`: Dictionary containing static generator metadata (e.g., type, location).
    - `nodal_result::Dict`: Dictionary containing simulation results per hour, including generation output.
    - `timeseries_data`: Variable containing time-series data (implicitly used in RES_curtailment_WO).
    - `start_hour::Int`: Represents the starting hour of analysis.

    # Output
    - No return value. Prints out information on generators with significant curtailment (especially Offshore Wind).

    # Dependencies
    - Relies on the external function `RES_curtailment_WO(...)` to compute curtailment for RES types.
    This fuction is defined in get_grid_indices.jl
"""

function where_curtailment(nodal_input,nodal_result,timeseries_data,number_of_hours; start_hour=1)
    where_curtailment = Dict() # Will store generator IDs with significant curtailment

    # Mapping TYNDP generator types to internal naming
    gen_types = Dict("Solar PV" => "solar_pv", 
                     "Onshore Wind" => "wind_onshore", 
                     "Offshore Wind" => "wind_offshore")

    # Loop through all generators in the results for the starting hour
    for g in keys(nodal_result["$start_hour"]["solution"]["gen"])
        gen_info = nodal_input["gen"]["$g"]
        gen_type_tyndp = get(gen_info, "type_tyndp", nothing)
        
        # Only evaluate curtailment for defined renewable types
        if haskey(gen_types, gen_type_tyndp)
            gen_type = gen_types[gen_type_tyndp]

            # Compute curtailment time series using external function
            Curtailment, _ = RES_curtailment_WO(g, gen_type, nodal_result, nodal_input, timeseries_data, start_hour,number_of_hours)
            
             # Store if curtailment exceeds 80% in more than 50% of the hours (can be adjusted)
            if Statistics.mean(Curtailment .> 0.8 )> 0.5
                where_curtailment[g] = Curtailment
            end
        end
    end

    # Print details for curtailed Offshore Wind generators
    for key in keys(where_curtailment)
        type = nodal_input["gen"]["$key"]["type_tyndp"]
        zone = nodal_input["gen"]["$key"]["zone"]
        bus = nodal_input["gen"]["$key"]["gen_bus"]
        #if type == "Offshore Wind" # Change to "Onshore Wind" or "Solar PV" if needed
            println("Generator: $key")
            println("   Type: $type --- Zone: $zone --- Bus: $bus\n")
        #end
    end

    # Print fallback message if no curtailment found
    if length(where_curtailment) == 0
        println("No curtailment")
    end
    
end

"""
    scatter_curtailment(nodal_input, nodal_result,timeseries_data,number_of_hours; start_hour=1)

Generates scatter plots of renewable energy curtailment, both:
1. Per generator across the entire simulation horizon.
2. Across all generators per time step.

    # Arguments
    - `nodal_input::Dict`: Static input data structure containing metadata about generators (types, locations, etc.).
    - `nodal_result::Dict`: Simulation results over all hours, containing actual generation values.
    - `timeseries_data`: Required by `RES_curtailment_WO`
    - `number_of_hours::Int`: Total number of simulation hours

    # Outputs
    - Saves two scatter plots as PNG:
        - `Curtailment_per_generator.png`: Shows curtailment for each generator across all hours.
        - `Curtailment_per_time.png`: Shows curtailment per time moment, over all generators.

    # Dependencies
    - Uses external function: `RES_curtailment_WO`
    - Uses: `Plots` package
"""

function scatter_curtailment(nodal_input,nodal_result,timeseries_data, number_of_hours; start_hour=1)
    Curt = Dict() # Stores curtailment time series per generator

    # Mapping TYNDP types to internal model names
    gen_types = Dict("Solar PV" => "solar_pv", 
                     "Onshore Wind" => "wind_onshore", 
                     "Offshore Wind" => "wind_offshore")

    # Loop through generators for the first hour to identify relevant RES units
    for g in keys(nodal_result["1"]["solution"]["gen"])
        gen_info = nodal_input["gen"]["$g"]
        gen_type_tyndp = get(gen_info, "type_tyndp", nothing)
        
        # Check if the generator type is in the defined types
        if haskey(gen_types, gen_type_tyndp)
            gen_type = gen_types[gen_type_tyndp]
            Curtailment, _ = RES_curtailment_WO(g, gen_type, nodal_result, nodal_input, timeseries_data, start_hour)
            Curt[g] = Curtailment # Store curtailment time series
        end
    end
    
    ### SCATTER PLOT 1: Curtailment per Generator Over Time ###
    gen = collect(keys(Curt))
    x_indices = Int[] # x-axis: generator index repeated per time step
    y_values_curt = Float64[] # y-axis: curtailment values

    for (i,key) in enumerate(gen)
        append!(x_indices,fill(i,length(Curt[key]))) # Repeating index per hour
        append!(y_values_curt,Curt[key])             # Add all curtailment values
    end
    # Create and save scatter plot
    P = Plots.scatter(
        x_indices, y_values_curt,
        xlabel = "Generators",
        ylabel = "Curtailment",
        title = "Curtailment per Generator",
        legend = false,
        xticks = (1:length(gen), gen),
        size = (3000, 1000)
    )  
    Plots.savefig("Curtailment_per_generator")

    ### SCATTER PLOT 2: Curtailment per Time Moment (across all generators) ###
    x_values_time = []  # x-axis: time steps
    y_values_curt = []  # y-axis: curtailment values

    # Loop over time and generators to build scatter points
    for t in 1:number_of_hours
        for (gen, values) in Curt
            push!(x_values_time, t)    # Time moment
            push!(y_values_curt, values[t])  # Corresponding curtailment
        end
    end

    # Create and save second scatter plot
   P2 = Plots.scatter(
        x_values_time, y_values_curt,
        xlabel = "Time Moment",
        ylabel = "Curtailment",
        title = "Curtailment per Time Moment",
        legend = false,
        xticks = ([], []),
        size = (2000, 1000)
    )
    Plots.savefig("Curtailment_per_time")
end