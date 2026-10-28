#!/bin/bash
# Hubbard U scan: prepare the U_<value> directories (placeholder LT_U in the template input),
# submit the jobs, and tabulate the lattice constants (from the restart files) against U.
#
# Usage: cp2k_U_conv.sh [-v "values"] [-i cp2k.inp] [-O cp2k.out] [-r cp2k-1.restart] [-j NBT]
#                       [prepare|submit|analyse]
#   -v VALUES   U values to scan (default: $(seq 1 0.5 6))
#   -i FILE     template input containing LT_U (default cp2k.inp)
#   -O FILE     CP2K output file name in each directory (default cp2k.out)
#   -r FILE     restart file with the optimised cell (default cp2k-1.restart)
#   -j FILE     job script copied into and submitted in each directory (default NBT)
#   Without prepare|submit|analyse (or 1|2|3) a menu is shown.

# Shared helpers (cp2k_common.sh: next to this script, else in PATH)
_lib="$(dirname "$(readlink -f "$0")")/cp2k_common.sh"
[ -f "$_lib" ] || _lib="$(command -v cp2k_common.sh)" || { echo "Error: cp2k_common.sh not found (keep it next to this script or in PATH)" >&2; exit 1; }
source "$_lib"

##Input parameters
input_file=cp2k.inp   #Template file of present system      
output_file=cp2k.out                                        
restart_file="cp2k-1.restart"
run_script=NBT                                              
plot_file="U.txt"                                                            

U_values=$(seq 1 0.5 6) #Considered U range and step

while getopts ":v:i:O:r:j:h" opt; do
    case "$opt" in
        v) U_values="$OPTARG" ;;
        i) input_file="$OPTARG" ;;
        O) output_file="$OPTARG" ;;
        r) restart_file="$OPTARG" ;;
        j) run_script="$OPTARG" ;;
        h) show_help; exit 0 ;;
        *) echo "Unknown option or missing value: -$OPTARG (see -h)"; exit 1 ;;
    esac
done
shift $((OPTIND - 1))

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

run_input_files() {
    submit_command=$(submit_cmd) || { echo "Neither qsub nor sbatch found, cannot submit jobs."; exit 1; }
    for ii in $U_values ; do
        work_dir=U_${ii}
        if [ ! -d $work_dir ] ; then
            echo "$work_dir not exist!"
            exit
        else
            submit_in_dir $work_dir $run_script "$submit_command"
            echo "$work_dir: job submitted!"
        fi
    done
}

# Print the lengths |A| |B| |C| (in Angstrom) of the &CELL section of a CP2K input/restart file
# (A/B/C vectors in any orientation, or ABC; via cp2k_inp.py). Prints an error message and fails otherwise.
cell_lengths() {
    "$cp2k_inp" get-cell "$1" --format lengths 2>&1
}

analysis() {
    cp2k_inp=$(find_script cp2k_inp.py) || exit 1
    echo "# U vs lattice parameters" > $plot_file
    echo "# Date: $(date)" >> $plot_file
    echo "# PWD: $PWD" >> $plot_file
    echo -e "#  U  |   A   |   B   |   C   |   delta_A(%)   |   delta_B(%)   |   delta_C(%)" >> $plot_file
    for ii in $U_values ; do
        work_dir=U_${ii}
        check_job=$(grep "PROGRAM ENDED AT" $work_dir/$output_file)
        ref_cell=""; new_cell=""
        if [ -n "$check_job" ]; then
            if ! ref_cell=$(cell_lengths $work_dir/$input_file); then
                echo "Warning: $work_dir/$input_file: $ref_cell" >&2; check_job=""
            elif ! new_cell=$(cell_lengths $work_dir/$restart_file); then
                echo "Warning: $work_dir/$restart_file: $new_cell" >&2; check_job=""
            fi
        fi
        if [ -n "$check_job" ]; then
            # Lattice constants are the lengths of the cell vectors (correct for non-orthogonal cells too)
            read A_ref B_ref C_ref <<< "$ref_cell"
            read A_value B_value C_value <<< "$new_cell"
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


choice="${1:-}"
if [ -z "$choice" ] ; then
    echo "Choose an option:"
    echo "1. Prepare input files"
    echo "2. Run input files"
    echo "3. Analysis"
    read -p "Enter your choice (1/2/3): " choice
fi

case $choice in
    1|prepare)
        prepare_input_files
        ;;
    2|submit|run)
        run_input_files
        ;;
    3|analyse|analyze|analysis)
        analysis
        ;;
    *)
        echo "Invalid choice. Exiting."
        exit 1
        ;;
esac

