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

# Loop through the arguments and create directories
for arg in "$@"
do
	cp $input_file $runscript "strain_$arg"
	cd "strain_$arg"

	# Run cp2k-restart.sh
	echo -e "${GREEN}Running cp2k-restart.sh for strain $arg..."
	/home/561/hm1876/cp2k/scripts/cp2k-restart.sh cp2k-1.restart $input_file
	echo -e "${ORANGE}.............................................................................."

	cd ..
done

# Confirm if submit all jobs
echo -e "${ORANGE}.............................................................................."
read -p "Submit all jobs? [Y/n]" choice

if [[ $choice == "Y" || $choice == "y" ]]; then
	# Loop through the arguments and submit jobs to qsub
	for arg in "$@"
	do

		cd "strain_$arg"
		echo -e "${GREEN}Submitting job for strain $arg..."
		qsub $runscript
		echo -e "${ORANGE}.............................................................................."
		cd ..
	done
else
	echo -e "${ORANGE}Jobs not submitted."
fi

