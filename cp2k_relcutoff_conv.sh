#!/bin/bash

##Input parameters
input_file=cp2k.inp   #Template file of present system      
output_file=cp2k.out                                        
run_script=conv_test
plot_file="REL_CUTOFF.txt"                                                            

cutoff=800   #REL_CUTOFF parameter (Ry)                  
rel_cutoffs=$(seq 10 10 80) #Considered REL_CUTOFF range and step

prepare_input_files() {
    for ii in $rel_cutoffs ; do
        work_dir=rel_cutoff_${ii}Ry
        if [ ! -d $work_dir ] ; then
            mkdir $work_dir
        else 
            rm -r $work_dir/*
        fi
        sed -e "s/LT_cutoff/${cutoff}/g" \
            -e "s/LT_rel_cutoff/${ii}/g" \
            $input_file > $work_dir/$input_file
        cp $run_script $work_dir
    done
}

run_input_files() {
    for ii in $rel_cutoffs ; do
        work_dir=rel_cutoff_${ii}Ry
        if [ ! -d $work_dir ] ; then
            echo "$work_dir not exist!"
            exit
        else
            cd $work_dir
            /opt/pbs/default/bin/qsub $run_script
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
    grid_header=true
    itime=0
    for ii in $rel_cutoffs ; do
        work_dir=rel_cutoff_${ii}Ry
        total_energy=$(grep -e '^[ \t]*Total energy' $work_dir/$output_file | awk '{print $3}')
        ngrids=$(grep -e '^[ \t]*QS| Number of grid levels:' $work_dir/$output_file | awk '{print $6}')
        if $grid_header ; then
            for ((igrid=1; igrid <= ngrids; igrid++)) ; do
                printf " | NG on grid %d" $igrid >> $plot_file
            done
            printf "\n" >> $plot_file
            grid_header=false
        fi
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

