"""
Overview of functions in `Analyse_load.jl`:

1. Analyse_load(hour_range, nodal_input, nodal_result, timeseries_data)
    - Calculates the total electricity demand (in MWh) over a specified range of hours.
    - Iterates over all loads using their nominal capacity (pmax) and demand scaling factor (LF).
    - Skips hours where the optimization was infeasible.
    - Output: Prints total demand (MWh) for the given hour range.

2. load_shedding(hour_range, nodal_input, nodal_result)
    - Identifies events of load curtailment, reduction, and actual load shedding.
    - First checks load curtailment (pcurt) and demand reduction (pred).
    - Then checks for output from VOLL-type generators to infer load shedding.
    - Output: Prints all detected events with location and time.
"""

"""
    Analyse_load(hour_range,nodal_input,nodal_result,timeseries_data)

Calculates the total electricity demand (in MWh) over a given range of hours.

# Arguments
- `hour_range`: A range of hours (e.g. `1:8760`) to analyze demand for.
- `nodal_input`: Dictionary with static load properties (`pmax`, `zone`).
- `nodal_result`: Time-indexed dictionary with optimization results.
- `timeseries_data`: Contains `["demand"]` per zone.

# Behavior
- Iterates through all loads defined in the `nodal_input` dictionary.
- Uses time-varying demand scaling factors from `timeseries_data["demand"]` per zone.
- Scales by load nominal capacity (`pmax`) and demand factor, and converts to MWh.

# Output
- Prints the total load in the given time window (in MWh), rounded to 2 decimal places.
    
"""

function Analyse_load(hour_range,nodal_input,nodal_result,timeseries_data,factor)
    total_load = 0  # Initialize accumulator for total load in MWh

    # Iterate over all defined loads in the input data
    for (l_id, l) in nodal_input["load"]
        pmax = l["pmax"]  # Nominal load capacity [p.u.]
        zone = l["zone"]  # Load zone (used to access demand profiles)

        for h in hour_range
            LF = timeseries_data["demand"][zone][h]  # Load factor for the zone at hour h

            # Check if load solution exists for this hour (i.e., optimization was feasible)
            if haskey(nodal_result["$h"]["solution"]["load"], l_id)
                total_load += pmax * LF * 100 * factor[h]  # Convert to MWh and accumulate
            end
        end
    end

    # Format and print total load, rounded to 2 decimal places
    formatted_load = string(round(total_load; digits=2))
    println("Total load: $formatted_load MWh")
end

"""
    load_shedding(hour_range,nodal_input,nodal_result)

Identifies and reports instances of load shedding and demand-side flexibility (e.g. curtailment or reduction)
during a specified set of hours.

# Arguments
- `hour_range`: A range of hours to inspect (e.g. `200:300`).
- `nodal_input`: Dictionary containing input data for the nodal model.
- `nodal_result`: Dictionary containing simulation results for the nodal model.

# Behavior
- First loop: Iterates over `nodal_result` to detect:
    - Curtailment (`pcurt > 0`) per load → prints the load bus and hour.
    - Demand reduction (`pred > 0`) per load → prints the load bus and hour.
- Second loop: Checks all generators for type `"VOLL"` (Value of Lost Load), which are used to model load shedding:
    - If any `"VOLL"` generator has non-zero output, it is interpreted as a load shedding event and reported.

# Output
- Prints:
    - All instances of load curtailment (`pcurt`) and reduction (`pred`).
    - All load shedding events due to dispatch of `VOLL` generators (including power and location).

"""

function load_shedding(hour_range,nodal_input,nodal_result)
    
    # First loop: check each load for curtailed or reduced demand
    for i in hour_range
        for (l,load_info) in nodal_result["$i"]["solution"]["load"]
    
            # Check for curtailed load (pcurt > 0 means curtailment happened)
            if load_info["pcurt"]>0
                AC_bus = nodal_input["load"]["$l"]["load_bus"]
                println("Pcurt: bus $l at time $i")
            end
            # Check for demand reduction due to demand-side flexibility or DR (pred > 0)
            if load_info["pred"]>0
                AC_bus = nodal_input["load"]["$l"]["load_bus"]
                println("Pred: bus $AC_bus at time $i")
            end
        end
    end

    # Second loop: detect load shedding via use of VOLL (Value of Lost Load) generators
    for i in hour_range
        for (g,gen) in nodal_result["$i"]["solution"]["gen"]
            if nodal_input["gen"]["$g"]["type"] == "VOLL"
                # If VOLL generator is producing, that indicates load shedding occurred
                if gen["pg"] > 0
                    bus = nodal_input["gen"]["$g"]["gen_bus"]
                    println("Load shedding in scenario $i at bus $bus: $(gen["pg"]*100) MW")
                end
            end
        end         
    end
end