using Distances
using DataStructures
using MultivariateStats
using StatsBase
using LinearAlgebra


function winsorize_matrix!(matrix, lower_pct, upper_pct)
    # Flatten de matrix naar een vector
    flat_data = vec(matrix)
    # Bepaal de grenswaarden
    lower = quantile(flat_data, lower_pct)
    upper = quantile(flat_data, upper_pct)
    # Pas de grenzen toe op de matrix
    matrix .= clamp.(matrix, lower, upper)
end

function Potential_investment_benefit(idx,number_of_hours,start_hour)
    lambda_f = []
    lambda_t = []
    ang_f = []
    ang_t = []

    if idx < 500000
              
        f_bus = ne_branch["$idx"]["f_bus"]
        t_bus = ne_branch["$idx"]["t_bus"]
        cap = ne_branch["$idx"]["rate_a"]
        br_x = ne_branch["$idx"]["br_x"]
        GD = _EUGO.latlon2distance(nodal_input,Int(f_bus),Int(t_bus))

        for i in 1:number_of_hours
            h = i + start_hour - 1
            push!(lambda_f,-nodal_result["$h"]["solution"]["bus"]["$f_bus"]["lam_kcl_r"]) #€/MWh
            push!(lambda_t,-nodal_result["$h"]["solution"]["bus"]["$t_bus"]["lam_kcl_r"])
            push!(ang_f,nodal_result["$h"]["solution"]["bus"]["$f_bus"]["va"] * pi/180) #rad
            push!(ang_t,nodal_result["$h"]["solution"]["bus"]["$t_bus"]["va"] * pi/180)
        end

        #lambda_diff = abs.(clamp.(lambda_t,-150,150) - clamp.(lambda_f,-150,150))
        lambda_diff = abs.(lambda_t - lambda_f)
        theta_diff = abs.(ang_f - ang_t)
        PB = []
        for i in 1:number_of_hours
            PB_i = factor[i] * lambda_diff[i] * theta_diff[i]/ (br_x) #h * €/MWh * rad /pu
            push!(PB,PB_i)
        end

        return sum(PB)
    else
        f_busdc = ne_branchDC["$idx"]["fbusdc"]
        t_busdc = ne_branchDC["$idx"]["tbusdc"]
        cap = ne_branchDC["$idx"]["rateA"]


        for i in 1:number_of_hours
            h = i + start_hour - 1
            push!(lambda_f,nodal_result["$h"]["solution"]["busdc"]["$f_busdc"]["lam_kcl_r"])
            push!(lambda_t,nodal_result["$h"]["solution"]["busdc"]["$t_busdc"]["lam_kcl_r"])
        end

        lambda_diff = abs.(lambda_t - lambda_f)
        PB = []
        for i in 1:number_of_hours
            PB_i = factor[i] * lambda_diff[i] * cap
            push!(PB,PB_i)
        end
        return sum(PB)
        
    end   
    
    
end

function delta_lambda(idx,number_of_hours,start_hour)
    lambda_f = []
    lambda_t = []

    if idx < 500000
              
        f_bus = ne_branch["$idx"]["f_bus"]
        t_bus = ne_branch["$idx"]["t_bus"]
       

        for i in 1:number_of_hours
            h = i + start_hour - 1
            push!(lambda_f,nodal_result["$h"]["solution"]["bus"]["$f_bus"]["lam_kcl_r"])
            push!(lambda_t,nodal_result["$h"]["solution"]["bus"]["$t_bus"]["lam_kcl_r"])
        end
    else
        f_busdc = ne_branchDC["$idx"]["fbusdc"]
        t_busdc = ne_branchDC["$idx"]["tbusdc"]
        f_busac = dc_to_ac_map[f_busdc]
        t_busac = dc_to_ac_map[t_busdc]
       
        for i in 1:number_of_hours
            h = i + start_hour - 1
            push!(lambda_f,nodal_result["$h"]["solution"]["busdc"]["$f_busdc"]["lam_kcl_r"])
            push!(lambda_t,nodal_result["$h"]["solution"]["busdc"]["$t_busdc"]["lam_kcl_r"])
        end
    end

    lambda_diff = abs.(lambda_t - lambda_f)
   
    
    delta_lambda = []
    for i in 1:number_of_hours
        delta_lambda_i = (factor[i]/8760) * factor[i] * lambda_diff[i]
        push!(delta_lambda,delta_lambda_i)
    end
    
    return sum(delta_lambda)
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

    # Pas PCA toe om het aantal dimensies te reduceren
    @time pca_AC = fit(PCA, Powerflow_matrix[:,1:length(ne_branch)]; maxoutdim=300);
    @time X_reduced_AC = MultivariateStats.transform(pca_AC, Powerflow_matrix[:,1:length(ne_branch)]);
    @time pca_DC = fit(PCA, Powerflow_matrix[:,length(ne_branch)+1:end]; maxoutdim=300);
    @time X_reduced_DC = MultivariateStats.transform(pca_DC, Powerflow_matrix[:,length(ne_branch)+1:end]);

    # Voer MiniBatchKMeans clustering uit
    @time result_AC = kmeans(X_reduced_AC, 1500; maxiter=75)
    @time result_DC = kmeans(X_reduced_DC, 200; maxiter=75)

    assignment_AC = result_AC.assignments;
    assignment_DC = result_DC.assignments;

        # Maak een mapping van cluster naar een voorbeeldindex
    cluster_to_index_AC = Dict{Int, Int}();
    cluster_to_index_DC = Dict{Int, Int}();

    for (idx, cl) in enumerate(assignment_AC)
        if !haskey(cluster_to_index_AC, cl)
            cluster_to_index_AC[cl] = idx  # Eerste keer dat dit cluster voorkomt
        end
    end
    for (idx, cl) in enumerate(assignment_DC)
        if !haskey(cluster_to_index_DC, cl)
            cluster_to_index_DC[cl] = idx  # Eerste keer dat dit cluster voorkomt
        end
    end

    clusters = DefaultDict{Int, Vector{Int}}(Vector{Int})
    for (idx, cluster_id) in enumerate(assignment_AC)
        push!(clusters[cluster_id], idx)
    end
    for (idx, cluster_id) in enumerate(assignment_DC)
        push!(clusters[cluster_id + 1500], idx + length(ne_branch))  # Offset voor DC indices
    end

    
    #cluster = clusters[319]
    #plot_filename = joinpath("results", join(["grid_cluster",use_case,".pdf"]))
    #plot_branches(zone_grid, cluster,plot_filename)

        # Verzamel de geselecteerde kolommen
    selected_indices_AC = collect(values(cluster_to_index_AC))
    selected_indices_DC = collect(values(cluster_to_index_DC)) .+ length(ne_branch)  # Offset voor DC indices
    selected_indices = vcat(selected_indices_AC, selected_indices_DC)
    selected_indices_sorted = sort(selected_indices)

    # Haal de kolommen uit de originele matrix
    Powerflow_reduced = Powerflow_matrix[:, selected_indices_sorted]

    println("Start computing Lambda matrix")
    Lambda_matrix = get_dual_branch(AC_branches, nodal_result,number_of_hours,1)
    
    threshold = 600
    num_above_threshold = count(x -> x > threshold, Lambda_matrix)
    total_elements = length(Lambda_matrix)
    upper_pct = 1.0 - (num_above_threshold / total_elements)
    winsorize_matrix!(Lambda_matrix, 0, upper_pct)


    println("Start computing Impact matrix")
    @time Impact_matrix = map(h -> Powerflow_reduced .* Lambda_matrix[:, h], 1:number_of_hours)
    #Impact_matrix = Powerflow_matrix .* reshape(Lambda_matrix, size(PTDF_matrix,1), 1, number_of_hours)
    #Impact_matrix = Array{Float32}(undef, size(Powerflow_matrix, 1), size(Powerflow_matrix, 2), number_of_hours)
    #for h in 1:number_of_hours
    #    Impact_matrix[:, :, h] .= Powerflow_matrix .* Lambda_matrix[:, h]
    #end    
    

    return Impact_matrix   
end

function pre_processor()

    #1: Create all possible candidates (AC & DC)
    ne_branch, ne_branchDC, AC_new_corridor_idx, DC_new_corridor_idx = candidate_lines(nodal_input,new_DC_buses)

    #2: Include cost data for every candidate (AC & DC)
    ne_branch, ne_branchDC = update_cost_data(ne_branch,ne_branchDC,nodal_input)

    #3: Create the PowerFlow matrix & Impact matrix for all candidate_lines
    Impact_matrix = PTDF_analysis_full(nodal_input,nodal_result,number_of_hours,ne_branch,ne_branchDC)

    #4: Filter candidates based on their impact
    amount_cand = length(ne_branch)+length(ne_branchDC)

    ImpactAC = zeros(Float64, length(selected_indices_AC), 2)
    ImpactDC = zeros(Float64, length(selected_indices_DC), 2)
    PB_AC = zeros(Float64, length(selected_indices_AC),2)
    PB_DC = zeros(Float64, length(selected_indices_DC),2)
    PIB_AC = zeros(Float64, length(selected_indices_AC),2)
    PIB_DC = zeros(Float64, length(selected_indices_DC),2)
    Lambda_AC = zeros(Float64, length(selected_indices_AC),2)
    Lambda_DC = zeros(Float64, length(selected_indices_DC),2)
    Cost_AC = zeros(Float64, length(selected_indices_AC),2)
    Cost_DC = zeros(Float64, length(selected_indices_DC),2)
    Total_Cost_AC = zeros(Float64, length(selected_indices_AC),2)
    Total_Cost_DC = zeros(Float64, length(selected_indices_DC),2)

    for i in 1:length(selected_indices_AC)
        som = 0.0
        for h in 1:length(Impact_matrix)
            som += sum(Impact_matrix[h][:, i]) * factor[h]   #IN CASE OF REPRESENTATIVE TIMESTEPS ADD FACTOR[h]
        end
        idx = sort(selected_indices_AC)[i]
        lambda_f = []
        lambda_t = []
        AC_index = idx + 200000 - 1

        if AC_index < AC_new_corridor_idx
            ImpactAC[i, 1] = AC_index
            ImpactAC[i, 2] = som
        
        else
            f_bus = ne_branch["$AC_index"]["f_bus"]
            t_bus = ne_branch["$AC_index"]["t_bus"]
            for i in 1:number_of_hours
                h = i + start_hour - 1
                push!(lambda_f,nodal_result["$h"]["solution"]["bus"]["$f_bus"]["lam_kcl_r"])
                push!(lambda_t,nodal_result["$h"]["solution"]["bus"]["$t_bus"]["lam_kcl_r"])
            end
            som += sum(ne_branch["$AC_index"]["rate_a"] * (abs.(lambda_f - lambda_t) .* factor))
            ImpactAC[i, 1] = AC_index
            ImpactAC[i, 2] = som 
        end
       
    end
            
    for i in 1:length(selected_indices_DC)
        som = 0.0
        for h in 1:length(Impact_matrix)
            som += sum(Impact_matrix[h][:, i]) * factor[h]   #IN CASE OF REPRESENTATIVE TIMESTEPS ADD FACTOR[h]
        end
        lambda_f = []
        lambda_t = []
        idx = sort(selected_indices_DC)[i]
        DC_index = idx + 500000 - length(ne_branch) - 1
        if DC_index < DC_new_corridor_idx
            ImpactDC[i, 1] = DC_index
            ImpactDC[i, 2] = som
        
        else
            f_busdc = ne_branchDC["$DC_index"]["fbusdc"]
            t_busdc = ne_branchDC["$DC_index"]["tbusdc"]
            f_busac = dc_to_ac_map[f_busdc]
            t_busac = dc_to_ac_map[t_busdc]
            for i in 1:number_of_hours
                h = i + start_hour - 1
                push!(lambda_f,nodal_result["$h"]["solution"]["busdc"]["$f_busdc"]["lam_kcl_r"])
                push!(lambda_t,nodal_result["$h"]["solution"]["busdc"]["$t_busdc"]["lam_kcl_r"])
            end
            som += sum(ne_branchDC["$DC_index"]["rateA"] * (abs.(lambda_f - lambda_t) .* factor))
            ImpactDC[i, 1] = DC_index
            ImpactDC[i, 2] = som
        end
        
        
    end

    for i in 1:length(selected_indices_AC)
        idx = sort(selected_indices_AC)[i]
        AC_index = idx + 200000 - 1
        PB_AC[i, 1] = AC_index
        #println( Potential_investment_benefit(AC_index,number_of_hours,start_hour))
        PB_AC[i, 2] = Potential_investment_benefit(AC_index,number_of_hours,start_hour)
        Lambda_AC[i,1] = AC_index
        Lambda_AC[i,2] =  delta_lambda(AC_index,number_of_hours,start_hour)
        Cost_AC[i,1] = AC_index
        Cost_AC[i,2] =  ne_branch["$AC_index"]["construction_cost"]
        Total_Cost_AC[i,1] = AC_index
        Total_Cost_AC[i,2] = ne_branch["$AC_index"]["construction_cost"]*8760
        PIB_AC[i,1] = AC_index
        PIB_AC[i,2] = PB_AC[i,2] / Total_Cost_AC[i,2]
    end

    for i in 1:length(selected_indices_DC)
        idx = sort(selected_indices_DC)[i]
        DC_index = idx + 500000 - length(ne_branch) - 1
        PB_DC[i,1] = DC_index
        PB_DC[i,2] =  Potential_investment_benefit(DC_index,number_of_hours,start_hour)
        Lambda_DC[i,1] = DC_index
        Lambda_DC[i,2] =  delta_lambda(DC_index,number_of_hours,start_hour)
        Cost_DC[i,1] = DC_index
        Cost_DC[i,2] =   ne_branchDC["$DC_index"]["cost"]
        Total_Cost_DC[i,1] = DC_index
        Total_Cost_DC[i,2] =  ne_branchDC["$DC_index"]["cost"]*8760
        PIB_DC[i,1] = DC_index
        PIB_DC[i,2] = PB_DC[i,2] / Total_Cost_DC[i,2] 
    end

    

    
    #Impact2 = zeros(Float64, length(selected_indices), 2)

    #for i in 1:length(selected_indices)
    #    som = 0.0
    #    for h in 1:length(Impact_matrix)
    #        som += sum(Impact_matrix[h][:, i])
    #    end
    #    idx = selected_indices[i]
    #    if idx <= length(ne_branch)
    #        AC_index = idx + 200000 - 1
    #        Impact2[i, 1] = AC_index
    #        Impact2[i, 2] = som
    #    else
    #        DC_index = idx + 500000 - length(ne_branch) - 1
    #        Impact2[i, 1] = DC_index
    #        Impact2[i, 2] = som
    #    end
    #end
    
    #=
    for i in 1:length(selected_indices)
        som = 0.0
        for h in 1:length(Impact_matrix)
            som += (sum(Impact_matrix[h][:, i]) * factor[h])
        end
        lambda_f = []
        lambda_t = []
        idx = selected_indices[i]
        if idx <= length(ne_branch)
            AC_index = idx + 200000 - 1
            if AC_index < AC_new_corridor_idx
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
                som += sum(ne_branch["$AC_index"]["rate_a"] * (abs.(lambda_f - lambda_t) .* factor))
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
                som += sum(ne_branchDC["$DC_index"]["rateA"] * (abs.(lambda_f - lambda_t) .* factor))
                Impact2[i, 1] = DC_index
                Impact2[i, 2] = som 
            end
        end       
    end
    =#

    #########################################
    ### Create Excel file voor resultaten ###
    #########################################

    filename = "Impact_North_AC.xlsx"
    headers = ["Index", "Impact Sum","PB","Lamba_diff", "Cost", "PIB"]

        # Open een nieuw Excel-bestand en schrijf de vector naar de eerste kolom
        XLSX.openxlsx(filename, mode="w") do xf
            sheet = xf[1]
            sheet[1, 1] = headers[1]
            sheet[1, 2] = headers[2]
            sheet[1, 3] = headers[3]
            sheet[1, 4] = headers[4]
            sheet[1, 5] = headers[5]
            sheet[1, 6] = headers[6]
            for i in 1:size(ImpactAC, 1)
                sheet[i+1, 1] = ImpactAC[i, 1]
                sheet[i+1, 2] = ImpactAC[i, 2]
                sheet[i+1, 3] = PB_AC[i,2]
                sheet[i+1, 4] = Lambda_AC[i,2]
                sheet[i+1, 5] = Cost_AC[i,2]
                sheet[i+1, 6] = PIB_AC[i,2]
            end
        end
    
    filename = "Impact_North_DC.xlsx"
    headers = ["Index", "Impact Sum","PB","Lamba_diff", "Cost", "PIB"]

        # Open een nieuw Excel-bestand en schrijf de vector naar de eerste kolom
        XLSX.openxlsx(filename, mode="w") do xf
            sheet = xf[1]
            sheet[1, 1] = headers[1]
            sheet[1, 2] = headers[2]
            sheet[1, 3] = headers[3]
            sheet[1, 4] = headers[4]
            sheet[1, 5] = headers[5]
            sheet[1, 6] = headers[6]
            for i in 1:size(ImpactDC, 1)
                sheet[i+1, 1] = ImpactDC[i, 1]
                sheet[i+1, 2] = ImpactDC[i, 2]
                sheet[i+1, 3] = PB_DC[i,2]
                sheet[i+1, 4] = Lambda_DC[i,2]
                sheet[i+1, 5] = Cost_DC[i,2]
                sheet[i+1, 6] = PIB_DC[i,2]
            end
        end
 
        #=
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

    Impact = zeros(Float64, length(selected_indices))  # amount_cand

    for i in 1:length(selected_indices)
    for i in 1:length(selected_indices)
        som = 0
        
        
        for h in 1:length(Impact_matrix)
            som += sum(Impact_matrix[h][:,i])
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
    for i in sort(selected_indices_AC)
        if i<=length(ne_branch)
            idx = i + 200000 - 1
            push!(Cost,ne_branch["$idx"]["construction_cost"])
        else
            idx = i + 500000 - 1 - length(ne_branch)
            push!(Cost,ne_branchDC["$idx"]["cost"])
        end
    end
        
    
    filename = "Lambda_diff.xlsx"

        # Open een nieuw Excel-bestand en schrijf de vector naar de eerste kolom
        XLSX.openxlsx(filename, mode="w") do xf
            sheet = xf[1]  # Gebruik het eerste werkblad
            sheet["A1"] = "Lambda_diff"  # Zet een kolomtitel
            for i in 1:length(Lambda_diff)
                sheet["A$(i+1)"] = Lambda_diff[i]  # Schrijf elk element onder elkaar
            end
        end


    Impact_sorted = Impact2[sortperm(Impact2[:, 2], rev = true), :]
    n_top = ceil(Int, 0.015 * size(Impact_sorted, 1))  # aantal bovenste elementen
    top_indices = Impact_sorted[1:n_top, 1] 
    random_indices = rand(Impact_sorted[:,1], 50)

    final_indices = vcat(top_indices, random_indices)
    final_indices = unique(final_indices)
    =#


    ImpactAC_sorted = ImpactAC[sortperm(ImpactAC[:, 2], rev = true), :]
    ImpactDC_sorted = ImpactDC[sortperm(ImpactDC[:, 2], rev = true), :]
    PIB_AC_sorted = PIB_AC[sortperm(PIB_AC[:, 2], rev = true), :]
    PIB_DC_sorted = PIB_DC[sortperm(PIB_DC[:, 2], rev = true), :]
    n_topAC = ceil(Int, 0.025 * size(ImpactAC_sorted, 1))  # aantal bovenste elementen
    n_topDC = ceil(Int, 0.15 * size(PIB_DC_sorted, 1))
    top_indicesAC = ImpactAC_sorted[1:n_topAC, 1] 
    top_indicesDC = PIB_DC_sorted[1:n_topDC, 1] 
    
    random_indices_AC = rand(ImpactAC_sorted[:,1], 5)
    random_indices_DC = rand(ImpactDC_sorted[:,1], 5)

    final_indices = vcat(top_indicesAC,top_indicesDC,random_indices_AC,random_indices_DC)  # VOEG EVENTUEEL RANDOM INDICES TOE OM TE CHECKEN
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

    
        #4: Update zone_grid for TNEP problem
    zone_grid = deepcopy(nodal_input)
    zone_grid["ne_branch"] = Dict{String,Any}()
    zone_grid["branchdc_ne"] = Dict{String,Any}()

    for i in corrected_indices_AC##keys(ne_branch)#
        zone_grid["ne_branch"]["$i"] = ne_branch["$i"]
    end
    for i in corrected_indices_DC##keys(ne_branchDC)#
        zone_grid["branchdc_ne"]["$i"] = ne_branchDC["$i"]
    end

    
end