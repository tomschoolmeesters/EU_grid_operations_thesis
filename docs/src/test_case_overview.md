# Overview

The test case being analyzed is the Distributed Energy (DE) scenario for the simulation year 2040 and climate year 2008.

---

## 1. Zonal OPF

```julia
run_zonal_opf.jl
```

In the **zonal Optimal Power Flow (OPF)** model, the entire European electricity system is represented using a simplified network with approximately one node per market zone. This high-level abstraction enables the estimation of cross-border electricity flows, particularly between the North Sea countries and their neighboring regions.

The model uses slightly updated **TYNDP input data** to build:
- an **input dictionary**, containing grid topology and technical parameters, and
- a **scenario dictionary**, containing time series for demand and renewable generation.

Subsequently, the model applies **PowerModels' NFA PowerModel**, a network flow approximation (NFA) that considers active power only, commonly referred to as the transportation model. This simplification enables efficient computation of the hourly dispatch, and the results are stored in a structured **result dictionary**.

---

## 2. Nodal OPF

```julia
run_nodal_opf.jl
```

Subsequently, a **nodal OPF** is performed for a more granular analysis of the North Sea region, specifically focusing on:
- Belgium (BE), 
- Germany (DE), 
- the United Kingdom (UK), 
- the Netherlands (NL), 
- and the western Danish bidding zone (DK1). 

Cross-border flows determined in the zonal OPF are used to fix boundary conditions for the nodal model. This approach allows an accurate approximation of external systems without requiring full nodal models for the rest of Europe.

In this nodal model:
- Internal grid structures are modeled in significantly more detail to capture **intra-zonal congestion**.
- **Offshore wind farm layouts** are adapted to realistically reflect potential transmission infrastructure and network constraints.

---

## 3. TNEP Candidate Filtering

```julia
run_nodal_tnep.jl
```
The third step focuses on **Transmission Network Expansion Planning (TNEP)** for the North Sea region.
The primary objective is to develop a robust **pre-processor** that efficiently filters the most relevant investment candidates in large-scale, multinational power systems. This step aims to:
- Reduce the initial pool of over 50,000 expansion candidates, and
- Improve computational tractability and solution quality of the TNEP model.

The focus is on both:

- Offshore HVDC links, and
- Onshore reinforcements in key North Sea countries.

The filtering methodology combines technical and economic criteria, including:

- **Power Transfer Distribution Factors (PTDFs)** to assess each candidate’s physical impact on power flows.
- **Nodal price differences** to estimate economic potential.
- **Benefit-to-cost ratios** to prioritize investments that offer the highest system value.

To further refine the selection, the approach applies:
- **Principal Component Analysis (PCA)** for dimensionality reduction.
- **k-means clustering** to ensure a spatially diverse and representative set of high-impact candidates.

These filtered candidates are then passed into the nodal TNEP optimization model, which:
- Uses a linearized OPF formulation adapted for hybrid AC/DC grids,
- Minimizes total system cost, accounting for:
    - generation cost,
    - load shedding penalties,
    - and investment expenditures.

---

## 4. Extra Visuals

This section outlines the various post-processing steps used to visualize and analyze the simulation results, grouped by theme.

### Geospatial Visualizations

#### Nodal Prices Map
Plots the geographical distribution of nodal prices for a specific hour.
```julia
_EUGO.plot_nodes_with_prices(nodal_input, nodal_result, hour_range; file_name, legend_file_name)
```

#### Grid Loading Visualization
Plots the electrical grid with line colors indicating loading levels.
```julia
_EUGO.plot_loaded_grid(nodal_input, nodal_result, plot_filename, legend_file_name, hour_range)
```

###  Generation and Load Analyses
These plots show the behavior of generators, loads, and storage over time.

#### Generation Types Overview
Visualizes electricity generation by type and storage usage over a given period.
```julia
_EUGO.Analyse_generation_types(hour_range, start_hour, nodal_input, nodal_result, output_dir_fig)
```

#### Load Profile and Demand Analysis
Computes total electricity demand (in MWh) over a specific time window.
```julia
_EUGO.Analyse_load(hour_range, nodal_input, nodal_result, timeseries_data_reduced, factor)
```

#### Installed Capacity by Type
Computes the total installed generation capacity for each generator type.
```julia
_EUGO.Capacity_installed(nodal_input)
```

### Component-Level Diagnostics
Detailed analysis of individual system components such as buses, branches, and generators.

#### Bus Analysis
Examines flows, demand, and connections for a specific bus.
```julia
_EUGO.Analyse_bus(n, nodal_input, nodal_result, timeseries_data_reduced, number_of_hours, start_hour)
```

#### Branch Analysis
Analyzes a specific AC or DC transmission line over time.
```julia
_EUGO.Analyse_branch(b, nodal_input, nodal_result, start_hour)
```

#### Generator Analysis
Explores the generation profile and curtailment of a specific generator.
```julia
_EUGO.Analyse_generator(g, start_hour, number_of_hours, nodal_input, nodal_result, timeseries_data_reduced)
```

### Network Performance Indices
These functions generate metrics that quantify network behavior, congestion, and capacity usage.

#### Congestion Index (Plot)
Plots the congestion index over a defined simulation window.
```julia
_EUGO.plot_Congestion_index(nodal_result, number_of_hours, plot_filename)
```

#### Congestion Index (Hourly)
Computes a numerical value for congestion based on nodal prices.
```julia
_EUGO.Congestion_index(nodal_result, number_of_hours)
```

#### Congestion Index (Overall)
Computes an aggregated annual congestion index across all nodes and hours.
```julia
_EUGO.overall_congestion_index(nodal_result, factor)
```

#### Saturation Index (Plot)
Plots how saturated transmission lines are relative to their thermal capacity.
```julia
_EUGO.plot_Saturation_index(nodal_result, nodal_input, plot_filename)
```

#### Saturation Index (Hourly)
Numerical version of the saturation index for all hours.
```julia
_EUGO.Saturation_index(nodal_result, nodal_input)
```

### Curtailment, Congestion & Shedding Insights
These methods detect and report critical events like curtailment, congestion, and load shedding.

#### Renewable Curtailment
Detects renewable generators with significant curtailment.
```julia
_EUGO.where_curtailment(nodal_input, nodal_result, timeseries_data_reduced, number_of_hours)
```

#### Load Shedding Detection (Full Period)
Identifies load shedding and demand-side flexibility events.
```julia
_EUGO.where_congestion(nodal_input, nodal_result)
```

#### Load Shedding (Specific Hours)
Same as above, but filtered for a specific time window.
```julia
_EUGO.load_shedding(hour_range, nodal_input, nodal_result)
```

#### Electrical Congestion on AC Lines
Identifies AC lines experiencing electrical congestion.
```julia
_EUGO.where_congestion_electrical(nodal_input, nodal_result)
```

### Line Flow Analysis
Analyze power flows through specific lines over time.
```julia
_EUGO.Line_loading(lines, nodal_input, nodal_result)
```


