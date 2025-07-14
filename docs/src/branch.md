# Analyse branches

#### Analyse\_branch

Analyzes a power branch (AC or DC) from a power system model over a given time window.

- Arguments
    - `b::Any`: The branch number (used as a key to access branch data).
    - `nodal_input::Dict`: A dictionary containing the input data for the nodal model, including branch and bus information.
    - `nodal_result::Dict`: A dictionary containing the results of the nodal analysis, including power flow solutions.
    - `start_hour::Int`: The starting hour (in model time) for the analysis period.

- Output
    - Prints the branch details
    - Displays a plot of power flow vs. time with rated capacity as a reference.


- Notes
    This function:
    - Extracts relevant metadata about the specified branch, such as type, buses, and zones.
    - Computes the power flow on the branch over the specified time window.
    - Generates a plot of the absolute power flow over time, along with the branch's rated capacity.


```julia
function Analyse_branch(b,nodal_input,nodal_result,start_hour=1)
```
