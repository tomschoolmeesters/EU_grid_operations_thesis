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
import StatsPlots

######### DEFINE INPUT PARAMETERS
tyndp_version = "2020"
scenario = "DE"
Year = "2040"
climate_year = "1984"
load_data = true
use_case = "be_uk_de_nl_fr_dk_no"
hour_start = 1
hour_end = 8760
isolated_zones = ["NO1","NO2","NO3","NO4","NO5","BE","FR","UK","DE","NL","DK2","DK1"]#["BE","FR","UK","DE","NL","DK2","DK1","NO1","NO2","NO3","NO4","NO5"]
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
    zonal_result, zonal_input, scenario_data = _EUGO.load_results(tyndp_version, scenario, Year, climate_year,"zonal") # Import zonal results
    ntcs, zones, arcs, tyndp_capacity, tyndp_demand, gen_types, gen_costs, emission_factor, inertia_constants, start_up_cost, node_positions = _EUGO.get_grid_data(tyndp_version, scenario, Year, climate_year) # import zonal input (mainly used for cost data)
    pv, wind_onshore, wind_offshore = _EUGO.load_res_data()
end

print("ALL FILES LOADED", "\n")
print("----------------------","\n")
######

# map EU-Grid zones to TYNDP model zones
zone_mapping = _EUGO.map_zones()

# Scale generation capacity based on TYNDP data
scenario_id = "$scenario$Year"
_EUGO.scale_generation!(tyndp_capacity, EU_grid, scenario_id, climate_year, zone_mapping)

# Isolate zone: input is vector of strings, if you need to relax the fixing border flow assumptions use:
# _EUGO.isolate_zones(EU_grid, ["DE"]; border_slack = x), this will leas to (1-slack)*xb_flow_ref < xb_flow < (1+slack)*xb_flow_ref
zone_grid = _EUGO.isolate_zones(EU_grid, isolated_zones, border_slack = 0.01) #you allow a 1% slack compared to the power flows computed through the zonal model, which might leave a bit more freedom to the optimizer compared to a strict equality constraint on the flow

for (g_id,g) in zone_grid["gen"]
  if g["type"] != "XB_dummy"
   g["cost"][1] = gen_costs[g["type_tyndp"]]
   end
end
# create RES time series based on the TYNDP model for 
# (1) all zones, e.g.  create_res_time_series(wind_onshore, wind_offshore, pv, zone_mapping) 
# (2) a specified zone, e.g. create_res_time_series(wind_onshore, wind_offshore, pv, zone_mapping; zone = "DE")
timeseries_data = _EUGO.create_res_and_demand_time_series(wind_onshore, wind_offshore, pv, scenario_data, climate_year, zone_mapping; zones = isolated_zones)

push!(timeseries_data, "xb_flows" => _EUGO.get_xb_flows(zone_grid, zonal_result, zonal_input, zone_mapping)) 

# Start runnning hourly OPF calculations
hour_start_idx = 1 
hour_end_idx = 144

plot_filename = joinpath("results", join(["grid_input_",use_case,".pdf"]))
_EUGO.plot_grid(zone_grid, plot_filename)

s = Dict("output" => Dict("branch_flows" => true), "conv_losses_mp" => true, "fix_cross_border_flows" => true)
s_dual = Dict("output" => Dict("branch_flows" => true,"duals" => true), "conv_losses_mp" => true,"fix_cross_border_flows" => true)

# This function will  create a dictionary with all hours as result. For all 8760 hours, this might be memory intensive
#result = _EUGO.batch_opf(hour_start_idx, hour_end_idx, zone_grid, timeseries_data, gurobi, s_dual)

# An alternative is to run it in chuncks of "batch_size", which will store the results as json files, e.g. hour_1_to_batch_size, ....
batch_size = 24
_EUGO.batch_opf(hour_start_idx, hour_end_idx, zone_grid, timeseries_data, gurobi, s_dual, batch_size, output_file_name)

result_file_name = joinpath(_EUGO.BASE_DIR, "results", "TYNDP"*tyndp_version, join(["result_nodal_tyndp_", scenario*Year,"_", climate_year, ".json"]))
number_of_hours = hour_end_idx - hour_start_idx + 1
iterations = Int(number_of_hours/ batch_size)
input_files = []
for idx in 1 : iterations
    hs_idx = Int((hour_start_idx - 1) + (idx - 1) * batch_size + 1) 
    he_idx = Int((hour_start_idx - 1) + idx * batch_size)
    opf_file_name = join([output_file_name, "_opf_",hs_idx,"_to_",he_idx,".json"])
    push!(input_files,opf_file_name)
end

Total_result = concatenate_json_files(input_files,result_file_name)




## Write out JSON files
# Result file, with hourly results

json_string = JSON.json(Total_result)
result_file_name = joinpath(_EUGO.BASE_DIR, "results", "TYNDP"*tyndp_version, join(["result_nodal_tyndp_", scenario*Year,"_", climate_year, ".json"]))
open(result_file_name,"w") do f
  JSON.print(f, json_string)
end

# Input data dictionary as .json file
input_file_name = joinpath(_EUGO.BASE_DIR, "results", "TYNDP"*tyndp_version,  join(["input_nodal_tyndp_", scenario*Year,"_", climate_year, ".json"]))
json_string = JSON.json(zone_grid)
open(input_file_name,"w") do f
  JSON.print(f, json_string)
end

# scenario file (e.g. zonal time series and installed capacities) as .json file
scenario_file_name = joinpath(_EUGO.BASE_DIR, "results", "TYNDP"*tyndp_version, join(["scenario_nodal_tyndp_", scenario*Year,"_", climate_year, ".json"]))
json_string = JSON.json(timeseries_data)
open(scenario_file_name,"w") do f
  JSON.print(f, json_string)
end

#=
#Generate some Plots
number_of_hours = 168
gen = []
for i in 1:number_of_hours
    if !isnan(result["$i"]["objective"])
    push!(gen,result["$i"]["solution"]["gen"]["3038"]["pg"])
    end
end
gen_2 = []
for i in 1:number_of_hours
    if !isnan(result["$i"]["objective"])
    push!(gen_2,result["$i"]["solution"]["gen"]["5711"]["pg"])
    end
end

plot(gen)
plot!(gen_2)
=#

for (g,gen) in zone_grid["gen"]
	if gen["type_tyndp"] == "Offshore Wind"
		windfarms["$g"] = Dict()
		zone = gen["zone"]
		gen_bus = gen["gen_bus"]
		lat = zone_grid["bus"]["$gen_bus"]["lat"]
		lon = zone_grid["bus"]["$gen_bus"]["lon"]
		windfarms["$g"]["zone"] = zone
    windfarms["$g"]["gen_bus"] = gen_bus
		windfarms["$g"]["lat"] = lat
		windfarms["$g"]["lon"] = lon
    windfarms["$g"]["pmax"] = gen["pmax"]*100
	end
end
ids = collect(keys(windfarms))

# Functie om een waarde veilig op te halen
getval(d, key) = get(d, key, missing)

# DataFrame maken
df = DataFrame(
    id = ids,
    lat = [getval(windfarms[k], "lat") for k in ids],
    lon = [getval(windfarms[k], "lon") for k in ids],
    zone = [getval(windfarms[k], "zone") for k in ids],
    gen_bus = [getval(windfarms[k], "gen_bus") for k in ids],
    p_max = [getval(windfarms[k], "pmax") for k in ids]
)
