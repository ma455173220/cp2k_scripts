#!/bin/bash

##Input parameters
input_file=cp2k.inp   #Template file of present system      
output_file=cp2k.out                                        
restart_file="cp2k-1.restart"
run_script=NBT                                              
plot_file="U.txt"                                                            

U_values=$(seq 1 0.5 6) #Considered U range and step

prepare_input_files() {
    for ii in $U_values ; do
        work_dir=U_${ii}
        if [ ! -d $work_dir ] ; then
            mkdir $work_dir
        else 
            echo "Directory '$work_dir' already exists. Do you want to delete existing files? (y/n)"
            read response
            if [ "$response" == "Y" ] || [ "$response" == "y" ]; then
                rm -r $work_dir/*
            else
                echo "Skipping deletion of existing files in '$work_dir'."
                continue  
            fi
        fi

        sed -e "s/LT_U/${ii}/g" $input_file > $work_dir/$input_file
        cp $run_script $work_dir

    done
}

# Detect the batch scheduler (PBS on Gadi, Slurm on Setonix)
detect_scheduler() {
    if command -v qsub >/dev/null 2>&1; then
        echo "pbs"
    elif command -v sbatch >/dev/null 2>&1; then
        echo "slurm"
    else
        echo "none"
    fi
}

run_input_files() {
    case "$(detect_scheduler)" in
        pbs)
            submit_cmd="qsub"
            [ -x /opt/pbs/default/bin/qsub ] && submit_cmd="/opt/pbs/default/bin/qsub"
            ;;
        slurm) submit_cmd="sbatch" ;;
        *) echo "Neither qsub nor sbatch found, cannot submit jobs."; exit 1 ;;
    esac
    for ii in $U_values ; do
        work_dir=U_${ii}
        if [ ! -d $work_dir ] ; then
            echo "$work_dir not exist!"
            exit
        else
            cd $work_dir
            $submit_cmd $run_script
            echo "$work_dir: job submitted!"
            cd ..
        fi
    done
}

analysis() {
    echo "# U vs lattice parameters" > $plot_file
    echo "# Date: $(date)" >> $plot_file
    echo "# PWD: $PWD" >> $plot_file
    echo -e "#  U  |   A   |   B   |   C   |   delta_A(%)   |   delta_B(%)   |   delta_C(%)" >> $plot_file
    for ii in $U_values ; do
        work_dir=U_${ii}
        check_job=$(grep "PROGRAM ENDED AT" $work_dir/$output_file)
        if [ -n "$check_job" ]; then
            A_ref=$(grep "^\s*A " $work_dir/$input_file | awk '{print $2}' | xargs printf "%.16f")
            B_ref=$(grep "^\s*B " $work_dir/$input_file | awk '{print $3}' | xargs printf "%.16f")
            C_ref=$(grep "^\s*C " $work_dir/$input_file | awk '{print $4}' | xargs printf "%.16f")
            A_value=$(grep "^\s*A " $work_dir/$restart_file | awk '{print $2}' | xargs printf "%.16f")
            B_value=$(grep "^\s*B " $work_dir/$restart_file | awk '{print $3}' | xargs printf "%.16f")
            C_value=$(grep "^\s*C " $work_dir/$restart_file | awk '{print $4}' | xargs printf "%.16f")
            delta_A=$(echo "scale=6; (($A_value - $A_ref) / $A_ref) * 100" | bc)
            delta_B=$(echo "scale=6; (($B_value - $B_ref) / $B_ref) * 100" | bc)
            delta_C=$(echo "scale=6; (($C_value - $C_ref) / $C_ref) * 100" | bc)
            printf "%3.2f %11.6f %11.6f %11.6f %11.6f %11.6f %11.6f" \
                $ii $A_value $B_value $C_value $delta_A $delta_B $delta_C >> $plot_file
        else
            printf "%3.2f      N/A         N/A         N/A         N/A         N/A         N/A" $ii >> $plot_file
        fi
        printf "\n" >> $plot_file
    done
    echo "If finished normally, now check $plot_file"
}


echo "Choose an option:"
echo "1. Prepare input files"
echo "2. Run input files"
echo "3. Analysis"
read -p "Enter your choice (1/2/3): " choice

case $choice in
    1)
        prepare_input_files
        ;;
    2)
        run_input_files
        ;;
    3)
        analysis
        ;;
    *)
        echo "Invalid choice. Exiting."
        exit 1
        ;;
esac

