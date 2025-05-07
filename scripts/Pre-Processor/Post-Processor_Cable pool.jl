gurobi = Gurobi.Optimizer
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
    if branch["isbuilt"] == 1
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
hour_end_idx = 36

plot_filename = joinpath("results", join(["grid_input_",use_case,".pdf"]))
_EUGO.plot_grid(nodal_input_ext, plot_filename)

s = Dict("output" => Dict("branch_flows" => true), "conv_losses_mp" => true, "fix_cross_border_flows" => true)
s_dual = Dict("output" => Dict("branch_flows" => true,"duals" => true), "conv_losses_mp" => true,"fix_cross_border_flows" => true)

# This function will  create a dictionary with all hours as result. For all 8760 hours, this might be memory intensive
result_OPF_w = _EUGO.batch_opf_repr(hour_start_idx, hour_end_idx,nodal_input_ext, timeseries_data_reduced, factor, gurobi, s_dual)


#################################
### Calculate total objective ###
#################################
Total_objective = 0
for (i,solution) in result_OPF
    objective = solution["objective"]
    Total_objective += objective
end



#################
### Synergies ###
#################

Sens = zeros(length(built_AC),length(built_AC))

for AC_cand in sort(built_AC)
    #println(AC_cand)
    #AC_cand = sort(built_AC)[1:1][1]
    j_idx = findfirst(==(AC_cand),sort(built_AC))

    nodal_input_wo = deepcopy(nodal_input)

    for (i,branch) in result["solution"]["nw"]["1"]["ne_branch"]
        if branch["built"] == 1 && "$i" != AC_cand
            nodal_input_wo["branch"]["$i"] = Dict{String,Any}()
            nodal_input_wo["branch"]["$i"] = zone_grid["ne_branch"]["$i"]
        end
    end
    for (i,branch) in result["solution"]["nw"]["1"]["branchdc_ne"]
        if branch["isbuilt"] == 1
            nodal_input_wo["branchdc"]["$i"] = Dict{String,Any}()
            nodal_input_wo["branchdc"]["$i"] = zone_grid["branchdc_ne"]["$i"]
        end
    end

    ### Perform OPF
        
    hour_start_idx = 1
    hour_end_idx = 36
    s_dual = Dict("output" => Dict("branch_flows" => true,"duals" => true), "conv_losses_mp" => true,"fix_cross_border_flows" => true)

    result_OPF_wo = _EUGO.batch_opf_repr(hour_start_idx, hour_end_idx,nodal_input_wo, timeseries_data_reduced, factor, gurobi, s_dual);

    ### Calculate sensitivity
    for i_idx in 1:length(built_AC)
        i = sort(built_AC)[i_idx]
        if i == AC_cand
            sens_ij = [0]
        else
            sens_ij = []
            for h in 1:number_of_hours
                sens_ij_h = (factor[h]/8760) * ((result_OPF_w["$h"]["solution"]["branch"]["$i"]["pt"] / result_OPF_wo["$h"]["solution"]["branch"]["$i"]["pt"]) - 1)
                push!(sens_ij,sens_ij_h)
            end
        end
        Sens[i_idx,j_idx] = sum(sens_ij)
    end
end

#################################
### Group synergetic branches ###
#################################

using Graphs

function build_interaction_graph(Sens::Matrix{Float64}; threshold=0.5)
n = size(Sens, 1)
g = SimpleGraph(n)

for i in 1:n, j in i+1:n  # alleen boven de diagonaal
    avg_s = (abs(Sens[i,j]) + abs(Sens[j,i])) / 2
    if avg_s > threshold
        add_edge!(g, i, j)
    end
end

return g
end
function find_line_clusters(Sens::Matrix{Float64}; threshold=0.5)
    g = build_interaction_graph(Sens; threshold=threshold)
    comps = connected_components(g)
    return comps
end

clusters_idx = find_line_clusters(Sens; threshold=2)
groups = []
for cl_idx in clusters_idx
    cl = []
    for i in cl_idx
        cl_i = string(sort(built_AC)[i])
        push!(cl,cl_i)
    end
    push!(groups,cl)
end

##################################
### Calculate alternative TNEP ###
##################################

nodal_input_cl = deepcopy(nodal_input)

for (i,branch) in result["solution"]["nw"]["1"]["ne_branch"]
    if branch["built"] == 1 && !("$i" in groups[2])
        nodal_input_cl["branch"]["$i"] = Dict{String,Any}()
        nodal_input_cl["branch"]["$i"] = zone_grid["ne_branch"]["$i"]
    end
end
for (i,branch) in result["solution"]["nw"]["1"]["branchdc_ne"]
    if branch["isbuilt"] == 1
        nodal_input_cl["branchdc"]["$i"] = Dict{String,Any}()
        nodal_input_cl["branchdc"]["$i"] = zone_grid["branchdc_ne"]["$i"]
    end
end

AC_canidate_keys = []
for i in groups[2]
    for (j,cl) in clusters
        if parse(Int,i) in cl
            push!(AC_canidate_keys,cl)
        end
    end
end

AC_candidate_keys_flat = string.(vcat(AC_canidate_keys...))

zone_grid_cl = deepcopy(nodal_input_cl)
zone_grid_cl["ne_branch"] = Dict{String,Any}()
#zone_grid_cl["branchdc_ne"] = Dict{String,Any}()

for i in AC_candidate_keys_flat
    zone_grid_cl["ne_branch"]["$i"] = ne_branch["$i"]
end


hours = 1:36
# Create dictionary for writing out results
print("######################################", "\n")
print("####### PREPARING DATA      ##########", "\n")
@time mn_input_data = _EUGO.prepare_mn_data_nodal(zone_grid_cl, EU_grid,timeseries_data_reduced, hours)

print("######################################", "\n")
print("####### STARTING OPTIMISATION ########", "\n")

gurobi = JuMP.optimizer_with_attributes(
    Gurobi.Optimizer,
    "MIPGap" => 0.05,
    "DualReductions"  => 0,
    "FeasibilityTol" => 1e-6)         # Stop als de gap kleiner is dan 0.05

s = Dict("output" => Dict("branch_flows" => true), "conv_losses_mp" => true, "fix_cross_border_flows" => true, "process_data_internally" => true)
@time result_TNEP_cl = _PMACDC.run_mp_tnepopf_repr(mn_input_data,_PM.DCPPowerModel, gurobi, multinetwork = true; setting = s)

    
    