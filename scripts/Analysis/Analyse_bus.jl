""" 
Overview of functions in Analyse_bus.jl:

1. Analyse_bus(n,nodal_input,nodal_result,number_of_hours,start_hour=1)
   - Analyzes power flows, demand, generation, and converters at a specified AC or DC bus.
   - Prints bus info, plots demand vs actual demand (AC only), generator outputs, branch and converter flows, and net power balance.

2. nodal_price(nodal_result, nodal_input,hour_range)
   - Calculates average nodal electricity prices for all AC and DC buses over a given time range.
   - Returns average prices per bus, along with minimum and maximum nodal prices.

3. plot_nodes_with_prices(data,nodal_result,hour_range;file_name,legend_file_name)
   - Plots a geographic map of grid nodes colored by nodal prices for given hours.
   - Saves plot and color scale legend as SVG files.
"""

"""
    Analyse_bus(n,nodal_input,nodal_result,number_of_hours,start_hour=1)

Analyzes the power flows, demand, generation, and converter connections for a given bus (AC or DC) over a simulation period.

    # Arguments
    - `n`: ID of the bus (AC or DC) to be analyzed.
    - `nodal_input`: Dictionary containing input data for the nodal model.
    - `nodal_result`: Dictionary containing simulation results for the nodal model.
    - `timeseries_data`: Dictionary containing time series data, including demand profiles.
    - `number_of_hours`: Total number of hours to analyze. Make sure this does not exceeds the length of the nodal_result data.
    - `start_hour`: Starting hour of the analysis period.

    # Output
    - Prints the bus details
    - Displays plots for:
        - Demand vs actual demand (AC bus only)
        - Generator output (AC bus only)
        - Branch and converter power flows
        - Net power balance (generation - withdrawals)

"""
function Analyse_bus(n,nodal_input,nodal_result,timeseries_data,number_of_hours,start_hour=1)

    # Determine if bus is AC or DC
    if "$n" in keys(nodal_input["busdc"])
        type = "DC Bus"
        zone = nodal_input["busdc"]["$n"]["zone"]
    else
        type = "AC Bus"
        zone = nodal_input["bus"]["$n"]["zone"]

        # Determine demand at AC bus over time
        demand_ideal = [] # Ideal demand based on load factor (input-based)
        demand_real = [] # Actual demand realized in the simulation (result-based)
        for i in start_hour:(start_hour + number_of_hours - 1)
            # Find the load index for this bus
            load_index = collect(filter(l -> nodal_input["load"][l]["load_bus"] == n, keys(nodal_input["load"])))
            
            if length(load_index) == 1
                LF = timeseries_data["demand"][zone][i] # load factor (LF) from time series data
                demand_at_bus = nodal_input["load"][load_index[1]]["pmax"] * LF * 100  # in MW
                actual_demand = nodal_result["$i"]["solution"]["load"][load_index[1]]["pflex"] * 100  # in MW

                push!(demand_ideal, demand_at_bus)
                push!(demand_real, actual_demand)
            end
        end

        # Plot demand vs actual demand (both values should be equal)
        P1 = Plots.plot(demand_ideal, label="Demand")
        Plots.plot!(demand_real, label = "Actual demand")
        Plots.title!("Demand profile at bus $n ($zone)")
        Plots.xlims!(0.8, 15.2)
        Plots.xticks!(1:1:15)
        Plots.xlabel!("Time [h]")
        Plots.ylabel!("Power [MW]")
        Plots.display(P1)
    end

    # Print basic info
    println("--------------------------------")
    println("Bus type: $type")
    println("Bus zone: ", zone)
    println("--------------------------------")

    # Check if a converter is attached to this bus
    if "$n" in keys(nodal_input["busdc"])
        conv = collect(filter(c -> nodal_input["convdc"][c]["busdc_i"] == n, keys(nodal_input["convdc"])))
        if length(conv) != 0
            ac_bus_list = [] # List of AC buses connected to this DC converter
            for x in eachindex(conv)
                ac_bus = nodal_input["convdc"][conv[x]]["busac_i"]
                push!(ac_bus_list,ac_bus)
            end 
            println("There is an AC/DC converter attached to this node: converter $conv")
            println("The corresponding AC bus is: ", ac_bus_list)
            println("--------------------------------")
        end
    else
        conv = collect(filter(c -> nodal_input["convdc"][c]["busac_i"] == n, keys(nodal_input["convdc"])))
        if length(conv) != 0
            dc_bus_list = [] # List of DC buses connected to this AC converter
            for x in eachindex(conv)
                dc_bus = nodal_input["convdc"][conv[x]]["busdc_i"]
                push!(dc_bus_list,dc_bus)
            end 
            println("There is an AC/DC converter attached to this node: converter $conv")
            println("The corresponding DC bus is: ", dc_bus_list)
            println("--------------------------------")
        end
    end

    # Analyze generators at AC buses (for AC bus only)
    if !("$n" in keys(nodal_input["busdc"]))
        gen_list = [] # List to store generators at bus n
        for hour in keys(nodal_result)
            if nodal_result["$hour"]["objective"] !== nothing
                for g in keys(nodal_result["$hour"]["solution"]["gen"])
                    if nodal_input["gen"]["$g"]["gen_bus"] == n && !(g in gen_list)
                        push!(gen_list, g)
                    end
                end
            end
        end

        if isempty(gen_list)
            println("There are no generators at this bus")
        else
            println("These generators are available at this bus:")
            gen_list = sort(gen_list)
            total_production_per_time = Dict{Int, Float64}() # Dictionary to store total generation per time step

            for g in gen_list
                production = Float64[] # List to store generation for this generator per time step
                for i in start_hour:(start_hour + number_of_hours - 1)
                    if nodal_result["$i"]["objective"] !== nothing
                        power = nodal_result["$i"]["solution"]["gen"]["$g"]["pg"] * 100
                        push!(production, power)
                        total_production_per_time[i] = get(total_production_per_time, i, 0.0) + power
                    else
                        push!(production, 0)
                        total_production_per_time[i] = get(total_production_per_time, i, 0.0)
                    end
                end

                avg_power = Statistics.mean(production)
                max_power = maximum(production)
                println("Generator $g: ", nodal_input["gen"]["$g"]["type_tyndp"])
                println("    --> with average power = ", avg_power)
                println("    --> with maximum power = ", max_power)
            end
        end
        println("--------------------------------")
    end


    # Gather branch connections (AC and DC)
    from_branches = [b for b in keys(nodal_input["branch"]) if nodal_input["branch"]["$b"]["f_bus"] == n]
    to_branches = [b for b in keys(nodal_input["branch"]) if nodal_input["branch"]["$b"]["t_bus"] == n]
    from_branches_DC = [b for b in keys(nodal_input["branchdc"]) if nodal_input["branchdc"]["$b"]["fbusdc"] == n]
    to_branches_DC = [b for b in keys(nodal_input["branchdc"]) if nodal_input["branchdc"]["$b"]["tbusdc"] == n]

    println("These are the branches connected to bus ", n)
    for b in from_branches
        println("Branch $b: From bus ", nodal_input["branch"]["$b"]["f_bus"], " ---> To bus ", nodal_input["branch"]["$b"]["t_bus"])
    end
    for b in to_branches
        println("Branch $b: From bus ", nodal_input["branch"]["$b"]["f_bus"], " ---> To bus ", nodal_input["branch"]["$b"]["t_bus"])
    end
    for b in from_branches_DC
        println("Branch $b: From bus ", nodal_input["branchdc"]["$b"]["fbusdc"], " ---> To bus ", nodal_input["branchdc"]["$b"]["tbusdc"])
    end
    for b in to_branches_DC
        println("Branch $b: From bus ", nodal_input["branchdc"]["$b"]["fbusdc"], " ---> To bus ", nodal_input["branchdc"]["$b"]["tbusdc"])
    end


    # Collect flow data
    Flows = Dict{String, Vector{Float64}}()
    Conv_Flows = Dict{String, Vector{Float64}}()

    for i in start_hour:(start_hour + number_of_hours - 1)
        # Converter flows (AC bus only)
        if !("$n" in keys(nodal_input["busdc"])) && !isempty(conv)
            for c in conv
                Conv_Flows[c] = get(Conv_Flows, c, Float64[]) # Initialize an empty vector for converter c if it doesn't exist yet in Conv_Flows
                # Append the power flow for this hour:
                # If there is a valid optimization result for hour i, take the pgrid value and convert to MW
                # Otherwise, assume 0 MW for this hour
                push!(Conv_Flows[c], nodal_result["$i"]["objective"] !== nothing ? nodal_result["$i"]["solution"]["convdc"]["$c"]["pgrid"] * 100 : 0)
            end
        end

        # Branch flows
        for b in [from_branches; to_branches]
            Flows[b] = get(Flows, b, Float64[]) # Initialize an empty vector for branch b if it doesn’t exist yet in Flows
            # Determine the flow value at timestep i:
            # - If there is a valid optimization result (objective ≠ nothing):
            #     * Use 'pf' if b is a "from branch" (outgoing flow)
            #     * Use 'pt' if b is a "to branch" (incoming flow)
            # - Otherwise, use 0 for this timestep
            flow_value = nodal_result["$i"]["objective"] !== nothing ?
                nodal_result["$i"]["solution"]["branch"]["$b"][in(b, from_branches) ? "pf" : "pt"] * 100 : 0
            push!(Flows[b], flow_value)
        end
    end

    # Plot total flows over time coming from branches and converters connected to this bus
    total_flows_per_timestep = zeros(number_of_hours)
    total_conv_per_timestep = zeros(number_of_hours)

    P3 = Plots.plot()
    for b in keys(Flows)
        total_flows_per_timestep .+= Flows[b]
        Plots.plot!(Flows[b], label="Branch $b")
    end
    for c in keys(Conv_Flows)
        total_conv_per_timestep .+= Conv_Flows[c]
        Plots.plot!(Conv_Flows[c], label="Converter $c")
    end
    Plots.title!("Active power withdrawn at $n ($zone)")
    Plots.xlims!(0.8, 15.2)
    Plots.xticks!(1:1:15)
    Plots.xlabel!("Time [h]")
    Plots.ylabel!("Power [MW]")
    display(P3)

    # Calculate power balance (Gen - Load = Flow)
    if isempty(gen_list)
        total_production_vector = zeros(number_of_hours)
    else
        sorted_keys = sort(collect(keys(total_production_per_time)))
        # Create a vector of total production values ordered by time
        total_production_vector = [total_production_per_time[t] for t in sorted_keys]
    end

    # Calculate net flow at the bus for each timestep:
    # Net flow = sum of branch flows + converter flows - total generation
    net_flow = total_flows_per_timestep + total_conv_per_timestep - total_production_vector
    # Plot the net power flow over time
    P4 = Plots.plot()
    Plots.plot!(net_flow, label="Total branch flow")
    Plots.title!("Sum of the active power flows at bus $n (= Gen - Load)")
    Plots.xlims!(0.8, 15.2)
    Plots.xticks!(1:1:15)
    Plots.xlabel!("Time [h]")
    Plots.ylabel!("Power [MW]")
    display(P4)
end

"""
    nodal_price(nodal_result, nodal_input, hour_range)

Computes the average nodal electricity prices for all AC and DC buses over a specified range of hours, and identifies the minimum and maximum nodal prices observed.

# Arguments
- `nodal_result`: Dictionary containing the simulation results.
- `nodal_input`: Dictionary containing input data.
- `hour_range`: Iterable of integers specifying the hours/time steps over which to compute average prices.

# Output
- Returns a tuple `(Nodal_price, p_minimum, p_maximum)` where:
  - `Nodal_price`: Dictionary mapping bus IDs (as integers) to their average nodal price over the specified time range.
  - `p_minimum`: The minimum nodal price observed across all buses and hours.
  - `p_maximum`: The maximum nodal price observed across all buses and hours.

# Notes
- Nodal prices are derived as the negative of the Lagrange multipliers (`lam_kcl_r`) from the power balance constraints.
- Supports both AC and DC buses.
"""


function nodal_price(nodal_result, nodal_input,hour_range)
    Nodal_price = Dict()
    p_minimum = 0
    p_maximum = 0
    
    for bus in keys(nodal_input["bus"]) # AC buses
        price_per_node = Float64[]
        for i in hour_range
             # Calculate price as negative Lagrange multiplier (in €/MWh)
            price =-nodal_result["$i"]["solution"]["bus"]["$bus"]["lam_kcl_r"]
            push!(price_per_node,price)
            # Update minimum and maximum prices if necessary
            if price >p_maximum
                p_maximum = price
            elseif price <p_minimum
                p_minimum = price
            end

        end
        # Compute average price for this bus and store it in the dictionary
        Nodal_price[parse(Int,bus)] = Statistics.mean(price_per_node)
    end

    for bus in keys(nodal_input["busdc"]) # DC buses
        price_per_node = Float64[]
        for i in hour_range
             # Calculate price as negative Lagrange multiplier (in €/MWh)
            price =-nodal_result["$i"]["solution"]["busdc"]["$bus"]["lam_kcl_r"]
            push!(price_per_node,price)
            # Update minimum and maximum prices if necessary
            if price >p_maximum
                p_maximum = price
            elseif price <p_minimum
                p_minimum = price
            end

        end
        # Compute average price for this bus and store it in the dictionary
        Nodal_price[parse(Int,bus)] = Statistics.mean(price_per_node)
    end

    # Return dictionary with average nodal prices and global min and max price
    return Nodal_price,p_minimum,p_maximum
end

"""
    plot_nodes_with_prices(data, nodal_result,hour_range;
                          file_name="results/grid_nodalprice.svg",
                          legend_file_name="results/grid_legend.svg")

Plots a geographical map of grid nodes colored by their nodal prices for a given hour.

# Arguments
- `data`: Dictionary containing input data, including AC and DC buses with their metadata (location, index).
- `nodal_result`: Results dictionary containing nodal prices and solution data.
- `hour_range`: Range of hours to consider for nodal price calculation e.g. [6], 1:20
- `file_name`: Path to save the main node price plot (SVG format).
- `legend_file_name`: Path to save the color scale legend (SVG format).

# Output
- Saves a colored map of nodes based on nodal prices to `file_name`.
- Saves a separate color scale legend to `legend_file_name`.

# Details
- Clamps prices between -50 and 300 €/MWh.
- Normalizes nodal prices to a 0-1 scale to map colors from the 'jet' colormap.
"""


using PlotlyJS, ColorSchemes, DataFrames
function plot_nodes_with_prices(data,nodal_result,hour_range
    ; 
    file_name = joinpath("results", join(["grid_nodalprice.svg"])),
    legend_file_name = joinpath("results", join(["grid_legend.svg"]))
)

    # Retrieve nodal prices for hour 6 from nodal_price function
    prices, p_min, p_max = nodal_price(nodal_result,data,hour_range)

    # Clamp price bounds for visualization
    # Change to p_min and p_max if wanted
    p_min = -50
    p_max = 300

    # Containers for node metadata
    nodes = []
    lat = []
    lon = []
    type = []
    
    # Collect AC bus data (index, latitude, longitude)
    for (b_id, b) in data["bus"]
        push!(nodes, b["index"])
        push!(lat, b["lat"])
        push!(lon, b["lon"])
        push!(type, 0)  # Mark AC nodes with 0
    end

    # Collect DC bus data similarly
    for (b_id, b) in data["busdc"]
        push!(nodes, b["index"])
        push!(lat, b["lat"])
        push!(lon, b["lon"])
        push!(type, 1)  # Mark DC nodes with 1
    end

    # Create DataFrame combining all nodes
    dict_nodes = DataFrame("node" => nodes, "lat" => lat, "lon" => lon, "type" => type)

    # Extract prices per node, default 0 if missing
    node_colors = [
        get(prices, row[:node], 0.0)
        for row in eachrow(dict_nodes)
    ]

    # Normalize prices to [0, 1] range for colormap indexing (avoid division by zero)
    norm_prices = (node_colors .- p_min) ./ (p_max - p_min + 1e-10)

    # Initialize list of plot traces
    traces = [PlotlyJS.scattergeo()]

    # Create a marker trace per node with color based on normalized price
    for (i, row) in enumerate(eachrow(dict_nodes))
        color = ColorSchemes.get(ColorSchemes.jet, norm_prices[i])  # Get color from jet colormap
        marker = PlotlyJS.attr(size=3.5, color=color)
        
        trace = PlotlyJS.scattergeo(mode="markers",
                                    lat=[row[:lat]],
                                    lon=[row[:lon]],
                                    marker=marker)
        push!(traces, trace)
    end
    traces = traces[2:end]  # Remove dummy placeholder

    
    # Define layout for geographic plot with map fit to node locations
    geo = PlotlyJS.attr(fitbounds="locations")
    layout = PlotlyJS.Layout(
        geo=geo,
        geo_resolution=50,
        width=1000,
        height=1100,
        showlegend=true,
        margin=PlotlyJS.attr(l=0, r=0, t=0, b=0)
    )

    # Generate and save main plot figure
    fig = PlotlyJS.plot(traces, layout)
    PlotlyJS.savefig(fig, file_name)


    # Create separate figure for color scale legend
    # Generate gradient colors from jet colormap
    colors = [ColorSchemes.get(ColorSchemes.jet, i) for i in 0:0.01:1]
    y_vals = collect(range(p_min, p_max, length=length(colors)))

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
                title = "Price (€/MWh)",
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


