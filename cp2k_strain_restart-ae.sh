#!/bin/bash

# The script assumes that cp2k.inp and cp2k_runscript are in the current directory
# The script also assumes that cp2k-restart.sh is in the PATH

# Define input files
input_file="cp2k.inp"
runscript="cp2k_runscript"

# Define color codes
GREEN='\033[1;32m'
ORANGE='\033[1;33m'

# Check if cp2k.inp and cp2k_runscript exist and are not empty
if [ ! -s "$input_file" ] || [ ! -s "$runscript" ]
then
	echo -e "${ORANGE}Error: $input_file or $runscript does not exist or is empty"
	echo -e "${ORANGE}Please make sure you have the correct files in the current directory"
	exit 1
fi

# Check if arguments are provided
if [ $# -eq 0 ]
then
	echo -e "${ORANGE}Usage: $0 arg1 arg2 ... argN"
	exit 1
fi

# Shared helpers (cp2k_common.sh: next to this script, else in PATH)
_lib="$(dirname "$(readlink -f "$0")")/cp2k_common.sh"
[ -f "$_lib" ] || _lib="$(command -v cp2k_common.sh)" || { echo "Error: cp2k_common.sh not found (keep it next to this script or in PATH)" >&2; exit 1; }
source "$_lib"

cp2k_restart=$(find_script cp2k-restart.sh /home/561/hm1876/cp2k/scripts/cp2k-restart.sh) || exit 1

# Loop through the arguments and update the existing strain directories
done_dirs=()
for arg in "$@"
do
	if [ ! -d "strain_$arg" ]
	then
		echo -e "${ORANGE}Warning: directory strain_$arg does not exist, skipping..."
		continue
	fi

	# Run cp2k-restart.sh (in a subshell, so a failure can never leave us in the wrong directory)
	echo -e "${GREEN}Running cp2k-restart.sh for strain $arg..."
	if ( cp "$input_file" "$runscript" "strain_$arg" && cd "strain_$arg" && "$cp2k_restart" cp2k-1.restart "$input_file" )
	then
		done_dirs+=("strain_$arg")
	else
		echo -e "${ORANGE}Warning: restart preparation failed in strain_$arg, it will not be submitted."
	fi
	echo -e "${ORANGE}.............................................................................."
done

if [ ${#done_dirs[@]} -eq 0 ]
then
	echo -e "${ORANGE}No strain directory was prepared, nothing to submit."
	exit 1
fi

# Confirm if submit all jobs
echo -e "${ORANGE}.............................................................................."
read -p "Submit all jobs? [Y/n]" choice

if [[ -z $choice || $choice == "Y" || $choice == "y" ]]; then
	submit_command=$(submit_cmd) || { echo -e "${ORANGE}Error: neither qsub nor sbatch found, jobs not submitted."; exit 1; }

	# Submit the prepared directories to qsub/sbatch
	for dir in "${done_dirs[@]}"
	do
		echo -e "${GREEN}Submitting job for strain ${dir#strain_}..."
		submit_in_dir "$dir" "$runscript" "$submit_command"
		echo -e "${ORANGE}.............................................................................."
	done
else
	echo -e "${ORANGE}Jobs not submitted."
fi

