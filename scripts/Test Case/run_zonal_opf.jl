###############################################
# Authors: Hakan Ergun (24.03.2022), Tom Schoolmeesters (14.07.2025)
# Description: Solves hourly economic dispatch problem for the TYNDP 
# reference grid using NTC and provided generation capacities, 
# RES and demand time series.
###############################################

########## IMPORTANT ##########
# You must download the required FEATHER files and place them in the data_sources folder!
# See data_sources/download_links.txt for download links.
################################

# --- Package imports and aliases ---
import DataFrames; const _DF = DataFrames
import CSV
import JuMP
import Gurobi
import Feather
import PowerModels; const _PM = PowerModels
import JSON
using Plots
using EU_grid_operations; const _EUGO = EU_grid_operations

# --- Solver configuration ---
solver = JuMP.optimizer_with_attributes(Gurobi.Optimizer, "OutputFlag" => 0)

# --- Scenario configuration (example: TYNDP 2024, NT, 2030, 2008) ---
tyndp_version = "2024"
fetch_data     = true
number_of_hours = 8760
scenario       = "DE"
year           = "2040"
climate_year   = "2008"
start_hour     = 1

# --- Load grid and scenario data (once if fetch_data is true) ---
if fetch_data
    pv, wind_onshore, wind_offshore = _EUGO.load_res_data()
    ntcs, nodes, arcs, capacity, demand, gen_types, gen_costs, emission_factor, inertia_constants, node_positions =
        _EUGO.get_grid_data(tyndp_version, scenario, year, climate_year, "zonal")
end

# --- Adjust cost assumptions ---
gen_costs["Offshore Wind"] = 17
gen_costs["VOLL"] = 300  # Value of Lost Load

# --- Build PowerModels input dictionary ---
scenario_id = "$scenario$year"
input_data, nodal_data = _EUGO.construct_data_dictionary(
    tyndp_version, ntcs, arcs, capacity, nodes, demand,
    scenario_id, climate_year, gen_types,
    pv, wind_onshore, wind_offshore,
    gen_costs, emission_factor, inertia_constants, node_positions
)

# Keep a copy of original input data
input_data_raw = deepcopy(input_data)

println("######################################")
println("### STARTING HOURLY OPTIMISATION ####")
println("######################################")

# Create output directory if it doesn't exist
output_dir = joinpath(@__DIR__, "..", "Test Case", "Output", "$scenario"*"_"*"$year"*"_"*"$climate_year")

# --- Hourly OPF run ---
result = Dict{String, Any}("$hour" => nothing for hour in 1:number_of_hours)

for hour in start_hour:(start_hour + number_of_hours - 1)
    println("Hour $hour of $(start_hour + number_of_hours - 1)")
    _EUGO.prepare_hourly_data!(input_data, nodal_data, hour)
    result["$hour"] = _PM.solve_opf(input_data, PowerModels.NFAPowerModel, solver)
end

# --- Export results as JSON files ---
result_file = joinpath(output_dir, "result_zonal_opf.json")

# Save result dictionary
open(result_file, "w") do f
    JSON.print(f, JSON.json(result))
end

# --- Batch optimisation (for separate file export per batch) ---
println("#############################################")
println("### STARTING HOURLY BATCHED OPTIMISATION ####")
println("#############################################")

batch_size = 876
iterations = Int(number_of_hours / batch_size)

# Create output directory if it doesn't exist
output_dir = joinpath(@__DIR__, "..", "Test Case", "Output", "$scenario"*"_"*"$year"*"_"*"$climate_year")
mkpath(output_dir)

for i in 0:(iterations - 1)
    batch_start = i * batch_size + start_hour
    batch_end = min(batch_start + batch_size - 1, start_hour + number_of_hours - 1)

    println("Processing batch $i: Hours $batch_start to $batch_end")

    batch_result = Dict{String, Any}(string(hour) => nothing for hour in batch_start:batch_end)

    for hour in batch_start:batch_end
        println("  Hour $hour of $batch_end")
        _EUGO.prepare_hourly_data!(input_data, nodal_data, hour)
        batch_result[string(hour)] = _PM.solve_opf(input_data, PowerModels.NFAPowerModel, solver)
    end

    # Save batch results
    opf_file_name = joinpath(output_dir, "zonal_opf_$(batch_start)_to_$(batch_end).json")
    open(opf_file_name, "w") do f
        write(f, JSON.json(batch_result))
    end
end

# --- Export results as JSON files ---
input_file = joinpath(output_dir, "input_zonal_opf.json")

scenario_file = joinpath(output_dir, "scenario_zonal_opf.json")

# Save raw input data
open(input_file, "w") do f
    JSON.print(f, JSON.json(input_data_raw))
end

# Save nodal (scenario) data
open(scenario_file, "w") do f
    JSON.print(f, JSON.json(nodal_data))
end
