###################
### ANALYSE OPF ###
###################

include("get_grid_indices.jl")
include("Analysis/Analyse_branch.jl")
include("Analysis/Analyse_bus.jl")
include("Analysis/Analyse_generation_types.jl")
include("Analysis/Analyse_generator.jl")
include("Analysis/where_curtailment.jl")
include("Analysis/Analyse_load.jl")
include("Analysis/Line_loading.jl")


##############################################
#### LOAD ZONAL TYNDP SCENARIO DATA ##########
##############################################
tyndp_version = "2024"
scenario = "DE"
Year = "2030"
climate_year = "2009"
zones = ["BE"]

zonal_result, zonal_input, scenario_data = _EUGO. load_results(tyndp_version, scenario, Year, climate_year, "zonal") # Import zonal results
                                                
print("ALL ZONAL FILES LOADED", "\n")
print("----------------------","\n")

##############################################
#### LOAD NODAL TYNDP SCENARIO DATA ##########
##############################################
#Run this to load the right simulation scenario

tyndp_version = "2020"
scenario = "DE"
Year = "2040"
climate_year = "2007"
zones = ["BE","UK","DE","NL","FR"]
nodal_result, nodal_input, timeseries_data = _EUGO. load_results(tyndp_version, scenario, Year, climate_year, "nodal") # Import nodal results

print("ALL NODAL FILES LOADED", "\n")
print("----------------------","\n")





  
