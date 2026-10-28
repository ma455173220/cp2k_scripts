#!/bin/bash
 
eps_schwarz="2 3 4 5 6 7 8"
 
input_file=Si_bulk.inp
output_file=Si_bulk.out
plot_file=cutoff_data.ssv
 
 
echo "# eps_schwarz vs total energy" > $plot_file
echo "# Date: $(date)" >> $plot_file
echo "# PWD: $PWD" >> $plot_file
echo -n "# eps_schwarz | Total Energy (Ha)" >> $plot_file
# Number of grid levels, taken from the first finished run (for the header)
ngrids_header=0
for ii in $eps_schwarz; do
    work_dir=eps_schwarz_${ii}
    if grep -q "PROGRAM ENDED AT" $work_dir/$output_file 2>/dev/null; then
        ngrids_header=$(grep -e '^[ \t]*QS| Number of grid levels:' $work_dir/$output_file | head -1 | awk '{print $6}')
        break
    fi
done
for ((igrid=1; igrid <= ngrids_header; igrid++)) ; do
    printf " | NG on grid %d" $igrid >> $plot_file
done
printf " | Time" >> $plot_file
printf "\n" >> $plot_file

for ii in $eps_schwarz; do
    work_dir=eps_schwarz_${ii}
    # Unfinished or missing run: N/A in every column, so the rows stay aligned
    if ! grep -q "PROGRAM ENDED AT" $work_dir/$output_file 2>/dev/null; then
        printf "%10.2f  %15s" $ii "N/A" >> $plot_file
        for ((igrid=1; igrid <= ngrids_header; igrid++)) ; do
            printf "  %6s" "N/A" >> $plot_file
        done
        printf "  %10s\n" "N/A" >> $plot_file
        echo "Warning: $work_dir/$output_file missing or run not finished" >&2
        continue
    fi
    total_energy=$(grep -e 'ENERGY| Total FORCE_EVAL' $work_dir/$output_file | tail -1 | awk -F ' ' '{print $NF}')
    printf "%10.2f  %15.10f" $ii $total_energy >> $plot_file
    for ((igrid=1; igrid <= ngrids_header; igrid++)) ; do
        grid=$(grep -e '^[ \t]*count for grid' $work_dir/$output_file | \
               awk -v igrid=$igrid '(NR == igrid){print $5}')
        printf "  %6d" $grid >> $plot_file
    done
    # Total wall time: last field of the "CP2K   1  ..." line of the timing report
    computational_time=$(grep -E '^ CP2K +1 ' $work_dir/$output_file | tail -1 | awk '{print $NF}')
    if [ -n "$computational_time" ]; then
        printf "  %10.5f"  $computational_time >> $plot_file
    else
        printf "  %10s" "N/A" >> $plot_file
    fi
    printf "\n" >> $plot_file
done
