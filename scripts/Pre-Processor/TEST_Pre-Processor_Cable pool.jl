####################################################
#  Pre-Processor: Creating a candidate cable pool  #
#   This is used for the TEST CASE only            #
#                                                  #
####################################################

using Combinatorics, Statistics
function TEST_candidate_lines(zone_grid,number_of_hours)

    ################################
    ### Initialise Candidate Set ###
    ################################

    CL_exisAC =  Vector{Tuple{Float64, Float64}}()
    CL_exisDC =  Vector{Tuple{Float64, Float64}}()
    CL_newAC = Vector{Tuple{Float64, Float64}}()
    CL_newDC = Vector{Tuple{Float64, Float64}}()

    ############################
    ### Check for congestion ###
    ############################

    #Thermal capacity
    Congested_lines = where_congestion()
    for line in Congested_lines
        if line in keys(nodal_input["branchdc"]) #KEY = BRANCHDC
            FromBus = nodal_input["branchdc"][line]["fbusdc"]
            ToBus = nodal_input["branchdc"][line]["tbusdc"]
            push!(CL_exisDC,(FromBus,ToBus))
        else #KEY = BRANCH  
            FromBus = nodal_input["branch"][line]["f_bus"]
            ToBus = nodal_input["branch"][line]["t_bus"]
            push!(CL_exisAC,(FromBus,ToBus))
        end
    end

    #"Electrical" Capacity based on branch series reactance
    Congested_lines_elec = where_congestion_electrical()
    for line in Congested_lines_elec
        FromBus = nodal_input["branch"][line]["f_bus"]
        ToBus = nodal_input["branch"][line]["t_bus"]
        if !((FromBus,ToBus) in CL_exisAC) && !((ToBus,FromBus) in CL_exisAC)
            push!(CL_exisAC,(FromBus,ToBus))
        end
    end

    ##############################
    ### Nodal Price Difference ###
    ##############################

    # Determine average system price
    average_price=[]
    for i in 1:number_of_hours
        if nodal_result["$i"]["objective"] !== nothing
            lambda=[]
            for bus in keys(nodal_result["$i"]["solution"]["bus"])
                push!(lambda,nodal_result["$i"]["solution"]["bus"]["$bus"]["lam_kcl_r"])
            end
            for dc_bus in keys(nodal_result["$i"]["solution"]["busdc"])
                push!(lambda,nodal_result["$i"]["solution"]["busdc"]["$dc_bus"]["lam_kcl_r"])
            end
            N = length(nodal_result["$i"]["solution"]["bus"])+length(nodal_result["$i"]["solution"]["busdc"])
            average_price = push!(average_price,median(lambda)) 
        end   
    end
    average_price = median(average_price)

        
    bus_AC = Dict{Float64,Any}() # Hoofd dictionary voor alle AC bussen
    bus_DC = Dict{Float64,Any}()  # Hoofd dictionary voor alle DC bussen

    for bus in keys(nodal_input["bus"])
        bus = parse(Int64,bus)
        lambda = []  # Lijst om lambda-waarden per bus op te slaan
        for i in 1:number_of_hours
            push!(lambda, nodal_result["$i"]["solution"]["bus"]["$bus"]["lam_kcl_r"])
        end
        bus_AC[bus] = lambda
    end

    for dc_bus in keys(nodal_input["busdc"])
        dc_bus = parse(Int64,dc_bus)
        lambda = []  # Lijst om lambda-waarden per bus op te slaan
        for i in 1:number_of_hours
            push!(lambda,nodal_result["$i"]["solution"]["busdc"]["$dc_bus"]["lam_kcl_r"])
        end
        bus_DC[dc_bus] = lambda  # Opslaan in de hoofd-dictionary
    end

    wind_bus = Dict{Float64,Any}()
    for g in keys(nodal_input["gen"])
        if nodal_input["gen"]["$g"]["type_tyndp"] == "Offshore Wind"
            bus = nodal_input["gen"]["$g"]["gen_bus"]
            lambda = []  # Lijst om lambda-waarden per bus op te slaan
            for i in 1:number_of_hours
                push!(lambda,nodal_result["$i"]["solution"]["bus"]["$bus"]["lam_kcl_r"])
            end
            wind_bus[bus] = lambda 
        end
    end

    verschillen_AC= Dict{Tuple{Float64, Float64},Any}()  # Opslag voor AC-AC verschillen
    #verschillen_AC_wind = Dict{Tuple{Float64, Float64},Any}()
    verschillen_DC = Dict{Tuple{Float64, Float64},Any}()  # Opslag voor DC-DC verschillen
    AC_buses = collect(keys(bus_AC))
    #AC_buses_wind = collect(keys(wind_bus))
    DC_buses = collect(keys(bus_DC))
    
    for (bus1, bus2) in combinations(AC_buses, 2)  # Alle unieke AC-AC combinaties
        verschil = abs.(bus_AC[bus1] .- bus_AC[bus2])  # Elementgewijs verschil berekenen
        verschillen_AC[(bus1, bus2)] = median(verschil)
    end


    #for (bus1, bus2) in combinations(AC_buses_wind, 2)  # Alle unieke AC-AC combinaties
    #    verschil = abs.(wind_bus[bus1] .- wind_bus[bus2])  # Elementgewijs verschil berekenen
    #    verschillen_AC_wind[(bus1, bus2)] = median(verschil)
    #end

    for (bus1, bus2) in combinations(DC_buses, 2)  # Alle unieke AC-AC combinaties
        verschil = abs.(bus_DC[bus1] .- bus_DC[bus2])  # Elementgewijs verschil berekenen
        verschillen_DC[(bus1, bus2)] = median(verschil)
    end

    # Sorteer combinaties op basis van hun gemiddelde verschil
    sorted_combinaties_AC = sort(collect(verschillen_AC), by=x -> x[2], rev=true)
    #sorted_combinaties_AC_wind = sort(collect(verschillen_AC_wind), by=x -> x[2], rev=true)
    sorted_combinaties_DC = sort(collect(verschillen_DC), by=x -> x[2], rev=true)

    # Top 5 combinaties met grootste verschillen
    top_X_AC = vcat(sorted_combinaties_AC)#, sorted_combinaties_AC_wind[1:30])
    top_X_DC = sorted_combinaties_DC


    # Print de resultaten
    for ((bus1, bus2), diff) in top_X_AC
        println("Combinatie: ($bus1, $bus2) - Mediaan: ", median(diff))
        if !((bus1, bus2) in CL_exisAC) && !((bus2, bus1) in CL_exisAC)
            push!(CL_newAC,(bus1,bus2))
        end
    end

    # Print de resultaten
    for ((bus1, bus2), diff) in top_X_DC
        println("Combinatie: ($bus1, $bus2) - Mediaan: ", median(diff))
        if !((bus1, bus2) in CL_exisDC) && !((bus2, bus1) in CL_exisDC)
            push!(CL_newDC,(bus1,bus2))
        end
    end


    ###########################
    ### Create new branches ###
    ###########################

    ne_branch = Dict{String,Any}()
    Branch_idx = 200
    for (bus1,bus2) in CL_exisAC
        exis_branch = nothing
        for b in keys(nodal_input["branch"])
            if (nodal_input["branch"][b]["f_bus"] == bus1 && nodal_input["branch"][b]["t_bus"] == bus2) || (nodal_input["branch"][b]["f_bus"] == bus2 && nodal_input["branch"][b]["t_bus"] == bus1)
                exis_branch = deepcopy(nodal_input["branch"][b])
            end
        end

        if exis_branch !== nothing
            ne_branch["$Branch_idx"] = exis_branch
            ne_branch["$Branch_idx"]["source_id"][2] = Branch_idx
            ne_branch["$Branch_idx"]["index"] = Branch_idx
            Branch_idx = Branch_idx + 1
        end
    end

    for (bus1,bus2) in CL_newAC
        exis_branch = deepcopy(nodal_input["branch"]["1"])

        ne_branch["$Branch_idx"] = exis_branch
        ne_branch["$Branch_idx"]["f_bus"] = Int(bus1)
        ne_branch["$Branch_idx"]["t_bus"] = Int(bus2)
        ne_branch["$Branch_idx"]["source_id"][2] = Int(Branch_idx)
        ne_branch["$Branch_idx"]["index"] = Int(Branch_idx)
        Branch_idx = Branch_idx + 1
    end

    ne_branchDC = Dict{String,Any}()
    Branch_idx = 1000
    for (bus1,bus2) in CL_exisDC
        exis_branch = nothing
        for b in keys(nodal_input["branchdc"])
            if (nodal_input["branchdc"][b]["fbusdc"] == Int(bus1) && nodal_input["branchdc"][b]["tbusdc"] ==Int(bus2)) || (nodal_input["branchdc"][b]["fbusdc"] == Int(bus2) && nodal_input["branchdc"][b]["tbusdc"] == Int(bus1))
                exis_branch = deepcopy(nodal_input["branchdc"][b])
            end
        end

        if exis_branch !== nothing
            ne_branchDC["$Branch_idx"] = exis_branch
            ne_branchDC["$Branch_idx"]["source_id"][2] = Branch_idx
            ne_branchDC["$Branch_idx"]["index"] = Branch_idx
            ne_branchDC["$Branch_idx"]["name"] = "New DC branch (exis)"
            Branch_idx = Branch_idx + 1
        end
    end

    for (bus1,bus2) in CL_newDC
        exis_branch = deepcopy(nodal_input["branchdc"]["1"])

        ne_branchDC["$Branch_idx"] = exis_branch
        ne_branchDC["$Branch_idx"]["fbusdc"] = Int(bus1)
        ne_branchDC["$Branch_idx"]["tbusdc"] = Int(bus2)
        ne_branchDC["$Branch_idx"]["source_id"][2] = Int(Branch_idx)
        ne_branchDC["$Branch_idx"]["index"] = Int(Branch_idx)
        ne_branchDC["$Branch_idx"]["name"] = "New DC branch (new)"
        Branch_idx = Branch_idx + 1
    end

    zone_grid_ext = deepcopy(zone_grid)
    #zone_grid_ext["branch"] = merge( zone_grid_ext["branch"],ne_branch)
    #zone_grid_ext["branchdc"] = merge( zone_grid_ext["branchdc"],ne_branchDC)

    zone_grid_ext["branchdc_ne"] = deepcopy(ne_branchDC)
    zone_grid_ext["ne_branch"] = deepcopy(ne_branch)


    return zone_grid_ext
end

