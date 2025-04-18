# Script to test the European grid
using PowerModels; const _PM = PowerModels
using PowerModelsACDC; const _PMACDC = PowerModelsACDC
using EU_grid_operations; const _EUGO = EU_grid_operations
using Gurobi
using JSON


## Import required functions - Some of them in later stages.....
import Ipopt
using Plots
import Memento
import JuMP
import Gurobi  # needs startvalues for all variables!
import JSON
import CbaOPF
import DataFrames; const _DF = DataFrames
import CSV
import Feather
using XLSX
using Statistics
using Clustering
using StatsBase
using SparseArrays
import StatsPlots

######### DEFINE INPUT PARAMETERS
tyndp_version = "2020"
scenario = "DE"
year = "2040"
climate_year = "1984"
load_data = true
use_case = "North_Sea_reloc"
hour_start = 1
hour_end = 200
isolated_zones = ["BE","NL","UK","DE","DK1","DK2"]#,"UK","DE","NL"]#["BE","FR","UK","DE","NL","DK2","DK1","NO1","NO2","NO3","NO4","NO5"]
relocate_wind = true
update_conv = true
add_VOLL = true

############ LOAD EU grid data ############
file = "./data_sources/European_grid_no_nseh.json"
output_file_name = joinpath("results", join([use_case,"_",scenario,"_", climate_year]))
gurobi = Gurobi.Optimizer
EU_grid = _PM.parse_file(file)
EU_grid["bus"]["6120"]["zone"] = "XB_node"
EU_grid["bus"]["6121"]["zone"] = "XB_node"
EU_grid["bus"]["6122"]["zone"] = "XB_node"
EU_grid["bus"]["6123"]["zone"] = "XB_node"
EU_grid["bus"]["6124"]["zone"] = "XB_node"
if relocate_wind
  new_DC_buses, relocation_dict, new_branches = update_input_data(EU_grid)
end
if add_VOLL
  EU_grid = add_VOLL_generation(EU_grid)
end

_PMACDC.process_additional_data!(EU_grid)
_EUGO.add_load_and_pst_properties!(EU_grid)

if update_conv
  EU_grid = update_conv_input(EU_grid)
end


#### LOAD TYNDP SCENARIO DATA ##########
if load_data == true
    zonal_result, zonal_input, scenario_data = _EUGO.load_results(tyndp_version, scenario, year, climate_year,"zonal") # Import zonal results
    ntcs, zones, arcs, tyndp_capacity, tyndp_demand, gen_types, gen_costs, emission_factor, inertia_constants, start_up_cost, node_positions = _EUGO.get_grid_data(tyndp_version, scenario,year, climate_year) # import zonal input (mainly used for cost data)
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
zone_grid = _EUGO.isolate_zones(EU_grid, isolated_zones, border_slack = 0.03) #you allow a 1% slack compared to the power flows computed through the zonal model, which might leave a bit more freedom to the optimizer compared to a strict equality constraint on the flow


#for (l, load) in zone_grid["load"]
#  load["pred_rel_max"] = 0
#  load["cost_red"] = 10e5 * zone_grid["baseMVA"]
#  load["cost_curt"] = 10e5 * zone_grid["baseMVA"]
#  load["flex"] = 1
#end

gen_costs["Offshore Wind"] = 17

for (g_id,g) in zone_grid["gen"]
  
  if g["type"] != "XB_dummy"
      g["cost"][1] = gen_costs[g["type_tyndp"]]
  else
    g["cost"][1] = 0
  end   
end

# create RES time series based on the TYNDP model for 
# (1) all zones, e.g.  create_res_time_series(wind_onshore, wind_offshore, pv, zone_mapping) 
# (2) a specified zone, e.g. create_res_time_series(wind_onshore, wind_offshore, pv, zone_mapping; zone = "DE")
timeseries_data = _EUGO.create_res_and_demand_time_series(wind_onshore, wind_offshore, pv, scenario_data, climate_year, zone_mapping; zones = isolated_zones)

push!(timeseries_data, "xb_flows" => _EUGO.get_xb_flows(zone_grid, zonal_result, zonal_input, zone_mapping)) 

################################
### Full timestep simulation ###
################################

# Start runnning hourly OPF calculations
hour_start_idx = 2000
hour_end_idx = 2072

plot_filename = joinpath("results", join(["grid_input_",use_case,".pdf"]))
_EUGO.plot_grid(zone_grid, plot_filename)

s = Dict("output" => Dict("branch_flows" => true), "conv_losses_mp" => true, "fix_cross_border_flows" => true)
s_dual = Dict("output" => Dict("branch_flows" => true,"duals" => true), "conv_losses_mp" => true,"fix_cross_border_flows" => true)

# This function will  create a dictionary with all hours as result. For all 8760 hours, this might be memory intensive
result = _EUGO.batch_opf(hour_start_idx, hour_end_idx, zone_grid, timeseries_data, gurobi, s_dual)

# An alternative is to run it in chuncks of "batch_size", which will store the results as json files, e.g. hour_1_to_batch_size, ....
batch_size = 24
_EUGO.batch_opf(hour_start_idx, hour_end_idx, zone_grid, timeseries_data, gurobi, s_dual, batch_size, output_file_name)


##########################################
### Representative timestep simulation ###
##########################################
# Create reduced timeseries_data



# This function will create a dictionary with all hours as result but with representative timesteps
hour_start_idx = 1
hour_end_idx = 24

result = _EUGO.batch_opf_repr(hour_start_idx, hour_end_idx,zone_grid, timeseries_data_reduced, factor, gurobi, s_dual)
  



##############################
### Saving results as json ###
##############################

result_file_name = joinpath(_EUGO.BASE_DIR, "results","OPF_NorthSEA", "TYNDP"*tyndp_version, join(["result_nodal_tyndp_", scenario*year,"_", climate_year, ".json"]))
number_of_hours = hour_end_idx - hour_start_idx + 1
iterations = Int(number_of_hours/ batch_size)
total_result = Dict{String,Any}()
for idx in 1 : iterations
  hs_idx = Int((hour_start_idx - 1) + (idx - 1) * batch_size + 1) 
  he_idx = Int((hour_start_idx - 1) + idx * batch_size)
  opf_file_name = join([output_file_name, "_opf_",hs_idx,"_to_",he_idx,".json"])
  data = JSON.parsefile(opf_file_name)
  for i in 1:batch_size
    j = (hs_idx-1)+i
    total_result["$j"] = deepcopy(data["$j"])
  end
end

d = JSON.parsefile(result_file_name)
result = JSON.parse(d)


## Write out JSON files
# Result file, with hourly results

json_string = JSON.json(result)
result_file_name = joinpath(_EUGO.BASE_DIR, "results", "TYNDP"*tyndp_version, join(["result_nodal_tyndp_", scenario*year,"_", climate_year, ".json"]))
open(result_file_name,"w") do f
  JSON.print(f, json_string)
end

# Input data dictionary as .json file
input_file_name = joinpath(_EUGO.BASE_DIR, "results", "TYNDP"*tyndp_version,  join(["input_nodal_tyndp_", scenario*year,"_", climate_year, ".json"]))
json_string = JSON.json(zone_grid)
open(input_file_name,"w") do f
  JSON.print(f, json_string)
end

# scenario file (e.g. zonal time series and installed capacities) as .json file
scenario_file_name = joinpath(_EUGO.BASE_DIR, "results", "TYNDP"*tyndp_version, join(["scenario_nodal_tyndp_", scenario*year,"_", climate_year, ".json"]))
json_string = JSON.json(timeseries_data)
open(scenario_file_name,"w") do f
  JSON.print(f, json_string)
end

