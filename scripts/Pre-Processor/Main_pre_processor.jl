function main_pre_processor(nodal_input,nodal_result)
    AC_branches, = get_AC_branch_info(nodal_input)
    Distance_matrix = get_distance_matrix(nodal_input,nodal_result,AC_branches)
    hc = hclust(Distance_matrix)
    max_clusters = size(Distance_matrix,1)

    WCSS = compute_wcss(hc, Distance_matrix, max_clusters)
    
    Plots.plot(1:max_clusters, WCSS, marker=:o, xlabel="Aantal clusters", ylabel="WCSS", title="Elbow Method")

    println("Enter the desired number of clusters (1 to $max_clusters): ")
    user_input = parse(Int, readline())

    # Check if the input is within the valid range
    if user_input < 1 || user_input > max_clusters
        println("Invalid input. Please choose a value between 1 and $max_clusters.")
    else
        println("Selected number of clusters: ", user_input)
        optimal_k = user_input
        labels = cutree(hc; k=optimal_k) 
        # Print welke transmissielijn in welk cluster zit
        Cluster_dict = Dict()
        for i in 1:optimal_k
            println("Cluster $i: ", findall(labels .== i))
            Cluster_dict[i] = findall(labels .== i)
            
        end
        Cluster_dict = sort(Cluster_dict)
        Cluster_dict_idx = deepcopy(Cluster_dict)
        for (cluster,cables) in Cluster_dict_idx
            corr_labels = []
            index = nothing
            for i in cables
                for (_, data) in AC_branches
                    if data["nr"] == i
                        index = data["idx"]
                    end
                end
                push!(corr_labels,index)
            end
            Cluster_dict_idx[cluster] = corr_labels
        end
    end

end



function PTDF_analysis(nodal_input,nodal_result,number_of_hours)
    PTDF_matrix, AC_branches, bus_index = get_PTDF_matrix(nodal_input)
    # Transform info from PTDF to a powerflow impact matrix: what is the impact of reinforcement ij on branch kl
    
    Powerflow_matrix = zeros(size(PTDF_matrix,1),size(PTDF_matrix,1))
    for i in 1:size(PTDF_matrix, 1)
        for j in 1:size(PTDF_matrix,1)
            # Zoek de tuple-key waarbij "nr" gelijk is aan i
            found_key = findfirst(k -> get(AC_branches[k], "nr", nothing) == j, collect(keys(AC_branches)))
        
            if isnothing(found_key)
                error("Geen bijbehorende key gevonden voor nr = $j")
            end
        
            # Omdat findfirst een index teruggeeft, moeten we de echte key ophalen
            actual_key = collect(keys(AC_branches))[found_key]
        
            f_bus = get(AC_branches[actual_key], "f_bus", nothing)
            t_bus = get(AC_branches[actual_key], "t_bus", nothing)
            branch_idx = get(AC_branches[actual_key], "idx", nothing)
        
            if isnothing(f_bus) || isnothing(t_bus)
                error("f_bus of t_bus ontbreekt voor key $actual_key")
            end
        
            f_bus_idx = get(bus_index, f_bus, nothing)
            t_bus_idx = get(bus_index, t_bus, nothing)
            candidate_rating = nodal_input["branch"]["$branch_idx"]["rate_a"]
        
            if isnothing(f_bus_idx) || isnothing(t_bus_idx)
                error("Busindex ontbreekt voor f_bus=$f_bus of t_bus=$t_bus")
            end
        
            Powerflow_matrix[i, j] = abs(PTDF_matrix[i, t_bus_idx] - PTDF_matrix[i, f_bus_idx])*candidate_rating
        end
    end

    Lambda_matrix = get_dual_branch(AC_branches, nodal_result,number_of_hours)
    Impact_matrix = Powerflow_matrix .* reshape(Lambda_matrix, 546, 1, 144)

    return Impact_matrix   
end

function PTDF_analysis_full(nodal_input,nodal_result,number_of_hours,ne_branch,ne_branchDC)
    PTDF_matrix, AC_branches, bus_index = get_PTDF_matrix(nodal_input)
    # Transform info from PTDF to a powerflow impact matrix: what is the impact of reinforcement ij on branch kl
    amount_cand = length(ne_branch)+length(ne_branchDC)
    Powerflow_matrix = zeros(size(PTDF_matrix,1),amount_cand)
    for i in 1:size(PTDF_matrix, 1) # i = elke bestaande AC_branch 
        #AC_candidates first
        for (idx,branch) in ne_branch 
            idx = parse(Int,idx)
            j = idx - 20000 + 1
            f_bus = get(branch,"f_bus",nothing)
            t_bus = get(branch,"t_bus",nothing)
            branch_idx = branch["index"]
        
            f_bus_idx = get(bus_index, f_bus, nothing)
            t_bus_idx = get(bus_index, t_bus, nothing)
            candidate_rating = branch["rate_a"]

            if isnothing(f_bus_idx) || isnothing(t_bus_idx)
                error("Busindex ontbreekt voor f_bus=$f_bus of t_bus=$t_bus")
            end
        
            Powerflow_matrix[i, j] = abs(PTDF_matrix[i, t_bus_idx] - PTDF_matrix[i, f_bus_idx])*candidate_rating
        end
        #DC_candidates second
        for (idx,branchDC) in ne_branchDC 
            idx = parse(Int,idx)
            j = idx - 30000 + 1 + length(ne_branch)
            f_busDC = branchDC["fbusdc"]
            t_busDC = branchDC["tbusdc"]

            f_busAC = 0
            t_busAC = 0

            for (c,conv) in nodal_input["convdc"]
                if conv["busdc_i"] == f_busDC
                    f_busAC = conv["busac_i"]
                end
                if conv["busdc_i"] == t_busDC
                    t_busAC = conv["busac_i"]
                end
            end
            branch_idx = branchDC["index"]
        
            f_bus_idx = get(bus_index, f_busAC, nothing)
            t_bus_idx = get(bus_index, t_busAC, nothing)
            candidate_rating = branchDC["rateA"]

            if isnothing(f_bus_idx) || isnothing(t_bus_idx)
                error("Busindex ontbreekt voor f_bus=$f_bus of t_bus=$t_bus")
            end
        
            Powerflow_matrix[i, j] = abs(PTDF_matrix[i, t_bus_idx] - PTDF_matrix[i, f_bus_idx])*candidate_rating
        end
    end
    
    Lambda_matrix = get_dual_branch(AC_branches, nodal_result,number_of_hours)
    #Lambda_matrix = get_dual_branch_full(ne_branch,ne_branchDC, nodal_result,number_of_hours)
    Impact_matrix = Powerflow_matrix .* reshape(Lambda_matrix, size(PTDF_matrix,1), 1, number_of_hours)

    return Impact_matrix   
end




function pre_processor()

    #1: Create all possible candidates (AC & DC)
    ne_branch, ne_branchDC = candidate_lines(nodal_input,OFF_dc_buses)

    #2: Create the PowerFlow matrix & Impact matrix for all candidate_lines
    Impact_matrix = PTDF_analysis_full(nodal_input,nodal_result,number_of_hours,ne_branch,ne_branchDC)

    #3: Filter candidates based on their impact
    amount_cand = length(ne_branch)+length(ne_branchDC)
    Impact = Vector()
    for i in 1:amount_cand
        push!(Impact,sum(Impact_matrix[:,i,:]))
    end
    filename = "ImpactBE_NL.xlsx"

    # Open een nieuw Excel-bestand en schrijf de vector naar de eerste kolom
    XLSX.openxlsx(filename, mode="w") do xf
        sheet = xf[1]  # Gebruik het eerste werkblad
        sheet["A1"] = "Impact"  # Zet een kolomtitel
        for i in 1:length(Impact)
            sheet["A$(i+1)"] = Impact[i]  # Schrijf elk element onder elkaar
        end
    end


    #4: Update zone_grid for TNEP problem


    
end