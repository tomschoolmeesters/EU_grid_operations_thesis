

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


function group_OFFwindfarms_ext(relocation_dict,zone,max_groups_2030, max_groups_2040,DC_number)
    # Extract latitudes en longitudes van de bussen in de AC lijst
    latitudes_2030 = [relocation_dict["$zone"]["$g_id"]["lat"] for g_id in keys(relocation_dict["$zone"]) if relocation_dict["$zone"]["$g_id"]["year"] == 2030]
    longitudes_2030 = [relocation_dict["$zone"]["$g_id"]["lon"] for g_id in keys(relocation_dict["$zone"]) if relocation_dict["$zone"]["$g_id"]["year"] == 2030]
    #latitudes_2040 = [relocation_dict["$zone"]["$g_id"]["lat"] for g_id in keys(relocation_dict["$zone"]) if relocation_dict["$zone"]["$g_id"]["year"] == 2040]
    #longitudes_2040 = [relocation_dict["$zone"]["$g_id"]["lon"] for g_id in keys(relocation_dict["$zone"]) if relocation_dict["$zone"]["$g_id"]["year"] == 2040]

    # Maak de matrix met latitudes in de eerste rij en longitudes in de tweede rij
    bus_matrix_2030 = hcat(latitudes_2030, longitudes_2030)'
    #bus_matrix_2040 = hcat(latitudes_2040, longitudes_2040)'
    println(zone)
    R_2030 = kmeans(bus_matrix_2030, max_groups_2030; maxiter=200, display=:iter)
    println("R_2030")
    #R_2040 = kmeans(bus_matrix_2040, max_groups_2040; maxiter=200, display=:iter)
    
    a_30 = assignments(R_2030) # get the assignments of points to clusters
    c_30 = counts(R_2030) # get the cluster sizes
    M_30 = R_2030.centers # get the cluster centers
    #a_40 = assignments(R_2040) # get the assignments of points to clusters
    #c_40 = counts(R_2040) # get the cluster sizes
    #M_40 = R_2040.centers # get the cluster centers

    DC_bus_30 = Dict{String,Any}()
    #DC_bus_40 = Dict{String,Any}()
    for i in 1:max_groups_2030
        DC_bus_30["$i"] = Dict{String,Any}()
        DC_bus_30["$i"]["idx"] = DC_number
        DC_bus_30["$i"]["lat"] = M_30[1,i]
        DC_bus_30["$i"]["lon"] = M_30[2,i]
        DC_number += 1
    end
    #for i in 1:max_groups_2040
    #    DC_bus_40["$i"] = Dict{String,Any}()
    #    DC_bus_40["$i"]["idx"] = DC_number
    #    DC_bus_40["$i"]["lat"] = M_40[1,i]
    #    DC_bus_40["$i"]["lon"] = M_40[2,i]
    #    DC_number += 1
    #end

    for i in 1:length(latitudes_2030)
        lat = latitudes_2030[i]
        lon = longitudes_2030[i]
        group = a_30[i]
        for (g_id,gen) in relocation_dict["$zone"]
            if gen["lat"] == lat && gen["lon"] == lon
                gen["corresponding_DCbus"] = DC_bus_30["$group"]["idx"]
            end
        end
    end
    #=
    for i in 1:length(latitudes_2040)
        lat = latitudes_2040[i]
        lon = longitudes_2040[i]
        group = a_40[i]
        for (g_id,gen) in relocation_dict["$zone"]
            if gen["lat"] == lat && gen["lon"] == lon
                gen["corresponding_DCbus"] = DC_bus_40["$group"]["idx"]
            end
        end
    end
    =#
    return DC_number, DC_bus_30#, DC_bus_40
end
