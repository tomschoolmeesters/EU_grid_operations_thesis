# Analyse loading

#### Analyse\_load

Calculates the total electricity demand (in MWh) over a given range of hours.

-  Arguments
    - `hour_range`: A range of hours (e.g. `1:8760`) to analyze demand for.
    - `nodal_input`: Dictionary with static load properties (`pmax`, `zone`).
    - `nodal_result`: Time-indexed dictionary with optimization results.
    - `timeseries_data`: Contains `["demand"]` per zone.

- Output
    -  Prints the total load in the given time window (in MWh), rounded to 2 decimal places.

- Description
    - Iterates through all loads defined in the `nodal_input` dictionary.
    - Uses time-varying demand scaling factors from `timeseries_data["demand"]` per zone.
    - Scales by load nominal capacity (`pmax`) and demand factor, and converts to MWh.

```julia
function Analyse_load(hour_range,nodal_input,nodal_result,timeseries_data)
```

#### load\_shedding

Identifies and reports instances of load shedding and demand-side flexibility (e.g. curtailment or reduction)
during a specified set of hours.

- Arguments
    - `hour_range`: A range of hours to inspect (e.g. `200:300`).
    - `nodal_input`: Dictionary containing input data for the nodal model.
    - `nodal_result`: Dictionary containing simulation results for the nodal model.

- Output
    - Prints:
        - All instances of load curtailment (`pcurt`) and reduction (`pred`).
        - All load shedding events due to dispatch of `VOLL` generators (including power and location).

- Description
    - First loop: Iterates over `nodal_result` to detect:
        - Curtailment (`pcurt > 0`) per load → prints the load bus and hour.
        - Demand reduction (`pred > 0`) per load → prints the load bus and hour.
    - Second loop: Checks all generators for type `"VOLL"` (Value of Lost Load), which are used to model load shedding:
        - If any `"VOLL"` generator has non-zero output, it is interpreted as a load shedding event and reported.

"""

```julia
function load_shedding(hour_range,nodal_input,nodal_result)
```

### Line\_loading

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

- Output
    - Displays a boxplot of line loading (MW) across hours.
    - Prints thermal limits for each line in MW.

```julia
function Line_loading(lines,nodal_input,nodal_result)
```

#### mean\_Loadfactor

Compute the average load factor for all transmission lines (AC and DC) over a specified time range.

- Arguments
    - `nodal_input`: Dictionary containing input data for the nodal model.
    - `hour_range`: Range of hours to analyze (e.g., `1:24`).

- Output
    - `Loading`: A dictionary mapping line IDs (as integers) to their average (AC) or maximum (DC) load factor over the time range.

- Description
    - For **AC lines**, the function calculates the hourly load factor as the **minimum** between the thermal and electrical load limits. Then it returns the **mean** load factor across all hours.
    - For **2-winding transformers**, the load factor is set to 0 across all hours (ignored in loading analysis).
    - For **DC lines**, the function calculates the hourly load factor based on the thermal rating and returns the **maximum** load factor over all hours.

- Notes
    - All power values are converted to MW (×100) from p.u. input.
    - Line IDs are parsed as integers for dictionary keys to allow uniform identification.

```julia
function mean_Loadfactor(nodal_input,hour_range)
```

#### hourly\_Loadfactor

Compute the hourly load factors for all AC and DC transmission lines over a given time range.

- Arguments
    - `nodal_input::Dict`: Dictionary containing input data for branches (`branch`, `branchdc`) with their ratings and parameters.
    - `hour_range::UnitRange{Int}`: Time steps (e.g. 1:24) for which the load factor is to be calculated.

- Output
    - `(Loading_AC, Loading_DC)`: Tuple of two dictionaries:
        - `Loading_AC::Dict{Int, Vector{Float64}}`: Hourly load factors for AC lines, keyed by line ID.
        - `Loading_DC::Dict{Int, Vector{Float64}}`: Hourly load factors for DC lines, keyed by line ID.

- Description
    - For AC lines, both thermal and electrical limits are considered:
        - Load factor per hour is taken as the maximum of thermal and electrical load factor.
    - For DC lines, only the thermal capacity is used.

```julia
function hourly_Loadfactor(nodal_input, hour_range)
```

#### plot\_loaded\_grid

Visualize the electrical grid using geospatial plots with optional coloring based on line loading.

- Arguments
    - `data`: A dictionary containing bus, busdc, branch, and branchdc data (typically `nodal_input`).
    - `file_name::String`: Output filename to save the plot.
    - `hour_range`: The list of time steps over which to average line loadings (passed to `mean_Loadfactor`).
    - `ac_only::Bool = false`: If `true`, plot only AC branches and AC buses.

- Output
    - Saves and displays a PlotlyJS `.html` map showing the grid topology with optional loading colors.

- Dependencies
    - Relies on the external function `mean_Loadfactor(...)` to compute line loadings.

```julia
function plot_loaded_grid(data, file_name, hour_range;ac_only = false)
```

