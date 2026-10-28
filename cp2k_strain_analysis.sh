#!/bin/bash
# Collect EFG tensor eigenvalues (default, --efg) or g-tensor eigenvalues (--gtensor) from the CP2K runs in
# all directories named "strain_{number}" in the current directory (made by cp2k_strain.sh).
# The first column of the table is {number} - 1 (the strain), sorted.
#
# Usage: cp2k_strain_analysis.sh [--efg | --gtensor] [-a ATOM] [-e ELEMENT] [-o output.csv]
#   --efg        EFG tensor eigenvalues and anisotropy of one atom (default)
#   --gtensor    g-tensor eigenvalues from the *.data file via eig.py (cp2k_strain_g-factor_analysis.sh)
#   -a ATOM      atom index for --efg (default 1)
#   -e ELEMENT   element of that atom for --efg (default B)
#   -o FILE      output table (default output.csv; both modes write output.csv unless -o is given)

# Shared helpers (cp2k_common.sh: next to this script, else in PATH)
_lib="$(dirname "$(readlink -f "$0")")/cp2k_common.sh"
[ -f "$_lib" ] || _lib="$(command -v cp2k_common.sh)" || { echo "Error: cp2k_common.sh not found (keep it next to this script or in PATH)" >&2; exit 1; }
source "$_lib"

mode="efg"
case "${1:-}" in
    --efg)     mode="efg"; shift ;;
    --gtensor) mode="gtensor"; shift ;;
esac

atom=1
element=B
output=output.csv
while getopts ":a:e:o:h" opt; do
    case "$opt" in
        a) atom="$OPTARG" ;;
        e) element="$OPTARG" ;;
        o) output="$OPTARG" ;;
        h) show_help; exit 0 ;;
        *) echo "Unknown option or missing value: -$OPTARG (see -h)"; exit 1 ;;
    esac
done

# EFG block header of the chosen atom, e.g. "  1 B   EFG Tensor" (the index must match exactly: 1 is not 11)
keyword="(^|[[:space:]])${atom}[[:space:]]+${element}[[:space:]]+EFG Tensor"

if [ "$mode" == "gtensor" ]; then
    eig_py=$(find_script eig.py /home/561/hm1876/cp2k/scripts/eig.py) || exit 1
fi

# Get a list of directories that start with "strain_" in the current directory
directories=$(ls -d strain_*)

# Initialize the output file with a header
if [ "$mode" == "efg" ]; then
    echo "strain eigenvalue1 eigenvalue2 eigenvalue3 ansio_value" > $output
else
    echo "strain g-factor1 g-factor2 g-factor3" > $output
fi

# Loop through each directory
for dir in $directories; do

    # Extract the strain number from the directory name
    # strain=$(echo $dir | sed 's/strain_//')
    strain=$(echo $dir| awk -F "/" '{print $1}' |  awk -F "_" '{print $NF}')
    strain_minus_1=$(echo "$strain - 1" | bc -l)
    strain_minus_1=$(printf "%.4f" $strain_minus_1)

    # Check if the CP2K output file exists and is not empty
    file="$dir/*.out"
    if [ ! -s $file ]; then
        echo "CP2K output file does not exist or is empty in directory $dir"
        continue
    fi

    if [ "$mode" == "gtensor" ]; then
        # Check if the CP2K g-tensor output file (cp2k-GTENSOR-1.data) exits and is not empty
        gfile="$dir/*.data"
        if [ ! -s ${gfile} ]; then
            echo "CP2K g-tensor output file does not exist or is empty in directory $dir"
            continue
        fi
    fi

    # Check if the CP2K run has completed
    if ! grep -q "PROGRAM ENDED AT" $file; then
        echo "CP2K run has not completed in directory $dir"
        continue
    fi

    if [ "$mode" == "efg" ]; then
        # Extract the EFG Tensor eigenvalues information
        eig_values=$(grep -E "$keyword" $file -A 4 | grep "EFG Tensor eigenvalues" | awk '{print $4, $5, $6}' | tail -1)
        aniso_values=$(grep -E "$keyword" $file -A 5 | grep "EFG Tensor anisotropy" | awk '{print $NF}' | tail -1)

        # Check if the information is extracted successfully
        if [ -z "$eig_values" ]; then
            echo "Failed to extract EFG Tensor eigenvalues information in directory $dir"
            continue
        fi

        # Check if anisotropy extraction is successful
        if [ -z "$aniso_values" ]; then
            echo "Failed to extract EFG Tensor anisotropy information in directory $dir"
            continue
        fi

        # Write the information to the output file
        echo "$strain_minus_1 $eig_values $aniso_values" >> $output
    else
        # Extract the g-factor
        gfactor=$(cd "$dir" && "$eig_py" | tail -n 1)
        gfactor=$(echo $gfactor | tr -d '[]')
        # Write the information to the output file
        echo "$strain_minus_1 $gfactor" >> $output
    fi

done

# Sort the output file by the first column
sort -g -k1 -o $output $output


# Print a message indicating the completion of the script
if [ "$mode" == "efg" ]; then
    echo "Finished extracting EFG Tensor eigenvalues information from CP2K output files in directories starting with 'strain_'. The results are saved in '$output'."
else
    echo "Finished extracting g-factor information from CP2K output files in directories starting with 'strain_'. The results are saved in '$output'."
fi
