# Script to test the European grid
using PowerModels; const _PM = PowerModels
using Revise
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
using PlotlyJS

######### DEFINE INPUT PARAMETERS
tyndp_version = "2024"
scenario = "NT"
year = "2030"
climate_year = "2008"
load_data = true
use_case = "North_Sea_reloc"
hour_start = 1
hour_end = 8760
isolated_zones = ["BE","NL","DE","DK1","UK"]#,"DK2"]#,"UK","DE","NL"]#["BE","FR","UK","DE","NL","DK2","DK1","NO1","NO2","NO3","NO4","NO5"]
relocate_wind = true
update_conv = true
add_VOLL = true
add_offshore_hubs = false
detailed_WF = true

############ LOAD EU grid data ############
file = "./data_sources/European_grid_no_nseh.json"
output_file_name = joinpath("results", join([use_case,"_",scenario,"_", climate_year]))
gurobi = Gurobi.Optimizer
EU_grid = _PM.parse_file(file)
EU_grid["bus"]["6120"]["zone"] = "XB_node"
EU_grid["bus"]["6121"]["zone"] = "XB_node"
EU_grid["bus"]["6122"]["zone"] = "XB_node"
EU_grid["bus"]["6122"]["lat"] = 49
EU_grid["bus"]["6123"]["zone"] = "XB_node"
EU_grid["bus"]["6124"]["zone"] = "XB_node"
EU_grid["gen"]["0"] = deepcopy(EU_grid["gen"]["26"])
EU_grid["gen"]["0"]["type_tyndp"] = "Nuclear"
EU_grid["gen"]["0"]["gen_bus"] = 132
EU_grid["gen"]["0"]["source_id"][2] = 0
EU_grid["gen"]["0"]["index"] = 0
EU_grid["gen"]["0"]["type"] = "Nuclear"

if relocate_wind && detailed_WF
  for (g,gen) in EU_grid["gen"]
    if gen["type_tyndp"] == "Offshore Wind" 
      pop!(EU_grid["gen"], g)
    end
  end
  pop!(EU_grid["bus"],"467")
  pop!(EU_grid["busdc"],"10005")
  pop!(EU_grid["busdc"],"10007")
  pop!(EU_grid["convdc"],"6")
  pop!(EU_grid["convdc"],"7")
  pop!(EU_grid["branchdc"],"3")
  pop!(EU_grid["branchdc"],"4")
  pop!(EU_grid["branchdc"],"21")
  pop!(EU_grid["branchdc"],"22")
  pop!(EU_grid["busdc"],"10041")
  pop!(EU_grid["busdc"],"10043")
  pop!(EU_grid["convdc"],"24")
  pop!(EU_grid["convdc"],"25")
  pop!(EU_grid["bus"],"492")
  new_DC_buses, relocation_dict, new_branches = update_input_data_ext(EU_grid,parse(Int,year))
elseif relocate_wind && !detailed_WF
  new_DC_buses, relocation_dict, new_branches = update_input_data(EU_grid)
end

if add_offshore_hubs
  add_offshore_hub(EU_grid)
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

number_of_hours_z = 8760
hour_start_idx = 1
batch_size = 876 
iterations = Int(number_of_hours_z/ batch_size)
zonal_result = Dict{String,Any}()
file_name = joinpath("results", join([scenario,"_",year,"_",climate_year]))
@time for idx in 1 : iterations
  hs_idx = Int((hour_start_idx - 1) + (idx - 1) * batch_size + 1) 
  he_idx = Int((hour_start_idx - 1) + idx * batch_size)
  
  opf_file_name = join([file_name, "_zonal_opf_",hs_idx,"_to_",he_idx,".json"])
  data = JSON.parsefile(opf_file_name)
  
  @inbounds for i in 1:batch_size
    j = (hs_idx-1)+i
    zonal_result["$j"] = deepcopy(data["$j"]["solution"]["branch"])
  end
end

BASE_DIR = "C:\\Users\\tomsc\\.julia\\dev\\EU_grid_operations_thesis"
input_file_name =    joinpath(BASE_DIR, "results", "TYNDP2024", "input_zonal_tyndp_"*scenario*year*"_"*climate_year*".json")
scenario_file_name = joinpath(BASE_DIR, "results", "TYNDP2024", "scenario_zonal_tyndp_"*scenario*year*"_"*climate_year*".json")
    
   
zonal_input = Dict()
scenario_data = Dict()
d = JSON.parsefile(input_file_name)
zonal_input = JSON.parse(d)
d = JSON.parsefile(scenario_file_name)
scenario_data = JSON.parse(d)

if load_data == true
    #zonal_result, zonal_input, scenario_data = _EUGO.load_results(tyndp_version, scenario, year, climate_year,"zonal") # Import zonal results
    ntcs, zones, arcs, tyndp_capacity, tyndp_demand, gen_types, gen_costs, emission_factor, inertia_constants, start_up_cost, node_positions = _EUGO.get_grid_data(tyndp_version, scenario,year, climate_year,"nodal") # import zonal input (mainly used for cost data)
    pv, wind_onshore, wind_offshore = _EUGO.load_res_data()
end

print("ALL FILES LOADED", "\n")
print("----------------------","\n")
######

# map EU-Grid zones to TYNDP model zones
zone_mapping = _EUGO.map_zones()

# Scale generation capacity based on TYNDP data
scenario_id = "$scenario$year"
country_names =  Dict{String,Any}()
    for i_idx in 1:length(zones[:,1])
        i = zones[i_idx,1]
        country_names[i] = zones[i_idx,2]
    end
    country_names["DKE1"] = "Denmark"
    country_names["DKW1"] = "Denmark"
    country_names["DKKF"] = "Denmark"
    country_names["DEKF"] = "Denmark"
    country_names["DK00"] = "Denmark"
    country_names["UKNI"] = "United Kingdom"
    country_names["GR03"] = "Greece"
    country_names["FR15"] = "France"

for (z,zone) in EU_grid["zonal_generation_capacity"]
  zonal_generation_capacity = 0
  for (g,gen) in EU_grid["gen"]
    if gen["zone"] == zone["zone"] && gen["type_tyndp"] == "Offshore Wind" && gen["year"] == 2030
      #println(zone["zone"],g,gen["pmax"])
      zonal_generation_capacity += gen["pmax"]
    end
  end
  println("Zonal generation capacity for zone ", zone["zone"], " is ", zonal_generation_capacity)
  zone["Offshore Wind"] = zonal_generation_capacity
end
 EU_grid["zonal_generation_capacity"]["4"]["Nuclear"] = EU_grid["gen"]["0"]["pmax"]
      
@time scale_generation24!(tyndp_capacity, EU_grid, scenario_id, climate_year, zone_mapping)
  
# Isolate zone: input is vector of strings, if you need to relax the fixing border flow assumptions use:
# _EUGO.isolate_zones(EU_grid, ["DE"]; border_slack = x), this will leas to (1-slack)*xb_flow_ref < xb_flow < (1+slack)*xb_flow_ref
zone_grid = _EUGO.isolate_zones(EU_grid, isolated_zones, border_slack = 0.03) #you allow a 3% slack compared to the power flows computed through the zonal model, which might leave a bit more freedom to the optimizer compared to a strict equality constraint on the flow

plot_filename = joinpath("results", join(["grid_input_OPF_WF",use_case,".pdf"]))
plot_grid(zone_grid,plot_filename)


#for (l, load) in zone_grid["load"]
#  load["pred_rel_max"] = 0
#  load["cost_red"] = 10e5 * zone_grid["baseMVA"]
#  load["cost_curt"] = 10e5 * zone_grid["baseMVA"]
#  load["flex"] = 1
#end


gen_costs["Offshore Wind"] = 17
gen_costs["VOLL"] = 300

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

push!(timeseries_data, "xb_flows" => get_xb_flows_v2(zone_grid, zonal_result, zonal_input, zone_mapping)) 

################################
### Full timestep simulation ###
################################

# Start runnning hourly OPF calculations
hour_start_idx = 2000
hour_end_idx = 2072
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

################################
### Update DC branch ratings ###
################################

for (b,border) in zone_grid["borders"]
  if !isempty(border["xb_convs"])
    for (c,convdc) in border["xb_convs"]
      busdc = convdc["busdc_i"]
      for (b,branchdc) in zone_grid["branchdc"]
        if branchdc["fbusdc"] == busdc || branchdc["tbusdc"] == busdc
          branchdc["rateA"] = branchdc["rateA"] *5
          branchdc["rateB"] = branchdc["rateB"] *5
          branchdc["rateC"] = branchdc["rateC"] *5
        end
      end
    end
  end
end

for (b,border) in zone_grid["borders"]
  if !isempty(border["xb_lines"])
    for (l,line) in border["xb_lines"]
          zone_grid["branch"]["$l"]["rate_a"] = zone_grid["branch"]["$l"]["rate_a"] *10
          zone_grid["branch"]["$l"]["rate_b"] = zone_grid["branch"]["$l"]["rate_b"] *10
          zone_grid["branch"]["$l"]["rate_c"] = zone_grid["branch"]["$l"]["rate_c"] *10
          zone_grid["branch"]["$l"]["br_x"] = zone_grid["branch"]["$l"]["br_x"] /10
    end
  end
end

##########################################
### Representative timestep simulation ###
##########################################
# Create reduced timeseries_data
option = 3 # 1: all zones, 2: all zones without demand, 3: all zones without demand and offshore wind, 4: all zones without demand and offshore wind and onshore wind
timeseries_data_reduced, factor, extreme_indices = get_reduced_timeseries(timeseries_data,option)

# This function will create a dictionary with all hours as result but with representative timesteps
hour_start_idx = 1
hour_end_idx = 15

s_dual = Dict("output" => Dict("branch_flows" => true,"duals" => true), "conv_losses_mp" => true,"fix_cross_border_flows" => true)

for (l,load) in zone_grid["load"]
  load["cost_curt"] = 300
end

result = _EUGO.batch_opf_repr(hour_start_idx, hour_end_idx,zone_grid, timeseries_data_reduced, factor, gurobi, s_dual)
  
nodal_result = deepcopy(result)
nodal_input = deepcopy(zone_grid)

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


#############
### PLOTS ###
Plots.plot(timeseries_data_reduced["solar_pv"]["BE"], 
     label="Solar PV", 
      linewidth = 2,
     color=:darkgoldenrod1,
     size = (800,500))

Plots.plot!(timeseries_data_reduced["wind_offshore"]["BE"], 
      label="Wind Offshore", 
       linewidth = 2,
      color=:royalblue3)

Plots.plot!(timeseries_data_reduced["wind_onshore"]["BE"], 
      label="Wind Onshore", 
       linewidth = 2,
      color=:purple1,
      grid = false)

# Voeg titel, x-as label en legenda toe
#title!("RES timeseries (01/02/2030)")
xlabel!("Scenario")
xticks!(1:1:15)
ylabel!("Capacity Factor")
Plots.plot!(ylims=(0,1))
Plots.savefig("res_timeseries_reduced.png")
#legend(:topright)


Plots.plot(timeseries_data["demand"]["BE"][744:767], 
     label="01/02/2030", 
      linewidth = 2,
     color=:orangered3,
     size = (800,500))


Plots.plot!(timeseries_data["demand"]["BE"][5088:5111], 
     label="01/08/2030", 
      linewidth = 2,
     color=:chartreuse4,
     size = (800,500))

# Voeg titel, x-as label en legenda toe
title!("Demand timeseries")
xlabel!("Hour")
ylabel!("Load Factor")
Plots.plot!(ylims=(0,1))
Plots.savefig("dem_timeseries.png")




number_of_hours_z = 8760
hour_start_idx = 1
batch_size = 876 
iterations = Int(number_of_hours_z/ batch_size)
zonal_result = Dict{String,Any}()
file_name = joinpath("results", join([scenario,"_",year,"_",climate_year]))
RES = 0
Solar_z = 0
Onshore_z = 0
  Offshore = 0
  generation = 0
  gen_BE = 0
  gen_UK = 0
  gen_NL = 0
  gen_DE = 0
  gen_DK = 0
@time for idx in 1 : iterations
  hs_idx = Int((hour_start_idx - 1) + (idx - 1) * batch_size + 1) 
  he_idx = Int((hour_start_idx - 1) + idx * batch_size)
  
  opf_file_name = join([file_name, "_zonal_opf_",hs_idx,"_to_",he_idx,".json"])
  data = JSON.parsefile(opf_file_name)
  
  
  for (i,solution) in data
    for (g,gen) in solution["solution"]["gen"]
      if zonal_input["gen"]["$g"]["node"] in ["BE00","DE00","NL00","UK00","DKE1","DEKF"]
        if zonal_input["gen"]["$g"]["type"] in ["Offshore Wind","Solar PV","Onshore Wind"]
          RES += gen["pg"]
        end
        if zonal_input["gen"]["$g"]["type"] == "Offshore Wind"
          Offshore += gen["pg"]
        end
        if zonal_input["gen"]["$g"]["type"] == "Onshore Wind"
          Onshore_z += gen["pg"]
        end
        if zonal_input["gen"]["$g"]["type"] == "Solar PV"
          Solar_z += gen["pg"]
        end
      
      #=
      if zonal_input["gen"]["$g"]["node"] == "BE00"
        gen_BE += gen["pg"]
      end
      if zonal_input["gen"]["$g"]["node"] == "DE00"
        gen_DE += gen["pg"]
      end
      if zonal_input["gen"]["$g"]["node"] == "NL00"
        gen_NL += gen["pg"]
      end
      if zonal_input["gen"]["$g"]["node"] == "UK00"
        gen_UK += gen["pg"]
      end
      if zonal_input["gen"]["$g"]["node"] == "DKE1" || zonal_input["gen"]["$g"]["node"] == "DEKF" 
        gen_DK += gen["pg"]
      end=#
        generation += gen["pg"]
      end
    end
  end
end
