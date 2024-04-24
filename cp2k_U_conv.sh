#!/bin/bash

##Input parameters
input_file=cp2k.inp   #Template file of present system      
output_file=cp2k.out                                        
restart_file="cp2k-1.restart"
run_script=NBT                                              
plot_file="U.txt"                                                            

U_values=$(seq 1 0.5 7) #Considered U range and step

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
    echo -e "# U |  A  |  B  |  C" >> $plot_file
    for ii in $U_values ; do
        work_dir=U_${ii}
        A_value=$(grep "^\s*A " $work_dir/$restart_file | awk '{print $2}')
        B_value=$(grep "^\s*B " $work_dir/$restart_file | awk '{print $3}')
        C_value=$(grep "^\s*C " $work_dir/$restart_file | awk '{print $4}')
        printf "%3.2f %20.15f %20.15f %20.15f" $ii $A_value $B_value $C_value >> $plot_file
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

