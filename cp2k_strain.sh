#!/bin/bash

# This script is used to create directories for different strains and submit jobs to qsub (PBS) or sbatch (Slurm)
# The script assumes that cp2k.inp and cp2k_runscript are in the current directory
# The script also assumes that Multiwfn is installed and the executable is in the PATH
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

# Set a function
function Multiwfn_run (){
	# If strain_choice is 1, then Multiwfn_function_choice=0
	if [ $strain_choice -eq 1 ]
	then
		Multiwfn_function_choice=0
	else
		# Choose the uniaxial strain direction
		read -p "Please select the uniaxial strain direction (XX, YY, ZZ): " uniaxial_strain_direction
		if [[ $uniaxial_strain_direction != "XX" && $uniaxial_strain_direction != "YY" && $uniaxial_strain_direction != "ZZ" ]]; then
			echo "Error: Invalid uniaxial strain direction. Please enter XX, YY, or ZZ."                                   
			exit 1                                                                                                      
		fi                                                                                                                  
		case $uniaxial_strain_direction in
			XX) Multiwfn_function_choice=1;;
			YY) Multiwfn_function_choice=2;;
			ZZ) Multiwfn_function_choice=3;;
			*) echo "Invalid stress direction"; exit 1;;
		esac
	fi

	cp2k_restart=$(find_script cp2k-restart.sh /home/561/hm1876/cp2k/scripts/cp2k-restart.sh) || exit 1

	# Loop through the arguments and create directories
	for arg in "$@"
	do
		if [ -d "strain_$arg" ]
		then
			echo -e "${GREEN}Directory strain_$arg already exists, skipping..."
			continue
		fi

		mkdir "strain_$arg"
		cp $input_file $runscript "strain_$arg"
		cd "strain_$arg"

		# Run Multiwfn and cp2k-restart.sh
		echo -e "${GREEN}Running Multiwfn and cp2k-restart.sh for strain $arg..."
		echo -e "$input_file\ncp2k\ntemp.inp\n-11\n21\n$Multiwfn_function_choice\n$arg\n-10\n0\nq" | Multiwfn 1>>/dev/null
		"$cp2k_restart" temp.inp $input_file
		rm temp.inp
		echo -e "${ORANGE}.............................................................................."

		cd ..
	done
}

function shear_strain (){
	# Choose the shear strain direction
	read -p "Please select the shear strain direction (XY, XZ, YZ): " shear_strain_direction
	if [[ $shear_strain_direction != "XY" && $shear_strain_direction != "XZ" && $shear_strain_direction != "YZ" ]]; then
		echo "Error: Invalid shear strain direction. Please enter XY, XZ, or YZ."
		exit 1
	fi

	cp2k2cif=$(find_script cp2k2cif.sh /home/561/hm1876/cp2k/scripts/cp2k2cif.sh) || exit 1
	deform_strain=$(find_script deform_strain.sh /home/561/hm1876/.local/bin/deform_strain.sh) || exit 1
	cp2k_restart=$(find_script cp2k-restart.sh /home/561/hm1876/cp2k/scripts/cp2k-restart.sh) || exit 1

	# Gnerate POSCAR for the deform_strain.sh script (cp2k2cif.sh menu option 1 = POSCAR;
	# cp2k2pos.sh was merged into cp2k2cif.sh)
	echo 1 | "$cp2k2cif" $input_file 1>>/dev/null
	if [ ! -s POSCAR ]
	then
		echo -e "${ORANGE}Error: POSCAR was not generated from $input_file by $cp2k2cif"
		exit 1
	fi

	# Loop through the arguments and create directories
	for arg in "$@"
	do
		if [ -d "strain_$arg" ]
		then
			echo -e "${GREEN}Directory strain_$arg already exists, skipping..."
			continue
		fi

		mkdir "strain_$arg"
		cp $input_file $runscript POSCAR "strain_$arg"
		cd "strain_$arg"

		# Run deform_strain, Multiwfn, and cp2k-restart.sh
		echo -e "${GREEN}Running deform_strain, Multiwfn, and cp2k-restart.sh for strain $arg..."
		new_arg=$(echo "$arg - 1" | bc)
		"$deform_strain" $shear_strain_direction $new_arg
		echo -e "POSCAR\ncp2k\ntemp.inp\n0\nq" | Multiwfn 1>>/dev/null
		"$cp2k_restart" temp.inp $input_file
		rm temp.inp
		echo -e "${ORANGE}.............................................................................."

		cd ..
	done
}

# Select strain type
echo "Please select a strain type:"
echo "1. Hydrostatic"
echo "2. Uniaxial"
echo "3. Shear"

read strain_choice

case $strain_choice in
	1 | 2)
		Multiwfn_run "$@"
		;;
	3)
		shear_strain "$@"
		;;
	*)
		echo "Invalid option selected."
		;;
esac

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
		if [ -d "strain_$arg" ] && [ -n "$(find "strain_$arg" -maxdepth 1 -name '*.out' -print -quit)" ]; then
			echo -e "${GREEN}Directory strain_$arg already exists and has output file, skipping..."
			echo -e "${ORANGE}.............................................................................."
			continue
		fi

		cd "strain_$arg"
		echo -e "${GREEN}Submitting job for strain $arg..."
		$submit_cmd $runscript
		echo -e "${ORANGE}.............................................................................."
		cd ..
	done
else
	echo -e "${ORANGE}Jobs not submitted."
fi

