function Line_loading(lines)
    Power = Dict{String, Vector{Float64}}()  # Initialize Power as a dictionary of arrays

    for line in lines
        line_key = string(line)  # Convert line to a string for dictionary keys
        power_values = Float64[]  # Initialize an array to store power values for this line

        if line_key in keys(nodal_input["branchdc"])  # DC branch
            for i in keys(nodal_result)  # For every hour
                push!(power_values, abs(nodal_result["$i"]["solution"]["branchdc"][line_key]["pt"]) * 100)
            end
        else  # AC branch
            for i in keys(nodal_result)  # For every hour
                push!(power_values, abs(nodal_result["$i"]["solution"]["branch"][line_key]["pt"]) * 100)
            end
        end

        Power[line_key] = power_values  # Store the power values for the current line
    end

    # Prepare data for boxplot
    line_labels = reshape(collect(keys(Power)), 1, length(keys(Power)))
    println(line_labels)
    powerdata = hcat(collect(values(Power))...)
    # Generate the boxplot
    P = boxplot(line_labels,eachcol(powerdata), xlabel="Lines", ylabel="Power (MW)", title="Line Power Distribution", legend=false, xticks=:auto)
    display(P)

    #Max ratings
    println("This is the maximal thermal rating of the line:")
    for l in line_labels
        if l in keys(nodal_input["branchdc"])
            max_rating = nodal_input["branchdc"]["$l"]["rateA"]*100 #MW
        else
            max_rating = nodal_input["branch"]["$l"]["rate_a"]*100 #MW
        end
        println("Line $l: $max_rating MW")
    end
end

function Loadfactor(hour_range)
    Loading = Dict()  # Initialize Power as a dictionary of arrays
    for line_ac in keys(nodal_input["branch"])
        if nodal_input["branch"]["$line_ac"]["type"] == "AC line"
            load_factors = Float64[]
            max_rating = nodal_input["branch"]["$line_ac"]["rate_a"]*100 #MW
            for i in hour_range
                push!(load_factors, (abs(nodal_result["$i"]["solution"]["branch"][line_ac]["pt"]) * 100)/max_rating)
            end
            Loading[parse(Int,line_ac)] = mean(load_factors)
        end
        if nodal_input["branch"]["$line_ac"]["type"] == "2W transf"
            load_factors = Float64[]
            max_rating = nodal_input["branch"]["$line_ac"]["rate_a"]*100 #MW
            for i in hour_range
                push!(load_factors, 0)
            end
            Loading[parse(Int,line_ac)] = mean(load_factors)
        end
    end
    
    for line_dc in keys(nodal_input["branchdc"])
        load_factors = Float64[]
        max_rating = nodal_input["branchdc"]["$line_dc"]["rateA"]*100 #MW
        for i in hour_range
            push!(load_factors, (abs(nodal_result["$i"]["solution"]["branchdc"][line_dc]["pt"]) * 100)/max_rating)
        end
        Loading[parse(Int,line_dc)] = maximum(load_factors)
    end

    return Loading
end

function where_congestion()
    congested_lines = String[]
    #AC lines
    for l_ac in keys(nodal_result["1"]["solution"]["branch"])
        hours = length(nodal_result)
        count_above_threshold = 0
        rated_power = nodal_input["branch"]["$l_ac"]["rate_a"]*100 #MW
        threshold_power = 0.95*rated_power
        for i in 1:hours
            power = abs(nodal_result["$i"]["solution"]["branch"]["$l_ac"]["pt"]*100)
            if power>threshold_power
                count_above_threshold += 1
            end
        end

        if count_above_threshold / hours >= 0.5
            push!(congested_lines, l_ac)  # Voeg lijn toe aan lijst
        end
    end

    for l_dc in keys(nodal_input["branchdc"])
        hours = length(nodal_result)
        count_above_threshold = 0
        rated_power = nodal_input["branchdc"]["$l_dc"]["rateA"]*100 #MW
        threshold_power = 0.95*rated_power
        for i in 1:hours
            power = abs(nodal_result["$i"]["solution"]["branchdc"]["$l_dc"]["pt"]*100)
            if power>threshold_power
                count_above_threshold += 1
            end
        end

        if count_above_threshold / hours >= 0.5
            push!(congested_lines, l_dc)  # Voeg lijn toe aan lijst
        end
    end
    
    #println(congested_lines)
    return congested_lines

end

function where_congestion_electrical()
    congested_lines = String[]
    #AC lines
    for l_ac in keys(nodal_result["1"]["solution"]["branch"])
        hours = length(nodal_result)
        count_above_threshold = 0
        rated_power = (nodal_input["branch"]["$l_ac"]["angmax"]/nodal_input["branch"]["$l_ac"]["br_x"]) *100 #MW
        threshold_power = 0.95*rated_power
        for i in 1:hours
            power = abs(nodal_result["$i"]["solution"]["branch"]["$l_ac"]["pt"]*100)
            if power>threshold_power
                count_above_threshold += 1
            end
        end

        if count_above_threshold / hours >= 0.5
            push!(congested_lines, l_ac)  # Voeg lijn toe aan lijst
        end
    end    
    #println(congested_lines)
    return congested_lines

end

import PlotlyJS
import ColorSchemes
function plot_loaded_grid(
    data, file_name; 
    ac_only = false, 
    color_branches = true, 
    flows_ac = nothing, 
    flows_dc = nothing, 
    maximum_flows = false, 
    plot_node_numbers_ac = false, 
    plot_node_numbers_dc = false, 
    line_loadings = Loadfactor([1559]))

    #using PlotlyJS, ColorSchemes, DataFrames

    # Creating a series of vectors to be added to a DataFrame dictionary
    # AC Buses (type 0) and DC Buses (type 1)
    nodes = []
    lat = []
    lon = []
    type = []
    for (b_id, b) in data["bus"]
        push!(nodes, b["index"])
        push!(lat, b["lat"])
        push!(lon, b["lon"])
        push!(type, 0)  # AC nodes
    end

    for (c, conv) in data["convdc"]
        bus_ac = conv["busac_i"]
        bus_dc = conv["busdc_i"]

        data["busdc"]["$bus_dc"]["lat"] = data["bus"]["$bus_ac"]["lat"]
        data["busdc"]["$bus_dc"]["lon"] = data["bus"]["$bus_ac"]["lon"]
    end

    for (b_id, b) in data["busdc"]
        push!(nodes, b["index"])
        push!(lat, b["lat"])
        push!(lon, b["lon"])
        push!(type, 1)  # DC nodes
    end

    # Creating a series of vectors to be added to a DataFrame dictionary
    # AC Branches (type 0) and DC Branches (type 1)
     
    branches = []
    lat_fr = []
    lon_fr = []
    lat_to = []
    lon_to = []
    bus_fr = []
    bus_to = []
    bus_fr_ = []
    bus_to_ = []
    type_ = []

    for (b, branch) in data["branch"]
        bus_fr = branch["f_bus"]
        bus_to = branch["t_bus"]
        if haskey(data["bus"], "$bus_fr") && haskey(data["bus"], "$bus_to")
            push!(branches, branch["index"])
            push!(bus_fr_, deepcopy(branch["f_bus"]))
            push!(bus_to_, deepcopy(branch["t_bus"]))
            push!(lat_fr, data["bus"]["$bus_fr"]["lat"])
            push!(lon_fr, data["bus"]["$bus_fr"]["lon"])
            push!(lat_to, data["bus"]["$bus_to"]["lat"])
            push!(lon_to, data["bus"]["$bus_to"]["lon"])
            push!(type_, 0)  # AC branches
        end
    end

    for (b, branch) in data["branchdc"]
        bus_fr = branch["fbusdc"]
        bus_to = branch["tbusdc"]
        if haskey(data["busdc"], "$bus_fr") && haskey(data["busdc"], "$bus_to")
            push!(branches, branch["index"])
            push!(bus_fr_, branch["fbusdc"])
            push!(bus_to_, branch["tbusdc"])
            push!(lat_fr, data["busdc"]["$bus_fr"]["lat"])
            push!(lon_fr, data["busdc"]["$bus_fr"]["lon"])
            push!(lat_to, data["busdc"]["$bus_to"]["lat"])
            push!(lon_to, data["busdc"]["$bus_to"]["lon"])
            push!(type_, 1)  # DC branches
        end
    end

    dict_nodes = DataFrames.DataFrame("node" => nodes, "lat" => lat, "lon" => lon, "type" => type)
    map_ = DataFrames.DataFrame("from" => bus_fr_, "to" => bus_to_, "lat_fr" => lat_fr, "lon_fr" => lon_fr, "lat_to" => lat_to, "lon_to" => lon_to, "type" => type_, "branch" => branches)

    txt_x = 1

    ac_buses=filter(:type => ==(0), dict_nodes)       
    markerAC = PlotlyJS.attr(size=[txt_x],
                color="green")
     
    dc_buses=filter(:type => ==(1), dict_nodes)       
    markerDC = PlotlyJS.attr(size=[txt_x],
                color="blue")
    #AC buses legend
    traceAC = [PlotlyJS.scattergeo(;mode="markers",
                lat=[row[:lat]],lon=[row[:lon]],
                marker=markerAC)  for row in eachrow(ac_buses)]

    #DC buses legend
    traceDC = [PlotlyJS.scattergeo(;mode="markers",
                lat=[row[:lat]],lon=[row[:lon]],
                marker=markerDC)  for row in eachrow(dc_buses)]

    trace_AC = [PlotlyJS.scattergeo()]
    trace_DC = [PlotlyJS.scattergeo()]

    for row in eachrow(map_)
        branch = row.branch
        if row[:type] == 0  # AC branch
            flow = get(line_loadings, branch, 0.0)  # Default to 0.0 if no loading info
            lineAC = PlotlyJS.attr(width = 1 * txt_x, color = ColorSchemes.get(ColorSchemes.jet, flow))
            push!(trace_AC, PlotlyJS.scattergeo(; mode = "lines", lat = [row.lat_fr, row.lat_to], lon = [row.lon_fr, row.lon_to], line = lineAC))
        else  # DC branch
            flow = get(line_loadings, branch, 0.0)
            lineDC = PlotlyJS.attr(width = 2 * txt_x, color = ColorSchemes.get(ColorSchemes.jet, flow))
            push!(trace_DC, PlotlyJS.scattergeo(; mode = "lines", lat = [row.lat_fr, row.lat_to], lon = [row.lon_fr, row.lon_to], line = lineDC))
        end
    end

    # Combine plot data
    if ac_only == true
        trace=vcat(trace_AC, traceAC) # only AC Branches and buses
    else
        trace=vcat(trace_AC, trace_DC, traceDC, traceAC) # both AC Branches and buses, DC Branches and buses
    end
    #set map location
    geo = PlotlyJS.attr(fitbounds="locations")
     
    #plot layput
   
    layout = PlotlyJS.Layout(geo = geo, geo_resolution = 50, width = 1000, height = 1100,
    showlegend = false,
    margin=PlotlyJS.attr(l=0, r=0, t=0, b=0))
    PlotlyJS.plot(trace, layout) # print figure
    PlotlyJS.savefig(PlotlyJS.plot(trace, layout), file_name)
end
