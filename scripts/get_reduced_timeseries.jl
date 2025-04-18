function min_max_scale(X)
    min_vals = minimum(X, dims=1)
    max_vals = maximum(X, dims=1)
    return (X .- min_vals) ./ (max_vals .- min_vals)
end

function get_reduced_timeseries(timeseries_data)

    solar_pv_BE = timeseries_data["solar_pv"]["BE"]
    solar_pv_NL = timeseries_data["solar_pv"]["NL"]
    solar_pv_UK = timeseries_data["solar_pv"]["UK"]
    solar_pv_DE = timeseries_data["solar_pv"]["DE"]
    solar_pv_DK1 = timeseries_data["solar_pv"]["DK1"]
    solar_pv_DK2 = timeseries_data["solar_pv"]["DK2"]

    offshore_BE = timeseries_data["wind_offshore"]["BE"]
    offshore_NL = timeseries_data["wind_offshore"]["NL"]
    offshore_UK = timeseries_data["wind_offshore"]["UK"]
    offshore_DE = timeseries_data["wind_offshore"]["DE"]
    offshore_DK1 = timeseries_data["wind_offshore"]["DK1"]
    offshore_DK2 = timeseries_data["wind_offshore"]["DK2"]

    onshore_BE = timeseries_data["wind_onshore"]["BE"]
    onshore_NL = timeseries_data["wind_onshore"]["NL"]
    onshore_UK = timeseries_data["wind_onshore"]["UK"]
    onshore_DE = timeseries_data["wind_onshore"]["DE"]
    onshore_DK1 = timeseries_data["wind_onshore"]["DK1"]
    onshore_DK2 = timeseries_data["wind_onshore"]["DK2"]

    demand_BE = timeseries_data["demand"]["BE"]
    demand_NL = timeseries_data["demand"]["NL"]
    demand_UK = timeseries_data["demand"]["UK"]
    demand_DE = timeseries_data["demand"]["DE"]
    demand_DK1 = timeseries_data["demand"]["DK1"]
    demand_DK2 = timeseries_data["demand"]["DK2"]

    XB_flow_FR = timeseries_data["xb_flows"]["FR"]["flow"]'

        offshore = zeros(8760)
    onshore = zeros(8760)
    solar_pv = zeros(8760)
    demand = zeros(8760)
    for zone in keys(timeseries_data["demand"])
        offshore .+= timeseries_data["wind_offshore"]["$zone"]
        onshore .+= timeseries_data["wind_onshore"]["$zone"]
        solar_pv .+= timeseries_data["solar_pv"]["$zone"]
        demand .+= timeseries_data["demand"]["$zone"]
    end
    renewables = offshore .+ onshore .+ solar_pv

    demand_N = min_max_scale(demand)
    renewables_N = min_max_scale(renewables)
    offshore_N = min_max_scale(offshore)
    onshore_N = min_max_scale(onshore)
    solar_pv_N = min_max_scale(solar_pv)

    offshore_BE_N = min_max_scale(offshore_BE)
    offshore_UK_N = min_max_scale(offshore_UK)
    offshore_DK2_N = min_max_scale(offshore_DK2)
    offshore_DK1_N = min_max_scale(offshore_DK1)
    offshore_NL_N = min_max_scale(offshore_NL)
    offshore_DE_N = min_max_scale(offshore_DE)

    onshore_BE_N = min_max_scale(onshore_BE)
    onshore_UK_N = min_max_scale(onshore_UK)
    onshore_DK2_N = min_max_scale(onshore_DK2)
    onshore_DK1_N = min_max_scale(onshore_DK1)
    onshore_NL_N = min_max_scale(onshore_NL)
    onshore_DE_N = min_max_scale(onshore_DE)

    demand_BE_N = min_max_scale(demand_BE)
    demand_UK_N = min_max_scale(demand_UK)
    demand_DK2_N = min_max_scale(demand_DK2)
    demand_DK1_N = min_max_scale(demand_DK1)
    demand_NL_N = min_max_scale(demand_NL)
    demand_DE_N = min_max_scale(demand_DE)

    XB_flow_FR_N = min_max_scale(XB_flow_FR)


    if option == 1
        data = hcat(demand_BE_N,demand_UK_N,demand_DK2_N,demand_DK1_N,demand_NL_N,demand_DE_N,
                    onshore_BE_N,onshore_UK_N,onshore_DK2_N,onshore_DK1_N,onshore_NL_N,onshore_DE_N,
                    offshore_BE_N,offshore_UK_N,offshore_DK2_N,offshore_DK1_N,offshore_NL_N,offshore_DE_N,
                    solar_pv_N,
                    XB_flow_FR_N)'
    elseif option == 2
        data = hcat(demand_N,onshore_N,solar_pv_N,
                    offshore_BE_N,offshore_UK_N,offshore_DK2_N,offshore_DK1_N,offshore_NL_N,offshore_DE_N,
                    XB_flow_FR_N)'

    elseif option == 3
        data = hcat(demand_N, solar_pv_N, offshore_N, onshore_N)'
    
    elseif option == 4
        data = hcat(demand_N, renewables_N)'
    end

    # Run k-means clustering voor de gecombineerde gegevens (vraag + de drie hernieuwbare bronnen)
    result = kmeans(data, 24)


    ################
    ### Plotting ###
    ################

    #=
    Plots.scatter(demand_N, renewables_N,
            xlabel = "Demand",
            ylabel = "Renewable Generation",
            title = "Demand vs Renewable Generation",
            legend = false,
            markercolor = :blue
        )

        Plots.scatter(timeseries_data["demand"]["UK"], timeseries_data["demand"]["NL"],
            xlabel = "Demand",
            ylabel = "Renewable Generation",
            title = "Demand vs Renewable Generation",
            legend = false,
            markercolor = :blue
        )
    =#
   

    centroids = result.centers
    
    println("Centroids of each cluster:")
    println(centroids)

    # Aantal datapunten per cluster
    num_points_per_cluster = zeros(Int, 24)

    # Tel het aantal datapunten per cluster
    for cluster_id in 1:24
        num_points_per_cluster[cluster_id] = sum(result.assignments .== cluster_id)
    end

    println("Aantal datapunten per cluster:")
    println(num_points_per_cluster)
    factor = num_points_per_cluster

    #####################################
    ### Build timeseries_data_reduced ###
    #####################################
        
    timeseries_data_reduced = deepcopy(timeseries_data)

    mins = [minimum(demand_BE), minimum(demand_UK), minimum(demand_DK2), minimum(demand_DK1), minimum(demand_NL), minimum(demand_DE),
            minimum(solar_pv_BE), minimum(solar_pv_UK), minimum(solar_pv_DK2), minimum(solar_pv_DK1), minimum(solar_pv_NL), minimum(solar_pv_DE),
            minimum(offshore_BE), minimum(offshore_UK), minimum(offshore_DK2), minimum(offshore_DK1), minimum(offshore_NL), minimum(offshore_DE), 
            minimum(onshore_BE), minimum(onshore_UK), minimum(onshore_DK2), minimum(onshore_DK1), minimum(onshore_NL), minimum(onshore_DE),
            minimum(XB_flow_FR)]

    maxs = [maximum(demand_BE), maximum(demand_UK), maximum(demand_DK2), maximum(demand_DK1), maximum(demand_NL), maximum(demand_DE),
            maximum(solar_pv_BE), maximum(solar_pv_UK), maximum(solar_pv_DK2), maximum(solar_pv_DK1), maximum(solar_pv_NL), maximum(solar_pv_DE),
            maximum(offshore_BE), maximum(offshore_UK), maximum(offshore_DK2), maximum(offshore_DK1), maximum(offshore_NL), maximum(offshore_DE),
            maximum(onshore_BE), maximum(onshore_UK), maximum(onshore_DK2), maximum(onshore_DK1), maximum(onshore_NL), maximum(onshore_DE),
            maximum(XB_flow_FR)]

    if option == 1

        timeseries_data_reduced["demand"]["BE"] = centroids[1,:] .* (maxs[1] .- mins[1]) .+ mins[1]
        timeseries_data_reduced["demand"]["UK"] = centroids[1,:] .* (maxs[2] .- mins[2]) .+ mins[2]
        timeseries_data_reduced["demand"]["DK2"] = centroids[1,:] .* (maxs[3] .- mins[3]) .+ mins[3]
        timeseries_data_reduced["demand"]["DK1"] = centroids[1,:] .* (maxs[4] .- mins[4]) .+ mins[4]
        timeseries_data_reduced["demand"]["NL"] = centroids[1,:] .* (maxs[5] .- mins[5]) .+ mins[5]
        timeseries_data_reduced["demand"]["DE"] = centroids[1,:] .* (maxs[6] .- mins[6]) .+ mins[6]

        timeseries_data_reduced["wind_onshore"]["BE"] = centroids[2,:] .* (maxs[7] .- mins[7]) .+ mins[7]
        timeseries_data_reduced["wind_onshore"]["UK"] = centroids[2,:] .* (maxs[8] .- mins[8]) .+ mins[8]
        timeseries_data_reduced["wind_onshore"]["DK2"] = centroids[2,:] .* (maxs[9] .- mins[9]) .+ mins[9]
        timeseries_data_reduced["wind_onshore"]["DK1"] = centroids[2,:] .* (maxs[10] .- mins[10]) .+ mins[10]
        timeseries_data_reduced["wind_onshore"]["NL"] = centroids[2,:] .* (maxs[11] .- mins[11]) .+ mins[11]
        timeseries_data_reduced["wind_onshore"]["DE"] = centroids[2,:] .* (maxs[12] .- mins[12]) .+ mins[12]

        timeseries_data_reduced["solar_pv"]["BE"] = centroids[3,:] .* (maxs[13] .- mins[13]) .+ mins[13]
        timeseries_data_reduced["solar_pv"]["UK"] = centroids[3,:] .* (maxs[14] .- mins[14]) .+ mins[14]
        timeseries_data_reduced["solar_pv"]["DK2"] = centroids[3,:] .* (maxs[15] .- mins[15]) .+ mins[15]
        timeseries_data_reduced["solar_pv"]["DK1"] = centroids[3,:] .* (maxs[16] .- mins[16]) .+ mins[16]
        timeseries_data_reduced["solar_pv"]["NL"] = centroids[3,:] .* (maxs[17] .- mins[17]) .+ mins[17]
        timeseries_data_reduced["solar_pv"]["DE"] = centroids[3,:] .* (maxs[18] .- mins[18]) .+ mins[18]

        timeseries_data_reduced["wind_offshore"]["BE"] = centroids[4,:] .* (maxs[19] .- mins[19]) .+ mins[19]
        timeseries_data_reduced["wind_offshore"]["UK"] = centroids[5,:] .* (maxs[20] .- mins[20]) .+ mins[20]
        timeseries_data_reduced["wind_offshore"]["DK2"] = centroids[6,:] .* (maxs[21] .- mins[21]) .+ mins[21]
        timeseries_data_reduced["wind_offshore"]["DK1"] = centroids[7,:] .* (maxs[22] .- mins[22]) .+ mins[22]
        timeseries_data_reduced["wind_offshore"]["NL"] = centroids[8,:] .* (maxs[23] .- mins[23]) .+ mins[23]
        timeseries_data_reduced["wind_offshore"]["DE"] = centroids[9,:] .* (maxs[24] .- mins[24]) .+ mins[24]

        for zone in keys(timeseries_data_reduced["xb_flows"])
            timeseries_data_reduced["xb_flows"]["$zone"]["flow"] = zeros(1,24)
        end
        timeseries_data_reduced["xb_flows"]["FR"]["flow"] = (centroids[10,:] .* (maxs[25] .- mins[25]) .+ mins[25])'
    
    else
        println("Option is not yet fully defined")
        timeseries_data_reduced = nothing
    end


    return timeseries_data_reduced, factor
end
