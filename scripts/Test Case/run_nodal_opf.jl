############### EU GRID TEST SCRIPT ###############

# Required packages
using PowerModels; const _PM = PowerModels
using PowerModelsACDC; const _PMACDC = PowerModelsACDC
using EU_grid_operations; const _EUGO = EU_grid_operations
using Revise
using Gurobi
using JSON
using Plots
import Ipopt
import Memento
import JuMP
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

####################################################

############# DEFINE INPUT PARAMETERS ##############
tyndp_version = "2024"
scenario = "DE"
year = "2040"
climate_year = "2008"
load_data = true
use_case = "Test_case_nodalOPF"  # Name of the test case: relocation of the wind farms
hour_start = 1
hour_end = 8760
isolated_zones = ["BE", "NL", "DE", "DK1", "UK"]

# Test case options
relocate_wind = true         # Relocate offshore wind farms to North Sea hubs
update_conv = true           # Update converter data (capacity increase to avoid bottlenecks)
add_VOLL = true              # Add VOLL generation to simulate load shedding
add_offshore_hubs = false    # Add extra offshore hubs as connection points/islands
detailed_WF = true           # Use detailed wind farm data (true) or only current locations (false)

####################################################

############# LOAD EU GRID DATA ####################
file = joinpath(@__DIR__, "..", "..", "data_sources", "European_grid_no_nseh.json")
output_file_name = joinpath("Test Case","Output", join([use_case, "_", scenario, "_", climate_year]))
gurobi = Gurobi.Optimizer
EU_grid = _PM.parse_file(file)

####################################################

########### MODIFY EU GRID STRUCTURE ###############

# Update zones and coordinates for certain buses
EU_grid["bus"]["6120"]["zone"] = "XB_node"
EU_grid["bus"]["6121"]["zone"] = "XB_node"
EU_grid["bus"]["6122"]["zone"] = "XB_node"
EU_grid["bus"]["6122"]["lat"] = 49
EU_grid["bus"]["6123"]["zone"] = "XB_node"
EU_grid["bus"]["6124"]["zone"] = "XB_node"

# Add a new nuclear generator based on an existing one
EU_grid["gen"]["0"] = deepcopy(EU_grid["gen"]["26"])
EU_grid["gen"]["0"]["type_tyndp"] = "Nuclear"
EU_grid["gen"]["0"]["gen_bus"] = 132
EU_grid["gen"]["0"]["source_id"][2] = 0
EU_grid["gen"]["0"]["index"] = 0
EU_grid["gen"]["0"]["type"] = "Nuclear"


####################################################

########### MODIFY GENERATORS & BUSES ##############

if relocate_wind && detailed_WF
    # Remove offshore wind generators
    for (g, gen) in EU_grid["gen"]
        if gen["type_tyndp"] == "Offshore Wind"
            pop!(EU_grid["gen"], g)
        end
    end

    # Remove obsolete buses, converters and DC branches after wind relocation
    for id in ["467", "492"]
        pop!(EU_grid["bus"], id)
    end
    for id in ["10005", "10007", "10041", "10043"]
        pop!(EU_grid["busdc"], id)
    end
    for id in ["6", "7", "24", "25"]
        pop!(EU_grid["convdc"], id)
    end
    for id in ["3", "4", "21", "22"]
        pop!(EU_grid["branchdc"], id)
    end

    # Add new offshore connections and return updates
    new_DC_buses, relocation_dict, new_branches = _EUGO.update_input_data_ext(EU_grid, parse(Int, year))

elseif relocate_wind && !detailed_WF
    new_DC_buses, relocation_dict, new_branches = _EUGO.update_input_data(EU_grid)
end

if add_offshore_hubs
    _EUGO.add_offshore_hub(EU_grid)
end

if add_VOLL
    EU_grid = _EUGO.add_VOLL_generation(EU_grid)
end

####################################################

########### FINALIZE GRID STRUCTURE ################

# Add extra data required for processing and OPF
_PMACDC.process_additional_data!(EU_grid)
_EUGO.add_load_and_pst_properties!(EU_grid)

if update_conv
    EU_grid = _EUGO.update_conv_input(EU_grid)
end

####################################################

############ LOAD TYNDP SCENARIO DATA #############

number_of_hours_z = 8760
hour_start_idx = 1
batch_size = 876
iterations = Int(number_of_hours_z / batch_size)
zonal_result = Dict{String, Any}()

# Construct base filename for OPF results
output_dir = joinpath(@__DIR__, "..", "Test Case", "Output", "$scenario"*"_"*"$year"*"_"*"$climate_year")
mkpath(output_dir)

# Load zonal OPF results in batches
@time for idx in 1:iterations
    hs_idx = Int((hour_start_idx - 1) + (idx - 1) * batch_size + 1)
    he_idx = Int((hour_start_idx - 1) + idx * batch_size)

    opf_file_name = joinpath(output_dir, "zonal_opf_$(hs_idx)_to_$(he_idx).json")
    data = JSON.parsefile(opf_file_name)

    @inbounds for i in 1:batch_size
        j = (hs_idx - 1) + i
        zonal_result["$j"] = deepcopy(data["$j"]["solution"]["branch"])
    end
end

###################################################

############ LOAD SCENARIO AND INPUT DATA #########

input_file_name = joinpath(@__DIR__,  "..","..", "Test Case", "Output", "$scenario"*"_"*"$year"*"_"*"$climate_year", "input_zonal_opf.json")
scenario_file_name = joinpath(@__DIR__,  "..","..", "Test Case", "Output", "$scenario"*"_"*"$year"*"_"*"$climate_year", "scenario_zonal_opf.json")

zonal_input = JSON.parse(JSON.parsefile(input_file_name))
scenario_data = JSON.parse(JSON.parsefile(scenario_file_name))

if load_data == true
    # Load nodal grid parameters from TYNDP scenario
    ntcs, zones, arcs, tyndp_capacity, tyndp_demand, gen_types, gen_costs,
    emission_factor, inertia_constants, start_up_cost, node_positions = 
        _EUGO.get_grid_data(tyndp_version, scenario, year, climate_year, "nodal")

    # Load RES generation profiles (PV, wind onshore & offshore)
    pv, wind_onshore, wind_offshore = _EUGO.load_res_data()
end

println("ALL FILES LOADED")
println("----------------------")

###################################################

############ PROCESS TYNDP INPUT DATA #############

# Map EU-Grid zones to TYNDP model zones
zone_mapping = _EUGO.map_zones()

# Prepare dictionary mapping for readable country names
scenario_id = "$scenario$year"
country_names = Dict{String, Any}()
for i_idx in 1:length(zones[:, 1])
    i = zones[i_idx, 1]
    country_names[i] = zones[i_idx, 2]
end

# Add manual mappings for zone codes
country_names["DKE1"] = "Denmark"
country_names["DKW1"] = "Denmark"
country_names["DKKF"] = "Denmark"
country_names["DEKF"] = "Denmark"
country_names["DK00"] = "Denmark"
country_names["UKNI"] = "United Kingdom"
country_names["GR03"] = "Greece"
country_names["FR15"] = "France"

# Calculate and assign Offshore Wind capacities to each zone
for (z, zone) in EU_grid["zonal_generation_capacity"]
    zonal_generation_capacity = 0
    for (g, gen) in EU_grid["gen"]
        if gen["zone"] == zone["zone"] &&
           gen["type_tyndp"] == "Offshore Wind" &&
           gen["year"] == 2030
            zonal_generation_capacity += gen["pmax"]
        end
    end
    println("Zonal generation capacity for zone ", zone["zone"], " is ", zonal_generation_capacity)
    zone["Offshore Wind"] = zonal_generation_capacity
end

# Add nuclear capacity manually
EU_grid["zonal_generation_capacity"]["4"]["Nuclear"] = EU_grid["gen"]["0"]["pmax"]

# Scale generation based on TYNDP data
@time _EUGO.scale_generation24!(tyndp_capacity, EU_grid, scenario_id, climate_year, zone_mapping,country_names)

###################################################

############### ZONE ISOLATION & COSTS ############

# Isolate selected zones with flow relaxation (3% slack allowed)
zone_grid = _EUGO.isolate_zones(EU_grid, isolated_zones, border_slack = 0.03)

# Plot the resulting input grid
output_dir_fig = joinpath(@__DIR__, "..", "Test Case", "Figures", "$scenario"*"_"*"$year"*"_"*"$climate_year")
plot_filename = joinpath(output_dir_fig, join(["plot_grid_", use_case,".svg"]))
_EUGO.plot_grid(zone_grid, plot_filename)

# Update generation costs
gen_costs["Offshore Wind"] = 17
gen_costs["VOLL"] = 300

# Assign generation costs to generators
for (g_id, g) in zone_grid["gen"]
    if g["type"] != "XB_dummy"
        g["cost"][1] = gen_costs[g["type_tyndp"]]
    else
        g["cost"][1] = 0
    end
end

###################################################

####### GENERATE RES & DEMAND TIME SERIES #########

# Create renewable generation and demand profiles per zone
timeseries_data = _EUGO.create_res_and_demand_time_series(
    wind_onshore,
    wind_offshore,
    pv,
    scenario_data,
    climate_year,
    zone_mapping;
    zones = isolated_zones
)

# Add cross-border flow time series to results
push!(timeseries_data, "xb_flows" => _EUGO.get_xb_flows_v2(zone_grid, zonal_result, zonal_input, zone_mapping))

###################################################

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
timeseries_data_reduced, factor, extreme_indices = _EUGO.get_reduced_timeseries(timeseries_data,option)

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
#=  ONLY IF DONE FULL HOUR ANALYSIS

result_file_name = joinpath(output_dir, "result_nodal_opf.json")
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
=#

## Write out JSON files
# Result file, with hourly results

json_string = JSON.json(result)
result_file_name = joinpath(output_dir, "result_nodal_opf.json")
open(result_file_name,"w") do f
  JSON.print(f, json_string)
end

# Input data dictionary as .json file
input_file_name = joinpath(output_dir, "input_nodal_opf.json")
json_string = JSON.json(zone_grid)
open(input_file_name,"w") do f
  JSON.print(f, json_string)
end

# scenario file (e.g. zonal time series and installed capacities) as .json file
scenario_file_name = joinpath(output_dir, "scenario_nodal_opf.json")
json_string = JSON.json(timeseries_data)
open(scenario_file_name,"w") do f
  JSON.print(f, json_string)
end


#############
### PLOTS ###
#############

# --- Plot 1: RES timeseries (reduced) voor België ---
Plots.plot(timeseries_data_reduced["solar_pv"]["BE"], 
           label="Solar PV", 
           linewidth=2,
           color=:darkgoldenrod1,
           size=(800, 500))

Plots.plot!(timeseries_data_reduced["wind_offshore"]["BE"], 
            label="Wind Offshore", 
            linewidth=2,
            color=:royalblue3)

Plots.plot!(timeseries_data_reduced["wind_onshore"]["BE"], 
            label="Wind Onshore", 
            linewidth=2,
            color=:purple1,
            grid=false)

xlabel!("Scenario")
xticks!(1:1:15)
ylabel!("Capacity Factor")
Plots.ylims!(0, 1)
#legend(:topright)
Plots.savefig(joinpath(output_dir_fig, "res_timeseries_reduced.svg"))


# --- Plot 2: Demand timeseries voor België ---
Plots.plot(timeseries_data["demand"]["BE"][744:767], 
           label="01/02/2030", 
           linewidth=2,
           color=:orangered3,
           size=(800, 500))

Plots.plot!(timeseries_data["demand"]["BE"][5088:5111], 
            label="01/08/2030", 
            linewidth=2,
            color=:chartreuse4)

title!("Demand Profile timeseries")
xlabel!("Hour")
ylabel!("Load Factor")
Plots.ylims!(0, 1)
Plots.savefig(joinpath(output_dir_fig, "dem_timeseries.svg"))


##############################
### Zonal OPF Batch Analysis ###
##############################

number_of_hours_z = 8760        # Total number of hours in the zonal OPF analysis
hour_start_idx = 1
batch_size = 876 
iterations = Int(number_of_hours_z / batch_size)

# Initialize accumulators
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



@time for idx in 1:iterations
    hs_idx = (hour_start_idx - 1) + (idx - 1) * batch_size + 1
    he_idx = (hour_start_idx - 1) + idx * batch_size
    
    opf_file_name = joinpath(output_dir, "zonal_opf_$(hs_idx)_to_$(he_idx).json")
    data = JSON.parsefile(opf_file_name)
    
    for (i, solution) in data
        for (g, gen) in solution["solution"]["gen"]
            node = zonal_input["gen"]["$g"]["node"]
            gen_type = zonal_input["gen"]["$g"]["type"]
            
            if node in ["BE00", "DE00", "NL00", "UK00", "DKE1", "DEKF"]
                if gen_type in ["Offshore Wind", "Solar PV", "Onshore Wind"]
                    RES += gen["pg"]
                end
                if gen_type == "Offshore Wind"
                    Offshore += gen["pg"]
                end
                if gen_type == "Onshore Wind"
                    Onshore_z += gen["pg"]
                end
                if gen_type == "Solar PV"
                    Solar_z += gen["pg"]
                end
                
                # Optioneel per land generaties optellen (nu uitgecommentarieerd)
                # if node == "BE00"
                #     gen_BE += gen["pg"]
                # elseif node == "DE00"
                #     gen_DE += gen["pg"]
                # elseif node == "NL00"
                #     gen_NL += gen["pg"]
                # elseif node == "UK00"
                #     gen_UK += gen["pg"]
                # elseif node == "DKE1" || node == "DEKF"
                #     gen_DK += gen["pg"]
                # end
                
                generation += gen["pg"]
            end
        end
    end
end
