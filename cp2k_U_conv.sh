#!/bin/bash

##Input parameters
input_file=cp2k.inp   #Template file of present system      
output_file=cp2k.out                                        
restart_file="cp2k-1.restart"
run_script=NBT                                              
plot_file="U.txt"                                                            

U_values=$(seq 0.5 0.5 7) #Considered U range and step

prepare_input_files() {
    for ii in $U_values ; do
        work_dir=U_${ii}
        if [ ! -d $work_dir ] ; then
            mkdir $work_dir
        else 
            rm -r $work_dir/*
        fi
        sed -e "s/LT_U/${ii}/g" \
            $input_file > $work_dir/$input_file
        cp $run_script $work_dir
    done
}

run_input_files() {
    for ii in $U_values ; do
        work_dir=U_${ii}
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

