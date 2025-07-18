
# Loading and Preprocessing Data

## scale\_generation24!

Scales the maximum generation capacities ("pmax") of generators in the grid model based on
capacity data from TYNDP scenarios for a given scenario, year, climate year, and geographic zones.

- Arguments
    - `tyndp_capacity`: Capacity data from TYNDP with installed capacities by scenario, year, type, climate year, and country.
    - `grid_data`: Dictionary containing grid information, including generator data and zonal generation capacities.
    - `scenario_id`: Scenario identifier string combining scenario code and year (e.g., "DE2024").
    - `climate_year`: Climate year to consider for capacity adjustments.
    - `zone_mapping`: Maps grid zones to country codes (used to find country names).
    - `country_names`: Maps country codes to full country names (used for lookups in capacity data).

- Keyword Arguments
    - `ns_hub_cap` (default = nothing): Optional capacity override for the "NSEH" offshore wind hub zone.
    - `exclude_offshore_wind` (default = false): If true, offshore wind generators are excluded from scaling.

- Output
    - Modifies `grid_data["gen"]` in-place by adjusting each generator's `pmax` attribute according to the ratio of 
    TYNDP capacities to original capacities.

- Dependencies
    - Calls the external function `get_generation_capacity_2024_v2(...)` to fetch zonal capacity from TYNDP data.
    - Expects `grid_data` structure to have keys "gen" and "zonal_generation_capacity" with proper data formats.

- Notes
    - The scaling factor is the ratio of TYNDP zonal capacity (normalized by baseMVA) over existing zonal capacity.
    - Supports partial scaling by excluding offshore wind generators if specified.
    - Special handling for the NSEH zone if `ns_hub_cap` is given.

- Description
    This function iterates over all generators in the grid, determines their TYNDP type and zone, retrieves
    the corresponding installed capacity from the TYNDP dataset for the specified scenario and year, and
    scales the generator's maximum capacity (`pmax`) accordingly. The goal is to update the model’s generation
    capacity to reflect the TYNDP projections while maintaining zone-specific capacity consistency.

```julia
function scale_generation24!(tyndp_capacity, grid_data, scenario_id, climate_year, zone_mapping,country_names; ns_hub_cap = nothing, exclude_offshore_wind = false)
```
---

## get\_xb\_flows\_v2

Computes cross-border power flows for each border defined in a zonal grid, based on zonal simulation results and input network data.

- Arguments
    - `zone_grid`: Contains information on zones and borders (including zone names and border connections).
    - `zonal_result`: Dictionary mapping each timestep (as a string key) to simulation results (including branch flows).
    - `zonal_input`: Input data structure containing network elements like branches with flow directions.
    - `zone_mapping`: Maps zone names in the grid model to TYNDP zone codes (e.g., `"DE00"`).

- Output
    - `borders`: Dictionary with keys as border names and values as a dictionary containing a `flow` matrix of shape (1, n_timesteps),
    where each value represents the net flow across that border at a given timestep:
        - Positive = export from the first zone to the second (e.g., from DE to AT)
        - Negative = import into the first zone from the second

- Differences from `get_xb_flows`
    - Supports multiple zones per border.
    - Sums bidirectional flows.
    - Simplified result access (no "solution" nesting).
```julia
function get_xb_flows_v2(zone_grid, zonal_result, zonal_input, zone_mapping)
```
---

## get\_grid\_data

Returns the appropriate grid data based on the TYNDP version and modeling detail.

- Arguments
    - `tyndp_version`: Year of the TYNDP dataset ("2020" or "2024").
    - `scenario`: Scenario name or identifier (e.g. "Distributed Energy").
    - `Year`: Target year of the analysis (e.g. "2030").
    - `climate_year`: Climate year (e.g. "2032").
    - `z_or_n`: Either `"zonal"` or `"nodal"` (only relevant for TYNDP 2024).

- Output
    - Returns a dictionary containing grid data for the specified configuration.

- Notes
    - `get_grid_data` dispatches to:
    - `get_grid_data_2020(...)` for TYNDP 2020 (zonal only),
    - `get_grid_data_2024_zonal(...)` for TYNDP 2024 zonal data,
    - `get_grid_data_2024_nodal(...)` for TYNDP 2024 nodal data.
    - Raises an error for unsupported configurations.

- Change summary
    - Function updated to distinguish between TYNDP 2020 and 2024, and between **zonal** and **nodal** data for 2024.

```julia
function get_grid_data(tyndp_version, scenario, Year, climate_year, z_or_n)    
```
---

## get\_grid\_data\_2024\_zonal

Load and process zonal grid data for the 2024 TYNDP (Ten-Year Network Development Plan) scenario.

-  Arguments
    - `scenario`: The scenario name (e.g., "NationalTrends", "DistributedEnergy").
    - `year`: The scenario reference year (e.g., "2030").
    - `climate_year`: The climate year used for demand time series (e.g., "1982").

- Returns
    A named tuple containing processed dataframes and dictionaries:
    - `ntcs`: Net Transfer Capacities (NTCs) with connection IDs and directional capacities.
    - `nodes`: Information on nodes (zones) including country, coordinates, and region.
    - `arcs`: Line connectivity between nodes (node_a, node_b).
    - `demand`: Demand time series per node.
    - `capacity_2020_template`: Installed generation capacities in a standardized format.
    - `gen_costs`: Generation costs (€/MWh) by generation type.
    - `emission_factor`: Emissions (tCO₂/MWh) per generation type.
    - `inertia_constants`: Inertia constants per generation type (in seconds).
    - `start_up_cost`: Start-up costs (€/MW/start) by generation type.

- Notes
    - Data is read from preprocessed Excel and CSV files under the `TYNDP2024` directory.
    - Generation types are mapped to economic and technical parameters using predefined assumptions based on TYNDP 2020 values and expert judgement.
    - Capacity is interpreted from PEMMDB2 files, while demand is read from scenario-specific CSVs.
    - Generation technologies are assigned costs, emissions, and operational parameters via dictionaries.

- Data Sources
    - [Reference Grid & Investment Candidates](https://2024.entsos-tyndp-scenarios.eu/download/)
    - [Demand Profiles](https://tyndp.entsoe.eu/maps-data)
    - PEMMDB2 installed capacity datasets (CSV)
    - Node lists and network connections (Excel)

```julia
function get_grid_data_2024_zonal(scenario, year, climate_year) 
```
---

## get\_grid\_data\_2024\_nodal

Parses and processes the 2024 ENTSO-E TYNDP scenario data to construct nodal grid representations for electricity system modeling.

- Arguments
    - `scenario::String`: The scenario name (e.g., "NationalTrends", "DistributedEnergy", "GlobalAmbition").
    - `year::String`: The target simulation year (e.g., "2030", "2040").
    - `climate_year::String`: The reference climate year used for demand profiles (e.g., "1982").

- Description
    This function:
    - Loads electricity grid topology, node data, generation capacities, and demand time series from the 2024 TYNDP Excel and CSV files.
    - Constructs the necessary nodal representations for lines (`arcs`), nodes (`nodes`), transfer capacities (`ntcs`), and generator attributes.
    - Defines dictionaries for generation cost, emissions factors, inertia constants, and startup costs, categorized by generation technology.

- Outputs
    Returns a set of core data structures used for nodal power system modeling:
    - `ntcs`: DataFrame of NTC values for each direction of grid connection.
    - `nodes`: DataFrame of electricity node properties and metadata.
    - `arcs`: DataFrame of line connections between nodes.
    - `capacity`: DataFrame of installed generation capacity and properties.
    - `demand`: DataFrame of hourly electricity demand for each node.
    - `gen_costs`, `emission_factor`, `inertia_constants`, `start_up_cost`: Dictionaries containing generator-specific parameters.

- Data Sources
    - Reference Grid & Investment Candidates: https://2024.entsos-tyndp-scenarios.eu/download/
    - Demand Profiles: https://tyndp.entsoe.eu/maps-data
    - Generation Capacities: 250117_TYNDP2024Scenarios_Electricity_SupplyMix.xlsx
    - Node List: LIST OF NODES_2024.xlsx

```julia
function get_grid_data_2024_nodal(scenario, year, climate_year) 
```
---

## get\_demand\_data\_ext

Compute a scaled electricity demand time series (in MWh) for a specific area based on a given scenario, year, and climate year.

- Arguments
    - `orig_demand`: Original hourly electricity demand per area (in MWh), with 8760 rows for each area.
    - `demand`: Scenario-based demand values (in GWh) including country, node type, scenario, year, and climate year.
    - `nodes`: A two-column matrix mapping area codes to country names.
    - `area`: The specific area code for which the demand time series is requested.
    - `scenario`: Scenario short code ("DE", "GA", or "NT"), which will be expanded to the full scenario name.
    - `year`: Target simulation year (e.g., "2030").
    - `climate_year`: Climate reference year (e.g., "2008").

- Output
    - `Vector{Float64}`: A vector of 8760 values representing the scaled electricity demand time series for the specified area.

- Description
    This function:
    1. Translates scenario codes to full scenario names.
    2. Maps area codes to country names, including manual overrides for special cases (e.g., different Denmark codes).
    3. Identifies all area codes belonging to the same country as the given area.
    4. Calculates the total real (historical/original) electricity demand of that country by summing the values of all relevant areas.
    5. Extracts the demand time series for the specified area (if present).
    6. Filters the demand scenario data for the relevant country, scenario, year, and climate year.
    7. Computes the total scenario-based demand for the country and scales the original area's time series accordingly.

    If the original area demand is missing, a zero time series is returned. If the scenario demand is missing, the scaling ratio is zero.

```julia
function get_demand_data_ext(orig_demand,demand,nodes,area,scenario,year,climate_year)
```
---

## get\_generation\_ratio\_2024

Compute the share (ratio) of installed generation capacity of a given type at a specific node compared to the total national capacity for that generator type or group.

- Arguments
    - `capacity`: Generation capacity data containing columns `"Node_Line"`, `"Generator_ID"`, and `"Value"` (capacity values).
    - `type`: The specific generator technology (e.g., "Gas CCGT new", "Offshore Wind").
    - `node`: Node (zone) identifier for which the capacity ratio is to be computed.
    - `nodes`: A dataset or matrix mapping node identifiers to country names, with columns `"node_id"` and `"country_text"` (or equivalent).

- Output
    - `Float64`: The share (between 0 and 1) of this node’s capacity of the specified generator type compared to the total national capacity of the same type or group.

- Description
    This function calculates how much of a specific generation technology's national capacity is located at a given node. It includes several steps:

    1. **Offshore Special Case**: If the node is an offshore virtual node (e.g., `"FR00"`, `"NL00"`, etc.) and the generator type is `"Offshore Wind"`, the function returns `1.0` (100%) by definition.
    2. **Country Mapping**: Constructs a mapping of node IDs to countries, with manual adjustments for Danish virtual nodes.
    3. **Node Capacity Extraction**: Extracts capacity value for the given generator type at the specified node.
    4. **Technology Grouping**: Groups certain technologies (e.g., multiple variants of "Gas CCGT") under one umbrella when computing national capacity.
    5. **National Capacity Aggregation**: Sums capacities of the same group/type across all nodes in the same country.
    6. **Ratio Calculation**: Computes the node's share of the total national capacity for the given generator type or group.
    7. **Error Handling**: If the denominator is zero (no national capacity found), the result defaults to `0`.


```julia
function get_generation_ratio_2024(capacity,type,node,nodes)
```
---

## get\_corrected\_capacity\_2024

Retrieves the corrected installed capacity (in MW) for a specific generation unit `g` in the country of `node_id`, for a given year, scenario, and climate year.

- Arguments
    - `year`: The year for which capacity is requested, as a string (e.g., "2024").
    - `scenario`: The scenario, given as a short code ("DE", "GA", "NT"). This is translated to its full name.
    - `g`: The generator technology/type (e.g., "Gas CCGT new", "Solar PV").
    - `node_id`: The node (zone) for which the country is determined.
    - `climate_year`: The climate year (e.g., 2008), used for filtering the data.
    - `nodes`: Data with nodes and their corresponding countries (columns with node_id and country name).
    - `data`: Dataset containing installed capacities and associated properties (columns include "Property_Name", "Country", "Year", "Climate_Year", "Category_Detail", "Value").

- Output
    - `Float64` or `Nothing`: Corrected installed capacity in MW for the specified type and country. Returns `nothing` if no capacity is found.

- Description
    The function works as follows:

    1. Translates short scenario codes to full scenario names.
    2. Creates a mapping from node_id → country, with manual corrections for certain Danish offshore nodes.
    3. Uses a dictionary to find which category(ies) in the data correspond to the given generation type `g`.
    4. Filters the data on installed capacity, country, year, and climate year.
    5. Sums the capacities that match the relevant categories for `g`.
    6. Converts capacity from GW to MW (multiplies by 1000).
    7. Returns the sum or `nothing` if no capacity is found.

This provides a “corrected” capacity (specific to scenario and climate year) for a generator in the country of the node.

```julia
function get_corrected_capacity_2024(year,scenario,g,node_id,climate_year,nodes,data)
```

