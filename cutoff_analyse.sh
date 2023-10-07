#!/bin/bash
 
cutoffs="50 100 150 200 250 300 350 400 450 500 550 600 650 700 750 800 850 900 950 1000 1200 1500 2000"
 
input_file=cp2k.inp
output_file=cp2k.out
plot_file=cutoff_data.ssv
 
 
echo "# Grid cutoff vs total energy" > $plot_file
echo "# Date: $(date)" >> $plot_file
echo "# PWD: $PWD" >> $plot_file
echo -n "# Cutoff (Ry) | Total Energy (Ha)" >> $plot_file
grid_header=true
for ii in $cutoffs ; do
    work_dir=cutoff_${ii}Ry
    total_energy=$(grep -e 'ENERGY| Total FORCE_EVAL' $work_dir/$output_file | awk -F ' ' '{print $NF}')
    ngrids=$(grep -e '^[ \t]*QS| Number of grid levels:' $work_dir/$output_file | \
             awk '{print $6}')
    if $grid_header ; then
        for ((igrid=1; igrid <= ngrids; igrid++)) ; do
            printf " | NG on grid %d" $igrid >> $plot_file
        done
	printf " | Time" >> $plot_file
        printf "\n" >> $plot_file
        grid_header=false
    fi
    printf "%10.2f  %15.10f" $ii $total_energy >> $plot_file
    for ((igrid=1; igrid <= ngrids; igrid++)) ; do
        grid=$(grep -e '^[ \t]*count for grid' $work_dir/$output_file | \
               awk -v igrid=$igrid '(NR == igrid){print $5}')
        printf "  %6d" $grid >> $plot_file
    done
    computational_time=`grep  "CP2K       " $work_dir/$output_file | tail -1 | awk -F ' ' '{print $NF}'`
    printf "  %10.5f"  $computational_time >> $plot_file
    printf "\n" >> $plot_file
done
