#!/bin/bash
 
rel_cutoffs="10 20 30 40 50 60 70 80 90 100"
 
input_file=cp2k.inp
output_file=cp2k.out
plot_file=rel_cutoff_data.ssv
 
 
echo "# Rel Grid cutoff vs total energy" > $plot_file
echo "# Date: $(date)" >> $plot_file
echo "# PWD: $PWD" >> $plot_file
echo -n "# Rel Cutoff (Ry) | Total Energy (Ha)" >> $plot_file
grid_header=true
for ii in $rel_cutoffs ; do
    work_dir=rel_cutoff_${ii}Ry
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
