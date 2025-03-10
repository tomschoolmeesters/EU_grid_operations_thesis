

using Clustering

function group_OFFwindfarms(relocation_dict,zone,max_groups,DC_number)
    # Extract latitudes en longitudes van de bussen in de AC lijst
    latitudes = [relocation_dict["$zone"]["$g_id"]["lat"] for g_id in keys(relocation_dict["$zone"])]
    longitudes = [relocation_dict["$zone"]["$g_id"]["lon"] for g_id in keys(relocation_dict["$zone"])]

    # Maak de matrix met latitudes in de eerste rij en longitudes in de tweede rij
    bus_matrix = hcat(latitudes, longitudes)'

    R = kmeans(bus_matrix, max_groups; maxiter=200, display=:iter)
    
    a = assignments(R) # get the assignments of points to clusters
    c = counts(R) # get the cluster sizes
    M = R.centers # get the cluster centers
    

    DC_bus = Dict{String,Any}()
    for i in 1:max_groups
        DC_bus["$i"] = Dict{String,Any}()
        DC_bus["$i"]["idx"] = DC_number
        DC_bus["$i"]["lat"] = M[1,i]
        DC_bus["$i"]["lon"] = M[2,i]
        DC_number += 1
    end

    for i in 1:length(latitudes)
        lat = latitudes[i]
        lon = longitudes[i]
        group = a[i]
        for (g_id,gen) in relocation_dict["$zone"]
            if gen["lat"] == lat && gen["lon"] == lon
                gen["corresponding_DCbus"] = DC_bus["$group"]["idx"]
            end
        end
    end

    return DC_number, DC_bus
end
