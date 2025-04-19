#######################
### POST-PROCESSING ###
#######################

nodal_input_ext = deepcopy(nodal_input)

for (i,branch) in result["solution"]["nw"]["1"]["ne_branch"]
    if branch["built"] == 1
        nodal_input_ext["branch"]["$i"] = Dict{String,Any}()
        nodal_input_ext["branch"]["$i"] = zone_grid["ne_branch"]["$i"]
    end
end
for (i,branch) in result["solution"]["nw"]["1"]["branchdc_ne"]
    if branch["isbuilt"] == 1 && i != "500205"
        nodal_input_ext["branchdc"]["$i"] = Dict{String,Any}()
        nodal_input_ext["branchdc"]["$i"] = zone_grid["branchdc_ne"]["$i"]
    end
end

################################
### Full timestep simulation ###
################################

hour_start_idx = 1
hour_end_idx = 24

plot_filename = joinpath("results", join(["grid_input_",use_case,".pdf"]))
_EUGO.plot_grid(nodal_input_ext, plot_filename)

s = Dict("output" => Dict("branch_flows" => true), "conv_losses_mp" => true, "fix_cross_border_flows" => true)
s_dual = Dict("output" => Dict("branch_flows" => true,"duals" => true), "conv_losses_mp" => true,"fix_cross_border_flows" => true)

# This function will  create a dictionary with all hours as result. For all 8760 hours, this might be memory intensive
result_OPF = _EUGO.batch_opf(hour_start_idx, hour_end_idx, nodal_input_ext, timeseries_data, gurobi, s_dual)


##########################################
### Representative timestep simulation ###
##########################################

hour_start_idx = 1
hour_end_idx = 48

plot_filename = joinpath("results", join(["grid_input_",use_case,".pdf"]))
_EUGO.plot_grid(nodal_input_ext, plot_filename)

s = Dict("output" => Dict("branch_flows" => true), "conv_losses_mp" => true, "fix_cross_border_flows" => true)
s_dual = Dict("output" => Dict("branch_flows" => true,"duals" => true), "conv_losses_mp" => true,"fix_cross_border_flows" => true)

# This function will  create a dictionary with all hours as result. For all 8760 hours, this might be memory intensive
result_OPF = _EUGO.batch_opf_repr(hour_start_idx, hour_end_idx,zone_grid, timeseries_data_reduced, factor, gurobi, s_dual)


#################################
### Calculate total objective ###
#################################
Total_objective = 0
for (i,solution) in nodal_result
    objective = solution["objective"]
    Total_objective += objective
end
