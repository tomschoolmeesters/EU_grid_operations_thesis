# Congestion

## where\_congestion

Identify lines (AC and DC) that are frequently congested. Based on thermal rating.

- Arguments
    - `nodal_input`: Contains line data (ratings) under `branch` (AC) and `branchdc` (DC).
    - `nodal_result`: Contains power flow results per hour for each line.

- Output
    - `congested_lines`: List of line IDs (as strings) that are congested in ≥50% of the hours.

- Congestion Criterion
    - A line is considered congested if its power flow exceeds 95% of its thermal rating in at least 50% of the hours.

```julia
function where_congestion(nodal_input, nodal_result)
```
---

## where\_congestion\_electrical

Identify AC lines that are electrically congested.

- Arguments
    - `nodal_input`: Contains AC branch parameters like `angmax` and `br_x`.
    - `nodal_result`: Contains hourly simulation results, including line flows.

- Output
    - `congested_lines::Vector{String}`: List of AC line IDs (as strings) where electrical congestion occurs in ≥50% of the hours.

- Congestion Criterion
    - A line is considered electrically congested if the absolute flow exceeds 95% of its electrical transfer limit in at least 50% of the hours.
    - The electrical limit is computed as:
        ```
        (angmax / br_x) * 100  # MW
        ```

```julia
function where_congestion_electrical(nodal_input,nodal_result)
```
---

## Congestion\_index

Calculates the Congestion Index for a simulation period based on the dual variables. This metric gives an indication 
of congestion levels in the network, where higher values imply more uneven marginal prices (i.e., congestion).

- Arguments
    - `result::Dict`: A dictionary containing optimization results for each hour, including dual variables at buses and DC buses.
    - `number_of_hours::Int`: The number of hours to compute the congestion index for (default is 15).

- Output
    - `Congestion_index_values::Dict{Int, Float64}`: A dictionary where the keys are the hour indices, and the values 
    are the computed congestion index `i_c` for each hour.

- Description
    - Calculates the **Congestion Index** as:
        
        i_c = sum(abs.(λ .- λ̄)) / (N * abs(λ̄))
        
- Notes
    - Skips any hour where the optimization result is infeasible (`objective === nothing`).

```julia
function Congestion_index(result,number_of_hours)
```
---

## overall\_congestion\_index

Computes the overall (annual) congestion index across the entire network by aggregating nodal prices over all simulation hours and nodes in a reduced timeseries horizon.

- Arguments
    - `result::Dict`: Dictionary containing the simulation results for all hours.
    - `factor::Vector{Float64}`: Weighting factor for each hour (e.g., from representative hours or scaling).

-Output
    - `I_c`: A single scalar representing the network-wide congestion index over the entire period.

- Description
    - The congestion index is computed as the normalized mean absolute deviation of nodal prices from the overall average:
    
        I_c = sum(abs.(λ - λ_avg)) / (N * abs(λ_avg))

```julia
function overall_congestion_index(result,factor)
```
---

## plot\_Congestion\_index

Plots the congestion index over a specified number of hours based on optimization results.

- Arguments
    - `result::Dict`: Dictionary containing simulation results for each hour.
    - `number_of_hours::Int`: Total number of simulation hours to include in the congestion index plot.

- Output
    - No return value. Adds the congestion index time series to a plot.

```julia
function plot_Congestion_index(result, number_of_hours)
```

# Saturation

## Saturation\_index

Computes the Saturation Index for each simulation hour, which indicates how fully the transmission lines are being utilized relative to their thermal limits.

- Arguments
    - `result::Dict`: Dictionary containing simulation results per hour, including power flow through branches.
    - `input::Dict`: Network input data

- Output
    - `Saturation_index_values::Dict`: A dictionary mapping each hour to its corresponding saturation index value.

- Description
    - Computes the Saturation Index as:  
        
        Saturation Index = sum(|P_flow|)/sum(P_rated)

```julia
function Saturation_index(result,input)
```
---

## plot\_Saturation\_index

Generates a plot of the saturation index over time based on the simulation results and input data.

- Arguments
    - `result::Dict`: Simulation results containing branch flow data.
    - `input::Dict`: Static input data including branch ratings.

- Output
    - Produces a plot of the saturation index values sorted by time step, with the y-axis labeled "Saturation Index Value".

```julia
function plot_Saturation_index(result,input)
```