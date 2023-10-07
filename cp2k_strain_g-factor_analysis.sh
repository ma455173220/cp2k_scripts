#!/bin/bash

# This script extracts g-factor information from CP2K output files
# in all directories named as "strain_{number}" in the current directory.
# The information will be saved in a ".csv" file, with the first column representing the number in "strain_{number}"

keyword="1 B   EFG Tensor"

# Get a list of directories that start with "strain_" in the current directory
directories=$(ls -d strain_*)

# Initialize the output file with a header
echo "strain g-factor1 g-factor2 g-factor3" > output.csv

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

    # Check if the CP2K g-tensor output file (cp2k-GTENSOR-1.data) exits and is not empty
    gfile="$dir/*.data"
    if [ ! -s ${gfile} ]; then
	echo "CP2K g-tensor output file does not exist or is empty in directory $dir"
	continue
    fi

    # Check if the CP2K run has completed
    if ! grep -q "PROGRAM ENDED AT" $file; then
        echo "CP2K run has not completed in directory $dir"
        continue
    fi

    # Extract the g-factor
    cd $dir
    gfactor=$(/home/561/hm1876/cp2k/scripts/eig.py | tail -n 1)
    gfactor=$(echo $gfactor | tr -d '[]')
    cd ..
    # Write the information to the output file
    echo "$strain_minus_1 $gfactor" >> output.csv

done

# Sort the output file by the first column in reverse order
# sort -g -k1 output.csv output.csv
sort -g -k1 -o output.csv output.csv


# Print a message indicating the completion of the script
echo "Finished extracting g-factor information from CP2K output files in directories starting with 'strain_'. The results are saved in 'output.csv'."

