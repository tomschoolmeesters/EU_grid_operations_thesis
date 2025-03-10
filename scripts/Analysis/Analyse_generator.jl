function Analyse_generator(g,start_hour,planning_year) # generator index g, start hour and planning year (2025,2030,2040)
    
    #Get information about gen
    type = nodal_input["gen"]["$g"]["type_tyndp"]
    zone = nodal_input["gen"]["$g"]["zone"]
    bus = nodal_input["gen"]["$g"]["gen_bus"]
    pmax = nodal_input["gen"]["$g"]["pmax"]*100 #MW
#    start_date = hour_to_date(planning_year, start_hour)
#    end_date = hour_to_date(planning_year, start_hour+number_of_hours-1)

    println("--------------------------------")
    println("Generator index: ",g)
    println("Generator type: ",type)
    println("Generator zone: ",zone)
    println("Generator bus: ",bus)
    println("Theoretical maximum power:", pmax," MW")
 #   println("Analysed period: vanaf ",start_date," tot ",end_date)
    println("--------------------------------")

    #Determine produced energy profile
    production = []
    for i in start_hour:(start_hour+number_of_hours-1)
        
        if nodal_result["$i"]["objective"] !== nothing
            push!(production,nodal_result["$i"]["solution"]["gen"]["$g"]["pg"]*100)
        else
            push!(production,0.0001) #0.0001 so I can highlight the infeasible time periods
        end
    end

    P1 = Plots.plot(production,label="Prodcuction")
    title!("Production profile of generator $g")
    xlabel!("Time [h]")
    ylabel!("Power [MW]")

    time = 1:length(production)
    highlight_indices = findall(x -> x == 0.0001, production)
    scatter!(time[highlight_indices], production[highlight_indices], label="Infeasible", color=:red, marker=:circle)

    if !(nodal_input["gen"]["$g"]["type_tyndp"] in ["Offshore wind","Onshore Wins","Solar PV"])
        display(P1)
    end
    
    #Calculate curtailment 
        #If Offshore Wind
    if nodal_input["gen"]["$g"]["type_tyndp"] == "Offshore Wind"
        gen_type = "wind_offshore"
        Curtailment,Uncurtailed = RES_curtailment_WO(g,gen_type,nodal_result, nodal_input, timeseries_data,start_hour)
        
        plot!(Uncurtailed, label="uncurtailed_energy")
        display(P1)
        
        P2 = Plots.plot(Curtailment*100,label = "Curtailment")
        title!("Curtailment of generator $g")
        xlabel!("Time [h]")
        ylabel!("Curtailment [%]")
        display(P2)
        #Print the moments at which the curtailment is higher than 50%
        high_curt = findall(x -> x>0.5,Curtailment)
        high_curt = high_curt .+ (start_hour - 1)
        high_curt_dates = []
        for hour in high_curt
            push!(high_curt_dates,hour_to_date(planning_year,hour))
        end
        #
        #println("At the following dates, curtailment is above 50%:")
        #for date in high_curt_dates
        #    println(date)
        #end
        println("--------------------------------")

        #If Onshore Wind
    elseif nodal_input["gen"]["$g"]["type_tyndp"] == "Onshore Wind"
        gen_type = "wind_onshore"
        Curtailment,Uncurtailed = RES_curtailment_WO(g,gen_type,nodal_result, nodal_input, timeseries_data,start_hour)
        
        plot!(Uncurtailed, label="uncurtailed_energy")
        display(P1)
        
        P2 = Plots.plot(Curtailment*100,label = "Curtailment")
        title!("Curtailment of generator $g")
        xlabel!("Time [h]")
        ylabel!("Curtailment [%]")
        display(P2)

        #Print the moments at which the curtailment is higher than 50%
        high_curt = findall(x -> x>0.5,Curtailment)
        high_curt = high_curt .+ (start_hour - 1)
        high_curt_dates = []
        for hour in high_curt
            push!(high_curt_dates,hour_to_date(planning_year,hour))
        end

        #println("At the following dates, curtailment is above 50%:")
        #for date in high_curt_dates
        #    println(date)
        #end
        println("--------------------------------")

        #If Solar PV
    elseif nodal_input["gen"]["$g"]["type_tyndp"] == "Solar PV"
        gen_type = "solar_pv"
        Curtailment,Uncurtailed = RES_curtailment_WO(g,gen_type,nodal_result, nodal_input, timeseries_data,start_hour)
        plot!(Uncurtailed,label = "Uncurtailed energy")
        
        
        display(P1)
        P2 = Plots.plot(Curtailment*100,label = "Curtailment")
        title!("Curtailment of generator $g")
        xlabel!("Time [h]")
        ylabel!("Curtailment [%]")
        display(P2)

        #Print the moments at which the curtailment is higher than 50%
        high_curt = findall(x -> x>0.5,Curtailment)
        high_curt = high_curt .+ (start_hour - 1)
        high_curt_dates = []
        for hour in high_curt
            push!(high_curt_dates,hour_to_date(planning_year,hour))
        end
        #
        #println("At the following dates, curtailment is above 50%:")
        #for date in high_curt_dates
        #    println(date)
        #end
        println("--------------------------------")

    end
end