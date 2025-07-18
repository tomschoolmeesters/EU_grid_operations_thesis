"""
    function Analyse_branch(b,nodal_input,nodal_result,start_hour=1)

Analyzes a power branch (AC or DC) from a power system model over a given time window.

    # Arguments
    - `b::Any`: The branch number (used as a key to access branch data).
    - `nodal_input::Dict`: A dictionary containing the input data for the nodal model, including branch and bus information.
    - `nodal_result::Dict`: A dictionary containing the results of the nodal analysis, including power flow solutions.
    - `start_hour::Int`: The starting hour (in model time) for the analysis period.

    # Description
    This function:
    - Extracts relevant metadata about the specified branch, such as type, buses, and zones.
    - Computes the power flow on the branch over the specified time window.
    - Generates a plot of the absolute power flow over time, along with the branch's rated capacity.

    # Output
    - Prints the branch details
    - Displays a plot of power flow vs. time with rated capacity as a reference.

"""

function Analyse_branch(b,nodal_input,nodal_result,start_hour=1)

    # Get information about the branch
    if "$b" in keys(nodal_input["branchdc"])  # Check for DC branch
        type = nodal_input["branchdc"]["$b"]["type"]
        name = nodal_input["branchdc"]["$b"]["name"]
        f_bus = nodal_input["branchdc"]["$b"]["fbusdc"]
        t_bus = nodal_input["branchdc"]["$b"]["tbusdc"]
        f_bus_zone = nodal_input["busdc"]["$f_bus"]["zone"]
        t_bus_zone = nodal_input["busdc"]["$t_bus"]["zone"]
        rated_Power = nodal_input["branchdc"]["$b"]["rateA"] * 100
    else  # Assume AC branch
        type = nodal_input["branch"]["$b"]["type"]
        f_bus = nodal_input["branch"]["$b"]["f_bus"]
        t_bus = nodal_input["branch"]["$b"]["t_bus"]
        f_bus_zone = nodal_input["bus"]["$f_bus"]["zone"]
        t_bus_zone = nodal_input["bus"]["$t_bus"]["zone"]
        rated_Power = nodal_input["branch"]["$b"]["rate_a"] * 100
    end
    
    # Print summary info
    println("--------------------------------")
    println("Cable or Line: $type")
    if "$b" in keys(nodal_input["branchdc"])
        println("Name: $name")
    end
    println("From bus: $f_bus in zone $f_bus_zone")
    println("To bus: $t_bus in zone $t_bus_zone")
    println("Rated Power: $rated_Power MW")
    println("--------------------------------")

    # Compute power flow for each hour
    Power = zeros(length(nodal_result))
    for i in keys(nodal_result)
        idx = parse(Int, i) - start_hour + 1
        if "$b" in keys(nodal_input["branchdc"])
            Power[idx] = abs(nodal_result["$i"]["solution"]["branchdc"]["$b"]["pt"]) * 100
        else
            Power[idx] = abs(nodal_result["$i"]["solution"]["branch"]["$b"]["pt"]) * 100
        end
    end

    # Plotting
    P5 = Plots.plot()
    Plots.plot!(Power, label="Power Flow")
    Plots.plot!(fill(rated_Power, length(Power)), label="Rated Capacity", linestyle=:dash)
    Plots.title!("Active power in branch $b")
    Plots.xlims!(0.8, 15.2)
    Plots.xticks!(1:1:15)
    Plots.xlabel!("Time [h]")
    Plots.ylabel!("Power [MW]")
    display(P5)    

end