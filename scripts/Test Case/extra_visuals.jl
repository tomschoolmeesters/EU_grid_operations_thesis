
# Plots a geographical map of grid nodes colored by their nodal prices for a given hour.
    hour_range = 12:12
    file_name = joinpath(output_dir_fig, "plot_nodal_prices.svg")
    legend_file_name = joinpath(output_dir_fig, "legend_nodal_prices.svg")
    _EUGO.plot_nodes_with_prices(nodal_input,nodal_result,hour_range; file_name, legend_file_name)

# Analyse and visualize electricity generation by generator type and storage over a specified range of hours.
    hour_range = 1:15
    start_hour = 1
    _EUGO.Analyse_generation_types(hour_range,start_hour,nodal_input,nodal_result,output_dir_fig)

# Plots the congestion index over a specified number of hours based on optimization results.
    number_of_hours = 15
    plot_filename = joinpath(output_dir_fig, "congestion_index.svg")
    _EUGO.plot_Congestion_index(nodal_result, number_of_hours, plot_filename)

# Generates a plot of the saturation index over time based on the simulation results and input data.
    plot_filename = joinpath(output_dir_fig, "saturation_index.svg")
    _EUGO.plot_Saturation_index(nodal_result,nodal_input, plot_filename)

# Visualize the electrical grid using geospatial plots with optional coloring based on line loading.
    plot_filename = joinpath(output_dir_fig, "plot_loaded_grid.svg")
    legend_file_name = joinpath(output_dir_fig, "legend_loaded_grid.svg")
    hour_range = 1:1
    _EUGO.plot_loaded_grid(nodal_input, nodal_result, plot_filename, legend_file_name, hour_range)


# Analyzes the power flows, demand, generation, and converter connections for a given bus (AC or DC) over a simulation period.
    number_of_hours = 15
    start_hour = 1
    n = 600 # Example bus index
    _EUGO.Analyse_bus(n,nodal_input,nodal_result,timeseries_data_reduced,number_of_hours,start_hour)

# Analyzes a power branch (AC or DC) from a power system model over a given time window.
    b = 8596 # Example branch index
    start_hour = 1
    _EUGO.Analyse_branch(b,nodal_input,nodal_result,start_hour)

# Analyzes the generation profile and curtailment behavior of a specified generator
    start_hour = 1
    number_of_hours = 15
    g = 2366 # Example generator index
    _EUGO.Analyse_generator(g,start_hour,number_of_hours,nodal_input,nodal_result,timeseries_data_reduced)

# Calculates the total electricity demand (in MWh) over a given range of hours.
    hour_range = 1:15
    _EUGO.Analyse_load(hour_range,nodal_input,nodal_result,timeseries_data_reduced,factor)

# Compute the total installed generation capacity per generator type.
    _EUGO.Capacity_installed(nodal_input)

# Identifies which renewable generators (Solar PV, Onshore Wind, Offshore Wind) experienced significant curtailment
    number_of_hours = 15
    _EUGO.where_curtailment(nodal_input,nodal_result,timeseries_data_reduced,number_of_hours)

# Identifies and reports instances of load shedding and demand-side flexibility (e.g. curtailment or reduction)
    _EUGO.where_congestion(nodal_input, nodal_result)

# Identify AC lines that are electrically congested.
    _EUGO.where_congestion_electrical(nodal_input,nodal_result)

# Calculates the Congestion Index for a simulation period based on the dual variables. This metric gives an indication of congestion levels in the network, where higher values imply more uneven marginal prices (i.e., congestion).
    number_of_hours = 15
    _EUGO.Congestion_index(nodal_result,number_of_hours)

# Computes the overall (annual) congestion index across the entire network by aggregating nodal prices over all simulation hours and nodes in a reduced timeseries horizon.
    _EUGO.overall_congestion_index(nodal_result,factor)

# Computes the Saturation Index for each simulation hour, which indicates how fully the transmission lines are being utilized relative to their thermal limits.
    _EUGO.Saturation_index(nodal_result,nodal_input)

# Identifies and reports instances of load shedding and demand-side flexibility (e.g. curtailment or reduction) during a specified set of hours.
    hour_range = 1:15
    _EUGO.load_shedding(hour_range,nodal_input,nodal_result)

# Visualize and analyze power flows through a set of transmission lines over all simulated hours.
    lines = ["306","307"]
    _EUGO.Line_loading(lines,nodal_input,nodal_result)