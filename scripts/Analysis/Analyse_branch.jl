function Analyse_branch(b,start_hour,planning_year)

    #Get information about bus
    if "$b" in keys(nodal_input["branchdc"]) #KEY = BRANCHDC
        type = nodal_input["branchdc"]["$b"]["type"]
        name = nodal_input["branchdc"]["$b"]["name"]
        f_bus = nodal_input["branchdc"]["$b"]["fbusdc"]
        t_bus = nodal_input["branchdc"]["$b"]["tbusdc"]
        f_bus_zone = nodal_input["busdc"]["$f_bus"]["zone"]
        t_bus_zone = nodal_input["busdc"]["$t_bus"]["zone"]
        rated_Power = nodal_input["branchdc"]["$b"]["rateA"] * 100
    else #KEY = BRANCH  
        type = nodal_input["branch"]["$b"]["type"]  
        f_bus = nodal_input["branch"]["$b"]["f_bus"]
        t_bus = nodal_input["branch"]["$b"]["t_bus"]
        f_bus_zone = nodal_input["bus"]["$f_bus"]["zone"]
        t_bus_zone = nodal_input["bus"]["$t_bus"]["zone"]
        rated_Power = nodal_input["branch"]["$b"]["rate_a"] * 100
    end
    
    start_date = hour_to_date(planning_year, start_hour)
    end_date = hour_to_date(planning_year, start_hour+number_of_hours-1)

    println("--------------------------------")
    println("Cable or Line: $type")
    if "$b" in keys(nodal_input["branchdc"])
        println("Name: $name")
    end
    println("From bus: $f_bus in zone $f_bus_zone")
    println("To bus $t_bus in zone $t_bus_zone")
    println("Rated Power: $rated_Power MW")
    println("Analysed period: vanaf ",start_date," tot ",end_date)
    println("--------------------------------")

    Power = zeros(length(nodal_result))
    for i in keys(nodal_result)
        if nodal_result["$i"]["termination_status"] == "OPTIMAL"

            if "$b" in keys(nodal_input["branchdc"]) #KEY = BRANCHDC
                
                Power[parse(Int,i)] = abs(nodal_result["$i"]["solution"]["branchdc"]["$b"]["pt"])*100

            else
                Power[parse(Int,i)] = abs(nodal_result["$i"]["solution"]["branch"]["$b"]["pt"])*100
            
            end
        end
    end     

    P5 = Plots.plot()
    plot!(Power)
    plot!(fill(rated_Power,length(Power)))
    title!("Active power in branch $b")
    xlabel!("Time [h]")
    ylabel!("Power [MW]")
    display(P5)    

end