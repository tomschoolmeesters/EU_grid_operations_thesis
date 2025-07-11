using Documenter
using EU_grid_operations  # pas aan naar je pakketnaam

makedocs(
    sitename = "EU_grid_operations Documentation",
    modules = [EU_grid_operations],
    format = Documenter.HTML(),
    pages = [
        "Home" => "index.md",
        "More Info" => "other_pages.md"
    ]
)

deploydocs(
    repo = "github.com/tomschoolmeesters/EU_grid_operations_thesis.git",
    target = "build"
)
