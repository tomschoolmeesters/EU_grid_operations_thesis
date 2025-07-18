function min_max_scale(X) # Scales the input array X column-wise to a range between 0 and 1 using min-max normalization.
    min_vals = minimum(X, dims=1)
    max_vals = maximum(X, dims=1)
    return (X .- min_vals) ./ (max_vals .- min_vals)
end

"""
    find_extreme_scenarios(demand, renewables, offshore, other_res, demand_w, demand_nw,
                           demand_quantile, renewables_quantile_high, renewables_quantile_low,
                           offshore_quantile_high, other_res_quantile_low,
                           demand_w_quantile_low, demand_nw_quantile_high)

Identifies indices of time steps representing various extreme scenarios in demand and renewable generation
based on quantile thresholds.

    # Arguments
    - `demand`: Vector, Total system demand time series.
    - `renewables`: Vector, Total renewable generation time series.
    - `offshore`: Vector, Offshore wind generation time series.
    - `other_res`: Vector, Other renewable generation time series (e.g., solar, onshore wind).
    - `demand_w`: Vector, Demand in the "windy" region (UK, DK1, NL).
    - `demand_nw`: Vector, Demand in the "non-windy" region (BE, DE).
    - `demand_quantile`: Quantile threshold for high demand.
    - `renewables_quantile_high`: Quantile threshold for high renewable generation.
    - `renewables_quantile_low`: Quantile threshold for low renewable generation.
    - `offshore_quantile_high`: Quantile threshold for high offshore wind generation.
    - `other_res_quantile_low`: Quantile threshold for low other renewable generation.
    - `demand_w_quantile_low`: Quantile threshold for low demand in "windy" region.
    - `demand_nw_quantile_high`: Quantile threshold for high demand in "non-windy" region.

    # Returns
    - `high_demand_high_renewables_indices`: Vector, Indices with high demand and high renewables.
    - `high_demand_low_renewables_indices`: Vector, Indices with high demand and low renewables.
    - `high_offshore_low_res_indices`: Vector, Indices with high offshore wind and low other RES.
    - `low_demandw_high_demandnw_indices`: Vector, Indices with low "windy" demand and high "non-windy" demand.
"""

function find_extreme_scenarios(demand, renewables, offshore, other_res, demand_w, demand_nw, demand_quantile,renewables_quantile_high, renewables_quantile_low, offshore_quantile_high, other_res_quantile_low, demand_w_quantile_low, demand_nw_quantile_high)
    # Find indices above/below specified quantiles for each dataset
    high_demand_indices = findall(x -> x >= Statistics.quantile(demand, demand_quantile), demand)
    high_renewables_indices = findall(x -> x >= Statistics.quantile(renewables, renewables_quantile_high), renewables)
    low_renewables_indices = findall(x -> x <= Statistics.quantile(renewables, renewables_quantile_low), renewables)
    high_offshore_indices = findall(x -> x >= Statistics.quantile(offshore, offshore_quantile_high), offshore)
    low_other_indices = findall(x -> x <= Statistics.quantile(other_res, other_res_quantile_low), other_res)
    low_demand_w_indices = findall(x -> x <= Statistics.quantile(demand_w, demand_w_quantile_low), demand_w)
    high_demand_nw_indices = findall(x -> x >= Statistics.quantile(demand_nw, demand_nw_quantile_high), demand_nw)

    # Intersect indices to find combined extreme scenarios
    high_demand_high_renewables_indices = intersect(high_demand_indices, high_renewables_indices)
    high_demand_low_renewables_indices = intersect(high_demand_indices, low_renewables_indices)
    high_offshore_low_res_indices = intersect(high_offshore_indices,low_other_indices)
    low_demandw_high_demandnw_indices = intersect(low_demand_w_indices, high_demand_nw_indices)

    return high_demand_high_renewables_indices, high_demand_low_renewables_indices, high_offshore_low_res_indices, low_demandw_high_demandnw_indices
end


"""
    get_reduced_timeseries(timeseries_data, option; quantiles..., num_clusters=11)

Reduce detailed hourly time series data into representative clusters using k-means clustering and importance subsampling.

    # Arguments
    - `timeseries_data`: Dictionary containing full hourly time series data for demand, renewables (solar PV, wind offshore/onshore), and cross-border flows across zones.
    - `option`: Integer (1 to 4) selecting the combination of normalized features to use for clustering.
        - 1: All features (demand, renewables, offshore, other_res, demand_w, demand_nw).
        - 2: Demand and renewables only.
        - 3: Renewables only.
        - 4: Demand only.
    - `demand_quantile`: Quantile threshold to classify high demand hours (default 0.8).
    - `renewables_quantile_high`: Quantile threshold for high renewable generation (default 0.8).
    - `renewables_quantile_low`: Quantile threshold for low renewable generation (default 0.3).
    - `offshore_quantile_high`: Quantile threshold for offshore wind (default 0.75).
    - `other_res_quantile_low`: Quantile threshold for other renewables (default 0.5).
    - `demand_w_quantile_low`: Quantile threshold for Western demand (default 0.35).
    - `demand_nw_quantile_high`: Quantile threshold for Northwestern demand (default 0.65).
    - `num_clusters`: Number of clusters for k-means clustering excluding the 4 extreme scenarios (default 11).

    # Description
    This function performs the following steps:
    1. Aggregates and sums hourly time series for demand, renewables (offshore/onshore wind, solar PV), and cross-border flows across zones.
    2. Normalizes each aggregated time series using min-max scaling.
    3. Selects feature subsets for clustering based on the `option` parameter.
    4. Identifies extreme scenario hours by applying quantile thresholds to normalized demand and renewable generation values.
    5. Clusters extreme scenarios separately (each extreme cluster with one centroid).
    6. Applies k-means clustering to the remaining time series data to reduce dimensionality.
    7. Combines extreme scenario centroids and main cluster centroids into a final set of representative time series.
    8. Denormalizes cluster centroids back to original scale and structures them into a reduced `timeseries_data` dictionary.

    # Output
    Returns a new dictionary similar to `timeseries_data`, where time series are replaced by cluster centroids representing reduced and aggregated scenarios.

"""

function get_reduced_timeseries(timeseries_data, option; demand_quantile=0.8, renewables_quantile_high=0.8, renewables_quantile_low=0.3, offshore_quantile_high = 0.75, other_res_quantile_low = 0.5, demand_w_quantile_low = 0.35, demand_nw_quantile_high = 0.65,num_clusters=11)

    # Extract solar PV generation for various zones from the input data
    solar_pv_BE = timeseries_data["solar_pv"]["BE"]
    solar_pv_NL = timeseries_data["solar_pv"]["NL"]
    solar_pv_UK = timeseries_data["solar_pv"]["UK"]
    solar_pv_DE = timeseries_data["solar_pv"]["DE"]
    solar_pv_DK1 = timeseries_data["solar_pv"]["DK1"]

    # Extract offshore wind generation for various zones
    offshore_BE = timeseries_data["wind_offshore"]["BE"]
    offshore_NL = timeseries_data["wind_offshore"]["NL"]
    offshore_UK = timeseries_data["wind_offshore"]["UK"]
    offshore_DE = timeseries_data["wind_offshore"]["DE"]
    offshore_DK1 = timeseries_data["wind_offshore"]["DK1"]

    # Extract onshore wind generation for various zones
    onshore_BE = timeseries_data["wind_onshore"]["BE"]
    onshore_NL = timeseries_data["wind_onshore"]["NL"]
    onshore_UK = timeseries_data["wind_onshore"]["UK"]
    onshore_DE = timeseries_data["wind_onshore"]["DE"]
    onshore_DK1 = timeseries_data["wind_onshore"]["DK1"]

    # Extract electricity demand data for various zones
    demand_BE = timeseries_data["demand"]["BE"]
    demand_NL = timeseries_data["demand"]["NL"]
    demand_UK = timeseries_data["demand"]["UK"]
    demand_DE = timeseries_data["demand"]["DE"]
    demand_DK1 = timeseries_data["demand"]["DK1"]
   
    # Extract cross-border flows for different interconnectors 
    XB_flow_FR = timeseries_data["xb_flows"]["FR"]["flow"]'
    XB_flow_CH = timeseries_data["xb_flows"]["CH"]["flow"]'
    XB_flow_AT = timeseries_data["xb_flows"]["AT"]["flow"]'
    XB_flow_NO2 = timeseries_data["xb_flows"]["NO2"]["flow"]'
    XB_flow_IE = timeseries_data["xb_flows"]["IE"]["flow"]'
    XB_flow_DK2 = timeseries_data["xb_flows"]["DK2"]["flow"]'
    XB_flow_CZ = timeseries_data["xb_flows"]["CZ"]["flow"]'
    XB_flow_SE4 = timeseries_data["xb_flows"]["SE4"]["flow"]'
    XB_flow_NI = timeseries_data["xb_flows"]["NI"]["flow"]'

    # Initialize aggregated arrays with zeros for 8760 hours (typical full year hourly data)
    offshore = zeros(8760)
    onshore = zeros(8760)
    solar_pv = zeros(8760)
    demand = zeros(8760)
    XB_flow = zeros(8760)

    # Sum renewables and demand data over all zones to get aggregated time series
    for zone in keys(timeseries_data["demand"])
        offshore .+= timeseries_data["wind_offshore"]["$zone"]
        onshore .+= timeseries_data["wind_onshore"]["$zone"]
        solar_pv .+= timeseries_data["solar_pv"]["$zone"]
        demand .+= timeseries_data["demand"]["$zone"]
    end
    # Sum cross-border flows over all interconnectors
    for zone in keys(timeseries_data["xb_flows"])
        XB_flow .+= timeseries_data["xb_flows"]["$zone"]["flow"][1,:]
    end

    # Calculate total renewables and other subsets for later use
    renewables = offshore .+ onshore .+ solar_pv
    other_res = onshore .+ solar_pv
    demand_w = demand_UK + demand_NL + demand_DK1   # Demand in "windy" zones
    demand_nw = demand_BE + demand_DE               # Demand in "non-windy" zones

    # Normalize all relevant timeseries to [0,1] range for clustering/scenario detection
    demand_N = min_max_scale(demand)
    renewables_N = min_max_scale(renewables)
    other_res_N = min_max_scale(other_res)
    demand_w_N = min_max_scale(demand_w)
    demand_nw_N = min_max_scale(demand_nw)
    offshore_N = min_max_scale(offshore)
    onshore_N = min_max_scale(onshore)
    solar_pv_N = min_max_scale(solar_pv)

    # Normalize offshore wind for individual zones
    offshore_BE_N = min_max_scale(offshore_BE)
    offshore_UK_N = min_max_scale(offshore_UK)
    offshore_DK1_N = min_max_scale(offshore_DK1)
    offshore_NL_N = min_max_scale(offshore_NL)
    offshore_DE_N = min_max_scale(offshore_DE)

    # Normalize onshore wind for individual zones
    onshore_BE_N = min_max_scale(onshore_BE)
    onshore_UK_N = min_max_scale(onshore_UK)
    onshore_DK1_N = min_max_scale(onshore_DK1)
    onshore_NL_N = min_max_scale(onshore_NL)
    onshore_DE_N = min_max_scale(onshore_DE)

    # Normalize solar pv for individual zones (not implemented)

    # Normalize demand for individual zones
    demand_BE_N = min_max_scale(demand_BE)
    demand_UK_N = min_max_scale(demand_UK)
    demand_DK1_N = min_max_scale(demand_DK1)
    demand_NL_N = min_max_scale(demand_NL)
    demand_DE_N = min_max_scale(demand_DE)

    # Normalize cross-border flows for each interconnector
    XB_flow_FR_N = min_max_scale(XB_flow_FR)
    XB_flow_CH_N = min_max_scale(XB_flow_CH)
    XB_flow_AT_N = min_max_scale(XB_flow_AT)
    XB_flow_NO2_N = min_max_scale(XB_flow_NO2)
    XB_flow_IE_N = min_max_scale(XB_flow_IE)
    XB_flow_DK2_N = min_max_scale(XB_flow_DK2)
    XB_flow_CZ_N = min_max_scale(XB_flow_CZ)
    XB_flow_SE4_N = min_max_scale(XB_flow_SE4)
    XB_flow_NI_N = min_max_scale(XB_flow_NI)

    # Normalize aggregated cross-border flow
    XB_flow_N = min_max_scale(XB_flow)


    # Select data matrix columns based on 'option' parameter (different feature combinations)
    if option == 1
        # Option 1: includes normalized demands, onshore, offshore for specific zones + aggregated solar pv + FR XB flow
        data = hcat(demand_BE_N,demand_UK_N,demand_DK1_N,demand_NL_N,demand_DE_N,
                    onshore_BE_N,onshore_UK_N,onshore_DK1_N,onshore_NL_N,onshore_DE_N,
                    offshore_BE_N,offshore_UK_N,offshore_DK1_N,offshore_NL_N,offshore_DE_N,
                    solar_pv_N,
                    XB_flow_FR_N)'

    elseif option == 2
        # Option 2: aggregated demand and renewables (except for offshore wind) + FR XB flow
        data = hcat(demand_N,onshore_N,solar_pv_N,
                    offshore_BE_N,offshore_UK_N,offshore_DK1_N,offshore_NL_N,offshore_DE_N,
                    XB_flow_FR_N)'

    elseif option == 3
        # Option 3: aggregate demand, solar, offshore, onshore, and cross-border flows
        data = hcat(demand_N, solar_pv_N, offshore_N, onshore_N, XB_flow_N)'
    
    elseif option == 4
        # Option 4: demand, total renewables, and FR flow only
        data = hcat(demand_N, renewables_N, XB_flow_FR_N)'
    end

    # Identify extreme scenarios (high/low demand and renewable combinations) based on quantiles
    high_demand_high_renewables_indices, high_demand_low_renewables_indices, high_offshore_low_res_indices, low_demandw_high_demandnw_indices = find_extreme_scenarios(demand_N, renewables_N, offshore_N, other_res_N , demand_w_N, demand_nw_N,demand_quantile, renewables_quantile_high, renewables_quantile_low, offshore_quantile_high, other_res_quantile_low,demand_w_quantile_low, demand_nw_quantile_high)

    # Combine indices of identified extremes into one unique set
    extreme_indices = unique(vcat(high_demand_high_renewables_indices, high_demand_low_renewables_indices, high_offshore_low_res_indices, low_demandw_high_demandnw_indices))

    # Extract data corresponding to each extreme scenario group from the full dataset
    extreme_data_high = data[:,high_demand_high_renewables_indices]         # High demand & high renewables
    extreme_data_low = data[:,high_demand_low_renewables_indices]           # High demand & low renewables
    extreme_data_off = data[:,high_offshore_low_res_indices]                # High offshore wind & low other renewables
    extreme_data_demand = data[:,low_demandw_high_demandnw_indices]         # Low demand (w) & high demand (nw)

    # For each extreme group, if data exists, reduce it to a single representative point using k-means clustering with 1 cluster
    if !isempty(extreme_data_high)
        result_high = kmeans(extreme_data_high, 1)
        centroid_high = result_high.centers
    else
        centroid_high = zeros(size(data, 1), 1) # Empty case: create zero vector with correct size
    end

    if !isempty(extreme_data_low)
        result_low = kmeans(extreme_data_low, 1)
        centroid_low = result_low.centers
    else
        centroid_low = zeros(size(data, 1), 1) # Empty case: create zero vector with correct size
    end

    if !isempty(extreme_data_off)
        result_off = kmeans(extreme_data_off, 1)
        centroid_off = result_off.centers
    else
        centroid_off = zeros(size(data, 1), 1) # Empty case: create zero vector with correct size
    end

    if !isempty(extreme_data_demand)
        result_demand = kmeans(extreme_data_demand, 1)
        centroid_demand = result_demand.centers
    else
        centroid_demand = zeros(size(data, 1), 1) # Empty case: create zero vector with correct size
    end

    # Remove extreme scenario indices from the dataset to focus clustering on "normal" data
    data_filtered = data[:,setdiff(1:end, extreme_indices)]

    # Adjust number of clusters if filtered data has fewer points than requested clusters
    if size(data_filtered, 2) < num_clusters
        num_clusters = size(data_filtered, 2)
        println("Warning: Number of clusters reduced to $(num_clusters) because there are not enough datapoints after removing extreme scenarios")
    end

    # Perform k-means clustering on filtered data to find representative clusters
    result_main = kmeans(data_filtered, num_clusters)
    centroids_main = result_main.centers

    ################
    ### Plotting ###
    ################
   
    # Combine all centroids (extremes + main clusters) horizontally into one matrix
    centroids = hcat(centroid_high, centroid_low, centroid_off,centroid_demand,centroids_main)

    # Create a factor array storing the number of points in each cluster/extreme group
    factor = [
        length(high_demand_high_renewables_indices), 
        length(high_demand_low_renewables_indices), 
        length(high_offshore_low_res_indices),
        length(low_demandw_high_demandnw_indices),
        result_main.counts... # Counts of main clusters unpacked
    ]

    # Print centroids and cluster sizes for verification
    println("Centroids of each cluster:")
    println(centroids)
    println("Number of data points per cluster:")
    println(factor)

    #####################################
    ### Build timeseries_data_reduced ###
    #####################################
     
    # Deep copy original timeseries data to keep original intact
    timeseries_data_reduced = deepcopy(timeseries_data)

    # Calculate minimum values for each variable/zone to use for rescaling
    mins = [minimum(demand_BE), minimum(demand_UK), minimum(demand_DK1), minimum(demand_NL), minimum(demand_DE),
            minimum(solar_pv_BE), minimum(solar_pv_UK), minimum(solar_pv_DK1), minimum(solar_pv_NL), minimum(solar_pv_DE),
            minimum(offshore_BE), minimum(offshore_UK),  minimum(offshore_DK1), minimum(offshore_NL), minimum(offshore_DE), 
            minimum(onshore_BE), minimum(onshore_UK), minimum(onshore_DK1), minimum(onshore_NL), minimum(onshore_DE),
            minimum(XB_flow_FR), minimum(XB_flow_CH),minimum(XB_flow_AT),minimum(XB_flow_NO2),minimum(XB_flow_IE),minimum(XB_flow_DK2),minimum(XB_flow_CZ),minimum(XB_flow_SE4),minimum(XB_flow_NI)]

    # Calculate maximum values for each variable/zone for rescaling       
    maxs = [maximum(demand_BE), maximum(demand_UK),  maximum(demand_DK1), maximum(demand_NL), maximum(demand_DE),
            maximum(solar_pv_BE), maximum(solar_pv_UK),  maximum(solar_pv_DK1), maximum(solar_pv_NL), maximum(solar_pv_DE),
            maximum(offshore_BE), maximum(offshore_UK),maximum(offshore_DK1), maximum(offshore_NL), maximum(offshore_DE),
            maximum(onshore_BE), maximum(onshore_UK), maximum(onshore_DK1), maximum(onshore_NL), maximum(onshore_DE),
            maximum(XB_flow_FR), maximum(XB_flow_CH),maximum(XB_flow_AT),maximum(XB_flow_NO2),maximum(XB_flow_IE),maximum(XB_flow_DK2),maximum(XB_flow_CZ),maximum(XB_flow_SE4),maximum(XB_flow_NI)]

    # Depending on the option chosen, rescale centroids back to original data range for each zone and variable
    if option == 1

        timeseries_data_reduced["demand"]["BE"] = centroids[1,:] .* (maxs[1] .- mins[1]) .+ mins[1]
        timeseries_data_reduced["demand"]["UK"] = centroids[2,:] .* (maxs[2] .- mins[2]) .+ mins[2]
        timeseries_data_reduced["demand"]["DK1"] = centroids[3,:] .* (maxs[3] .- mins[3]) .+ mins[3]
        timeseries_data_reduced["demand"]["NL"] = centroids[4,:] .* (maxs[4] .- mins[4]) .+ mins[4]
        timeseries_data_reduced["demand"]["DE"] = centroids[5,:] .* (maxs[5] .- mins[5]) .+ mins[5]

        timeseries_data_reduced["wind_onshore"]["BE"] = centroids[6,:] .* (maxs[16] .- mins[16]) .+ mins[16]
        timeseries_data_reduced["wind_onshore"]["UK"] = centroids[7,:] .* (maxs[17] .- mins[17]) .+ mins[17]
        timeseries_data_reduced["wind_onshore"]["DK1"] = centroids[8,:] .* (maxs[18] .- mins[18]) .+ mins[18]
        timeseries_data_reduced["wind_onshore"]["NL"] = centroids[9,:] .* (maxs[19] .- mins[19]) .+ mins[19]
        timeseries_data_reduced["wind_onshore"]["DE"] = centroids[10,:] .* (maxs[20] .- mins[20]) .+ mins[20]

        timeseries_data_reduced["solar_pv"]["BE"] = centroids[16,:] .* (maxs[6] .- mins[6]) .+ mins[6]
        timeseries_data_reduced["solar_pv"]["UK"] = centroids[16,:] .* (maxs[7] .- mins[7]) .+ mins[7]
        timeseries_data_reduced["solar_pv"]["DK1"] = centroids[16,:] .* (maxs[8] .- mins[8]) .+ mins[8]
        timeseries_data_reduced["solar_pv"]["NL"] = centroids[16,:] .* (maxs[9] .- mins[9]) .+ mins[9]
        timeseries_data_reduced["solar_pv"]["DE"] = centroids[16,:] .* (maxs[10] .- mins[10]) .+ mins[10]

        timeseries_data_reduced["wind_offshore"]["BE"] = centroids[11,:] .* (maxs[11] .- mins[11]) .+ mins[11]
        timeseries_data_reduced["wind_offshore"]["UK"] = centroids[12,:] .* (maxs[12] .- mins[12]) .+ mins[12]
        timeseries_data_reduced["wind_offshore"]["DK1"] = centroids[13,:] .* (maxs[13] .- mins[13]) .+ mins[13]
        timeseries_data_reduced["wind_offshore"]["NL"] = centroids[14,:] .* (maxs[14] .- mins[14]) .+ mins[14]
        timeseries_data_reduced["wind_offshore"]["DE"] = centroids[15,:] .* (maxs[15] .- mins[15]) .+ mins[15]

        # Set all cross-border flows to zero (not necessary if you include all XB flows in option 1 (like FR) but here not implemented)
        for zone in keys(timeseries_data_reduced["xb_flows"])
            timeseries_data_reduced["xb_flows"]["$zone"]["flow"] = zeros(1,amount_of_clusters)
        end

        timeseries_data_reduced["xb_flows"]["FR"]["flow"] = (centroids[17,:] .* (maxs[21] .- mins[21]) .+ mins[21])'

    elseif option == 2 
        println("Option is not yet fully defined")
        timeseries_data_reduced = nothing

    elseif option == 3
        timeseries_data_reduced["demand"]["BE"] = centroids[1,:] .* (maxs[1] .- mins[1]) .+ mins[1]
        timeseries_data_reduced["demand"]["UK"] = centroids[1,:] .* (maxs[2] .- mins[2]) .+ mins[2]
        timeseries_data_reduced["demand"]["DK1"] = centroids[1,:] .* (maxs[3] .- mins[3]) .+ mins[3]
        timeseries_data_reduced["demand"]["NL"] = centroids[1,:] .* (maxs[4] .- mins[4]) .+ mins[4]
        timeseries_data_reduced["demand"]["DE"] = centroids[1,:] .* (maxs[5] .- mins[5]) .+ mins[5]

        timeseries_data_reduced["wind_onshore"]["BE"] = centroids[4,:] .* (maxs[16] .- mins[16]) .+ mins[16]
        timeseries_data_reduced["wind_onshore"]["UK"] = centroids[4,:] .* (maxs[17] .- mins[17]) .+ mins[17]
        timeseries_data_reduced["wind_onshore"]["DK1"] = centroids[4,:] .* (maxs[18] .- mins[18]) .+ mins[18]
        timeseries_data_reduced["wind_onshore"]["NL"] = centroids[4,:] .* (maxs[19] .- mins[19]) .+ mins[19]
        timeseries_data_reduced["wind_onshore"]["DE"] = centroids[4,:] .* (maxs[20] .- mins[20]) .+ mins[20]

        timeseries_data_reduced["solar_pv"]["BE"] = centroids[2,:] .* (maxs[6] .- mins[6]) .+ mins[6]
        timeseries_data_reduced["solar_pv"]["UK"] = centroids[2,:] .* (maxs[7] .- mins[7]) .+ mins[7]
        timeseries_data_reduced["solar_pv"]["DK1"] = centroids[2,:] .* (maxs[8] .- mins[8]) .+ mins[8]
        timeseries_data_reduced["solar_pv"]["NL"] = centroids[2,:] .* (maxs[9] .- mins[9]) .+ mins[9]
        timeseries_data_reduced["solar_pv"]["DE"] = centroids[2,:] .* (maxs[10] .- mins[10]) .+ mins[10]

        timeseries_data_reduced["wind_offshore"]["BE"] = centroids[3,:] .* (maxs[11] .- mins[11]) .+ mins[11]
        timeseries_data_reduced["wind_offshore"]["UK"] = centroids[3,:] .* (maxs[12] .- mins[12]) .+ mins[12]
        timeseries_data_reduced["wind_offshore"]["DK1"] = centroids[3,:] .* (maxs[13] .- mins[13]) .+ mins[13]
        timeseries_data_reduced["wind_offshore"]["NL"] = centroids[3,:] .* (maxs[14] .- mins[14]) .+ mins[14]
        timeseries_data_reduced["wind_offshore"]["DE"] = centroids[3,:] .* (maxs[15] .- mins[15]) .+ mins[15]


        timeseries_data_reduced["xb_flows"]["FR"]["flow"] = (centroids[5,:] .* (maxs[21] .- mins[21]) .+ mins[21])'
        timeseries_data_reduced["xb_flows"]["CH"]["flow"] = (centroids[5,:] .* (maxs[22] .- mins[22]) .+ mins[22])'
        timeseries_data_reduced["xb_flows"]["AT"]["flow"] = (centroids[5,:] .* (maxs[23] .- mins[23]) .+ mins[23])'
        timeseries_data_reduced["xb_flows"]["NO2"]["flow"] = (centroids[5,:] .* (maxs[24] .- mins[24]) .+ mins[24])'
        timeseries_data_reduced["xb_flows"]["IE"]["flow"] = (centroids[5,:] .* (maxs[25] .- mins[25]) .+ mins[25])'
        timeseries_data_reduced["xb_flows"]["DK2"]["flow"] = (centroids[5,:] .* (maxs[26] .- mins[26]) .+ mins[26])'
        timeseries_data_reduced["xb_flows"]["CZ"]["flow"] = (centroids[5,:] .* (maxs[27] .- mins[27]) .+ mins[27])'
        timeseries_data_reduced["xb_flows"]["SE4"]["flow"] = (centroids[5,:] .* (maxs[28] .- mins[28]) .+ mins[28])'
        timeseries_data_reduced["xb_flows"]["NI"]["flow"] = (centroids[5,:] .* (maxs[29] .- mins[29]) .+ mins[29])'
        timeseries_data_reduced["xb_flows"]["SE3"]["flow"] = zeros(1,size(centroids,2))
        timeseries_data_reduced["xb_flows"]["PL"]["flow"] = zeros(1,size(centroids,2))
        timeseries_data_reduced["xb_flows"]["NO5"]["flow"] = zeros(1,size(centroids,2))

    elseif option == 4
        timeseries_data_reduced["demand"]["BE"] = centroids[1,:] .* (maxs[1] .- mins[1]) .+ mins[1]
        timeseries_data_reduced["demand"]["UK"] = centroids[1,:] .* (maxs[2] .- mins[2]) .+ mins[2]
        timeseries_data_reduced["demand"]["DK1"] = centroids[1,:] .* (maxs[3] .- mins[3]) .+ mins[3]
        timeseries_data_reduced["demand"]["NL"] = centroids[1,:] .* (maxs[4] .- mins[4]) .+ mins[4]
        timeseries_data_reduced["demand"]["DE"] = centroids[1,:] .* (maxs[5] .- mins[5]) .+ mins[5]

        timeseries_data_reduced["wind_onshore"]["BE"] = centroids[2,:] .* (maxs[16] .- mins[16]) .+ mins[16]
        timeseries_data_reduced["wind_onshore"]["UK"] = centroids[2,:] .* (maxs[17] .- mins[17]) .+ mins[17]
        timeseries_data_reduced["wind_onshore"]["DK1"] = centroids[2,:] .* (maxs[18] .- mins[18]) .+ mins[18]
        timeseries_data_reduced["wind_onshore"]["NL"] = centroids[2,:] .* (maxs[19] .- mins[19]) .+ mins[19]
        timeseries_data_reduced["wind_onshore"]["DE"] = centroids[2,:] .* (maxs[20] .- mins[20]) .+ mins[20]

        timeseries_data_reduced["solar_pv"]["BE"] = centroids[2,:] .* (maxs[6] .- mins[6]) .+ mins[6]
        timeseries_data_reduced["solar_pv"]["UK"] = centroids[2,:] .* (maxs[7] .- mins[7]) .+ mins[7]
        timeseries_data_reduced["solar_pv"]["DK1"] = centroids[2,:] .* (maxs[8] .- mins[8]) .+ mins[8]
        timeseries_data_reduced["solar_pv"]["NL"] = centroids[2,:] .* (maxs[9] .- mins[9]) .+ mins[9]
        timeseries_data_reduced["solar_pv"]["DE"] = centroids[2,:] .* (maxs[10] .- mins[10]) .+ mins[10]

        timeseries_data_reduced["wind_offshore"]["BE"] = centroids[2,:] .* (maxs[11] .- mins[11]) .+ mins[11]
        timeseries_data_reduced["wind_offshore"]["UK"] = centroids[2,:] .* (maxs[12] .- mins[12]) .+ mins[12]
        timeseries_data_reduced["wind_offshore"]["DK1"] = centroids[2,:] .* (maxs[13] .- mins[13]) .+ mins[13]
        timeseries_data_reduced["wind_offshore"]["NL"] = centroids[2,:] .* (maxs[14] .- mins[14]) .+ mins[14]
        timeseries_data_reduced["wind_offshore"]["DE"] = centroids[2,:] .* (maxs[15] .- mins[15]) .+ mins[15]



        for zone in keys(timeseries_data_reduced["xb_flows"])
            timeseries_data_reduced["xb_flows"]["$zone"]["flow"] = zeros(1,amount_of_clusters)
        end
        timeseries_data_reduced["xb_flows"]["FR"]["flow"] = (centroids[3,:] .* (maxs[21] .- mins[21]) .+ mins[21])'
    
    end


    return timeseries_data_reduced, factor, extreme_indices
end
