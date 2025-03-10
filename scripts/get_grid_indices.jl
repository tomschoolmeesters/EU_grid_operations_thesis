

### DATE ###
# Function to determine the dates corresponding with the given hour (1-8760)

using Dates
function hour_to_date(jaar, uur)
    # Controleer of het uur binnen het bereik valt
    if uur < 1 || uur >= 8761
        println("The specified hour must be between 1 and 8760.")
        return
    end

    # Startdatum van het jaar
    startdatum = DateTime(jaar, 1, 1, 0, 0)  # 1 januari om 00:00 uur

    # Bereken de huidige datum en tijd door uren toe te voegen aan de startdatum
    huidige_datumtijd = startdatum + Hour(uur-1)
    
    # Haal de dag, maand, jaar en uur op
    dag = day(huidige_datumtijd)
    maand = month(huidige_datumtijd)
#    jaar = year(huidige_datumtijd)
    uur_van_de_dag = hour(huidige_datumtijd)
    
    # Geef de datum en tijd terug als een string
#    return "Datum: $dag/$maand/$jaar, Uur: $uur_van_de_dag:00"
end

### GET RES CURTAILMENT ###
# Calculate the amount of RES (wind, solar) energy which is curtailed, 
# Given the generator index g, the generator type: ["Solar PV", "Offshore Wind", "Onshore Wind"], the input data set, the timeseries dataset and the starting hour of the simulation

function RES_curtailment_WO(g, gen_type, result, input, timeseries, start_hour)
    # Preallocate arrays for curtailment values and uncurtailed energy
    RES_Curtailment = zeros(number_of_hours)
    Uncurtailed = zeros(number_of_hours)

    # Iterate over the simulation hours
    for t in 1:number_of_hours
        i = start_hour + t - 1  # Calculate the actual hour index

        # Check if the result for this hour exists and is valid
        if result["$i"]["objective"] !== nothing
            # Check if the generator exists in the solution for this hour
            if haskey(result["$i"]["solution"]["gen"], "$g")
                # Fetch generator details
                zone = input["gen"]["$g"]["zone"]
                CF = timeseries["$gen_type"][zone][i]

                # Compute uncurtailed and delivered energy
                uncurtailed_energy = CF * input["gen"]["$g"]["pmax"] * 100  # in MW
                energy_delivered = result["$i"]["solution"]["gen"]["$g"]["pg"] * 100  # in MW

                # Calculate curtailment
                curtailment = uncurtailed_energy == 0.0 ? 0.0 : (uncurtailed_energy - energy_delivered) / uncurtailed_energy

                # Store values in preallocated arrays
                Uncurtailed[t] = uncurtailed_energy
                RES_Curtailment[t] = curtailment
            else
                println("Generator not in result for hour $i")
            end
        else
            # Handle infeasibility case
            RES_Curtailment[t] = 1.0
            Uncurtailed[t] = t == 1 ? 0.0 : Uncurtailed[t - 1]  # Create a flat profile if necessary
        end
    end

    return RES_Curtailment, Uncurtailed
end

### CONGESTION INDEX ###
# Compute the congestion index and plot it given the optimization result you want to analyse

function Congestion_index(hour_range)
    Congestion_index_values=Dict()
    for i in 1:100
        if result["$i"]["objective"] !== nothing
            lambda=[]
            for bus in keys(result["$i"]["solution"]["bus"])
                push!(lambda,result["$i"]["solution"]["bus"]["$bus"]["lam_kcl_r"])
            end
            for dc_bus in keys(result["$i"]["solution"]["busdc"])
                push!(lambda,result["$i"]["solution"]["busdc"]["$dc_bus"]["lam_kcl_r"])
            end
            N = length(result["$i"]["solution"]["bus"])+length(result["$i"]["solution"]["busdc"])
            lambda_average = sum(lambda)/N
            
            i_c = sum(abs.(lambda.-lambda_average))/(N*abs(lambda_average))
            Congestion_index_values[i] = i_c
        end
        
    end
    return Congestion_index_values#,lambda

end

function plot_Congestion_index(result)
    Congestion_index_values = Congestion_index(result)
    sorted_keys = sorted_keys = sort(collect(keys(Congestion_index_values)), by=x -> x)
    sorted_values = [Congestion_index_values[k] for k in sorted_keys]

    Plots.plot(sorted_keys,sorted_values)

    ylabel!("Congestion Index Value")
end



### SATURATION INDEX ###
# Function to calculate the saturation index

function Saturation_index(result,input)
    Saturation_index_values = Dict()
    for i in keys(result)
        if result["$i"]["objective"] !== nothing
            branch = collect(keys(result["$i"]["solution"]["branch"]))
            sum_power_flow = sum(abs(result["$i"]["solution"]["branch"]["$b"]["pt"]) for b in branch) #MW, Active power withdrawn at the to bus
            sum_rated_power = sum(input["branch"]["$b"]["rate_a"] for b in branch) #MVA, Long term thermal line rating
            Saturation_index_values[i] = sum_power_flow/sum_rated_power
        end
    end
    return Saturation_index_values
end

function plot_Saturation_index(result,input)
    Saturation_index_values = Saturation_index(result,input)
    sorted_keys = sort(collect(keys(Saturation_index_values)), by=x -> parse(Int, x))
    sorted_values = [Saturation_index_values[k] for k in sorted_keys]

    plot(sorted_keys,sorted_values,label="")
    ylabel!("Saturation Index Value")
end
