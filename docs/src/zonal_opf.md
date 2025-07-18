## Purpose

This script performs an **hourly economic dispatch optimization** for the European power grid as represented in ENTSO-E's **Ten-Year Network Development Plan (TYNDP)**. It uses predefined network and generation data to solve hourly grid operation models over a user-defined time period.

The goal is to determine the most cost-efficient dispatch of electricity generation, subject to network constraints — **excluding internal zonal congestions**.

---

## General Workflow

1. **User Parameters**  
   The user selects:
   - TYNDP version
   - Scenario
   - Planning year
   - Climate year
   - Number of hours
   - Whether to fetch and parse fresh data

2. **Data Loading**  
   Based on selected parameters, the script loads:
   - Renewable energy (RES) profiles: solar PV, onshore wind, offshore wind
   - Grid structure: nodes, arcs, net transfer capacities (NTCs)
   - Installed generation capacities and types
   - Demand time series
   - Generator cost and emission data

3. **Data Preparation**  
   The script builds a data dictionary in **PowerModels.jl** format, suitable for optimal power flow (OPF) analysis.

4. **Hourly Optimization**  
   - A loop runs a DC-approximation OPF for each hour.
   - Results are stored in memory and saved in batches for performance.

5. **Result Storage**  
   The following files are saved:
   - Hourly OPF results per batch (`opf_batches/`)
   - Full result file with all hourly outcomes
   - Input data dictionary
   - Scenario metadata (e.g., time series, installed capacity)

---

## User Input Parameters

These parameters must be configured at the beginning of the script:

```julia
tyndp_version    = "2020" or "2024"
scenario         = "DE", "NT", or "GA" (Distributed Energy, National Trends, Global Ambition)
year             = planning year (depends on TYNDP version)
climate_year     = reference weather year for RES generation
number_of_hours  = number of hours to simulate (up to 8760)
start_hour       = starting hour (typically 1)
fetch_data       = true/false (whether to reload and parse data)
```
---

## Expected Input Data (Automatically Loaded)

All data is loaded from Feather files and internal modules:

- Time series for RES (solar PV, wind)
- Grid topology (nodes, arcs)
- Net transfer capacities (NTCs)
- Generator types and capacities
- Demand data per node
- Cost and emissions information
- Node geographical positions
- Inertia constants

> **Note**: Users must manually download the required Feather files and place them in the `data_sources/` folder.  
> See `data_sources/download_links.txt` for source links.

---

## Output Files

The script creates several output files in **JSON format**:

### 1. Hourly Batch Results

- **Saved to**: `Test Case/Output/[SCENARIO]_[YEAR]_[CLIMATE_YEAR]/zonal_opf_[START]_to_[END].json`

---

### 2. Full Result File

- **Saved to**:  
  `Test Case/Output/[SCENARIO]_[YEAR]_[CLIMATE_YEAR]/result_zonal_opf.json`

- **Contains**:  
  Full hourly OPF results for the specified time range

---

### 3. Input Data Dictionary

- **Saved to**:  
  `Test Case/Output/[SCENARIO]_[YEAR]_[CLIMATE_YEAR]/input_zonal_opf.json`

- **Contains**:  
  All grid and time series data used to run the model

---

### 4. Scenario Metadata

- **Saved to**:  
  `Test Case/Output/[SCENARIO]_[YEAR]_[CLIMATE_YEAR]/scenario_zonal_opf.json`

- **Contains**:  
  Installed capacities, RES availability, and demand profiles

---

## Key Dependencies

- [`JuMP.jl`](https://jump.dev) – for mathematical optimization
- [`PowerModels.jl`](https://lanl-ansi.github.io/PowerModels.jl/stable/) – for power flow modeling
- [`Gurobi`](https://www.gurobi.com/) – used as the optimization solver
- `EU_grid_operations` – custom module for scenario data parsing
