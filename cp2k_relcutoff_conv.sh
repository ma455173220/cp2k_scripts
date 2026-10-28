#!/bin/bash

##Input parameters
submit_cmd=""  # "qsub" or "sbatch"; leave empty to auto-detect (PBS -> qsub, Slurm -> sbatch)
input_file=cp2k.inp   #Template file of present system      
output_file=cp2k.out                                        
run_script=conv_test
plot_file="REL_CUTOFF.txt"                                                            

cutoff=800   #CUTOFF parameter (Ry)                  
rel_cutoffs=$(seq 10 10 80) #Considered REL_CUTOFF range and step

prepare_input_files() {
    for ii in $rel_cutoffs ; do
        work_dir=rel_cutoff_${ii}Ry
        if [ ! -d $work_dir ] ; then
            mkdir $work_dir
        else 
            read -p "Directory '$work_dir' already exists. Do you want to delete existing files? [y/N] " response
            if [ "$response" == "Y" ] || [ "$response" == "y" ]; then
                rm -r $work_dir/*
            else
                echo "Skipping '$work_dir' (existing files kept)."
                continue
            fi
        fi
        sed -e "s/LT_cutoff/${cutoff}/g" \
            -e "s/LT_rel_cutoff/${ii}/g" \
            $input_file > $work_dir/$input_file
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
    if [ -z "$submit_cmd" ] ; then
        case "$(detect_scheduler)" in
            pbs)   submit_cmd="qsub" ;;
            slurm) submit_cmd="sbatch" ;;
            *) echo "Neither qsub nor sbatch found, cannot submit jobs."; exit 1 ;;
        esac
    fi
    for ii in $rel_cutoffs ; do
        work_dir=rel_cutoff_${ii}Ry
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
    echo "# Grid cutoff vs total energy" > $plot_file
    echo "# Date: $(date)" >> $plot_file
    echo "# PWD: $PWD" >> $plot_file
    echo "# CUTOFF = $cutoff" >> $plot_file
    echo -n "#Rel_Cutoff |  Energy (Hartree)  |  delte E " >> $plot_file
    # Number of grid levels, taken from the first finished run (for the header)
    ngrids=0
    for ii in $rel_cutoffs ; do
        work_dir=rel_cutoff_${ii}Ry
        if grep -q "PROGRAM ENDED AT" $work_dir/$output_file 2>/dev/null; then
            ngrids=$(grep -e '^[ \t]*QS| Number of grid levels:' $work_dir/$output_file | head -1 | awk '{print $6}')
            break
        fi
    done
    for ((igrid=1; igrid <= ngrids; igrid++)) ; do
        printf " | NG on grid %d" $igrid >> $plot_file
    done
    printf "\n" >> $plot_file
    itime=0
    for ii in $rel_cutoffs ; do
        work_dir=rel_cutoff_${ii}Ry
        # Unfinished or missing run: N/A in every column (rows stay aligned; delta E skips this point)
        if ! grep -q "PROGRAM ENDED AT" $work_dir/$output_file 2>/dev/null; then
            printf "%10.1f  %18s       N/A   " $ii "N/A" >> $plot_file
            for ((igrid=1; igrid <= ngrids; igrid++)) ; do
                printf "%12s   " "N/A" >> $plot_file
            done
            printf "\n" >> $plot_file
            echo "Warning: $work_dir/$output_file missing or run not finished" >&2
            continue
        fi
        total_energy=$(grep -e '^[ \t]*Total energy' $work_dir/$output_file | tail -1 | awk '{print $3}')
        if (( $itime == 0 )); then
            printf "%10.1f  %18.10f       N/A   " $ii $total_energy >> $plot_file
        else
            E_var=$(echo "$total_energy - $E_last" | bc)
            absolute_E_var=$(echo "if ($E_var < 0) $E_var * -1 else $E_var" | bc -l)
            if (( $(echo "$absolute_E_var < 0.000001" | bc -l) )); then
                printf "xx %7.1f  %18.10f  %11.2e" $ii $total_energy $E_var >> $plot_file
            else
                printf "%10.1f  %18.10f  %11.2e" $ii $total_energy $E_var >> $plot_file
            fi
        fi
        for ((igrid=1; igrid <= ngrids; igrid++)) ; do
            grid=$(grep -e '^[ \t]*count for grid' $work_dir/$output_file | awk -v igrid=$igrid '(NR == igrid){print $5}')
            printf "%12d   " $grid >> $plot_file
        done
        printf "\n" >> $plot_file
        E_last=$total_energy
        itime=$(($itime+1))
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

