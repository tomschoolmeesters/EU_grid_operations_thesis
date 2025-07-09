
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



#######################
### Plot candidates ###
#######################

plot_filename = joinpath("results", join(["grid_input_candidates_tnep_test",use_case,".pdf"]))
plot_grid_candidates(zone_grid,plot_filename)

################################
### Full timestep simulation ###
################################

hours = 1:24
# Create dictionary for writing out results
print("######################################", "\n")
print("####### PREPARING DATA      ##########", "\n")
@time mn_input_data = prepare_mn_data_nodal(zone_grid, EU_grid,timeseries_data, hours)

print("######################################", "\n")
print("####### STARTING OPTIMISATION ########", "\n")

gurobi = JuMP.optimizer_with_attributes(
    Gurobi.Optimizer,
    "MIPGap" => 0.05,
    "DualReductions"  => 0,
    "FeasibilityTol" => 1e-6)         # Stop als de gap kleiner is dan 0.01


s = Dict("output" => Dict("branch_flows" => true), "conv_losses_mp" => true, "fix_cross_border_flows" => true, "process_data_internally" => true)
@time result = _PMACDC.run_mp_tnepopf(mn_input_data,_PM.DCPPowerModel, gurobi, multinetwork = true; setting = s)


##########################################
### Representative timestep simulation ###
##########################################

hours = 1:15
# Create dictionary for writing out results
print("######################################", "\n")
print("####### PREPARING DATA      ##########", "\n")
@time mn_input_data = _EUGO.prepare_mn_data_nodal(zone_grid, EU_grid,timeseries_data_reduced, hours)

print("######################################", "\n")
print("####### STARTING OPTIMISATION ########", "\n")

gurobi = JuMP.optimizer_with_attributes(
    Gurobi.Optimizer,
    "MIPGap" => 0.15,
    "DualReductions"  => 0,
    "FeasibilityTol" => 1e-6,
    "MIPFocus" => 3) 


s = Dict("output" => Dict("branch_flows" => true), "conv_losses_mp" => true, "fix_cross_border_flows" => true, "process_data_internally" => false)
@time result = _PMACDC.run_mp_tnepopf_repr(mn_input_data,_PM.DCPPowerModel, gurobi, multinetwork = true; setting = s)


#############################
### Plot built candidates ###
#############################
plot_filename = joinpath("results", join(["grid_input_tnep_detailed",use_case,".pdf"]))
plot_grid_tnep(zone_grid,plot_filename,result)


####################
### Save results ###
####################

json_string = JSON.json(result)
result_file_name = joinpath(_EUGO.BASE_DIR, "results", "TNEP"*tyndp_version, join(["result_tnep_BENL_", scenario*year,"_", climate_year, ".json"]))
open(result_file_name,"w") do f
  JSON.print(f, json_string)
end
