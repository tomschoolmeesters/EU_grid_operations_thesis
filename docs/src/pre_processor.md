# Pre-Processor

## get\_AC\_branch\_info

Extracts AC branch and bus information from nodal input data.

- Arguments
    - `nodal_input`: Dictionary containing keys "branch", "branchdc", and "convdc". Each key maps to a nested dictionary of indexed branch/converter data.

- Output
    - `AC_branches`: Dictionary mapping (from_bus, to_bus) tuples to a Dict of branch data.
    - `AC_buses`: Sorted vector, unique list of AC bus indices.

- Description
    - Gathers AC and converted DC branch data.
    - Avoids duplicate branches by checking both directions.
    - For DC branches, maps DC buses to AC buses using converter definitions.

```julia
function get_AC_branch_info(nodal_input)
```

---

## get\_susceptance\_matrix

Constructs the AC susceptance (B) matrix based on nodal input.

- Arguments
    - `nodal_input`: Dictionary with branch and converter information (see `get_AC_branch_info`).

- Output
    - `susceptance_matrix`: Sparse symmetric matrix of size n x n where n is the number of AC buses.
    - `bus_index`: Dictionary, Mapping from bus number to matrix index.
    - `AC_branches`: AC branch dictionary, as built by `get_AC_branch_info`.

- Description
    - Builds the B matrix using inverse reactances for off-diagonal entries.
    - Ensures diagonal entries cause each row to sum to zero.
    - Suitable for DC power flow studies or similar.

- Dependencies
    - Calls `get_AC_branch_info` internally.

```julia
function get_susceptance_matrix(nodal_input)
```

---

## get\_inverse\_susceptance\_matrix

Computes the inverse of the susceptance matrix based on nodal input data.

- Arguments
    - `nodal_input`: Dictionary with power system data, used to construct the reduced susceptance matrix.

- Output
    - `inverse_susceptance_matrix`: Dense matrix representing the inverse of the reduced B matrix.
    - `bus_index`: Dictionary, Mapping from bus number to matrix index.
    - `AC_branches`: AC branch dictionary, as built by `get_AC_branch_info`.

- Description
    - This function calls `get_susceptance_matrix` to obtain a B matrix.
    - Uses LU decomposition to compute the matrix inverse efficiently and numerically stably.

```julia
function get_inverse_susceptance_matrix(nodal_input)
```

---

## get\_PTDF\_matrix

Calculates the Power Transfer Distribution Factor (PTDF) matrix from nodal input data.

- Arguments
    - `nodal_input`: Dictionary containing network data including "bus", "branch", and "branchdc".

- Output
    - `PTDF_matrix`: Matrix of size (branches x buses) representing power flow sensitivity.
    - `bus_index`: Dictionary, Mapping from bus number to matrix index.
    - `AC_branches`: AC branch dictionary, as built by `get_AC_branch_info`.

- Description
    - PTDF describes how a power injection at one bus affects the power flow on each branch in the system.
    - Builds the branch-bus incidence matrix (A), diagonal branch reactance matrix (X), and uses inverse B matrix.
    - PTDF = inv(X) * A * B⁻¹, computed efficiently using LU decomposition.

```julia
function get_PTDF_matrix(nodal_input)
```

---

## OFF\_AC\_buses

Extracts all AC buses that are associated with offshore wind infrastructure. These include:
    1. AC buses directly connected to generators labeled as "Offshore Wind".
    2. AC buses connected to offshore DC buses via HVDC converters.

- Arguments
    - `nodal_input`: Dictionary containing the network data structure. Must include:
        - `"gen"`: Dictionary of generators.
        - `"convdc"`: Dictionary of DC/AC converters.
    - `OFF_DC_buses`: Dictionary of offshore DC bus indices (as strings).

- Output
    - `AC_buses`: A vector of unique AC bus indices associated with offshore infrastructure.

```julia
function OFF_AC_buses(nodal_input, OFF_DC_buses)
```

---

## is\_point\_in\_polygon

Determines whether a given point is inside a polygon using the ray casting algorithm.

- Arguments
    - `point`: A tuple `(latitude, longitude)` representing the point to test.
    - `polygon`: A vector of tuples `[(lat1, lon1), (lat2, lon2), ...]` defining the polygon's vertices.
    The polygon is assumed to be closed (first and last point connected).

- Output
    - `inside`: `true` if the point lies inside the polygon, otherwise `false`.

```julia
function is_point_in_polygon(point, polygon)
```
---

## update\_connectionzone

Filters offshore DC buses based on whether they lie within a predefined polygonal connection zone.

- Arguments
    - `OFF_dc_buses`: Dictionary mapping DC bus IDs (as strings) to their properties, including `"lat"` and `"lon"`.

- Output
    - `updated_OFF_dc_buses`: Dictionary with only the DC buses located inside the connection zone polygon.

- Description
    This function defines a polygon (representing the North Sea connection zone) and filters
    the input DC buses, keeping only those whose latitude and longitude fall within the polygon
    (using the `is_point_in_polygon` function, based on the ray casting algorithm).


```julia
function update_connectionzone(OFF_dc_buses)
```

---

## candidate\_lines\_ext

Generates candidate new and existing AC and DC line corridors for reinforcement and expansion based on the input network data and offshore DC buses.

- Arguments
    - `nodal_input`: Dictionary containing network data (buses, branches, converters, etc.).
    - `OFF_dc_buses`: List of offshore DC bus indices.
    - `offshore_hubs` (optional): If true, include specific offshore hubs in the DC buses.

- Output
    - `ne_branch`: Dictionary of new and reinforced AC branches.
    - `ne_branchDC`: Dictionary of new and reinforced DC branches.
    - `AC_new_corridor_idx`: Starting index for new AC corridors.
    - `DC_new_corridor_idx`: Starting index for new DC corridors.

```julia
function candidate_lines_ext(nodal_input, OFF_dc_buses; offshore_hubs=false)
```

**Transmission Candidate Categories and Logic**

The `candidate_lines_ext` function generates four distinct categories of candidate transmission lines to reflect potential reinforcements and expansions of the grid in the North Sea basin:

- **Existing AC Corridors**

These are modeled as reinforcements of the already existing AC lines. The function:
- Identifies all existing AC branches.
- Duplicates each as a new candidate branch with updated transmission ratings:
    - 1.5 GW for regular AC lines.
    - 3 GW if one of the buses connects to an offshore wind farm (offshore AC connection).
- Lines with an unrealistically low rating (`rate_a = 0.01`) are re-evaluated using converter data.

```julia
if exis_branch["rate_a"] != 0.01
    rating_val = (exis_branch["f_bus"] >= 50000 || exis_branch["t_bus"] >= 50000) ? 30 : 15
else
    # Rating derived from converter info
    rating_val = get_clustering_rating(corr_DC, relocation_dict["$zone_bus"]) / 100
end
```

- **New AC corridors**

New AC connections are created between unconnected AC buses that:
    - Are within 100 km of each other.
    - Do not connect the UK to non-UK zones (i.e., no UK ↔ EU AC corridors).
    - Use a default rating of 1 GW, unless connected to an offshore wind farm, in which case a rating matching the cluster capacity is applied.

```julia
if _EUGO.latlon2distance(nodal_input, Int(bus1), Int(bus2)) <= 100 &&
    !(zone1 == "UK" && zone2 != "UK") && !(zone2 == "UK" && zone1 != "UK")
        push!(CL_newAC, (bus1, bus2))
end
```

- **Existing DC corridors**

All built DC lines are duplicated and reinforced with a 2 GW transmission rating.

```julia
exis_branch["rateA"] = 20
exis_branch["rateB"] = 20
exis_branch["rateC"] = 20
```

- **New Offshore DC corridors**

New candidate DC lines are created only between offshore DC buses (clusters or hubs). These represent inter-cluster HVDC transmission corridors and are:
    - Rated at 4 GW, based on the 2 GW TenneT program doubled for multi-terminal flexibility.
    - Unrestricted by distance but implicitly constrained by the offshore zoning logic in `update_connectionzone`.
```julia
new_branchdc["rateA"] = 40
new_branchdc["rateB"] = 40
new_branchdc["rateC"] = 40
```
---

## update\_cost\_data

Calculates construction costs for new and reinforced AC and DC branches based on their ratings, distances, and financial assumptions.

- Arguments
    - `ne_branch`: Dictionary of AC branches to update cost data for.
    - `ne_branchDC`: Dictionary of DC branches to update cost data for.
    - `nodal_input`: Network data used to calculate distances.

- Output
    - Updated `ne_branch` and `ne_branchDC` dictionaries with cost fields added.

```julia
function update_cost_data(ne_branch, ne_branchDC, nodal_input)
```
---

## get\_dual\_branch

Extracts the absolute difference of dual variables (λ_KCL) at both ends of each AC branch over multiple hours.

- Arguments
    - `AC_branches`: Dictionary of AC branch data, indexed by (from_bus, to_bus), each with `"nr"`, `"f_bus"`, `"t_bus"` keys.
    - `nodal_result`: Result dictionary containing dual values (`lam_kcl_r`) per bus and time step.
    - `number_of_hours`: Number of hours over which to extract the values.
    - `start_hour`: The starting hour index in `nodal_result`.

- Returns
    - `Lambda_matrix`: Matrix of size (branches x number_of_hours), where each element is the absolute difference in dual values at both ends of a branch.

- Description
    - For each branch and each time step, the λ (dual variable of KCL) at the `from_bus` and `to_bus` is retrieved.
    - The absolute difference is stored, giving insight into shadow prices or congestion.
    - If the bus is not found in the results, a default value of 0 is used.

```julia
function get_dual_branch(AC_branches, nodal_result, number_of_hours, start_hour)
```
---

## winsorize\_matrix!

Applies Winsorization to a matrix, limiting its values within specified lower and upper percentiles.

- Arguments
    - `matrix`: The input matrix to modify in place.
    - `lower_pct`: Lower percentile cutoff (e.g., 0.01 for 1st percentile).
    - `upper_pct`: Upper percentile cutoff (e.g., 0.99 for 99th percentile).

- Output
    - `Nothing`: Modifies `matrix` in place.

- Description
    - This technique reduces the influence of extreme outliers by capping all values below the lower percentile and above the upper percentile.

```julia
function winsorize_matrix!(matrix, lower_pct, upper_pct)
```

---

## PTDF\_analysis\_full

Performs a full PTDF-based sensitivity and clustering analysis of candidate reinforcements.

- Arguments
    - `nodal_input`: Input network data containing buses, branches, branchDCs, and converters.
    - `number_of_hours`: Number of time steps (e.g., hourly results) for which the dual values are available.
    - `ne_branch`: Dictionary of candidate AC branches (indexed with keys as IDs).
    - `ne_branchDC`: Dictionary of candidate DC branches (indexed with keys as IDs).

- Returns
    - `Impact_matrix`: List of power flow impact matrices per hour (size: n_branches x n_selected_candidates).
    - `selected_indices_AC`: Selected representative AC reinforcement indices (original indices from `ne_branch`).
    - `selected_indices_DC`: Selected representative DC reinforcement indices (original indices from `ne_branchDC`).
    - `dc_to_ac_map`: Mapping from DC bus IDs to their corresponding AC buses (used in PTDF projection).

- Description
    - Computes the Power Transfer Distribution Factor (PTDF) matrix.
    - Constructs a Power Flow sensitivity matrix based on reinforcement impact.
    - Applies PCA and clustering (MiniBatchKMeans) to reduce the number of candidate reinforcements.
    - Computes the impact of reinforcements on branch shadow prices (dual KCL variables).
    - Applies winsorization to stabilize dual values before computing final impact matrices.

- Notes
    - Assumes candidate AC branches are indexed starting at 200000, and DC branches at 500000.

```julia
function PTDF_analysis_full(nodal_input, nodal_result, number_of_hours, ne_branch, ne_branchDC)
```
---

## Potential\_investment\_benefit

Compute the potential benefit of a new investment (AC or DC link) based on nodal price differences
and voltage angle differences over a given time horizon.

- Arguments
    - `idx`: Branch index (AC if < 500000, otherwise DC).
    - `ne_branch`: Dictionary containing AC branch data keyed by index.
    - `ne_branchDC`: Dictionary containing DC branch data keyed by index.
    - `number_of_hours`: Total number of hours in the analysis period.
    - `start_hour`: Start hour index.
    - `nodal_result`: Nested dictionary containing hourly nodal simulation results.
    - `factor`: Vector of weighting factors per hour.

- Output
    - The total potential investment benefit over the analyzed period.

- Notes
    - AC branches use angle differences and reactance.
    - DC branches use fixed capacity and lambda differences.
    - Angles are converted from degrees to radians for AC computation.

```julia
function Potential_investment_benefit(idx, ne_branch, ne_branchDC, number_of_hours, start_hour, nodal_result, factor)
```
---

## delta\_lambda

Computes the weighted absolute difference in nodal dual variables (λ) between the 'from' and 'to' buses
of a candidate reinforcement line (AC or DC) over a given time horizon.

- Arguments
    - `idx`: Unique identifier for the candidate line (AC < 500000, DC ≥ 500000).
    - `number_of_hours`: Number of hours to evaluate.
    - `start_hour`: Start hour (1-based) of the analysis period.
    - `nodal_result`: Dictionary of OPF results per hour, containing nodal duals.
    - `dc_to_ac_map`: Mapping from DC buses to equivalent AC buses.
    - `ne_branch`: Dictionary of candidate AC branches.
    - `ne_branchDC`: Dictionary of candidate DC branches.
    - `factor`: Hourly weight vector used to scale lambda differences.

- Output
    - `delta_lambda`: Weighted sum of absolute λ-differences over time.

```julia
function delta_lambda(idx, number_of_hours, start_hour, nodal_result, dc_to_ac_map, ne_branch, ne_branchDC, factor)
```
---

## pre\_processor

Processes AC and DC transmission line candidates for investment analysis in a transmission network expansion planning (TNEP) context. Computes impact, potential benefits, lambda differences, costs, and selects the top-performing lines.

- Arguments
    - `nodal_input`: Input data for the power system (network topology, etc.)
    - `nodal_result`: Simulation results per timestep
    - `Impact_matrix`: Impact matrices per timestep
    - `selected_indices_AC`: Indices of candidate AC lines
    - `selected_indices_DC`: Indices of candidate DC lines
    - `number_of_hours`: Number of simulated hours
    - `factor`: Weight per hour (e.g., timestep scaling)
    - `AC_new_corridor_idx`: Threshold index separating old and new AC corridors
    - `ne_branch`: Dictionary of new AC candidate branches
    - `ne_branchDC`: Dictionary of new DC candidate branches
    - `start_hour`: Start hour index for simulation horizon

- Output
    - `zone_grid_final`: Updated grid dictionary containing selected AC/DC candidate lines

- Selection details
   - The function selects the top 5.5% of AC candidates and top 16% of DC candidates based on their performance metrics (impact, benefit-to-cost ratio, lambda differences).
    - In addition, a random subset of 10 AC candidates and 5 DC candidates is included for comparative analysis and robustness checks.
    - This combination of deterministic and random selection helps balance exploitation of best candidates with exploration of alternatives.

- Notes
    - Random selection of additional lines is included for comparison/testing
    - Only top-performing lines are added to the final network dictionary
    - Selection criteria consider multiple performance dimensions: impact on network, benefit-to-cost ratios, and lambda differences.
    - The function is optimized for large-scale TNEP simulations with hourly time resolution.

```julia
function pre_processor(nodal_input, nodal_result, Impact_matrix, selected_indices_AC, selected_indices_DC,
                       number_of_hours, factor, AC_new_corridor_idx, ne_branch, ne_branchDC; start_hour=1)
```

