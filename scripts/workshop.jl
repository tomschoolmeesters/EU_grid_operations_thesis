

using PowerModels; const _PM = PowerModels
using Ipopt, JuMP
using Gurobi
using PowerModelsACDC; const _PMACDC = PowerModelsACDC
 

test_case_5_acdc = "case5_acdc.m"
 
s_dual = Dict("output" => Dict("branch_flows" => true,"duals" => true), "conv_losses_mp" => true)
s = Dict("output" => Dict("branch_flows" => true), "conv_losses_mp" => true)

data_file_5_acdc = joinpath(@__DIR__,"data_sources",test_case_5_acdc)
data_original_5_acdc = _PM.parse_file(data_file_5_acdc)
 
data_5_acdc = deepcopy(data_original_5_acdc)
_PMACDC.process_additional_data!(data_5_acdc)


 

 
model = Model(Ipopt.Optimizer)
 
ipopt = JuMP.optimizer_with_attributes(Ipopt.Optimizer, "tol" => 1e-6, "print_level" => 0)
gurobi = JuMP.optimizer_with_attributes(Gurobi.Optimizer)
 
formulation = ACPPowerModel
solver = ipopt
result_opf_ac = _PMACDC.run_acdcopf(data_5_acdc,formulation,solver; setting = s_dual)