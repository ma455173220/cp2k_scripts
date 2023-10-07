#Perform k-point convergence test
#Written by Tian Lu (sobereva@sina.com, Beijing Kein Research Center for Natural Sciences)
#!/bin/bash
 
template_file=kpconv.inp   #Template file of present system
kpoint_list=XYZ.txt   #File containing k-point list
cp2k_bin=cp2k.popt   #CP2K command
runmode=1   #1: Run each task sequentially  2: Simultaneously run multiple tasks, should define nproc_per_calc
nproc_to_use=16   #Total number of CPU cores to use
nproc_per_calc=4   #Number of CPU cores for each run, needed only for runmode=2
recalc=1  #0: Keep old folder and files if exist  1: Always remove them and recalculate

input_file=test.inp
output_file=test.out
plot_file=KP.txt

if [ $recalc -eq 1 ] ; then
		echo "Running: rm -r kp_*"
    rm -r kp_*
fi
nline=`wc -l $kpoint_list |cut -d ' ' -f 1`
echo "Number of tests: $nline"

#Prepare input files
for ((i = 1; i <= $nline; i++)) ; do
    kpthis=$(awk -v iline=$i 'NR==iline' $kpoint_list)
    work_dir=kp_${i}
    if [ ! -d $work_dir ] ; then
        mkdir $work_dir
    fi
    sed -e "s/kp_test/${kpthis}/g" $template_file > $work_dir/$input_file
done


#Run input files
if [ $runmode -eq 1 ] ; then
    for ((i = 1; i <= $nline; i++)) ; do
        work_dir=kp_${i}
        cd $work_dir
        if [ ! -e $output_file ] ; then
            echo "Running $work_dir/$input_file"
            #time $cp2k_bin -o $output_file $input_file #ssmp version
            time mpirun -np $nproc_to_use $cp2k_bin -o $output_file $input_file #popt version
        else
            echo "$work_dir/$output_file has existed, skip calculation"
        fi
        cd ..
    done
else
    export OMP_NUM_THREADS=$nproc_per_calc
    counter=1
    max_parallel_calcs=$(expr $nproc_to_use / $nproc_per_calc)
    for ((i = 1; i <= $nline; i++)) ; do
        work_dir=kp_${i}
        cd $work_dir
        if [ ! -e $output_file ] ; then
            echo "Running $work_dir/$input_file"
            #$cp2k_bin -o $output_file $input_file & #ssmp version
            mpirun -np $nproc_per_calc $cp2k_bin -o $output_file $input_file & #popt version
        else
            echo "$work_dir/$output_file has existed, skip calculation"
        fi
        cd ..
        mod_test=$(echo "$counter % $max_parallel_calcs" | bc)
        if [ $mod_test -eq 0 ] ; then
            wait
        fi
        counter=$(expr $counter + 1)
    done
    wait
fi


#Analysis
echo "# k-point vs total energy" > $plot_file
echo "# Date: $(date)" >> $plot_file
echo "# PWD: $PWD" >> $plot_file
echo -n "#   k-points |  Energy (Hartree)  |   delte E  " >> $plot_file
printf "\n" >> $plot_file
itime=0
for ((i = 1; i <= $nline; i++)) ; do
    work_dir=kp_${i}
    kpthis=$(awk -v iline=$i 'NR==iline' $kpoint_list)
    total_energy=$(grep -e '^[ \t]*Total energy' $work_dir/$output_file | awk '{print $3}')
    if (( $itime == 0 )); then
      printf "     %s  %18.10f               " "$kpthis" $total_energy >> $plot_file
    else
      E_var=$(echo "$total_energy - $E_last" | bc)
      printf "     %s  %18.10f  %15.10f" "$kpthis" $total_energy $E_var >> $plot_file
    fi
    printf "\n" >> $plot_file
    E_last=$total_energy
    itime=$(($itime+1))
done

echo "If finished normally, now check $plot_file"