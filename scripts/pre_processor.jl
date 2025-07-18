"""
    get_AC_branch_info(nodal_input)

Extracts AC branch and bus information from nodal input data.

# Arguments
    - `nodal_input`: Dictionary containing keys "branch", "branchdc", and "convdc". 
    Each key maps to a nested dictionary of indexed branch/converter data.

# Returns
    - `AC_branches`: Dictionary mapping (from_bus, to_bus) tuples to a Dict of branch data.
    - `AC_buses`: Sorted vector, unique list of AC bus indices.

# Description
    - Gathers AC and converted DC branch data.
    - Avoids duplicate branches by checking both directions.
    - For DC branches, maps DC buses to AC buses using converter definitions.

"""

function get_AC_branch_info(nodal_input)
    AC_branches = Dict()    # Dictionary to store branch info keyed by (from_bus, to_bus)
    AC_buses = Vector()     # List to collect AC bus indices
    nr = 1                  # Counter to assign unique number to each branch

    # Process AC branches
    for (_, branch) in nodal_input["branch"]
        f_bus = branch["f_bus"]
        t_bus = branch["t_bus"]

        push!(AC_buses, f_bus)
        push!(AC_buses, t_bus)

        # Use (f_bus, t_bus) as key if neither direction is already present
        if !((f_bus, t_bus) in keys(AC_branches)) && !((t_bus, f_bus) in keys(AC_branches))
            AC_branches[(f_bus, t_bus)] = Dict(
                "br_x" => branch["br_x"],   # Branch reactance
                "idx" => branch["index"],   # original index
                "f_bus" => f_bus,
                "t_bus" => t_bus,
                "nr" => nr                  # internal unique identifier
            )
            nr += 1
        end
    end

    # Process DC branches by converting DC buses to AC via converters
    for (_, branchdc) in nodal_input["branchdc"]
        f_busDC = branchdc["fbusdc"]
        t_busDC = branchdc["tbusdc"]
        f_busAC = 0
        t_busAC = 0

        # Search corresponding AC buses from converter data
        for (_, conv) in nodal_input["convdc"]
            if conv["busdc_i"] == f_busDC
                f_busAC = conv["busac_i"]
            end
            if conv["busdc_i"] == t_busDC
                t_busAC = conv["busac_i"]
            end
        end

        push!(AC_buses, f_busAC)
        push!(AC_buses, t_busAC)

        # Add DC-equivalent AC branch if not already present
        if !((f_busAC, t_busAC) in keys(AC_branches))
            AC_branches[(f_busAC, t_busAC)] = Dict(
                "br_x" => 0.000233,             # fixed reactance for DC-equivalent branch
                "idx" => branchdc["index"],
                "f_bus" => f_busAC,
                "t_bus" => t_busAC,
                "nr" => nr
            )
            nr += 1
        end
    end

    # Remove duplicate buses and sort list
    AC_buses = unique(AC_buses)
    AC_buses = sort(AC_buses)

    return AC_branches, AC_buses
end

"""
    get_susceptance_matrix(nodal_input)

Constructs the AC susceptance (B) matrix based on nodal input.

# Arguments
    - `nodal_input`: Dictionary with branch and converter information (see `get_AC_branch_info`).

# Returns
    - `susceptance_matrix`: Sparse symmetric matrix of size n x n where n is the number of AC buses.
    - `bus_index`: Dictionary, Mapping from bus number to matrix index.
    - `AC_branches`: AC branch dictionary, as built by `get_AC_branch_info`.

# Description
    - Builds the B matrix using inverse reactances for off-diagonal entries.
    - Ensures diagonal entries cause each row to sum to zero.
    - Suitable for DC power flow studies or similar.

# Dependencies
    - Calls `get_AC_branch_info` internally.
"""

function get_susceptance_matrix(nodal_input)

    AC_branches, AC_buses = get_AC_branch_info(nodal_input)
    AC_buses_amount = length(AC_buses)
    
    # Map actual bus numbers to matrix indices (1-based)
    bus_index = Dict(bus => idx for (idx, bus) in enumerate(AC_buses))
    
    # Initialize sparse susceptance matrix
    susceptance_matrix = SparseArrays.spzeros(AC_buses_amount, AC_buses_amount)

    # Fill off-diagonal elements with -1 / reactance
    for (_, branch) in AC_branches
        if branch["f_bus"] in keys(bus_index) && branch["t_bus"] in keys(bus_index)
            i = bus_index[branch["f_bus"]]
            j = bus_index[branch["t_bus"]]
            if i != j
                susceptance_matrix[i, j] = -1 / branch["br_x"]
                susceptance_matrix[j, i] = -1 / branch["br_x"]  # Symmetric entry
            end
        else
            println("Bus $(branch["f_bus"]) or $(branch["t_bus"]) not in bus_index")
        end
    end

    # Fill diagonal entries so each row sums to zero (i.e., Kirchhoff's current law)
    for i in 1:AC_buses_amount
        susceptance_matrix[i, i] = -sum(susceptance_matrix[i, :])
    end

    return susceptance_matrix, bus_index, AC_branches
end


"""
    get_inverse_susceptance_matrix(nodal_input)

Computes the inverse of the susceptance matrix based on nodal input data.

# Arguments
    - `nodal_input`: Dictionary with power system data, used to construct the reduced susceptance matrix.

# Returns
    - `inverse_susceptance_matrix`: Dense matrix representing the inverse of the reduced B matrix.
    - `bus_index`: Dictionary, Mapping from bus number to matrix index.
    - `AC_branches`: AC branch dictionary, as built by `get_AC_branch_info`.

# Description
    - This function calls `get_susceptance_matrix` to obtain a B matrix.
    - Uses LU decomposition to compute the matrix inverse efficiently and numerically stably.

# Dependencies
    - Requires `LinearAlgebra` for LU decomposition and matrix inversion.
"""

function get_inverse_susceptance_matrix(nodal_input)
    # Get the reduced B matrix and accompanying data
    susceptance_matrix, bus_index, AC_branches = get_susceptance_matrix(nodal_input)

    # Perform LU decomposition of the reduced B matrix (converted to dense format)
    M = LinearAlgebra.lu(Matrix(susceptance_matrix))
    L = M.L  # Lower triangular matrix
    U = M.U  # Upper triangular matrix

    # Compute the inverse using the LU decomposition: inv(B) = inv(U) * inv(L)
    inverse_susceptance_matrix = inv(Matrix(U)) * inv(Matrix(L))

    return inverse_susceptance_matrix, bus_index, AC_branches
end


"""
    get_PTDF_matrix(nodal_input)

Calculates the Power Transfer Distribution Factor (PTDF) matrix from nodal input data.

# Arguments
    - `nodal_input`: Dictionary containing network data including "bus", "branch", and "branchdc".

# Returns
    - `PTDF_matrix`: Matrix of size (branches x buses) representing power flow sensitivity.
    - `bus_index`: Dictionary, Mapping from bus number to matrix index.
    - `AC_branches`: AC branch dictionary, as built by `get_AC_branch_info`.

# Description
    - PTDF describes how a power injection at one bus affects the power flow on each branch in the system.
    - Builds the branch-bus incidence matrix (A), diagonal branch reactance matrix (X), and uses inverse B matrix.
    - PTDF = inv(X) * A * B⁻¹, computed efficiently using LU decomposition.

"""

function get_PTDF_matrix(nodal_input)
    # Compute inverse susceptance matrix and related data
    B_inv, bus_index, AC_branches = get_inverse_susceptance_matrix(nodal_input)

    num_nodes = size(B_inv, 1)          # Number of buses (excluding slack)
    num_branches = length(AC_branches)  # Total number of branches

    # Initialize incidence matrix A (branches × buses)
    A = SparseArrays.spzeros(num_branches, num_nodes)

    # Diagonal matrix X to hold branch reactances
    X = SparseArrays.spzeros(num_branches, num_branches)

    # Placeholder for PTDF result
    PTDF_matrix = SparseArrays.spzeros(num_branches, num_nodes)

    # Construct A and X matrices
    for (_, line) in AC_branches
        nr = line["nr"]  # Branch internal index
        f_bus_i = bus_index[line["f_bus"]]
        t_bus_i = bus_index[line["t_bus"]]

        # Populate incidence matrix: +1 for from bus, -1 for to bus
        A[nr, f_bus_i] = 1
        A[nr, t_bus_i] = -1

        # Diagonal matrix X with branch reactance
        X[nr, nr] = line["br_x"]
    end

    # Convert sparse X to dense format and perform LU decomposition for inversion
    X = Matrix(X)
    X_lu = LinearAlgebra.lu(X)
    L = X_lu.L
    U = X_lu.U

    # Compute PTDF = inv(X) * A * B_inv using LU factors
    PTDF_matrix = inv(Matrix(U)) * inv(Matrix(L)) * A * B_inv

    return PTDF_matrix, AC_branches, bus_index
end


"""
    OFF_AC_buses(nodal_input, OFF_DC_buses)

Extracts all AC buses that are associated with offshore wind infrastructure. These include:
1. AC buses directly connected to generators labeled as "Offshore Wind".
2. AC buses connected to offshore DC buses via HVDC converters.

# Arguments
    - `nodal_input`: Dictionary containing the network data structure. Must include:
        - `"gen"`: Dictionary of generators.
        - `"convdc"`: Dictionary of DC/AC converters.
    - `OFF_DC_buses`: Dictionary of offshore DC bus indices (as strings).

# Output
    - `AC_buses`: A vector of unique AC bus indices associated with offshore infrastructure.

"""

function OFF_AC_buses(nodal_input, OFF_DC_buses)
    AC_buses = Int[]  # Initialize empty vector to store AC bus indices

    # Collect AC buses connected to offshore wind generators
    for (_, gen) in nodal_input["gen"]
        if gen["type_tyndp"] == "Offshore Wind"
            push!(AC_buses, gen["gen_bus"])
        end
    end

    # Collect AC buses linked to offshore DC buses via converters
    offshore_dc_keys = collect(keys(OFF_DC_buses))  # Offshore DC bus indices as strings
    for (_, conv) in nodal_input["convdc"]
        if string(conv["busdc_i"]) in offshore_dc_keys
            push!(AC_buses, conv["busac_i"])
        end
    end

    return unique(AC_buses)  # Return unique AC buses
end


"""
    is_point_in_polygon(point, polygon)

Determines whether a given point is inside a polygon using the ray casting algorithm.

# Arguments
    - `point`: A tuple `(latitude, longitude)` representing the point to test.
    - `polygon`: A vector of tuples `[(lat1, lon1), (lat2, lon2), ...]` defining the polygon's vertices.
    The polygon is assumed to be closed (first and last point connected).

# Output
    - `inside`: `true` if the point lies inside the polygon, otherwise `false`.

"""

function is_point_in_polygon(point, polygon)
    lat, lon = point
    n = length(polygon)
    inside = false
    j = n  # Previous vertex index (last point to first)

    for i in 1:n
        lat_i, lon_i = polygon[i]
        lat_j, lon_j = polygon[j]

        # Check if the horizontal ray crosses the edge (i, j)
        if ((lon_i > lon) != (lon_j > lon)) &&
           (lat < (lat_j - lat_i) * (lon - lon_i) / (lon_j - lon_i) + lat_i)
            inside = !inside
        end
        j = i  # Move to next edge
    end

    return inside
end

"""
    update_connectionzone(OFF_dc_buses)

Filters offshore DC buses based on whether they lie within a predefined polygonal connection zone.

# Arguments
    - `OFF_dc_buses`: Dictionary mapping DC bus IDs (as strings) to their properties, including `"lat"` and `"lon"`.

# Output
    - `updated_OFF_dc_buses`: Dictionary with only the DC buses located inside the connection zone polygon.

# Description
    This function defines a polygon (representing the North Sea connection zone) and filters
    the input DC buses, keeping only those whose latitude and longitude fall within the polygon
    (using the `is_point_in_polygon` function, based on the ray casting algorithm).

"""

function update_connectionzone(OFF_dc_buses)
    updated_OFF_dc_buses = Dict{String, Dict{String, Any}}()

    # Define polygon around North Sea connection zone
    polygon = [
        (59.328063, -1.764659),
        (56.055162, -2.804328),
        (51.148378,  2.795292),
        (54.145881,  8.978585),
        (57.816142,  8.504350)
    ]

    for (b, bus) in OFF_dc_buses
        point = (bus["lat"], bus["lon"])

        # Keep bus if it lies within the polygon
        if is_point_in_polygon(point, polygon)
            updated_OFF_dc_buses[string(b)] = bus
        end
    end

    return updated_OFF_dc_buses
end

"""
    candidate_lines_ext(nodal_input, OFF_dc_buses; offshore_hubs=false)

Generates candidate new and existing AC and DC line corridors for reinforcement
and expansion based on the input network data and offshore DC buses.

# Arguments
- `nodal_input`: Dictionary containing network data (buses, branches, converters, etc.).
- `OFF_dc_buses`: List of offshore DC bus indices.
- `offshore_hubs` (optional): If true, include specific offshore hubs in the DC buses.

# Returns
- `ne_branch`: Dictionary of new and reinforced AC branches.
- `ne_branchDC`: Dictionary of new and reinforced DC branches.
- `AC_new_corridor_idx`: Starting index for new AC corridors.
- `DC_new_corridor_idx`: Starting index for new DC corridors.
"""

function candidate_lines_ext(nodal_input, OFF_dc_buses, relocation_dict; offshore_hubs=false)
    # Get offshore AC buses connected to the offshore DC buses
    OFF_ac_buses = OFF_AC_buses(nodal_input, OFF_dc_buses)

    # Optionally include predefined offshore hubs (OFF1..OFF5) in DC buses
    if offshore_hubs
        OFF_hubs_buses = []
        for (b, bus) in nodal_input["busdc"]
            if bus["name"] in ["OFF1","OFF2","OFF3","OFF4","OFF5"]
                push!(OFF_hubs_buses, bus["index"])
            end
        end
        OFF_dc_buses = vcat(OFF_dc_buses, OFF_hubs_buses)
    end

    # Update offshore DC buses with connection zones
    updated_OFF_DC_buses = update_connectionzone(OFF_dc_buses)

    # Initialize containers for candidate line corridors
    CL_exisAC = Vector{Tuple{Float64, Float64}}()   # Existing AC lines
    CL_exisDC = Vector{Tuple{Float64, Float64}}()   # Existing DC lines
    CL_newAC = Vector{Tuple{Float64, Float64}}()    # New AC corridors
    CL_newDC = Vector{Tuple{Float64, Float64}}()    # New DC corridors
    CL_newDC_OFF = Vector{Tuple{Float64, Float64}}() # New offshore DC corridors

    # Collect existing AC lines from network data
    for (b, branch) in nodal_input["branch"]
        push!(CL_exisAC, (branch["f_bus"], branch["t_bus"]))
    end

    # Collect existing DC lines from network data
    for (b, dc_branch) in nodal_input["branchdc"]
        push!(CL_exisDC, (dc_branch["fbusdc"], dc_branch["tbusdc"]))
    end

    # Prepare lists of AC and DC buses outside offshore AC buses
    bus_AC = Float64[]       # AC buses outside offshore AC buses
    bus_DC = Float64[]       # DC buses outside offshore DC buses
    bus_OFF_DC = Float64[]   # Offshore DC buses
    new_OFFconn_AC = Vector{Tuple{Float64, Float64}}()  # New offshore AC connections

    # Identify AC buses outside offshore zones, collect offshore AC connections
    for bus_str in keys(nodal_input["bus"])
        bus = parse(Int, bus_str)
        if !(bus in OFF_ac_buses)
            push!(bus_AC, bus)
        else
            # For offshore AC buses, collect new offshore AC connection candidates from generators in 2040
            for (g, gen) in nodal_input["gen"]
                if gen["gen_bus"] == bus && gen["year"] == 2040
                    println("Offshore connection AC: ", gen["AC_cluster"], " - ", nodal_input["bus"]["$bus"]["onshore_bus"])
                    push!(new_OFFconn_AC, (gen["AC_cluster"], nodal_input["bus"]["$bus"]["onshore_bus"]))
                end
            end
        end
    end
    bus_AC = unique(bus_AC)

    # Separate DC buses into offshore and non-offshore
    for dc_bus_str in keys(nodal_input["busdc"])
        dc_bus = parse(Int, dc_bus_str)
        if !("$dc_bus" in keys(updated_OFF_DC_buses))
            push!(bus_DC, dc_bus)
        else
            push!(bus_OFF_DC, dc_bus)
        end
    end
    bus_DC = unique(bus_DC)
    bus_OFF_DC = unique(bus_OFF_DC)

    # Generate candidate new AC corridors between AC buses not already connected,
    # limited by distance and zone restrictions
    for (bus1, bus2) in Combinatorics.combinations(bus_AC, 2)
        if !((bus1, bus2) in CL_exisAC) && !((bus2, bus1) in CL_exisAC)
            zone1 = nodal_input["bus"]["$(Int(bus1))"]["zone"]
            zone2 = nodal_input["bus"]["$(Int(bus2))"]["zone"]
            if latlon2distance(nodal_input, Int(bus1), Int(bus2)) <= 100
                # Avoid UK to non-UK interconnections for new corridors
                if !(zone1 == "UK" && zone2 != "UK") && !(zone2 == "UK" && zone1 != "UK")
                    push!(CL_newAC, (bus1, bus2))
                end
            end
        end
    end
    # Optionally add offshore AC connections here if needed:
    # CL_newAC = vcat(CL_newAC, new_OFFconn_AC)

    # Generate candidate new DC corridors (non-offshore)
    for (bus1, bus2) in Combinatorics.combinations(bus_DC, 2)
        if !((bus1, bus2) in CL_exisDC) && !((bus2, bus1) in CL_exisDC)
            push!(CL_newDC, (bus1, bus2))
        end
    end

    # Generate candidate new DC offshore corridors
    for (bus1, bus2) in Combinatorics.combinations(bus_OFF_DC, 2)
        if !((bus1, bus2) in CL_exisDC) && !((bus2, bus1) in CL_exisDC)
            push!(CL_newDC_OFF, (bus1, bus2))
        end
    end

    # Build new branch dictionary for AC lines
    ne_branch = Dict{String, Any}()
    Branch_idx = 200000  # Starting index for new AC branches

    # Reinforce existing AC lines with updated ratings
    for (bus1, bus2) in CL_exisAC
        exis_branch = nothing
        for b in keys(nodal_input["branch"])
            branch = nodal_input["branch"][b]
            if (branch["f_bus"] == bus1 && branch["t_bus"] == bus2) || (branch["f_bus"] == bus2 && branch["t_bus"] == bus1)
                exis_branch = deepcopy(branch)
                break
            end
        end

        if exis_branch !== nothing
            if exis_branch["rate_a"] != 0.01
                # Adjust ratings based on bus index values (offshore or not)
                rating_val = (exis_branch["f_bus"] >= 50000 || exis_branch["t_bus"] >= 50000) ? 30 : 15
                exis_branch["rate_a"] = rating_val
                exis_branch["rate_b"] = rating_val
                exis_branch["rate_c"] = rating_val
            else
                # For very low rating lines, calculate rating based on converter info
                bus1_int = Int(bus1)
                rating_val = 30.01
                for (c, conv) in nodal_input["convdc"]
                    if conv["busac_i"] == bus1_int
                        corr_DC = conv["busdc_i"]
                        zone_bus = nodal_input["bus"]["$bus1_int"]["zone"]
                        rating_val = get_clustering_rating(corr_DC, relocation_dict["$zone_bus"]) / 100
                        println("Calculated rating: ", rating_val)
                    end
                end
                exis_branch["rate_a"] = rating_val
                exis_branch["rate_b"] = rating_val
                exis_branch["rate_c"] = rating_val
            end

            exis_branch["source_id"][2] = Branch_idx
            exis_branch["index"] = Branch_idx
            ne_branch["$Branch_idx"] = exis_branch
            Branch_idx += 1
        end
    end

    AC_new_corridor_idx = Branch_idx  # Save index start for new AC corridors

    # Add new AC corridors with default or calculated ratings
    for (bus1, bus2) in CL_newAC
        new_branch = deepcopy(nodal_input["branch"]["371"])  # Template branch

        if bus1 >= 50000
            bus1_int = Int(bus1)
            rating = 15
            for (c, conv) in nodal_input["convdc"]
                if conv["busac_i"] == bus1_int
                    corr_DC = conv["busdc_i"]
                    zone_bus = nodal_input["bus"]["$bus1_int"]["zone"]
                    rating = get_clustering_rating(corr_DC, relocation_dict["$zone_bus"]) / 100
                end
            end
            new_branch["rate_a"] = rating
            new_branch["rate_b"] = rating
            new_branch["rate_c"] = rating
        else
            new_branch["rate_a"] = 10
            new_branch["rate_b"] = 10
            new_branch["rate_c"] = 10
        end

        new_branch["f_bus"] = Int(bus1)
        new_branch["t_bus"] = Int(bus2)
        new_branch["source_id"][2] = Branch_idx
        new_branch["index"] = Branch_idx
        ne_branch["$Branch_idx"] = new_branch
        Branch_idx += 1
    end

    # Build new branch dictionary for DC lines
    ne_branchDC = Dict{String, Any}()
    Branch_idx = 500000  # Starting index for new DC branches

    # Reinforce existing DC lines with set ratings
    for (bus1, bus2) in CL_exisDC
        exis_branch = nothing
        for b in keys(nodal_input["branchdc"])
            branchdc = nodal_input["branchdc"][b]
            if (branchdc["fbusdc"] == Int(bus1) && branchdc["tbusdc"] == Int(bus2)) || 
               (branchdc["fbusdc"] == Int(bus2) && branchdc["tbusdc"] == Int(bus1))
                exis_branch = deepcopy(branchdc)
                break
            end
        end

        if exis_branch !== nothing
            exis_branch["rateA"] = 20
            exis_branch["rateB"] = 20
            exis_branch["rateC"] = 20
            exis_branch["source_id"][2] = Branch_idx
            exis_branch["index"] = Branch_idx
            exis_branch["name"] = "New DC branch (exis)"
            ne_branchDC["$Branch_idx"] = exis_branch
            Branch_idx += 1
        end
    end

    DC_new_corridor_idx = Branch_idx  # Save index start for new DC corridors

    # Add new offshore DC corridors with fixed ratings
    for (bus1, bus2) in CL_newDC_OFF
        new_branchdc = deepcopy(nodal_input["branchdc"]["44"])  # Template DC branch
        new_branchdc["fbusdc"] = Int(bus1)
        new_branchdc["tbusdc"] = Int(bus2)
        new_branchdc["rateA"] = 40
        new_branchdc["rateB"] = 40
        new_branchdc["rateC"] = 40
        new_branchdc["source_id"][2] = Branch_idx
        new_branchdc["index"] = Branch_idx
        new_branchdc["name"] = "New DC branch (new)"
        ne_branchDC["$Branch_idx"] = new_branchdc
        Branch_idx += 1
    end

    return ne_branch, ne_branchDC, AC_new_corridor_idx, DC_new_corridor_idx
end

"""
    update_cost_data(ne_branch, ne_branchDC, nodal_input)

Calculates construction costs for new and reinforced AC and DC branches
based on their ratings, distances, and financial assumptions.

# Arguments
    - `ne_branch`: Dictionary of AC branches to update cost data for.
    - `ne_branchDC`: Dictionary of DC branches to update cost data for.
    - `nodal_input`: Network data used to calculate distances.

# Output
    - Updated `ne_branch` and `ne_branchDC` dictionaries with cost fields added.
"""

function update_cost_data(ne_branch, ne_branchDC, nodal_input)
    # Cost assumptions and financial parameters
    AC_cost_MWkm = 0.0012
    DC_cost_MWkm = 0.00234
    interest = 0.05
    lifetime_AC = 40
    lifetime_DC = 30

    # Annuity factors for cost amortization
    annuity_AC = interest / (1 - (1 + interest)^(-lifetime_AC))
    annuity_DC = interest / (1 - (1 + interest)^(-lifetime_DC))

    # Calculate construction cost for each AC branch
    for (b, branch) in ne_branch
        f_bus = branch["f_bus"]
        t_bus = branch["t_bus"]
        P = branch["rate_a"] * 100  # Convert rating to MW
        d = latlon2distance(nodal_input, Int(f_bus), Int(t_bus))
        AC_cost = AC_cost_MWkm * d * P * 1e6  # Euro
        AC_cost_year = AC_cost * annuity_AC
        AC_cost_hour = AC_cost_year / 8760  # hours/year
        branch["construction_cost"] = AC_cost_hour / 100  # Normalize cost
    end

    # Calculate construction cost for each DC branch
    for (b, branchdc) in ne_branchDC
        f_bus = branchdc["fbusdc"]
        t_bus = branchdc["tbusdc"]
        P = branchdc["rateA"] * 100  # Convert rating to MW
        d = latlon2distance(nodal_input, Int(f_bus), Int(t_bus))
        DC_cost = DC_cost_MWkm * d * P * 1e6  # Euro
        DC_cost_year = DC_cost * annuity_DC
        DC_cost_hour = DC_cost_year / 8760
        branchdc["cost"] = DC_cost_hour / 100
    end

    return ne_branch, ne_branchDC
end

"""
    get_dual_branch(AC_branches, nodal_result, number_of_hours, start_hour)

Extracts the absolute difference of dual variables (λ_KCL) at both ends of each AC branch over multiple hours.

# Arguments
    - `AC_branches`: Dictionary of AC branch data, indexed by (from_bus, to_bus), each with `"nr"`, `"f_bus"`, `"t_bus"` keys.
    - `nodal_result`: Result dictionary containing dual values (`lam_kcl_r`) per bus and time step.
    - `number_of_hours`: Number of hours over which to extract the values.
    - `start_hour`: The starting hour index in `nodal_result`.

# Returns
    - `Lambda_matrix`: Matrix of size (branches x number_of_hours), where each element is the absolute difference in dual values at both ends of a branch.

# Description
    - For each branch and each time step, the λ (dual variable of KCL) at the `from_bus` and `to_bus` is retrieved.
    - The absolute difference is stored, giving insight into shadow prices or congestion.
    - If the bus is not found in the results, a default value of 0 is used.

"""

function get_dual_branch(AC_branches, nodal_result, number_of_hours, start_hour)

    Lambda_matrix = zeros(length(AC_branches), number_of_hours)  # Preallocate result matrix

    for (_, line) in AC_branches
        nr = line["nr"]              # Branch index
        f_bus = line["f_bus"]        # From bus
        t_bus = line["t_bus"]        # To bus

        lambda_f = Float64[]         # Store λ at from_bus over time
        lambda_t = Float64[]         # Store λ at to_bus over time

        for j in 1:number_of_hours
            i = j + start_hour - 1   # Actual time index in result data

            # Check if from bus exists in result, else assign 0
            if string(f_bus) in keys(nodal_result["$i"]["solution"]["bus"])
                push!(lambda_f, nodal_result["$i"]["solution"]["bus"]["$f_bus"]["lam_kcl_r"])
            else
                push!(lambda_f, 0.0)
            end

            # Check if to bus exists in result, else assign 0
            if string(t_bus) in keys(nodal_result["$i"]["solution"]["bus"])
                push!(lambda_t, nodal_result["$i"]["solution"]["bus"]["$t_bus"]["lam_kcl_r"])
            else
                push!(lambda_t, 0.0)
            end
        end

        # Compute absolute difference for each time step and store in matrix
        lambda_branch = abs.(lambda_f .- lambda_t)
        Lambda_matrix[nr, :] = lambda_branch
    end

    return Lambda_matrix
end


"""
    winsorize_matrix!(matrix, lower_pct, upper_pct)

Applies Winsorization to a matrix, limiting its values within specified lower and upper percentiles.

# Arguments
    - `matrix`: The input matrix to modify in place.
    - `lower_pct`: Lower percentile cutoff (e.g., 0.01 for 1st percentile).
    - `upper_pct`: Upper percentile cutoff (e.g., 0.99 for 99th percentile).

# Output
    - `Nothing`: Modifies `matrix` in place.

# Description
    - This technique reduces the influence of extreme outliers by capping all values below the lower percentile and above the upper percentile.

"""

function winsorize_matrix!(matrix, lower_pct, upper_pct)
    # Flatten the matrix into a 1D vector
    flat_data = vec(matrix)

    # Calculate the lower and upper quantile cutoffs
    lower = Statistics.quantile(flat_data, lower_pct)
    upper = Statistics.quantile(flat_data, upper_pct)

    # Clamp all values in the matrix between the quantile thresholds
    matrix .= clamp.(matrix, lower, upper)
end

"""
    PTDF_analysis_full(nodal_input, number_of_hours, ne_branch, ne_branchDC)

Performs a full PTDF-based sensitivity and clustering analysis of candidate reinforcements.

# Arguments
- `nodal_input`: Input network data containing buses, branches, branchDCs, and converters.
- `number_of_hours`: Number of time steps (e.g., hourly results) for which the dual values are available.
- `ne_branch`: Dictionary of candidate AC branches (indexed with keys as IDs).
- `ne_branchDC`: Dictionary of candidate DC branches (indexed with keys as IDs).

# Returns
- `Impact_matrix`: List of power flow impact matrices per hour (size: n_branches x n_selected_candidates).
- `selected_indices_AC`: Selected representative AC reinforcement indices (original indices from `ne_branch`).
- `selected_indices_DC`: Selected representative DC reinforcement indices (original indices from `ne_branchDC`).
- `dc_to_ac_map`: Mapping from DC bus IDs to their corresponding AC buses (used in PTDF projection).

# Description
    - Computes the Power Transfer Distribution Factor (PTDF) matrix.
    - Constructs a Power Flow sensitivity matrix based on reinforcement impact.
    - Applies PCA and clustering (MiniBatchKMeans) to reduce the number of candidate reinforcements.
    - Computes the impact of reinforcements on branch shadow prices (dual KCL variables).
    - Applies winsorization to stabilize dual values before computing final impact matrices.

# Notes
- Assumes candidate AC branches are indexed starting at 200000, and DC branches at 500000.
"""

function PTDF_analysis_full(nodal_input, nodal_result, number_of_hours, ne_branch, ne_branchDC)

    # Compute the PTDF matrix, AC branch data, and bus indexing map
    PTDF_matrix, AC_branches, bus_index = get_PTDF_matrix(nodal_input)

    # Total number of reinforcement candidates (AC + DC)
    amount_cand = length(ne_branch) + length(ne_branchDC)
    Powerflow_matrix = zeros(size(PTDF_matrix, 1), amount_cand)

    println("Start computing PowerFlow matrix")

    # Precompute DC-to-AC bus mapping via converters for efficient lookup
    dc_to_ac_map = Dict(conv["busdc_i"] => conv["busac_i"] for (_, conv) in nodal_input["convdc"])

    # Construct tuples: (from_idx, to_idx, column_idx_in_matrix, capacity)
    ac_branch_indices = [
        (bus_index[branch["f_bus"]], bus_index[branch["t_bus"]], parse(Int, idx) - 200000 + 1, branch["rate_a"])
        for (idx, branch) in ne_branch
    ]

    dc_branch_indices = [
        (bus_index[dc_to_ac_map[branchDC["fbusdc"]]], bus_index[dc_to_ac_map[branchDC["tbusdc"]]], 
         parse(Int, idx) - 500000 + 1 + length(ne_branch), branchDC["rateA"])
        for (idx, branchDC) in ne_branchDC
    ]

    # Fill in the Powerflow matrix: absolute PTDF diff * branch capacity
    for i in 1:size(PTDF_matrix, 1)
        for (f_idx, t_idx, j, rating) in ac_branch_indices
            rating = (rating == 0.01) ? 70 : rating  # Replace invalid ratings with default
            Powerflow_matrix[i, j] = abs(PTDF_matrix[i, t_idx] - PTDF_matrix[i, f_idx]) * rating
        end
        for (f_idx, t_idx, j, rating) in dc_branch_indices
            Powerflow_matrix[i, j] = abs(PTDF_matrix[i, t_idx] - PTDF_matrix[i, f_idx]) * rating
        end
    end

    # Apply PCA separately to AC and DC branches to reduce dimensionality
    @time pca_AC = MultivariateStats.fit(MultivariateStats.PCA, Powerflow_matrix[:, 1:length(ne_branch)]; maxoutdim=100)
    @time X_reduced_AC = MultivariateStats.transform(pca_AC, Powerflow_matrix[:, 1:length(ne_branch)])

    @time pca_DC = MultivariateStats.fit(MultivariateStats.PCA, Powerflow_matrix[:, length(ne_branch)+1:end]; maxoutdim=300)
    @time X_reduced_DC = MultivariateStats.transform(pca_DC, Powerflow_matrix[:, length(ne_branch)+1:end])

    # Apply k-means clustering to group similar reinforcements
    @time result_AC = Clustering.kmeans(X_reduced_AC, 1200; maxiter=105)
    @time result_DC = Clustering.kmeans(X_reduced_DC, 200; maxiter=105)

    assignment_AC = result_AC.assignments
    assignment_DC = result_DC.assignments

    # Store one representative candidate per cluster (AC)
    cluster_to_index_AC = Dict{Int, Int}()
    for (idx, cl) in enumerate(assignment_AC)
        if !haskey(cluster_to_index_AC, cl)
            cluster_to_index_AC[cl] = idx
        end
    end

    # Store one representative candidate per cluster (DC)
    cluster_to_index_DC = Dict{Int, Int}()
    for (idx, cl) in enumerate(assignment_DC)
        if !haskey(cluster_to_index_DC, cl)
            cluster_to_index_DC[cl] = idx
        end
    end

    # Build mapping of full cluster content to original line identifiers
    clusters = DataStructures.DefaultDict{Int, Vector{Int}}(Vector{Int})
    for (idx, cluster_id) in enumerate(assignment_AC)
        push!(clusters[cluster_id], idx + 200000 - 1)  # Adjust to original AC index space
    end
    for (idx, cluster_id) in enumerate(assignment_DC)
        push!(clusters[cluster_id + 1200], idx + 500000 - 1)  # DC clusters start at 1200
    end

    # Heuristically include offshore wind lines (WF): from bus > 50k, to bus < 20k
    cl_WF = []
    for (b, branch) in ne_branch
        if branch["f_bus"] > 50000 && branch["t_bus"] < 20000
            push!(cl_WF, parse(Int, b))  # Add original candidate index
        end
    end
    cl_WF = cl_WF .- (200000 - 1)  # Adjust to Powerflow_matrix indexing

    # Collect representative indices from clusters and WF heuristic
    selected_indices_AC = vcat(collect(values(cluster_to_index_AC)), cl_WF)
    selected_indices_DC = collect(values(cluster_to_index_DC)) .+ length(ne_branch)  # Offset for DC portion
    selected_indices = vcat(selected_indices_AC, selected_indices_DC)
    selected_indices_sorted = sort(selected_indices)

    # Extract submatrix corresponding to selected reinforcement candidates
    Powerflow_reduced = Powerflow_matrix[:, selected_indices_sorted]

    println("Start computing Lambda matrix")
    
    # Get dual variables (shadow prices) per hour from OPF results
    Lambda_matrix = get_dual_branch(AC_branches, nodal_result, number_of_hours, 1)

    # Winsorize values to limit high outliers (e.g., prevent exploding impacts)
    threshold = 600
    num_above_threshold = count(x -> x > threshold, Lambda_matrix)
    total_elements = length(Lambda_matrix)
    upper_pct = 1.0 - (num_above_threshold / total_elements)
    winsorize_matrix!(Lambda_matrix, 0, upper_pct)

    println("Start computing Impact matrix")

    # Multiply Powerflow_reduced with Lambda values for each hour to get impact
    @time Impact_matrix = map(h -> Powerflow_reduced .* Lambda_matrix[:, h], 1:number_of_hours)

    return Impact_matrix, selected_indices_AC, selected_indices_DC, dc_to_ac_map
end


"""
    Potential_investment_benefit(idx, ne_branch, ne_branchDC, number_of_hours, start_hour, nodal_result, factor)

Compute the potential benefit of a new investment (AC or DC link) based on nodal price differences
and voltage angle differences over a given time horizon.

# Arguments
    - `idx`: Branch index (AC if < 500000, otherwise DC).
    - `ne_branch`: Dictionary containing AC branch data keyed by index.
    - `ne_branchDC`: Dictionary containing DC branch data keyed by index.
    - `number_of_hours`: Total number of hours in the analysis period.
    - `start_hour`: Start hour index.
    - `nodal_result`: Nested dictionary containing hourly nodal simulation results.
    - `factor`: Vector of weighting factors per hour.

# Output
    - The total potential investment benefit over the analyzed period.

# Notes
    - AC branches use angle differences and reactance.
    - DC branches use fixed capacity and lambda differences.
    - Angles are converted from degrees to radians for AC computation.
"""

function Potential_investment_benefit(idx, ne_branch, ne_branchDC, number_of_hours, start_hour, nodal_result, factor)
    # Initialize storage vectors for both lambda (nodal prices) and voltage angles
    lambda_f = Float64[]  # Nodal prices at the 'from' end
    lambda_t = Float64[]  # Nodal prices at the 'to' end
    ang_f = Float64[]     # Voltage angles at the 'from' end (only for AC)
    ang_t = Float64[]     # Voltage angles at the 'to' end (only for AC)

    if idx < 500000
        # === AC branch ===
        f_bus = ne_branch["$idx"]["f_bus"]
        t_bus = ne_branch["$idx"]["t_bus"]
        cap = ne_branch["$idx"]["rate_a"]
        br_x = ne_branch["$idx"]["br_x"]

        for i in 1:number_of_hours
            h = i + start_hour - 1
            # Extract nodal prices (lam_kcl_r) and convert voltage angle to radians
            push!(lambda_f, -nodal_result["$h"]["solution"]["bus"]["$f_bus"]["lam_kcl_r"])
            push!(lambda_t, -nodal_result["$h"]["solution"]["bus"]["$t_bus"]["lam_kcl_r"])
            push!(ang_f, nodal_result["$h"]["solution"]["bus"]["$f_bus"]["va"] * π / 180)
            push!(ang_t, nodal_result["$h"]["solution"]["bus"]["$t_bus"]["va"] * π / 180)
        end

        lambda_diff = abs.(lambda_t .- lambda_f)
        theta_diff = abs.(ang_f .- ang_t)

        PB = Float64[]
        for i in 1:number_of_hours
            # Benefit based on price difference, angle difference, and reactance
            PB_i = factor[i] * lambda_diff[i] * theta_diff[i] / br_x
            push!(PB, PB_i)
        end

        return sum(PB)

    else
        # === DC branch ===
        f_busdc = ne_branchDC["$idx"]["fbusdc"]
        t_busdc = ne_branchDC["$idx"]["tbusdc"]
        cap = ne_branchDC["$idx"]["rateA"]

        for i in 1:number_of_hours
            h = i + start_hour - 1
            # Extract nodal prices (lam_kcl_r) from DC buses
            push!(lambda_f, nodal_result["$h"]["solution"]["busdc"]["$f_busdc"]["lam_kcl_r"])
            push!(lambda_t, nodal_result["$h"]["solution"]["busdc"]["$t_busdc"]["lam_kcl_r"])
        end

        lambda_diff = abs.(lambda_t .- lambda_f)

        PB = Float64[]
        for i in 1:number_of_hours
            # Benefit is linear with price difference and capacity
            PB_i = factor[i] * lambda_diff[i] * cap
            push!(PB, PB_i)
        end

        return sum(PB)
    end
end

"""
    delta_lambda(idx, number_of_hours, start_hour, nodal_result, dc_to_ac_map, ne_branch, ne_branchDC, factor)

Computes the weighted absolute difference in nodal dual variables (λ) between the 'from' and 'to' buses
of a candidate reinforcement line (AC or DC) over a given time horizon.

# Arguments
    - idx::Int: Unique identifier for the candidate line (AC < 500000, DC ≥ 500000).
    - number_of_hours::Int: Number of hours to evaluate.
    - start_hour::Int: Start hour (1-based) of the analysis period.
    - nodal_result::Dict: Dictionary of OPF results per hour, containing nodal duals.
    - dc_to_ac_map::Dict{Int, Int}: Mapping from DC buses to equivalent AC buses.
    - ne_branch::Dict{String, Any}: Dictionary of candidate AC branches.
    - ne_branchDC::Dict{String, Any}: Dictionary of candidate DC branches.
    - factor::Vector{Float64}: Hourly weight vector used to scale lambda differences.

# Output
    - delta_lambda::Float64: Weighted sum of absolute λ-differences over time.
"""

function delta_lambda(idx, number_of_hours, start_hour,nodal_result,ne_branch, ne_branchDC, factor)

    lambda_f = Float64[]  # Store λ values at the 'from' side of the branch
    lambda_t = Float64[]  # Store λ values at the 'to' side of the branch

    if idx < 500000
        # === Candidate is an AC branch ===
        f_bus = ne_branch["$idx"]["f_bus"]
        t_bus = ne_branch["$idx"]["t_bus"]

        # Collect λ values for each hour from the AC bus section
        for i in 1:number_of_hours
            h = i + start_hour - 1
            push!(lambda_f, nodal_result["$h"]["solution"]["bus"]["$f_bus"]["lam_kcl_r"])
            push!(lambda_t, nodal_result["$h"]["solution"]["bus"]["$t_bus"]["lam_kcl_r"])
        end

    else
        # === Candidate is a DC branch ===
        f_busdc = ne_branchDC["$idx"]["fbusdc"]
        t_busdc = ne_branchDC["$idx"]["tbusdc"]

        # Collect λ values for each hour from the DC bus section
        for i in 1:number_of_hours
            h = i + start_hour - 1
            push!(lambda_f, nodal_result["$h"]["solution"]["busdc"]["$f_busdc"]["lam_kcl_r"])
            push!(lambda_t, nodal_result["$h"]["solution"]["busdc"]["$t_busdc"]["lam_kcl_r"])
        end
    end

    # Compute absolute differences in λ between 'to' and 'from' buses
    lambda_diff = abs.(lambda_t .- lambda_f)

    # Scale by time weight and normalize by year (8760 hours)
    delta_lambda = Float64[]
    for i in 1:number_of_hours
        delta_lambda_i = (1 / 8760) * factor[i] * lambda_diff[i]
        push!(delta_lambda, delta_lambda_i)
    end

    # Return total impact as the sum over all hours
    return sum(delta_lambda)
end

"""
    pre_processor(nodal_input, nodal_result, Impact_matrix, selected_indices_AC, selected_indices_DC,
                  number_of_hours, factor, AC_new_corridor_idx, ne_branch, ne_branchDC; start_hour=1)

Processes AC and DC transmission line candidates for investment analysis in a transmission network expansion planning (TNEP) context.
Computes impact, potential benefits, lambda differences, costs, and selects the top-performing lines.

# Arguments
    - `nodal_input::Dict`: Input data for the power system (network topology, etc.)
    - `nodal_result::Dict`: Simulation results per timestep
    - `Impact_matrix::Vector{Matrix}`: Impact matrices per timestep
    - `selected_indices_AC::Vector{Int}`: Indices of candidate AC lines
    - `selected_indices_DC::Vector{Int}`: Indices of candidate DC lines
    - `number_of_hours::Int`: Number of simulated hours
    - `factor::Vector{Float64}`: Weight per hour (e.g., timestep scaling)
    - `AC_new_corridor_idx::Int`: Threshold index separating old and new AC corridors
    - `ne_branch::Dict`: Dictionary of new AC candidate branches
    - `ne_branchDC::Dict`: Dictionary of new DC candidate branches
    - `start_hour::Int=1`: Start hour index for simulation horizon

# Output
    - `zone_grid_final`: Updated grid dictionary containing selected AC/DC candidate lines

# Notes
    - Random selection of additional lines is included for comparison/testing
    - Only top-performing lines are added to the final network dictionary
"""

function pre_processor(nodal_input, nodal_result, Impact_matrix, selected_indices_AC, selected_indices_DC,
                       number_of_hours, factor, AC_new_corridor_idx, ne_branch, ne_branchDC, output_dir; start_hour=1)

    # Initialize storage arrays
    ImpactAC, ImpactDC = zeros(Float64, length(selected_indices_AC), 2), zeros(Float64, length(selected_indices_DC), 2)
    PB_AC, PB_DC = zeros(Float64, length(selected_indices_AC), 2), zeros(Float64, length(selected_indices_DC), 2)
    PIB_AC, PIB_DC = zeros(Float64, length(selected_indices_AC), 2), zeros(Float64, length(selected_indices_DC), 2)
    Lambda_AC, Lambda_DC = zeros(Float64, length(selected_indices_AC), 2), zeros(Float64, length(selected_indices_DC), 2)
    Cost_AC, Cost_DC = zeros(Float64, length(selected_indices_AC), 2), zeros(Float64, length(selected_indices_DC), 2)
    Total_Cost_AC, Total_Cost_DC = zeros(Float64, length(selected_indices_AC), 2), zeros(Float64, length(selected_indices_DC), 2)

    # Loop over selected AC lines
    for i in 1:length(selected_indices_AC)
        som = 0.0
        for h in 1:length(Impact_matrix)
            som += sum(Impact_matrix[h][:, i]) * factor[h]  # Weight by timestep importance
        end

        idx = sort(selected_indices_AC)[i]
        AC_index = idx + 200000 - 1

        # If AC line already exists
        if AC_index < AC_new_corridor_idx
            ImpactAC[i, :] = [AC_index, som]
        else
            f_bus = ne_branch["$AC_index"]["f_bus"]
            t_bus = ne_branch["$AC_index"]["t_bus"]
            lambda_f, lambda_t = Float64[], Float64[]

            # Collect locational marginal prices for f/t buses
            for t in 1:number_of_hours
                h = t + start_hour - 1
                push!(lambda_f, nodal_result["$h"]["solution"]["bus"]["$f_bus"]["lam_kcl_r"])
                push!(lambda_t, nodal_result["$h"]["solution"]["bus"]["$t_bus"]["lam_kcl_r"])
            end

            # Compute weighted congestion value
            som += sum(ne_branch["$AC_index"]["rate_a"] * abs.(lambda_f .- lambda_t) .* factor)
            ImpactAC[i, :] = [AC_index, som]
        end
    end

    # Loop over selected DC lines
    for i in 1:length(selected_indices_DC)
        som = 0.0
        for h in 1:length(Impact_matrix)
            som += sum(Impact_matrix[h][:, i]) * factor[h]
        end

        idx = sort(selected_indices_DC)[i]
        DC_index = idx + 500000 - length(ne_branch) - 1

        if DC_index < AC_new_corridor_idx
            ImpactDC[i, :] = [DC_index, som]
        else
            f_busdc = ne_branchDC["$DC_index"]["fbusdc"]
            t_busdc = ne_branchDC["$DC_index"]["tbusdc"]

            lambda_f, lambda_t = Float64[], Float64[]

            for t in 1:number_of_hours
                h = t + start_hour - 1
                push!(lambda_f, nodal_result["$h"]["solution"]["busdc"]["$f_busdc"]["lam_kcl_r"])
                push!(lambda_t, nodal_result["$h"]["solution"]["busdc"]["$t_busdc"]["lam_kcl_r"])
            end

            som += sum(ne_branchDC["$DC_index"]["rateA"] * abs.(lambda_f .- lambda_t) .* factor)
            ImpactDC[i, :] = [DC_index, som]
        end
    end

    # Compute additional indicators for AC lines
    for i in 1:length(selected_indices_AC)
        idx = sort(selected_indices_AC)[i]
        AC_index = idx + 200000 - 1
        PB_AC[i, :] = [AC_index,  Potential_investment_benefit(AC_index, ne_branch, ne_branchDC, number_of_hours, start_hour, nodal_result, factor)]
        Lambda_AC[i, :] = [AC_index,  delta_lambda(AC_index, number_of_hours, start_hour,nodal_result,ne_branch, ne_branchDC, factor)]
        Cost = ne_branch["$AC_index"]["construction_cost"]
        Cost_AC[i, :] = [AC_index, Cost]
        Total_Cost_AC[i, :] = [AC_index, Cost * 8760]
        PIB_AC[i, :] = [AC_index, PB_AC[i, 2] / Total_Cost_AC[i, 2]]
    end

    # Compute indicators for DC lines
    for i in 1:length(selected_indices_DC)
        idx = sort(selected_indices_DC)[i]
        DC_index = idx + 500000 - length(ne_branch) - 1
        PB_DC[i, :] = [DC_index,  Potential_investment_benefit(DC_index, ne_branch, ne_branchDC, number_of_hours, start_hour, nodal_result, factor)]
        Lambda_DC[i, :] = [DC_index,  delta_lambda(DC_index, number_of_hours, start_hour,nodal_result,ne_branch, ne_branchDC, factor)]
        Cost = ne_branchDC["$DC_index"]["cost"]
        Cost_DC[i, :] = [DC_index, Cost]
        Total_Cost_DC[i, :] = [DC_index, Cost * 8760]
        PIB_DC[i, :] = [DC_index, PB_DC[i, 2] / Total_Cost_DC[i, 2]]
    end

    #############################
    ### Write Excel summaries ###
    #############################

    AC_excel_path = joinpath(output_dir, "Impact_North_AC.xlsx")
    DC_excel_path = joinpath(output_dir, "Impact_North_DC.xlsx")

    headers = ["Index", "Impact Sum", "PB", "Lamba_diff", "Cost", "Total_Cost", "PIB"]
    XLSX.openxlsx(AC_excel_path, mode="w") do xf
        sheet = xf[1]
        sheet[1, 1:7] = headers
        for i in 1:size(ImpactAC, 1)
            sheet[i+1, :] = [ImpactAC[i, 1], ImpactAC[i, 2], PB_AC[i, 2], Lambda_AC[i, 2], Cost_AC[i, 2], Total_Cost_AC[i, 2], PIB_AC[i, 2]]
        end
    end

    XLSX.openxlsx(DC_excel_path, mode="w")  do xf
        sheet = xf[1]
        sheet[1, 1:7] = headers
        for i in 1:size(ImpactDC, 1)
            sheet[i+1, :] = [ImpactDC[i, 1], ImpactDC[i, 2], PB_DC[i, 2], Lambda_DC[i, 2], Cost_DC[i, 2], Total_Cost_DC[i, 2], PIB_DC[i, 2]]
        end
    end

    ###############################
    ### Select top-performing lines
    ###############################

    ImpactAC_sorted = ImpactAC[sortperm(ImpactAC[:, 2], rev=true), :]
    ImpactDC_sorted = ImpactDC[sortperm(ImpactDC[:, 2], rev=true), :]
    PIB_AC_sorted = PIB_AC[sortperm(PIB_AC[:, 2], rev=true), :]
    PIB_DC_sorted = PIB_DC[sortperm(PIB_DC[:, 2], rev=true), :]

    n_topAC = ceil(Int, 0.055 * size(ImpactAC_sorted, 1))
    n_topDC = ceil(Int, 0.16 * size(PIB_DC_sorted, 1))

    top_indicesAC = ImpactAC_sorted[1:n_topAC, 1]
    top_indicesDC = PIB_DC_sorted[1:n_topDC, 1]

    random_indices_AC = rand(ImpactAC_sorted[:, 1], 10)
    random_indices_DC = rand(PIB_DC_sorted[:, 1], 5)

    final_indices = unique(vcat(top_indicesAC, top_indicesDC, random_indices_AC, random_indices_DC))

    corrected_indices_AC, corrected_indices_DC = Int[], Int[]
    for i in final_indices
        if i < 500000
            push!(corrected_indices_AC, Int(i))
        else
            push!(corrected_indices_DC, Int(i))
        end
    end

    #######################
    ### Build zone_grid ###
    #######################

    zone_grid = deepcopy(nodal_input)
    zone_grid["ne_branch"] = Dict{String,Any}()
    zone_grid["branchdc_ne"] = Dict{String,Any}()

    for i in corrected_indices_AC
        zone_grid["ne_branch"]["$i"] = deepcopy(ne_branch["$i"])
    end
    for i in corrected_indices_DC
        zone_grid["branchdc_ne"]["$i"] = deepcopy(ne_branchDC["$i"])
    end

    zone_grid_final = deepcopy(zone_grid)
    for (b, branch) in zone_grid_final["branch"]
        if branch["rate_a"] == 0.01
            println(b)
            pop!(zone_grid_final["branch"], b)
        end
    end

    return zone_grid_final
end