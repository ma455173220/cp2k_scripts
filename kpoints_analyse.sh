#!/bin/bash
# Tabulate total energy, grid counts and wall time of a series of runs in directories <prefix>_<value>
# (k-point test by default; eps_schwarz_analyse.sh uses the eps_schwarz preset).
#
# Usage: kpoints_analyse.sh [--preset kpoints|eps_schwarz] [-p PREFIX] [-v "values"] [-O OUTFILE]
#                           [-o TABLE] [-l LABEL]
#   --preset NAME  defaults of the k-point (kpoints) or EPS_SCHWARZ (eps_schwarz) test
#   -p PREFIX      directory prefix               (kpoints        | eps_schwarz)
#   -v VALUES      values, i.e. directory suffixes ("2 3 4 5 6 7 8 9 10" | "2 3 4 5 6 7 8")
#   -O OUTFILE     CP2K output file in each directory (Si_bulk.out)
#   -o TABLE       table to write                 (kpoints_data.ssv | cutoff_data.ssv)
#   -l LABEL       name of the scanned quantity in the table header (K-points | eps_schwarz)
#   See also cp2k_conv_analyse.py (meV/atom differences vs a reference, "converged at", TSV, plot):
#     cp2k_conv_analyse.py -p kpoints_ -O Si_bulk.out

# Shared helpers (cp2k_common.sh: next to this script, else in PATH)
_lib="$(dirname "$(readlink -f "$0")")/cp2k_common.sh"
[ -f "$_lib" ] || _lib="$(command -v cp2k_common.sh)" || { echo "Error: cp2k_common.sh not found (keep it next to this script or in PATH)" >&2; exit 1; }
source "$_lib"

preset="kpoints"
if [ "${1:-}" == "--preset" ]; then
    preset="${2:-}"
    shift 2
fi
case "$preset" in
    kpoints)
        prefix=kpoints
        values="2 3 4 5 6 7 8 9 10"
        plot_file=kpoints_data.ssv
        label="K-points"
        ;;
    eps_schwarz)
        prefix=eps_schwarz
        values="2 3 4 5 6 7 8"
        plot_file=cutoff_data.ssv
        label="eps_schwarz"
        ;;
    *)
        echo "Unknown preset '$preset' (kpoints or eps_schwarz)"; exit 1 ;;
esac
output_file=Si_bulk.out

while getopts ":p:v:O:o:l:h" opt; do
    case "$opt" in
        p) prefix="$OPTARG" ;;
        v) values="$OPTARG" ;;
        O) output_file="$OPTARG" ;;
        o) plot_file="$OPTARG" ;;
        l) label="$OPTARG" ;;
        h) show_help; exit 0 ;;
        *) echo "Unknown option or missing value: -$OPTARG (see -h)"; exit 1 ;;
    esac
done

echo "# $label vs total energy" > $plot_file
echo "# Date: $(date)" >> $plot_file
echo "# PWD: $PWD" >> $plot_file
echo -n "# $label | Total Energy (Ha)" >> $plot_file
# Number of grid levels, taken from the first finished run (for the header)
ngrids_header=0
for ii in $values; do
    work_dir=${prefix}_${ii}
    if cp2k_finished $work_dir/$output_file; then
        ngrids_header=$(grep -e '^[ \t]*QS| Number of grid levels:' $work_dir/$output_file | head -1 | awk '{print $6}')
        break
    fi
done
for ((igrid=1; igrid <= ngrids_header; igrid++)) ; do
    printf " | NG on grid %d" $igrid >> $plot_file
done
printf " | Time" >> $plot_file
printf "\n" >> $plot_file

for ii in $values; do
    work_dir=${prefix}_${ii}
    # Unfinished or missing run: N/A in every column, so the rows stay aligned
    if ! cp2k_finished $work_dir/$output_file; then
        printf "%10.2f  %15s" $ii "N/A" >> $plot_file
        for ((igrid=1; igrid <= ngrids_header; igrid++)) ; do
            printf "  %6s" "N/A" >> $plot_file
        done
        printf "  %10s\n" "N/A" >> $plot_file
        echo "Warning: $work_dir/$output_file missing or run not finished" >&2
        continue
    fi
    total_energy=$(cp2k_energy $work_dir/$output_file)
    printf "%10.2f  %15.10f" $ii $total_energy >> $plot_file
    for ((igrid=1; igrid <= ngrids_header; igrid++)) ; do
        grid=$(grep -e '^[ \t]*count for grid' $work_dir/$output_file | \
               awk -v igrid=$igrid '(NR == igrid){print $5}')
        printf "  %6d" $grid >> $plot_file
    done
    # Total wall time: last field of the "CP2K   1  ..." line of the timing report
    computational_time=$(cp2k_walltime $work_dir/$output_file)
    if [ -n "$computational_time" ]; then
        printf "  %10.5f"  $computational_time >> $plot_file
    else
        printf "  %10s" "N/A" >> $plot_file
    fi
    printf "\n" >> $plot_file
done
