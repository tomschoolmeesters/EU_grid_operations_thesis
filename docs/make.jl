using Pkg
Pkg.activate(@__DIR__)
Pkg.instantiate()

using Documenter, EUGridOperations

makedocs(
    sitename = "EU_grid_operations Documentation",
    modules = [EU_grid_operations],
    format = Documenter.HTML(),
    pages = [
        "Home" => "index.md"
        ]
)

deploydocs(
    repo = "github.com/tomschoolmeesters/EU_grid_operations_thesis.git",
    devbranch = "main",
    target = "build"
)
