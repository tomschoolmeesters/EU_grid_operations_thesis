using SparseArrays
using Documenter, EU_grid_operations

makedocs(
    modules = [EU_grid_operations],
    sitename = "EU_grid_operations",
    format = Documenter.HTML(),
    pages = [
    "Home" => "src/index.md"
    ]
)

deploydocs(
    repo = "https://github.com/tomschoolmeesters/EU_grid_operations_thesis.git",
    branch = "main",
    devbranch = "main",  # change if your main branch has a different name
    target = "build",
    versions = nothing
)