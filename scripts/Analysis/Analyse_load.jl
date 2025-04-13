function Analyse_load(hour_range)
    total_load = 0

    for (l_id, l) in nodal_input["load"]
        pmax = l["pmax"]
        zone = l["zone"]
        for h in hour_range
            LF = timeseries_data["demand"][zone][h]
            if haskey(nodal_result["$h"]["solution"]["load"], l_id)
                total_load += pmax*LF*100 #MWh
            end
        end
    end
    formatted_load = string(round(total_load; digits=2))  # Geen exponentiële notatie
    println("Total load: $formatted_load MWh")
end


function load_shedding(hour_range)
    
    for i in hour_range
        for (l,load_info) in nodal_result["$i"]["solution"]["load"]
    
            if load_info["pcurt"]>0
                AC_bus = nodal_input["load"]["$l"]["load_bus"]
                println("Pcurt: bus $l at time $i")
            end
            if load_info["pred"]>0
                AC_bus = nodal_input["load"]["$l"]["load_bus"]
                println("Pred: bus $AC_bus at time $i")
            end
        end
    end
end