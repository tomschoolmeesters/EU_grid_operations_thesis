using Documenter, EU_grid_operations

makedocs(
    modules = [EU_grid_operations],
    sitename = "EU_grid_operations",
    warnonly = :missing_docs,
    pages = [
        "Home" => "Readme.md"
        "Manual" => []
        "Library" => []
        
    ]
)

deploydocs(
    repo = "github.com/tomschoolmeesters/EU_grid_operations_thesis.git"
)