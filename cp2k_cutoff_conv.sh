#!/bin/bash
# CUTOFF (default) or REL_CUTOFF (--rel, used by cp2k_relcutoff_conv.sh) convergence test:
# prepare the directories, submit the jobs, and collect the energies in a table.
#
# Usage: cp2k_cutoff_conv.sh [--rel] [-v "values"] [-f fixed] [-i cp2k.inp] [-O cp2k.out] [-j conv_test]
#                            [prepare|submit|analyse]
#   --rel        scan REL_CUTOFF at fixed CUTOFF (directories rel_cutoff_<v>Ry, table REL_CUTOFF.txt)
#   -v VALUES    values to scan            (default: CUTOFF $(seq 100 50 1000), REL_CUTOFF $(seq 10 10 80))
#   -f VALUE     the fixed other parameter (default: REL_CUTOFF 60 / CUTOFF 800)
#   -i FILE      template input with the placeholders LT_cutoff and LT_rel_cutoff (default cp2k.inp)
#   -O FILE      CP2K output file name in each directory (default cp2k.out)
#   -j FILE      job script copied into and submitted in each directory (default conv_test)
#   Without prepare|submit|analyse (or 1|2|3) a menu is shown.
#   See also cp2k_conv_analyse.py (meV/atom differences vs a reference, "converged at", TSV, plot):
#     cp2k_conv_analyse.py -p 'cutoff_*Ry'   (or 'rel_cutoff_*Ry')

# Shared helpers (cp2k_common.sh: next to this script, else in PATH)
_lib="$(dirname "$(readlink -f "$0")")/cp2k_common.sh"
[ -f "$_lib" ] || _lib="$(command -v cp2k_common.sh)" || { echo "Error: cp2k_common.sh not found (keep it next to this script or in PATH)" >&2; exit 1; }
source "$_lib"

##Input parameters
submit_command=""  # "qsub" or "sbatch"; leave empty to auto-detect (PBS -> qsub, Slurm -> sbatch)
input_file=cp2k.inp   #Template file of present system
output_file=cp2k.out
run_script=conv_test

scan="cutoff"
if [ "${1:-}" == "--rel" ] ; then
    scan="rel_cutoff"
    shift
fi

if [ "$scan" == "cutoff" ] ; then
    plot_file="CUTOFF.txt"
    fixed=60                    #REL_CUTOFF parameter (Ry)
    values=$(seq 100 50 1000)   #Considered CUTOFF range and step
else
    plot_file="REL_CUTOFF.txt"
    fixed=800                   #CUTOFF parameter (Ry)
    values=$(seq 10 10 80)      #Considered REL_CUTOFF range and step
fi

while getopts ":v:f:i:O:j:h" opt; do
    case "$opt" in
        v) values="$OPTARG" ;;
        f) fixed="$OPTARG" ;;
        i) input_file="$OPTARG" ;;
        O) output_file="$OPTARG" ;;
        j) run_script="$OPTARG" ;;
        h) show_help; exit 0 ;;
        *) echo "Unknown option or missing value: -$OPTARG (see -h)"; exit 1 ;;
    esac
done
shift $((OPTIND - 1))

# Work directory of a scan value
work_dir_of() {
    echo "${scan}_${1}Ry"
}

prepare_input_files() {
    for ii in $values ; do
        work_dir=$(work_dir_of $ii)
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
        if [ "$scan" == "cutoff" ] ; then
            sed -e "s/LT_rel_cutoff/${fixed}/g" \
                -e "s/LT_cutoff/${ii}/g" \
                $input_file > $work_dir/$input_file
        else
            sed -e "s/LT_cutoff/${fixed}/g" \
                -e "s/LT_rel_cutoff/${ii}/g" \
                $input_file > $work_dir/$input_file
        fi
        cp $run_script $work_dir
    done
}

run_input_files() {
    if [ -z "$submit_command" ] ; then
        submit_command=$(submit_cmd) || { echo "Neither qsub nor sbatch found, cannot submit jobs."; exit 1; }
    fi
    for ii in $values ; do
        work_dir=$(work_dir_of $ii)
        if [ ! -d $work_dir ] ; then
            echo "$work_dir not exist!"
            exit
        else
            submit_in_dir $work_dir $run_script "$submit_command"
            echo "$work_dir: job submitted!"
        fi
    done
}

analysis() {
    echo "# Grid cutoff vs total energy" > $plot_file
    echo "# Date: $(date)" >> $plot_file
    echo "# PWD: $PWD" >> $plot_file
    if [ "$scan" == "cutoff" ] ; then
        echo "# REL_CUTOFF = $fixed" >> $plot_file
        echo -n "#   Cutoff |  Energy (Hartree)  |  delte E " >> $plot_file
    else
        echo "# CUTOFF = $fixed" >> $plot_file
        echo -n "#Rel_Cutoff |  Energy (Hartree)  |  delte E " >> $plot_file
    fi
    # Number of grid levels, taken from the first finished run (for the header)
    ngrids=0
    for ii in $values ; do
        work_dir=$(work_dir_of $ii)
        if cp2k_finished $work_dir/$output_file; then
            ngrids=$(grep -e '^[ \t]*QS| Number of grid levels:' $work_dir/$output_file | head -1 | awk '{print $6}')
            break
        fi
    done
    for ((igrid=1; igrid <= ngrids; igrid++)) ; do
        printf " | NG on grid %d" $igrid >> $plot_file
    done
    printf "\n" >> $plot_file
    itime=0
    for ii in $values ; do
        work_dir=$(work_dir_of $ii)
        # Unfinished or missing run: N/A in every column (rows stay aligned; delta E skips this point)
        if ! cp2k_finished $work_dir/$output_file; then
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

