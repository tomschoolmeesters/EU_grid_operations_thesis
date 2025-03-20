####################################################
#  Pre-Processor: Creating a candidate cable pool  #
#  Test case: TYNDP 2020, 2040, 2007               #
#  Number_of_hours: 1200                           #
####################################################

using Combinatorics, Statistics

function median_sytem_price(nodal_result)
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

    return average_price
end

function is_point_in_polygon(point, polygon)
    lat, lon = point
    n = length(polygon)
    inside = false
    j = n
    
    for i in 1:n
        lat_i, lon_i = polygon[i]
        lat_j, lon_j = polygon[j]
        
        if ((lon_i > lon) != (lon_j > lon)) &&
           (lat < (lat_j - lat_i) * (lon - lon_i) / (lon_j - lon_i) + lat_i)
            inside = !inside
        end
        j = i
    end
    return inside
end

function update_connectionzone(OFF_dc_buses)
    updated_OFF_dc_buses = Dict{String,Any}()

    polygon = [
        (59.328063, -1.764659),
        (56.055162, -2.804328),
        (51.148378, 2.795292),
        (54.145881, 8.978585),
        (57.816142, 8.504350)]

    for (b,bus) in OFF_dc_buses
        point = (bus["lat"],bus["lon"])
        if is_point_in_polygon(point,polygon)
            updated_OFF_dc_buses["$b"] = bus
        end
    end
    return updated_OFF_dc_buses
end

function get_susceptance_matrix(nodal_input)
    AC_branches = Dict()
    AC_buses = Vector()
    nr = 1
    for (i, branch) in nodal_input["branch"]
        
        f_bus = branch["f_bus"]
        t_bus = branch["t_bus"]
        index = branch["index"]
        branch_x = branch["br_x"]
        push!(AC_buses, f_bus)
        push!(AC_buses, t_bus)
        
        
        # Gebruik een tuple als sleutel
        if !((f_bus,t_bus) in keys(AC_branches))
            
            AC_branches[(f_bus, t_bus)] = Dict()
            AC_branches[(f_bus, t_bus)]["br_x"] = branch["br_x"]
            AC_branches[(f_bus, t_bus)]["idx"] = branch["index"]
            AC_branches[(f_bus, t_bus)]["f_bus"] = f_bus
            AC_branches[(f_bus, t_bus)]["t_bus"] = t_bus
            AC_branches[(f_bus, t_bus)]["nr"] = nr
            nr += 1
        end
        #AC_branches["$index"] = Dict()
        #AC_branches["$index"]["br_x"] = branch["br_x"]
        #AC_branches["$index"]["idx"] = branch["index"]
        #AC_branches["$index"]["f_bus"] = f_bus    
        #AC_branches["$index"]["t_bus"] = t_bus
        

    end
    AC_buses = unique(AC_buses)
    AC_buses = sort(AC_buses)
    AC_buses_amount = length(AC_buses)
    bus_index = Dict(bus => idx for (idx, bus) in enumerate(AC_buses))
    susceptance_matrix = spzeros(AC_buses_amount,AC_buses_amount)
    println("Start first step")
    for (br_idx,branch) in AC_branches
        if branch["f_bus"] in keys(bus_index) && branch["t_bus"] in keys(bus_index)
            i = bus_index[branch["f_bus"]]
            j = bus_index[branch["t_bus"]]
            if i!=j
                susceptance_matrix[i,j] = -1/branch["br_x"]
                susceptance_matrix[j,i] = -1/branch["br_x"]
            end
        else
            println("Bus $(branch["f_bus"]) or $(branch["t_bus"]) not in bus_index")
        end
    end

    println("first step done")
    for i in 1:AC_buses_amount
        susceptance_matrix[i,i] = -sum(susceptance_matrix[i,:])
    end
    return susceptance_matrix, bus_index, AC_branches
end

function get_reduced_susceptance_matrix(nodal_input)
    susceptance_matrix, bus_index, AC_branches = get_susceptance_matrix(nodal_input)
    reduced_susceptance_matrix = deepcopy(susceptance_matrix)
    slack_bus = [i for (i,bus) in nodal_input["bus"] if bus["bus_type"] == 3]
    for bus in slack_bus
        bus = parse(Int,bus)
        if bus in keys(bus_index)
            println("Slack $bus")
            slack_i = bus_index[bus]
            reduced_susceptance_matrix = reduced_susceptance_matrix[1:end .!= slack_i, 1:end .!= slack_i]
            bus_index = Dict(k => (v > slack_i ? v - 1 : v) for (k, v) in bus_index if k != bus)
        end
    end
    
    return reduced_susceptance_matrix, bus_index,AC_branches
end

function get_inverse_susceptance_matrix(nodal_input)
    reduced_susceptance_matrix, bus_index, AC_branches = get_reduced_susceptance_matrix(nodal_input)
    M = lu(Matrix(reduced_susceptance_matrix))
    L = M.L
    U = M.U
    inverse_susceptance_matrix = inv(Matrix(U))*inv(Matrix(L))
    return inverse_susceptance_matrix, bus_index, AC_branches
end



function get_PTDF_matrix(nodal_input)
    B_inv, bus_index, AC_branches = get_inverse_susceptance_matrix(nodal_input)
    slack_bus = [i for (i,bus) in nodal_input["bus"] if bus["bus_type"] == 3]
    num_nodes = size(B_inv,1)
    num_branches = length(AC_branches)

    A = spzeros(num_branches,num_nodes)
    X = spzeros(num_branches,num_branches)
    PTDF_matix = spzeros(num_branches,num_nodes)
    for (line_idx, line) in AC_branches
        
        nr = line["nr"]
        f_bus = line["f_bus"]
        f_bus_i = bus_index[f_bus]
        t_bus = line["t_bus"]
        t_bus_i = bus_index[t_bus]
        
        
            
            A[nr,f_bus_i] = 1
            A[nr,t_bus_i] = -1

            X[nr,nr] = line["br_x"]
            
        #end
    end
    PTDF_matix = inv(Matrix(X))*A*B_inv
    
end

function get_congestion_matrix(nodal_input,nodal_result)
    Loading_AC, = hourly_Loadfactor(nodal_input,1:number_of_hours)
    Loading_AC = sort(Loading_AC)
    number_of_branches = length(Loading_AC)
    Congestion_matrix = zeros(number_of_branches,144)
    row = 1
    for (b_id,branch) in Loading_AC
        Congestion_matrix[row,:] = branch
        row += 1
    end
    return Congestion_matrix


end
# Bereken de WCSS voor verschillende aantal clusters
function compute_wcss(hc, D, max_k)
    wcss = Float64[]
    for k in 1:max_k
        labels = cutree(hc, k=k)  # Cluster labels bepalen
        total_variance = 0.0
        for i in 1:k
            cluster_indices = findall(labels .== i)
            if length(cluster_indices) > 1
                cluster_distances = D[cluster_indices, cluster_indices]
                total_variance += sum(cluster_distances) / (2 * length(cluster_indices))
            end
        end
        push!(wcss, total_variance)
    end
    return wcss
end

# Voer de berekeningen uit
max_clusters = 207
wcss = compute_wcss(hc, Dist, max_clusters)

# Plot de elbow curve
Plots.plot(1:max_clusters, wcss, marker=:o, xlabel="Aantal clusters", ylabel="WCSS", title="Elbow Method")
cable_indices = collect(keys(Loading_AC))  # Alle kabelindexen
optimal_k = 120  # Verander dit naar het gevonden aantal clusters

# Haal cluster labels op
labels = cutree(hc, k=optimal_k)

# Print welke transmissielijn in welk cluster zit
Cluster_dict = Dict()
for i in 1:optimal_k
    println("Cluster $i: ", findall(labels .== i))
    Cluster_dict[i] = findall(labels .== i)
    
end
Cluster_dict = sort(Cluster_dict)
for (cluster,cables) in Cluster_dict
    corr_labels = [cable_indices[i] for i in cables]
    Cluster_dict[cluster] = corr_labels
end


function candidate_lines(nodal_input,nodal_result,OFF_dc_buses,number_of_hours)

    updated_OFF_DC_buses = update_connectionzone(OFF_dc_buses)
    
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
    #Congested_lines = Congested_lines[1:2]
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
    #Congested_lines_elec = Congested_lines_elec[1:2]
    for line in Congested_lines_elec
        FromBus = nodal_input["branch"][line]["f_bus"]
        ToBus = nodal_input["branch"][line]["t_bus"]
        if !((FromBus,ToBus) in CL_exisAC) && !((ToBus,FromBus) in CL_exisAC)
            push!(CL_exisAC,(FromBus,ToBus))
        end
    end

    ##################################
    ### Check for price difference ###
    ##################################

    bus_AC = Dict()  # Hoofd dictionary voor alle AC bussen
    zones = deepcopy(nodal_input["zones"])
    for zone in zones
        bus_AC["$zone"] = Dict{Float64,Any}()
    end

    bus_DC = Dict{Float64,Any}()  # Hoofd dictionary voor alle DC bussen
    bus_OFF_DC = Dict{Float64,Any}()  # Hoofd dictionary voor alle OFFSHORE DC bussen

    for bus in keys(nodal_input["bus"])
        bus = parse(Int64,bus)
        bus_zone = nodal_input["bus"]["$bus"]["zone"]
        lambda = []  # Lijst om lambda-waarden per bus op te slaan
        for i in 1:number_of_hours
            push!(lambda, nodal_result["$i"]["solution"]["bus"]["$bus"]["lam_kcl_r"])
        end

        if bus_zone in zones
            bus_AC["$bus_zone"][bus] = lambda  # Opslaan in de hoofd-dictionary
        end
    end

    for dc_bus in keys(nodal_input["busdc"])
        dc_bus = parse(Int64,dc_bus)
        lambda = []  # Lijst om lambda-waarden per bus op te slaan
        for i in 1:number_of_hours
            push!(lambda,nodal_result["$i"]["solution"]["busdc"]["$dc_bus"]["lam_kcl_r"])
        end
        if !("$dc_bus" in keys(updated_OFF_DC_buses))
            bus_DC[dc_bus] = lambda 
        else
            bus_OFF_DC[dc_bus] = lambda  
        end
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

    verschillen_AC = Dict{String, Any}()  # Hoofd dictionary voor alle AC bussen
    for zone in zones
        verschillen_AC["$zone"] = Dict{Tuple{Float64, Float64},Any}()
    end
    verschillen_AC_wind = Dict{Tuple{Float64, Float64},Any}()
    verschillen_DC = Dict{Tuple{Float64, Float64},Any}()  
    verschillen_OFF_DC = Dict{Tuple{Float64, Float64},Any}() 

    AC_buses = Dict{String,Any}()
    for zone in zones
        AC_buses["$zone"] = collect(keys(bus_AC["$zone"]))
    end
    AC_buses_wind = collect(keys(wind_bus))
    DC_buses = collect(keys(bus_DC))
    OFF_DC_buses = collect(keys(bus_OFF_DC))

    for zone in zones
        for (bus1, bus2) in combinations(AC_buses["$zone"], 2)  # Alle unieke AC-AC combinaties
            if _EUGO.latlon2distance(nodal_input,Int(bus1),Int(bus2)) <= 100
                verschil = abs.(bus_AC["$zone"][bus1] .- bus_AC["$zone"][bus2])  # Elementgewijs verschil berekenen
                verschillen_AC["$zone"][(bus1, bus2)] = median(verschil)
            end
        end
    end

    for (bus1, bus2) in combinations(AC_buses_wind, 2)  # Alle unieke AC-AC combinaties
        if _EUGO.latlon2distance(nodal_input,Int(bus1),Int(bus2)) <= 100
            verschil = abs.(wind_bus[bus1] .- wind_bus[bus2])  # Elementgewijs verschil berekenen
            verschillen_AC_wind[(bus1, bus2)] = median(verschil)
        end
    end

    for (bus1, bus2) in combinations(DC_buses, 2)  # Alle unieke AC-AC combinaties
        verschil = abs.(bus_DC[bus1] .- bus_DC[bus2])  # Elementgewijs verschil berekenen
        verschillen_DC[(bus1, bus2)] = median(verschil)
    end

    for (bus1, bus2) in combinations(OFF_DC_buses, 2)  # Alle unieke AC-AC combinaties
        verschil = abs.(bus_OFF_DC[bus1] .- bus_OFF_DC[bus2])  # Elementgewijs verschil berekenen
        verschillen_OFF_DC[(bus1, bus2)] = median(verschil)
    end

    # Sorteer combinaties op basis van hun gemiddelde verschil
    sorted_combinaties_AC = Dict{String,Any}()
    for zone in zones
        sorted_combinaties_AC["$zone"] = sort(collect(verschillen_AC["$zone"]), by=x -> x[2], rev=true)
    end
    sorted_combinaties_AC_wind = sort(collect(verschillen_AC_wind), by=x -> x[2], rev=true)
    sorted_combinaties_DC = sort(collect(verschillen_DC), by=x -> x[2], rev=true)
    sorted_combinaties_OFF_DC = sort(collect(verschillen_OFF_DC), by=x -> x[2], rev=true)

    # Top 5 combinaties met grootste verschillen
    #top_X_AC = []
    top_X_AC = vcat(
        [sorted_combinaties_AC["$zone"] for zone in zones],
        sorted_combinaties_AC_wind[1:2])
    
    top_X_DC = vcat(sorted_combinaties_DC[1:2],
                    sorted_combinaties_OFF_DC[1:2])

    #println(top_X_DC)
    #println(sorted_combinaties_AC_wind[1:30])


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
    Branch_idx = 20000
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
        exis_branch = deepcopy(nodal_input["branch"]["8659"])

        ne_branch["$Branch_idx"] = exis_branch
        ne_branch["$Branch_idx"]["f_bus"] = Int(bus1)
        ne_branch["$Branch_idx"]["t_bus"] = Int(bus2)
        ne_branch["$Branch_idx"]["source_id"][2] = Int(Branch_idx)
        ne_branch["$Branch_idx"]["index"] = Int(Branch_idx)
        Branch_idx = Branch_idx + 1
    end

    ne_branchDC = Dict{String,Any}()
    Branch_idx = 30000
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
        exis_branch = deepcopy(nodal_input["branchdc"]["32"])

        ne_branchDC["$Branch_idx"] = exis_branch
        ne_branchDC["$Branch_idx"]["fbusdc"] = Int(bus1)
        ne_branchDC["$Branch_idx"]["tbusdc"] = Int(bus2)
        ne_branchDC["$Branch_idx"]["source_id"][2] = Int(Branch_idx)
        ne_branchDC["$Branch_idx"]["index"] = Int(Branch_idx)
        ne_branchDC["$Branch_idx"]["name"] = "New DC branch (new)"
        Branch_idx = Branch_idx + 1
    end

    zone_grid_ext = deepcopy(nodal_input)
    #zone_grid_ext["branch"] = merge( zone_grid_ext["branch"],ne_branch)
    #zone_grid_ext["branchdc"] = merge( zone_grid_ext["branchdc"],ne_branchDC)

    zone_grid_ext["branchdc_ne"] = deepcopy(ne_branchDC)
    zone_grid_ext["ne_branch"] = deepcopy(ne_branch)

    return zone_grid_ext
end

