#!/bin/bash

# This script extracts EFG Tensor eigenvalues information from CP2K output files
# in all directories named as "strain_{number}" in the current directory.
# The information will be saved in a ".csv" file, with the first column representing the number in "strain_{number}"
# and the second to fourth columns representing the EFG Tensor eigenvalues.

keyword="1 B   EFG Tensor"

# Get a list of directories that start with "strain_" in the current directory
directories=$(ls -d strain_*)

# Initialize the output file with a header
echo "strain eigenvalue1 eigenvalue2 eigenvalue3 ansio_value" > output.csv

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

    # Check if the CP2K run has completed
    if ! grep -q "PROGRAM ENDED AT" $file; then
        echo "CP2K run has not completed in directory $dir"
        continue
    fi

    # Extract the EFG Tensor eigenvalues information
    eig_values=$(grep "$keyword" $file -A 4 | grep "EFG Tensor eigenvalues" | awk '{print $4, $5, $6}' | tail -1)
    aniso_values=$(grep "$keyword" $file -A 5 | grep "EFG Tensor anisotropy" | awk '{print $NF}' | tail -1)

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
    echo "$strain_minus_1 $eig_values $aniso_values" >> output.csv

done

# Sort the output file by the first column in reverse order
# sort -g -k1 output.csv output.csv
sort -g -k1 -o output.csv output.csv


# Print a message indicating the completion of the script
echo "Finished extracting EFG Tensor eigenvalues information from CP2K output files in directories starting with 'strain_'. The results are saved in 'output.csv'."

