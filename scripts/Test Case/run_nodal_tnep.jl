
#1: Create all possible candidates (AC & DC)
ne_branch, ne_branchDC, AC_new_corridor_idx, DC_new_corridor_idx = _EUGO.candidate_lines_ext(nodal_input,new_DC_buses,relocation_dict)

#2: Include cost data for every candidate (AC & DC)
ne_branch, ne_branchDC = _EUGO.update_cost_data(ne_branch,ne_branchDC,nodal_input)

#3: Create the PowerFlow matrix & Impact matrix for all candidate_lines
number_of_hours = 15
Impact_matrix, selected_indices_AC, selected_indices_DC, dc_to_ac_map = _EUGO.PTDF_analysis_full(nodal_input,nodal_result,number_of_hours,ne_branch,ne_branchDC)

zone_grid = _EUGO.pre_processor(nodal_input, nodal_result, Impact_matrix, selected_indices_AC, selected_indices_DC, number_of_hours, factor, AC_new_corridor_idx, ne_branch, ne_branchDC,output_dir; start_hour=1)


#######################
### Plot candidates ###
#######################
output_dir_fig = joinpath(@__DIR__, "..", "Test Case", "Figures", "$scenario"*"_"*"$year"*"_"*"$climate_year")
plot_filename = joinpath(output_dir_fig, join(["input_candidates_tnep.svg"]))
_EUGO.plot_grid_candidates(zone_grid,plot_filename)

################################
### Full timestep simulation ###
################################

hours = 1:24 
# Create dictionary for writing out results
print("######################################", "\n")
print("####### PREPARING DATA      ##########", "\n")
@time mn_input_data = _EUGO.prepare_mn_data_nodal(zone_grid, EU_grid,timeseries_data, hours)

print("######################################", "\n")
print("####### STARTING OPTIMISATION ########", "\n")

gurobi = JuMP.optimizer_with_attributes(
    Gurobi.Optimizer,
    "MIPGap" => 0.05,       # Stop als de gap kleiner is dan 5%
    "DualReductions"  => 0) 


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
    "MIPGap" => 0.05,       # Stop als de gap kleiner is dan 5%
    "DualReductions"  => 0,
    "MIPFocus" => 3) 


s = Dict("output" => Dict("branch_flows" => true), "conv_losses_mp" => true, "fix_cross_border_flows" => true, "process_data_internally" => false)
@time result = _PMACDC.run_mp_tnepopf_repr(mn_input_data,_PM.DCPPowerModel, gurobi, multinetwork = true; setting = s)


#############################
### Plot built candidates ###
#############################

output_dir_fig = joinpath(@__DIR__, "..", "Test Case", "Figures", "$scenario"*"_"*"$year"*"_"*"$climate_year")
plot_filename = joinpath(output_dir_fig, join(["plot_built_tnep.svg"]))
plot_grid_tnep(zone_grid,plot_filename,result)


####################
### Save results ###
####################

json_string = JSON.json(result)
result_file_name = joinpath(output_dir, "result_nodal_tnep.json")
open(result_file_name,"w") do f
  JSON.print(f, json_string)
end

json_string = JSON.json(zone_grid)
input_file_name = joinpath(output_dir, "input_nodal_tnep.json")
open(input_file_name,"w") do f
  JSON.print(f, json_string)
end
