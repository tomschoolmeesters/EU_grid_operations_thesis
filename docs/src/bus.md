# Analyse buses

This section provides tools to analyze individual buses in the power grid, including their demand, generation, power flows, and nodal prices over time.

## Analyse\_bus

Analyzes the power flows, demand, generation, and converter connections for a given bus (AC or DC) over a simulation period.

- Arguments
    - `n`: ID of the bus (AC or DC) to be analyzed.
    - `nodal_input`: Dictionary containing input data for the nodal model.
    - `nodal_result`: Dictionary containing simulation results for the nodal model.
    - `timeseries_data`: Dictionary containing time series data, including demand profiles.
    - `number_of_hours`: Total number of hours to analyze. Make sure this does not exceeds the length of the nodal_result data.
    - `start_hour`: Starting hour of the analysis period.

- Output
    - Prints the bus details
    - Displays plots for:
        - Demand vs actual demand (AC bus only)
        - Generator output (AC bus only)
        - Branch and converter power flows
        - Net power balance (generation - withdrawals)

```julia
function Analyse_bus(n,nodal_input,nodal_result,timeseries_data,number_of_hours,start_hour=1)
```
---

##  nodal\_price

Computes the average nodal electricity prices for all AC and DC buses over a specified range of hours, and identifies the minimum and maximum nodal prices observed.

- Arguments
    - `nodal_result`: Dictionary containing the simulation results.
    - `nodal_input`: Dictionary containing input data.
    - `hour_range`: Iterable of integers specifying the hours/time steps over which to compute average prices.

- Output
    - Returns a tuple `(Nodal_price, p_minimum, p_maximum)` where:
        - `Nodal_price`: Dictionary mapping bus IDs (as integers) to their average nodal price over the specified time range.
        - `p_minimum`: The minimum nodal price observed across all buses and hours.
        - `p_maximum`: The maximum nodal price observed across all buses and hours.

- Notes
    - Nodal prices are derived as the negative of the Lagrange multipliers (`lam_kcl_r`) from the power balance constraints.
    - Supports both AC and DC buses.

```julia
function nodal_price(nodal_result, nodal_input,hour_range)
```
---

## plot\_nodes\_with\_prices

Plots a geographical map of grid nodes colored by their nodal prices for a given hour.

- Arguments
    - `data`: Dictionary containing input data, including AC and DC buses with their metadata (location, index).
    - `nodal_result`: Results dictionary containing nodal prices and solution data.
    - `hour_range`: Range of hours to consider for nodal price calculation e.g. [6], 1:20
    - `file_name`: Path to save the main node price plot (SVG format).
    - `legend_file_name`: Path to save the color scale legend (SVG format).

- Output
    - Saves a colored map of nodes based on nodal prices to `file_name`.
    - Saves a separate color scale legend to `legend_file_name`.

- Notes
    - Clamps prices between -50 and 300 €/MWh.
    - Normalizes nodal prices to a 0-1 scale to map colors from the 'jet' colormap.

```julia
function plot_nodes_with_prices(data,nodal_result,hour_range; file_name, legend_file_name)
```