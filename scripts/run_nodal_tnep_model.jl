#####################################
#  main.jl
# Author: Hakan Ergun 24.03.2022
# Script to solve the hourly ecomic dispatch problem for the TYNDP 
# reference grid based on NTC and provided genreation capacities
# RES and demand time series
#######################################

# Import packages and create short names
import DataFrames; const _DF = DataFrames
import CSV
import JuMP
import Gurobi
import Feather
import PowerModels; const _PM = PowerModels
import PowerModelsACDC; const _PMACDC = PowerModelsACDC
import InfrastructureModels; const _IM = InfrastructureModels
import JSON
import CbaOPF
import Plots
using EU_grid_operations; const _EUGO = EU_grid_operations
gurobi = JuMP.optimizer_with_attributes(Gurobi.Optimizer)

# Select the TYNDP version to be used:
# - 2020
# - 2024

# Select input paramters for:
# # TYNDP 2020:
#  - Scenario selection: Distributed Energy (DE), National Trends (NT), Global Ambition (GA)
#  - Planning years: 2025 (NT only), 2030, 2040
#  - Climate year: 1982, 1984, 2007
#  - Number of hours: 1 - 8760
# TYNDP 2024:
#  - Scenario selection: Distributed Energy (DE), National Trends (NT), Global Ambition (GA)
#  -  Planning years: 2030, 2040, 2050
#  -  Climate year: 1995, 2008, 2009
#  -  Number of hours: 1 - 8760
# Fetch data: true/false, to parse input data (takes ~ 1 min.)

# A sample set for TYNDP 2024
#tyndp_version = "2020"
#fetch_data = true
#number_of_hours = 8760
#scenario = "DE"
#Year = "2040"
#climate_year = "2007"
#hours = 1:2

# A sample set for TYNDP 2020
# tyndp_version = "2020"
# fetch_data = true
# number_of_hours = 8760
# scenario = "DE"
# year = "2040"
# climate_year = "2007"


# Load grid and scenario data
if fetch_data == true
    pv, wind_onshore, wind_offshore = _EUGO.load_res_data()
    ntcs, nodes, arcs, capacity, demand, gen_types, gen_costs, emission_factor, inertia_constants, node_positions = _EUGO.get_grid_data(tyndp_version, scenario, Year, climate_year)
end


nodal_input["ne_branch"] = branches

for (b, branch) in nodal_input["ne_branch"]
    branch["delta_cap_max"] = branch["rate_a"] * 2 # for testing.....
    #distance = _EUGO.latlon2distance(nodal_input, branch)
    branch["capacity_cost"] = 300e5 * nodal_input["baseMVA"] / (25 * 8760) # for testing, update with more realistic numbers.....
    branch["construction_cost"] = 5;
end

for (l, load) in nodal_input["load"]
    load["pred_rel_max"] = 0
    load["cost_red"] = 10e5 * nodal_input["baseMVA"]
    load["cost_curt"] = 10e5 * nodal_input["baseMVA"]
    load["flex"] = 1
end

# Create dictionary for writing out results
#print("######################################", "\n")
#print("####### PREPARING DATA      ##########", "\n")
#@time mn_input_data = _EUGO.prepare_mn_data(nodal_input, nodal_data, hours)

print("######################################", "\n")
print("####### STARTING OPTIMISATION#### ####", "\n")
#@time result = CbaOPF.solve_nodal_tnep(mn_data, _PM.NFAPowerModel, gurobi; multinetwork = true) 

_PMACDC.run_mp_tnepopf(nodal_input,_PM.NFAPowerModel,gurobi)

cap  = zeros(1, maximum(parse.(Int, collect(keys(input_data["branch"])))))
for (n, network) in result["solution"]["nw"]
    for idx in sort(parse.(Int, collect(keys(network["branch"]))))
        branch = network["branch"]["$idx"]
        cap[1, idx] = max(cap[idx], branch["delta_cap"])
    end
end
Plots.plot(cap')


for (b, branch) in input_data["branch"]
     print(b, " ", abs(result["solution"]["nw"]["1"]["branch"][b]["pf"]) / branch["rate_a"], "\n")
end

# ## Write out JSON files
# # Result file, with hourly results
# json_string = JSON.json(result)
# result_file_name = join(["./results/result_zonal_tyndp_", scenario,"_", climate_year, ".json"])
# open(result_file_name,"w") do f
#   JSON.print(f, json_string)
# end

# # Input data dictionary as .json file
# input_file_name = join(["./results/input_zonal_tyndp_", scenario,"_", climate_year, ".json"])
# json_string = JSON.json(input_data_raw)
# open(input_file_name,"w") do f
#   JSON.print(f, json_string)
# end

# # scenario file (e.g. zonal time series and installed capacities) as .json file
# scenario_file_name = join(["./results/scenario_zonal_tyndp_", scenario,"_", climate_year, ".json"])
# json_string = JSON.json(nodal_data)
# open(scenario_file_name,"w") do f
#   JSON.print(f, json_string)
# end