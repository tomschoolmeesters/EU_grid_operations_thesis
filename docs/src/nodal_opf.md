## Purpose

This script performs a **detailed power grid simulation** and analysis for the European electricity grid, focusing on nodal optimal power flow (OPF) calculations. It is designed to:
- Load and preprocess European grid data (including generator and bus modifications).
- Integrate TYNDP (Ten-Year Network Development Plan) scenario data.
- Model specific scenarios such as offshore wind relocation, converter updates, and load shedding.
- Run both full hourly and representative timestep OPF simulations.
- Analyze and visualize renewable energy and demand profiles.
- Export detailed results for further analysis.

---

## General Workflow

- **Import Dependencies**: 

    Load all required Julia packages and libraries needed for grid modeling, optimization, data handling, and plotting.

- **Define Input Parameters**: 

    Specify scenario parameters such as year, climate year, zones, and options for modifications (e.g., relocating wind farms, adding offshore hubs).

- **Load Grid Data**: 

    Parse the EU grid JSON file into the PowerModels data structure.

```julia
file = joinpath(@__DIR__, "..", "..", "data_sources", "European_grid_no_nseh.json")
EU_grid = _PM.parse_file(file)
```

- **Modify Grid Structure**:

    - Update bus zone assignments and coordinates.
    - Conditionally remove or add generators, buses, converters, and branches based on scenario flags.

```julia
update_input_data_ext(EU_grid,year)
add_offshore_hub(EU_grid)
add_VOLL_generation(EU_grid)
```

- **Finalize Grid Setup**:

    - Process additional grid data.
    - Optionally update converter parameters.

```julia
_PMACDC.process_additional_data!(EU_grid)
add_load_and_pst_properties!(EU_grid)
update_conv_input(EU_grid)
```

- **Load TYNDP Scenario Data**:

    - Load zonal OPF results in batches from JSON files.
    - Load nodal grid parameters, generation profiles, and other input data if enabled.

- **Process Input Data**:

    - Map zones and country codes.
    - Calculate zonal offshore wind capacities and scale generation profiles.

```julia
scale_generation24!(tyndp_capacity, EU_grid, scenario_id, climate_year, zone_mapping,country_names)
```
- **Zone Isolation & Cost Updates**:

    - Isolate selected zones with flow relaxation.
    - Update generation costs, especially for offshore wind and value of lost load (VOLL).

- **Generate Time Series Data**:
    - Create renewable generation and demand profiles for each zone.
    - Include cross-border flow time series.

```julia
create_res_and_demand_time_series(wind_onshore, wind_offshore, pv, scenario_data, climate_year, zone_mapping; zones = isolated_zones)
get_xb_flows_v2(zone_grid, zonal_result, zonal_input, zone_mapping)
```

- **Run OPF Simulations**:

    - Full timestep OPF simulation (hourly, memory intensive) OR...
    - Representative timestep simulation using reduced time series data.

```julia
# Representative timestep simulation (reduced data)
timeseries_data_reduced, factor, extreme_indices = _EUGO.get_reduced_timeseries(timeseries_data, option=3)
result = _EUGO.batch_opf_repr(hour_start_idx, hour_end_idx, zone_grid, timeseries_data_reduced, factor, gurobi, s_dual)
```

- **Update Branch Ratings**: 

    Modify DC branch ratings and AC branch parameters at borders to avoid infeasibilities.

- **Save Results**: 

    Export OPF results, grid input data, and scenario data to JSON files.

- **Visualization**:

    - Plot renewable energy generation time series.
    - Plot demand time series.
    - Plot grid structure.

- **Zonal OPF Batch Analysis**: 

    Aggregate generation statistics (e.g., renewable generation by type and zone) from zonal OPF results.


## General Inputs

### 1. Grid Data
- **Topology**: The European grid network including buses, branches, DC converters, and zones.
- **Generator Data**: Types, capacities, and locations of generators including nuclear, onshore/offshore wind, solar PV, etc.
- **Zones**: Definition of control zones and isolated zones for flexible boundary conditions.
- **Cross-Border Flows**: Net Transfer Capacities and border flow constraints.
- **Line Ratings**: Thermal limits of AC and DC branches.

### 2. Scenario Parameters
- **TYNDP Version**: Year/version of the Ten-Year Network Development Plan (e.g., "2024").
- **Scenario**: Scenario name (e.g., "NT" for Neutral Transition).
- **Year**: Target simulation year (e.g., "2030").
- **Climate Year**: Historical weather year for renewables profile (e.g., "2008").
- **Use Case**: Simulation use case identifier (e.g., "North_Sea_reloc").
- **Relocate Wind**: Boolean flag to update offshore wind locations.
- **Add VOLL**: Flag to add Value of Lost Load generation.
- **Isolated Zones**: List of zones treated as electrically isolated for study.

### 3. Renewable and Demand Time Series
- Hourly generation profiles for solar PV, onshore and offshore wind power.
- Hourly demand profiles per node or zone.
- Zonal mappings to translate between TYNDP zones and model zones.

### 4. Solver and Tools
- **Optimization Solvers**: Gurobi for mixed-integer programming, Ipopt for nonlinear optimization.
- **Power Flow Models**: PowerModels.jl and PowerModelsACDC.jl.

---

## Overall Outputs

### 1. OPF Results
- Hourly generator dispatch (`pg`), branch flows, and voltage profiles.
- Dual variables (if enabled) for constraints, useful for sensitivity and market price analyses.
- Cross-border flow values respecting constraints and slack.

```julia
result = _EUGO.batch_opf_repr(hour_start_idx, hour_end_idx,zone_grid, timeseries_data_reduced, factor, gurobi, s_dual)
nodal_result = deepcopy(result)

result_file_name = joinpath(output_dir, "result_nodal_opf.json")
```

### 2. Scenario Metadata
- Installed generation capacities by type and zone.
- Renewable availability profiles and demand time series used in simulations.
```julia
pv, wind_onshore, wind_offshore = _EUGO.load_res_data()
timeseries_data = _EUGO.create_res_and_demand_time_series(...)

scenario_file_name = joinpath(output_dir, "scenario_nodal_opf.json")
```

### 3. Input Data Snapshots
- Grid topology including updated converter and branch ratings.
- Generator cost and emission parameters.
```julia
input_file_name = joinpath(output_dir, "input_nodal_opf.json")
```

### 4. Visualizations
- Plots of reduced and full renewable energy profiles per zone.
- Demand time series plots.
- Grid topology visualizations highlighting isolated zones and cross-border interconnections.
```julia
Plots.plot(timeseries_data_reduced["solar_pv"]["BE"], ...)
Plots.savefig(joinpath(output_dir_fig, "res_timeseries_reduced.svg"))

Plots.plot(timeseries_data["demand"]["BE"][744:767], ...)
Plots.savefig(joinpath(output_dir_fig, "dem_timeseries.svg"))

plot_filename = joinpath(output_dir_fig, join(["plot_grid_", use_case,".svg"]))
_EUGO.plot_grid(zone_grid, plot_filename)
```

---

## Notes
- Users must manually download required data files and place them in the designated `data_sources/` folder.
- The simulation can be customized by changing input parameters such as `scenario`, `year`, `isolated_zones`, and flags controlling wind relocation and converter updates.
- Batch processing is used to handle large hourly datasets efficiently.
- The test case provides a flexible framework to test different grid scenarios, generation mixes, and cross-border flow assumptions.

---
