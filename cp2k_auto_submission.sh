#!/bin/bash

# This script monitors the progress of CP2K calculations and automatically

# Set the path to the directory where CP2K calculations are running
dir=".."

# Set the name of the output file
file="$dir/*.out"

# Set the name of the restart file
restart_file="$dir/*.restart"

# Set the sleep time between each loop
sleep_time=60

# Create a log file to record the script's activities
echo "CP2K job monitor started at $(date)" > cp2k_auto_submission.log

# Loop indefinitely
while true; do

    # Check if the output file exists and is not empty
    if [ ! -s $file ]; then
        echo "--- CP2K output file does not exist or is empty in directory $dir ---" >> cp2k_auto_submission.log
        sleep $sleep_time
        continue
    fi

    # Check if the CP2K run has completed
    if ! grep -q "PROGRAM ENDED AT" $file; then
        echo "--- CP2K run has not completed in directory $dir ---" >> cp2k_auto_submission.log
        sleep $sleep_time
        continue
    else
        echo "--- CP2K run has completed in directory $dir at $(date) ---" >> cp2k_auto_submission.log
    fi

    # Check if the restart file exists
    if [ ! -e $restart_file ]; then
        echo "--- $restart_file does not exist in directory $dir ---" >> cp2k_auto_submission.log
    else
        echo "--- $restart_file exists in directory $dir ---" >> cp2k_auto_submission.log
        /home/561/hm1876/cp2k/scripts/cp2k-restart.sh $restart_file cp2k.inp
    fi

    # Generate new input files for strain calculations
    echo "--- Generating new input files for strain calculations ---" >> cp2k_auto_submission.log
    echo "y" | /home/561/hm1876/cp2k/scripts/cp2k_strain.sh 1.05 1.1 1.15 1.2 0.95 0.9 1.01 1.03 0.99 0.97 
    echo "--- End of iteration ---" >> cp2k_auto_submission.log

    # Exit the loop
    exit

done

