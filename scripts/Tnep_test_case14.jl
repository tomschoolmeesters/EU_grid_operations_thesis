
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
using CSV
using DataFrames
using Plots

function generate_timeseries()
    timeseries_data = Dict{String,Any}()
    timeseries_data["wind_offshore"] = Dict{String,Any}()
    timeseries_data["wind_offshore"]["6"] = Vector{Any}()
    timeseries_data["demand"] = Vector{Any}()


    df = CSV.read("./data_sources/timeseries_offshore_wind.csv",DataFrame)
    timeseries_offshore_wind = df[:,:1]
    timeseries_data["wind_offshore"]["6"] = timeseries_offshore_wind

    df = CSV.read("./data_sources/timeseries_demand.csv",DataFrame)
    timeseries_demand = df[:,:1]
    timeseries_data["demand"] = timeseries_demand*1.5

    return timeseries_data
end


#####################################
#####################################

file = "./data_sources/case14.m"
Test_Case = _PM.parse_file(file)
_PMACDC.process_additional_data!(Test_Case)
for (g,gen) in Test_Case["gen"]
    if g == 6
        gen["type_tyndp"] = "wind_offshore"
    elseif g == 1 || g == 2
        gen["type_tyndp"] = "gas"
    else
        gen["type_tyndp"] = "synchronous generator"
    end
end
Test_Case["branchdc"] = Dict(string(parse(Int, k) + 500) => v for (k, v) in Test_Case["branchdc"])
for (l, load) in Test_Case["load"]
    load["pred_rel_max"] = 0
    load["cost_red"] = 10e5 * Test_Case["baseMVA"]
    load["cost_curt"] = 10e5 * Test_Case["baseMVA"]
    load["flex"] = 1
end

timeseries_data = generate_timeseries()

gurobi = Gurobi.Optimizer

# Start runnning hourly OPF calculations
start_hour = 1 
number_of_hours = 144

input_data = deepcopy(Test_Case)
s = Dict("output" => Dict("branch_flows" => true,"duals" => true), "conv_losses_mp" => true)
nodal_result = Dict{String, Any}("$hour" => nothing for hour in 1:number_of_hours)
for hour = start_hour:(start_hour+number_of_hours-1)
    print("Hour ", hour, " of ", start_hour+number_of_hours-1, "\n")
    # Write time series data into input data dictionary
    Input_data = deepcopy(Test_Case)
    _EUGO.hourly_grid_data_test!(Input_data, Test_Case, hour, timeseries_data)
    # Solve Network Flow OPF using PowerModels
    nodal_result["$hour"] = _PMACDC.run_acdcopf(Input_data, PowerModels.DCPPowerModel, gurobi; setting = s)
end

nodal_input = deepcopy(input_data)
input_data = TEST_candidate_lines(input_data,number_of_hours)


for (b,branch) in input_data["ne_branch"]
    branch["construction_cost"] = 0
end

for (b,branch) in input_data["branchdc_ne"]
    branch["cost"] = 0
end

mn_data = _IM.replicate(input_data, number_of_hours, Set{String}(["source_type", "name", "source_version", "per_unit"]))

for hour = start_hour:(start_hour+number_of_hours-1)
    for (l, load) in mn_data["nw"]["$hour"]["load"]
        load["pd"] =  timeseries_data["demand"][hour] * nodal_input["load"][l]["pd"]
    end
    
    for (g, gen) in mn_data["nw"]["$hour"]["gen"]
        if gen["type_tyndp"] == "Offshore Wind"
            gen["pg"] =  timeseries_data["wind_offshore"][zone][hour]* nodal_input["gen"][g]["pmax"]
            gen["pmax"] =  timeseries_data["wind_offshore"][zone][hour] * nodal_input["gen"][g]["pmax"]
        end
    end
end


gurobi = JuMP.optimizer_with_attributes(
    Gurobi.Optimizer)

s = Dict("output" => Dict("branch_flows" => true), "conv_losses_mp" => true, "fix_cross_border_flows" => false, "process_data_internally" => false)
@time result = _PMACDC.run_mp_tnepopf(mn_data,_PM.DCPPowerModel, gurobi, multinetwork = true; setting = s)

#################
### ANALYSIS ####
#################

function Analyse_generator(g) # generator index g
    
    #Get information about gen
    bus = input_data["gen"]["$g"]["gen_bus"]
    pmax = input_data["gen"]["$g"]["pmax"]*100 #MW


    println("--------------------------------")
    println("Generator index: ",g)
    println("Generator bus: ",bus)
    println("Theoretical maximum power:", pmax," MW")
    println("--------------------------------")

    #Determine produced energy profile
    production = []
    for i in start_hour:(start_hour+number_of_hours-1)
        if nodal_result["$i"]["objective"] !== nothing
            push!(production,nodal_result["$i"]["solution"]["gen"]["$g"]["pg"]*100)
        else
            push!(production,0.0001) #0.0001 so I can highlight the infeasible time periods
        end
    end

    P1 = Plots.plot(production,label="Production")
    title!("Production profile of generator $g")
    xlabel!("Time [h]")
    ylabel!("Power [MW]")

    time = 1:length(production)
    highlight_indices = findall(x -> x == 0.0001, production)
    scatter!(time[highlight_indices], production[highlight_indices], label="Infeasible", color=:red, marker=:circle)
    
    #Calculate curtailment 
        #If Offshore Wind
    if g != "6"
        display(P1)
    else
        Uncurtailed_power = Vector()
        for i in start_hour:(start_hour+number_of_hours-1)
            push!(Uncurtailed_power,timeseries_data["wind_offshore"][g][i] * input_data["gen"][g]["pmax"]*100)
        end

        plot!(Uncurtailed_power, label="uncurtailed_energy")
        display(P1)
        
    end
end


function Analyse_branch(b)
    #Get information about bus
    if "$b" in keys(input_data["branchdc"]) #KEY = BRANCHDC
        f_bus = nodal_input["branchdc"]["$b"]["fbusdc"]
        t_bus = nodal_input["branchdc"]["$b"]["tbusdc"]
        thermal_Rating = nodal_input["branchdc"]["$b"]["rateA"] * 100
        electric_capacity = thermal_Rating

    else #KEY = BRANCH   
        f_bus = nodal_input["branch"]["$b"]["f_bus"]
        t_bus = nodal_input["branch"]["$b"]["t_bus"]
        thermal_Rating = nodal_input["branch"]["$b"]["rate_a"] * 100
        electric_capacity = nodal_input["branch"]["$b"]["angmax"] / nodal_input["branch"]["$b"]["br_x"] * 100
    end
    
    println("--------------------------------")
    println("From bus: $f_bus ")
    println("To bus $t_bus ")
    println("Rated Power: $thermal_Rating MW")
    println("Electrical capacity: $electric_capacity MW")
    println("--------------------------------")

    Power = zeros(length(nodal_result))
    for i in keys(nodal_result)
        if "$b" in keys(nodal_input["branchdc"]) #KEY = BRANCHDC
            Power[parse(Int,i)] = abs(nodal_result["$i"]["solution"]["branchdc"]["$b"]["pt"])*100
        else
            Power[parse(Int,i)] = abs(nodal_result["$i"]["solution"]["branch"]["$b"]["pt"])*100
        end
    end     

    P5 = Plots.plot()
    plot!(Power,label="Power flow")
    plot!(fill(thermal_Rating,length(Power)),label="Rated Power",color=:red)
    plot!(fill(electric_capacity,length(Power)),label="Electrical capacity",color=:green)
    title!("Active power in branch $b")
    xlabel!("Time [h]")
    ylabel!("Power [MW]")
    display(P5)    

end