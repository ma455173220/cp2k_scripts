#!/bin/bash

# Base parameters
BASE_NCPUS=48
BASE_MEM=190
JOBNAME="cp2k.inp"
RUNSCRIPT_NAME="cp2k_runscript"

# Loop to create folders for different numbers of nodes
for NODE in {1..10}; do
    # Calculate ncpus and mem for the corresponding number of nodes
    NCPUS=$((BASE_NCPUS * NODE))
    MEM=$((BASE_MEM * NODE))GB

    # Create new folder, if it exists clear it
    FOLDER_NAME="node_${NODE}"
    if [ -d "$FOLDER_NAME" ]; then
        rm -rf $FOLDER_NAME/*
    else
        mkdir -p $FOLDER_NAME
    fi

    # Copy cp2k.inp and cp2k_runscript to the new folder
    cp $JOBNAME $FOLDER_NAME/
    cp $RUNSCRIPT_NAME $FOLDER_NAME/

    # Modify the cp2k_runscript parameters in the new folder
    sed -i "s/^#PBS -l ncpus=.*/#PBS -l ncpus=$NCPUS/" $FOLDER_NAME/$RUNSCRIPT_NAME
    sed -i "s/^#PBS -l mem=.*/#PBS -l mem=$MEM/" $FOLDER_NAME/$RUNSCRIPT_NAME

    echo "Created folder $FOLDER_NAME with ncpus=$NCPUS and mem=$MEM"
done
