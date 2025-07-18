## Purpose

---

## General Workflow

### 1. Generate candidate lines (AC and DC)

The function `_EUGO.candidate_lines_ext` generates all technically feasible AC and DC line candidates.
These candidates form the base input for cost evaluation and impact analysis.

```julia
ne_branch, ne_branchDC, AC_new_corridor_idx, DC_new_corridor_idx = _EUGO.candidate_lines_ext(
    nodal_input, new_DC_buses, relocation_dict)
```

### 2. Add cost data to candidates

Cost data (CAPEX and/or OPEX) is added to each line candidate using _EUGO.update_cost_data. This ensures each candidate can be evaluated economically in the optimization step.

```julia
ne_branch, ne_branchDC = _EUGO.update_cost_data(ne_branch, ne_branchDC, nodal_input)
```

### 3. Run impact analysis (PTDF matrices)
The Power Transfer Distribution Factor (PTDF) matrices are computed to understand the sensitivity of each line to power injections. These matrices help identify which candidates have meaningful impact on the network.

```julia
Impact_matrix, selected_indices_AC, selected_indices_DC, dc_to_ac_map = _EUGO.PTDF_analysis_full(
    nodal_input, nodal_result, number_of_hours, ne_branch, ne_branchDC)
```

### 4. Preprocess the candidates

The pre-processor serves to **filter and prioritize candidate transmission lines** for expansion by combining their **technical impact** on the existing grid (using PTDF-based metrics) with their **economic relevance** (based on nodal price signals). This reduces the large pool of potential candidates to a manageable and meaningful subset, ensuring that only technically and economically promising options proceed to detailed optimization.

```julia
zone_grid = _EUGO.pre_processor(nodal_input, nodal_result, Impact_matrix, selected_indices_AC, selected_indices_DC,number_of_hours, factor, AC_new_corridor_idx, ne_branch, ne_branchDC; start_hour=1)
```

### 5. Run optimization (full and representative timeframes)
The TNEP optimization is formulated as a **Mixed-Integer Programming (MIP)** problem using the PowerModels.jl framework and solved with the **Gurobi Optimizer (v12.0.1)**. Due to the computational complexity, a **MIP gap of 5%** is used as a stopping criterion. This means the solver terminates when the difference between the best known solution and the bound is less than 5% of the objective value, balancing solution quality and computational effort.

Two types of optimization runs can be performed:
- **Full Timestep Simulation:** Runs across the entire time horizon (e.g., 1 to 8760 hours), providing detailed temporal resolution but at high computational cost.
- **Representative Timestep Simulation:** Uses a reduced set of representative hours (e.g., 1 to 15) to approximate system behavior, significantly reducing computation time while maintaining solution quality.

#### Example of a Representative Timestep Optimization Call

```julia
mn_input_data = _EUGO.prepare_mn_data_nodal(zone_grid, EU_grid, timeseries_data_reduced, 1:15)

result = _PMACDC.run_mp_tnepopf_repr(
mn_input_data, _PM.DCPPowerModel,
JuMP.optimizer_with_attributes(Gurobi.Optimizer, "MIPGap" => 0.05, "DualReductions" => 0, "MIPFocus" => 3),
multinetwork = true;
setting = Dict("output" => Dict("branch_flows" => true), "conv_losses_mp" => true,
                "fix_cross_border_flows" => true, "process_data_internally" => false))
```
This approach ensures a good trade-off between computational efficiency and solution accuracy, suitable for large-scale transmission expansion planning studies.

---

## General Inputs

| Input Name              | Description                                               |
|-------------------------|-----------------------------------------------------------|
| `nodal_input`           | Raw nodal grid topology and parameters                    |
| `nodal_result`          | Power flow results or historical data                     |
| `new_DC_buses`          | New candidate buses for DC connections                    |
| `relocation_dict`       | Mapping of relocatable grid assets                        |
| `EU_grid`               | Base EU transmission grid for reference                   |
| `timeseries_data_reduced` | Reduced or representative time series data             |
| `factor`                | Scaling or weighting factor used in preprocessing         |

---

## Overall Outputs

After running the full TNEP pipeline, the following key output files are generated. Each serves a distinct purpose for visualization, analysis, or further modeling:

| Output File                              |  Description                                                                 |
|--------------------------------------------|------------------------------------------------------------------------------|
| `input_candidates_tnep.svg`                | **Visual overview** of all generated **AC and DC candidate lines** before optimization. Useful for validation and inspection of the initial candidate pool. |
| `grid_input_tnep_detailed_<use_case>.pdf`  | **Post-optimization grid visualization** showing which lines were built and where reinforcements occurred. Generated per specific use case. |
| `result_nodal_tnep.json`                   | **Structured result file** containing selected expansions, hourly power flows, and **solver metadata**. Ideal for post-processing or further study. |
