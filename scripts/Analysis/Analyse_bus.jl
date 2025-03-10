
function Analyse_bus(n,start_hour,planning_year)

    #Get information about bus
    if "$n" in keys(nodal_input["busdc"])
        type = "DC Bus"
        zone = nodal_input["busdc"]["$n"]["zone"]
    else
        type = "AC Bus"
        zone = nodal_input["bus"]["$n"]["zone"]

        #Determine demand at bus
        demand_ideal = []
        demand_real = []
        for i in start_hour:(start_hour+number_of_hours-1)
            load_index = collect(filter(l -> nodal_input["load"][l]["load_bus"] == n, keys(nodal_input["load"])))
            if length(load_index) == 1
                LF = timeseries_data["demand"][zone][i]
                demand_at_bus = nodal_input["load"][load_index[1]]["pmax"]*LF*100 #in MW
                actual_demand = nodal_result["$i"]["solution"]["load"][load_index[1]]["pflex"]*100 #in MW
                
                push!(demand_ideal,demand_at_bus)
                push!(demand_real,actual_demand)
                #push!(flex, pflex)
            end
        end
        P1 = Plots.plot(demand_ideal,label="Demand")
        plot!(demand_real, label = "Actual demand")
        title!("Demand profile at bus $n ($zone)")
        xlabel!("Time [h]")
        ylabel!("Power [MW]")
        display(P1)

    end

    #start_date = hour_to_date(planning_year, start_hour)
    #end_date = hour_to_date(planning_year, start_hour+number_of_hours-1)

    println("--------------------------------")
    println("Bus type: $type")
    println("Bus zone: ",zone)
    #println("Analysed period: vanaf ",start_date," tot ",end_date)
    println("--------------------------------")

    #Is there a converter connected to this bus?
    if "$n" in keys(nodal_input["busdc"])
        conv = collect(filter(c -> nodal_input["convdc"][c]["busdc_i"] == n, keys(nodal_input["convdc"])))
        if length(conv) !=0
            ac_bus_list = []
            for x in eachindex(conv)
                ac_bus = nodal_input["convdc"][conv[x]]["busac_i"]
                push!(ac_bus_list,ac_bus)
            end
            println("There is a DC converter attached to this node: converter $conv")
            println("The corresponding AC bus is: ", ac_bus_list)
            println("--------------------------------")
        end
    else
        conv = collect(filter(c -> nodal_input["convdc"][c]["busac_i"] == n, keys(nodal_input["convdc"])))
        if length(conv) != 0
            dc_bus_list = []
            for x in eachindex(conv)
                dc_bus = nodal_input["convdc"][conv[x]]["busdc_i"]
                push!(dc_bus_list,dc_bus)
            end
            println("There is a DC converter attached to this node: converter $conv")
            println("The corresponding DC bus is: ",dc_bus_list)
            println("--------------------------------")
        end
    end

    #Determine producing generators (Only AC)

    if !("$n" in keys(nodal_input["busdc"]))
        gen_list = []
        for hour in keys(nodal_result)
            if nodal_result["$hour"]["objective"] !== nothing
                for g in keys(nodal_result["$hour"]["solution"]["gen"])
                    if nodal_input["gen"]["$g"]["gen_bus"] == n &&
                        !(g in gen_list) #nodal_result["$hour"]["solution"]["gen"]["$g"]["pg"] !== 0.0 && 

                        push!(gen_list,g)
                    end
                end
            end
        end

        if length(gen_list) == 0
            println("There are no generators at this bus")
        else
            println("These generators are available at this bus:")
            gen_list = sort(gen_list)
            
            # Variabele om totale productie per tijdstap bij te houden
            total_production_per_time = Dict{Int, Float64}()
            
            for g in gen_list
                production = []
                for i in start_hour:(start_hour + number_of_hours - 1)
                    if nodal_result["$i"]["objective"] !== nothing
                        # Productie toevoegen aan productie-lijst
                        power = nodal_result["$i"]["solution"]["gen"]["$g"]["pg"] * 100
                        push!(production, power)
        
                        # Toevoegen aan de totale productie per tijdstap
                        if haskey(total_production_per_time, i)
                            total_production_per_time[i] += power
                        else
                            total_production_per_time[i] = power
                        end
                    else
                        push!(production, 0)
                        # Tijdstap zonder resultaat telt als 0
                        if !haskey(total_production_per_time, i)
                            total_production_per_time[i] = 0
                        end
                    end
                end
        
                # Bepaal gemiddelde en maximale productie voor generator g
                average_power = mean(production)
                maximum_power = maximum(production)
                println("Generator ", g, ": ", nodal_input["gen"]["$g"]["type_tyndp"])
                println("    --> with average power = ", average_power)
                println("    --> with maximum power = ", maximum_power)
            end
        
        end
        
        println("--------------------------------")
    end

    #Get information about flows around that bus ( AC bus)
    from_branches = []
    to_branches = []
    from_branches_DC = []
    to_branches_DC = []

    for branch in keys(nodal_input["branch"])
        if nodal_input["branch"]["$branch"]["f_bus"] == n
            push!(from_branches,branch)
        elseif nodal_input["branch"]["$branch"]["t_bus"] == n
            push!(to_branches,branch)
        end
    end

    for branch in keys(nodal_input["branchdc"])
        if nodal_input["branchdc"]["$branch"]["fbusdc"] == n
            push!(from_branches_DC,branch)
        elseif nodal_input["branchdc"]["$branch"]["tbusdc"] == n
            push!(to_branches_DC,branch)
        end
    end
    
    from_branches = sort(from_branches)
    to_branches = sort(to_branches)
    println("This are the branches connected to bus ",n)
    for b in from_branches
        println("Branch ",b,": From bus ",nodal_input["branch"]["$b"]["f_bus"], " ---> To bus ",nodal_input["branch"]["$b"]["t_bus"])
    end
    for b in to_branches
        println("Branch ",b,": From bus ",nodal_input["branch"]["$b"]["f_bus"], " ---> To bus ",nodal_input["branch"]["$b"]["t_bus"])
    end
    for b in from_branches_DC
        println("Branch ",b,": From bus ",nodal_input["branchdc"]["$b"]["fbusdc"], " ---> To bus ",nodal_input["branchdc"]["$b"]["tbusdc"])
    end
    for b in to_branches_DC
        println("Branch ",b,": From bus ",nodal_input["branchdc"]["$b"]["fbusdc"], " ---> To bus ",nodal_input["branchdc"]["$b"]["tbusdc"])
    end


    Flows = Dict()
    Conv_Flows = Dict()
    for i in start_hour:(start_hour+number_of_hours-1)
        
        if !("$n" in keys(nodal_input["busdc"])) && length(conv) !=0
            for c in conv
                if !haskey(Conv_Flows, c)
                    # Maak een nieuwe lege lijst voor de branch als deze nog niet bestaat
                    Conv_Flows[c] = []
                end
                # Voeg de power flow voor dit uur toe aan de lijst van de generator
                if nodal_result["$i"]["objective"] !== nothing
                    push!(Conv_Flows[c], nodal_result["$i"]["solution"]["convdc"]["$c"]["pgrid"]*100)
                else
                    push!(Conv_Flows[c],0)
                end
            end
        end
    
        for b in from_branches
            
            if !haskey(Flows, b)
                # Maak een nieuwe lege lijst voor de branch als deze nog niet bestaat
                Flows[b] = []
            end
            # Voeg de power flow voor dit uur toe aan de lijst van de generator
            if nodal_result["$i"]["objective"] !== nothing
                push!(Flows[b], nodal_result["$i"]["solution"]["branch"]["$b"]["pf"]*100)
            else
                push!(Flows[b],0)
            end
        end
        for b in to_branches
            
            if !haskey(Flows, b)
                # Maak een nieuwe lege lijst voor de branch als deze nog niet bestaat
                Flows[b] = []
            end
            # Voeg de power flow voor dit uur toe aan de lijst van de generator
            if nodal_result["$i"]["objective"] !== nothing
                push!(Flows[b], nodal_result["$i"]["solution"]["branch"]["$b"]["pt"]*100)
            else
                push!(Flows[b],0)
            end
        end
    end

    total_flows_per_timestep = zeros(number_of_hours)
    total_conv_per_timestep = zeros(number_of_hours)
    P3 = Plots.plot()
    for b in keys(Flows)
        total_flows_per_timestep .+= Flows[b]
        plot!(Flows[b],label = "Branch $b")
    end
    for c in keys(Conv_Flows)
        total_conv_per_timestep .+= Conv_Flows[c]
        plot!(Conv_Flows[c],label = "Converter $c")
    end
    title!("Active power withdrawn at $n ($zone)")
    xlabel!("Time [h]")
    ylabel!("Power [MW]")
    display(P3)
    # Haal de totale productie per tijdstap op in een gesorteerde vector
    if length(gen_list) == 0
        total_production_vector = zeros(length(nodal_result))
    else
        sorted_keys = sort(collect(keys(total_production_per_time)))
        total_production_vector = [total_production_per_time[t] for t in sorted_keys]
    end
    total_flows_per_timestep = total_flows_per_timestep + total_conv_per_timestep - total_production_vector
    P4 = Plots.plot()
    plot!(total_flows_per_timestep, label= "Total branch flow")
    title!("Sum of the active power flows at bus $n. (= Gen - Load)")
    xlabel!("Time [h]")
    ylabel!("Power [MW]")
    display(P4)


end

function nodal_price(hour_range)
    Nodal_price = Dict()
    p_minimum = 0
    p_maximum = 0
    
    for bus in keys(nodal_input["bus"])
        price_per_node = Float64[]
        for i in hour_range
            price =nodal_result["$i"]["solution"]["bus"]["$bus"]["lam_kcl_r"]
            push!(price_per_node,price)
            if price >p_maximum
                p_maximum = price
            elseif price <p_minimum
                p_minimum = price
            end

        end
        Nodal_price[parse(Int,bus)] = mean(price_per_node)
    end

    for bus in keys(nodal_input["busdc"])
        price_per_node = Float64[]
        for i in hour_range
            price =nodal_result["$i"]["solution"]["busdc"]["$bus"]["lam_kcl_r"]
            push!(price_per_node,price)
            if price >p_maximum
                p_maximum = price
            elseif price <p_minimum
                p_minimum = price
            end

        end
        Nodal_price[parse(Int,bus)] = mean(price_per_node)
    end

    return Nodal_price,p_minimum,p_maximum

end



using PlotlyJS, ColorSchemes, DataFrames
function plot_nodes_with_prices(
    ;data = zone_grid, 
    file_name = joinpath("results", join(["grid_nodalprice.pdf"])),
    plot_node_numbers_ac = false,
    plot_node_numbers_dc = false
)

    prices,p_min,p_max = nodal_price([4012])
    # Data containers voor nodes
    nodes = []
    lat = []
    lon = []
    type = []
    
    # Verzamel de AC-busgegevens
    for (b_id, b) in data["bus"]
        push!(nodes, b["index"])
        push!(lat, b["lat"])
        push!(lon, b["lon"])
        push!(type, 0)  # AC nodes
    end
    
    # Voeg DC-busgegevens toe
    for (b_id, b) in data["busdc"]
        push!(nodes, b["index"])
        push!(lat, b["lat"])
        push!(lon, b["lon"])
        push!(type, 1)  # DC nodes
    end

    # Maak een dataframe met node-informatie
    dict_nodes = DataFrame("node" => nodes, "lat" => lat, "lon" => lon, "type" => type)
    B = dict_nodes

    # Bereken kleuren op basis van prijzen
    node_colors = [
        get(prices, row[:node], 0.0)  # Haal prijs op, standaard 0.0 indien niet aanwezig
        for row in eachrow(dict_nodes)]
    
    # Normaliseer de kleuren naar [0, 1] voor de colormap

    norm_prices = (node_colors .- p_min) ./ (p_max - p_min + 1e-10)  # Vermijd deling door nul

    # Plot nodes
    
    traces = [PlotlyJS.scattergeo()]
    for (i, row) in enumerate(eachrow(dict_nodes))
        color = ColorSchemes.get(ColorSchemes.jet, norm_prices[i])  # Kleur op basis van prijs
        marker = PlotlyJS.attr(size = 3.5, color = color)
        
        trace = PlotlyJS.scattergeo(mode = "markers",
            lat = [row[:lat]],
            lon = [row[:lon]],
            marker = marker)
        push!(traces, trace)
    end
    traces = traces[2:end]
    
    #return traces,B
    # Maak layout
    geo = PlotlyJS.attr(fitbounds="locations")
    layout = PlotlyJS.Layout(geo = geo, geo_resolution = 50, width = 1000, height = 1100,
    showlegend = true,
    margin=PlotlyJS.attr(l=0, r=0, t=0, b=0))

    # Plot en save

    fig = PlotlyJS.plot(traces, layout)
    PlotlyJS.savefig(fig, file_name)

end

