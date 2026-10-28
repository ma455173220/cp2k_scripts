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

# Locate a helper script: next to this script, then in PATH, then the old Gadi location
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
function find_script (){
	if [ -x "$SCRIPT_DIR/$1" ]; then
		echo "$SCRIPT_DIR/$1"
	elif command -v "$1" >/dev/null 2>&1; then
		command -v "$1"
	elif [ -x "$2" ]; then
		echo "$2"
	else
		echo -e "${ORANGE}Error: cannot find $1 (searched $SCRIPT_DIR, PATH and $2)" >&2
		return 1
	fi
}

# Detect the batch scheduler (PBS on Gadi, Slurm on Setonix)
detect_scheduler() {
	if command -v qsub >/dev/null 2>&1; then
		echo "pbs"
	elif command -v sbatch >/dev/null 2>&1; then
		echo "slurm"
	else
		echo "none"
	fi
}

cp2k_restart=$(find_script cp2k-restart.sh /home/561/hm1876/cp2k/scripts/cp2k-restart.sh) || exit 1

# Loop through the arguments and create directories
for arg in "$@"
do
	cp $input_file $runscript "strain_$arg"
	cd "strain_$arg"

	# Run cp2k-restart.sh
	echo -e "${GREEN}Running cp2k-restart.sh for strain $arg..."
	"$cp2k_restart" cp2k-1.restart $input_file
	echo -e "${ORANGE}.............................................................................."

	cd ..
done

# Confirm if submit all jobs
echo -e "${ORANGE}.............................................................................."
read -p "Submit all jobs? [Y/n]" choice

if [[ -z $choice || $choice == "Y" || $choice == "y" ]]; then
	case "$(detect_scheduler)" in
		pbs)   submit_cmd="qsub" ;;
		slurm) submit_cmd="sbatch" ;;
		*)     echo -e "${ORANGE}Error: neither qsub nor sbatch found, jobs not submitted."; exit 1 ;;
	esac

	# Loop through the arguments and submit jobs to qsub/sbatch
	for arg in "$@"
	do

		cd "strain_$arg"
		echo -e "${GREEN}Submitting job for strain $arg..."
		$submit_cmd $runscript
		echo -e "${ORANGE}.............................................................................."
		cd ..
	done
else
	echo -e "${ORANGE}Jobs not submitted."
fi

