using Dates
"""
Overview of functions in get_grid_indices.jl:

1. hour_to_date(year, hour)
    - Converts a given hour index (1-8760) within a year to a readable calendar date and hour string.
    - Validates input hour range and returns formatted date-time string.

2. RES_curtailment_WO(g, gen_type, result, input, timeseries, start_hour, number_of_hours)
    - Computes hourly curtailment ratios and uncurtailed energy (MW) for a specified renewable generator.
    - Supports Solar PV, Offshore Wind, and Onshore Wind generators.

3. OFF_curtailment_red(nodal_input, nodal_result, timeseries_red, factor, number_of_hours)
    - Only for reduced time series.
    - Calculates overall weighted curtailment ratio for offshore wind over a reduced time series.

4. Congestion_index(result, number_of_hours)
    - Computes hourly congestion indices based on dual variables (nodal prices) from simulation results.
    - Measures price deviation across all AC and DC buses to indicate network congestion.

5. overall_congestion_index(result, factor)
    - Only for reduced time series.
    - Aggregates congestion index over the entire simulation horizon with weighting factors.
    - Returns a scalar congestion metric representing network-wide congestion.

6. plot_Congestion_index(result, number_of_hours)
    - Plots the congestion index time series for a specified number of hours.

7. Saturation_index(result, input)
    - Calculates the saturation index per hour measuring transmission line utilization relative to thermal limits.
    - Sums absolute power flows divided by rated capacities over all branches.

8. plot_Saturation_index(result, input)
    - Plots saturation index values over time sorted by hour.
"""

"""
    hour_to_date(year::Int, hour::Int)

Converts a given hour index (1-8760) within a year to a human-readable calendar date and time string.

    # Arguments
    - `year::Int`: The calendar year to which the hour index belongs.
    - `hour::Int`: The hour of the year (1 to 8760, assuming a non-leap year).

    # Output
    - Returns a formatted string in the form: `"Date: DD/MM/YYYY, Hour: HH:00"`.
      For example: `"Date: 15/2/2025, Hour: 17:00"`.

    # Dependencies
    - Uses the `Dates` module from the Julia standard library.
"""


function hour_to_date(year, hour)
    # Check if the hour value is within the valid range for a non-leap year
    if hour < 1 || hour > 8760
        println("The specified hour must be between 1 and 8760.")
        return
    end

    # Create a DateTime object for January 1st of the given year at 00:00
    start_date = DateTime(year, 1, 1, 0, 0)

    # Add (hour - 1) hours to get the correct date and time
    current_datetime = start_date + Hour(hour - 1)

    # Extract components of the date
    day_of_month = day(current_datetime)
    month_of_year = month(current_datetime)
    year_of_date = year(current_datetime)
    hour_of_day = hour(current_datetime)

    # Return a formatted string with the date and hour
    return "Date: $day_of_month/$month_of_year/$year_of_date, Hour: $hour_of_day:00"
end

"""
    RES_curtailment_WO(g, gen_type, result, input, timeseries, start_hour, number_of_hours)

Computes the hourly curtailment profile for a specific renewable energy generator (Solar PV, Offshore Wind, or Onshore Wind) over a simulation period.

    # Arguments
    - `g::Int`: Generator index (as used in the input and result dictionaries).
    - `gen_type::String`: Type of renewable generator (`"Solar PV"`, `"Offshore Wind"`, or `"Onshore Wind"`).
    - `result::Dict`: Dictionary containing simulation results, indexed by hour.
    - `input::Dict`: Static input data describing generator characteristics (e.g., `pmax`, zone).
    - `timeseries::Dict`: Time-series capacity factor data by generator type and zone.
    - `start_hour::Int`: Index of the first hour of the simulation.
    - `number_of_hours::Int`: Total number of hours in the simulation.

    # Output
    - Returns a tuple of two arrays:
        - `RES_Curtailment::Vector{Float64}`: Hourly curtailment ratios (0.0 to 1.0).
        - `Uncurtailed::Vector{Float64}`: Hourly uncurtailed energy values (in MW) = maximum available power.

    # Description
    - For each hour in the simulation, the function calculates the potential (uncurtailed) and actual (delivered) energy for the specified generator.
    - Curtailment is defined as the relative difference between potential and delivered energy:  
      `curtailment = (uncurtailed - delivered) / uncurtailed`
    - Infeasible hours (where no valid solution exists) are assigned a full curtailment value of `1.0`, and a flat energy profile is preserved.
    - If the generator is not active in a given hour's result, a warning is printed.

"""
function RES_curtailment_WO(g, gen_type, result, input, timeseries, start_hour, number_of_hours)
    # Preallocate arrays for curtailment values and uncurtailed energy
    RES_Curtailment = zeros(number_of_hours)
    Uncurtailed = zeros(number_of_hours)

    # Iterate over the simulation hours
    for t in 1:number_of_hours
        i = start_hour + t - 1  # Calculate the actual hour index

        # Check if the result for this hour exists and is valid
        if result["$i"]["objective"] !== nothing
            # Check if the generator exists in the solution for this hour
            if haskey(result["$i"]["solution"]["gen"], "$g")
                # Fetch generator details
                zone = input["gen"]["$g"]["zone"]
                CF = timeseries["$gen_type"][zone][i]

                # Compute uncurtailed and delivered energy
                uncurtailed_energy = CF * input["gen"]["$g"]["pmax"] * 100  # in MW
                energy_delivered = result["$i"]["solution"]["gen"]["$g"]["pg"] * 100  # in MW

                # Calculate curtailment ratio; avoid division by zero when uncurtailed_energy is 0
                curtailment = uncurtailed_energy == 0.0 ? 0.0 : (uncurtailed_energy - energy_delivered) / uncurtailed_energy

                # Store values in preallocated arrays
                Uncurtailed[t] = uncurtailed_energy
                RES_Curtailment[t] = curtailment
            else
                # Warn if the generator data is missing for this hour
                println("Generator not in result for hour $i")
            end
        else
            # Handle infeasibility case:
            # If no valid solution (e.g., infeasibility), assume full curtailment
            RES_Curtailment[t] = 1.0
            # Maintain previous uncurtailed value to keep a flat profile if possible
            Uncurtailed[t] = t == 1 ? 0.0 : Uncurtailed[t - 1] 
        end
    end

    return RES_Curtailment, Uncurtailed
end

"""
    OFF_curtailment_red(nodal_input, nodal_result, timeseries_red, factor, number_of_hours)

Calculates the overall offshore wind curtailment ratio over a reduced set of time steps, 
accounting for hourly weighting factors.

    # Arguments
    - `nodal_input::Dict`: Input dictionary containing static generator data, including capacity and type.
    - `nodal_result::Dict`: Dictionary containing simulation results per hour, including generation output.
    - `timeseries_red::Dict`: Reduced time series data for capacity factors by generation type and zone.
    - `factor::Vector{Float64}`: Vector of weighting factors for each hour.
    - `number_of_hours::Int`: Number of hours in the reduced time series.

    # Output
    - Returns `OFF_curt::Float64`: The overall offshore wind curtailment ratio (between 0 and 1).

    # Description
    - Iterates over all hours and all generators of type "Offshore Wind".
    - For each hour and generator, calculates uncurtailed energy as capacity factor x installed capacity x scaling x weight.
    - Computes curtailment as the relative difference:  
        `(uncurtailed_energy - energy_delivered) / uncurtailed_energy`
    - Returns the yearly curtailment ratio for offshore wind based on the reduced time horizon.
"""

function OFF_curtailment_red(nodal_input,nodal_result,timeseries_red,factor,number_of_hours)
    # Initialize accumulators for total uncurtailed and delivered energy
    uncurtailed_energy = 0
    energy_delivered = 0

    # Loop over all hours in the reduced time series
    for i in 1:number_of_hours
        # Loop over all Offshore Wind generators in the input data
        for (g,gen) in nodal_input["gen"]
            if nodal_input["gen"]["$g"]["type_tyndp"] == "Offshore Wind"
                if haskey(nodal_result["$i"]["solution"]["gen"], g)
                    # Retrieve capacity factor for offshore wind for the generator's zone and hour
                    CF = timeseries_red["wind_offshore"][nodal_input["gen"]["$g"]["zone"]][i]

                    # Accumulate uncurtailed energy: capacity factor * max capacity * 100 (scale factor) * hour weight
                    uncurtailed_energy += CF * nodal_input["gen"]["$g"]["pmax"] * 100 * factor[i] # in MWh

                    # Accumulate energy actually delivered from the simulation results
                    energy_delivered += nodal_result["$i"]["solution"]["gen"]["$g"]["pg"] * 100  * factor[i]# in MWh
                end
            end
        end
    end

    # Calculate overall curtailment ratio for offshore wind: fraction of energy curtailed
    OFF_curt = (uncurtailed_energy - energy_delivered)/uncurtailed_energy
    return OFF_curt
end

"""
    Congestion_index(result, number_of_hours)

Calculates the Congestion Index for a simulation period based on the dual variables. This metric gives an indication 
of congestion levels in the network, where higher values imply more uneven marginal prices (i.e., congestion).

    # Arguments
    - `result::Dict`: A dictionary containing optimization results for each hour, including dual variables at buses and DC buses.
    - `number_of_hours::Int`: The number of hours to compute the congestion index for (default is 15).

    # Output
    - `Congestion_index_values::Dict{Int, Float64}`: A dictionary where the keys are the hour indices, and the values 
    are the computed congestion index `i_c` for each hour.

    # Description
    - Calculates the **Congestion Index** as:
        
        i_c = sum(abs.(λ .- λ̄)) / (N * abs(λ̄))
        
    # Notes
    - Skips any hour where the optimization result is infeasible (`objective === nothing`).
"""
function Congestion_index(result,number_of_hours)
    Congestion_index_values=Dict()
    for i in 1:number_of_hours
        if result["$i"]["objective"] !== nothing
            lambda=[] # Array to collect Lagrange multipliers (λ) from all buses
            for bus in keys(result["$i"]["solution"]["bus"])
                push!(lambda,result["$i"]["solution"]["bus"]["$bus"]["lam_kcl_r"])
            end
            for dc_bus in keys(result["$i"]["solution"]["busdc"])
                push!(lambda,result["$i"]["solution"]["busdc"]["$dc_bus"]["lam_kcl_r"])
            end

            N = length(result["$i"]["solution"]["bus"])+length(result["$i"]["solution"]["busdc"]) # Total number of buses (AC + DC)
           
            # Compute the average Lagrange multiplier (nodal price)
            lambda_average = sum(lambda)/N
            
            # Compute the congestion index:
            i_c = sum(abs.(lambda.-lambda_average))/(N*abs(lambda_average))
            Congestion_index_values[i] = i_c
        end
    end
    return Congestion_index_values
end

"""
    overall_congestion_index(result,factor)

Computes the overall (annual) congestion index across the entire network by aggregating nodal prices over all simulation hours and nodes in a reduced timeseries horizon.

# Arguments
- `result::Dict`: Dictionary containing the simulation results for all hours.
- `factor::Vector{Float64}`: Weighting factor for each hour (e.g., from representative hours or scaling).

# Output
- `I_c`: A single scalar representing the network-wide congestion index over the entire period.

# Description
- The congestion index is computed as the normalized mean absolute deviation of nodal prices from the overall average:
  
      I_c = sum(abs.(λ - λ_avg)) / (N * abs(λ_avg))

"""

function overall_congestion_index(result,factor)
    lambda = []
     # Process all AC buses
    for bus in keys(result["1"]["solution"]["bus"])
        lambda_bus = 0.0
        # Accumulate the weighted nodal price over all hours
        for i in 1:length(result)
            lam = result["$i"]["solution"]["bus"]["$bus"]["lam_kcl_r"]
            lambda_bus += lam * factor[i] / 8760
        end
        push!(lambda, lambda_bus)  # Store annual average for this bus
    end

    # Process all DC buses
    for dc_bus in keys(result["1"]["solution"]["busdc"])
        lambda_dc_bus = 0.0
        for i in 1:length(result)
            lam = result["$i"]["solution"]["busdc"]["$dc_bus"]["lam_kcl_r"]
            lambda_dc_bus += lam * factor[i] / 8760
        end
        push!(lambda, lambda_dc_bus)  # Store annual average for this DC bus
    end

    # Total number of nodes (AC + DC)
    N = length(lambda)

    # Compute overall average nodal price
    lambda_average = sum(lambda) / N

    # Compute the normalized average absolute deviation from the mean
    I_c = sum(abs.(lambda .- lambda_average)) / (N * abs(lambda_average))

    return I_c
end

"""
    plot_Congestion_index(result, number_of_hours)

Plots the congestion index over a specified number of hours based on optimization results.

    # Arguments
    - `result::Dict`: Dictionary containing simulation results for each hour.
    - `number_of_hours::Int`: Total number of simulation hours to include in the congestion index plot.

    # Output
    - No return value. Adds the congestion index time series to a plot.

"""

function plot_Congestion_index(result, number_of_hours,plot_filename)
    Congestion_index_values = Congestion_index(result,number_of_hours)

    # Extract and sort the keys (time steps) to ensure the x-axis is ordered
    sorted_keys = sorted_keys = sort(collect(keys(Congestion_index_values)), by=x -> x)
    # Retrieve the congestion index values in the same sorted order
    sorted_values = [Congestion_index_values[k] for k in sorted_keys]

    P = Plots.plot()
    Plots.plot!(sorted_keys,sorted_values)

    Plots.xlims!(0.8, 15.2)
    Plots.xticks!(1:1:15)

    Plots.xlabel!("Hour")
    Plots.ylabel!("Congestion Index Value")

    Plots.savefig(P, plot_filename)

end

"""
    Saturation_index(result, input)

Computes the Saturation Index for each simulation hour, which indicates how fully the transmission lines are being utilized relative to their thermal limits.

    # Arguments
    - `result::Dict`: Dictionary containing simulation results per hour, including power flow through branches.
    - `input::Dict`: Network input data

    # Output
    - `Saturation_index_values::Dict`: A dictionary mapping each hour to its corresponding saturation index value.

    # Description
    - Computes the Saturation Index as:  
        
        Saturation Index = sum(|P_flow|)/sum(P_rated)

"""
function Saturation_index(result,input)
    Saturation_index_values = Dict()
    # Iterate over all time steps (hours) in the result dictionary
    for i in keys(result)
        if result["$i"]["objective"] !== nothing
            branch = collect(keys(result["$i"]["solution"]["branch"]))

            # Sum of absolute power flows (pt) across all branches in MW
            sum_power_flow = sum(abs(result["$i"]["solution"]["branch"]["$b"]["pt"]) for b in branch)*100 
            # Sum of rated capacities (rate_a) for the same branches in MVA
            sum_rated_power = sum(input["branch"]["$b"]["rate_a"] for b in branch)*100
            
            # Calculate the saturation index for this hour
            Saturation_index_values[i] = sum_power_flow/sum_rated_power
        end
    end
    return Saturation_index_values
end

"""
    plot_Saturation_index(result, input)

Generates a plot of the saturation index over time based on the simulation results and input data.

    # Arguments
    - `result::Dict`: Simulation results containing branch flow data.
    - `input::Dict`: Static input data including branch ratings.

    # Output
    - Produces a plot of the saturation index values sorted by time step, with the y-axis labeled "Saturation Index Value".
"""

function plot_Saturation_index(result,input,plot_filename)
    Saturation_index_values = Saturation_index(result,input)

    # Extract and sort the keys (time steps) to ensure the x-axis is ordered
    sorted_keys = sort(collect(keys(Saturation_index_values)), by=x -> parse(Int, x))
    # Retrieve the congestion index values in the same sorted order
    sorted_values = [Saturation_index_values[k] for k in sorted_keys]

    P = Plots.plot()
    Plots.plot!(sorted_keys,sorted_values,label="")

    Plots.xlims!(0.8, 15.2)
    Plots.xticks!(1:1:15)

    Plots.xlabel!("Hour")
    Plots.ylabel!("Saturation Index Value")

    Plots.savefig(P, plot_filename)
end
