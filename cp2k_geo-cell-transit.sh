#!/bin/bash

# The script assumes that cp2k.inp is in the current directory
# The script also assumes that Multiwfn is installed and the executable is in the PATH

# Define input files
input_file="cp2k.inp"

# Define color codes
GREEN='\033[1;32m'
ORANGE='\033[1;33m'

# Check if cp2k.inp exists and is not empty
if [ ! -s "$input_file" ] 
then
	echo -e "${ORANGE}Error: $input_file does not exist or is empty"
	echo -e "${ORANGE}Please make sure you have the correct files in the current directory"
	exit 1
fi

# Set a function
function Multiwfn_run (){

	if [ $function_choice -eq 1 ]
	then
		Multiwfn_function_choice=3
	else
		Multiwfn_function_choice=4
	fi

	# Run Multiwfn 
	echo -e "${GREEN}Function starts..."
	echo -e "${GREEN}Running Multiwfn..."
	echo -e "$input_file\ncp2k\ntemp.inp\n-1\n$Multiwfn_function_choice\n0\nq" | Multiwfn 1>>/dev/null

	# Rewrite cp2k.inp
	echo -e "${GREEN}Rewriting $input_file..."
	sed -i '/&MOTION/,/&END MOTION/d' $input_file
	sed -n '/&MOTION/,/&END MOTION/p' temp.inp >> $input_file

	# Modify the input file
    	if [ "$Multiwfn_function_choice" = "3" ]; then
    	    sed -i 's/\(RUN_TYPE\).*/\1 GEO_OPT/' $input_file
	    sed -i '/STRESS_TENSOR/d' $input_file
    	elif [ "$Multiwfn_function_choice" = "4" ]; then
    	    sed -i 's/\(RUN_TYPE\).*/\1 CELL_OPT/' $input_file
	    sed -i '/&END FORCE_EVAL/i STRESS_TENSOR ANALYTICAL #Compute full stress tensor analytically' $input_file
    	fi

	rm temp.inp
	echo -e "${GREEN}Done!"

}


# Select function type
echo "Please select a function type:"
echo "1. GEO_OPT"
echo "2. CELL_OPT"

read function_choice

case $function_choice in
	1 | 2)
		Multiwfn_run
		;;
	*)
		echo "Invalid option selected."
		;;
esac
