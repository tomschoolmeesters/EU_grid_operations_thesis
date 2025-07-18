using Pkg
Pkg.activate(@__DIR__)
Pkg.instantiate()

using Documenter, EU_grid_operations

makedocs(
    sitename = "EU_grid_operations",
    modules = [EU_grid_operations],
    format = Documenter.HTML(),
    pages = [
    "Home" => "index.md",
    "Library" => 
        ["Loading and Preprocessing Data" => "loading_data.md",
        "Analyse Bus" => "bus.md",
        "Analyse Branch" => "branch.md",
        "Analyse Generator" => "generator.md",
        "Congestion and Saturation" => "congestion_saturation.md",
        "Analyse Load" => "load.md",
        "Representative Scenarios" => "representative_scenarios.md",
        "Pre-Processor" => "pre_processor.md",
        ],

    "Update of PowerModelsACDC" => "powermodelsacdc_update.md",

    "Test Cases" =>
        ["Overview" => "test_case_overview.md",
        "Zonal OPF" => "zonal_opf.md",
        "Nodal OPF" => "nodal_opf.md",
        "Nodal TNEP" => "nodal_tnep.md",
        "Post-Processing" => "post_processing.md"
        ]
    ]

)

deploydocs(
    repo = "github.com/tomschoolmeesters/EU_grid_operations_thesis.git",
    devbranch = "main",
    target = "build"
)
