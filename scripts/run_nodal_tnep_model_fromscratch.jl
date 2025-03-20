
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
import XLSX
include("Pre-Processor/Pre-Processor_Cable pool.jl")



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
 tyndp_version = "2020"
 fetch_data = true
 number_of_hours = 144
 scenario = "DE"
 year = "2040"
 climate_year = "1984"
 hours = 1:1
 load_data = true
 use_case = "North_Sea_reloc"
 hour_start = 1
 hour_end = 1
 isolated_zones = ["DE"]#,"FR","UK","DE","NL","DK2","DK1"]#["BE","FR","UK","DE","NL","DK2","DK1","NO1","NO2","NO3","NO4","NO5"]
relocate_wind = true

############ LOAD EU grid data ############
file = "./data_sources/European_grid_no_nseh.json"
output_file_name = joinpath("results", join([use_case,"_",scenario,"_", climate_year]))
gurobi = Gurobi.Optimizer
EU_grid = _PM.parse_file(file)
if relocate_wind
    update_input_data(EU_grid)
end
_PMACDC.process_additional_data!(EU_grid)
_EUGO.add_load_and_pst_properties!(EU_grid)

#### LOAD TYNDP SCENARIO DATA ##########
if load_data == true
    zonal_result, zonal_input, scenario_data = _EUGO.load_results(tyndp_version, scenario, year, climate_year,"zonal") # Import zonal results
    ntcs, zones, arcs, tyndp_capacity, tyndp_demand, gen_types, gen_costs, emission_factor, inertia_constants, start_up_cost, node_positions = _EUGO.get_grid_data(tyndp_version, scenario, year, climate_year) # import zonal input (mainly used for cost data)
    pv, wind_onshore, wind_offshore = _EUGO.load_res_data()
end

print("ALL FILES LOADED", "\n")
print("----------------------","\n")
######

# map EU-Grid zones to TYNDP model zones
zone_mapping = _EUGO.map_zones()

# Scale generation capacity based on TYNDP data
scenario_id = "$scenario$year"
_EUGO.scale_generation!(tyndp_capacity, EU_grid, scenario_id, climate_year, zone_mapping)

# Isolate zone: input is vector of strings, if you need to relax the fixing border flow assumptions use:
# _EUGO.isolate_zones(EU_grid, ["DE"]; border_slack = x), this will leas to (1-slack)*xb_flow_ref < xb_flow < (1+slack)*xb_flow_ref
zone_grid = _EUGO.isolate_zones(EU_grid, isolated_zones, border_slack = 0.01) #you allow a 1% slack compared to the power flows computed through the zonal model, which might leave a bit more freedom to the optimizer compared to a strict equality constraint on the flow

##############################################
#### LOAD NODAL TYNDP SCENARIO DATA ##########
##############################################
#Run this to load the right simulation scenario
    
nodal_result, nodal_input, timeseries_data = _EUGO.load_results(tyndp_version, scenario, year, climate_year, "nodal") # Import nodal results

print("ALL NODAL FILES LOADED", "\n")
print("----------------------","\n")
zone_grid = deepcopy(nodal_input)
# Generate (new)corridors and add to zone_grid
@time zone_grid = candidate_lines(nodal_input,nodal_result,new_DC_buses,number_of_hours)

    
plot_filename = joinpath("results", join(["grid_input_candidates_tnep",use_case,".pdf"]))
plot_grid_candidates(zone_grid,plot_filename)


for (g_id,g) in zone_grid["gen"]
    if g["type"] != "XB_dummy"
        g["cost"][1] = gen_costs[g["type_tyndp"]]
    end
    if g["type"] == "XB_dummy"
        g["cost"][1] = 0
    end
end

for (b, branch) in zone_grid["branch"]
    branch["delta_cap_max"] = branch["rate_a"] * 1 # for testing.....
    branch["capacity_cost"] = 300e5 * zone_grid["baseMVA"] / (25 * 8760) # for testing, update with more realistic numbers.....
end

for (l, load) in zone_grid["load"]
    load["pred_rel_max"] = 0
    load["cost_red"] = 10e5 * zone_grid["baseMVA"]
    load["cost_curt"] = 10e5 * zone_grid["baseMVA"]
    load["flex"] = 1
end


for (b,branch) in zone_grid["ne_branch"]
    branch["construction_cost"] = 1
end

for (b,branch) in zone_grid["branchdc_ne"]
    branch["cost"] = 15
end

# create RES time series based on the TYNDP model for 
# (1) all zones, e.g.  create_res_time_series(wind_onshore, wind_offshore, pv, zone_mapping) 
# (2) a specified zone, e.g. create_res_time_series(wind_onshore, wind_offshore, pv, zone_mapping; zone = "DE")
timeseries_data = _EUGO.create_res_and_demand_time_series(wind_onshore, wind_offshore, pv, scenario_data, climate_year, zone_mapping; zones = isolated_zones)

#for (br_id,br) in zonal_result["1"]["solution"]["branch"]
#    br["pf"] = 0
#    br["pt"] = 0
#end

push!(timeseries_data, "xb_flows" => _EUGO.get_xb_flows(zone_grid, zonal_result, zonal_input, zone_mapping)) 


# Create dictionary for writing out results
print("######################################", "\n")
print("####### PREPARING DATA      ##########", "\n")
@time mn_input_data = _EUGO.prepare_mn_data_nodal(zone_grid, timeseries_data, hours)


print("######################################", "\n")
print("####### STARTING OPTIMISATION ########", "\n")
#s = Dict("output" => Dict("branch_flows" => true), "conv_losses_mp" => true, "fix_cross_border_flows" => true)
#@time result = CbaOPF.solve_nodal_tnep(mn_input_data, _PM.DCPPowerModel, gurobi; multinetwork = true, setting = s) 

gurobi = JuMP.optimizer_with_attributes(
    Gurobi.Optimizer,
    "TimeLimit" => 240,        # Maximaal 300 seconden 8 hours
    "MIPGap" => 0.01)         # Stop als de gap kleiner is dan 12% 0.01


s = Dict("output" => Dict("branch_flows" => true), "conv_losses_mp" => true, "fix_cross_border_flows" => true, "process_data_internally" => false)#, "borders"=>[1,2,3,4,5,6,7,8,9,10,11,12])
@time result = _PMACDC.run_mp_tnepopf(mn_input_data,_PM.DCPPowerModel, gurobi, multinetwork = true; setting = s)

plot_filename = joinpath("results", join(["grid_input_tnep",use_case,".pdf"]))
plot_grid_tnep(zone_grid,plot_filename)

cap  = zeros(1, maximum(parse.(Int, collect(keys(zone_grid["branch"])))))
for (n, network) in result["solution"]["nw"]
    for idx in sort(parse.(Int, collect(keys(network["branch"]))))
        branch = network["branch"]["$idx"]
        cap[1, idx] = max(cap[idx], branch["delta_cap"])
    end
end
Plots.plot(cap')


for (b, branch) in result["solution"]["nw"]["1"]["branch"]#zone_grid["branch"]
     print(b, " ", abs(result["solution"]["nw"]["1"]["branch"][b]["pf"]) / zone_grid["branch"]["$b"]["rate_a"], "\n")
end


for (g, gen) in zone_grid["gen"]
    println(gen["type"], " ", gen["type_tyndp"])
end