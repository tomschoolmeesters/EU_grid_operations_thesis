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
    println("Start computing PowerFlow matrix")
    # Precompute DC to AC bus mappings for faster lookup
    dc_to_ac_map = Dict(conv["busdc_i"] => conv["busac_i"] for (_, conv) in nodal_input["convdc"])
    ac_branch_indices = [(bus_index[branch["f_bus"]], bus_index[branch["t_bus"]], parse(Int, idx) - 200000 + 1, branch["rate_a"]) for (idx, branch) in ne_branch]
    dc_branch_indices = [(bus_index[dc_to_ac_map[branchDC["fbusdc"]]], bus_index[dc_to_ac_map[branchDC["tbusdc"]]], parse(Int, idx) - 500000 + 1 + length(ne_branch), branchDC["rateA"]) for (idx, branchDC) in ne_branchDC]
    for i in 1:size(PTDF_matrix, 1)
        for (f_idx, t_idx, j, rating) in ac_branch_indices
            Powerflow_matrix[i, j] = abs(PTDF_matrix[i, t_idx] - PTDF_matrix[i, f_idx]) * rating
        end
        for (f_idx, t_idx, j, rating) in dc_branch_indices
            Powerflow_matrix[i, j] = abs(PTDF_matrix[i, t_idx] - PTDF_matrix[i, f_idx]) * rating
        end
    end

    using Distances
    X = Powerflow_matrix;

    # Pas PCA toe om het aantal dimensies te reduceren
    using MultivariateStats
    pca = fit(PCA, Powerflow_matrix; maxoutdim=300);
    X_reduced = MultivariateStats.transform(pca, Powerflow_matrix);

    # Voer MiniBatchKMeans clustering uit
    @time result = kmeans(X_reduced, 10000; maxiter=10)

    assignment = result.assignments;

        # Maak een mapping van cluster naar een voorbeeldindex
    cluster_to_index = Dict{Int, Int}();

    for (idx, cl) in enumerate(assignment)
        if !haskey(cluster_to_index, cl)
            cluster_to_index[cl] = idx  # Eerste keer dat dit cluster voorkomt
        end
    end
    clusters = DefaultDict{Int, Vector{Int}}(Vector{Int})
    for (idx, cluster_id) in enumerate(assignment)
        push!(clusters[cluster_id], idx)
    end

    cluster = clusters[648]
    
    plot_filename = joinpath("results", join(["grid_cluster",use_case,".pdf"]))
    plot_branches(zone_grid, cluster,plot_filename)

        # Verzamel de geselecteerde kolommen
    selected_indices = collect(values(cluster_to_index))
    selected_indices_sorted = sort(selected_indices)  # Optioneel: voor consistente volgorde

    # Haal de kolommen uit de originele matrix
    Powerflow_reduced = Powerflow_matrix[:, selected_indices_sorted]

    #for i in 1:size(PTDF_matrix, 1) # i = elke bestaande AC_branch 
        #AC_candidates first
    #    for (idx, branch) in ne_branch
    #        j = parse(Int, idx) - 200000 + 1
    #        f_bus = branch["f_bus"]
    #        t_bus = branch["t_bus"]
   # 
   #         f_bus_idx = bus_index[f_bus]
   #         t_bus_idx = bus_index[t_bus]
   #         candidate_rating = branch["rate_a"]
   # 
   #         Powerflow_matrix[i, j] = abs(PTDF_matrix[i, t_bus_idx] - PTDF_matrix[i, f_bus_idx])*candidate_rating
   #     end
    
        #DC_candidates second
   #     for (idx, branchDC) in ne_branchDC
   #         j = parse(Int, idx) - 500000 + 1 + length(ne_branch)
   #         f_busAC = dc_to_ac_map[branchDC["fbusdc"]]
   #         t_busAC = dc_to_ac_map[branchDC["tbusdc"]]
   # 
   #         f_bus_idx = bus_index[f_busAC]
   #         t_bus_idx = bus_index[t_busAC]
   #         candidate_rating = branchDC["rateA"]
    
    
     #       Powerflow_matrix[i, j] = abs(PTDF_matrix[i, t_bus_idx] - PTDF_matrix[i, f_bus_idx])*candidate_rating
    #    end
    #end
    #println("Start computing Lambda matrix")
    Lambda_matrix = get_dual_branch(AC_branches, nodal_result,number_of_hours,2000)
    #Lambda_matrix = get_dual_branch_full(ne_branch,ne_branchDC, nodal_result,number_of_hours)
    println("Start computing Impact matrix")
    #Impact_matrix = Powerflow_matrix .* reshape(Lambda_matrix, size(PTDF_matrix,1), 1, number_of_hours)
    #Impact_matrix = Array{Float32}(undef, size(Powerflow_matrix, 1), size(Powerflow_matrix, 2), number_of_hours)
    #for h in 1:number_of_hours
    #    Impact_matrix[:, :, h] .= Powerflow_matrix .* Lambda_matrix[:, h]
    #end    
    @time Impact_matrix = map(h -> Powerflow_reduced .* Lambda_matrix[:, h], 1:number_of_hours)

    return Impact_matrix   
end



using StatsBase

function winsorize_matrix!(matrix, lower_pct, upper_pct)
    # Flatten de matrix naar een vector
    flat_data = vec(matrix)
    # Bepaal de grenswaarden
    lower = quantile(flat_data, lower_pct)
    upper = quantile(flat_data, upper_pct)
    # Pas de grenzen toe op de matrix
    matrix .= clamp.(matrix, lower, upper)
end

threshold = 150
num_above_threshold = count(x -> x > threshold, Lambda_matrix)
total_elements = length(Lambda_matrix)
upper_pct = 1.0 - (num_above_threshold / total_elements)

winsorize_matrix!(Lambda_matrix, 0, upper_pct)




function pre_processor()

    #1: Create all possible candidates (AC & DC)
    ne_branch, ne_branchDC, AC_new_corridor_idx, DC_new_corridor_idx = candidate_lines(nodal_input,OFF_dc_buses)

    #2: Include cost data for every candidate (AC & DC)
    ne_branch, ne_branchDC = update_cost_data(ne_branch,ne_branchDC,nodal_input)

    #3: Create the PowerFlow matrix & Impact matrix for all candidate_lines
    Impact_matrix = PTDF_analysis_full(nodal_input,nodal_result,number_of_hours,ne_branch,ne_branchDC)

    #4: Filter candidates based on their impact
    amount_cand = length(ne_branch)+length(ne_branchDC)
    
    Impact2 = zeros(Float64, length(selected_indices), 2)

    for i in 1:length(selected_indices)
        som = 0.0
        for h in 1:length(Impact_matrix)
            som += sum(Impact_matrix[h][:, i])
        end
        idx = selected_indices[i]
        if idx <= length(ne_branch)
            AC_index = idx + 200000 - 1
            Impact2[i, 1] = AC_index
            Impact2[i, 2] = som
        else
            DC_index = idx + 500000 - length(ne_branch) - 1
            Impact2[i, 1] = DC_index
            Impact2[i, 2] = som
        end
    end
    

    for i in 1:length(selected_indices)
        som = 0.0
        for h in 1:length(Impact_matrix)
            som += sum(Impact_matrix[h][:, i])
        end
        lambda_f = []
        lambda_t = []
        idx = selected_indices[i]
        if idx <= length(ne_branch)
            AC_index = idx + 200000 - 1
            if idx < AC_new_corridor_idx
                Impact2[i, 1] = AC_index
                Impact2[i, 2] = som
            else
                f_bus = ne_branch["$AC_index"]["f_bus"]
                t_bus = ne_branch["$AC_index"]["t_bus"]
                for i in 1:number_of_hours
                    h = i + start_hour - 1
                    push!(lambda_f,nodal_result["$h"]["solution"]["bus"]["$f_bus"]["lam_kcl_r"])
                    push!(lambda_t,nodal_result["$h"]["solution"]["bus"]["$t_bus"]["lam_kcl_r"])
                end
                som += sum(ne_branch["$AC_index"]["rate_a"] * abs.(lambda_f - lambda_t))
                Impact2[i, 1] = AC_index
                Impact2[i, 2] = som
            end
            
        else
            DC_index = idx + 500000 - length(ne_branch) - 1
            if DC_index < DC_new_corridor_idx
                Impact2[i, 1] = DC_index
                Impact2[i, 2] = som
            else
                f_busdc = ne_branchDC["$DC_index"]["fbusdc"]
                t_busdc = ne_branchDC["$DC_index"]["tbusdc"]
                f_busac = dc_to_ac_map[f_busdc]
                t_busac = dc_to_ac_map[t_busdc]
                for i in 1:number_of_hours
                    h = i + start_hour - 1
                    push!(lambda_f,nodal_result["$h"]["solution"]["bus"]["$f_busac"]["lam_kcl_r"])
                    push!(lambda_t,nodal_result["$h"]["solution"]["bus"]["$t_busac"]["lam_kcl_r"])
                end
                som += sum(ne_branchDC["$DC_index"]["rateA"] * abs.(lambda_f - lambda_t))
                Impact2[i, 1] = DC_index
                Impact2[i, 2] = som
            end
        end       
    end

    filename = "Impact_North.xlsx"
    headers = ["Index", "Impact Sum"]

        # Open een nieuw Excel-bestand en schrijf de vector naar de eerste kolom
        XLSX.openxlsx(filename, mode="w") do xf
            sheet = xf[1]
            sheet[1, 1] = headers[1]
            sheet[1, 2] = headers[2]
            for i in 1:size(Impact2, 1)
                sheet[i+1, 1] = Impact2[i, 1]
                sheet[i+1, 2] = Impact2[i, 2]
            end
        end
 

    AC_indices = []
    DC_indices = []
    for idx in selected_indices_sorted
        if idx <= length(ne_branch)
            AC_index = idx + 200000 -1
            push!(AC_indices, AC_index)
        end
        if idx > length(ne_branch)
            DC_index = idx + 500000 - length(ne_branch) - 1
            push!(DC_indices,DC_index)
        end
    end    

    indices = vcat(AC_indices,DC_indices)
    ###########################  
    
    
    Impact = Vector()
    for i in 1:amount_cand
        push!(Impact,sum(Impact_matrix[:,i,:]))
    end

    Impact = zeros(Float64, length(selected_indices))  # amount_cand

    for i in 1:length(selected_indices)
        som = 0
        
        for h in 1:length(Impact_matrix)
            som += sum(Impact_matrix[h][:,i])
        end
        Impact[i] = som
    end
    filename = "Impact_BE_NL.xlsx"

        # Open een nieuw Excel-bestand en schrijf de vector naar de eerste kolom
        XLSX.openxlsx(filename, mode="w") do xf
            sheet = xf[1]  # Gebruik het eerste werkblad
            sheet["A1"] = "Impact"  # Zet een kolomtitel
            for i in 1:length(Impact)
                sheet["A$(i+1)"] = Impact[i]  # Schrijf elk element onder elkaar
            end
        end


    Impact = zeros(Float64, amount_cand)  # amount_cand
    dc_to_ac_map = Dict(conv["busdc_i"] => conv["busac_i"] for (_, conv) in nodal_input["convdc"])
    for i in 1:amount_cand
        som = 0
        for h in 1:length(Impact_matrix)
            som += sum(Impact_matrix[h][:,i][1:200])
        end
        lambda_f = Float64[]
        lambda_t = Float64[]
        if i <= length(ne_branch)
            idx = i + 200000 - 1
            if idx < AC_new_corridor_idx
                Impact[i] = som
            else
                f_bus = ne_branch["$idx"]["f_bus"]
                t_bus = ne_branch["$idx"]["t_bus"]
                for i in 1:number_of_hours
                    h = i + start_hour - 1
                    push!(lambda_f,nodal_result["$h"]["solution"]["bus"]["$f_bus"]["lam_kcl_r"])
                    push!(lambda_t,nodal_result["$h"]["solution"]["bus"]["$t_bus"]["lam_kcl_r"])
                end
                som += sum(ne_branch["$idx"]["rate_a"] * abs.(lambda_f - lambda_t))
                Impact[i] = som
            end
        else
            idx = i + 500000 - 1 - length(ne_branch)
            if idx < DC_new_corridor_idx
                Impact[i] = som
            else
                f_busdc = ne_branchDC["$idx"]["fbusdc"]
                t_busdc = ne_branchDC["$idx"]["tbusdc"]
                f_busac = dc_to_ac_map[f_busdc]
                t_busac = dc_to_ac_map[t_busdc]
                for i in 1:number_of_hours
                    h = i + start_hour - 1
                    push!(lambda_f,nodal_result["$h"]["solution"]["bus"]["$f_busac"]["lam_kcl_r"])
                    push!(lambda_t,nodal_result["$h"]["solution"]["bus"]["$t_busac"]["lam_kcl_r"])
                end
                som += sum(ne_branchDC["$idx"]["rateA"] * abs.(lambda_f - lambda_t))
                Impact[i] = som
            end
        end
        
    end
    filename = "Impact_North.xlsx"

        # Open een nieuw Excel-bestand en schrijf de vector naar de eerste kolom
        XLSX.openxlsx(filename, mode="w") do xf
            sheet = xf[1]  # Gebruik het eerste werkblad
            sheet["A1"] = "Impact"  # Zet een kolomtitel
            for i in 1:length(Impact)
                sheet["A$(i+1)"] = Impact[i]  # Schrijf elk element onder elkaar
            end
        end
    

    #########################

    Cost = []
    for i in 1:amount_cand
        if i<=length(ne_branch)
            idx = i + 200000 - 1
            push!(Cost,ne_branch["$idx"]["construction_cost"])
        else
            idx = i + 500000 - 1 - length(ne_branch)
            push!(Cost,ne_branchDC["$idx"]["cost"])
        end
    end
        
    
    filename = "construction_cost.xlsx"

        # Open een nieuw Excel-bestand en schrijf de vector naar de eerste kolom
        XLSX.openxlsx(filename, mode="w") do xf
            sheet = xf[1]  # Gebruik het eerste werkblad
            sheet["A1"] = "Cost"  # Zet een kolomtitel
            for i in 1:length(Cost)
                sheet["A$(i+1)"] = Cost[i]  # Schrijf elk element onder elkaar
            end
        end


    Impact_sorted = Impact2[sortperm(Impact2[:, 2], rev = true), :]
    n_top = ceil(Int, 0.05 * size(Impact_sorted, 1))  # aantal bovenste elementen
    top_indices = Impact_sorted[1:n_top, 1] 
    random_indices = rand(Impact_sorted[:,1], 100)

    final_indices = vcat(top_indices, random_indices)
    final_indices = unique(final_indices)


    corrected_indices_AC = []
    corrected_indices_DC = []
    for i in final_indices
        if i < 500000
            i = Int(i)
            push!(corrected_indices_AC,i)
        else
            i = Int(i)
            push!(corrected_indices_DC,i)
        end
    end

    indices = collect(1:length(Impact))
    sorted_indices = sortperm(Impact, rev=true)
    top_n = ceil(Int, 0.01 * length(Impact))
    top_indices = sorted_indices[1:top_n]
    corrected_indices_AC = []
    corrected_indices_DC = []
    for i in top_indices
        if i<=length(ne_branch)
            idx = i + 200000 - 1
            push!(corrected_indices_AC,idx)
        else
            idx = i + 500000 - 1 - length(ne_branch)
            push!(corrected_indices_DC,idx)
        end
    end


    #4: Update zone_grid for TNEP problem
    zone_grid = deepcopy(nodal_input)
    zone_grid["ne_branch"] = Dict{String,Any}()
    zone_grid["branchdc_ne"] = Dict{String,Any}()

    for i in corrected_indices_AC#keys(ne_branch)#keys(ne_branch)
        zone_grid["ne_branch"]["$i"] = ne_branch["$i"]
    end
    for i in corrected_indices_DC#keys(ne_branchDC)#
        zone_grid["branchdc_ne"]["$i"] = ne_branchDC["$i"]
    end

    
end