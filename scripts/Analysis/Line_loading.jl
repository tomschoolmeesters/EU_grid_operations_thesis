"""
Overview of functions in this file Line_loading.jl:

1. Line_loading(lines, nodal_input, nodal_result)
    - Visualizes hourly power flows (in MW) for specified transmission lines.
    - Creates boxplots showing power flow distributions over all simulated hours.
    - Prints the maximum thermal rating for each line.

2. mean_Loadfactor(nodal_input, hour_range)
    - Computes average load factors for all lines over a specified hour range.
    - For AC lines: calculates the mean of the minimum between thermal and electrical load factors.
    - For DC lines: returns the maximum load factor over the time range.

3. hourly_Loadfactor(nodal_input, hour_range)
    - Calculates hourly load factors separately for AC and DC lines.
    - For AC lines: load factor per hour is the maximum of thermal and electrical limits.
    - For DC lines: uses thermal rating for load factor calculation.
    - Returns two dictionaries mapping line IDs to hourly load factor vectors.

4. where_congestion(nodal_input, nodal_result)
    - Identifies lines (AC and DC) that are thermally congested.
    - A line is congested if power flow exceeds 95% of its thermal rating in at least 50% of hours.
    - Returns a list of congested line IDs.

5. where_congestion_electrical(nodal_input, nodal_result)
    - Identifies AC lines electrically congested.
    - Congestion occurs if flow exceeds 95% of electrical transfer limit in ≥50% of hours.
    - Returns a list of electrically congested AC line IDs.

6. plot_loaded_grid(data, file_name, hour_range; ac_only=false)
    - Visualizes the electrical grid with geospatial plots.
    - Colors branches based on average load factors over the specified hour range.
    - Optionally plots only AC branches and buses.
    - Saves and displays the plot as a map.
"""

"""
    Line_loading(lines,nodal_input,nodal_result)

Visualize and analyze power flows through a set of transmission lines over all simulated hours.

    # Arguments
    - `lines`: A list of line identifiers (as strings or symbols) to analyze.
    - `nodal_input`: Dictionary containing input data for the nodal model.
    - `nodal_result`: Dictionary containing simulation results for the nodal model.

    # Description
    This function does the following:
    1. Checks whether each line is a DC or AC branch using `nodal_input`.
    2. Collects absolute hourly power flow (`pt`) values for each line from `nodal_result`.
    3. Converts power values from p.u. to MW (×100).
    4. Creates a boxplot of power flow distribution for each line.
    5. Prints the maximum thermal rating (rateA or rate_a) for each line.

    # Output
    - Displays a boxplot of line loading (MW) across hours.
    - Prints thermal limits for each line in MW.
"""

function Line_loading(lines,nodal_input,nodal_result)

    # Initialize dictionary to store power flows per line (in MW)
    Power = Dict{String, Vector{Float64}}()

    for line in lines
        line_key = string(line)                      # Ensure line is a string (for dictionary access)
        power_values = Float64[]                     # Initialize vector to hold power values

        if line_key in keys(nodal_input["branchdc"]) # DC branch
            for i in keys(nodal_result)              # Loop over each hour
                pt = nodal_result["$i"]["solution"]["branchdc"][line_key]["pt"]
                push!(power_values, abs(pt) * 100)   # Convert to MW and store absolute value
            end
        else                                          # AC branch
            for i in keys(nodal_result)
                pt = nodal_result["$i"]["solution"]["branch"][line_key]["pt"]
                push!(power_values, abs(pt) * 100)
            end
        end

        Power[line_key] = power_values               # Store time series in dictionary
    end

    # Prepare data for boxplot
    line_labels = reshape(collect(keys(Power)), 1, length(Power))  # Line names as labels
    powerdata = hcat(collect(values(Power))...)                    # Concatenate values column-wise

    # Generate and display the boxplot
    P = Plots.boxplot(
        line_labels,
        eachcol(powerdata),
        xlabel = "Lines",
        ylabel = "Power (MW)",
        title = "Line Power Distribution",
        legend = false,
        xticks = :auto
    )
    display(P)

    # Print thermal rating for each line
    println("This is the maximal thermal rating of each line:")
    for l in line_labels
        if l in keys(nodal_input["branchdc"])
            max_rating = nodal_input["branchdc"]["$l"]["rateA"] * 100  # MW
        else
            max_rating = nodal_input["branch"]["$l"]["rate_a"] * 100  # MW
        end
        println("Line $l: $max_rating MW")
    end
end

"""
    mean_Loadfactor(nodal_input, hour_range)

Compute the average load factor for all transmission lines (AC and DC) over a specified time range.

    # Arguments
    - `nodal_input`: Dictionary containing input data for the nodal model.
    - `hour_range`: Range of hours to analyze (e.g., `1:24`).

    # Returns
    - `Loading`: A dictionary mapping line IDs (as integers) to their average (AC) or maximum (DC) load factor over the time range.

    # Description
    - For **AC lines**, the function calculates the hourly load factor as the **minimum** between the thermal and electrical load limits. Then it returns the **mean** load factor across all hours.
    - For **2-winding transformers**, the load factor is set to 0 across all hours (ignored in loading analysis).
    - For **DC lines**, the function calculates the hourly load factor based on the thermal rating and returns the **maximum** load factor over all hours.

    # Notes
    - All power values are converted to MW (×100) from p.u. input.
    - Line IDs are parsed as integers for dictionary keys to allow uniform identification.
"""

function mean_Loadfactor(nodal_input,nodal_result,hour_range)
    # Dictionary to store mean loading per line (indexed by integer line ID)
    Loading = Dict()

    # --- Loop through AC branches ---
    for line_ac in keys(nodal_input["branch"])
        line_data = nodal_input["branch"]["$line_ac"]
        
        if line_data["type"] == "AC line"
            load_factors = Float64[]
            max_rating = line_data["rate_a"] * 100  # Thermal rating in MW
            max_elec_rating = (line_data["angmax"] / line_data["br_x"]) * 100  # Electrical limit in MW

            for i in hour_range
                pt = abs(nodal_result["$i"]["solution"]["branch"]["$line_ac"]["pt"]) * 100
                load_factor_therm = pt / max_rating
                load_factor_elec = pt / max_elec_rating
                push!(load_factors, minimum([load_factor_therm, load_factor_elec]))
            end

            Loading[parse(Int, line_ac)] = Statistics.mean(load_factors)

        elseif line_data["type"] == "2W transf"
            load_factors = zeros(Float64, length(hour_range))  # Transformer not evaluated, assign zero
            Loading[parse(Int, line_ac)] = Statistics.mean(load_factors)
        end
    end

    # --- Loop through DC branches ---
    for line_dc in keys(nodal_input["branchdc"])
        load_factors = Float64[]
        max_rating = nodal_input["branchdc"]["$line_dc"]["rateA"] * 100  # MW

        for i in hour_range
            pt = abs(nodal_result["$i"]["solution"]["branchdc"][line_dc]["pt"]) * 100
            push!(load_factors, pt / max_rating)
        end

        # Store maximum load factor across all hours for DC lines
        Loading[parse(Int, line_dc)] = maximum(load_factors)
    end

    return Loading
end

"""
    hourly_Loadfactor(nodal_input, hour_range)

Compute the hourly load factors for all AC and DC transmission lines over a given time range.

    # Arguments
    - `nodal_input::Dict`: Dictionary containing input data for branches (`branch`, `branchdc`) with their ratings and parameters.
    - `hour_range::UnitRange{Int}`: Time steps (e.g. 1:24) for which the load factor is to be calculated.

    # Returns
    - `(Loading_AC, Loading_DC)`: Tuple of two dictionaries:
        - `Loading_AC::Dict{Int, Vector{Float64}}`: Hourly load factors for AC lines, keyed by line ID.
        - `Loading_DC::Dict{Int, Vector{Float64}}`: Hourly load factors for DC lines, keyed by line ID.

    # Description
    - For AC lines, both thermal and electrical limits are considered:
        - Load factor per hour is taken as the maximum of thermal and electrical load factor.
    - For DC lines, only the thermal capacity is used.
"""

function hourly_Loadfactor(nodal_input, nodal_result, hour_range)
    Loading_AC = Dict()  # Stores hourly load factors for AC lines
    Loading_DC = Dict()  # Stores hourly load factors for DC lines

    # --- Process AC lines ---
    for line_ac in keys(nodal_result["1"]["solution"]["branch"])
        load_factors = Float64[]  # Collects hourly load factors for this line

        # Thermal and electrical ratings (in MW)
        max_rating = nodal_input["branch"]["$line_ac"]["rate_a"] * 100
        max_elec_rating = (nodal_input["branch"]["$line_ac"]["angmax"] / nodal_input["branch"]["$line_ac"]["br_x"]) * 100

        for i in hour_range
            # Calculate thermal and electrical load factors
            pt = abs(nodal_result["$i"]["solution"]["branch"]["$line_ac"]["pt"]) * 100  # MW
            load_factor_therm = pt / max_rating
            load_factor_elec = pt / max_elec_rating

            # Use the more conservative (higher) of the two
            push!(load_factors, maximum([load_factor_therm, load_factor_elec]))
        end

        # Store in dictionary using integer line ID
        Loading_AC[parse(Int, line_ac)] = load_factors
    end

    # --- Process DC lines ---
    for line_dc in keys(nodal_input["branchdc"])
        load_factors = Float64[]  # Hourly load factors

        max_rating = nodal_input["branchdc"]["$line_dc"]["rateA"] * 100  # MW

        for i in hour_range
            pt = abs(nodal_result["$i"]["solution"]["branchdc"][line_dc]["pt"]) * 100  # MW
            push!(load_factors, pt / max_rating)
        end

        Loading_DC[parse(Int, line_dc)] = load_factors
    end

    return Loading_AC, Loading_DC
end

"""
    where_congestion(nodal_input, nodal_result)

Identify lines (AC and DC) that are frequently congested. Based on thermal rating.

    # Arguments
    - `nodal_input`: Contains line data (ratings) under `branch` (AC) and `branchdc` (DC).
    - `nodal_result`: Contains power flow results per hour for each line.

    # Returns
    - `congested_lines`: List of line IDs (as strings) that are congested in ≥50% of the hours.

    # Congestion Criterion
    - A line is considered congested if its power flow exceeds 95% of its thermal rating in at least 50% of the hours.
"""

function where_congestion(nodal_input, nodal_result)
    congested_lines = String[]  # Stores IDs of congested lines
    hours = length(nodal_result)

    # --- Check AC lines ---
    for l_ac in keys(nodal_result["1"]["solution"]["branch"])
        count_above_threshold = 0
        rated_power = nodal_input["branch"]["$l_ac"]["rate_a"] * 100  # MW
        threshold_power = 0.95 * rated_power  # 95% congestion threshold

        for i in 1:hours
            power = abs(nodal_result["$i"]["solution"]["branch"]["$l_ac"]["pt"] * 100)
            if power > threshold_power
                count_above_threshold += 1
            end
        end

        # If congested in ≥50% of hours, add to list
        if count_above_threshold / hours >= 0.50
            push!(congested_lines, l_ac)
        end
    end

    # --- Check DC lines ---
    for l_dc in keys(nodal_input["branchdc"])
        count_above_threshold = 0
        rated_power = nodal_input["branchdc"]["$l_dc"]["rateA"] * 100  # MW
        threshold_power = 0.95 * rated_power # 95% congestion threshold

        for i in 1:hours
            power = abs(nodal_result["$i"]["solution"]["branchdc"]["$l_dc"]["pt"] * 100)
            if power > threshold_power
                count_above_threshold += 1
            end
        end

        # If congested in ≥50% of hours, add to list
        if count_above_threshold / hours >= 0.5
            push!(congested_lines, l_dc)
        end
    end

    return congested_lines
end

"""
    where_congestion_electrical(nodal_input, nodal_result)

Identify AC lines that are electrically congested.

    # Arguments
    - `nodal_input`: Contains AC branch parameters like `angmax` and `br_x`.
    - `nodal_result`: Contains hourly simulation results, including line flows.

    # Returns
    - `congested_lines::Vector{String}`: List of AC line IDs (as strings) where electrical congestion occurs in ≥50% of the hours.

    # Congestion Criterion
    - A line is considered electrically congested if the absolute flow exceeds 95% of its electrical transfer limit in at least 50% of the hours.
    - The electrical limit is computed as:
        ```
        (angmax / br_x) * 100  # MW
        ```
"""

function where_congestion_electrical(nodal_input,nodal_result)
    congested_lines = String[]  # Store IDs of congested AC lines
    hours = length(nodal_result)

    for l_ac in keys(nodal_result["1"]["solution"]["branch"])
        count_above_threshold = 0
        # Compute electrical transfer limit [MW]
        rated_power = (nodal_input["branch"]["$l_ac"]["angmax"] / nodal_input["branch"]["$l_ac"]["br_x"]) * 100
        threshold_power = 0.95 * rated_power  # 95% congestion threshold

        for i in 1:hours
            power = abs(nodal_result["$i"]["solution"]["branch"]["$l_ac"]["pt"] * 100)
            if power > threshold_power
                count_above_threshold += 1
            end
        end

        # If congested in ≥50% of hours, add to list
        if count_above_threshold / hours >= 0.50
            push!(congested_lines, l_ac)
        end
    end
    return congested_lines
end

"""
    plot_loaded_grid(data, file_name, hour_range;ac_only)

Visualize the electrical grid using geospatial plots with optional coloring based on line loading.

    # Arguments
    - `data`: A dictionary containing bus, busdc, branch, and branchdc data (typically `nodal_input`).
    - `file_name::String`: Output filename to save the plot.
    - `hour_range`: The list of time steps over which to average line loadings (passed to `mean_Loadfactor`).
    - `ac_only::Bool = false`: If `true`, plot only AC branches and AC buses.

    # Returns
    - Saves and displays a PlotlyJS `.html` map showing the grid topology with optional loading colors.

    # Dependencies
    - Relies on the external function `mean_Loadfactor(...)` to compute line loadings.
"""

import PlotlyJS
import ColorSchemes

function plot_loaded_grid(
    data, result, file_name, legend_file_name, hour_range;
    ac_only = false)

    line_loadings = mean_Loadfactor(data, result, hour_range)

    # ========== Extract nodes ==========
    nodes, lat, lon, type = [], [], [], []

    # AC buses
    for (b_id, b) in data["bus"]
        push!(nodes, b["index"])
        push!(lat, b["lat"])
        push!(lon, b["lon"])
        push!(type, 0)
    end

    # Align DC bus coordinates with their connected AC bus
    for (_, conv) in data["convdc"]
        bus_ac = conv["busac_i"]
        bus_dc = conv["busdc_i"]
        data["busdc"]["$bus_dc"]["lat"] = deepcopy(data["bus"]["$bus_ac"]["lat"])
        data["busdc"]["$bus_dc"]["lon"] = deepcopy(data["bus"]["$bus_ac"]["lon"])
    end

    # DC buses
    for (_, b) in data["busdc"]
        push!(nodes, b["index"])
        push!(lat, b["lat"])
        push!(lon, b["lon"])
        push!(type, 1)
    end

    dict_nodes = DataFrames.DataFrame("node" => nodes, "lat" => lat, "lon" => lon, "type" => type)

    # ========== Extract branches ==========
    branches, lat_fr, lon_fr, lat_to, lon_to = [], [], [], [], []
    bus_fr_, bus_to_, type_ = [], [], []

    # AC branches
    for (_, branch) in data["branch"]
        bus_fr = branch["f_bus"]
        bus_to = branch["t_bus"]
        if haskey(data["bus"], "$bus_fr") && haskey(data["bus"], "$bus_to")
            push!(branches, branch["index"])
            push!(bus_fr_, bus_fr)
            push!(bus_to_, bus_to)
            push!(lat_fr, data["bus"]["$bus_fr"]["lat"])
            push!(lon_fr, data["bus"]["$bus_fr"]["lon"])
            push!(lat_to, data["bus"]["$bus_to"]["lat"])
            push!(lon_to, data["bus"]["$bus_to"]["lon"])
            push!(type_, 0)
        end
    end

    # DC branches
    for (_, branch) in data["branchdc"]
        bus_fr = branch["fbusdc"]
        bus_to = branch["tbusdc"]
        if haskey(data["busdc"], "$bus_fr") && haskey(data["busdc"], "$bus_to")
            push!(branches, branch["index"])
            push!(bus_fr_, bus_fr)
            push!(bus_to_, bus_to)
            push!(lat_fr, data["busdc"]["$bus_fr"]["lat"])
            push!(lon_fr, data["busdc"]["$bus_fr"]["lon"])
            push!(lat_to, data["busdc"]["$bus_to"]["lat"])
            push!(lon_to, data["busdc"]["$bus_to"]["lon"])
            push!(type_, 1)
        end
    end

    map_ = DataFrames.DataFrame(
        "from" => bus_fr_,
        "to" => bus_to_,
        "lat_fr" => lat_fr,
        "lon_fr" => lon_fr,
        "lat_to" => lat_to,
        "lon_to" => lon_to,
        "type" => type_,
        "branch" => branches
    )

    # ========== Plot Nodes ==========
    txt_x = 1
    markerAC = PlotlyJS.attr(size = [txt_x], color = "green")
    markerDC = PlotlyJS.attr(size = [txt_x], color = "blue")

    ac_buses = filter(:type => ==(0), dict_nodes)
    dc_buses = filter(:type => ==(1), dict_nodes)

    traceAC = [PlotlyJS.scattergeo(; mode = "markers", lat = [r.lat], lon = [r.lon], marker = markerAC) for r in eachrow(ac_buses)]
    traceDC = [PlotlyJS.scattergeo(; mode = "markers", lat = [r.lat], lon = [r.lon], marker = markerDC) for r in eachrow(dc_buses)]

    # ========== Plot Branches ==========
    trace_AC = [PlotlyJS.scattergeo()]
    trace_DC = [PlotlyJS.scattergeo()]

    for row in eachrow(map_)
        branch = row.branch
        flow = get(line_loadings, branch, 0.0)

        if row[:type] == 0  # AC
            lineAC = PlotlyJS.attr(width = 1 * txt_x, color = ColorSchemes.get(ColorSchemes.jet, flow))
            push!(trace_AC, PlotlyJS.scattergeo(; mode = "lines", lat = [row.lat_fr, row.lat_to], lon = [row.lon_fr, row.lon_to], line = lineAC))
        else  # DC
            lineDC = PlotlyJS.attr(width = 1 * txt_x, color = ColorSchemes.get(ColorSchemes.jet, flow))
            push!(trace_DC, PlotlyJS.scattergeo(; mode = "lines", lat = [row.lat_fr, row.lat_to], lon = [row.lon_fr, row.lon_to], line = lineDC))
        end
    end

    # ========== Combine and Plot ==========
    trace = ac_only ? vcat(trace_AC, traceAC) : vcat(trace_AC, trace_DC, traceDC, traceAC)
    layout = PlotlyJS.Layout(
        geo = PlotlyJS.attr(fitbounds = "locations"),
        geo_resolution = 50,
        width = 1000,
        height = 1100,
        showlegend = false,
        margin = PlotlyJS.attr(l = 0, r = 0, t = 0, b = 0)
    )

    fig = PlotlyJS.plot(trace, layout)
    PlotlyJS.savefig(fig, file_name)
    display(fig)

    # Create separate figure for color scale legend
    # Generate gradient colors from jet colormap
    colors = [ColorSchemes.get(ColorSchemes.jet, i) for i in 0:0.01:1]
    y_vals = collect(range(0, 1, length=length(colors)))

    # Create a vertical scatter plot for the legend colors
    legend_trace = PlotlyJS.scatter(
        x = fill(1, length(colors)),
        y = y_vals,
        mode = "markers",
        marker = PlotlyJS.attr(
            size = 10,
            color = colors,
            showscale = true,
            colorbar = PlotlyJS.attr(
                title = "Load Factor",
                titleside = "right",
                thickness = 15
            )
        ),
        showlegend = false
    )

    # Layout for legend figure
    legend_layout = PlotlyJS.Layout(
        title = "Color Scale Legend",
        width = 300,
        height = 600,
        margin = PlotlyJS.attr(l=10, r=10, t=50, b=10),
        plot_bgcolor = "white",      # Background inside plot axes
        paper_bgcolor = "white"      # Background of entire figure
    )

    # Generate and save legend figure
    legend_fig = PlotlyJS.plot([legend_trace], legend_layout)
    PlotlyJS.savefig(legend_fig, legend_file_name)
end
