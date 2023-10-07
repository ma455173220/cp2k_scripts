#Perform CUTOFF convergence test
#Written by Tian Lu (sobereva@sina.com, Beijing Kein Research Center for Natural Sciences) based on the script on CP2K website
#!/bin/bash
 
template_file=cutconv.inp   #Template file of present system
rel_cutoff=60   #REL_CUTOFF parameter (Ry)
cp2k_bin=cp2k.popt   #CP2K command
nproc_per_calc=6   #Number of CPU cores for each run, needed only for runmode=2
nproc_to_use=36   #Total number of CPU cores to use
runmode=2   #1: Run each task sequentially  2: Simultaneously run multiple tasks, should define nproc_per_calc
recalc=0  #0: Keep old folder and files if exist  1: Always remove them and recalculate
#cutoffs="50 100 150 200 250 300 350 400 450 500 550 600"   #Manually specify

cutoffs=$(seq 100 50 700) #Considered CUTOFF range and step

if [ $recalc -eq 1 ] ; then
		echo "Running: rm -r cutoff_*"
    rm -r cutoff_*
fi
input_file=test.inp
output_file=test.out
plot_file=CUTOFF.txt

#Prepare input files
for ii in $cutoffs ; do
    work_dir=cutoff_${ii}Ry
    if [ ! -d $work_dir ] ; then
        mkdir $work_dir
    fi
    sed -e "s/LT_rel_cutoff/${rel_cutoff}/g" \
        -e "s/LT_cutoff/${ii}/g" \
        $template_file > $work_dir/$input_file
done


#Run input files
if [ $runmode -eq 1 ] ; then
    for ii in $cutoffs ; do
        work_dir=cutoff_${ii}Ry
        cd $work_dir
        if [ ! -e $output_file ] ; then
            echo "Running $work_dir/$input_file"
            #$cp2k_bin -o $output_file $input_file #ssmp version
            mpirun -np $nproc_to_use $cp2k_bin -o $output_file $input_file #popt version
        else
            echo "$work_dir/$output_file has existed, skip calculation"
        fi
        cd ..
    done
else
    export OMP_NUM_THREADS=$nproc_per_calc
    counter=1
    max_parallel_calcs=$(expr $nproc_to_use / $nproc_per_calc)
    for ii in $cutoffs ; do
        work_dir=cutoff_${ii}Ry
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
echo "# Grid cutoff vs total energy" > $plot_file
echo "# Date: $(date)" >> $plot_file
echo "# PWD: $PWD" >> $plot_file
echo "# REL_CUTOFF = $rel_cutoff" >> $plot_file
echo -n "#   Cutoff |  Energy (Hartree)  |   delte E  " >> $plot_file
grid_header=true
itime=0
for ii in $cutoffs ; do
    work_dir=cutoff_${ii}Ry
    total_energy=$(grep -e '^[ \t]*Total energy' $work_dir/$output_file | awk '{print $3}')
    ngrids=$(grep -e '^[ \t]*QS| Number of grid levels:' $work_dir/$output_file | \
             awk '{print $6}')
    if $grid_header ; then
        for ((igrid=1; igrid <= ngrids; igrid++)) ; do
            printf " | NG on grid %d" $igrid >> $plot_file
        done
        printf "\n" >> $plot_file
        grid_header=false
    fi
    if (( $itime == 0 )); then
      printf "%10.1f  %18.10f               " $ii $total_energy >> $plot_file
    else
      E_var=$(echo "$total_energy - $E_last" | bc)
      printf "%10.1f  %18.10f  %13.10f" $ii $total_energy $E_var >> $plot_file
    fi
    for ((igrid=1; igrid <= ngrids; igrid++)) ; do
        grid=$(grep -e '^[ \t]*count for grid' $work_dir/$output_file | \
               awk -v igrid=$igrid '(NR == igrid){print $5}')
        printf "%12d   " $grid >> $plot_file
    done
    printf "\n" >> $plot_file
    E_last=$total_energy
    itime=$(($itime+1))
done

echo "If finished normally, now check $plot_file"