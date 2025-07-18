# Representative Scenarios

## find\_extreme\_scenarios

Identifies indices of time steps representing various extreme scenarios in demand and renewable generation
based on quantile thresholds.

- Arguments
    - `demand`: Vector, Total system demand time series.
    - `renewables`: Vector, Total renewable generation time series.
    - `offshore`: Vector, Offshore wind generation time series.
    - `other_res`: Vector, Other renewable generation time series (e.g., solar, onshore wind).
    - `demand_w`: Vector, Demand in the "windy" region (UK, DK1, NL).
    - `demand_nw`: Vector, Demand in the "non-windy" region (BE, DE).
    - `demand_quantile`: Quantile threshold for high demand.
    - `renewables_quantile_high`: Quantile threshold for high renewable generation.
    - `renewables_quantile_low`: Quantile threshold for low renewable generation.
    - `offshore_quantile_high`: Quantile threshold for high offshore wind generation.
    - `other_res_quantile_low`: Quantile threshold for low other renewable generation.
    - `demand_w_quantile_low`: Quantile threshold for low demand in "windy" region.
    - `demand_nw_quantile_high`: Quantile threshold for high demand in "non-windy" region.

- Output
    - `high_demand_high_renewables_indices`: Vector, Indices with high demand and high renewables.
    - `high_demand_low_renewables_indices`: Vector, Indices with high demand and low renewables.
    - `high_offshore_low_res_indices`: Vector, Indices with high offshore wind and low other RES.
    - `low_demandw_high_demandnw_indices`: Vector, Indices with low "windy" demand and high "non-windy" demand.

```julia
function find_extreme_scenarios(demand, renewables, offshore, other_res, demand_w, demand_nw, demand_quantile,renewables_quantile_high, renewables_quantile_low, offshore_quantile_high, other_res_quantile_low, demand_w_quantile_low, demand_nw_quantile_high)
```
---

## get\_reduced\_timeseries

Reduce detailed hourly time series data into representative clusters using k-means clustering and importance subsampling.

- Arguments
    - `timeseries_data`: Dictionary containing full hourly time series data for demand, renewables (solar PV, wind offshore/onshore), and cross-border flows across zones.
    - `option`: Integer (1 to 4) selecting the combination of normalized features to use for clustering.
        - 1: All features (demand, renewables, offshore, other_res, demand_w, demand_nw).
        - 2: Demand and renewables only.
        - 3: Renewables only.
        - 4: Demand only.
    - `demand_quantile`: Quantile threshold to classify high demand hours (default 0.8).
    - `renewables_quantile_high`: Quantile threshold for high renewable generation (default 0.8).
    - `renewables_quantile_low`: Quantile threshold for low renewable generation (default 0.3).
    - `offshore_quantile_high`: Quantile threshold for offshore wind (default 0.75).
    - `other_res_quantile_low`: Quantile threshold for other renewables (default 0.5).
    - `demand_w_quantile_low`: Quantile threshold for Western demand (default 0.35).
    - `demand_nw_quantile_high`: Quantile threshold for Northwestern demand (default 0.65).
    - `num_clusters`: Number of clusters for k-means clustering excluding the 4 extreme scenarios (default 11).

- Output
    Returns a new dictionary similar to `timeseries_data`, where time series are replaced by cluster centroids representing reduced and aggregated scenarios.

- Description
    This function performs the following steps:
    1. Aggregates and sums hourly time series for demand, renewables (offshore/onshore wind, solar PV), and cross-border flows across zones.
    2. Normalizes each aggregated time series using min-max scaling.
    3. Selects feature subsets for clustering based on the `option` parameter.
    4. Identifies extreme scenario hours by applying quantile thresholds to normalized demand and renewable generation values.
    5. Clusters extreme scenarios separately (each extreme cluster with one centroid).
    6. Applies k-means clustering to the remaining time series data to reduce dimensionality.
    7. Combines extreme scenario centroids and main cluster centroids into a final set of representative time series.
    8. Denormalizes cluster centroids back to original scale and structures them into a reduced `timeseries_data` dictionary.

```julia
function get_reduced_timeseries(timeseries_data, option; demand_quantile=0.8, renewables_quantile_high=0.8, renewables_quantile_low=0.3, offshore_quantile_high = 0.75, other_res_quantile_low = 0.5, demand_w_quantile_low = 0.35, demand_nw_quantile_high = 0.65,num_clusters=11)
```

