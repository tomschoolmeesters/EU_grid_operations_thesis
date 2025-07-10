using Documenter, EU_grid_operations

makedocs(
    modules = [EU_grid_operations],
    sitename = "EU_grid_operations",
    warnonly = :missing_docs,
    format = Documenter.HTML(),
    pages = [
        "Home" => "index.md"
     ]
)

deploydocs(
    repo = "github.com/tomschoolmeesters/EU_grid_operations_thesis.git",
    target = "build",
    branch = "main",
    devbranch = "main",
    versions = nothing
)