# Analyse generators

## Analyse\_generator

Analyzes the generation profile and curtailment behavior of a specified generator over a selected time window within a planning year. It visualizes the power output, highlights infeasible simulation periods, and (for RES generators) computes and plots curtailment metrics.

- Arguments
    - `g`: Index or identifier of the generator to be analyzed.
    - `start_hour`: The starting hour of the analysis period within the year (e.g. 1 for Jan 1st 00:00).
    - `number_of_hours`: Total number of hours to analyze. Make sure this does not exceeds the length of the nodal_result data.
    - `nodal_input`: A dictionary containing input data for the nodal model, including generator properties.
    - `nodal_result`: A dictionary containing results from the nodal analysis, including power generation solutions.
    - `timeseries_data`: Dictionary containing time series data, including demand profiles.

- Output
    - No return value.
    - Displays:
        - Power production profile plot (with infeasible hours highlighted).
        - For RES types ("Offshore Wind", "Onshore Wind", "Solar PV"): a curtailment percentage plot.

- Dependencies
    - Relies on the external function `RES_curtailment_WO(...)` to compute curtailment for RES types.
    This fuction is defined in get_grid_indices.jl

```julia
function Analyse_generator(g,start_hour,number_of_hours,nodal_input,nodal_result,timeseries_data)
```   
---

## Analyse\_generation\_types

Analyse and visualize electricity generation by generator type and storage over a specified range of hours.

- Arguments
    - `hour_range`: Range of hours to analyze (e.g., `1:24`).
    - `start_hour`: The first hour in the full simulation (used to adjust indices).
    - `nodal_input`: Dictionary containing input data for the nodal model.
    - `nodal_result`: Dictionary containing simulation results for the nodal model.

- Description
    This function performs the following:
    1. Aggregates total generation by generator type and storage.
    2. Generates a pie chart showing the contribution of each type.
    3. Builds a time series of generation and load for the selected types.
    4. Asks the user which types they wish to plot.
    5. Plots generation vs. load over time for the selected types.

- Note
    - Be careful when using a result based on the reduced timeseries. If you use a reduced timeseries and want to plot the pie diagram for a full year, you need to adjust the values using the corresponding factor. (not implemented here yet)

```julia
function Analyse_generation_types(hour_range,start_hour,nodal_input,nodal_result)
```
---

## Capacity\_installed

Compute the total installed generation capacity per generator type.

- Arguments
    - `nodal_input`: Dictionary containing input data for the nodal model.

- Output
    - A dictionary where each key is a generator type (`type_tyndp`) and the value is the total installed capacity in MW.

- Description
    This function loops through the `nodal_input["gen"]` structure to:
    1. Identify all unique generator types based on `type_tyndp`.
    2. Sum the maximum generation capacity (`pmax`) for each type.

```julia
function Capacity_installed(nodal_input)
```
---

## RES\_curtailment\_WO

Computes the hourly curtailment profile for a specific renewable energy generator (Solar PV, Offshore Wind, or Onshore Wind) over a simulation period.

- Arguments
    - `g::Int`: Generator index (as used in the input and result dictionaries).
    - `gen_type::String`: Type of renewable generator (`"Solar PV"`, `"Offshore Wind"`, or `"Onshore Wind"`).
    - `result::Dict`: Dictionary containing simulation results, indexed by hour.
    - `input::Dict`: Static input data describing generator characteristics (e.g., `pmax`, zone).
    - `timeseries::Dict`: Time-series capacity factor data by generator type and zone.
    - `start_hour::Int`: Index of the first hour of the simulation.
    - `number_of_hours::Int`: Total number of hours in the simulation.

- Output
    - Returns a tuple of two arrays:
        - `RES_Curtailment::Vector{Float64}`: Hourly curtailment ratios (0.0 to 1.0).
        - `Uncurtailed::Vector{Float64}`: Hourly uncurtailed energy values (in MW) = maximum available power.

- Description
    - For each hour in the simulation, the function calculates the potential (uncurtailed) and actual (delivered) energy for the specified generator.
    - Curtailment is defined as the relative difference between potential and delivered energy:  
      `curtailment = (uncurtailed - delivered) / uncurtailed`
    - Infeasible hours (where no valid solution exists) are assigned a full curtailment value of `1.0`, and a flat energy profile is preserved.
    - If the generator is not active in a given hour's result, a warning is printed.

```julia
function RES_curtailment_WO(g, gen_type, result, input, timeseries, start_hour, number_of_hours)
```
---

## OFF\_curtailment\_red

Calculates the overall offshore wind curtailment ratio over a reduced set of time steps, 
accounting for hourly weighting factors.

- Arguments
    - `nodal_input::Dict`: Input dictionary containing static generator data, including capacity and type.
    - `nodal_result::Dict`: Dictionary containing simulation results per hour, including generation output.
    - `timeseries_red::Dict`: Reduced time series data for capacity factors by generation type and zone.
    - `factor::Vector{Float64}`: Vector of weighting factors for each hour.
    - `number_of_hours::Int`: Number of hours in the reduced time series.

- Output
    - Returns `OFF_curt::Float64`: The overall offshore wind curtailment ratio (between 0 and 1).

- Description
    - Iterates over all hours and all generators of type "Offshore Wind".
    - For each hour and generator, calculates uncurtailed energy as capacity factor x installed capacity x scaling x weight.
    - Computes curtailment as the relative difference:  
        `(uncurtailed_energy - energy_delivered) / uncurtailed_energy`
    - Returns the yearly curtailment ratio for offshore wind based on the reduced time horizon.

```julia
function OFF_curtailment_red(nodal_input,nodal_result,timeseries_red,factor,number_of_hours)
```
---

## where\_curtailment

Identifies which renewable generators (Solar PV, Onshore Wind, Offshore Wind) experienced significant curtailment
based on a predefined condition. Specifically, it flags generators where the curtailment exceeds 80% for more than 50% of the time.

- Arguments
    - `nodal_input::Dict`: Dictionary containing static generator metadata (e.g., type, location).
    - `nodal_result::Dict`: Dictionary containing simulation results per hour, including generation output.
    - `timeseries_data`: Variable containing time-series data (implicitly used in RES_curtailment_WO).
    - `start_hour::Int`: Represents the starting hour of analysis.

- Output
    - No return value. Prints out information on generators with significant curtailment (especially Offshore Wind).

- Dependencies
    - Relies on the external function `RES_curtailment_WO(...)` to compute curtailment for RES types.
    This fuction is defined in get_grid_indices.jl

```julia
function where_curtailment(nodal_input,nodal_result,timeseries_data; start_hour=1)
```