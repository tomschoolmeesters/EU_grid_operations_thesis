"""
    Analyse_generator(g,start_hour,number_of_hours,nodal_input,nodal_result,timeseries_data)

Analyzes the generation profile and curtailment behavior of a specified generator
over a selected time window within a planning year. It visualizes the power output, 
highlights infeasible simulation periods, and (for RES generators) computes and 
plots curtailment metrics.

# Arguments
- `g`: Index or identifier of the generator to be analyzed.
- `start_hour`: The starting hour of the analysis period within the year (e.g. 1 for Jan 1st 00:00).
- `number_of_hours`: Total number of hours to analyze. Make sure this does not exceeds the length of the nodal_result data.
- `nodal_input`: A dictionary containing input data for the nodal model, including generator properties.
- `nodal_result`: A dictionary containing results from the nodal analysis, including power generation solutions.
- `timeseries_data`: Dictionary containing time series data, including demand profiles.

# Output
- No return value.
- Displays:
    - Power production profile plot (with infeasible hours highlighted).
    - For RES types ("Offshore Wind", "Onshore Wind", "Solar PV"): a curtailment percentage plot.

# Dependencies
- Relies on the external function `RES_curtailment_WO(...)` to compute curtailment for RES types.
  This fuction is defined in get_grid_indices.jl
"""

function Analyse_generator(g,start_hour,number_of_hours,nodal_input,nodal_result,timeseries_data) # generator index g, start hour and planning year (2025,2030,2040)
    
    # Get generator properties from input data
    type = nodal_input["gen"]["$g"]["type_tyndp"]
    zone = nodal_input["gen"]["$g"]["zone"]
    bus = nodal_input["gen"]["$g"]["gen_bus"]
    pmax = nodal_input["gen"]["$g"]["pmax"] * 100  # Convert to MW

    # Print generator details
    println("--------------------------------")
    println("Generator index: ", g)
    println("Generator type: ", type)
    println("Generator zone: ", zone)
    println("Generator bus: ", bus)
    println("Theoretical maximum power: ", pmax, " MW")
    println("--------------------------------")

    # Build the production time series for the analysis window
    production = []
    for i in start_hour:(start_hour + number_of_hours - 1)
        if nodal_result["$i"]["objective"] !== nothing
            push!(production, nodal_result["$i"]["solution"]["gen"]["$g"]["pg"] * 100)
        else
            push!(production, 0.0001)  # Use small value to indicate infeasibility
        end
    end

    # Plot production profile
    P1 = Plots.plot(production, label="Production")
    Plots.title!("Production profile of generator $g")
    Plots.xlabel!("Time [h]")
    Plots.ylabel!("Power [MW]")

    # Highlight infeasible periods (red dots)
    time = 1:length(production)
    highlight_indices = findall(x -> x == 0.0001, production)
    Plots.scatter!(time[highlight_indices], production[highlight_indices],
             label="Infeasible", color=:red, marker=:circle)

    # Display the production plot for non-RES generators
    if !(type in ["Offshore Wind", "Onshore Wind", "Solar PV"])
        display(P1)
    end
    
    # RES-specific curtailment analysis
    if type == "Offshore Wind"
        gen_type = "wind_offshore"

        # Calculate curtailment and the uncurtailed energy time series for offshore wind
        Curtailment, Uncurtailed = RES_curtailment_WO(g, gen_type, nodal_result, nodal_input, timeseries_data, start_hour,number_of_hours)
        # Add the uncurtailed energy series to the existing production plot
        Plots.plot!(Uncurtailed, label="Uncurtailed Energy")
        display(P1)

        # Create a new plot to show the curtailment percentage over time
        P2 = Plots.plot(Curtailment * 100, label="Curtailment")
        Plots.title!("Curtailment of generator $g")
        Plots.xlabel!("Time [h]")
        Plots.ylabel!("Curtailment [%]")
        display(P2)

        # Identify all time steps where curtailment exceeds 50% (can be adjusted)
        high_curt = findall(x -> x > 0.5, Curtailment)
        high_curt = high_curt .+ (start_hour - 1) # Adjust to absolute hour

    elseif type == "Onshore Wind"
        gen_type = "wind_onshore"

        # Calculate curtailment and the uncurtailed energy time series for offshore wind
        Curtailment, Uncurtailed = RES_curtailment_WO(g, gen_type, nodal_result, nodal_input, timeseries_data, start_hour, number_of_hours)
        # Add the uncurtailed energy series to the existing production plot
        Plots.plot!(Uncurtailed, label="Uncurtailed Energy")
        display(P1)

        # Create a new plot to show the curtailment percentage over time
        P2 = Plots.plot(Curtailment * 100, label="Curtailment")
        Plots.title!("Curtailment of generator $g")
        Plots.xlabel!("Time [h]")
        Plots.ylabel!("Curtailment [%]")
        display(P2)

        # Identify all time steps where curtailment exceeds 50% (can be adjusted)
        high_curt = findall(x -> x > 0.5, Curtailment)
        high_curt = high_curt .+ (start_hour - 1) # Adjust to absolute hour

    elseif type == "Solar PV"
        gen_type = "solar_pv"

        # Calculate curtailment and the uncurtailed energy time series for offshore wind
        Curtailment, Uncurtailed = RES_curtailment_WO(g, gen_type, nodal_result, nodal_input, timeseries_data, start_hour, number_of_hours)
        # Add the uncurtailed energy series to the existing production plot
        Plots.plot!(Uncurtailed, label="Uncurtailed Energy")
        display(P1)

        # Create a new plot to show the curtailment percentage over time
        P2 = Plots.plot(Curtailment * 100, label="Curtailment")
        Plots.title!("Curtailment of generator $g")
        Plots.xlabel!("Time [h]")
        Plots.ylabel!("Curtailment [%]")
        display(P2)

        # Identify all time steps where curtailment exceeds 50% (can be adjusted)
        high_curt = findall(x -> x > 0.5, Curtailment)
        high_curt = high_curt .+ (start_hour - 1)
    end
end