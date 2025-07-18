using Clustering
"""
Overview of functions in group_wind_farms.jl

1. group_OFFwindfarms(relocation_dict, zone, max_groups, DC_number)
    - Clusters all offshore wind farms in a zone into a specified number of groups based on location.
    - Assigns each cluster a new DC bus with unique index and coordinates.

2. group_OFFwindfarms_ext(relocation_dict, zone, max_groups_2030, max_groups_2040, DC_number)
    - Separately clusters offshore wind farms for years 2030 and 2040 within a zone.
    - Assigns each cluster a new DC bus with unique index and coordinates.
"""

"""
    group_OFFwindfarms(relocation_dict, zone, max_groups, DC_number)

Clusters offshore wind farms within a specified zone into a limited number of groups using their geographic coordinates (latitude and longitude).  
Assigns each cluster a new DC bus with a unique index and cluster center location.

    # Arguments
    - `relocation_dict::Dict`: Nested dictionary containing offshore wind generator data keyed by zone and generator ID, including `lat` and `lon` coordinates.
    - `zone::String`: The zone identifier specifying which generators to cluster.
    - `max_groups::Int`: The maximum number of clusters (groups) to create.
    - `DC_number::Int`: Starting index for numbering new DC buses.

    # Output
    - Returns a tuple:
        - Updated `DC_number`: Incremented to account for newly created DC buses.
        - `DC_bus`: Dictionary mapping cluster IDs to DC bus information including cluster index, latitude, and longitude.

    # Dependencies
    - Uses the `Clustering` package for k-means clustering.
"""


function group_OFFwindfarms(relocation_dict,zone,max_groups,DC_number)
    # Extract latitudes and longitudes of all generators in the specified zone
    latitudes = [relocation_dict["$zone"]["$g_id"]["lat"] for g_id in keys(relocation_dict["$zone"])]
    longitudes = [relocation_dict["$zone"]["$g_id"]["lon"] for g_id in keys(relocation_dict["$zone"])]

    # Combine latitudes and longitudes into a 2 x N matrix (each column is a point)
    bus_matrix = hcat(latitudes, longitudes)'

    # Perform k-means clustering with specified max groups, limit iterations for stability
    R = kmeans(bus_matrix, max_groups; maxiter=200, display=:iter)

    # Extract cluster assignments and cluster centers
    assignments_vec = assignments(R)  # Vector indicating cluster assignment for each point
    cluster_centers = R.centers       # 2 x max_groups matrix of cluster centers

    # Initialize dictionary to hold new DC buses representing cluster centers
    DC_bus = Dict{String,Any}()

    for i in 1:max_groups
        DC_bus["$i"] = Dict{String,Any}()
        DC_bus["$i"]["idx"] = DC_number
        DC_bus["$i"]["lat"] = cluster_centers[1, i]
        DC_bus["$i"]["lon"] = cluster_centers[2, i]
        DC_number += 1
    end

    # Assign each generator in the zone to its corresponding DC bus based on cluster membership
    latlon_to_gids = Dict{Tuple{Float64,Float64}, Vector{String}}()
    for (g_id, gen) in relocation_dict["$zone"]
        key = (gen["lat"], gen["lon"])
        push!(get!(latlon_to_gids, key, String[]), g_id)
    end

    for i in 1:length(latitudes)
        lat = latitudes[i]
        lon = longitudes[i]
        group = assignments_vec[i]

        # Assign all generators at this lat-lon to the cluster's DC bus
        for g_id in latlon_to_gids[(lat, lon)]
            relocation_dict["$zone"]["$g_id"]["corresponding_DCbus"] = DC_bus["$group"]["idx"]
        end
    end

    return DC_number, DC_bus
end

"""
    group_OFFwindfarms_ext(relocation_dict, zone, max_groups_2030, max_groups_2040, DC_number)

Clusters offshore wind farms within a specified zone into separate groups for the years 2030 and 2040, based on their geographic coordinates (latitude and longitude).  
Assigns each cluster a new DC bus with a unique index and cluster center location for each year separately.

    # Arguments
    - `relocation_dict::Dict`: Nested dictionary containing offshore wind generator data keyed by zone and generator ID, including `lat` and `lon` coordinates.
    - `zone::String`: The zone identifier specifying which generators to cluster.
    - `max_groups_2030::Int`: The maximum number of clusters to create for generators planned for 2030.
    - `max_groups_2040::Int`: The maximum number of clusters to create for generators planned for 2040.
    - `DC_number::Int`: Starting index for numbering new DC buses.

    # Output
    - Returns a tuple:
        - Updated `DC_number`: Incremented to account for all newly created DC buses across both years.
        - `DC_bus_30`: Dictionary mapping 2030 cluster IDs to DC bus information including cluster index, latitude, and longitude.
        - `DC_bus_40`: Dictionary mapping 2040 cluster IDs to DC bus information including cluster index, latitude, and longitude.

    # Dependencies
    - Uses the `Clustering` package for k-means clustering.
"""

function group_OFFwindfarms_ext(relocation_dict,zone,max_groups_2030, max_groups_2040,DC_number)
    # Extract latitudes and longitudes of offshore wind farms for both 2030 and 2040
    latitudes_2030 = [relocation_dict["$zone"]["$g_id"]["lat"] for g_id in keys(relocation_dict["$zone"]) if relocation_dict["$zone"]["$g_id"]["year"] == 2030]
    longitudes_2030 = [relocation_dict["$zone"]["$g_id"]["lon"] for g_id in keys(relocation_dict["$zone"]) if relocation_dict["$zone"]["$g_id"]["year"] == 2030]
    latitudes_2040 = [relocation_dict["$zone"]["$g_id"]["lat"] for g_id in keys(relocation_dict["$zone"]) if relocation_dict["$zone"]["$g_id"]["year"] == 2040]
    longitudes_2040 = [relocation_dict["$zone"]["$g_id"]["lon"] for g_id in keys(relocation_dict["$zone"]) if relocation_dict["$zone"]["$g_id"]["year"] == 2040]

    # Create coordinate matrices for clustering (rows: lat/lon, columns: points)
    bus_matrix_2030 = hcat(latitudes_2030, longitudes_2030)'
    bus_matrix_2040 = hcat(latitudes_2040, longitudes_2040)'

    # Perform k-means clustering
    R_2030 = kmeans(bus_matrix_2030, max_groups_2030; maxiter=200, display=:iter)
    R_2040 = kmeans(bus_matrix_2040, max_groups_2040; maxiter=200, display=:iter)
    
    # Extract clustering results for 2030
    a_30 = assignments(R_2030)      # get the assignments of points to clusters
    M_30 = R_2030.centers           # get the cluster centers
    # Extract clustering results for 2040
    a_40 = assignments(R_2040)      # get the assignments of points to clusters
    M_40 = R_2040.centers           # get the cluster centers

    # Initialize dictionaries to store DC bus info for each cluster/year
    DC_bus_30 = Dict{String,Any}()
    DC_bus_40 = Dict{String,Any}()
    
    # Assign DC bus indices and coordinates for 2030 clusters
    for i in 1:max_groups_2030
        DC_bus_30["$i"] = Dict{String,Any}()
        DC_bus_30["$i"]["idx"] = DC_number
        DC_bus_30["$i"]["lat"] = M_30[1, i]
        DC_bus_30["$i"]["lon"] = M_30[2, i]
        DC_number += 1
    end

    # Assign DC bus indices and coordinates for 2040 clusters
    for i in 1:max_groups_2040
        DC_bus_40["$i"] = Dict{String,Any}()
        DC_bus_40["$i"]["idx"] = DC_number
        DC_bus_40["$i"]["lat"] = M_40[1, i]
        DC_bus_40["$i"]["lon"] = M_40[2, i]
        DC_number += 1
    end


    # Link each 2030 wind farm to its corresponding DC bus based on cluster
    for i in 1:length(latitudes_2030)
        lat = latitudes_2030[i]
        lon = longitudes_2030[i]
        group = a_30[i]
        for (g_id, gen) in relocation_dict["$zone"]
            if gen["lat"] == lat && gen["lon"] == lon
                gen["corresponding_DCbus"] = DC_bus_30["$group"]["idx"]
            end
        end
    end

    # Link each 2040 wind farm to its corresponding DC bus based on cluster
    for i in 1:length(latitudes_2040)
        lat = latitudes_2040[i]
        lon = longitudes_2040[i]
        group = a_40[i]
        for (g_id, gen) in relocation_dict["$zone"]
            if gen["lat"] == lat && gen["lon"] == lon
                gen["corresponding_DCbus"] = DC_bus_40["$group"]["idx"]
            end
        end
    end

    # Return updated DC bus counter and dictionaries with DC bus info for both years
    return DC_number, DC_bus_30, DC_bus_40
end
