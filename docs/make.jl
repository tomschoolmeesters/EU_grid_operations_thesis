using Documenter, EU_grid_operations

makedocs(
    modules = [EU_grid_operations],
    sitename = "EU_grid_operations",
    format = Documenter.HTML(),
    pages = [
        "Home" => "index.md"
    ]
)

deploydocs(
    repo = "github.com/tomschoolmeesters/EU_grid_operations_thesis.git",
    branch = "gh-pages",
    devbranch = "main",  # change if your main branch has a different name
    target = "build",
    versions = nothing
)